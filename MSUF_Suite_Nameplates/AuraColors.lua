local _, private = ...
local NS, A = private.NS, private.NS.NameplateAuraColors
local Colors = {}
private.AuraColors = Colors
local states = setmetatable({}, { __mode = "k" })
local module, config, rows, revision, plan = nil, nil, {}, 0, nil
-- A public fixed span exceeds every supported nameplate height. Hidden
-- native slots collapse to zero; no secret size or visibility is read.
local SPAN = 4096
local EMPTY_FILTER = { includeSpellIDs = { [1] = true } }

local function Paint(texture, hex)
    texture:SetColorTexture(NS.RGB(hex))
end

local function Layer(state, health)
    local texture = health:CreateTexture(nil, "ARTWORK", nil, 7)
    local mask = state.wrapper:CreateMaskTexture()
    mask:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    mask:SetHeight(SPAN)
    texture:AddMaskTexture(mask)
    texture:Hide()
    return { texture = texture, mask = mask }
end

local function New(health)
    local state = { slots = {}, singles = {}, layers = {} }
    -- Keep the large predicate slots out of Blizzard's pooled nameplate
    -- hierarchy. Only the small fill textures belong to the health bar.
    state.wrapper = CreateFrame("Frame", nil, UIParent, "DisableUntrustedLayoutScriptsTemplate")
    state.wrapper:SetIgnoringChildrenForBounds(true)
    state.wrapper:SetAllPoints(health)
    state.container = CreateFrame("AuraContainer", nil, state.wrapper, "CustomAuraContainerTemplate")
    state.container:SetSize(1, 1)
    state.container:SetPoint("BOTTOM", health, "BOTTOM", 0, 0)
    -- Creation order establishes priority within ARTWORK, below native text.
    for i = A.LIMIT, 1, -1 do state.layers[i] = Layer(state, health) end
    state.all, state.none = Layer(state, health), Layer(state, health)
    return state
end

local function Slot(state, pool, key, index, anchor, relative, offset, filter)
    local frame = pool[index]
    if not frame then
        frame = state.container:AddAuraSlot(key .. index, "HARMFUL|PLAYER", {
            candidateFilters = filter,
            initializeFrame = function(button)
                button:SetMouseClickEnabled(false)
                button:SetMouseMotionEnabled(false)
                button:SetSize(1, SPAN)
                button:SetCollapsesLayout(true)
                button:SetPoint("BOTTOM", anchor, relative, 0, offset)
            end,
        })
        pool[index] = frame
    else
        -- SetEnabled queues a native dirty pass; it does not synchronously
        -- remove frame restrictions. Existing slot layout is never touched.
        state.container:SetAuraSlotCandidateFilters(key .. index, filter)
    end
    return frame
end

local function Anchor(layer, fill, slot, offset, color)
    layer.texture:SetAllPoints(fill)
    Paint(layer.texture, color)
    layer.mask:ClearAllPoints()
    layer.mask:SetPoint("LEFT", fill, "LEFT", 0, 0)
    layer.mask:SetPoint("RIGHT", fill, "RIGHT", 0, 0)
    layer.mask:SetPoint("BOTTOM", slot, "TOP", 0, offset)
end

local function ConfigureState(state, health)
    state.active = false
    state.container:SetEnabled(false)
    local fill, previous = health:GetStatusBarTexture(), state.container
    -- Origin is the health bottom, independent of its secret dimensions.
    state.container:ClearAllPoints()
    state.container:SetPoint("TOP", health, "BOTTOM", 0, -SPAN * #rows)
    for i, row in ipairs(rows) do
        local ids = {}
        for _, id in ipairs(row.ids) do ids[id] = true end
        local filter = { includeSpellIDs = ids }
        previous = Slot(state, state.slots, "all", i, previous, "TOP", 0, filter)
        if config.auraColorsIndividual then
            local slot = Slot(state, state.singles, "single", i, health, "BOTTOM", -SPAN, filter)
            Anchor(state.layers[i], fill, slot, -SPAN / 2, row.color)
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
    Anchor(state.all, fill, previous, -SPAN / 2, config.auraColorsAll)
    Anchor(state.none, fill, previous, SPAN * #rows - SPAN / 2, config.auraColorsNone)
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

function Colors.Configure(c, force)
    if not c.auraColorsEnabled then
        config, rows, plan = c, {}, nil
        return
    end
    if NS.InCombat() then
        module.needsRefresh = true
        return
    end
    config = c
    local spec = A.Spec()
    if not force and plan and plan.spec == spec and plan.data == c.auraColorsData
        and plan.all == c.auraColorsAll and plan.none == c.auraColorsNone
        and plan.warn == c.auraColorsNoneEnabled and plan.individual == c.auraColorsIndividual then return end
    rows = A.Selected(A.Decode(c.auraColorsData)[spec])
    plan = { spec = spec, data = c.auraColorsData, all = c.auraColorsAll, none = c.auraColorsNone,
        warn = c.auraColorsNoneEnabled, individual = c.auraColorsIndividual }
    revision = revision + 1
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
    if state and state.revision ~= revision and NS.InCombat() then
        module.needsRefresh = true
        return
    end
    if not state then
        state = New(health)
        states[uf] = state
    end
    local fill = health:GetStatusBarTexture()
    if state.active and state.revision == revision and state.fill == fill and state.unit == unit then return end
    if state.revision ~= revision or state.fill ~= fill then ConfigureState(state, health) end
    if state.unit ~= unit then
        state.container:SetUnit(unit)
        state.unit = unit
    end
    state.wrapper:Show()
    state.container:SetEnabled(true)
    state.all.texture:SetShown(not config.auraColorsIndividual or #rows > 1)
    state.none.texture:SetShown(config.auraColorsNoneEnabled)
    for i, layer in ipairs(state.layers) do layer.texture:SetShown(config.auraColorsIndividual and i <= #rows) end
    state.active = true
end

function Colors.Bind(owner) module = owner end
