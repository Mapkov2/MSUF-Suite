local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Exports for the options page, MSUF Edit Mode and MSUF: bar
-- and picker rows, Blizzard's layout snapshot, previews, status, sounds,
-- the position conversions that keep a bar in place when its growth edge
-- moves, and the movers. A loaded but inactive module answers from a cold
-- settings snapshot (C.Cold). The preview export stays in Controller.lua
-- and the spec export in Events.lua, with the state they use.
local M = C.M
local ID = "cooldownManager"
local CDM = NS.CDM
local SLOTS, KEYS = CDM.SLOTS, CDM.KEYS
local EMPTY = C.EMPTY
local K = C.Const
local KIND = K.KIND
local Finite, Clamp = S.Finite, K.Clamp
local Dispatch = S.Dispatch
local Cold = C.Cold
local ceil = math.ceil
local wipe = C.wipe

------------------------------------------------------------------ bar and picker rows
local keyScratch, describe, homes = {}, {}, {}

-- A press on the suite action bars (MSUF_Suite_ActionBars calls it) lights
-- the icons of the pressed spell. Published only while that is wanted (the
-- module runs and "Show action bar presses on cooldown icons" is on), so
-- the action bars read no action on a press otherwise.
local function ActionPressed(spellID)
    if not M.active or not S.Public(spellID) or type(spellID) ~= "number" then return end
    C.Index.ForSpell(spellID, nil, C.Effects.Press)
end
function C.PressBridge()
    S.CooldownManagerActionPressed = M.active == true and C.state.pressFeedback == true and ActionPressed or nil
end

-- Why a listed entry does not show on its bar now: "cap" (past Maximum
-- icons), "ready" (Hide icons that are ready) or "empty" (no Healthstone in
-- the bags, Time: entry.empty); nil while it shows.
local function HiddenBy(placed, cap, hide, live, desc)
    if cap ~= nil and placed >= cap then return "cap" end
    if hide and live ~= nil and desc.family == K.FAMILY.COOLDOWN and not live.cooling then return "ready" end
    if live ~= nil and live.empty == true then return "empty" end
end

-- The bar's keys for the current spec in display order, unlearned ones
-- included; hidden (and hiddenBy) marks what a bar rule hides in live play.
-- Entries past Maximum icons that "Send excess cooldowns to" moves to
-- another bar are not hidden: movedTo names the bar they show on.
function S.CooldownManagerBarEntries(slot)
    local rows = {}
    if not CDM.SLOT_INDEX[slot] then return rows end
    Cold()
    local keys = C.Resolve.Keys(slot, keyScratch)
    local view = C.views[slot] or EMPTY
    local cap = view.maxIcons
    if type(cap) ~= "number" or cap <= 0 then cap = nil end
    local moved = cap and C.Resolve.OverflowTarget(slot)
    local spells = C.Choices()
    -- Only learned entries take a place (Resolve builds nothing else).
    local placed = 0
    for i = 1, #keys do
        local key = keys[i]
        local live = C.entries[key]
        if live and live.slot ~= slot then live = nil end
        local desc = live or C.Resolve.Describe(key, describe)
        if desc then
            local ov = spells[key]
            if type(ov) ~= "table" then ov = EMPTY end
            local hide = ov.hideReady
            if hide == nil then hide = view.hideReady == true end
            local hiddenBy = HiddenBy(placed, cap, hide, live, desc)
            if desc.known ~= false then placed = placed + 1 end
            local movedTo = hiddenBy == "cap" and moved or nil
            if movedTo then hiddenBy = nil end
            rows[#rows + 1] = { key = key, name = desc.name, texture = ov.icon or desc.texture, known = desc.known ~= false, family = desc.family,
                hasAura = desc.hasAura == true, hidden = hiddenBy ~= nil, hiddenBy = hiddenBy, movedTo = movedTo }
        end
    end
    return rows
end

-- Read the active Blizzard CooldownViewer layout for this specialization.
-- Order and category moves come from Catalog.Rebuild; hidden pseudo-categories
-- are absent. Include unlearned entries so a talent switch keeps its layout.
-- This only returns a copy: importing is an explicit options-page action.
function S.CooldownManagerBlizzardSnapshot()
    Cold()
    local catalog = C.Catalog
    if not catalog.Ready() then return nil, "Blizzard's cooldown list is not ready yet." end
    catalog.Rebuild()
    if not C.state.specTag or catalog.specTag ~= C.state.specTag then
        return nil, "Blizzard's cooldown list is not ready yet."
    end
    local bars = { ess = {}, uti = {}, buf = {}, bar = {}, ext = {} }
    local count = 0
    for slot, list in pairs(bars) do
        for pass = 1, 2 do
            for i = 1, #catalog.order do
                local rec = catalog.records[catalog.order[i]]
                if rec and rec.bar == slot and (catalog.TAIL[rec.category] == true) == (pass == 2) then
                    list[#list + 1] = rec.key
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then return nil, "Blizzard's cooldown list is empty." end
    return bars
end

-- Picker rows of one family; slot is the bar each entry lives on now.
function S.CooldownManagerCatalogEntries(family)
    Cold()
    wipe(homes)
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        local keys = C.Resolve.Keys(slot, keyScratch)
        for j = 1, #keys do
            if homes[keys[j]] == nil then homes[keys[j]] = slot end
        end
    end
    local rows = C.Catalog.List(family)
    for i = 1, #rows do rows[i].slot = homes[rows[i].key] end
    return rows
end

------------------------------------------------------------------ previews, status, sounds
function S.CooldownManagerRenderPreview(parent, slot, maxWidth, maxHeight)
    if not CDM.SLOT_INDEX[slot] or type(parent) ~= "table" then return nil end
    Cold()
    return C.Preview.Render(parent, slot, maxWidth, maxHeight)
end
function S.CooldownManagerReleasePreview(parent)
    C.Preview.Release(parent)
end
function S.CooldownManagerSimulate(on)
    return C.Preview.Simulate(on)
end

-- Moves with every Blizzard catalog rebuild; the page's tile memo keys on it.
function S.CooldownManagerGeneration() return C.Catalog.generation end

function S.CooldownManagerStatus()
    if not M.active then return nil end
    local mode, reason = C.Native.Mode()
    -- Every sentence is translated on its own and the reader gets them in a
    -- row: nothing is joined before it is translated.
    local sentences = { S.Text(mode == K.BLIZZARD.INVISIBLE and "Blizzard's cooldown bars keep running invisibly."
        or "Blizzard's cooldown bars are off.") }
    if reason then sentences[#sentences + 1] = reason end
    if not C.Catalog.Ready() then sentences[#sentences + 1] = S.Text("Waiting for Blizzard's cooldown data.") end
    return table.concat(sentences, " ")
end

function S.CooldownManagerPlaySound(value)
    return C.Alerts.Play(value, true)
end

------------------------------------------------------------------ position conversions
local offsetScratch = {}
-- Size of a bar's content as the layout will draw it. Cooldown bars count
-- their shown icons; aura bars reserve every entry within maxIcons, player
-- entries first and target-row entries (Auras.TargetRow) from a new line,
-- as Layout.PlaceAuras draws them.
local function Extent(view, plan)
    local list = plan.entries
    if plan.kind == KIND.COOLDOWN then
        local n, preview = 0, C.state.preview
        for i = 1, #list do
            local entry = list[i]
            if entry.icon and (preview or not entry.hidden or view.cooldownFixed) then n = n + 1 end
        end
        return C.Layout.Offsets(view, n, offsetScratch)
    end
    local cap = view.maxIcons
    if type(cap) ~= "number" or cap <= 0 then cap = #list end
    local n1, n2 = 0, 0
    for i = 1, #list do
        if n1 + n2 >= cap then break end
        if C.Auras.TargetRow(list[i]) then
            n2 = n2 + 1
        else
            n1 = n1 + 1
        end
    end
    local w, h, sp, per, vertical = C.Layout.Metrics(view)
    -- Fixed places on one line keep target entries on that line (Layout.PlaceAuras).
    local _, ordered, split = C.Layout.FixedAuras(view, list)
    if ordered or split then n1, n2 = n1 + n2, 0 end
    local lines = ceil(n1 / per) + ceil(n2 / per)
    if lines == 0 then return w, h end
    local along, across = w, h
    if vertical then along, across = h, w end
    local full = n1 > n2 and n1 or n2
    if full > per then full = per end
    local extent, depth = full * along + (full - 1) * sp, lines * across + (lines - 1) * sp
    if vertical then return depth, extent end
    return extent, depth
end

-- The bar's view as it would be with another growth or orientation: reads
-- fall through to the live view, which is never written, so a raising
-- Extent cannot leave the live bar changed.
local probeMeta = {}
local probe = setmetatable({}, probeMeta)
local function Probe(view, grow, vertical)
    probeMeta.__index = view
    probe.grow, probe.vertical = grow, vertical
    return probe
end

-- Grow direction and orientation move the growth-edge anchor. The new x/y
-- keep the bar's center where it is now (free bars that are shown only;
-- anyAnchor: attached bars too). The controller converts the riding
-- Essential bar through this as well (SyncViewerOffset).
local function Convert(slot, grow, vertical, anyAnchor)
    local keys = KEYS[slot]
    if not keys then return nil end
    local values = {}
    if grow ~= nil and keys.grow then values[keys.grow] = grow end
    if vertical ~= nil and keys.vertical then values[keys.vertical] = vertical end
    local view, bar, plan = C.views[slot], C.bars[slot], C.plans[slot]
    if not (M.active and view and bar and bar.shown and plan and (anyAnchor or C.Layout.Free(slot)) and UIParent) then return values end
    local left, bottom, w, h = bar.frame:GetRect()
    local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
    if not (Finite(left) and Finite(bottom) and Finite(w) and Finite(h) and Finite(uiW) and Finite(uiH)) then return values end
    local converted = Probe(view, grow, vertical)
    local nw, nh = Extent(converted, plan)
    local point = C.Layout.Point(converted)
    probeMeta.__index = nil
    local dx, dy = K.EdgeOffset(point, nw, nh)
    values[keys.x], values[keys.y] = Clamp(keys.x, left + w / 2 - uiW / 2 + dx), Clamp(keys.y, bottom + h / 2 - uiH / 2 + dy)
    return values
end
C.Convert = Convert

function S.CooldownManagerConvertGrow(slot, grow)
    if grow ~= K.GROW.DOWN and grow ~= K.GROW.UP then return nil end
    return Convert(slot, grow, nil)
end
function S.CooldownManagerConvertVertical(slot, vertical)
    return Convert(slot, nil, vertical == true)
end

-- The Essential bar riding Blizzard's bar after an attach change counts
-- its x/y from that bar: turning free it keeps its place as an offset from
-- it (zero when a rectangle is unreadable). The flag travels with the
-- values, so SyncViewerOffset finds nothing to convert on that Refresh.
-- The layout reads the attach chain from C.views, so the new anchor is set
-- on the live view for that one isolated question and always put back.
local function RideAnchor(values, anchor)
    local view = C.views.ess
    if not (M.active and view) then return end
    local old = view.anchor
    view.anchor = anchor
    local rides = Dispatch(C.Layout.RidesViewer, "ess") == true
    view.anchor = old
    values.essOnViewer = rides
    if not rides then return end
    local keys = KEYS.ess
    values[keys.x], values[keys.y] = 0, 0
    local bar = C.bars.ess
    local vx, vy = C.Layout.ViewerPoint(view)
    if not (vx and bar and bar.shown) then return end
    local left, bottom, w, h = bar.frame:GetRect()
    if not (Finite(left) and Finite(bottom) and Finite(w) and Finite(h)) then return end
    local point = C.Layout.Point(view)
    local x = point == "LEFT" and left or point == "RIGHT" and left + w or left + w / 2
    local y = point == "TOP" and bottom + h or point == "BOTTOM" and bottom or bottom + h / 2
    values[keys.x], values[keys.y] = Clamp(keys.x, x - vx), Clamp(keys.y, y - vy)
end

-- Attach changes keep the bar on screen: to Free, the x/y that hold its
-- current place; to a bar or unit frame, a zero offset from that anchor.
function S.CooldownManagerConvertAnchor(slot, anchor)
    local keys = KEYS[slot]
    if not keys or type(anchor) ~= "number" then return nil end
    local values
    if anchor == K.ANCHOR.FREE then
        values = Convert(slot, nil, nil, true) or {}
    else
        values = { [keys.x] = 0, [keys.y] = 0 }
    end
    values[keys.anchor] = anchor
    if slot == "ess" then RideAnchor(values, anchor) end
    return values
end
function S.CooldownManagerMovable(slot) return C.Layout.Movable(slot) end

------------------------------------------------------------------ Edit Mode movers
local movers = {}
local function Control(id, key)
    local rule = S.catalog[ID].rules[key]
    return { id = id, label = S.Text(rule.label), kind = "number", min = rule.min, max = rule.max, step = 1,
        get = function() return S.Config(ID)[key] end,
        set = function(value) return S.Set(ID, key, value) end }
end
local ICON_CONTROLS, BAR_CONTROLS = { "size", "spacing", "perRow" }, { "barWidth", "barHeight" }
-- Free bars move in MSUF Edit Mode; attached bars follow their parent.
local function Mover(i)
    local def = SLOTS[i]
    local slot, keys = def.key, KEYS[def.key]
    local list = keys.size and ICON_CONTROLS or BAR_CONTROLS
    local controls, history = {}, {}
    for j = 1, #list do
        local key = keys[list[j]]
        if key then
            controls[#controls + 1] = Control(list[j], key)
            history[#history + 1] = key
        end
    end
    return { label = def.title, order = 700 + i, xKey = keys.x, yKey = keys.y, extraControls = controls, historyKeys = history,
        getFrame = function()
            local bar = C.bars[slot]
            return bar and bar.frame
        end,
        point = function()
            local view = C.views[slot]
            return view and C.Layout.Point(view) or "TOP"
        end,
        place = function(x, y) return C.Layout.DragPlace(slot, x, y) end,
        isEnabled = function()
            local view = C.views[slot]
            return M.active == true and view ~= nil and view.on == true and C.plans[slot] ~= nil and C.Layout.Movable(slot)
        end }
end
local function AssistMover()
    return { label = "Assisted combat icon", order = 730, xKey = "assistIconX", yKey = "assistIconY",
        point = function() return "CENTER" end, getFrame = C.Effects.RecommendationFrame,
        isEnabled = function() return M.active == true and C.state.assistIcon == true end,
        historyKeys = { "assistIconSize" }, extraControls = { Control("size", "assistIconSize") } }
end
-- The controller asks after every Enable and Refresh; specs are built once.
function M:RegisterMovers()
    for i = 1, #SLOTS do
        movers[i] = movers[i] or Mover(i)
        S.RegisterOwnedMover(ID, SLOTS[i].key, movers[i])
    end
    movers.assist = movers.assist or AssistMover()
    S.RegisterOwnedMover(ID, "assistIcon", movers.assist)
end

------------------------------------------------------------------ MSUF
-- MSUF resolves its "anchor to cooldown bars" targets through this.
NS.CooldownManager = {
    GetAnchorFrame = function(viewerName) return C.Native.AnchorFrame(viewerName) end,
}
