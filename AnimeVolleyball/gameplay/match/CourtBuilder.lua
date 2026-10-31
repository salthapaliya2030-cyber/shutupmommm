-- ============================================================
-- CourtBuilder.lua  |  gameplay/match/
-- Procedural court geometry builder (runs on server, once).
-- Builds: floor, net, boundary lines, boundary walls,
-- stadium lighting rigs, lobby matchmaking cylinder,
-- and team spawn markers.
-- Output: all parts parented under workspace.Court
-- ============================================================

local GameConstants = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)

local CourtBuilder = {}

-- ─────────────────────────────────────────────────────────────
-- UTILITY HELPERS
-- ─────────────────────────────────────────────────────────────
local function makePart(name, size, cframe, color, material, anchored)
    local p = Instance.new("Part")
    p.Name       = name
    p.Size       = size
    p.CFrame     = cframe
    p.Color      = color or Color3.fromRGB(200, 200, 200)
    p.Material   = material or Enum.Material.SmoothPlastic
    p.Anchored   = anchored ~= false  -- default true
    p.CanCollide = true
    p.CastShadow = true
    return p
end

local function makeLight(parent, brightness, color, range, shadows)
    local light        = Instance.new("PointLight", parent)
    light.Brightness   = brightness or 5
    light.Color        = color      or Color3.fromRGB(255, 245, 220)
    light.Range        = range      or 40
    light.Shadows      = shadows    ~= false
    return light
end

-- ─────────────────────────────────────────────────────────────
-- MAIN BUILD FUNCTION
-- ─────────────────────────────────────────────────────────────
function CourtBuilder.build()
    -- Create parent folder
    local courtFolder = workspace:FindFirstChild("Court")
        or Instance.new("Folder", workspace)
    courtFolder.Name = "Court"

    local C = GameConstants.Court
    local halfL = C.HalfLength
    local halfW = C.HalfWidth

    -- ── FLOOR (18 × 0.2 × 9 studs)
    local floor = makePart("Floor",
        Vector3.new(halfW * 2, 0.2, halfL * 2),
        CFrame.new(0, C.FloorY - 0.1, 0),
        Color3.fromRGB(185, 142, 80),
        Enum.Material.SmoothPlastic
    )
    floor.Reflectance = 0.28
    floor.Parent = courtFolder

    -- Floor surface appearance (PBR maps wired in GraphicsEngine)
    local sa = Instance.new("SurfaceAppearance", floor)
    sa.ColorMapId     = "rbxassetid://CourtWoodAlbedo"
    sa.NormalMapId    = "rbxassetid://CourtWoodNormal"
    sa.RoughnessMapId = "rbxassetid://CourtWoodRoughness"

    -- ── COURT BOUNDARY LINES (white strips on floor surface)
    local function makeLine(name, size, z, x)
        local line = makePart(name,
            Vector3.new(size.X, 0.05, size.Z),
            CFrame.new(x or 0, C.FloorY + 0.01, z or 0),
            Color3.fromRGB(255, 255, 255),
            Enum.Material.SmoothPlastic
        )
        line.CanCollide = false
        line.Parent     = courtFolder
        return line
    end

    -- Side lines (along Z axis)
    makeLine("SideLineLeft",  Vector3.new(0.15, 1, halfL * 2), 0, -halfW)
    makeLine("SideLineRight", Vector3.new(0.15, 1, halfL * 2), 0,  halfW)

    -- End lines (along X axis)
    makeLine("EndLineA", Vector3.new(halfW * 2, 1, 0.15), -halfL, 0)
    makeLine("EndLineB", Vector3.new(halfW * 2, 1, 0.15),  halfL, 0)

    -- Attack lines (3m from center)
    makeLine("AttackLineA", Vector3.new(halfW * 2, 1, 0.12), -3, 0)
    makeLine("AttackLineB", Vector3.new(halfW * 2, 1, 0.12),  3, 0)

    -- Center line (under net)
    makeLine("CenterLine", Vector3.new(halfW * 2, 1, 0.08), 0, 0)

    -- ── NET STRUCTURE
    local netHeight = C.NetTopY
    local netPost_L = makePart("NetPostLeft",
        Vector3.new(0.2, netHeight + 0.5, 0.2),
        CFrame.new(-halfW - 0.3, (netHeight + 0.5) / 2, C.NetPlaneZ),
        Color3.fromRGB(180, 180, 180),
        Enum.Material.Metal
    )
    netPost_L.Parent = courtFolder

    local netPost_R = netPost_L:Clone()
    netPost_R.Name = "NetPostRight"
    netPost_R.CFrame = CFrame.new(halfW + 0.3, (netHeight + 0.5) / 2, C.NetPlaneZ)
    netPost_R.Parent = courtFolder

    -- Net mesh (thin plane, no collision above net height – ball passes over)
    local netMesh = makePart("Net",
        Vector3.new(halfW * 2 + 0.6, netHeight, C.NetThickness),
        CFrame.new(0, netHeight / 2, C.NetPlaneZ),
        Color3.fromRGB(220, 220, 220),
        Enum.Material.Neon
    )
    netMesh.Transparency  = 0.35
    netMesh.CanCollide    = true   -- physical collision for ball below top
    netMesh.CastShadow    = false
    netMesh.Parent        = courtFolder

    -- Invisible collision plane ABOVE net (prevents ball phasing through top edge)
    local netTop = makePart("NetTopEdge",
        Vector3.new(halfW * 2 + 0.6, 0.12, C.NetThickness * 3),
        CFrame.new(0, netHeight + 0.04, C.NetPlaneZ),
        Color3.fromRGB(255, 255, 255),
        Enum.Material.SmoothPlastic
    )
    netTop.Transparency = 1.0
    netTop.CanCollide   = true
    netTop.CastShadow   = false
    netTop.Parent       = courtFolder

    -- ── INVISIBLE BOUNDARY WALLS (trigger surface-normal raycast on ball)
    local function makeWall(name, size, cf)
        local w = makePart(name, size, cf,
            Color3.fromRGB(0,0,0), Enum.Material.SmoothPlastic)
        w.Transparency = 1.0
        w.CanCollide   = true
        w.CastShadow   = false
        w:SetAttribute("IsBoundaryWall", true)
        w.Parent       = courtFolder
        return w
    end

    makeWall("WallLeft",  Vector3.new(0.3, 20, halfL * 2),
        CFrame.new(-halfW - 0.15, 10, 0))
    makeWall("WallRight", Vector3.new(0.3, 20, halfL * 2),
        CFrame.new( halfW + 0.15, 10, 0))
    makeWall("WallBackA", Vector3.new(halfW * 2, 20, 0.3),
        CFrame.new(0, 10, -halfL - 0.15))
    makeWall("WallBackB", Vector3.new(halfW * 2, 20, 0.3),
        CFrame.new(0, 10,  halfL + 0.15))
    makeWall("Ceiling",   Vector3.new(halfW * 2 + 4, 0.3, halfL * 2 + 4),
        CFrame.new(0, 22, 0))

    -- ── FLOOR UNDER-COURT (prevents ball falling through on edge clips)
    local underFloor = makePart("UnderFloor",
        Vector3.new(halfW * 2 + 4, 0.3, halfL * 2 + 4),
        CFrame.new(0, -2, 0),
        Color3.fromRGB(40, 40, 40),
        Enum.Material.SmoothPlastic
    )
    underFloor.Parent = courtFolder

    -- ── STADIUM LIGHTING RIGS  (4 overhead lights)
    local lightPositions = {
        Vector3.new(-halfW * 0.5,  18, -halfL * 0.5),
        Vector3.new( halfW * 0.5,  18, -halfL * 0.5),
        Vector3.new(-halfW * 0.5,  18,  halfL * 0.5),
        Vector3.new( halfW * 0.5,  18,  halfL * 0.5),
    }

    for i, pos in ipairs(lightPositions) do
        local rig = makePart("LightRig" .. i,
            Vector3.new(0.6, 0.6, 0.6),
            CFrame.new(pos),
            Color3.fromRGB(30, 30, 30),
            Enum.Material.Metal
        )
        rig.CastShadow = false
        rig.Parent     = courtFolder
        makeLight(rig, 6, Color3.fromRGB(255, 248, 230), 35, true)

        -- Spotlight aiming down
        local spot = Instance.new("SpotLight", rig)
        spot.Brightness = 8
        spot.Angle      = 55
        spot.Color      = Color3.fromRGB(255, 248, 230)
        spot.Range      = 40
        spot.Face       = Enum.NormalId.Bottom
        spot.Shadows    = true
    end

    -- ── TEAM SPAWN MARKERS (visible colored discs on floor)
    for team, positions in pairs(C.Spawns) do
        local teamColor = team == "A"
            and Color3.fromRGB(60, 100, 220)
            or  Color3.fromRGB(220, 60, 60)

        for role, coord in pairs(positions) do
            local marker = makePart("Spawn_" .. team .. "_" .. role,
                Vector3.new(1.2, 0.05, 1.2),
                CFrame.new(coord.x, C.FloorY + 0.02, coord.z),
                teamColor,
                Enum.Material.Neon
            )
            marker.CanCollide = false
            marker.CastShadow = false
            marker.Transparency = 0.5
            marker.Parent = courtFolder

            local mc = Instance.new("CylinderMesh", marker)
            mc.Scale  = Vector3.new(1, 0.3, 1)

            -- Label
            local billboard = Instance.new("BillboardGui", marker)
            billboard.Size  = UDim2.fromScale(3, 1)
            billboard.StudsOffset = Vector3.new(0, 1, 0)
            local lbl = Instance.new("TextLabel", billboard)
            lbl.Text  = team .. " - " .. role
            lbl.Size  = UDim2.fromScale(1,1)
            lbl.BackgroundTransparency = 1
            lbl.TextColor3 = Color3.fromRGB(255,255,255)
            lbl.Font  = Enum.Font.GothamBold
            lbl.TextScaled = true
        end
    end

    -- ── MATCHMAKING ZONE (glowing green cylinder in lobby area)
    local matchZone = makePart("MatchZone",
        Vector3.new(5, 0.3, 5),
        CFrame.new(0, C.FloorY + 0.1, halfL + 6),
        Color3.fromRGB(60, 220, 80),
        Enum.Material.Neon
    )
    matchZone.CanCollide  = false
    matchZone.Transparency = 0.3
    matchZone.CastShadow  = false
    matchZone.Parent      = workspace  -- directly in workspace so ServerMain can find it

    local zoneLabel = Instance.new("BillboardGui", matchZone)
    zoneLabel.Size  = UDim2.fromScale(8, 2)
    zoneLabel.StudsOffset = Vector3.new(0, 2, 0)
    local zoneText  = Instance.new("TextLabel", zoneLabel)
    zoneText.Text   = "▶ ENTER MATCH"
    zoneText.Size   = UDim2.fromScale(1,1)
    zoneText.BackgroundTransparency = 1
    zoneText.TextColor3 = Color3.fromRGB(60, 255, 100)
    zoneText.Font  = Enum.Font.GothamBold
    zoneText.TextScaled = true

    -- Pulsing glow animation
    local pulseTween = game:GetService("TweenService"):Create(matchZone,
        TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { Transparency = 0.6, Color = Color3.fromRGB(80, 255, 100) }
    )
    pulseTween:Play()

    -- ── VOLLEYBALL  (if it doesn't already exist)
    if not workspace:FindFirstChild("Volleyball") then
        local ball = makePart("Volleyball",
            Vector3.new(
                GameConstants.Physics.BallRadius * 2,
                GameConstants.Physics.BallRadius * 2,
                GameConstants.Physics.BallRadius * 2
            ),
            CFrame.new(0, 4, 0),
            Color3.fromRGB(255, 255, 230),
            Enum.Material.SmoothPlastic,
            false  -- NOT anchored
        )
        ball.Anchored   = false
        ball.CanCollide = true
        ball.CastShadow = true

        local ballMesh  = Instance.new("SpecialMesh", ball)
        ballMesh.MeshType = Enum.MeshType.Sphere

        local sa2 = Instance.new("SurfaceAppearance", ball)
        sa2.ColorMapId     = "rbxassetid://VolleyballAlbedo"
        sa2.NormalMapId    = "rbxassetid://VolleyballNormal"
        sa2.RoughnessMapId = "rbxassetid://VolleyballRoughness"

        ball.Parent = workspace
    end

    print("[CourtBuilder] Court construction complete.")
    return courtFolder
end

return CourtBuilder
