local _, NS = ...

local emptySpec = {}
local forever = (rawget(NS, "Client") or emptySpec).isForever
local Geometry = {}
NS.Geometry = Geometry

local shapePath = NS.path .. "Media\\Shapes\\"
local pillHeights = { 20, 24, 28, 32 }
local assets = {}
local STRETCHED = Enum.UITextureSliceMode.Stretched

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
    if not family then
        family = {}
        assets[shape] = family
    end
    local size = family[extent]
    if not size then
        size = {}
        family[extent] = size
    end
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
    local window = forever and (spec.role == "shell" or spec.role == "popup")
    local radius = window and geometry.radius or spec.radius or geometry.radius
    local extent = pill and ClosestValue(pillHeights, spec.pillHeight or 24) or ClosestValue(NS.GeometryRadii, radius)
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

-- These textures are owned by the skin. Their tint and visibility can change
-- independently of the asset and slice applied here.
local appliedShapes = setmetatable({}, { __mode = "k" })
local assetSlices = {}

local function SliceToken(asset, left, top, right, bottom)
    local slice = assetSlices[asset]
    if not slice then
        slice = { left, top, right, bottom }
        assetSlices[asset] = slice
    elseif slice[1] ~= left or slice[2] ~= top or slice[3] ~= right or slice[4] ~= bottom then
        -- Assets use fixed margins. A different slice still paints and clears
        -- the previous token without creating another retained variant.
        return nil
    end
    return slice
end

function Geometry.ConfigureShape(texture, asset, geometry, alwaysApply)
    if not texture or not asset then return end
    local margins = geometry.slice and geometry.margins
    local left, top, right, bottom
    local token
    if margins then
        left, top, right, bottom = margins[1], margins[2], margins[3], margins[4]
        if not alwaysApply then token = SliceToken(asset, left, top, right, bottom) end
    elseif not alwaysApply then
        token = asset
    end
    if token and appliedShapes[texture] == token then return end
    texture:ClearTextureSlice()
    texture:SetTexture(asset)
    if margins then
        texture:SetTextureSliceMargins(left, top, right, bottom)
        texture:SetTextureSliceMode(STRETCHED)
    end
    appliedShapes[texture] = token
end
