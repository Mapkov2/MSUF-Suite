-- Auto-uprank exceptions and the explicit "Update placed spell ranks now"
-- action (MSUF_Suite_QualityOfLife/AutoUprank.lua). Exact-rank exceptions
-- guard every replacement and every retry; the explicit action follows
-- replaceLowerRanks, waits for combat and a busy cursor to clear and then
-- rechecks each slot's identity; the default automatic path is unchanged.
local root = assert((...), "Suite root required"):gsub("\\", "/"):gsub("/$", "")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")

-- A secret raises on comparison, arithmetic, indexing and concatenation.
local SECRET = newproxy(true)
do
    local mt = getmetatable(SECRET)
    local function Misuse() error("secret value misused", 2) end
    for _, key in ipairs({ "__index", "__newindex", "__call", "__concat", "__len", "__unm", "__add", "__sub",
        "__mul", "__div", "__mod", "__pow", "__lt", "__le" }) do mt[key] = Misuse end
end
local function Public(v) return v ~= SECRET end
local function Finite(v) return Public(v) and type(v) == "number" and v == v and v > -math.huge and v < math.huge end

local events, queue, actions, ranks, names, prints, errors = {}, {}, {}, {}, {}, {}, {}
local combat, held, picked, secret = false, nil, nil, {}
local calls, scans, walks = 0, 0, 0
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 }, ActionBarSet = { All = 3 } }
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

-- The player's book: every known spell ID in order; ranks[id] is "low" or "high".
local function Book()
    local ids = {}
    for id in pairs(ranks) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end
C_SpellBook = {
    FindSpellBookSlotForSpell = function(id)
        for slot, known in ipairs(Book()) do if known == id then return slot, 0 end end
    end,
    IsSpellBookItemLowRank = function(slot)
        if secret.low then return SECRET end
        return ranks[Book()[slot]] == "low"
    end,
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #Book() } end,
    GetSpellBookItemType = function(slot)
        walks = walks + 1
        return 1, Book()[slot]
    end,
}
C_ActionBar = { FindSpellActionButtons = function(spell, set)
    assert(set == Enum.ActionBarSet.All, "gamepad storage omitted")
    if secret.buttons then return SECRET end
    local slots = {}
    for slot, action in pairs(actions) do if action.id == spell then slots[#slots + 1] = slot end end
    return slots
end }
C_Spell = {
    GetSpellName = function(id) if secret.name then return SECRET end return names[id] end,
    PickupSpell = function(id) held, picked = "spell", id end,
}
GetCursorInfo = function()
    if secret.cursor then return SECRET end
    return held, 17, "spell", picked
end
GetActionInfo = function(slot)
    scans = scans + 1
    if secret.action == slot then return SECRET, SECRET end
    local a = actions[slot]
    if a then return a.kind or "spell", a.id end
end
local module
PlaceAction = function(slot)
    assert(not combat and held == "spell", "unsafe action placement")
    calls = calls + 1
    actions[slot] = { id = picked }
    if events.ACTIONBAR_SLOT_CHANGED then events.ACTIONBAR_SLOT_CHANGED(module, "ACTIONBAR_SLOT_CHANGED", slot) end
end
ClearCursor = function() held, picked = nil, nil end

local context = {}
function context:Event(event, fn) events[event] = fn end
function context:RemoveEvent(event) events[event] = nil end
function context:Coalesce(_, fn)
    local job = {}
    function job:Request() queue[fn] = true end
    return job
end
local ns = {
    InCombat = function() return combat end,
    Print = function(text) prints[#prints + 1] = text end,
    Dispatch = function(fn, ...)
        local ok, err = pcall(fn, ...)
        if not ok then errors[#errors + 1] = err end
        return ok
    end,
}
local suite = { Install = function(_, m) module = m end, Public = Public, Finite = Finite,
    PublicText = function(v) return Public(v) and type(v) == "string" and v ~= "" and v or nil end,
    Text = function(v) return v end }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/AutoUprank.lua"))("MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
module.context = context

local function Run()
    local pending = queue
    queue = {}
    for fn in pairs(pending) do fn(module) end
end
local function Fire(event, ...) if events[event] then events[event](module, event, ...) end end
local function Last() return prints[#prints] end

-- Fireball 10 < 11 < 12, Frostbolt 20 < 21, Heal 30 < 31. Shoot 39 is lower
-- than two highest spells sharing its name (40, 41): ambiguous, never chosen.
-- Slot 5 is a macro, slot 7 holds the highest Frostbolt, 501 is gamepad storage.
local function Seed(config, hidden)
    module:Disable()
    ranks = { [10] = "low", [11] = "low", [12] = "high", [20] = "low", [21] = "high", [30] = "low",
        [31] = "high", [39] = "low", [40] = "high", [41] = "high" }
    names = { [10] = "Fireball", [11] = "Fireball", [12] = "Fireball", [20] = "Frostbolt", [21] = "Frostbolt",
        [22] = "Frostbolt", [30] = "Heal", [31] = "Heal", [39] = "Shoot", [40] = "Shoot", [41] = "Shoot" }
    actions = { [1] = { id = 11 }, [2] = { id = 10 }, [3] = { id = 20 }, [4] = { id = 30 },
        [5] = { kind = "macro", id = 10 }, [6] = { id = 39 }, [7] = { id = 21 }, [501] = { id = 11 } }
    combat, held, picked, secret, queue = false, nil, nil, hidden or {}, {}
    wipe(prints)
    wipe(errors)
    module.active = true
    module.config = { report = false, replaceLowerRanks = false, exceptSpellIDs = "" }
    for key, value in pairs(config or {}) do module.config[key] = value end
    module:Enable()
end
local function LearnFrostbolt() ranks[21], ranks[22] = "low", "high" end
local function Untouched(...)
    local slots = { ... }
    local seed = { [1] = 11, [2] = 10, [3] = 20, [4] = 30, [6] = 39, [7] = 21, [501] = 11 }
    for _, slot in ipairs(slots) do
        if actions[slot].id ~= seed[slot] then return false end
    end
    return actions[5].kind == "macro" and actions[5].id == 10
end
local function Clean(message)
    assert(#errors == 0, message .. ": " .. tostring(errors[1]))
    for _, t in ipairs({ module.observed, module.eligible, module.discovered, module.pending, module.except,
        module.plan or {}, module.ranks or {} }) do
        for k, v in pairs(t) do assert(k ~= SECRET and v ~= SECRET, message .. ": a secret was cached") end
    end
end

------------------------------------------------------------------ default automatic path
module.config, module.active = {}, false
Seed()
assert(calls == 0 and walks == #Book(), "enable placed an action or walked the book more than once")
local before = scans
Fire("ACTIONBAR_SLOT_CHANGED", 4)
assert(scans == before + 1, "one slot change must read exactly one action")
LearnFrostbolt()
before = walks
Fire("LEARNED_SPELL_IN_SKILL_LINE", 22, nil, false); Run()
assert(actions[7].id == 22 and Untouched(1, 2, 3, 4, 6, 501), "default automatic behavior changed")
assert(walks == before, "a learned rank walked the spellbook")
local walked
before, walked = scans, walks
module.config.exceptSpellIDs = "31"; module:Refresh()
assert(scans == before and walks == walked, "an exception edit scanned actions or the spellbook")

------------------------------------------------------------------ exceptions, automatic path
Seed({ exceptSpellIDs = "21" }); LearnFrostbolt()
Fire("LEARNED_SPELL_IN_SKILL_LINE", 22, nil, false); Run()
assert(actions[7].id == 21, "automatic update replaced an excepted placed rank")
Seed({ exceptSpellIDs = "22" }); LearnFrostbolt()
Fire("LEARNED_SPELL_IN_SKILL_LINE", 22, nil, false); Run()
assert(actions[7].id == 21, "automatic update placed an excepted rank")
Seed(); combat = true; LearnFrostbolt()
Fire("LEARNED_SPELL_IN_SKILL_LINE", 22, nil, false); Run()
assert(actions[7].id == 21 and events.PLAYER_REGEN_ENABLED, "combat did not defer the learned rank")
module.config.exceptSpellIDs = "21"; module:Refresh()
combat = false; Fire("PLAYER_REGEN_ENABLED"); Run()
assert(actions[7].id == 21 and events.PLAYER_REGEN_ENABLED == nil, "a pending retry ignored a later exception")
Seed({ exceptSpellIDs = " 30,11 0  99999999999,,4294967296" })
local listed = 0
for id in pairs(module.except) do listed = listed + 1; assert(id == 30 or id == 11, "invalid exception kept") end
assert(listed == 2, "valid exceptions were dropped")

------------------------------------------------------------------ explicit update, default setting
Seed(); LearnFrostbolt()
before = walks
assert(module:UpdatePlacedRanks() == true, "the running helper refused the explicit update")
assert(walks - before == #Book(), "the explicit update must walk the spellbook exactly once")
Run()
assert(actions[7].id == 22, "the explicit update skipped a slot seen at the highest rank")
assert(Untouched(1, 2, 3, 4, 6, 501), "the explicit update replaced deliberate lower ranks by default")
assert(prints[1] == "Updated 1 action slots to your highest learned spell ranks.", "explicit result not reported")
assert(Last():find("^5 lower ranks you may have placed on purpose stayed%.")
    and Last():find("Also replace deliberately lower ranks", 1, true), "kept lower ranks were not explained")
Clean("explicit default")

------------------------------------------------------------------ explicit update, lower ranks allowed
Seed({ replaceLowerRanks = true, exceptSpellIDs = "30, 11" })
module:UpdatePlacedRanks(); Run()
assert(actions[2].id == 12 and actions[3].id == 21, "allowed lower ranks were not updated")
assert(Untouched(1, 4, 6, 7, 501), "an excepted, ambiguous, highest or macro slot changed")
assert(prints[1] == "Updated 2 action slots to your highest learned spell ranks." and #prints == 1, "result report")
Seed({ replaceLowerRanks = true, exceptSpellIDs = "12" })
module:UpdatePlacedRanks(); Run()
assert(Untouched(1, 2, 501) and actions[3].id == 21 and actions[4].id == 31, "an excepted target rank was placed")
Seed({ replaceLowerRanks = true }); ranks[12], ranks[30], ranks[31] = nil, nil, nil
module:UpdatePlacedRanks(); Run()
assert(Untouched(1, 2, 4, 501) and actions[3].id == 21, "an unlearned rank was placed")
Seed(); module:UpdatePlacedRanks(); Run()
assert(prints[1] == "No action slots were updated.", "an empty explicit update stayed silent")

------------------------------------------------------------------ deferred explicit update
Seed({ replaceLowerRanks = true }); held = "item"; before = calls
module:UpdatePlacedRanks(); Run()
assert(calls == before and held == "item" and events.CURSOR_CHANGED, "a busy cursor was touched")
assert(Last() == "Spell ranks will update once combat ends and your cursor is empty.", "deferral not explained")
actions[2] = { id = 31 }; Fire("ACTIONBAR_SLOT_CHANGED", 2)
actions[3] = { id = 20 }; Fire("ACTIONBAR_SLOT_CHANGED", 3)
actions[4] = { id = 31 }
held = nil; Fire("CURSOR_CHANGED"); Run()
assert(actions[1].id == 12 and actions[501].id == 12, "deferred explicit work did not resume")
assert(actions[2].id == 31 and actions[3].id == 20 and actions[4].id == 31, "deferred explicit work overwrote a player edit")
assert(events.CURSOR_CHANGED == nil and module.plan == nil, "finished explicit work kept listening")
assert(Last() == "Updated 2 action slots to your highest learned spell ranks.", "deferred result report")
Seed({ replaceLowerRanks = true }); combat = true
module:UpdatePlacedRanks(); Run()
assert(actions[2].id == 10 and events.PLAYER_REGEN_ENABLED, "combat did not defer explicit work")
combat = false; Fire("PLAYER_REGEN_ENABLED"); Run()
assert(actions[2].id == 12 and actions[4].id == 31 and events.PLAYER_REGEN_ENABLED == nil, "combat resume failed")
Seed({ replaceLowerRanks = true }); combat = true
module:UpdatePlacedRanks(); Run()
module.config.replaceLowerRanks = false
module.config.exceptSpellIDs = "12"; module:Refresh()
combat = false; Fire("PLAYER_REGEN_ENABLED"); Run()
assert(Untouched(1, 2, 3, 4, 501), "pending explicit work ignored the current settings")
-- A placement that leaves a foreign item on the cursor pauses the rest.
Seed({ replaceLowerRanks = true })
local place = PlaceAction
PlaceAction = function(slot)
    place(slot)
    PlaceAction = place
    held, picked = "item", 777
end
module:UpdatePlacedRanks(); Run()
local changed = 0
for _, slot in ipairs({ 1, 2, 3, 4, 501 }) do if not Untouched(slot) then changed = changed + 1 end end
assert(changed == 1 and held == "item" and picked == 777 and events.CURSOR_CHANGED and module.plan,
    "a cursor taken during explicit work did not pause it")
held, picked = nil, nil; Fire("CURSOR_CHANGED"); Run()
assert(actions[1].id == 12 and actions[2].id == 12 and actions[3].id == 21 and actions[4].id == 31
    and actions[501].id == 12 and module.plan == nil, "paused explicit work did not finish")
assert(Last() == "Updated 5 action slots to your highest learned spell ranks.", "a paused update lost its count")
Seed({ replaceLowerRanks = true }); held = "item"
module:UpdatePlacedRanks(); Run()
Fire("ACTIONBAR_SLOT_CHANGED", 0)
assert(module.plan == nil and Last():find("action bars changed", 1, true), "a full reset kept a stale snapshot")
held = nil; Fire("CURSOR_CHANGED"); Run()
assert(Untouched(1, 2, 3, 4, 501), "a cancelled snapshot was applied")
Seed({ replaceLowerRanks = true }); held = "item"
module:UpdatePlacedRanks(); Run()
module.active = false; module:Disable()
held = nil; Run()
assert(next(events) == nil and module.plan == nil and Untouched(1, 2, 3, 4, 501), "disable kept explicit work")
assert(module:UpdatePlacedRanks() == false, "a stopped helper accepted explicit work")

------------------------------------------------------------------ secret inputs
for _, hidden in ipairs({ { low = true }, { name = true }, { buttons = true } }) do
    Seed({ replaceLowerRanks = true }, hidden)
    before = calls
    module:UpdatePlacedRanks(); Run()
    Fire("LEARNED_SPELL_IN_SKILL_LINE", 12, nil, false); Run()
    assert(calls == before and Untouched(1, 2, 3, 4, 501), "a secret spellbook answer led to a replacement")
    Clean("secret spellbook")
end
Seed({ replaceLowerRanks = true }, { action = 2 })
module:UpdatePlacedRanks(); Run()
assert(actions[2].id == 10 and actions[1].id == 12, "a secret action slot was replaced or blocked the others")
Clean("secret action")
Seed({ replaceLowerRanks = true }); secret.cursor = true
module:UpdatePlacedRanks(); Run()
assert(Untouched(1, 2) and events.CURSOR_CHANGED, "a secret cursor was treated as empty")
secret.cursor = nil; Fire("CURSOR_CHANGED"); Run()
assert(actions[2].id == 12, "explicit work did not resume after a secret cursor")
Seed(); before = scans
Fire("LEARNED_SPELL_IN_SKILL_LINE", SECRET, nil, false)
Fire("LEARNED_SPELL_IN_SKILL_LINE", 22, nil, SECRET)
Fire("ACTIONBAR_SLOT_CHANGED", SECRET); Run()
assert(scans == before and next(module.pending) == nil, "a secret event argument caused work")
Clean("secret events")

------------------------------------------------------------------ catalog
local config, catalog = Support.CatalogDefaults(root, "autoUprank", "QualityOfLife", { isForever = true })
local rules = catalog.SuiteCatalog.autoUprank.rules
assert(config.enabled == false and config.replaceLowerRanks == false and config.exceptSpellIDs == "", "defaults changed")
assert(rules.exceptSpellIDs.ids == true and rules.exceptSpellIDs.section == "auto_uprank"
    and not rules.exceptSpellIDs.automation and rules.exceptSpellIDs.maxLength >= 100, "exception list rule")
assert(type(rules.exceptSpellIDs.help) == "string" and rules.exceptSpellIDs.label:find("spell IDs", 1, true),
    "the exception list explains no format")
print("suite_auto_uprank_update_contract: PASS")
