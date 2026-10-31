-- ============================================================
-- ClientMain.lua  |  graphics/ui/
-- Client-side LocalScript entry point.
-- Initializes all client systems in correct dependency order.
-- Wires input signals to server remote events.
-- ============================================================

local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GameConstants    = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes          = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)
local GraphicsEngine   = require(game.ReplicatedStorage.AnimeVB.graphics.materials.GraphicsEngine)
local CameraEngine     = require(game.ReplicatedStorage.AnimeVB.graphics.viewport.CameraEngine)
local AnimationEngine  = require(game.ReplicatedStorage.AnimeVB.animations.joints.AnimationEngine)

-- UI and particle systems are required for side effects (event listeners)
require(game.ReplicatedStorage.AnimeVB.graphics.ui.UIController)
require(game.ReplicatedStorage.AnimeVB.graphics.particles.ParticleSystem)

local player = game.Players.LocalPlayer

-- ─────────────────────────────────────────────────────────────
-- INITIALIZATION SEQUENCE
-- ─────────────────────────────────────────────────────────────
GraphicsEngine.init()
CameraEngine.init()

-- Register local character for animation
player.CharacterAdded:Connect(function(character)
    AnimationEngine.registerCharacter(player.UserId, character)
    GraphicsEngine.applyCelOutline(character)

    -- Load style from profile and apply skin
    local profile = Remotes.Functions.GetProfile:InvokeServer()
    if profile and profile.style then
        local styleData = GameConstants.Styles[profile.style]
        if styleData then
            GraphicsEngine.applyCharacterSkin(character, styleData.rarity)
        end
    end
end)

if player.Character then
    AnimationEngine.registerCharacter(player.UserId, player.Character)
    GraphicsEngine.applyCelOutline(player.Character)
end

-- ─────────────────────────────────────────────────────────────
-- FLOOR SHADOW RENDERER
-- ─────────────────────────────────────────────────────────────
local shadowPart = nil

Remotes.Events.BallShadowUpdate.OnClientEvent:Connect(function(payload)
    if not shadowPart then
        shadowPart = Instance.new("Part")
        shadowPart.Name         = "BallShadow"
        shadowPart.Size         = Vector3.new(1, 0.05, 1)
        shadowPart.Anchored     = true
        shadowPart.CanCollide   = false
        shadowPart.CastShadow   = false
        shadowPart.Material     = Enum.Material.Neon
        shadowPart.Color        = Color3.fromRGB(255, 255, 255)
        shadowPart.Parent       = workspace

        local cyl = Instance.new("CylinderMesh", shadowPart)
        cyl.Scale = Vector3.new(1, 0.05, 1)
    end

    local r     = payload.radius or 1
    shadowPart.Size          = Vector3.new(r * 2, 0.05, r * 2)
    shadowPart.Position      = Vector3.new(payload.x, GameConstants.Court.FloorY + 0.03, payload.z)
    shadowPart.Transparency  = 1 - (payload.alpha or 0.5)
end)

-- ─────────────────────────────────────────────────────────────
-- INPUT → SERVER RELAY
-- Client sends ONLY minimal input signals; server does all math
-- ─────────────────────────────────────────────────────────────
local inputMap = {
    -- Jump
    [Enum.KeyCode.Space] = function()
        Remotes.Events.PlayerInput:FireServer({
            actionType = "Jump",
            timestamp  = os.clock(),
        })
    end,

    -- Set (Q / E)
    [Enum.KeyCode.Q] = function()
        local moveDir = _getMoveDirection()
        Remotes.Events.PlayerInput:FireServer({
            actionType    = "Set",
            moveDirection = moveDir,
            timestamp     = os.clock(),
        })
    end,
    [Enum.KeyCode.E] = function()
        local moveDir = _getMoveDirection()
        Remotes.Events.PlayerInput:FireServer({
            actionType    = "Set",
            moveDirection = moveDir,
            timestamp     = os.clock(),
        })
    end,

    -- Ability
    [Enum.KeyCode.F] = function()
        Remotes.Functions.RequestAbility:InvokeServer()
    end,
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local handler = inputMap[input.KeyCode]
    if handler then handler() end
end)

-- Mouse button 1: Bump or Spike depending on character state
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

    local char     = player.Character
    if not char    then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local rootY    = char.HumanoidRootPart and char.HumanoidRootPart.Position.Y or 0
    local isAirborne = rootY > (GameConstants.Court.FloorY + 0.5)

    if isAirborne then
        -- SPIKE
        local lookVec = CameraEngine.getLookVector()
        local dirMod  = _getDirModifier()

        Remotes.Events.PlayerInput:FireServer({
            actionType    = "Spike",
            lookVector    = lookVec,
            dirModifier   = dirMod,
            timestamp     = os.clock(),
        })
    else
        -- BUMP
        Remotes.Events.PlayerInput:FireServer({
            actionType = "Bump",
            timestamp  = os.clock(),
        })
    end
end)

-- Right mouse + move = dive (double tap down)
-- Simplified: Ctrl = dive
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.LeftControl then
        Remotes.Events.PlayerInput:FireServer({
            actionType = "Dive",
            timestamp  = os.clock(),
        })
    end
end)

-- ─────────────────────────────────────────────────────────────
-- HELPERS
-- ─────────────────────────────────────────────────────────────
function _getMoveDirection()
    local char = player.Character
    if not char then return Vector3.zero end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return Vector3.zero end
    return humanoid.MoveDirection
end

function _getDirModifier()
    -- Read currently held WASD key for spike directional modifier
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then return "W" end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then return "S" end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then return "A" end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then return "D" end
    return nil
end

-- ─────────────────────────────────────────────────────────────
-- OTHER PLAYER CHARACTER REGISTRATION (for animation sync)
-- ─────────────────────────────────────────────────────────────
game.Players.PlayerAdded:Connect(function(otherPlayer)
    otherPlayer.CharacterAdded:Connect(function(character)
        AnimationEngine.registerCharacter(otherPlayer.UserId, character)
        GraphicsEngine.applyCelOutline(character)
    end)
end)

game.Players.PlayerRemoving:Connect(function(otherPlayer)
    AnimationEngine.unregisterCharacter(otherPlayer.UserId)
end)

print("[ClientMain] Anime Volleyball Client initialized.")
