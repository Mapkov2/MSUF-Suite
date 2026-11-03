local _, NS = ...

-- Public native bounds become absolute UIParent coordinates. Veils never
-- anchor to a Blizzard frame, including a root with secure descendants.
local Geometry = {}
NS.WindowFocusGeometry = Geometry
local Safety = NS.Safety
local ranks = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local MAX_SLICES = 32

function Geometry.Read(frame, rect)
    local left, bottom = Safety.Read(frame, "GetLeft"), Safety.Read(frame, "GetBottom")
    local width, height = Safety.Read(frame, "GetWidth"), Safety.Read(frame, "GetHeight")
    local scale, uiScale = Safety.Read(frame, "GetEffectiveScale"), Safety.Read(UIParent, "GetEffectiveScale")
    if type(left) ~= "number" or type(bottom) ~= "number" or type(width) ~= "number" or type(height) ~= "number"
        or type(scale) ~= "number" or type(uiScale) ~= "number" or width <= 0 or height <= 0 or uiScale <= 0 then return false end
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
    rect.source = source
end

function Geometry.Begin(state)
    if not state.slices then
        state.slices, state.scratch = {}, {}
        for index = 1, MAX_SLICES do state.slices[index], state.scratch[index] = {}, {} end
    end
    local rect = state.rect
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

local function Append(state, left, bottom, width, height, source)
    if width <= 0 or height <= 0 then return true end
    if state.outputCount == MAX_SLICES then return false end
    state.outputCount = state.outputCount + 1
    Put(state.scratch[state.outputCount], left, bottom, width, height, source)
    return true
end

-- Rectangle subtraction keeps the active window clear and avoids double
-- veils where another native window sits above an inactive one.
function Geometry.Subtract(state, cut)
    state.outputCount = 0
    for index = 1, state.sliceCount do
        local rect = state.slices[index]
        local right, top = rect.left + rect.width, rect.bottom + rect.height
        local left, bottom = math.max(rect.left, cut.left), math.max(rect.bottom, cut.bottom)
        local cutRight, cutTop = math.min(right, cut.left + cut.width), math.min(top, cut.bottom + cut.height)
        if left >= cutRight or bottom >= cutTop then
            if not Append(state, rect.left, rect.bottom, rect.width, rect.height, rect.source) then return false end
        elseif not Append(state, rect.left, cutTop, rect.width, top - cutTop, rect.source)
            or not Append(state, rect.left, rect.bottom, rect.width, bottom - rect.bottom, rect.source)
            or not Append(state, rect.left, bottom, left - rect.left, cutTop - bottom, rect.source)
            or not Append(state, cutRight, bottom, right - cutRight, cutTop - bottom, rect.source) then return false end
    end
    state.slices, state.scratch = state.scratch, state.slices
    state.sliceCount = state.outputCount
    return true
end

function Geometry.SubtractWindow(state, window)
    for index = 1, window.footprintCount do
        if not Geometry.Subtract(state, window.footprints[index]) then return false end
    end
    return true
end

function Geometry.Above(first, second)
    return first.rank > second.rank or first.rank == second.rank
        and (first.level > second.level or first.level == second.level and first.order > second.order)
end
