local _, P = ...
local NS, S = P.NS, P.Suite

-- The character window, opened for the player by QoL helpers (merchant
-- visits, item upgrades). ShowUIPanel and HideUIPanel hand the panel to
-- Blizzard's secure FramePositionDelegate (Blizzard_UIParentPanelManager),
-- so it opens and closes as if the player had done it; ToggleCharacter would
-- run CharacterFrame's tab and sub-frame code from addon code. The window
-- opens on the tab the player used last. Each helper owns only an opening it
-- made: the window closes once no owner holds it, and never after the player
-- or anything else closed it in between.
local owners, watcher = {}, nil

local function CancelPendingClose()
    if watcher then watcher:UnregisterEvent("PLAYER_REGEN_ENABLED") end
end

local function Hidden()
    for owner in pairs(owners) do owners[owner] = nil end
    CancelPendingClose()
end

local function CloseUnowned()
    CancelPendingClose()
    if next(owners) == nil and CharacterFrame:IsShown() then
        S.Dispatch(NS.Finish, HideUIPanel, CharacterFrame)
    end
end

local function Watch()
    if watcher then return end
    watcher = S.CreateFrame("Frame")
    watcher:SetScript("OnEvent", CloseUnowned)
    CharacterFrame:HookScript("OnHide", Hidden)
end

-- Opens the window for owner outside combat. True when owner now holds it;
-- a window the player opened stays the player's.
function S.OpenCharacterFor(owner)
    if InCombatLockdown() or CharacterFrame:IsShown() then return owners[owner] == true end
    Watch()
    S.Dispatch(NS.Finish, ShowUIPanel, CharacterFrame)
    if not CharacterFrame:IsShown() then return false end
    owners[owner] = true
    return true
end

-- Lets go of owner's opening. The panel manager refuses addon calls in
-- combat, so the close then waits for PLAYER_REGEN_ENABLED.
function S.CloseCharacterFor(owner)
    if not owners[owner] then return end
    owners[owner] = nil
    if next(owners) ~= nil or not CharacterFrame:IsShown() then return end
    if InCombatLockdown() then
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    CloseUnowned()
end

function S.HoldsCharacter(owner)
    return owners[owner] == true
end
