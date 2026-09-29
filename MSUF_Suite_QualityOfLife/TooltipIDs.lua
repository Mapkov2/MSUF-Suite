local _, P = ...
local NS, S = P.NS, P.Suite

local M = {}

local function AddID(tooltip, label, id)
    if not S.Finite(id) or id < 1 then return end
    tooltip:AddDoubleLine(S.Text(label), tostring(math.floor(id)), .65, .81, .87, 1, .88, .58)
end

local function Eligible(tooltip, data)
    if not M.active or tooltip ~= GameTooltip or NS.Safety.IsForbidden(tooltip)
        or not S.Public(data) or type(data) ~= "table" then return false end
    local alt = IsAltKeyDown()
    return S.Public(alt) and alt == true
end

local function Item(tooltip, data)
    if Eligible(tooltip, data) then AddID(tooltip, "Item ID", data.id) end
end

local function Spell(tooltip, data)
    if Eligible(tooltip, data) then AddID(tooltip, "Spell ID", data.id) end
end

local function Unit(tooltip, data)
    if not Eligible(tooltip, data) then return end
    local guid = S.PublicText(data.guid)
    if not guid or not (guid:find("^Creature%-") or guid:find("^Vehicle%-")) then return end
    local npcText = select(6, strsplit("-", guid))
    local id = tonumber(npcText)
    AddID(tooltip, "Creature ID", id)
end

local function RefreshTooltip()
    local tooltip = _G.GameTooltip
    if tooltip and not NS.Safety.IsForbidden(tooltip) and tooltip:IsShown()
        and tooltip.RefreshDataNextUpdate then
        tooltip:RefreshDataNextUpdate()
    end
end

local function ModifierChanged(_, _, key)
    if not S.PublicText(key) or key ~= "LALT" and key ~= "RALT" then return end
    RefreshTooltip()
end

local function Install()
    if M.hooked or not TooltipDataProcessor or not Enum.TooltipDataType then return end
    local add, kinds = TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType
    if type(add) ~= "function" then return end
    add(kinds.Item, Item)
    add(kinds.Spell, Spell)
    add(kinds.Unit, Unit)
    M.hooked = true
    M.context:RemoveEvent("ADDON_LOADED")
end

local function OnAddon()
    Install()
end

function M:Enable()
    Install()
    if not self.hooked then self.context:Event("ADDON_LOADED", OnAddon) end
    self.context:Event("MODIFIER_STATE_CHANGED", ModifierChanged)
    RefreshTooltip()
end

function M:Refresh()
    RefreshTooltip()
end

function M:Disable()
    RefreshTooltip()
end

S.Install("tooltipIDs", M)
