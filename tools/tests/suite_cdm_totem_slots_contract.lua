local root = assert(arg[1], "repository root required")
-- Totem slots (EntryFill's t<slot> entries, Index's slot routing) on the
-- shared data world, Retail and WoW Forever. A user adds a totem slot to a
-- cooldown bar from the picker; the entry shows whatever totem, statue or
-- summon the game puts in that slot, of any spell and any rank. This
-- contract holds:
--   * the keys t1..t8 are valid cooldown entries, t0 and t9 are not, and
--     equipment slot keys keep their 1..19 range;
--   * a totem entry has no spell, item or category, hides while its slot is
--     empty (hideEmpty) and is known while the character has the slot;
--   * Retail names every slot by number, also for a Shaman; WoW Forever
--     names a Shaman's slots by element from the client's own
--     FIRE_TOTEM_SLOT, EARTH_, WATER_ and AIR_TOTEM_SLOT, other classes' by
--     number;
--   * equipment slots go by the client's own slot names, the rings numbered,
--     trinkets and unnamed slots as the catalog names them;
--   * a listed totem slot is built into its bar and routed by its slot only:
--     never into the cooldown, charge, bag, item, usable or ready lists, so
--     no spell, bag or icon event reaches it; an unreadable slot payload
--     reaches every totem entry.
local World = dofile(root .. "/tools/tests/cdm_data_world.lua")
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end
local SLOTS = 4
GetTotemDuration = function() return {} end
GetNumTotemSlots = function() return SLOTS end

local function Load(forever, class)
    local W = World(root)
    if forever then W.NS.Client.isForever = true end
    UnitClass = function() return class, class, 7 end
    -- EntryFill reads the client and the element slots when it loads.
    assert(loadfile(root .. "/MSUF_Suite_CooldownManager/EntryFill.lua"))("MSUF_Suite_CooldownManager", W.P)
    for _, file in ipairs({ "Resolve.lua", "ResolveStages.lua", "Index.lua" }) do
        assert(loadfile(root .. "/MSUF_Suite_CooldownManager/" .. file))("MSUF_Suite_CooldownManager", W.P)
    end
    return W
end

------------------------------------------------------------------ keys
do
    local W = Load(false, "SHAMAN")
    local CDM, Fill = W.CDM, W.C.EntryFill
    for slot = 1, 8 do Check(CDM.ValidEntryKey("t" .. slot), "t" .. slot .. " is a key") end
    Check(not CDM.ValidEntryKey("t0") and not CDM.ValidEntryKey("t9") and CDM.ValidEntryKey("e19")
        and not CDM.ValidEntryKey("e20"), "totem keys stop at 8, equipment keys at 19")
    Check(Fill.FamilyOf("t3") == W.C.Const.FAMILY.COOLDOWN, "a totem slot belongs on cooldown bars")
end

------------------------------------------------------------------ Retail entries and names
do
    local W = Load(false, "SHAMAN")
    local C, Fill = W.C, W.C.EntryFill
    local entry = {}
    Check(Fill.Fill(entry, "t1") and entry.src == "t" and entry.id == 1 and entry.family == C.Const.FAMILY.COOLDOWN,
        "a totem slot fills")
    Check(entry.spell == nil and entry.base == nil and entry.itemID == nil and entry.spellCategory == nil and entry.auraIDs == nil,
        "a totem slot has no spell, item or category")
    Check(entry.hideEmpty == true and entry.known == true and entry.texture == Fill.TOTEM_ICON and Fill.TOTEM_ICON == 136099,
        "a totem slot hides while empty and shows the totem icon")
    Check(entry.name == "Totem slot 1" and Fill.TotemLabel(2) == "Totem slot 2", "Retail names a Shaman's slots by number")
    Check(Fill.Fill(entry, "t5") and entry.known == false, "a slot the character does not have is not known")
    -- Equipment slots: the client's names, rings numbered, trinkets as the catalog.
    HANDSSLOT, BACKSLOT = "Hands", "Back"
    Check(Fill.SlotLabel(10) == "Hands" and Fill.SlotLabel(15) == "Back", "slots by the client's own names")
    Check(Fill.SlotLabel(11) == "Ring 1" and Fill.SlotLabel(12) == "Ring 2", "rings are numbered")
    Check(Fill.SlotLabel(13) == "Trinket 1" and Fill.SlotLabel(2) == "Equipment slot 2", "trinkets and unnamed slots")
    HANDSSLOT, BACKSLOT = nil, nil
    -- The client's names are read once (they never change while it runs).
    Check(Fill.Fill(entry, "e10") and entry.name == "Hands", "an empty hand slot keeps its name")
end

------------------------------------------------------------------ WoW Forever names
do
    FIRE_TOTEM_SLOT, EARTH_TOTEM_SLOT, WATER_TOTEM_SLOT, AIR_TOTEM_SLOT = 1, 2, 3, 4
    local W = Load(true, "SHAMAN")
    local Fill = W.C.EntryFill
    Check(Fill.TotemLabel(1) == "Fire totem" and Fill.TotemLabel(2) == "Earth totem" and Fill.TotemLabel(3) == "Water totem"
        and Fill.TotemLabel(4) == "Air totem", "Forever names a Shaman's slots by element")
    local entry = {}
    Check(Fill.Fill(entry, "t4") and entry.name == "Air totem", "the entry carries the element")
    W = Load(true, "PALADIN")
    Check(W.C.EntryFill.TotemLabel(1) == "Totem slot 1", "other Forever classes name slots by number")
    EARTH_TOTEM_SLOT, FIRE_TOTEM_SLOT = 1, 2
    W = Load(true, "SHAMAN")
    Check(W.C.EntryFill.TotemLabel(1) == "Earth totem" and W.C.EntryFill.TotemLabel(2) == "Fire totem",
        "the element order is the client's, not ours")
    FIRE_TOTEM_SLOT, EARTH_TOTEM_SLOT, WATER_TOTEM_SLOT, AIR_TOTEM_SLOT = nil, nil, nil, nil
end

------------------------------------------------------------------ build and routing
do
    local W = Load(false, "SHAMAN")
    local C, CDM = W.C, W.CDM
    local Resolve, Index = C.Resolve, C.Index
    W.Views()
    W.infos[11] = { cooldownID = 11, spellID = 5011, linkedSpellIDs = {}, selfAura = false, hasAura = false, charges = false,
        isKnown = true, isInvisible = false, flags = 0, category = 0 }
    W.sets[0], W.known[5011] = { 11 }, true
    local lists = CDM.CleanLists(nil)
    lists.specs[63] = { ess = { "b11", "t1", "t2", "t9" } }
    C.lists, C.state.specID, C.state.specTag = lists, 63, "63"
    C.Catalog.Rebuild()
    Resolve.Build()
    Index.Rebuild()
    local keys = {}
    for i, entry in ipairs(C.plans.ess.entries) do keys[i] = entry.key end
    Check(table.concat(keys, ",") == "b11,t1,t2", "listed totem slots build into their bar: " .. table.concat(keys, ","))
    local t1, t2 = C.entries.t1, C.entries.t2
    Check(#Index.totems == 2 and Index.byTotem[1][1] == t1 and #Index.byTotem[1] == 1 and Index.byTotem[2][1] == t2,
        "totem entries route by their slot")
    for _, name in ipairs({ "cooldown", "charged", "bags", "items", "usable", "ready", "gcd", "counted", "ranged", "proc", "assist" }) do
        for _, entry in ipairs(Index[name]) do
            Check(entry.src ~= "t", "a totem slot stays out of the " .. name .. " list")
        end
    end
    for _, list in pairs(Index.bySpell) do
        for _, entry in ipairs(list) do Check(entry.src ~= "t", "no spell routes to a totem slot") end
    end
    local seen = {}
    local function Hit(entry) seen[#seen + 1] = entry.key end
    Check(Index.ForTotem(2, Hit) == 1 and seen[1] == "t2", "a slot payload reaches that slot's entries")
    Check(Index.ForTotem(3, Hit) == 0 and #seen == 1, "an unused slot reaches nothing")
    Check(Index.ForTotem(W.Secret(), Hit) == 2 and seen[2] == "t1" and seen[3] == "t2", "an unreadable slot reaches every totem")
    Check(Index.ForTotem(nil, Hit) == 2, "an absent slot reaches every totem")
    lists.specs[63] = { ess = { "b11" } }
    C.lists = lists
    Resolve.Build()
    Index.Rebuild()
    Check(#Index.totems == 0 and next(Index.byTotem) == nil and not C.entries.t1, "a removed totem slot leaves every list")
end

print(("CDM totem slots: %d checks passed (keys, entries, Retail and Forever names, slot routing)"):format(checks))
