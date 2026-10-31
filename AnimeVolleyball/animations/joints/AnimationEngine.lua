-- ============================================================
-- AnimationEngine.lua  |  animations/joints/
-- Client-side animation engine.
-- Manages Motor6D joint offsets, animation track playback,
-- smooth joint blending, and velocity-driven silhouette stretch.
-- ============================================================

local RunService    = game:GetService("RunService")
local GameConstants = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes       = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)

-- ─────────────────────────────────────────────────────────────
-- ANIMATION TRACK DEFINITIONS
-- Key = animation name, value = Roblox Animation asset ID
-- Replace asset IDs with your actual uploaded animation IDs.
-- ─────────────────────────────────────────────────────────────
local ANIM_IDS = {
    Idle            = "rbxassetid://11111111",
    Run             = "rbxassetid://22222222",
    Jump            = "rbxassetid://33333333",
    Land            = "rbxassetid://44444444",
    Spike           = "rbxassetid://55555555",
    Set             = "rbxassetid://66666666",
    Bump            = "rbxassetid://77777777",
    Dive            = "rbxassetid://88888888",
    Stun            = "rbxassetid://99999999",
    Recover         = "rbxassetid://10101010",
}

-- ─────────────────────────────────────────────────────────────
-- PER-CHARACTER ANIMATOR
-- ─────────────────────────────────────────────────────────────
local CharacterAnimator = {}
CharacterAnimator.__index = CharacterAnimator

function CharacterAnimator.new(character)
    local self = setmetatable({}, CharacterAnimator)

    self.character = character
    self.humanoid  = character:FindFirstChildOfClass("Humanoid")
    self.animator  = self.humanoid:FindFirstChildOfClass("Animator")
        or Instance.new("Animator", self.humanoid)

    self.root      = character:FindFirstChild("HumanoidRootPart")

    -- Motor6D joint references
    self.joints = {
        RightShoulder = character:FindFirstChild("RightUpperArm")
            and character.RightUpperArm:FindFirstChild("RightShoulder"),
        LeftShoulder  = character:FindFirstChild("LeftUpperArm")
            and character.LeftUpperArm:FindFirstChild("LeftShoulder"),
        RightHip      = character:FindFirstChild("RightUpperLeg")
            and character.RightUpperLeg:FindFirstChild("RightHip"),
        LeftHip       = character:FindFirstChild("LeftUpperLeg")
            and character.LeftUpperLeg:FindFirstChild("LeftHip"),
        Neck          = character:FindFirstChild("Head")
            and character.Head:FindFirstChild("Neck"),
        Waist         = character:FindFirstChild("UpperTorso")
            and character.UpperTorso:FindFirstChild("Waist"),
        RightElbow    = character:FindFirstChild("RightLowerArm")
            and character.RightLowerArm:FindFirstChild("RightElbow"),
        LeftElbow     = character:FindFirstChild("LeftLowerArm")
            and character.LeftLowerArm:FindFirstChild("LeftElbow"),
        RightKnee     = character:FindFirstChild("RightLowerLeg")
            and character.RightLowerLeg:FindFirstChild("RightKnee"),
        LeftKnee      = character:FindFirstChild("LeftLowerLeg")
            and character.LeftLowerLeg:FindFirstChild("LeftKnee"),
    }

    -- Track cache: animName → AnimationTrack
    self.tracks = {}
    self._preloadAnimations()

    -- Blend state for smooth joint transitions
    self.blendWeights = {}
    self.targetAngles = {}

    -- Velocity-driven silhouette stretch state
    self._prevRootCFrame = self.root.CFrame
    self._stretchConn    = nil
    self:_startStretchLoop()

    return self
end

-- ─────────────────────────────────────────────────────────────
-- PRELOAD ALL ANIMATIONS
-- ─────────────────────────────────────────────────────────────
function CharacterAnimator:_preloadAnimations()
    for name, id in pairs(ANIM_IDS) do
        local animObj    = Instance.new("Animation")
        animObj.AnimationId = id
        local track      = self.animator:LoadAnimation(animObj)
        track.Priority   = Enum.AnimationPriority.Action
        self.tracks[name] = track
    end
end

-- ─────────────────────────────────────────────────────────────
-- PLAY ANIMATION TRACK
-- contactFrameCallback fires at the contact frame timestamp
-- ─────────────────────────────────────────────────────────────
function CharacterAnimator:playTrack(name, contactFrameCallback)
    local track = self.tracks[name]
    if not track then
        warn("[AnimationEngine] Track not found: " .. name)
        return
    end

    -- Stop any conflicting action tracks
    for _, t in pairs(self.tracks) do
        if t.IsPlaying and t.Priority == Enum.AnimationPriority.Action then
            t:Stop(0.1)
        end
    end

    track:Play(0.1)

    -- Fire contact frame callback via timeline marker
    local markerSignal = track:GetMarkerReachedSignal("ContactFrame")
    local conn
    conn = markerSignal:Connect(function()
        if contactFrameCallback then
            contactFrameCallback()
        end
        conn:Disconnect()
    end)
end

-- ─────────────────────────────────────────────────────────────
-- STOP ALL TRACKS
-- ─────────────────────────────────────────────────────────────
function CharacterAnimator:stopAll(fadeTime)
    for _, track in pairs(self.tracks) do
        if track.IsPlaying then
            track:Stop(fadeTime or 0.15)
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- SMOOTH MOTOR6D JOINT INTERPOLATION
-- Directly manipulates C0 offsets on joints for custom IK poses
-- ─────────────────────────────────────────────────────────────
function CharacterAnimator:setJointTarget(jointName, targetCFrame, speed)
    local joint = self.joints[jointName]
    if not joint then return end

    speed = speed or 8  -- blend speed (studs/s equivalent)

    -- Store target; interpolation happens in update loop
    self.targetAngles[jointName] = targetCFrame
    if not self.blendWeights[jointName] then
        self.blendWeights[jointName] = 0
    end

    -- Start blend connection if not already running
    if not self._blendConn then
        self._blendConn = RunService.RenderStepped:Connect(function(dt)
            self:_updateJointBlends(dt, speed)
        end)
    end
end

function CharacterAnimator:_updateJointBlends(dt, speed)
    local anyActive = false
    for jointName, targetCF in pairs(self.targetAngles) do
        local joint = self.joints[jointName]
        if joint then
            anyActive = true
            local alpha = math.clamp(dt * speed, 0, 1)
            joint.C0 = joint.C0:Lerp(targetCF, alpha)
        end
    end
    if not anyActive and self._blendConn then
        self._blendConn:Disconnect()
        self._blendConn = nil
    end
end

-- ─────────────────────────────────────────────────────────────
-- VELOCITY-DRIVEN SILHOUETTE STRETCH
-- Elbow/knee joints dynamically blend and stretch at high speed
-- ─────────────────────────────────────────────────────────────
function CharacterAnimator:_startStretchLoop()
    self._stretchConn = RunService.RenderStepped:Connect(function(dt)
        if not self.root then return end

        local vel        = self.root.Velocity
        local speed      = vel.Magnitude

        -- Stretch factor: 0 at rest, 1 at high velocity
        local stretchFactor = math.clamp(speed / 60, 0, 1)

        if stretchFactor < 0.05 then return end

        -- Lean waist slightly forward in run direction
        if self.joints.Waist and speed > 8 then
            local leanAngle = stretchFactor * 0.22  -- radians
            local leanCF    = CFrame.Angles(-leanAngle, 0, 0)
            self.joints.Waist.C0 = self.joints.Waist.C0:Lerp(
                CFrame.new(0, 0, 0) * leanCF, dt * 10
            )
        end

        -- Knee stretch during jump (airborne)
        local rootY      = self.root.Position.Y
        local isAirborne = rootY > (GameConstants.Court.FloorY + 0.3)
        if isAirborne and self.joints.RightKnee and self.joints.LeftKnee then
            local kneeAngle = stretchFactor * 0.5
            local kneeCF    = CFrame.Angles(kneeAngle, 0, 0)
            self.joints.RightKnee.C0 = self.joints.RightKnee.C0:Lerp(
                CFrame.new(0,0,0) * kneeCF, dt * 12
            )
            self.joints.LeftKnee.C0 = self.joints.LeftKnee.C0:Lerp(
                CFrame.new(0,0,0) * kneeCF, dt * 12
            )
        end

        -- Elbow stretch during spike windup
        -- (driven by animation track, amplified here for high-velocity hits)
        if self.joints.RightElbow then
            local elbowCF = CFrame.Angles(stretchFactor * 0.3, 0, 0)
            self.joints.RightElbow.C0 = self.joints.RightElbow.C0:Lerp(
                CFrame.new(0,0,0) * elbowCF, dt * 8
            )
        end
    end)
end

function CharacterAnimator:destroy()
    if self._stretchConn then self._stretchConn:Disconnect() end
    if self._blendConn   then self._blendConn:Disconnect() end
    self:stopAll(0)
end

-- ─────────────────────────────────────────────────────────────
-- ANIMATION ENGINE MANAGER (client-side, manages all players)
-- ─────────────────────────────────────────────────────────────
local AnimationEngine = {}

local animators = {}  -- [playerID] → CharacterAnimator

-- Listen for server animation broadcast
Remotes.Events.PlayAnimation.OnClientEvent:Connect(function(payload)
    local animator = animators[payload.playerID]
    if animator then
        animator:playTrack(payload.animationName)
    end
end)

function AnimationEngine.registerCharacter(playerID, character)
    if animators[playerID] then
        animators[playerID]:destroy()
    end
    animators[playerID] = CharacterAnimator.new(character)
end

function AnimationEngine.unregisterCharacter(playerID)
    if animators[playerID] then
        animators[playerID]:destroy()
        animators[playerID] = nil
    end
end

function AnimationEngine.getAnimator(playerID)
    return animators[playerID]
end

return AnimationEngine
