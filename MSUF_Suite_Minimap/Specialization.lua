local _, P = ...
local NS, S = P.NS, P.Suite
local MM = P.Minimap
local M = MM.M
local Q = {}
MM.specialization = Q

local function Wanted()
    local c = M.config
    return M.active and NS.CanShowMinimapSpecialization() and c.specButton
        and (c.specShowSpec or c.specShowLoot)
end

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
    MM.ScaleTooltip(button)
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
    if not Wanted() or not M.config.specShowSpec or NS.IsCombatLocked() or not S.Finite(index) then return end
    C_SpecializationInfo.SetSpecialization(index)
end

local function ChangeLoot(id)
    if not Wanted() or not M.config.specShowLoot or NS.IsCombatLocked() or not S.Finite(id) then return end
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
    if not Wanted() then return end
    MenuUtil.CreateContextMenu(button, function(_, root)
        root:CreateTitle(S.Text("Quick specialization"))
        local locked = NS.IsCombatLocked()
        local count = SpecCount()
        if M.config.specShowSpec then
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
        if M.config.specShowLoot then
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
    -- The host owns visibility, scale and Edit Mode. This is not an addon
    -- button on Blizzard's map, so neither drawer nor MBB collects it.
    local button = S.CreateFrame("Button", nil, MM.host)
    button:SetFrameLevel(MM.mapLevel + 5)
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
    button:SetScript("OnHide", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    MM.HookHover(button)
    button:Hide()
    self.button, self.icon, self.bg = button, icon, bg
end

local function UpdateIcon()
    if not Q.icon or not Wanted() then return end
    local _, _, _, icon = CurrentSpec()
    Q.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
end

local function OnChanged(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then return end
    UpdateIcon()
end

function MM.ReleaseSpecialization()
    MM.Unlisten("PLAYER_ENTERING_WORLD", "specialization")
    MM.Unlisten("PLAYER_SPECIALIZATION_CHANGED", "specialization")
    MM.Unlisten("PLAYER_LOOT_SPEC_UPDATED", "specialization")
    if Q.button then Q.button:Hide() end
    MM.SetExtent("specialization", 0, 0, 0, 0)
end

function MM.ApplySpecialization()
    if not Wanted() then
        MM.ReleaseSpecialization()
        return
    end
    Create(Q)
    local c, button = M.config, Q.button
    local corner = NS.MinimapSpecCorners[c.specCorner] or NS.MinimapSpecCorners[1]
    local x, y, size = corner[3] + c.specX, corner[4] + c.specY, c.specSize
    button:SetSize(size, size)
    button:ClearAllPoints()
    button:SetPoint(corner[1], MM.host, corner[2], x, y)
    local r, g, b = MM.BorderRGB()
    Q.bg:SetColorTexture(r, g, b, .88)
    local width, height = MM.Dimensions()
    local left = corner[2]:find("LEFT", 1, true) and x - size or width + x
    local bottom = corner[2]:find("TOP", 1, true) and height + y - size or y
    MM.SetExtent("specialization", math.max(0, -left), math.max(0, left + size - width),
        math.max(0, bottom + size - height), math.max(0, -bottom))
    MM.Listen("PLAYER_ENTERING_WORLD", "specialization", OnChanged)
    MM.Listen("PLAYER_SPECIALIZATION_CHANGED", "specialization", OnChanged)
    MM.Listen("PLAYER_LOOT_SPEC_UPDATED", "specialization", OnChanged)
    UpdateIcon()
    button:Show()
end
