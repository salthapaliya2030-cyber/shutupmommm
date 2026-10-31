-- ============================================================
-- ScreenConfigs.lua  |  graphics/ui/
-- Declarative layout configuration for all UI screens.
-- UIController.lua reads these specs to build and validate
-- frame positions. All values use relative UDim2 coordinates.
-- Anchor validation routine runs on ScreenGui load to prevent
-- component drift during resolution changes.
-- ============================================================

local ScreenConfigs = {}

-- ─────────────────────────────────────────────────────────────
-- LAYOUT SPEC FORMAT
-- Each entry describes one UI element:
--   anchorPoint  : Vector2  – pivot point (0-1, 0-1)
--   position     : {xs, xo, ys, yo}  – UDim2 scale + offset
--   size         : {xs, xo, ys, yo}
--   zIndex       : integer
--   aspectRatio  : number|nil  – if set, UIAspectRatioConstraint applied
-- ─────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────
-- MAIN MENU SCREEN
-- ─────────────────────────────────────────────────────────────
ScreenConfigs.MainMenu = {
    -- Currency panel: top left corner
    CurrencyPanel = {
        anchorPoint = Vector2.new(0, 0),
        position    = { xs = 0.01, xo = 0, ys = 0.01, yo = 0 },
        size        = { xs = 0.18, xo = 0, ys = 0.08, yo = 0 },
        zIndex      = 5,
    },

    -- Yen label: top of currency panel
    YenLabel = {
        anchorPoint = Vector2.new(0, 0),
        position    = { xs = 0, xo = 0, ys = 0, yo = 0 },
        size        = { xs = 1,  xo = 0, ys = 0.50, yo = 0 },
        zIndex      = 6,
    },

    -- Gem label: bottom of currency panel
    GemLabel = {
        anchorPoint = Vector2.new(0, 0),
        position    = { xs = 0, xo = 0, ys = 0.5, yo = 0 },
        size        = { xs = 1,  xo = 0, ys = 0.50, yo = 0 },
        zIndex      = 6,
    },

    -- Play button: dead center of screen
    PlayButton = {
        anchorPoint = Vector2.new(0.5, 0.5),
        position    = { xs = 0.5, xo = 0, ys = 0.42, yo = 0 },
        size        = { xs = 0.22, xo = 0, ys = 0.10, yo = 0 },
        zIndex      = 5,
    },

    -- Navigation bar: absolute bottom center
    NavBar = {
        anchorPoint = Vector2.new(0.5, 1.0),
        position    = { xs = 0.5, xo = 0, ys = 0.95, yo = 0 },
        size        = { xs = 0.36, xo = 0, ys = 0.09, yo = 0 },
        zIndex      = 5,
    },

    -- Inventory button: left slot of nav bar
    InventoryBtn = {
        anchorPoint = Vector2.new(0, 0.5),
        size        = { xs = 0.3, xo = 0, ys = 0.85, yo = 0 },
        layoutOrder = 1,
        zIndex      = 6,
    },

    -- Settings button: center slot
    SettingsBtn = {
        anchorPoint = Vector2.new(0, 0.5),
        size        = { xs = 0.3, xo = 0, ys = 0.85, yo = 0 },
        layoutOrder = 2,
        zIndex      = 6,
    },

    -- Style rolling button: right slot
    RollingBtn = {
        anchorPoint = Vector2.new(0, 0.5),
        size        = { xs = 0.3, xo = 0, ys = 0.85, yo = 0 },
        layoutOrder = 3,
        zIndex      = 6,
    },
}

-- ─────────────────────────────────────────────────────────────
-- GACHA MODAL
-- ─────────────────────────────────────────────────────────────
ScreenConfigs.GachaModal = {
    Modal = {
        anchorPoint = Vector2.new(0.5, 0.5),
        position    = { xs = 0.5, xo = 0, ys = 0.5, yo = 0 },
        size        = { xs = 0.55, xo = 0, ys = 0.80, yo = 0 },
        zIndex      = 50,
    },

    -- Gacha wheel: circular via UIAspectRatioConstraint (1:1)
    GachaWheel = {
        anchorPoint = Vector2.new(0.5, 0.5),
        position    = { xs = 0.5, xo = 0, ys = 0.38, yo = 0 },
        size        = { xs = 0.55, xo = 0, ys = 0, yo = 0 },  -- height driven by aspect ratio
        aspectRatio = 1.0,   -- enforces circle
        zIndex      = 51,
    },

    SpinYenBtn = {
        anchorPoint = Vector2.new(0, 0),
        position    = { xs = 0.06, xo = 0, ys = 0.78, yo = 0 },
        size        = { xs = 0.38, xo = 0, ys = 0.10, yo = 0 },
        zIndex      = 51,
    },

    SpinGemBtn = {
        anchorPoint = Vector2.new(1, 0),
        position    = { xs = 0.94, xo = 0, ys = 0.78, yo = 0 },
        size        = { xs = 0.38, xo = 0, ys = 0.10, yo = 0 },
        zIndex      = 51,
    },

    CloseBtn = {
        anchorPoint = Vector2.new(1, 0),
        position    = { xs = 0.97, xo = 0, ys = 0.02, yo = 0 },
        size        = { xs = 0.09, xo = 0, ys = 0.07, yo = 0 },
        zIndex      = 52,
    },
}

-- ─────────────────────────────────────────────────────────────
-- MATCH HUD
-- ─────────────────────────────────────────────────────────────
ScreenConfigs.MatchHUD = {
    -- Score: absolute top center
    ScorePanel = {
        anchorPoint = Vector2.new(0.5, 0),
        position    = { xs = 0.5, xo = 0, ys = 0.01, yo = 0 },
        size        = { xs = 0.32, xo = 0, ys = 0.08, yo = 0 },
        zIndex      = 10,
    },

    -- Ability icon: absolute bottom right, circular
    AbilityPanel = {
        anchorPoint = Vector2.new(1, 1),
        position    = { xs = 0.97, xo = 0, ys = 0.97, yo = 0 },
        size        = { xs = 0.09, xo = 0, ys = 0, yo = 0 },
        aspectRatio = 1.0,  -- enforces perfect circle
        zIndex      = 10,
    },

    -- Touch counter indicator (small, under score)
    TouchCounter = {
        anchorPoint = Vector2.new(0.5, 0),
        position    = { xs = 0.5, xo = 0, ys = 0.10, yo = 0 },
        size        = { xs = 0.12, xo = 0, ys = 0.04, yo = 0 },
        zIndex      = 10,
    },

    -- Set score tracker (small, below main score)
    SetTracker = {
        anchorPoint = Vector2.new(0.5, 0),
        position    = { xs = 0.5, xo = 0, ys = 0.10, yo = 0 },
        size        = { xs = 0.20, xo = 0, ys = 0.035, yo = 0 },
        zIndex      = 10,
    },
}

-- ─────────────────────────────────────────────────────────────
-- MATCH SETUP PROMPT
-- ─────────────────────────────────────────────────────────────
ScreenConfigs.MatchSetup = {
    Modal = {
        anchorPoint = Vector2.new(0.5, 0.5),
        position    = { xs = 0.5, xo = 0, ys = 0.5, yo = 0 },
        size        = { xs = 0.55, xo = 0, ys = 0.65, yo = 0 },
        zIndex      = 30,
    },

    -- Left column: team selection (50% width of modal)
    TeamColumn = {
        anchorPoint = Vector2.new(0, 0),
        position    = { xs = 0.02, xo = 0, ys = 0.14, yo = 0 },
        size        = { xs = 0.44, xo = 0, ys = 0.62, yo = 0 },
        zIndex      = 31,
    },

    -- Right column: position selection
    PositionColumn = {
        anchorPoint = Vector2.new(0, 0),
        position    = { xs = 0.54, xo = 0, ys = 0.14, yo = 0 },
        size        = { xs = 0.44, xo = 0, ys = 0.62, yo = 0 },
        zIndex      = 31,
    },

    -- Team A button
    TeamABtn = {
        anchorPoint = Vector2.new(0, 0),
        position    = { xs = 0.075, xo = 0, ys = 0.18, yo = 0 },
        size        = { xs = 0.85, xo = 0, ys = 0.28, yo = 0 },
        zIndex      = 32,
    },

    -- Team B button
    TeamBBtn = {
        anchorPoint = Vector2.new(0, 0),
        position    = { xs = 0.075, xo = 0, ys = 0.52, yo = 0 },
        size        = { xs = 0.85, xo = 0, ys = 0.28, yo = 0 },
        zIndex      = 32,
    },

    -- Position buttons (evenly stacked)
    SpikerBtn = {
        size = { xs = 0.85, xo = 0, ys = 0.22, yo = 0 },
        position = { xs = 0.075, xo = 0, ys = 0.18, yo = 0 },
        zIndex = 32,
    },
    SetterBtn = {
        size = { xs = 0.85, xo = 0, ys = 0.22, yo = 0 },
        position = { xs = 0.075, xo = 0, ys = 0.42, yo = 0 },
        zIndex = 32,
    },
    LiberoBtn = {
        size = { xs = 0.85, xo = 0, ys = 0.22, yo = 0 },
        position = { xs = 0.075, xo = 0, ys = 0.66, yo = 0 },
        zIndex = 32,
    },

    -- Join button: absolute bottom center of modal
    JoinBtn = {
        anchorPoint = Vector2.new(0.5, 1.0),
        position    = { xs = 0.5, xo = 0, ys = 0.92, yo = 0 },
        size        = { xs = 0.50, xo = 0, ys = 0.10, yo = 0 },
        zIndex      = 32,
    },

    -- Error text: bottom of modal
    ErrorText = {
        anchorPoint = Vector2.new(0.5, 0),
        position    = { xs = 0.05, xo = 0, ys = 0.88, yo = 0 },
        size        = { xs = 0.90, xo = 0, ys = 0.08, yo = 0 },
        zIndex      = 33,
    },
}

-- ─────────────────────────────────────────────────────────────
-- ANCHOR VALIDATION ROUTINE
-- Called on ScreenGui load and on AbsoluteSize change.
-- Ensures no element has drifted outside [0,1] scale range.
-- ─────────────────────────────────────────────────────────────
function ScreenConfigs.validateAnchors(screenGui)
    local violations = {}

    for _, frame in ipairs(screenGui:GetDescendants()) do
        if frame:IsA("GuiObject") then
            -- Check position scale values are in [0, 1]
            local px = frame.Position.X.Scale
            local py = frame.Position.Y.Scale

            if px < 0 or px > 1 or py < 0 or py > 1 then
                table.insert(violations, {
                    name = frame:GetFullName(),
                    issue = string.format("Position out of range: (%.2f, %.2f)", px, py),
                })
            end

            -- Check size scale values are non-negative
            local sx = frame.Size.X.Scale
            local sy = frame.Size.Y.Scale
            if sx < 0 or sy < 0 then
                table.insert(violations, {
                    name  = frame:GetFullName(),
                    issue = string.format("Negative size scale: (%.2f, %.2f)", sx, sy),
                })
            end

            -- Check AspectRatioConstraint exists on circular elements
            local isCircular = frame:GetAttribute("RequiresAspectRatio")
            if isCircular and not frame:FindFirstChildOfClass("UIAspectRatioConstraint") then
                table.insert(violations, {
                    name  = frame:GetFullName(),
                    issue = "Missing UIAspectRatioConstraint on circular element",
                })
                -- Auto-fix
                local arc = Instance.new("UIAspectRatioConstraint", frame)
                arc.AspectRatio = 1.0
            end
        end
    end

    if #violations > 0 then
        warn("[ScreenConfigs] Anchor validation found " .. #violations .. " issue(s):")
        for _, v in ipairs(violations) do
            warn("  " .. v.name .. ": " .. v.issue)
        end
    else
        print("[ScreenConfigs] All anchor positions validated OK.")
    end

    return violations
end

return ScreenConfigs
