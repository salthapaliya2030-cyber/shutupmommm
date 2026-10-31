-- ============================================================
-- ServeController.lua  |  gameplay/match/
-- Server-authoritative serve sequence.
-- Welds ball to server hand, triggers toss, power meter window,
-- validates timing, and executes serve or foot fault.
-- ============================================================

local RunService    = game:GetService("RunService")
local GameConstants = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes       = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)
local BallPhysics   = require(script.Parent.Parent.physics.BallPhysics)

local ServeController = {}
ServeController.__index = ServeController

-- ─────────────────────────────────────────────────────────────
-- SERVE PHASE STATES
-- ─────────────────────────────────────────────────────────────
local Phase = {
    IDLE            = "IDLE",
    TOSS_PENDING    = "TOSS_PENDING",
    POWER_WINDOW    = "POWER_WINDOW",
    COMPLETE        = "COMPLETE",
    FAULT           = "FAULT",
}

function ServeController.new(ball, ballPhysics, matchFSM)
    local self = setmetatable({}, ServeController)

    self.ball       = ball
    self.ballPhys   = ballPhysics
    self.matchFSM   = matchFSM
    self.phase      = Phase.IDLE
    self.serverPlayer = nil
    self.tossTime     = nil
    self.inputWindowStart = nil
    self.inputWindowEnd   = nil

    return self
end

-- ─────────────────────────────────────────────────────────────
-- BEGIN SERVE SEQUENCE
-- ─────────────────────────────────────────────────────────────
function ServeController:beginServe(serverPlayer)
    self.phase        = Phase.TOSS_PENDING
    self.serverPlayer = serverPlayer

    -- Get server's hand joint
    local char = serverPlayer.Character
    if not char then
        self:_fault("NoCharacter")
        return
    end

    local handJoint = char:FindFirstChild("RightHand")
    if not handJoint then
        self:_fault("NoHandJoint")
        return
    end

    -- Position ball at serve spawn (behind back line)
    local team       = self.matchFSM:_getPlayerTeam(serverPlayer)
    local serveSpawn = GameConstants.Court.ServeSpawn[team or "A"]
    self.ball.CFrame = CFrame.new(serveSpawn.x, serveSpawn.y + 1.2, serveSpawn.z)

    -- Weld ball to hand to prevent premature gravity drop
    self.ballPhys:attachToHand(handJoint)

    print("[ServeController] Ball welded to hand of " .. serverPlayer.Name)
end

-- ─────────────────────────────────────────────────────────────
-- TOSS (triggered by server receiving TossInput from client)
-- ─────────────────────────────────────────────────────────────
function ServeController:executeToss()
    if self.phase ~= Phase.TOSS_PENDING then return end

    -- Play toss animation
    Remotes.Events.PlayAnimation:FireAllClients({
        playerID         = self.serverPlayer.UserId,
        animationName    = "Serve",
        contactFrameTime = GameConstants.AnimMarkers.Serve.ContactFrame,
    })

    -- Release ball with vertical velocity
    self.ballPhys:releaseToss()
    self.tossTime = os.clock()
    self.phase    = Phase.POWER_WINDOW

    -- Open input window
    local markers = GameConstants.AnimMarkers.Serve
    self.inputWindowStart = self.tossTime + markers.InputWindow.Start
    self.inputWindowEnd   = self.tossTime + markers.InputWindow.End

    -- Auto-fault if no input received by window close
    task.delay(markers.InputWindow.End + 0.05, function()
        if self.phase == Phase.POWER_WINDOW then
            self:_fault("MissedWindow")
        end
    end)
end

-- ─────────────────────────────────────────────────────────────
-- SERVE HIT (client input arrives during power window)
-- ─────────────────────────────────────────────────────────────
function ServeController:receiveHitInput(lookVector, dirModifier)
    if self.phase ~= Phase.POWER_WINDOW then return end

    local now     = os.clock()
    local inWindow = now >= self.inputWindowStart and now <= self.inputWindowEnd

    if not inWindow then
        self:_fault("FootFault_TimingMiss")
        return
    end

    -- Calculate power from timing (center of window = max power)
    local windowMid  = (self.inputWindowStart + self.inputWindowEnd) / 2
    local windowHalf = (self.inputWindowEnd - self.inputWindowStart) / 2
    local offset     = math.abs(now - windowMid)
    local power      = 1.0 - (offset / windowHalf) * 0.5  -- 0.5 to 1.0

    -- Execute serve
    self.ballPhys:executeServe(lookVector, power, dirModifier)

    self.phase = Phase.COMPLETE
    print(string.format("[ServeController] Serve executed. Power: %.2f", power))
end

-- ─────────────────────────────────────────────────────────────
-- FAULT
-- ─────────────────────────────────────────────────────────────
function ServeController:_fault(reason)
    self.phase = Phase.FAULT

    print("[ServeController] Fault: " .. reason)

    -- Award point to opposing team
    local team         = self.matchFSM:_getPlayerTeam(self.serverPlayer)
    local scoringTeam  = team == "A" and "B" or "A"

    Remotes.Events.FoulTriggered:FireAllClients({
        foulType        = "ServiceFault",
        offendingPlayer = self.serverPlayer.UserId,
        pointAwardedTo  = scoringTeam,
    })

    self.matchFSM:_awardPoint(scoringTeam, "ServiceFault_" .. reason)
end

return ServeController
