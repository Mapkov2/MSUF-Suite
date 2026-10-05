local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- The two optional sensors of a stack-filled buff bar's buttons: the
-- threshold colour ("Change bar color from stacks") and the stack glow
-- ("Glow at stacks"). Each is a child aura container inside the primary
-- button with one slot on the entry's IDs; Blizzard fills their application
-- bars, so no Lua reads a stack count. Built and restyled by AuraButtons'
-- ApplyEntry through the same sealed-button rules.
local StackColors = {}
C.StackColors = StackColors
local K = C.Const
local SameSet, CopySet = K.SameSet, K.CopySet
local Glows = C.AuraGlows
local options = {}

local function Shape(color, part, rec)
    local lk, n = rec.lk, rec.colorAt
    local width = lk.w - (lk.icon and lk.h or lk.bw) - lk.bw
    local height = lk.h - 2 * lk.bw
    local travel = width + 2 * lk.px
    color.sensor:SetSize(travel * n, lk.px)
    color.sensor:ClearAllPoints()
    color.sensor:SetPoint("LEFT", part.bar, "LEFT", -travel * n, 0)
    color.host:SetSize(width, height)
    color.texture:SetTexture(lk.tex)
    local r, g, b = K.HexRGB(rec.colorHex)
    color.texture:SetVertexColor(r, g, b, 1)
    color.n, color.hex, color.w, color.h, color.px = n, rec.colorHex, lk.w, lk.h, lk.px
    color.icon, color.bw, color.tex = lk.icon, lk.bw, lk.tex
    options.maxApplications = n
    color.button:SetApplicationBar(color.sensor, options)
end

local function Initialize(color, part, rec, button)
    color.button = button
    Glows.Overlay(button, part.button)
    -- Over the fill, under the markers, glows and text (K.AURA_LEVEL); the
    -- clip and the colour share that one level.
    local level = part.button:GetFrameLevel() + K.AURA_LEVEL.color
    button:SetFrameLevel(level)
    -- The outer clip follows the primary fill texture entirely on the
    -- native side. Nothing reads its restricted size or the stack count.
    local gate = CreateFrame("Frame", nil, button)
    gate:SetFrameLevel(level)
    gate:SetAllPoints(part.bar:GetStatusBarTexture())
    gate:SetClipsChildren(true)
    local sensor = CreateFrame("StatusBar", nil, button)
    sensor:SetStatusBarTexture(K.WHITE)
    sensor:SetMinMaxValues(0, 1)
    sensor:SetValue(0)
    sensor:SetAlpha(0)
    local host = CreateFrame("Frame", nil, gate)
    host:SetFrameLevel(level)
    host:SetPoint("LEFT", sensor:GetStatusBarTexture(), "RIGHT", 0, 0)
    local texture = host:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(host)
    color.gate, color.sensor, color.host, color.texture = gate, sensor, host, texture
    Shape(color, part, rec)
end

-- A child container of one primary button: one slot on the entry's IDs and
-- no anchors (never to another container). Blizzard's containers start
-- disabled (IsEnabled is enabled == true, set only by SetEnabled; UNIT_AURA
-- registers and ParseAllAuras reads only while enabled), so it is enabled
-- once its slot exists.
local function Child(button, unit, key, filter, ids, init)
    local frame = CreateFrame("AuraContainer", nil, button, "CustomAuraContainerTemplate")
    frame:SetUnit(unit)
    frame:AddAuraSlot(key, filter, { candidateFilters = { includeSpellIDs = ids }, initializeFrame = init })
    frame:SetEnabled(true)
    return frame
end

-- A primary aura button has only one application-bar binding. The optional
-- second slot owns the threshold sensor; its container is a CHILD of the
-- primary button and has no anchors to another container. Blizzard's native
-- OnHide/OnShow unregister/register its events from inherited visibility.
-- Pooled inactive primary buttons therefore do no secondary aura processing.
local function Create(part, rec, ids, filter)
    local color = { ids = CopySet({}, ids) }
    part.color = color
    color.unit, color.filter = rec.unit, filter
    color.frame = Child(part.button, rec.unit, "color", filter, color.ids,
        function(button) Initialize(color, part, rec, button) end)
    return color
end

-- A stack-filled primary keeps its application sink. The optional glow
-- owns another child slot, so its threshold/operator cannot replace that
-- sink or the independently configured color threshold.
local function ApplyStack(rec, part, entry, dry)
    if not rec.stackExtra then return false end
    local sensor = part.stackSensor
    local ov = entry.ov or C.EMPTY
    local enabled = type(ov.stackGlow) == "number" and ov.stackGlow > 0
    if not enabled then
        if not sensor or not sensor.enabled then return false end
        if dry then return true end
        sensor.frame:SetEnabled(false)
        sensor.frame:Hide()
        sensor.enabled = false
        -- An idle sensor's glow holds no combat state driver.
        Glows.ApplyCombatGate(sensor.part.stack.glow, false, false)
        return false
    end
    local ids, filter = rec.ids[part.pos], rec.filter[part.pos]
    if not ids then return false end
    local draw = Glows
    if not sensor then
        if dry then return true end
        sensor = { ids = CopySet({}, ids), unit = rec.unit, filter = filter, enabled = true }
        part.stackSensor = sensor
        sensor.frame = Child(part.button, rec.unit, "stack", filter, sensor.ids, function(button)
            draw.Overlay(button, part.button)
            local p = { button = button }
            sensor.part = p
            -- At the primary button's glow level (K.AURA_LEVEL).
            draw.BridgeStack(rec, p, ov, part.button:GetFrameLevel() + K.AURA_LEVEL.glow)
        end)
        return false
    end
    local routing = sensor.unit ~= rec.unit or sensor.filter ~= filter or not SameSet(sensor.ids, ids)
    if routing then
        if dry then return true end
        CopySet(sensor.ids, ids)
        sensor.frame:SetAuraSlotCandidateFilters("stack", { includeSpellIDs = sensor.ids })
        sensor.frame:SetAuraSlotFilterString("stack", filter)
        sensor.frame:SetUnit(rec.unit)
        sensor.unit, sensor.filter = rec.unit, filter
    end
    if draw.ApplyStack(rec, sensor.part, ov, dry) then return true end
    local glow = sensor.part.stack
    if draw.ApplyCombatGate(glow.glow, glow.on, dry) then return true end
    if not sensor.enabled then
        if dry then return true end
        sensor.frame:SetEnabled(true)
        sensor.frame:Show()
        sensor.enabled = true
    end
    return false
end

function StackColors.Apply(rec, part, entry, dry)
    if ApplyStack(rec, part, entry, dry) then return true end
    if not rec.color then return false end
    local color, lk = part.color, rec.lk
    local ids, filter = rec.ids[part.pos], rec.filter[part.pos]
    if not ids then return false end
    local shape = not color or color.n ~= rec.colorAt or color.hex ~= rec.colorHex
        or color.w ~= lk.w or color.h ~= lk.h or color.px ~= lk.px or color.icon ~= lk.icon
        or color.bw ~= lk.bw or color.tex ~= lk.tex
    local routing = not color or color.unit ~= rec.unit or color.filter ~= filter or not SameSet(color.ids, ids)
    if not shape and not routing then return false end
    if dry then return true end
    if not color then
        Create(part, rec, ids, filter)
        return false
    end
    if routing then
        CopySet(color.ids, ids)
        color.frame:SetAuraSlotCandidateFilters("color", { includeSpellIDs = color.ids })
        color.frame:SetAuraSlotFilterString("color", filter)
        color.frame:SetUnit(rec.unit)
        color.unit, color.filter = rec.unit, filter
    end
    if shape then Shape(color, part, rec) end
    return false
end

-- A retarget of a fixed target bar: the child containers inside its slot
-- buttons parse the new target. Container-level calls, legal in combat.
function StackColors.Retarget(rec)
    local parts = rec.parts
    for i = 1, #parts do
        local part = parts[i]
        local color, sensor = part.color, part.stackSensor
        if color then color.frame:UpdateAllAuras() end
        if sensor and sensor.enabled then sensor.frame:UpdateAllAuras() end
    end
end

function StackColors.Open(part)
    if part.color then
        local open = part.color.button:CanBeAccessedInContext()
        if not S.Public(open) or open ~= true then return false end
    end
    if part.stackSensor then
        local open = part.stackSensor.part.button:CanBeAccessedInContext()
        if not S.Public(open) or open ~= true then return false end
    end
    return true
end
