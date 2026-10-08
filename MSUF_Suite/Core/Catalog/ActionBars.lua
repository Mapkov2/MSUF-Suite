local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_ActionBars")
local Number, Bool, Choice, Color = B.Number, B.Bool, B.Choice, B.Color

-- Twelve bars: ten action bars with suite-owned secure buttons, then the
-- stance and pet bars, which keep Blizzard's own buttons in suite headers.
NS.ActionBarTitles = {
    "Action bar 1", "Action bar 2", "Action bar 3", "Action bar 4", "Action bar 5",
    "Action bar 6", "Action bar 7", "Action bar 8", "Action bar 9", "Action bar 10",
    "Stance bar", "Pet bar",
}
local BAR_COUNT = #NS.ActionBarTitles
NS.ActionBarCount = BAR_COUNT
-- Shared by the runtime and the menu's live preview, including extra bars.
NS.ActionBarFirstSlots = { 1, 61, 49, 25, 37, 145, 157, 169, 13, 109 }
NS.ActionBarCommands = { "ACTIONBUTTON", "MULTIACTIONBAR1BUTTON", "MULTIACTIONBAR2BUTTON", "MULTIACTIONBAR3BUTTON",
    "MULTIACTIONBAR4BUTTON", "MULTIACTIONBAR5BUTTON", "MULTIACTIONBAR6BUTTON", "MULTIACTIONBAR7BUTTON",
    "MSUFSUITE_BAR9_BUTTON", "MSUFSUITE_BAR10_BUTTON", "SHAPESHIFTBUTTON", "BONUSACTIONBUTTON" }

-- The named values of the bar choices (each is the saved index of the
-- choice's label list) and the bar numbers: bar 1 is Blizzard's main bar,
-- bars FIRST_NATIVE to LAST_NATIVE reuse Blizzard's own multibar buttons,
-- bars from FIRST_EXTRA on have no Blizzard counterpart bar, bars up to
-- LAST_ACTION have suite-owned buttons, then stance and pet.
local ENUM = {
    VISIBILITY = { ALWAYS = 1, COMBAT = 2, OUT_OF_COMBAT = 3, MOUSEOVER = 4, MOUSEOVER_OR_COMBAT = 5, NEVER = 6 },
    PROC_GLOW = { BLIZZARD = 1, PIXEL = 2, NONE = 3 },
    BUTTON_SHAPE = { SQUARE = 1, CIRCLE = 2 },
    BORDER_ART = { PIXEL = 1, BLIZZARD = 2 },
    ASSIST_STYLE = { BLIZZARD = 1, RING = 2, FILL = 3, RING_AND_FILL = 4 },
    -- "Mouseover highlight" and "Pressed highlight".
    HIGHLIGHT = { BORDER = 1, FILL = 2, BLIZZARD = 3, NONE = 4 },
    ENDCAP = { NONE = 1, DIAMOND = 2, CHEVRONS = 3 },
    PAGE_ARROW_SIDE = { LEFT = 1, RIGHT = 2 },
    -- "First button corner": the corner button 1 sits in.
    START = { TOP_LEFT = 1, TOP_RIGHT = 2, BOTTOM_LEFT = 3, BOTTOM_RIGHT = 4 },
    LOOK = { MIDNIGHT_BLUE = 1, MIDNIGHT_DARK = 2, FOREVER = 3, CUSTOM = 4, CLEAN_MODERN = 5, CLASS_STYLE = 6 },
    BAR = { MAIN = 1, FIRST_NATIVE = 2, LAST_NATIVE = 8, FIRST_EXTRA = 9, LAST_ACTION = 10, STANCE = 11, PET = 12 },
}
NS.ActionBarEnum = ENUM

-- The bar layout, in the core so the options preview draws it without the
-- action bar addon (MSUF_Suite_ActionBars/Bars.lua AB.Grid and AB.Cell are
-- the runtime's copy). n buttons, R = clamp(rows). Rows first: perRow =
-- ceil(n/R), rows = ceil(n/perRow). Columns first: perColumn = R,
-- columns = ceil(n/R), rows = min(R, n). Returns columns, rows, R.
function NS.ActionBarGrid(n, rows, vertical)
    n = math.max(1, math.floor(n))
    local r = math.min(math.max(math.floor(rows), 1), n)
    if vertical then return math.ceil(n / r), math.min(r, n), r end
    local per = math.ceil(n / r)
    return per, math.ceil(n / per), r
end
-- Cell of 0-based button i. Row 0 is the top row and column 0 the left
-- column for "Top left"; a right corner mirrors the columns, a bottom corner
-- the rows.
function NS.ActionBarCell(i, columns, rows, r, vertical, start)
    local col, row
    if vertical then
        row, col = i % r, math.floor(i / r)
    else
        col, row = i % columns, math.floor(i / columns)
    end
    local START = ENUM.START
    if start == START.TOP_RIGHT or start == START.BOTTOM_RIGHT then col = columns - 1 - col end
    if start == START.BOTTOM_LEFT or start == START.BOTTOM_RIGHT then row = rows - 1 - row end
    return col, row
end
local VISIBILITY, HIGHLIGHT, LOOK = ENUM.VISIBILITY, ENUM.HIGHLIGHT, ENUM.LOOK

-- No client check: Blizzard_RestrictedAddOnEnvironment (secure handlers and
-- state drivers) loads on Retail and on Forever.
B.Module("actionbars", {
    title = "Action bars",
    description = "Ten action bars plus stance and pet bars with free layout, paging, visibility rules and button styling. Key bindings keep using Blizzard's commands.",
    core = true, defaultEnabled = true,
    page = "suite_actionbars",
    conflicts = { "ElvUI", "Bartender4", "Dominos", "EllesmereUIActionBars", "ConsolePort_Bar" },
    summary = "look barVisibility barButtons barRows barCooldownSize barKeybind barBackground"
        .. " barBackgroundAlpha pickupModifier cooldownNumbers rangeColoring iconZoom borderSize",
})

local id = "actionbars"
local blue = {
    iconZoom = 6, borderSize = 1, borderColor = "41627a", borderClassColor = false,
    slotColor = "0a1522", slotAlpha = 50,
    highlightStyle = HIGHLIGHT.BORDER, pushedStyle = HIGHLIGHT.FILL, interactionColor = "57c7df",
    interactionClassColor = false,
    keybindColor = "f4f7fb", macroColor = "aab5c2",
    countColor = "f4f7fb", cooldownColor = "f4f7fb",
}
local dark = {
    iconZoom = 6, borderSize = 1, borderColor = "575b58", borderClassColor = false,
    slotColor = "111315", slotAlpha = 62,
    highlightStyle = HIGHLIGHT.FILL, pushedStyle = HIGHLIGHT.FILL, interactionColor = "b9ab86",
    interactionClassColor = false,
    keybindColor = "e9e9e4", macroColor = "b9bdb9",
    countColor = "e9e9e4", cooldownColor = "e9e9e4",
}
local forever = {
    iconZoom = 4, borderSize = 1, borderColor = "9f8960", borderClassColor = false,
    slotColor = "111517", slotAlpha = 68,
    highlightStyle = HIGHLIGHT.FILL, pushedStyle = HIGHLIGHT.FILL, interactionColor = "d8b66a",
    interactionClassColor = false,
    keybindColor = "f4f3eb", macroColor = "d4dce2",
    countColor = "f4f3eb", cooldownColor = "f4f3eb",
}
local cleanModern = {
    iconZoom = 6, borderSize = 1, borderColor = "333333", borderClassColor = false,
    slotColor = "101010", slotAlpha = 62,
    highlightStyle = HIGHLIGHT.FILL, pushedStyle = HIGHLIGHT.FILL, interactionColor = "e6ecf2",
    interactionClassColor = false,
    keybindColor = "f5f5f5", macroColor = "bfc4c9",
    countColor = "f5f5f5", cooldownColor = "f5f5f5",
}
NS.ActionBarLookPresets = { [LOOK.MIDNIGHT_BLUE] = blue, [LOOK.MIDNIGHT_DARK] = dark, [LOOK.FOREVER] = forever,
    [LOOK.CLEAN_MODERN] = cleanModern }
NS.ActionBarLookPresets[LOOK.CLASS_STYLE] = B.ClassPreset(cleanModern, { borderColor = "border", interactionColor = "accent" })
NS.ActionBarLookVisualKeys = {}
for key in pairs(dark) do NS.ActionBarLookVisualKeys[key] = true end
NS.SuiteCatalog[id].look = {
    key = "look", presets = NS.ActionBarLookPresets, visualKeys = NS.ActionBarLookVisualKeys,
    custom = LOOK.CUSTOM, global = true,
    -- A global look also tints every bar background in its palette.
    extra = function(values, lookIndex)
        local background = NS.DataTextLooks[lookIndex].background
        for bar = 1, NS.ActionBarCount do values["bar" .. bar .. "BackgroundColor"] = background end
    end,
}
local initial = NS.Client.isForever and forever or dark
B.Section(id, "look", "Choose a look", {
    Choice("look", "Style preset", NS.Client.isForever and LOOK.FOREVER or LOOK.MIDNIGHT_DARK,
        { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Custom", "Clean Modern", "Class Style" }),
})
B.Section(id, "appearance", "Button appearance", {
    Choice("buttonShape", "Button shape", ENUM.BUTTON_SHAPE.SQUARE, { "Square", "Circle" }),
    Choice("borderArt", "Button frame style", ENUM.BORDER_ART.PIXEL, { "Pixel border", "Blizzard frame" }),
    Number("borderScale", "Button frame scale (percent)", 100, 70, 160, 5),
    Number("borderExpansion", "Button frame expansion", 0, -8, 20),
    -- Blizzard's own highlight reaches only Blizzard's buttons, which bar 1
    -- does not reuse; the Suite's ring covers every bar.
    Choice("assistStyle", "Rotation recommendation", ENUM.ASSIST_STYLE.RING, { "Blizzard", "Ring", "Fill", "Ring and fill" }),
    Color("assistColor", "Recommendation color", "f5d35c"),
    Number("assistAlpha", "Recommendation opacity (percent)", 100, 0, 100, 5),
    Number("assistExpansion", "Recommendation expansion", 2, -8, 20),
    Number("assistX", "Recommendation horizontal offset", 0, -30, 30),
    Number("assistY", "Recommendation vertical offset", 0, -30, 30),
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
    Choice("procGlow", "Spell alert glow", ENUM.PROC_GLOW.BLIZZARD, { "Blizzard glow", "Pixel border", "None" }),
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
B.TextSection(id, {
    Color("keybindColor", "Keybind color", initial.keybindColor),
    Color("macroColor", "Macro name color", initial.macroColor),
    Color("countColor", "Count color", initial.countColor),
    Color("cooldownColor", "Cooldown number color", initial.cooldownColor),
})
B.Section(id, "behavior", "Behavior", {
    Choice("pickupModifier", "Move actions while holding (all action bars)", 1,
        { "Use Blizzard setting", "Shift", "Ctrl", "Alt", "No modifier" }),
    Bool("mouseoverShowAll", "Hovering one mouseover bar reveals all of them", false),
    Bool("showOnPanels", "Show bars while spellbook or macros are open", false),
    Bool("showOnDrag", "Show hidden bars while dragging a spell", true),
    Bool("disableFormPaging", "Keep bar 1 on its page in stance or shapeshift forms", false),
    Bool("disableSkyridingPaging", "Keep bar 1 on its page while skyriding", false),
    Bool("pageArrows", "Show page arrows beside bar 1", false),
    Choice("pageArrowSide", "Page arrow side", ENUM.PAGE_ARROW_SIDE.RIGHT, { "Left", "Right" }),
    Bool("pagingTarget", "Page bar 1 by friendly or hostile target", false),
    Number("pageFriendly", "Page for friendly target", 1, 1, 6),
    Number("pageHostile", "Page for hostile target", 2, 1, 6),
    Bool("pagingModifiers", "Page bar 1 with Shift, Ctrl and Alt", false),
    Number("pageShift", "Page while holding Shift", 2, 1, 6),
    Number("pageCtrl", "Page while holding Ctrl", 3, 1, 6),
    Number("pageAlt", "Page while holding Alt", 4, 1, 6),
    Bool("imported", "Blizzard layout imported", false),
})

-- Compact fallback when Blizzard has no layout to import. All bars start on
-- mouseover; importing Blizzard geometry must not replace this visibility.
local MOUSEOVER = VISIBILITY.MOUSEOVER
local defaults = {
    { MOUSEOVER, 12, 1, "BOTTOM", 0, 40 }, { MOUSEOVER, 12, 1, "BOTTOM", 0, 82 }, { MOUSEOVER, 12, 1, "BOTTOM", 0, 124 },
    { MOUSEOVER, 12, 12, "RIGHT", -8, 0 }, { MOUSEOVER, 12, 12, "RIGHT", -50, 0 },
    { MOUSEOVER, 12, 1, "BOTTOM", 0, 166 }, { MOUSEOVER, 12, 1, "BOTTOM", 0, 208 }, { MOUSEOVER, 12, 1, "BOTTOM", 0, 250 },
    { MOUSEOVER, 12, 1, "BOTTOM", 0, 292 }, { MOUSEOVER, 12, 1, "BOTTOM", 0, 334 },
    { MOUSEOVER, 10, 1, "BOTTOM", -240, 170 }, { MOUSEOVER, 10, 1, "BOTTOM", 240, 170 },
}
local anchorIndex = {}
for i, point in ipairs(NS.AnchorPoints) do anchorIndex[point] = i end
ENUM.POINT = { CENTER = anchorIndex.CENTER }
NS.ActionBarAnchorPoints = NS.AnchorPoints
local TEXT_ANCHORS = { "Default" }
for _, label in ipairs(NS.AnchorLabels) do TEXT_ANCHORS[#TEXT_ANCHORS + 1] = label end

for i = 1, BAR_COUNT do
    local p = "bar" .. i
    local title = NS.ActionBarTitles[i]
    local d = defaults[i]
    local maxButtons = d[2]
    local special = i > ENUM.BAR.LAST_ACTION
    B.Section(id, p, title, {
        Choice(p .. "Visibility", "Show this bar", d[1],
            { "Always", "In combat", "Out of combat", "Mouseover", "Mouseover or combat", "Never" }),
        Bool(p .. "HideGamepad", "Hide with an active connected gamepad (Forever)"),
        Choice(p .. "ResumeVisibility", "Visibility when turned on", d[1] == VISIBILITY.NEVER and VISIBILITY.ALWAYS or d[1],
            { "Always", "In combat", "Out of combat", "Mouseover", "Mouseover or combat" }),
        Number(p .. "Alpha", "Bar opacity (percent)", 100, 0, 100, 5),
        Number(p .. "FadeAlpha", "Opacity without mouseover (percent)", 0, 0, 100, 5),
        Number(p .. "Layer", "MSUF layer (-1 = Auto)", -1, -1, 30),
        Number(p .. "Buttons", "Buttons", maxButtons, 1, maxButtons),
        Number(p .. "Rows", "Rows", d[3] > 1 and d[3] or 1, 1, maxButtons),
        Number(p .. "Size", "Button size", special and 30 or 40, 16, 80),
        Number(p .. "Spacing", "Button spacing", 2, -10, 20),
        Bool(p .. "Vertical", "Fill columns first", d[3] > 1),
        Choice(p .. "Start", "First button corner", ENUM.START.TOP_LEFT, { "Top left", "Top right", "Bottom left", "Bottom right" }),
        Bool(p .. "ShowEmpty", "Show empty buttons", not special),
        Bool(p .. "ClickThrough", "Click through", false),
        Choice(p .. "Point", "Screen anchor", anchorIndex[d[4]], NS.AnchorLabels),
        Number(p .. "X", "Horizontal position", d[5], -4000, 4000),
        Number(p .. "Y", "Vertical position", d[6], -3000, 3000),
        Bool(p .. "Keybind", "Show keybinds", true),
        Number(p .. "KeybindSize", "Keybind size", special and 10 or 12, 6, 30),
        Bool(p .. "Macro", "Show macro names", not special),
        Number(p .. "MacroSize", "Macro name size", 10, 6, 30),
        Number(p .. "CountSize", "Count size", 14, 6, 30),
        Number(p .. "CooldownSize", "Cooldown number size", special and 12 or 16, 6, 30),
        Bool(p .. "CooldownAutoSize", "Fit cooldown text to button", true),
        Choice(p .. "KeybindPoint", "Keybind anchor", 1, TEXT_ANCHORS),
        Number(p .. "KeybindX", "Keybind horizontal offset", 0, -80, 80),
        Number(p .. "KeybindY", "Keybind vertical offset", 0, -80, 80),
        Choice(p .. "MacroPoint", "Macro name anchor", 1, TEXT_ANCHORS),
        Number(p .. "MacroX", "Macro name horizontal offset", 0, -80, 80),
        Number(p .. "MacroY", "Macro name vertical offset", 0, -80, 80),
        Choice(p .. "CountPoint", "Count anchor", 1, TEXT_ANCHORS),
        Number(p .. "CountX", "Count horizontal offset", 0, -80, 80),
        Number(p .. "CountY", "Count vertical offset", 0, -80, 80),
        Choice(p .. "CooldownPoint", "Cooldown number anchor", 1, TEXT_ANCHORS),
        Number(p .. "CooldownX", "Cooldown number horizontal offset", 0, -80, 80),
        Number(p .. "CooldownY", "Cooldown number vertical offset", 0, -80, 80),
        Choice(p .. "LeftEndcap", "Left endcap", ENUM.ENDCAP.NONE, { "None", "Diamond", "Chevrons" }),
        Number(p .. "LeftEndcapSize", "Left endcap size", 32, 8, 120),
        Number(p .. "LeftEndcapX", "Left endcap horizontal offset", 0, -200, 200),
        Number(p .. "LeftEndcapY", "Left endcap vertical offset", 0, -200, 200),
        Choice(p .. "RightEndcap", "Right endcap", ENUM.ENDCAP.NONE, { "None", "Diamond", "Chevrons" }),
        Number(p .. "RightEndcapSize", "Right endcap size", 32, 8, 120),
        Number(p .. "RightEndcapX", "Right endcap horizontal offset", 0, -200, 200),
        Number(p .. "RightEndcapY", "Right endcap vertical offset", 0, -200, 200),
        Bool(p .. "Background", "Bar background", false),
        Color(p .. "BackgroundColor", "Background color", "000000"),
        Number(p .. "BackgroundAlpha", "Background opacity (percent)", 50, 0, 100, 5),
        Number(p .. "BackgroundPadding", "Background padding", 4, 0, 24),
        Number(p .. "BackgroundPaddingX", "Horizontal padding (-1 = shared)", -1, -1, 80),
        Number(p .. "BackgroundPaddingY", "Vertical padding (-1 = shared)", -1, -1, 80),
        Number(p .. "BackgroundX", "Background horizontal offset", 0, -80, 80),
        Number(p .. "BackgroundY", "Background vertical offset", 0, -80, 80),
        Number(p .. "BackgroundBorder", "Background border thickness", 0, 0, 4),
    }, { bar = i })
end

local rules = NS.SuiteCatalog.actionbars.rules
rules.imported.hidden = true
rules.disableSkyridingPaging.hidden = NS.Client.isForever or nil
rules.borderColor.disabledBy = "borderClassColor"
rules.interactionColor.disabledBy = "interactionClassColor"
rules.rangeColor.enableKey = "rangeColoring"
-- Assisted combat exists on Retail only (Forever's Camelot UI has none:
-- InterfaceOverrides.HasAssistedCombat() is false there), so Forever hides
-- the recommendation options. The look options need a Suite style.
local ASSIST_LOOK = { assistColor = true, assistAlpha = true, assistExpansion = true, assistX = true, assistY = true }
rules.assistStyle.hidden = NS.Client.isForever or nil
for key in pairs(ASSIST_LOOK) do
    rules[key].hidden = NS.Client.isForever or nil
    rules[key].requiresChoice = { key = "assistStyle", values = { [ENUM.ASSIST_STYLE.RING] = true, [ENUM.ASSIST_STYLE.FILL] = true,
        [ENUM.ASSIST_STYLE.RING_AND_FILL] = true } }
end
for _, key in ipairs({ "pageShift", "pageCtrl", "pageAlt" }) do rules[key].enableKey = "pagingModifiers" end
for _, key in ipairs({ "pageFriendly", "pageHostile" }) do rules[key].enableKey = "pagingTarget" end
rules.pageArrowSide.enableKey = "pageArrows"
for i = 1, BAR_COUNT do
    local p = "bar" .. i
    rules[p .. "ResumeVisibility"].hidden = true
    -- Only Forever has a gamepad interface to hide bars for
    -- (InputUtil.IsGamepadUIEnabled); Retail never applies the option.
    rules[p .. "HideGamepad"].hidden = not NS.Client.isForever or nil
    rules[p .. "FadeAlpha"].requiresChoice = { key = p .. "Visibility",
        values = { [VISIBILITY.MOUSEOVER] = true, [VISIBILITY.MOUSEOVER_OR_COMBAT] = true } }
    rules[p .. "KeybindSize"].enableKey = p .. "Keybind"
    rules[p .. "MacroSize"].enableKey = p .. "Macro"
    for _, suffix in ipairs({ "BackgroundColor", "BackgroundAlpha", "BackgroundPadding", "BackgroundPaddingX",
        "BackgroundPaddingY", "BackgroundX", "BackgroundY", "BackgroundBorder" }) do
        rules[p .. suffix].enableKey = p .. "Background"
    end
    -- An endcap's size and offsets apply once it has a shape.
    for _, side in ipairs({ "Left", "Right" }) do
        for _, suffix in ipairs({ "EndcapSize", "EndcapX", "EndcapY" }) do
            rules[p .. side .. suffix].requiresChoice = { key = p .. side .. "Endcap",
                values = { [ENUM.ENDCAP.DIAMOND] = true, [ENUM.ENDCAP.CHEVRONS] = true } }
        end
    end
    for _, suffix in ipairs({ "Point", "X", "Y" }) do rules[p .. suffix].category = "advanced" end
    if i > ENUM.BAR.LAST_ACTION then
        -- Blizzard's stance and pet buttons have no macro names.
        for _, suffix in ipairs({ "Macro", "MacroSize", "MacroPoint", "MacroX", "MacroY" }) do rules[p .. suffix].hidden = true end
    end
end
