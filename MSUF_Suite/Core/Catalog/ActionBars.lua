local _, NS = ...
local B = NS.CatalogBuild
local Number, Bool, Choice, Color, Font = B.Number, B.Bool, B.Choice, B.Color, B.Font

-- Twelve bars: ten action bars with suite-owned secure buttons, then the
-- stance and pet bars, which keep Blizzard's own buttons in suite headers.
NS.ActionBarTitles = {
    "Action bar 1", "Action bar 2", "Action bar 3", "Action bar 4", "Action bar 5",
    "Action bar 6", "Action bar 7", "Action bar 8", "Action bar 9", "Action bar 10",
    "Stance bar", "Pet bar",
}
local BAR_COUNT = #NS.ActionBarTitles
NS.ActionBarCount = BAR_COUNT

local function Available()
    if type(_G.SecureHandlerSetFrameRef) ~= "function"
        or type(_G.RegisterStateDriver) ~= "function" then
        return false, "This client has no secure state drivers"
    end
    return true
end

B.Module("actionbars", {
    title = "Action bars",
    description = "Ten action bars plus stance and pet bars with free layout, paging, visibility rules and button styling. Key bindings keep using Blizzard's commands.",
    core = not NS.Client.isForever, defaultEnabled = not NS.Client.isForever,
    page = "suite_actionbars",
    conflicts = { "ElvUI", "Bartender4", "Dominos", "EllesmereUIActionBars", "ConsolePort_Bar" },
    available = Available,
})

local id = "actionbars"
local blue = {
    iconZoom = 6, borderSize = 1, borderColor = "41627a", borderClassColor = false,
    slotColor = "0a1522", slotAlpha = 50,
    highlightStyle = 1, pushedStyle = 2, interactionColor = "57c7df",
    interactionClassColor = false,
    keybindColor = "f4f7fb", macroColor = "aab5c2",
    countColor = "f4f7fb", cooldownColor = "f4f7fb",
}
local dark = {
    iconZoom = 6, borderSize = 1, borderColor = "575b58", borderClassColor = false,
    slotColor = "111315", slotAlpha = 62,
    highlightStyle = 2, pushedStyle = 2, interactionColor = "b9ab86",
    interactionClassColor = false,
    keybindColor = "e9e9e4", macroColor = "b9bdb9",
    countColor = "e9e9e4", cooldownColor = "e9e9e4",
}
local forever = {
    iconZoom = 4, borderSize = 1, borderColor = "9f8960", borderClassColor = false,
    slotColor = "111517", slotAlpha = 68,
    highlightStyle = 2, pushedStyle = 2, interactionColor = "d8b66a",
    interactionClassColor = false,
    keybindColor = "f4f3eb", macroColor = "d4dce2",
    countColor = "f4f3eb", cooldownColor = "f4f3eb",
}
NS.ActionBarLookPresets = { [1] = blue, [2] = dark, [3] = forever }
NS.ActionBarLookVisualKeys = {}
for key in pairs(dark) do NS.ActionBarLookVisualKeys[key] = true end
local initial = NS.Client.isForever and forever or dark
B.Section(id, "look", "Choose a look", {
    Choice("look", "Style preset", NS.Client.isForever and 3 or 2,
        { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Custom" }),
})
B.Section(id, "appearance", "Button appearance", {
    Number("iconZoom", "Icon zoom (percent)", initial.iconZoom, 0, 15, 0.5),
    Number("borderSize", "Button border", initial.borderSize, 0, 4),
    Color("borderColor", "Border color", initial.borderColor),
    Bool("borderClassColor", "Class-colored border", initial.borderClassColor),
    Color("slotColor", "Empty slot color", initial.slotColor),
    Number("slotAlpha", "Empty slot opacity (percent)", initial.slotAlpha, 0, 100, 5),
    Choice("highlightStyle", "Mouseover highlight", initial.highlightStyle, { "Border", "Soft fill", "Blizzard", "None" }),
    Choice("pushedStyle", "Pressed highlight", initial.pushedStyle, { "Border", "Soft fill", "Blizzard", "None" }),
    Color("interactionColor", "Highlight color", initial.interactionColor),
    Bool("interactionClassColor", "Class-colored highlights", initial.interactionClassColor),
    Bool("castHighlight", "Highlight the spell being cast", true),
    Choice("procGlow", "Spell alert glow", 1, { "Blizzard glow", "Pixel border", "None" }),
})
B.Section(id, "cooldowns", "Cooldowns and states", {
    Bool("cooldownNumbers", "Show cooldown numbers", true),
    Bool("rechargeNumbers", "Show recharge numbers while charges remain", true),
    Number("swipeAlpha", "Cooldown swipe opacity (percent)", 80, 0, 100, 5),
    Color("swipeColor", "Cooldown swipe color", "000000"),
    Bool("desaturateCooldown", "Desaturate buttons on cooldown", false),
    Number("cooldownAlpha", "Button opacity while on cooldown (percent)", 100, 0, 100, 5),
    Bool("rangeColoring", "Color out-of-range buttons", true),
    Color("rangeColor", "Out-of-range color", "cc1a1a"),
    Bool("hideEmptyCharges", "Hide the charge count at zero", false),
})
B.Section(id, "text", "Text", {
    Font("font", "Font"),
    Choice("fontOutline", "Text outline", 1, { "Outline", "Thick outline", "None" }),
    Choice("fontRendering", "Font rendering", 3, { "Smooth", "Sharp / pixel", "Slug" }),
    Bool("fontShadow", "Text shadow"),
    Number("fontShadowOpacity", "Shadow opacity (percent)", 100, 20, 100, 5),
    Choice("fontShadowDistance", "Shadow distance", 1, { "1 px", "2 px" }),
    Color("keybindColor", "Keybind color", initial.keybindColor),
    Color("macroColor", "Macro name color", initial.macroColor),
    Color("countColor", "Count color", initial.countColor),
    Color("cooldownColor", "Cooldown number color", initial.cooldownColor),
})
local textRules = NS.SuiteCatalog[id].rules
textRules.fontShadow.requiresChoice = { key = "fontRendering", values = { [1] = true, [2] = true } }
for _, key in ipairs({ "fontShadowOpacity", "fontShadowDistance" }) do
    textRules[key].enableKey = "fontShadow"
    textRules[key].requiresChoice = textRules.fontShadow.requiresChoice
end
B.Section(id, "behavior", "Behavior", {
    Bool("mouseoverShowAll", "Hovering one mouseover bar reveals all of them", false),
    Bool("showOnDrag", "Show hidden bars while dragging a spell", true),
    Bool("disableFormPaging", "Keep bar 1 on its page in stance or shapeshift forms", false),
    Bool("disableSkyridingPaging", "Keep bar 1 on its page while skyriding", false),
    Bool("pagingModifiers", "Page bar 1 with Shift, Ctrl and Alt", false),
    Number("pageShift", "Page while holding Shift", 2, 1, 6),
    Number("pageCtrl", "Page while holding Ctrl", 3, 1, 6),
    Number("pageAlt", "Page while holding Alt", 4, 1, 6),
    Bool("imported", "Blizzard layout imported", false),
})

-- Compact fallback when Blizzard has no layout to import. All bars start on
-- mouseover; importing Blizzard geometry must not replace this visibility.
local defaults = {
    { 4, 12, 1, "BOTTOM", 0, 40 }, { 4, 12, 1, "BOTTOM", 0, 82 }, { 4, 12, 1, "BOTTOM", 0, 124 },
    { 4, 12, 12, "RIGHT", -8, 0 }, { 4, 12, 12, "RIGHT", -50, 0 },
    { 4, 12, 1, "BOTTOM", 0, 166 }, { 4, 12, 1, "BOTTOM", 0, 208 }, { 4, 12, 1, "BOTTOM", 0, 250 },
    { 4, 12, 1, "BOTTOM", 0, 292 }, { 4, 12, 1, "BOTTOM", 0, 334 },
    { 4, 10, 1, "BOTTOM", -240, 170 }, { 4, 10, 1, "BOTTOM", 240, 170 },
}
local anchorLabels = { "Top left", "Top", "Top right", "Left", "Center", "Right", "Bottom left", "Bottom", "Bottom right" }
local anchorIndex = {}
for i, label in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do anchorIndex[label] = i end
NS.ActionBarAnchorPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

for i = 1, BAR_COUNT do
    local p = "bar" .. i
    local title = NS.ActionBarTitles[i]
    local d = defaults[i]
    local maxButtons = d[2]
    local special = i > 10
    B.Section(id, p, title, {
        Choice(p .. "Visibility", "Show this bar", d[1], { "Always", "In combat", "Out of combat", "Mouseover", "Mouseover or combat", "Never" }),
        Choice(p .. "ResumeVisibility", "Visibility when turned on", d[1] == 6 and 1 or d[1],
            { "Always", "In combat", "Out of combat", "Mouseover", "Mouseover or combat" }),
        Number(p .. "Alpha", "Bar opacity (percent)", 100, 0, 100, 5),
        Number(p .. "FadeAlpha", "Opacity without mouseover (percent)", 0, 0, 100, 5),
        Number(p .. "Buttons", "Buttons", maxButtons, 1, maxButtons),
        Number(p .. "Rows", "Rows", d[3] > 1 and d[3] or 1, 1, maxButtons),
        Number(p .. "Size", "Button size", special and 30 or 40, 16, 80),
        Number(p .. "Spacing", "Button spacing", 2, -10, 20),
        Bool(p .. "Vertical", "Fill columns first", d[3] > 1),
        Choice(p .. "Start", "First button corner", 1, { "Top left", "Top right", "Bottom left", "Bottom right" }),
        Bool(p .. "ShowEmpty", "Show empty buttons", not special),
        Bool(p .. "ClickThrough", "Click through", false),
        Choice(p .. "Point", "Screen anchor", anchorIndex[d[4]], anchorLabels),
        Number(p .. "X", "Horizontal position", d[5], -4000, 4000),
        Number(p .. "Y", "Vertical position", d[6], -3000, 3000),
        Bool(p .. "Keybind", "Show keybinds", true),
        Number(p .. "KeybindSize", "Keybind size", special and 10 or 12, 6, 30),
        Bool(p .. "Macro", "Show macro names", not special),
        Number(p .. "MacroSize", "Macro name size", 10, 6, 30),
        Number(p .. "CountSize", "Count size", 14, 6, 30),
        Number(p .. "CooldownSize", "Cooldown number size", special and 12 or 16, 6, 30),
        Bool(p .. "Background", "Bar background", false),
        Color(p .. "BackgroundColor", "Background color", "000000"),
        Number(p .. "BackgroundAlpha", "Background opacity (percent)", 50, 0, 100, 5),
        Number(p .. "BackgroundPadding", "Background padding", 4, 0, 24),
    }, { bar = i })
end

local rules = NS.SuiteCatalog.actionbars.rules
rules.imported.hidden = true
rules.borderColor.disabledBy = "borderClassColor"
rules.interactionColor.disabledBy = "interactionClassColor"
rules.rangeColor.enableKey = "rangeColoring"
for _, key in ipairs({ "pageShift", "pageCtrl", "pageAlt" }) do rules[key].enableKey = "pagingModifiers" end
for i = 1, BAR_COUNT do
    local p = "bar" .. i
    rules[p .. "ResumeVisibility"].hidden = true
    rules[p .. "FadeAlpha"].requiresChoice = { key = p .. "Visibility", values = { [4] = true, [5] = true } }
    rules[p .. "KeybindSize"].enableKey = p .. "Keybind"
    rules[p .. "MacroSize"].enableKey = p .. "Macro"
    for _, suffix in ipairs({ "BackgroundColor", "BackgroundAlpha", "BackgroundPadding" }) do rules[p .. suffix].enableKey = p .. "Background" end
    for _, suffix in ipairs({ "Point", "X", "Y" }) do rules[p .. suffix].category = "advanced" end
    if i > 10 then
        -- Blizzard's stance and pet buttons have no macro names.
        rules[p .. "Macro"].hidden, rules[p .. "MacroSize"].hidden = true, true
    end
end
