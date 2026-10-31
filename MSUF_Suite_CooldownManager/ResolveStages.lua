local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Builds in parts (Resolve.parts). The options rows run a build's claims and
-- collection only (Keys, Describe). In combat a resolve runs in stages over
-- frames (2026-10-28 M+ trace: 56 resolves after combat catalog changes,
-- 1.78 ms each, all in one frame): the inputs and every shown bar's keys
-- first, then at most STEP keys per frame filled into shadows of the live
-- entries, then one frame that applies the shadows and switches the plans
-- (Resolve's Publish). Until it lands every reader sees the last complete
-- build. A resolve request, a catalog event, an override or a retexture
-- while it stages starts it again; past RESTARTS, and in previews, the
-- build runs at once, as out of combat.
local wipe = C.wipe
local Resolve = C.Resolve
local parts = Resolve.parts
local CDM = NS.CDM
local SLOTS = CDM.SLOTS
local Catalog, EntryFill = C.Catalog, C.EntryFill
local CopySet = C.Const.CopySet

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
    local specLists, hidden, replaced = parts.SpecData()
    local presets = parts.PresetLists()
    parts.Claim(specLists, presets)
    local n = parts.Collect(i, parts.KindOf(i), specLists, hidden, replaced, true, out, presets)
    -- Preset-only spells the character does not know, and healthstones the
    -- client has no item for, never show (Materialize).
    local presetSpell, consumable, PresetKnown = parts.presetSpell, parts.consumable, parts.PresetKnown
    local m = 0
    for j = 1, n do
        local key = out[j]
        local _, id = EntryFill.Parse(key)
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
    if not EntryFill.Fill(out, key) then return nil end
    out.key = key
    return out
end

------------------------------------------------------------------ combat stages
local STEP, RESTARTS = 12, 2
-- Every field a fill writes (EntryFill, Materialize, AuraTimers.Classify);
-- auraIDs goes into the live entry's own set. The contract checks the list.
local FILL = { "src", "id", "family", "category", "selfAura", "hasAura", "charges", "hasRange", "equipSlot", "itemID",
    "spellCategory", "tooltip", "linked", "unit", "hideEmpty", "override", "prevOverride", "base", "spell", "known", "texture",
    "name", "auraHelpful", "ov", "timer", "slot", "index" }
local stage = Resolve.stage
stage.refill = { base = {}, known = {}, override = {}, charges = {}, icon = {}, item = {}, name = {} }
stage.keys, stage.counts, stage.kinds, stage.shown, stage.restarts = {}, {}, {}, {}, 0
Resolve.STEP, Resolve.FILL = STEP, FILL
-- shadows and their aura sets per key, kept across builds; order: the
-- entries this build placed, live or new.
local shadows, sets, shadowOf, order = {}, {}, {}, {}

function stage.Shadow(live)
    local key = live.key
    local shadow = shadows[key]
    if not shadow then
        shadow = { key = key }
        shadows[key] = shadow
    end
    for f = 1, #FILL do
        local field = FILL[f]
        shadow[field] = live[field]
    end
    local set
    if live.auraIDs then
        set = sets[key] or {}
        sets[key] = set
    end
    shadow.auraIDs = set
    shadowOf[live] = shadow
    return shadow
end
-- The landing (Publish): shadows into their live entries, new entries into
-- the map. A live entry keeps its aura set's identity.
function stage.Apply()
    local entries = C.entries
    for i = 1, #order do
        local entry = order[i]
        local shadow = shadowOf[entry]
        if shadow then
            for f = 1, #FILL do
                local field = FILL[f]
                entry[field] = shadow[field]
            end
            local ids, live = shadow.auraIDs, entry.auraIDs
            if ids and live then
                CopySet(live, ids)
            else
                entry.auraIDs = ids
                if ids and ids == sets[entry.key] then sets[entry.key] = nil end
            end
        end
        entries[entry.key] = entry
    end
end

-- The inputs first (presets and claims), every shown bar's keys in the
-- next frame (Collect), then the fills.
local function Begin()
    local preview, spells, specLists, hidden, replaced, presets = parts.Prepare(stage)
    stage.on, stage.stale, stage.spells, stage.i, stage.j, stage.n = true, false, spells, 0, 1, 0
    stage.preview, stage.specLists, stage.hidden, stage.replaced, stage.presets = preview, specLists, hidden, replaced, presets
    wipe(shadowOf)
    wipe(order)
end
local function Collect()
    wipe(stage.shown)
    local views = C.views
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        local view = views[slot]
        if view and view.on then
            local keys, kind = stage.keys[slot] or {}, parts.KindOf(i)
            stage.keys[slot], stage.kinds[slot], stage.shown[slot] = keys, kind, true
            stage.counts[slot] = parts.Collect(i, kind, stage.specLists, stage.hidden, stage.replaced, stage.preview, keys,
                stage.presets)
        end
    end
    stage.i = 1
end
-- Fills at most STEP keys.
local function Step()
    local budget = STEP
    while stage.i <= #SLOTS do
        local slot = SLOTS[stage.i].key
        if stage.shown[slot] then
            local keys, count, plan = stage.keys[slot], stage.counts[slot], parts.PlanOf(slot)
            local staging = plan.staging
            while stage.j <= count do
                if budget == 0 then return end
                budget = budget - 1
                local entry = parts.Materialize(keys[stage.j], slot, stage.n + 1, false, stage.spells, stage)
                stage.j = stage.j + 1
                if entry then
                    stage.n = stage.n + 1
                    staging[stage.n] = entry
                    order[#order + 1] = entry
                end
            end
            for k = #staging, stage.n + 1, -1 do staging[k] = nil end
            plan.stagingKind = stage.kinds[slot]
        end
        stage.i, stage.j, stage.n = stage.i + 1, 1, 0
    end
end
-- One stage per call: nil while it stages, C.plans and whether a list
-- changed when it lands, false when the build must run at once.
function Resolve.Stage(fresh)
    if C.state.preview then return false end
    local again = stage.on and (fresh or stage.stale)
    if again and stage.restarts >= RESTARTS then return false end
    if again or not stage.on then
        stage.restarts = again and stage.restarts + 1 or 0
        Begin()
        return nil
    end
    -- The keys and the landing get frames of their own.
    if stage.i == 0 then
        Collect()
        return nil
    elseif stage.i <= #SLOTS then
        Step()
        return nil
    end
    stage.on = false
    return parts.Publish(stage.shown, stage)
end
