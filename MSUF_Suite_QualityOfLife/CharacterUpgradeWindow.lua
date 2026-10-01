local _, P = ...
local NS, S = P.NS, P.Suite

-- Opens the character window beside an item upgrade merchant. Blizzard places
-- the pushable CharacterFrame next to the non-pushable ItemUpgradeFrame
-- (UIPanelWindows); CharacterPanel.lua owns the opening and closing.
local M = {}

local function OpenCharacter(self)
    if not self.active or not ItemUpgradeFrame:IsShown() then return end
    if NS.IsCombatLocked() then
        self.context:Event("PLAYER_REGEN_ENABLED", OpenCharacter)
        return
    end
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    S.OpenCharacterFor(self)
end

local function UpgradeShown()
    if M.active then OpenCharacter(M) end
end

local function UpgradeHidden()
    if not M.active then return end
    M.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    S.CloseCharacterFor(M)
end

-- Blizzard_ItemUpgradeUI loads on demand; script hooks cannot be removed.
local function InstallHooks(self)
    if not self.hooked then
        ItemUpgradeFrame:HookScript("OnShow", UpgradeShown)
        ItemUpgradeFrame:HookScript("OnHide", UpgradeHidden)
        self.hooked = true
    end
    self.context:RemoveEvent("ADDON_LOADED")
    OpenCharacter(self)
end

local function AddonLoaded(self, _, addon)
    if addon == "Blizzard_ItemUpgradeUI" then InstallHooks(self) end
end

function M:Enable()
    if _G.ItemUpgradeFrame then
        InstallHooks(self)
    else
        self.context:Event("ADDON_LOADED", AddonLoaded)
    end
end

function M:Refresh() end

function M:Disable()
    self.context:RemoveEvent("ADDON_LOADED")
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    S.CloseCharacterFor(self)
end

S.Install("characterUpgradeWindow", M)
