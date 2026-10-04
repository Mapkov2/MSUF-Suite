local _, P = ...
local V, Tr = P.HUDPreview, P.Tr
local DrawText, Fill, Color = V.Label, V.Fill, V.Color
local WHITE, TEXT, MUTED = { .96, .97, .99 }, { .95, .96, .98 }, { .78, .81, .85 }
local GOLD, GREEN = { .98, .79, .39 }, { .39, .86, .54 }
V.Choices = {
    objectives = { { "quests", "QUESTS" }, { "world", "WORLD QUESTS" }, { "scenario", "SCENARIO" },
        { "achievements", "ACHIEVEMENTS" } },
    runSummary = { { "raid", "Preview raid result" } },
    announcements = { { "zone", "Zone and subzone" }, { "quest", "Quest accepted and completed" }, { "achievement", "Achievements" },
        { "level", "Level up" }, { "scenario", "Scenario complete" }, { "notice", "Other events" } },
    afkScreen = { { "character", "Character" } },
}
if not P.Suite.Client.isForever then
    V.Choices.runSummary[#V.Choices.runSummary + 1] = { "mythic", "Preview Mythic+ result" }
end
local TRACKER_GROUPS = {
    quests = { "QUESTS", "questsColor", { .91, .92, .95 } },
    world = { "WORLD QUESTS", "worldColor", { .73, .58, .94 }, "showWorldQuests" },
    scenario = { "SCENARIO", "scenarioColor", { .39, .64, .90 }, "showScenario" },
    achievements = { "ACHIEVEMENTS", "achievementsColor", { .83, .62, .38 }, "showAchievements" },
}

local function Tracker(ui, mode)
    local c, width, y = ui.config, ui.config.width, -12
    local group = TRACKER_GROUPS[mode] or TRACKER_GROUPS.quests
    local text = { Color(c, "textColor", TEXT, "text") }
    if c.showHeader then
        DrawText(ui, Tr("OBJECTIVES"), 11, -7, width - 40, c.titleSize, { Color(c, "titleColor", WHITE, "title") })
        Fill(ui, 11, -33, width - 22, 1, { Color(c, "dividerColor", MUTED, "borderSoft") }, .35)
        y = -46
    end
    if not group[4] or c[group[4]] then
        DrawText(ui, Tr(group[1]), 11, y, width - 22, c.sectionSize, { Color(c, group[2], group[3]) })
        y = y - c.sectionSize - 14
        local symbol = c.questIconStyle == 1 and "" or c.questIconStyle == 2 and "! "
            or "|TInterface\\GossipFrame\\AvailableQuestIcon:16:16|t "
        DrawText(ui, symbol .. Tr("Example Quest"), 18, y, width - 36, c.entrySize, text)
        y = y - c.entrySize - 9
        DrawText(ui, "3/8  " .. Tr("Collect supplies"), 28, y, width - 42, c.objectiveSize, text)
        y = y - c.objectiveSize - 7
        DrawText(ui, "5/5  " .. Tr("Defeat enemies"), 28, y, width - 42, c.objectiveSize,
            { Color(c, "completeColor", { .49, .75, .53 }) })
        y = y - c.objectiveSize - 7
        if c.showTimers then
            DrawText(ui, "2:34", 28, y, width - 42, c.objectiveSize, { Color(c, "mutedColor", MUTED, "muted") })
            y = y - c.objectiveSize - 7
        end
    end
    local height = math.min(c.height, math.max(70, -y + 10))
    local background = Fill(ui, 0, 0, width, height,
        { Color(c, "backgroundColor", { .035, .039, .047 }, "surface") }, c.backgroundOpacity / 100)
    background:SetDrawLayer("BACKGROUND", -1)
    return width, height
end

local function ResultRows(c, mode)
    local rows = {}
    local function Add(key, label, value) if c[key] then rows[#rows + 1] = { Tr(label), value } end end
    if mode == "mythic" then
        Add("showDuration", "Run time", "23:42")
        Add("showTimer", "Timer", Tr("In time"))
        Add("showDeaths", "Deaths", "2")
        Add("showPenalty", "Time penalty", "0:10")
        Add("showUpgrades", "Keystone", "+2")
        Add("showScore", "Rating", "+18")
        Add("showRecord", "Record", Tr("New best"))
    else
        Add("showDuration", "Kill time", "4:34")
        Add("showBest", "Fastest kill", "4:34")
        Add("showGroupSize", "Group size", "20")
        Add("showKills", "Kills recorded", "1")
    end
    return rows
end

local function Summary(ui, mode)
    local c, width = ui.config, ui.config.width
    local title = { Color(c, "titleColor", WHITE) }
    local text = { Color(c, "textColor", { .88, .92, .97 }, "text") }
    local accent = { Color(c, "accentColor", GREEN) }
    DrawText(ui, Tr(mode == "mythic" and "MYTHIC+ COMPLETE" or "RAID BOSS DEFEATED"), 18, -17, width - 40, c.titleSize, title)
    local subtitle = mode == "mythic" and string.format(Tr("Example Dungeon  +%d"), 15) or Tr("Example Boss")
    DrawText(ui, subtitle, 18, -51, width - 36, c.detailSize, accent)
    local y = -91
    local labelWidth = math.floor(math.max(95, math.min(142, width * .38)))
    for _, row in ipairs(ResultRows(c, mode)) do
        DrawText(ui, row[1], 18, y, labelWidth, c.detailSize, text)
        DrawText(ui, row[2], 26 + labelWidth, y, width - labelWidth - 44, c.detailSize, title)
        y = y - math.max(27, c.detailSize + 6)
    end
    local height = -y + 10
    Fill(ui, 0, 0, width, height, { Color(c, "backgroundColor", { .05, .07, .10 }, "surface") }, c.backgroundOpacity / 100)
    Fill(ui, 0, 0, width, 3, accent)
    return width, height
end

local ANNOUNCEMENTS = {
    zone = { "Example Dungeon", "NEW AREA", "zoneColor", { .96, .88, .67 } },
    quest = { "Example Quest", "QUEST COMPLETE", "questColor", GOLD },
    achievement = { "Example Quest", "ACHIEVEMENT EARNED", "achievementColor", { .88, .69, .41 } },
    level = { "LEVEL UP", "LEVEL UP", "levelColor", { .47, .81, .98 } },
    scenario = { "SCENARIO COMPLETE", "Defeat enemies", "scenarioColor", { .69, .58, .96 } },
    notice = { "Other events", "Example Dungeon", "noticeColor", { .66, .84, .98 } },
}
local function Announcement(ui, mode)
    local c, sample = ui.config, ANNOUNCEMENTS[mode] or ANNOUNCEMENTS.zone
    local color = { Color(c, sample[3], sample[4]) }
    Fill(ui, 65, -8, 530, 111, { Color(c, "backgroundColor", { .02, .025, .035 }, "surface") }, c.backgroundOpacity / 100)
    Fill(ui, 312.5, -12, 35, 2, color, .95)
    Fill(ui, 200, -75, 260, 1, color, .62)
    local title = mode == "level" and string.format(Tr("LEVEL %d"), 70) or Tr(sample[1])
    DrawText(ui, title, 14, -23, 632, c.titleSize, color, 80, 2):SetJustifyH("CENTER")
    DrawText(ui, Tr(sample[2]), 18, -84, 624, c.subtitleSize,
        { Color(c, "subtitleColor", { .91, .93, .96 }, "text") }, 75, 1):SetJustifyH("CENTER")
    return 660, 130
end

V.Render = { objectives = Tracker, runSummary = Summary, announcements = Announcement }
