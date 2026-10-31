local root = assert(arg[1], "repository root required")
-- Cooldown manager content on the options page (package cdm11-D):
--  * The spell picker's group rows (Interrupts, Crowd control, Movement,
--    Battle resurrection, Dispels, Major offensive cooldowns): only groups
--    the character knows spells of, first in the list, how many each adds,
--    found by search, one history entry per click, spells already on the bar
--    not added twice, spells of other bars moving here, a full bar taking
--    none, buff bars without them, shared groups asking for spell keys only.
--  * The haste buff row (Bloodlust and its look-alikes) on buff bars: one
--    row, found by any source's name, one pick, no row on a client that
--    knows no source.
--  * The ready pulse rules: the bar's switch among the cooldown effects,
--    the General settings greyed until a bar pulses.
-- Runs on the options contract's harness up to its picker checks.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_options_contract.lua", [=[
do (function()
local checks, failures = 0, {}
local function Check(value, message)
    checks = checks + 1
    if not value then failures[#failures + 1] = message end
end
local groupCalls, plainAsked = 0, nil
local fixture = {
    interrupts = { "s2139", icon = 1101 },
    crowdcontrol = { "b4", "s118", icon = 1102 },
    movement = {}, battlerez = {}, dispels = {},
    offensive = { "s190319", icon = 1103 },
}
S.CooldownManagerGroupKeys = function(plain)
    groupCalls, plainAsked = groupCalls + 1, plain
    return fixture
end
local function Rows(pick)
    local out = {}
    for _, row in ipairs(pick.rows) do if row.shown and row.item then out[#out + 1] = row end end
    return out
end
local function Row(pick, key)
    for _, row in ipairs(Rows(pick)) do if row.item.key == key then return row end end
end
local function Search(pick, text)
    pick.search:SetText(text)
    Fire(pick.search, "OnTextChanged", true)
    local keys = {}
    for _, row in ipairs(Rows(pick)) do keys[#keys + 1] = row.item.key end
    return table.concat(keys, ",")
end
picker.set("ess")
M.RequestRefresh()
Check(Page.picker == nil or not Page.picker.shown, "the picker starts closed")
Fire(grid.plus, "OnClick", "LeftButton")
local pick = assert(Page.picker)
Check(pick.shown, "the picker opens")
local calls = groupCalls
Check(calls >= 1 and not plainAsked, "a cooldown bar asks for the groups, with Blizzard's entries allowed")

------------------------------------------------------------------ group rows
local rows = Rows(pick)
Check(rows[1].item.kind == "header" and rows[1].item.text == "Add a group of spells", "the groups come first")
Check(rows[2].item.key == "interrupts" and rows[3].item.key == "crowdcontrol" and rows[4].item.key == "offensive"
    and rows[5].item.kind == "header" and rows[5].item.text == "Blizzard cooldowns",
    "only groups with known spells have rows, in the runtime's order")
Check(rows[2].item.kind == "group" and rows[2].text.text == "Interrupts" and rows[3].text.text == "Crowd control spells"
    and rows[4].text.text == "Major offensive cooldowns", "the groups' names")
Check(rows[2].status.text == "Adds 1" and rows[3].status.text == "Adds 2" and rows[4].status.text == "Adds 1",
    "each row says how many spells it adds")
Check(rows[2].icon.texture == 1101, "a row shows the group's first spell")
Check(Keys("ess") == "b1,b2,b3" and Keys("uti") == "b4,b5,b6", "the fixture's bars before the picks")

-- One click: one history entry, the unlisted spells join, a spell of another bar moves.
local writes, encoded = historyWrites, encodes
Fire(Row(pick, "crowdcontrol"), "OnClick")
Check(historyWrites == writes + 1 and encodes == encoded + 1, "a group is one history entry through the codec")
Check(Keys("ess") == "b1,b2,b3,b4,s118" and Keys("uti") == "b5,b6", "the group's spells joined the bar, one left Utility")
Check(table.concat(Lists().specs[62].ess, ",") == "b1,b2,b3,b4,s118", "explicit list keeps the bar's order first")
Check(pick.shown and pick.note.text == "Added Crowd control spells." and Page.note == pick.note.text, "the picker names the group and stays open")
local done = Row(pick, "crowdcontrol")
Check(done.status.text == "On this bar" and done.alpha == 0.45, "the picked group greys in place")
Check(Row(pick, "interrupts").status.text == "Adds 1" and Row(pick, "b4").status.text == "On this bar",
    "the other rows follow: Frost Nova is on this bar now")
Fire(done, "OnClick")
Check(historyWrites == writes + 1, "a group that is all on the bar writes nothing")
-- A spell the bar holds already is not added again.
fixture.offensive = { "b1", "s190319" }
Page.RebuildPicker()
Check(Row(pick, "offensive").status.text == "Adds 1", "a listed spell is not counted")
writes = historyWrites
Fire(Row(pick, "offensive"), "OnClick")
Check(historyWrites == writes + 1 and Keys("ess") == "b1,b2,b3,b4,s118,s190319", "the listed spell kept its place, the other joined")
local list = Lists().specs[62].ess
local seen = {}
for _, key in ipairs(list) do
    Check(not seen[key], "the list holds " .. key .. " twice")
    seen[key] = true
end

------------------------------------------------------------------ search
Check(Search(pick, "interrupt") == "interrupts", "the interrupts row is found by name")
local found = Rows(pick)
Check(#found == 2 and found[1].item.kind == "header" and found[2].item.key == "interrupts", "search keeps the group header with its row")
Check(Search(pick, "major") == "offensive", "found by a word of its name")
Check(Search(pick, "zzz") == "" and pick.empty.shown, "nothing matches")
Search(pick, "")

------------------------------------------------------------------ add it to the page: refusals
-- Bad keys, a wrong bar family and a full bar change nothing.
writes = historyWrites
local ok, why = Page.AddGroup("ess", { "zzz" })
Check(ok == false and why == "Invalid spell or item." and historyWrites == writes, "a malformed key is refused whole")
ok, why = Page.AddGroup("buf", { "s118" })
Check(ok == false and why == "That bar shows buffs." and historyWrites == writes, "a buff bar takes no cooldown group")
local limit = CDM.LIMITS.entries
CDM.LIMITS.entries = #Lists().specs[62].ess
fixture.movement = { "s1953" }
ok, why = Page.AddGroup("ess", { "s1953", "s212653" })
Check(ok == false and why == "This bar is full." and historyWrites == writes and Keys("ess") == "b1,b2,b3,b4,s118,s190319",
    "a full bar takes none of the group")
CDM.LIMITS.entries = limit
ok, why = Page.AddGroup("ess", { "s1953", "s212653" })
Check(ok == true and why == 2 and historyWrites == writes + 1, "two new spells: true and 2")
ok, why = Page.AddGroup("ess", { "s1953" })
Check(ok == true and why == 0 and historyWrites == writes + 1, "nothing new: true and 0, no entry")
combat = true
ok = Page.AddGroup("ess", { "s5" })
Check(ok == false, "no edit in combat")
combat = false
fixture.movement = {}

------------------------------------------------------------------ shared groups and buff bars
picker.set("c2")
Config().c2_kind, Config().c2_shareContents = 1, true
Page.RebuildPicker()
Check(plainAsked == true, "a shared group asks for spell keys only")
Config().c2_shareContents = false
Page.RebuildPicker()
Check(not plainAsked, "an unshared custom bar takes Blizzard's entries")
local before = groupCalls
picker.set("buf")
Page.RebuildPicker()
for _, row in ipairs(Rows(pick)) do Check(row.item.kind ~= "group", "a buff bar lists no spell group") end
Check(groupCalls == before, "a buff bar does not ask for the groups")

------------------------------------------------------------------ the haste buff row
local sources = { [2825] = { "Bloodlust", 1200 }, [32182] = { "Heroism", 1201 }, [80353] = { "Time Warp", 1202 } }
for id, spell in pairs(sources) do SPELLS[id] = spell end
Page.RebuildPicker()
rows = Rows(pick)
local haste = Row(pick, CDM.HASTE_KEY)
Check(haste and haste.item.kind == "entry" and haste.item.family == 2 and haste.text.text == "Bloodlust (any source)"
    and haste.icon.texture == 1200, "the buff picker offers the haste buff once, named for the group")
local at
for i, row in ipairs(rows) do if row == haste then at = i end end
Check(at and at > 1 and rows[at - 1].item.kind == "header" and rows[at - 1].item.text == "Received buffs (any caster)"
    and rows[at + 1].item.key == "a10060", "it leads the received buffs")
Check(Search(pick, "heroism") == CDM.HASTE_KEY and Search(pick, "time warp") == CDM.HASTE_KEY and Search(pick, "bloodlust") == CDM.HASTE_KEY,
    "found by the name of any source")
Search(pick, "")
Check(Page.Identity(CDM.HASTE_KEY) == "Bloodlust (any source)", "the page names the entry, not a spell number")
writes = historyWrites
Fire(Row(pick, CDM.HASTE_KEY), "OnClick")
Check(historyWrites == writes + 1 and Page.WhereIs(CDM.HASTE_KEY) == "buf" and Keys("buf"):find(CDM.HASTE_KEY, 1, true),
    "one pick adds it to the buff bar")
Fire(Row(pick, CDM.HASTE_KEY), "OnClick")
Check(historyWrites == writes + 1, "picking it again writes nothing")
-- A client that knows none of the sources (WoW Forever) has no row.
for id in pairs(sources) do SPELLS[id] = nil end
Page.RebuildPicker()
Check(not Row(pick, CDM.HASTE_KEY), "no source known: no row")
Config().listsData = assert(CDM.Codec.EncodeLists(CDM.CleanLists(nil)))
S.CooldownManagerGroupKeys = nil
picker.set("ess")
Page.RebuildPicker()
Check(Rows(pick)[1].item.text == "Blizzard cooldowns", "without the runtime's groups the picker is as before")
pick:Hide()

------------------------------------------------------------------ the ready pulse rules
local function Section(id)
    for _, spec in ipairs(Page.SECTIONS) do
        if spec.id == id then return table.concat(spec.suffixes, ",") .. "," end
    end
    return ""
end
Check(Section("effects"):find("assist,kickMark,bling,readyPulse,", 1, true), "the pulse switch follows the flash among the cooldown effects")
Check(Page.Relevant("ess", "readyPulse") and Page.Relevant("c1", "readyPulse") and not Page.Relevant("buf", "readyPulse")
    and not Page.Relevant("bar", "readyPulse"), "cooldown bars have the pulse, buff bars do not")
Config().c1_kind = 2
Check(not Page.Relevant("c1", "readyPulse"), "a custom bar loses it as a buff bar")
Config().c1_kind = 1
local rule = Suite.SuiteCatalog[ID].rules
Check(rule[CDM.KEYS.c1.readyPulse].tooltip and rule[CDM.KEYS.c1.readyPulse].tooltip:find("hidden", 1, true),
    "the switch says it pulses for a hidden bar too")
local function Why(key)
    local enabled, reason = P.RuleEnabled(ID, rule[key], Page.KeyFn, true)
    return enabled, reason
end
for _, key in ipairs({ "pulseCombat", "pulseSize", "pulseY", "pulseHold" }) do
    local enabled, reason = Why(key)
    Check(enabled == false and reason:find("Pulse ready cooldowns in the screen center", 1, true),
        key .. " is greyed while no bar pulses, with its reason: " .. tostring(reason))
end
Config().c3_readyPulse = true
for _, key in ipairs({ "pulseCombat", "pulseSize", "pulseY", "pulseHold" }) do
    Check(Why(key) == true, key .. " is editable once a bar pulses")
end
Config().c3_readyPulse = false
M.RequestRefresh()
Check(Control("pulseSize").enabled == false and Control("pulseHold").enabled == false, "the General controls grey with the rule")
Config().c3_readyPulse = true
M.RequestRefresh()
Check(Control("pulseSize").enabled == true and Control("pulseCombat").enabled == true, "and wake when a bar pulses")
Config().c3_readyPulse = false
M.RequestRefresh()
Check(Control("readyPulse").meta.sectionId == PAGE .. "_effects"
    and Control("pulseSize").meta.sectionId == PAGE .. "_cooldownManager_module", "the switch sits in Cooldown effects, the rest in Basics")
if #failures > 0 then error("suite_cdm_content_options_contract failed:\n  " .. table.concat(failures, "\n  ")) end
print("suite_cdm_content_options_contract: " .. checks .. " checks passed")
end)() end
]=], "-- Picker: filter, claim from another bar, keep open, custom IDs.")
