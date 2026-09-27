local _, Suite = ...
-- Each character's gold at login lives in RootDB.suiteGold, so the session
-- gold of Bags and DataTexts survives /reload. Suite.goldSessionCaptured
-- tells whether the stored value is this session's baseline. Secret values
-- are never stored.

local function PlayerKey()
    return Suite.PublicText(UnitGUID("player"))
end

-- This character's stored login gold: a non-negative number, or nil.
function Suite.StoredSessionGold()
    local root, key = Suite.RootDB, PlayerKey()
    local stored = key and type(root) == "table" and type(root.suiteGold) == "table" and root.suiteGold[key]
    if Suite.Finite(stored) and stored >= 0 then return stored end
end

-- Records money as this session's baseline. Returns false while the
-- database or the player is unreadable.
function Suite.SetSessionGold(money)
    local root, key = Suite.RootDB, PlayerKey()
    if type(root) ~= "table" or not key then return false end
    if type(root.suiteGold) ~= "table" then root.suiteGold = {} end
    root.suiteGold[key] = money
    Suite.goldSessionCaptured = true
    return true
end

-- Runs at the first PLAYER_ENTERING_WORLD (Startup.lua): a /reload keeps the
-- stored baseline, a login stores the current money.
function Suite.CaptureSessionGold(isReloadingUi)
    Suite.goldSessionCaptured = false
    local money = GetMoney()
    if not Suite.Finite(money) or money < 0 then return end
    if isReloadingUi == true and Suite.StoredSessionGold() then
        Suite.goldSessionCaptured = true
        return
    end
    Suite.SetSessionGold(money)
end
