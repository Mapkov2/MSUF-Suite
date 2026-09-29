local _, P = ...
local NS, S = P.NS, P.Suite

local M = {}

local function SafeShown(frame)
    return frame and not NS.Safety.IsForbidden(frame) and frame:IsShown()
end

local function CloseCharacter(self)
    if not self.openedCharacter then return end
    local character = _G.CharacterFrame
    if not SafeShown(character) then
        self.openedCharacter = nil
        self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if NS.IsCombatLocked() and character:IsProtected() then
        self.context:Event("PLAYER_REGEN_ENABLED", CloseCharacter)
        return
    end
    self.openedCharacter = nil
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    pcall(HideUIPanel, character)
end

local function OpenCharacter(self)
    if not self.active or self.openedCharacter or type(ToggleCharacter) ~= "function" then return end
    local upgrade, character = _G.ItemUpgradeFrame, _G.CharacterFrame
    if not SafeShown(upgrade) or not character or NS.Safety.IsForbidden(character)
        or character:IsShown() then return end
    if NS.IsCombatLocked() then
        self.context:Event("PLAYER_REGEN_ENABLED", OpenCharacter)
        return
    end
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    -- CharacterFrame is a pushable native panel. WoW decides its placement
    -- beside the non-pushable ItemUpgradeFrame (upstream/live UIPanelWindows).
    if not pcall(ToggleCharacter, "PaperDollFrame", true) then return end
    if SafeShown(upgrade) and SafeShown(character) then self.openedCharacter = true end
end

local function UpgradeShown()
    if M.active then OpenCharacter(M) end
end

local function UpgradeHidden()
    if not M.openedCharacter then M.context:RemoveEvent("PLAYER_REGEN_ENABLED") end
    CloseCharacter(M)
end

local function CharacterHidden()
    M.openedCharacter = nil
    M.context:RemoveEvent("PLAYER_REGEN_ENABLED")
end

local function InstallHooks(self)
    if self.hooked then
        if SafeShown(_G.ItemUpgradeFrame) then OpenCharacter(self) end
        return
    end
    local upgrade, character = _G.ItemUpgradeFrame, _G.CharacterFrame
    if not upgrade or NS.Safety.IsForbidden(upgrade)
        or not character or NS.Safety.IsForbidden(character) then return end
    upgrade:HookScript("OnShow", UpgradeShown)
    upgrade:HookScript("OnHide", UpgradeHidden)
    character:HookScript("OnHide", CharacterHidden)
    self.hooked = true
    self.context:RemoveEvent("ADDON_LOADED")
    if upgrade:IsShown() then OpenCharacter(self) end
end

local function AddonLoaded(self, _, addon)
    if addon == "Blizzard_ItemUpgradeUI" then InstallHooks(self) end
end

function M:Enable()
    InstallHooks(self)
    if not self.hooked then self.context:Event("ADDON_LOADED", AddonLoaded) end
end

function M:Refresh()
    if self.active then self:Enable() end
end

function M:Disable()
    self.context:RemoveEvent("ADDON_LOADED")
    if not self.openedCharacter then self.context:RemoveEvent("PLAYER_REGEN_ENABLED") end
    CloseCharacter(self)
end

S.Install("characterUpgradeWindow", M)
