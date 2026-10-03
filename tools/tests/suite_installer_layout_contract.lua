local root = assert(arg[1])
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = Copy(v) end
    return result
end
local Suite = {}
assert(loadfile(root .. "/MSUF_Suite/Core/InstallerLayout.lua"))("MSUF_Suite", Suite)
local Layout = Suite.InstallerLayout
local authored = { dataTexts = { bar1Point = 8, bar1X = 1020, bar1Y = 170, bar1Width = 521 }, actionbars = {} }
for _, index in ipairs({ 3, 5 }) do
    local prefix, bars = "bar" .. index, authored.actionbars
    bars[prefix .. "Point"], bars[prefix .. "X"] = 7, index == 3 and 2480 or 2520
    bars[prefix .. "Y"], bars[prefix .. "Size"], bars[prefix .. "Spacing"] = 236, 40, 2
    bars[prefix .. "Buttons"], bars[prefix .. "Rows"] = 12, 12
end
for _, width in ipairs({ 1280, 1920, 2560, 3440, 5120 }) do
    for _, scale in ipairs({ 0.5, 0.65, 0.8, 1, 1.15 }) do
        local modules = Copy(authored)
        Layout.Prepare(modules)
        local texts, bars, screen = modules.dataTexts, modules.actionbars, width / scale
        assert(texts.bar1Point == 9 and texts.bar1X == 0 and texts.bar1Y == 170 and texts.bar1Width == 521)
        assert(bars.bar3Point == 9 and bars.bar3X == -40 and bars.bar5Point == 9 and bars.bar5X == 0)
        local textsRight = screen + texts.bar1X
        local meterRight, meterLeft = screen, screen - 520
        assert(textsRight == meterRight and math.abs((textsRight - texts.bar1Width) - meterLeft) <= 1,
            "the information strip detached from the paired meters")
        assert(screen + bars.bar3X - 40 == screen - 80 and screen + bars.bar5X == screen,
            "side bars must keep their authored right-edge distances")
        Layout.Prepare(modules)
        assert(bars.bar3X == -40 and texts.bar1X == 0, "preparing twice moved the layout")
    end
end
assert(authored.dataTexts.bar1X == 1020 and authored.actionbars.bar3X == 2480, "factory cache was mutated")
local custom = Copy(authored)
custom.dataTexts.bar1X, custom.actionbars.bar3X = 40, 90
Layout.Prepare(custom)
assert(custom.dataTexts.bar1X == 40 and custom.dataTexts.bar1Point == 8 and custom.actionbars.bar3X == 90)

local baseline = { suite = { modules = {
    dataTexts = { enabled = true, bar1Enabled = true, bar1Point = 8, bar1X = 0, bar1Y = 170,
        bar1Width = 522, bar1Height = 26, bar1Layout = 1, bar1FullScreen = false, bar1Dock = 1, bar1Vertical = false },
    damageMeter = { enabled = true, windowCount = 2, w1X = 0, w2X = -260, w1Y = 0, w2Y = 0,
        w1Width = 260, w2Width = 260, w1Height = 170, w2Height = 170 },
} } }
local baselineSkin = { enabled = true, icons = { microMenu = { positionPreset = "custom", layoutMode = "owned",
    layoutPoint = "BOTTOMRIGHT", layoutRelativePoint = "BOTTOMRIGHT", layoutX = -522, layoutY = 0,
    orientation = "vertical", buttonsPerLine = 6, scale = 0.7, spacing = 5, padding = 5,
    buttonSize = 30, iconSize = 22, growth = "LEFT_UP" } } }
local profile, skinProfile, combat, refuse, overlay, skinOverlay, writes = nil, nil, false, false, false, 0
local active, skinActive = "Legacy", "Legacy"
Suite.RootDB = {}
Suite.Database = { GetActiveProfileName = function() return active end,
    GetProfile = function(name) if name == "Legacy" then return profile end end }
Suite.InCombat = function() return combat end
Suite.ProfileIO = {}
Suite.ProfileVariants = { BeforeMutation = function()
    if refuse then return false end
    if overlay then profile.suite.modules.dataTexts.bar1X = 50 end
    if skinOverlay then skinProfile = Copy(skinProfile); skinProfile.icons.microMenu.layoutX = -700 end
    return true
end, AfterMutation = function() end }
Suite.Suite = { SetMany = function(id, values)
    writes = writes + 1
    if refuse then return false end
    for key, value in pairs(values) do profile.suite.modules[id][key] = value end
    return true
end }
MapkoSkin = { addonName = "MSUF_Suite_Skin", ProfileIO = {}, Database = {
    GetActiveProfileName = function() return skinActive end,
    GetProfile = function(name) if name == "Legacy" then return skinProfile end end,
} }
MSUF_ActiveProfile = "Legacy"
assert(loadfile(root .. "/MSUF_Suite/Core/Profiles.lua"))("MSUF_Suite", Suite)
local P = Suite.SuiteProfiles
local function Reset()
    profile, skinProfile = Copy(baseline), Copy(baselineSkin)
    active, skinActive, MSUF_ActiveProfile = "Legacy", "Legacy", "Legacy"
    combat, refuse, overlay, skinOverlay, writes = false, false, false, false, 0
    Suite.RootDB.installation = { revision = 3, status = "complete", profile = "suite", frameProfileName = "Legacy" }
end
Reset()
assert(P.EnsureModernPanelLayout() and writes == 1 and profile.suite.modules.dataTexts.bar1Point == 9
    and profile.suite.modules.damageMeter.w2X == -260 and skinProfile.icons.microMenu.layoutX == -522)
assert(Suite.RootDB.installation.modernPanelAnchorRevision == 1 and not P.EnsureModernPanelLayout() and writes == 1)
for _, id in ipairs({ "dataTexts", "damageMeter" }) do
    for key, value in pairs(baseline.suite.modules[id]) do
        Reset()
        if type(value) == "boolean" then value = not value else value = value + 1 end
        profile.suite.modules[id][key] = value
        assert(not P.EnsureModernPanelLayout() and writes == 0, "edited " .. id .. "." .. key .. " was overwritten")
    end
end
for key, value in pairs(baselineSkin.icons.microMenu) do
    Reset()
    if type(value) == "number" then value = value + 1 else value = value .. "custom" end
    skinProfile.icons.microMenu[key] = value
    assert(not P.EnsureModernPanelLayout() and writes == 0, "edited menu." .. key .. " was overwritten")
end
for _, change in ipairs({
    function() combat = true end,
    function() skinProfile.enabled = false end,
    function() refuse = true end,
    function() overlay = true end,
    function() skinOverlay = true end,
    function() active = "Other" end,
    function() skinActive = "Other" end,
    function() MSUF_ActiveProfile = "Other" end,
    function() Suite.RootDB.installation.status = "pending" end,
    function() Suite.RootDB.installation.profile = "classic" end,
    function() Suite.RootDB.installation.revision = 4 end,
    function() Suite.RootDB.installation.frameProfileName = "Other" end,
}) do
    Reset(); change()
    assert(not P.EnsureModernPanelLayout() and writes == 0, "migration bypassed an ownership or combat guard")
end
print("Installer layout: 25 viewport/scale cases, preserved factories and guarded legacy panel repair passed")
