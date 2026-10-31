local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_Modules")

-- The two HUDs own their frames. The tracker hides Blizzard's, so another
-- addon that replaces it (Kaliel's Tracker, CurseForge folder !KalielsTracker)
-- keeps the field: the module then reports "Managed by" instead of running.
B.Module("objectives", {
    title = "Objective Tracker", page = "suite_hud", core = true,
    conflicts = { "!KalielsTracker" },
    description = "An MSUF-owned objective tracker with grouped, readable entries.",
    summary = "width height entrySize objectiveSize colorStyle backgroundOpacity",
})
local objectiveContent = {
    B.Bool("pauseInRaidCombat", "Pause tracker during raid combat", false),
    B.Bool("hideInRaid", "Hide tracker throughout raid instances", false),
    B.Bool("hideDuringBoss", "Hide tracker during raid boss encounters", false),
    B.Bool("showHeader", "Show tracker heading", true),
    B.Bool("groupUnderlines", "Underline tracker group headings", false),
    B.Choice("questIconStyle", "Quest type symbols", 1, { "Off", "Suite symbols", "Blizzard symbols" }),
    B.Bool("showAchievements", "Tracked achievements", true),
    B.Bool("showCollectibles", "Tracked collectibles", true),
    B.Bool("showScenario", "Scenario and delve steps", true),
    B.Bool("showZoneEvents", "Zone event progress", true),
    B.Bool("showWorldQuests", "World quests", true),
    B.Bool("showBonus", "Nearby bonus objectives", true),
    B.Bool("showQuestItems", "Usable quest items", true),
    B.Bool("showTimers", "Objective countdowns", true),
}
local function IndexOf(rules, key)
    for i, rule in ipairs(rules) do
        if rule.key == key then return i end
    end
end
if not NS.Client.isForever then
    table.insert(objectiveContent, 1,
        B.Bool("showMythicPlus", "Replace objectives with the Mythic+ timer during a key", true))
    -- The Traveler's Log and Housing endeavors exist on Retail only: the
    -- Traveler's Log is a Mainline-only part of the Adventure Guide and the
    -- Housing addons do not load in Forever's Camelot client. Tracked recipes
    -- (professions) are Retail only as well.
    local after = IndexOf(objectiveContent, "showCollectibles")
    table.insert(objectiveContent, after + 1, B.Bool("showTravelersLog", "Traveler's Log activities", true))
    table.insert(objectiveContent, after + 2, B.Bool("showEndeavors", "Housing endeavors", true))
    table.insert(objectiveContent, after + 3, B.Bool("showRecipes", "Tracked recipes", true))
end
B.Section("objectives", "content", "What to track", objectiveContent)
-- Settings that change nothing in some states of another setting stay greyed
-- there (MSUF_Suite_Options/Menu/Bridge.lua, P.RuleEnabled). Hiding the tracker
-- throughout a raid makes the narrower raid rules moot.
local objectiveRules = NS.SuiteCatalog.objectives.rules
objectiveRules.hideDuringBoss.disabledBy = "hideInRaid"
objectiveRules.pauseInRaidCombat.disabledBy = "hideInRaid"
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
    -- Target times need a pace reference; the forces size settings need the
    -- forces bar or text they size.
    objectiveRules.bossTargets.requiresChoice = { key = "bossPace", values = { [2] = true, [3] = true, [4] = true, [5] = true } }
    objectiveRules.forcesBarHeight.enableKey = "showForcesBar"
    objectiveRules.forcesBarWidth.enableKey = "showForcesBar"
    objectiveRules.forcesTextSize.enableKey = "showForcesText"
end
-- The encounter view needs ENCOUNTER_START and ENCOUNTER_END, the boss unit
-- tokens, UNIT_HEALTH, INSTANCE_ENCOUNTER_ENGAGE_UNIT, UnitHealthPercent with
-- CurveConstants.ScaleTo100 and C_InstanceEncounter. Retail and WoW Forever
-- both document all of them (Blizzard_APIDocumentationGenerated).
B.Section("objectives", "raid", "Raid encounters", {
    B.Bool("showRaid", "Show raid encounters in the objective tracker", false),
})
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
B.TextStyle("objectives", "type", "Tracker text", 70)
B.Section("objectives", "colors", "Tracker colors", {
    B.Choice("colorStyle", "Color source", 1, { "Suite skin + default accents", "Custom colors" }),
    B.Number("backgroundOpacity", "Background opacity (percent)", 0, 0, 100, 1),
    B.Color("backgroundColor", "Background", "090a0c"),
    B.Color("titleColor", "Tracker title", "f5f7fa"),
    B.Color("textColor", "Quest titles", "f2f5fa"),
})
local detailColors = {
    B.Color("mutedColor", "Objective details", "c7cfd9"),
    B.Color("completeColor", "Completed objectives", "7dc088"),
    B.Color("dividerColor", "Header divider", "b0b8c7"),
}
-- The Mythic+ timer bar turns this color once the key is over time.
if not NS.Client.isForever then
    detailColors[#detailColors + 1] = B.Color("lateColor", "Mythic+ over time", "eb5c5c")
end
B.Section("objectives", "detailColors", "Objective text colors", detailColors)
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
local extraColors = {
    B.Color("worldColor", "World quests", "ba94f0"),
    B.Color("bonusColor", "Bonus objectives", "78d1cc"),
    B.Color("achievementsColor", "Achievements", "d49e61"),
}
-- Tracked recipes start in the regular quest color, as they always drew.
if not NS.Client.isForever then
    local recipes = B.Color("recipesColor", "Tracked recipes", "e8ebf2")
    recipes.enableKey = "showRecipes"
    extraColors[#extraColors + 1] = recipes
end
B.Section("objectives", "extraColors", "Extra group colors", extraColors)
-- A profile saved before recipes had their own color drew them in its quest
-- color; carry that color over once so the tracker looks the same.
if not NS.Client.isForever then
    NS.SuiteCatalog.objectives.prepareConfig = function(config)
        if config.recipesColor == nil and config.questsColor ~= nil then config.recipesColor = config.questsColor end
    end
end

-- A separate result card remains available when the objective tracker is off.
-- It reads completion events only and has its own MSUF Edit Mode mover.
B.Module("runSummary", {
    title = "Run Summaries", page = "suite_hud", defaultEnabled = true,
    description = "A movable summary after a Mythic+ run or raid boss kill.",
    summary = "width scale titleSize detailSize autoHide colorStyle backgroundOpacity",
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
    -- Rows only have a height while the party table shows.
    NS.SuiteCatalog.runSummary.rules.playerRowHeight.requiresChoice =
        { key = "partyDetails", values = { [2] = true, [3] = true, [4] = true } }
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
B.TextStyle("runSummary", "type", "Summary text", 70)
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
    summary = "duration anchor titleSize subtitleSize colorStyle backgroundOpacity",
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
B.TextStyle("announcements", "type", "Announcement text", 70)
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

------------------------------------------------------------------ shared readers
-- What the HUD modules (MSUF_Suite_Modules) and their menu previews
-- (MSUF_Suite_Options) both read from these rules, defined once so a preview
-- cannot drift from the screen it shows.

-- The text style settings of a HUD as the trailing arguments of
-- S.SetStyledFont: outline, rendering, shadow, shadow opacity and distance.
-- A setting that is missing keeps the text as it was drawn before the settings
-- existed. A role gives headline text a stronger shadow than the body text.
local OUTLINES = { "", "OUTLINE", "THICKOUTLINE" }
local NO_SETTINGS = {}
local ROLE_SHADOW = {
    title = { opacity = 10, distance = 0 },
    subtitle = { opacity = 5, distance = 0 },
    banner = { opacity = 10, distance = 1 },
}
function NS.HUDTextArgs(config, role)
    config = config or NO_SETTINGS
    local bonus = role and ROLE_SHADOW[role]
    local opacity = (config.fontShadowOpacity or 70) + (bonus and bonus.opacity or 0)
    return OUTLINES[config.fontOutline] or "OUTLINE", config.fontRendering or NS.FontRendering.SMOOTH,
        config.fontShadow ~= false, math.min(100, opacity), (config.fontShadowDistance or 1) + (bonus and bonus.distance or 0)
end

-- The inventory slots the AFK screen lists, in display order. The list ends
-- with slot 18, the ranged weapon, and slot 0, the ammunition: only WoW
-- Forever's character sheet has them (AFKSlotCount), Retail has neither.
NS.AFKSlots = { 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18, 0 }
NS.AFK_RANGED_ROW, NS.AFK_AMMO_ROW = 19, 20

-- How many of them the character sheet shows: the ranged slot only where
-- Blizzard's own gate shows it (C_PaperDollInfo.IsRangedSlotShown, Forever),
-- and the ammunition slot there too.
function NS.AFKSlotCount()
    return NS.Client.isForever and C_PaperDollInfo.IsRangedSlotShown() == true
        and NS.AFK_AMMO_ROW or NS.AFK_RANGED_ROW - 1
end
