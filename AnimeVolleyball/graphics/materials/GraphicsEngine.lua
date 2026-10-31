-- ============================================================
-- GraphicsEngine.lua  |  graphics/materials/
-- Client-side graphics initialization.
-- Applies: edge beveling, smooth mesh materials, specular floor,
-- satin character textures, cel-shading outline pass,
-- velocity-based motion blur, and alpha-blending interpolation.
-- ============================================================

local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")
local GameConstants     = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes           = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)

local GraphicsEngine = {}

-- ─────────────────────────────────────────────────────────────
-- LIGHTING ENVIRONMENT
-- ─────────────────────────────────────────────────────────────
function GraphicsEngine.initLighting()
    -- Stadium atmosphere
    Lighting.Ambient        = Color3.fromRGB(60, 70, 90)
    Lighting.OutdoorAmbient = Color3.fromRGB(40, 50, 70)
    Lighting.Brightness     = 3.2
    Lighting.ColorShift_Top = Color3.fromRGB(255, 245, 220)
    Lighting.ExposureCompensation = 0.3
    Lighting.GlobalShadows  = true
    Lighting.ShadowSoftness = 0.25

    -- Bloom post-processing
    local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
        or Instance.new("BloomEffect", Lighting)
    bloom.Intensity  = 0.6
    bloom.Size       = 24
    bloom.Threshold  = 0.8

    -- Slight color correction for anime palette
    local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
        or Instance.new("ColorCorrectionEffect", Lighting)
    cc.Saturation  = 0.18
    cc.Contrast    = 0.10
    cc.Brightness  = 0.04

    -- Depth of field (subtle; keeps court sharp, softens background)
    local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
        or Instance.new("DepthOfFieldEffect", Lighting)
    dof.FarIntensity  = 0.05
    dof.NearIntensity = 0.0
    dof.FocusDistance = 30
    dof.InFocusRadius = 25
end

-- ─────────────────────────────────────────────────────────────
-- EDGE BEVELING SCRIPT
-- Applied to all BasePart geometry in the environment folder
-- ─────────────────────────────────────────────────────────────
function GraphicsEngine.applyEdgeBeveling(parentFolder)
    for _, desc in ipairs(parentFolder:GetDescendants()) do
        if desc:IsA("BasePart") and not desc:IsA("UnionOperation") then
            -- Roblox equivalent: set smooth surface on all faces
            for _, surface in ipairs({
                Enum.NormalId.Front,
                Enum.NormalId.Back,
                Enum.NormalId.Left,
                Enum.NormalId.Right,
                Enum.NormalId.Top,
                Enum.NormalId.Bottom,
            }) do
                desc:SetAttribute("SmoothSurface", true)
            end

            -- Force SmoothingAngle via attribute (custom rendering pipeline reads this)
            desc:SetAttribute("BevelRadius",    0.08)   -- 8% of smallest dimension
            desc:SetAttribute("SmoothingAngle", 35)     -- degrees

            -- Use SmoothPlastic by default to catch specular cleanly
            if desc.Material == Enum.Material.SmoothPlastic or
               desc.Material == Enum.Material.Plastic then
                desc.Material = Enum.Material.SmoothPlastic
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- COURT FLOOR  – glossy mirror finish
-- ─────────────────────────────────────────────────────────────
function GraphicsEngine.configureCourtFloor(floorPart)
    floorPart.Material    = Enum.Material.SmoothPlastic
    floorPart.Reflectance = 0.35
    floorPart.Color       = Color3.fromRGB(185, 142, 80)  -- warm wood tone

    -- Surface appearance for PBR maps
    local sa = floorPart:FindFirstChildOfClass("SurfaceAppearance")
        or Instance.new("SurfaceAppearance", floorPart)

    -- In production: assign actual texture IDs
    sa.ColorMapId      = "rbxassetid://CourtWoodAlbedo"
    sa.NormalMapId     = "rbxassetid://CourtWoodNormal"
    sa.RoughnessMapId  = "rbxassetid://CourtWoodRoughness"  -- low roughness = glossy
    sa.MetalnessMapId  = "rbxassetid://CourtWoodMetalness"

    -- Active specular multiplier: force mirror-soft reflections
    floorPart:SetAttribute("SpecularMultiplier", 1.8)
end

-- ─────────────────────────────────────────────────────────────
-- CHARACTER SKIN  – satin texture overlay
-- ─────────────────────────────────────────────────────────────
function GraphicsEngine.applyCharacterSkin(character, styleRarity)
    -- Map style rarity to skin texture set
    local skinPack = GraphicsEngine._getSkinPack(styleRarity)

    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            part.Material    = Enum.Material.SmoothPlastic
            part.Reflectance = 0.08   -- subtle satin sheen

            local sa = part:FindFirstChildOfClass("SurfaceAppearance")
                or Instance.new("SurfaceAppearance", part)

            sa.ColorMapId     = skinPack.albedo
            sa.NormalMapId    = skinPack.normal
            sa.RoughnessMapId = skinPack.roughness  -- slightly rough for satin, not mirror

            -- Eliminate flat matte gradients by setting MetalnessMap to zero
            sa.MetalnessMapId = "rbxassetid://ZeroMetalness"
        end
    end
end

function GraphicsEngine._getSkinPack(rarity)
    local packs = {
        Common    = { albedo = "rbxassetid://SkinBase",    normal = "rbxassetid://SkinNormal",    roughness = "rbxassetid://SkinRoughSatin" },
        Rare      = { albedo = "rbxassetid://SkinRare",    normal = "rbxassetid://SkinNormal",    roughness = "rbxassetid://SkinRoughSatin" },
        Legendary = { albedo = "rbxassetid://SkinGold",    normal = "rbxassetid://SkinNormal",    roughness = "rbxassetid://SkinRoughGlossy" },
        Godly     = { albedo = "rbxassetid://SkinPurple",  normal = "rbxassetid://SkinNormal",    roughness = "rbxassetid://SkinRoughGlossy" },
        Secret    = { albedo = "rbxassetid://SkinRed",     normal = "rbxassetid://SkinNormalHD",  roughness = "rbxassetid://SkinRoughMirror" },
    }
    return packs[rarity] or packs.Common
end

-- ─────────────────────────────────────────────────────────────
-- CEL-SHADING OUTLINE PASS
-- Applies a black outline via SelectionBox or custom surface script
-- ─────────────────────────────────────────────────────────────
function GraphicsEngine.applyCelOutline(model)
    -- In Roblox, cel outlines are achieved via inverted-hull method:
    -- For each character part, create a slightly scaled clone with
    -- inverted face normals rendered in solid black.
    -- Here we tag each part; the custom render pipeline reads the tag.

    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part:SetAttribute("CelOutline", true)
            part:SetAttribute("OutlineThickness", 0.04)  -- studs
            part:SetAttribute("OutlineColor", "0,0,0")   -- RGB black
        end
    end

    -- Volleyball gets a thicker, high-contrast outline
    local ball = workspace:FindFirstChild("Volleyball")
    if ball then
        ball:SetAttribute("CelOutline", true)
        ball:SetAttribute("OutlineThickness", 0.06)
    end
end

-- ─────────────────────────────────────────────────────────────
-- VELOCITY-BASED MOTION BLUR
-- Runs on RenderStepped; samples camera delta and injects blur
-- ─────────────────────────────────────────────────────────────
local motionBlurEffect = nil
local prevCamCFrame    = CFrame.new()

function GraphicsEngine.initMotionBlur()
    -- Use DepthOfField or a custom ScreenGui overlay for blur
    -- Roblox doesn't have a native DirectX motion blur post-effect,
    -- so we simulate via a translucent smear frame overlay.

    local player     = game.Players.LocalPlayer
    local playerGui  = player:WaitForChild("PlayerGui")

    local blurGui    = Instance.new("ScreenGui", playerGui)
    blurGui.Name     = "MotionBlurGui"
    blurGui.ResetOnSpawn = false

    local blurFrame  = Instance.new("Frame", blurGui)
    blurFrame.Name   = "BlurOverlay"
    blurFrame.Size   = UDim2.fromScale(1, 1)
    blurFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    blurFrame.Position    = UDim2.fromScale(0.5, 0.5)
    blurFrame.BackgroundTransparency = 1.0  -- starts invisible
    blurFrame.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
    blurFrame.ZIndex  = 100

    motionBlurEffect  = blurFrame

    -- Alpha-blending interpolation loop at Camera.InterpolationHz
    RunService.RenderStepped:Connect(function(dt)
        local camera  = workspace.CurrentCamera
        local camCF   = camera.CFrame

        -- Measure angular velocity of camera
        local delta   = camCF:ToObjectSpace(prevCamCFrame)
        local _, rY, rX = delta:ToEulerAnglesYXZ()
        local angVel  = (math.abs(rX) + math.abs(rY)) / dt

        -- Measure ball velocity
        local ball    = workspace:FindFirstChild("Volleyball")
        local ballVel = ball and ball.Velocity.Magnitude or 0

        local maxVel  = GameConstants.Camera.MotionBlurThresh
        local blurAlpha = math.clamp(
            math.max(angVel * 0.8, ballVel) / maxVel, 0, 1
        ) * 0.25  -- max 25% opacity smear

        -- Apply directional smear
        motionBlurEffect.BackgroundTransparency = 1 - blurAlpha

        prevCamCFrame = camCF
    end)
end

-- ─────────────────────────────────────────────────────────────
-- SCREEN SHAKE (triggered by server ScreenShake event)
-- Decaying sinusoidal offset on camera CFrame
-- ─────────────────────────────────────────────────────────────
function GraphicsEngine.initScreenShake()
    local camera  = workspace.CurrentCamera
    local shaking = false
    local shakeOffset = CFrame.new()

    Remotes.Events.ScreenShake.OnClientEvent:Connect(function(payload)
        shaking = true
        local mag   = payload.magnitude or 0.5
        local freq  = payload.frequency or 18
        local decay = payload.decay or 0.85

        local t     = 0
        local conn
        conn = RunService.RenderStepped:Connect(function(dt)
            t = t + dt
            local envelope = mag * (decay ^ (t * 20))

            if envelope < 0.001 then
                shakeOffset = CFrame.new()
                shaking     = false
                conn:Disconnect()
                return
            end

            local offsetX = math.sin(t * freq * math.pi * 2) * envelope
            local offsetY = math.cos(t * freq * math.pi * 1.7) * envelope * 0.6
            shakeOffset   = CFrame.new(offsetX, offsetY, 0)
        end)
    end)

    -- Inject shake into camera each frame
    RunService.RenderStepped:Connect(function()
        if shaking then
            camera.CFrame = camera.CFrame * shakeOffset
        end
    end)
end

-- ─────────────────────────────────────────────────────────────
-- FULLSCREEN TOGGLE (F11)
-- ─────────────────────────────────────────────────────────────
function GraphicsEngine.initFullscreenToggle()
    local UserInputService = game:GetService("UserInputService")
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.F11 then
            local settings = UserSettings():GetService("UserGameSettings")
            settings.FullscreenDisabled = not settings.FullscreenDisabled
        end
    end)
end

-- ─────────────────────────────────────────────────────────────
-- RADIAL SCREEN FLASH (spike score impact)
-- ─────────────────────────────────────────────────────────────
function GraphicsEngine.initRadialFlash()
    local player    = game.Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    Remotes.Events.RadialFlash.OnClientEvent:Connect(function(payload)
        local flashGui  = Instance.new("ScreenGui", playerGui)
        flashGui.ResetOnSpawn = false

        local circle    = Instance.new("Frame", flashGui)
        circle.AnchorPoint = Vector2.new(0.5, 0.5)
        circle.Position    = UDim2.fromScale(0.5, 0.5)
        circle.Size        = UDim2.fromScale(0, 0)
        circle.BackgroundColor3       = payload.color or Color3.fromRGB(255, 255, 255)
        circle.BackgroundTransparency = 0.3
        circle.ZIndex     = 200

        local corner = Instance.new("UICorner", circle)
        corner.CornerRadius = UDim.new(1, 0)

        -- Expand outward
        TweenService:Create(circle,
            TweenInfo.new(payload.duration or 0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            { Size = UDim2.fromScale(3, 3), BackgroundTransparency = 1.0 }
        ):Play()

        task.delay((payload.duration or 0.25) + 0.1, function()
            flashGui:Destroy()
        end)
    end)
end

-- ─────────────────────────────────────────────────────────────
-- MASTER INIT
-- ─────────────────────────────────────────────────────────────
function GraphicsEngine.init()
    GraphicsEngine.initLighting()
    GraphicsEngine.initMotionBlur()
    GraphicsEngine.initScreenShake()
    GraphicsEngine.initFullscreenToggle()
    GraphicsEngine.initRadialFlash()

    -- Apply edge beveling to court and props
    local court = workspace:FindFirstChild("Court")
    if court then
        GraphicsEngine.applyEdgeBeveling(court)
        local floor = court:FindFirstChild("Floor")
        if floor then GraphicsEngine.configureCourtFloor(floor) end
    end

    print("[GraphicsEngine] Initialized.")
end

return GraphicsEngine
