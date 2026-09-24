local _, NS = ...
local B = NS.CatalogBuild
local Number, Bool, Choice, Color, Font, Texture = B.Number, B.Bool, B.Choice, B.Color, B.Font, B.Texture

-- Meter windows read the client's own combat data (C_DamageMeter). The API
-- ships on Retail, WoW Forever and every Classic-family client; values are
-- secret during combat only on Retail/Forever, which the runtime handles.
local MAX_WINDOWS = 5
NS.DamageMeterMaxWindows = MAX_WINDOWS
-- Choice index = Enum.DamageMeterType value + 1 (identical on all clients).
NS.DamageMeterTypeLabels = {
    "Damage done", "Damage per second", "Healing done", "Healing per second", "Absorbs",
    "Interrupts", "Dispels", "Damage taken", "Avoidable damage taken", "Deaths", "Enemy damage taken",
}

local function Available()
    local api = _G.C_DamageMeter
    if type(api) ~= "table" or type(api.GetCombatSessionFromType) ~= "function"
        or type(_G.Enum) ~= "table" or type(_G.Enum.DamageMeterType) ~= "table" then
        return false, "This client has no combat meter data"
    end
    return true
end

B.Module("damageMeter", {
    title = "Damage meter",
    description = "Lightweight meter windows for damage, healing, interrupts, dispels, deaths and damage taken. They read the client's own combat data; Blizzard's meter window stays hidden while this module is active.",
    core = true, page = "suite_damageMeter",
    conflicts = { "EllesmereUIDamageMeters" },
    available = Available,
})

local id = "damageMeter"
local midnight = {
    barColor = "57c7df", trackColor = "0a1522", trackAlpha = 42,
    leftColor = "f4f7fb", rightColor = "f4f7fb",
    bgColor = "0a1220", bgAlpha = 82, borderSize = 1, borderColor = "41627a",
    headerColor = "122434", headerAlpha = 92, titleColor = "f4f7fb",
}
local midnightDark = {
    barColor = "b9ab86", trackColor = "111315", trackAlpha = 42,
    leftColor = "e9e9e4", rightColor = "e9e9e4",
    bgColor = "151719", bgAlpha = 82, borderSize = 1, borderColor = "575b58",
    headerColor = "202326", headerAlpha = 88, titleColor = "f3f0e7",
}
local forever = {
    barColor = "d8b66a", trackColor = "111517", trackAlpha = 35,
    leftColor = "f4f3eb", rightColor = "f4f3eb",
    bgColor = "14181b", bgAlpha = 82, borderSize = 1, borderColor = "9f8960",
    headerColor = "20272a", headerAlpha = 82, titleColor = "f1e3c4",
}
NS.DamageMeterLookPresets = { [1] = midnight, [2] = midnightDark, [3] = forever }
NS.DamageMeterLookVisualKeys = {}
for key in pairs(midnight) do NS.DamageMeterLookVisualKeys[key] = true end
local initial = NS.Client.isForever and forever or midnightDark
B.Section(id, "look", "Choose a look", {
    Choice("look", "Style preset", NS.Client.isForever and 3 or 2,
        { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Custom" }),
})
B.Section(id, "general", "Windows and data", {
    Number("windowCount", "Number of windows", 2, 1, MAX_WINDOWS),
    Number("refreshRate", "Update interval in combat (seconds)", 1, 0.2, 2, 0.1),
    Choice("visibility", "Show windows", 1, { "Always", "In combat", "In a group", "Mouseover", "Never" }),
    Bool("autoCurrent", "Return to the current fight when combat starts", true),
    Bool("mythicReset", "Reset data when a Mythic+ keystone starts", true),
    Bool("confirmReset", "Ask before resetting data", true),
})
B.Section(id, "bars", "Bars", {
    Texture("barTexture", "Bar texture"),
    Number("barHeight", "Bar height", 18, 8, 40),
    Number("barSpacing", "Bar spacing", 2, -1, 10),
    Bool("classColors", "Class-colored bars", true),
    Color("barColor", "Bar color", initial.barColor),
    Number("barAlpha", "Bar opacity (percent)", 100, 0, 100, 5),
    Color("trackColor", "Bar background color", initial.trackColor),
    Number("trackAlpha", "Bar background opacity (percent)", initial.trackAlpha, 0, 100, 5),
    Choice("iconStyle", "Bar icons", 2, { "None", "Specialization", "Class" }),
    Number("iconZoom", "Icon zoom (percent)", 6, 0, 20),
    Bool("showPlayer", "Keep your own bar visible", true),
    Bool("gradientEnabled", "Bar gradient", false),
    Number("gradientStrength", "Gradient strength (percent)", 45, 0, 100, 5),
    Color("gradientColor", "Gradient color", "000000"),
    Bool("gradientDirLeft", "Gradient left", false),
    Bool("gradientDirRight", "Gradient right", true),
    Bool("gradientDirUp", "Gradient up", false),
    Bool("gradientDirDown", "Gradient down", false),
})
B.Section(id, "text", "Text and numbers", {
    Font("font", "Font"),
    Choice("outline", "Text style", 1, { "Shadow", "Outline", "Thick outline", "None", "Outline + shadow", "Thick outline + shadow" }),
    Choice("rendering", "Font rendering", 1, { "Smooth", "Sharp / pixel", "Slug" }),
    Number("shadowOpacity", "Shadow opacity (percent)", 100, 20, 100, 5),
    Choice("shadowDistance", "Shadow distance", 1, { "1 px", "2 px" }),
    Number("textOpacity", "Text opacity (percent)", 100, 50, 100, 5),
    Number("baseline", "Text baseline (px)", 0, -4, 4),
    Number("leftSize", "Name size", 11, 8, 18),
    Number("rightSize", "Value size", 11, 8, 18),
    Bool("showRealm", "Show server names", false),
    Number("nameMaxChars", "Shorten names after characters (0 = off)", 0, 0, 40),
    Bool("nameEllipsis", "Add ... to shortened names", true),
    Bool("rank", "Show rank numbers", true),
    Choice("numberFormat", "Value format", 3, { "Per second only", "Primary value only", "Primary (secondary)", "Primary | secondary", "Custom layout" }),
    Choice("valueOrder", "Value order", 1, {
        "Total, per second, percent", "Total, percent, per second",
        "Per second, total, percent", "Per second, percent, total",
        "Percent, total, per second", "Percent, per second, total",
    }),
    Choice("valueSeparator", "Value separator", 2, { "None (spaces)", "Parentheses ( )", "Square brackets [ ]", "Vertical bar |", "Slash /", "Hyphen -" }),
    Bool("percent", "Show share of the total when available", false),
    Bool("leftClassColor", "Class-colored names", false),
    Color("leftColor", "Name color", initial.leftColor),
    Bool("rightClassColor", "Class-colored values", false),
    Color("rightColor", "Value color", initial.rightColor),
})
B.Section(id, "window", "Window and header", {
    Color("bgColor", "Background color", initial.bgColor),
    Number("bgAlpha", "Background opacity (percent)", initial.bgAlpha, 0, 100, 5),
    Number("borderSize", "Border thickness", initial.borderSize, 0, 4),
    Color("borderColor", "Border color", initial.borderColor),
    Number("headerHeight", "Header height", 22, 14, 40),
    Color("headerColor", "Header color", initial.headerColor),
    Number("headerAlpha", "Header opacity (percent)", initial.headerAlpha, 0, 100, 5),
    Number("headerFontSize", "Header text size", 11, 8, 18),
    Color("titleColor", "Header text color", initial.titleColor),
    Number("headerIconSize", "Header button size", 18, 14, 30),
    Bool("headerMouseover", "Show header buttons only on mouseover", false),
})
B.Section(id, "details", "Details", {
    Bool("hoverTooltip", "Show a spell breakdown on mouseover", true),
    Number("tooltipRows", "Breakdown rows", 10, 3, 20),
    Number("tooltipScale", "Breakdown scale (percent)", 100, 80, 150, 5),
    Bool("spellTooltips", "Show spell tooltips in the breakdown", true),
})
B.Section(id, "timer", "Combat timer", {
    Bool("combatTime", "Show combat time", true),
    Bool("headerTimer", "Show duration in window headers", true),
    Bool("timer", "Show a separate floating timer", false),
    Number("timerSize", "Timer text size", 26, 10, 40),
    Bool("timerKeep", "Keep the last duration after combat", false),
    Number("timerX", "Timer: horizontal", 0, -3000, 3000),
    Number("timerY", "Timer: vertical", 250, -2000, 2000),
})

local defaultTypes = { 1, 3, 8, 6, 10 }
for i = 1, MAX_WINDOWS do
    local p = "w" .. i
    local title = "Window " .. i
    B.Section(id, p, title, {
        Choice(p .. "Type", "Meter", defaultTypes[i], NS.DamageMeterTypeLabels),
        Choice(p .. "Session", "Fight", 1, { "Current fight", "Overall" }),
        Number(p .. "Width", "Width", NS.Client.isForever and 340 or 260, 150, 900),
        Number(p .. "Height", "Height", 170, 50, 900),
        Number(p .. "X", "Horizontal position", -20, -4000, 4000),
        Number(p .. "Y", "Vertical position", (NS.Client.isForever and 60 or 20) + (i - 1) * 190, -3000, 3000),
        Bool(p .. "Locked", "Lock window", false),
        Bool(p .. "HideDungeon", "Hide in dungeons", false),
        Bool(p .. "HideRaid", "Hide in raids", false),
        Bool(p .. "HidePvP", "Hide in battlegrounds and arenas", false),
        Bool(p .. "HideWorld", "Hide outside instances", false),
    }, { window = i })
end

-- Presentation dependencies for the menu: enableKey needs the named switch on,
-- disabledBy needs it off, requiresChoice needs one of the listed choices.
local rules = NS.SuiteCatalog.damageMeter.rules
rules.leftColor.disabledBy = "leftClassColor"
rules.rightColor.disabledBy = "rightClassColor"
rules.barColor.disabledBy = "classColors"
rules.gradientStrength.enableKey = "gradientEnabled"
rules.gradientColor.enableKey = "gradientEnabled"
for _, key in ipairs({ "gradientDirLeft", "gradientDirRight", "gradientDirUp", "gradientDirDown" }) do
    rules[key].hidden = true -- The Bars-style D-pad below owns these switches.
    rules[key].enableKey = "gradientEnabled"
end
rules.iconZoom.requiresChoice = { key = "iconStyle", values = { [2] = true, [3] = true } }
rules.shadowOpacity.requiresChoice = { key = "outline", values = { [1] = true, [5] = true, [6] = true } }
rules.shadowDistance.requiresChoice = { key = "outline", values = { [1] = true, [5] = true, [6] = true } }
rules.valueOrder.requiresChoice = { key = "numberFormat", values = { [5] = true } }
rules.valueSeparator.requiresChoice = { key = "numberFormat", values = { [5] = true } }
rules.headerTimer.enableKey = "combatTime"
rules.timer.enableKey = "combatTime"
for _, key in ipairs({ "tooltipRows", "tooltipScale", "spellTooltips" }) do rules[key].enableKey = "hoverTooltip" end
for _, key in ipairs({ "timerSize", "timerKeep", "timerX", "timerY" }) do rules[key].enableKey = "timer" end
rules.timerX.category, rules.timerY.category = "advanced", "advanced"
for i = 1, MAX_WINDOWS do
    rules["w" .. i .. "X"].category = "advanced"
    rules["w" .. i .. "Y"].category = "advanced"
end
