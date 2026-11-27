local _, NS = ...

-- Each visible slice clips a full-window canvas. Nothing parents to or writes
-- native windows; their focus controller supplies readable UIParent geometry.
local Visual = {}
NS.WindowFocusVisual = Visual
local Safety = NS.Safety
local records = setmetatable({}, { __mode = "k" })
local LAYERS = {
    { layer = "BACKGROUND", sub = 0, color = { 0, 0, 0, 0.145 } },
    { layer = "BACKGROUND", sub = 1, color = { 0.010, 0.014, 0.026, 0.045 } },
    { layer = "BORDER", sub = 0, asset = "Smoothv2.tga", inset = -5, color = { 0.018, 0.026, 0.052, 0.032 } },
    { layer = "BORDER", sub = 1, asset = "Smoothv2.tga", inset = 4, rotated = true, color = { 0.014, 0.022, 0.046, 0.026 } },
    { layer = "BORDER", sub = 2, asset = "Smoothv2.tga", color = { 0.024, 0.034, 0.068, 0.040 } },
    { layer = "BORDER", sub = 3, asset = "Charcoal.tga", color = { 0.035, 0.040, 0.070, 0.052 } },
}

local function PaintFallback(record)
    local canvas = record.canvas
    local layers = record.layers
    for index = 1, #LAYERS do
        local spec = LAYERS[index]
        local texture = layers[index]
        if not texture then
            texture = canvas:CreateTexture(nil, spec.layer, nil, spec.sub)
            layers[index] = texture
        end
        texture:ClearAllPoints()
        if spec.inset then
            texture:SetPoint("TOPLEFT", canvas, "TOPLEFT", spec.inset, -spec.inset)
            texture:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -spec.inset, spec.inset)
        else
            texture:SetAllPoints(canvas)
        end
        local color = spec.color
        if spec.asset then
            texture:SetTexture(NS.path .. "Media\\Bars\\" .. spec.asset)
            texture:SetVertexColor(color[1], color[2], color[3], color[4])
        else
            texture:SetColorTexture(color[1], color[2], color[3], color[4])
        end
        if spec.rotated then texture:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1) end
        texture:SetBlendMode("BLEND")
        texture:Show()
    end
end

local function Paint(record, refresh)
    if NS.SuiteCore().HostBridge.MenuFocusVeil(record.canvas, "dropdown") then
        if record.fallbackVisible then
            for index = 1, #record.layers do record.layers[index]:Hide() end
            record.fallbackVisible = false
        end
    elseif refresh or record.fallbackVisible == nil then
        PaintFallback(record)
        record.fallbackVisible = true
    elseif not record.fallbackVisible then
        -- The host only owns its named layers. Our local material retained
        -- its anchors, assets and colors while those layers were displayed.
        for index = 1, #record.layers do record.layers[index]:Show() end
        record.fallbackVisible = true
    end
end

local function ReducedMotion()
    return not NS.Motion.Enabled() or NS.SuiteCore().HostBridge.MenuReducedMotion()
end

local function Finish(group)
    local record = records[group]
    if not record or record.dim or not Safety.CanDecorate(record.overlay) then return end
    record.overlay:Hide()
    record.overlay:SetAlpha(0)
    record.visible = false
end

local function Fade(record, to, immediate)
    local overlay, group, alpha = record.overlay, record.group, record.alpha
    local from = Safety.Read(overlay, "GetAlpha") or 0
    if Safety.Read(group, "IsPlaying") then
        local progress = Safety.Read(alpha, "GetSmoothProgress")
        if progress then from = record.from + (record.to - record.from) * progress end
    end
    group:Stop()
    if immediate or ReducedMotion() then
        overlay:SetAlpha(to)
        if to == 0 then Finish(group) end
        return
    end
    alpha:SetDuration(to == 1 and 0.095 or 0.080)
    alpha:SetSmoothing(to == 1 and "OUT" or "IN")
    alpha:SetFromAlpha(from)
    alpha:SetToAlpha(to)
    record.from, record.to = from, to
    overlay:SetAlpha(from)
    group:Play()
end

function Visual.Create()
    local overlay = Safety.CreateChildFrame("Frame", UIParent)
    overlay:EnableMouse(false)
    overlay:SetClipsChildren(true)
    overlay:SetAlpha(0)
    overlay:Hide()
    -- Keep the host's six-layer material intact. This window-only underlay
    -- combines with its 14.5% black layer to reach a clear 42% black base.
    local canvas = Safety.CreateChildFrame("Frame", overlay)
    canvas:EnableMouse(false)
    local shade = canvas:CreateTexture(nil, "BACKGROUND", nil, -1)
    shade:SetAllPoints(canvas)
    local base = LAYERS[1].color[4]
    shade:SetColorTexture(0, 0, 0, (0.42 - base) / (1 - base))
    local group = overlay:CreateAnimationGroup()
    local alpha = group:CreateAnimation("Alpha")
    group:SetToFinalAlpha(true)
    group:SetScript("OnFinished", Finish)
    local record = { overlay = overlay, canvas = canvas, group = group, alpha = alpha, layers = {} }
    records[group] = record
    return record
end

function Visual.Show(record, rect, fullRect, strata, level)
    if not Safety.CanDecorate(record.overlay) then return false end
    local overlay, canvas = record.overlay, record.canvas
    if record.left ~= rect.left or record.bottom ~= rect.bottom then
        record.left, record.bottom = rect.left, rect.bottom
        overlay:ClearAllPoints()
        overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", rect.left, rect.bottom)
    end
    if record.width ~= rect.width or record.height ~= rect.height then
        record.width, record.height = rect.width, rect.height
        overlay:SetSize(rect.width, rect.height)
    end
    if record.strata ~= strata or record.level ~= level then
        record.strata, record.level = strata, level
        overlay:SetFrameStrata(strata)
        overlay:SetFrameLevel(level)
        canvas:SetFrameStrata(strata)
        canvas:SetFrameLevel(level + 1)
    end
    local scale = (rect.source or rect).unitScale or 1
    if record.scale ~= scale then
        record.scale = scale
        canvas:SetScale(scale)
    end
    local x, y = (fullRect.left - rect.left) / scale, (fullRect.bottom - rect.bottom) / scale
    if record.canvasX ~= x or record.canvasY ~= y then
        record.canvasX, record.canvasY = x, y
        canvas:ClearAllPoints()
        canvas:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", x, y)
    end
    local width, height = fullRect.width / scale, fullRect.height / scale
    if record.canvasWidth ~= width or record.canvasHeight ~= height then
        record.canvasWidth, record.canvasHeight = width, height
        canvas:SetSize(width, height)
    end
    record.rect, record.fullRect = rect, fullRect
    if not record.dim then
        Paint(record)
        record.dim, record.visible = true, true
        overlay:Show()
        Fade(record, 1)
    end
    if not NS.WindowFocusContour.Apply(record, rect, fullRect) then
        Visual.Hide(record, true)
        return false
    end
    return true
end

function Visual.Hide(record, immediate)
    if not record.visible or not Safety.CanDecorate(record.overlay) then return end
    if not record.dim and not immediate then return end
    record.dim = false
    Fade(record, 0, immediate)
end

function Visual.Refresh(record)
    if not record.visible or not Safety.CanDecorate(record.overlay) then return end
    Paint(record, true)
    if not NS.WindowFocusContour.Apply(record, record.rect, record.fullRect, true) then
        Visual.Hide(record, true)
        return
    end
    if ReducedMotion() then Fade(record, record.dim and 1 or 0, true) end
end

-- Reuse the tooltip's actual edge art on an addon-owned overlay. The center
-- belongs to the outlined window; only the eight edge pieces are installed.
local outlineLayout
-- With rounded windows the outline follows the window's corners. Each ring is
-- the window shape's 2 px edge, one UI unit further in than the one before,
-- so a thicker outline leaves no gap along the curves.
local ROUND_RING_SPECS = { { role = "shell", border = 1 }, { role = "shell", border = 2 } }
local MAX_ROUND_RINGS = 9

-- Outline pixels as UI units at the outline's own scale.
local function OutlineUnits(art, pixels)
    local factor = NS.SuiteCore().WindowCaption.PixelFactor()
    local scale = art:GetEffectiveScale()
    if type(factor) ~= "number" or type(scale) ~= "number" or factor <= 0 or scale <= 0 then return pixels end
    return pixels * factor / scale
end

local function MatchWindowScale(art, frame)
    local target = Safety.Read(frame, "GetEffectiveScale")
    local parent = Safety.Read(UIParent, "GetEffectiveScale")
    local scale = type(target) == "number" and target > 0 and type(parent) == "number" and parent > 0 and target / parent or 1
    if (art.roundScale or 1) ~= scale then
        art:SetScale(scale)
        art.roundScale = scale
    end
end

function Visual.PaintRoundOutline(frame, art, pixels, r, g, b, a, strata, level, attachToWindow, logicalWidth)
    if not art then
        art = attachToWindow and Safety.CreateChildFrame("Frame", frame) or CreateFrame("Frame", nil, UIParent)
        art:EnableMouse(false)
        art:SetAllPoints(frame)
        art.rings = {}
    end
    if not attachToWindow then MatchWindowScale(art, frame) end
    local units = logicalWidth and pixels or OutlineUnits(art, pixels)
    local thin = units < 1.5
    local count = thin and 1 or math.min(MAX_ROUND_RINGS, math.floor(units + 0.5) - 1)
    local geometry = NS.Geometry.Resolve(ROUND_RING_SPECS[thin and 1 or 2], art.geometry)
    art.geometry = geometry
    for index = 1, count do
        local ring = art.rings[index]
        if not ring then
            ring = art:CreateTexture(nil, "OVERLAY")
            art.rings[index] = ring
        end
        local inset = index - 1
        ring:ClearAllPoints()
        ring:SetPoint("TOPLEFT", art, "TOPLEFT", inset, -inset)
        ring:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -inset, inset)
        NS.Geometry.ConfigureShape(ring, geometry.edge, geometry)
        ring:SetVertexColor(r, g, b, a)
        ring:Show()
    end
    for index = count + 1, #art.rings do art.rings[index]:Hide() end
    if strata and art:GetFrameStrata() ~= strata then art:SetFrameStrata(strata) end
    if level and art:GetFrameLevel() ~= level then art:SetFrameLevel(level) end
    art:Show()
    return art
end

function Visual.PaintTooltipOutline(frame, art, strata, level)
    local tooltips = NS.SuiteCore().Tooltips
    local r, g, b, a
    if tooltips and tooltips.DB.enabled then
        r, g, b, a = tooltips.TooltipChrome.GetBorder()
    else
        r, g, b, a = NS.Theme.GetColor("border")
        a = NS.DB.geometry.border > 0 and a * NS.Theme.GetBorderOpacity() or 0
    end
    if a <= 0 then
        if art then art:Hide() end
        return art
    end
    if not art then
        if not outlineLayout then
            local native = NineSliceUtil and NineSliceUtil.GetLayout("TooltipDefaultLayout")
            if not native then return end
            outlineLayout = NS.CopyValue(native)
            outlineLayout.Center = nil
        end
        art = CreateFrame("Frame", nil, UIParent, "NineSlicePanelTemplate")
        art:EnableMouse(false)
        art:SetAllPoints(frame)
        NineSliceUtil.ApplyLayout(art, outlineLayout)
    end
    local tooltipScale = Safety.Read(GameTooltip, "GetEffectiveScale")
    local parentScale = Safety.Read(UIParent, "GetEffectiveScale")
    local scale = tooltipScale and parentScale and parentScale > 0 and tooltipScale / parentScale or 1
    if art:GetScale() ~= scale then art:SetScale(scale) end
    if art:GetFrameStrata() ~= strata then art:SetFrameStrata(strata) end
    if art:GetFrameLevel() ~= level then art:SetFrameLevel(level) end
    art:SetBorderColor(r, g, b, a)
    art:Show()
    return art
end
