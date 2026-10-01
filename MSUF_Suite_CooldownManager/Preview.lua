local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Sample state for MSUF Edit Mode ("edit") and the options page
-- ("options"): every bar visible, rules suspended, unlearned spells shown
-- and three sample icons on empty bars. The options page also gets a
-- standalone drawing of one bar (never a live bar) and an optional
-- simulation: an 8 s cooldown on the first icon of each bar, a proc glow on
-- the second and a buff glow on the third, from duration objects built out
-- of plain numbers. The simulation runs only while the page is open and out
-- of combat; its one ticker exists only while it runs. This file keeps its
-- own small constants; at load it reads only C.EMPTY and C.Layout.Shown
-- (Layout.lua loads first), so the options contract loads it with a stub
-- CDM table that has both.
local Pv = { mode = nil, sim = false }
C.Preview = Pv
local EMPTY = C.EMPTY
local pairs, type, max, min = pairs, type, math.max, math.min
local wipe = table.wipe
local QUESTION = 134400
local SIM_LENGTH, SIM_LOOP = 8, 10

------------------------------------------------------------------ sample icons
-- The first class spells of each family in Blizzard's order, unlearned ones
-- included; the question mark when the catalog has none.
local samples = { {}, {} }
local function Samples()
    local catalog = C.Catalog
    local order, records = catalog.order, catalog.records
    local a, b = samples[1], samples[2]
    wipe(a)
    wipe(b)
    for i = 1, #order do
        local rec = records[order[i]]
        local list = rec and samples[rec.family]
        if list and #list < 3 then
            local tex = catalog.RecordTexture(rec)
            if tex then list[#list + 1] = tex end
        end
        if #a >= 3 and #b >= 3 then break end
    end
end
local function Sample(family, n)
    local list = samples[family]
    return list and list[n] or QUESTION
end

-- Resolve rebuilds placeholders with the question mark; this runs after
-- every resolve while a preview is on.
function Pv.Decorate()
    if not Pv.mode then return end
    local filled = false
    for _, plan in pairs(C.plans) do
        local entries = plan.entries
        for i = 1, #entries do
            local entry = entries[i]
            if entry.src == "p" then
                if not filled then
                    Samples()
                    filled = true
                end
                entry.texture = Sample(entry.family, entry.id)
            end
        end
    end
end

------------------------------------------------------------------ mode
-- Returns true when the preview turned on or off (the controller then marks
-- resolve, cooldowns, effects, layout and visibility).
function Pv.SetMode(mode)
    if mode ~= "edit" and mode ~= "options" then mode = nil end
    if Pv.mode == mode then return false end
    local was = Pv.mode ~= nil
    Pv.mode = mode
    local on = mode ~= nil
    if mode ~= "options" then Pv.Simulate(false) end
    C.state.preview = on
    if was == on then return false end
    C.Auras.SetPreview(on)
    return true
end

------------------------------------------------------------------ simulation
local durations = setmetatable({}, { __mode = "k" })
local touched = {}   -- entry -> "cd"|"proc"|"aura" while simulated
local canvases = {}  -- canvas holders by parent
local ticker

local function Duration(icon)
    local d = durations[icon]
    if d == nil then
        d = C_DurationUtil.CreateDuration()
        durations[icon] = d
    end
    return d
end

local function Sim(entry, role)
    local icon = entry.icon
    if not icon then return end
    touched[entry] = role
    if role == "cd" then
        local d = Duration(icon)
        if d then
            d:SetTimeFromStart(GetTime(), SIM_LENGTH)
            C.Time.Simulate(entry, d)
        end
    else
        C.Effects.SetGlow(icon, role, true)
    end
end

-- Live icons return to their real state (a real proc glow comes back
-- through Update); canvas icons to rest.
local function Unsim(entry, role)
    local icon = entry.icon
    if not icon then return end
    if role == "cd" then
        if icon.sim then C.Time.Simulate(entry, nil) end
    else
        C.Effects.SetGlow(icon, role, false)
        if entry.src ~= "p" then C.Effects.Update(entry) end
    end
end

-- Sample icons that already run their role keep running (a repaint on a
-- slider tick restarts nothing); the ticker restarts every sample.
local ROLES = { "cd", "proc", "aura" }
local function Canvas(holder)
    local fakes = holder.fakes
    for i = 1, 3 do
        local fake, role = fakes[i], ROLES[i]
        if fake and i <= holder.count and holder.kind ~= 3 and touched[fake] ~= role then Sim(fake, role) end
    end
end

local function StopAll()
    for entry, role in pairs(touched) do
        touched[entry] = nil
        Unsim(entry, role)
    end
end

local function Restart()
    StopAll()
    if not Pv.sim then return end
    for _, plan in pairs(C.plans) do
        if plan.kind == 1 then
            local entries, n = plan.entries, 0
            for i = 1, #entries do
                local entry = entries[i]
                if entry.icon and n < 3 then
                    n = n + 1
                    Sim(entry, ROLES[n])
                end
            end
        end
    end
    for _, holder in pairs(canvases) do
        if holder.shown then Canvas(holder) end
    end
end
Pv.Restart = Restart

function Pv.Simulate(on)
    on = on == true
    if on and (Pv.mode ~= "options" or NS.IsCombatLocked() or not C.M.active) then on = false end
    if on == Pv.sim then return on end
    Pv.sim = on
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if on then
        ticker = C_Timer.NewTicker(SIM_LOOP, Restart)
        Restart()
    else
        StopAll()
    end
    return on
end

------------------------------------------------------------------ options canvas
-- One holder per parent frame, reused: standalone icons (kinds 1 and 2) or
-- simple rows (kind 3), in bar order with the cooldown layout math
-- (Layout.Offsets; aura bars without their player and target parts).
-- The options page lays its own mouse buttons over the drawing and reads,
-- after each Render: holder.count (items drawn), holder.kind, holder.items[i]
-- (the icon or row region), holder.keys[i] (the entry key, false for a
-- sample icon of an empty bar) and holder.dim[i] (unlearned or sample).
-- Plain table fields written in place: no widget call, nothing allocated.
local keyScratch, describe = {}, {}

local function Holder(parent)
    local holder = canvases[parent]
    if not holder then
        holder = S.CreateFrame("Frame", nil, parent)
        holder.icons, holder.rows, holder.fakes, holder.out, holder.look = {}, {}, {}, {}, { gen = 0 }
        holder.keys, holder.dim, holder.textures, holder.names = {}, {}, {}, {}
        holder.items = holder.icons
        holder.count, holder.shown = 0, false
        canvases[parent] = holder
    end
    return holder
end

-- What a bar's content depends on besides its own slot and kind: which bars
-- are on and their kinds (claims), by slot index.
local WEIGHT = {}
for i = 1, 16 do WEIGHT[i] = 8 ^ (i - 1) end
local function Bars()
    local sig = 0
    for _, view in pairs(C.views) do
        local weight = view.index and WEIGHT[view.index]
        if weight then sig = sig + ((view.on and 4 or 0) + (view.kind or 0)) * weight end
    end
    return sig
end
-- Resolving a bar's keys is the costly part of a repaint: it runs again only
-- when the catalog, the entries, the spec, the lists, the spell choices,
-- the preview mode or the bars moved (every settings tick repaints).
local function SameContent(holder, slot, kind)
    local catalog, state = C.Catalog, C.state
    local gen, entries = catalog and catalog.generation or 0, state.entryGen or 0
    local spec, bars, preview = state.specID or 0, Bars(), state.preview == true
    local same = holder.cSlot == slot and holder.cKind == kind and holder.cGen == gen and holder.cEntries == entries
        and holder.cSpec == spec and holder.cBars == bars and holder.cPreview == preview and holder.cLists == C.lists
        and holder.cSpells == C.spells
    holder.cSlot, holder.cKind, holder.cGen, holder.cEntries = slot, kind, gen, entries
    holder.cSpec, holder.cBars, holder.cPreview, holder.cLists, holder.cSpells = spec, bars, preview, C.lists, C.spells
    return same
end

-- Textures and names of what the bar holds now (or would hold when off);
-- unlearned spells included, sample icons for an empty bar.
local function Content(slot, kind, holder)
    local keys = C.Resolve.Keys(slot, keyScratch)
    -- The choices in effect for this specialization, as the live bars read them.
    local spells = C.Choices()
    local itemKeys, dim, textures, names = holder.keys, holder.dim, holder.textures, holder.names
    local n = 0
    for i = 1, #keys do
        local key = keys[i]
        local entry = C.entries[key]
        local tex, name, known
        if entry and entry.src ~= "p" then
            tex, name, known = entry.texture, entry.name, entry.known
        else
            local d = C.Resolve.Describe(key, describe)
            if d then tex, name, known = d.texture, d.name, d.known end
        end
        local ov = spells[key]
        if type(ov) == "table" and ov.icon then tex = ov.icon end
        n = n + 1
        textures[n], names[n] = tex or QUESTION, name or ""
        itemKeys[n], dim[n] = key, known == false
    end
    if n == 0 then
        Samples()
        local family = kind == 1 and 1 or 2
        for i = 1, 3 do textures[i], names[i], itemKeys[i], dim[i] = Sample(family, i), "", false, true end
        n = 3
    end
    for i = #textures, n + 1, -1 do textures[i], names[i] = nil, nil end
    for i = #itemKeys, n + 1, -1 do itemKeys[i], dim[i] = nil, nil end
    return n
end

-- Canvas writes are memoized like the live bars: a repaint of an unchanged
-- bar (every settings tick repaints the page) makes no widget calls. The
-- shown state uses the layout's memo (Layout.Shown).
local Shown = C.Layout.Shown
local function Place(region, parent, x, y)
    if region.pvX == x and region.pvY == y then return end
    region.pvX, region.pvY = x, y
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
end
local function HideFrom(list, first)
    for i = first, #list do Shown(list[i], false) end
end

local SAMPLE_CHARGES = { maxCharges = 3, currentCharges = 2, isActive = false }
local function Icons(holder, view, count, slot)
    local icons, fakes, out, textures = holder.icons, holder.fakes, holder.out, holder.textures
    for i = 1, count do
        local icon = icons[i]
        if not icon then
            icon = C.Icons.CreateStandalone(holder)
            icons[i] = icon
            -- A plain sample entry lets the glow and time layers find the bar.
            fakes[i] = { key = "preview", src = "p", id = i, family = 1, ov = EMPTY, icon = icon }
            icon.entry = fakes[i]
        end
        local fake = fakes[i]
        local key = holder.keys[i]
        local entry = key and C.entries[key]
        local ov = key and C.Choices()[key] or EMPTY
        if type(ov) ~= "table" then ov = EMPTY end
        local name = holder.names[i]
        if fake.ov ~= ov or fake.name ~= name or fake.slot ~= slot then icon.esEntry = nil end
        fake.slot, fake.ov, fake.name = slot, ov, name
        if C.Layout.MixedRows(view) then
            local iw, ih = C.Layout.Footprint(view, i)
            if icon.styleGen ~= view.styleGen or icon.styleView ~= view or icon.w ~= iw or icon.h ~= ih then C.Icons.StyleIcon(icon, view, iw, ih) end
        elseif icon.styleGen ~= view.styleGen or icon.styleView ~= view then
            C.Icons.StyleIcon(icon, view)
        end
        C.Icons.Apply(fake)
        local keyText = entry and entry.keyText
        C.Icons.SetKeybind(fake, keyText and keyText ~= "" and keyText or tostring(i))
        if icon.pvChargeView ~= view or icon.pvChargeStyle ~= view.styleGen then
            icon.pvChargeView, icon.pvChargeStyle = view, view.styleGen
            C.TrackingBars.Charges(icon, SAMPLE_CHARGES)
        end
        C.Icons.SetTexture(icon, textures[i])
        Place(icon, holder, out[2 * i - 1], out[2 * i])
        Shown(icon, true)
    end
    HideFrom(icons, count + 1)
    HideFrom(holder.rows, 1)
end

-- Buff bars use the same plain sample and live style as Edit Mode.
local function Rows(holder, view, count)
    local choices = C.Choices()
    for i = 1, count do
        local ov = choices[holder.keys[i]]
        if type(ov) ~= "table" then ov = EMPTY end
        local row = C.AuraButtons.Sample(holder, holder.rows[i], view, ov, holder.textures[i], holder.names[i])
        holder.rows[i] = row
        Place(row, holder, holder.out[2 * i - 1], holder.out[2 * i])
        Shown(row, true)
    end
    HideFrom(holder.rows, count + 1)
    HideFrom(holder.icons, 1)
end

-- Samples past the first keep ones stop (all of them for rows).
local function Rest(holder, keep)
    local fakes = holder.fakes
    for i = keep + 1, #fakes do
        local role = touched[fakes[i]]
        if role then
            touched[fakes[i]] = nil
            Unsim(fakes[i], role)
        end
    end
end

-- Draws one bar into parent, scaled down only when it exceeds the space.
function Pv.Render(parent, slot, maxWidth, maxHeight)
    local view = parent and C.views[slot]
    if not view then return nil end
    local holder = Holder(parent)
    local kind = view.kind or 1
    local n = holder.n
    if not SameContent(holder, slot, kind) or not n then
        n = Content(slot, kind, holder)
        holder.n = n
    end
    local width, height, count = C.Layout.Offsets(view, n, holder.out)
    Rest(holder, kind ~= 3 and count or 0)
    if kind == 3 then
        Rows(holder, view, count)
    else
        Icons(holder, view, count, slot)
    end
    holder.kind, holder.count, holder.slot = kind, count, slot
    holder.items = kind == 3 and holder.rows or holder.icons
    if holder.pvW ~= width or holder.pvH ~= height then
        holder.pvW, holder.pvH = width, height
        holder:SetSize(width, height)
    end
    local scale = 1
    if type(maxWidth) == "number" and maxWidth > 0 and width > maxWidth then scale = maxWidth / width end
    if type(maxHeight) == "number" and maxHeight > 0 and height * scale > maxHeight then scale = maxHeight / height end
    scale = max(.1, min(1, scale))
    if holder.pvScale ~= scale then
        holder.pvScale = scale
        holder:SetScale(scale)
    end
    if not holder.shown then
        holder.shown = true
        holder:Show()
    end
    if Pv.sim then Canvas(holder) end
    return holder
end

function Pv.Release(parent)
    local holder = canvases[parent]
    if not holder then return end
    Rest(holder, 0)
    holder.shown, holder.cSlot = false, nil
    holder:Hide()
end

function Pv.ReleaseAll()
    for parent in pairs(canvases) do Pv.Release(parent) end
end
