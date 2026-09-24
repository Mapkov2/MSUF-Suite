local _, NS = ...
local B = NS.CatalogBuild
local Choice, Bool, Number, Color, Font, Texture = B.Choice, B.Bool, B.Number, B.Color, B.Font, B.Texture

NS.DataTextSources = {
    "None", "Gold", "Bag space", "Durability", "Clock", "FPS", "Latency", "Coordinates", "Location", "XP", "Session gold",
}
NS.DataTextSourceKeys = {
    false, "gold", "bags", "durability", "clock", "fps", "latency", "coordinates", "location", "xp", "sessionGold",
}
NS.DataTextPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
NS.DataTextLooks = {
    { background = "0a1220", border = "41627a", accent = "57c7df", label = "a9ccdf",
      value = "f4f7fb", separator = "41627a", warning = "ff7575" },
    { background = "151719", border = "575b58", accent = "b9ab86", label = "d8ceb5",
      value = "e9e9e4", separator = "555a56", warning = "ed8d80" },
    { background = "14181b", border = "9f8960", accent = "d8b66a", label = "d8b66a",
      value = "f4f3eb", separator = "727774", warning = "ed8d80" },
}
local initialLook = NS.Client.isForever and 3 or 2
local initial = NS.DataTextLooks[initialLook]
local function Capital(key) return key:sub(1, 1):upper() .. key:sub(2) end
function NS.DataTextBarStyleKey(bar, key) return "bar" .. bar .. Capital(key) end

B.Module("dataTexts", {
    title = "DataTexts",
    description = "Movable information bars with individually chosen data sources.",
    core = NS.Client.isForever, optIn = not NS.Client.isForever,
    page = "suite_dataTexts",
})
-- New Forever setups use the small information strip shown by the selected
-- look. Existing profiles keep their explicit module switch and placement.
NS.SuiteCatalog.dataTexts.rules.enabled.default = true

local barStyle = {
    Choice("look", "MSUF style", initialLook, { "Midnight Blue", "Midnight Dark", "MSUF Forever" }),
    Bool("backgroundEnabled", "Show background", true),
    Texture("backgroundTexture", "Background texture"),
    Number("backgroundOpacity", "Background opacity (percent)", NS.Client.isForever and 94 or 82, 0, 100, 5),
    Bool("borderEnabled", "Show outline", true),
    Number("borderSize", "Outline thickness", 1, 1, 4),
    Bool("accentEnabled", "Show accent line", true),
    Bool("separatorEnabled", "Separate places", false),
    Number("separatorSize", "Separator thickness", 1, 1, 3),
    Number("padding", "Text padding", 5, 0, 20),
    Number("gap", "Space between places", 0, 0, 20),
    Bool("customColors", "Custom colors", false),
    Color("backgroundColor", "Background color", initial.background),
    Color("borderColor", "Outline color", initial.border),
    Color("accentColor", "Accent color", initial.accent),
    Color("separatorColor", "Separator color", initial.separator),
}
local textStyle = {
    Font("font", "Font"),
    Number("fontSize", "Text size", NS.Client.isForever and 11 or 12, 9, 22),
    Choice("textOutline", "Text outline", 1, { "Outline", "Thick outline", "None", "Monochrome outline" }),
    Choice("textAlign", "Text alignment", 2, { "Left", "Center", "Right" }),
    Bool("showLabels", "Show data names", true),
    Color("labelColor", "Label color", initial.label),
    Color("valueColor", "Value color", initial.value),
    Color("warningColor", "Warning color", initial.warning),
}
local dependencies = {
    backgroundTexture = "backgroundEnabled", backgroundOpacity = "backgroundEnabled",
    borderSize = "borderEnabled", separatorSize = "separatorEnabled",
    backgroundColor = "customColors", borderColor = "customColors", accentColor = "customColors",
    separatorColor = "customColors", labelColor = "customColors", valueColor = "customColors",
    warningColor = "customColors",
}
NS.DataTextStyleKeys = {}
for _, group in ipairs({ barStyle, textStyle }) do
    for _, rule in ipairs(group) do
        NS.DataTextStyleKeys[#NS.DataTextStyleKeys + 1] = rule.key
        rule.enableKey = dependencies[rule.key]
    end
end
B.Section("dataTexts", "appearance", "Shared bar style", barStyle)
B.Section("dataTexts", "textStyle", "Shared text style", textStyle)
if NS.Client.isMainline then
    B.Section("dataTexts", "bags", "Blizzard bag buttons", {
        Bool("hideBlizzardBagBar", "Hide Blizzard bag buttons; use the Bag space DataText", true),
    })
end

-- Settings are copied from the shared style when an override is switched on.
local function AddBarStyle(bar)
    local prefix, section = "bar" .. bar, "bar" .. bar .. "Style"
    local switch = Bool(prefix .. "StyleOverride", "Own style", false)
    switch.hidden = true
    switch.enableKey = prefix .. "Enabled"
    B.Add("dataTexts", switch, section, "Bar " .. bar .. " styling")
    for _, group in ipairs({ barStyle, textStyle }) do
        for _, rule in ipairs(group) do
            local own = {}
            for field, value in pairs(rule) do own[field] = value end
            own.key = NS.DataTextBarStyleKey(bar, rule.key)
            own.enableKey = rule.enableKey and NS.DataTextBarStyleKey(bar, rule.enableKey) or switch.key
            if own.color then own.hideInColors = true end
            B.Add("dataTexts", own, section, "Bar " .. bar .. " styling")
        end
    end
end

local defaults = { NS.Client.isMainline and { 3, 4, 5 } or { 2, 4, 6 }, { 5, 8, 9 }, { 3, 7, 10 } }
for bar = 1, 3 do
    local prefix, section = "bar" .. bar, "bar" .. bar
    B.Section("dataTexts", section, "Bar " .. bar, {
        Bool(prefix .. "Enabled", "Show bar", bar == 1),
        Number(prefix .. "Width", "Width", NS.Client.isForever and bar == 1 and 340 or 390, 180, 900, 5),
        Number(prefix .. "Height", "Height", NS.Client.isForever and bar == 1 and 28 or 26, 18, 50),
        Choice(prefix .. "Layout", "Slot sizing", NS.Client.isForever and bar == 1 and 2 or 1, { "Equal", "Fit text" }),
        Choice(prefix .. "Visibility", "Visibility", 1, { "Always", "Out of combat", "In combat", "Mouseover" }),
        Choice(prefix .. "Point", "Screen anchor", NS.Client.isForever and bar == 1 and 9 or 8, {
            "Top left", "Top", "Top right", "Left", "Center", "Right", "Bottom left", "Bottom", "Bottom right",
        }),
        Number(prefix .. "X", "Horizontal position", NS.Client.isForever and bar == 1 and -20 or 0, -4000, 4000),
        Number(prefix .. "Y", "Vertical position", NS.Client.isForever and bar == 1 and 20 or 85 + (bar - 1) * 36, -3000, 3000),
    })
    NS.SuiteCatalog.dataTexts.rules[prefix .. "Enabled"].hidden = true
    for slot = 1, 6 do
        B.Add("dataTexts", Choice(prefix .. "Slot" .. slot, "Place " .. slot,
            defaults[bar][slot] or 1, NS.DataTextSources), section, "Bar " .. bar)
    end
    AddBarStyle(bar)
end

for _, rule in ipairs(NS.SuiteCatalog.dataTexts.controls) do
    if rule.section and rule.section:match("^bar[123]$") and not rule.key:match("Enabled$") then
        rule.enableKey = rule.section .. "Enabled"
    end
end

-- Resolve only on settings/profile transitions. Timed data updates use the
-- prepared style attached to each bar.
function NS.DataTextEffectiveStyle(config, bar)
    local prefix = config["bar" .. bar .. "StyleOverride"] and "bar" .. bar or nil
    local function Value(key) return config[prefix and NS.DataTextBarStyleKey(bar, key) or key] end
    local palette = NS.DataTextLooks[Value("look")] or NS.DataTextLooks[initialLook]
    local custom = Value("customColors") == true
    local function ColorValue(key) return custom and Value(key .. "Color") or palette[key] end
    return {
        backgroundEnabled = Value("backgroundEnabled"), backgroundTexture = Value("backgroundTexture"),
        backgroundOpacity = Value("backgroundOpacity"), backgroundColor = ColorValue("background"),
        borderEnabled = Value("borderEnabled"), borderSize = Value("borderSize"), borderColor = ColorValue("border"),
        accentEnabled = Value("accentEnabled"), accentColor = ColorValue("accent"),
        separatorEnabled = Value("separatorEnabled"), separatorSize = Value("separatorSize"),
        separatorColor = ColorValue("separator"), padding = Value("padding"), gap = Value("gap"),
        font = Value("font"), fontSize = Value("fontSize"), textOutline = Value("textOutline"),
        textAlign = Value("textAlign"), showLabels = Value("showLabels"),
        labelColor = ColorValue("label"), valueColor = ColorValue("value"), warningColor = ColorValue("warning"),
    }
end
