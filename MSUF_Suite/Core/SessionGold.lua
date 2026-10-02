local _, Suite = ...
-- The character gold of Bags and DataTexts. Each character's gold at login
-- lives in RootDB.suiteGold, so the session gold survives /reload;
-- Suite.goldSessionCaptured tells whether the stored value is this session's
-- baseline. The gold ledger keeps every character's balance. Secret values
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

-- One clear for remembered character gold: the gold ledger (suiteBagGold)
-- and the DataTexts balances of older builds it has not merged yet
-- (goldLedger). The options pages of both modules offer it.
function Suite.ClearCharacterGold()
    local root = Suite.RootDB
    if type(root) ~= "table" then return false end
    root.goldLedger, root.suiteBagGold = nil, nil
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

------------------------------------------------------------------ character gold
-- One ledger of every character's gold, shared by the Bags gold history
-- ("Record gold history and character balances") and the DataTexts account
-- total ("Remember this character's gold for the account total"). It lives
-- in the core because both modules load on demand.
-- RootDB.suiteBagGold.characters[guid]: name, money (the last recorded
-- balance), updated (server time), days (the Bags' 30 days of income and
-- spending, Finance.lua) and which of the two recorded the character: bags,
-- account. Suite.ClearCharacterGold empties it.
local Gold = {}
Suite.GoldLedger = Gold
local LEDGER_VERSION = 1

-- Older builds kept the DataTexts balances apart, in RootDB.goldLedger
-- (guid -> name, money). They join the ledger as account balances; a
-- character the Bags already recorded keeps its record and history.
local function MergeAccountBalances(root, characters)
    local old = root.goldLedger
    root.goldLedger = nil
    if type(old) ~= "table" then return end
    for guid, entry in pairs(old) do
        if type(guid) == "string" and type(entry) == "table" and Suite.PublicText(entry.name)
            and Suite.Finite(entry.money) and entry.money >= 0 then
            local record = characters[guid]
            if type(record) ~= "table" then
                characters[guid] = { name = entry.name, money = entry.money, days = {}, account = true }
            else
                record.account = true
                if not Suite.Finite(record.money) then record.money = entry.money end
                if type(record.name) ~= "string" then record.name = entry.name end
            end
        end
    end
end

-- The ledger's characters, nil without saved variables. Records of a ledger
-- older than the account balances came from the Bags gold history alone.
function Gold.Characters()
    local root = Suite.RootDB
    if type(root) ~= "table" then return nil end
    local ledger = root.suiteBagGold
    if type(ledger) ~= "table" or type(ledger.characters) ~= "table" then
        ledger = { characters = {}, version = LEDGER_VERSION }
        root.suiteBagGold = ledger
    elseif ledger.version ~= LEDGER_VERSION then
        for _, record in pairs(ledger.characters) do
            if type(record) == "table" then record.bags = true end
        end
        ledger.version = LEDGER_VERSION
    end
    if root.goldLedger ~= nil then MergeAccountBalances(root, ledger.characters) end
    return ledger.characters
end

-- Whether a record has a balance to list.
function Gold.Listed(record)
    return type(record) == "table" and Suite.PublicText(record.name) ~= nil and Suite.Finite(record.money)
        and record.money >= 0
end

-- Records the player's current balance for a feature ("bags" or
-- "account"). Returns the record, the amount, the GUID and whether the
-- record is new, or nothing while the player or the money is unreadable
-- (secret values are never stored).
function Gold.Record(feature)
    local guid, name = Suite.PublicText(UnitGUID("player")), Suite.PublicText(UnitName("player"))
    local amount = GetMoney()
    if not guid or not name or not Suite.Finite(amount) or amount < 0 then return nil end
    local characters = Gold.Characters()
    if not characters then return nil end
    local record, created = characters[guid], false
    if type(record) ~= "table" then
        record, created = { days = {} }, true
        characters[guid] = record
    end
    local realm = Suite.PublicText(GetRealmName())
    record.name = realm and name .. " - " .. realm or name
    record.money, record.updated, record[feature] = math.floor(amount), GetServerTime(), true
    return record, record.money, guid, created
end

-- This session's login gold for the session gold of the Bags and DataTexts:
-- the core's capture at the first PLAYER_ENTERING_WORLD (below),
-- or after a /reload the stored one. When the login capture was unreadable,
-- the first public amount either module sees (money) becomes it, stored so
-- both agree and a /reload keeps it. nil while unknown.
function Suite.SessionGoldBaseline(money)
    if not Suite.loginKind then return nil end
    local stored = Suite.StoredSessionGold()
    if stored and (Suite.goldSessionCaptured == true or Suite.loginKind == "reload") then return stored end
    if not Suite.Finite(money) or money < 0 then return nil end
    money = math.floor(money)
    return Suite.SetSessionGold(money) and money or nil
end
