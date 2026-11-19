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
-- Native first slots shared by the runtime and preview. Bar 10 stores
-- independent actions, so page 10 stays available to form paging.
NS.ActionBarFirstSlots = { 1, 61, 49, 25, 37, 145, 157, 169, 13 }
NS.ActionBarCommands = { "ACTIONBUTTON", "MULTIACTIONBAR1BUTTON", "MULTIACTIONBAR2BUTTON", "MULTIACTIONBAR3BUTTON",
    "MULTIACTIONBAR4BUTTON", "MULTIACTIONBAR5BUTTON", "MULTIACTIONBAR6BUTTON", "MULTIACTIONBAR7BUTTON",
    "MSUFSUITE_BAR9_BUTTON", "MSUFSUITE_BAR10_BUTTON", "SHAPESHIFTBUTTON", "BONUSACTIONBUTTON" }

-- The named values of the bar choices (each is the saved index of the
-- choice's label list) and the bar numbers: bar 1 is Blizzard's main bar,
-- bars FIRST_NATIVE to LAST_NATIVE reuse Blizzard's own multibar buttons,
-- bars from FIRST_EXTRA on have no Blizzard counterpart bar, bars up to
-- LAST_ACTION have suite-owned buttons, then stance and pet.
local ENUM = {
    -- CUSTOM combines the per-bar conditions below (NS.ActionBarConditionBody).
    VISIBILITY = { ALWAYS = 1, COMBAT = 2, OUT_OF_COMBAT = 3, MOUSEOVER = 4, MOUSEOVER_OR_COMBAT = 5, NEVER = 6, CUSTOM = 7 },
    -- "Custom conditions": how the chosen conditions combine, and the
    -- choices of the combat, mount and target conditions.
    COMBINE = { ANY = 1, ALL = 2 },
    CONDITION = { IGNORE = 1, YES = 2, NO = 3 },
    TARGET_CONDITION = { IGNORE = 1, EXISTS = 2, NONE = 3, HOSTILE = 4, FRIENDLY = 5 },
    PROC_GLOW = { BLIZZARD = 1, PIXEL = 2, NONE = 3 },
    -- MSUF's icon shapes from ROUNDED on (MSUF 7.0; older hosts draw them
    -- square). STAR is left out: its ring is a silhouette that only works
    -- behind the icon, and the buttons draw their frame, hover, pressed and
    -- glow art above it.
    BUTTON_SHAPE = { SQUARE = 1, CIRCLE = 2, ROUNDED = 3, DIAMOND = 4, HEXAGON = 5, BLIZZARD = 6 },
    BUTTON_SHAPE_IDS = { "RECTANGLE", "CIRCLE", "ROUNDED", "DIAMOND", "HEXAGON", "BLIZZARD" },
    BORDER_ART = { PIXEL = 1, BLIZZARD = 2 },
    ASSIST_STYLE = { BLIZZARD = 1, RING = 2, FILL = 3, RING_AND_FILL = 4 },
    -- "Mouseover highlight" and "Pressed highlight".
    HIGHLIGHT = { BORDER = 1, FILL = 2, BLIZZARD = 3, NONE = 4 },
    ENDCAP = { NONE = 1, DIAMOND = 2, CHEVRONS = 3, BLIZZARD = 4, WAYFARER = 5 },
    PAGE_ARROW_SIDE = { LEFT = 1, RIGHT = 2 },
    -- "Show tooltips" per bar, and the side a spell flyout opens to.
    TOOLTIP = { ALWAYS = 1, OUT_OF_COMBAT = 2, NEVER = 3 },
    FLYOUT = { AUTOMATIC = 1, UP = 2, DOWN = 3, LEFT = 4, RIGHT = 5 },
    -- "First button corner": the corner button 1 sits in.
    START = { TOP_LEFT = 1, TOP_RIGHT = 2, BOTTOM_LEFT = 3, BOTTOM_RIGHT = 4 },
    LOOK = { MIDNIGHT_BLUE = 1, MIDNIGHT_DARK = 2, FOREVER = 3, CUSTOM = 4, CLEAN_MODERN = 5, CLASS_STYLE = 6 },
    BAR = { MAIN = 1, FIRST_NATIVE = 2, LAST_NATIVE = 8, FIRST_EXTRA = 9, INDEPENDENT = 10,
        LAST_ACTION = 10, STANCE = 11, PET = 12 },
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

function NS.PaintBlizzardActionBarEndcap(cap, side, size)
    for _, piece in ipairs(cap.pieces) do piece:Hide() end
    local piece = cap.pieces[1]
    piece:ClearAllPoints()
    piece:SetRotation(0)
    piece:SetVertexColor(1, 1, 1, 1)
    piece:SetTexCoord(0, 1, 0, 1)
    piece:SetAtlas(side == "Left" and "ui-hud-actionbar-gryphon-left" or "ui-hud-actionbar-gryphon-right")
    piece:SetSize(size * 104.5 / 98, size)
    piece:SetPoint("CENTER", cap, "CENTER")
    piece:Show()
end

function NS.PaintWayfarerActionBarEndcap(cap, side, size)
    for _, piece in ipairs(cap.pieces) do piece:Hide() end
    local piece = cap.pieces[1]
    piece:ClearAllPoints()
    piece:SetRotation(0)
    piece:SetVertexColor(1, 1, 1, 1)
    piece:SetTexture("Interface\\AddOns\\MSUF_Suite\\Media\\WayfarerEndcap.tga")
    local flip = side == "Right"
    piece:SetTexCoord(flip and 1 or 0, flip and 0 or 1, 0, 1)
    piece:SetSize(size, size)
    piece:SetPoint("CENTER", cap, "CENTER")
    piece:Show()
end

-- No client check: Blizzard_RestrictedAddOnEnvironment (secure handlers and
-- state drivers) loads on Retail and on Forever.
B.Module("actionbars", {
    title = "Action bars",
    description = "Ten action bars plus stance and pet bars with free layout, paging, visibility rules and button styling. Key bindings keep using Blizzard's commands.",
    core = true, defaultEnabled = true,
    cvars = { AutoPushSpellToActionBar = true },
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
    Choice("buttonShape", "Button shape", ENUM.BUTTON_SHAPE.SQUARE,
        { "Square", "Circle", "Rounded", "Diamond", "Hexagon", "Blizzard portrait" }),
    Choice("borderArt", "Button frame style", ENUM.BORDER_ART.PIXEL, { "Pixel border", "Blizzard frame" }),
    Number("borderScale", "Button frame scale (percent)", 100, 70, 160, 5),
    Number("borderExpansion", "Button frame expansion", 0, -8, 20),
    B.String("mediaBorder", "SharedMedia border", "", 260),
    Number("mediaBorderSize", "SharedMedia edge size", 16, 1, 32),
    Number("mediaBorderPadding", "SharedMedia border padding", 0, -12, 20),
    Bool("styleSpecialButtons", "Style Extra Action and Zone Ability buttons", false),
    Bool("hideSpecialArtwork", "Hide Extra Action and Zone Ability artwork", false),
    Bool("specialKeybind", "Show Extra Action keybind", true),
    Number("specialKeybindSize", "Extra Action keybind size", 12, 6, 30),
    Number("specialCooldownSize", "Special button cooldown text size", 16, 6, 30),
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
    -- MSUF's icon skin of every button, chosen on MSUF's Icon Skins page:
    -- DEFAULT follows its default skin, CUSTOM keeps the look above.
    B.String("iconSkin", "Icon skin", "DEFAULT", 64),
    -- Opt-in: only buttons the Suite creates itself join Masque
    -- (MSUF_Suite_ActionBars/Masque.lua); reused Blizzard buttons never do.
    B.Tooltip(Bool("masque", "Skin Suite-made buttons with Masque", false),
        "Hands the frame, icon and highlight art of the buttons the Suite creates itself (action bars 9 and 10, and bar 1 "
            .. "where Blizzard's buttons cannot be reused) to Masque, one Masque group per bar. Bars that reuse Blizzard's "
            .. "buttons keep the Suite look. Turning it off restores the Suite look at once."),
})
B.Section(id, "cooldowns", "Cooldowns and states", {
    Bool("cooldownNumbers", "Show cooldown numbers", true),
    Bool("rechargeNumbers", "Show recharge numbers while charges remain", true),
    Number("swipeAlpha", "Cooldown swipe opacity (percent)", 80, 0, 100, 5),
    Color("swipeColor", "Cooldown swipe color", "000000"),
    Bool("desaturateCooldown", "Desaturate buttons on cooldown", false),
    Number("cooldownAlpha", "Button opacity while on cooldown (percent)", 100, 0, 100, 5),
    Bool("rangeColoring", "Color out-of-range buttons", true),
    Choice("rangeIndicator", "Range warning on", 1, { "Icon", "Keybind", "Icon and keybind" }),
    Color("rangeColor", "Out-of-range color", "cc1a1a"),
    -- The defaults are Blizzard's own button tints (S.USABLE_TINT, shared with
    -- the cooldown manager): 1/1/1, .5/.5/1 and .4/.4/.4.
    Color("usableColor", "Usable color", "ffffff"),
    Color("noPowerColor", "Not enough resources color", "8080ff"),
    Color("unusableColor", "Unusable color", "666666"),
    Bool("hideEmptyCharges", "Hide the charge count at zero", false),
})
B.TextSection(id, {
    Color("keybindColor", "Keybind color", initial.keybindColor),
    Color("macroColor", "Macro name color", initial.macroColor),
    Color("countColor", "Count color", initial.countColor),
    Color("cooldownColor", "Cooldown number color", initial.cooldownColor),
    Bool("keybindFontOverride", "Customize the keybind font", false),
    B.Font("keybindFont", "Keybind font"),
    Choice("keybindFontOutline", "Keybind outline", 1, { "Outline", "Thick outline", "None" }),
    Bool("macroFontOverride", "Customize the macro name font", false),
    B.Font("macroFont", "Macro name font"),
    Choice("macroFontOutline", "Macro name outline", 1, { "Outline", "Thick outline", "None" }),
    Bool("countFontOverride", "Customize the count font", false),
    B.Font("countFont", "Count font"),
    Choice("countFontOutline", "Count outline", 1, { "Outline", "Thick outline", "None" }),
    Bool("cooldownFontOverride", "Customize the cooldown font", false),
    B.Font("cooldownFont", "Cooldown font"),
    Choice("cooldownFontOutline", "Cooldown outline", 1, { "Outline", "Thick outline", "None" }),
})
B.Section(id, "behavior", "Behavior", {
    Bool("shortKeybinds", "Shorten keybind text", true),
    Choice("autoAddSpells", "Add newly learned spells to action bars", 1, { "Use Blizzard setting", "Enable", "Disable" }),
    Choice("pickupModifier", "Move actions while holding (all action bars)", 1,
        { "Use Blizzard setting", "Shift", "Ctrl", "Alt", "No modifier" }),
    Bool("mouseoverShowAll", "Hovering one mouseover bar reveals all of them", false),
    Bool("showOnPanels", "Show bars while spellbook or macros are open", false),
    Bool("showOnDrag", "Show hidden bars while dragging a spell", true),
    Bool("disableFormPaging", "Keep bar 1 on its page in stance or shapeshift forms", false),
    Bool("disableMoonkinPaging", "Keep bar 1 on its page in Moonkin Form", false),
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
    B.Tooltip(Bool("profileKeybinds", "Include key bindings in profile exports and imports", true),
        "While the Suite action bars are on, exports carry the keys of bars 1 to 10, and an import replaces your action "
            .. "bar keys in the key binding set this character uses. Restore previous setup under Account transfer undoes it."),
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
-- Saved profiles store the index, so new modes only ever append. The hidden
-- resume list mirrors it, so switching a Custom bar off and on keeps Custom.
local VISIBILITY_LABELS = { "Always", "In combat", "Out of combat", "Mouseover", "Mouseover or combat", "Never",
    "Custom conditions" }
local CONDITION, TARGET_CONDITION = ENUM.CONDITION, ENUM.TARGET_CONDITION
local PAGING_TIP = "Macro conditions with page numbers, for example [mod:shift] 2; [@target,harm] 3. Vehicle, override, "
    .. "possess, pet battle and form paging keep their priority; otherwise the bar returns to its own page. Invalid text is "
    .. "never applied."

for i = 1, BAR_COUNT do
    local p = "bar" .. i
    local title = NS.ActionBarTitles[i]
    local d = defaults[i]
    local maxButtons = d[2]
    local special = i > ENUM.BAR.LAST_ACTION
    B.Section(id, p, title, {
        Choice(p .. "Visibility", "Show this bar", d[1], VISIBILITY_LABELS),
        Choice(p .. "CondCombine", "Show when", ENUM.COMBINE.ANY, { "Any condition is met", "All conditions are met" }),
        Choice(p .. "CondCombat", "Combat condition", CONDITION.YES, { "Ignore", "In combat", "Out of combat" }),
        Choice(p .. "CondMounted", "Mount condition", CONDITION.IGNORE, { "Ignore", "Mounted", "Not mounted" }),
        Choice(p .. "CondTarget", "Target condition", TARGET_CONDITION.IGNORE,
            { "Ignore", "Has a target", "No target", "Hostile target", "Friendly target" }),
        Bool(p .. "CondMouseover", "Reveal on mouseover", true),
        Bool(p .. "HideGamepad", "Hide with an active connected gamepad (Forever)"),
        Bool(p .. "GroupOnly", "Show only while grouped"),
        Choice(p .. "ResumeVisibility", "Visibility when turned on", d[1] == VISIBILITY.NEVER and VISIBILITY.ALWAYS or d[1],
            VISIBILITY_LABELS),
        B.Tooltip(B.String(p .. "Paging", "Custom paging (macro conditions)", "", 255), PAGING_TIP),
        Number(p .. "Alpha", "Bar opacity (percent)", 100, 0, 100, 5),
        Number(p .. "FadeAlpha", "Opacity without mouseover (percent)", 0, 0, 100, 5),
        Number(p .. "FadeDuration", "Fade duration (seconds; 0 is instant)", 0, 0, 2, 0.05),
        Number(p .. "Layer", "MSUF layer (-1 = Auto)", -1, -1, 30),
        Number(p .. "Buttons", "Buttons", maxButtons, 1, maxButtons),
        Number(p .. "Rows", "Rows", d[3] > 1 and d[3] or 1, 1, maxButtons),
        Number(p .. "Size", "Button size", special and 30 or 40, 16, 80),
        Number(p .. "HeightPercent", "Button height (percent)", 100, 40, 100),
        Number(p .. "Spacing", "Button spacing", 2, -10, 20),
        Bool(p .. "Vertical", "Fill columns first", d[3] > 1),
        Choice(p .. "Start", "First button corner", ENUM.START.TOP_LEFT, { "Top left", "Top right", "Bottom left", "Bottom right" }),
        Bool(p .. "ShowEmpty", "Show empty buttons", not special),
        Choice(p .. "FlyoutDirection", "Spell flyout direction", ENUM.FLYOUT.AUTOMATIC,
            { "Automatic", "Up", "Down", "Left", "Right" }),
        Bool(p .. "ClickThrough", "Click through", false),
        Choice(p .. "Tooltip", "Show tooltips", ENUM.TOOLTIP.ALWAYS, { "Always", "Out of combat", "Never" }),
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
        Choice(p .. "LeftEndcap", "Left endcap", ENUM.ENDCAP.NONE, { "None", "Diamond", "Chevrons", "Blizzard", "Wayfarer" }),
        Number(p .. "LeftEndcapSize", "Left endcap size", 32, 8, 120),
        Number(p .. "LeftEndcapX", "Left endcap horizontal offset", 0, -200, 200),
        Number(p .. "LeftEndcapY", "Left endcap vertical offset", 0, -200, 200),
        Choice(p .. "RightEndcap", "Right endcap", ENUM.ENDCAP.NONE, { "None", "Diamond", "Chevrons", "Blizzard", "Wayfarer" }),
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
rules.mediaBorder.border = true
for _, key in ipairs({ "specialKeybind", "specialKeybindSize", "specialCooldownSize" }) do
    rules[key].enableKey = "styleSpecialButtons"
end
for _, prefix in ipairs({ "keybind", "macro", "count", "cooldown" }) do
    rules[prefix .. "Font"].enableKey = prefix .. "FontOverride"
    rules[prefix .. "Font"].defaultLabel = "Shared action bar font"
    rules[prefix .. "FontOutline"].enableKey = prefix .. "FontOverride"
end
rules.imported.hidden = true
-- The key bindings travel with profile strings only while this is on
-- (ProfileIO.lua). The choice itself stays with this profile: no export or
-- import carries it.
rules.profileKeybinds.personal = true
rules.iconSkin.hidden = true
rules.disableSkyridingPaging.hidden = NS.Client.isForever or nil
-- The forms opt-out already covers Moonkin Form.
rules.disableMoonkinPaging.disabledBy = "disableFormPaging"
rules.borderColor.disabledBy = "borderClassColor"
rules.interactionColor.disabledBy = "interactionClassColor"
rules.rangeColor.enableKey = "rangeColoring"
rules.rangeIndicator.enableKey = "rangeColoring"
-- Recharge numbers are cooldown numbers (Style.lua needs both switches on).
rules.rechargeNumbers.enableKey = "cooldownNumbers"
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
    rules[p .. "HeightPercent"].hidden = i > ENUM.BAR.LAST_ACTION or nil
    rules[p .. "HeightPercent"].requiresChoice = { key = "buttonShape", values = { [ENUM.BUTTON_SHAPE.SQUARE] = true } }
    -- Only Forever has a gamepad interface to hide bars for
    -- (InputUtil.IsGamepadUIEnabled); Retail never applies the option.
    rules[p .. "HideGamepad"].hidden = not NS.Client.isForever or nil
    -- The fade options apply to the mouseover modes (Custom conditions fade
    -- while "Reveal on mouseover" is on).
    local mouseover = { key = p .. "Visibility",
        values = { [VISIBILITY.MOUSEOVER] = true, [VISIBILITY.MOUSEOVER_OR_COMBAT] = true, [VISIBILITY.CUSTOM] = true } }
    rules[p .. "FadeAlpha"].requiresChoice = mouseover
    rules[p .. "FadeDuration"].requiresChoice = mouseover
    local custom = { key = p .. "Visibility", values = { [VISIBILITY.CUSTOM] = true } }
    for _, suffix in ipairs({ "CondCombine", "CondCombat", "CondMounted", "CondTarget", "CondMouseover" }) do
        rules[p .. suffix].requiresChoice = custom
    end
    -- Paging needs a native page of its own: bars 1 to 9 (bar 10 stores
    -- independent actions; stance and pet buttons have no pages).
    rules[p .. "Paging"].hidden = not NS.ActionBarFirstSlots[i] or nil
    -- Blizzard's stance and pet buttons open no spell flyouts.
    rules[p .. "FlyoutDirection"].hidden = i > ENUM.BAR.LAST_ACTION or nil
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
                values = { [ENUM.ENDCAP.DIAMOND] = true, [ENUM.ENDCAP.CHEVRONS] = true,
                    [ENUM.ENDCAP.BLIZZARD] = true, [ENUM.ENDCAP.WAYFARER] = true } }
        end
    end
    for _, suffix in ipairs({ "Point", "X", "Y" }) do rules[p .. suffix].category = "advanced" end
    if i > ENUM.BAR.LAST_ACTION then
        -- Blizzard's stance and pet buttons have no macro names.
        for _, suffix in ipairs({ "Macro", "MacroSize", "MacroPoint", "MacroX", "MacroY" }) do rules[p .. suffix].hidden = true end
    end
end

------------------------------------------------------------------ custom paging
-- A bar's paging text is a whitelisted subset of the macro option syntax:
-- clauses "[conditions] page" separated by ";". Every accepted clause is
-- rebuilt from known words, so a state driver only ever sees normalized
-- text. Anything else refuses the whole text (the bar keeps its own page),
-- imported profiles included. Native states are not in the whitelist: the
-- runtime keeps vehicle, override, possess, pet battle and form paging ahead
-- of every custom clause (MSUF_Suite_ActionBars/Paging.lua).
local HOME_PAGES, PAGE_OWNERS = {}, {}
for index, slot in ipairs(NS.ActionBarFirstSlots) do
    local page = math.floor((slot - 1) / 12) + 1
    HOME_PAGES[index] = page
    if page <= 6 then PAGE_OWNERS[page] = index end
end
NS.ActionBarHomePages = HOME_PAGES
local MAX_CLAUSES = 16
local function Trim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
local function Word(set) return function(arg) return set[arg] == true end end
local function Within(low, high)
    return function(arg)
        local n = arg:find("^%d%d?$") and tonumber(arg)
        return n ~= nil and n >= low and n <= high
    end
end
local MODIFIER = Word({ shift = true, ctrl = true, alt = true, lshift = true, rshift = true, lctrl = true, rctrl = true,
    lalt = true, ralt = true })
-- word -> { arg = check of one value, needs = a value is required }
local PAGING_TESTS = {
    mod = { arg = MODIFIER }, modifier = { arg = MODIFIER }, group = { arg = Word({ party = true, raid = true }) },
    form = { arg = Within(0, 10) }, stance = { arg = Within(0, 10) }, bonusbar = { arg = Within(1, 5) },
    bar = { arg = Within(1, 6), needs = true }, actionbar = { arg = Within(1, 6), needs = true },
    spec = { arg = Within(1, 4), needs = true },
}
for _, word in ipairs({ "combat", "mounted", "flying", "swimming", "stealth", "indoors", "outdoors", "resting", "pet",
    "exists", "dead", "help", "harm", "channeling", "flyable" }) do PAGING_TESTS[word] = {} end
local PAGING_UNITS = { target = true, focus = true, mouseover = true, player = true, pet = true }

local function ParseTest(token)
    local word, args = token:match("^(%a+)%s*:%s*(.-)$")
    word = word or token:match("^%a+$")
    local test = word and PAGING_TESTS[word]
    local negated = ""
    if word and not test and word:sub(1, 2) == "no" then
        negated, word = "no", word:sub(3)
        test = PAGING_TESTS[word]
    end
    if not test then return nil, "Unknown condition: %s", token end
    if not args or args == "" then
        if test.needs then return nil, "The condition %s needs a value.", word end
        return negated .. word
    end
    if not test.arg then return nil, "The condition %s takes no value.", word end
    local list = {}
    for arg in (args .. "/"):gmatch("([^/]*)/") do
        arg = Trim(arg)
        if not test.arg(arg) then return nil, "Unsupported value for %s: %s", word, arg end
        list[#list + 1] = arg
    end
    return negated .. word .. ":" .. table.concat(list, "/")
end

local function ParseGroup(inner)
    local tokens = {}
    for raw in (inner .. ","):gmatch("([^,]*),") do
        local token = Trim(raw)
        if token == "" then return nil, "A condition list has an empty entry." end
        local unit = token:match("^@(%w+)$") or token:match("^target%s*=%s*(%w+)$")
        if unit then
            if #tokens > 0 or not PAGING_UNITS[unit] then return nil, "Unsupported unit: %s", unit end
            tokens[1] = "@" .. unit
        else
            local test, why, a, b = ParseTest(token)
            if not test then return nil, why, a, b end
            tokens[#tokens + 1] = test
        end
    end
    return "[" .. table.concat(tokens, ",") .. "]"
end

-- One clause: its normalized conditions ("" for none) and its page.
local function ParseClause(clause)
    local groups, rest = {}, clause
    while rest:sub(1, 1) == "[" do
        local close = rest:find("]", 2, true)
        if not close then return nil, "A condition is missing its closing bracket." end
        local group, why, a, b = ParseGroup(rest:sub(2, close - 1))
        if not group then return nil, why, a, b end
        groups[#groups + 1] = group
        rest = Trim(rest:sub(close + 1))
    end
    local page = rest:find("^%d%d?$") and tonumber(rest)
    if not page then return nil, "Each clause ends with a page number: %s", clause end
    return table.concat(groups), page
end

-- The normalized clauses of a paging text, the pages they name and whether
-- the last one has no condition; else nil, a message and its values.
local function ParsePaging(text)
    if #text > 255 or text:find("[^%w%s%[%]@,:/;=]") then
        return nil, "Use only macro conditions, page numbers and semicolons."
    end
    local clauses, pages, final = {}, {}, false
    for raw in (text:lower() .. ";"):gmatch("([^;]*);") do
        local clause = Trim(raw)
        if clause ~= "" then
            if final then return nil, "Nothing can follow a clause without conditions." end
            if #clauses >= MAX_CLAUSES then return nil, "Use at most %d clauses.", MAX_CLAUSES end
            local conditions, page, a, b = ParseClause(clause)
            if not conditions then return nil, page, a, b end
            final = conditions == ""
            clauses[#clauses + 1] = final and tostring(page) or conditions .. " " .. page
            pages[#pages + 1] = page
        end
    end
    if #clauses == 0 then return nil, "Add at least one clause." end
    return { driver = table.concat(clauses, "; "), pages = pages, final = final }
end

-- Whether an enabled bar keeps manual page `page` (2 to 6) as its own.
function NS.ActionBarPageOwned(config, page)
    local owner = PAGE_OWNERS[page]
    if not owner or owner == 1 then return false end
    local mode = config["bar" .. owner .. "Visibility"]
    return mode ~= nil and mode ~= VISIBILITY.NEVER
end

-- One owner per page: a bar's own page; for bar 1 also the form and bonus
-- pages 7 to 11 it shows anyway; for any bar a manual page 2 to 6 that no
-- enabled bar owns and no lower bar's custom paging claimed first.
local function PageAllowed(config, index, page, claims)
    if page == HOME_PAGES[index] or (index == 1 and page >= 7 and page <= 11) then return true end
    if page < 2 or page > 6 then
        if index == 1 then return false, "Bar 1 pages to pages 1 to 11." end
        return false, "This bar pages to its own page or to a free page from 2 to 6."
    end
    if NS.ActionBarPageOwned(config, page) then
        return false, "Page %d belongs to action bar %d.", page, PAGE_OWNERS[page]
    end
    local claim = claims[page]
    if claim and claim ~= index then return false, "Page %d is already paged by action bar %d.", page, claim end
    return true
end

local function Check(config, index, claims)
    local text = config["bar" .. index .. "Paging"]
    if type(text) ~= "string" or not text:find("%S") then return false end
    if not HOME_PAGES[index] then return nil, "Custom paging is not available for this bar." end
    local parsed, why, a, b = ParsePaging(text)
    if not parsed then return nil, why, a, b end
    for i = 1, #parsed.pages do
        local ok, reason, c, d = PageAllowed(config, index, parsed.pages[i], claims)
        if not ok then return nil, reason, c, d end
    end
    return parsed
end

-- Pages 2 to 6 that bars 2 to 9 page to besides their own, by page. A lower
-- bar's valid claim wins; switched-off bars claim nothing.
function NS.ActionBarPageClaims(config)
    local claims = {}
    for index = 2, #HOME_PAGES do
        local parsed = config["bar" .. index .. "Visibility"] ~= VISIBILITY.NEVER and Check(config, index, claims)
        if parsed then
            for i = 1, #parsed.pages do
                local page = parsed.pages[i]
                if page ~= HOME_PAGES[index] then claims[page] = index end
            end
        end
    end
    return claims
end

-- The custom paging of bar `index`: false while it has none or is switched
-- off; the parsed text ({ driver, pages, final }) when every page is free
-- for it; else nil, a message (a format) and up to two values for it.
-- claims: NS.ActionBarPageClaims(config), computed when omitted.
function NS.ActionBarPaging(config, index, claims)
    if config["bar" .. index .. "Visibility"] == VISIBILITY.NEVER then return false end
    return Check(config, index, claims or NS.ActionBarPageClaims(config))
end
