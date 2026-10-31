-- ============================================================
-- WorldInit.lua  |  gameplay/match/
-- Server Script – runs ONCE at server start.
-- Initializes the world: builds court, wires all server
-- systems together into a unified game loop.
-- Runs BEFORE ServerMain.lua kicks in for player handling.
-- ============================================================

local CourtBuilder      = require(script.Parent.CourtBuilder)
local SlotValidator     = require(script.Parent.SlotValidator)
local SetRegulationEngine = require(script.Parent.SetRegulationEngine)
local AbilityManager    = require(script.Parent.AbilityManager)
local StyleApplier      = require(script.Parent.StyleApplier)
local GameConstants     = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes           = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)

-- ─────────────────────────────────────────────────────────────
-- PHASE 1: BUILD WORLD GEOMETRY
-- ─────────────────────────────────────────────────────────────
print("[WorldInit] Building court geometry...")
local courtFolder = CourtBuilder.build()
print("[WorldInit] Court built: " .. courtFolder.Name)

-- ─────────────────────────────────────────────────────────────
-- PHASE 2: INITIALIZE SHARED SERVICES
-- ─────────────────────────────────────────────────────────────
local ball = workspace:WaitForChild("Volleyball", 10)
if not ball then
    error("[WorldInit] FATAL: Volleyball not found in workspace after 10s")
end

-- Slot validator (singleton for this server session)
local slotValidator = SlotValidator.new()
_G.SlotValidator = slotValidator  -- expose for ServerMain

-- Set regulation engine
local setEngine = SetRegulationEngine.new()
_G.SetEngine = setEngine

-- Ability manager
local abilityManager = AbilityManager.new(ball)
_G.AbilityManager = abilityManager

print("[WorldInit] Services initialized.")

-- ─────────────────────────────────────────────────────────────
-- PHASE 3: WIRE REMOTE FUNCTION HANDLERS
-- ─────────────────────────────────────────────────────────────

-- RequestJoinSlot handled by SlotValidator
Remotes.Functions.RequestJoinSlot.OnServerInvoke = function(player, payload)
    local result = slotValidator:claimSlot(player, payload.team, payload.position)
    if result.success then
        -- Assign team attribute for other systems to read
        player:SetAttribute("Team",     payload.team)
        player:SetAttribute("Position", payload.position)
    end
    return result
end

-- RequestAbility
Remotes.Functions.RequestAbility.OnServerInvoke = function(player)
    local success = abilityManager:tryActivate(player)
    return { success = success }
end

-- ─────────────────────────────────────────────────────────────
-- PHASE 4: PLAYER CONNECTION LIFECYCLE
-- ─────────────────────────────────────────────────────────────
local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
    -- Register for ability tracking when they join a match
    player.CharacterAdded:Connect(function(character)
        local styleKey   = player:GetAttribute("EquippedStyle") or "Rookie"
        local assignment = slotValidator:getAssignment(player)
        if assignment then
            -- Apply style physics multipliers
            StyleApplier.applyToCharacter(player, character, styleKey)
            -- Register with ability manager
            abilityManager:registerPlayer(player, styleKey)
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    slotValidator:releaseSlot(player)
    abilityManager:unregisterPlayer(player)
end)

-- ─────────────────────────────────────────────────────────────
-- PHASE 5: HEARTBEAT – ABILITY TIMER TICKS
-- ─────────────────────────────────────────────────────────────
local RunService = game:GetService("RunService")
RunService.Heartbeat:Connect(function(dt)
    abilityManager:update(dt)
end)

-- ─────────────────────────────────────────────────────────────
-- PHASE 6: MATCH END REWARD FLOW
-- ─────────────────────────────────────────────────────────────
Remotes.Events.MatchWon.OnServerEvent = nil  -- MatchWon is only server→client

-- Internal callback from MatchStateMachine (called directly, not via remote)
function _G.onMatchEnd(winningTeam, playerTeamMap)
    local GachaEngine = require(
        game.ServerScriptService.AnimeVB.gameplay.gacha.GachaEngine
    )

    -- Calculate rewards
    local rewards = setEngine:calculateRewards(winningTeam, playerTeamMap)

    -- Append to each player's currency profile
    for userId, yen in pairs(rewards) do
        local player = Players:GetPlayerByUserId(userId)
        if player then
            GachaEngine.appendReward(player, yen)
        end
    end

    -- Broadcast final match result
    Remotes.Events.MatchWon:FireAllClients({
        winningTeam = winningTeam,
        rewards     = rewards,
    })

    -- Full reset after delay
    task.delay(5.0, function()
        setEngine:fullReset()
        slotValidator:reset()
        abilityManager:resetAll()

        -- Teleport everyone back to lobby zone
        for _, player in ipairs(Players:GetPlayers()) do
            local char = player.Character
            if char then
                -- Lobby spawn behind match zone
                local C = GameConstants.Court
                char.HumanoidRootPart.CFrame =
                    CFrame.new(0, C.FloorY + 1, C.HalfLength + 8)
            end
            Remotes.Events.TransitionToLobby:FireClient(player)
        end
    end)
end

print("[WorldInit] World initialization complete. Server ready.")
