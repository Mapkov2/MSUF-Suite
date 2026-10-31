local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Combat catalog rebuilds in slices (Catalog.Slice, from Catalog.Rebuild):
-- the category sets when a pass starts, then at most SLICE cooldown infos
-- per frame into shadow records (2026-10-28 M+ trace: 111 rebuilds after
-- SPELLS_CHANGED in 17 min of combat, 1.66 ms each, one frame each).
-- Records, lists and indexes switch once, in the frame that reads the last
-- ID (Land); until then everything reads the last complete catalog. A
-- catalog event, or any override while a pass reads (Catalog.OnOverride),
-- starts it again; past RESTARTS it reads all at once, as out of combat.
-- Shadow records are kept per cooldownID across passes.
local Catalog = C.Catalog
local parts = Catalog.parts
local Copy, CopyLinked, Start, CAT_ORDER = parts.Copy, parts.CopyLinked, parts.Start, parts.CAT_ORDER
local fetched, eff, defaultOrder, issecret = parts.fetched, parts.eff, parts.defaultOrder, parts.issecret
local Flag = Catalog.Flag
local type, wipe = type, C.wipe
local SLICE, RESTARTS = 20, 2
local FIELDS = { "spell", "override", "tooltip", "equipSlot", "spellCategory", "selfAura", "hasAura", "charges", "known",
    "defaultCategory" }
local pass = Catalog.pass
pass.ids, pass.cats, pass.order, pass.seen = {}, {}, {}, {}
pass.total, pass.at, pass.kept, pass.restarts = 0, 0, 0, 0
local shadows = {}
Catalog.SLICE = SLICE

local function Queue()
    local getSet = C_CooldownViewer.GetCooldownViewerCategorySet
    local ids, cats, seen = pass.ids, pass.cats, pass.seen
    wipe(seen)
    local n = 0
    for c = 1, #CAT_ORDER do
        local category = CAT_ORDER[c]
        local set = getSet(category, true)
        if not issecret(set) and type(set) == "table" then
            for j = 1, #set do
                local id = set[j]
                if not issecret(id) and type(id) == "number" and id > 0 and not seen[id] then
                    seen[id] = true
                    n = n + 1
                    ids[n], cats[n] = id, category
                end
            end
        end
    end
    for i = #ids, n + 1, -1 do ids[i], cats[i] = nil, nil end
    pass.total, pass.at, pass.kept, pass.on, pass.stale = n, 0, 0, true, false
end
-- One slice; true once the pass has read its last ID.
local function Read()
    local getInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo
    local hideInvisible = CDM_HIDE_INVISIBLE_ITEMS == true
    local ids, cats, order = pass.ids, pass.cats, pass.order
    local n, last = pass.kept, pass.at + SLICE
    if last > pass.total then last = pass.total end
    for i = pass.at + 1, last do
        local id = ids[i]
        local info = getInfo(id)
        if not issecret(info) and type(info) == "table" and not (hideInvisible and Flag(info.isInvisible)) then
            local shadow = shadows[id]
            if not shadow then
                shadow = {}
                shadows[id] = shadow
            end
            Copy(shadow, info, cats[i])
            n = n + 1
            order[n] = id
        end
    end
    for i = #order, n + 1, -1 do order[i] = nil end
    pass.at, pass.kept = last, n
    return last >= pass.total
end
-- The shadows become the live records (the same compare Fetch makes), then
-- the commit; returns whether the catalog content changed.
local function Land()
    local reusable, tag, guide, layout = Start()
    local records, order, n = Catalog.records, pass.order, pass.kept
    local moved, reordered = false, false
    for i = 1, n do
        local id = order[i]
        local shadow, rec = shadows[id], records[id]
        if not rec then
            rec = { id = id, key = "b" .. id }
            records[id] = rec
            moved = true
        end
        for f = 1, #FIELDS do
            local field = FIELDS[f]
            local value = shadow[field]
            if rec[field] ~= value then
                rec[field] = value
                moved = true
            end
        end
        if rec.linked ~= shadow.linked and CopyLinked(rec, shadow.linked) then moved = true end
        fetched[id], eff[id] = true, shadow.defaultCategory
        if defaultOrder[i] ~= id then reordered = true end
        defaultOrder[i] = id
    end
    if #defaultOrder ~= n then reordered = true end
    for i = #defaultOrder, n + 1, -1 do defaultOrder[i] = nil end
    pass.on = false
    return parts.Finish(moved, reordered, reusable, tag, guide, layout)
end

-- One slice per call: nil while the pass reads, true and whether the
-- content changed when it lands, false when the rebuild must read now.
function Catalog.Slice(fresh)
    local again = pass.on and (fresh or pass.stale)
    if again and pass.restarts >= RESTARTS then return false end
    if again or not pass.on then
        pass.restarts = again and pass.restarts + 1 or 0
        Queue()
    end
    if not Read() then return nil end
    return true, Land()
end
