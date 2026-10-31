-- ============================================================
-- CharacterStateMachine.lua  |  gameplay/fsm/
-- Server-authoritative finite state machine.
-- Five mutually exclusive states per character.
-- All state transitions validated server-side only.
-- ============================================================

local RunService    = game:GetService("RunService")
local GameConstants = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes       = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)

-- ─────────────────────────────────────────────────────────────
-- STATES
-- ─────────────────────────────────────────────────────────────
local States = {
    IDLE        = "IDLE",
    RUNNING     = "RUNNING",
    AIRBORNE    = "AIRBORNE",
    RECOVERING  = "RECOVERING",   -- post-dive recovery, inputs LOCKED
    STUNNED     = "STUNNED",      -- mistimed hit stun, inputs LOCKED
}

-- ─────────────────────────────────────────────────────────────
-- CHARACTER STATE OBJECT
-- ─────────────────────────────────────────────────────────────
local CharacterStateMachine = {}
CharacterStateMachine.__index = CharacterStateMachine

function CharacterStateMachine.new(player, humanoidRootPart, humanoid)
    local self = setmetatable({}, CharacterStateMachine)

    self.player          = player
    self.root            = humanoidRootPart
    self.humanoid        = humanoid
    self.currentState    = States.IDLE
    self.stateTimer      = 0        -- tracks time spent in locked states
    self.lockedDuration  = 0        -- duration of current lock
    self.jumpVelocity    = nil      -- immutable vector set on jump takeoff
    self.canInput        = true     -- master input gate

    -- Style stat cache (loaded from profile on spawn)
    self.style = GameConstants.Styles.Rookie  -- default

    return self
end

-- ─────────────────────────────────────────────────────────────
-- TRANSITION  – the only legal way to change state
-- ─────────────────────────────────────────────────────────────
function CharacterStateMachine:transition(newState, optDuration)
    if self.currentState == newState then return end

    -- Exit old state
    self:_onExit(self.currentState)

    local prev = self.currentState
    self.currentState = newState
    self.stateTimer   = 0
    self.lockedDuration = optDuration or 0

    -- Lock inputs for recovery and stun
    self.canInput = not (
        newState == States.RECOVERING or
        newState == States.STUNNED
    )

    -- Notify clients
    Remotes.Events.StateChanged:FireAllClients({
        playerID = self.player.UserId,
        newState = newState,
    })

    -- Enter new state
    self:_onEnter(newState)

    print(string.format("[FSM] %s: %s → %s", self.player.Name, prev, newState))
end

-- ─────────────────────────────────────────────────────────────
-- JUMP  – captures immutable arc, blocks mid-air input changes
-- ─────────────────────────────────────────────────────────────
function CharacterStateMachine:executeJump()
    if self.currentState ~= States.IDLE and
       self.currentState ~= States.RUNNING then
        return false
    end

    local styleJumpMult = self.style.JumpMult or 1.0
    local jumpY = GameConstants.Physics.JumpImpulse * styleJumpMult

    -- Lock the horizontal velocity to current root velocity (no mid-air redirect)
    local horizVel = Vector3.new(self.root.Velocity.X, 0, self.root.Velocity.Z)
    self.jumpVelocity = Vector3.new(horizVel.X, jumpY, horizVel.Z)

    -- Apply to physics body
    self.root.Velocity = self.jumpVelocity

    self:transition(States.AIRBORNE)
    return true
end

-- ─────────────────────────────────────────────────────────────
-- LAND  – called when root.Y returns to FloorY
-- ─────────────────────────────────────────────────────────────
function CharacterStateMachine:onLand()
    if self.currentState ~= States.AIRBORNE then return end
    self.jumpVelocity = nil
    self:transition(States.IDLE)
end

-- ─────────────────────────────────────────────────────────────
-- DIVE  – transitions to RECOVERING for RecoverEnd duration
-- ─────────────────────────────────────────────────────────────
function CharacterStateMachine:executeDive()
    if not self.canInput then return false end
    if self.currentState == States.AIRBORNE or
       self.currentState == States.RECOVERING or
       self.currentState == States.STUNNED then
        return false
    end

    local recoverDuration = GameConstants.AnimMarkers.Dive.RecoverEnd
    self:transition(States.RECOVERING, recoverDuration)
    return true
end

-- ─────────────────────────────────────────────────────────────
-- STUN  – penalty for mistimed hit
-- ─────────────────────────────────────────────────────────────
function CharacterStateMachine:applyStun()
    local dur = GameConstants.AnimMarkers.StunLength
    self:transition(States.STUNNED, dur)
    Remotes.Events.StunPlayer:FireAllClients({
        playerID = self.player.UserId,
        duration = dur,
    })
    Remotes.Events.HeadTextPop:FireAllClients({
        playerID  = self.player.UserId,
        textLabel = "TOO LOW!",
    })
end

-- ─────────────────────────────────────────────────────────────
-- UPDATE  – called every Heartbeat tick from MatchEngine
-- ─────────────────────────────────────────────────────────────
function CharacterStateMachine:update(dt)
    self.stateTimer = self.stateTimer + dt

    -- Auto-release locked states when timer expires
    if (self.currentState == States.RECOVERING or
        self.currentState == States.STUNNED) and
       self.lockedDuration > 0 and
       self.stateTimer >= self.lockedDuration then

        self:transition(States.IDLE)
        return
    end

    -- Airborne land detection
    if self.currentState == States.AIRBORNE then
        local rootY = self.root.Position.Y
        if rootY <= (GameConstants.Court.FloorY + 0.15) then
            self:onLand()
        end
    end

    -- Walking speed clamp (enforce minimum floor)
    if self.currentState == States.RUNNING or self.currentState == States.IDLE then
        local spd = self.humanoid.WalkSpeed
        if spd < GameConstants.Physics.WalkSpeedMin then
            self.humanoid.WalkSpeed = GameConstants.Physics.WalkSpeedMin
        end
        local styleSpeedMult = self.style.SpeedMult or 1.0
        local maxSpd = GameConstants.Physics.WalkSpeedMax * styleSpeedMult
        if spd > maxSpd then
            self.humanoid.WalkSpeed = maxSpd
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- INTERNAL CALLBACKS
-- ─────────────────────────────────────────────────────────────
function CharacterStateMachine:_onEnter(state)
    if state == States.STUNNED then
        -- Freeze velocity
        self.root.Velocity = Vector3.zero
    end
end

function CharacterStateMachine:_onExit(state)
    -- Nothing needed currently; reserved for cleanup hooks
end

-- ─────────────────────────────────────────────────────────────
-- GETTERS
-- ─────────────────────────────────────────────────────────────
function CharacterStateMachine:getState() return self.currentState end
function CharacterStateMachine:isInputBlocked() return not self.canInput end
function CharacterStateMachine:isAirborne() return self.currentState == States.AIRBORNE end

CharacterStateMachine.States = States
return CharacterStateMachine
