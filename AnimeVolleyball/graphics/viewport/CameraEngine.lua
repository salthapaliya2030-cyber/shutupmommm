-- ============================================================
-- CameraEngine.lua  |  graphics/viewport/
-- Client-side camera controller.
-- Two modes: Orbital (free-roam) and Shiftlock (over-shoulder).
-- Alpha-blending interpolation at 60 Hz.
-- Cinematic tween for match setup court view.
-- ============================================================

local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local GameConstants    = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes          = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)

local CameraEngine = {}

local camera           = workspace.CurrentCamera
local player           = game.Players.LocalPlayer
local character        = nil
local rootPart         = nil

-- ─────────────────────────────────────────────────────────────
-- MODE STATE
-- ─────────────────────────────────────────────────────────────
local Mode = { ORBITAL = "ORBITAL", SHIFTLOCK = "SHIFTLOCK", CINEMATIC = "CINEMATIC" }
local currentMode = Mode.ORBITAL

-- Orbital angles
local orbitalYaw   = 0
local orbitalPitch = 30   -- degrees
local orbitalDist  = GameConstants.Camera.OrbitalDistance

-- Shiftlock
local slYaw   = 0
local slPitch = 0
local slOffset = GameConstants.Camera.ShiftlockOffset

-- Current interpolated camera CFrame
local targetCF  = CFrame.new()
local currentCF = CFrame.new()

-- Input flags
local rightMouseHeld = false

-- ─────────────────────────────────────────────────────────────
-- INIT
-- ─────────────────────────────────────────────────────────────
function CameraEngine.init()
    camera.CameraType = Enum.CameraType.Scriptable

    -- Character reference (refreshed on respawn)
    player.CharacterAdded:Connect(function(char)
        character = char
        rootPart  = char:WaitForChild("HumanoidRootPart")
    end)

    if player.Character then
        character = player.Character
        rootPart  = character:FindFirstChild("HumanoidRootPart")
    end

    -- Mouse input
    UserInputService.InputBegan:Connect(CameraEngine._onInputBegan)
    UserInputService.InputEnded:Connect(CameraEngine._onInputEnded)
    UserInputService.InputChanged:Connect(CameraEngine._onInputChanged)

    -- Main update loop
    RunService.RenderStepped:Connect(CameraEngine._update)

    -- Match setup cinematic trigger
    Remotes.Events.ShowMatchSetupPrompt.OnClientEvent:Connect(function()
        CameraEngine._enterCinematic()
    end)
    Remotes.Events.TransitionToMatch.OnClientEvent:Connect(function()
        CameraEngine._exitCinematic()
    end)
    Remotes.Events.TransitionToLobby.OnClientEvent:Connect(function()
        CameraEngine.setMode(Mode.ORBITAL)
    end)

    print("[CameraEngine] Initialized.")
end

-- ─────────────────────────────────────────────────────────────
-- MODE SWITCH
-- ─────────────────────────────────────────────────────────────
function CameraEngine.setMode(mode)
    currentMode = mode

    if mode == Mode.SHIFTLOCK then
        -- Lock and hide cursor
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        UserInputService.MouseIconEnabled = false
    else
        -- Unlock cursor
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
    end
end

-- ─────────────────────────────────────────────────────────────
-- INPUT HANDLERS
-- ─────────────────────────────────────────────────────────────
function CameraEngine._onInputBegan(input, gameProcessed)
    if gameProcessed then return end

    -- Shiftlock toggle
    if input.KeyCode == Enum.KeyCode.LeftShift then
        if currentMode == Mode.SHIFTLOCK then
            CameraEngine.setMode(Mode.ORBITAL)
        else
            CameraEngine.setMode(Mode.SHIFTLOCK)
        end
    end

    -- Right mouse: begin orbital rotation
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        rightMouseHeld = true
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
    end
end

function CameraEngine._onInputEnded(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        rightMouseHeld = false
        if currentMode ~= Mode.SHIFTLOCK then
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end
    end
end

function CameraEngine._onInputChanged(input, gameProcessed)
    if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    if currentMode == Mode.CINEMATIC then return end

    local delta = input.Delta

    if currentMode == Mode.ORBITAL and rightMouseHeld then
        -- Orbital rotation
        orbitalYaw   = orbitalYaw   - delta.X * 0.35
        orbitalPitch = math.clamp(
            orbitalPitch - delta.Y * 0.30,
            GameConstants.Camera.OrbitalMinY,
            GameConstants.Camera.OrbitalMaxY
        )

    elseif currentMode == Mode.SHIFTLOCK then
        -- Shiftlock: mouse directly rotates character + camera
        slYaw   = slYaw   - delta.X * 0.30
        slPitch = math.clamp(slPitch - delta.Y * 0.25, -70, 70)

        -- Rotate character body
        if rootPart then
            rootPart.CFrame = CFrame.new(rootPart.Position)
                * CFrame.Angles(0, math.rad(slYaw), 0)
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- PER-FRAME UPDATE
-- ─────────────────────────────────────────────────────────────
function CameraEngine._update(dt)
    if not rootPart then return end

    local rootPos = rootPart.Position

    if currentMode == Mode.ORBITAL then
        -- Spherical orbit around root
        local yawRad   = math.rad(orbitalYaw)
        local pitchRad = math.rad(orbitalPitch)

        local offset   = Vector3.new(
            math.sin(yawRad) * math.cos(pitchRad),
            math.sin(pitchRad),
            math.cos(yawRad) * math.cos(pitchRad)
        ) * orbitalDist

        targetCF = CFrame.lookAt(rootPos + offset, rootPos)

    elseif currentMode == Mode.SHIFTLOCK then
        -- Over-the-shoulder
        local yawRad   = math.rad(slYaw)
        local pitchRad = math.rad(slPitch)

        local lookDir  = Vector3.new(
            math.sin(yawRad) * math.cos(pitchRad),
            math.sin(pitchRad),
            math.cos(yawRad) * math.cos(pitchRad)
        )

        local camPos   = rootPos
            + slOffset.X * rootPart.CFrame.RightVector
            + Vector3.new(0, slOffset.Y, 0)

        targetCF = CFrame.lookAt(camPos, camPos + lookDir)

    elseif currentMode == Mode.CINEMATIC then
        return  -- controlled by tween
    end

    -- Alpha-blending interpolation (smooth damp)
    local alpha  = math.clamp(dt * GameConstants.Camera.InterpolationHz, 0, 1)
    currentCF    = currentCF:Lerp(targetCF, alpha)
    camera.CFrame = currentCF
end

-- ─────────────────────────────────────────────────────────────
-- CINEMATIC TWEEN (match setup court view)
-- ─────────────────────────────────────────────────────────────
local cinematicTarget = CFrame.new(0, 12, 20) * CFrame.Angles(math.rad(-30), 0, 0)

function CameraEngine._enterCinematic()
    currentMode = Mode.CINEMATIC
    UserInputService.MouseBehavior   = Enum.MouseBehavior.Default
    UserInputService.MouseIconEnabled = false   -- UI uses its own cursor

    TweenService:Create(camera,
        TweenInfo.new(1.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        { CFrame = cinematicTarget }
    ):Play()
end

function CameraEngine._exitCinematic()
    -- Snap back to shiftlock
    CameraEngine.setMode(Mode.SHIFTLOCK)
    currentCF = camera.CFrame  -- prevent lerp jump
end

-- ─────────────────────────────────────────────────────────────
-- LOOK VECTOR ACCESSOR (used by server spike calculation)
-- ─────────────────────────────────────────────────────────────
function CameraEngine.getLookVector()
    return camera.CFrame.LookVector
end

return CameraEngine
