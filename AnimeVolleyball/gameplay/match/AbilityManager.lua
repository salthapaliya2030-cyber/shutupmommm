-- ============================================================
-- AbilityManager.lua  |  gameplay/match/
-- Server-authoritative ability and energy meter manager.
-- Tracks energy per player, validates F-key activations,
-- applies physics override modifiers, and manages duration timers.
-- ============================================================

local GameConstants = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes       = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)

local AbilityManager = {}
AbilityManager.__index = AbilityManager

-- ─────────────────────────────────────────────────────────────
-- CONSTRUCTION
-- ─────────────────────────────────────────────────────────────
function AbilityManager.new(ball)
    local self = setmetatable({}, AbilityManager)

    self.ball = ball

    -- Per-player energy state
    -- [userId] = { energy, styleKey, abilityActive, abilityTimer }
    self.playerState = {}

    return self
end

-- ─────────────────────────────────────────────────────────────
-- REGISTER PLAYER
-- ─────────────────────────────────────────────────────────────
function AbilityManager:registerPlayer(player, styleKey)
    local style = GameConstants.Styles[styleKey] or GameConstants.Styles.Rookie
    self.playerState[player.UserId] = {
        energy        = 0,
        styleKey      = styleKey,
        style         = style,
        abilityActive = false,
        abilityTimer  = 0,
    }
end

function AbilityManager:unregisterPlayer(player)
    self.playerState[player.UserId] = nil
end

-- ─────────────────────────────────────────────────────────────
-- ENERGY GAIN  (called from ServerMain on each registered touch)
-- ─────────────────────────────────────────────────────────────
function AbilityManager:addEnergy(player, touchType)
    local state = self.playerState[player.UserId]
    if not state then return end

    local A     = GameConstants.Ability
    local gain  = 0

    if touchType == "Bump"           then gain = A.GainPerBump
    elseif touchType == "Set"        then gain = A.GainPerSet
    elseif touchType == "Spike"      then gain = A.GainPerSpike
    elseif touchType == "PerfectReceive" then
        gain = A.GainPerBump + A.GainPerPerfect
    end

    state.energy = math.clamp(state.energy + gain, 0, A.MaxEnergy)

    -- Sync to client
    Remotes.Events.EnergyUpdate:FireClient(player, {
        playerID  = player.UserId,
        newEnergy = state.energy,
    })
end

-- ─────────────────────────────────────────────────────────────
-- ABILITY ACTIVATION  (F key, validated server-side)
-- ─────────────────────────────────────────────────────────────
function AbilityManager:tryActivate(player)
    local state = self.playerState[player.UserId]
    if not state then return false end

    -- Must be at full energy and not already active
    if state.energy < GameConstants.Ability.MaxEnergy then return false end
    if state.abilityActive then return false end

    local style       = state.style
    local abilityName = style.Ability
    if not abilityName or abilityName == "None" then return false end

    -- Drain energy
    state.energy        = 0
    state.abilityActive = true
    state.abilityTimer  = style.AbilityDuration or 5.0

    -- Broadcast to all clients (visual overlay, HUD update)
    Remotes.Events.AbilityActivated:FireAllClients({
        playerID    = player.UserId,
        abilityName = abilityName,
        duration    = state.abilityTimer,
    })

    -- Sync drained energy bar
    Remotes.Events.EnergyUpdate:FireClient(player, {
        playerID  = player.UserId,
        newEnergy = 0,
    })

    -- Apply physics modifier
    self:_applyAbilityModifier(player, abilityName, state.abilityTimer)

    -- Head text pop
    Remotes.Events.HeadTextPop:FireAllClients({
        playerID  = player.UserId,
        textLabel = abilityName,
    })

    print(string.format("[AbilityManager] %s activated %s for %.1fs",
        player.Name, abilityName, state.abilityTimer))

    return true
end

-- ─────────────────────────────────────────────────────────────
-- PHYSICS MODIFIER APPLICATION
-- ─────────────────────────────────────────────────────────────
function AbilityManager:_applyAbilityModifier(player, abilityName, duration)

    if abilityName == "BoomJump" then
        -- Temporarily boost jump impulse via character attribute
        local char = player.Character
        if char then
            char:SetAttribute("JumpBoost", 1.6)
            task.delay(duration, function()
                if char and char.Parent then
                    char:SetAttribute("JumpBoost", nil)
                end
            end)
        end

    elseif abilityName == "MagneticPull" then
        -- Ball curves toward this player on contact (tag on ball)
        self.ball:SetAttribute("MagneticPlayer", player.UserId)
        task.delay(duration, function()
            if self.ball and self.ball.Parent then
                self.ball:SetAttribute("MagneticPlayer", nil)
            end
        end)

    elseif abilityName == "SteelBlock" then
        -- Any block hit by this player returns at 2× speed
        local char = player.Character
        if char then
            char:SetAttribute("SteelBlock", true)
            task.delay(duration, function()
                if char and char.Parent then
                    char:SetAttribute("SteelBlock", nil)
                end
            end)
        end

    elseif abilityName == "ShieldBreaker" then
        -- Ball passes through blocker hitboxes this duration
        self.ball:SetAttribute("ShieldBreaker", player.UserId)
        task.delay(duration, function()
            if self.ball and self.ball.Parent then
                self.ball:SetAttribute("ShieldBreaker", nil)
            end
        end)
    end
end

-- ─────────────────────────────────────────────────────────────
-- UPDATE  (called from Heartbeat; decrements ability timers)
-- ─────────────────────────────────────────────────────────────
function AbilityManager:update(dt)
    for userId, state in pairs(self.playerState) do
        if state.abilityActive then
            state.abilityTimer = state.abilityTimer - dt
            if state.abilityTimer <= 0 then
                state.abilityActive = false
                state.abilityTimer  = 0
                -- Passive energy regen starts here (optional: extend with regen rate)
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- MAGNETIC PULL CHECK  (called from BallPhysics on contact)
-- If ball has MagneticPlayer attribute, bend velocity toward them
-- ─────────────────────────────────────────────────────────────
function AbilityManager:applyMagneticPull(ballPart, allCharacters)
    local magnetUID = ballPart:GetAttribute("MagneticPlayer")
    if not magnetUID then return end

    -- Find target character
    for _, char in pairs(allCharacters) do
        local playerRef = game.Players:GetPlayerFromCharacter(char)
        if playerRef and playerRef.UserId == magnetUID then
            local dir     = (char.HumanoidRootPart.Position - ballPart.Position).Unit
            ballPart.Velocity = ballPart.Velocity + dir * 8
            return
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- STEEL BLOCK CHECK  (called from BallPhysics on block contact)
-- ─────────────────────────────────────────────────────────────
function AbilityManager:checkSteelBlock(player, ballVelocity)
    local char = player.Character
    if not char then return ballVelocity end
    if not char:GetAttribute("SteelBlock") then return ballVelocity end
    -- Return ball at 2× speed
    return ballVelocity * -2.0
end

-- ─────────────────────────────────────────────────────────────
-- SHIELD BREAKER CHECK  (called before blocker hitbox test)
-- Returns true if ball should BYPASS blocker
-- ─────────────────────────────────────────────────────────────
function AbilityManager:isShieldBreaker(ballPart)
    return ballPart:GetAttribute("ShieldBreaker") ~= nil
end

-- ─────────────────────────────────────────────────────────────
-- RESET ALL (on round end)
-- ─────────────────────────────────────────────────────────────
function AbilityManager:resetAll()
    for _, state in pairs(self.playerState) do
        -- Energy persists between rallies (only resets on match end)
        state.abilityActive = false
        state.abilityTimer  = 0
    end

    -- Clear ball ability tags
    if self.ball then
        self.ball:SetAttribute("ShieldBreaker",  nil)
        self.ball:SetAttribute("MagneticPlayer", nil)
    end
end

return AbilityManager
