local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Settings, spell lists and the Blizzard snapshot -> one plan per shown bar.
-- Rules: explicit list entries claim their key for the first bar that lists
-- them ("one spell, one home"); built-in bars use the current specialization's
-- stock categories for Suite profiles, or the saved Blizzard layout when that
-- mode is selected. Explicit legacy lists append new Blizzard entries; Suite
-- defaults and imported lists replace the built-in bar. Custom bars show their list only; an entry
-- of the wrong family for the bar is skipped. Entry tables are reused by key
-- so runtime fields (icon, cooling, glows) survive a rebuild. Cold path.
local Public = S.Public
local type, pairs, tonumber = type, pairs, tonumber
local EMPTY = C.EMPTY
local wipe = C.wipe
local CDM = NS.CDM
local SLOTS = CDM.SLOTS
local Catalog = C.Catalog
local Num = Catalog.Num

local Resolve = {}
C.Resolve = Resolve

-- Healthstones (Presets.CONSUMABLES): their item entries and Blizzard's
-- records of their categories hide while the bags hold none (hideEmpty,
-- read by Time). Potion categories never hide: their item lists may miss a
-- rank. Keys are built once.
local CONSUMABLES = C.Presets and C.Presets.CONSUMABLES or EMPTY
local consumableKeys, consumable, itemCategory, hideItem, hideCategory = {}, {}, {}, {}, {}
for i = 1, #CONSUMABLES do
    local item, category = CONSUMABLES[i].item, CONSUMABLES[i].category
    local key = "i" .. item
    consumableKeys[i], itemCategory[key] = key, category
    consumable[key], hideItem[item], hideCategory[category] = true, true, true
end

local KIND_FAMILY = { 1, 2, 2 }
local SOURCE_FAMILY = { s = 1, i = 1, e = 1, a = 2, d = 2 }
local PLACEHOLDER_TEXTURE, PLACEHOLDER_COUNT = 134400, 3
local placeholderKeys = {}
for i = 1, #SLOTS do
    local slot, keys = SLOTS[i].key, {}
    for n = 1, PLACEHOLDER_COUNT do keys[n] = "p" .. slot .. "_" .. n end
    placeholderKeys[slot] = keys
end

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
    local has = spell and C_Spell and C_Spell.SpellHasRange
    local result = has and has(spell)
    return Public(result) and result == true
end
-- maxCharges is NeverSecret; checked anyway.
local function Charged(spell)
    local get = spell and C_Spell and C_Spell.GetSpellCharges
    local info = get and get(spell)
    if not (Public(info) and type(info) == "table") then return false end
    local max = info.maxCharges
    return Public(max) and type(max) == "number" and max > 1
end
local function Known(spell)
    local book = C_SpellBook
    local check = book and (book.IsSpellKnownOrInSpellBook or book.IsSpellKnown)
    if not check then return true end
    local known = check(spell)
    if Public(known) and known == true then return true end
    local pet = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    if pet == nil then return false end
    known = check(spell, pet)
    return Public(known) and known == true
end
local function BaseSpell(id)
    local get = C_Spell and C_Spell.GetBaseSpell
    return get and Num(get(id)) or id
end
local function OverrideOf(base)
    local find = C_SpellBook and C_SpellBook.FindSpellOverrideByID
    local id = find and Num(find(base))
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
    local spell = C_Spell
    local check = spell and spell.IsSpellHarmful or IsHarmfulSpell
    local result = check and check(id)
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

------------------------------------------------------------------ presets
-- Preset rows (Presets.lua): spell IDs become the Blizzard entry that tracks
-- the spell when the catalog has one (base, override or linked ID), so the
-- row claims it off Essential/Utility; otherwise a plain spell entry. Built
-- again only when the catalog's content changed (Catalog.content).
-- Unlearned spells drop out in Materialize before anything is read.
-- presetSpell: plain spell keys that come only from a preset, with their
-- base spell; unlearned ones stay hidden even in previews (every race's
-- racial, other specs' spells).
-- The Potions and racials row starts with the Healthstones: each item key
-- stands in for Blizzard's record of its category while the catalog has no
-- learned one (covered: category -> the learned record with the lowest ID),
-- so the healthstone shows once; standIn maps such a category to its item
-- key, so an unlearned record never previews next to it.
local presetKeys, presetGen, presetSpec, presetRaid, presetSeen, spellKey, presetSpell = {}, nil, nil, nil, {}, {}, {}
local covered, standIn = {}, {}
local function Consumables(out)
    local n = 0
    for i = 1, #CONSUMABLES do
        local category = CONSUMABLES[i].category
        if not covered[category] then
            local key = consumableKeys[i]
            standIn[category] = key
            if not presetSeen[key] then
                presetSeen[key] = true
                n = n + 1
                out[n] = key
            end
        end
    end
    return n
end
local function PresetLists()
    local gen = Catalog.content
    local specID = C.state.specID
    local raid = C.state.raidEssentials ~= false
    if presetGen == gen and presetSpec == specID and presetRaid == raid then return presetKeys end
    presetGen, presetSpec, presetRaid = gen, specID, raid
    wipe(spellKey)
    wipe(presetSpell)
    wipe(covered)
    wipe(standIn)
    for _, rec in pairs(Catalog.records) do
        local category = rec.known and rec.spellCategory
        if category then
            local held = covered[category]
            if not held or rec.id < held.id then covered[category] = rec end
        end
        if rec.family == 1 then
            local key = rec.key
            if rec.spell and not spellKey[rec.spell] then spellKey[rec.spell] = key end
            if rec.override and not spellKey[rec.override] then spellKey[rec.override] = key end
            local linked = rec.linked
            for i = 1, #(linked or EMPTY) do
                if not spellKey[linked[i]] then
                    spellKey[linked[i]] = key
                end
            end
        end
    end
    local Presets = C.Presets
    for i = 1, #SLOTS do
        local def = SLOTS[i]
        local ids = Presets and (def.key == "ess" and raid
                and Presets.RaidEssentials and Presets.RaidEssentials(specID)
            or def.preset == "defensives" and Presets.Defensives()
            or def.preset == "racials" and Presets.RACIALS) or nil
        if ids then
            local out = presetKeys[def.key] or {}
            wipe(presetSeen)
            local n = def.preset == "racials" and Consumables(out) or 0
            for j = 1, #ids do
                local id = ids[j]
                local key = spellKey[id]
                if not key then
                    -- A replaced spell and its replacement share one entry.
                    local base = BaseSpell(id)
                    key = spellKey[base]
                    if not key then
                        key = "s" .. base
                        presetSpell[key] = base
                    end
                end
                if not presetSeen[key] then
                    presetSeen[key] = true
                    n = n + 1
                    out[n] = key
                end
            end
            for j = #out, n + 1, -1 do out[j] = nil end
            presetKeys[def.key] = out
        elseif def.key == "ess" then
            presetKeys.ess = nil
        end
    end
    return presetKeys
end
-- Whether the character knows a preset-only spell (every race's racial,
-- every spec's defensives): read once and kept until the spellbook may have
-- changed (Resolve.SpellsChanged, from the catalog and loading-screen
-- events). A module that is off gets no such events and reads live.
local presetKnown = {}
local function PresetKnown(key)
    local active = C.M.active == true
    local known
    if active then known = presetKnown[key] end
    if known == nil then
        known = Known(presetSpell[key])
        if active then presetKnown[key] = known end
    end
    return known
end
function Resolve.SpellsChanged() wipe(presetKnown) end

-- A healthstone has two keys, its item and Blizzard's record of its
-- category, and a user list can hold either (the page saves the keys a bar
-- shows). Both name the one that shows now: the learned record, else the
-- item that stands in for it. Claims and list places use this key, so the
-- healthstone keeps its list place and never shows twice. Needs PresetLists.
local function Canon(key)
    local category = itemCategory[key]
    if category then
        local rec = covered[category]
        return rec and rec.key or key
    end
    local src, id = Parse(key)
    if src == "b" then
        local rec = Catalog.records[id]
        local stand = rec and not rec.known and rec.spellCategory and standIn[rec.spellCategory]
        if stand then return stand end
    end
    return key
end

------------------------------------------------------------------ claims and collection
local claimed, used, keys, tmp, placed, planCache = {}, {}, {}, {}, {}, {}
-- usedSlot: equipment slots the bar being collected lists (e13). slotHome:
-- the bar that claimed each listed equipment slot, across all bars.
local usedSlot, slotHome = {}, {}

local function SpecData()
    local specID, lists = C.state.specID, C.lists
    local specLists, hidden, replaced = nil, EMPTY, EMPTY
    if specID ~= nil and type(lists) == "table" then
        local specs = lists.specs
        specLists = type(specs) == "table" and specs[specID] or nil
        if type(specLists) ~= "table" then specLists = nil end
        local h = type(lists.hidden) == "table" and lists.hidden[specID]
        if type(h) == "table" then hidden = h end
        local r = type(lists.replace) == "table" and lists.replace[specID]
        if type(r) == "table" then replaced = r end
    end
    return specLists, hidden, replaced
end
local function KindOf(i)
    local def = SLOTS[i]
    local view = C.views[def.key]
    return view and view.kind or def.kind or 1
end
-- The list a bar holds first: the user's list for this spec, then Suite
-- defaults for Essential, Utility, Defensives and both buff rows.
local function ListOf(i, specLists, presets)
    local def = SLOTS[i]
    local list = specLists and specLists[def.key]
    if type(list) == "table" then return list, true end
    if def.key == "ess" or def.preset == "defensives" then return presets[def.key], false end
    if C.state.raidEssentials ~= false then
        local defaults = Catalog.defaultByBar[def.key]
        if defaults then return defaults, false end
    end
end
local function ClaimList(list, slot, family)
    for j = 1, #list do
        local key = Canon(list[j])
        if claimed[key] == nil and FamilyOf(key) == family then
            claimed[key] = slot
            local src, id = Parse(key)
            if src == "e" and slotHome[id] == nil then slotHome[id] = slot end
        end
    end
end
-- A key is claimed by the first bar (menu order) whose list holds it and whose
-- kind can show it, so a bar switched to another kind releases its entries.
-- User lists claim first. Among Suite defaults, the dedicated Defensives row
-- owns its spells before stock/guide Essential and Utility categories do.
local function Claim(specLists, presets)
    wipe(claimed)
    wipe(slotHome)
    for pass = 1, 2 do
        if pass == 2 then
            local i = CDM.SLOT_INDEX.def
            local list, explicit = ListOf(i, specLists, presets)
            local view = C.views.def
            if list and not explicit and view and view.on then
                ClaimList(list, "def", KIND_FAMILY[KindOf(i)])
            end
        end
        for i = 1, #SLOTS do
            local def = SLOTS[i]
            local family = KIND_FAMILY[KindOf(i)]
            local list, explicit = ListOf(i, specLists, presets)
            if not (pass == 2 and def.preset == "defensives") and list and explicit == (pass == 1) then
                -- A preset only claims while its bar is shown; switched off,
                -- its spells go back to their Blizzard bars.
                local view = C.views[def.key]
                if explicit or (view and view.on) then ClaimList(list, def.key, family) end
            end
            if pass == 2 and def.preset == "racials" and presets[def.key] then
                local view = C.views[def.key]
                if view and view.on then ClaimList(presets[def.key], def.key, family) end
            end
        end
    end
end
-- A Blizzard entry joins a built-in bar unless another bar claims it, it is
-- hidden or already placed. A trinket record follows its equipment slot like
-- a claimed spell: a bar that lists the slot (e13) is its one home, so the
-- record stays off every other bar and off that one (the e13 icon shows it).
-- Trinket buff records (family 2) are not slots and stay on Buffs. An
-- unlearned healthstone record yields to its claimed stand-in item.
local function Offer(rec, slot, hidden, out, n)
    local key = rec.key
    local owner = claimed[key]
    local equip = rec.family == 1 and rec.equipSlot
    local home = equip and slotHome[equip]
    local stand = rec.spellCategory and standIn[rec.spellCategory]
    if not used[key] and not hidden[key] and (owner == nil or owner == slot)
        and not (equip and (usedSlot[equip] or (home ~= nil and home ~= slot)))
        and not (stand and claimed[stand] ~= nil) then
        used[key] = true
        n = n + 1
        out[n] = key
    end
    return n
end
local function Collect(i, kind, specLists, hidden, replaced, preview, out, presets)
    local def = SLOTS[i]
    local slot, family = def.key, KIND_FAMILY[kind]
    local n = 0
    wipe(used)
    wipe(usedSlot)
    local list, explicit = ListOf(i, specLists, presets)
    if list then
        for j = 1, #list do
            local key = Canon(list[j])
            if claimed[key] == slot and not used[key] and (explicit or not hidden[key]) then
                used[key] = true
                n = n + 1
                out[n] = key
                local src, id = Parse(key)
                if src == "e" then usedSlot[id] = true end
            end
        end
    end
    -- Suite spec defaults and explicitly imported Blizzard lists are complete
    -- selections. Other user lists retain the older append-new-spells rule.
    local strict = (list ~= nil and not explicit and
        (slot == "ess" or Catalog.defaultByBar[slot] ~= nil))
        or replaced[slot] == true
    if def.builtin and family and not strict then
        local records = Catalog.records
        if preview then
            -- Unlearned entries too, in Blizzard's global order; pool entries
            -- (trinkets on Essential) after the bar's own, as in byBar.
            local order, tail = Catalog.order, Catalog.TAIL
            for pass = 1, 2 do
                for j = 1, #order do
                    local rec = records[order[j]]
                    if rec and rec.bar == slot and rec.family == family and (tail[rec.category] == true) == (pass == 2) then
                        n = Offer(rec, slot, hidden, out, n)
                    end
                end
            end
        else
            local source = Catalog.byBar[slot] or EMPTY
            for j = 1, #source do
                local rec = records[source[j]]
                if rec and rec.bar == slot and rec.family == family then n = Offer(rec, slot, hidden, out, n) end
            end
        end
    elseif slot == "ess" and not explicit then
        -- Some talent variants are absent from the short raid preset. Fill a
        -- sparse Essential row with up to four learned spells from the guide
        -- and Blizzard's Essential category, after the preferred raid buttons. Keep
        -- dedicated Defensives claims and explicit user lists authoritative.
        local knownCount = 0
        for j = 1, n do
            local key = out[j]
            local src, id = Parse(key)
            local rec = src == "b" and Catalog.records[id]
            if rec and rec.known and not rec.equipSlot
                or src == "s" and presetSpell[key] and PresetKnown(key) then
                knownCount = knownCount + 1
            end
        end
        local defaults = Catalog.defaultByBar.ess or EMPTY
        for j = 1, #defaults do
            if knownCount >= 4 then break end
            local key = defaults[j]
            local src, id = Parse(key)
            local rec = src == "b" and Catalog.records[id]
            if rec and rec.known and not rec.equipSlot
                and rec.family == family then
                local before = n
                n = Offer(rec, slot, hidden, out, n)
                if n > before then knownCount = knownCount + 1 end
            end
        end
        -- An equipped on-use trinket still belongs at the end of Essential.
        -- User lists and imported layouts remain exact, including removals.
        local order, records = Catalog.order, Catalog.records
        for j = 1, #order do
            local rec = records[order[j]]
            if rec and rec.bar == slot and rec.family == family and rec.equipSlot then
                n = Offer(rec, slot, hidden, out, n)
            end
        end
    end
    -- Potions and racials: the Healthstones, then the racial, after
    -- Blizzard's entries (and after a user list, which they survive).
    local extra = def.preset == "racials" and presets[slot]
    if extra then
        for j = 1, #extra do
            local key = extra[j]
            if claimed[key] == slot and not used[key] and not hidden[key] then
                used[key] = true
                n = n + 1
                out[n] = key
            end
        end
    end
    for j = #out, n + 1, -1 do out[j] = nil end
    return n
end

------------------------------------------------------------------ refill changes
-- An entry that stays on its bar can still change on refill (a talent swaps
-- the override or the texture, a trinket swap changes the item). Those are
-- collected so the controller refreshes just them instead of every bar:
-- touched = entries whose filled fields changed, auraTouched = the subset
-- whose aura IDs or watched unit changed (their containers need a sync).
local WATCH = { "spell", "base", "override", "tooltip", "texture", "name", "charges", "hasRange", "known", "hasAura", "selfAura",
    "unit", "equipSlot", "itemID", "spellCategory", "linked", "family", "category" }
-- Where the aura-relevant fields sit in the snapshot.
local UNIT_AT, HASAURA_AT
for i = 1, #WATCH do
    if WATCH[i] == "unit" then
        UNIT_AT = i
    elseif WATCH[i] == "hasAura" then
        HASAURA_AT = i
    end
end
local touched, auraTouched, was, wasIDs = {}, {}, {}, {}
Resolve.touched, Resolve.auraTouched = touched, auraTouched
local function Snapshot(entry)
    for i = 1, #WATCH do was[i] = entry[WATCH[i]] end
    wipe(wasIDs)
    local ids = entry.auraIDs
    if ids then
        for id in pairs(ids) do
            wasIDs[id] = true
        end
    end
end
local function SameIDs(ids)
    local n = 0
    if ids then
        for id in pairs(ids) do
            if not wasIDs[id] then return false end
            n = n + 1
        end
    end
    for _ in pairs(wasIDs) do n = n - 1 end
    return n == 0
end
local function Compare(entry)
    local diff = false
    for i = 1, #WATCH do
        if was[i] ~= entry[WATCH[i]] then
            diff = true
            break
        end
    end
    local aura = was[UNIT_AT] ~= entry.unit or was[HASAURA_AT] ~= entry.hasAura or not SameIDs(entry.auraIDs)
    if diff or aura then touched[#touched + 1] = entry end
    if aura then auraTouched[entry] = true end
end

------------------------------------------------------------------ build
-- Only what can show is filled: an unlearned Blizzard record (outside the
-- previews) and an unlearned preset-only spell are dropped before any entry
-- table is made or any spell data is read.
local function Materialize(key, slot, index, preview, spells)
    if placed[key] then return nil end
    local src, id = Parse(key)
    if src == "b" then
        local rec = Catalog.records[id]
        if not (rec and (rec.known or preview)) then return nil end
    elseif presetSpell[key] and not PresetKnown(key) then
        return nil
    end
    local entries = C.entries
    local old = entries[key]
    local entry = old or { key = key }
    if old then Snapshot(old) end
    if not Fill(entry, key) or not (entry.known or preview and not presetSpell[key]) then return nil end
    local ov = spells[key]
    ov = type(ov) == "table" and ov or EMPTY
    local chosen = entry.unit and AURA_UNIT[ov.auraUnit]
    if chosen then entry.unit = chosen end
    if old then Compare(old) end
    entry.slot, entry.index, entry.ov = slot, index, ov
    entries[key], placed[key] = entry, true
    return entry
end
local function Placeholder(slot, n, family)
    local key = placeholderKeys[slot][n]
    local entry = C.entries[key] or { key = key }
    Clear(entry, "p", n, family)
    SetOverride(entry, nil)
    entry.base, entry.spell, entry.known = nil, nil, true
    entry.texture, entry.name, entry.auraIDs = PLACEHOLDER_TEXTURE, nil, nil
    if family == 2 then entry.unit = "player" end
    entry.slot, entry.index, entry.ov = slot, n, EMPTY
    C.entries[key], placed[key] = entry, true
    return entry
end
local function Fold(plan, kind, n)
    local list = plan.entries
    local diff = plan.kind ~= kind or #list ~= n
    for j = 1, n do
        if list[j] ~= tmp[j] then
            list[j] = tmp[j]
            diff = true
        end
    end
    for j = #list, n + 1, -1 do list[j] = nil end
    plan.kind = kind
    if diff then plan.gen = plan.gen + 1 end
    return diff
end

-- Returns C.plans and whether any bar's entry list changed. Each plan's gen
-- increments when its list changes; Resolve.touched lists entries that kept
-- their place but changed on refill. view.maxIcons is applied by the layout.
function Resolve.Build()
    local views, plans, entries = C.views, C.plans, C.entries
    local state = C.state
    local preview = state.preview == true
    -- The options canvas redraws only when entries may have changed.
    state.entryGen = (state.entryGen or 0) + 1
    local specLists, hidden, replaced = SpecData()
    local spells = type(C.spells) == "table" and type(C.spells.e) == "table" and C.spells.e or EMPTY
    local presets = PresetLists()
    Claim(specLists, presets)
    wipe(placed)
    wipe(touched)
    wipe(auraTouched)
    local any = false
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        local view = views[slot]
        if view and view.on then
            local kind = KindOf(i)
            local plan = planCache[slot]
            if not plan then
                plan = { slot = slot, entries = {}, gen = 0 }
                planCache[slot] = plan
            end
            local count = Collect(i, kind, specLists, hidden, replaced, preview, keys, presets)
            local n = 0
            for j = 1, count do
                local entry = Materialize(keys[j], slot, n + 1, preview, spells)
                if entry then
                    n = n + 1
                    tmp[n] = entry
                end
            end
            if preview and n == 0 then
                local family = KIND_FAMILY[kind] or 1
                for p = 1, PLACEHOLDER_COUNT do
                    n = n + 1
                    tmp[n] = Placeholder(slot, p, family)
                end
            end
            for j = #tmp, n + 1, -1 do tmp[j] = nil end
            if Fold(plan, kind, n) or plans[slot] ~= plan then any = true end
            plans[slot] = plan
        elseif plans[slot] then
            plans[slot] = nil
            any = true
        end
    end
    -- Entries that left every bar lose their place; Icons releases their frames.
    for key, entry in pairs(entries) do
        if not placed[key] then
            entries[key] = nil
            entry.slot, entry.index = nil, nil
        end
    end
    return plans, any
end

------------------------------------------------------------------ options helpers
-- Keys a bar would hold for the current spec, shown or not, unlearned
-- Blizzard entries included (the page dims them). Cold.
function Resolve.Keys(slot, out)
    out = out or {}
    local i = CDM.SLOT_INDEX[slot]
    if not i then
        wipe(out)
        return out
    end
    local specLists, hidden, replaced = SpecData()
    local presets = PresetLists()
    Claim(specLists, presets)
    local n = Collect(i, KindOf(i), specLists, hidden, replaced, true, out, presets)
    -- Preset-only spells the character does not know, and healthstones the
    -- client has no item for, never show (Materialize).
    local m = 0
    for j = 1, n do
        local key = out[j]
        local _, id = Parse(key)
        if (not presetSpell[key] or PresetKnown(key)) and not (consumable[key] and not Catalog.ItemIcon(id)) then
            m = m + 1
            out[m] = key
        end
    end
    for j = n, m + 1, -1 do out[j] = nil end
    return out
end
-- Fills a caller-owned table with the entry fields for one key without
-- touching the live entries. Nil when the key resolves to nothing.
function Resolve.Describe(key, out)
    out = out or {}
    if not Fill(out, key) then return nil end
    out.key = key
    return out
end
