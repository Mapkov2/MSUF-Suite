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

local function Paint(record)
    if NS.SuiteCore().HostBridge.MenuFocusVeil(record.canvas, "dropdown") then
        for index = 1, #record.layers do record.layers[index]:Hide() end
    else
        PaintFallback(record)
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
    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", rect.left, rect.bottom)
    overlay:SetSize(rect.width, rect.height)
    overlay:SetFrameStrata(strata)
    overlay:SetFrameLevel(level)
    local scale = (rect.source or rect).unitScale or 1
    canvas:SetScale(scale)
    canvas:ClearAllPoints()
    canvas:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", (fullRect.left - rect.left) / scale, (fullRect.bottom - rect.bottom) / scale)
    canvas:SetSize(fullRect.width / scale, fullRect.height / scale)
    canvas:SetFrameStrata(strata)
    canvas:SetFrameLevel(level + 1)
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
    Paint(record)
    if not NS.WindowFocusContour.Apply(record, record.rect, record.fullRect) then
        Visual.Hide(record, true)
        return
    end
    if ReducedMotion() then Fade(record, record.dim and 1 or 0, true) end
end
