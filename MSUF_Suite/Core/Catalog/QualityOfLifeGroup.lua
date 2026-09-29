local _, NS = ...
local B = NS.CatalogBuild
local Number, Bool, Choice = B.Number, B.Bool, B.Choice

B.Module("groupDeathAlert", {
    title = "Group death alert",
    description = "Reports group member deaths in chat during combat.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
})
B.Section("groupDeathAlert", "group_death_alert", "Group death alert", {
    Bool("includePlayer", "Include your own death"),
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
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
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
})
B.Section("groupRaidShortcuts", "raid_shortcuts", "Raid shortcuts", {
    Number("tankMarker", "Tank raid marker", 4, 1, 8),
    Number("healerMarker", "Healer raid marker", 6, 1, 8),
    Bool("autoMarkTank", "Automatically mark the party tank"),
    Bool("autoMarkHealer", "Automatically mark the party healer"),
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

B.Module("delveSolePower", {
    title = "Single Delve power",
    description = "Automatically choose a Delve power when exactly one safe option is available.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
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

B.Module("groupBloodlust", {
    title = "Bloodlust lockout",
    description = "Show your Bloodlust exhaustion or ready state while grouped.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Bloodlust lockout is available only in Retail" end
        return true
    end,
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
