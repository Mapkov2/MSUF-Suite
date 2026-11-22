local _, P = ...
local S, PAGE, ID = P.S, "suite_hud", "planningTools"
-- One settings section per supported area of the planner window.
-- A tab hidden there is hidden here too: its button could only open the
-- Weekly overview.
P.PlannerSections = {
    { key = "characters", title = "Weekly overview", keys = { "weekly" } },
    { key = "preparation", title = "Preparation", keys = { "preparation" } },
    { key = "loot", title = "Loot goals", keys = {} },
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
function P.PlannerSectionID(tab)
    return PAGE .. "_" .. ID .. "_" .. tab
end
function P.PlanningRuleTarget(key)
    for _, section in ipairs(P.PlannerSections) do
        for _, ruleKey in ipairs(section.keys) do
            if ruleKey == key then return P.PlannerSectionID(section.key) end
        end
    end
    return P.PlannerSectionID("module")
end
local function Ready()
    local planner = S.PlanningTools
    return not P.Combat() and planner and planner.Active()
end
function P.OpenPlanner(tab)
    if P.Combat() or not TabSupported(tab) then return false end
    if Ready() then return S.PlanningTools.Window.Open(tab) end
    return P.Suite.Menu.Open(PAGE, ID)
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
local function BuildPlannerSection(ctx, builder, spec)
    if not TabSupported(spec.key) then return end
    local rules = {}
    for _, key in ipairs(spec.keys) do rules[#rules + 1] = P.catalog[ID].rules[key] end
    local section = P.PlannerSectionID(spec.key)
    P.RuleSection(ctx, builder, PAGE, ID, section, P.Tr(spec.title), rules, {
        open = true, onBuilt = P.HUDMenu.Prepare,
        extra = function(body, y, width)
            local label, key = "Open Adventure planner", "action.open." .. spec.key
            local meta = P.Meta(PAGE, ID, key, "action", section)
            local button = P.Button(ctx, body, label, 16, y, width,
                function() if Ready() then S.PlanningTools.Window.Open(spec.key) end end, Ready, meta)
            P.HUDMenu.Prepare(body, { { widget = button, rule = { key = key, label = label }, meta = meta } })
            return y - 38
        end,
    })
end
function P.BuildHUDPlanner(ctx, builder)
    P.ModuleCard(ctx, builder, PAGE, ID, {
        { "Open Adventure planner", function() P.OpenPlanner("characters") end, Ready, key = "openPlanner" },
    }, { title = "Adventure planner", open = true, prepareControl = P.HUDMenu.PrepareControl })
    for _, section in ipairs(P.PlannerSections) do BuildPlannerSection(ctx, builder, section) end
end
