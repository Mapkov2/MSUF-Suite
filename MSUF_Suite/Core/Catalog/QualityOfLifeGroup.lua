local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
local Number, Bool, Choice = B.Number, B.Bool, B.Choice

B.Module("groupDeathAlert", {
    title = "Group death alert",
    description = "Reports group member deaths in chat during combat.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
})
B.Section("groupDeathAlert", "group_death_alert", "Group death alert", {
    Bool("includePlayer", "Include your own death"),
    Bool("chat", "Show deaths in local chat", true),
    Bool("screen", "Show deaths on screen"),
    Bool("sound", "Play a sound for group deaths"),
})

B.Module("releaseProtection", {
    title = "Release spirit protection",
    description = "Require a held modifier key before clicking Release Spirit in the death dialog.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
})
B.Section("releaseProtection", "release_protection", "Release spirit protection", {
    Choice("modifier", "Hold to release", 1, { "Shift", "Ctrl", "Alt" }),
    Bool("openWorld", "Protect release in the open world", true),
    Bool("party", "Protect release in dungeons and delves", true),
    Bool("raid", "Protect release in raids", true),
    Bool("pvp", "Protect release in battlegrounds and arenas", true),
})

B.Module("groupFinderDoubleClick", {
    title = "Group finder double-click",
    description = "Double-click a search result to open Blizzard's normal application dialog.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Group finder double-click is available only in Retail" end
        return true
    end,
})

B.Section("groupFinderDoubleClick", "group_finder_double_click", "Group finder double-click", {
    B.Automation(Bool("quickApply", "Submit on double-click (Shift opens the dialog)")),
    Bool("showNote", "Show a saved note beside the application dialog"),
    B.String("note", "Saved application note", "", 63),
    B.Bool("exportNote", "Put the saved note into profile exports (the string then contains your note)", false),
})
-- A typed note is the player's own text; ProfileIO exports it only when the
-- player chose to. The choice itself stays with this profile.
local groupFinder = NS.SuiteCatalog.groupFinderDoubleClick
groupFinder.rules.note.personal, groupFinder.rules.exportNote.personal = true, true
groupFinder.personalExport = "exportNote"

B.Module("groupFinderApplicantSort", {
    title = "Mythic+ applicant score sorting",
    description = "Sort Mythic+ applications by average member dungeon score when every score is available.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Applicant score sorting is available only in Retail" end
        return true
    end,
})

B.Module("groupFinderExitReminder", {
    title = "Active application reminder",
    description = "Show a local reminder when you leave group listings with active applications.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Group listing reminders are available only in Retail" end
        return true
    end,
})

B.Module("trustedPartyInvites", {
    title = "Trusted party invites",
    description = "Accept ordinary party invites from selected friends or guild members when no queue or confirmation would be lost.",
    optIn = true, automation = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Trusted party invites are available only in Retail" end
        return true
    end,
})
B.Section("trustedPartyInvites", "trusted_invites", "Trusted party invites", {
    Bool("battleNet", "Accept Battle.net friends", true),
    Bool("wowFriends", "Accept WoW friends", true),
    Bool("guild", "Accept guild members"),
})

B.Module("groupRaidShortcuts", {
    title = "Raid shortcuts",
    description = "Open Blizzard's raid tools, start a pull countdown, or mark one party tank or healer by command or opt-in automation.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Raid shortcuts are available only in Retail" end
        return true
    end,
    editElement = "tools",
})
local function RaidMarker(key, label, default)
    -- Blizzard raid-target IDs; keep this order for existing saved profiles.
    local rule = Choice(key, label, default, { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" })
    rule.choiceIcons = {}
    for index = 1, #rule.choices do
        rule.choiceIcons[index] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index
    end
    return rule
end
B.Section("groupRaidShortcuts", "raid_shortcuts", "Raid shortcuts", {
    Bool("showPanel", "Show the collapsible raid tools panel"),
    Number("panelColumns", "Panel columns", 3, 1, 3, 1),
    Number("panelScale", "Raid tools scale (percent)", 100, 60, 160, 5),
    Number("panelX", "Raid tools horizontal position", 0, -4000, 4000),
    Number("panelY", "Raid tools vertical position", 160, -3000, 3000),
    RaidMarker("tankMarker", "Tank raid marker", 4),
    RaidMarker("healerMarker", "Healer raid marker", 6),
    B.Automation(Bool("autoMarkTank", "Automatically mark the party tank")),
    B.Automation(Bool("autoMarkHealer", "Automatically mark the party healer")),
})

B.Module("mythicKeyShare", {
    title = "Keystone command",
    description = "Show or share your key with /keys; /keys group requests keys from Suite users in your group.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Keystone sharing is available only in Retail" end
        return true
    end,
})

B.Section("mythicKeyShare", "keystone_command", "Keystone overview", {
    B.Automation(Bool("insertKey", "Insert your keystone when the pedestal opens (Shift skips)")),
    Number("fontSize", "Keystone text size", 14, 10, 20, 1),
    Number("windowScale", "Keystone window scale (percent)", 100, 60, 160, 5),
})

B.Module("delveSolePower", {
    title = "Single Delve power",
    description = "Automatically choose a Delve power when exactly one safe option is available.",
    optIn = true, automation = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Delve power choices are available only in Retail" end
        return true
    end,
})

B.Module("mythicResetReminder", {
    title = "Mythic+ reset reminder",
    description = "Show a local reminder when Blizzard reports a Mythic+ reset.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Mythic+ reset reminders are available only in Retail" end
        return true
    end,
})

B.Section("mythicResetReminder", "mythic_reset", "Instance reset notices", {
    B.Automation(Bool("announceReset", "Announce confirmed instance resets to the group")),
})

B.Module("groupBloodlust", {
    title = "Bloodlust lockout",
    description = "Show your Bloodlust exhaustion or ready state while grouped.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Bloodlust lockout is available only in Retail" end
        return true
    end,
    editElement = "lockout",
})
B.Section("groupBloodlust", "bloodlust_lockout", "Bloodlust lockout", {
    Bool("onlyWhenLocked", "Show only while exhausted"),
    Number("width", "Display width", 172, 160, 350),
    Number("height", "Display height", 42, 42, 80),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", 120, -3000, 3000),
})
NS.AddQoLVisualStyle("groupBloodlust", "bloodlust_lockout", "Bloodlust lockout")
for _, key in ipairs({ "point", "x", "y" }) do
    NS.SuiteCatalog.groupBloodlust.rules[key].hidden = true
end

B.Module("dungeonPortals", {
    title = "Dungeon portals", page = "suite_qualityOfLife", optIn = true, defaultEnabled = false,
    description = "Learned dungeon teleports beside the minimap, with an optional group-join suggestion.",
    available = function()
        if NS.Client.isForever then return false, "Dungeon portals are available only in Retail" end
        return true
    end,
})
B.Section("dungeonPortals", "dungeon_portals", "Dungeon portals", {
    Bool("showMinimap", "Show dungeon portals beside the minimap", true),
    Number("flyoutScale", "Dungeon portal flyout scale (percent)", 100, 60, 160, 5),
    Bool("joinPopup", "Suggest a learned portal when joining a dungeon group"),
    Number("popupScale", "Dungeon portal suggestion scale (percent)", 100, 60, 160, 5),
})
