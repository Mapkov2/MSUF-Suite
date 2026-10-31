local _, P = ...
local S = P.S
P.OwnedTools = {
    keyAudit = "Review actions and keys", currencyGoals = "Manage currency goals",
    keywordAlerts = "Edit watched phrases", inventoryArchive = "Open inventory tool",
    restockPlanner = "Open inventory tool", craftShopping = "Open inventory tool", bankTransfer = "Open inventory tool",
}
local QOL_CATEGORY = {
    inventoryProtection = "merchants", mailTemplates = "everydayAutomation", waypointLists = "mapTravel",
    soundProfiles = "everydayAutomation", notificationHistory = "interfaceChat",
}
function P.ExtendQoLTools(groups, categories)
    for _, group in ipairs(P.QoLComfortGroups) do groups[#groups + 1] = group end
    for _, source in ipairs({ P.InventoryToolGroups, P.EverydayToolGroups }) do
        for _, group in ipairs(source) do
            if QOL_CATEGORY[group.id] then groups[#groups + 1] = group end
        end
    end
    for _, category in ipairs(categories) do
        for _, target in ipairs(category.tabs or { category }) do
            for id, owner in pairs(QOL_CATEGORY) do
                if target.id == owner then target.keys[#target.keys + 1] = id .. ".enabled" end
            end
        end
    end
end

function P.BuildNewToolActions(ctx, details, id, section, y, width)
    if id == "macroBuilder" then
        P.Button(ctx, details, "Open macro workshop", 16, y, width,
            function() P.Suite.Menu.Open("suite_macros") end, nil,
            P.Meta("suite_qualityOfLife", id, "action.open", "action", section))
        return y - 38
    end
    y = P.BuildQoLComfortActions(ctx, details, id, section, y, width)
    y = P.BuildInventoryToolActions(ctx, details, id, section, y, width)
    y = P.BuildPlanningToolsActions(ctx, details, id, section, y, width)
    return P.BuildEverydayToolActions(ctx, details, id, section, y, width)
end

local function Prepare(body, widget, page, id, key, kind, label)
    if key == "enabled" then label = P.catalog[id].title end
    local entry = { widget = widget, rule = { key = key, label = label },
        meta = P.Meta(page, id, key, kind, page .. "_" .. id .. "_module") }
    if page == "suite_actionbars" then P.ActionBarMenu.Prepare(body, { entry })
    elseif body._suiteWorkspace then P.MenuWorkspace.Prepare(body, { entry })
    else P.RegisterWorkspaceSearch(widget, entry.meta, entry.rule) end
end

-- Helpers keep their own switch and reset even when the page's styling is off.
function P.BuildOwnedTool(ctx, builder, id)
    if not P.Available(id) then return end
    local spec, rules = P.catalog[id], {}
    for _, rule in ipairs(spec.controls) do
        if rule.key ~= "enabled" and not rule.hidden then rules[#rules + 1] = rule end
    end
    local page, section = spec.page, spec.page .. "_" .. id .. "_module"
    local function Ready() return not P.Combat() and S.instances[id] and S.instances[id].active == true end
    P.ModuleCard(ctx, builder, page, id, {
        { P.OwnedTools[id], function() if Ready() then S.instances[id]:Open() end end, Ready, key = "open" },
    }, { title = spec.title, open = false,
        -- The switch stays the player's choice; a tool without settings has nothing to reset.
        reset = function() return #rules == 0 or P.ResetRules(id, rules) end,
        prepareControl = function(body, widget, key, kind, label) Prepare(body, widget, page, id, key, kind, label) end,
        buildBody = function(body, y, width)
            local bottom, entries = P.RuleGrid(ctx, body, page, id, rules, y, width, nil, section)
            for _, entry in ipairs(entries) do
                entry.meta = P.Meta(page, id, entry.rule.key, "setting", section)
            end
            if page == "suite_actionbars" then P.ActionBarMenu.Prepare(body, entries)
            else P.MenuWorkspace.Prepare(body, entries) end
            return bottom
        end,
    })
end

function P.Suite.Menu.FocusOwnedTool(id)
    local spec = P.catalog[id]
    if not spec or not P.OwnedTools[id] then return true end
    local page, section = spec.page, spec.page .. "_" .. id .. "_module"
    local called, opened, focused = P.M.SearchBridge.OpenSearchTarget(page, "", nil, nil, {},
        { pageKey = page, sectionId = section })
    return called == true and opened == true and focused == true
end

function P.AppendToolSearchActions(Add)
    local legacyWords = {
        characters = { "Characters", P.Tr("Characters"), "Planning & Collections", P.Tr("Planning & Collections") },
        goals = { "Goals", P.Tr("Goals") }, lfg = { "LFG", P.Tr("LFG") },
        loadouts = { "Loadouts", P.Tr("Loadouts") }, notes = { "Notes", P.Tr("Notes") },
        raid = { "Raid night", P.Tr("Raid night") }, runs = { "Runs", P.Tr("Runs") },
    }
    for _, id in ipairs(P.order) do
        local label, spec = P.OwnedTools[id], P.catalog[id]
        if label then Add(id, "action.open", label, spec.page .. "_" .. id .. "_module") end
    end
    for _, section in ipairs(P.PlannerSections) do
        if not section.hidden and (not section.retail or not P.Suite.Client.isForever) then
            local words = { section.title, P.Tr(section.title) }
            for _, word in ipairs(legacyWords[section.key] or {}) do words[#words + 1] = word end
            Add("planningTools", "action.open." .. section.key, "Open Adventure planner",
                "suite_planningTools_" .. section.key, nil, nil, nil, { section = P.Tr(section.title), words = words })
        end
    end
    Add("buffReminders", "action.planner.preparation", "Preparation", "suite_buffReminders_buffReminders_module")
    Add("objectives", "action.planner.raid", "Raid attempts", "suite_hud_objectives_module")
    if not P.Suite.Client.isForever then
        Add("runSummary", "action.planner.runs", "Mythic+ archive", "suite_hud_runSummary_module")
        Add("loadoutReminder", "action.planner.loadouts", "Instance loadouts", "suite_qualityOfLife_loadoutReminder_loadout_reminder")
        Add("groupFinderTools", "action.planner.lfg", "Group finder workspaces", "suite_qualityOfLife_groupFinderTools_group_finder_tools")
    end
    Add("cooldownManager", "action.inspectVisibility", "Check visibility settings", "suite_cooldownManager_visibility")
    Add("chat", "searchHistory", "Search saved chat", "suite_chat_tools")
    Add("inventoryProtection", "action.open", "Open inventory tool", "suite_qualityOfLife_inventoryProtection_inventoryProtection")
    Add("mailTemplates", "action.open", "Open inventory tool", "suite_qualityOfLife_mailTemplates_mailTemplates")
    Add("waypointLists", "action.open", "Open saved waypoint lists", "suite_qualityOfLife_waypointLists_saved_waypoints")
    Add("notificationHistory", "action.open", "Open notice history", "suite_qualityOfLife_notificationHistory_notice_history")
end
