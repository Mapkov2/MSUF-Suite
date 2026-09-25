local _, P = ...
local S, Tr = P.S, P.Tr
local PAGE = "suite_hud"

local function AppearanceRules(id)
    local rules = P.SectionRules(id, "type")
    local colorSections = id == "objectives"
        and { "colors", "detailColors", "questColors", "activityColors", "extraColors" }
        or { "colors", "eventColors", "moreEventColors" }
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
            help = "A Suite-owned tracker with grouped quests, world quests, scenario steps and tracked achievements. The raid combat option hides this tracker and suspends its updates until combat ends. Click a group heading or the small button on an entry to collapse it. Quest titles open their quest log page; right-click opens its actions. The Blizzard tracker is hidden while this module is active.",
            open = true,
        })
    P.RuleSection(ctx, b, PAGE, "objectives", "suite_hud_objectives_layout",
        Tr("Size and position"), P.SectionRules("objectives", "layout"), {
            help = "Drag the tracker in MSUF Edit Mode, or enter exact size and position here.",
        })
    P.RuleSection(ctx, b, PAGE, "objectives", "suite_hud_objectives_type",
        Tr("Appearance"), AppearanceRules("objectives"), {
            help = "Set font, text sizes and opacity here. Open the three-dot color menu in this section for tracker colors; choosing one switches to Custom colors automatically.",
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
    aliases = { "objectives", "objective tracker", "announcements", "events", "afk", "hud" } })
