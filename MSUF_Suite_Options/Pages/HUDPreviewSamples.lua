local _, P = ...
local V, Tr = P.HUDPreview, P.Tr
local DrawText, Fill, Color = V.Label, V.Fill, V.Color
local WHITE, TEXT, MUTED = { .96, .97, .99 }, { .95, .96, .98 }, { .78, .81, .85 }
local GOLD, GREEN = { .98, .79, .39 }, { .39, .86, .54 }
V.Choices = {
    objectives = { { "quests", "QUESTS" }, { "world", "WORLD QUESTS" }, { "scenario", "SCENARIO" },
        { "achievements", "ACHIEVEMENTS" }, { "collectibles", "COLLECTIBLES" }, { "zone", "ZONE EVENT" },
        { "focused", "FOCUSED" }, { "campaign", "CAMPAIGN" }, { "important", "IMPORTANT" },
        { "complete", "READY TO TURN IN" }, { "bonus", "BONUS OBJECTIVES" } },
    runSummary = { { "raid", "Preview raid result" } },
    announcements = { { "zone", "Zone and subzone" }, { "quest", "Quest accepted and completed" }, { "achievement", "Achievements" },
        { "level", "Level up" }, { "scenario", "Scenario complete" }, { "notice", "Other events" } },
    afkScreen = { { "character", "Character" } },
}
if not P.Suite.Client.isForever then
    V.Choices.runSummary[#V.Choices.runSummary + 1] = { "mythic", "Preview Mythic+ result" }
    for _, choice in ipairs({ { "travelersLog", "TRAVELER'S LOG" }, { "endeavors", "ENDEAVORS" },
        { "recipes", "PROFESSIONS" }, { "mythic", "MYTHIC+" }, { "mythicLate", "MYTHIC+ OVER TIME" } }) do
        V.Choices.objectives[#V.Choices.objectives + 1] = choice
    end
end
V.Choices.objectives[#V.Choices.objectives + 1] = { "raid", "RAID" }
-- The heading, color setting, default color and show setting of each group;
-- the colors match MSUF_Suite_Modules/ObjectivesTracker.lua. Tracked recipes
-- are headed by Blizzard's own profession tracker header there.
local TRACKER_GROUPS = {
    quests = { "QUESTS", "questsColor", { .91, .92, .95 } },
    world = { "WORLD QUESTS", "worldColor", { .73, .58, .94 }, "showWorldQuests" },
    scenario = { "SCENARIO", "scenarioColor", { .39, .64, .90 }, "showScenario" },
    achievements = { "ACHIEVEMENTS", "achievementsColor", { .83, .62, .38 }, "showAchievements" },
    collectibles = { "COLLECTIBLES", "achievementsColor", { .93, .66, .40 }, "showCollectibles" },
    zone = { "ZONE EVENT", "scenarioColor", { .45, .72, .95 }, "showZoneEvents" },
    travelersLog = { "TRAVELER'S LOG", "questsColor", { .60, .82, .70 }, "showTravelersLog" },
    endeavors = { "ENDEAVORS", "questsColor", { .86, .60, .72 }, "showEndeavors" },
    focused = { "FOCUSED", "focusedColor", { .98, .84, .42 } },
    campaign = { "CAMPAIGN", "campaignColor", { .98, .76, .32 } },
    important = { "IMPORTANT", "importantColor", { .94, .52, .79 } },
    complete = { "READY TO TURN IN", "completeGroupColor", { .39, .86, .54 } },
    bonus = { "BONUS OBJECTIVES", "bonusColor", { .47, .82, .80 }, "showBonus" },
    recipes = { PROFESSIONS_TRACKER_HEADER_PROFESSION or "PROFESSIONS", "recipesColor", { .91, .92, .95 }, "showRecipes" },
}
-- The Mythic+ and raid views of the tracker (HUDPreviewViews.lua).
V.Views = {}
-- The group underline is as tall as the tracker draws it.
local UNDERLINE_HEIGHT = 4

-- The tracker heading with its title and entry count; returns the next row.
local function Header(ui, title, count)
    local c, width = ui.config, ui.config.width
    if not c.showHeader then return -12 end
    DrawText(ui, Tr(title), 11, -7, width - 40, c.titleSize, { Color(c, "titleColor", WHITE, "title") })
    DrawText(ui, Tr(count), width - 56, -10, 45, c.sectionSize, { Color(c, "mutedColor", MUTED, "muted") })
        :SetJustifyH("RIGHT")
    Fill(ui, 11, -33, width - 22, 1, { Color(c, "dividerColor", MUTED, "borderSoft") }, .35)
    return -46
end

-- One group: its heading in the group color, an entry and its objectives.
-- Rows carry a stripe in the group color or, with group underlines on, a line
-- under the heading.
local function Group(ui, group, y)
    local c, width = ui.config, ui.config.width
    local color = { Color(c, group[2], group[3]) }
    local top = y
    DrawText(ui, Tr(group[1]), 11, y, width - 22, c.sectionSize, color)
    y = y - c.sectionSize - 14
    if c.groupUnderlines then
        Fill(ui, 13, y + UNDERLINE_HEIGHT, width - 17, UNDERLINE_HEIGHT, { P.RGB(c.dividerColor) })
    end
    local text = { Color(c, "textColor", TEXT, "text") }
    local symbol = c.questIconStyle == 1 and "" or c.questIconStyle == 2 and "! "
        or "|TInterface\\GossipFrame\\AvailableQuestIcon:16:16|t "
    DrawText(ui, symbol .. Tr("Example Quest"), 18, y, width - 36, c.entrySize, text)
    y = y - c.entrySize - 9
    local entryBottom = y
    DrawText(ui, "3/8  " .. Tr("Collect supplies"), 28, y, width - 42, c.objectiveSize, text)
    y = y - c.objectiveSize - 7
    DrawText(ui, "5/5  " .. Tr("Defeat enemies"), 28, y, width - 42, c.objectiveSize,
        { Color(c, "completeColor", { .49, .75, .53 }) })
    y = y - c.objectiveSize - 7
    if c.showTimers then
        DrawText(ui, "2:34", 28, y, width - 42, c.objectiveSize, { Color(c, "mutedColor", MUTED, "muted") })
        y = y - c.objectiveSize - 7
    end
    if not c.groupUnderlines then
        Fill(ui, 2, top + 2, 2, top + 2 - entryBottom, color, .95)
        Fill(ui, 2, entryBottom, 2, entryBottom - y, color, .35)
    end
    return y
end

local function Tracker(ui, mode)
    local c, width = ui.config, ui.config.width
    local view = V.Views[mode]
    local y = Header(ui, view and view.title or "OBJECTIVES", view and view.count or "1")
    local group = TRACKER_GROUPS[mode] or TRACKER_GROUPS.quests
    if view then
        y = view.draw(ui, y)
    elseif not group[4] or c[group[4]] then
        y = Group(ui, group, y)
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
    DrawText(ui, Tr(mode == "mythic" and "MYTHIC+ COMPLETE" or "RAID BOSS DEFEATED"), 18, -17, width - 40, c.titleSize,
        title, "title")
    local subtitle = mode == "mythic" and string.format(Tr("Example Dungeon  +%d"), 15) or Tr("Example Boss")
    DrawText(ui, subtitle, 18, -51, width - 36, c.detailSize, accent, "subtitle")
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
    DrawText(ui, title, 14, -23, 632, c.titleSize, color, "banner"):SetJustifyH("CENTER")
    DrawText(ui, Tr(sample[2]), 18, -84, 624, c.subtitleSize,
        { Color(c, "subtitleColor", { .91, .93, .96 }, "text") }, "subtitle"):SetJustifyH("CENTER")
    return 660, 130
end

V.Render = { objectives = Tracker, runSummary = Summary, announcements = Announcement }
