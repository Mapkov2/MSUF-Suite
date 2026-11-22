local _, P = ...
local NS, S = P.NS, P.Suite

local M = {}
local Line = S.TooltipLines.Line
local hasSharedBank = not NS.Client.isForever

local function Owned(id, bank, reagent, account)
    local count = C_Item.GetItemCount(id, bank, false, reagent, account)
    return S.Finite(count) and count >= 0 and math.floor(count) or nil
end

local function Part(tooltip, label, count)
    if count > 0 then Line(tooltip, label, tostring(count)) end
end

local function Paint(tooltip, data)
    local id = data.id
    if not S.Finite(id) or id < 1 then return end
    local count = Owned(id, true, hasSharedBank, hasSharedBank)
    if not count or count <= 0 then return end
    Line(tooltip, "Owned", tostring(count))
    if not M.config.byLocation then return end
    -- The API returns cumulative totals. Subtract only fully public reads;
    -- an unreadable component leaves the accurate total above intact.
    local bags = Owned(id, false, false, false)
    if not bags or bags > count then return end
    if not hasSharedBank then
        Part(tooltip, "Bags", bags)
        Part(tooltip, "Bank", count - bags)
        return
    end
    local withBank = Owned(id, true, false, false)
    local withReagents = Owned(id, true, true, false)
    if not withBank or not withReagents
        or bags > withBank or withBank > withReagents or withReagents > count then return end
    Part(tooltip, "Bags", bags)
    Part(tooltip, "Bank", withBank - bags)
    Part(tooltip, "Reagent bank", withReagents - withBank)
    Part(tooltip, "Warband bank", count - withReagents)
end

-- Settings apply from the next tooltip build (TooltipLines.lua).
function M:Enable() S.TooltipLines.Add(self, "Item", Paint) end
function M:Refresh() end
function M:Disable() end

S.Install("itemCounts", M)
