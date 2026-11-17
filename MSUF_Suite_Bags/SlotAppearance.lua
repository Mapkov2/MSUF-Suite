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

-- One flat stroke, shared by native bag slots and the menu sample. Native
-- quest, cooldown, lock and new-item feedback stays above these textures.
function Slots.Paint(record, frame, c, empty, quality, texture)
    local width = (empty and c.emptySlotBorderWidth or c.slotBorderWidth) or 1
    local r, g, b = S.RGB(c.backgroundColor)
    local ar, ag, ab = S.RGB(c.accentColor)
    ar, ag, ab = ar * .18 + r * .82, ag * .18 + g * .82, ab * .18 + b * .82
    if not empty and S.Finite(quality) and quality > Enum.ItemQuality.Common then
        ar, ag, ab = C_Item.GetItemQualityColor(quality)
    end
    local edges = Edges(record, frame, texture)
    record.slotInner:SetColorTexture(r + (1 - r) * .05, g + (1 - g) * .05, b + (1 - b) * .05, 1)
    for i = 1, 4 do
        edges[i]:SetColorTexture(ar, ag, ab, 1)
        if i <= 2 then edges[i]:SetHeight(math.max(1, width)) else edges[i]:SetWidth(math.max(1, width)) end
        edges[i]:SetShown(width > 0)
    end
    -- The empty plate covers the native empty atlas without a second inset.
    if empty then record.slotOuter:SetColorTexture(r + (1 - r) * .05, g + (1 - g) * .05, b + (1 - b) * .05, 1) end
    record.slotInner:Hide()
end

function Slots.Native(module, button, record, empty, activating)
    if activating then
        for _, region in ipairs({ button.NormalTexture, button.IconBorder }) do
            P.BagLayout.Alpha(module.context, region, 0)
        end
    end
    local cache = P.SlotCache
    if activating or record.strokeStyle ~= module.slotStyle then
        local bag, slot = button:GetBagID(), button:GetID()
        record.strokeKey = S.Finite(bag) and S.Finite(slot) and bag * cache.KEY + slot or nil
    end
    local info = cache.info[record.strokeKey]
    local quality = info and info.quality
    if not S.Public(quality) then quality = nil end
    record.strokeVersion = cache.version[record.strokeKey]
    if record.strokeStyle == module.slotStyle and record.strokeEmpty == empty and record.strokeQuality == quality then return end
    Slots.Paint(record, button, module.config, empty, quality, module.WindowTexture)
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
