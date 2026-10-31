local _, NS = ...
local Model = NS.Macros.Model
local Templates = {}
NS.Macros.Templates = Templates

local function Add(id, label, steps)
    Templates[#Templates + 1] = { id = id, label = label, document = {
        version = 1, name = "", scope = "character", icon = 134400, mode = "rules", raw = "",
        showTooltip = true, steps = steps,
    } }
end

local function Condition(key, value, negate)
    return { key = key, value = value or "", negate = negate == true }
end

local function Rule(conditions, useFirst)
    return { value = "", conditions = conditions or {}, useFirst = useFirst == true }
end

Add("spell", "Cast a spell", { Model.NewStep("cast") })
Add("focus", "Focus interrupt", { { command = "cast", branches = {
    Rule({ Condition("unit", "focus"), Condition("harm"), Condition("dead", "", true) }),
    Rule({ Condition("harm"), Condition("dead", "", true) }, true),
} } })
Add("help-harm", "Heal or attack", { { command = "cast", branches = {
    Rule({ Condition("mod", "alt"), Condition("unit", "player") }),
    Rule({ Condition("help"), Condition("dead", "", true) }, true),
    Rule({ Condition("harm"), Condition("dead", "", true) }),
} } })
Add("mouseover", "Mouseover healing", { { command = "cast", branches = {
    Rule({ Condition("unit", "mouseover"), Condition("help"), Condition("dead", "", true) }),
    Rule({ Condition("help"), Condition("dead", "", true) }, true),
    Rule({ Condition("unit", "player") }, true),
} } })
Add("mouseover-harm", "Mouseover attack", { { command = "cast", branches = {
    Rule({ Condition("unit", "mouseover"), Condition("harm"), Condition("dead", "", true) }),
    Rule({ Condition("harm"), Condition("dead", "", true) }, true),
} } })
do
    local steps = Model.New("mouseover").steps
    steps[1].raidMarker = 8
    Add("mouseover-mark", "Mouseover heal and mark", steps)
end
Add("cursor", "Cast at cursor", { { command = "cast", branches = { Rule({ Condition("unit", "cursor") }) } } })
Add("modifiers", "Modifier choices", { { command = "cast", branches = {
    Rule({ Condition("mod", "shift") }), Rule({ Condition("mod", "ctrl") }), Rule({}),
} } })
Add("self", "Cast on yourself", { { command = "cast", branches = { Rule({ Condition("unit", "player") }) } } })
Add("pet", "Pet attack and spell", { Model.NewStep("petattack"), Model.NewStep("cast") })
Add("weapons", "Switch weapons", { Model.NewStep("equipslot"), Model.NewStep("equipslot") })
Add("sequence", "Spell or item sequence", { { command = "castsequence", branches = { Rule({}) },
    sequence = {}, reset = { target = true, combat = true } } })

for _, entry in ipairs({ { "health", "Health supplies" }, { "drink", "Food and drink" },
    { "food", "Buff food" }, { "flask", "Flasks" }, { "bandage", "Bandages" } }) do
    Templates[#Templates + 1] = { id = entry[1], label = entry[2], document = {
        version = 1, name = "", scope = "character", icon = 134400, mode = "consumable", raw = "",
        showTooltip = true, steps = {}, consumable = { kind = entry[1], managed = true,
            preferConjured = true, includeFood = true, combatMana = false, stopCasting = false,
            priorities = { "stone", "potion", "spell" }, spells = {}, items = {}, reset = { combat = true } },
    } }
end
