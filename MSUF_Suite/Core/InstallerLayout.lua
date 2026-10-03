local _, Suite = ...
local Layout = {}
Suite.InstallerLayout = Layout
-- The supplied Modern layout was authored with a 2560-unit UIParent.
-- Move its right-hand groups to the right edge, preserving their distances
-- and dimensions rather than relying on the destination's screen width.
local MODERN_WIDTH = 2560

function Layout.Prepare(modules)
    local texts, bars = modules.dataTexts, modules.actionbars
    if texts and texts.bar1Point == 8 and texts.bar1X == 1020 then
        texts.bar1Point, texts.bar1X = 9, 0
    end
    if not bars then return end
    for _, index in ipairs({ 3, 5 }) do
        local prefix = "bar" .. index
        local sourceX = index == 3 and 2480 or 2520
        if bars[prefix .. "Point"] == 7 and bars[prefix .. "X"] == sourceX then
            local count = math.max(1, bars[prefix .. "Buttons"])
            local rows = math.min(count, math.max(1, bars[prefix .. "Rows"]))
            local columns = math.ceil(count / rows)
            local width = columns * bars[prefix .. "Size"] + (columns - 1) * bars[prefix .. "Spacing"]
            bars[prefix .. "Point"], bars[prefix .. "X"] = 9, sourceX + width - MODERN_WIDTH
        end
    end
end

local LEGACY_TEXTS = { enabled = true, bar1Enabled = true, bar1Point = 8, bar1X = 0,
    bar1Y = 170, bar1Height = 26, bar1Layout = 1, bar1FullScreen = false, bar1Dock = 1, bar1Vertical = false }
local LEGACY_METERS = { enabled = true, windowCount = 2, w1X = 0, w2X = -260,
    w1Y = 0, w2Y = 0, w1Width = 260, w2Width = 260, w1Height = 170, w2Height = 170 }
local LEGACY_MENU = { positionPreset = "custom", layoutMode = "owned", layoutPoint = "BOTTOMRIGHT",
    layoutRelativePoint = "BOTTOMRIGHT", layoutX = -522, layoutY = 0,
    orientation = "vertical", buttonsPerLine = 6, scale = 0.7, spacing = 5, padding = 5,
    buttonSize = 30, iconSize = 22, growth = "LEFT_UP" }

local function Matches(values, expected)
    if not values then return false end
    for key, value in pairs(expected) do
        if values[key] ~= value then return false end
    end
    return true
end

-- Repair only the old installer's complete, untouched paired panel.
-- A moved, resized or disabled group remains the player's choice.
function Layout.IsLegacyPanel(modules, skinProfile)
    local texts = modules and modules.dataTexts
    local menu = skinProfile and skinProfile.icons and skinProfile.icons.microMenu
    return skinProfile and skinProfile.enabled == true and Matches(texts, LEGACY_TEXTS) and texts.bar1Width == 522
        and Matches(modules.damageMeter, LEGACY_METERS) and Matches(menu, LEGACY_MENU)
end
