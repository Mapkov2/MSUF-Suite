local _, NS = ...
local Style = NS.NameplateStyle

local SLANT_MEDIA = "Interface\\AddOns\\MSUF_Suite\\Media\\Nameplates\\SlantedHealth"

function Style.CreateSlantedMask(owner)
    local mask = owner:CreateMaskTexture()
    mask:SetTexture(SLANT_MEDIA .. "Mask.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(owner)
    return mask
end

-- The mask's left edge is vertical. A full-width mask aligned to the right of
-- the partial fill keeps its taper parallel to the outline at every value.
function Style.FitSlantedFillMask(state, owner, fill)
    local width = owner:GetWidth()
    if not NS.Finite(width) or width <= 0 then width = nil end
    local mask = state.fillMask
    if state.fillAnchor ~= fill or (width == nil) ~= (state.fillWidth == nil) then
        mask:ClearAllPoints()
        if width then
            mask:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
            mask:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
        else
            mask:SetAllPoints(fill)
        end
        state.fillAnchor = fill
    end
    if width and state.fillWidth ~= width then mask:SetWidth(width) end
    state.fillWidth = width
end

function Style.CreateSlantedRim(owner, layer, sublevel)
    local rim = owner:CreateTexture(nil, layer, nil, sublevel)
    rim:SetTexture(SLANT_MEDIA .. "Edge.tga")
    rim:SetAllPoints(owner)
    rim:Hide()
    return rim
end

function Style.PaintSlantedRim(visual, size, color)
    local shown = visual.slanted and size > 0 or false
    local rim = visual.slantRim
    if shown then
        if visual.slantColor ~= color then
            rim:SetVertexColor(NS.RGB(color))
            visual.slantColor = color
        end
        visual.borderColor = color
    end
    rim:SetShown(shown)
    return shown
end

function Style.ReplaceSlantedMask(texture, previous, mask)
    if previous == mask then return mask end
    if previous then texture:RemoveMaskTexture(previous) end
    if mask then texture:AddMaskTexture(mask) end
    return mask
end

-- The preview owns its regions, so it can apply the mask without the native texture lease.
function Style.SetSlantedSample(owner, visual, enabled, fill, pattern, ...)
    if enabled and not visual.mask then
        visual.mask = Style.CreateSlantedMask(owner)
        visual.fillMask = Style.CreateSlantedMask(owner)
        visual.slantRim = Style.CreateSlantedRim(owner, "OVERLAY", 7)
        visual.paintSlantedRim = Style.PaintSlantedRim
    end
    if enabled then Style.FitSlantedFillMask(visual, owner, fill) end
    if enabled == (visual.slanted == true) then return end
    if enabled then
        fill:AddMaskTexture(visual.fillMask)
        pattern:AddMaskTexture(visual.fillMask)
    else
        fill:RemoveMaskTexture(visual.fillMask)
        pattern:RemoveMaskTexture(visual.fillMask)
    end
    for index = 1, select("#", ...) do
        local texture = select(index, ...)
        if enabled then texture:AddMaskTexture(visual.mask) else texture:RemoveMaskTexture(visual.mask) end
    end
    visual.slanted, visual.borderColor = enabled, nil
end
