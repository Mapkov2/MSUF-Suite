local root = assert(arg[1], "repository root required")
-- Combat catalog rebuilds at the 2026-10-28 M+ trace's size (76 cooldown
-- records in 8 category sets): 111 rebuilds after SPELLS_CHANGED in 17 min
-- of combat, Catalog.Fetch 1.66 ms mean (14.2 max), every one in a single
-- frame, and the 56 that changed a record ran their resolve in the same
-- frame. This contract holds the cut and the split:
--   * Fetch copies a record with inline readers (no Num/Flag/Put calls);
--   * in combat a pass reads at most Catalog.SLICE infos per frame into
--     shadow records and lands in one frame; until then the live catalog
--     is untouched, and it reads exactly what an immediate rebuild reads;
--   * a frame that ran catalog work in combat runs no resolve.
-- "measure" (arg 2) prints the numbers without asserting them, for a
-- before/after run against other sources (SUITE_CDM_CATALOG_SOURCE,
-- SUITE_CDM_FLUSH_SOURCE).
local measureOnly = arg[2] == "measure"
local W = dofile(root .. "/tools/tests/cdm_data_world.lua")(root)
local C, NS = W.C, W.NS
local Catalog, Resolve, Index = C.Catalog, C.Resolve, C.Index
local checks = 0
local function Check(value, message)
    checks = checks + 1
    if not measureOnly then assert(value, message) end
end
local function Read(path)
    local handle = assert(io.open(path, "rb"))
    local text = handle:read("*a"):gsub("\r", "")
    handle:close()
    return text
end

------------------------------------------------------------------ static
-- The flush's catalog unit (Events.lua) continues a combat pass and the
-- flush holds the rest of its data step; the stand-in below repeats it.
if not measureOnly then
    local events = Read(root .. "/MSUF_Suite_CooldownManager/Events.lua")
    -- The spec is read when a pass starts, not once per slice: a pass makes
    -- no native call an immediate rebuild does not.
    Check(events:find("local function CatalogUnit(locked, fresh)\n", 1, true)
        and events:find("    if fresh and UpdateSpec() then dirty.resolve = true end\n", 1, true)
        and events:find("    local changed = C.Catalog.Rebuild(locked, fresh)\n    if changed == nil then\n"
            .. "        if not dirty.catalog then dirty.catalog = \"slice\" end\n        return\n    end\n", 1, true),
        "Events.lua CatalogUnit no longer continues a sliced pass")
    local catalog = Read(root .. "/MSUF_Suite_CooldownManager/Catalog.lua")
    local copy = assert(catalog:match("\nlocal function Copy%(.-\nend\n"))
    for _, helper in ipairs({ "Num(", "Flag(", "Put(", "Public(" }) do
        Check(not copy:find(helper, 1, true), "Copy calls " .. helper .. "...) per field again")
    end
    -- The slices live in CatalogSlices.lua: Catalog.lua keeps headroom under
    -- the 810-line limit (809 when it held them).
    local _, lines = catalog:gsub("\n", "")
    Check(lines <= 760 and not catalog:find("local function Land()", 1, true) and not catalog:find("local function Queue()", 1, true),
        "Catalog.lua holds the combat slices again or lost its headroom (" .. lines .. " lines)")
    -- Any icon update restages a combat resolve, before routing: a key new
    -- to the stage has no live entry to retexture.
    local icon = events:match("\nlocal function OnIcon%(.-\nend\n") or ""
    Check(icon:find("\n    resolveStage.stale = resolveStage.on\n    if issecret", 1, true),
        "SPELL_UPDATE_ICON restages a combat resolve only when a live texture moved")
end

------------------------------------------------------------------ fixture
-- 14 Essential, 14 Utility, 20 buffs, 14 bars, 6 potions, 4 spec-agnostic
-- buffs, 2 trinkets and 2 trinket procs: the trace's 76 info reads.
local SPELL_CATEGORY = C.Const.SPELL_CATEGORY
local POTIONS = { SPELL_CATEGORY.COMBAT_POTION, SPELL_CATEGORY.HEALTH_POTION, SPELL_CATEGORY.HEALTHSTONE }
local function Add(category, count, make)
    local list = {}
    for i = 1, count do
        local id = 1000 + category * 100 + i
        list[i] = id
        local info = { cooldownID = id, spellID = 50000 + id, linkedSpellIDs = {}, selfAura = false, hasAura = false,
            charges = false, isKnown = true, isInvisible = false, flags = 0, category = category }
        if make then make(info, i) end
        W.infos[id] = info
    end
    W.sets[category] = list
end
Add(0, 14, function(info, i) info.charges, info.isKnown, info.flags = i % 4 == 0, i <= 12, i == 14 and 2 or 0 end)
Add(1, 14, function(info, i) info.isKnown = i ~= 7 end)
Add(2, 20, function(info, i)
    info.hasAura, info.selfAura = true, i % 2 == 0
    if i % 5 == 0 then info.linkedSpellIDs = { 60000 + i, 61000 + i } end
end)
Add(3, 14, function(info) info.hasAura, info.selfAura = true, true end)
Add(5, 6, function(info, i) info.spellCategoryID = POTIONS[i] end)
Add(6, 4, function(info) info.hasAura = true end)
Add(7, 2, function(info, i) info.spellID, info.equipSlot = nil, 12 + i end)
Add(8, 2, function(info, i) info.equipSlot, info.hasAura = 12 + i, true end)
local INFOS = 76
W.Views()
C.state.specID = 63

-- Everything a resolve reads from the catalog, as one string.
local function Snapshot()
    local out, ids = {}, {}
    for id in pairs(Catalog.records) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local rec, row = Catalog.records[id], { id }
        for _, field in ipairs({ "spell", "override", "tooltip", "equipSlot", "spellCategory", "selfAura", "hasAura", "charges", "known",
            "defaultCategory", "category", "family", "bar" }) do row[#row + 1] = tostring(rec[field]) end
        row[#row + 1] = table.concat(rec.linked, "+")
        out[#out + 1] = table.concat(row, ":")
    end
    local function List(list) return table.concat(list, ",") end
    out[#out + 1] = List(Catalog.order)
    for _, key in ipairs({ "ess", "uti", "buf", "bar", "ext" }) do
        out[#out + 1] = key .. "=" .. List(Catalog.byBar[key]) .. "/" .. List(Catalog.defaultByBar[key] or {})
    end
    return table.concat(out, "\n")
end

------------------------------------------------------------------ immediate rebuild
-- Out of combat nothing changes but the cost: every info is read and copied.
assert(Catalog.Rebuild() == true)
W.Reset()
local unchanged = W.Cost(Catalog.Rebuild)
Check(W.natives.GetCooldownViewerCooldownInfo == INFOS and W.natives.GetCooldownViewerCategorySet == 8
    and W.natives.GetLayoutData == 1, "an immediate rebuild changed its native reads")
W.infos[1003].isKnown = false
local changedCost = W.Cost(Catalog.Rebuild)
W.infos[1003].isKnown = true
Catalog.Rebuild()
print(("CDM combat catalog: immediate rebuild vm unchanged=%d changed=%d (76 records)"):format(unchanged, changedCost))
-- Measured 2026-10-29 with Num/Flag/Put per field: 22407 unchanged, 32589
-- changed; inline readers: 16540 / 25508. Budgets +1 %.
Check(unchanged <= 16705, "unchanged 76-record rebuild exceeded its VM budget")
Check(changedCost <= 25763, "changed 76-record rebuild exceeded its VM budget")

------------------------------------------------------------------ combat slices
local function Pass(fresh)
    local frames, maxVM, maxReads, total, result = 0, 0, 0, 0, nil
    W.Reset()
    repeat
        local before = W.natives.GetCooldownViewerCooldownInfo or 0
        local vm, value = W.Cost(Catalog.Rebuild, true, fresh and frames == 0)
        local reads = (W.natives.GetCooldownViewerCooldownInfo or 0) - before
        frames, total, result = frames + 1, total + vm, value
        if vm > maxVM then maxVM = vm end
        if reads > maxReads then maxReads = reads end
    until value ~= nil or frames > 20
    return result, frames, maxVM, maxReads, total
end
do
    local before, generation, content = Snapshot(), Catalog.generation, Catalog.content
    W.infos[1003].isKnown, W.infos[1201].linkedSpellIDs = false, { 62001 }
    -- The first slice changes nothing anyone can read.
    W.Reset()
    Check(Catalog.Rebuild(true, true) == nil, "a combat rebuild read every info in one frame")
    Check((W.natives.GetCooldownViewerCooldownInfo or 0) <= (Catalog.SLICE or 0), "a slice read more than SLICE infos")
    Check(Snapshot() == before and Catalog.generation == generation and Catalog.content == content,
        "a pending pass changed the live catalog")
    local result, frames, maxVM, maxReads = Pass(false)
    Check(result == true, "the landed pass lost the change")
    Check(maxReads <= (Catalog.SLICE or INFOS), "a later slice read more than SLICE infos")
    Check(Catalog.content == content + 1 and Catalog.records[1003].known == false and Catalog.records[1201].linked[1] == 62001,
        "the landed pass did not publish its records once")
    -- What landed is what an immediate rebuild sees: nothing left to change.
    local landed = Snapshot()
    Check(Catalog.Rebuild() == false and Snapshot() == landed, "a landed pass differs from an immediate rebuild")
    W.infos[1003].isKnown, W.infos[1201].linkedSpellIDs = true, {}
    Catalog.Rebuild()
    -- An unchanged combat pass: the same native reads as an immediate rebuild.
    local settled = Catalog.content
    local value, count, peak, reads, total = Pass(true)
    Check(value == false and Catalog.content == settled, "an unchanged combat pass moved the content")
    Check(W.natives.GetCooldownViewerCooldownInfo == INFOS and W.natives.GetCooldownViewerCategorySet == 8
        and W.natives.GetLayoutData == 1, "a combat pass read more or less than an immediate rebuild")
    print(("CDM combat catalog: combat pass %d frames, max vm %d per frame (%d infos), total vm %d"):format(count, peak, reads,
        total))
    -- 2026-10-29: four frames, the landing one 10324 (16 infos and the
    -- compare of all 76 shadows) of the immediate 16540. Budget +1 %.
    Check(count == 4 and peak <= 10427, "combat slices exceeded their per-frame VM budget")
    print(("CDM combat catalog: changed pass %d frames, max vm %d"):format(frames, maxVM))
end

-- A catalog event while a pass reads starts it again; past two restarts
-- the pass reads everything at once, as out of combat.
do
    W.Reset()
    Check(Catalog.Rebuild(true, true) == nil, "first slice")
    Check(Catalog.Rebuild(true, true) == nil and W.natives.GetCooldownViewerCategorySet == 16,
        "a fresh catalog event did not restart the pass")
    Check(Catalog.Rebuild(true, true) == nil and W.natives.GetCooldownViewerCategorySet == 24, "second restart")
    W.Reset()
    Check(Catalog.Rebuild(true, true) == false and W.natives.GetCooldownViewerCooldownInfo == INFOS,
        "a third restart did not read everything at once")
    -- An override while a pass reads: the next slice starts again.
    W.Reset()
    Check(Catalog.Rebuild(true, true) == nil, "pass for the override")
    Catalog.OnOverride(51001, 51999)
    Check(Catalog.Rebuild(true, false) == nil and W.natives.GetCooldownViewerCategorySet == 16,
        "an override during a pass kept the slices read before it")
    local value = Pass(false)
    Check(value == true and Catalog.records[1001].override == nil, "the restarted pass did not read the override again")
    -- Out of combat a rebuild reads everything now and drops the pass.
    Check(Catalog.Rebuild(true, true) == nil, "pass to drop")
    W.Reset()
    Check(Catalog.Rebuild(false, false) == false and W.natives.GetCooldownViewerCooldownInfo == INFOS,
        "an out-of-combat rebuild continued a combat pass")
    W.Reset()
    Check(Catalog.Rebuild(true, false) == nil and W.natives.GetCooldownViewerCategorySet == 8,
        "a dropped pass was continued")
    Pass(false)
    -- Any override restarts a pass, also one no live record follows: a
    -- record new to the pass may.
    W.Reset()
    Check(Catalog.Rebuild(true, true) == nil, "pass for an untracked override")
    Catalog.OnOverride(424242, 1)
    Check(Catalog.Rebuild(true, false) == nil and W.natives.GetCooldownViewerCategorySet == 16,
        "an override of a base no live record follows kept the pass")
    Pass(false)
end

------------------------------------------------------------------ flush frames
-- The flush with its layers stubbed: catalog slices run alone in their
-- frames, the resolve a pass asks for runs in the next frame. Out of
-- combat both share one frame, as before.
local queue = {}
C_Timer = { After = function(_, fn) queue[#queue + 1] = fn end }
EventRegistry = { TriggerEvent = function() end }
local noop = function() end
W.S.NewUnitRunner = function() return function(_, _, _, fn, a, b) fn(a, b) end, function() return false end, noop end
W.S.Dispatch = function(fn, ...) return fn(...) end
C.Layout = { dirty = {}, Request = noop, Flush = noop, ApplyAll = noop, Apply = noop }
C.Preview, C.ActionGlows, C.ActionUsableGlows = { Decorate = noop }, { Refresh = noop }, {}
C.Icons, C.Auras, C.Native = { Texture = noop, Sync = noop, Style = noop }, { Sync = noop, Restyle = noop }, { Apply = noop }
C.Time = { Refresh = function() return false end, BeginQueries = noop, EndQueries = noop }
C.Effects = { Update = noop, UsableShown = function() return false end, Usable = noop, CombatChanged = noop }
C.Keybinds, C.Visibility = { Refresh = noop }, { ApplyAll = noop, Apply = noop }
assert(loadfile(os.getenv("SUITE_CDM_FLUSH_SOURCE") or root .. "/MSUF_Suite_CooldownManager/Flush.lua"))("MSUF_Suite_CooldownManager", W.P)
local F = C.Flush
local function CatalogUnit(locked, fresh)
    local changed = Catalog.Rebuild(locked, fresh)
    if changed == nil then
        if not F.dirty.catalog then F.dirty.catalog = "slice" end
        return
    end
    if changed then F.dirty.resolve = true end
end
F.BindDataUnits(CatalogUnit, function() Index.Rebuild() end, noop, noop, noop)
-- resolves: builds that land; stages: every call (a combat resolve stages).
local build, resolves, stages = Resolve.Build, 0, 0
Resolve.Build = function(...)
    local plans, any = build(...)
    stages = stages + 1
    if plans ~= nil then resolves = resolves + 1 end
    return plans, any
end
local function Frames(label)
    local rows, peak, peakCatalog = {}, 0, 0
    while #queue > 0 and #rows < 20 do
        local fns = queue
        queue = {}
        local reads, built = W.natives.GetCooldownViewerCooldownInfo or 0, stages
        local vm = W.Cost(function() for i = 1, #fns do fns[i]() end end)
        reads, built = (W.natives.GetCooldownViewerCooldownInfo or 0) - reads, stages - built
        rows[#rows + 1] = ("%d:%dvm/%dinfos/%dresolve"):format(#rows + 1, vm, reads, built)
        Check(not (reads > 0 and built > 0 and W.combat), label .. ": a combat frame held catalog reads and resolve work")
        if vm > peak then peak = vm end
        if reads > 0 and vm > peakCatalog then peakCatalog = vm end
    end
    print(("CDM combat catalog: %s frames %s"):format(label, table.concat(rows, " ")))
    return #rows, peak, peakCatalog
end
F.dirty.catalog, F.dirty.resolve = true, true
F.Schedule()
local frames = Frames("settle")
Check(frames == 1 and resolves == 1, "out of combat the catalog and its resolve left one frame")
W.combat = true
W.infos[1003].isKnown = false
resolves = 0
F.dirty.catalog = true
F.Schedule()
local count, peak, peakCatalog = Frames("combat change")
Check(count > 5 and resolves == 1, "the combat pass and its staged resolve did not take frames of their own")
-- 2026-10-29: 5601, 4003, 4003, then 19421 (landing with the derived
-- lists); before, one frame of 25508 catalog and the resolve. Budget +1 %.
Check(peakCatalog <= 19615, "a combat catalog frame exceeded its VM budget")
print(("CDM combat catalog: combat frames max vm %d (catalog frames %d)"):format(peak, peakCatalog))
-- 2026-10-29: the resolve was one frame of 78427 (with its routing index);
-- staged its frames are 3877-13458 and the landing 24502 (with the index).
-- Budget +1 %.
Check(peak <= 24747, "a combat frame of the catalog and resolve chain exceeded its VM budget")
W.combat = false
W.infos[1003].isKnown = true
F.dirty.catalog = true
F.Schedule()
Frames("restore")
-- A catalog event every frame in combat: after Flush.DEFER catalog frames
-- the data step yields a frame to the resolve, so it lands (staged, or at
-- once past its restarts) and never shares a frame with catalog reads.
do
    W.combat, resolves = true, 0
    W.infos[1003].isKnown = false
    local frames = 0
    while resolves == 0 and frames < 60 do
        frames = frames + 1
        F.dirty.catalog = true
        F.Schedule()
        local fns = queue
        queue = {}
        local reads, built = W.natives.GetCooldownViewerCooldownInfo or 0, stages
        for i = 1, #fns do fns[i]() end
        reads, built = (W.natives.GetCooldownViewerCooldownInfo or 0) - reads, stages - built
        Check(not (reads > 0 and built > 0), "storm: a frame held catalog reads and resolve work")
    end
    print(("CDM combat catalog: a catalog event every frame, the resolve landed after %d frames"):format(frames))
    Check(resolves >= 1 and F.DEFER, "catalog events every frame starved the combat resolve")
    W.combat = false
    W.infos[1003].isKnown = true
    F.dirty.catalog = true
    F.Schedule()
    Frames("restore after storm")
end

------------------------------------------------------------------ item reads
-- ItemState (Time.lua) reads one cooldown per refreshed entry: by its
-- equipment slot, else by its item ID. A bag pass refreshes Index.bags once
-- each (Flush.lua marks a set), so a pass reads an item or slot twice only
-- if two placed cooldown entries share one. The default bars do not.
do
    C.lists = NS.CDM.CleanLists(nil)
    C.views.ext.on = true
    Resolve.Build()
    Index.Rebuild()
    local seen, bags = {}, Index.bags
    for i = 1, #bags do
        local entry = bags[i]
        local slot = entry.equipSlot or (entry.src == "e" and entry.id) or nil
        local key = slot and ("slot" .. slot) or ("item" .. tostring(entry.itemID or entry.id))
        Check(not seen[key], "two bag entries read " .. key .. " in one pass")
        seen[key] = true
    end
    print(("CDM combat catalog: bag pass reads %d item/slot cooldowns, all distinct"):format(#bags))
end

print("CDM combat catalog: " .. checks .. " checks passed")
