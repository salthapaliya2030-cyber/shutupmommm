-- ============================================================
-- UIController.lua  |  graphics/ui/
-- Client-side UI controller.
-- Manages: main menu, match HUD, gacha wheel modal,
-- team/position selection prompt, and ability energy meter.
-- All placement uses relative UDim2 scaling (never fixed pixels).
-- Includes UIAspectRatioConstraint on circular elements.
-- ============================================================

local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GameConstants    = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes          = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)

local player    = game.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─────────────────────────────────────────────────────────────
-- SCREEN GUI ROOT
-- ─────────────────────────────────────────────────────────────
local mainGui   = Instance.new("ScreenGui", playerGui)
mainGui.Name    = "AnimeVBGui"
mainGui.ResetOnSpawn     = false
mainGui.IgnoreGuiInset   = true
mainGui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling

-- Anchor-validation: ensure all frames anchored correctly on load
mainGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    -- This fires on resolution change; all UDim2 frames auto-reflow
end)

-- ─────────────────────────────────────────────────────────────
-- UTILITY: Create Frame
-- ─────────────────────────────────────────────────────────────
local function makeFrame(parent, size, pos, color, transparency, name)
    local f = Instance.new("Frame", parent)
    f.Name   = name or "Frame"
    f.Size   = size
    f.Position = pos
    f.BackgroundColor3        = color or Color3.fromRGB(20, 20, 30)
    f.BackgroundTransparency  = transparency or 0
    f.BorderSizePixel         = 0
    return f
end

local function makeLabel(parent, text, size, pos, textColor, fontSize, name)
    local l = Instance.new("TextLabel", parent)
    l.Name     = name or "Label"
    l.Size     = size
    l.Position = pos
    l.Text     = text
    l.TextColor3 = textColor or Color3.fromRGB(255, 255, 255)
    l.Font     = Enum.Font.GothamBold
    l.TextScaled = true
    l.BackgroundTransparency = 1
    l.BorderSizePixel = 0
    return l
end

local function makeButton(parent, text, size, pos, color, name)
    local b   = Instance.new("TextButton", parent)
    b.Name    = name or "Button"
    b.Size    = size
    b.Position = pos
    b.Text    = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font    = Enum.Font.GothamBold
    b.TextScaled = true
    b.BackgroundColor3       = color or Color3.fromRGB(40, 100, 200)
    b.BackgroundTransparency = 0.1
    b.BorderSizePixel        = 0
    local corner = Instance.new("UICorner", b)
    corner.CornerRadius = UDim.new(0.12, 0)

    -- Hover feedback
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.1), { Size = size + UDim2.fromScale(0.01, 0.01) }):Play()
        b.BackgroundTransparency = 0.0
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.1), { Size = size }):Play()
        b.BackgroundTransparency = 0.1
    end)
    return b
end

-- ═══════════════════════════════════════════════════════════════
--  MAIN MENU
-- ═══════════════════════════════════════════════════════════════
local mainMenuFrame = makeFrame(mainGui,
    UDim2.fromScale(1, 1),
    UDim2.fromScale(0, 0),
    Color3.fromRGB(8, 12, 28), 0, "MainMenu"
)

-- Currency labels (top left)
local currencyPanel = makeFrame(mainMenuFrame,
    UDim2.fromScale(0.18, 0.08),
    UDim2.fromScale(0.01, 0.01),
    Color3.fromRGB(20, 20, 40), 0.3, "CurrencyPanel"
)
local yenLabel = makeLabel(currencyPanel, "Yen: 0",
    UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0),
    Color3.fromRGB(255, 230, 80), 18, "YenLabel"
)
local gemLabel = makeLabel(currencyPanel, "Gems: 0",
    UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0.5),
    Color3.fromRGB(120, 220, 255), 18, "GemLabel"
)

-- Play button (dead center)
local playButton = makeButton(mainMenuFrame, "▶  PLAY",
    UDim2.fromScale(0.22, 0.10),
    UDim2.fromScale(0.5, 0.42),
    Color3.fromRGB(50, 180, 80), "PlayButton"
)
playButton.AnchorPoint = Vector2.new(0.5, 0.5)

-- Bottom navigation bar (absolute bottom center)
local navBar = makeFrame(mainMenuFrame,
    UDim2.fromScale(0.36, 0.09),
    UDim2.fromScale(0.5, 0.95),
    Color3.fromRGB(20, 20, 40), 0.2, "NavBar"
)
navBar.AnchorPoint = Vector2.new(0.5, 1.0)

local navLayout = Instance.new("UIListLayout", navBar)
navLayout.FillDirection  = Enum.FillDirection.Horizontal
navLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
navLayout.Padding = UDim.new(0.03, 0)
navLayout.SortOrder = Enum.SortOrder.LayoutOrder

local inventoryBtn = makeButton(navBar, "🎒 INVENTORY",
    UDim2.fromScale(0.3, 0.85), UDim2.fromScale(0, 0.075),
    Color3.fromRGB(50, 50, 100), "InventoryBtn")
inventoryBtn.LayoutOrder = 1

local settingsBtn = makeButton(navBar, "⚙ SETTINGS",
    UDim2.fromScale(0.3, 0.85), UDim2.fromScale(0, 0.075),
    Color3.fromRGB(50, 50, 100), "SettingsBtn")
settingsBtn.LayoutOrder = 2

local rollingBtn = makeButton(navBar, "🎲 STYLE ROLL",
    UDim2.fromScale(0.3, 0.85), UDim2.fromScale(0, 0.075),
    Color3.fromRGB(100, 40, 180), "RollingBtn")
rollingBtn.LayoutOrder = 3

-- ═══════════════════════════════════════════════════════════════
--  GACHA WHEEL MODAL
-- ═══════════════════════════════════════════════════════════════
local gachaModal = makeFrame(mainGui,
    UDim2.fromScale(0.55, 0.80),
    UDim2.fromScale(0.5, 0.5),
    Color3.fromRGB(10, 8, 25), 0.05, "GachaModal"
)
gachaModal.AnchorPoint = Vector2.new(0.5, 0.5)
gachaModal.Visible     = false

local gachaCorner = Instance.new("UICorner", gachaModal)
gachaCorner.CornerRadius = UDim.new(0.04, 0)

-- Gacha wheel circle
local gachaWheel = makeFrame(gachaModal,
    UDim2.fromScale(0.55, 0),
    UDim2.fromScale(0.5, 0.38),
    Color3.fromRGB(30, 20, 60), 0.1, "GachaWheel"
)
gachaWheel.AnchorPoint = Vector2.new(0.5, 0.5)
-- Keep wheel perfectly circular via UIAspectRatioConstraint
local wheelAspect = Instance.new("UIAspectRatioConstraint", gachaWheel)
wheelAspect.AspectRatio = 1.0

local gachaCorner2 = Instance.new("UICorner", gachaWheel)
gachaCorner2.CornerRadius = UDim.new(1, 0)

local wheelLabel = makeLabel(gachaWheel, "?",
    UDim2.fromScale(1,1), UDim2.fromScale(0,0),
    Color3.fromRGB(255, 240, 80), 48, "WheelLabel"
)

-- Spin buttons
local spinYenBtn = makeButton(gachaModal, "Spin (500 Yen)",
    UDim2.fromScale(0.38, 0.10),
    UDim2.fromScale(0.28, 0.78),
    Color3.fromRGB(180, 140, 20), "SpinYenBtn")

local spinGemBtn = makeButton(gachaModal, "Spin (30 Gems)",
    UDim2.fromScale(0.38, 0.10),
    UDim2.fromScale(0.70, 0.78),
    Color3.fromRGB(60, 160, 220), "SpinGemBtn")
spinGemBtn.AnchorPoint = Vector2.new(1, 0)

local closeGachaBtn = makeButton(gachaModal, "✕",
    UDim2.fromScale(0.09, 0.07),
    UDim2.fromScale(0.97, 0.02),
    Color3.fromRGB(180, 40, 40), "CloseGachaBtn")
closeGachaBtn.AnchorPoint = Vector2.new(1, 0)

-- Wheel spin animation
local function spinWheel(resultText, resultColor)
    local spins    = 3 + math.random(0, 2)
    local duration = 1.8
    local target   = { Rotation = gachaWheel.Rotation + spins * 360 }

    TweenService:Create(gachaWheel,
        TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        target
    ):Play()

    task.delay(duration, function()
        wheelLabel.Text       = resultText  or "?"
        wheelLabel.TextColor3 = resultColor or Color3.fromRGB(255, 240, 80)
    end)
end

-- Spin request
local function fireSpin(currency)
    Remotes.Functions.RequestSpin:InvokeServer({ currency = currency })
end

spinYenBtn.Activated:Connect(function() fireSpin("Yen") end)
spinGemBtn.Activated:Connect(function() fireSpin("Gem") end)
closeGachaBtn.Activated:Connect(function() gachaModal.Visible = false end)
rollingBtn.Activated:Connect(function() gachaModal.Visible = true end)

Remotes.Events.SpinResult.OnClientEvent:Connect(function(payload)
    local rarityColors = {
        Secret    = Color3.fromRGB(255, 60, 20),
        Godly     = Color3.fromRGB(160, 32, 240),
        Legendary = Color3.fromRGB(255, 200, 0),
        Rare      = Color3.fromRGB(100, 200, 255),
        Common    = Color3.fromRGB(200, 200, 200),
    }
    spinWheel(payload.styleName, rarityColors[payload.rarity])
end)

-- ═══════════════════════════════════════════════════════════════
--  MATCH SETUP PROMPT
-- ═══════════════════════════════════════════════════════════════
local setupModal = makeFrame(mainGui,
    UDim2.fromScale(0.55, 0.65),
    UDim2.fromScale(0.5, 0.5),
    Color3.fromRGB(10, 15, 35), 0.05, "MatchSetupModal"
)
setupModal.AnchorPoint = Vector2.new(0.5, 0.5)
setupModal.Visible     = false
Instance.new("UICorner", setupModal).CornerRadius = UDim.new(0.04, 0)

local setupTitle = makeLabel(setupModal, "MATCH SETUP",
    UDim2.fromScale(1, 0.12), UDim2.fromScale(0, 0),
    Color3.fromRGB(255, 240, 80), 28, "SetupTitle")

-- Error text (bottom of modal)
local setupError = makeLabel(setupModal, "",
    UDim2.fromScale(0.9, 0.08), UDim2.fromScale(0.05, 0.88),
    Color3.fromRGB(255, 80, 80), 14, "SetupError")

-- Two-column layout
local teamColumn = makeFrame(setupModal,
    UDim2.fromScale(0.44, 0.62),
    UDim2.fromScale(0.02, 0.14),
    Color3.fromRGB(0,0,0), 1, "TeamColumn")

local posColumn = makeFrame(setupModal,
    UDim2.fromScale(0.44, 0.62),
    UDim2.fromScale(0.54, 0.14),
    Color3.fromRGB(0,0,0), 1, "PosColumn")

makeLabel(teamColumn, "CHOOSE TEAM",
    UDim2.fromScale(1, 0.15), UDim2.fromScale(0,0),
    Color3.fromRGB(200,200,220), 14)

makeLabel(posColumn, "CHOOSE POSITION",
    UDim2.fromScale(1, 0.15), UDim2.fromScale(0,0),
    Color3.fromRGB(200,200,220), 14)

local teamABtn = makeButton(teamColumn, "TEAM A",
    UDim2.fromScale(0.85, 0.28), UDim2.fromScale(0.075, 0.18),
    Color3.fromRGB(40, 80, 200), "TeamABtn")

local teamBBtn = makeButton(teamColumn, "TEAM B",
    UDim2.fromScale(0.85, 0.28), UDim2.fromScale(0.075, 0.52),
    Color3.fromRGB(200, 50, 50), "TeamBBtn")

local spikerBtn = makeButton(posColumn, "SPIKER",
    UDim2.fromScale(0.85, 0.22), UDim2.fromScale(0.075, 0.18),
    Color3.fromRGB(50, 50, 90), "SpikerBtn")

local setterBtn = makeButton(posColumn, "SETTER",
    UDim2.fromScale(0.85, 0.22), UDim2.fromScale(0.075, 0.42),
    Color3.fromRGB(50, 50, 90), "SetterBtn")

local liberoBtn = makeButton(posColumn, "LIBERO",
    UDim2.fromScale(0.85, 0.22), UDim2.fromScale(0.075, 0.66),
    Color3.fromRGB(50, 50, 90), "LiberoBtn")

-- Join button (illuminates when valid selection made)
local joinBtn = makeButton(setupModal, "JOIN MATCH ▶",
    UDim2.fromScale(0.50, 0.10), UDim2.fromScale(0.5, 0.92),
    Color3.fromRGB(50, 200, 80), "JoinBtn")
joinBtn.AnchorPoint        = Vector2.new(0.5, 1.0)
joinBtn.BackgroundTransparency = 0.6  -- greyed out initially

-- Selection state
local selectedTeam     = nil
local selectedPosition = nil

local teamBtns = { A = teamABtn, B = teamBBtn }
local posBtns  = { Spiker = spikerBtn, Setter = setterBtn, Libero = liberoBtn }

local function updateJoinBtn()
    if selectedTeam and selectedPosition then
        joinBtn.BackgroundTransparency = 0.0
    else
        joinBtn.BackgroundTransparency = 0.6
    end
end

local function selectTeam(team)
    selectedTeam = team
    for t, btn in pairs(teamBtns) do
        btn.BackgroundTransparency = (t == team) and 0.0 or 0.45
    end
    updateJoinBtn()
end

local function selectPos(pos)
    selectedPosition = pos
    for p, btn in pairs(posBtns) do
        btn.BackgroundTransparency = (p == pos) and 0.0 or 0.45
    end
    updateJoinBtn()
end

teamABtn.Activated:Connect(function() selectTeam("A") end)
teamBBtn.Activated:Connect(function() selectTeam("B") end)
spikerBtn.Activated:Connect(function() selectPos("Spiker") end)
setterBtn.Activated:Connect(function() selectPos("Setter") end)
liberoBtn.Activated:Connect(function() selectPos("Libero") end)

joinBtn.Activated:Connect(function()
    if not selectedTeam or not selectedPosition then return end
    local result = Remotes.Functions.RequestJoinSlot:InvokeServer({
        team     = selectedTeam,
        position = selectedPosition,
    })
    if not result.success then
        setupError.Text = result.errorMsg or "Error"
        task.delay(2.5, function() setupError.Text = "" end)
    else
        setupModal.Visible = false
    end
end)

-- Slot updates (grey out filled positions)
Remotes.Events.SlotStatusUpdate.OnClientEvent:Connect(function(payload)
    for team, positions in pairs(payload.slotTable) do
        for pos, uid in pairs(positions) do
            local btn = posBtns[pos]
            if btn and uid and team == selectedTeam then
                btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
                btn.Active = false
            end
        end
    end
end)

-- Show prompt
Remotes.Events.ShowMatchSetupPrompt.OnClientEvent:Connect(function(payload)
    mainMenuFrame.Visible = false
    setupModal.Visible    = true
    selectedTeam          = nil
    selectedPosition      = nil
    updateJoinBtn()
end)

-- ═══════════════════════════════════════════════════════════════
--  MATCH HUD
-- ═══════════════════════════════════════════════════════════════
local matchHUD = makeFrame(mainGui,
    UDim2.fromScale(1, 1),
    UDim2.fromScale(0, 0),
    Color3.fromRGB(0,0,0), 1, "MatchHUD"
)
matchHUD.Visible = false

-- Score counter (top center)
local scorePanel = makeFrame(matchHUD,
    UDim2.fromScale(0.32, 0.08),
    UDim2.fromScale(0.5, 0.01),
    Color3.fromRGB(10, 10, 20), 0.3, "ScorePanel"
)
scorePanel.AnchorPoint = Vector2.new(0.5, 0)

local scoreLabel = makeLabel(scorePanel, "0  :  0",
    UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
    Color3.fromRGB(255, 255, 255), 32, "ScoreLabel")

-- Ability icon (bottom right, circular)
local abilityPanel = makeFrame(matchHUD,
    UDim2.fromScale(0.09, 0),
    UDim2.fromScale(0.97, 0.97),
    Color3.fromRGB(20, 20, 50), 0.2, "AbilityPanel"
)
abilityPanel.AnchorPoint = Vector2.new(1, 1)
-- Circular via aspect ratio constraint
local abilityAspect = Instance.new("UIAspectRatioConstraint", abilityPanel)
abilityAspect.AspectRatio = 1.0
local abilityCorner = Instance.new("UICorner", abilityPanel)
abilityCorner.CornerRadius = UDim.new(1, 0)

-- Radial clock overlay (simulated via rotation of a clip frame)
local abilityFillOuter = makeFrame(abilityPanel,
    UDim2.fromScale(1,1), UDim2.fromScale(0,0),
    Color3.fromRGB(80, 200, 255), 0.15, "AbilityFillOuter"
)
Instance.new("UICorner", abilityFillOuter).CornerRadius = UDim.new(1, 0)

local abilityLabel = makeLabel(abilityPanel, "F",
    UDim2.fromScale(1,1), UDim2.fromScale(0,0),
    Color3.fromRGB(255, 255, 255), 28, "AbilityLabel")

-- Floor shadow indicator (created in BallShadowRenderer.lua)

-- ─────────────────────────────────────────────────────────────
-- HUD TRANSITIONS
-- ─────────────────────────────────────────────────────────────
Remotes.Events.TransitionToMatch.OnClientEvent:Connect(function()
    -- Slide main menu off screen
    TweenService:Create(mainMenuFrame,
        TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
        { Position = UDim2.fromScale(-1, 0) }
    ):Play()
    task.delay(0.5, function()
        mainMenuFrame.Visible = false
        matchHUD.Visible = true
    end)
end)

Remotes.Events.TransitionToLobby.OnClientEvent:Connect(function()
    matchHUD.Visible = false
    mainMenuFrame.Position = UDim2.fromScale(0, 0)
    mainMenuFrame.Visible  = true
end)

-- Score updates
Remotes.Events.PointScored.OnClientEvent:Connect(function(payload)
    scoreLabel.Text = string.format("%d  :  %d",
        payload.newScore.A or 0, payload.newScore.B or 0)
end)

-- Energy meter tween (radial drain/fill)
Remotes.Events.EnergyUpdate.OnClientEvent:Connect(function(payload)
    if payload.playerID ~= player.UserId then return end
    local pct = payload.newEnergy / GameConstants.Ability.MaxEnergy
    TweenService:Create(abilityFillOuter,
        TweenInfo.new(0.4, Enum.EasingStyle.Quad),
        { BackgroundTransparency = 0.15 + (1 - pct) * 0.80 }
    ):Play()
end)

-- Currency updates
Remotes.Events.CurrencyUpdate.OnClientEvent:Connect(function(payload)
    yenLabel.Text = string.format("Yen: %d",  payload.yen  or 0)
    gemLabel.Text = string.format("Gems: %d", payload.gems or 0)
end)

print("[UIController] Initialized.")
