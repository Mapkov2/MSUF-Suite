local _, NS = ...
local B = NS.CatalogBuild

-- The two HUDs own their frames.
B.Module("objectives", {
    title = "Objective Tracker", page = "suite_hud", core = true,
    description = "An MSUF-owned objective tracker with grouped, readable entries.",
})
local objectiveContent = {
    B.Bool("pauseInRaidCombat", "Pause tracker during raid combat", false),
    B.Bool("hideInRaid", "Hide tracker throughout raid instances", false),
    B.Bool("hideDuringBoss", "Hide tracker during raid boss encounters", false),
    B.Bool("showHeader", "Show tracker heading", true),
    B.Choice("questIconStyle", "Quest type symbols", 1, { "Off", "Suite symbols", "Blizzard symbols" }),
    B.Bool("showAchievements", "Tracked achievements", true),
    B.Bool("showScenario", "Scenario and delve steps", true),
    B.Bool("showWorldQuests", "World quests", true),
    B.Bool("showBonus", "Nearby bonus objectives", true),
    B.Bool("showQuestItems", "Usable quest items", true),
    B.Bool("showTimers", "Objective countdowns", true),
}
if not NS.Client.isForever then
    table.insert(objectiveContent, 1,
        B.Bool("showMythicPlus", "Replace objectives with the Mythic+ timer during a key", true))
end
B.Section("objectives", "content", "What to track", objectiveContent)
if not NS.Client.isForever then
    -- One choice names both the reference (a boss's own best or the fastest
    -- whole run) and its scope (this keystone level or any level).
    B.Section("objectives", "mythic", "Mythic+ boss pace", {
        B.Choice("bossPace", "Boss pace reference", 1, { "Off", "Best time per boss, this key level",
            "Best time per boss, any key level", "Fastest run, this key level", "Fastest run, any key level" }),
        B.Bool("bossTargets", "Show the target time of bosses still alive", false),
    })
    B.Section("objectives", "mythicBars", "Mythic+ bars", {
        B.Number("timerBarHeight", "Timer bar height", 7, 3, 22, 1),
        B.Bool("timerBarText", "Show time inside the timer bar"),
        B.Bool("timerThresholds", "Show upgrade threshold markers"),
        B.Number("chestSpacing", "Upgrade row spacing", 22, 17, 25, 1),
        B.Bool("showForcesBar", "Show the enemy forces bar", true),
        B.Bool("showForcesText", "Show the enemy forces text", true),
        B.Bool("showObservedPull", "Show observed enemy forces projection"),
        B.Number("forcesBarHeight", "Enemy forces bar height", 5, 2, 16, 1),
        B.Number("forcesBarWidth", "Enemy forces bar width (percent)", 100, 30, 100, 5),
        B.Number("forcesTextSize", "Enemy forces text size", 13, 9, 20, 1),
    })
    B.Section("objectives", "raid", "Raid encounters", {
        B.Bool("showRaid", "Show raid encounters in the objective tracker", false),
    })
end
B.Section("objectives", "layout", "Size and position", {
    B.Number("width", "Tracker width", 310, 220, 520, 5),
    B.Number("height", "Maximum tracker height", 570, 220, 900, 10),
    B.Number("scale", "Scale (percent)", 100, 60, 160, 5),
    B.Number("x", "Horizontal position", -35, -4000, 4000),
    B.Number("y", "Vertical position", -290, -3000, 3000),
})
B.Section("objectives", "type", "Tracker text", {
    B.Font("font", "Font"),
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

-- A separate result card remains available when the objective tracker is off.
-- It reads completion events only and has its own MSUF Edit Mode mover.
B.Module("runSummary", {
    title = "Run Summaries", page = "suite_hud", defaultEnabled = true,
    description = "A movable summary after a Mythic+ run or raid boss kill.",
})
local summaryContent = {
    B.Bool("showRaid", "Show after raid boss kills", true),
    B.Bool("showDuration", "Show completion time", true),
    B.Bool("showBest", "Show fastest raid kill", true),
    B.Bool("showGroupSize", "Show raid group size", true),
    B.Bool("showKills", "Show recorded raid kills", true),
    B.Number("autoHide", "Close automatically after (seconds; 0 = manual)", 0, 0, 120, 5),
}
if not NS.Client.isForever then
    table.insert(summaryContent, 1, B.Bool("showMythicPlus", "Show after Mythic+ runs", true))
    summaryContent[#summaryContent + 1] = B.Bool("showTimer", "Show Mythic+ timer result", true)
    summaryContent[#summaryContent + 1] = B.Bool("showDeaths", "Show Mythic+ deaths", true)
    summaryContent[#summaryContent + 1] = B.Bool("showPenalty", "Show Mythic+ time penalty", true)
    summaryContent[#summaryContent + 1] = B.Bool("showUpgrades", "Show keystone upgrade", true)
    summaryContent[#summaryContent + 1] = B.Bool("showScore", "Show rating change when available", true)
    summaryContent[#summaryContent + 1] = B.Bool("showRecord", "Show new dungeon record", true)
end
B.Section("runSummary", "content", "Results and details", summaryContent)
if not NS.Client.isForever then
    -- The party table grows by detail level instead of one switch per column.
    B.Section("runSummary", "history", "Mythic+ party and history", {
        B.Choice("partyDetails", "Party table", 3, { "Off", "Characters and scores", "Add combat figures",
            "Add combat figures and loot" }),
        B.Number("playerRowHeight", "Player row height", 25, 20, 40, 1),
        -- 1 to 100 runs, the range the profile history offered before it moved
        -- to the character.
        B.Number("keepRuns", "Runs kept per character", 30, 1, 100, 1),
        B.Choice("cardTiming", "Show the Mythic+ card", 1, { "When the key ends", "After closing the chest loot" }),
    })
end
B.Section("runSummary", "layout", "Size and position", {
    B.Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    B.Number("width", "Summary width", 390, 260, 650, 5),
    B.Number("scale", "Scale (percent)", 100, 60, 160, 5),
    B.Number("x", "Horizontal position", 0, -4000, 4000),
    B.Number("y", "Vertical position", 80, -3000, 3000),
})
B.Section("runSummary", "type", "Summary text", {
    B.Font("font", "Font"),
    B.Number("titleSize", "Title size", 20, 12, 30),
    B.Number("detailSize", "Detail size", 14, 10, 22),
})
B.Section("runSummary", "colors", "Summary colors", {
    B.Choice("colorStyle", "Color source", 1, { "Suite skin + default accents", "Custom colors" }),
    B.Number("backgroundOpacity", "Background opacity (percent)", 92, 0, 100, 1),
    B.Color("backgroundColor", "Background", "10151d"),
    B.Color("titleColor", "Title", "f5f7fa"),
    B.Color("textColor", "Details", "e5edf5"),
    B.Color("accentColor", "Accent", "63db8a"),
})

B.Module("announcements", {
    title = "Announcements", page = "suite_hud", core = true,
    description = "Cinematic zone and event announcements in the Suite look.",
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
    B.Font("font", "Font"),
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
for _, hud in ipairs({ "objectives", "runSummary", "announcements" }) do
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
