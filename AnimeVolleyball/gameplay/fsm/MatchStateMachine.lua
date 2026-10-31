-- ============================================================
-- MatchStateMachine.lua  |  gameplay/fsm/
-- Governs the overall match lifecycle:
--   LOBBY → SETUP → SERVE → RALLY → POINT → SET_END → MATCH_END
-- Server-authoritative only. No client logic here.
-- ============================================================

local RunService    = game:GetService("RunService")
local GameConstants = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes       = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)
local TouchCounter  = require(script.Parent.Parent.gameplay.physics.TouchCounter)
local BallPhysics   = require(script.Parent.Parent.gameplay.physics.BallPhysics)

-- ─────────────────────────────────────────────────────────────
-- MATCH STATES
-- ─────────────────────────────────────────────────────────────
local MS = {
    LOBBY      = "LOBBY",
    SETUP      = "SETUP",       -- team/position selection
    SERVE      = "SERVE",       -- pre-serve, ball welded to server hand
    RALLY      = "RALLY",       -- live play
    POINT      = "POINT",       -- short pause, award point, reset
    SET_END    = "SET_END",     -- a set concluded
    MATCH_END  = "MATCH_END",   -- match concluded
}

-- ─────────────────────────────────────────────────────────────
-- MATCH ENGINE OBJECT
-- ─────────────────────────────────────────────────────────────
local MatchStateMachine = {}
MatchStateMachine.__index = MatchStateMachine

function MatchStateMachine.new(ballObject)
    local self = setmetatable({}, MatchStateMachine)

    self.state        = MS.LOBBY
    self.ball         = ballObject
    self.touchCounter = TouchCounter.new()

    self.scores = {
        sets      = { A = 0, B = 0 },
        points    = { A = 0, B = 0 },
    }

    self.servingTeam  = "A"
    self.deuceActive  = false
    self.players      = { A = {}, B = {} }
    self.characterFSMs = {}     -- playerID → CharacterStateMachine

    -- Heartbeat connection handle
    self._heartbeatConn = nil

    return self
end

-- ─────────────────────────────────────────────────────────────
-- START
-- ─────────────────────────────────────────────────────────────
function MatchStateMachine:start()
    self:_transition(MS.SERVE)
    self._heartbeatConn = RunService.Heartbeat:Connect(function(dt)
        self:_tick(dt)
    end)
end

function MatchStateMachine:stop()
    if self._heartbeatConn then
        self._heartbeatConn:Disconnect()
        self._heartbeatConn = nil
    end
end

-- ─────────────────────────────────────────────────────────────
-- HEARTBEAT
-- ─────────────────────────────────────────────────────────────
function MatchStateMachine:_tick(dt)
    -- Update all character FSMs
    for _, fsm in pairs(self.characterFSMs) do
        fsm:update(dt)
    end

    if self.state == MS.RALLY then
        -- Ball boundary / net checks happen in BallPhysics module
        -- TouchCounter checked on every touch event (event-driven)
        self:_checkBallBounds()
    end
end

-- ─────────────────────────────────────────────────────────────
-- BALL OUT-OF-BOUNDS / FLOOR CHECK
-- ─────────────────────────────────────────────────────────────
function MatchStateMachine:_checkBallBounds()
    local pos = self.ball.Position
    local C   = GameConstants.Court

    -- Floor impact
    if pos.Y <= (C.FloorY + GameConstants.Physics.BallRadius + 0.05) then
        -- Determine which team's court the ball landed in
        local scoringTeam = pos.Z > 0 and "A" or "B"
        self:_awardPoint(scoringTeam, "FloorImpact")
        return
    end

    -- Out of bounds
    local outX = math.abs(pos.X) > (C.HalfWidth  + C.BoundaryPad)
    local outZ = math.abs(pos.Z) > (C.HalfLength + C.BoundaryPad)
    if outX or outZ then
        -- Last touching team loses the point
        local lastTeam = self.touchCounter:getLastTouchTeam()
        local scoringTeam = lastTeam == "A" and "B" or "A"
        self:_awardPoint(scoringTeam, "OutOfBounds")
        return
    end

    -- Touch count exceeded
    if self.touchCounter:getTouchCount() > GameConstants.Match.MaxTouches then
        local offendingTeam = self.touchCounter:getLastTouchTeam()
        local scoringTeam   = offendingTeam == "A" and "B" or "A"
        self:_awardPoint(scoringTeam, "TouchViolation")
    end
end

-- ─────────────────────────────────────────────────────────────
-- TOUCH REGISTRATION  (called from BallPhysics on contact)
-- ─────────────────────────────────────────────────────────────
function MatchStateMachine:registerTouch(player, touchType, hitVelocity)
    if self.state ~= MS.RALLY and self.state ~= MS.SERVE then return end

    local playerID = player.UserId
    local team     = self:_getPlayerTeam(player)

    -- Net overreach foul check (done in BallPhysics before calling here)

    -- Double-touch check
    if self.touchCounter:wouldCauseDoubleFoul(playerID) then
        local scoringTeam = team == "A" and "B" or "A"
        Remotes.Events.FoulTriggered:FireAllClients({
            foulType         = "DoubleTouchFoul",
            offendingPlayer  = playerID,
            pointAwardedTo   = scoringTeam,
        })
        self:_awardPoint(scoringTeam, "DoubleTouchFoul")
        return false
    end

    -- Register the touch
    local touchIndex = self.touchCounter:registerTouch(playerID, team, touchType)

    -- Broadcast
    Remotes.Events.TouchRegistered:FireAllClients({
        playerID   = playerID,
        touchType  = touchType,
        touchIndex = touchIndex,
        position   = self.ball.Position,
    })

    -- Transition serve → rally on first contact
    if self.state == MS.SERVE then
        self:_transition(MS.RALLY)
    end

    return true
end

-- ─────────────────────────────────────────────────────────────
-- AWARD POINT
-- ─────────────────────────────────────────────────────────────
function MatchStateMachine:_awardPoint(scoringTeam, cause)
    if self.state ~= MS.RALLY and self.state ~= MS.SERVE then return end

    -- HARD STATE PURGE: zero out ball velocity immediately
    self.ball.Velocity        = Vector3.zero
    self.ball.AngularVelocity = Vector3.zero

    self.scores.points[scoringTeam] = self.scores.points[scoringTeam] + 1
    self:_transition(MS.POINT)

    local newScores = table.clone(self.scores.points)
    Remotes.Events.PointScored:FireAllClients({
        scoringTeam = scoringTeam,
        newScore    = newScores,
        causeText   = cause,
    })

    -- Check set win condition
    task.delay(2.0, function()
        if self:_checkSetWin() then
            return
        end
        -- Reset for next rally
        self:_resetRound(scoringTeam)
    end)
end

-- ─────────────────────────────────────────────────────────────
-- SET WIN CHECK
-- ─────────────────────────────────────────────────────────────
function MatchStateMachine:_checkSetWin()
    local pA = self.scores.points.A
    local pB = self.scores.points.B
    local winTarget = GameConstants.Match.SetWinPoints
    local gap       = GameConstants.Match.DeuceGap

    local aWins = pA >= winTarget and (pA - pB) >= gap
    local bWins = pB >= winTarget and (pB - pA) >= gap

    -- Activate deuce
    if (pA >= winTarget or pB >= winTarget) and math.abs(pA - pB) < gap then
        self.deuceActive = true
    end

    if aWins or bWins then
        local winner = aWins and "A" or "B"
        self.scores.sets[winner] = self.scores.sets[winner] + 1

        Remotes.Events.SetWon:FireAllClients({
            winningTeam = winner,
            setScores   = table.clone(self.scores.sets),
        })

        -- Reset Deuce flag and point scores
        self.deuceActive      = false
        self.scores.points.A  = 0
        self.scores.points.B  = 0

        self:_transition(MS.SET_END)

        -- Check match win
        task.delay(3.0, function()
            if self:_checkMatchWin() then return end
            -- Next set
            self:_resetRound(winner)
            self:_transition(MS.SERVE)
        end)

        return true
    end

    return false
end

-- ─────────────────────────────────────────────────────────────
-- MATCH WIN CHECK
-- ─────────────────────────────────────────────────────────────
function MatchStateMachine:_checkMatchWin()
    local sA = self.scores.sets.A
    local sB = self.scores.sets.B
    local goal = GameConstants.Match.SetsToWinMatch

    if sA >= goal or sB >= goal then
        local winner = sA >= goal and "A" or "B"
        self:_transition(MS.MATCH_END)
        Remotes.Events.MatchWon:FireAllClients({
            winningTeam = winner,
            stats       = self:_collectStats(),
            rewardYen   = self:_calculateRewards(winner),
        })
        return true
    end
    return false
end

-- ─────────────────────────────────────────────────────────────
-- ROUND RESET  (Hard State Purge)
-- ─────────────────────────────────────────────────────────────
function MatchStateMachine:_resetRound(servingTeam)
    self.servingTeam = servingTeam or self.servingTeam

    -- Zero all character velocities
    for _, fsm in pairs(self.characterFSMs) do
        fsm.root.Velocity = Vector3.zero
        fsm:transition(fsm.States.IDLE)
    end

    -- Flush touch counter (prevents Deuce memory leaks)
    self.touchCounter:flush()

    -- Teleport characters to spawn
    for team, playerList in pairs(self.players) do
        for _, player in ipairs(playerList) do
            local profile = player:FindFirstChild("GameProfile")
            local position = profile and profile:FindFirstChild("Position")
            if position and player.Character then
                local spawnCoord = GameConstants.Court.Spawns[team][position.Value]
                player.Character.HumanoidRootPart.CFrame =
                    CFrame.new(spawnCoord.x, spawnCoord.y + 1, spawnCoord.z)
            end
        end
    end

    -- Reset ball to server spawn
    local serveSpawn = GameConstants.Court.ServeSpawn[self.servingTeam]
    self.ball.CFrame  = CFrame.new(serveSpawn.x, serveSpawn.y + 1.5, serveSpawn.z)
    self.ball.Velocity        = Vector3.zero
    self.ball.AngularVelocity = Vector3.zero

    self:_transition(MS.SERVE)

    -- Broadcast state
    Remotes.Events.MatchStateChanged:FireAllClients({
        newState    = MS.SERVE,
        teamScores  = table.clone(self.scores),
        touchCount  = 0,
        servingTeam = self.servingTeam,
    })
end

-- ─────────────────────────────────────────────────────────────
-- REWARDS CALCULATION
-- ─────────────────────────────────────────────────────────────
function MatchStateMachine:_calculateRewards(winningTeam)
    local R   = GameConstants.Rewards
    local out = {}
    for team, playerList in pairs(self.players) do
        for _, player in ipairs(playerList) do
            local stats = self:_getPlayerStats(player)
            local base  = team == winningTeam and R.BaseWin or R.BaseLoss
            local yen   = base
                + (stats.spikes  * R.PerSpike)
                + (stats.blocks  * R.PerBlock)
                + (stats.perfReceives * R.PerPerfectReceive)
            out[player.UserId] = yen
        end
    end
    return out
end

-- Placeholder stat collectors (wired to TouchCounter in full impl)
function MatchStateMachine:_getPlayerStats(player)
    return self.touchCounter:getStatsForPlayer(player.UserId)
end

function MatchStateMachine:_collectStats()
    local out = {}
    for _, playerList in pairs(self.players) do
        for _, p in ipairs(playerList) do
            out[p.UserId] = self:_getPlayerStats(p)
        end
    end
    return out
end

-- ─────────────────────────────────────────────────────────────
-- HELPERS
-- ─────────────────────────────────────────────────────────────
function MatchStateMachine:_transition(newState)
    local prev = self.state
    self.state = newState
    print(string.format("[MatchFSM] %s → %s", prev, newState))
end

function MatchStateMachine:_getPlayerTeam(player)
    for team, list in pairs(self.players) do
        for _, p in ipairs(list) do
            if p == player then return team end
        end
    end
    return nil
end

function MatchStateMachine:addPlayer(player, team, position)
    table.insert(self.players[team], player)
    local prof = Instance.new("Folder")
    prof.Name  = "GameProfile"
    local posVal      = Instance.new("StringValue")
    posVal.Name       = "Position"
    posVal.Value      = position
    posVal.Parent     = prof
    local teamVal     = Instance.new("StringValue")
    teamVal.Name      = "Team"
    teamVal.Value     = team
    teamVal.Parent    = prof
    prof.Parent       = player
end

function MatchStateMachine:registerFSM(playerID, fsm)
    self.characterFSMs[playerID] = fsm
end

function MatchStateMachine:onPlayerDisconnect(player)
    -- Flush touch cache before bot substitution
    self.touchCounter:flushPlayer(player.UserId)
    -- Remove from player table
    for team, list in pairs(self.players) do
        for i, p in ipairs(list) do
            if p == player then
                table.remove(list, i)
                print("[MatchFSM] Player disconnected; touch cache flushed, bot assigned")
                break
            end
        end
    end
end

MatchStateMachine.States = MS
return MatchStateMachine
