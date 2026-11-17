local _, private = ...
local NS, Style = private.NS, private.NS.NameplateStyle
local Writable, Mutable = private.CastAppearance.Accessible, private.CastAppearance.Mutable
local Public = NS.Public
local Outline = {}
private.CastOutline = Outline

local states = setmetatable({}, { __mode = "k" })
local baseColors = setmetatable({}, { __mode = "k" })
local warning = { outlineR = 1, outlineG = .22, outlineB = .13, outlineA = 1 }
local warningColor

-- Keep native Show/Hide and retain the alpha that a rebuild wants to use.
local function NativeAlpha(state, key, region, hide, reset)
    local saved = state[key]
    if hide == (saved ~= nil) and not (hide and reset) then return true end
    if Public(region) and not region then return saved == nil end
    if not Writable(region) then return false end
    if hide then
        local alpha = region:GetAlpha()
        if not NS.Finite(alpha) then return false end
        if alpha ~= 0 then region:SetAlpha(0) end
        if alpha ~= 0 or saved == nil then state[key] = alpha end
    else
        region:SetAlpha(saved)
        state[key] = nil
    end
    return true
end

local function BaseColor(settings, visible)
    local color = baseColors[settings]
    local r, g, b = settings.outlineR or 0, settings.outlineG or 0, settings.outlineB or 0
    local a = visible and (settings.outlineA or 1) or 0
    if not color or color.r ~= r or color.g ~= g or color.b ~= b or color.a ~= a then
        color = CreateColor(r, g, b, a)
        baseColors[settings] = color
    end
    return color
end

local function PaintSecret(visual, targeted, normal)
    for i = 1, 4 do visual.edges[i]:SetVertexColorFromBoolean(targeted, warningColor, normal) end
end

local function PaintEdges(cast, state, targeted, known)
    local active, width, visual = known and targeted == true, state.width, state.visual
    if known then
        state.lastTarget, state.booleanColor = active, nil
    else
        state.lastTarget = nil
    end
    local size = width > 0 and width or ((active or not known) and state.warningWidth or 0)
    if size == 0 then
        if visual then Style.PaintBorder(visual, cast, 0) end
        return
    end
    if not visual then
        visual = Style.CreateBorder(cast)
        state.visual = visual
        -- The independent native important-cast and interrupt art draws above this edge.
        for i = 1, 4 do visual.edges[i]:SetDrawLayer("ARTWORK", 5) end
    end
    if known then
        Style.PaintCastOutline(visual, cast, size, active and warning or state.settings)
    else
        Style.PaintBorder(visual, cast, size, "ffffff")
        state.booleanColor = BaseColor(state.settings, width > 0)
        warningColor = warningColor or CreateColor(warning.outlineR, warning.outlineG, warning.outlineB, warning.outlineA)
        PaintSecret(visual, targeted, state.booleanColor)
        visual.r, visual.g, visual.b, visual.a = nil, nil, nil, nil
    end
end

local function OnTargetChanged(cast, targeted)
    local state = Public(cast) and states[cast]
    if not state or not state.targetActive then return end
    local known = Public(targeted)
    if known and state.lastTarget == (targeted == true) then return end
    if not Mutable(cast) then
        if private.Textures then private.Textures.DeferCast(cast) end
        return
    end
    if not known and state.booleanColor then
        PaintSecret(state.visual, targeted, state.booleanColor)
    else
        PaintEdges(cast, state, targeted, known)
    end
end

local function PaintNativeTarget(cast, state, replace, reset)
    if not replace then
        if not state.targetRegion then return true end
        if not NativeAlpha(state, "targetAlpha", state.targetRegion, false) then return false end
        state.targetRegion = nil
        return true
    end
    if state.targetRegion then return NativeAlpha(state, "targetAlpha", state.targetRegion, true, reset) end
    local region = cast.CastTargetIndicator
    if not Public(region) or not region or not cast.GetIsHighlightedCastTarget or not cast.SetIsHighlightedCastTarget then
        return true
    end
    -- A castbar that can become unwritable in combat must keep its native warning.
    local protected = cast:IsProtected()
    if not Public(protected) or protected ~= false then return true end
    if not NativeAlpha(state, "targetAlpha", region, true) then return false end
    state.targetRegion = region
    if not state.targetHooked then
        hooksecurefunc(cast, "SetIsHighlightedCastTarget", OnTargetChanged)
        state.targetHooked = true
    end
    return true
end

function Outline.Paint(cast, settings, reset)
    local width = settings and settings.outlineSize
    local replace = settings and settings.targetHighlight == true
    local state = states[cast]
    if not state then
        if width == nil and not replace then return true end
        state = {}
        states[cast] = state
    end
    local targetDone = PaintNativeTarget(cast, state, replace, reset)
    state.targetActive = replace and state.targetRegion ~= nil
    state.settings, state.width = settings, width or 0
    if state.width > 0 or state.targetActive then
        local scale = cast:GetEffectiveScale()
        local size = state.width > 0 and state.width or 1
        if NS.Finite(scale) and scale > 0 then size = PixelUtil.GetNearestPixelSize(size, scale, 1) end
        if state.width > 0 then state.width = size else state.warningWidth = size end
    end
    local targeted
    if state.targetActive then targeted = cast:GetIsHighlightedCastTarget() end
    PaintEdges(cast, state, targeted, Public(targeted))
    return NativeAlpha(state, "borderAlpha", cast.Border, width ~= nil, reset) and targetDone
end
