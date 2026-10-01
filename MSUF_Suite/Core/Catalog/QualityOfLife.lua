local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
local Number, Bool, Choice, String = B.Number, B.Bool, B.Choice, B.String

-- Small Suite-owned notices and buttons share the same shared looks.
-- Status colors (low durability, missing pet, Bloodlust lockout) stay semantic.
NS.QoLVisualStyles = {
    [1] = { background = "0a1220", border = "41627a", accent = "57c7df", text = "f4f7fb", muted = "aab5c2" },
    [2] = { background = "151719", border = "575b58", accent = "b9ab86", text = "e9e9e4", muted = "b9bdb9" },
    [3] = { background = "14181b", border = "9f8960", accent = "d8b66a", text = "f4f3eb", muted = "d4dce2" },
    [4] = { background = "101010", border = "333333", accent = "e6ecf2", text = "f5f5f5", muted = "bfc4c9" },
}
NS.QoLVisualStyles[5] = B.ClassPreset(NS.QoLVisualStyles[4], { border = "border", accent = "accent" })
function NS.AddQoLVisualStyle(id, section, title)
    NS.SuiteCatalog[id].look = { key = "look", global = { 1, 2, 3, [5] = 4, [6] = 5 } }
    B.Add(id, Choice("look", "MSUF style", 1,
        { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Clean Modern", "Class Style" }), section, title)
end

-- This independent recent-cast display starts with a restrained game-like
-- palette, regardless of the profile's global Suite look.
B.Module("actionTracker", {
    title = "Action tracker",
    description = "A compact, movable history of your recent successful spells.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    editElement = "actions",
})
NS.ActionTrackerLooks = {
    [1] = { panelColor = "171316", panelOpacity = 88, borderColor = "563938",
        accentColor = "d4a64c", textColor = "f2eeea" },
    [2] = { panelColor = "0a1220", panelOpacity = 90, borderColor = "41627a",
        accentColor = "57c7df", textColor = "f4f7fb" },
    [3] = { panelColor = "151719", panelOpacity = 90, borderColor = "575b58",
        accentColor = "b9ab86", textColor = "e9e9e4" },
    [4] = { panelColor = "14181b", panelOpacity = 90, borderColor = "9f8960",
        accentColor = "d8b66a", textColor = "f4f3eb" },
    [6] = { panelColor = "101010", panelOpacity = 90, borderColor = "333333",
        accentColor = "e6ecf2", textColor = "f5f5f5" },
}
NS.ActionTrackerLooks[7] = B.ClassPreset(NS.ActionTrackerLooks[6], { borderColor = "border", accentColor = "accent" })
NS.SuiteCatalog.actionTracker.look = {
    key = "look", presets = NS.ActionTrackerLooks,
    visualKeys = { panelColor = true, panelOpacity = true, borderColor = true,
        accentColor = true, textColor = true }, custom = 5,
    global = { 2, 3, 4, [5] = 6, [6] = 7 },
}
local actionLook = NS.ActionTrackerLooks[1]
B.Section("actionTracker", "action_tracker", "Recent actions", {
    Choice("look", "Style", 1, { "Classic UI", "Midnight Blue", "Midnight Dark", "MSUF Forever", "Custom", "Clean Modern", "Class Style" }),
    Choice("displayPreset", "Display preset", 1, { "Standard rows", "Icons only" }),
    Number("rows", "Visible actions", 5, 1, 8),
    Number("width", "Display width", 210, 150, 420, 5),
    Number("rowHeight", "Row height", 31, 24, 48),
    Number("rowGap", "Space between rows", 2, 0, 10),
    Choice("growth", "History growth direction", 1, { "Down", "Up", "Right", "Left" }),
    Choice("insertAnimation", "New action animation", 1, { "None", "Fade in", "Pop in" }),
    Bool("showHeader", "Show recent-spell header"),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Number("hideAfter", "Hide after inactivity (seconds; 0 = stay)", 15, 0, 60),
    Bool("pauseInCombat", "Pause inactivity timeout in combat", true),
    Bool("showNames", "Show spell names", true),
    Bool("showChevron", "Show gold action markers", true),
    B.Font("font", "Font"),
    Number("fontSize", "Spell name size", 12, 9, 20),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", -40, -3000, 3000),
})
B.Section("actionTracker", "action_tracker_visibility", "Where to show recent actions", {
    Bool("showDungeons", "Dungeons", true),
    Bool("showRaids", "Raids", true),
    Bool("showDelves", "Delves", true),
    Bool("showPvP", "Battlegrounds and arenas", true),
    Bool("showWorld", "Outside instances", true),
})
-- Position is owned by MSUF Edit Mode; these catalog rules remain available
-- for mover persistence, profile import and undo without duplicate sliders.
for _, key in ipairs({ "point", "x", "y" }) do
    NS.SuiteCatalog.actionTracker.rules[key].hidden = true
end
B.Section("actionTracker", "action_tracker_colors", "Colors", {
    B.Color("panelColor", "Row background", actionLook.panelColor),
    Number("panelOpacity", "Row opacity (percent)", actionLook.panelOpacity, 0, 100),
    B.Color("borderColor", "Row border", actionLook.borderColor),
    B.Color("accentColor", "Action marker", actionLook.accentColor),
    B.Color("textColor", "Spell name", actionLook.textColor),
}, { category = "advanced" })

-- Comfort modules are opt-in: setup presets and shared profiles never turn on
-- spending, automation, or combat logging. automation marks a module that acts
-- for the player (spends, sells, uses or cancels things, changes Blizzard
-- settings, sends requests): an imported profile never switches it on.
B.Module("qol", {
    title = "Merchant helpers",
    description = "Repair equipment and sell poor-quality items when a merchant opens. Hold Shift to skip selling.",
    optIn = true, automation = true, page = "suite_qualityOfLife",
    conflicts = { "EnhanceQoLVendor", "Scrap", "SellJunk" },
})
-- The page switches Repair and Junk independently; the shared addon gate is
-- derived from those two feature switches rather than shown as a third toggle.
NS.SuiteCatalog.qol.rules.enabled.hidden = true
B.Section("qol", "repair", "Repair", {
    B.Automation(Bool("repair", "Automatically repair equipment")),
    Number("repairLimit", "Maximum repair cost (gold)", 100, 0, 10000, 10),
    Bool("guildRepair", "Use guild repair when available"),
    Bool("repairFallback", "Fall back to character money", true),
})
B.Section("qol", "junk", "Junk", {
    B.Automation(Bool("autoJunk", "Sell poor-quality items")),
    Bool("junkReport", "Report junk sale requests in chat", true),
})
NS.SuiteCatalog.qol.rules.repairLimit.enableKey = "repair"
NS.SuiteCatalog.qol.rules.guildRepair.enableKey = "repair"
NS.SuiteCatalog.qol.rules.repairFallback.enableKey = "guildRepair"
NS.SuiteCatalog.qol.rules.junkReport.enableKey = "autoJunk"

B.Module("quests", {
    title = "Quest helpers",
    description = "Accept and turn in quests automatically. Hold Shift to pause. Reward choices and quests with a money cost stay manual.",
    optIn = true, automation = true, page = "suite_qualityOfLife",
})
B.Section("quests", "automation", "Quest actions", {
    Bool("accept", "Automatically accept offered quests"),
    Bool("complete", "Automatically complete ready quests"),
    Bool("reward", "Collect rewards without a choice"),
    Bool("gossip", "Select offered or completed quests in dialogue"),
})
local onlyIDs = String("onlyIDs", "Only these quest IDs (empty: all)", "", 1600)
onlyIDs.ids = true
local skipIDs = String("skipIDs", "Never automate these quest IDs", "", 1600)
skipIDs.ids = true
B.Section("quests", "filters", "Quest filters", {
    Bool("firstTime", "Only quests not yet completed on this account"),
    Bool("skipTrivial", "Leave trivial quests manual"),
    Bool("skipDaily", "Leave daily quests manual"),
    Bool("skipWeekly", "Leave weekly quests manual"),
    onlyIDs, skipIDs,
}, { category = "advanced" })
NS.SuiteCatalog.quests.rules.reward.enableKey = "complete"

B.Module("merchantLevel", {
    title = "Merchant item levels",
    description = "Show the item level on equipment sold by a merchant.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Merchant item levels are available only in Retail" end
        return true
    end,
})

B.Module("vaultSpec", {
    title = "Great Vault loot specialization",
    description = "Show your selected loot specialization in the Great Vault window.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "The Great Vault is available only in Retail" end
        return true
    end,
})

B.Module("tooltipIDs", {
    title = "Tooltip IDs",
    description = "Hold Alt to show item, spell, creature, quest, currency and temporary weapon enchant IDs on the main tooltip.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Tooltip IDs are available only in Retail" end
        return true
    end,
})
B.Section("tooltipIDs", "tooltip_ids", "Tooltip IDs", {
    Bool("showQuestCurrency", "Show quest and currency IDs", true),
    Bool("showSpellIcon", "Show spell icon ID"),
    Bool("showTempEnchant", "Show temporary weapon enchant ID", true),
    Bool("showAccountCurrency", "Show currency on other characters"),
})

B.Module("tooltipVisibility", {
    title = "Tooltip visibility",
    description = "Optionally hide the main tooltip in combat, instances or for selected content types.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
})
B.Section("tooltipVisibility", "tooltip_visibility", "Tooltip visibility", {
    Bool("inCombat", "Hide main tooltip in combat"),
    Bool("inInstances", "Hide main tooltip in instances"),
    Bool("hideItems", "Hide item tooltips"),
    Bool("hideSpells", "Hide spell tooltips"),
    Bool("hideUnits", "Hide unit tooltips"),
})

B.Module("itemCounts", {
    title = "Item counts in tooltips",
    description = "Show your owned item count, including bank and Warband bank, on item tooltips.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Item count tooltips are available only in Retail" end
        return true
    end,
})
B.Section("itemCounts", "item_counts", "Item counts", {
    Bool("byLocation", "Separate bags, bank and Warband bank"),
})

B.Module("socketGemSuggestions", {
    title = "Gems in bags",
    description = "Show carried gems beside Blizzard's socket window for manual review.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "The socket window is available only in Retail" end
        return true
    end,
})

B.Module("tooltipSpellCopy", {
    title = "Copy spell ID",
    description = "Select the last public spell tooltip ID for copying with /msufcopyspell.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Spell ID copying is available only in Retail" end
        return true
    end,
})

B.Module("tooltipMPlusScore", {
    title = "Mythic+ score in tooltips",
    description = "Show a player's public current-season Mythic+ score on their main tooltip.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Mythic+ scores are available only in Retail" end
        return true
    end,
})

B.Module("tooltipClassColors", {
    title = "Class-colored player names",
    description = "Color player names by class on the main tooltip.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Class-colored player names are available only in Retail" end
        return true
    end,
})

B.Module("macroBuilder", {
    title = "Macro builder",
    description = "Preview a mouseover or focus spell macro and create it on your character with /msufmacro.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "The macro builder is available only in Retail" end
        return true
    end,
})

B.Module("chatProfileLinks", {
    title = "Character profile links",
    description = "Copy Raider.IO or Warcraft Logs profile URLs from native character context menus.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Character profile links are available only in Retail" end
        return true
    end,
})
B.Section("chatProfileLinks", "profile_links", "Character profile links", {
    Bool("raiderIO", "Show Raider.IO link", true),
    Bool("warcraftLogs", "Show Warcraft Logs link", true),
})

B.Module("waypoints", {
    title = "Waypoint command",
    description = "Set a native map waypoint with /way x y or /msufway x y.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Native waypoints are available only in Retail" end
        return true
    end,
})
B.Section("waypoints", "waypoint_command", "Waypoint command", {
    Bool("openMap", "Open the map after setting a waypoint"),
    Bool("superTrack", "Track the new waypoint", true),
})

B.Module("dailyComfort", {
    title = "Daily UI comforts",
    description = "Optional shortcuts for tutorials, item deletion and screenshot notices.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    cvars = {
        showTutorials = true, chatMouseScroll = true, chatClassColorOverride = true, mapFade = true,
        worldMapShowPlayerCoords = true, worldMapShowCursorCoords = true,
        doNotFlashLowHealthWarning = true, overrideScreenFlash = true,
        Sound_EnableMusic = true, Sound_EnableAmbience = true,
        Sound_EnableDialog = true, Sound_EnableErrorSpeech = true,
        whisperMode = true,
    },
})
B.Section("dailyComfort", "daily_comfort", "Daily UI comforts", {
    Bool("skipCinematicConfirm", "Skip cinematic confirmation"),
    B.Automation(Bool("autoSkipCinematic", "Automatically skip cinematics and movies")),
    Bool("hideTutorials", "Hide tutorial prompts"),
    Bool("fillDelete", "Fill DELETE in item confirmations"),
    Bool("hideScreenshotSuccess", "Hide screenshot success notice"),
    Bool("vendorCharacter", "Open equipment window at merchants"),
    Bool("auctionExpansionHint", "Mark the auction house filter while Current Expansion Only is off"),
})
B.Section("dailyComfort", "daily_cvars", "Chat, map and sound", {
    Bool("chatWheel", "Scroll chat with the mouse wheel"),
    Bool("chatClassColors", "Color chat names by class"),
    Bool("noChatFade", "Keep chat messages visible"),
    Choice("whisperWindows", "Whisper windows", 1,
        { "Follow Blizzard settings", "Separate window", "Window and main chat" }),
    Bool("keepMapVisible", "Keep world map visible while moving"),
    Bool("playerMapCoords", "Show player coordinates on the world map"),
    Bool("cursorMapCoords", "Show cursor coordinates on the world map"),
    Bool("hideLowHealthFlash", "Hide low-health screen flash"),
    Bool("alternateScreenFlash", "Use alternate screen flashes"),
    Bool("muteMusic", "Mute music"),
    Bool("muteAmbience", "Mute ambience"),
    Bool("muteDialog", "Mute spoken dialogue"),
    Bool("muteErrorSpeech", "Mute error speech"),
})

B.Module("collectionNewMarkers", {
    title = "Collection new markers",
    description = "Clear new mount, pet and toy fanfares acquired while this helper is active.",
    optIn = true, automation = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Collection markers are available only in Retail" end
        return true
    end,
})
B.Section("collectionNewMarkers", "collection_markers", "Collection new markers", {
    Bool("mounts", "Clear new mount markers", true),
    Bool("pets", "Clear new pet markers", true),
    Bool("toys", "Clear new toy markers", true),
})

B.Module("guildChatPrivacy", {
    title = "Guild chat privacy cover",
    description = "Manually cover whole chat windows that contain guild or officer messages.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Guild chat privacy is available only in Retail" end
        return true
    end,
})

B.Module("uiErrorFilter", {
    title = "Quiet repeated errors",
    description = "Choose individual recurring UI errors to hide with Blizzard's own message filter.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
})
B.Section("uiErrorFilter", "ui_error_filter", "UI error messages", {
    Bool("range", "Hide spell out of range"),
    Bool("target", "Hide no valid target"),
    Bool("mana", "Hide not enough mana"),
    Bool("item", "Hide item cooldown and cannot use item"),
})

B.Module("cursorEffects", {
    title = "Cursor highlight",
    description = "A ring around the mouse pointer that is easy to spot, optionally filled by your global cooldown or cast.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Cursor highlight is available only in Retail" end
        return true
    end,
    editElement = "gcd",
})
B.Section("cursorEffects", "cursor_effects", "Pointer highlight", {
    B.Color("color", "Highlight color", "ffffff"),
    Choice("ringShape", "Ring shape", 1, { "Segments", "Thin ring", "Dots", "No ring" }),
    Number("size", "Highlight size", 36, 20, 72),
    Number("opacity", "Opacity (percent)", 85, 10, 100, 5),
    Bool("showTrail", "Leave a short trail behind the pointer"),
    Bool("showDot", "Mark the pointer's centre with a dot"),
    Number("dotSize", "Dot size", 4, 1, 12),
    Bool("cameraHoldOnly", "Show ring, dot and trail only while you turn the camera with the mouse"),
})
B.Section("cursorEffects", "cursor_progress", "Progress inside the ring", {
    Bool("showGCD", "Fill the ring with your global cooldown"),
    Bool("showCast", "Fill the ring with your casts and channels"),
    Bool("castSpark", "Draw a bright edge on the cast fill"),
})
B.Section("cursorEffects", "cursor_gcd", "Global cooldown on its own", {
    Bool("gcdDetached", "Show the global cooldown in its own circle instead of the ring"),
    Number("gcdSize", "Circle size", 40, 20, 120),
    Number("gcdOpacity", "Circle opacity (percent)", 80, 10, 100, 5),
    Choice("gcdPoint", "Screen anchor", 5, NS.AnchorLabels),
    Number("gcdX", "Horizontal position", 0, -4000, 4000),
    Number("gcdY", "Vertical position", -140, -3000, 3000),
})
B.Section("cursorEffects", "cursor_when", "When to show", {
    Bool("combatOnly", "Only while in combat"),
    Choice("zone", "Where", 1, { "Everywhere", "Only inside instances", "Only outside instances" }),
    Choice("ringWhen", "Ring, dot and trail", 1, { "Always", "In combat", "Out of combat" }),
    Choice("gcdWhen", "Global cooldown", 1, { "Always", "In combat", "Out of combat" }),
    Choice("castWhen", "Cast fill", 1, { "Always", "In combat", "Out of combat" }),
})
do
    -- MSUF Edit Mode places the detached circle.
    local rules = NS.SuiteCatalog.cursorEffects.rules
    rules.gcdPoint.hidden, rules.gcdX.hidden, rules.gcdY.hidden = true, true, true
    rules.dotSize.enableKey, rules.castSpark.enableKey = "showDot", "showCast"
    rules.gcdSize.enableKey, rules.gcdOpacity.enableKey = "gcdDetached", "gcdDetached"
end
NS.SuiteCatalog.cursorEffects.look = {
    key = "look", global = { 1, 2, 3, [5] = 4, [6] = 6 }, custom = 5,
    visualKeys = { color = true }, presets = {},
}
for index, palette in pairs(NS.QoLVisualStyles) do
    if index ~= 5 then NS.SuiteCatalog.cursorEffects.look.presets[index] = { color = palette.accent } end
end
NS.SuiteCatalog.cursorEffects.look.presets[6] = B.ClassPreset({ color = "e6ecf2" }, { color = "accent" })
B.Add("cursorEffects", Choice("look", "MSUF style", 5,
    { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Clean Modern", "Custom", "Class Style" }),
    "cursor_effects", "Pointer highlight")

B.Module("mapLandingShortcuts", {
    title = "Expansion shortcuts",
    description = "Open expansion, Great Vault, Adventure Guide and map pages from a small menu by the minimap.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Expansion shortcuts are available only in Retail" end
        return true
    end,
})
B.Section("mapLandingShortcuts", "expansion_shortcuts", "Expansion shortcuts", {
    Bool("showLandingPage", "Include expansion landing page", true),
    Bool("showVault", "Include Great Vault", true),
    Bool("showJournal", "Include Adventure Guide", true),
    Bool("showMap", "Include world map", true),
    Number("size", "Button size", 18, 14, 32),
    Number("offsetX", "Horizontal offset", 4, -60, 60),
    Number("offsetY", "Vertical offset", 0, -60, 60),
})

B.Module("combatPetStatus", {
    title = "Pet status warning",
    description = "Show a movable warning when your pet is missing or dead.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    editElement = "warning",
})
B.Section("combatPetStatus", "pet_status", "Pet status warning", {
    Bool("showMissing", "Warn when pet is missing", true),
    Bool("showDead", "Warn when pet is dead", true),
    Bool("combatOnly", "Show only in combat"),
    Bool("anyClass", "Warn on classes without a permanent pet"),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", 0, -3000, 3000),
})
for _, key in ipairs({ "point", "x", "y" }) do
    NS.SuiteCatalog.combatPetStatus.rules[key].hidden = true
end

B.Module("combatMovementCue", {
    title = "Movement ability cue",
    description = "Briefly show a ready movement spell from your chosen IDs when you start moving.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Movement ability cue is available only in Retail" end
        return true
    end,
    editElement = "combat",
})
local movementIDs = String("spellIDs", "Movement spell IDs", "", 128)
movementIDs.ids = true
B.Section("combatMovementCue", "movement_cue", "Movement ability cue", {
    movementIDs,
    Bool("combatOnly", "Show only in combat", true),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", -120, -3000, 3000),
})
for _, key in ipairs({ "point", "x", "y" }) do
    NS.SuiteCatalog.combatMovementCue.rules[key].hidden = true
end

B.Module("burningRushCue", {
    title = "Burning Rush cue",
    description = "Show the active Burning Rush aura during combat through Blizzard's native aura container.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Burning Rush cue is available only in Retail" end
        local _, class = UnitClass("player")
        if not NS.Public(class) or class ~= "WARLOCK" then return false, "Available only to Warlocks" end
        return true
    end,
    editElement = "combat",
})
B.Section("burningRushCue", "burning_rush_cue", "Burning Rush cue", {
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", -170, -3000, 3000),
})
for _, key in ipairs({ "point", "x", "y" }) do
    NS.SuiteCatalog.burningRushCue.rules[key].hidden = true
end

B.Module("loadoutReminder", {
    title = "Talent and loot spec reminder",
    description = "Show the active talent build and loot specialization on ready checks or instance entry, with an optional saved expectation.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Talent loadouts are available only in Retail" end
        return true
    end,
})
B.Section("loadoutReminder", "loadout_reminder", "When to remind", {
    Bool("onReadyCheck", "On ready check", true),
    Bool("onLfgProposal", "When a dungeon queue pops"),
    Bool("onInstanceEntry", "On instance entry", true),
    Bool("onlyMismatch", "Show only when saved selection differs"),
    Number("duration", "Display duration (seconds)", 8, 3, 20),
    Bool("exportSavedSelection", "Put the saved selection into profile exports (the string then identifies this character)"),
})
B.Section("loadoutReminder", "loadout_expectation", "Saved selection", {
    Number("expectedConfigID", "Expected talent build ID (0: any)", 0, 0, 100000000),
    Number("expectedLootSpecID", "Expected loot spec ID (0: any)", 0, 0, 100000),
    String("expectedCharacterGUID", "Expected character", "", 100),
}, { category = "advanced" })
-- The saved selection belongs to one character: hidden, and exported only
-- when the player chose to (ProfileIO resets personal rules otherwise), since
-- a foreign build ID without its character would remind every importer.
for _, key in ipairs({ "expectedCharacterGUID", "expectedConfigID", "expectedLootSpecID" }) do
    local rule = NS.SuiteCatalog.loadoutReminder.rules[key]
    rule.hidden, rule.personal = true, true
end
-- The choice itself stays with this profile: no export or import carries it.
NS.SuiteCatalog.loadoutReminder.personalExport = "exportSavedSelection"
NS.SuiteCatalog.loadoutReminder.rules.exportSavedSelection.personal = true

B.Module("quietPopups", {
    title = "Quiet Blizzard popups",
    description = "Independently hide Talking Head, Boss Banner and Quick Join toasts while retaining Blizzard's underlying events.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
})
B.Section("quietPopups", "quiet_popups", "Popups", {
    Bool("talkingHead", "Hide Talking Head"),
    Bool("bossBanner", "Hide Boss Banner"),
    Bool("quickJoin", "Hide Quick Join toast"),
})

B.Module("loot", {
    title = "Fast loot",
    description = "Collect all unlocked loot slots at once. Blizzard's own Auto Loot setting stays unchanged; roll decisions stay manual.",
    optIn = true, page = "suite_qualityOfLife",
})
NS.SuiteCatalog.loot.rules.enabled.hidden = true
B.Section("loot", "collection", "Collecting loot", {
    B.Automation(Bool("quickLoot", "Collect available loot automatically")),
    Choice("lootModifier", "Collection rule", 2, { "Always", "Except while holding Shift", "Only while holding Shift" }),
})
B.Section("loot", "history", "Loot history", {
    Bool("manageHistory", "Customize loot history visibility"),
    Choice("historyMode", "Loot history behavior", 1, { "Hide automatically", "Close after a delay" }),
    Number("historyDelay", "Close after (seconds)", 5, 1, 30),
})
NS.SuiteCatalog.loot.rules.lootModifier.enableKey = "quickLoot"
NS.SuiteCatalog.loot.rules.historyMode.enableKey = "manageHistory"
NS.SuiteCatalog.loot.rules.historyDelay.enableKey = "manageHistory"

B.Module("lootContainers", {
    title = "Open new containers",
    description = "Open newly acquired loot containers one at a time outside combat. Hold Shift to leave them manual.",
    optIn = true, automation = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Automatic container opening is available only in Retail" end
        return true
    end,
})

B.Section("lootContainers", "open_containers", "Open new containers", {
    Bool("skipWarbound", "Keep Warbound containers unopened", true),
    Bool("holdDundun", "Hold Midnight Artisan payouts while Shard of Dundun is capped"),
})

-- skipWarbound arrived after Open new containers shipped. Players who already
-- used the helper keep opening Warbound containers; new users start with the
-- Warbound rule on. Normalization writes the default only afterwards.
function NS.MigrateLootContainersWarbound(modules)
    local config = modules.lootContainers
    if type(config) == "table" and config.enabled == true and config.skipWarbound == nil then
        config.skipWarbound = false
    end
end

B.Module("lootVendorRules", {
    title = "Sell marked items",
    description = "At a merchant, review and confirm sales from an explicit item ID list.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Marked item selling is available only in Retail" end
        return true
    end,
})

B.Module("lootToastFilter", {
    title = "Filtered loot notice",
    description = "Show extra compact item notices for Blizzard personal loot toasts matching your rarity and item list.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Filtered loot notice is available only in Retail" end
        return true
    end,
})
local toastIDs = String("itemIDs", "Item IDs (empty: all qualifying items)", "", 800)
toastIDs.ids = true
B.Section("lootToastFilter", "filtered_loot", "Filtered loot notice", {
    Number("minQuality", "Minimum item quality", 4, 0, 6),
    Choice("kindFilter", "Item type filter", 1,
        { "All matching items", "Mount items only", "Pet items only", "Mount and pet items" }),
    toastIDs,
})

B.Module("trainerLearnAll", {
    title = "Learn all at trainer",
    description = "Review the total cost, then learn available non-profession abilities at a trainer.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Trainer learning is available only in Retail" end
        return true
    end,
})

B.Module("characterUpgradeWindow", {
    title = "Equipment window at upgrades",
    description = "Open your equipment window beside an item upgrade merchant and close only the window MSUF opened.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Item upgrade window is available only in Retail" end
        return true
    end,
})

B.Module("professionAppearance", {
    title = "Profession appearance remover",
    description = "Remove selected profession outfit auras outside combat. Fishing is excluded to preserve fishing-rod effects.",
    optIn = true, automation = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Profession appearance removal is available only in Retail" end
        return true
    end,
})
B.Section("professionAppearance", "profession_outfits", "Profession appearance remover", {
    Bool("alchemy", "Remove alchemy outfit", true),
    Bool("blacksmithing", "Remove blacksmithing outfit", true),
    Bool("cooking", "Remove cooking outfit", true),
    Bool("enchanting", "Remove enchanting outfit", true),
    Bool("engineering", "Remove engineering outfit", true),
    Bool("herbalism", "Remove herbalism outfit", true),
    Bool("inscription", "Remove inscription outfit", true),
    Bool("jewelcrafting", "Remove jewelcrafting outfit", true),
    Bool("mining", "Remove mining outfit", true),
    Bool("skinning", "Remove skinning outfit", true),
    Bool("tailoring", "Remove tailoring outfit", true),
    Bool("leatherworking", "Remove leatherworking outfit", true),
    Bool("orbDeception", "Remove Orb of Deception disguise"),
    Bool("holidayCostumes", "Remove Hallow's End pirate, ninja and leper gnome costumes"),
    Bool("noggenfoggerSkeleton", "Remove Noggenfogger skeleton (also removes underwater breathing)"),
})
local cosmeticIDs = String("cosmeticSpellIDs", "Extra cosmetic aura spell IDs to remove", "", 240)
cosmeticIDs.ids = true
B.Add("professionAppearance", cosmeticIDs, "profession_outfits", "Profession appearance remover")
local vendorIDs = String("itemIDs", "Item IDs to offer for sale", "", 1600)
vendorIDs.ids = true
B.Section("lootVendorRules", "marked_sales", "Sell marked items", {
    vendorIDs,
    Number("maxQuality", "Highest allowed quality", 2, 0, 3),
    Bool("includeGear", "Allow equippable items"),
})

B.Module("combatLog", {
    title = "Automatic combat logging",
    description = "Start the combat log in the instance types you choose. A log you started manually stays on when you leave.",
    optIn = true, automation = true, page = "suite_qualityOfLife",
})
B.Section("combatLog", "log_dungeons", "Dungeons", {
    Bool("dungeonNormal", "Normal dungeons"),
    Bool("dungeonHeroic", "Heroic dungeons"),
    Bool("dungeonMythic", "Mythic dungeons"),
    Bool("dungeonMythicPlus", "Mythic+ dungeons", true),
    Bool("dungeonTimewalking", "Timewalking dungeons"),
})
B.Section("combatLog", "log_raids", "Raids", {
    Bool("raidLFR", "Raid Finder"),
    Bool("raidNormal", "Normal raids", true),
    Bool("raidHeroic", "Heroic raids", true),
    Bool("raidMythic", "Mythic raids", true),
    Bool("raidTimewalking", "Timewalking raids"),
})
B.Section("combatLog", "log_other", "Other instances", {
    Bool("pvp", "Battlegrounds and arenas"),
    Bool("scenario", "Scenarios"),
    Bool("delve", "Delves"),
})
B.Section("combatLog", "log_exit", "When leaving", {
    Choice("stopPolicy", "After leaving selected content", 2,
        { "Stop immediately", "Stop after 30 seconds", "Leave logging on" }),
    Bool("chatNotice", "Show a chat message when MSUF changes logging"),
})
