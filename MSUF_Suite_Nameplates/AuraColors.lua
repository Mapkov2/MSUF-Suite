local _, private = ...
local NS, A = private.NS, private.NS.NameplateAuraColors
local Colors = {}
private.AuraColors = Colors
local states = setmetatable({}, { __mode = "k" })
local module, refresh, config, rows, revision, plan = nil, nil, nil, {}, 0, nil
local waiting, editMode = false, false
-- A public fixed span exceeds every supported nameplate height. Hidden
-- native slots collapse to zero; no secret size or visibility is read.
local SPAN = 4096
local EMPTY_FILTER = { includeSpellIDs = { [1] = true } }

local function Paint(texture, hex)
    texture:SetColorTexture(NS.RGB(hex))
end

-- Blizzard seals each native slot once its initializeFrame returns: the
-- provider runs initializeFrame, then ApplyAccessRestrictions with
-- DenyTaintedAccessWhenAurasAreSecret (AuraContainerFrameProviders.lua:78-86,
-- AuraContainerShared.lua:108; live, ptr2 and forever). While auras are
-- secret, addon code may then not even name the slot as an anchor target.
-- Each slot's initializeFrame anchors an own marker to the slot's top.
-- Markers stay outside the slot hierarchy, but their layout dependencies
-- still reach it: a mask anchored to a marker can become inaccessible too.
-- Build mask geometry once, before that dependency is established; later
-- configuration only updates native filters and ordinary fill textures. The
-- container calls it makes (AddAuraSlot, SetAuraSlotCandidateFilters,
-- SetEnabled, SetUnit; Blizzard_CustomAuraContainer.lua,
-- Blizzard_AuraContainer.lua:28-48) carry no combat or secret restriction:
-- access restrictions are applied to the slots only.
local function Marker(state, button)
    local marker = CreateFrame("Frame", nil, state.wrapper, "DisableUntrustedLayoutScriptsTemplate")
    marker:SetIgnoringChildrenForBounds(true)
    marker:SetSize(1, 1)
    marker:SetPoint("BOTTOM", button, "TOP", 0, 0)
    return marker
end

-- Only Forever's gamepad navigation still holds builds back: while a panel is
-- open it would walk each new slot from our execution and throw
-- (MSUF_Suite/Core/Platform.lua AuraBuildBlocked). The panel's closing
-- resumes them (Colors.Resume); the plate waits uncolored meanwhile.
local function Blocked()
    if not NS.Client.AuraBuildBlocked() then return false end
    NS.Client.AfterAuraBuild(Colors, Colors.Resume)
    waiting = true
    return true
end

-- Each active colour predicate has its own (layer, sublevel): the hidden
-- count variants share a rank but never draw together. Rank 0 is lowest; New gives
-- rows LIMIT..1 ranks 0..LIMIT-1, then "all" (it beats every row) and "none"
-- (its mask excludes the others). The band lies above the native fill
-- (StatusBar ARTWORK 0), absorb art (ARTWORK 1-2) and the role tint
-- (Skin.lua, ARTWORK 3), below the selection border and dim overlay
-- (OVERLAY 0), the health text (OVERLAY 1) and the aggro flash (OVERLAY 2):
-- healthBar layers in Blizzard_NamePlates.xml, the same on live, ptr2 and
-- forever. ARTWORK 4-7 and OVERLAY -8..-1 hold up to twelve ranks.
local function DrawLevel(rank)
    if rank < 4 then return "ARTWORK", 4 + rank end
    return "OVERLAY", rank - 12
end

local function Layer(state, health, rank)
    local layer, sublevel = DrawLevel(rank)
    local texture = health:CreateTexture(nil, layer, nil, sublevel)
    local mask = state.wrapper:CreateMaskTexture()
    mask:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    mask:SetHeight(SPAN)
    texture:AddMaskTexture(mask)
    texture:Hide()
    return { texture = texture, mask = mask }
end

-- The top of the plate's own frame tree (WorldFrame for Blizzard's
-- nameplates, read here rather than assumed): the masks then share the
-- plates' visibility. Under UIParent they hid with the interface (Alt+Z
-- hides UIParent only) while the plate and its colour textures stayed,
-- unmasked over the whole bar.
local function Root(frame)
    local parent = frame:GetParent()
    while parent do frame, parent = parent, parent:GetParent() end
    return frame
end

local function New(health)
    local state = { slots = {}, singles = {}, layers = {}, allCounts = {}, noneCounts = {} }
    -- Keep the large predicate slots out of Blizzard's pooled nameplate
    -- hierarchy, beside the plates. Only the small fill textures belong to
    -- the health bar.
    state.wrapper = CreateFrame("Frame", nil, Root(health), "DisableUntrustedLayoutScriptsTemplate")
    state.wrapper:SetIgnoringChildrenForBounds(true)
    state.wrapper:SetAllPoints(health)
    state.container = CreateFrame("AuraContainer", nil, state.wrapper, "CustomAuraContainerTemplate")
    -- No Edit Mode samples in the DoT predicate (12.1.5, Forever; Platform.lua).
    state.realAuras = NS.Client.RealAurasOnly(state.container)
    state.container:SetSize(1, 1)
    state.container:SetPoint("TOP", health, "BOTTOM", 0, 0)
    -- Priority by draw level (DrawLevel): row 1 above row 2 and so on.
    for i = 1, A.LIMIT do state.layers[i] = Layer(state, health, A.LIMIT - i) end
    return state
end

-- A slot's marker (its top, see Marker). anchor is the container, the health
-- bar or the previous slot's marker; the slot itself is never kept.
local function Slot(state, pool, key, index, anchor, relative, offset, filter)
    local marker = pool[index]
    if not marker then
        state.container:AddAuraSlot(key .. index, "HARMFUL|PLAYER", {
            candidateFilters = filter,
            initializeFrame = function(button)
                button:SetMouseClickEnabled(false)
                button:SetMouseMotionEnabled(false)
                button:SetSize(1, SPAN)
                button:SetCollapsesLayout(true)
                button:SetPoint("BOTTOM", anchor, relative, 0, offset)
                marker = Marker(state, button)
            end,
        })
        pool[index] = marker
    else
        -- SetEnabled queues a native dirty pass; it does not synchronously
        -- remove frame restrictions. Existing slot layout is never touched.
        state.container:SetAuraSlotCandidateFilters(key .. index, filter)
    end
    return marker
end

local function Anchor(layer, health, marker, offset)
    if layer.anchored then return end
    layer.mask:SetPoint("LEFT", health, "LEFT", 0, 0)
    layer.mask:SetPoint("RIGHT", health, "RIGHT", 0, 0)
    -- Last: this anchor can inherit the slot's access restrictions.
    layer.mask:SetPoint("BOTTOM", marker, "BOTTOM", 0, offset)
    layer.anchored = true
end

local function PaintLayer(layer, fill, color)
    layer.texture:SetAllPoints(fill)
    Paint(layer.texture, color)
end

local function ConfigureState(state, health)
    state.active = false
    state.container:SetEnabled(false)
    local fill, previous, relative = health:GetStatusBarTexture(), state.container, "TOP"
    for i, row in ipairs(rows) do
        local ids = {}
        for _, id in ipairs(row.ids) do ids[id] = true end
        local filter = { includeSpellIDs = ids }
        -- The first slot sits on the container's top, each further one on
        -- the previous slot's marker (a marker's bottom is its slot's top).
        previous, relative = Slot(state, state.slots, "all", i, previous, relative, 0, filter), "BOTTOM"
        -- The count-specific masks keep this prefix's marker forever.
        -- Only the variants matching the current selected count are shown.
        if not state.allCounts[i] then
            state.allCounts[i], state.noneCounts[i] = Layer(state, health, A.LIMIT), Layer(state, health, A.LIMIT + 1)
            Anchor(state.allCounts[i], health, previous, -SPAN * i - SPAN / 2)
            Anchor(state.noneCounts[i], health, previous, -SPAN / 2)
        end
        if config.auraColorsIndividual then
            local marker = Slot(state, state.singles, "single", i, health, "BOTTOM", -SPAN, filter)
            Anchor(state.layers[i], health, marker, -SPAN / 2)
            PaintLayer(state.layers[i], fill, row.color)
        end
    end
    for i = #rows + 1, #state.slots do
        state.container:SetAuraSlotCandidateFilters("all" .. i, EMPTY_FILTER)
    end
    for i = 1, #state.singles do
        if not config.auraColorsIndividual or i > #rows then
            state.container:SetAuraSlotCandidateFilters("single" .. i, EMPTY_FILTER)
        end
    end
    -- Keep visible health well inside the opaque mask, away from sampled
    -- edges. Missing/present slots shift it by a full span in native layout.
    if state.all then
        state.all.texture:Hide()
        state.none.texture:Hide()
    end
    state.all, state.none = state.allCounts[#rows], state.noneCounts[#rows]
    PaintLayer(state.all, fill, config.auraColorsAll)
    PaintLayer(state.none, fill, config.auraColorsNone)
    state.revision, state.fill = revision, fill
end

local function Hide(state)
    if not state.active and not state.unit then return end
    state.container:SetEnabled(false)
    state.wrapper:Hide()
    state.all.texture:Hide()
    state.none.texture:Hide()
    for _, layer in ipairs(state.layers) do layer.texture:Hide() end
    state.unit = nil
    state.active = false
end

function Colors.Restore(uf)
    local state = states[uf]
    if state then Hide(state) end
end

-- The resolved rows of two reads: the same DoTs (IDs and aliases) with the
-- same colors in the same order.
local function SameRows(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        local x, y = a[i], b[i]
        if x.id ~= y.id or x.color ~= y.color or #x.ids ~= #y.ids then return false end
        for k = 1, #x.ids do
            if x.ids[k] ~= y.ids[k] then return false end
        end
    end
    return true
end

-- force: catalog, talent and spec events read the selection again. Only a
-- change of the resolved rows or the shared colors and switches makes the
-- plates reconfigure (a new revision); an equal read leaves them as they are.
function Colors.Configure(c, force)
    if not c.auraColorsEnabled then
        config, rows, plan = c, {}, nil
        return
    end
    config = c
    local spec = A.Spec()
    if not force and plan and plan.spec == spec and plan.data == c.auraColorsData
        and plan.all == c.auraColorsAll and plan.none == c.auraColorsNone
        and plan.warn == c.auraColorsNoneEnabled and plan.individual == c.auraColorsIndividual then return end
    local selected = A.Selected(A.Decode(c.auraColorsData)[spec])
    local changed = not plan or plan.all ~= c.auraColorsAll or plan.none ~= c.auraColorsNone
        or plan.warn ~= c.auraColorsNoneEnabled or plan.individual ~= c.auraColorsIndividual
        or not SameRows(rows, selected)
    rows = selected
    plan = plan or {}
    plan.spec, plan.data, plan.all, plan.none = spec, c.auraColorsData, c.auraColorsAll, c.auraColorsNone
    plan.warn, plan.individual = c.auraColorsNoneEnabled, c.auraColorsIndividual
    if changed then revision = revision + 1 end
end

function Colors.Apply(uf, unit, enemy)
    local state = states[uf]
    if not config or not config.auraColorsEnabled or #rows == 0 or not enemy
        or config.look == private.Mode.LOOK_BLIZZARD or not config.enemy or not unit then
        if state then Hide(state) end
        return
    end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not health or NS.Safety.IsForbidden(health) then return end
    local fill = health:GetStatusBarTexture()
    -- A new plate, another selection or another fill texture builds or
    -- reconfigures; only an open Forever gamepad panel holds that back.
    if (not state or state.revision ~= revision or state.fill ~= fill) and Blocked() then return end
    if not state then
        state = New(health)
        states[uf] = state
    end
    -- 12.1.0 feeds the container Edit Mode's samples, which match no DoT:
    -- its colors hide until Edit Mode closes (SetEditMode).
    if editMode and not state.realAuras then
        Hide(state)
        return
    end
    if state.active and state.revision == revision and state.fill == fill and state.unit == unit then return end
    if state.revision ~= revision or state.fill ~= fill then ConfigureState(state, health) end
    if state.unit ~= unit then
        state.container:SetUnit(unit)
        state.unit = unit
    end
    state.wrapper:Show()
    state.container:SetEnabled(true)
    -- A lone DoT takes the all color as well (A.Preview).
    state.all.texture:Show()
    state.none.texture:SetShown(config.auraColorsNoneEnabled)
    for i, layer in ipairs(state.layers) do layer.texture:SetShown(config.auraColorsIndividual and i <= #rows) end
    state.active = true
end

-- The gamepad panel that held builds back closed (Platform.lua calls back):
-- the shown plates are painted.
function Colors.Resume()
    if not waiting or Blocked() then return end
    waiting = false
    refresh(module)
end

-- Blizzard's Edit Mode opened or closed (Skin.lua): the shown plates repaint
-- unless the caller repaints them itself (repaint == false).
function Colors.SetEditMode(active, repaint)
    editMode = active == true
    if repaint ~= false then refresh(module) end
end

-- owner: the nameplate module; repaint(owner) applies the colors of the shown plates.
function Colors.Bind(owner, repaint) module, refresh = owner, repaint end
