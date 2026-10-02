local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }

local M = {}

local function LootSpecText()
    local selected = GetLootSpecialization()
    if not S.Finite(selected) or selected < 0 then return nil end
    if selected == 0 then
        local index = C_SpecializationInfo.GetSpecialization()
        if not S.Finite(index) or index < 1 then return S.Text("Loot specialization: Current") end
        local _, name = C_SpecializationInfo.GetSpecializationInfo(index)
        name = S.PublicText(name)
        if not name then return S.Text("Loot specialization: Current") end
        return string.format(S.Text("Loot specialization: Current (%s)"), name)
    end
    local _, name = GetSpecializationInfoByID(selected)
    name = S.PublicText(name)
    return name and string.format(S.Text("Loot specialization: %s"), name) or nil
end

function M:Draw()
    local frame = _G.WeeklyRewardsFrame
    if not self.active or not self.label or not frame or not frame:IsShown() then
        if self.label then self.label:Hide() end
        return
    end
    local value = LootSpecText()
    if not value then self.label:Hide() return end
    self.label:SetText(value)
    self.label:Show()
end

local function Attach(self)
    if NS.IsCombatLocked() then
        self.context:Event("PLAYER_REGEN_ENABLED", function(module) Attach(module) end)
        return
    end
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    local frame = _G.WeeklyRewardsFrame
    if not frame or NS.Safety.IsForbidden(frame) then return end
    if not self.label then
        local label = S.CreateFontString(frame.BorderContainer or frame, nil, "OVERLAY")
        label:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -47, 35)
        label:SetWidth(380)
        label:SetJustifyH("RIGHT")
        S.SetFont(label, nil, 13, "OUTLINE")
        label:SetTextColor(1, .82, .42)
        self.label = label
    end
    if not self.hooked then
        frame:HookScript("OnShow", function() if M.active then M:Draw() end end)
        self.hooked = true
    end
    self.context:RemoveEvent("ADDON_LOADED")
    self:Draw()
end

local function OnAddon(self, _, addon)
    if addon == "Blizzard_WeeklyRewards" then Attach(self) end
end

local function SpecChanged(self)
    local frame = _G.WeeklyRewardsFrame
    if frame and frame:IsShown() then self:Draw() end
end

function M:Enable()
    self.context:Event("PLAYER_LOOT_SPEC_UPDATED", SpecChanged)
    self.context:Event("PLAYER_SPECIALIZATION_CHANGED", SpecChanged)
    Attach(self)
    if not self.label then self.context:Event("ADDON_LOADED", OnAddon, IN_COMBAT) end
end

function M:Refresh()
    self:Draw()
end

function M:Disable()
    if self.label then self.label:Hide() end
end

S.Install("vaultSpec", M)
