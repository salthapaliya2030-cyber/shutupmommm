-- ============================================================
-- RemoteRegistry.lua  |  shared/remotes/
-- Central factory that creates and exposes every RemoteEvent
-- and RemoteFunction used across the client-server boundary.
-- Run this as a ModuleScript required by both Server and Client.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Parent folder inside ReplicatedStorage
local folder = ReplicatedStorage:FindFirstChild("GameRemotes")
if not folder then
    folder = Instance.new("Folder")
    folder.Name = "GameRemotes"
    folder.Parent = ReplicatedStorage
end

local function getOrCreate(class, name)
    local existing = folder:FindFirstChild(name)
    if existing then return existing end
    local obj = Instance.new(class)
    obj.Name = name
    obj.Parent = folder
    return obj
end

-- ─────────────────────────────────────────────────────────────
--  RemoteEvents  (fire-and-forget, server → client or vice-versa)
-- ─────────────────────────────────────────────────────────────
local RE = {}

-- INPUT: client → server (minimal signal only)
RE.PlayerInput          = getOrCreate("RemoteEvent", "PlayerInput")
    -- payload: { actionType, dirModifier, timestamp }

-- MATCH STATE: server → all clients
RE.MatchStateChanged    = getOrCreate("RemoteEvent", "MatchStateChanged")
    -- payload: { newState, teamScores, touchCount, servingTeam }

RE.BallVelocityUpdate   = getOrCreate("RemoteEvent", "BallVelocityUpdate")
    -- payload: { position, velocity, timestamp }

RE.TouchRegistered      = getOrCreate("RemoteEvent", "TouchRegistered")
    -- payload: { playerID, touchType, touchIndex, position }

RE.FoulTriggered        = getOrCreate("RemoteEvent", "FoulTriggered")
    -- payload: { foulType, offendingPlayer, pointAwardedTo }

RE.PointScored          = getOrCreate("RemoteEvent", "PointScored")
    -- payload: { scoringTeam, newScore, causeText }

RE.SetWon               = getOrCreate("RemoteEvent", "SetWon")
    -- payload: { winningTeam, setScores }

RE.MatchWon             = getOrCreate("RemoteEvent", "MatchWon")
    -- payload: { winningTeam, stats, rewardYen }

-- ANIMATION SYNC: server → all clients
RE.PlayAnimation        = getOrCreate("RemoteEvent", "PlayAnimation")
    -- payload: { playerID, animationName, contactFrameTime }

RE.SpawnEffect          = getOrCreate("RemoteEvent", "SpawnEffect")
    -- payload: { effectType, worldPosition, styleRarity }

RE.HeadTextPop          = getOrCreate("RemoteEvent", "HeadTextPop")
    -- payload: { playerID, textLabel }

RE.ScreenShake          = getOrCreate("RemoteEvent", "ScreenShake")
    -- payload: { magnitude, frequency, decay }

RE.RadialFlash          = getOrCreate("RemoteEvent", "RadialFlash")
    -- payload: { duration, color }

-- ABILITY
RE.AbilityActivated     = getOrCreate("RemoteEvent", "AbilityActivated")
    -- payload: { playerID, abilityName, duration }

RE.EnergyUpdate         = getOrCreate("RemoteEvent", "EnergyUpdate")
    -- payload: { playerID, newEnergy }

-- GACHA / ECONOMY
RE.SpinResult           = getOrCreate("RemoteEvent", "SpinResult")
    -- payload: { rarity, styleName, currencyBalances }

RE.CurrencyUpdate       = getOrCreate("RemoteEvent", "CurrencyUpdate")
    -- payload: { yen, gems }

-- UI FLOW
RE.TransitionToMatch    = getOrCreate("RemoteEvent", "TransitionToMatch")
    -- payload: { team, position, spawnCoord }

RE.TransitionToLobby    = getOrCreate("RemoteEvent", "TransitionToLobby")
    -- payload: {}

RE.ShowMatchSetupPrompt = getOrCreate("RemoteEvent", "ShowMatchSetupPrompt")
    -- payload: { availableSlots }

RE.SlotStatusUpdate     = getOrCreate("RemoteEvent", "SlotStatusUpdate")
    -- payload: { slotTable }  -- updates team/position availability

RE.ErrorFeedback        = getOrCreate("RemoteEvent", "ErrorFeedback")
    -- payload: { message }

-- CHARACTER STATE
RE.StateChanged         = getOrCreate("RemoteEvent", "StateChanged")
    -- payload: { playerID, newState }

RE.StunPlayer           = getOrCreate("RemoteEvent", "StunPlayer")
    -- payload: { playerID, duration }

-- FLOOR SHADOW
RE.BallShadowUpdate     = getOrCreate("RemoteEvent", "BallShadowUpdate")
    -- payload: { x, z, radius, alpha }

-- ─────────────────────────────────────────────────────────────
--  RemoteFunctions  (request / response)
-- ─────────────────────────────────────────────────────────────
local RF = {}

RF.RequestSpin          = getOrCreate("RemoteFunction", "RequestSpin")
    -- client → server: { currency }  → returns { success, result or errorMsg }

RF.RequestJoinSlot      = getOrCreate("RemoteFunction", "RequestJoinSlot")
    -- client → server: { team, position } → returns { success, errorMsg? }

RF.RequestAbility       = getOrCreate("RemoteFunction", "RequestAbility")
    -- client → server: {} → returns { success }

RF.GetProfile           = getOrCreate("RemoteFunction", "GetProfile")
    -- client → server: {} → returns { yen, gems, level, style, inventory }

-- ─────────────────────────────────────────────────────────────
--  Public API
-- ─────────────────────────────────────────────────────────────
return {
    Events    = RE,
    Functions = RF,
    Folder    = folder,
}
