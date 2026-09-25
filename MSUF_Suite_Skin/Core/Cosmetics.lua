local _, NS = ...

-- Reversible alpha suppression of native decoration. Each region remembers
-- its original value and is restored only while it still shows our value.
local Cosmetics = {
    states = setmetatable({}, { __mode = "k" }),
    owners = {},
}
NS.Cosmetics = Cosmetics

local nineSlicePieces = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

local function AccessibleAlpha(region)
    return tonumber(NS.Safety.Read(region, "GetAlpha"))
end

local function Track(region, state, owner)
    Cosmetics.states[region] = state
    if owner == nil then return end
    local set = Cosmetics.owners[owner]
    if not set then
        set = setmetatable({}, { __mode = "k" })
        Cosmetics.owners[owner] = set
    end
    set[region] = true
end

function Cosmetics.Fade(region, owner)
    if type(region) ~= "table" or type(region.SetAlpha) ~= "function"
        or NS.Safety.IsForbidden(region) then
        return false
    end
    local state = Cosmetics.states[region]
    if not state then
        local alpha = AccessibleAlpha(region)
        if alpha == nil then
            return false
        end
        state = { kind = "alpha", alpha = alpha, owner = owner }
    elseif state.kind ~= "alpha" or state.owner ~= owner then
        return false
    end
    Track(region, state, owner)
    region:SetAlpha(0)
    return true
end

function Cosmetics.SuppressVertexAlpha(region, owner)
    if type(region) ~= "table" or type(region.SetVertexColor) ~= "function"
        or NS.Safety.IsForbidden(region) then
        return false
    end
    local state = Cosmetics.states[region]
    if not state then
        local r, g, b, a = NS.Safety.ReadColor(region, "GetVertexColor")
        if not r then return false end
        state = { kind = "vertex", vertex = { r, g, b, a }, owner = owner }
    elseif state.kind ~= "vertex" or state.owner ~= owner then
        return false
    end
    Track(region, state, owner)
    region:SetVertexColor(state.vertex[1], state.vertex[2], state.vertex[3], 0)
    return true
end

local function FadePieces(frame, pieces, owner)
    if type(frame) ~= "table" then return end
    for index = 1, #pieces do
        Cosmetics.Fade(frame[pieces[index]], owner)
    end
end

local dialogHeaderPieces = { "LeftBG", "CenterBG", "RightBG" }
local flatBackgroundPieces = { "BottomLeft", "BottomRight", "BottomEdge", "TopSection" }

function Cosmetics.FadeNineSlice(nineSlice, owner)
    FadePieces(nineSlice, nineSlicePieces, owner)
end

function Cosmetics.FadeDialogHeader(header, owner)
    FadePieces(header, dialogHeaderPieces, owner)
end

function Cosmetics.FadeFlatBackground(background, owner)
    FadePieces(background, flatBackgroundPieces, owner)
end

-- Restores the original value only while the region still shows ours;
-- a value installed later by Blizzard or another addon wins.
local function RestoreRegion(region, state)
    if state.kind == "vertex" then
        local vertex = state.vertex
        local r, g, b, a = NS.Safety.ReadColor(region, "GetVertexColor")
        if a == 0 and r == vertex[1] and g == vertex[2] and b == vertex[3] then
            region:SetVertexColor(vertex[1], vertex[2], vertex[3], vertex[4])
        end
    elseif AccessibleAlpha(region) == 0 then
        region:SetAlpha(state.alpha)
    end
    Cosmetics.states[region] = nil
end

function Cosmetics.Restore(region, owner)
    local state = region and Cosmetics.states[region]
    if not state or state.owner ~= owner then return false end
    RestoreRegion(region, state)
    local set = Cosmetics.owners[owner]
    if set then set[region] = nil end
    return true
end

function Cosmetics.RestoreOwner(owner)
    local set = Cosmetics.owners[owner]
    if not set then
        return
    end
    for region in pairs(set) do
        local state = Cosmetics.states[region]
        if state and state.owner == owner then
            RestoreRegion(region, state)
        end
    end
    Cosmetics.owners[owner] = nil
end

function Cosmetics.GetOwner(region)
    local state = Cosmetics.states[region]
    return state and state.owner or nil
end
