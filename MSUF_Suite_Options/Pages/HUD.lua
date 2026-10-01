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

local function BuildObjectives(ctx, b)
    P.ModuleCard(ctx, b, PAGE, "objectives", {
        { "Move in Edit Mode", function() P.MoveOnScreen("objectives", "tracker") end,
            key = "edit" },
        { "Tracker colors", function() OpenColors("objectives") end, key = "colors" },
    }, { title = "Objective Tracker" })
    P.RuleSection(ctx, b, PAGE, "objectives", "suite_hud_objectives_content",
        Tr("What to track"), P.SectionRules("objectives", "content"), {
            help = P.Help("Choose what the Suite tracker lists and when it steps aside.", "The Suite draws its own tracker and hides Blizzard's while it runs. Entries are sorted into groups: the focused quest, campaign and important quests, quests ready to hand in, regular quests, world quests, nearby bonus objectives, scenario and delve steps, and tracked achievements. In a raid it can hide completely, only while a boss is engaged, or pause the regular list during any raid fight; the encounter view keeps running then. Quest symbols come as Suite letters or as Blizzard's icons, and the heading line can be switched off. The key binding Use tracked quest item uses the focused quest's item, else the first usable one, and picks a new item only outside combat. Left-click a group name to fold it or a quest to open its log entry; right-click for more actions."),
            open = true,
        })
    local mythicRules = P.SectionRules("objectives", "mythic")
    if mythicRules and #mythicRules > 0 then
        P.RuleSection(ctx, b, PAGE, "objectives", "suite_hud_objectives_mythic",
            Tr("Mythic+ boss pace"), mythicRules, {
                help = "While a key runs, each defeated boss shows how far ahead or behind you are: against the best time you ever had on that boss, or against the boss times of your fastest completed run, at this keystone level or at any. Only runs this character completed count. With target times on, bosses still alive show the time to beat.",
            })
    end
    local barRules = P.SectionRules("objectives", "mythicBars")
    if barRules and #barRules > 0 then
        P.RuleSection(ctx, b, PAGE, "objectives", "suite_hud_objectives_mythicBars",
            Tr("Mythic+ bars"), barRules, {
                help = "Observed enemies adds up the enemy forces of the living enemies in combat that you see as a nameplate or target, and the total they would bring. Enemies that give no forces count as zero; while the client keeps a value hidden, the line shows -- instead of a guess. Enemies out of sight are not counted.",
            })
    end
    local raidRules = P.SectionRules("objectives", "raid")
    if raidRules and #raidRules > 0 then
        P.RuleSection(ctx, b, PAGE, "objectives", "suite_hud_objectives_raid",
            Tr("Raid encounters"), raidRules, {
                help = P.Help("Follow raid pulls with your best progress and fastest kill.", "Inside a raid the tracker turns into an encounter view at its usual place: boss name, pull timer, the bosses engaged right now with their health, your best wipe and your fastest kill. Phases come from DBM or BigWigs when one is installed; otherwise the phase stays open. A wipe with more bosses down beats one with fewer, and with the same count the one with less boss health left wins. Each character keeps its own records. Boss health shows only while the client reveals it."),
            })
    end
    P.RuleSection(ctx, b, PAGE, "objectives", "suite_hud_objectives_layout",
        Tr("Size and position"), P.SectionRules("objectives", "layout"), {
            help = "Move the tracker in MSUF Edit Mode, or type its size and position here.",
        })
    P.RuleSection(ctx, b, PAGE, "objectives", "suite_hud_objectives_type",
        Tr("Appearance"), AppearanceRules("objectives"), {
            help = "Font, text sizes and background opacity. The tracker colors are in this section's three-dot menu; picking one switches the color source to Custom colors.",
        })
end

-- Clearing the history asks first (MSUF's popup helper is a host export;
-- StaticPopup_Show exists on every client).
local function ConfirmClearHistory(run)
    local M = P.M
    if not M.InstallStaticPopup then return run("ClearHistory") end
    M.InstallStaticPopup("MSUF_SUITE_CLEAR_RUNS_CONFIRM", {
        text = Tr("Erase this character's Mythic+ history? The removed runs cannot be restored."),
        button1 = YES, button2 = NO,
        OnAccept = function(_, data) if type(data) == "function" then data("ClearHistory") end end,
    })
    StaticPopup_Show("MSUF_SUITE_CLEAR_RUNS_CONFIRM", nil, nil, run)
end

local function BuildSummary(ctx, b)
    local function SummaryAction(method, ...)
        local module = S.instances and S.instances.runSummary
        if module and module.active and type(module[method]) == "function" then
            if method == "Preview" and P.Combat() then return end
            local result = module[method](module, ...)
            -- Explicit previews use the real on-screen card. Follow the same
            -- menu-dismissal path as Move in Edit Mode so it is not obscured.
            if method == "Preview" and P.M.frame and P.M.frame.Hide then P.M.frame:Hide() end
            return result
        end
    end
    local summaryActions = {
        { "Move in Edit Mode", function() P.MoveOnScreen("runSummary", "summary") end, key = "edit" },
        { "Preview raid result", function() SummaryAction("Preview", "raid") end, key = "preview_raid" },
        { "Show last result", function() SummaryAction("ShowLast") end, key = "last" },
        { "Summary colors", function() OpenColors("runSummary") end, key = "colors" },
    }
    if S.catalog.runSummary.rules.showMythicPlus then
        table.insert(summaryActions, { "Open run history", function() SummaryAction("ShowHistory") end, key = "history" })
        table.insert(summaryActions, { "Clear run history", function() ConfirmClearHistory(SummaryAction) end,
            key = "clear_history" })
        table.insert(summaryActions, 2,
            { "Preview Mythic+ result", function() SummaryAction("Preview", "mythic") end, key = "preview_mythic" })
    end
    P.ModuleCard(ctx, b, PAGE, "runSummary", summaryActions, { title = "Run Summaries" })
    P.RuleSection(ctx, b, PAGE, "runSummary", "suite_hud_summary_content",
        Tr("Results and details"), P.SectionRules("runSummary", "content"), {
            help = "After a completed Mythic+ run or successful raid encounter, show the public result values in a separate card. Choose which figures appear and how long the card stays open. The last result can be reopened here. Combat delays the card until it is safe to show.",
            open = true,
        })
    local historyRules = P.SectionRules("runSummary", "history")
    if historyRules and #historyRules > 0 then
        P.RuleSection(ctx, b, PAGE, "runSummary", "suite_hud_summary_history",
            Tr("Mythic+ party and history"), historyRules, {
                help = "The party table grows in steps: characters with build and score, then the combat figures of Blizzard's damage meter, then the loot seen in chat. Each character keeps its latest runs; open the newest here or with /msufruns and step through older ones. Deleting a run asks for a second click. The card can wait until you close the chest's loot window.",
            })
    end
    P.RuleSection(ctx, b, PAGE, "runSummary", "suite_hud_summary_layout",
        Tr("Size and position"), P.SectionRules("runSummary", "layout"), {
            help = "Drag the result card in MSUF Edit Mode, or set its screen anchor, width, scale and position here.",
        })
    P.RuleSection(ctx, b, PAGE, "runSummary", "suite_hud_summary_type",
        Tr("Appearance"), AppearanceRules("runSummary"), {
            help = "Set font, text sizes and opacity here. Use the three-dot color menu for the card palette.",
        })
end

local function BuildAnnouncements(ctx, b)
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

local function Build(ctx)
    local b = P.W.PageBuilder(ctx)
    BuildObjectives(ctx, b)
    BuildSummary(ctx, b)
    BuildAnnouncements(ctx, b)
end

P.RegisterPage({ key = PAGE, label = "HUD", title = "HUD", build = Build, icon = { 7, 1 },
    nav = "combat", navOrder = 4,
    aliases = { "objectives", "objective tracker", "run summary", "mythic plus", "raid kill", "announcements", "events", "afk", "hud" } })
