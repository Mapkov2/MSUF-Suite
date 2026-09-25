local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Blizzard Cooldown Manager snapshot. Reads the category sets and the user's
-- saved layout through read-only C APIs (never Blizzard's data provider or
-- layout manager) and keeps whitelisted copies, so no Blizzard table is held.
-- The bar contents follow Blizzard's own rules: default order per category,
-- HideByDefault, the saved global order, then per-cooldown category moves.
-- Cold path only; allocation is fine here.
local Public = S.Public
local type, pairs, tonumber, select, floor = type, pairs, tonumber, select, math.floor
local EMPTY = C.EMPTY
local wipe = C.wipe

-- generation moves with every rebuild, content only when a rebuild changed
-- a record, an order or a bar list.
local Catalog = { records = {}, order = {}, generation = 0, content = 0, byBar = { ess = {}, uti = {}, buf = {}, bar = {}, ext = {} },
    defaultByBar = { ess = {}, uti = {}, buf = {}, bar = {} }, byBase = {},
    equipBars = {} }
C.Catalog = Catalog

-- Blizzard's fetch order (CooldownViewerSettingsDataProvider cooldownCategories).
local CAT_ORDER = { 0, 1, 2, 3, 7, 8, 5, 6 }
-- HideByDefault moves bar categories into the hidden pseudo-categories; the
-- item pools stay in their own category (that is their "not shown" state).
local HIDDEN_OF = { [0] = -1, [1] = -1, [2] = -2, [3] = -2, [5] = 5, [6] = 6, [7] = 7, [8] = 8 }
local FAMILY = { [-1] = 1, [0] = 1, [1] = 1, [5] = 1, [7] = 1, [-2] = 2, [2] = 2, [3] = 2, [6] = 2, [8] = 2 }
-- Equipment slots (7, trinkets) join Essential; potions and healthstones (5)
-- stay on Potions and racials. TAIL categories follow their bar's own
-- entries, in Blizzard's order among themselves; a trinket moved into
-- Essential in Blizzard's settings (category 0) keeps its saved place.
local BAR_OF = { [0] = "ess", [1] = "uti", [2] = "buf", [3] = "bar", [5] = "ext", [7] = "ess", [6] = "buf", [8] = "buf" }
local TAIL = { [7] = true }
Catalog.BAR_OF, Catalog.TAIL = BAR_OF, TAIL
local HIDE_BY_DEFAULT = 2
local CATEGORY_ICON = C.Const.CATEGORY_ICONS
local CATEGORY_TITLE = { [4] = { "COOLDOWN_VIEWER_TOOLTIP_POTION_COMBAT_TITLE", "Combat potion" },
    [30] = { "COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTH_TITLE", "Health potion" },
    [1711] = { "COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTHSTONE_TITLE", "Healthstone" },
    [2566] = { "COOLDOWN_VIEWER_TOOLTIP_POTION_DEMONIC_HEALTHSTONE_TITLE", "Demonic Healthstone" } }

------------------------------------------------------------------ plain-value helpers
local function Num(v)
    if Public(v) and type(v) == "number" and v > 0 then return v end
end
local function Flag(v) return Public(v) and v == true end
Catalog.Num, Catalog.Flag = Num, Flag

local band = bit and bit.band
local function HiddenByDefault(flags)
    if not (Public(flags) and type(flags) == "number") then return false end
    if band then return band(flags, HIDE_BY_DEFAULT) ~= 0 end
    return floor(flags / HIDE_BY_DEFAULT) % 2 == 1
end

local function SpellTexture(spell)
    local get = spell and C_Spell and C_Spell.GetSpellTexture
    if not get then return nil end
    local icon, _, conditional = get(spell)
    if Public(conditional) and conditional then return conditional end
    if Public(icon) and icon then return icon end
end
local function SpellName(spell)
    local get = spell and C_Spell and C_Spell.GetSpellName
    local name = get and get(spell)
    if Public(name) and type(name) == "string" and name ~= "" then return name end
end
local function EquipItem(slot)
    local id = slot and GetInventoryItemID and GetInventoryItemID("player", slot)
    return Num(id)
end
local function EquipTexture(slot)
    if not slot then return nil end
    local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", slot)
    if Public(tex) and tex then return tex end
    -- Empty slot: the paper-doll slot art, as Blizzard's viewer shows it.
    local info = C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfoForInvSlot
    if info then
        local _, icon = info(slot)
        if Public(icon) and icon then return icon end
    end
end
local function ItemName(item)
    local get = item and C_Item and C_Item.GetItemNameByID
    local name = get and get(item)
    if Public(name) and type(name) == "string" and name ~= "" then return name end
end
local function ItemIcon(item)
    local get = item and C_Item and C_Item.GetItemIconByID
    local icon = get and get(item)
    if Public(icon) and icon then return icon end
end
local function ItemSpell(item)
    local get = item and C_Item and C_Item.GetItemSpell
    if not get then return nil end
    local _, spell = get(item)
    return Num(spell)
end
local function SlotLabel(slot)
    if slot == 13 then return S.Text("Trinket 1") end
    if slot == 14 then return S.Text("Trinket 2") end
    return S.Text("Equipment slot") .. " " .. slot
end
Catalog.SpellTexture, Catalog.SpellName, Catalog.EquipItem, Catalog.EquipTexture = SpellTexture, SpellName, EquipItem, EquipTexture
Catalog.ItemName, Catalog.ItemIcon, Catalog.ItemSpell, Catalog.SlotLabel = ItemName, ItemIcon, ItemSpell, SlotLabel

-- Static viewer rules (dynamic aura and linked-spell swaps are not mirrored):
-- category icon, equipped item, tooltip spell, then the base spell (the client
-- applies the override itself).
function Catalog.RecordTexture(rec)
    local icon = rec.spellCategory and CATEGORY_ICON[rec.spellCategory]
    if icon then return icon end
    if rec.equipSlot then
        local tex = EquipTexture(rec.equipSlot)
        if tex then return tex end
    end
    return SpellTexture(rec.tooltip) or SpellTexture(rec.spell)
end
function Catalog.RecordName(rec)
    local name = rec.equipSlot and ItemName(EquipItem(rec.equipSlot))
    if name then return name end
    name = SpellName(rec.tooltip or rec.override or rec.spell)
    if name then return name end
    local title = rec.spellCategory and CATEGORY_TITLE[rec.spellCategory]
    if title then
        local text = _G[title[1]]
        if Public(text) and type(text) == "string" and text ~= "" then return text end
        return S.Text(title[2])
    end
end

------------------------------------------------------------------ readiness
-- Blizzard initializes its layout data after these three events. The runtime
-- usually loads later, so a non-empty Essential set also counts as ready.
-- The gate frame exists only while that check fails: loading the runtime
-- (the options page does it with the module off) creates nothing. After
-- login only the data event can still be ahead of us.
local gate = { VARIABLES_LOADED = false, PLAYER_ENTERING_WORLD = false, COOLDOWN_VIEWER_DATA_LOADED = false }
local ready, gateFrame = false, nil
local function GateComplete()
    for _, seen in pairs(gate) do
        if not seen then
            return false
        end
    end
    return true
end
local function SetReady()
    ready = true
    if gateFrame then
        gateFrame:UnregisterAllEvents()
        gateFrame:SetScript("OnEvent", nil)
        gateFrame = nil
    end
end
local function OnGate(_, event)
    gate[event] = true
    if GateComplete() then SetReady() end
end
local function Watch()
    if gateFrame or type(CreateFrame) ~= "function" then return end
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    local logged = type(IsLoggedIn) == "function" and IsLoggedIn() == true
    for event in pairs(gate) do
        if (valid and not valid(event)) or (logged and event ~= "COOLDOWN_VIEWER_DATA_LOADED") then gate[event] = true end
    end
    if GateComplete() then
        SetReady()
        return
    end
    gateFrame = S.CreateFrame("Frame")
    for event, seen in pairs(gate) do
        if not seen then gateFrame:RegisterEvent(event) end
    end
    gateFrame:SetScript("OnEvent", OnGate)
end
function Catalog.Ready()
    if ready then return true end
    local viewer = C_CooldownViewer
    local get = viewer and viewer.GetCooldownViewerCategorySet
    -- A spec can have no Essential entry. Any populated spell or aura category
    -- proves the viewer data exists, including after a late module load.
    local populated = false
    for category = 0, 3 do
        local ids = get and get(category, true)
        if Public(ids) and type(ids) == "table" and #ids > 0 then
            populated = true
            break
        end
    end
    if populated then
        SetReady()
    else
        Watch()
    end
    return ready
end

------------------------------------------------------------------ layout decode
-- GetLayoutData is "<encoding>|" .. Base64(Deflate(CBOR)). Decoded once per
-- distinct string; the cache is set before decoding so a string the client
-- rejects is not retried on every rebuild.
local lastBlob, lastData = nil, nil
local function Decode(blob)
    if not Public(blob) then return lastData end
    if type(blob) ~= "string" then blob = "" end
    if blob == lastBlob then return lastData end
    lastBlob, lastData = blob, nil
    if blob == "" then return nil end
    local util = C_EncodingUtil
    if not (util and util.DecodeBase64 and util.DecompressString and util.DeserializeCBOR) then return nil end
    local bar = blob:find("|", 1, true)
    if not bar or tonumber(blob:sub(1, bar - 1)) ~= 1 then return nil end
    local raw = util.DecodeBase64(blob:sub(bar + 1))
    if type(raw) ~= "string" or raw == "" then return nil end
    local deflate = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
    local inflated = util.DecompressString(raw, deflate)
    if type(inflated) ~= "string" or inflated == "" then return nil end
    local data = util.DeserializeCBOR(inflated)
    if type(data) ~= "table" then return nil end
    local version = data[1]
    -- Blizzard has readers for save formats 1-5 only; others are ignored.
    if type(version) ~= "number" or version < 1 or version > 5 or floor(version) ~= version then return nil end
    lastData = data
    return data
end

local function Lower(a, b)
    local ta, tb = type(a), type(b)
    if ta == tb and (ta == "number" or ta == "string") then return a < b end
    return ta == "number" and tb ~= "number"
end
-- v4+: [2][tag] is a layout ID (0 = the starter layout, no customization);
-- v2/v3: a layout name; v1 has no active map. Blizzard's fallback is the first
-- layout of the tag in pairs() order; the lowest key stands in for it.
local function ActiveLayout(data, tag)
    if not (data and tag) then return nil end
    local version = data[1]
    local layouts, active = data[3], data[2]
    local mine = type(layouts) == "table" and layouts[tag] or nil
    local want = version >= 2 and type(active) == "table" and active[tag] or nil
    if version >= 4 and want == 0 then return nil end
    if type(mine) ~= "table" then return nil end
    if want ~= nil and type(mine[want]) == "table" then return mine[want] end
    local best
    for key, layout in pairs(mine) do
        if type(layout) == "table" and (best == nil or Lower(key, best)) then best = key end
    end
    return best ~= nil and mine[best] or nil
end

local function SpecTag()
    local classID = UnitClass and select(3, UnitClass("player"))
    local info = C_SpecializationInfo
    local spec = info and info.GetSpecialization and info.GetSpecialization()
    if Num(classID) and Public(spec) and type(spec) == "number" then return classID * 10 + spec end
end
Catalog.SpecTag = SpecTag

------------------------------------------------------------------ rebuild
local fetched, defaultOrder, merged, kept, eff, linkedTmp = {}, {}, {}, {}, {}, {}
local bars = { ess = {}, uti = {}, buf = {}, bar = {}, ext = {} }
local defaultBars = { ess = {}, uti = {}, buf = {}, bar = {} }
local defaultSeen = {}
local tailTmp, equipTmp = {}, {}
local basePool = {}
local changed = false

local function Put(rec, field, value)
    if rec[field] ~= value then
        rec[field] = value
        changed = true
    end
end
local function CopyLinked(rec, list)
    local n = 0
    if type(list) == "table" then
        for i = 1, #list do
            local id = Num(list[i])
            if id then
                n = n + 1
                linkedTmp[n] = id
            end
        end
    end
    for i = #linkedTmp, n + 1, -1 do linkedTmp[i] = nil end
    local old = rec.linked
    if old and #old == n then
        local same = true
        for i = 1, n do
            if old[i] ~= linkedTmp[i] then
                same = false
                break
            end
        end
        if same then return end
    end
    if n == 0 then
        rec.linked = EMPTY
    else
        local copy = {}
        for i = 1, n do copy[i] = linkedTmp[i] end
        rec.linked = copy
    end
    changed = true
end

-- One whitelisted record per cooldownID. The returned info table is read and
-- dropped; nothing of it is kept.
local function Copy(id, info, category)
    local records = Catalog.records
    local rec = records[id]
    if not rec then
        rec = { id = id, key = "b" .. id }
        records[id] = rec
        changed = true
    end
    local cat = info.category
    if not (Public(cat) and type(cat) == "number") then cat = category end
    local hidden = HiddenByDefault(info.flags)
    local default = hidden and HIDDEN_OF[cat] or cat
    Put(rec, "spell", Num(info.spellID))
    Put(rec, "override", Num(info.overrideSpellID))
    Put(rec, "tooltip", Num(info.overrideTooltipSpellID))
    Put(rec, "equipSlot", Num(info.equipSlot))
    Put(rec, "spellCategory", Num(info.spellCategoryID))
    Put(rec, "selfAura", Flag(info.selfAura))
    Put(rec, "hasAura", Flag(info.hasAura))
    Put(rec, "charges", Flag(info.charges))
    Put(rec, "known", Flag(info.isKnown))
    Put(rec, "defaultCategory", default)
    CopyLinked(rec, info.linkedSpellIDs)
    eff[id] = default
end

local function Fetch()
    local viewer = C_CooldownViewer
    local getSet, getInfo = viewer.GetCooldownViewerCategorySet, viewer.GetCooldownViewerCooldownInfo
    -- Blizzard currently shows invisible entries (CDM_HIDE_INVISIBLE_ITEMS is false).
    local hideInvisible = _G.CDM_HIDE_INVISIBLE_ITEMS == true
    local n = 0
    for c = 1, #CAT_ORDER do
        local category = CAT_ORDER[c]
        local ids = getSet(category, true)
        if Public(ids) and type(ids) == "table" then
            for j = 1, #ids do
                local id = Num(ids[j])
                -- A cooldownID listed by two sets keeps its first position.
                if id and not fetched[id] then
                    local info = getInfo(id)
                    if Public(info) and type(info) == "table" and not (hideInvisible and Flag(info.isInvisible)) then
                        Copy(id, info, category)
                        fetched[id] = true
                        n = n + 1
                        defaultOrder[n] = id
                    end
                end
            end
        end
    end
    for i = #defaultOrder, n + 1, -1 do defaultOrder[i] = nil end
    return n
end

-- Saved order: keep saved IDs that still exist, in saved order, then append
-- new IDs in default order. Category moves apply to existing IDs only.
local function ApplyLayout(layout)
    local order, n = defaultOrder, #defaultOrder
    local saved = layout and layout[1]
    if type(saved) == "table" then
        wipe(kept)
        local m = 0
        for i = 1, #saved do
            local id = saved[i]
            if id ~= nil and fetched[id] and not kept[id] then
                kept[id] = true
                m = m + 1
                merged[m] = id
            end
        end
        for i = 1, n do
            local id = defaultOrder[i]
            if not kept[id] then
                m = m + 1
                merged[m] = id
            end
        end
        for i = #merged, m + 1, -1 do merged[i] = nil end
        order = merged
    end
    local moves = layout and layout[2]
    if type(moves) == "table" then
        for cat, ids in pairs(moves) do
            local c = tonumber(cat)
            if c and type(ids) == "table" then
                for _, id in pairs(ids) do
                    if fetched[id] then eff[id] = c end
                end
            end
        end
    end
    return order
end

local function Commit(dst, src)
    local n, diff = #src, #dst ~= #src
    for i = 1, n do
        if dst[i] ~= src[i] then
            dst[i] = src[i]
            diff = true
        end
    end
    for i = #dst, n + 1, -1 do dst[i] = nil end
    if diff then changed = true end
end

-- Records by base spell: an override update that names no tracked spell
-- costs one lookup. Arrays are pooled across rebuilds.
local function IndexBases()
    local byBase = Catalog.byBase
    for spell, list in pairs(byBase) do
        for i = #list, 1, -1 do list[i] = nil end
        basePool[#basePool + 1] = list
        byBase[spell] = nil
    end
    for _, rec in pairs(Catalog.records) do
        local spell = rec.spell
        if spell then
            local list = byBase[spell]
            if not list then
                local n = #basePool
                list = basePool[n] or {}
                basePool[n] = nil
                byBase[spell] = list
            end
            list[#list + 1] = rec
        end
    end
end

function Catalog.Rebuild()
    if not Catalog.Ready() then return false end
    local viewer = C_CooldownViewer
    if not (viewer and viewer.GetCooldownViewerCategorySet and viewer.GetCooldownViewerCooldownInfo) then return false end
    changed = false
    local tag = SpecTag()
    -- Decode first: if the client rejects the string, nothing is half-built.
    local getLayout, blob = viewer.GetLayoutData, nil
    if getLayout then blob = getLayout() end
    local data = Decode(blob)
    local layout = ActiveLayout(data, tag)
    wipe(fetched)
    wipe(eff)
    Fetch()
    local order = ApplyLayout(layout)
    local records = Catalog.records
    for id, rec in pairs(records) do
        if not fetched[id] then
            records[id] = nil
            changed = true
        end
    end
    for _, list in pairs(bars) do wipe(list) end
    for _, list in pairs(defaultBars) do wipe(list) end
    wipe(equipTmp)
    -- Guide-authored order/category moves refine Utility and both buff rows
    -- for this spec. Current client records are authoritative: guide IDs that
    -- no longer exist disappear, while newly added client IDs append in stock
    -- order. The player's saved Blizzard layout is still an explicit import.
    local guide = C.GuideProfiles and C.GuideProfiles[C.state.specID]
    local guideOrder = guide and guide.order
    local guideMoves = guide and guide.moves
    wipe(defaultSeen)
    local function AddDefault(id)
        if defaultSeen[id] then return end
        defaultSeen[id] = true
        local rec = records[id]
        if not rec then return end
        local category = guideMoves and guideMoves[id] or rec.defaultCategory
        local slot = BAR_OF[category]
        local list = defaultBars[slot]
        if list then list[#list + 1] = rec.key end
    end
    for i = 1, #(guideOrder or EMPTY) do AddDefault(guideOrder[i]) end
    for i = 1, #defaultOrder do AddDefault(defaultOrder[i]) end
    local t = 0
    for i = 1, #order do
        local id = order[i]
        local rec = records[id]
        local cat = eff[id]
        Put(rec, "category", cat)
        Put(rec, "family", FAMILY[cat] or FAMILY[rec.defaultCategory])
        Put(rec, "bar", BAR_OF[cat])
        -- Bars that hold an equipment slot, learned or not: a gear change
        -- there can add, remove or restyle an entry.
        if rec.equipSlot and rec.bar then equipTmp[rec.bar] = true end
        if rec.known and rec.bar then
            if TAIL[cat] then
                t = t + 1
                tailTmp[t] = id
            else
                local list = bars[rec.bar]
                list[#list + 1] = id
            end
        end
    end
    for i = 1, t do
        local id = tailTmp[i]
        local list = bars[records[id].bar]
        list[#list + 1] = id
    end
    for i = #tailTmp, t + 1, -1 do tailTmp[i] = nil end
    Commit(Catalog.order, order)
    for key, list in pairs(bars) do Commit(Catalog.byBar[key], list) end
    for key, list in pairs(defaultBars) do Commit(Catalog.defaultByBar[key], list) end
    local equipBars = Catalog.equipBars
    for key in pairs(equipBars) do
        if not equipTmp[key] then
            equipBars[key] = nil
            changed = true
        end
    end
    for key in pairs(equipTmp) do
        if not equipBars[key] then
            equipBars[key] = true
            changed = true
        end
    end
    IndexBases()
    if Catalog.specTag ~= tag then
        Catalog.specTag = tag
        changed = true
    end
    Catalog.generation = Catalog.generation + 1
    if changed then Catalog.content = Catalog.content + 1 end
    return changed
end

------------------------------------------------------------------ overrides
-- COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED(base, override|nil). Runs in
-- combat: records come from byBase, live entries from the routing index
-- (every entry on a shown bar by base spell), so a base nothing tracks
-- costs two lookups. No allocation beyond the client's own strings.
local function Override(entry, base, override)
    entry.prevOverride = entry.override
    entry.override = override
    entry.spell = override or base
    if entry.auraIDs and override then entry.auraIDs[override] = true end
    local rec = entry.src == "b" and Catalog.records[entry.id]
    if rec then
        entry.texture = Catalog.RecordTexture(rec) or entry.texture
        entry.name = Catalog.RecordName(rec) or entry.name
    else
        entry.texture = SpellTexture(base) or entry.texture
        entry.name = SpellName(entry.spell) or entry.name
    end
end
function Catalog.OnOverride(base, override)
    base, override = Num(base), Num(override)
    if not base then return false end
    local recs = Catalog.byBase[base]
    local index = C.Index
    local list = index and index.byBase and index.byBase[base]
    if not recs and not list then return false end
    local any = false
    if recs then
        for i = 1, #recs do
            local rec = recs[i]
            if rec.override ~= override then
                rec.override = override
                any = true
            end
        end
    end
    if list then
        for i = 1, #list do
            local entry = list[i]
            if (entry.src == "b" or entry.src == "s") and entry.base == base and entry.override ~= override then
                Override(entry, base, override)
                any = true
            end
        end
    end
    -- Entry names and textures moved: the options canvas draws again.
    if any then C.state.entryGen = (C.state.entryGen or 0) + 1 end
    return any
end

-- The saved Blizzard layout differs from the last one decoded (cold; the
-- layout callbacks rebuild only then).
function Catalog.LayoutStale()
    local viewer = C_CooldownViewer
    local get = viewer and viewer.GetLayoutData
    if not get then return false end
    local blob = get()
    if not Public(blob) then return true end
    if type(blob) ~= "string" then blob = "" end
    return blob ~= lastBlob
end

------------------------------------------------------------------ picker rows
-- Blizzard entries of one family (unlearned ones flagged) with their spell
-- IDs, so the picker finds them by ID. Trinket slots are the page's own
-- section. The caller owns the rows.
function Catalog.List(family)
    local rows, n = {}, 0
    local records, entries = Catalog.records, C.entries
    local order = Catalog.order
    for i = 1, #order do
        local rec = records[order[i]]
        if rec and rec.family == family then
            local placed = entries[rec.key]
            n = n + 1
            rows[n] = { key = rec.key, name = Catalog.RecordName(rec), texture = Catalog.RecordTexture(rec), known = rec.known,
                category = rec.category, family = family, slot = placed and placed.slot or nil,
                spell = rec.spell, override = rec.override, tooltip = rec.tooltip }
        end
    end
    return rows
end
