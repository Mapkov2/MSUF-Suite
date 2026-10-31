local _, P = ...
local S, PAGE, ID = P.S, "suite_planningTools", "planningTools"
-- One settings section per supported area of the planner window.
-- A tab hidden there is hidden here too: its button could only open the
-- Weekly overview.
P.PlannerSections = {
    { key = "characters", title = "Weekly overview", keys = { "weekly" } },
    { key = "preparation", title = "Preparation", keys = { "preparation" } },
    { key = "loadouts", title = "Instance loadouts", keys = { "loadouts" }, retail = true },
    { key = "runs", title = "Mythic+ archive", keys = {}, retail = true },
    { key = "raid", title = "Raid archive", keys = { "raidHistory", "keepAttempts" } },
    { key = "goals", title = "Mythic+ goals", keys = {}, retail = true, hidden = true },
    { key = "lfg", title = "Group finder workspaces", keys = {}, retail = true },
    { key = "notes", title = "Instance notes and checklists", keys = { "entryNotes" } },
}
local function TabSupported(tab)
    for _, section in ipairs(P.PlannerSections) do
        if section.key == tab then
            return not section.hidden and (not section.retail or not P.Suite.Client.isForever)
        end
    end
    return false
end
function P.PlanningRuleTarget(key)
    for _, section in ipairs(P.PlannerSections) do
        for _, ruleKey in ipairs(section.keys) do
            if ruleKey == key then return PAGE .. "_" .. section.key end
        end
    end
    return PAGE .. "_planningTools_module"
end
local function Ready()
    local planner = S.PlanningTools
    return not P.Combat() and planner and planner.Active()
end
function P.OpenPlanner(tab)
    if P.Combat() or not TabSupported(tab) then return false end
    if Ready() then return S.PlanningTools.Window.Open(tab) end
    if not P.Suite.Menu.Open(PAGE) then return false end
    local called, opened = P.M.SearchBridge.OpenSearchTarget(PAGE, "", nil, nil, {},
        { pageKey = PAGE, sectionId = PAGE .. "_planningTools_module" })
    return called == true and opened == true
end
function P.PlannerAction(tab, key)
    local title = "Open Adventure planner"
    for _, section in ipairs(P.PlannerSections) do if section.key == tab then title = section.title break end end
    return { title, function() P.OpenPlanner(tab) end,
        function() return not P.Combat() and TabSupported(tab) end, key = key or "planner." .. tab }
end
function P.PlannerButton(ctx, body, page, owner, section, tab, y, width)
    if not TabSupported(tab) then return y end
    local action = P.PlannerAction(tab)
    P.Button(ctx, body, action[1], 16, y, width, action[2], action[3],
        P.Meta(page, owner, "action.planner." .. tab, "action", section))
    return y - 38
end
function P.BuildPlanningToolsActions(ctx, body, id, section, y, width)
    local tab = id == "loadoutReminder" and "loadouts" or id == "groupFinderTools" and "lfg"
    if tab then return P.PlannerButton(ctx, body, P.catalog[id].page, id, section, tab, y, width) end
    return y
end
-- Saved exact-search links retain the former workspace preparation contract.
local function SearchReady() return true end
local function PreparePlannerSearch(_, entries)
    for _, entry in ipairs(entries or {}) do
        if entry.widget then
            local meta = P.Meta(PAGE, ID, entry.rule.key, "setting", P.PlanningRuleTarget(entry.rule.key))
            P.RegisterWorkspaceSearch(entry.widget, meta, entry.rule, "suiteWorkspace", SearchReady, entry.label)
        end
    end
end
local function BuildPlannerSection(ctx, builder, spec)
    if not TabSupported(spec.key) then return end
    local rules = {}
    for _, key in ipairs(spec.keys) do rules[#rules + 1] = P.catalog[ID].rules[key] end
    local section = PAGE .. "_" .. spec.key
    P.RuleSection(ctx, builder, PAGE, ID, section, P.Tr(spec.title), rules, {
        open = true, onBuilt = PreparePlannerSearch,
        extra = function(body, y, width)
            P.Button(ctx, body, "Open Adventure planner", 16, y, width,
                function() if Ready() then S.PlanningTools.Window.Open(spec.key) end end, Ready,
                P.Meta(PAGE, ID, "action.open." .. spec.key, "action", section))
            return y - 38
        end,
    })
end
local function Build(ctx)
    local builder = P.W.PageBuilder(ctx)
    P.ModuleCard(ctx, builder, PAGE, ID, {
        { "Open Adventure planner", function() P.OpenPlanner("characters") end, Ready, key = "openPlanner" },
    }, { title = "Adventure planner", open = true })
    for _, section in ipairs(P.PlannerSections) do BuildPlannerSection(ctx, builder, section) end
end
P.RegisterPage({ key = PAGE, label = "Adventure planner", title = "Adventure planner", build = Build,
    icon = { 7, 1 }, nav = "general", navOrder = 3,
    aliases = { "planner", "adventure", "weekly", "preparation", "loadouts", "runs", "raid", "goals", "lfg", "notes" } })
