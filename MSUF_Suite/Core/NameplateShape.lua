local _, NS = ...
local Style = NS.NameplateStyle

local SLANT_MEDIA = "Interface\\AddOns\\MSUF_Suite\\Media\\Nameplates\\SlantedHealth"
local CORE_MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\slanted_bar_"
local SUFFIX = { RIGHT_DOWN = "", RIGHT_UP = "_right_up", LEFT_DOWN = "_left_down", LEFT_UP = "_left_up",
    BOTH_DOWN = "_both_down", BOTH_UP = "_both_up" }
Style.SlantedDirections = { "DEFAULT", "RIGHT_DOWN", "RIGHT_UP", "LEFT_DOWN", "LEFT_UP", "BOTH_DOWN", "BOTH_UP" }

function Style.SlantedSettings(config)
    local bridge = NS.HostBridge
    local enabled, direction, power, hover = true, nil, true, true
    if bridge and bridge.SharedSlantedBars then enabled, direction, power, hover = bridge.SharedSlantedBars() end
    local selected = Style.SlantedDirections[config.slantedDirection]
    if SUFFIX[selected] then direction = selected end
    return enabled and config.look ~= 2 and config.enemySlantedHealth == true, SUFFIX[direction] and direction or nil, power, hover
end

local roundedMaterials = {}

local function RoundedSettings()
    local bridge = NS.HostBridge
    if not bridge or not bridge.SharedRoundedBars then return end
    local mask, edge, power, hover, cast = bridge.SharedRoundedBars()
    if not mask or not edge then return end
    local material = roundedMaterials[mask]
    if not material then
        material = { mask = mask, edge = edge }
        roundedMaterials[mask] = material
    end
    return material, power, hover, cast
end

function Style.RoundedSettings(config)
    if config.look == 2 or config.roundedHealth ~= true then return false end
    local material, power, hover = RoundedSettings()
    return material ~= nil, material, power, hover
end

function Style.NameplateShapeSettings(config)
    local enabled, material, power, hover = Style.RoundedSettings(config)
    if enabled then return enabled, material, power, hover end
    return Style.SlantedSettings(config)
end

function Style.RoundedCastMaterial()
    local material, _, _, cast = RoundedSettings()
    if cast then return material end
end

local function ApplySlice(region, path, rounded)
    if not rounded and not region._msufSuiteRoundedSlice then return end
    local bridge = NS.HostBridge
    if bridge and bridge.ApplyNameplateShapeSlice then bridge.ApplyNameplateShapeSlice(region, path) end
    region._msufSuiteRoundedSlice = rounded or nil
end

function Style.SetShapeMaskMedia(mask, material)
    local rounded = type(material) == "table"
    local suffix = SUFFIX[material]
    local texture = rounded and material.mask or suffix and CORE_MEDIA .. "mask" .. suffix .. ".png" or SLANT_MEDIA .. "Mask.tga"
    mask:SetTexture(texture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    ApplySlice(mask, texture, rounded)
end

function Style.CreateShapeMask(owner, material)
    local mask = owner:CreateMaskTexture()
    Style.SetShapeMaskMedia(mask, material)
    mask:SetAllPoints(owner)
    return mask
end

-- Rounded corners stay on the outer bar. One-sided slants keep their
-- full-width taper and track the corresponding edge of the filled region.
function Style.FitShapeFillMask(state, owner, fill)
    local direction = state.direction
    if type(direction) == "table" then
        if state.fillAnchor ~= owner then
            state.fillMask:ClearAllPoints()
            state.fillMask:SetAllPoints(owner)
            state.fillAnchor, state.fillEdge, state.fillWidth = owner, nil, nil
        end
        return
    end
    local edge = (direction == "LEFT_DOWN" or direction == "LEFT_UP") and "LEFT" or "RIGHT"
    local both = direction == "BOTH_DOWN" or direction == "BOTH_UP"
    local width = not both and owner:GetWidth()
    if not NS.Finite(width) or width <= 0 then width = nil end
    local mask = state.fillMask
    if state.fillAnchor ~= fill or state.fillEdge ~= edge or (width == nil) ~= (state.fillWidth == nil) then
        mask:ClearAllPoints()
        if width then
            local top, bottom = "TOP" .. edge, "BOTTOM" .. edge
            mask:SetPoint(top, fill, top)
            mask:SetPoint(bottom, fill, bottom)
        else
            mask:SetAllPoints(fill)
        end
        state.fillAnchor, state.fillEdge = fill, edge
    end
    if width and state.fillWidth ~= width then mask:SetWidth(width) end
    state.fillWidth = width
end

function Style.SetShapeRimMedia(rim, material)
    local rounded = type(material) == "table"
    local suffix = SUFFIX[material]
    local path = rounded and material.edge or suffix and CORE_MEDIA .. "edge" .. suffix .. ".png" or SLANT_MEDIA .. "Edge.tga"
    rim:SetTexture(path)
    ApplySlice(rim, path, rounded)
end

function Style.CreateShapeRim(owner, layer, sublevel, material)
    local rim = owner:CreateTexture(nil, layer, nil, sublevel)
    Style.SetShapeRimMedia(rim, material)
    rim:SetAllPoints(owner)
    rim:Hide()
    return rim
end

function Style.PaintSlantedRim(visual, size, color)
    local shown = size > 0
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
function Style.SetShapeSample(owner, visual, enabled, fill, pattern, direction, ...)
    enabled = enabled == true
    if enabled then
        if not visual.mask then
            visual.mask = Style.CreateShapeMask(owner, direction)
            visual.fillMask = Style.CreateShapeMask(owner, direction)
            visual.slantRim = Style.CreateShapeRim(owner, "OVERLAY", 7, direction)
        elseif visual.direction ~= direction then
            Style.SetShapeMaskMedia(visual.mask, direction)
            Style.SetShapeMaskMedia(visual.fillMask, direction)
            Style.SetShapeRimMedia(visual.slantRim, direction)
        end
        visual.direction = direction
        Style.FitShapeFillMask(visual, owner, fill)
    end
    if enabled == (visual.slanted == true) then return end
    if enabled then
        fill:AddMaskTexture(visual.fillMask)
        if pattern then pattern:AddMaskTexture(visual.fillMask) end
    else
        fill:RemoveMaskTexture(visual.fillMask)
        if pattern then pattern:RemoveMaskTexture(visual.fillMask) end
    end
    for index = 1, select("#", ...) do
        local texture = select(index, ...)
        if texture then
            if enabled then texture:AddMaskTexture(visual.mask) else texture:RemoveMaskTexture(visual.mask) end
        end
    end
    visual.paintSlantedRim = enabled and Style.PaintSlantedRim or nil
    visual.slanted, visual.borderColor, visual.borderSize = enabled, nil, nil
    if not enabled then visual.slantRim:Hide() end
end
