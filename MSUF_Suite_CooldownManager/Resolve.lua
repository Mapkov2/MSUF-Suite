local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Settings, spell lists and the Blizzard snapshot -> one plan per shown bar.
-- Rules: explicit list entries claim their key for the first bar that lists
-- them ("one spell, one home"); built-in bars use the current specialization's
-- stock categories for Suite profiles, or the saved Blizzard layout when that
-- mode is selected. Explicit legacy lists append new Blizzard entries; Suite
-- defaults and imported lists replace the built-in bar. Custom bars show
-- their list only; an entry of the wrong family for the bar is skipped.
-- Entry tables are reused by key so runtime fields (icon, cooling, glows)
-- survive a rebuild; what one key stands for is EntryFill.lua's. Cold path.
local type, pairs = type, pairs
local EMPTY = C.EMPTY
local wipe = C.wipe
local CDM = NS.CDM
-- The per-spell choices in effect for the current specialization (shared
-- choices with this specialization's on top). The one accessor the build,
-- the options rows and the previews read; cached per data and spec.
local choiceData, choiceSpec, choiceMap
function C.Choices()
    local spec = C.state.specID
    if choiceData ~= C.spells or choiceSpec ~= spec then
        choiceData, choiceSpec = C.spells, spec
        choiceMap = CDM.EffectiveSpells(choiceData, spec)
    end
    return choiceMap or EMPTY
end
-- A build after a spec change refreshes the choices of entries that kept
-- their place (Compare).
local buildSpec, overrideScopeChanged
local SLOTS = CDM.SLOTS
local Catalog = C.Catalog

local Resolve = {}
C.Resolve = Resolve
local conditionKnown, conditionsPending, conditionSpec = {}, false, nil
local REQUIRE = { "requireSpell1", "requireSpell2", "requireSpell3" }
local EXCLUDE = { "excludeSpell1", "excludeSpell2", "excludeSpell3" }

-- Healthstones (Presets.CONSUMABLES): an item key and Blizzard's record of
-- its category name the same healthstone (Canon). Keys are built once.
local CONSUMABLES = C.Presets.CONSUMABLES
local consumableKeys, consumable, itemCategory = {}, {}, {}
for i = 1, #CONSUMABLES do
    local item, category = CONSUMABLES[i].item, CONSUMABLES[i].category
    local key = "i" .. item
    consumableKeys[i], itemCategory[key] = key, category
    consumable[key] = true
end

local KIND = CDM.KIND
local KIND_FAMILY = { [KIND.COOLDOWN] = 1, [KIND.AURA_ICON] = 2, [KIND.AURA_BAR] = 2 }
local PLACEHOLDER_TEXTURE, PLACEHOLDER_COUNT = C.Const.QUESTION_ICON, 3
local placeholderKeys = {}
for i = 1, #SLOTS do
    local slot, keys = SLOTS[i].key, {}
    for n = 1, PLACEHOLDER_COUNT do keys[n] = "p" .. slot .. "_" .. n end
    placeholderKeys[slot] = keys
end

-- One entry key's fields (EntryFill.lua loads first).
local EntryFill = C.EntryFill
local Parse, FamilyOf, Known, BaseSpell = EntryFill.Parse, EntryFill.FamilyOf, EntryFill.Known, EntryFill.BaseSpell
local Fill, Clear, SetOverride, AURA_UNIT = EntryFill.Fill, EntryFill.Clear, EntryFill.SetOverride, EntryFill.AURA_UNIT

-- Talent and spell conditions (requireSpell1..3, excludeSpell1..3): known in
-- the player's or the pet's spell book (Known). The spell book is readable
-- in combat too. A value holds once read: SpellsChanged in combat defers the
-- wipe to the end of the fight, so entries never come and go mid-fight, and
-- a value first read in combat (a reload mid-fight) is read again after it.
local function ConditionKnown(id)
    local value = conditionKnown[id]
    if value ~= nil then return value end
    value = Known(id)
    conditionKnown[id] = value
    if NS.IsCombatLocked() then conditionsPending = true end
    return value
end
function Resolve.ConditionsAllow(ov)
    if not ov then return true end
    for i = 1, 3 do
        local required, excluded = ov[REQUIRE[i]], ov[EXCLUDE[i]]
        if required and ConditionKnown(required) ~= true then return false end
        if excluded and ConditionKnown(excluded) ~= false then return false end
    end
    return true
end
function Resolve.ResumeConditions()
    if not conditionsPending then return false end
    wipe(conditionKnown)
    conditionsPending = false
    return true
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
-- Appends key to a preset list once.
local function AddPreset(out, n, key)
    if not presetSeen[key] then
        presetSeen[key] = true
        n = n + 1
        out[n] = key
    end
    return n
end
local function Consumables(out)
    local n = 0
    for i = 1, #CONSUMABLES do
        local category = CONSUMABLES[i].category
        if not covered[category] then
            local key = consumableKeys[i]
            standIn[category] = key
            n = AddPreset(out, n, key)
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
        local ids = def.key == "ess" and raid and Presets.RaidEssentials(specID)
            or def.preset == "defensives" and Presets.Defensives()
            or def.preset == "racials" and Presets.RACIALS or nil
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
                n = AddPreset(out, n, key)
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
function Resolve.SpellsChanged()
    wipe(presetKnown)
    if NS.IsCombatLocked() then
        conditionsPending = true
    else
        wipe(conditionKnown)
    end
end

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
    return view and view.kind or def.kind or KIND.COOLDOWN
end
-- The list a bar holds first: the user's list for this spec, then Suite
-- defaults for Essential, Utility, Defensives and both buff rows.
local function ListOf(i, specLists, presets)
    local def = SLOTS[i]
    local view = C.views[def.key]
    if def.custom and view and view.shareContents then
        return C.lists and C.lists.shared and C.lists.shared[def.key] or EMPTY, true
    end
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
    for i, def in ipairs(SLOTS) do
        local view = C.views[def.key]
        if def.custom and view and view.shareContents then
            ClaimList(C.lists and C.lists.shared and C.lists.shared[def.key] or EMPTY, def.key, KIND_FAMILY[KindOf(i)])
        end
    end
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
-- The bar's own list: keys this bar claimed, in list order.
local function CollectList(list, explicit, slot, hidden, out, n)
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
    return n
end
-- Blizzard's entries of a built-in bar after its list.
local function CollectBlizzard(slot, family, preview, hidden, out, n)
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
    return n
end
-- Some talent variants are absent from the short raid preset. Fill a
-- sparse Essential row with up to four learned spells from the guide and
-- Blizzard's Essential category, after the preferred raid buttons. Keep
-- dedicated Defensives claims and explicit user lists authoritative.
local function FillEssential(slot, family, hidden, out, n)
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
    return n
end
local function Collect(i, kind, specLists, hidden, replaced, preview, out, presets)
    local def = SLOTS[i]
    local slot, family = def.key, KIND_FAMILY[kind]
    local n = 0
    wipe(used)
    wipe(usedSlot)
    local list, explicit = ListOf(i, specLists, presets)
    if list then n = CollectList(list, explicit, slot, hidden, out, n) end
    -- Suite spec defaults and explicitly imported Blizzard lists are complete
    -- selections. Other user lists retain the older append-new-spells rule.
    local strict = (list ~= nil and not explicit and
        (slot == "ess" or Catalog.defaultByBar[slot] ~= nil))
        or replaced[slot] == true
    if def.builtin and family and not strict then
        n = CollectBlizzard(slot, family, preview, hidden, out, n)
    elseif slot == "ess" and not explicit then
        n = FillEssential(slot, family, hidden, out, n)
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
local SameSet, CopySet = C.Const.SameSet, C.Const.CopySet
local wasChoices
Resolve.touched, Resolve.auraTouched = touched, auraTouched
local function Snapshot(entry)
    wasChoices = entry.ov
    for i = 1, #WATCH do was[i] = entry[WATCH[i]] end
    CopySet(wasIDs, entry.auraIDs or EMPTY)
end
local function Compare(entry)
    -- Settings changes already refresh all affected behavior/auras. A spec
    -- change can keep the same entry list, so explicitly refresh its choices.
    local choicesChanged = overrideScopeChanged and wasChoices ~= entry.ov
    local diff = choicesChanged
    for i = 1, #WATCH do
        if was[i] ~= entry[WATCH[i]] then
            diff = true
            break
        end
    end
    local aura = was[UNIT_AT] ~= entry.unit or was[HASAURA_AT] ~= entry.hasAura or not SameSet(entry.auraIDs or EMPTY, wasIDs)
        or (choicesChanged and entry.hasAura)
    if diff or aura then touched[#touched + 1] = entry end
    if aura then auraTouched[entry] = true end
end

------------------------------------------------------------------ build
-- Only what can show is filled: an unlearned Blizzard record (outside the
-- previews) and an unlearned preset-only spell are dropped before any entry
-- table is made or any spell data is read.
local function Materialize(key, slot, index, preview, spells)
    if placed[key] then return nil end
    if not preview and not Resolve.ConditionsAllow(spells[key]) then return nil end
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
    entry.ov = ov
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

-- "Send excess cooldowns to": the bar that takes a shown cooldown bar's
-- entries past Maximum icons. One hop only: the destination must be another
-- shown cooldown bar without its own overflow (no cycles, no
-- order-dependent chains); anything else routes nothing. The build and
-- the options rows (Exports) share this rule.
function Resolve.OverflowTarget(slot)
    local i = CDM.SLOT_INDEX[slot]
    local view = i and C.views[slot]
    local cap = view and view.maxIcons
    if not (view and view.on and KindOf(i) == KIND.COOLDOWN and type(cap) == "number" and cap > 0) then return nil end
    local target = SLOTS[(view.overflow or 1) - 1]
    local key = target and target.key
    local targetView = key and key ~= slot and C.views[key]
    if targetView and targetView.on and KindOf(CDM.SLOT_INDEX[key]) == KIND.COOLDOWN and (targetView.overflow or 1) == 1 then
        return key
    end
end
local function RouteOverflow(plans)
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        local plan = plans[slot]
        local target = plan and Resolve.OverflowTarget(slot)
        local targetPlan = target and plans[target]
        if targetPlan then
            local cap = C.views[slot].maxIcons
            local source, destination = plan.staging, targetPlan.staging
            for j = cap + 1, #source do destination[#destination + 1] = source[j] end
            for j = #source, cap + 1, -1 do source[j] = nil end
        end
    end
end

-- The end of a build: every staged list (after the overflow routing) becomes
-- its plan's entry list, and entries that left every bar lose their place;
-- Icons releases their frames. Returns whether any entry list changed.
local function Commit(plans, entries)
    local any = false
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        local plan = plans[slot]
        if plan then
            local staging = plan.staging
            for j = 1, #staging do
                local entry = staging[j]
                entry.slot, entry.index, tmp[j] = slot, j, entry
            end
            for j = #tmp, #staging + 1, -1 do tmp[j] = nil end
            if Fold(plan, plan.stagingKind, #staging) then any = true end
        end
    end
    for key, entry in pairs(entries) do
        if not placed[key] then
            entries[key] = nil
            entry.slot, entry.index = nil, nil
        end
    end
    return any
end

-- Returns C.plans and whether any bar's entry list changed. Each plan's gen
-- increments when its list changes; Resolve.touched lists entries that kept
-- their place but changed on refill. view.maxIcons is applied by the layout.
function Resolve.Build()
    local views, plans, entries = C.views, C.plans, C.entries
    local state = C.state
    if not NS.IsCombatLocked() and (conditionsPending or conditionSpec ~= state.specID) then
        wipe(conditionKnown)
        conditionsPending, conditionSpec = false, state.specID
    end
    local preview = state.preview == true
    -- The options canvas redraws only when entries may have changed.
    state.entryGen = (state.entryGen or 0) + 1
    local specLists, hidden, replaced = SpecData()
    overrideScopeChanged, buildSpec = buildSpec ~= state.specID, state.specID
    local spells = C.Choices()
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
                plan = { slot = slot, entries = {}, staging = {}, gen = 0 }
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
            local staging = plan.staging
            for j = 1, n do staging[j] = tmp[j] end
            for j = #staging, n + 1, -1 do staging[j] = nil end
            plan.stagingKind = kind
            if plans[slot] ~= plan then any = true end
            plans[slot] = plan
        elseif plans[slot] then
            plans[slot] = nil
            any = true
        end
    end
    RouteOverflow(plans)
    if Commit(plans, entries) then any = true end
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
