local _, NS = ...

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
    if not region or type(region.GetAlpha) ~= "function" then
        return nil
    end
    local ok, value = pcall(region.GetAlpha, region)
    if not ok then
        return nil
    end
    if type(issecretvalue) == "function" and issecretvalue(value) then
        if type(canaccessvalue) ~= "function" or not canaccessvalue(value) then
            return nil
        end
    end
    return tonumber(value)
end

local function OwnerSet(owner)
    local set = Cosmetics.owners[owner]
    if not set then
        set = setmetatable({}, { __mode = "k" })
        Cosmetics.owners[owner] = set
    end
    return set
end

function Cosmetics.Fade(region, owner)
    if not region or type(region.SetAlpha) ~= "function" then
        return false
    end
    local state = Cosmetics.states[region]
    if not state then
        local alpha = AccessibleAlpha(region)
        if alpha == nil then
            return false
        end
        state = { kind = "alpha", alpha = alpha, owner = owner }
        Cosmetics.states[region] = state
    elseif state.kind ~= "alpha" or state.owner ~= owner then
        return false
    end
    OwnerSet(owner)[region] = true
    region:SetAlpha(0)
    return true
end

function Cosmetics.SuppressVertexAlpha(region, owner)
    if not region or type(region.GetVertexColor) ~= "function"
        or type(region.SetVertexColor) ~= "function" then
        return false
    end
    local state = Cosmetics.states[region]
    if not state then
        local ok, r, g, b, a = pcall(region.GetVertexColor, region)
        if not ok then return false end
        state = { kind = "vertex", vertex = { r, g, b, a }, owner = owner }
        Cosmetics.states[region] = state
    elseif state.kind ~= "vertex" or state.owner ~= owner then
        return false
    end
    OwnerSet(owner)[region] = true
    region:SetVertexColor(state.vertex[1], state.vertex[2], state.vertex[3], 0)
    return true
end

function Cosmetics.FadeNineSlice(nineSlice, owner)
    if not nineSlice then
        return
    end
    for index = 1, #nineSlicePieces do
        Cosmetics.Fade(nineSlice[nineSlicePieces[index]], owner)
    end
end

function Cosmetics.FadeDialogHeader(header, owner)
    if not header then
        return
    end
    Cosmetics.Fade(header.LeftBG, owner)
    Cosmetics.Fade(header.CenterBG, owner)
    Cosmetics.Fade(header.RightBG, owner)
end

function Cosmetics.FadeFlatBackground(background, owner)
    if not background then
        return
    end
    Cosmetics.Fade(background.BottomLeft, owner)
    Cosmetics.Fade(background.BottomRight, owner)
    Cosmetics.Fade(background.BottomEdge, owner)
    Cosmetics.Fade(background.TopSection, owner)
end

function Cosmetics.Restore(region, owner)
    local state = region and Cosmetics.states[region]
    if not state or state.owner ~= owner then return false end

    if state.kind == "vertex" and type(region.GetVertexColor) == "function"
        and type(region.SetVertexColor) == "function" then
        local ok, r, g, b, a = pcall(region.GetVertexColor, region)
        if ok and a == 0 and r == state.vertex[1]
            and g == state.vertex[2] and b == state.vertex[3] then
            region:SetVertexColor(unpack(state.vertex))
        end
    elseif state.kind == "alpha" and type(region.SetAlpha) == "function" then
        local current = AccessibleAlpha(region)
        if current == 0 then region:SetAlpha(state.alpha) end
    end

    Cosmetics.states[region] = nil
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
        if state and state.owner == owner and state.kind == "vertex"
            and type(region.GetVertexColor) == "function"
            and type(region.SetVertexColor) == "function" then
            local ok, r, g, b, a = pcall(region.GetVertexColor, region)
            if ok and a == 0 and r == state.vertex[1] and g == state.vertex[2] and b == state.vertex[3] then
                region:SetVertexColor(unpack(state.vertex))
            end
            Cosmetics.states[region] = nil
        elseif state and state.owner == owner and type(region.SetAlpha) == "function" then
            local current = AccessibleAlpha(region)
            if current == 0 then
                region:SetAlpha(state.alpha)
            end
            Cosmetics.states[region] = nil
        end
    end
    Cosmetics.owners[owner] = nil
end

function Cosmetics.GetOwner(region)
    local state = Cosmetics.states[region]
    return state and state.owner or nil
end
