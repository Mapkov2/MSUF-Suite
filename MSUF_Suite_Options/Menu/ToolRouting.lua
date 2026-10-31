local _, P = ...
local LEGACY_PAGE = "suite_qualityOfLife"
local actions, settings
local function RememberLegacyAction(id, oldKey, key, section)
    local page = P.catalog[id].page
    local old = P.Meta(LEGACY_PAGE, id, oldKey, "action").controlId
    if old then actions[old] = { page = page, id = id, key = key, section = section } end
end
local function EnsureLegacyTargets()
    if actions then return end
    actions, settings = {}, {}
    for id in pairs(P.OwnedTools) do
        settings[id] = true
        RememberLegacyAction(id, "action.open", "action.open", P.catalog[id].page .. "_" .. id .. "_module")
    end
    settings.planningTools, settings.macroBuilder = true, true
    RememberLegacyAction("macroBuilder", "action.open", "action.open", nil)
    RememberLegacyAction("planningTools", "action.openPlanner", "action.open.characters", "suite_planningTools_characters")
end

local function RelocatedTarget(target, page, control, section)
    local copy = {}
    for key, value in pairs(target) do copy[key] = value end
    copy.pageKey, copy.controlId, copy.sectionId = page, control, section
    copy.prepareKind, copy.prepareValue = nil, nil
    return copy
end

-- Saved search targets are immutable records. Only the opening target is relocated.
function P.ResolveToolSearchTarget(page, target)
    if not target then return end
    if page == "suite_macros" then
        local tab = target.prepareKind == "suiteMacroTab" and target.prepareValue
        if not tab and target.sectionId == "suite_macros_macroBuilder_module" then
            tab = target.settingKey == "msufsuite.macroBuilder.enabled" and "consumable" or "rules"
        end
        if tab then
            P.MacroPage.PrepareSearch(tab)
            return page, RelocatedTarget(target, page, target.controlId, nil)
        end
    end
    if target.prepareKind == "suiteCDMBar" then return P.ResolveCDMInspectionTarget(page, target) end
    if page ~= LEGACY_PAGE then return end
    EnsureLegacyTargets()
    local action = actions[target.controlId]
    if action then
        if action.id == "macroBuilder" then P.MacroPage.PrepareSearch("rules") end
        local meta = P.Meta(action.page, action.id, action.key, "action", action.section)
        local control = action.id ~= "macroBuilder" and meta.controlId or nil
        return action.page, RelocatedTarget(target, action.page, control, action.section)
    end
    local id, key = (target.settingKey or ""):match("^msufsuite%.([^.]+)%.(.+)$")
    local spec = id and settings[id] and P.catalog[id]
    if spec and spec.rules[key] then
        local section = id == "planningTools" and P.PlanningRuleTarget(key) or spec.page .. "_" .. id .. "_module"
        if id == "macroBuilder" then
            section = nil
            P.MacroPage.PrepareSearch("consumable")
        end
        local meta = P.Meta(spec.page, id, key, "setting", section)
        return spec.page, RelocatedTarget(target, spec.page, meta.controlId, section)
    end
    for owner in pairs(settings) do
        if target.sectionId and target.sectionId:find("^suite_qualityOfLife_" .. owner .. "_") then
            local ownerPage = P.catalog[owner].page
            local section = ownerPage .. "_" .. owner .. "_module"
            if owner == "macroBuilder" then section = nil P.MacroPage.PrepareSearch("rules") end
            return ownerPage, RelocatedTarget(target, ownerPage, nil, section)
        end
    end
end
P.Suite.HostBridge.RegisterSearchTargetResolver(P.M, "MSUF_Suite.Tools", P.ResolveToolSearchTarget)
