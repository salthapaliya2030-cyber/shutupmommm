-- ============================================================
-- StyleProfiles.lua  |  gameplay/gacha/
-- Authoritative style profile data table.
-- Each entry contains the full multiplier set, ability config,
-- trail visuals, and unlock level requirement.
-- This module extends GameConstants.Styles with richer metadata
-- and is the canonical reference for all style-based logic.
-- ============================================================

local StyleProfiles = {}

-- ─────────────────────────────────────────────────────────────
-- RARITY TIER DEFINITIONS
-- ─────────────────────────────────────────────────────────────
StyleProfiles.RarityOrder = {
    "Common", "Rare", "Legendary", "Godly", "Secret"
}

StyleProfiles.RarityColors = {
    Common    = Color3.fromRGB(180, 180, 180),
    Rare      = Color3.fromRGB(100, 180, 255),
    Legendary = Color3.fromRGB(255, 200, 0),
    Godly     = Color3.fromRGB(160, 32, 240),
    Secret    = Color3.fromRGB(255, 60, 20),
}

-- ─────────────────────────────────────────────────────────────
-- STYLE CATALOG
-- ─────────────────────────────────────────────────────────────
StyleProfiles.Catalog = {

    -- ════════════════════════════════════════
    --  COMMON TIER
    -- ════════════════════════════════════════
    Rookie = {
        rarity        = "Common",
        displayName   = "Rookie",
        description   = "The starting kit. No frills, no thrills.",
        levelRequired = 1,

        -- Physics multipliers (applied over base constants)
        JumpMult  = 1.00,
        SpeedMult = 1.00,
        SpikeMult = 1.00,
        BlockMult = 1.00,

        -- Ability
        Ability         = "None",
        AbilityDuration = 0,

        -- Visuals
        TrailColor    = Color3.fromRGB(200, 200, 200),
        OutlineColor  = Color3.fromRGB(0, 0, 0),
        AuraEnabled   = false,
    },

    Scrapper = {
        rarity        = "Common",
        displayName   = "Scrapper",
        description   = "A fighter spirit with slightly improved reaction.",
        levelRequired = 1,

        JumpMult  = 1.05,
        SpeedMult = 1.08,
        SpikeMult = 1.02,
        BlockMult = 1.05,

        Ability         = "None",
        AbilityDuration = 0,

        TrailColor   = Color3.fromRGB(150, 150, 150),
        AuraEnabled  = false,
    },

    -- ════════════════════════════════════════
    --  RARE TIER
    -- ════════════════════════════════════════
    Ace = {
        rarity        = "Rare",
        displayName   = "Ace",
        description   = "The class ace. Elevated jump, first taste of ability.",
        levelRequired = 5,

        JumpMult  = 1.15,
        SpeedMult = 1.10,
        SpikeMult = 1.20,
        BlockMult = 1.00,

        Ability         = "BoomJump",
        AbilityDuration = 4.0,
        AbilityDesc     = "Grants 60% extra jump height for 4 seconds.",

        TrailColor   = Color3.fromRGB(100, 180, 255),
        OutlineColor = Color3.fromRGB(0, 80, 180),
        AuraEnabled  = false,
    },

    Blitz = {
        rarity        = "Rare",
        displayName   = "Blitz",
        description   = "Traded spike power for blistering court speed.",
        levelRequired = 5,

        JumpMult  = 1.10,
        SpeedMult = 1.30,
        SpikeMult = 1.08,
        BlockMult = 1.05,

        Ability         = "BoomJump",
        AbilityDuration = 3.5,

        TrailColor   = Color3.fromRGB(80, 200, 255),
        AuraEnabled  = false,
    },

    -- ════════════════════════════════════════
    --  LEGENDARY TIER
    -- ════════════════════════════════════════
    Phantom = {
        rarity        = "Legendary",
        displayName   = "Phantom",
        description   = "A ghost on the court. Ball bends to their will.",
        levelRequired = 10,

        JumpMult  = 1.35,
        SpeedMult = 1.25,
        SpikeMult = 1.45,
        BlockMult = 1.15,

        Ability         = "MagneticPull",
        AbilityDuration = 5.0,
        AbilityDesc     = "Ball curves toward Phantom for 5 seconds.",

        TrailColor    = Color3.fromRGB(255, 200, 0),
        OutlineColor  = Color3.fromRGB(180, 140, 0),
        AuraEnabled   = true,
        AuraColor     = Color3.fromRGB(255, 230, 80),
        AuraIntensity = 0.4,
    },

    Ironwall = {
        rarity        = "Legendary",
        displayName   = "Ironwall",
        description   = "The impenetrable fortress. Defense-first archetype.",
        levelRequired = 10,

        JumpMult  = 1.20,
        SpeedMult = 1.00,
        SpikeMult = 1.10,
        BlockMult = 1.70,

        Ability         = "SteelBlock",
        AbilityDuration = 6.0,
        AbilityDesc     = "Blocks return ball at 2× speed for 6 seconds.",

        TrailColor    = Color3.fromRGB(200, 200, 80),
        OutlineColor  = Color3.fromRGB(160, 160, 0),
        AuraEnabled   = true,
        AuraColor     = Color3.fromRGB(255, 255, 100),
        AuraIntensity = 0.5,
    },

    -- ════════════════════════════════════════
    --  GODLY TIER
    -- ════════════════════════════════════════
    Nexus = {
        rarity        = "Godly",
        displayName   = "Nexus",
        description   = "Convergence of power. The benchmark of elite play.",
        levelRequired = 25,

        JumpMult  = 1.60,
        SpeedMult = 1.40,
        SpikeMult = 1.70,
        BlockMult = 1.35,

        Ability         = "SteelBlock",
        AbilityDuration = 6.0,
        AbilityDesc     = "All blocks become unstoppable return volleys.",

        TrailColor    = Color3.fromRGB(160, 32, 240),
        OutlineColor  = Color3.fromRGB(100, 0, 180),
        AuraEnabled   = true,
        AuraColor     = Color3.fromRGB(180, 60, 255),
        AuraIntensity = 0.7,
        LightningTrail = true,
    },

    Tempest = {
        rarity        = "Godly",
        displayName   = "Tempest",
        description   = "A storm in motion. Curves, bends, and destroys.",
        levelRequired = 25,

        JumpMult  = 1.65,
        SpeedMult = 1.55,
        SpikeMult = 1.65,
        BlockMult = 1.20,

        Ability         = "MagneticPull",
        AbilityDuration = 7.0,
        AbilityDesc     = "Ball magnetically returns to Tempest for 7 seconds.",

        TrailColor    = Color3.fromRGB(120, 0, 220),
        OutlineColor  = Color3.fromRGB(80, 0, 160),
        AuraEnabled   = true,
        AuraColor     = Color3.fromRGB(140, 40, 255),
        AuraIntensity = 0.8,
    },

    -- ════════════════════════════════════════
    --  SECRET TIER
    -- ════════════════════════════════════════
    Void = {
        rarity        = "Secret",
        displayName   = "Void",
        description   = "From the abyss. Breaks every rule of the game.",
        levelRequired = 50,

        JumpMult  = 2.00,
        SpeedMult = 1.65,
        SpikeMult = 2.20,
        BlockMult = 1.80,

        Ability         = "ShieldBreaker",
        AbilityDuration = 7.0,
        AbilityDesc     = "Spikes phase through blocker hitboxes for 7 seconds.",

        TrailColor    = Color3.fromRGB(255, 60, 20),
        OutlineColor  = Color3.fromRGB(180, 20, 0),
        AuraEnabled   = true,
        AuraColor     = Color3.fromRGB(255, 80, 30),
        AuraIntensity = 1.0,
        LightningTrail = true,
        GroundCrackOnLand = true,   -- extra VFX: cracks appear on jump land
    },

    Eclipse = {
        rarity        = "Secret",
        displayName   = "Eclipse",
        description   = "The darkness before the dawn. Total domination.",
        levelRequired = 50,

        JumpMult  = 1.90,
        SpeedMult = 1.80,
        SpikeMult = 2.10,
        BlockMult = 2.00,

        Ability         = "ShieldBreaker",
        AbilityDuration = 8.0,
        AbilityDesc     = "Maximum duration ShieldBreaker. Nullifies all blocks.",

        TrailColor    = Color3.fromRGB(255, 30, 60),
        OutlineColor  = Color3.fromRGB(150, 0, 30),
        AuraEnabled   = true,
        AuraColor     = Color3.fromRGB(255, 50, 80),
        AuraIntensity = 1.0,
        LightningTrail    = true,
        GroundCrackOnLand = true,
    },
}

-- ─────────────────────────────────────────────────────────────
-- HELPERS
-- ─────────────────────────────────────────────────────────────

-- Get all style names for a given rarity
function StyleProfiles.getByRarity(rarity)
    local out = {}
    for name, def in pairs(StyleProfiles.Catalog) do
        if def.rarity == rarity then
            table.insert(out, name)
        end
    end
    return out
end

-- Get display string for UI gacha result panel
function StyleProfiles.getDisplayInfo(styleKey)
    local def = StyleProfiles.Catalog[styleKey]
    if not def then return nil end
    return {
        name        = def.displayName,
        rarity      = def.rarity,
        description = def.description,
        ability     = def.AbilityDesc or "None",
        color       = StyleProfiles.RarityColors[def.rarity],
    }
end

-- Validate that a profile's equipped style is in their inventory
function StyleProfiles.isOwned(inventory, styleKey)
    return table.find(inventory, styleKey) ~= nil
end

return StyleProfiles
