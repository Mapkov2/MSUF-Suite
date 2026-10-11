local root = assert(arg[1])
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
local lists = CDM.CleanLists({ specs = {
    [62] = { ess = { "s133" } }, [266] = { ess = { "s1459", "s122" } },
    [267] = { ess = { "s382440" } },
} })
local spells = CDM.CleanSpells({ e = { s1459 = { icon = 1002 } }, s = { [62] = { s133 = { icon = 1001 } } } })
assert(S.SetMany(ID, { listsData = assert(CDM.Codec.EncodeLists(lists)), spellsData = assert(CDM.Codec.EncodeSpells(spells)) }))
S.CooldownManagerEditorContext = function(spec, classID)
    local config = S.Config(ID)
    local data = CDM.Codec.DecodeLists(config.listsData)
    local rows = {}
    for _, key in ipairs(data.specs[spec] and data.specs[spec].ess or {}) do
        rows[#rows + 1] = {key=key,name=key,texture=1002,family=1,known=true}
    end
    return { spec=spec,classID=classID,bars={ess=rows},choices=CDM.EffectiveSpells(CDM.Codec.DecodeSpells(config.spellsData),spec) }
end
local player = Page.PlayerSpec()
local before = S.Config(ID).listsData
assert(Page.SelectSpec(266))
assert(Page.Spec() == 266 and Page.PlayerSpec() == player and Page.spellSpecScope,
    "editor target changed the player or retained shared override scope")
assert(S.Config(ID).listsData == before, "selection changed saved lists")
assert(Page.Entries("ess")[1].key == "s1459", "editor read the current player's rows")
assert(Page.MoveEntry("s122", "ess", "s1459", 1))
local changed = CDM.Codec.DecodeLists(S.Config(ID).listsData)
assert(changed.specs[266].ess[1] == "s122" and changed.specs[62].ess[1] == "s133"
    and changed.specs[267].ess[1] == "s382440", "reorder escaped its selected spec")
assert(Page.SetSpellField("s1459", "icon", 9999))
local changedSpells = CDM.Codec.DecodeSpells(S.Config(ID).spellsData)
assert(changedSpells.s[266].s1459.icon == 9999 and changedSpells.e.s1459.icon == 1002
    and changedSpells.s[62].s133.icon == 1001, "spell write escaped its selected spec")
local imported = false
local oldImport = S.CooldownManagerBlizzardSnapshot
S.CooldownManagerBlizzardSnapshot = function() imported = true; return {} end
assert(not Page.ImportBlizzard() and not imported, "foreign import read the current player's Blizzard data")
S.CooldownManagerBlizzardSnapshot = oldImport
local focusedSpec
local input = { HasFocus=function() return focusedSpec == nil end, ClearFocus=function() focusedSpec=Page.Spec() end }
Page.inputs[#Page.inputs + 1] = input
Page.Note("test", function() error("stale undo") end)
assert(Page.SelectSpec(267) and focusedSpec == 266 and Page.undo == nil,
    "scope switch did not finish the old input and discard its undo")
local config = S.Config(ID)
local firstLists = config.listsData
assert(Suite.Database.Create("CDM target test", true))
assert(Suite.Database.Activate("CDM target test"))
assert(Page.SelectSpec(266))
assert(Page.AddEntry("ess", "s382440", 1))
assert(S.Config(ID) ~= config and config.listsData == firstLists,
    "editing another profile changed the previous profile")
local current = Suite.Database.GetActiveProfileName()
MSUF_GlobalDB = MSUF_GlobalDB or {}
MSUF_GlobalDB.char = {
    ["Warlock-Realm"]={activeProfile=current,specProfileMap={[266]=current,[267]="Other"}},
    ["Unknown-Realm"]={activeProfile=current},
    ["Rogue-Realm"]={activeProfile="Other",specProfileMap={[259]="Other"}},
}
local chars = Suite.HostBridge.ProfileCharacters(current)
assert(#chars == 2 and chars[1].name == "Unknown-Realm" and chars[2].spec == 266,
    "character shortcuts leaked another profile or invented a specialization")
assert(not Page.SelectSpec(99999), "invalid target was accepted")
assert(Page.SelectSpec(nil) and Page.Spec() == player, "return to current character retained a foreign spec")
print("CDM editor targets: profile/spec isolation, real list reorder and spell overrides, input/undo scope, import refusal and character assignments passed")
