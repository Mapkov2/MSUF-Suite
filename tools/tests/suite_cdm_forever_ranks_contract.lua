local root = assert(arg[1], "repository root required")
-- WoW Forever spell ranks (RankData.lua, EntryFill.lua's C.Ranks, Catalog,
-- Resolve and Index on the shared data world). Every rank is a spell of its
-- own, and Rogues and Warriors unlearn a rank when they learn the next one.
-- This contract holds:
--   * Retail has no families and every rank function answers as before;
--   * RankData.lua (Enhance QoL's list) loads on Forever only: every family
--     starts with its key and no rank is in two families;
--   * the learned rank is the highest one the player's (else the pet's)
--     spell book knows, kept until Resolve.SpellsChanged;
--   * a saved key of any rank keeps its key and reads the learned rank, and
--     follows a rank-up (the refill compare asks for a build in combat);
--   * Blizzard's record of an unlearned first rank reads the learned rank,
--     also after an override event without Blizzard's own override;
--   * every rank routes to the entry, an aura entry matches every rank's
--     aura, and a preset rank finds Blizzard's record of another rank;
--   * ForeverPresets.lua (Enhance QoL's Forever data) replaces the Retail
--     Defensives, picker groups and racials on Forever and adds mana potion,
--     other potion and bandage families after the Healthstone and the
--     health potion on Potions and racials; Retail keeps its lists;
--   * an unlearned Blizzard record of a spell the client lacks (no name, no
--     icon: Forever's Retail rows) stays out of the previews and the picker,
--     while an unlearned record of a spell the client has still shows there.
local World = dofile(root .. "/tools/tests/cdm_data_world.lua")
local DATA = { "RankData.lua", "ForeverPresets.lua", "Presets.lua", "GuideProfiles.lua", "Catalog.lua", "CatalogSlices.lua",
    "EntryFill.lua", "Resolve.lua", "ResolveStages.lua", "Index.lua" }
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end
local function Info(id, category, spell, known, flags)
    return { cooldownID = id, spellID = spell, linkedSpellIDs = {}, selfAura = false, hasAura = false, charges = false,
        isKnown = known ~= false, isInvisible = false, flags = flags or 0, category = category }
end
local function Keys(entries)
    local out = {}
    for i = 1, #entries do out[i] = entries[i].key end
    return table.concat(out, ",")
end
local function Has(list, value)
    for i = 1, #(list or {}) do
        if list[i] == value then return true end
    end
    return false
end
-- The player's and the pet's spell books (W.known, W.pet), read the way
-- Enhance QoL reads them (C_SpellBook.IsSpellKnown with a bank).
local function Load(forever)
    local W = World(root)
    W.pet = {}
    C_SpellBook.IsSpellKnown = function(id, bank)
        if bank == Enum.SpellBookSpellBank.Pet then return W.pet[id] == true end
        return W.known[id] == true
    end
    if forever then
        W.NS.Client.isForever = true
        W.infos[101], W.sets[0] = Info(101, 0, 5001), { 101 }
        for _, file in ipairs(DATA) do
            assert(loadfile(root .. "/MSUF_Suite_CooldownManager/" .. file))("MSUF_Suite_CooldownManager", W.P)
        end
    end
    return W
end

------------------------------------------------------------------ Retail
do
    local W = Load(false)
    local C = W.C
    local Ranks, Fill = C.Ranks, C.EntryFill
    assert(loadfile(root .. "/MSUF_Suite_CooldownManager/RankData.lua"))("MSUF_Suite_CooldownManager", W.P)
    Check(C.RANK_FAMILIES == nil and Ranks.on == false, "Retail loads no rank families")
    W.known[1769] = true
    Check(Ranks.Canon(1768) == 1768 and Ranks.Family(1768) == nil and Ranks.Learned(1766) == nil
        and Ranks.Override(1766) == nil, "a Retail spell ID stands for itself")
    Check(Fill.KeySpell == Fill.BaseSpell and Fill.BaseSpell(1768) == 1768, "Retail keys and reads the base spell")
    local map = { [1767] = "b9" }
    Ranks.Claim(map, 1766, "b1")
    Ranks.Claim(map, 1767, "b2")
    Check(map[1766] == "b1" and map[1767] == "b9" and map[1768] == nil, "a Retail claim takes the ID only, first claim wins")
    local set = Ranks.Expand({ [772] = true })
    Check(set[772] and next(set, 772) == nil and next(set) == 772, "a Retail aura set stays as listed")
    local name = C_Spell.GetSpellName
    C_Spell.GetSpellName = function(id) if id ~= 999001 then return name(id) end end
    Check(C.Catalog.Exists({ id = 304, spell = 999001, known = false }), "Retail keeps every unlearned record")
    C_Spell.GetSpellName = name
    local Presets = C.Presets
    Check(C.FOREVER_PRESETS == nil and Has(Presets.Defensives(4), 31224) and Has(Presets.Category("interrupts", 4), 1766)
        and #select(2, Presets.Category("offensive", 4, 260)) > 0 and Has(Presets.RACIALS, 58984),
        "Retail keeps its own preset lists")
    Check(#Presets.CONSUMABLES == 2 and Presets.CONSUMABLES[2].item == 224464 and next(Presets.STOCK) == nil,
        "Retail keeps its two Healthstones")
end

------------------------------------------------------------------ Forever: the list
local W = Load(true)
local C, NS = W.C, W.NS
local CDM = NS.CDM
local Ranks, Fill, Catalog, Resolve, Index = C.Ranks, C.EntryFill, C.Catalog, C.Resolve, C.Index
do
    Check(Ranks.on == true, "Forever loads the rank families")
    local count, owner = 0, {}
    for base, family in pairs(C.RANK_FAMILIES) do
        count = count + 1
        Check(family[1] == base and #family > 1, "family " .. base .. " starts with its key and has ranks")
        for i = 1, #family do
            local id = family[i]
            Check(type(id) == "number" and id > 0 and id % 1 == 0 and owner[id] == nil, "rank " .. tostring(id) .. " listed once")
            owner[id] = base
            Check(Ranks.Canon(id) == base and Ranks.Family(id) == family, "rank " .. id .. " finds its family")
        end
    end
    Check(count > 250, "Enhance QoL's families are all there: " .. count)
    Check(table.concat(Ranks.Family(1768), ",") == "1766,1767,1768,1769", "Kick's four ranks, first rank first")
    Check(table.concat(Ranks.Family(19647), ",") == "19244,19647", "a pet ability's ranks (Spell Lock)")
    Check(owner[99133] == nil and Ranks.Canon(99133) == 99133 and Ranks.Family(99133) == nil,
        "an ID outside every family stands for itself")
end

------------------------------------------------------------------ Forever: the presets
do
    local Presets, FOREVER = C.Presets, C.FOREVER_PRESETS
    Check(FOREVER and Presets.Defensives(4) == FOREVER.defensives[4] and Has(Presets.Defensives(4), 5277)
        and not Has(Presets.Defensives(4), 31224), "Forever's Defensives default is its own list")
    local byClass, bySpec = Presets.Category("interrupts", 4, 260)
    Check(byClass == FOREVER.interrupts[4] and Has(byClass, 1766) and #bySpec == 0, "the picker groups by class only")
    for _, name in ipairs(Presets.CATEGORY_ORDER) do
        Check(Presets.CATEGORY_CLASS[name] == (FOREVER[name] or C.EMPTY), "group " .. name .. " is Forever's")
    end
    Check(Presets.RACIALS == FOREVER.racials and Has(Presets.RACIALS, 20600) and Has(Presets.RACIALS, 1259718)
        and Has(Presets.RACIALS, 1259823) and not Has(Presets.RACIALS, 58984), "Forever's racials are its own list")
    -- Every listed cast ID is its spell's first rank.
    for _, name in ipairs(Presets.CATEGORY_ORDER) do
        for _, list in pairs(FOREVER[name]) do
            for _, id in ipairs(list) do Check(Ranks.Canon(id) == id, name .. " lists the first rank of " .. id) end
        end
    end
    for _, id in ipairs(FOREVER.racials) do Check(Ranks.Canon(id) == id, "racials list the first rank of " .. id) end
    -- Potions and racials: the Healthstone and the health potion, then the
    -- mana potions, the other potions and the bandages, each one family.
    local K, Catalog = C.Const.SPELL_CATEGORY, C.Catalog
    local FAMILIES = { { 5512, K.HEALTHSTONE }, { 118, K.HEALTH_POTION }, { 2455, K.MANA_POTION, FOREVER.manaPotions },
        { 2459, K.FOREVER_COMBAT_POTION, FOREVER.combatPotions }, { 1251, K.BANDAGE, FOREVER.bandages } }
    Check(#Presets.CONSUMABLES == #FAMILIES, "Forever has five consumable families")
    local seen = {}
    for i, family in ipairs(FAMILIES) do
        local consumable = Presets.CONSUMABLES[i]
        local items = Presets.CATEGORY_ITEMS[family[2]]
        Check(consumable.item == family[1] and consumable.category == family[2] and items[1] == family[1]
            and Presets.STOCK[family[1]] == family[2] and (family[3] == nil or items == family[3]),
            "consumable family " .. i .. " is item " .. family[1])
        for _, item in ipairs(items) do
            Check(not seen[item], "item " .. item .. " is in one family")
            seen[item] = true
        end
    end
    Check(K.MANA_POTION < 0 and K.FOREVER_COMBAT_POTION < 0 and K.BANDAGE < 0, "the Suite's own categories are negative")
    Check(Catalog.ItemName(2455) == "Mana potion" and Catalog.ItemName(2459) == "Combat potion"
        and Catalog.ItemName(1251) == "Bandage", "the new families go by their titles")
    Check(Has(FOREVER.combatPotions, 13442) and not Has(FOREVER.combatPotions, 13446) and not Has(FOREVER.combatPotions, 13444)
        and Has(FOREVER.manaPotions, 13444) and Has(FOREVER.bandages, 14530), "each potion is in its own family")
end

------------------------------------------------------------------ Forever: the learned rank
do
    -- A Rogue with Kick rank 4: rank 1 is unlearned.
    W.known = { [1769] = true }
    Resolve.SpellsChanged()
    Check(Ranks.Learned(1766) == 1769 and Ranks.Learned(1767) == 1769, "the highest learned rank stands for the family")
    Check(Ranks.Override(1766) == 1769 and Ranks.Override(1769) == nil, "an entry of rank 1 follows rank 4")
    Check(Fill.Known(1766) == true, "the family is known while any rank is")
    Check(Fill.KeySpell(1768) == 1766 and Fill.BaseSpell(1768) == 1769, "keys take the first rank, reads the learned one")
    -- Kept until the spell book may have changed.
    W.known = { [1768] = true }
    Check(Ranks.Learned(1766) == 1769, "the learned rank is kept until the spell book changes")
    Resolve.SpellsChanged()
    Check(Ranks.Learned(1766) == 1768, "Resolve.SpellsChanged reads the spell book again")
    -- The pet's book after the player's (Spell Lock is the Felhunter's).
    W.pet[19647] = true
    Resolve.SpellsChanged()
    Check(Ranks.Learned(19244) == 19647 and Fill.Known(19244) == true, "a pet ability's rank comes from the pet's book")
    -- Nothing learned: the family keys and reads its first rank, unknown.
    Check(Ranks.Learned(1752) == nil and Fill.BaseSpell(1757) == 1752 and Fill.Known(1757) == false,
        "an unlearned family reads its first rank and is unknown")
end

------------------------------------------------------------------ Forever: spell and aura entries
do
    -- A Sinister Strike key saved at rank 2 while the Rogue knows rank 5.
    W.known = { [1760] = true }
    Resolve.SpellsChanged()
    local entry = { key = "s1757" }
    Check(Fill.Fill(entry, "s1757"), "a saved rank fills")
    Check(entry.key == "s1757" and entry.id == 1757 and entry.base == 1760 and entry.spell == 1760 and entry.known == true,
        "a saved rank keeps its key and reads the learned rank")
    W.known = { [8621] = true }
    Resolve.SpellsChanged()
    Check(Fill.Fill(entry, "s1757") and entry.base == 8621 and entry.spell == 8621 and entry.known == true,
        "it follows the next rank-up")
    -- An aura: Rend rank 7 carries 11574.
    W.known = {}
    Resolve.SpellsChanged()
    local rend = { key = "d772" }
    Check(Fill.Fill(rend, "d772"), "a debuff key fills")
    local family = Ranks.Family(772)
    for i = 1, #family do Check(rend.auraIDs[family[i]], "the debuff matches rank " .. family[i]) end
    local fireball = { key = "a99133" }
    Check(Fill.Fill(fireball, "a99133") and fireball.auraIDs[99133] and next(fireball.auraIDs, 99133) == nil
        and next(fireball.auraIDs) == 99133, "an aura outside every family keeps its one ID")
end

------------------------------------------------------------------ Forever: Blizzard's records, routing and presets
W.Views()
W.classID = 8
C.state.specID = 63
-- Blizzard's Kick record names rank 1, its Ice Barrier record rank 3.
-- Perception (the Human racial) is a Utility record hidden by default.
W.infos[301], W.infos[302], W.infos[303] = Info(301, 0, 1766), Info(302, 1, 13032), Info(303, 1, 20600, true, 2)
W.sets[0], W.sets[1] = { 101, 301 }, { 302, 303 }
W.known = { [1769] = true, [1760] = true, [13033] = true, [20600] = true }
Resolve.SpellsChanged()
Check(Catalog.Ready() and Catalog.Rebuild() == true, "the catalog reads")
C.views.c1.on = true
C.lists = CDM.CleanLists({ specs = { [63] = { c1 = { "b301", "s1757" } } } })
local plans = Resolve.Build()
local E = C.entries
do
    Check(plans.c1 and Keys(plans.c1.entries) == "b301,s1757", "the custom bar: " .. (plans.c1 and Keys(plans.c1.entries) or "none"))
    local kick, strike = E.b301, E.s1757
    Check(kick.base == 1766 and kick.override == 1769 and kick.spell == 1769, "Blizzard's rank 1 record reads rank 4")
    Check(strike.base == 1760 and strike.spell == 1760, "the saved rank reads the learned one")
    Index.Rebuild()
    for _, id in ipairs(Ranks.Family(1766)) do Check(Has(Index.bySpell[id], kick), "Kick rank " .. id .. " routes to the entry") end
    for _, id in ipairs(Ranks.Family(1752)) do
        Check(Has(Index.bySpell[id], strike), "Sinister Strike rank " .. id .. " routes to the entry")
    end
    local calls = 0
    Index.ForSpell(1768, nil, function(entry) calls = calls + (entry == kick and 1 or 0) end)
    Check(calls == 1, "an event of another rank reaches the entry once")
    -- Blizzard's override wins; without one the entry keeps the learned rank.
    Catalog.OnOverride(1766, 1768)
    Check(kick.spell == 1768 and kick.override == 1768, "Blizzard's own override wins")
    Catalog.OnOverride(1766, nil)
    Check(kick.spell == 1769 and kick.override == 1769, "without Blizzard's override the learned rank comes back")
    Check(Catalog.OnOverride(1766, nil) == false, "an unchanged override event changes nothing")
    -- Potions and racials: the five families, then the racial's record.
    Check(plans.ext and Keys(plans.ext.entries) == "i5512,i118,i2455,i2459,i1251,b303",
        "Potions and racials: " .. (plans.ext and Keys(plans.ext.entries) or "no bar"))
    -- Ice Barrier (the Mage's Defensives preset 11426, rank 1) finds
    -- Blizzard's rank 3 record.
    local defensives = plans.def and Keys(plans.def.entries) or "no bar"
    Check(("," .. defensives .. ","):find(",b302,", 1, true) and E.s11426 == nil,
        "the Defensives preset takes Blizzard's Ice Barrier record: " .. defensives)
end
-- Forever lists Retail rows on Potions and racials whose spell it lacks: no
-- name and no icon. Unlearned, they stay out of the preview and the picker
-- (a question mark and "b200345" before); an unlearned real spell stays in.
do
    local name, texture = C_Spell.GetSpellName, C_Spell.GetSpellTexture
    C_Spell.GetSpellName = function(id) if id ~= 999001 then return name(id) end end
    C_Spell.GetSpellTexture = function(id) if id ~= 999001 then return texture(id) end end
    W.infos[304], W.infos[305] = Info(304, 5, 999001, false), Info(305, 5, 9484, false)
    W.sets[5] = { 304, 305 }
    Check(Catalog.Rebuild() == true, "the Potions rows arrive")
    C.state.preview = true
    local preview = Resolve.Build()
    local keys = "," .. Keys(preview.ext.entries) .. ","
    Check(not keys:find(",b304,", 1, true) and keys:find(",b305,", 1, true), "the preview leaves out the void row only: " .. keys)
    local listed = {}
    for _, row in ipairs(Catalog.List(1)) do listed[row.key] = true end
    Check(not listed.b304 and listed.b305 and listed.b301, "the picker leaves out the void row only")
    Check(not Catalog.Exists(C.Catalog.records[304]) and Catalog.Exists(C.Catalog.records[305]), "Catalog.Exists tells them apart")
    W.infos[304].isKnown = true
    Check(Catalog.Rebuild() == true and Catalog.Exists(C.Catalog.records[304]), "a learned record always counts")
    C.state.preview = false
    W.infos[304], W.infos[305], W.sets[5] = nil, nil, nil
    C_Spell.GetSpellName, C_Spell.GetSpellTexture = name, texture
    Check(Catalog.Rebuild() == true, "the rows leave again")
    plans = Resolve.Build()
end
-- A rank-up in combat asks for a build; an unchanged spell book does not.
do
    W.combat = true
    Check(Resolve.SpellsChanged() == true and Resolve.RefillChanged() == false, "an unchanged spell book needs no build")
    W.known[1760], W.known[8621] = nil, true
    Check(Resolve.SpellsChanged() == true and Resolve.RefillChanged() == true, "a rank-up in combat asks for a build")
    W.combat = false
    Resolve.SpellsChanged()
    plans = Resolve.Build()
    Check(E.s1757.base == 8621 and E.s1757.spell == 8621, "the build reads the new rank")
end

print(("CDM Forever spell ranks: %d checks passed"):format(checks))
