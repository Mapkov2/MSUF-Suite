local root = assert(arg[1])
-- The Lists page follows the runtime's profile-row rule (Resolve.ListOf):
-- the Suite's spec defaults (raid essentials, spec Utility and buff rows)
-- apply only with "Use MSUF cooldown profiles by specialization" on AND a
-- profile row for the spec (S.CooldownManagerProfileRow). A spec without a
-- row (WoW Forever) follows Blizzard's layout, so its reset labels say so,
-- an edit of Essential keeps Blizzard's new spells appending (no replace
-- flag), and copies to it carry no inherited defaults. Specs with a row,
-- and a page without the runtime export, keep today's behavior.
local originalLoad, P = loadfile
loadfile = function(path)
    local chunk = assert(originalLoad(path))
    return function(addon, namespace)
        if path:find("MSUF_Suite_Options/Menu/Bridge.lua", 1, true) then P = namespace end
        return chunk(addon, namespace)
    end
end
assert(originalLoad(root .. "/tools/tests/suite_cooldown_manager_options_contract.lua"))()
loadfile = originalLoad
local Page, Suite, S = P.CDMPage, P.Suite, P.S
local CDM, ID = Suite.CDM, "cooldownManager"
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end
local spec = assert(Page.Spec())
local rows = {}
S.CooldownManagerProfileRow = function(id) return rows[id] == true end
local EMPTY_LISTS = assert(CDM.Codec.EncodeLists(CDM.CleanLists(nil))) or ""
local function Reset() assert(S.SetMany(ID, { listsData = EMPTY_LISTS, raidEssentials = true })) end
local function Lists() return CDM.Codec.DecodeLists(S.Config(ID).listsData) end
local function Labels()
    return table.concat({ Page.ClearLabel("ess"), Page.ClearLabel("uti"), Page.ClearLabel("buf"), Page.ClearLabel("bar") }, "|")
end
local BLIZZARD = "Reset to Blizzard's list|Reset to Blizzard's list|Reset to Blizzard's list|Reset to Blizzard's list"
local PROFILE = "Restore raid essentials|Restore spec defaults|Restore spec defaults|Restore spec defaults"

------------------------------------------------------------------ labels
Reset()
Check(Labels() == BLIZZARD, "a spec without a profile row offers to restore spec defaults: " .. Labels())
rows[spec] = true
Check(Labels() == PROFILE, "a spec with a profile row lost its reset labels: " .. Labels())
assert(S.SetMany(ID, { raidEssentials = false }))
Check(Labels() == BLIZZARD, "the profile option off still offers spec defaults")
local export = S.CooldownManagerProfileRow
S.CooldownManagerProfileRow, rows[spec] = nil, nil
assert(S.SetMany(ID, { raidEssentials = true }))
Check(Labels() == PROFILE, "without the runtime export the page left today's labels")
S.CooldownManagerProfileRow = export

------------------------------------------------------------------ edits
-- Reordering Essential makes its list explicit; only a spec with Suite
-- defaults marks it strict (replace), as raid essentials are a selection.
local function Reorder()
    Reset()
    local shown = Page.Entries("ess")
    local first, second = Page.EntryKey(shown[1]), Page.EntryKey(shown[2])
    assert(first and second, "the fixture's Essential bar needs two entries")
    assert(Page.MoveEntry(second, "ess", first, CDM.FAMILY.COOLDOWN))
    local replace = Lists().replace[spec]
    return replace and replace.ess == true
end
rows[spec] = nil
Check(not Reorder(), "an edit on a spec without a profile row made Essential strict")
rows[spec] = true
Check(Reorder(), "an edit on a spec with a profile row no longer replaces raid essentials")

------------------------------------------------------------------ copies
-- A copy creates the other spec's list; it inherits Suite defaults only
-- where that spec has them.
local others = {}
for _, id in ipairs(Page.ClassSpecs({})) do if id ~= spec then others[#others + 1] = id end end
assert(#others > 0, "the fixture class needs a second specialization")
local function CopyInherits(key)
    Reset()
    assert(Page.AddEntry("uti", key, CDM.FAMILY.COOLDOWN))
    assert(Page.CopyToSpecs("uti", key))
    local list = Lists().specs[others[1]]
    return list and list.uti and list.uti.inherit == true
end
rows[spec], rows[others[1]] = true, nil
Check(not CopyInherits("s133"), "a copy to a spec without a profile row inherited spec defaults")
rows[others[1]] = true
Check(CopyInherits("s133"), "a copy to a spec with a profile row no longer inherits its defaults")
Reset()

print("CDM lists profile row: " .. checks .. " checks passed")
