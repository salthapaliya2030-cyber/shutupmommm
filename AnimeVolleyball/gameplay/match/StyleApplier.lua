-- ============================================================
-- StyleApplier.lua  |  gameplay/match/
-- Reads a player's equipped Style from their saved profile
-- and overwrites their character's base physics constants.
-- Jump height, walk speed, spike velocity, and block defense
-- are all permanently overwritten for the match duration.
-- ============================================================

local GameConstants = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes       = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)

local StyleApplier = {}

-- ─────────────────────────────────────────────────────────────
-- APPLY STYLE TO CHARACTER
-- Called after character spawns and profile is loaded
-- ─────────────────────────────────────────────────────────────
function StyleApplier.applyToCharacter(player, character, styleKey)
    local style = GameConstants.Styles[styleKey]
    if not style then
        style = GameConstants.Styles.Rookie
        styleKey = "Rookie"
        warn("[StyleApplier] Unknown style '" .. tostring(styleKey) .. "', defaulting to Rookie")
    end

    local humanoid  = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        warn("[StyleApplier] No Humanoid found on character")
        return
    end

    -- ── WALK SPEED
    local newSpeed = GameConstants.Physics.WalkSpeedBase * (style.SpeedMult or 1.0)
    newSpeed       = math.clamp(newSpeed,
        GameConstants.Physics.WalkSpeedMin,
        GameConstants.Physics.WalkSpeedMax * 1.5)
    humanoid.WalkSpeed = newSpeed

    -- ── JUMP POWER
    -- Roblox Humanoid.JumpPower controls jump height
    local baseJump    = GameConstants.Physics.JumpImpulse
    local styledJump  = baseJump * (style.JumpMult or 1.0)
    humanoid.JumpPower = styledJump

    -- ── TAG CHARACTER WITH STYLE DATA (read by server on spike/block)
    character:SetAttribute("StyleKey",    styleKey)
    character:SetAttribute("SpikeMult",   style.SpikeMult  or 1.0)
    character:SetAttribute("BlockMult",   style.BlockMult  or 1.0)
    character:SetAttribute("JumpMult",    style.JumpMult   or 1.0)
    character:SetAttribute("AbilityName", style.Ability    or "None")
    character:SetAttribute("StyleRarity", style.rarity     or "Common")

    -- ── TRAIL COLOR (read by ParticleSystem on SpawnEffect)
    if style.TrailColor then
        local tc = style.TrailColor
        character:SetAttribute("TrailColorR", tc.R)
        character:SetAttribute("TrailColorG", tc.G)
        character:SetAttribute("TrailColorB", tc.B)
    end

    print(string.format("[StyleApplier] Applied style '%s' (%s) to %s | Speed:%.1f Jump:%.1f Spike:×%.2f Block:×%.2f",
        styleKey, style.rarity, player.Name,
        newSpeed, styledJump, style.SpikeMult or 1.0, style.BlockMult or 1.0))
end

-- ─────────────────────────────────────────────────────────────
-- READ STYLE MULTIPLIERS FROM CHARACTER ATTRIBUTES
-- Used by ServerMain spike/block handlers to avoid re-querying profile
-- ─────────────────────────────────────────────────────────────
function StyleApplier.getSpikeMult(character)
    return character:GetAttribute("SpikeMult") or 1.0
end

function StyleApplier.getBlockMult(character)
    return character:GetAttribute("BlockMult") or 1.0
end

function StyleApplier.getJumpMult(character)
    return character:GetAttribute("JumpMult") or 1.0
end

function StyleApplier.getStyleRarity(character)
    return character:GetAttribute("StyleRarity") or "Common"
end

function StyleApplier.getAbilityName(character)
    return character:GetAttribute("AbilityName") or "None"
end

-- ─────────────────────────────────────────────────────────────
-- VALIDATE LEVEL GATE  (called before applying style)
-- Returns true if player's level satisfies the style's requirement
-- ─────────────────────────────────────────────────────────────
function StyleApplier.validateLevelGate(accountLevel, styleKey)
    local style = GameConstants.Styles[styleKey]
    if not style then return false end

    local gates = GameConstants.Gacha.LevelGates
    local rarity = style.rarity

    if rarity == "Secret"    and accountLevel < gates.Secret    then return false end
    if rarity == "Godly"     and accountLevel < gates.Godly     then return false end
    if rarity == "Legendary" and accountLevel < gates.Legendary then return false end

    return true
end

-- ─────────────────────────────────────────────────────────────
-- BOT STYLE APPLICATION
-- Bots use Nexus (Godly) by default; difficulty can override
-- ─────────────────────────────────────────────────────────────
function StyleApplier.applyToBotModel(npcModel, styleKey)
    local style = GameConstants.Styles[styleKey] or GameConstants.Styles.Nexus
    local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    humanoid.WalkSpeed  = GameConstants.Physics.WalkSpeedBase * (style.SpeedMult or 1.0)
    humanoid.JumpPower  = GameConstants.Physics.JumpImpulse   * (style.JumpMult  or 1.0)

    npcModel:SetAttribute("StyleKey",    styleKey)
    npcModel:SetAttribute("SpikeMult",   style.SpikeMult  or 1.0)
    npcModel:SetAttribute("BlockMult",   style.BlockMult  or 1.0)
    npcModel:SetAttribute("StyleRarity", style.rarity     or "Common")
    npcModel:SetAttribute("AbilityName", style.Ability    or "None")
end

return StyleApplier
