local _, NS = ...

local Card, Safety, Palette = {}, NS.Safety, NS.TooltipPalette
NS.ItemTooltipCard = Card

local defaults = NS.Defaults.theme.tooltipLayout
local limits = { iconSize = { 16, 38 }, x = { 4, 64 }, y = { -14, 14 }, height = { 36, defaults.height },
    borderWidth = { 1, 4 }, unitHealthHeight = { 8, 36 }, unitPowerHeight = { 8, 36 },
    unitHealthTextSize = { 0, 32 }, unitHealthTextX = { -150, 150 }, unitHealthTextY = { -100, 100 } }
local unitFields = { "unitHealth", "unitPower", "unitValueText", "unitHealthTextFormat", "unitHealthTextFont",
    "unitHealthTextSize", "unitHealthTextColor", "unitHealthTextX", "unitHealthTextY" }
local unitBars = { unitHealth = true, unitPower = true }
local unitColors = { unitHealthTextColor = true }
for prefix in pairs(unitBars) do
    limits[prefix .. "Width"] = { 25, 150 }
    limits[prefix .. "X"] = { -150, 150 }
    limits[prefix .. "Y"] = { -100, 100 }
    for _, suffix in ipairs({ "Height", "Width", "X", "Y", "Texture", "Background", "Color", "BackgroundColor" }) do
        unitFields[#unitFields + 1] = prefix .. suffix
    end
    unitColors[prefix .. "Color"] = true
    unitColors[prefix .. "BackgroundColor"] = true
end
local presets = {
    compact = {},
    detailed = { borderMode = "title" },
    minimal = { rule = false, icon = false, kind = false, height = 36 },
    dense = { iconSize = 24, x = 6, height = 40, headerColor = { .08, .10, .14, 1 } },
}
local types = { item = "itemStyle", spell = "spellStyle", unit = "unitStyle", quest = "questStyle", loot = "lootStyle" }
local borderModes = { suite = true, title = true, custom = true, native = true }
local surfaceModes = {
    cardSurface = { unified = true, split = true }, lootSurface = { auto = true, match = true, native = true },
    paletteDirection = { VERTICAL = true, HORIZONTAL = true },
    unitHealth = { native = true, show = true, hide = true },
    unitHealthTextFormat = { [""] = true, off = true, value = true, percent = true },
}
local function Setting(field)
    local settings = NS.DB.theme.tooltipLayout
    local value
    if type(settings) == "table" then value = settings[field] end
    if type(value) == type(defaults[field]) and (not surfaceModes[field] or surfaceModes[field][value]) then
        local limit = limits[field]
        if not limit or (value >= limit[1] and value <= limit[2]) then return value end
    end
    return defaults[field]
end
Card.Setting = Setting
function Card.HeaderHeight() return Setting("height") end

local function PresetTypeStyle(preset)
    return preset == "compact" and "suite" or "custom"
end

function Card.TypeStyleChoice(kind)
    local settings = NS.DB.theme.tooltipLayout
    local saved = type(settings) == "table" and settings[types[kind]]
    if saved == "custom" or saved == "suite" then return saved end
    return "inherit"
end

function Card.TypeStyle(kind)
    local choice = Card.TypeStyleChoice(kind)
    if choice ~= "inherit" then return choice end
    local base = Setting("presetBase")
    if base and base ~= "" then return PresetTypeStyle(base) end
    if kind == "loot" then return "suite" end
    if kind == "quest" then return Card.TypeStyle("unit") end
    local legacy = NS.DB.theme.itemTooltipStyle == "card" and (kind == "unit" or Setting(kind))
    return legacy and "custom" or "suite"
end

function Card.MatchesLootSurface()
    local mode = Setting("lootSurface")
    return mode == "match" or mode == "auto" and Card.TypeStyle("loot") == "custom"
end

local function LayoutSettings()
    local theme = NS.DB.theme
    if type(theme.tooltipLayout) ~= "table" then theme.tooltipLayout = {} end
    return theme.tooltipLayout
end

function Card.SetTypeStyle(kind, value)
    if NS.IsCombatLocked() or not Safety.Public(kind) or not Safety.Public(value) or not types[kind]
        or (value ~= "custom" and value ~= "suite" and value ~= "inherit") then return false end
    if Card.TypeStyleChoice(kind) == value then return true end
    local settings = LayoutSettings()
    settings[types[kind]] = value ~= "inherit" and value or nil
    settings.preset = "custom"
    NS.Registry.NotifyListeners("tooltipStyle", kind)
    return true
end

local function MatchPreviewType(settings, kind)
    if Safety.Public(kind) and types[kind] and Card.TypeStyle(kind) ~= "custom" then settings[types[kind]] = "custom" end
end

function Card.Set(field, value, kind)
    if NS.IsCombatLocked() or not Safety.Public(field) or not Safety.Public(value)
        or type(field) ~= "string" or field == "preset" or field == "presetBase" or field == "headerColor" or defaults[field] == nil
        or field == "borderColor" or Palette.fields[field] or unitColors[field]
        or field == "itemStyle" or field == "spellStyle"
        or field == "unitStyle" or field == "questStyle" or field == "lootStyle"
        or type(value) ~= type(defaults[field]) then return false end
    if field == "borderMode" and not borderModes[value] then return false end
    if surfaceModes[field] and not surfaceModes[field][value] then return false end
    local limit = limits[field]
    if limit and (value ~= value or value < limit[1] or value > limit[2]) then return false end
    if not Safety.Public(kind) or kind ~= nil and Setting(field) == value then return false end
    local settings = LayoutSettings()
    settings[field], settings.preset = value, "custom"
    MatchPreviewType(settings, kind)
    NS.Registry.NotifyListeners("tooltipStyle", field)
    return true
end

function Card.SetOffsets(x, y, kind)
    if NS.IsCombatLocked() or not Safety.Public(x) or not Safety.Public(y)
        or type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return false end
    x = math.max(limits.x[1], math.min(limits.x[2], math.floor(x + .5)))
    y = math.max(limits.y[1], math.min(limits.y[2], math.floor(y + .5)))
    if x == Setting("x") and y == Setting("y") then return false end
    local settings = LayoutSettings()
    settings.x, settings.y, settings.preset = x, y, "custom"
    MatchPreviewType(settings, kind)
    NS.Registry.NotifyListeners("tooltipStyle", "position")
    return true
end

local function ClampBarDimension(field, value)
    local range = limits[field]
    return math.max(range[1], math.min(range[2], math.floor(value + .5)))
end

local function SetBarPair(prefix, first, second, a, b)
    if NS.IsCombatLocked() or not Safety.Public(prefix) or not (unitBars[prefix] or prefix == "unitHealthText" and first == "X")
        or not Safety.Public(a) or not Safety.Public(b) or type(a) ~= "number" or type(b) ~= "number"
        or a ~= a or b ~= b then return false end
    local keyA, keyB = prefix .. first, prefix .. second
    a, b = ClampBarDimension(keyA, a), ClampBarDimension(keyB, b)
    if a == Setting(keyA) and b == Setting(keyB) then return false end
    local settings = LayoutSettings()
    settings[keyA], settings[keyB], settings.preset = a, b, "custom"
    NS.Registry.NotifyListeners("tooltipStyle", prefix)
    return true
end

function Card.SetUnitBarOffsets(prefix, x, y) return SetBarPair(prefix, "X", "Y", x, y) end
function Card.SetUnitBarSize(prefix, width, height) return SetBarPair(prefix, "Width", "Height", width, height) end

local function Channel(value)
    return Safety.Public(value) and type(value) == "number" and value >= 0 and value <= 1
end

local function GetColor(key)
    local rgba = Setting(key)
    if canaccesstable(rgba) and Channel(rgba[1]) and Channel(rgba[2]) and Channel(rgba[3]) and Channel(rgba[4]) then
        return unpack(rgba, 1, 4)
    end
    return unpack(defaults[key])
end

local function SetColor(key, r, g, b, a)
    if NS.IsCombatLocked() or not (Channel(r) and Channel(g) and Channel(b) and Channel(a)) then return false end
    local settings = LayoutSettings()
    settings[key], settings.preset = { r, g, b, a }, "custom"
    if key == "borderColor" then settings.borderMode = "custom" end
    if Palette.fields[key] then settings.palette = true end
    NS.Registry.NotifyListeners("tooltipStyle", key)
    return true
end

function Card.HeaderColor() return GetColor("headerColor") end
function Card.BorderColor() return GetColor("borderColor") end
function Card.SetHeaderColor(...) return SetColor("headerColor", ...) end
function Card.SetBorderColor(...) return SetColor("borderColor", ...) end
function Card.UnitBarColor(key) return GetColor(key) end
function Card.SetUnitBarColor(key, ...)
    if Safety.Public(key) and unitColors[key] then return SetColor(key, ...) end
    return false
end

function Card.SetPaletteColor(key, ...)
    if Safety.Public(key) and Palette.fields[key] then return SetColor(key, ...) end
    return false
end

function Card.SetPreset(key, resetSurface, usePresetStyles)
    if NS.IsCombatLocked() or not Safety.Public(key) or type(key) ~= "string" then return false end
    local style = presets[key] or Palette.BuildPreset(key)
    if key ~= "custom" and not style then return false end
    local theme, item, spell, unit = NS.DB.theme, Card.TypeStyle("item"), Card.TypeStyle("spell"), Card.TypeStyle("unit")
    local loot, quest = Card.TypeStyle("loot"), Setting("questStyle")
    local cardSurface, lootSurface = Setting("cardSurface"), Setting("lootSurface")
    local backgroundTexture, headerTexture = Setting("backgroundTexture"), Setting("headerTexture")
    local previous = theme.tooltipLayout
    local vitals = {}
    for _, field in ipairs(unitFields) do vitals[field] = NS.CopyValue(Setting(field)) end
    local base = Setting("presetBase")
    if key == "custom" then
        LayoutSettings().preset = "custom"
    else
        theme.tooltipLayout = NS.CopyValue(style)
        local nextLayout = theme.tooltipLayout
        nextLayout.preset = key
        if not usePresetStyles and key ~= "compact" and presets[key] and type(previous) == "table" and previous.palette then
            nextLayout.palette, nextLayout.paletteGradient, nextLayout.paletteDirection =
                previous.palette, previous.paletteGradient, previous.paletteDirection
            for field in pairs(Palette.fields) do nextLayout[field] = NS.CopyValue(previous[field]) end
            nextLayout.headerColor = NS.CopyValue(previous.headerColor)
            nextLayout.borderColor = NS.CopyValue(previous.borderColor)
            nextLayout.borderMode = previous.borderMode
        end
    end
    local settings = theme.tooltipLayout
    for field, value in pairs(vitals) do settings[field] = value end
    if usePresetStyles and key ~= "custom" then
        settings.presetBase = key
    elseif key ~= "custom" then
        settings.presetBase = base
        settings.itemStyle, settings.spellStyle, settings.unitStyle, settings.questStyle, settings.lootStyle = item, spell, unit, quest, loot
    end
    if resetSurface then cardSurface, lootSurface = defaults.cardSurface, defaults.lootSurface end
    settings.cardSurface, settings.lootSurface = cardSurface, lootSurface
    if not resetSurface then settings.backgroundTexture, settings.headerTexture = backgroundTexture, headerTexture end
    NS.Registry.NotifyListeners("tooltipStyle", "preset")
    return true
end

function Card.Preset()
    local theme = NS.DB.theme
    local key = Setting("preset")
    if key == "custom" or presets[key] or Palette.HasPreset(key) then return key end
    return theme.itemTooltipStyle == "card" and "custom" or "compact"
end

function Card.PresetChoice()
    local key = Card.Preset()
    if key == "custom" then return key end
    local expected = PresetTypeStyle(key)
    for kind in pairs(types) do
        if Card.TypeStyle(kind) ~= expected then return "custom" end
    end
    return key
end

local layoutFields = { "x", "y", "iconSize", "height", "cardSurface", "lootSurface" }
local appearanceFields = { "backgroundTexture", "headerTexture", "headerColor", "icon", "level", "kind", "tint",
    "rule", "palette", "paletteGradient", "paletteDirection", "borderMode", "borderWidth", "borderColor",
    "fillColor", "endColor", "titleColor", "accentColor" }

local function ResetFields(fields, reason)
    if NS.IsCombatLocked() then return false end
    local settings = LayoutSettings()
    for _, field in ipairs(fields) do settings[field] = nil end
    settings.preset = "custom"
    NS.Registry.NotifyListeners("tooltipStyle", reason)
    return true
end

function Card.ResetLayout() return ResetFields(layoutFields, "layout") end
function Card.ResetAppearance() return ResetFields(appearanceFields, "preset") end

function Card.ResetUnitVitals()
    if NS.IsCombatLocked() then return false end
    local settings = LayoutSettings()
    for _, field in ipairs(unitFields) do settings[field] = nil end
    NS.Registry.NotifyListeners("tooltipStyle", "unit")
    return true
end

function Card.Reset()
    if NS.IsCombatLocked() then return false end
    local theme = NS.DB.theme
    theme.tooltipLayout = NS.CopyValue(defaults)
    theme.itemTooltipStyle = "compact"
    NS.Registry.NotifyListeners("tooltipStyle", "preset")
    return true
end

function Card.Range(field) return unpack(limits[field]) end
