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

-- The root's native artwork hosts are the same for every node of one
-- discovery walk: they are read once per walk and compared by identity per
-- node. Nothing is kept across walks, so a later walk sees a replaced host.
function Contour.Anchors(root, anchors)
    local border = Field(root, "BorderFrame")
    anchors.portrait, anchors.borderPortrait = Field(root, "PortraitContainer"), Field(border, "PortraitContainer")
    anchors.tutorial = Field(border, "Tutorial")
    return anchors
end

function Contour.Artwork(anchors, frame)
    if frame == anchors.portrait or frame == anchors.borderPortrait then
        return Field(frame, "portrait"), Field(frame, "CircleMask"), true
    end
    if frame == anchors.tutorial then return Field(frame, "I"), nil, true end
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

local function ReadArt(region, descriptor, rect, uiScale)
    if not region or Safety.Read(region, "IsShown") ~= true then return nil end
    local asset = Safety.Read(region, "GetTexture")
    local atlas = Safety.Read(region, "GetAtlas")
    if type(asset) ~= "string" and type(asset) ~= "number" and type(atlas) ~= "string" then return nil end
    if not NS.WindowFocusGeometry.Read(region, rect, uiScale) then return nil end
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

function Contour.DescribeRoot(frame, contour)
    local skin = NS.SuiteCore().Skin
    local geometry, inset
    if skin and skin.GetOwnedWindowContour then geometry, inset = skin.GetOwnedWindowContour(frame) end
    if not geometry then return Contour.Describe(frame, contour) end
    contour = contour or {}
    contour.geometry, contour.inset = geometry, inset or 0
    contour.art, contour.circle = nil, nil
    return contour
end

function Contour.SetCutout(rect)
    local contour = rect.contour
    local geometry = contour and contour.geometry
    rect.roundedCut = nil
    if not geometry or not geometry.outside then return end
    local scale = rect.unitScale or 1
    local inset = contour.inset * scale
    local width, height = rect.width - inset * 2, rect.height - inset * 2
    if width <= 0 or height <= 0 then return end
    local cut = rect.cutScratch or {}
    rect.cutScratch, rect.roundedCut = cut, cut
    cut.left, cut.bottom = rect.left + inset, rect.bottom + inset
    cut.width, cut.height, cut.unitScale = width, height, scale
    cut.cornerX = math.min(geometry.margins[1] * scale, width / 2)
    cut.cornerY = math.min(geometry.margins[2] * scale, height / 2)
    cut.geometry = geometry
end

function Contour.Native(art, circle, contour, rect, uiScale)
    contour = contour or {}
    contour.geometry = nil
    contour.art = ReadArt(art, contour.art, rect, uiScale)
    if not contour.art then return nil end
    contour.circle = nil
    if circle then
        local bounds = contour.scratch or {}
        contour.scratch = bounds
        local mask = ReadArt(circle, contour.mask, bounds, uiScale)
        if not mask then return nil end
        mask.left, mask.bottom = (bounds.left - rect.left) / rect.width, (bounds.bottom - rect.bottom) / rect.height
        mask.width, mask.height = bounds.width / rect.width, bounds.height / rect.height
        contour.mask, contour.circle = mask, mask
    end
    return contour
end

-- Masks belong only to this canvas. Native contour descriptors and the Suite's
-- shape tables may be reused, so compare the actual UV and slice values.
local paints = setmetatable({}, { __mode = "k" })

local function SameUV(cache, uv)
    if cache.uvCount ~= #uv then return false end
    for index = 1, #uv do
        if cache[index] ~= uv[index] then return false end
    end
    return true
end

local function NativeMaterial(mask, cache, descriptor, refresh)
    local atlas, asset, uv = descriptor.atlas, descriptor.asset, descriptor.uv
    if not refresh and cache.kind == "art" and cache.asset == asset and cache.atlas == atlas and SameUV(cache, uv) then return end
    local count = #uv
    cache.kind = nil
    for index = 1, count do cache[index] = uv[index] end
    if Safety.HasMethod(mask, "ClearTextureSlice") then mask:ClearTextureSlice() end
    if atlas then mask:SetAtlas(atlas)
    else mask:SetTexture(asset, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
    mask:SetTexCoord(unpack(uv))
    cache.kind, cache.asset, cache.atlas, cache.uvCount = "art", asset, atlas, count
end

local function ShapeMaterial(mask, cache, geometry, asset, refresh)
    local margins = geometry.slice and geometry.margins
    local left, top, right, bottom
    if margins then left, top, right, bottom = margins[1], margins[2], margins[3], margins[4] end
    local sliced = margins ~= nil and margins ~= false
    if not refresh and cache.kind == "shape" and cache.asset == asset and cache.sliced == sliced
        and cache.left == left and cache.top == top and cache.right == right and cache.bottom == bottom then return end
    cache.kind = nil
    NS.Geometry.ConfigureShape(mask, asset, geometry, true)
    mask:SetTexCoord(0, 1, 0, 1)
    cache.kind, cache.asset, cache.sliced = "shape", asset, sliced
    cache.left, cache.top, cache.right, cache.bottom = left, top, right, bottom
end

-- Slice support of our own mask is fixed per client build: checked when the
-- mask is first painted and again on an explicit refresh.
local function Sliceable(mask)
    return Safety.HasMethod(mask, "ClearTextureSlice") and Safety.HasMethod(mask, "SetTextureSliceMargins")
        and Safety.HasMethod(mask, "SetTextureSliceMode")
end

local function Mask(record, index, refresh)
    record.masks = record.masks or {}
    local mask = record.masks[index]
    if not mask then
        mask = record.canvas:CreateMaskTexture(nil, "ARTWORK")
        record.masks[index] = mask
    end
    local cache = paints[mask]
    if not cache then cache = {} paints[mask] = cache end
    if refresh or cache.sliceable == nil then cache.sliceable = Sliceable(mask) end
    return mask, cache
end

local function PositionMask(canvas, fullRect, mask, cache, left, bottom, width, height, scale, refresh, serial)
    local x, y = (left - fullRect.left) / scale, (bottom - fullRect.bottom) / scale
    width, height = width / scale, height / scale
    if refresh or cache.x ~= x or cache.y ~= y then
        mask:ClearAllPoints()
        mask:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", x, y)
    end
    if refresh or cache.width ~= width or cache.height ~= height then mask:SetSize(width, height) end
    if refresh or not cache.shown or (mask.IsShown and Safety.Read(mask, "IsShown") == false) then mask:Show() end
    if cache.serial == serial then
        cache.x, cache.y, cache.width, cache.height, cache.shown = x, y, width, height, true
    else
        -- A synchronous native callback painted this mask during a setter.
        cache.x, cache.width, cache.kind, cache.shown = nil, nil, nil, nil
    end
end

local function PaintMask(record, index, source, fullRect, descriptor, refresh)
    local mask, cache = Mask(record, index, refresh)
    local serial = (cache.serial or 0) + 1
    cache.serial = serial
    local scale = source.unitScale or 1
    local left, bottom = source.left, source.bottom
    local width, height = source.width, source.height
    local geometry = descriptor.geometry
    if geometry then
        if not cache.sliceable then return false end
        local inset = descriptor.inset * scale
        left, bottom = left + inset, bottom + inset
        width, height = width - inset * 2, height - inset * 2
    elseif index == 2 then
        left, bottom = left + descriptor.left * width, bottom + descriptor.bottom * height
        width, height = width * descriptor.width, height * descriptor.height
    end
    if width <= 0 or height <= 0 then return false end
    if geometry then ShapeMaterial(mask, cache, geometry, geometry.fill, refresh)
    else NativeMaterial(mask, cache, descriptor, refresh) end
    PositionMask(record.canvas, fullRect, mask, cache, left, bottom, width, height, scale, refresh, serial)
    return true
end

local function PaintCutout(record, cut, fullRect, refresh)
    local mask, cache = Mask(record, 1, refresh)
    if not cache.sliceable then return false end
    local serial = (cache.serial or 0) + 1
    cache.serial = serial
    local geometry = cut.geometry
    ShapeMaterial(mask, cache, geometry, geometry.outside, refresh)
    PositionMask(record.canvas, fullRect, mask, cache, cut.left, cut.bottom, cut.width, cut.height, cut.unitScale, refresh, serial)
    return true
end

local function RepairBindings(record, texture, count)
    local total = Safety.Read(texture, "GetNumMaskTextures")
    if type(total) ~= "number" then return false end
    local first, second = false, false
    for index = 1, total do
        local mask = Safety.Read(texture, "GetMaskTexture", index)
        if not mask then return false end
        if mask == record.masks[1] then first = true end
        if mask == record.masks[2] then second = true end
    end
    for index = 1, #record.masks do
        local bound = index == 1 and first or index == 2 and second
        if index <= count and not bound then texture:AddMaskTexture(record.masks[index])
        elseif index > count and bound then texture:RemoveMaskTexture(record.masks[index]) end
    end
    return true
end

local function Bind(record, count, refresh, ...)
    record.masked = record.masked or {}
    for index = 1, select("#", ...) do
        local texture = select(index, ...)
        if Safety.Public(texture) then
            local previous = record.masked[texture] or 0
            if (previous ~= count or refresh) and Safety.Read(texture, "GetObjectType") == "Texture" then
                if not refresh or not RepairBindings(record, texture, count) then
                    for maskIndex = previous + 1, count do texture:AddMaskTexture(record.masks[maskIndex]) end
                    for maskIndex = count + 1, previous do texture:RemoveMaskTexture(record.masks[maskIndex]) end
                end
                record.masked[texture] = count > 0 and count or nil
            end
        end
    end
end

function Contour.Apply(record, rect, fullRect, refresh)
    local source = rect.source or rect
    local contour = source.contour
    local count = 0
    local cutout = rect.cutoutMask
    if contour or cutout then
        if not Safety.HasMethod(record.canvas, "CreateMaskTexture") then return false end
    end
    if cutout then
        -- Geometry only selects an inverse mask where the source is opaque.
        -- Binding both would let WoW's union reveal the foreground interior.
        count = 1
        if not PaintCutout(record, cutout, fullRect, refresh) then return false end
    elseif contour then
        count = contour.circle and 2 or 1
        if not PaintMask(record, 1, source, fullRect, contour.geometry and contour or contour.art, refresh) then return false end
        if contour.circle and not PaintMask(record, 2, source, fullRect, contour.circle, refresh) then return false end
    end
    -- Host material can replace a region without changing the region count.
    -- Recheck identities while a mask is in use or still needs removal.
    if count > 0 or record.masked and next(record.masked) or refresh and record.masks then
        Bind(record, count, refresh, record.canvas:GetRegions())
    end
    return true
end
