local _, NS = ...

-- Contours are read only on visible layout discovery. Their owned masks never
-- attach to Blizzard regions; cached numeric geometry also serves drag updates.
local Contour = {}
NS.WindowFocusContour = Contour
local Safety = NS.Safety

local function Field(frame, name)
    if not Safety.Public(frame) or Safety.IsForbidden(frame) then return nil end
    local value = Safety.Field(frame, name)
    if Safety.Public(value) and not Safety.IsForbidden(value) then return value end
end

function Contour.Skin(frame)
    local surface = NS.Registry.GetSurface(frame)
    if surface and surface.visible ~= false then return surface end
end

function Contour.Artwork(root, frame)
    local border = Field(root, "BorderFrame")
    if frame == Field(root, "PortraitContainer") or frame == Field(border, "PortraitContainer") then
        return Field(frame, "portrait"), Field(frame, "CircleMask"), true
    end
    if frame == Field(border, "Tutorial") then return Field(frame, "I"), nil, true end
end

local function CopyUV(target, ...)
    if select("#", ...) ~= 8 then return false end
    for index = 1, 8 do
        local value = select(index, ...)
        if not Safety.Public(value) or type(value) ~= "number" then return false end
        target[index] = value
    end
    return true
end

local function ReadArt(region, descriptor, rect)
    if not region or Safety.Read(region, "IsShown") ~= true then return nil end
    local asset = Safety.Read(region, "GetTexture")
    local atlas = Safety.Read(region, "GetAtlas")
    if type(asset) ~= "string" and type(asset) ~= "number" and type(atlas) ~= "string" then return nil end
    if not NS.WindowFocusGeometry.Read(region, rect) then return nil end
    descriptor = descriptor or {}
    descriptor.uv = descriptor.uv or {}
    if not CopyUV(descriptor.uv, Safety.Call(region, "GetTexCoord")) then return nil end
    descriptor.asset, descriptor.atlas = asset, atlas
    return descriptor
end

function Contour.Describe(frame, contour)
    local surface = Contour.Skin(frame)
    if not surface or not surface.geometry then return nil end
    contour = contour or {}
    contour.geometry, contour.inset = surface.geometry, tonumber(surface.spec.inset) or 0
    contour.art, contour.circle = nil, nil
    return contour
end

function Contour.Native(art, circle, contour, rect)
    contour = contour or {}
    contour.geometry = nil
    contour.art = ReadArt(art, contour.art, rect)
    if not contour.art then return nil end
    contour.circle = nil
    if circle then
        local bounds = contour.scratch or {}
        contour.scratch = bounds
        local mask = ReadArt(circle, contour.mask, bounds)
        if not mask then return nil end
        mask.left, mask.bottom = (bounds.left - rect.left) / rect.width, (bounds.bottom - rect.bottom) / rect.height
        mask.width, mask.height = bounds.width / rect.width, bounds.height / rect.height
        contour.mask, contour.circle = mask, mask
    end
    return contour
end

local function Configure(mask, descriptor)
    if Safety.HasMethod(mask, "ClearTextureSlice") then mask:ClearTextureSlice() end
    if descriptor.atlas then mask:SetAtlas(descriptor.atlas)
    else mask:SetTexture(descriptor.asset, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
    mask:SetTexCoord(unpack(descriptor.uv))
end

local function Mask(record, index)
    record.masks = record.masks or {}
    local mask = record.masks[index]
    if not mask then
        mask = record.canvas:CreateMaskTexture(nil, "ARTWORK")
        record.masks[index] = mask
    end
    return mask
end

local function PaintMask(record, index, source, fullRect, descriptor)
    local mask = Mask(record, index)
    local scale = source.unitScale or 1
    local left, bottom = source.left, source.bottom
    local width, height = source.width, source.height
    if descriptor.geometry then
        if not Safety.HasMethod(mask, "ClearTextureSlice") or not Safety.HasMethod(mask, "SetTextureSliceMargins")
            or not Safety.HasMethod(mask, "SetTextureSliceMode") then return false end
        local inset = descriptor.inset * scale
        left, bottom = left + inset, bottom + inset
        width, height = width - inset * 2, height - inset * 2
        NS.Geometry.ConfigureShape(mask, descriptor.geometry.fill, descriptor.geometry)
        mask:SetTexCoord(0, 1, 0, 1)
    else
        Configure(mask, descriptor)
        if index == 2 then
            left, bottom = left + descriptor.left * width, bottom + descriptor.bottom * height
            width, height = width * descriptor.width, height * descriptor.height
        end
    end
    if width <= 0 or height <= 0 then return false end
    mask:ClearAllPoints()
    mask:SetPoint("BOTTOMLEFT", record.canvas, "BOTTOMLEFT", (left - fullRect.left) / scale, (bottom - fullRect.bottom) / scale)
    mask:SetSize(width / scale, height / scale)
    mask:Show()
    return true
end

local function Bind(record, count, ...)
    record.masked = record.masked or {}
    for index = 1, select("#", ...) do
        local texture = select(index, ...)
        if texture:GetObjectType() == "Texture" then
            local previous = record.masked[texture] or 0
            for maskIndex = previous + 1, count do texture:AddMaskTexture(record.masks[maskIndex]) end
            for maskIndex = count + 1, previous do texture:RemoveMaskTexture(record.masks[maskIndex]) end
            record.masked[texture] = count
        end
    end
end

function Contour.Apply(record, rect, fullRect)
    local source = rect.source or rect
    local contour = source.contour
    local count = 0
    if contour then
        if not Safety.HasMethod(record.canvas, "CreateMaskTexture") then return false end
        count = contour.circle and 2 or 1
        if not PaintMask(record, 1, source, fullRect, contour.geometry and contour or contour.art) then return false end
        if contour.circle and not PaintMask(record, 2, source, fullRect, contour.circle) then return false end
    end
    Bind(record, count, record.canvas:GetRegions())
    return true
end
