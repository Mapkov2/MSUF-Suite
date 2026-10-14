local root = assert((...), "Suite root required")
local events, queue, actions, ranks, names = {}, {}, {}, {}, {}
local combat, held, picked, wrong, raises = false, nil, nil, false, false
local calls, scans, reports = 0, 0, 0
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 }, ActionBarSet = { All = 3 } }
function wipe(t) for k in pairs(t) do t[k] = nil end end
local SECRET = {}
local function Public(v) return v ~= SECRET end
local function Finite(v) return Public(v) and type(v) == "number" and v == v and v > -math.huge and v < math.huge end
local context = {}
function context:Event(event, fn) events[event] = fn end
function context:RemoveEvent(event) events[event] = nil end
function context:Coalesce(_, fn)
    local job = {}
    function job:Request() queue[fn] = true end
    return job
end
local module
local ns = { InCombat = function() return combat end, Print = function() reports = reports + 1 end,
    Dispatch = function(fn, ...) return pcall(fn, ...) end }
local suite = { Install = function(_, m) module = m end, Public = Public, Finite = Finite,
    PublicText = function(v) return Public(v) and type(v) == "string" and v ~= "" and v or nil end,
    Text = function(v) return v end }
GetActionInfo = function(slot)
    scans = scans + 1
    local a = actions[slot]
    if a then return a.kind or "spell", a.id end
end
C_SpellBook = {
    FindSpellBookSlotForSpell = function(id) if ranks[id] then return id, 0 end end,
    IsSpellBookItemLowRank = function(id) return ranks[id] == "low" end,
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 2 } end,
    GetSpellBookItemType = function(slot) return 1, slot == 1 and 100 or 101 end,
}
C_ActionBar = { FindSpellActionButtons = function(spell, set)
    assert(set == Enum.ActionBarSet.All, "gamepad storage omitted")
    local slots = {}
    for slot, action in pairs(actions) do if action.id == spell then slots[#slots + 1] = slot end end
    return slots
end }
C_Spell = { GetSpellName = function(id) return names[id] end,
    PickupSpell = function(id)
        if raises then error("native pickup refused") end
        held, picked = "spell", wrong and 303 or id
    end }
GetCursorInfo = function() return held, 17, "spell", picked end
PlaceAction = function(slot)
    assert(not combat and held == "spell", "unsafe action placement")
    calls = calls + 1
    actions[slot] = { id = picked }
    if events.ACTIONBAR_SLOT_CHANGED then events.ACTIONBAR_SLOT_CHANGED(module, "ACTIONBAR_SLOT_CHANGED", slot) end
end
ClearCursor = function() held, picked = nil, nil end
local chunk = assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/AutoUprank.lua"))
local sets = Enum.ActionBarSet
Enum.ActionBarSet = nil
chunk("MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
Enum.ActionBarSet = sets
assert(scans == 0 and next(events) == nil, "disabled helper performed work")
module.context, module.active, module.config = context, true, { report = true, replaceLowerRanks = false }
local function Run()
    local pending = queue
    queue = {}
    for fn in pairs(pending) do fn(module) end
end
local function Fire(event, ...) if events[event] then events[event](module, event, ...) end end
local function Seed()
    actions = { [1] = { id = 101 }, [2] = { id = 100 }, [3] = { kind = "macro", id = 101 } }
    ranks, names = { [100] = "low", [101] = "high" }, { [100] = "Heal", [101] = "Heal", [202] = "Heal", [303] = "Other" }
    combat, held, picked, wrong, raises = false, nil, nil, false, false
    module.active = true
    module:Enable()
end
local function Learn()
    ranks[101], ranks[202] = "low", "high"
    Fire("LEARNED_SPELL_IN_SKILL_LINE", 202, nil, false)
end
Seed()
assert(calls == 0 and scans == 3, "enable changed slots or scanned unoccupied storage")
Learn(); Learn(); Run()
assert(calls == 1 and actions[1].id == 202 and actions[2].id == 100 and actions[3].kind == "macro", "rank/downrank/macro behavior")
assert(reports == 1 and next(module.pending) == nil, "duplicate learned events were not coalesced")
Seed(); Learn(); combat = true; Run()
assert(actions[1].id == 101 and events.PLAYER_REGEN_ENABLED, "combat-edge placement was not deferred")
combat = false; Fire("PLAYER_REGEN_ENABLED"); Run()
assert(actions[1].id == 202 and events.PLAYER_REGEN_ENABLED == nil, "combat resume failed")
Seed(); Learn(); held = "item"; Run()
assert(actions[1].id == 101 and held == "item" and events.CURSOR_CHANGED, "busy cursor was touched")
held = nil; Fire("CURSOR_CHANGED"); Run()
assert(actions[1].id == 202 and events.CURSOR_CHANGED == nil, "cursor resume failed")
Seed(); Learn(); combat = true; Run(); actions[1] = { id = 303 }; Fire("ACTIONBAR_SLOT_CHANGED", 1)
combat = false; Fire("PLAYER_REGEN_ENABLED"); Run()
assert(actions[1].id == 303, "pending rank overwrote a user edit")
Seed(); Learn(); wrong = true; local before = calls; Run()
assert(actions[1].id == 101 and calls == before, "mismatched spell cursor overwrote an action")
Seed(); Learn(); raises = true; Run()
assert(module.placing == false and actions[1].id == 101, "native failure poisoned placement state")
Seed(); Learn(); module.config.replaceLowerRanks = true; Run()
assert(actions[1].id == 202 and actions[2].id == 202, "explicit lower-rank replacement did not run")
module.config.replaceLowerRanks = false
Seed(); before = scans; Fire("LEARNED_SPELL_IN_SKILL_LINE", SECRET, nil, false)
Fire("LEARNED_SPELL_IN_SKILL_LINE", 202, nil, true); Run()
assert(scans == before, "secret/guild spell event triggered a slot scan")
Seed(); Learn(); module.active = false; module:Disable(); before = calls; Run()
assert(calls == before and next(events) == nil, "disabled helper retained pending work/listeners")
Seed(); ranks[101], ranks[202] = "low", "low"; Fire("LEARNED_SPELL_IN_SKILL_LINE", 202, nil, false); Run()
assert(actions[1].id == 101, "a nonhighest learned rank was placed")
Seed(); actions[501] = { id = 101 }; Fire("ACTIONBAR_SLOT_CHANGED", 501); Learn(); Run()
assert(actions[501].id == 202, "native gamepad storage beyond 180 was omitted")
Seed(); actions[501] = { id = 101 }; Fire("ACTIONBAR_SLOT_CHANGED", 0); Run(); Learn(); Run()
assert(actions[501].id == 202, "full native storage rebuild omitted a controller slot")
Seed(); local pickup = C_Spell.PickupSpell
C_Spell.PickupSpell = function(id) pickup(id); actions[1] = { id = 404 } end
Learn(); before = calls; Run()
assert(actions[1].id == 404 and calls == before and held == nil, "pickup callback overwrote a newly edited slot or retained our cursor")
C_Spell.PickupSpell = pickup
Seed(); combat = true; Learn(); Run()
actions[1] = nil; Fire("ACTIONBAR_SLOT_CHANGED", 0)
combat = false; Fire("PLAYER_REGEN_ENABLED"); Run()
actions[1] = { id = 101 }; Fire("ACTIONBAR_SLOT_CHANGED", 1)
Fire("LEARNED_SPELL_IN_SKILL_LINE", 202, nil, false); Run()
assert(actions[1].id == 101, "a full reset retained stale downrank eligibility")
Seed(); Learn(); held = "item"; Run()
actions[1] = nil; Fire("ACTIONBAR_SLOT_CHANGED", 0)
actions[1] = { id = 101 }; Fire("ACTIONBAR_SLOT_CHANGED", 1)
held = nil; Fire("CURSOR_CHANGED"); Run()
assert(actions[1].id == 101, "same-frame full reset retained stale downrank eligibility")
Seed(); local place = PlaceAction
PlaceAction = function() error("native placement refused") end
Learn(); Run()
assert(module.placing == false and held == nil and actions[1].id == 101, "failed placement retained our spell cursor")
PlaceAction = function(slot) place(slot); held, picked = "item", 777 end
Seed(); Learn(); Run()
assert(actions[1].id == 202 and held == "item" and picked == 777, "placement callback's foreign cursor was cleared")
PlaceAction = function(slot) local old = actions[slot].id; place(slot); held, picked = "spell", old end
Seed(); Learn(); Run()
assert(actions[1].id == 202 and held == nil, "displaced old spell remained on cursor")
PlaceAction = place
local f = assert(io.open(root .. "/MSUF_Suite/Core/Catalog/QualityOfLife.lua", "rb"))
local source = f:read("*a"); f:close()
assert(source:find('automation = true, defaultEnabled = false', 1, true), "automation opt-in contract missing")
print("suite_auto_uprank_contract: PASS")
