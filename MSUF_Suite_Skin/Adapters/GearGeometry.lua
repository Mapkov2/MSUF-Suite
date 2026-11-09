local _, NS = ...

local Geometry = {}
NS.GearGeometry = Geometry
local Safety = NS.Safety
local Public, Read = Safety.Public, Safety.Read

-- Reversible geometry -------------------------------------------------------------------
-- Source: upstream/live 8ea15b61, CharacterFrameMixin:UpdateSize and
-- PaperDollFrame.xml. Only the Character page grows; sidebar collapse stays native.

local function CanLayout(frame)
    return NS.Safety.CanCreateRegions(frame, not NS.IsCombatLocked())
end

local function Points(frame)
    local points = {}
    for index = 1, math.min(frame:GetNumPoints(), 4) do
        points[index] = { frame:GetPoint(index) }
    end
    return points
end

-- Geometry is stored with less precision than Lua numbers, so offsets, sizes
-- and scales read back after Set* differ slightly from the values set. Only
-- a larger difference means Blizzard (or another addon) changed the value.
local GEOMETRY_EPSILON = 0.01
local SCALE_EPSILON = 0.0001

local function Near(current, applied, epsilon)
    if type(current) == "number" and type(applied) == "number" then
        return NS.Safety.Public(current) and math.abs(current - applied) <= epsilon
    end
    return current == applied
end

local function ReadInsets(frame)
    local left, right, top, bottom = Safety.Call(frame, "GetHitRectInsets")
    if not Public(left) or not Public(right) or not Public(top) or not Public(bottom)
        or type(left) ~= "number" or type(right) ~= "number" or type(top) ~= "number" or type(bottom) ~= "number" then return end
    return left, right, top, bottom
end

local function SameInsets(expected, left, right, top, bottom)
    return expected and left ~= nil and Near(left, expected[1], GEOMETRY_EPSILON)
        and Near(right, expected[2], GEOMETRY_EPSILON) and Near(top, expected[3], GEOMETRY_EPSILON)
        and Near(bottom, expected[4], GEOMETRY_EPSILON)
end

local function SamePoints(frame, points)
    if not points or Read(frame, "GetNumPoints") ~= #points then return false end
    for index, point in ipairs(points) do
        local a, b, c, d, e = frame:GetPoint(index)
        if not Public(a) or not Public(b) or not Public(c) or not Public(d) or not Public(e)
            or a ~= point[1] or b ~= point[2] or c ~= point[3]
            or not Near(d, point[4], GEOMETRY_EPSILON) or not Near(e, point[5], GEOMETRY_EPSILON) then
            return false
        end
    end
    return true
end

local function RecordGeometry(v, frame)
    local record = v.geometry[frame]
    if not record then
        record = {}
        v.geometry[frame] = record
    end
    return record
end

-- Anchors frame at one point (plus an optional second), remembering the
-- native points the first time we move it.
local function Place(v, frame, point, parent, relative, x, y, second)
    if not CanLayout(frame) then return end
    local record = RecordGeometry(v, frame)
    if not SamePoints(frame, record.appliedPoints) then record.points = Points(frame) end
    local applied = record.appliedPoints
    if not applied then
        applied = { {} }
        record.appliedPoints = applied
    end
    local first = applied[1]
    first[1], first[2], first[3], first[4], first[5] = point, parent, relative, x, y
    applied[2] = second
    if not SamePoints(frame, applied) then
        frame:ClearAllPoints()
        for _, anchor in ipairs(applied) do frame:SetPoint(unpack(anchor, 1, 5)) end
    end
end

local function Size(v, frame, width, height)
    if not CanLayout(frame) then return end
    local record = RecordGeometry(v, frame)
    if width then
        local current = frame:GetWidth()
        if not Near(current, record.appliedWidth, GEOMETRY_EPSILON) then record.width = current end
        if not Near(current, width, GEOMETRY_EPSILON) then frame:SetWidth(width) end
        record.appliedWidth = width
    end
    if height then
        local current = frame:GetHeight()
        if not Near(current, record.appliedHeight, GEOMETRY_EPSILON) then record.height = current end
        if not Near(current, height, GEOMETRY_EPSILON) then frame:SetHeight(height) end
        record.appliedHeight = height
    end
end

local function Conceal(v, frame)
    if not CanLayout(frame) or not frame.IsShown then return end
    local record = RecordGeometry(v, frame)
    if record.shown == nil then record.shown = frame:IsShown() end
    if frame:IsShown() then frame:Hide() end
end

local function Scale(v, frame, value)
    if not CanLayout(frame) then return end
    local record = RecordGeometry(v, frame)
    local current = frame:GetScale()
    if not Near(current, record.appliedScale, SCALE_EPSILON) then record.scale = current end
    if not Near(current, value, SCALE_EPSILON) then frame:SetScale(value) end
    record.appliedScale = value
end

local function RepositionPanels(v, oldWidth, oldHeight)
    local root = v.root
    v.repositionPending = v.repositionPending or root:GetWidth() ~= oldWidth or root:GetHeight() ~= oldHeight
    -- Blizzard's panel manager writes secure attributes, even for a safe root.
    if v.repositionPending and not NS.IsCombatLocked() then
        v.repositionPending = nil
        UpdateUIPanelPositions(root)
    end
end

-- Puts back what the layout changed on one frame. Only values we still own
-- go back; a newer native change is kept.
local function RestoreFrame(frame, record)
    if not CanLayout(frame) then return false end
    local strata = record.strata and Read(frame, "GetFrameStrata") == record.appliedStrata and record.strata
    local level = record.level
    if level then
        local current, rootLevel = Read(frame, "GetFrameLevel"), Read(record.levelRoot, "GetFrameLevel")
        local drift = (rootLevel or record.levelBase) - record.levelBase
        if current ~= record.appliedLevel and current ~= record.appliedLevel + drift then level = nil
        elseif record.levelRelative then level = level + drift end
    end
    local insets = record.insets and SameInsets(record.appliedInsets, ReadInsets(frame)) and record.insets
    if SamePoints(frame, record.appliedPoints) then
        frame:ClearAllPoints()
        for _, point in ipairs(record.points) do frame:SetPoint(unpack(point, 1, 5)) end
    end
    if record.width and Near(frame:GetWidth(), record.appliedWidth, GEOMETRY_EPSILON) then
        frame:SetWidth(record.width)
    end
    if record.height and Near(frame:GetHeight(), record.appliedHeight, GEOMETRY_EPSILON) then
        frame:SetHeight(record.height)
    end
    if record.scale and Near(frame:GetScale(), record.appliedScale, SCALE_EPSILON) then
        frame:SetScale(record.scale)
    end
    if strata then frame:SetFrameStrata(strata) end
    if level then frame:SetFrameLevel(level) end
    if insets then frame:SetHitRectInsets(unpack(insets)) end
    if record.shown ~= nil and not frame:IsShown() then frame:SetShown(record.shown) end
    return true
end

Geometry.CanLayout, Geometry.Place, Geometry.Size = CanLayout, Place, Size
Geometry.Scale, Geometry.Conceal = Scale, Conceal
Geometry.Near, Geometry.Epsilon = Near, GEOMETRY_EPSILON
Geometry.RestoreFrame, Geometry.RepositionPanels = RestoreFrame, RepositionPanels

-- Suite art sits beneath these exact Blizzard controls. The layout owner
-- never changes their parent, visibility, scripts or protected actions.
local CharacterGeometry = {}
NS.SuiteCore().Skin.CharacterGeometry = CharacterGeometry
local layout
local RELEASE_KEY = "suite-character-geometry"

function Geometry.Owns(root)
    return layout and layout.root == root
end

local function Positive(value)
    return type(value) == "number" and value > 0 and value < math.huge
end

local function Coordinate(value)
    return type(value) == "number" and value > -math.huge and value < math.huge
end

local function Movable(frame)
    local count = Read(frame, "GetNumPoints")
    if not count or count > 4 or not Safety.HasMethod(frame, "GetPoint") or not Safety.HasMethod(frame, "ClearAllPoints")
        or not Safety.HasMethod(frame, "SetPoint") then return false end
    for index = 1, count do
        local a, b, c, d, e = frame:GetPoint(index)
        if not Public(a) or not Public(b) or not Public(c) or not Public(d) or not Public(e) then return false end
    end
    return true
end

local function NativeChild(root, frame)
    if not Public(frame) or not CanLayout(frame) or not Read(frame, "GetFrameStrata")
        or not Read(frame, "GetFrameLevel") or not Safety.HasMethod(frame, "SetFrameStrata")
        or not Safety.HasMethod(frame, "SetFrameLevel") then return false end
    for _ = 1, 8 do
        frame = Read(frame, "GetParent")
        if frame == root then return true end
        if not frame then break end
    end
    return false
end

local function ResolveScale(frame, size, rootScale)
    if not Positive(size) or not Safety.HasMethod(frame, "SetScale") then return end
    local width, scale = Read(frame, "GetWidth"), Read(frame, "GetScale")
    local effective = Read(frame, "GetEffectiveScale")
    if not Positive(width) or not Positive(scale) or not Positive(effective) then return end
    local ratio = size / width
    return ratio, scale * ratio * rootScale / effective
end

local function ResolveSlot(root, entry, rootScale)
    if type(entry.token) ~= "string" or not Coordinate(entry.x) or not Coordinate(entry.y) then return end
    local frame = _G["Character" .. entry.token]
    if not NativeChild(root, frame) or not Movable(frame) or not Safety.HasMethod(frame, "GetRegions") then return end
    local ratio, scale = ResolveScale(frame, entry.size, rootScale)
    if not ratio then return end
    local slot = { frame = frame, x = entry.x / ratio, y = -entry.y / ratio, scale = scale }
    local alternateX = entry.alternateX
    if alternateX ~= nil then
        if not Coordinate(alternateX) then return end
        if alternateX ~= entry.x then
            if not Safety.HasMethod(frame, "SetHitRectInsets") or not ReadInsets(frame) then return end
            local offset = (alternateX - entry.x) / ratio
            slot.hitInsets = { math.min(0, offset), -math.max(0, offset), 0, 0 }
        end
    end
    return slot
end

local function ResolveLayout(root, plan)
    if type(plan) ~= "table" or type(plan.slots) ~= "table" or type(plan.model) ~= "table" or type(plan.close) ~= "table"
        or type(plan.strata) ~= "string" or not Positive(plan.modelLevel)
        or not Positive(plan.slotLevel) or not Positive(plan.closeLevel) then return end
    local rect = plan.model
    if not Coordinate(rect.x) or not Coordinate(rect.y) or not Positive(rect.width) or not Positive(rect.height)
        or not Coordinate(plan.close.x) or not Coordinate(plan.close.y) then return end
    local rootScale = Read(root, "GetEffectiveScale")
    if not Positive(rootScale) then return end
    local model, close = CharacterModelScene, Safety.Field(root, "CloseButton")
    if not Public(close) then return end
    close = close or CharacterFrameCloseButton
    if not NativeChild(root, model) or not Movable(model) or not NativeChild(root, close) or not Movable(close) then return end
    local modelScale, closeEffective = Read(model, "GetEffectiveScale"), Read(close, "GetEffectiveScale")
    if not Positive(modelScale) or not Positive(closeEffective) then return end
    local controls = Safety.Field(model, "ControlFrame")
    if not Public(controls) then return end
    if controls and not NativeChild(root, controls) then return end
    local closeRatio, closeScale = closeEffective / rootScale
    if plan.close.size ~= nil then
        closeRatio, closeScale = ResolveScale(close, plan.close.size, rootScale)
        if not closeRatio then return end
    end
    local slots = {}
    for _, entry in ipairs(plan.slots) do
        local slot = ResolveSlot(root, entry, rootScale)
        if slot then slots[#slots + 1] = slot elseif not entry.optional then return end
    end
    return model, close, modelScale / rootScale, closeRatio, closeScale, slots, controls
end

local function Layer(v, frame, strata, level)
    local record = RecordGeometry(v, frame)
    local currentStrata = Read(frame, "GetFrameStrata")
    if not currentStrata then return end
    if currentStrata ~= record.appliedStrata then record.strata = currentStrata end
    if currentStrata ~= strata then frame:SetFrameStrata(strata) end
    record.appliedStrata = strata
    if not level then return end
    local currentLevel = Read(frame, "GetFrameLevel")
    if not currentLevel then return end
    local base = v.levelBase
    local prior = record.appliedLevel and record.appliedLevel + base - record.levelBase
    if currentLevel ~= record.appliedLevel and currentLevel ~= prior then
        record.level = currentLevel
        record.levelRelative = Read(frame, "HasFixedFrameLevel") ~= true
    elseif record.levelRelative then
        record.level = record.level + base - record.levelBase
    end
    level = base + level
    if currentLevel ~= level then frame:SetFrameLevel(level) end
    record.appliedLevel = level
    record.levelRoot, record.levelBase = v.root, base
end

local function FadeTextures(owner, ...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if Read(region, "GetObjectType") == "Texture" and Read(region, "GetAlpha") ~= 0 then
            NS.Cosmetics.Fade(region, owner)
        end
    end
end

-- The original button covers the union of the two authored icon positions.
-- Owned blockers in the Suite view expose only the active part of that span.
local function ApplyHitInsets(v, frame, insets)
    local record = v.geometry[frame]
    if not insets and not record.insets then return end
    local left, right, top, bottom = ReadInsets(frame)
    if left == nil then return end
    local ownsInsets = SameInsets(record.appliedInsets, left, right, top, bottom)
    if insets then
        if not ownsInsets then record.insets = { left, right, top, bottom } end
        if not SameInsets(insets, left, right, top, bottom) then frame:SetHitRectInsets(unpack(insets)) end
    else
        if ownsInsets then frame:SetHitRectInsets(unpack(record.insets)) end
        record.insets = nil
    end
    record.appliedInsets = insets
end

local function ApplySlot(v, slot, plan)
    local frame = slot.frame
    Scale(v, frame, slot.scale)
    Place(v, frame, "TOPLEFT", v.root, "TOPLEFT", slot.x, slot.y)
    Layer(v, frame, plan.strata, plan.slotLevel)
    ApplyHitInsets(v, frame, slot.hitInsets)
    FadeTextures(v, frame:GetRegions())
    local border = Safety.Field(frame, "BorderFrame")
    if Public(border) and border then FadeTextures(v, Safety.Call(border, "GetRegions")) end
end

local function ApplyModel(v, model, plan, ratio, controls)
    local rect, root = plan.model, v.root
    -- Two corners size the Forever scene without changing its implicit
    -- native dimensions. Retail's fixed size also stays in the native object.
    local bottom = { "BOTTOMRIGHT", root, "TOPLEFT", (rect.x + rect.width) / ratio, -(rect.y + rect.height) / ratio }
    Place(v, model, "TOPLEFT", root, "TOPLEFT", rect.x / ratio, -rect.y / ratio, bottom)
    Layer(v, model, plan.strata, plan.modelLevel)
    -- Keep the stock toolbar behind Suite art even when raising the scene shifts its children.
    if controls then Layer(v, controls, "LOW") end
    FadeTextures(v, Safety.Field(model, "BackgroundTopLeft"), Safety.Field(model, "BackgroundTopRight"),
        Safety.Field(model, "BackgroundBotLeft"), Safety.Field(model, "BackgroundBotRight"),
        PaperDollInnerBorderTopLeft, PaperDollInnerBorderTopRight, PaperDollInnerBorderBottomLeft,
        PaperDollInnerBorderBottomRight, PaperDollInnerBorderLeft, PaperDollInnerBorderRight,
        PaperDollInnerBorderTop, PaperDollInnerBorderBottom, PaperDollInnerBorderBottom2)
    -- Blizzard sets the overlay alpha on every native PaperDoll show.
    NS.Cosmetics.SuppressVertexAlpha(Safety.Field(model, "BackgroundOverlay"), v)
end

function CharacterGeometry.Apply(root, plan)
    if NS.IsCombatLocked() or root ~= CharacterFrame or not CanLayout(root) then return false end
    if layout and (layout.root ~= root or layout.releasing) then return false end
    if layout and layout.applying then return true end
    local basic = NS.CharacterDetails.views[root]
    if basic and basic.geometry and next(basic.geometry) then return false end
    local base = Read(root, "GetFrameLevel")
    if type(base) ~= "number" then return false end
    local model, close, modelRatio, closeRatio, closeScale, slots, controls = ResolveLayout(root, plan)
    if not model then return false end
    NS.CombatGate.Cancel(RELEASE_KEY)
    local v = layout or { root = root, geometry = {} }
    layout, v.applying, v.plan, v.levelBase = v, true, plan, base
    plan.rootLevel = base
    ApplyModel(v, model, plan, modelRatio, controls)
    for _, slot in ipairs(slots) do ApplySlot(v, slot, plan) end
    if closeScale then Scale(v, close, closeScale) end
    Place(v, close, "TOPLEFT", root, "TOPLEFT", plan.close.x / closeRatio, -plan.close.y / closeRatio)
    Layer(v, close, plan.strata, plan.closeLevel)
    v.applying = nil
    return true
end

local function ReleaseLayout()
    local v = layout
    if not v or v.releasing or Safety.IsForbidden(v.root) then return end
    v.releasing = true
    for frame, record in pairs(v.geometry) do
        if RestoreFrame(frame, record) then v.geometry[frame] = nil end
    end
    NS.Cosmetics.RestoreOwner(v)
    v.releasing = nil
    if not next(v.geometry) then layout = nil end
end

function CharacterGeometry.Release(root)
    if layout and layout.root == root then NS.CombatGate.RunOrDefer(RELEASE_KEY, ReleaseLayout) end
end

function CharacterGeometry.Present(root, surface)
    NS.WindowFocus.Present(root, surface)
end

function CharacterGeometry.WindowAction(root, action)
    if not layout or layout.root ~= root then return false end
    return NS.WindowControls.SuiteAction(root, layout.plan, action)
end
