local _, NS = ...

-- Shared tooltips are also native layout inputs. Keep their textures, anchors
-- and widget payload intact. The palette is applied only to existing chrome.
local Safety = NS.Safety
local TooltipChrome = {}
NS.TooltipChrome = TooltipChrome

local tooltips = setmetatable({}, { __mode = "k" })
local pending = setmetatable({}, { __mode = "k" })
local scheduled = false
local styleHooked = false
local borderPieces = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
}
local fillSpec = { role = "popup", radius = 8 }

local plan
local function PrepareStyle()
    local material = NS.Theme.GetMaterial("popup")
    local r, g, b, a = NS.Theme.GetColor(material.border)
    local edge = NS.Geometry.Resolve(fillSpec).edge
    plan = {
        fill = NS.Surface.PrepareFill(material, fillSpec),
        r = r, g = g, b = b, alpha = edge and a * NS.Theme.GetBorderOpacity() or 0,
    }
end

local function SaveColor(color, r, g, b, a)
    color[1], color[2], color[3], color[4] = r, g, b, a
end

local function Capture(state, region)
    if not Safety.Public(region) or not Safety.CanDecorate(region) then return end
    local r, g, b, a = Safety.ReadColor(region, "GetVertexColor")
    if r == nil then return end
    local paint = state.regions[region]
    if not paint then
        paint = { spec = fillSpec, original = {}, applied = {} }
        state.regions[region] = paint
    end
    if not Safety.ColorMatches(paint.applied, r, g, b, a, Safety.COLOR_OWN) then
        SaveColor(paint.original, r, g, b, a)
    end
    return paint
end

local function Paint(frame, state)
    if not Safety.CanDecorate(frame) then return false, "protected" end
    local slice = Safety.Field(frame, "NineSlice")
    if not Safety.Public(slice) or not Safety.CanDecorate(slice) then return false, "missing" end
    local center = Safety.Field(slice, "Center")
    local fill = Capture(state, center)
    if not fill then return false, "missing" end

    if not plan then PrepareStyle() end
    NS.Surface.PaintFill(center, nil, fill, nil, plan.fill)
    SaveColor(fill.applied, Safety.ReadColor(center, "GetVertexColor"))

    local r, g, b, alpha = plan.r, plan.g, plan.b, plan.alpha
    if state.tint then r, g, b = unpack(state.tint) end
    -- Blizzard can install another region in the same slice. Resolve the
    -- live handle before using its retained original and applied colors.
    for index = 1, #borderPieces do
        local region = Safety.Field(slice, borderPieces[index])
        local paint = Capture(state, region)
        if paint then
            region:SetVertexColor(r, g, b, alpha)
            SaveColor(paint.applied, r, g, b, alpha)
        end
    end
    return true
end

local function Flush()
    scheduled = false
    for frame in pairs(pending) do
        pending[frame] = nil
        local state = tooltips[frame]
        if state then Safety.Dispatch(Paint, frame, state) end
    end
end

local function RequestPaint(frame)
    pending[frame] = true
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, Flush)
end

-- Both clients reset the Center color in SharedTooltip_SetBackdropStyle.
-- Its callers can still clear or lay out widgets. The global post-hook
-- records the request and the paint runs after the native call stack.
local function OnStyleChanged(frame)
    if Safety.Public(frame) and type(frame) == "table" and tooltips[frame] then
        RequestPaint(frame)
    end
end

local function OnThemeChanged(_, domain)
    if domain ~= "theme" and domain ~= "color" and domain ~= "appearance"
        and domain ~= "geometry" and domain ~= "profile" then return end
    plan = nil
    if next(tooltips) then PrepareStyle() end
    for frame in pairs(tooltips) do RequestPaint(frame) end
end

function TooltipChrome.Apply(frame, owner)
    if not Safety.Public(frame) or not Safety.CanDecorate(frame) then return false, "protected" end
    local state = tooltips[frame]
    if not state then
        state = { owners = {}, regions = setmetatable({}, { __mode = "k" }) }
        tooltips[frame] = state
    end
    state.owners[owner] = true
    if not styleHooked and type(SharedTooltip_SetBackdropStyle) == "function" then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", OnStyleChanged)
        NS.Registry.AddListener(TooltipChrome, OnThemeChanged)
        styleHooked = true
    end
    return Paint(frame, state)
end

-- QoL supplies its item/class color through Surface.TintEdge. Keep the
-- request with this tooltip so Blizzard style resets cannot overwrite it.
function TooltipChrome.TintEdge(frame, r, g, b)
    if not Safety.Public(frame) or not Safety.CanDecorate(frame) then return false end
    local state = tooltips[frame]
    if not state then return false end
    if Safety.Public(r) and r == nil then
        state.tint = nil
    elseif Safety.Public(r) and Safety.Public(g) and Safety.Public(b)
        and type(r) == "number" and type(g) == "number" and type(b) == "number" then
        state.tint = state.tint or {}
        state.tint[1], state.tint[2], state.tint[3] = r, g, b
    else
        return false
    end
    RequestPaint(frame)
    return true
end

local function Restore(region, paint)
    if not Safety.CanDecorate(region) then return end
    local r, g, b, a = Safety.ReadColor(region, "GetVertexColor")
    local owned = Safety.ColorMatches(paint.applied, r, g, b, a, Safety.COLOR_OWN)
    if paint.gradientFrom then
        -- Blizzard's tooltip atlases use a flat tint. Remove our gradient
        -- independently of a native style reset that changed the vertex color.
        local white = CreateColor(1, 1, 1, 1)
        region:SetGradient("VERTICAL", white, white)
    end
    if owned then
        region:SetVertexColor(unpack(paint.original))
    elseif paint.gradientFrom and r ~= nil then
        region:SetVertexColor(r, g, b, a)
    end
end

function TooltipChrome.DisableOwner(owner)
    for frame, state in pairs(tooltips) do
        state.owners[owner] = nil
        if not next(state.owners) then
            tooltips[frame], pending[frame] = nil, nil
            for region, paint in pairs(state.regions) do Restore(region, paint) end
        end
    end
end
