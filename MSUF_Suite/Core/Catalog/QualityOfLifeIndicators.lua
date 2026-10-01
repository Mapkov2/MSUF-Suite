local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
local Number, Bool, Choice, String = B.Number, B.Bool, B.Choice, B.String

-- On-screen Quality of Life indicators, each with its own Edit Mode element:
-- the experience bar, the Innervate cue, the durability warning, battle
-- resurrection charges and the Skyriding HUD. This file loads right after
-- QualityOfLife.lua, so the module order stays the same.

-- The XP display shares the Quality of Life addon but has its own independent
-- profile switch, runtime and Edit Mode element.
B.Module("xpBar", {
    title = "Experience bar",
    description = "Movable experience bar with rested XP, session gain, XP per hour and time to level.",
    optIn = true, page = "suite_qualityOfLife",
    editElement = "experience",
})
-- The XP bar paints its look itself; it has no Custom choice.
NS.SuiteCatalog.xpBar.look = { key = "look", global = true }
B.Section("xpBar", "xp_bar", "Experience bar", {
    Choice("look", "MSUF style", NS.Client.isForever and 3 or 2,
        { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Custom", "Clean Modern", "Class Style" }),
    Number("width", "Bar width", 400, 220, 800, 5),
    Number("height", "Bar height", 18, 8, 40),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Number("layer", "MSUF layer (-1 = Auto)", -1, -1, 30),
    Bool("showSegments", "Show XP bar divisions", true),
    Bool("showRested", "Show rested XP", true),
    Bool("showSession", "Show session XP", true),
    Bool("showRate", "Show XP per hour", true),
    Bool("showETA", "Show time to level", true),
    Bool("hideAtMax", "Hide at maximum level", true),
    Choice("point", "Screen anchor", 2, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", -24, -3000, 3000),
    -- The Custom style (choice 4) paints these.
    B.Color("customFill", "Custom style: bar color", "6fc3a0"),
    B.Color("customRested", "Custom style: rested color", "6c8fd6"),
    B.Color("customPanel", "Custom style: background color", "111820"),
    B.Color("customBorder", "Custom style: border and text color", "aab8c4"),
})

-- Incoming whispers are only a cue: chat text can be secret in combat, so
-- this feature never tries to infer whether a message requests Innervate.
B.Module("innervateCue", {
    title = "Innervate whisper cue",
    description = "Alert a Druid to incoming combat whispers when Innervate may be ready. Optionally outline a chosen MSUF group frame.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Innervate whisper cue is available only in Retail" end
        local _, class = UnitClass("player")
        if not NS.Public(class) or class ~= "DRUID" then return false, "Available only to Druids" end
        return true
    end,
    editElement = "alert",
})
B.Section("innervateCue", "innervate_cue", "Innervate whisper cue", {
    Bool("openWorld", "Alert in the open world", true),
    Bool("party", "Alert in dungeons, delves and PvP", true),
    Bool("raid", "Alert in raids", true),
    Bool("sound", "Play a warning sound", true),
    Bool("highlightTarget", "Outline preferred target's MSUF group frame", true),
    String("targetName", "Preferred target (Name or Name-Realm)", "", 100),
    Number("duration", "Alert duration (seconds)", 4, 2, 10),
    Number("width", "Alert width", 280, 180, 500),
    Number("height", "Alert height", 54, 44, 90),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", 180, -3000, 3000),
})
NS.SuiteCatalog.innervateCue.rules.targetName.enableKey = "highlightTarget"

-- The warning reads equipped durability only when its events fire. Its own
-- position is stored in the active Suite profile and exposed to MSUF Edit Mode.
B.Module("durabilityAlert", {
    title = "Low durability warning",
    description = "Show a movable warning when equipped gear needs repair. Hidden during combat.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    editElement = "warning",
})
B.Section("durabilityAlert", "durability_warning", "Low durability warning", {
    Number("threshold", "Warn below (percent)", 40, 1, 99),
    Number("width", "Warning width", 250, 180, 500),
    Number("height", "Warning height", 62, 56, 90),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", 180, -3000, 3000),
})

-- The shared battle-resurrection pool is only meaningful during an active
-- Mythic+ run or raid encounter. Blizzard owns the charge countdown itself.
B.Module("battleRes", {
    title = "Battle resurrection",
    description = "Show available shared battle resurrections and the next recharge in Mythic+ and raid encounters.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Shared battle resurrection charges are available only in Retail" end
        return true
    end,
    editElement = "charges",
})
B.Section("battleRes", "battle_res", "Battle resurrection", {
    Number("width", "Display width", 146, 146, 350),
    Number("height", "Display height", 44, 44, 80),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", 120, -3000, 3000),
})

-- The flight HUD is Retail-only and remains dormant until explicitly enabled.
B.Module("skyriding", {
    title = "Skyriding HUD",
    description = "Movable MSUF flight display for speed, Vigor, Second Wind and Whirling Surge.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Skyriding is available only in Retail" end
        return true
    end,
    editElement = "flight",
})
NS.SkyridingLookPresets = {
    [1] = { panelColor = "0a1220", borderColor = "41627a", trackColor = "102033",
        accentColor = "57c7df", windColor = "558bdd", textColor = "f4f7fb",
        mutedColor = "aab5c2", thrillColor = "d8b66a" },
    [2] = { panelColor = "151719", borderColor = "575b58", trackColor = "202326",
        accentColor = "b9ab86", windColor = "8b9cb2", textColor = "e9e9e4",
        mutedColor = "b9bdb9", thrillColor = "e2c57c" },
    [3] = { panelColor = "14181b", borderColor = "9f8960", trackColor = "20272a",
        accentColor = "d8b66a", windColor = "668db8", textColor = "f4f3eb",
        mutedColor = "d4dce2", thrillColor = "f0d284" },
    [5] = { panelColor = "101010", borderColor = "333333", trackColor = "191919",
        accentColor = "e6ecf2", windColor = "b7c2cd", textColor = "f5f5f5",
        mutedColor = "bfc4c9", thrillColor = "e6ecf2" },
}
NS.SkyridingLookPresets[6] = B.ClassPreset(NS.SkyridingLookPresets[5], { borderColor = "border", accentColor = "accent" })
NS.SkyridingLookVisualKeys = {
    panelColor = true, borderColor = true, trackColor = true, accentColor = true,
    windColor = true, textColor = true, mutedColor = true, thrillColor = true,
    panelOpacity = true, trackOpacity = true, borderSize = true,
}
NS.SuiteCatalog.skyriding.look = {
    key = "look", presets = NS.SkyridingLookPresets, visualKeys = NS.SkyridingLookVisualKeys,
    custom = 4, global = true,
}
local initialSky = NS.SkyridingLookPresets[1]
B.Section("skyriding", "flight_hud", "Skyriding HUD", {
    Choice("look", "MSUF style", 1, { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Custom", "Clean Modern", "Class Style" }),
    Number("width", "HUD width", 350, 220, 600, 5),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Bool("airborneOnly", "Show only while airborne"),
    Bool("showSpeed", "Show speed and Thrill threshold", true),
    Bool("showVigor", "Show Vigor charges", true),
    Choice("vigorDisplay", "Vigor appearance", 1, { "Bars", "Blizzard gems" }),
    Number("gemScale", "Vigor gem scale (percent)", 100, 50, 160, 5),
    Bool("chargeSound", "Sound when a Vigor charge refills"),
    Bool("showSecondWind", "Show Second Wind charges", true),
    Bool("showWhirlingSurge", "Show Whirling Surge cooldown", true),
    Number("speedMax", "Speed bar maximum (percent)", 1200, 500, 2000, 50),
    Number("thrillSpeed", "Thrill speed (percent)", 830, 300, 1500, 10),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", -145, -3000, 3000),
})
B.Section("skyriding", "flight_typography", "Text and bars", {
    B.Font("font", "Font"),
    Number("fontSize", "Font size", 11, 9, 18),
    Choice("fontOutline", "Text outline", 1, { "None", "Outline", "Thick outline" }),
    Choice("fontRendering", "Font rendering", 3, { "Smooth", "Sharp / pixel", "Slug" }),
    Bool("fontShadow", "Text shadow"),
    Number("fontShadowOpacity", "Shadow opacity (percent)", 100, 20, 100, 5),
    Choice("fontShadowDistance", "Shadow distance", 1, { "1 px", "2 px" }),
    B.Texture("barTexture", "Bar texture"),
    Number("barHeight", "Bar height", 10, 6, 18),
    Number("vigorHeight", "Vigor bar height (0 inherits)", 0, 0, 32),
    Number("windHeight", "Second Wind bar height (0 inherits)", 0, 0, 32),
    Number("speedHeight", "Speed bar height (0 inherits)", 0, 0, 32),
    Bool("surgeAutoSize", "Whirling Surge icon follows Vigor height", true),
    Number("surgeSize", "Whirling Surge icon size", 28, 12, 64),
    Number("speedTextX", "Speed value X offset", 0, -300, 300),
    Number("speedTextY", "Speed value Y offset", 0, -100, 100),
    Number("rowGap", "Space between rows", 0, 0, 12),
})
NS.SuiteCatalog.skyriding.rules.font.defaultLabel = "MSUF global font (default)"
B.LinkFontShadow(NS.SuiteCatalog.skyriding.rules)
B.Section("skyriding", "flight_colors", "Colors and panel", {
    B.Color("panelColor", "Panel color", initialSky.panelColor),
    Number("panelOpacity", "Panel opacity (percent)", 94, 0, 100),
    B.Color("borderColor", "Border color", initialSky.borderColor),
    Number("borderSize", "Border thickness", 1, 0, 3),
    B.Color("trackColor", "Empty bar color", initialSky.trackColor),
    Number("trackOpacity", "Empty bar opacity (percent)", 100, 0, 100),
    B.Color("accentColor", "Vigor and speed color", initialSky.accentColor),
    B.Color("windColor", "Second Wind color", initialSky.windColor),
    B.Color("thrillColor", "Thrill speed color", initialSky.thrillColor),
    B.Color("textColor", "Value text color", initialSky.textColor),
    B.Color("mutedColor", "Label text color", initialSky.mutedColor),
})
NS.SuiteCatalog.skyriding.rules.speedMax.enableKey = "showSpeed"
NS.SuiteCatalog.skyriding.rules.thrillSpeed.enableKey = "showSpeed"

for _, entry in ipairs({
    { "mapLandingShortcuts", "expansion_shortcuts", "Expansion shortcuts" },
    { "combatPetStatus", "pet_status", "Pet status warning" },
    { "combatMovementCue", "movement_cue", "Movement ability cue" },
    { "burningRushCue", "burning_rush_cue", "Burning Rush cue" },
    { "loadoutReminder", "loadout_reminder", "When to remind" },
    { "lootToastFilter", "filtered_loot", "Filtered loot notice" },
    { "innervateCue", "innervate_cue", "Innervate whisper cue" },
    { "durabilityAlert", "durability_warning", "Low durability warning" },
    { "battleRes", "battle_res", "Battle resurrection" },
}) do
    NS.AddQoLVisualStyle(entry[1], entry[2], entry[3])
end
