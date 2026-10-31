-- ============================================================
-- BoneData.lua  |  animations/bones/
-- Character skeleton definition.
-- Defines joint hierarchy, default C0/C1 offsets, and the
-- bind pose CFrames used by the AnimationEngine and IK system.
-- ============================================================

local BoneData = {}

-- ─────────────────────────────────────────────────────────────
-- JOINT HIERARCHY
-- parent → { children }
-- ─────────────────────────────────────────────────────────────
BoneData.Hierarchy = {
    ["HumanoidRootPart"] = {
        ["LowerTorso"]  = {
            ["UpperTorso"] = {
                ["Head"]          = {},
                ["LeftUpperArm"]  = {
                    ["LeftLowerArm"] = {
                        ["LeftHand"] = {}
                    }
                },
                ["RightUpperArm"] = {
                    ["RightLowerArm"] = {
                        ["RightHand"] = {}
                    }
                },
            },
            ["LeftUpperLeg"] = {
                ["LeftLowerLeg"] = {
                    ["LeftFoot"] = {}
                }
            },
            ["RightUpperLeg"] = {
                ["RightLowerLeg"] = {
                    ["RightFoot"] = {}
                }
            },
        }
    }
}

-- ─────────────────────────────────────────────────────────────
-- BIND POSE OFFSETS
-- C0 = joint offset from parent in bind pose
-- These are ADDED TO, not replaced by, animation track offsets
-- ─────────────────────────────────────────────────────────────
BoneData.BindPose = {
    -- Root → LowerTorso
    Root = CFrame.new(0, 0, 0),

    -- Waist (LowerTorso → UpperTorso)
    Waist = CFrame.new(0, 0.2, 0),

    -- Neck (UpperTorso → Head)
    Neck  = CFrame.new(0, 1.5, 0),

    -- Right shoulder
    RightShoulder = CFrame.new(1.5, 1.0, 0)
        * CFrame.Angles(0, 0, math.rad(-5)),

    -- Left shoulder
    LeftShoulder  = CFrame.new(-1.5, 1.0, 0)
        * CFrame.Angles(0, 0, math.rad(5)),

    -- Right elbow
    RightElbow    = CFrame.new(0, -1.3, 0),

    -- Left elbow
    LeftElbow     = CFrame.new(0, -1.3, 0),

    -- Right hip
    RightHip      = CFrame.new(0.5, -1.0, 0),

    -- Left hip
    LeftHip       = CFrame.new(-0.5, -1.0, 0),

    -- Right knee
    RightKnee     = CFrame.new(0, -1.5, 0),

    -- Left knee
    LeftKnee      = CFrame.new(0, -1.5, 0),
}

-- ─────────────────────────────────────────────────────────────
-- KEY POSE OFFSETS  (applied over bind pose during animations)
-- ─────────────────────────────────────────────────────────────
BoneData.Poses = {
    -- Spike windup: right arm raised, waist rotated
    SpikeWindup = {
        RightShoulder = CFrame.Angles(math.rad(-150), 0, math.rad(-20)),
        RightElbow    = CFrame.Angles(math.rad(-30), 0, 0),
        Waist         = CFrame.Angles(math.rad(-10), math.rad(30), 0),
    },

    -- Spike contact: arm at full extension overhead
    SpikeContact = {
        RightShoulder = CFrame.Angles(math.rad(30), 0, math.rad(10)),
        RightElbow    = CFrame.Angles(math.rad(15), 0, 0),
        Waist         = CFrame.Angles(math.rad(5), math.rad(-15), 0),
    },

    -- Set: both hands raised in front, slight waist forward lean
    SetContact = {
        RightShoulder = CFrame.Angles(math.rad(-80), 0, math.rad(-15)),
        LeftShoulder  = CFrame.Angles(math.rad(-80), 0, math.rad(15)),
        RightElbow    = CFrame.Angles(math.rad(-20), 0, 0),
        LeftElbow     = CFrame.Angles(math.rad(-20), 0, 0),
        Waist         = CFrame.Angles(math.rad(-5), 0, 0),
    },

    -- Bump: forearms horizontal, body low
    BumpContact = {
        RightShoulder = CFrame.Angles(math.rad(-45), 0, math.rad(-30)),
        LeftShoulder  = CFrame.Angles(math.rad(-45), 0, math.rad(30)),
        RightElbow    = CFrame.Angles(0, 0, math.rad(-40)),
        LeftElbow     = CFrame.Angles(0, 0, math.rad(40)),
        Waist         = CFrame.Angles(math.rad(-15), 0, 0),
        RightHip      = CFrame.Angles(math.rad(20), 0, 0),
        LeftHip       = CFrame.Angles(math.rad(20), 0, 0),
    },

    -- Dive: full body horizontal, arms forward
    Dive = {
        Waist         = CFrame.Angles(math.rad(-55), 0, 0),
        RightShoulder = CFrame.Angles(math.rad(-100), 0, 0),
        LeftShoulder  = CFrame.Angles(math.rad(-100), 0, 0),
        RightHip      = CFrame.Angles(math.rad(-10), 0, 0),
        LeftHip       = CFrame.Angles(math.rad(-10), 0, 0),
        RightKnee     = CFrame.Angles(math.rad(15), 0, 0),
        LeftKnee      = CFrame.Angles(math.rad(15), 0, 0),
    },

    -- Stun: drop to one knee
    Stun = {
        Waist         = CFrame.Angles(math.rad(-20), 0, 0),
        RightHip      = CFrame.Angles(math.rad(80), 0, 0),
        RightKnee     = CFrame.Angles(math.rad(-80), 0, 0),
        LeftHip       = CFrame.Angles(math.rad(-10), 0, 0),
    },
}

-- ─────────────────────────────────────────────────────────────
-- ANIMATION TRACK TIMELINE MARKERS
-- These must be embedded in each Roblox Animation asset as
-- KeyframeMarkers named "ContactFrame" at the listed timestamps.
-- ─────────────────────────────────────────────────────────────
BoneData.TrackMarkers = {
    Spike = {
        { name = "WindupStart",    time = GameConstants and GameConstants.AnimMarkers.Spike.WindupStart   or 0.00 },
        { name = "WindupEnd",      time = GameConstants and GameConstants.AnimMarkers.Spike.WindupEnd     or 0.30 },
        { name = "ContactFrame",   time = GameConstants and GameConstants.AnimMarkers.Spike.ContactFrame  or 0.42 },
        { name = "FollowThrough",  time = GameConstants and GameConstants.AnimMarkers.Spike.FollowThrough or 0.72 },
    },
    Set = {
        { name = "ContactFrame",   time = 0.25 },
    },
    Bump = {
        { name = "ContactFrame",   time = 0.20 },
    },
    Serve = {
        { name = "TossFrame",      time = 0.30 },
        { name = "InputWindowOpen",  time = 0.55 },
        { name = "ContactFrame",   time = 0.70 },
        { name = "InputWindowClose", time = 0.80 },
    },
    Dive = {
        { name = "ContactFrame",   time = 0.18 },
        { name = "RecoverStart",   time = 0.50 },
        { name = "RecoverEnd",     time = 1.40 },
    },
}

-- ─────────────────────────────────────────────────────────────
-- MESH SKIN DATA
-- Describes vertex group assignments for smooth deformation.
-- Used by the edge-beveling and skin mesh scripts.
-- ─────────────────────────────────────────────────────────────
BoneData.SkinGroups = {
    -- Weight maps: [boneGroup] = { partNames, blendRadius }
    { bones = { "RightUpperArm", "RightLowerArm" },
      parts = { "RightUpperArm", "RightLowerArm" },
      blendRadius = 0.4 },

    { bones = { "LeftUpperArm", "LeftLowerArm" },
      parts = { "LeftUpperArm", "LeftLowerArm" },
      blendRadius = 0.4 },

    { bones = { "RightUpperLeg", "RightLowerLeg" },
      parts = { "RightUpperLeg", "RightLowerLeg" },
      blendRadius = 0.4 },

    { bones = { "LeftUpperLeg", "LeftLowerLeg" },
      parts = { "LeftUpperLeg", "LeftLowerLeg" },
      blendRadius = 0.4 },

    { bones = { "LowerTorso", "UpperTorso" },
      parts = { "LowerTorso", "UpperTorso" },
      blendRadius = 0.35 },
}

return BoneData
