local _, P = ...
local NS, S = P.NS, P.Suite

local M = {}

local function Paint(tooltip, data)
    if not M.active or tooltip ~= GameTooltip or NS.Safety.IsForbidden(tooltip)
        or not S.Public(data) or type(data) ~= "table" then return end
    local id = data.id
    if not S.Finite(id) or id < 1 then return end
    -- GetItemCount's final argument includes the Warband bank on Retail.
    -- All returned values are checked before Lua compares or formats them.
    local count = C_Item.GetItemCount(id, true, false, true, true)
    if not S.Finite(count) or count <= 0 then return end
    tooltip:AddDoubleLine(S.Text("Owned"), tostring(math.floor(count)), .65, .81, .87, 1, .88, .58)
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
