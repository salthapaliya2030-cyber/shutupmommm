-- ============================================================
-- BotAI.lua  |  gameplay/bot/
-- Server-side NPC AI controller.
-- Implements three difficulty profiles, predictive tracking,
-- exclusive target lock, and WASD directional tilt operations.
-- ============================================================

local RunService    = game:GetService("RunService")
local GameConstants = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes       = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)

-- ─────────────────────────────────────────────────────────────
-- BOT OBJECT
-- ─────────────────────────────────────────────────────────────
local Bot = {}
Bot.__index = Bot

function Bot.new(npcModel, team, position, difficulty, matchFSM, ballPhysics)
    local self = setmetatable({}, Bot)

    self.model      = npcModel
    self.root       = npcModel.PrimaryPart
    self.humanoid   = npcModel:FindFirstChildOfClass("Humanoid")
    self.team       = team
    self.position   = position    -- "Spiker", "Setter", "Libero"
    self.difficulty = difficulty  -- "Easy", "Medium", "Godly"
    self.matchFSM   = matchFSM
    self.ballPhysics = ballPhysics

    self.profile    = GameConstants.Bot[difficulty]
    self.style      = GameConstants.Styles.Nexus   -- default bot style
    self.energy     = 0

    -- AI state
    self.isPrimaryReceiver = false
    self.targetZone        = nil    -- cover zone Vector3
    self.decisionPending   = false
    self.pathLatencyTimer  = 0

    -- WASD tilt the bot intends to use this hit
    self.intendedTilt      = nil

    -- Heartbeat connection
    self._conn = RunService.Heartbeat:Connect(function(dt)
        self:_tick(dt)
    end)

    return self
end

-- ─────────────────────────────────────────────────────────────
-- EXCLUSIVE TARGET ASSIGNMENT
-- Call on all bots whenever ball crosses net
-- ─────────────────────────────────────────────────────────────
function Bot.assignTargets(botList, ballShadowPos)
    -- Find bot closest to shadow ring
    local bestBot  = nil
    local bestDist = math.huge

    for _, bot in ipairs(botList) do
        local d = (bot.root.Position - ballShadowPos).Magnitude
        if d < bestDist then
            bestDist = d
            bestBot  = bot
        end
    end

    -- Assign primary receiver; route others to cover zones
    local coverZones = Bot._generateCoverZones(ballShadowPos, botList)
    local coverIdx   = 1

    for _, bot in ipairs(botList) do
        if bot == bestBot then
            bot.isPrimaryReceiver = true
            bot.targetZone        = ballShadowPos
        else
            bot.isPrimaryReceiver = false
            bot.targetZone        = coverZones[coverIdx]
            coverIdx = coverIdx + 1
        end
        -- Break current pathfinding loop by resetting latency timer
        bot.pathLatencyTimer  = 0
        bot.decisionPending   = false
    end
end

-- ─────────────────────────────────────────────────────────────
-- COVER ZONE GENERATOR
-- ─────────────────────────────────────────────────────────────
function Bot._generateCoverZones(ballPos, botList)
    local C     = GameConstants.Court
    local zones = {}

    -- Spread bots to strategic defensive positions
    local offsets = {
        Vector3.new(-3, 0, 0),
        Vector3.new( 3, 0, 0),
        Vector3.new( 0, 0, -3),
    }

    for i, offset in ipairs(offsets) do
        local zone = Vector3.new(
            math.clamp(ballPos.X + offset.X, -C.HalfWidth, C.HalfWidth),
            C.FloorY,
            math.clamp(ballPos.Z + offset.Z, -C.HalfLength, C.HalfLength)
        )
        table.insert(zones, zone)
    end

    return zones
end

-- ─────────────────────────────────────────────────────────────
-- PER-FRAME TICK
-- ─────────────────────────────────────────────────────────────
function Bot:_tick(dt)
    local ballPos = self.matchFSM.ball.Position

    -- Apply path latency delay (Easy/Medium profiles)
    if self.pathLatencyTimer < self.profile.PathLatency then
        self.pathLatencyTimer = self.pathLatencyTimer + dt
        return
    end

    local targetPos = self.targetZone or ballPos

    -- Move toward target (humanoid:MoveTo)
    local flat = Vector3.new(targetPos.X, self.root.Position.Y, targetPos.Z)
    self.humanoid:MoveTo(flat)

    -- Decide whether to hit
    local distToBall = (self.root.Position - ballPos).Magnitude
    if distToBall < 2.5 and self.isPrimaryReceiver then
        self:_attemptHit(ballPos)
    end
end

-- ─────────────────────────────────────────────────────────────
-- HIT DECISION
-- ─────────────────────────────────────────────────────────────
function Bot:_attemptHit(ballPos)
    if self.decisionPending then return end
    self.decisionPending = true

    -- Error roll (Easy/Medium only)
    local profile = self.profile
    if profile.ErrorChance > 0 and math.random() < profile.ErrorChance then
        -- Mistimed hit: either too early or too late
        local isTooEarly = math.random() < profile.ErrorEarlyBias
        task.delay(isTooEarly and 0 or GameConstants.AnimMarkers.Spike.ContactFrame + 0.3,
        function()
            -- Miss: bot enters stun state
            local fsmRef = self.matchFSM.characterFSMs[self.model.Name]
            if fsmRef then fsmRef:applyStun() end
            self.decisionPending = false
        end)
        return
    end

    -- Determine touch type based on current rally state
    local touchCount = self.matchFSM.touchCounter:getTouchCount()
    local touchType  = self:_decideTouchType(touchCount)

    -- Choose WASD tilt
    local tilt = self:_chooseTilt()

    -- Wait for contact frame then execute
    local contactDelay = GameConstants.AnimMarkers.Spike.ContactFrame
    task.delay(contactDelay, function()
        self:_executeBotHit(touchType, tilt)
        self.decisionPending   = false
        self.isPrimaryReceiver = false
        self.pathLatencyTimer  = 0   -- reset latency for next assignment
    end)
end

-- ─────────────────────────────────────────────────────────────
-- TOUCH TYPE DECISION
-- ─────────────────────────────────────────────────────────────
function Bot:_decideTouchType(touchCount)
    if touchCount == 0 then return "Bump" end
    if touchCount == 1 then return "Set"  end
    return "Spike"
end

-- ─────────────────────────────────────────────────────────────
-- TILT CHOOSER (Medium / Godly deliberate angle selection)
-- ─────────────────────────────────────────────────────────────
function Bot:_chooseTilt()
    if not self.profile.WASDTiltEnabled then return nil end

    -- Aim away from player cluster
    local tilts = { "W", "S", "A", "D" }
    local choice = tilts[math.random(1, #tilts)]

    -- Accuracy check (Medium may miss intended zone)
    if math.random() > (self.profile.TiltAccuracy or 1.0) then
        return nil
    end

    return choice
end

-- ─────────────────────────────────────────────────────────────
-- EXECUTE HIT via MatchFSM
-- ─────────────────────────────────────────────────────────────
function Bot:_executeBotHit(touchType, tilt)
    -- Compute look vector toward opponent court
    local targetZ = self.team == "A" and 5 or -5
    local targetPos  = Vector3.new(0, GameConstants.Court.FloorY, targetZ)
    local lookVector = (targetPos - self.root.Position).Unit

    local bp = self.matchFSM.ball

    if touchType == "Bump" then
        self.matchFSM:registerTouch(
            { UserId = self.model.Name },  -- synthetic player ref for bots
            "Bump",
            bp.Velocity
        )
        self.matchFSM.ball.Velocity = self:_computeBotBump(lookVector)

    elseif touchType == "Set" then
        self.matchFSM:registerTouch({ UserId = self.model.Name }, "Set", bp.Velocity)
        self.matchFSM.ball.Velocity = Vector3.new(
            lookVector.X * 6, 22, lookVector.Z * 6
        )

    elseif touchType == "Spike" then
        -- Godly: check ability
        if self.difficulty == "Godly" and self.energy >= GameConstants.Ability.MaxEnergy then
            self:_activateAbility()
        end

        self.matchFSM:registerTouch({ UserId = self.model.Name }, "Spike", bp.Velocity)
        local spikeMult = self.style.SpikeMult or 1.0
        local vel = lookVector * (58 * spikeMult) + Vector3.new(0, -20, 0)
        vel = self.matchFSM.ball.Velocity  -- placeholder; real impl calls BallPhysics

        -- Apply WASD tilt
        if tilt then
            vel = self.matchFSM.ball.Velocity  -- BallPhysics._applyWASDModifier
        end

        self.matchFSM.ball.Velocity = vel

        Remotes.Events.SpawnEffect:FireAllClients({
            effectType    = "Spike",
            worldPosition = self.matchFSM.ball.Position,
            styleRarity   = self.style.rarity,
        })
    end
end

function Bot:_computeBotBump(lookVector)
    local C = GameConstants.Physics
    local angle = math.rad(C.BumpLiftAngle)
    return Vector3.new(
        lookVector.X * 8,
        math.sin(angle) * 20,
        lookVector.Z * 8
    )
end

-- ─────────────────────────────────────────────────────────────
-- ABILITY (Godly profile)
-- ─────────────────────────────────────────────────────────────
function Bot:_activateAbility()
    if self.energy < GameConstants.Ability.MaxEnergy then return end
    self.energy = 0
    local abilityName = self.style.Ability

    Remotes.Events.AbilityActivated:FireAllClients({
        playerID    = self.model.Name,
        abilityName = abilityName,
        duration    = self.style.AbilityDuration or 5,
    })

    -- Apply physics override modifier (ShieldBreaker example)
    if abilityName == "ShieldBreaker" then
        -- Ball passes through blocker hitboxes: set tag on ball
        self.matchFSM.ball:SetAttribute("ShieldBreaker", true)
        task.delay(self.style.AbilityDuration or 5, function()
            self.matchFSM.ball:SetAttribute("ShieldBreaker", false)
        end)
    end
end

function Bot:addEnergy(amount)
    self.energy = math.clamp(self.energy + amount, 0, GameConstants.Ability.MaxEnergy)
end

function Bot:destroy()
    if self._conn then self._conn:Disconnect() end
end

return Bot
