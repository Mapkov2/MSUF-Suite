local _, P = ...
local NS, S = P.NS, P.Suite

local M = {}

local function Owned(id, bank, reagent, account)
    local count = C_Item.GetItemCount(id, bank, false, reagent, account)
    return S.Finite(count) and count >= 0 and math.floor(count) or nil
end

local function Paint(tooltip, data)
    if not M.active or tooltip ~= GameTooltip or NS.Safety.IsForbidden(tooltip)
        or not S.Public(data) or type(data) ~= "table" then return end
    local id = data.id
    if not S.Finite(id) or id < 1 then return end
    -- GetItemCount's final argument includes the Warband bank on Retail.
    -- All returned values are checked before Lua compares or formats them.
    local count = Owned(id, true, true, true)
    if not count or count <= 0 then return end
    tooltip:AddDoubleLine(S.Text("Owned"), tostring(count), .65, .81, .87, 1, .88, .58)
    if not M.config or not M.config.byLocation then return end

    -- The API returns cumulative totals. Subtract only fully public reads;
    -- an unreadable component leaves the accurate total above intact.
    local bags = Owned(id, false, false, false)
    local withBank = Owned(id, true, false, false)
    local withReagents = Owned(id, true, true, false)
    if not bags or not withBank or not withReagents
        or bags > withBank or withBank > withReagents or withReagents > count then return end
    local locations = {
        { S.Text("Bags"), bags },
        { S.Text("Bank"), withBank - bags },
        { S.Text("Reagent bank"), withReagents - withBank },
        { S.Text("Warband bank"), count - withReagents },
    }
    for i = 1, #locations do
        local part = locations[i]
        if part[2] > 0 then
            tooltip:AddDoubleLine(part[1], tostring(part[2]), .65, .81, .87, 1, .88, .58)
        end
    end
end

local function Install()
    if M.hooked or not TooltipDataProcessor or not Enum.TooltipDataType
        or type(TooltipDataProcessor.AddTooltipPostCall) ~= "function" then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Paint)
    M.hooked = true
    M.context:RemoveEvent("ADDON_LOADED")
end

local function RefreshTooltip()
    local tooltip = _G.GameTooltip
    if tooltip and not NS.Safety.IsForbidden(tooltip) and tooltip:IsShown() then
        tooltip:RefreshDataNextUpdate()
    end
end

function M:Enable()
    Install()
    if not self.hooked then self.context:Event("ADDON_LOADED", Install) end
    RefreshTooltip()
end

function M:Refresh() RefreshTooltip() end
function M:Disable() RefreshTooltip() end

S.Install("itemCounts", M)
