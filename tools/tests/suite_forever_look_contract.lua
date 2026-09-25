local root = assert(arg[1], "Suite root required")

local function Engine(isForever)
    local ns = { Client = { isForever = isForever },
        FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" } }
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", ns)
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Database.lua"))("MSUF_Suite_Skin", ns)
    return ns
end

local forever = Engine(true)
assert(forever.Defaults.theme.look == "foreverGlass"
    and forever.Defaults.geometry.radius == 12
    and forever.Defaults.typography.face == "sharedMedia"
    and forever.Defaults.icons.microMenu.positionPreset == "bottomCenter"
    and forever.Defaults.icons.microMenu.layoutPoint == "BOTTOM"
    and forever.Defaults.icons.microMenu.layoutY == 120
    and forever.Defaults.icons.microMenu.buttonBackground == false
    and forever.Defaults.icons.microMenu.buttonsPerLine == 14
    and forever.Defaults.icons.microMenu.spacing == -3,
    "new Forever profile did not get the compact menu look")

local previousStrip = forever.CopyValue(forever.Defaults)
previousStrip.revision = 45
previousStrip.icons.microMenu.buttonsPerLine = 13
previousStrip.icons.microMenu.spacing = 0
forever.Database.Normalize(previousStrip)
assert(previousStrip.icons.microMenu.buttonsPerLine == 14
    and previousStrip.icons.microMenu.spacing == -3,
    "previous Forever factory strip did not receive compact spacing")
local customStrip = forever.CopyValue(previousStrip)
customStrip.revision = 45
customStrip.icons.microMenu.buttonsPerLine = 8
customStrip.icons.microMenu.spacing = 4
forever.Database.Normalize(customStrip)
assert(customStrip.icons.microMenu.buttonsPerLine == 8
    and customStrip.icons.microMenu.spacing == 4,
    "custom Forever Micro Bar rows or spacing were overwritten")

local legacy = forever.CopyValue(forever.Defaults)
legacy.revision = 36
legacy.theme.gradientStrength = 0.50
legacy.theme.materialDepth = 0.14
legacy.theme.shellOpacity = 0.92
legacy.theme.panelOpacity = 0.92
legacy.theme.controlOpacity = 0.96
legacy.theme.borderOpacity = 0.72
legacy.theme.hoverStyle = "softFill"
legacy.theme.hoverIntensity = 0.68
legacy.theme.colors.background[4] = forever.PresetOverrides.glass.background[4]
legacy.geometry.radius = 12
local micro = legacy.icons.microMenu
micro.positionPreset = "bottomRight"
micro.layoutPoint, micro.layoutRelativePoint = "BOTTOMRIGHT", "BOTTOMRIGHT"
micro.layoutX, micro.layoutY = -24, 24
micro.barBorder, micro.padding = 2, 3
micro.buttonBackground, micro.buttonBorder = true, 1
micro.iconSize, micro.spacing = 20, 3
micro.iconStyle = "line"
forever.Database.Normalize(legacy)
assert(legacy.revision == 50 and legacy.geometry.radius == 12
    and legacy.theme.shellOpacity == 0.92 and legacy.theme.hoverStyle == "softFill"
    and legacy.theme.colors.background[4] == forever.PresetOverrides.foreverGlass.background[4]
    and micro.positionPreset == "bottomCenter" and micro.layoutX == 0 and micro.layoutY == 120
    and micro.barBorder == 1 and micro.padding == 5
    and not micro.buttonBackground and micro.buttonBorder == 0
    and micro.iconStyle == "bold",
    "old Forever Micro Bar did not receive the new compact look")

local retired = forever.CopyValue(forever.Defaults)
retired.revision = 38
retired.theme.gradientStrength, retired.theme.materialDepth = 0.16, 0.06
retired.theme.shellOpacity, retired.theme.panelOpacity = 0.99, 0.97
retired.theme.controlOpacity, retired.theme.borderOpacity = 1, 0.92
retired.theme.hoverStyle, retired.theme.hoverIntensity = "outline", 0.72
retired.theme.iconBorderOpacity = 0.82
retired.geometry.radius = 4
retired.typography.face = "friz"
retired.theme.colors.background = { 9/255, 20/255, 31/255, 0.98 }
retired.theme.colors.border = { 161/255, 132/255, 86/255, 0.86 }
retired.theme.colors.microBarFill = forever.CopyValue(retired.theme.colors.background)
retired.theme.colors.microBarBorder = forever.CopyValue(retired.theme.colors.border)
local retiredMicro = retired.icons.microMenu
retiredMicro.positionPreset = "bottomLeft"
retiredMicro.layoutPoint, retiredMicro.layoutRelativePoint = "BOTTOMLEFT", "BOTTOMLEFT"
retiredMicro.layoutX, retiredMicro.layoutY = 18, 18
retiredMicro.barBorder, retiredMicro.padding = 1, 5
retiredMicro.buttonBackground, retiredMicro.buttonBorder = true, 1
retiredMicro.iconSize, retiredMicro.spacing = 20, 3
retiredMicro.iconStyle = "line"
local tuned = forever.CopyValue(retired)
tuned.theme.colors.border[1] = 0.31
tuned.theme.colors.border[4] = 0.44
tuned.theme.panelOpacity = 0.81
tuned.icons.microMenu.positionPreset = "custom"
tuned.icons.microMenu.layoutX = -75
forever.Database.Normalize(retired)
local original = forever.PresetOverrides.foreverGlass
assert(retired.revision == 50 and retired.geometry.radius == 12
    and retired.theme.gradientStrength == 0.50 and retired.theme.shellOpacity == 0.92
    and retired.theme.hoverStyle == "softFill" and retired.typography.face == "sharedMedia"
    and retired.theme.colors.background[1] == original.background[1]
    and retired.theme.colors.background[4] == original.background[4]
    and retired.theme.colors.border[1] == original.border[1]
    and retired.theme.colors.microBarFill[1] == original.microBarFill[1]
    and retired.theme.colors.microBarBorder[1] == original.border[1],
    "retired Forever palette did not return to the backed-up values")
assert(retired.icons.microMenu.positionPreset == "bottomCenter"
    and retired.icons.microMenu.layoutX == 0 and retired.icons.microMenu.layoutY == 120
    and retired.icons.microMenu.barBorder == 1 and retired.icons.microMenu.padding == 5,
    "retired Micro Bar defaults were not refreshed")

forever.Database.Normalize(tuned)
assert(tuned.theme.colors.border[1] == 0.31 and tuned.theme.colors.border[4] == 0.44
    and tuned.theme.panelOpacity == 0.81
    and tuned.icons.microMenu.positionPreset == "custom"
    and tuned.icons.microMenu.layoutX == -75,
    "saved custom Forever choices were overwritten")

local custom = forever.CopyValue(legacy)
custom.revision = 36
custom.theme.panelOpacity = 0.81
custom.theme.colors.background[4] = 0.55
custom.geometry.radius = 8
custom.icons.microMenu.positionPreset = "custom"
custom.icons.microMenu.layoutX = -75
forever.Database.Normalize(custom)
assert(custom.theme.panelOpacity == 0.81 and custom.geometry.radius == 8
    and custom.theme.colors.background[4] == 0.55
    and custom.icons.microMenu.positionPreset == "custom"
    and custom.icons.microMenu.layoutX == -75,
    "Forever migration overwrote a hand-tuned value")

local function MatchesHex(color, hex)
    for index = 1, 3 do
        local expected = tonumber(hex:sub(index * 2 - 1, index * 2), 16) / 255
        if math.abs(color[index] - expected) > 0.000001 then return false end
    end
    return true
end

local retailColors = {
    background = "14181B", ink = "111517", surface = "20272A",
    raised = "292F31", card = "292F31", popup = "191D20",
    border = "9F8960", borderSoft = "68716F", buttonBorder = "727774",
    active = "363C3C", hover = "454A47", accent = "D8B66A",
    text = "F4F3EB", title = "F1E3C4", muted = "D4DCE2",
    microBarFill = "0E1C28", microBarFillAlt = "122431",
    microBarBorder = "9F8960", microButtonFill = "292F31",
    microButtonFillAlt = "20272A", microButtonBorder = "727774",
    microIcon = "D8B66A", microIconHover = "F1E3C4",
    microIconPressed = "D8B66A", microIconDisabled = "8F9999",
}
for role, hex in pairs(retailColors) do
    assert(MatchesHex(forever.PresetOverrides.foreverGlass[role], hex),
        "Forever palette differs from Retail Classic Glass: " .. role)
end

local priorPalette = forever.CopyValue(forever.Defaults)
priorPalette.revision = 40
priorPalette.theme.colors.card = { 32/255, 39/255, 42/255, 0.51 }
local priorMicroSources = {
    microBarFill = "background", microBarFillAlt = "ink", microBarBorder = "border",
    microButtonFill = "buttonFill", microButtonFillAlt = "buttonFillAlt",
    microButtonBorder = "buttonBorder", microIcon = "text",
    microIconHover = "accentBright", microIconPressed = "accent",
    microIconDisabled = "disabled",
}
for role, source in pairs(priorMicroSources) do
    priorPalette.theme.colors[role] = forever.CopyValue(forever.PresetOverrides.foreverGlass[source])
end
priorPalette.theme.colors.microIconHover = { 0.11, 0.22, 0.33, 0.47 }
local microAlpha = priorPalette.theme.colors.microBarFill[4]
forever.Database.Normalize(priorPalette)
assert(priorPalette.revision == 50
    and MatchesHex(priorPalette.theme.colors.card, "292F31")
    and priorPalette.theme.colors.card[4] == 0.51
    and MatchesHex(priorPalette.theme.colors.microBarFill, "0E1C28")
    and priorPalette.theme.colors.microBarFill[4] == microAlpha
    and MatchesHex(priorPalette.theme.colors.microIcon, "D8B66A")
    and priorPalette.theme.colors.microIconHover[1] == 0.11
    and priorPalette.theme.colors.microIconHover[4] == 0.47,
    "Retail palette migration replaced a custom color or left factory colors behind")

local lowBar = forever.CopyValue(forever.Defaults)
lowBar.revision = 42
lowBar.icons.microMenu.layoutY = 18
forever.Database.Normalize(lowBar)
assert(lowBar.icons.microMenu.layoutY == 120,
    "old factory bottom-center position still collides with action bars")
local customBar = forever.CopyValue(lowBar)
customBar.revision = 42
customBar.icons.microMenu.positionPreset = "custom"
customBar.icons.microMenu.layoutY = 84.7
forever.Database.Normalize(customBar)
assert(customBar.icons.microMenu.layoutY == 85,
    "hand-placed Micro Bar position was overwritten")
local exportedFactoryBar = forever.CopyValue(forever.Defaults)
exportedFactoryBar.revision = 48
exportedFactoryBar.icons.microMenu.positionPreset = "custom"
exportedFactoryBar.icons.microMenu.layoutX = 463
exportedFactoryBar.icons.microMenu.layoutY = 0
forever.Database.Normalize(exportedFactoryBar)
assert(exportedFactoryBar.icons.microMenu.positionPreset == "bottomCenter"
    and exportedFactoryBar.icons.microMenu.layoutPoint == "BOTTOM"
    and exportedFactoryBar.icons.microMenu.layoutX == 0
    and exportedFactoryBar.icons.microMenu.layoutY == 120,
    "shipped Forever factory bar still overlaps the chat")
local placedBar = forever.CopyValue(exportedFactoryBar)
placedBar.revision = 48
placedBar.icons.microMenu.positionPreset = "custom"
placedBar.icons.microMenu.layoutX = 464
forever.Database.Normalize(placedBar)
assert(placedBar.icons.microMenu.positionPreset == "custom"
    and placedBar.icons.microMenu.layoutX == 464,
    "hand-placed Forever bar was overwritten")
local savedForeverBar = forever.CopyValue(forever.Defaults)
savedForeverBar.revision = 49
savedForeverBar.icons.microMenu.positionPreset = "custom"
savedForeverBar.icons.microMenu.layoutPoint = "BOTTOMLEFT"
savedForeverBar.icons.microMenu.layoutRelativePoint = "BOTTOMLEFT"
savedForeverBar.icons.microMenu.layoutX = 18
savedForeverBar.icons.microMenu.layoutY = 18
forever.Database.Normalize(savedForeverBar)
assert(savedForeverBar.revision == 50
    and savedForeverBar.icons.microMenu.positionPreset == "bottomCenter"
    and savedForeverBar.icons.microMenu.layoutPoint == "BOTTOM"
    and savedForeverBar.icons.microMenu.layoutRelativePoint == "BOTTOM"
    and savedForeverBar.icons.microMenu.layoutX == 0
    and savedForeverBar.icons.microMenu.layoutY == 120,
    "saved Forever profile still places the Micro Bar over chat")
local movedForeverBar = forever.CopyValue(savedForeverBar)
movedForeverBar.revision = 49
movedForeverBar.icons.microMenu.positionPreset = "custom"
movedForeverBar.icons.microMenu.layoutPoint = "BOTTOMLEFT"
movedForeverBar.icons.microMenu.layoutRelativePoint = "BOTTOMLEFT"
movedForeverBar.icons.microMenu.layoutX = 19
movedForeverBar.icons.microMenu.layoutY = 18
forever.Database.Normalize(movedForeverBar)
assert(movedForeverBar.icons.microMenu.positionPreset == "custom"
    and movedForeverBar.icons.microMenu.layoutPoint == "BOTTOMLEFT"
    and movedForeverBar.icons.microMenu.layoutX == 19,
    "a nearby player position was overwritten")
local oldGlyphs = forever.CopyValue(forever.Defaults)
oldGlyphs.revision = 43
oldGlyphs.icons.microMenu.iconStyle = "line"
oldGlyphs.icons.microMenu.positionPreset = "custom"
oldGlyphs.icons.microMenu.layoutX = -424
forever.Database.Normalize(oldGlyphs)
assert(oldGlyphs.icons.microMenu.iconStyle == "bold"
    and oldGlyphs.icons.microMenu.layoutX == -424,
    "named Forever style did not upgrade without moving the Micro Bar")
local customGlyphs = forever.CopyValue(oldGlyphs)
customGlyphs.revision = 43
customGlyphs.icons.microMenu.iconStyle = "line"
customGlyphs.icons.microMenu.preset = "custom"
forever.Database.Normalize(customGlyphs)
assert(customGlyphs.icons.microMenu.iconStyle == "line",
    "custom Micro Bar glyphs were overwritten")

local retail = Engine(false)
assert(retail.Defaults.theme.look == "midnightDark"
    and retail.Defaults.icons.microMenu.positionPreset == "bottomRight",
    "Forever defaults leaked into Retail")
print("Suite Forever look: fresh defaults, selective migration and Retail isolation passed")
