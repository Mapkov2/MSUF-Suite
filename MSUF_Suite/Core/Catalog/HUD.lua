local _, NS = ...
local B = NS.CatalogBuild

local function MainlineFamily()
    if not NS.Client.isMainline then
        return false, "Available in Retail and Forever"
    end
    return true
end

-- The two HUDs own their frames.
B.Module("objectives", {
    title = "Objective Tracker", page = "suite_hud", core = true,
    defaultEnabled = NS.Client.isMainline,
    description = "An MSUF-owned objective tracker with grouped, readable entries.",
    available = MainlineFamily,
})
local objectiveContent = {
    B.Bool("showAchievements", "Tracked achievements", true),
    B.Bool("showScenario", "Scenario and delve steps", true),
    B.Bool("showWorldQuests", "World quests", true),
    B.Bool("showBonus", "Nearby bonus objectives", true),
    B.Bool("showQuestItems", "Usable quest items", true),
    B.Bool("showTimers", "Objective countdowns", true),
}
if NS.Client.isMainline and not NS.Client.isForever then
    table.insert(objectiveContent, 1,
        B.Bool("showMythicPlus", "Replace objectives with the Mythic+ timer during a key", true))
end
B.Section("objectives", "content", "What to track", objectiveContent)
B.Section("objectives", "layout", "Size and position", {
    B.Number("width", "Tracker width", 310, 220, 520, 5),
    B.Number("height", "Maximum tracker height", 570, 220, 900, 10),
    B.Number("scale", "Scale (percent)", 100, 60, 160, 5),
    B.Number("x", "Horizontal position", -35, -4000, 4000),
    B.Number("y", "Vertical position", -290, -3000, 3000),
})
B.Section("objectives", "type", "Tracker text", {
    B.Font("font", "Font (empty: Suite font)"),
    B.Number("titleSize", "Tracker title size", 18, 11, 28),
    B.Number("sectionSize", "Group heading size", 14, 9, 20),
    B.Number("entrySize", "Quest title size", 15, 10, 24),
    B.Number("objectiveSize", "Objective text size", 13, 9, 20),
})
B.Section("objectives", "colors", "Tracker colors", {
    B.Choice("colorStyle", "Color source", 1, { "Suite skin + default accents", "Custom colors" }),
    B.Number("backgroundOpacity", "Background opacity (percent)", 0, 0, 100, 1),
    B.Color("backgroundColor", "Background", "090a0c"),
    B.Color("titleColor", "Tracker title", "f5f7fa"),
    B.Color("textColor", "Quest titles", "f2f5fa"),
})
B.Section("objectives", "detailColors", "Objective text colors", {
    B.Color("mutedColor", "Objective details", "c7cfd9"),
    B.Color("completeColor", "Completed objectives", "7dc088"),
    B.Color("dividerColor", "Header divider", "b0b8c7"),
})
B.Section("objectives", "questColors", "Quest group colors", {
    B.Color("focusedColor", "Focused quest", "fad66b"),
    B.Color("campaignColor", "Campaign", "fac252"),
    B.Color("importantColor", "Important quest", "f085c9"),
})
B.Section("objectives", "activityColors", "Activity group colors", {
    B.Color("scenarioColor", "Scenario and delve", "63a3e6"),
    B.Color("completeGroupColor", "Ready to turn in", "63db8a"),
    B.Color("questsColor", "Regular quests", "e8ebf2"),
})
B.Section("objectives", "extraColors", "Extra group colors", {
    B.Color("worldColor", "World quests", "ba94f0"),
    B.Color("bonusColor", "Bonus objectives", "78d1cc"),
    B.Color("achievementsColor", "Achievements", "d49e61"),
})

B.Module("announcements", {
    title = "Announcements", page = "suite_hud", core = true,
    defaultEnabled = NS.Client.isMainline,
    description = "Cinematic zone and event announcements in the Suite look.",
    available = MainlineFamily,
})
B.Section("announcements", "content", "Announcements", {
    B.Bool("zone", "Zone and subzone", true),
    B.Bool("eventToasts", "Replace Blizzard event banners", true),
    B.Bool("quests", "Quest accepted and completed", true),
    B.Bool("achievements", "Achievements", true),
    B.Bool("level", "Level up", true),
    B.Bool("scenario", "Scenario complete", true),
})
B.Section("announcements", "layout", "Timing and position", {
    B.Number("duration", "Display time (seconds)", 4, 2, 8),
    B.Number("scale", "Scale (percent)", 100, 60, 160, 5),
    B.Choice("anchor", "Position relative to", 1, { "Top center", "Screen center" }),
    B.Number("x", "Horizontal position", 0, -4000, 4000),
    B.Number("y", "Vertical position", -90, -3000, 3000),
})
B.Section("announcements", "type", "Announcement text", {
    B.Font("font", "Font (empty: Suite font)"),
    B.Number("titleSize", "Headline size", 31, 20, 42),
    B.Number("subtitleSize", "Subtitle size", 16, 10, 24),
})
B.Section("announcements", "colors", "Announcement colors", {
    B.Choice("colorStyle", "Color source", 1, { "Suite skin + default accents", "Custom colors" }),
    B.Number("backgroundOpacity", "Background opacity (percent)", 57, 0, 100, 1),
    B.Color("backgroundColor", "Background", "050609"),
    B.Color("subtitleColor", "Subtitle", "e8edf5"),
    B.Color("zoneColor", "Zone headline", "f5e0ab"),
})
B.Section("announcements", "eventColors", "Event headline colors", {
    B.Color("questColor", "Quests", "fac965"),
    B.Color("achievementColor", "Achievements", "e0b069"),
    B.Color("levelColor", "Level up", "78cffa"),
})
B.Section("announcements", "moreEventColors", "More headline colors", {
    B.Color("scenarioColor", "Scenarios", "b094f5"),
    B.Color("noticeColor", "Other events", "a8d6fa"),
})

-- Editing any HUD color switches the color source to Custom colors.
for _, hud in ipairs({ "objectives", "announcements" }) do
    local colors = {}
    for key, rule in pairs(NS.SuiteCatalog[hud].rules) do
        if rule.color then colors[key] = true end
    end
    NS.SuiteCatalog[hud].look = { key = "colorStyle", visualKeys = colors, custom = 2 }
end

-- This screen has deliberately no appearance or layout rules. The HUD page
-- exposes only the module's standard enable switch.
B.Module("afkScreen", {
    title = "AFK Screen", page = "suite_hud", core = true,
    defaultEnabled = true,
    description = "A cinematic Suite screen with your character while you are AFK. Move or use /afk to return.",
})
