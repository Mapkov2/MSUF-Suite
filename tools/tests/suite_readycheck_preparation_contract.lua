local root = assert(arg[1], "repository root required")
local function Load(path, private)
    return assert(loadfile(root .. "/" .. path))("MSUF_Suite", private)
end

local secret = setmetatable({}, {
    __lt = function() error("secret comparison") end,
    __mul = function() error("secret arithmetic") end,
})
local combat, durability, loadout, reads = false, nil, nil, 0
local entries = {
    { kind = "spell", id = 1, present = false },
    { kind = "spell", id = 2, group = true, present = false, own = { present = true } },
    { kind = "spell", id = 3, present = nil },
    { kind = "spell", id = 4, present = false, dismissed = true },
    { kind = "item", id = 5, restock = true },
    { kind = "item", id = 6, present = false },
}
local owner = { active = true, list = { entries = entries }, listen = {} }
C_Spell = { GetSpellName = function(id) return "Spell " .. id end }
C_Item = { GetItemInfo = function(id) return id == 5 and "Food stock" or secret end }
local S = {
    Text = function(key) return key end,
    Finite = function(value) return type(value) == "number" end,
    PublicText = function(value) return type(value) == "string" and value or nil end,
    instances = { buffReminders = owner },
    PlanningLoadoutIssues = function() return loadout end,
    ReadInfoSource = function(key)
        assert(key == "durability")
        reads = reads + 1
        return durability
    end,
}
Load("MSUF_Suite_Modules/PreparationStatus.lua", { Suite = S, NS = { InCombat = function() return combat end } })
local detail, route = S.ReadyCheckPreparation()
assert(detail == "Missing Spell 1\nRestock Food stock" and route == "buffs", "personal issues were not filtered or named")
owner.list.needsFullRefresh, durability = true, secret
assert(S.ReadyCheckPreparation() == nil, "dirty or restricted data reported as a preparation issue")
durability = .2
detail, route = S.ReadyCheckPreparation()
assert(detail == "Low durability (20%)" and route == "gear", "durability did not use the shared reader")
loadout = { "Talent loadout: A -> B", "Loot specialization: A -> B" }
detail, route = S.ReadyCheckPreparation()
assert(detail:find(loadout[1], 1, true) == 1 and route == "loadouts", "loadout issues did not route to the planner")
local before = reads
combat = true
assert(S.ReadyCheckPreparation() == nil and reads == before, "combat ready check queried live data")
print("Ready-check preparation contract passed")
