local root = assert(arg[1])
local NS = { IsSecret = function() return false end, Finite = function(value) return type(value) == "number" end,
    Text = function(value) return value end, Client = { isForever = false }, NameplateStyle = { Roles = {} } }
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateExtensions.lua"))("Core", NS)
local spec = { rules = {}, controls = { { key = "enabled" } }, look = { visualKeys = {}, presets = { {}, {}, {}, {} } } }
NS.SuiteCatalog = { nameplates = spec }
local B = {}
local function Rule(key, label, default) return { key = key, label = label, default = default } end
B.Bool, B.Number, B.Choice, B.Color = Rule, Rule, Rule, Rule
function B.Section(_, section, title, rules)
    for _, rule in ipairs(rules) do
        assert(not spec.rules[rule.key], "duplicate rule " .. rule.key)
        rule.section, rule.sectionTitle = section, title
        spec.rules[rule.key] = rule
        spec.controls[#spec.controls + 1] = rule
    end
end
NS.CatalogBuild = { ForAddon = function() return B end }
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/NameplateExtensions.lua"))("Core", NS)
local look, legacyGates = 3, 0
local P = {
    Suite = NS, Tr = function(value) return value end,
    Help = function(summary, details) return { summary = summary, details = details } end,
    Get = function() return look end,
    Gates = { nameplates = function() legacyGates = legacyGates + 1 return true end },
}
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesExtensions.lua"))("Options", P)
local sections, help = {}, {}
P.NameplatesExtensions.Append(sections, help)
local placed = {}
local function Place(keys)
    for _, key in ipairs(keys or {}) do assert(not placed[key], "duplicate placement " .. key) placed[key] = true end
end
for _, section in ipairs(sections) do
    assert(section.area and section.title)
    Place(section.keys)
    Place(section.colors)
    for _, tab in ipairs(section.tabs or {}) do Place(tab.keys) if tab.help then assert(help[tab.help]) end end
end
for key, rule in pairs(spec.rules) do
    assert(placed[key], "unplaced extension rule " .. key)
    assert(spec.look.visualKeys[key], "missing look reset for " .. key)
    for _, preset in ipairs(spec.look.presets) do assert(preset[key] == rule.default, "preset retains old extension " .. key) end
end
assert(help.castFeedback.details:find("no enemy school%-lockout duration"), "interrupt feedback must explain missing lockout data")
assert(help.plateRange.details:find("no per%-unit spell line%-of%-sight"), "range must explain absent LOS API")
assert(help.threatDetail.summary:find("Focus > safe tank threat"), "color priority is visible")
local resourceRule = spec.rules.targetClassResources
assert(P.Gates.nameplates(resourceRule, resourceRule.key) == true)
NS.Client.isForever = true
local enabled, reason = P.Gates.nameplates(resourceRule, resourceRule.key)
assert(enabled == false and reason:find("Forever"), "Forever resource control explains native capability")
NS.Client.isForever, look = false, 2
assert(P.Gates.nameplates(resourceRule, resourceRule.key) == false, "native look cannot silently accept skin-only controls")
assert(legacyGates == 1, "existing nameplate gate remains intact")
print("nameplate extensions UI contract passed: all controls placed, default resets, capabilities and priority explanation")
