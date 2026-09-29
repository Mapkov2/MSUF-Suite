local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local TYPE_CHOICES = {
    { "hideItems", "Item" },
    { "hideSpells", "Spell" },
    { "hideUnits", "Unit" },
}

local function MatchesType(tooltip, tooltipType)
    local matches = tooltip:IsTooltipType(tooltipType)
    return S.Public(matches) and matches == true
end

local function ShouldHide(tooltip)
    if M.config.inCombat and NS.IsCombatLocked() then return true end
    if M.config.inInstances then
        local inInstance = IsInInstance()
        if S.Public(inInstance) and inInstance == true then return true end
    end
    if M.config.hideItems and MatchesType(tooltip, Enum.TooltipDataType.Item)
        or M.config.hideSpells and MatchesType(tooltip, Enum.TooltipDataType.Spell)
        or M.config.hideUnits and MatchesType(tooltip, Enum.TooltipDataType.Unit) then return true end
    return false
end

local function MaybeHide()
    local tooltip = _G.GameTooltip
    if not M.active or not tooltip or NS.Safety.IsForbidden(tooltip)
        or not tooltip:IsShown() or not ShouldHide(tooltip) then return end
    if NS.IsCombatLocked() and tooltip:IsProtected() then return end
    tooltip:Hide()
end

local function MaybeHideData(tooltip)
    if tooltip == _G.GameTooltip then MaybeHide() end
end

local function Install(self)
    local tooltip = _G.GameTooltip
    if not tooltip or NS.Safety.IsForbidden(tooltip) then return false end
    if not self.hooked then
        tooltip:HookScript("OnShow", MaybeHide)
        self.hooked = true
    end
    self.context:RemoveEvent("ADDON_LOADED")
    return true
end

local function Sync(self)
    if not Install(self) then self.context:Event("ADDON_LOADED", function(module) Install(module) end) end
    if self.config.inCombat then
        self.context:Event("PLAYER_REGEN_DISABLED", MaybeHide, true)
    else
        self.context:RemoveEvent("PLAYER_REGEN_DISABLED")
    end
    if self.config.inInstances then
        self.context:Event("PLAYER_ENTERING_WORLD", MaybeHide, true)
        self.context:Event("ZONE_CHANGED_NEW_AREA", MaybeHide, true)
    else
        self.context:RemoveEvent("PLAYER_ENTERING_WORLD")
        self.context:RemoveEvent("ZONE_CHANGED_NEW_AREA")
    end
    self.typeHooks = self.typeHooks or {}
    for i = 1, #TYPE_CHOICES do
        local choice = TYPE_CHOICES[i]
        if self.config[choice[1]] then
            local kind = Enum.TooltipDataType[choice[2]]
            if not self.typeHooks[kind] then
                TooltipDataProcessor.AddTooltipPostCall(kind, MaybeHideData)
                self.typeHooks[kind] = true
            end
        end
    end
    MaybeHide()
end

function M:Enable() Sync(self) end
function M:Refresh() Sync(self) end
function M:Disable() end

S.Install("tooltipVisibility", M)
