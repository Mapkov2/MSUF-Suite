local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- What one entry key stands for: the key parsed once per string, plain
-- spell lookups, and the fill of an entry table per source (a Blizzard
-- record, a spell, an item, an equipment slot, a custom aura) from
-- read-only APIs and the catalog. Resolve.lua builds the bars' plans from
-- these and Exports.lua describes keys for the options page. Cold path.
local Public = S.Public
local type, tonumber = type, tonumber
local EMPTY = C.EMPTY
local wipe = C.wipe
local CDM = NS.CDM
local Catalog = C.Catalog
local Num = Catalog.Num
local EntryFill = {}
C.EntryFill = EntryFill

-- Healthstones (Presets.CONSUMABLES): their item entries and Blizzard's
-- records of their categories hide while the bags hold none (hideEmpty,
-- read by Time). Potion categories never hide: their item lists may miss a
-- rank.
local CONSUMABLES = C.Presets.CONSUMABLES
local hideItem, hideCategory = {}, {}
for i = 1, #CONSUMABLES do
    hideItem[CONSUMABLES[i].item], hideCategory[CONSUMABLES[i].category] = true, true
end
local SOURCE_FAMILY = { s = 1, i = 1, e = 1, a = 2, d = 2 }

-- Keys are parsed once per distinct string.
local srcOf, idOf = {}, {}
local function Parse(key)
    local src = srcOf[key]
    if src == nil then
        src = false
        if type(key) == "string" and CDM.ValidEntryKey(key) then src, idOf[key] = key:sub(1, 1), tonumber(key:sub(2)) end
        srcOf[key] = src
    end
    return src, idOf[key]
end
local function FamilyOf(key)
    local src, id = Parse(key)
    if src == "b" then
        local rec = Catalog.records[id]
        return rec and rec.family
    end
    return src and SOURCE_FAMILY[src] or nil
end

------------------------------------------------------------------ plain lookups
local function HasRange(spell)
    local result = spell and C_Spell.SpellHasRange(spell)
    return Public(result) and result == true
end
-- maxCharges is NeverSecret; checked anyway.
local function Charged(spell)
    local info = spell and C_Spell.GetSpellCharges(spell)
    if not (Public(info) and type(info) == "table") then return false end
    local max = info.maxCharges
    return Public(max) and type(max) == "number" and max > 1
end
-- The player's spell book, then the pet's.
local function Known(spell)
    local check = C_SpellBook.IsSpellKnownOrInSpellBook
    local known = check(spell)
    if Public(known) and known == true then return true end
    known = check(spell, Enum.SpellBookSpellBank.Pet)
    return Public(known) and known == true
end
local function BaseSpell(id)
    return Num(C_Spell.GetBaseSpell(id)) or id
end
local function OverrideOf(base)
    local id = Num(C_SpellBook.FindSpellOverrideByID(base))
    if id and id ~= base then return id end
end

------------------------------------------------------------------ entry fill
local function SetOverride(entry, override)
    if entry.override ~= override then
        entry.prevOverride = entry.override
        entry.override = override
    end
end
local function AuraSet(set, a, b, c, linked)
    if set then
        wipe(set)
    else
        set = {}
    end
    if a then set[a] = true end
    if b then set[b] = true end
    if c then set[c] = true end
    if linked then
        for i = 1, #linked do
            set[linked[i]] = true
        end
    end
    return set
end
-- Resets the source fields; auraIDs is left for the caller so its table is reused.
local function Clear(entry, src, id, family)
    entry.src, entry.id, entry.family, entry.category = src, id, family, nil
    entry.selfAura, entry.hasAura, entry.charges, entry.hasRange = false, false, false, false
    entry.equipSlot, entry.itemID, entry.spellCategory, entry.tooltip = nil, nil, nil, nil
    entry.linked, entry.unit, entry.hideEmpty = EMPTY, nil, false
end

-- The unit a Blizzard aura entry is looked for on: the target when any of its
-- aura IDs is a harmful spell (a DoT, Deathstalker's Mark), else the player
-- (a buff). Blizzard's selfAura flag is not used for aura lookups by
-- Blizzard itself. Cold: cached per spell ID.
local harmfulCache = {}
local function Harmful(id)
    if not id then return false end
    local known = harmfulCache[id]
    if known ~= nil then return known end
    local result = C_Spell.IsSpellHarmful(id)
    known = Public(result) and result == true or false
    harmfulCache[id] = known
    return known
end
local function AuraUnit(base, override, tooltip, linked)
    if Harmful(base) or Harmful(override) or Harmful(tooltip) then return "target" end
    for i = 1, #(linked or EMPTY) do
        if Harmful(linked[i]) then
            return "target"
        end
    end
    return "player"
end
-- Per-spell "Track on" (auraUnit): 2 me, 3 target, 4 both.
local AURA_UNIT = { nil, "player", "target", "both" }

local function FillBlizzard(entry, rec)
    local base, override, family = rec.spell, rec.override, rec.family
    Clear(entry, "b", rec.id, family)
    SetOverride(entry, override)
    entry.base, entry.tooltip, entry.spell, entry.linked, entry.category = base, rec.tooltip, override or base, rec.linked, rec.category
    entry.selfAura, entry.hasAura, entry.charges, entry.known = rec.selfAura, rec.hasAura, rec.charges, rec.known
    entry.equipSlot, entry.spellCategory, entry.hideEmpty = rec.equipSlot, rec.spellCategory, hideCategory[rec.spellCategory] == true
    entry.itemID = rec.equipSlot and Catalog.EquipItem(rec.equipSlot) or nil
    entry.hasRange = family == 1 and base ~= nil and HasRange(base)
    entry.texture, entry.name = Catalog.RecordTexture(rec), Catalog.RecordName(rec)
    if family == 2 or rec.hasAura then
        entry.auraIDs = AuraSet(entry.auraIDs, base, override, rec.tooltip, rec.linked)
        entry.unit = AuraUnit(base, override, rec.tooltip, rec.linked)
    else
        entry.auraIDs = nil
    end
    return true
end
local function FillSpell(entry, id)
    local name = Catalog.SpellName(id)
    if not name then return false end
    local base = BaseSpell(id)
    local override = OverrideOf(base)
    local spell = override or base
    Clear(entry, "s", id, 1)
    SetOverride(entry, override)
    entry.base, entry.spell = base, spell
    entry.charges, entry.known, entry.hasRange = Charged(spell), Known(base), HasRange(base)
    entry.texture, entry.name = Catalog.SpellTexture(base), Catalog.SpellName(spell) or name
    entry.auraIDs = nil
    return true
end
local function FillItem(entry, id)
    local icon = Catalog.ItemIcon(id)
    if not icon then return false end
    local spell = Catalog.ItemSpell(id)
    Clear(entry, "i", id, 1)
    SetOverride(entry, nil)
    entry.base, entry.spell, entry.itemID, entry.known, entry.hideEmpty = spell, spell, id, true, hideItem[id] == true
    entry.texture, entry.name = icon, Catalog.ItemName(id)
    entry.auraIDs = nil
    return true
end
local function FillEquip(entry, slot)
    local item = Catalog.EquipItem(slot)
    local spell = item and Catalog.ItemSpell(item) or nil
    Clear(entry, "e", slot, 1)
    SetOverride(entry, nil)
    entry.base, entry.spell, entry.equipSlot, entry.itemID, entry.known = spell, spell, slot, item, item ~= nil
    entry.texture = Catalog.EquipTexture(slot)
    entry.name = item and Catalog.ItemName(item) or Catalog.SlotLabel(slot)
    entry.auraIDs = nil
    return true
end
local function FillAura(entry, src, id)
    local name, texture = Catalog.SpellName(id), Catalog.SpellTexture(id)
    if not (name or texture) then return false end
    Clear(entry, src, id, 2)
    SetOverride(entry, nil)
    entry.base, entry.spell, entry.known = id, id, true
    entry.selfAura, entry.hasAura = src == "a", true
    entry.texture, entry.name = texture, name
    entry.auraIDs = AuraSet(entry.auraIDs, id)
    entry.unit = src == "a" and "player" or "target"
    return true
end
local function Fill(entry, key)
    local src, id = Parse(key)
    if src == "b" then
        local rec = Catalog.records[id]
        return rec ~= nil and FillBlizzard(entry, rec)
    elseif src == "s" then
        return FillSpell(entry, id)
    elseif src == "i" then
        return FillItem(entry, id)
    elseif src == "e" then
        return FillEquip(entry, id)
    elseif src == "a" or src == "d" then
        return FillAura(entry, src, id)
    end
    return false
end

EntryFill.Parse, EntryFill.FamilyOf, EntryFill.Known, EntryFill.BaseSpell = Parse, FamilyOf, Known, BaseSpell
EntryFill.Fill, EntryFill.Clear, EntryFill.SetOverride, EntryFill.AURA_UNIT = Fill, Clear, SetOverride, AURA_UNIT
