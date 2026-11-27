local _, P = ...
local S = P.Suite
local Slots = {}
P.BagSlotAppearance = Slots
local CORNERS = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
    { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }

local function Edges(record, frame, texture)
    if record.slotEdges then return record.slotEdges end
    local edges = {}
    for index, anchors in ipairs(CORNERS) do
        local edge = texture(frame, "ARTWORK", 3)
        edge:SetPoint(anchors[1])
        edge:SetPoint(anchors[2])
        edges[index] = edge
    end
    record.slotEdges = edges
    return edges
end

-- Every slot in a live bag uses one palette. The menu can use a different
-- profile, so compare both actual color settings before reusing it.
local background, accent, fillR, fillG, fillB, borderR, borderG, borderB
local function Palette(c)
    if background ~= c.backgroundColor or accent ~= c.accentColor or not fillR then
        background, accent = c.backgroundColor, c.accentColor
        local r, g, b = S.RGB(background)
        local ar, ag, ab = S.RGB(accent)
        fillR, fillG, fillB = r + (1 - r) * .05, g + (1 - g) * .05, b + (1 - b) * .05
        borderR, borderG, borderB = ar * .18 + r * .82, ag * .18 + g * .82, ab * .18 + b * .82
    end
end

-- One flat stroke, shared by native bag slots and the menu sample. Native
-- quest, cooldown, lock and new-item feedback stays above these textures.
function Slots.Paint(record, frame, c, empty, quality, texture)
    local width = (empty and c.emptySlotBorderWidth or c.slotBorderWidth) or 1
    Palette(c)
    local ar, ag, ab = borderR, borderG, borderB
    local public = true
    if not empty and S.Finite(quality) and quality > Enum.ItemQuality.Common then
        -- Match the palette Blizzard uses to tint its own bag buttons.
        local color = ColorManager.GetColorDataForBagItemQuality(quality)
        if S.Public(color) and color and S.Finite(color.r) and S.Finite(color.g) and S.Finite(color.b) then
            ar, ag, ab = color.r, color.g, color.b
        else
            ar, ag, ab = C_Item.GetItemQualityColor(quality)
            public = S.Public(ar) and S.Public(ag) and S.Public(ab)
        end
    end
    -- Blizzard may reassign the native button without changing its decoration.
    -- Preview buttons also serve the bank sample, which can change their edges.
    local native = record.slotNativeActive
    local priorWidth = native and record.edgeWidth
    local recolor = not priorWidth or not public or record.edgeR ~= ar or record.edgeG ~= ag or record.edgeB ~= ab
    if recolor or priorWidth ~= width then
        local edges = Edges(record, frame, texture)
        for i = 1, 4 do
            if recolor then edges[i]:SetColorTexture(ar, ag, ab, 1) end
            if priorWidth ~= width then
                if i <= 2 then edges[i]:SetHeight(math.max(1, width)) else edges[i]:SetWidth(math.max(1, width)) end
                edges[i]:SetShown(width > 0)
            end
        end
        if native then
            record.edgeWidth = width
            if public then record.edgeR, record.edgeG, record.edgeB = ar, ag, ab else record.edgeR = nil end
        end
    end
    -- The empty plate covers the native empty atlas without a second inset.
    if not native or record.innerColor ~= c.backgroundColor then
        record.slotInner:SetColorTexture(fillR, fillG, fillB, 1)
        record.slotInner:Hide()
        if native then record.innerColor = c.backgroundColor end
    end
    if empty and (not native or record.outerColor ~= c.backgroundColor) then
        record.slotOuter:SetColorTexture(fillR, fillG, fillB, 1)
        if native then record.outerColor = c.backgroundColor end
    end
end

function Slots.Native(module, button, record, empty, activating)
    if activating then
        for _, region in ipairs({ button.NormalTexture, button.IconBorder }) do
            P.BagLayout.Alpha(module.context, region, 0)
        end
    end
    local cache = P.SlotCache
    if activating or not record.strokeKey or record.strokeStyle ~= module.slotStyle then
        local bag, slot = button:GetBagID(), button:GetID()
        record.strokeKey = S.Finite(bag) and S.Finite(slot) and bag * cache.KEY + slot or nil
    end
    local info = cache.info[record.strokeKey]
    local quality = info and info.quality
    if not S.Public(quality) then quality = nil end
    record.strokeVersion = cache.version[record.strokeKey]
    if not activating and record.strokeEmpty == empty and record.strokeQuality == quality then
        if record.strokeStyle == module.slotStyle then return end
        -- A style change without a palette change reuses the decoration. A
        -- ColorManager update (Bags.lua SlotColorsChanged) bumps the palette
        -- revision too, so colored items consult Blizzard's color again.
        if record.paintRevision == module.slotPaintRevision and (empty or not S.Finite(quality) or quality <= Enum.ItemQuality.Common) then
            record.strokeStyle = module.slotStyle
            return
        end
    end
    Slots.Paint(record, button, module.config, empty, quality, module.WindowTexture)
    record.paintRevision = module.slotPaintRevision
    record.strokeStyle, record.strokeEmpty, record.strokeQuality = module.slotStyle, empty, quality
end

function S.BagsPaintPreviewSlot(slot, c, item)
    if not slot.slotOuter then
        slot.slotOuter, slot.slotInner = slot.border, slot:CreateTexture(nil, "BACKGROUND")
    end
    local function Texture(frame, layer, sublevel) return frame:CreateTexture(nil, layer, nil, sublevel) end
    Slots.Paint(slot, slot, c, not item.itemID, item.quality, Texture)
    slot.icon:SetAllPoints(slot)
    slot.icon:SetShown(item.itemID ~= nil)
    if not item.itemID then slot.slotOuter:Show() end
end
