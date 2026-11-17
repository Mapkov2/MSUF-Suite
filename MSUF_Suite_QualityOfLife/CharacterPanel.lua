local _, P = ...
local NS, S = P.NS, P.Suite

-- Merchant and upgrade helpers open the character window on its last tab.
-- Each helper owns only an opening it made. The window closes when the last
-- owner releases it, unless the player already closed it in between.
local owners, watcher = {}, nil

local function CanDrive()
    if S.GamepadUI() then return false end
    if not NS.Client.isForever then return true end
    -- The native panel delegate runs in the caller and writes shared slots
    -- also used by Blizzard Edit Mode. Only a defined floating area takes
    -- ShowUIPanel and HideUIPanel's direct path. Recheck it on deferred close.
    local defined = CharacterFrame:GetAttribute("UIPanelLayout-defined")
    if not NS.Public(defined) or defined ~= true then return false end
    local area = CharacterFrame:GetAttribute("UIPanelLayout-area")
    return NS.Public(area) and area == nil
end

local function CancelPendingClose()
    if watcher then watcher:UnregisterEvent("PLAYER_REGEN_ENABLED") end
end

local function Hidden()
    for owner in pairs(owners) do owners[owner] = nil end
    CancelPendingClose()
end

local function CloseUnowned()
    CancelPendingClose()
    if next(owners) == nil and CharacterFrame:IsShown() and CanDrive() then
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
    if InCombatLockdown() or not CanDrive() or CharacterFrame:IsShown() then return owners[owner] == true end
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
