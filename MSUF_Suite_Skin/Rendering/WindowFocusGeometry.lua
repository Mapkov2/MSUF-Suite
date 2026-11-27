local _, NS = ...

-- Public native bounds become absolute UIParent coordinates. Veils never
-- anchor to a Blizzard frame, including a root with secure descendants.
local Geometry = {}
NS.WindowFocusGeometry = Geometry
local Safety = NS.Safety
local ranks = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local MAX_SLICES = 32
local MAX_ROUNDED_SLICES = 96
local CORNER_EXPONENT = { round = 2, continuous = 4, squircle = 6 }

function Geometry.Read(frame, rect, uiScale, boundsMethod, nativeSample)
    -- GetRect returns the same four local coordinates together on both
    -- clients. An unanchored or restricted region has no usable rectangle.
    local left, bottom, width, height = Safety.Call(frame, boundsMethod or "GetRect")
    if not (Safety.Public(left) and Safety.Public(bottom) and Safety.Public(width) and Safety.Public(height)) then return false end
    local scale = Safety.Read(frame, "GetEffectiveScale")
    uiScale = uiScale or Safety.Read(UIParent, "GetEffectiveScale")
    if type(left) ~= "number" or type(bottom) ~= "number" or type(width) ~= "number" or type(height) ~= "number"
        or type(scale) ~= "number" or type(uiScale) ~= "number" or width <= 0 or height <= 0 or uiScale <= 0 then return false end
    if nativeSample then
        nativeSample.left, nativeSample.bottom, nativeSample.width, nativeSample.height, nativeSample.unitScale =
            left, bottom, width, height, scale
    end
    local ratio = scale / uiScale
    rect.unitScale = ratio
    rect.left, rect.bottom, rect.width, rect.height = left * ratio, bottom * ratio, width * ratio, height * ratio
    return true
end

function Geometry.Layer(state)
    local frame = state.frame
    local layer = Safety.Read(frame, "GetFrameStrata")
    local level = Safety.Read(frame, "GetFrameLevel")
    if not ranks[layer] or type(level) ~= "number" then return false end
    local border = Safety.Field(frame, "BorderFrame")
    if Safety.IsForbidden(border) then border = nil end
    local borderLayer = Safety.Read(border, "GetFrameStrata")
    if ranks[borderLayer] and ranks[borderLayer] > ranks[layer] then layer = borderLayer end
    local chrome = Safety.Read(Safety.Field(frame, "NineSlice"), "GetFrameLevel")
    local borderLevel = Safety.Read(border, "GetFrameLevel")
    local borderChrome = Safety.Read(Safety.Field(border, "NineSlice"), "GetFrameLevel")
    state.strata, state.rank = layer, ranks[layer]
    state.level = math.max(level, chrome or 0, borderLevel or 0, borderChrome or 0) + 30
    return true
end

local function Put(rect, left, bottom, width, height, source)
    rect.left, rect.bottom, rect.width, rect.height = left, bottom, width, height
    rect.source, rect.cutoutMask = source, nil
end

function Geometry.Begin(state)
    if not state.slices then
        state.slices, state.scratch = {}, {}
        for index = 1, MAX_SLICES do state.slices[index], state.scratch[index] = {}, {} end
    end
    local rect = state.rect
    state.sliceLimit = MAX_SLICES
    state.roundedCuts = nil
    Put(state.slices[1], rect.left, rect.bottom, rect.width, rect.height, rect)
    state.sliceCount = 1
    for index = 2, state.footprintCount or 1 do
        local extra = state.extraSlices
        if not extra then extra = {} state.extraSlices = extra end
        extra.rect = state.footprints[index]
        Geometry.Begin(extra)
        for prior = 1, index - 1 do
            if not Geometry.Subtract(extra, state.footprints[prior]) then return false end
        end
        for piece = 1, extra.sliceCount do
            if state.sliceCount == MAX_SLICES then return false end
            state.sliceCount = state.sliceCount + 1
            local source = extra.slices[piece]
            Put(state.slices[state.sliceCount], source.left, source.bottom, source.width, source.height, source.source)
        end
    end
    return true
end

local function Append(state, left, bottom, width, height, previous, mask)
    if width <= 0 or height <= 0 then return true end
    if state.outputCount == state.sliceLimit then return false end
    state.outputCount = state.outputCount + 1
    local index = state.outputCount
    local rect = state.scratch[index]
    if not rect then rect = {} state.scratch[index] = rect end
    Put(rect, left, bottom, width, height, previous.source)
    rect.cutoutMask = mask or previous.cutoutMask
    return true
end

-- The solid center and each pair of parallel edges form two rectangles.
-- An intersection fully inside either can be removed without a mask.
local function InSolidCross(cut, left, bottom, right, top)
    return left >= cut.left + cut.cornerX and right <= cut.left + cut.width - cut.cornerX
        or bottom >= cut.bottom + cut.cornerY and top <= cut.bottom + cut.height - cut.cornerY
end

function Geometry.Covers(root, rect, gutter)
    local cut = root.roundedCut or root
    local left, bottom = rect.left - gutter, rect.bottom - gutter
    local right, top = rect.left + rect.width + gutter, rect.bottom + rect.height + gutter
    return left >= cut.left and bottom >= cut.bottom and right <= cut.left + cut.width and top <= cut.bottom + cut.height
        and (not cut.geometry or InSolidCross(cut, left, bottom, right, top))
end

local function CanUseCutoutMask(rect, cut, left, bottom, right, top)
    if rect.cutoutMask then return false end
    local source = rect.source or rect
    if (source.unitScale or 1) ~= cut.unitScale then return false end
    if not source.contour then return true end
    local shape = source.roundedCut
    return shape and left >= shape.left and bottom >= shape.bottom
        and right <= shape.left + shape.width and top <= shape.bottom + shape.height
        and InSolidCross(shape, left, bottom, right, top)
end

-- WoW combines masks by union. Where the source mask is still needed or
-- another rounded cut already owns this slice's mask, subtract the new
-- corner with narrow rectangular bands. Sample the inner edge of each band
-- so it cannot spill onto the solid portion of the window we are keeping clear.
local function AppendBands(state, rect, cut, left, bottom, right, top, upper, rightSide)
    local geometry = cut.geometry
    local step = 2 * cut.unitScale
    local exponent = CORNER_EXPONENT[geometry.shape]
    local radiusX = geometry.radius * cut.cornerX / geometry.margins[1]
    local radiusY = geometry.radius * cut.cornerY / geometry.margins[2]
    local edgeY = upper and cut.bottom + cut.height or cut.bottom
    local edgeX = rightSide and cut.left + cut.width or cut.left
    local y = bottom
    while y < top do
        local nextY = math.min(y + step, top)
        local depth = upper and edgeY - y or nextY - edgeY
        local distance = math.max(0, 1 - depth / radiusY)
        local offset = radiusX * (1 - (1 - distance ^ exponent) ^ (1 / exponent))
        local bandLeft = rightSide and math.max(left, edgeX - offset) or left
        local bandRight = rightSide and right or math.min(right, edgeX + offset)
        if not Append(state, bandLeft, y, bandRight - bandLeft, nextY - y, rect) then return false end
        y = nextY
    end
    return true
end

local function AppendCorner(state, rect, cut, left, bottom, right, top, upper, rightSide)
    if left >= right or bottom >= top then return true end
    if CanUseCutoutMask(rect, cut, left, bottom, right, top) then
        return Append(state, left, bottom, right - left, top - bottom, rect, cut)
    end
    return AppendBands(state, rect, cut, left, bottom, right, top, upper, rightSide)
end

local function AppendCorners(state, rect, cut, left, bottom, right, top)
    if InSolidCross(cut, left, bottom, right, top) then return true end
    local leftEnd = math.min(right, cut.left + cut.cornerX)
    local rightStart = math.max(left, cut.left + cut.width - cut.cornerX)
    local bottomEnd = math.min(top, cut.bottom + cut.cornerY)
    local topStart = math.max(bottom, cut.bottom + cut.height - cut.cornerY)
    return AppendCorner(state, rect, cut, left, bottom, leftEnd, bottomEnd, false, false)
        and AppendCorner(state, rect, cut, rightStart, bottom, right, bottomEnd, false, true)
        and AppendCorner(state, rect, cut, left, topStart, leftEnd, top, true, false)
        and AppendCorner(state, rect, cut, rightStart, topStart, right, top, true, true)
end

-- Keep external pieces as rectangles. Only the corner tiles can show dim
-- material inside a rounded cut's bounds.
function Geometry.Subtract(state, cut)
    state.outputCount = 0
    if cut.geometry then
        state.sliceLimit = MAX_ROUNDED_SLICES
        state.roundedCuts = true
    end
    for index = 1, state.sliceCount do
        local rect = state.slices[index]
        local right, top = rect.left + rect.width, rect.bottom + rect.height
        local left, bottom = math.max(rect.left, cut.left), math.max(rect.bottom, cut.bottom)
        local cutRight, cutTop = math.min(right, cut.left + cut.width), math.min(top, cut.bottom + cut.height)
        if left >= cutRight or bottom >= cutTop then
            if not Append(state, rect.left, rect.bottom, rect.width, rect.height, rect) then return false end
        elseif not Append(state, rect.left, cutTop, rect.width, top - cutTop, rect)
            or not Append(state, rect.left, rect.bottom, rect.width, bottom - rect.bottom, rect)
            or not Append(state, rect.left, bottom, left - rect.left, cutTop - bottom, rect)
            or not Append(state, cutRight, bottom, right - cutRight, cutTop - bottom, rect)
            or cut.geometry and not AppendCorners(state, rect, cut, left, bottom, cutRight, cutTop) then return false end
    end
    state.slices, state.scratch = state.scratch, state.slices
    state.sliceCount = state.outputCount
    return true
end

function Geometry.SubtractWindow(state, window, rectangular)
    for index = 1, window.footprintCount do
        local rect = window.footprints[index]
        local cut = not rectangular and rect.roundedCut or rect
        if not Geometry.Subtract(state, cut) then return false end
    end
    return true
end

function Geometry.Above(first, second)
    return first.rank > second.rank or first.rank == second.rank
        and (first.level > second.level or first.level == second.level and first.order > second.order)
end
