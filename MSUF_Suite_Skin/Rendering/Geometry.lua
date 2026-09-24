local _, NS = ...

local Geometry = {}
NS.Geometry = Geometry

local shapePath = NS.path .. "Media\\Shapes\\"
local pillHeights = { 20, 24, 28, 32 }
local emptySpec = {}
local assets = {}

local function ClosestValue(values, requested)
    requested = tonumber(requested) or values[1]
    local best = values[1]
    local distance = math.abs(requested - best)
    for index = 2, #values do
        local candidateDistance = math.abs(requested - values[index])
        if candidateDistance < distance then
            best = values[index]
            distance = candidateDistance
        end
    end
    return best
end

-- Finite asset combinations, never keyed by a frame or an arbitrary spec.
local function GetAssets(shape, extent, border)
    local family = assets[shape]
    if not family then family = {}; assets[shape] = family end
    local size = family[extent]
    if not size then size = {}; family[extent] = size end
    local result = size[border]
    if not result then
        local stem = shape == "pill" and ("pill_h" .. tostring(extent))
            or (shape .. "_r" .. tostring(extent))
        result = {
            fill = shapePath .. stem .. "_fill.png",
            edge = border > 0 and shapePath .. stem .. "_edge" .. tostring(border) .. ".png" or nil,
            hoverEdge = shapePath .. stem .. "_edge" .. tostring(border > 0 and border or 1) .. ".png",
        }
        size[border] = result
    end
    return result
end

function Geometry.Resolve(spec, result)
    spec = spec or emptySpec
    local geometry = NS.DB and NS.DB.geometry or NS.Defaults.geometry
    local shape = spec.shape
    if spec.useControlShape then
        shape = geometry.controlShape
    end
    shape = shape or geometry.family

    local border = spec.border
    if border == nil then
        border = geometry.border
    end
    -- List entries use fill/hover contrast instead of a boxed outline. This
    -- keeps dense Blizzard lists clean while preserving borders on windows,
    -- dialogs, inputs, tabs and action buttons.
    if spec.listItem == true then
        border = 0
    end
    border = ClosestValue(NS.GeometryBorders, border)

    if shape ~= "pill" and shape ~= "round" and shape ~= "continuous" and shape ~= "squircle" then
        shape = "continuous"
    end
    local pill = shape == "pill"
    local extent = pill and ClosestValue(pillHeights, spec.pillHeight or 24)
        or ClosestValue(NS.GeometryRadii, spec.radius or geometry.radius)
    local asset = GetAssets(shape, extent, border)
    -- Callers may reuse their own result, but never share mutable geometry
    -- between surfaces. Every spec/default is resolved again on every refresh.
    result = result or {}
    local margins = result.margins or {}
    local margin = pill and extent / 2 or (extent == 12 and 15.5 or 9.5)
    margins[1], margins[3] = margin, margin
    margins[2], margins[4] = pill and 0 or margin, pill and 0 or margin
    result.fill, result.edge, result.hoverEdge = asset.fill, asset.edge, asset.hoverEdge
    result.margins, result.shape = margins, shape
    result.radius = not pill and extent or nil
    result.border, result.slice = border, spec.slice ~= false
    return result
end

function Geometry.GetFamilies()
    return NS.GeometryFamilies
end

function Geometry.GetRadii()
    return NS.GeometryRadii
end

function Geometry.GetBorders()
    return NS.GeometryBorders
end
