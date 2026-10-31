local root = assert(arg[1], "repository root required")
-- Action bar audit fixes, on the options page the player clicks: a Behavior
-- reset keeps the hidden `imported` flag (cleared, the next refresh imports
-- Blizzard's layout over every bar, Controller.lua), the reset of one bar
-- keeps its visibility (its only on/off switch) and resets the rest, the
-- recharge numbers follow the cooldown numbers, and the preview shows the
-- out-of-range color, the spell alert glow and bar 1's page arrows.
SUITE_OPTIONS_FIXTURE = true
local F = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
local M, S, NS, Suite = F.M, F.S, F.optionsNS, F.Suite
local ENUM = Suite.ActionBarEnum
local rules = S.catalog.actionbars.rules
local config = S.Config("actionbars")

local ctx = { key = "suite_actionbars", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {},
    entry = { sections = {} } }
F.SetCurrent(ctx)
M.pages.suite_actionbars.build(ctx)
for _, refresh in ipairs(ctx.refreshers) do refresh() end
local function Control(path)
    local id = "menu2.suite_actionbars.actionbars." .. path
    for _, widget in ipairs(ctx.widgets) do
        if widget.meta and widget.meta.controlId == id then return widget end
    end
    error("no control " .. id)
end
local function Section(id)
    for _, section in ipairs(ctx.sections) do
        if section.sectionId == "suite_actionbars_" .. id then return section end
    end
    error("no section " .. id)
end
local function Reset(id)
    local reset = assert(Section(id)._msufSuiteSectionReset, id .. " has no reset")
    assert(reset(), id .. " reset wrote nothing")
end

------------------------------------------------------------------ Behavior reset
assert(rules.imported.hidden, "fixture: imported is a hidden flag")
assert(S.SetMany("actionbars", { imported = true, pageArrows = true, pageArrowSide = ENUM.PAGE_ARROW_SIDE.LEFT,
    pagingModifiers = true, pageShift = 5, pickupModifier = 3 }))
Reset("behavior")
assert(config.imported == true, "a Behavior reset cleared imported: the next refresh imports Blizzard's layout again")
assert(config.pageArrows == false and config.pagingModifiers == false and config.pageShift == rules.pageShift.default
    and config.pickupModifier == rules.pickupModifier.default, "the Behavior reset left visible settings behind")
-- Button appearance keeps its hidden icon skin in the reset (no other control
-- offers the way back), so the page filters only Behavior.
assert(rules.iconSkin.hidden and S.SetMany("actionbars", { iconSkin = "CUSTOM", buttonShape = ENUM.BUTTON_SHAPE.CIRCLE }))
Reset("appearance")
assert(config.iconSkin == rules.iconSkin.default and config.buttonShape == rules.buttonShape.default,
    "the Button appearance reset no longer restores the icon skin")
-- The generic reset still resets the hidden rules it is handed: the Damage
-- Meter's gradient D-pad and the icon skins of other pages depend on it.
assert(S.SetMany("actionbars", { imported = true }))
assert(NS.ResetRules("actionbars", { rules.imported }) and config.imported == false,
    "P.ResetRules must keep resetting the hidden rules a page passes")
config.imported = true

------------------------------------------------------------------ one bar's reset
local picker = Control("editor.selected")
picker.set(3)
assert(S.SetMany("actionbars", { bar3Visibility = ENUM.VISIBILITY.NEVER, bar3ResumeVisibility = ENUM.VISIBILITY.COMBAT,
    bar3Size = 55, bar3Tooltip = ENUM.TOOLTIP.NEVER, bar3FadeDuration = .4, bar3FlyoutDirection = ENUM.FLYOUT.LEFT,
    bar3X = 77, bar4Size = 61, bar4Visibility = ENUM.VISIBILITY.ALWAYS }))
Reset("editor")
assert(config.bar3Visibility == ENUM.VISIBILITY.NEVER and config.bar3ResumeVisibility == ENUM.VISIBILITY.COMBAT,
    "the bar reset brought a switched-off bar back")
for _, suffix in ipairs({ "Size", "Tooltip", "FadeDuration", "FlyoutDirection", "X" }) do
    assert(config["bar3" .. suffix] == rules["bar3" .. suffix].default, "the bar reset kept bar3" .. suffix)
end
assert(config.bar4Size == 61 and config.bar4Visibility == ENUM.VISIBILITY.ALWAYS, "the bar reset reached another bar")
-- A bar that is on keeps its mode too.
assert(S.SetMany("actionbars", { bar3Visibility = ENUM.VISIBILITY.COMBAT, bar3Size = 48 }))
Reset("editor")
assert(config.bar3Visibility == ENUM.VISIBILITY.COMBAT and config.bar3Size == rules.bar3Size.default,
    "the bar reset changed the mode of a bar that is on")
-- The module card and the visibility section still own the way back.
assert(S.SetMany("actionbars", { bar3Visibility = ENUM.VISIBILITY.NEVER }))
Reset("bar_visibility")
assert(config.bar3Visibility == rules.bar3Visibility.default, "the visibility section reset lost its mode")
picker.set(1)

------------------------------------------------------------------ recharge numbers
assert(rules.rechargeNumbers.enableKey == "cooldownNumbers", "recharge numbers are not tied to the cooldown numbers")
assert(config.enabled and S.SetMany("actionbars", { cooldownNumbers = true }), "fixture: the module is off")
assert(NS.RuleEnabled("actionbars", rules.rechargeNumbers), "recharge numbers are off while cooldown numbers are on")
assert(S.SetMany("actionbars", { cooldownNumbers = false }))
local enabled, why = NS.RuleEnabled("actionbars", rules.rechargeNumbers, nil, true)
assert(enabled == false and why:find(NS.Tr("Show cooldown numbers"), 1, true),
    "recharge numbers stay editable without cooldown numbers: " .. tostring(why))
assert(S.SetMany("actionbars", { cooldownNumbers = true }))

------------------------------------------------------------------ preview samples
local ui = assert(ctx._msufSuiteActionBarPreview, "the page has no action bar preview")
for _, tile in ipairs(ui.tiles) do
    function tile.icon:SetVertexColor(...) self.vertex = { ... } end
    function tile.glowRing:SetVertexColor(...) self.vertex = { ... } end
end
local function Paint(values, bar)
    assert(S.SetMany("actionbars", values))
    picker.set(bar or 1)
    ui.Paint()
end
local function Same(got, hex, what)
    local r, g, b = Suite.RGB(hex)
    assert(got and math.abs(got[1] - r) < 1e-6 and math.abs(got[2] - g) < 1e-6 and math.abs(got[3] - b) < 1e-6,
        what .. " does not use the bars' color " .. hex)
end
local function EdgesShown(tile)
    for _, edge in ipairs(tile.glowEdges) do if edge.shown then return true end end
    return false
end
-- Empty bars (the stand-in has no action): the samples carry their own icon.
F.actionPreview.actions = {}
local base = { bar1Buttons = 6, bar1Rows = 1, rangeColoring = true, procGlow = ENUM.PROC_GLOW.BLIZZARD,
    buttonShape = ENUM.BUTTON_SHAPE.SQUARE, pageArrows = false, interactionClassColor = false }
Paint(base)
local range, glow, plain = ui.tiles[2], ui.tiles[3], ui.tiles[1]
assert(range.filled and range.icon.shown, "the out-of-range sample has no icon to tint")
Same(range.icon.vertex, config.rangeColor, "the out-of-range sample")
Same(plain.icon.vertex, config.usableColor, "a button in range")
assert(glow.filled and glow.alert.shown and not EdgesShown(glow) and not glow.glowRing.shown,
    "the Blizzard alert glow sample is missing")
assert(not plain.alert.shown and not range.alert.shown, "the alert glow sample reached other buttons")
assert(not plain.filled, "an empty button was filled with a sample")
Paint({ rangeColor = "12ab34" })
Same(range.icon.vertex, "12ab34", "the out-of-range sample after a color change")
Paint({ rangeColor = rules.rangeColor.default, rangeColoring = false })
Same(range.icon.vertex, config.usableColor, "a button with range coloring off")
assert(not range.filled, "the sample icon stayed with range coloring off")
-- Pixel glow: a border in the highlight color, or the ring of a shaped button.
Paint({ rangeColoring = true, procGlow = ENUM.PROC_GLOW.PIXEL, interactionColor = "f0a000" })
assert(EdgesShown(glow) and not glow.alert.shown and not glow.glowRing.shown, "the pixel glow sample is missing")
assert(glow.glowEdges[1].color[1] > 0.9 and glow.glowEdges[1].color[3] == 0, "the pixel glow ignores the highlight color")
Paint({ buttonShape = ENUM.BUTTON_SHAPE.CIRCLE })
assert(glow.glowRing.shown and not EdgesShown(glow), "a shaped button's pixel glow is not its ring")
Same(glow.glowRing.vertex, "f0a000", "the shaped pixel glow")
Paint({ buttonShape = ENUM.BUTTON_SHAPE.SQUARE, procGlow = ENUM.PROC_GLOW.NONE })
assert(not glow.alert.shown and not EdgesShown(glow) and not glow.glowRing.shown and not glow.filled,
    "the glow sample outlived the option")
-- Fewer buttons than the sample slots: the last button wears both.
Paint({ procGlow = ENUM.PROC_GLOW.BLIZZARD, bar1Buttons = 1 })
assert(plain.filled and plain.alert.shown and plain.icon.vertex[1] == Suite.RGB(config.rangeColor),
    "a one-button bar shows no samples")
-- Empty buttons that stay hidden take no sample: the buttons that show do.
F.actionPreview.actions[1], F.actionPreview.actions[5] = { icon = 135810 }, { icon = 135811 }
Paint({ bar1Buttons = 6, bar1ShowEmpty = false })
local tiles = ui.tiles
assert(tiles[1].shown and tiles[5].shown and not tiles[2].shown and not tiles[3].shown,
    "fixture: only the buttons with an action show")
Same(tiles[1].icon.vertex, config.usableColor, "the first button that shows")
Same(tiles[5].icon.vertex, config.rangeColor, "the second button that shows")
assert(tiles[5].alert.shown and not tiles[1].alert.shown, "the alert sample is not on the last button that shows")
assert(not tiles[2].filled and not tiles[3].filled, "a hidden empty button took a sample")
F.actionPreview.actions = {}
Paint({ bar1ShowEmpty = rules.bar1ShowEmpty.default })
-- Stance and pet buttons have neither state.
Paint({ bar11Buttons = 3 }, 11)
for i = 1, 3 do
    assert(not ui.tiles[i].alert.shown and not ui.tiles[i].glow, "the stance bar shows a spell alert sample")
end
Paint({ bar2Buttons = 4 }, 2)
assert(ui.tiles[2].filled and ui.tiles[3].filled, "other action bars lost the samples")

-- Page arrows hang beside bar 1 only, on the chosen side.
local function Arrows() return ui.arrows.shown and ui.arrows.points[#ui.arrows.points] end
Paint({ pageArrows = false, bar1Buttons = 6 })
assert(not ui.arrows.shown, "page arrows show while the option is off")
Paint({ pageArrows = true, pageArrowSide = ENUM.PAGE_ARROW_SIDE.RIGHT })
local point = assert(Arrows(), "page arrows are missing from the preview")
assert(point[1] == "LEFT" and point[3] == "RIGHT" and point[4] > 0, "right page arrows sit on the wrong side")
Paint({ pageArrowSide = ENUM.PAGE_ARROW_SIDE.LEFT })
point = assert(Arrows())
assert(point[1] == "RIGHT" and point[3] == "LEFT" and point[4] < 0, "left page arrows sit on the wrong side")
-- A bar that fills the preview exactly leaves no room for the arrows: they
-- shrink the fit.
local wide = math.floor((ui.width - 8) / 12)
Paint({ pageArrows = false, bar1Buttons = 12, bar1Size = wide, bar1Spacing = 0 })
assert(ui.canvas.scale == 1, "fixture: the full-width bar does not fit unscaled")
Paint({ pageArrows = true })
assert(ui.canvas.scale < 1, "the page arrows are not part of the preview's fit")
Paint({ bar2Buttons = 4 }, 2)
assert(not ui.arrows.shown, "page arrows show on another bar")

picker.set(1)
print("Action bar audit: Behavior reset, one-bar reset, recharge numbers and the preview samples passed")
