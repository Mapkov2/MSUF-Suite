local _, Suite = ...
local Build = Suite.CatalogBuild
local Appearance = {}
Suite.TooltipAppearance = Appearance

local defaults = {
    preset = "", item = true, spell = false, icon = true, level = true, kind = true,
    itemStyle = "", spellStyle = "", unitStyle = "", questStyle = "", lootStyle = "suite",
    cardSurface = "unified", lootSurface = "auto", backgroundTexture = "", headerTexture = "",
    unitHealth = "native", unitPower = false, unitValueText = false,
    unitHealthTextFormat = "", unitHealthTextFont = "", unitHealthTextSize = 0,
    unitHealthTextColor = { 1, 1, 1, 1 }, unitHealthTextX = 0, unitHealthTextY = 0,
    unitHealthHeight = 12, unitPowerHeight = 10,
    unitHealthColor = { .24, .75, .36, 1 }, unitPowerColor = { .29, .58, .94, 1 },
    unitHealthWidth = 100, unitPowerWidth = 100,
    unitHealthX = 0, unitHealthY = 0, unitPowerX = 0, unitPowerY = 0,
    unitHealthTexture = "", unitPowerTexture = "",
    unitHealthBackground = "", unitPowerBackground = "",
    unitHealthBackgroundColor = { .03, .04, .05, .95 }, unitPowerBackgroundColor = { .03, .04, .05, .95 },
    palette = false, paletteGradient = false, paletteDirection = "VERTICAL",
    fillColor = {}, endColor = {}, titleColor = {}, accentColor = {},
    tint = true, rule = true, iconSize = 30, x = 10, y = 0, height = 48,
    headerColor = { 0.09, 0.10, 0.13, 0 },
    borderMode = "suite", borderWidth = 1, borderColor = { 0.42, 0.52, 0.66, 1 },
}
Appearance.defaults = { tooltipLayout = defaults, itemTooltipStyle = "compact" }

-- Keep only the saved layout fields the renderer understands. Empty palette
-- colors inherit the current look, so they are valid as well as RGBA values.
local function ReadColor(value)
    if type(value) ~= "table" then return end
    local r, g, b, a = value[1], value[2], value[3], value[4]
    if Suite.Finite(r) and Suite.Finite(g) and Suite.Finite(b) and Suite.Finite(a)
        and r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1 and a >= 0 and a <= 1 then
        return { r, g, b, a }
    end
end

local function CopyLayout(source)
    local layout = {}
    for field, default in pairs(defaults) do
        local value = source[field]
        if type(default) == "table" then
            if type(value) == "table" then layout[field] = ReadColor(value) end
        elseif type(value) == type(default) then
            if type(value) == "number" and Suite.Finite(value) or type(value) == "boolean"
                or type(value) == "string" and #value <= 260 then layout[field] = value end
        end
    end
    return layout
end

local id = "tooltipAppearance"
Build.Module(id, {
    addon = "MSUF_Suite_Tooltips", page = "suite_tooltips", title = "Tooltips",
    description = "Show tooltips",
    defaultEnabled = true, core = true,
})
Build.Add(id, { key = "tooltipLayout", default = {}, copy = CopyLayout, hidden = true })
Build.Add(id, { key = "itemTooltipStyle", default = "compact", maxLength = 16, hidden = true })
Build.Add(id, { key = "configured", default = false, hidden = true })

-- A split-out layout is owned by the Suite profile. Import it once when the
-- matching Skinning profile is readable, or let a standalone edit claim it.
function Appearance.ImportLegacy(theme, name)
    if not theme or not Suite.DB or Suite.Database.GetActiveProfileName() ~= name
        or not Suite.DB.suite or Suite.DB.suite.schema ~= 1 then return false end
    local config = Suite.Suite.Config(id)
    if config.configured then return false end
    local layout = type(theme.tooltipLayout) == "table" and CopyLayout(theme.tooltipLayout) or {}
    config.tooltipLayout = layout
    config.itemTooltipStyle = theme.itemTooltipStyle == "card" and "card" or "compact"
    config.configured = true
    return true
end

function Appearance.Engine()
    if not Suite.Client.AddOnEnabled("MSUF_Suite_Tooltips") then return end
    if not Suite.Tooltips and not Suite.InCombat() then
        C_AddOns.LoadAddOn("MSUF_Suite_Tooltips")
    end
    return Suite.Tooltips
end
