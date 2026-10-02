local _, P = ...
local NS, S = P.NS, P.Suite
-- Retail and Forever keep backpack and bag slots on a separate BagsBar.
-- The bag DataText is the visible entry point while "Hide Blizzard bag
-- buttons" is on; Blizzard still owns item movement and the actual container
-- windows. A "hide" state driver keeps the bar hidden, also through Blizzard's
-- own shows; turning the option off or stopping DataTexts gives it back.
local NativeBagBar = {}
P.DataTextNativeBagBar = NativeBagBar
local ID = "dataTexts"
local M = P.DataTexts
local nativeBagBar, nativeBagBarWasShown, nativeBagDriver, nativeBagHooked
local nativeBagShowHooks = setmetatable({}, { __mode = "k" })

local function Sync()
    if NS.IsCombatLocked() then
        S.Queue(ID)
        return
    end
    local frame = _G.BagsBar
    if M.active and M.config and M.config.hideBlizzardBagBar == true and frame then
        if nativeBagBar ~= frame then
            nativeBagBar = frame
            nativeBagBarWasShown = frame:IsShown() == true
        end
        if not nativeBagDriver then
            RegisterStateDriver(frame, "visibility", "hide")
            nativeBagDriver = true
        end
        frame:Hide()
        if not nativeBagShowHooks[frame] then
            frame:HookScript("OnShow", Sync)
            nativeBagShowHooks[frame] = true
        end
        -- WoW Forever only: its mouse-and-keyboard action bar setup shows the bag bar.
        if not nativeBagHooked and _G.MainActionBar_InitializeMKB then
            hooksecurefunc("MainActionBar_InitializeMKB", Sync)
            nativeBagHooked = true
        end
    elseif nativeBagBar then
        if nativeBagDriver then UnregisterStateDriver(nativeBagBar, "visibility") end
        nativeBagDriver = nil
        local restoreFrame, wasShown = nativeBagBar, nativeBagBarWasShown
        nativeBagBar, nativeBagBarWasShown = nil, nil
        if wasShown then restoreFrame:Show() end
    end
end
NativeBagBar.Sync = Sync

-- ADDON_LOADED: Blizzard's bag buttons load on demand.
function NativeBagBar.AddonLoaded(_, _, addon)
    if addon == "Blizzard_MainMenuBarBagButtons" then Sync() end
end
