local _, NS = ...

local Chrome = {}
NS.FlightMapChrome = Chrome
local Kit, Safety = NS.AdapterKit, NS.Safety
local states = Kit.WeakSet()

-- Shared TaxiFrame.lua writes the live map into InsetBg. Its similarly named
-- InsetBorder pieces all belong to the surrounding BasicFrameTemplateWithInset.
local taxiArt = {
    "TopLeftCorner", "TopRightCorner", "BotLeftCorner", "BotRightCorner",
    "TopBorder", "BottomBorder", "LeftBorder", "RightBorder",
    "TitleBg", "TopTileStreaks", "Bg",
    "InsetBorderTopLeft", "InsetBorderTopRight", "InsetBorderBottomLeft", "InsetBorderBottomRight",
    "InsetBorderTop", "InsetBorderBottom", "InsetBorderLeft", "InsetBorderRight",
}
local mapBorderArt = { "TopBorder", "TopTileStreaks" }
local nineSliceArt = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

local function Direct(parent, key, kind)
    local region = Safety.Field(parent, key)
    if Safety.Public(region) and Safety.CanDecorate(region)
        and Kit.ParentIs(region, parent) and Kit.ObjectType(region) == kind then return region end
end

local function FadePieces(parent, keys, state, preserve)
    for _, key in ipairs(keys) do
        local piece = Direct(parent, key, "Texture")
        if piece and piece ~= preserve then NS.Cosmetics.FadeDecoration(piece, state) end
    end
end

-- Textures share the native host's BORDER layer, below the title FontString.
-- Each strip ends at the map margin and follows native panel resizing.
local function Strip(host, from, to, x1, y1, x2, y2, width, height)
    local texture = host:CreateTexture(nil, "BORDER", nil, 1)
    texture:SetPoint(from, host, from, x1, y1)
    texture:SetPoint(to, host, to, x2, y2)
    if width then texture:SetWidth(width) else texture:SetHeight(height) end
    return texture
end

local function CreateArt(host, top, left, right, bottom)
    return {
        Strip(host, "TOPLEFT", "TOPRIGHT", 0, 0, 0, 0, nil, top - 1),
        Strip(host, "TOPLEFT", "TOPRIGHT", 0, 1 - top, 0, 1 - top, nil, 1),
        Strip(host, "TOPLEFT", "BOTTOMLEFT", 0, -top, 0, bottom, left),
        Strip(host, "TOPRIGHT", "BOTTOMRIGHT", 0, -top, 0, bottom, right),
        Strip(host, "BOTTOMLEFT", "BOTTOMRIGHT", 0, 0, 0, 0, nil, bottom),
    }
end

local tokens = { "ink", "border", "background", "background", "background" }
local watchedColors = { color = { ink = true, border = true, background = true } }
local function Paint(art)
    for index, texture in ipairs(art) do
        texture:SetColorTexture(NS.Theme.GetColor(tokens[index]))
        texture:Show()
    end
end

local function Repaint()
    for host, state in pairs(states) do
        if next(state.owners) and Safety.CanCreateRegions(host) then Paint(state.art) end
    end
end

local function State(host, owner, top, left, right, bottom)
    local state = states[host]
    if not state then
        state = { owners = {}, art = CreateArt(host, top, left, right, bottom) }
        states[host] = state
        NS.Registry.WatchSettings(Repaint, watchedColors)
    end
    state.owners[owner] = true
    Paint(state.art)
    return state
end

function Chrome.Apply(frame, owner)
    if NS.IsCombatLocked() or not Safety.CanCreateRegions(frame) then return end
    if frame == TaxiFrame then
        local map = Direct(frame, "InsetBg", "Texture")
        if not map or not Direct(frame, "TopBorder", "Texture") then return end
        local state = State(frame, owner, 24, 4, 6, 4)
        FadePieces(frame, taxiArt, state, map)
    elseif frame == FlightMapFrame then
        local host = Direct(frame, "BorderFrame", "Frame")
        if not host or not Safety.CanCreateRegions(host) then return end
        local nineSlice = Direct(host, "NineSlice", "Frame")
        if not nineSlice or not Direct(host, "TopBorder", "Texture") then return end
        -- Match MapCanvasFrameScrollContainerTemplate's native viewport.
        local state = State(host, owner, 20, 1, 1, 1)
        -- SetupTitle reparents Bg to the map root. Underlay belongs to the
        -- quest details interaction; neither participates in this paint pass.
        FadePieces(host, mapBorderArt, state)
        FadePieces(nineSlice, nineSliceArt, state)
    else
        return
    end
    return true
end

function Chrome.Disable(owner)
    for _, state in pairs(states) do
        if state.owners[owner] then
            state.owners[owner] = nil
            if not next(state.owners) then
                for _, texture in ipairs(state.art) do texture:Hide() end
                NS.Cosmetics.RestoreOwner(state)
            end
        end
    end
end
