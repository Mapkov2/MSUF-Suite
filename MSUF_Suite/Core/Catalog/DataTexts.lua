local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_DataTexts")
local Choice, Bool, Number, Color, Font, Texture = B.Choice, B.Bool, B.Number, B.Color, B.Font, B.Texture

NS.DataTextSources = {
    "None", "Gold", "Bag space", "Durability", "Clock", "FPS", "Latency", "Coordinates", "Location", "XP", "Session gold", "Date", "FPS / latency",
}
NS.DataTextSourceKeys = {
    false, "gold", "bags", "durability", "clock", "fps", "latency", "coordinates", "location", "xp", "sessionGold", "date", "fpsLatency",
}
-- Bounds imported configurations to at most 1536 place buttons.
-- Frames are acquired on demand and recycled across profile transitions.
NS.DataTextBarLimit = 256
for _, source in ipairs({ { "Broker plugin", "broker" }, { "Currency", "currency" }, { "Crests", "crests" },
    { "Item level", "itemLevel" }, { "Professions", "professions" }, { "Specialization", "specialization" },
    { "Audio volume", "audio" }, { "Hearthstone", "hearth" }, { "XP / reputation", "progress" },
    { "Dungeon portals", "portals" }, { "Micro menu", "microMenu" } }) do
    NS.DataTextSources[#NS.DataTextSources + 1] = source[1]
    NS.DataTextSourceKeys[#NS.DataTextSourceKeys + 1] = source[2]
end
NS.DataTextPoints = NS.AnchorPoints
-- The choice values of the bar and source settings below (each is its
-- label's position there); the DataTexts runtime names its modes through these.
NS.DataTextVisibility = { ALWAYS = 1, OUT_OF_COMBAT = 2, IN_COMBAT = 3, MOUSEOVER = 4 }
NS.DataTextLayout = { EQUAL = 1, FIT = 2 }
NS.DataTextPlacement = { FLOW = 1, CENTER = 2, FILL = 3 }
NS.DataTextDock = { FREE = 1, TOP = 2, BOTTOM = 3, LEFT = 4, RIGHT = 5 }
NS.DataTextAccentPosition = { BOTTOM = 1, TOP = 2 }
NS.DataTextCrestMode = { OBSERVED = 1, SELECTED = 2 }

function NS.CenterDefaultDataTexts(modules)
    local data = modules.dataTexts
    -- The Retail Suite installer once placed this bar at the right edge.
    -- Change only its untouched coordinates; Forever uses that edge on purpose.
    if type(data) == "table" and data.bar1Point == 9
        and data.bar1X == 0 and data.bar1Y == 170 then
        data.bar1Point = 8
    end
end
-- The same player-state choices as the unit-frame Visibility. Every bar
-- owns its settings so one information strip can stay visible independently.
NS.DataTextLoadConditions = {
    { "HideInHousing", "Housing" },
    { "HideInCombat", "In combat", "[combat] hide" },
    { "HideInGroup", "In group", "[group] hide" },
    { "HideInInstance", "In instance" },
    { "HideInVehicle", "In vehicle", "[@player,unithasvehicleui] hide; [vehicleui] hide" },
    { "HideMounted", "Mounted", "[mounted] hide" },
    { "HideNoTarget", "No target", "[@target,noexists] hide" },
    { "HideOutOfCombat", "Out of combat", "[nocombat] hide" },
    { "HideOutOfCombatNoTarget", "Out of combat and no target", "[nocombat,@target,noexists] hide" },
    { "HideResting", "Resting", "[resting] hide" },
    { "HideSolo", "Solo", "[nogroup] hide" },
    { "HideStealthed", "Stealthed", "[stealth] hide" },
    { "ShowWhenInjured", "Show only below 100% health" },
}
NS.DataTextLooks = {
    { background = "0a1220", border = "41627a", accent = "57c7df", label = "a9ccdf",
      value = "f4f7fb", separator = "41627a", warning = "ff7575" },
    { background = "151719", border = "575b58", accent = "b9ab86", label = "d8ceb5",
      value = "e9e9e4", separator = "555a56", warning = "ed8d80" },
    { background = "14181b", border = "9f8960", accent = "d8b66a", label = "d8b66a",
      value = "f4f3eb", separator = "727774", warning = "ed8d80" },
    [5] = { background = "101010", border = "333333", accent = "e6ecf2", label = "bfc4c9",
      value = "f5f5f5", separator = "333333", warning = "ed8d80" },
}
NS.DataTextLooks[6] = B.ClassPreset(NS.DataTextLooks[5], {
    border = "border", separator = "border", accent = "accent", label = "label",
})
local initialLook = NS.Client.isForever and 3 or 2
local initial = NS.DataTextLooks[initialLook]
local function Capital(key) return key:sub(1, 1):upper() .. key:sub(2) end
function NS.DataTextBarStyleKey(bar, key) return "bar" .. bar .. Capital(key) end

B.Module("dataTexts", {
    title = "DataTexts",
    description = "Movable information bars with individually chosen data sources.",
    core = NS.Client.isForever, optIn = not NS.Client.isForever,
    page = "suite_dataTexts",
    summary = "look barLook barWidth barHeight barVisibility barFontSize fontSize textAlign backgroundEnabled"
        .. " backgroundOpacity trackAltGold hideBlizzardBagBar",
})
-- New Forever setups use the small information strip shown by the selected
-- look. Existing profiles keep their explicit module switch and placement.
NS.SuiteCatalog.dataTexts.rules.enabled.default = true
-- A global look selects its palette for the shared style and for every bar
-- with its own style, and drops custom colors that would hide it.
NS.SuiteCatalog.dataTexts.look = {
    key = "look", global = true,
    extra = function(values, lookIndex, config)
        values.customColors = false
        for _, bar in ipairs(NS.DataTextBarIDs(config)) do
            if config["bar" .. bar .. "StyleOverride"] then
                values["bar" .. bar .. "Look"] = lookIndex
                values["bar" .. bar .. "CustomColors"] = false
            end
        end
    end,
}

local barStyle = {
    Choice("look", "MSUF style", initialLook, { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Custom", "Clean Modern", "Class Style" }),
    Bool("backgroundEnabled", "Show background", true),
    Texture("backgroundTexture", "Background texture"),
    Number("backgroundOpacity", "Background opacity (percent)", NS.Client.isForever and 94 or 82, 0, 100, 5),
    Bool("backgroundGradient", "Fade background vertically", false),
    Color("backgroundFadeColor", "Background fade color", "10283a"),
    Bool("borderEnabled", "Show outline", true),
    Number("borderSize", "Outline thickness", 1, 1, 4),
    Bool("accentEnabled", "Show accent line", true),
    Choice("accentPosition", "Accent position", 1, { "Bottom", "Top" }),
    Bool("separatorEnabled", "Separate places", false),
    Number("separatorSize", "Separator thickness", 1, 1, 3),
    Number("padding", "Text padding", 5, 0, 20),
    Number("gap", "Space between places", 0, 0, 20),
    Bool("bagBadge", "Show bag medallion", false),
    Number("bagBadgeSize", "Bag medallion size", 68, 36, 96),
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
    Choice("fontRendering", "Font rendering", NS.FontRendering.SLUG, { "Smooth", "Sharp / pixel", "Slug" }),
    Bool("fontShadow", "Text shadow"),
    Number("fontShadowOpacity", "Shadow opacity (percent)", 100, 20, 100, 5),
    Choice("fontShadowDistance", "Shadow distance", 1, { "1 px", "2 px" }),
    Choice("textAlign", "Text alignment", 2, { "Left", "Center", "Right" }),
    Bool("showLabels", "Show data names", true),
    Bool("labelColon", "Colon after data names", true),
    Bool("clockLabel", "Show Time before clock", true),
    Bool("bagsPercent", "Show used bag space as percent", false),
    Color("labelColor", "Label color", initial.label),
    Color("valueColor", "Value color", initial.value),
    Bool("valueClassColor", "Use class color for values", false),
    Color("warningColor", "Warning color", initial.warning),
}
local dependencies = {
    backgroundTexture = "backgroundEnabled", backgroundOpacity = "backgroundEnabled",
    backgroundFadeColor = "backgroundGradient", borderSize = "borderEnabled",
    accentPosition = "accentEnabled", separatorSize = "separatorEnabled",
    bagBadgeSize = "bagBadge",
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
-- After the dependency table, which would clear the shadow's enable keys;
-- each bar's own style copies the linked rules below.
B.LinkFontShadow(NS.SuiteCatalog.dataTexts.rules)
B.Section("dataTexts", "bags", "Blizzard bag buttons", {
    Bool("hideBlizzardBagBar", "Hide Blizzard bag buttons; use the Bag space DataText", true),
})
B.Section("dataTexts", "gold", "Gold across characters", {
    Bool("trackAltGold", "Remember this character's gold for the account total", false),
})
B.Section('dataTexts', 'sources', 'Additional data sources', {
    Bool('itemLevelEquipped', 'Show equipped item level', true),
    Number('itemLevelDecimals', 'Item level decimals', 1, 0, 2),
    Choice('audioChannel', 'Audio channel', 1, { 'Master', 'Sound effects', 'Music', 'Ambience', 'Dialog' }),
    B.String('hearthItems', 'Hearthstone item / toy IDs in preference order', '6948', 1000),
    Bool('randomHearth', 'Choose a random owned Hearthstone variant for the next click', false),
    B.String('crestCurrencies', 'Observed seasonal upgrade stages in display order (empty = all)', '', 256),
    Choice('crestMode', 'Crest selection source', 1, { 'Observed upgrade stages', 'Selected crest currencies' }),
    B.String('crestCurrencyIDs', 'Selected crest currency IDs in display order', '', 1000),
    B.String('crestSeparator', 'Separator between Crest amounts', ' / ', 20),
    Bool('showTokenPrice', 'Show the native WoW Token market price in Gold tooltips', false),
})

-- Settings are copied from the shared style when an override is switched on.
local function AddBarStyle(bar)
    local prefix, section = "bar" .. bar, "bar" .. bar .. "Style"
    local title = NS.Text("Bar %d styling"):format(bar)
    local switch = Bool(prefix .. "StyleOverride", "Own style", false)
    switch.hidden = true
    switch.enableKey = prefix .. "Enabled"
    B.Add("dataTexts", switch, section, title)
    for _, group in ipairs({ barStyle, textStyle }) do
        for _, rule in ipairs(group) do
            local own = {}
            for field, value in pairs(rule) do own[field] = value end
            own.key = NS.DataTextBarStyleKey(bar, rule.key)
            own.enableKey = rule.enableKey and NS.DataTextBarStyleKey(bar, rule.enableKey) or switch.key
            if rule.requiresChoice then
                own.requiresChoice = { key = NS.DataTextBarStyleKey(bar, rule.requiresChoice.key),
                    values = rule.requiresChoice.values }
            end
            B.Add("dataTexts", own, section, title)
        end
    end
end

local defaults = { { 3, 4, 5 }, { 5, 8, 9 }, { 3, 7, 10 } }
for bar = 1, 12 do
    -- Section titles are built here, so their format strings translate here.
    local prefix, section, title = "bar" .. bar, "bar" .. bar, NS.Text("Bar %d"):format(bar)
    B.Section("dataTexts", section, title, {
        B.String(prefix .. 'Name', 'Bar name', NS.Text('Bar %d'):format(bar), 64),
        Bool(prefix .. 'Vertical', 'Vertical bar', false),
        Bool(prefix .. 'FullScreen', 'Span the entire screen width or height', false),
        Choice(prefix .. 'Dock', 'Snap to screen edge', 1, { 'Free', 'Top', 'Bottom', 'Left', 'Right' }),
        Bool(prefix .. "Enabled", "Show bar", bar == 1),
        Number(prefix .. "Width", "Width", NS.Client.isForever and bar == 1 and 340 or 390, 180, 900, 5),
        Number(prefix .. "Height", "Height", NS.Client.isForever and bar == 1 and 28 or 26, 18, 100),
        Choice(prefix .. "Layout", "Slot sizing", NS.Client.isForever and bar == 1 and 2 or 1, { "Equal", "Fit text" }),
        Choice(prefix .. "Visibility", "Visibility", 1, { "Always", "Out of combat", "In combat", "Mouseover" }),
        Number(prefix .. "Layer", "MSUF layer (-1 = Auto)", -1, -1, 30),
        Choice(prefix .. "Point", "Screen anchor", NS.Client.isForever and bar == 1 and 9 or 8, NS.AnchorLabels),
        Number(prefix .. "X", "Horizontal position", NS.Client.isForever and bar == 1 and -20 or 0, -4000, 4000),
        Number(prefix .. "Y", "Vertical position", NS.Client.isForever and bar == 1 and 20 or 85 + (bar - 1) * 36, -3000, 3000),
    })
    NS.SuiteCatalog.dataTexts.rules[prefix .. "Enabled"].hidden = true
    for slot = 1, 6 do
        B.Add("dataTexts", Choice(prefix .. "Slot" .. slot, NS.Text("Place %d"):format(slot),
            defaults[bar] and defaults[bar][slot] or 1, NS.DataTextSources), section, title)
        -- Format-string labels: each translates once, then takes the place number.
        local block, target = prefix .. "Slot" .. slot, prefix .. "Blocks"
        local function Label(format) return NS.Text(format):format(slot) end
        B.Add("dataTexts", B.String(block .. "Broker", Label("Place %d broker name"), "", 100), target, title)
        B.Add("dataTexts", Number(block .. "Currency", Label("Place %d currency ID"), 0, 0, 100000), target, title)
        B.Add("dataTexts", Number(block .. "MaxWidth", Label("Place %d maximum broker width"), 180, 40, 600),
            target, title)
        B.Add("dataTexts", Choice(block .. "Placement", Label("Place %d position"), 1,
            { "Flow", "Exact center", "Fill remaining space" }), target, title)
        B.Add("dataTexts", Number(block .. "Padding", Label("Place %d padding"), 5, 0, 30), target, title)
        B.Add("dataTexts", Color(block .. "Background", Label("Place %d background"), "101010"), target, title)
        B.Add("dataTexts", Number(block .. "Alpha", Label("Place %d background opacity"), 0, 0, 100), target, title)
        B.Add("dataTexts", Color(block .. "IconColor", Label("Place %d icon color"), "ffffff"), target, title)
        B.Add("dataTexts", Number(block .. "Scale", Label("Place %d scale"), 100, 50, 200, 5), target, title)
    end
    for _, condition in ipairs(NS.DataTextLoadConditions) do
        local rule = Bool(prefix .. "LoadCond" .. condition[1], condition[2], false)
        rule.enableKey = prefix .. "Enabled"
        B.Add("dataTexts", rule, prefix .. "Load", NS.Text("Bar %d Visibility"):format(bar))
    end
    AddBarStyle(bar)
end

local spec = NS.SuiteCatalog.dataTexts
B.Add("dataTexts", B.String("barIds", "Configured bar IDs", "", 2048)).hidden = true
local templates, templateOrder, dynamic, dynamicOrder = {}, {}, {}, {}
local dynamicCursor = 1
for _, rule in ipairs(spec.controls) do
    local suffix = rule.key:match("^bar12(.+)$")
    if suffix then
        templates[suffix] = rule
        templateOrder[#templateOrder + 1] = suffix
    end
end
local function ValidID(value)
    local id = tonumber(value)
    return id and id >= 1 and id <= 1000000 and id == math.floor(id) and id or nil
end
local function DynamicRule(id, suffix)
    local rules = dynamic[id]
    if not rules then
        local retired = dynamicOrder[dynamicCursor]
        if retired then dynamic[retired] = nil end
        dynamicOrder[dynamicCursor] = id
        dynamicCursor = dynamicCursor % NS.DataTextBarLimit + 1
        rules = {}
        dynamic[id] = rules
    end
    local prefix = "bar" .. id
    local key = prefix .. suffix
    if not rules[key] then
        local template = templates[suffix]
        local rule = {}
        for field, value in pairs(template) do rule[field] = value end
        rule.key = key
        rule.section = template.section:gsub("^bar12", prefix)
        rule.sectionTitle = NS.Text("Bar %d"):format(id)
        if rule.enableKey then rule.enableKey = rule.enableKey:gsub("^bar12", prefix) end
        if rule.requiresChoice then
            rule.requiresChoice = { key = rule.requiresChoice.key:gsub("^bar12", prefix), values = rule.requiresChoice.values }
        end
        if suffix == "Name" then rule.default = NS.Text("Bar %d"):format(id) end
        rules[rule.key] = rule
    end
    return rules[key]
end
setmetatable(spec.rules, { __index = function(_, key)
    if type(key) ~= "string" then return end
    local raw, suffix = key:match("^bar(%d+)(.+)$")
    local id = ValidID(raw)
    if id and id > 12 and tostring(id) == raw and templates[suffix] then return DynamicRule(id, suffix) end
end })
function NS.DataTextBarIDs(config)
    local ids, seen = {}, {}
    local function Add(raw)
        local id = ValidID(raw)
        if id and not seen[id] and #ids < NS.DataTextBarLimit then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    if type(config.barIds) == "string" and config.barIds ~= "" then
        for raw in config.barIds:gmatch("%d+") do Add(raw) end
    else
        Add(1)
        Add(2)
        Add(3)
        for id = 4, 12 do
            local prefix = "bar" .. id
            for suffix in pairs(templates) do
                local key = prefix .. suffix
                if config[key] ~= nil and config[key] ~= spec.rules[key].default then
                    Add(id)
                    break
                end
            end
        end
    end
    -- Individual variant overrides can activate a bar without replacing the
    -- base list. Removed bars also switch their Enabled setting off.
    for key, value in pairs(config) do
        if value == true and type(key) == "string" then Add(key:match("^bar(%d+)Enabled$")) end
    end
    table.sort(ids)
    return ids
end
local controlMaps = setmetatable({}, { __mode = "k" })
local function ControlMap(config, force)
    local record = controlMaps[config]
    if record and not force and record.signature == config.barIds then return record end
    record = { signature = config.barIds, present = {}, enabled = {} }
    for _, id in ipairs(NS.DataTextBarIDs(config)) do record.present[id] = true end
    for key, value in pairs(config) do
        local raw = type(key) == "string" and key:match("^bar(%d+)Enabled$")
        if raw then record.enabled[tonumber(raw)] = value end
    end
    controlMaps[config] = record
    return record
end
spec.controlAvailable = function(rule, config)
    local id = tonumber(rule.key:match("^bar(%d+)"))
    if not id then return true end
    local record = ControlMap(config)
    if record.enabled[id] ~= config["bar" .. id .. "Enabled"] then record = ControlMap(config, true) end
    if (config.barIds == nil or config.barIds == "") and id >= 4 and id <= 12 then
        -- Legacy customizations can create a retained bar without an ID list.
        -- These twelve templates are bounded and require no list allocation.
        local prefix = "bar" .. id
        for suffix in pairs(templates) do
            local key = prefix .. suffix
            if config[key] ~= nil and config[key] ~= spec.rules[key].default then return true end
        end
        return false
    end
    return record.present[id] == true
end
spec.getControls = function(config)
    local out = {}
    local present = ControlMap(config, true).present
    for _, rule in ipairs(spec.controls) do
        if not rule.key:match("^bar%d+") then out[#out + 1] = rule end
    end
    local ids = {}
    for id in pairs(present) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        for _, suffix in ipairs(templateOrder) do out[#out + 1] = spec.rules["bar" .. id .. suffix] end
    end
    return out
end
function NS.DataTextNextBarID(config)
    local ids = NS.DataTextBarIDs(config)
    if #ids >= NS.DataTextBarLimit then return end
    local seen = {}
    for _, id in ipairs(ids) do
        seen[id] = true
    end
    for id = 1, #ids + 1 do if not seen[id] then return id end end
end
function NS.DataTextBarCreationValues(config, id)
    local ids = NS.DataTextBarIDs(config)
    ids[#ids + 1] = id
    table.sort(ids)
    local values = { barIds = table.concat(ids, ",") }
    for suffix in pairs(templates) do
        local key = "bar" .. id .. suffix
        values[key] = spec.rules[key].default
    end
    values["bar" .. id .. "Enabled"] = true
    return values
end
function NS.DataTextBarRemovalValues(config, id)
    local ids = {}
    for _, current in ipairs(NS.DataTextBarIDs(config)) do if current ~= id then ids[#ids + 1] = current end end
    return { barIds = #ids > 0 and table.concat(ids, ",") or "0", ["bar" .. id .. "Enabled"] = false }
end
spec.prepareConfig = function(config)
    local check = NS.Suite.CheckProfileValue
    local function Repaired(rule, value)
        local checked = check(rule, value)
        if checked ~= nil then
            return checked
        end
        return rule.default
    end
    -- Physical rules stay legacy-only; lazy rules never seed another profile.
    for key, value in pairs(config) do
        local raw = type(key) == "string" and key:match("^bar(%d+).+")
        local id = ValidID(raw)
        if id and id > 12 then
            local rule = spec.rules[key]
            if rule then config[key] = Repaired(rule, value) end
        end
    end
    for _, id in ipairs(NS.DataTextBarIDs(config)) do
        if id > 12 then
            for _, suffix in ipairs(templateOrder) do
                local key = "bar" .. id .. suffix
                local rule = spec.rules[key]
                local value = config[key]
                config[key] = Repaired(rule, value)
            end
        end
    end
end

-- A per-bar starting point based on the three-source antique footer. The
-- resulting ordinary settings remain editable, and other bars are untouched.
function NS.DataTextAntiqueFooterValues(bar, config)
    local prefix, values = "bar" .. bar, { enabled = true }
    values[prefix .. "Enabled"] = true
    values[prefix .. "Width"] = 380
    values[prefix .. "Height"] = 36
    values[prefix .. "Layout"] = 1
    values[prefix .. "StyleOverride"] = true
    for slot = 1, 6 do values[prefix .. "Slot" .. slot] = ({ 3, 4, 5 })[slot] or 1 end
    for _, key in ipairs(NS.DataTextStyleKeys) do
        values[NS.DataTextBarStyleKey(bar, key)] = config[key]
    end
    local ornate = {
        backgroundEnabled = true, backgroundTexture = "", backgroundOpacity = 100,
        backgroundGradient = true, backgroundColor = "06101c", backgroundFadeColor = "153247",
        borderEnabled = true, borderSize = 1, borderColor = "3c5260",
        accentEnabled = true, accentPosition = 2, accentColor = "c49a55",
        separatorEnabled = true, separatorSize = 1, separatorColor = "715a3b",
        padding = 5, gap = 0, bagBadge = true, bagBadgeSize = 38,
        customColors = true, fontSize = 11, textAlign = 2, showLabels = true,
        labelColon = false, clockLabel = false, bagsPercent = true,
        labelColor = "d6aa69", valueColor = "d6aa69", warningColor = "ff8b74",
        valueClassColor = false,
    }
    for key, value in pairs(ornate) do
        values[NS.DataTextBarStyleKey(bar, key)] = value
    end
    return values
end

for _, rule in ipairs(NS.SuiteCatalog.dataTexts.controls) do
    if rule.section and rule.section:match("^bar%d+$") and not rule.key:match("Enabled$") then
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
        backgroundGradient = Value("backgroundGradient"), backgroundFadeColor = Value("backgroundFadeColor"),
        borderEnabled = Value("borderEnabled"), borderSize = Value("borderSize"), borderColor = ColorValue("border"),
        accentEnabled = Value("accentEnabled"), accentPosition = Value("accentPosition"),
        accentColor = ColorValue("accent"),
        separatorEnabled = Value("separatorEnabled"), separatorSize = Value("separatorSize"),
        separatorColor = ColorValue("separator"), padding = Value("padding"), gap = Value("gap"),
        bagBadge = Value("bagBadge"), bagBadgeSize = Value("bagBadgeSize"),
        font = Value("font"), fontSize = Value("fontSize"), textOutline = Value("textOutline"),
        fontRendering = Value("fontRendering"), fontShadow = Value("fontShadow"),
        fontShadowOpacity = Value("fontShadowOpacity"), fontShadowDistance = Value("fontShadowDistance"),
        textAlign = Value("textAlign"), showLabels = Value("showLabels"),
        labelColon = Value("labelColon"), clockLabel = Value("clockLabel"), bagsPercent = Value("bagsPercent"),
        labelColor = ColorValue("label"), valueColor = ColorValue("value"), warningColor = ColorValue("warning"),
        valueClassColor = Value("valueClassColor"),
    }
end
