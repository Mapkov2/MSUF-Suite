local root, flavor = assert(arg[1]), arg[2] or "Mainline"
arg[3] = "ownership"
local E = assert(loadfile(root .. "/tools/tests/suite_options_menu_contract.lua"))()
local P, S, M, Suite = E.P, E.S, E.M, E.Suite
local count = 0
local function Check(value, message) assert(value, message) count = count + 1 end
local pages = { keyAudit = "suite_actionbars", currencyGoals = "suite_bags", keywordAlerts = "suite_chat",
    inventoryArchive = "suite_bags", restockPlanner = "suite_bags", craftShopping = "suite_bags",
    bankTransfer = "suite_bags", planningTools = "suite_planningTools" }
Check(M.pages.suite_planningTools ~= nil, "planner has no independent page")
for id, page in pairs(pages) do Check(P.catalog[id].page == page, "wrong owner: " .. id) end
local remaining = { inventoryProtection = "lootMerchants", mailTemplates = "everydayAutomation",
    waypointLists = "mapTravel", soundProfiles = "everydayAutomation", notificationHistory = "interfaceChat" }
for _, category in ipairs(P.QualityOfLifeCategories) do
    Check(category.id ~= "planningCollections", "catchall category remains")
end
for _, feature in ipairs(P.QualityOfLifeSearchFeatures) do
    Check(not pages[feature.id], "moved tool still lives in QoL: " .. feature.id)
    if remaining[feature.id] then Check(feature.category == remaining[feature.id], "wrong QoL category") end
end
for id, page in pairs(pages) do
    local target = { pageKey = "suite_qualityOfLife", settingKey = "msufsuite." .. id .. ".enabled",
        sectionId = "suite_qualityOfLife_" .. id .. "_old", controlId = "old" }
    local nextPage, nextTarget = P.ResolveToolSearchTarget(target.pageKey, target)
    Check(nextPage == page and nextTarget.settingKey == target.settingKey, "legacy setting did not move: " .. id)
    Check(nextTarget ~= target and target.controlId == "old" and target.pageKey == "suite_qualityOfLife", "saved target was mutated")
    local key = id == "planningTools" and "action.openPlanner" or "action.open"
    local control = P.Meta("suite_qualityOfLife", id, key, "action").controlId
    local actionPage, actionTarget = P.ResolveToolSearchTarget("suite_qualityOfLife", { controlId = control })
    Check(actionPage == page and actionTarget.controlId ~= control, "legacy action did not move: " .. id)
end
Check(P.ResolveToolSearchTarget("suite_qualityOfLife", { settingKey = "msufsuite.unknown.enabled" }) == nil,
    "unknown settings must not be redirected")
M.RegisterSearchProvider = function() return true end
assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Search.lua"))("MSUF_Suite_Options", P)
local cold = P.SearchRows()
local function FindControl(ctx, id, key)
    local setting = "msufsuite." .. id .. "." .. key
    for _, widget in ipairs(ctx.widgets) do
        local meta = rawget(widget, "registeredMeta") or rawget(widget, "meta")
        if meta and meta.settingKey == setting then return widget, meta end
    end
end
local contexts = {}
for _, page in ipairs({ "suite_bags", "suite_actionbars", "suite_chat", "suite_planningTools" }) do
    contexts[page] = E.build(page)
end
-- Planner settings share the normal page scroll; no second navigation layer.
local plannerContext = contexts.suite_planningTools
Check(plannerContext.suiteWorkspace == nil, "planner settings still require choosing a topic tab")
Check(plannerContext.fixedPreview == nil, "planner settings reserve an empty navigation header")
local plannerSections = {}
for _, section in ipairs(plannerContext.sections) do
    plannerSections[section.sectionId] = section
    Check(section.finished, "planner section does not contribute to page scroll height")
    Check(section:IsVisible(), "planner section is hidden behind another topic")
end
local expectedSections = 1
for _, spec in ipairs(P.PlannerSections) do
    local available = not spec.hidden and not (spec.retail and flavor == "Forever")
    local section = plannerSections["suite_planningTools_" .. spec.key]
    Check((section ~= nil) == available, "planner client visibility changed: " .. spec.key)
    if available then expectedSections = expectedSections + 1 end
end
Check(#plannerContext.sections == expectedSections, "planner has extra navigation sections")
local launcherId = P.Meta("suite_planningTools", "planningTools", "action.openPlanner", "action").controlId
Check(E.widgets[launcherId] ~= nil, "planner has no direct launch button in its first card")
for _, spec in ipairs(P.PlannerSections) do
    if not spec.hidden and not (spec.retail and flavor == "Forever") then
        for _, key in ipairs(spec.keys) do
            local widget, meta = FindControl(plannerContext, "planningTools", key)
            Check(meta.searchPrepareKind == "suiteWorkspace" and meta.searchPrepareValue == key,
                "saved planner search contract lost: " .. key)
            Check(meta.prepareExactSearchTarget(widget) == true,
                "saved planner search target cannot prepare: " .. key)
        end
    end
end
for id, page in pairs(pages) do
    if P.Available(id) then
        local widget, meta = FindControl(contexts[page], id, "enabled")
        Check(widget and meta.sectionId == page .. "_" .. id .. "_module", "helper switch missing: " .. id)
        local row
        for _, entry in ipairs(cold) do if entry.settingKey == "msufsuite." .. id .. ".enabled" then row = entry break end end
        Check(row and row.pageKey == page and row.sectionId == meta.sectionId, "cold helper route mismatch: " .. id)
        if id ~= "planningTools" then
            Check(widget.registeredLabel == P.catalog[id].title, "warm helper enable lost semantic label: " .. id)
        end
    end
end
for _, row in ipairs(cold) do
    local id = row.suiteModuleId
    if pages[id] and row.settingKey and row.suiteRuleKey then
        local _, meta = FindControl(contexts[pages[id]], id, row.suiteRuleKey)
        Check(meta and row.controlId == meta.controlId, "cold search identity differs from actual control: " .. row.settingKey)
    end
end
if flavor == "Mainline" then
    local qol = E.build("suite_qualityOfLife")
    local row = assert(qol.qualityOfLifeFeatureRows.suite_qualityOfLife_mailTemplates_mailTemplates)
    E.inContext(qol, function() row.reveal(true) end)
    local found
    local control = P.Meta("suite_qualityOfLife", "mailTemplates", "action.open", "action").controlId
    for _, widget in ipairs(qol.widgets) do
        if widget.meta and widget.meta.controlId == control then found = widget break end
    end
    Check(found ~= nil or E.widgets[control] ~= nil, "mail template editor has no action without visible rules")
end
local _, keyMeta = FindControl(contexts.suite_actionbars, "keyAudit", "onlyIssues")
Check(keyMeta and keyMeta.sectionId == "suite_actionbars_keyAudit_module", "workspace rewrote the helper setting owner")
for id, label in pairs(P.OwnedTools) do
    if P.Available(id) then
        local wanted = P.Meta(pages[id], id, "action.open", "action").controlId
        local found
        for _, row in ipairs(cold) do if row.controlId == wanted then found = row break end end
        Check(found and found.pageKey == pages[id], "cold search lost helper action: " .. id)
    end
end
local archives = { sentinel = true }
Suite.RootDB.menuOwnershipFixture = archives
S.Set("keyAudit", "onlyIssues", true)
S.Set("currencyGoals", "capPercent", 75)
S.Set("keywordAlerts", "cooldown", 125)
S.Set("planningTools", "weekly", false)
S.Set("notificationHistory", "limit", 80)
Check(M.ResetPageToDefaults("suite_qualityOfLife"), "QoL reset failed")
Check(S.Config("keyAudit").onlyIssues and S.Config("currencyGoals").capPercent == 75
    and S.Config("keywordAlerts").cooldown == 125 and S.Config("planningTools").weekly == false,
    "QoL reset crossed menu ownership")
Check(S.Config("notificationHistory").limit == P.catalog.notificationHistory.rules.limit.default, "QoL missed its own tool")
Check(M.ResetPageToDefaults("suite_bags"), "Bags reset failed")
Check(S.Config("currencyGoals").capPercent == P.catalog.currencyGoals.rules.capPercent.default
    and S.Config("keyAudit").onlyIssues and S.Config("keywordAlerts").cooldown == 125, "Bags reset crossed ownership")
Check(Suite.RootDB.menuOwnershipFixture == archives and archives.sentinel, "menu reset removed stored data")
local opened
S.PlanningTools = { Active = function() return true end, Window = { Open = function(tab) opened = tab return true end } }
P.PlannerAction("preparation")[2]()
Check(opened == "preparation", "preparation link did not open exact tab")
P.PlannerAction("raid")[2]()
Check(opened == "raid", "raid link did not open exact tab")
local skin = C_AddOns.GetAddOnEnableState
C_AddOns.GetAddOnEnableState = function(name, ...) if name == "MSUF_Suite_Bags" then return 0 end return skin(name, ...) end
P.ForgetAvailability()
local ctx = E.build("suite_bags")
Check(FindControl(ctx, "inventoryArchive", "enabled") ~= nil, "bag styling disabled the independent archive")
C_AddOns.GetAddOnEnableState = skin
P.ForgetAvailability()
local warm = P.SearchRows()
local function Routes(rows)
    local result = {}
    for _, row in ipairs(rows) do if row.settingKey and row.suiteModuleId and pages[row.suiteModuleId] then
        result[row.settingKey] = row.pageKey .. ":" .. row.sectionId
    end end
    return result
end
local a, b = Routes(cold), Routes(warm)
for key, route in pairs(a) do Check(b[key] == route, "visiting page changed search ownership: " .. key) end
print("Suite menu ownership: " .. count .. " checks passed (" .. flavor .. ")")
