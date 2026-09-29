local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local CORNERS = {
    { "TOPRIGHT", "TOPLEFT", -4, 0 },
    { "TOPLEFT", "TOPRIGHT", 4, 0 },
    { "BOTTOMRIGHT", "BOTTOMLEFT", -4, 0 },
    { "BOTTOMLEFT", "BOTTOMRIGHT", 4, 0 },
}

local function CurrentSpec()
    local index = C_SpecializationInfo.GetSpecialization()
    if not S.Finite(index) or index < 1 then return nil end
    local id, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(index)
    if not S.Finite(id) then return nil end
    return index, id, S.PublicText(name), S.Finite(icon) and icon or nil
end

local function CurrentLoot()
    local id = GetLootSpecialization()
    if not S.Finite(id) or id < 0 then return nil end
    return id
end

local function SpecCount()
    local count = GetNumSpecializations(false, false)
    return S.Finite(count) and math.min(4, math.max(0, count)) or 0
end

local function OnEnter(button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText(S.Text("Quick specialization"))
    local _, _, name = CurrentSpec()
    if name then GameTooltip:AddLine(S.Text("Current spec: ") .. name, 1, 1, 1) end
    local loot = CurrentLoot()
    if loot then
        local lootName = S.Text("Current specialization")
        if loot > 0 then
            local _, name = GetSpecializationInfoByID(loot)
            lootName = S.PublicText(name) or lootName
        end
        GameTooltip:AddLine(S.Text("Loot: ") .. lootName, .8, .8, .8)
    end
    if NS.IsCombatLocked() then
        GameTooltip:AddLine(S.Text("Changing specialization is unavailable in combat."), 1, .55, .4, true)
    end
    GameTooltip:Show()
end

local function ChangeSpec(index)
    if NS.IsCombatLocked() or not S.Finite(index) then return end
    C_SpecializationInfo.SetSpecialization(index)
end

local function ChangeLoot(id)
    if NS.IsCombatLocked() or not S.Finite(id) then return end
    SetLootSpecialization(id)
end

local function IsCurrentSpec(index)
    local current = CurrentSpec()
    return current == index
end

local function IsCurrentLoot(id)
    return CurrentLoot() == id
end

local function OpenMenu(button)
    MenuUtil.CreateContextMenu(button, function(_, root)
        root:CreateTitle(S.Text("Quick specialization"))
        local locked = NS.IsCombatLocked()
        local count = SpecCount()
        if M.config.showSpec then
            local specs = root:CreateButton(S.Text("Specialization"))
            for index = 1, count do
                local id, name = C_SpecializationInfo.GetSpecializationInfo(index)
                name = S.PublicText(name)
                if S.Finite(id) and name then
                    local entry = specs:CreateRadio(name, IsCurrentSpec, ChangeSpec, index)
                    entry:SetEnabled(not locked)
                end
            end
        end
        if M.config.showLoot then
            local loot = root:CreateButton(S.Text("Loot specialization"))
            local auto = loot:CreateRadio(S.Text("Current specialization"), IsCurrentLoot, ChangeLoot, 0)
            auto:SetEnabled(not locked)
            for index = 1, count do
                local id, name = C_SpecializationInfo.GetSpecializationInfo(index)
                name = S.PublicText(name)
                if S.Finite(id) and name then
                    local entry = loot:CreateRadio(name, IsCurrentLoot, ChangeLoot, id)
                    entry:SetEnabled(not locked)
                end
            end
        end
    end)
end

local function Create(self)
    if self.button then return end
    local button = S.CreateFrame("Button", nil, UIParent)
    button:SetFrameStrata("HIGH")
    button:RegisterForClicks("AnyUp")
    local bg = S.CreateTexture(button, nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(.06, .08, .1, .88)
    local icon = S.CreateTexture(button, nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    button:SetScript("OnClick", OpenMenu)
    button:SetScript("OnEnter", OnEnter)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
    self.button, self.icon, self.bg = button, icon, bg
end

local function Update(self)
    local button = self.button
    if not button then return end
    if not self.config.showSpec and not self.config.showLoot then
        button:Hide()
        return
    end
    local c = self.config
    S.QoLColor(self.bg, S.QoLStyle(c).background, .88)
    local corner = CORNERS[c.corner] or CORNERS[1]
    button:SetSize(c.size, c.size)
    button:ClearAllPoints()
    button:SetPoint(corner[1], Minimap, corner[2], corner[3] + c.x, corner[4] + c.y)
    local _, _, _, icon = CurrentSpec()
    self.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    button:Show()
end

local function OnChanged(self)
    Update(self)
end

function M:Enable()
    Create(self)
    self.context:Event("PLAYER_ENTERING_WORLD", OnChanged)
    self.context:Event("PLAYER_SPECIALIZATION_CHANGED", OnChanged)
    self.context:Event("PLAYER_LOOT_SPEC_UPDATED", OnChanged)
    Update(self)
end

function M:Refresh()
    Update(self)
end

function M:Disable()
    if self.button then self.button:Hide() end
end

S.Install("mapQuickSwitch", M)
