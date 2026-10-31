-- ============================================================
-- GameConstants.lua  |  shared/constants/
-- Single source of truth for every numeric constant, coordinate
-- grid value, and formula in the entire engine sandbox.
-- ALL other scripts must require() this module – never hardcode.
-- ============================================================

local GameConstants = {}

-- ─────────────────────────────────────────────────────────────
-- COURT GEOMETRY  (Cartesian, Y = vertical altitude)
-- ─────────────────────────────────────────────────────────────
GameConstants.Court = {
    -- Full court rectangle (centered at world origin)
    HalfLength   = 9,        -- Z axis (each side = 9 studs)
    HalfWidth    = 4.5,      -- X axis
    FloorY       = 0,        -- Y altitude of court surface

    -- Net
    NetPlaneZ    = 0,        -- Net sits at Z = 0
    NetTopY      = 2.43,     -- Official net height (men's)
    NetThickness = 0.05,

    -- Boundary walls (used by raycast surface-normal script)
    BoundaryPad  = 0.5,      -- Extra buffer before out-of-bounds

    -- Spawn coordinates  [team][position]
    Spawns = {
        A = {
            Spiker  = { x =  0,   y = 0, z = -5 },
            Setter  = { x = -2,   y = 0, z = -3 },
            Libero  = { x =  2,   y = 0, z = -7 },
        },
        B = {
            Spiker  = { x =  0,   y = 0, z =  5 },
            Setter  = { x =  2,   y = 0, z =  3 },
            Libero  = { x = -2,   y = 0, z =  7 },
        },
    },

    -- Serve start position (behind back line)
    ServeSpawn   = { A = { x=0, y=0, z=-9.5 }, B = { x=0, y=0, z=9.5 } },
}

-- ─────────────────────────────────────────────────────────────
-- PHYSICS CONSTANTS
-- ─────────────────────────────────────────────────────────────
GameConstants.Physics = {
    Gravity           = -196.2,   -- studs/s^2 (standard 9.81 * 20 scale)
    BallRadius        = 0.5,
    BallMass          = 0.27,     -- kg equivalent

    -- Jump arc (immutable once airborne)
    JumpImpulse       = 52,       -- initial vertical velocity (studs/s)
    JumpGravityMult   = 1.0,

    -- Walking/running
    WalkSpeedBase     = 16,
    WalkSpeedMin      = 4,        -- zero-stamina floor clamp
    WalkSpeedMax      = 24,

    -- Net rolling dampening
    NetFrictionMult   = 0.15,     -- strips 85 % of horizontal KE on net hit
    NetVertDamp       = 0.30,
    NetMinVelThresh   = 0.8,      -- below this → inject drop force
    NetDropForce      = -9.81,

    -- Touch cooldown (prevents single-frame multi-register)
    TouchCooldown     = 0.10,     -- seconds

    -- Spike directional modifiers (WASD)
    SpikeModifiers = {
        W_GravityBoost   = -1.6,  -- steeper cut shot (negative Y boost)
        S_HorizBoost     = 1.8,   -- deep back-row attack (more forward)
        A_LateralForce   = 14,    -- left curve
        D_LateralForce   = -14,   -- right curve
    },

    -- Bump vector transform
    BumpMomentumKill  = -0.25,    -- fraction applied to strip incoming velocity
    BumpLiftAngle     = 65,       -- degrees from horizontal for new arc

    -- Set velocity hard cap
    SetMaxVelocity    = 28,       -- studs/s magnitude ceiling

    -- Serve toss
    ServeTossVelocity = 18,
    ServePowerMin     = 0.3,
    ServePowerMax     = 1.0,
}

-- ─────────────────────────────────────────────────────────────
-- ANIMATION TIMELINE MARKERS  (seconds from track start)
-- ─────────────────────────────────────────────────────────────
GameConstants.AnimMarkers = {
    Spike = {
        WindupStart   = 0.00,
        WindupEnd     = 0.30,
        ContactFrame  = 0.42,    -- EXACT hand-peak; server registers hit here
        FollowThrough = 0.72,
        TrackLength   = 1.00,
    },
    Set = {
        WindupStart  = 0.00,
        ContactFrame = 0.25,
        TrackLength  = 0.55,
    },
    Bump = {
        WindupStart  = 0.00,
        ContactFrame = 0.20,
        TrackLength  = 0.50,
    },
    Serve = {
        TossFrame    = 0.30,
        InputWindow  = { Start = 0.55, End = 0.80 },
        ContactFrame = 0.70,
        TrackLength  = 1.10,
    },
    Dive = {
        ContactFrame = 0.18,
        RecoverEnd   = 1.40,
        TrackLength  = 1.60,
    },
    StunLength       = 1.20,
}

-- ─────────────────────────────────────────────────────────────
-- MATCH RULES
-- ─────────────────────────────────────────────────────────────
GameConstants.Match = {
    MaxTouches        = 3,
    SetWinPoints      = 25,
    DeuceGap          = 2,        -- must lead by this to win in deuce
    SetsToWinMatch    = 2,        -- best of 3
    MaxPlayersPerTeam = 3,
    RolesPerTeam      = { "Spiker", "Setter", "Libero" },
}

-- ─────────────────────────────────────────────────────────────
-- BOT AI PROFILES
-- ─────────────────────────────────────────────────────────────
GameConstants.Bot = {
    Easy = {
        PathLatency      = 0.75,  -- seconds delay before moving
        ErrorChance      = 0.35,  -- 35 % miss / mistimed hit
        ErrorEarlyBias   = 0.5,   -- of misses: 50 % too early, 50 % late
        WASDTiltEnabled  = false,
        AbilityEnabled   = false,
    },
    Medium = {
        PathLatency      = 0.20,
        ErrorChance      = 0.12,
        ErrorEarlyBias   = 0.5,
        WASDTiltEnabled  = true,
        TiltAccuracy     = 0.70,  -- 70 % land in intended zone
        AbilityEnabled   = false,
    },
    Godly = {
        PathLatency      = 0.00,
        ErrorChance      = 0.00,
        WASDTiltEnabled  = true,
        TiltAccuracy     = 1.00,
        AbilityEnabled   = true,
        AbilityReactTime = 0.00,  -- instant F-key deploy
    },
}

-- ─────────────────────────────────────────────────────────────
-- GACHA DROP TABLE
-- Weights are cumulative upper bounds on [0, 1]
-- ─────────────────────────────────────────────────────────────
GameConstants.Gacha = {
    -- Base weights (AccountLevel >= level gate for Secret/Godly/Legendary)
    DropTable = {
        { rarity = "Common",    weight = 0.60,  cumulative = 0.60  },
        { rarity = "Rare",      weight = 0.25,  cumulative = 0.85  },
        { rarity = "Legendary", weight = 0.10,  cumulative = 0.95  },
        { rarity = "Godly",     weight = 0.04,  cumulative = 0.99  },
        { rarity = "Secret",    weight = 0.01,  cumulative = 1.00  },
    },

    LevelGates = {
        Legendary = 10,
        Godly     = 25,
        Secret    = 50,
    },

    SpinCostYen  = 500,
    SpinCostGem  = 30,

    -- Pity system: guaranteed Legendary+ after N spins
    PityThreshold = 90,
}

-- ─────────────────────────────────────────────────────────────
-- STYLE PROFILES  (multiply base physics constants)
-- ─────────────────────────────────────────────────────────────
GameConstants.Styles = {
    -- Common tier
    Rookie = {
        rarity = "Common", level = 1,
        JumpMult  = 1.0, SpeedMult = 1.0, SpikeMult = 1.0, BlockMult = 1.0,
        Ability   = "None",
    },
    -- Rare tier
    Ace = {
        rarity = "Rare", level = 5,
        JumpMult  = 1.15, SpeedMult = 1.10, SpikeMult = 1.20, BlockMult = 1.00,
        Ability   = "BoomJump",
        AbilityDuration = 4.0,
    },
    -- Legendary tier
    Phantom = {
        rarity = "Legendary", level = 10,
        JumpMult  = 1.35, SpeedMult = 1.25, SpikeMult = 1.45, BlockMult = 1.15,
        Ability   = "MagneticPull",
        AbilityDuration = 5.0,
        TrailColor = Color3.fromRGB(255, 200, 0),  -- radiant gold
    },
    -- Godly tier
    Nexus = {
        rarity = "Godly", level = 25,
        JumpMult  = 1.60, SpeedMult = 1.40, SpikeMult = 1.70, BlockMult = 1.35,
        Ability   = "SteelBlock",
        AbilityDuration = 6.0,
        TrailColor = Color3.fromRGB(160, 32, 240),  -- electric purple
    },
    -- Secret tier
    Void = {
        rarity = "Secret", level = 50,
        JumpMult  = 2.00, SpeedMult = 1.65, SpikeMult = 2.20, BlockMult = 1.80,
        Ability   = "ShieldBreaker",
        AbilityDuration = 7.0,
        TrailColor = Color3.fromRGB(255, 60, 20),   -- fiery red
    },
}

-- ─────────────────────────────────────────────────────────────
-- ENERGY / ABILITY METER
-- ─────────────────────────────────────────────────────────────
GameConstants.Ability = {
    MaxEnergy      = 100,
    GainPerBump    = 12,
    GainPerSet     = 8,
    GainPerSpike   = 20,
    GainPerPerfect = 5,   -- bonus on PERFECT hit
    AbilityKey     = Enum.KeyCode.F,
}

-- ─────────────────────────────────────────────────────────────
-- VISUAL / CAMERA
-- ─────────────────────────────────────────────────────────────
GameConstants.Camera = {
    -- Shiftlock offset from character root
    ShiftlockOffset  = Vector3.new(1.8, 1.6, -4.5),

    -- Orbital camera limits
    OrbitalMinY      = 10,    -- degrees from horizon
    OrbitalMaxY      = 80,
    OrbitalDistance  = 18,

    -- Screen shake on spike land
    ShakeMagnitude   = 0.6,
    ShakeFreq        = 18,    -- Hz
    ShakeDecay       = 0.85,  -- exponential decay per cycle

    -- Motion blur velocity threshold (studs/s)
    MotionBlurThresh = 40,
    MotionBlurMaxLen = 0.08,  -- seconds of blur length

    InterpolationHz  = 60,
}

-- ─────────────────────────────────────────────────────────────
-- FLOOR SHADOW INDICATOR
-- ─────────────────────────────────────────────────────────────
GameConstants.Shadow = {
    MaxRadius    = 3.0,   -- studs, when ball is at apex
    MinRadius    = 0.25,  -- studs, at impact
    MaxAltitude  = 20,    -- Y at which ring is fully expanded
    MaxAlpha     = 0.85,
    MinAlpha     = 0.20,
    RaycastDown  = -50,   -- Y direction of floor raycast
}

-- ─────────────────────────────────────────────────────────────
-- PARTICLE EFFECT CONFIGS
-- ─────────────────────────────────────────────────────────────
GameConstants.Particles = {
    ImpactDebrisCount     = 28,
    ImpactDebrisLifetime  = 0.60,
    ImpactRingRadius      = 3.0,
    ScreenFlashDuration   = 0.25,
    TrailSegmentLength    = 0.12,  -- seconds per trail segment
    ParticlePoolSize      = 64,    -- max live particles per emitter
}

-- ─────────────────────────────────────────────────────────────
-- REWARD FORMULA
-- Yen reward = (SpikesLanded * 10) + (Blocks * 15) + (PerfectReceives * 8) + BaseWin
-- ─────────────────────────────────────────────────────────────
GameConstants.Rewards = {
    BaseWin           = 150,
    BaseLoss          = 30,
    PerSpike          = 10,
    PerBlock          = 15,
    PerPerfectReceive = 8,
}

-- ─────────────────────────────────────────────────────────────
-- DATASTORE KEYS
-- ─────────────────────────────────────────────────────────────
GameConstants.DataStore = {
    ProfileStore = "PlayerProfiles_v1",
    MutexTimeout = 30,   -- seconds before a stuck mutex is released
}

return GameConstants
