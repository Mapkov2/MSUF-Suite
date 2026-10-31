local root = assert(arg[1], "repository root required")
-- "Use MSUF cooldown profiles by specialization" (raidEssentials) is on by
-- default, but only Retail specializations have a profile row
-- (Presets.RAID_ESSENTIALS); WoW Forever's (1482, 1484-1491) have none.
-- Without a row Essential followed Blizzard's layout while Utility and both
-- buff rows held Blizzard's stock defaults, so a spell the player moved
-- from Essential to Utility in Blizzard's settings showed on neither bar.
-- A specialization without a row follows Blizzard's layout on every
-- built-in bar, in the runtime (Resolve) and in the other-spec editor
-- (Editor); specializations with a row keep their bars exactly.
local W = dofile(root .. "/tools/tests/cdm_data_world.lua")(root)
local C, NS = W.C, W.NS
local CDM = NS.CDM
local Catalog, Resolve = C.Catalog, C.Resolve
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end
local function Info(id, category, extra)
    local info = { cooldownID = id, spellID = 50000 + id, linkedSpellIDs = {}, selfAura = false, hasAura = false, charges = false,
        isKnown = true, isInvisible = false, flags = 0, category = category }
    for key, value in pairs(extra or {}) do info[key] = value end
    W.infos[id] = info
end
W.sets[0], W.sets[1], W.sets[2], W.sets[3] = { 101, 102, 103 }, { 111, 112 }, { 201, 202 }, { 301 }
for _, id in ipairs({ 101, 102, 103 }) do Info(id, 0) end
for _, id in ipairs({ 111, 112 }) do Info(id, 1) end
for _, id in ipairs({ 201, 202 }) do Info(id, 2, { hasAura = true, selfAura = true }) end
Info(301, 3, { hasAura = true, selfAura = true })
-- The player's Blizzard layout (save format 5, spec tag 83): 102 moved
-- from Essential to Utility, the buff 201 moved to the bars.
W.layouts.moved = { [1] = 5, [2] = { [83] = 7 }, [3] = { [83] = { [7] = { [1] = {}, [2] = { [1] = { 102 }, [3] = { 201 } } } } } }
W.layoutBlob = "1|moved"
W.Views()
C.lists = CDM.CleanLists(nil)

local function Plan(slot)
    local plan, out = C.plans[slot], {}
    for i, entry in ipairs(plan and plan.entries or {}) do out[i] = entry.key end
    return table.concat(out, ",")
end
local function Bars(spec, raid)
    C.state.specID, C.state.raidEssentials = spec, raid
    Catalog.Rebuild()
    Resolve.Build()
    return { ess = Plan("ess"), uti = Plan("uti"), buf = Plan("buf"), bar = Plan("bar") }
end

------------------------------------------------------------------ WoW Forever
local FOREVER = 1484
Check(C.Presets.RaidEssentials(FOREVER) == nil, "the fixture needs a specialization without a profile row")
local on = Bars(FOREVER, nil)
Check(on.uti == "b102,b111,b112", "a spell moved to Utility in Blizzard's layout did not show there: " .. on.uti)
Check(on.ess == "b101,b103", "Essential lost Blizzard's layout: " .. on.ess)
Check(on.buf == "b202" and on.bar == "b201,b301", "the buff rows did not follow Blizzard's layout: " .. on.buf .. " / " .. on.bar)
Check(table.concat(Resolve.Keys("uti"), ",") == on.uti, "the options rows differ from the runtime Utility bar")
-- The profile option changes nothing without a row: off shows the same.
local off = Bars(FOREVER, false)
for _, slot in ipairs({ "ess", "uti", "buf", "bar" }) do
    Check(off[slot] == on[slot], slot .. " differs between the profile option on and off without a profile row")
end

------------------------------------------------------------------ Retail rows
-- Fire Mage has a row: Utility and both buff rows keep the stock defaults
-- (the guide and Blizzard's categories), not the saved layout. These are
-- the bars before this change, for this fixture.
local retail = Bars(63, nil)
Check(retail.uti == "b111,b112" and retail.ess == "b101,b102,b103", "a Retail profile row changed: " .. retail.ess .. " / " .. retail.uti)
Check(retail.buf == "b201,b202" and retail.bar == "b301", "Retail buff defaults changed: " .. retail.buf .. " / " .. retail.bar)
local retailOff = Bars(63, false)
Check(retailOff.uti == "b102,b111,b112" and retailOff.ess == "b101,b103", "Retail with the profile option off left Blizzard's layout")

------------------------------------------------------------------ other-spec editor
-- The editor previews a specialization from what the options page saved
-- while it was active (Editor.Remember); its bars match the runtime's.
NS.RootDB = {}
NS.Database.GetActiveProfileName = function() return "Default" end
NS.InCombat = function() return false end
W.S.ClassRGB = function() return 1, 1, 1 end
assert(loadfile(root .. "/MSUF_Suite_CooldownManager/Editor.lua"))("MSUF_Suite_CooldownManager", W.P)
local config = { listsData = "", spellsData = "", raidEssentials = true }
for _, def in ipairs(CDM.SLOTS) do config[CDM.KEYS[def.key].on] = def.builtin == true end
local function EditorBars(spec, raid)
    Bars(spec, raid)
    C.Editor.Remember()
    config.raidEssentials = raid ~= false
    local context = C.Editor.Context(spec, W.classID, config)
    local out = {}
    for _, slot in ipairs({ "ess", "uti", "buf", "bar" }) do
        local keys = {}
        for i, row in ipairs(context.bars[slot]) do keys[i] = row.key end
        out[slot] = table.concat(keys, ",")
    end
    return out
end
local editor = EditorBars(FOREVER, nil)
Check(editor.uti == "b102,b111,b112" and editor.ess == "b101,b103",
    "the editor kept stock Utility for a specialization without a profile row: " .. editor.ess .. " / " .. editor.uti)
Check(editor.buf == "b202" and editor.bar == "b201,b301", "the editor's buff rows left Blizzard's layout")
local editorRetail = EditorBars(63, nil)
Check(editorRetail.uti == "b111,b112", "the editor changed a Retail profile row: " .. editorRetail.uti)

------------------------------------------------------------------ options rule
-- The Lists page asks the runtime the same question (Exports.lua).
W.S.Finite = W.S.Finite or function(v) return type(v) == "number" end
W.S.Dispatch = W.S.Dispatch or function(fn, ...) return fn(...) end
assert(loadfile(root .. "/MSUF_Suite_CooldownManager/Exports.lua"))("MSUF_Suite_CooldownManager", W.P)
Check(W.S.CooldownManagerProfileRow(FOREVER) == false and W.S.CooldownManagerProfileRow(63) == true,
    "the options page's profile-row answer differs from Presets.RAID_ESSENTIALS")

print("CDM profile fallback: " .. checks .. " checks passed")
