local root = assert(arg[1]):gsub("\\", "/")
local prepared
local P = {
    M = {}, OwnedTools = {},
    catalog = {
        macroBuilder = { page = "suite_macros", rules = { enabled = {} } },
        planningTools = { page = "suite_planningTools", rules = { enabled = {} } },
    },
    MacroPage = { PrepareSearch = function(tab) prepared = tab end },
    Meta = function(page, id, key)
        return { controlId = page .. ":" .. id .. ":" .. key }
    end,
    PlanningRuleTarget = function() return "suite_planningTools_general" end,
    Suite = { HostBridge = { RegisterSearchTargetResolver = function() end } },
}
assert(loadfile(root .. "/MSUF_Suite_Options/Menu/ToolRouting.lua"))("MSUF_Suite_Options", P)
local function Check(target, expected, control)
    prepared = nil
    local page, copy = P.ResolveToolSearchTarget("suite_macros", target)
    assert(page == "suite_macros" and copy ~= target)
    assert(prepared == expected and copy.sectionId == nil)
    assert(copy.prepareKind == nil and copy.prepareValue == nil)
    assert(copy.controlId == control)
end
local target = { prepareKind = "suiteMacroTab", prepareValue = "consumable", controlId = "tab" }
Check(target, "consumable", "tab")
assert(target.prepareKind == "suiteMacroTab" and target.prepareValue == "consumable")
Check({ sectionId = "suite_macros_macroBuilder_module" }, "rules")
Check({ sectionId = "suite_macros_macroBuilder_module", settingKey = "msufsuite.macroBuilder.enabled" }, "consumable")
local legacy = { settingKey = "msufsuite.macroBuilder.enabled", sectionId = "suite_qualityOfLife_macroBuilder_module" }
local page, copy = P.ResolveToolSearchTarget("suite_qualityOfLife", legacy)
assert(page == "suite_macros" and copy.sectionId == nil and prepared == "consumable")
assert(copy.controlId == "suite_macros:macroBuilder:enabled")
assert(legacy.sectionId == "suite_qualityOfLife_macroBuilder_module")
page, copy = P.ResolveToolSearchTarget("suite_qualityOfLife", {
    controlId = "suite_qualityOfLife:macroBuilder:action.open",
})
assert(page == "suite_macros" and copy.controlId == nil and copy.sectionId == nil and prepared == "rules")
page, copy = P.ResolveToolSearchTarget("suite_qualityOfLife", { settingKey = "msufsuite.planningTools.enabled" })
assert(page == "suite_planningTools" and copy.sectionId == "suite_planningTools_general")
prepared = nil
assert(P.ResolveToolSearchTarget("suite_bags", { controlId = "unrelated" }) == nil and prepared == nil)
print("macro search routing: direct tabs, legacy targets and immutable records passed")
