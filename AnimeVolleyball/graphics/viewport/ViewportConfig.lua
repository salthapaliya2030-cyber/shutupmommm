-- ============================================================
-- ViewportConfig.lua  |  graphics/viewport/
-- Visual ring, viewport, and mesh configuration registry.
-- Defines specular multipliers, cel-shade parameters,
-- model LOD settings, and shadow quality per asset type.
-- Read by GraphicsEngine during initialization.
-- ============================================================

local ViewportConfig = {}

-- ─────────────────────────────────────────────────────────────
-- RENDER QUALITY TIERS
-- ─────────────────────────────────────────────────────────────
ViewportConfig.QualityTiers = {
    Ultra = {
        ShadowQuality    = 4,
        ParticleCount    = 64,
        TrailSegments    = 24,
        ReflectionQuality = 2,
        MotionBlurEnabled = true,
        DepthOfField      = true,
        BloomEnabled      = true,
    },
    High = {
        ShadowQuality    = 3,
        ParticleCount    = 48,
        TrailSegments    = 16,
        ReflectionQuality = 1,
        MotionBlurEnabled = true,
        DepthOfField      = false,
        BloomEnabled      = true,
    },
    Medium = {
        ShadowQuality    = 2,
        ParticleCount    = 24,
        TrailSegments    = 8,
        ReflectionQuality = 0,
        MotionBlurEnabled = false,
        DepthOfField      = false,
        BloomEnabled      = true,
    },
    Low = {
        ShadowQuality    = 1,
        ParticleCount    = 12,
        TrailSegments    = 4,
        ReflectionQuality = 0,
        MotionBlurEnabled = false,
        DepthOfField      = false,
        BloomEnabled      = false,
    },
}

-- Auto-detect quality tier based on platform
function ViewportConfig.detectQualityTier()
    local platform = game:GetService("UserInputService").TouchEnabled
    if platform then
        return ViewportConfig.QualityTiers.Medium  -- mobile default
    end
    return ViewportConfig.QualityTiers.Ultra  -- PC default
end

-- ─────────────────────────────────────────────────────────────
-- SPECULAR RING CONFIGURATIONS
-- These visual rings appear around the ball and key parts
-- to reinforce the polished anime aesthetic.
-- ─────────────────────────────────────────────────────────────
ViewportConfig.SpecularRings = {
    Ball = {
        Enabled       = true,
        Radius        = 0.6,    -- studs (slightly outside ball surface)
        Thickness     = 0.04,
        Color         = Color3.fromRGB(255, 255, 255),
        Transparency  = 0.7,
        RotationSpeed = 45,     -- degrees/second
        PulseOnHit    = true,   -- briefly brightens on ball contact
        PulseIntensity = 0.2,
        PulseDuration = 0.15,
    },

    CharacterAura = {
        Enabled       = true,
        Radius        = 1.4,
        Thickness     = 0.06,
        Color         = Color3.fromRGB(255, 255, 255),
        Transparency  = 0.85,
        RotationSpeed = 20,
        -- Color overridden per style (from StyleProfiles.AuraColor)
    },

    AbilityActive = {
        Enabled       = true,
        Radius        = 1.8,
        Thickness     = 0.10,
        Color         = Color3.fromRGB(255, 200, 80),
        Transparency  = 0.5,
        RotationSpeed = 90,     -- spins fast during ability
        PulseEnabled  = true,
        PulseSpeed    = 3,      -- Hz
    },
}

-- ─────────────────────────────────────────────────────────────
-- MESH MODEL SPECS
-- Describes geometry parameters for each asset type
-- ─────────────────────────────────────────────────────────────
ViewportConfig.MeshSpecs = {
    Volleyball = {
        MeshType      = "Sphere",
        Diameter      = 1.0,       -- studs
        PolyCount     = "Auto",    -- Roblox handles sphere LOD
        Reflectance   = 0.12,
        SpecularMult  = 1.4,
        BevelEnabled  = false,     -- sphere needs no bevel
        SurfaceType   = "SmoothPlastic",
    },

    CharacterLimb = {
        BevelRadius   = 0.08,      -- 8% corner rounding
        SmoothAngle   = 35,        -- degrees; edges below this angle are smoothed
        SkinThickness = 0.04,      -- mesh skin deformation thickness at joints
        JointBlendRadius = 0.4,    -- vertex weight blend zone at joints
    },

    CourtFloor = {
        Reflectance   = 0.35,
        SpecularMult  = 1.8,
        TextureTileX  = 4,         -- how many times to tile texture across floor
        TextureTileZ  = 8,
        GlossEnabled  = true,
    },

    NetMesh = {
        Transparency  = 0.35,
        EmissiveEnabled = false,
        LineWidth     = 0.05,      -- visual grid line width on net texture
        GridColor     = Color3.fromRGB(200, 200, 200),
    },
}

-- ─────────────────────────────────────────────────────────────
-- CEL-SHADING PARAMETERS
-- ─────────────────────────────────────────────────────────────
ViewportConfig.CelShading = {
    OutlineThickness     = 0.04,   -- studs (inverted-hull expansion)
    OutlineColor         = Color3.fromRGB(0, 0, 0),
    OutlineTransparency  = 0.0,
    OutlineOnlyOnOpaque  = true,   -- don't outline transparent parts (net)
    ShadingSteps         = 3,      -- quantize lighting to 3 bands for anime look

    -- Shadow band thresholds (light intensity → quantized shade)
    ShadingBands = {
        { threshold = 0.25, shade = 0.15 },  -- darkest (shadow)
        { threshold = 0.60, shade = 0.55 },  -- mid-tone
        { threshold = 1.00, shade = 1.00 },  -- highlight
    },

    -- Rim light (bright edge on character facing away from camera)
    RimLightEnabled   = true,
    RimLightColor     = Color3.fromRGB(200, 220, 255),
    RimLightIntensity = 0.4,
    RimLightWidth     = 0.18,     -- fraction of silhouette edge
}

-- ─────────────────────────────────────────────────────────────
-- ALPHA INTERPOLATION SETTINGS
-- Controls smoothness of all camera, joint, and object transitions
-- ─────────────────────────────────────────────────────────────
ViewportConfig.Interpolation = {
    CameraHz          = 60,    -- alpha-blending runs at this frequency
    JointBlendSpeed   = 10,    -- studs/s blend factor for Motor6D lerps
    ObjectTweenStyle  = Enum.EasingStyle.Cubic,
    ObjectTweenDir    = Enum.EasingDirection.Out,
    PositionLerpAlpha = 0.18,  -- per-frame lerp alpha for smooth object tracking
    RotationLerpAlpha = 0.14,
}

-- ─────────────────────────────────────────────────────────────
-- SHADOW INDICATOR RING VISUAL PARAMS
-- (complements GameConstants.Shadow with rendering details)
-- ─────────────────────────────────────────────────────────────
ViewportConfig.ShadowRing = {
    MeshType      = "Cylinder",
    HeightScale   = 0.05,          -- very flat
    Color         = Color3.fromRGB(255, 255, 255),
    NeonEnabled   = true,
    MaxTransparency = 0.80,        -- at high altitude
    MinTransparency = 0.15,        -- at impact
}

-- ─────────────────────────────────────────────────────────────
-- POST-PROCESSING STACK ORDER
-- Applied bottom to top
-- ─────────────────────────────────────────────────────────────
ViewportConfig.PostProcessingStack = {
    { effect = "BloomEffect",          priority = 1 },
    { effect = "ColorCorrectionEffect", priority = 2 },
    { effect = "DepthOfFieldEffect",   priority = 3 },
    { effect = "SunRaysEffect",        priority = 4 },
    -- Motion blur is handled via script overlay (not a Lighting effect)
}

return ViewportConfig
