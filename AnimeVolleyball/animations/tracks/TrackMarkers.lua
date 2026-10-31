-- ============================================================
-- TrackMarkers.lua  |  animations/tracks/
-- Explicit timeline marker definitions for every animation track.
-- These MUST be embedded in each Roblox Animation asset as
-- KeyframeMarker events at the listed time values.
-- Reference this when building animations in the Roblox
-- Animation Editor plugin.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- HOW TO USE:
-- 1. Open Animation Editor in Roblox Studio
-- 2. For each animation listed below, add keyframe markers at
--    the exact timestamps using the "Add Event" button
-- 3. Name each event exactly as listed in the "name" field
-- 4. The AnimationEngine uses GetMarkerReachedSignal() to hook
--    gameplay logic to these exact frames
-- ─────────────────────────────────────────────────────────────

local TrackMarkers = {}

TrackMarkers.Spike = {
    -- Phase 1: Arm pulls back, weight shifts to rear foot
    { name = "WindupStart",    time = 0.00, description = "Begin windup: right arm swings back, torso rotates" },
    -- Phase 2: Full extension behind head
    { name = "WindupEnd",      time = 0.30, description = "Arm fully cocked; elbow at max retraction" },
    -- Phase 3: CONTACT – server registers ball hit HERE and only here
    { name = "ContactFrame",   time = 0.42, description = "Hand at peak vertical extension; HITBOX CHECK" },
    -- Phase 4: Follow-through
    { name = "FollowThrough",  time = 0.72, description = "Arm sweeps through; body momentum carries forward" },
    -- Track ends
    trackLength = 1.00,

    -- Joint keyframes for the animator:
    keyframes = {
        [0.00] = { RightShoulder = { rx = 0,    ry = 0, rz = 0   }, Waist = { rx = 0,  ry = 0,  rz = 0 } },
        [0.15] = { RightShoulder = { rx = -100, ry = 0, rz = -15 }, Waist = { rx = -8, ry = 25, rz = 0 } },
        [0.30] = { RightShoulder = { rx = -150, ry = 0, rz = -20 }, Waist = { rx = -10, ry = 30, rz = 0} },
        [0.42] = { RightShoulder = { rx = 30,   ry = 0, rz = 10  }, Waist = { rx = 5,  ry = -15, rz = 0} },  -- CONTACT
        [0.72] = { RightShoulder = { rx = -20,  ry = 0, rz = 5   }, Waist = { rx = 2,  ry = -5,  rz = 0} },
        [1.00] = { RightShoulder = { rx = 0,    ry = 0, rz = 0   }, Waist = { rx = 0,  ry = 0,  rz = 0 } },
    }
}

TrackMarkers.Set = {
    { name = "WindupStart",  time = 0.00, description = "Both hands rise in front of face" },
    { name = "ContactFrame", time = 0.25, description = "Fingertips at peak; HITBOX CHECK" },
    trackLength = 0.55,

    keyframes = {
        [0.00] = { RightShoulder = { rx = 0, ry = 0, rz = 0 },    LeftShoulder = { rx = 0, ry = 0, rz = 0 } },
        [0.12] = { RightShoulder = { rx = -60, ry = 0, rz = -10 }, LeftShoulder = { rx = -60, ry = 0, rz = 10 } },
        [0.25] = { RightShoulder = { rx = -80, ry = 0, rz = -15 }, LeftShoulder = { rx = -80, ry = 0, rz = 15 } }, -- CONTACT
        [0.55] = { RightShoulder = { rx = 0, ry = 0, rz = 0 },    LeftShoulder = { rx = 0, ry = 0, rz = 0 } },
    }
}

TrackMarkers.Bump = {
    { name = "WindupStart",  time = 0.00, description = "Arms extend low and forward, body lowers" },
    { name = "ContactFrame", time = 0.20, description = "Forearms horizontal; HITBOX CHECK" },
    trackLength = 0.50,

    keyframes = {
        [0.00] = { RightShoulder = { rx = 0,   ry = 0, rz = 0   }, LeftShoulder = { rx = 0,   ry = 0, rz = 0  } },
        [0.10] = { RightShoulder = { rx = -30, ry = 0, rz = -25 }, LeftShoulder = { rx = -30, ry = 0, rz = 25 } },
        [0.20] = { RightShoulder = { rx = -45, ry = 0, rz = -30 }, LeftShoulder = { rx = -45, ry = 0, rz = 30 } }, -- CONTACT
        [0.50] = { RightShoulder = { rx = 0,   ry = 0, rz = 0   }, LeftShoulder = { rx = 0,   ry = 0, rz = 0  } },
    }
}

TrackMarkers.Serve = {
    { name = "TossFrame",        time = 0.30, description = "Ball released vertically from hand" },
    { name = "InputWindowOpen",  time = 0.55, description = "Client power window opens" },
    { name = "ContactFrame",     time = 0.70, description = "Optimal hit frame; center of power window" },
    { name = "InputWindowClose", time = 0.80, description = "Power window closes" },
    trackLength = 1.10,

    keyframes = {
        [0.00] = { RightShoulder = { rx = 0,    ry = 0, rz = 0   } },
        [0.30] = { RightShoulder = { rx = -30,  ry = 0, rz = -10 } },  -- TOSS
        [0.55] = { RightShoulder = { rx = -130, ry = 0, rz = -18 } },  -- Window open
        [0.70] = { RightShoulder = { rx = 35,   ry = 0, rz = 12  } },  -- CONTACT
        [1.10] = { RightShoulder = { rx = 0,    ry = 0, rz = 0   } },
    }
}

TrackMarkers.Dive = {
    { name = "ContactFrame",  time = 0.18, description = "Body fully extended horizontal; optional bump hit" },
    { name = "RecoverStart",  time = 0.50, description = "Push up begins" },
    { name = "RecoverEnd",    time = 1.40, description = "Character back to standing; UNLOCK inputs" },
    trackLength = 1.60,

    keyframes = {
        [0.00] = { Waist = { rx = 0,   ry = 0, rz = 0 } },
        [0.10] = { Waist = { rx = -35, ry = 0, rz = 0 } },
        [0.18] = { Waist = { rx = -55, ry = 0, rz = 0 } }, -- CONTACT
        [0.50] = { Waist = { rx = -30, ry = 0, rz = 0 } },
        [1.40] = { Waist = { rx = 0,   ry = 0, rz = 0 } }, -- RECOVER
    }
}

TrackMarkers.Stun = {
    -- No ContactFrame marker; stun is purely visual
    trackLength = 1.20,
    description = "Character drops to one knee; inputs locked for full duration",

    keyframes = {
        [0.00] = { RightHip  = { rx = 0,  ry = 0, rz = 0 }, RightKnee = { rx = 0,   ry = 0, rz = 0 } },
        [0.15] = { RightHip  = { rx = 80, ry = 0, rz = 0 }, RightKnee = { rx = -80, ry = 0, rz = 0 } },
        [1.05] = { RightHip  = { rx = 80, ry = 0, rz = 0 }, RightKnee = { rx = -80, ry = 0, rz = 0 } },
        [1.20] = { RightHip  = { rx = 0,  ry = 0, rz = 0 }, RightKnee = { rx = 0,   ry = 0, rz = 0 } },
    }
}

TrackMarkers.Idle = {
    trackLength = 2.00,
    description = "Gentle weight-shift idle loop; looped at 2.0s",
}

TrackMarkers.Run = {
    trackLength = 0.60,
    description = "Full run cycle with forward lean; looped at 0.6s",
}

-- ─────────────────────────────────────────────────────────────
-- MARKER EMBEDDING INSTRUCTIONS
-- ─────────────────────────────────────────────────────────────
TrackMarkers.Instructions = [[
To embed these markers in the Roblox Animation Editor:
1. Open the Keyframe Sequence in the Animation Editor.
2. Right-click on the timeline at the exact time value.
3. Select "Add Event" from the context menu.
4. Set the "Function Name" to exactly the value in the "name" field.
5. Do NOT add any parameters; the server uses GetMarkerReachedSignal(name).
6. For "ContactFrame": this is the MOST CRITICAL marker. The server checks
   ball hitbox intersection ONLY on this event firing. Off by even one frame
   means the player misses or triggers a stun.
7. Export animations and upload to Roblox; paste returned Asset IDs into
   ANIM_IDS table in AnimationEngine.lua.
]]

return TrackMarkers
