local _, P = ...
local S, Tr = P.S, P.Tr
local PAGE = "suite_hud"

local function AppearanceRules(id)
    local rules = P.SectionRules(id, "type")
    local colorSections = id == "objectives"
        and { "colors", "detailColors", "questColors", "activityColors", "extraColors" }
        or { "colors", "eventColors", "moreEventColors" }
    if id == "runSummary" then colorSections = { "colors" } end
    for _, section in ipairs(colorSections) do
        for _, rule in ipairs(P.SectionRules(id, section)) do
            -- RuleSection renders non-color controls and collects all color
            -- rules in its existing three-dot shortcut.
            rules[#rules + 1] = rule
        end
    end
    return rules
end

local function OpenColors(id)
    local M = P.M
    if type(M.SelectPage) ~= "function" or M.SelectPage("opt_colors") == false then return end
    if type(M.ColorsSetPainterCategory) == "function" then M.ColorsSetPainterCategory("suite") end
    local entry = M.cache and M.cache.opt_colors
    local section = entry and entry.sections and entry.sections["colors_suite_" .. id]
    if section and P.W.FocusCollapsibleSection then
        P.W.FocusCollapsibleSection(section, { flash = true })
    end
end

local function Build(ctx)
    local b = P.W.PageBuilder(ctx)
    P.ModuleCard(ctx, b, PAGE, "objectives", {
        { "Move in Edit Mode", function() P.MoveOnScreen("objectives", "tracker") end,
            key = "edit" },
        { "Tracker colors", function() OpenColors("objectives") end, key = "colors" },
    }, { title = "Objective Tracker" })
    P.RuleSection(ctx, b, PAGE, "objectives", "suite_hud_objectives_content",
        Tr("What to track"), P.SectionRules("objectives", "content"), {
            help = "A Suite-owned tracker with grouped quests, world quests, scenario steps and tracked achievements. The raid combat option pauses ordinary objectives; the optional raid encounter view stays active during boss pulls. Click a group heading or the small button on an entry to collapse it. Quest titles open their quest log page; right-click opens its actions. The Blizzard tracker is hidden while this module is active.",
            open = true,
        })
    local raidRules = P.SectionRules("objectives", "raid")
    if raidRules and #raidRules > 0 then
        P.RuleSection(ctx, b, PAGE, "objectives", "suite_hud_objectives_raid",
            Tr("Raid encounters"), raidRules, {
                help = "During a raid encounter, show the boss name, pull time, active boss units, best wipe progress and fastest kill. DBM or BigWigs can supply phases of the same boss; without them, the phase stays unknown. Multi-boss progress counts defeated bosses before comparing the remaining health of surviving bosses. Records begin with pulls observed by this Suite profile. Boss health appears live only when the client exposes a readable value. This view uses the Objective Tracker position and replaces ordinary objectives while inside a raid.",
            })
    end
    P.RuleSection(ctx, b, PAGE, "objectives", "suite_hud_objectives_layout",
        Tr("Size and position"), P.SectionRules("objectives", "layout"), {
            help = "Drag the tracker in MSUF Edit Mode, or enter exact size and position here.",
        })
    P.RuleSection(ctx, b, PAGE, "objectives", "suite_hud_objectives_type",
        Tr("Appearance"), AppearanceRules("objectives"), {
            help = "Set font, text sizes and opacity here. Open the three-dot color menu in this section for tracker colors; choosing one switches to Custom colors automatically.",
        })
    local function SummaryAction(method, ...)
        local module = S.instances and S.instances.runSummary
        if module and module.active and type(module[method]) == "function" then
            return module[method](module, ...)
        end
    end
    local summaryActions = {
        { "Move in Edit Mode", function() P.MoveOnScreen("runSummary", "summary") end, key = "edit" },
        { "Preview raid result", function() SummaryAction("Preview", "raid") end, key = "preview_raid" },
        { "Show last result", function() SummaryAction("ShowLast") end, key = "last" },
        { "Summary colors", function() OpenColors("runSummary") end, key = "colors" },
    }
    if S.catalog.runSummary.rules.showMythicPlus then
        table.insert(summaryActions, 2,
            { "Preview Mythic+ result", function() SummaryAction("Preview", "mythic") end, key = "preview_mythic" })
    end
    P.ModuleCard(ctx, b, PAGE, "runSummary", summaryActions, { title = "Run Summaries" })
    P.RuleSection(ctx, b, PAGE, "runSummary", "suite_hud_summary_content",
        Tr("Results and details"), P.SectionRules("runSummary", "content"), {
            help = "After a completed Mythic+ run or successful raid encounter, show the public result values in a separate card. Choose which figures appear and how long the card stays open. The last result can be reopened here. Combat delays the card until it is safe to show.",
            open = true,
        })
    P.RuleSection(ctx, b, PAGE, "runSummary", "suite_hud_summary_layout",
        Tr("Size and position"), P.SectionRules("runSummary", "layout"), {
            help = "Drag the result card in MSUF Edit Mode, or set its screen anchor, width, scale and position here.",
        })
    P.RuleSection(ctx, b, PAGE, "runSummary", "suite_hud_summary_type",
        Tr("Appearance"), AppearanceRules("runSummary"), {
            help = "Set font, text sizes and opacity here. Use the three-dot color menu for the card palette.",
        })
    P.ModuleCard(ctx, b, PAGE, "announcements", {
        { "Move in Edit Mode", function() P.MoveOnScreen("announcements", "banner") end,
            key = "edit" },
        { "Announcement colors", function() OpenColors("announcements") end, key = "colors" },
    }, { title = "Announcements" })
    P.RuleSection(ctx, b, PAGE, "announcements", "suite_hud_announcements_content",
        Tr("Announcement content"), P.SectionRules("announcements", "content"), {
            help = "MSUF replaces Blizzard's zone text and event banners. Quest, achievement and scenario alert frames are hidden when their MSUF announcements are enabled. Turning a type off restores Blizzard's corresponding alert.",
            open = true,
        })
    P.RuleSection(ctx, b, PAGE, "announcements", "suite_hud_announcements_layout",
        Tr("Timing and position"), P.SectionRules("announcements", "layout"), {
            help = "Drag announcements in MSUF Edit Mode, or set their timing, scale and exact position here.",
        })
    P.RuleSection(ctx, b, PAGE, "announcements", "suite_hud_announcements_type",
        Tr("Appearance"), AppearanceRules("announcements"), {
            help = "Set font, text sizes and background opacity here. Open the three-dot color menu in this section for announcement colors; choosing one switches to Custom colors automatically.",
        })
    P.ModuleCard(ctx, b, PAGE, "afkScreen", nil, { title = "AFK Screen" })
end

P.RegisterPage({ key = PAGE, label = "HUD", title = "HUD", build = Build, icon = { 7, 1 },
    aliases = { "objectives", "objective tracker", "run summary", "mythic plus", "raid kill", "announcements", "events", "afk", "hud" } })
