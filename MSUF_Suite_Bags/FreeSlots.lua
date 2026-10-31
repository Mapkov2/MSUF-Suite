local _, P = ...
local S = P.Suite
-- The free slot count in the footer of the bag and bank views, split into the
-- bags and the reagent bag. The bags' count is taken from the records the index
-- reads anyway (a slot with no item has no item ID: index.free, InventoryIndex.lua
-- and BankIndex.lua), so it costs no client call.
local FreeSlots = {}
P.FreeSlots = FreeSlots
local REAGENT_BAG = Enum.BagIndex.ReagentBag

-- The reagent bag has its own window and is not in the combined bag's index:
-- its slots come from the shared slot cache (SlotCache.lua), which reads a
-- bag again only after the client said it changed.
-- Returns nil without a reagent bag.
function FreeSlots.Reagent()
    local size = P.SlotCache.Sync(REAGENT_BAG)
    if size == 0 then return nil end
    local free = 0
    for slot = 1, size do
        if not P.SlotCache.Get(REAGENT_BAG, slot) then free = free + 1 end
    end
    return free
end

-- Copies the counts into out: regular, and reagent when withReagent and a
-- reagent bag exists.
function FreeSlots.Read(out, index, withReagent)
    out.regular = index.free
    out.reagent = withReagent and FreeSlots.Reagent() or nil
end

-- Shows the counts; the text is built only when a count changed.
function FreeSlots.Paint(text, counts)
    local regular, reagent = counts.regular, counts.reagent
    if text.freeRegular ~= regular or text.freeReagent ~= reagent then
        text.freeRegular, text.freeReagent = regular, reagent
        if reagent then
            text:SetText(string.format(S.Text("%d free + %d reagent"), regular, reagent))
        else
            text:SetText(string.format(S.Text("%d free"), regular))
        end
    end
    text:Show()
end
