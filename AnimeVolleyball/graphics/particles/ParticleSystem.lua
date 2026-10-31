-- ============================================================
-- ParticleSystem.lua  |  graphics/particles/
-- Client-side particle effect orchestrator.
-- Responds to server SpawnEffect / HeadTextPop events.
-- Self-destroying container structure prevents perf degradation.
-- ============================================================

local TweenService  = game:GetService("TweenService")
local RunService    = game:GetService("RunService")
local GameConstants = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes       = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)

-- ─────────────────────────────────────────────────────────────
-- PARTICLE POOL  (capped at ParticlePoolSize per emitter)
-- ─────────────────────────────────────────────────────────────
local ParticlePool = {}
local activeParts  = 0

local function spawnPart(position, size, color, lifetime)
    if activeParts >= GameConstants.Particles.ParticlePoolSize then return nil end
    activeParts = activeParts + 1

    local p       = Instance.new("Part")
    p.Size        = size or Vector3.new(0.15, 0.15, 0.15)
    p.Color       = color or Color3.fromRGB(255, 255, 255)
    p.Material    = Enum.Material.Neon
    p.Anchored    = false
    p.CanCollide  = false
    p.Position    = position
    p.CastShadow  = false
    p.Parent      = workspace

    game:GetService("Debris"):AddItem(p, lifetime or 0.6)
    task.delay(lifetime or 0.6, function()
        activeParts = activeParts - 1
    end)

    return p
end

-- ─────────────────────────────────────────────────────────────
-- BALL TRAIL
-- Returns a container Part with an attached Trail
-- ─────────────────────────────────────────────────────────────
local function createTrail(ball, trailColor, width)
    local container  = Instance.new("Attachment", ball)
    container.Name   = "TrailAttachment"

    local trailA     = Instance.new("Attachment", ball)
    trailA.Position  = Vector3.new(0,  0.35, 0)
    local trailB     = Instance.new("Attachment", ball)
    trailB.Position  = Vector3.new(0, -0.35, 0)

    local trail      = Instance.new("Trail")
    trail.Attachment0 = trailA
    trail.Attachment1 = trailB
    trail.Color       = ColorSequence.new({
        ColorSequenceKeypoint.new(0, trailColor),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
    })
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.0),
        NumberSequenceKeypoint.new(1, 1.0),
    })
    trail.Width    = width or 0.5
    trail.Lifetime = GameConstants.Particles.TrailSegmentLength * 8
    trail.Parent   = ball

    return trail, container, trailA, trailB
end

-- ─────────────────────────────────────────────────────────────
-- EFFECT REGISTRY
-- ─────────────────────────────────────────────────────────────
local activeTrail      = nil
local activeTrailParts = {}

local function clearTrail()
    for _, obj in ipairs(activeTrailParts) do
        if obj and obj.Parent then obj:Destroy() end
    end
    activeTrailParts = {}
    activeTrail      = nil
end

-- ─────────────────────────────────────────────────────────────
-- EFFECT SPAWNER (triggered by server SpawnEffect event)
-- ─────────────────────────────────────────────────────────────
Remotes.Events.SpawnEffect.OnClientEvent:Connect(function(payload)
    local effectType    = payload.effectType
    local worldPos      = payload.worldPosition
    local styleRarity   = payload.styleRarity or "Common"
    local ball          = workspace:FindFirstChild("Volleyball")

    clearTrail()

    -- ── BUMP: soft blue wind stream
    if effectType == "Bump" then
        local color = Color3.fromRGB(80, 160, 255)
        if ball then
            local t, c, a, b = createTrail(ball, color, 0.4)
            activeTrail = t
            table.insert(activeTrailParts, c)
            table.insert(activeTrailParts, a)
            table.insert(activeTrailParts, b)
            table.insert(activeTrailParts, t)
        end

    -- ── SET: glowing yellow geometric ring at apex
    elseif effectType == "Set" then
        -- Ring ring emitted at apex (delayed by flight time estimate)
        task.delay(0.6, function()
            local ring = Instance.new("Part")
            ring.Size           = Vector3.new(0.05, 2.0, 2.0)
            ring.Color          = Color3.fromRGB(255, 240, 80)
            ring.Material       = Enum.Material.Neon
            ring.Anchored       = true
            ring.CanCollide     = false
            ring.CastShadow     = false
            if ball then ring.Position = ball.Position end
            ring.Parent = workspace

            TweenService:Create(ring,
                TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { Size = Vector3.new(0.01, 4, 4), Transparency = 1.0 }
            ):Play()

            game:GetService("Debris"):AddItem(ring, 0.5)
        end)

    -- ── SPIKE: plasma trail (color by rarity)
    elseif effectType == "Spike" or effectType == "Serve" then
        local rarityColors = {
            Secret    = Color3.fromRGB(255, 60, 20),
            Godly     = Color3.fromRGB(160, 32, 240),
            Legendary = Color3.fromRGB(255, 200, 0),
            Rare      = Color3.fromRGB(100, 180, 255),
            Common    = Color3.fromRGB(255, 255, 255),
        }
        local color = rarityColors[styleRarity] or rarityColors.Common

        if ball then
            -- Neon glow on ball itself
            ball.Material = Enum.Material.Neon
            ball.Color    = color
            task.delay(0.3, function()
                ball.Material = Enum.Material.SmoothPlastic
                ball.Color    = Color3.fromRGB(255, 255, 255)
            end)

            local t, c, a, b = createTrail(ball, color, 0.8)
            t.Lifetime = 0.22
            activeTrail = t
            table.insert(activeTrailParts, c)
            table.insert(activeTrailParts, a)
            table.insert(activeTrailParts, b)
            table.insert(activeTrailParts, t)
        end

        -- Radial screen flash
        Remotes.Events.RadialFlash:FireServer()  -- server re-fires to all clients
        -- (in real impl the server fires this itself on PointScored for floor impact)

    end
end)

-- ─────────────────────────────────────────────────────────────
-- FLOOR IMPACT EXPLOSION (fired with PointScored floor impact)
-- ─────────────────────────────────────────────────────────────
Remotes.Events.PointScored.OnClientEvent:Connect(function(payload)
    local ball = workspace:FindFirstChild("Volleyball")
    if not ball then return end

    local impactPos = ball.Position
    local P         = GameConstants.Particles

    -- Radial debris burst
    for i = 1, P.ImpactDebrisCount do
        local angle    = (i / P.ImpactDebrisCount) * math.pi * 2
        local debrisPart = spawnPart(
            impactPos + Vector3.new(0, 0.2, 0),
            Vector3.new(0.1, 0.1, 0.1),
            Color3.fromRGB(255, 200 + math.random(-30, 30), 50 + math.random(0, 100)),
            P.ImpactDebrisLifetime
        )
        if debrisPart then
            debrisPart.Velocity = Vector3.new(
                math.cos(angle) * P.ImpactRingRadius * 5,
                math.random(8, 15),
                math.sin(angle) * P.ImpactRingRadius * 5
            )
        end
    end

    clearTrail()
end)

-- ─────────────────────────────────────────────────────────────
-- FLOATING HEAD TEXT POPS
-- "PERFECT BUMP", "TILT SET", "SHIELD BREAKER" etc.
-- ─────────────────────────────────────────────────────────────
local textLabels = {
    PerfectReceive = "PERFECT BUMP",
    Set            = "TILT SET",
    Spike          = "SPIKE!",
    ShieldBreaker  = "SHIELD BREAKER",
    SteelBlock     = "STEEL BLOCK",
    BoomJump       = "BOOM JUMP",
    MagneticPull   = "MAGNETIC PULL",
    TooLow         = "TOO LOW!",
}

Remotes.Events.HeadTextPop.OnClientEvent:Connect(function(payload)
    local playerID  = payload.playerID
    local textKey   = payload.textLabel
    local labelText = textLabels[textKey] or textKey

    -- Find character head
    local targetChar
    for _, player in ipairs(game.Players:GetPlayers()) do
        if player.UserId == playerID then
            targetChar = player.Character
            break
        end
    end

    -- Could be a bot; find by name
    if not targetChar then
        targetChar = workspace:FindFirstChild(tostring(playerID))
    end

    if not targetChar then return end

    local headPart = targetChar:FindFirstChild("Head")
    if not headPart then return end

    -- Create BillboardGui above head
    local bb        = Instance.new("BillboardGui", headPart)
    bb.Size         = UDim2.fromScale(5, 1.5)
    bb.StudsOffset  = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop  = false
    bb.ResetOnSpawn = false

    local label     = Instance.new("TextLabel", bb)
    label.Size      = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text      = labelText
    label.TextColor3 = Color3.fromRGB(255, 240, 80)
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextStrokeTransparency = 0.3
    label.Font      = Enum.Font.GothamBold
    label.TextScaled = true

    -- Float upward and fade
    TweenService:Create(label,
        TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { TextTransparency = 1.0 }
    ):Play()

    TweenService:Create(bb,
        TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { StudsOffset = Vector3.new(0, 6, 0) }
    ):Play()

    game:GetService("Debris"):AddItem(bb, 1.1)
end)

print("[ParticleSystem] Initialized.")
