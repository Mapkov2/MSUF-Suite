local root = assert(arg[1])
local NS = { IsSecret = function() return false end, Finite = function(value) return type(value) == "number" end,
    Text = function(value) return value end, Client = { isForever = false }, NameplateStyle = { Roles = {} },
    AnchorPoints = {}, AnchorLabels = {} }
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateExtensions.lua"))("Core", NS)
local spec = { rules = {}, controls = { { key = "enabled" } }, look = { visualKeys = {}, presets = { {}, {}, {}, {} } } }
NS.SuiteCatalog = { nameplates = spec }
local B = {}
local function Rule(key, label, default) return { key = key, label = label, default = default } end
B.Bool, B.Number, B.Choice, B.Color = Rule, Rule, Rule, Rule
B.Texture = function(key, label) return Rule(key, label, "") end
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
    local unitAccordion = rule.section == "castExtensions" and not key:match("^interruptFeedback")
    if not unitAccordion and rule.section ~= "plateDimensions" and rule.section ~= "plateContext" and rule.section ~= "plateOpacity"
        and rule.section ~= "plateInteraction" and rule.section ~= "plateExtraText" and rule.section ~= "barGradients" then
        assert(placed[key], "unplaced extension rule " .. key)
    end
    if rule.section == "barGradients" then
        local override = key == "barsOverride" or key == "barsOverrideSaved"
        assert(not spec.look.visualKeys[key] == override, "bar appearance and its source switch have different owners")
        local value = override or rule.default
        assert(spec.look.presets[1][key] == value and spec.look.presets[4][key] == value,
            "skin presets did not restore their own bar setting " .. key)
        assert(spec.look.presets[2][key] == nil, "Blizzard look changed the saved bar settings")
    elseif rule.section == "enemyLoadConditions" or rule.section == "plateOpacity" then
        assert(not spec.look.visualKeys[key], "a separate setting depends on the appearance preset")
    else
        assert(spec.look.visualKeys[key], "missing look reset for " .. key)
        for _, preset in ipairs(spec.look.presets) do assert(preset[key] == rule.default, "preset retains old extension " .. key) end
    end
end
assert(help.castFeedback.details:find("no enemy school%-lockout duration"), "interrupt feedback must explain missing lockout data")
assert(help.plateRange.details:find("current target", 1, true), "spell range must explain the target-only scope")
assert(help.threatDetail.summary:find("Focus > safe tank threat"), "color priority is visible")
assert(not spec.rules.targetClassResources)
look = 2
assert(P.Gates.nameplates(spec.rules.enemyRangeEnabled, "enemyRangeEnabled") == false)
look = 3
assert(P.Gates.nameplates(spec.rules.enemyRangeEnabled, "enemyRangeEnabled") == true)
assert(legacyGates == 1, "existing nameplate gate remains intact")
do
    local value, commit, click, reads = 0, nil, nil, 0
    local choices = {}
    P.Suite.Public = function() return true end
    P.Get = function() return value end
    P.Set = function(_, _, id) value = id end
    P.Combat = function() return false end
    P.Meta, P.GateControls, P.StyleMenuControl = function() end, function() end, function() end
    P.Text = function() return { SetText = function() end } end
    P.M = { BindTextInputAt = function(_, _, _, _, _, _, _, set) commit = set return {} end,
        TrackRefresh = function() end }
    P.Button = function(_, _, _, _, _, _, callback) click = callback return {} end
    P.ContextMenu = function(owner, build)
        build(owner, { CreateButton = function() end, CreateRadio = function(_, label, _, pick) choices[label] = pick end })
    end
    Enum = { SpellBookSpellBank = { Player = 0 } }
    C_SpellBook = {
        GetNumSpellBookSkillLines = function() reads = reads + 1 return 1 end,
        GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 3 } end,
        GetSpellBookItemInfo = function(index) return { spellID = index } end,
        IsSpellKnown = function(id) return id ~= 3 end,
    }
    C_Spell = { SpellHasRange = function(id) return id ~= 2 end, GetSpellName = function() return "Test spell" end }
    P.NameplatesExtensions.RangeSpell({}, {}, 0, 560, "range", { key = "enemyRangeSpell", label = "Spell ID", max = 10000000 })
    assert(reads == 0, "opening Range Check eagerly scanned the spellbook")
    commit("123")
    assert(value == 123, "manual spell ID was not saved")
    click()
    assert(reads == 1 and choices["Test spell (1)"] and not choices["Test spell (2)"] and not choices["Test spell (3)"],
        "picker exposed an unknown or non-range spell")
    choices["Test spell (1)"]()
    assert(value == 1, "spellbook choice was not saved")
end
print("nameplate extensions UI contract passed: all controls placed, default resets, capabilities and priority explanation")
