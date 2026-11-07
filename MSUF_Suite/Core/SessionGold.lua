local _, Suite = ...
local Gold = {}
Suite.GoldLedger = Gold
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

-- Use the local calendar date of the server timestamp for both history and Today.
function Gold.LocalDay(now)
    local t = date("*t", now)
    local year, month = t.year, t.month
    if month <= 2 then year = year - 1 end
    local era = math.floor(year / 400)
    local yearOfEra = year - era * 400
    local dayOfYear = math.floor((153 * ((month + 9) % 12) + 2) / 5) + t.day - 1
    local dayOfEra = yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100) + dayOfYear
    return era * 146097 + dayOfEra - 719468
end

local recording

-- Recorded income, spending and net change in copper for the local day.
function Gold.Today()
    if not recording then return end
    local root, guid = Suite.RootDB, PlayerKey()
    if not guid then return end
    local ledger = root and root.suiteBagGold
    local characters = type(ledger) == "table" and ledger.characters
    local record = type(characters) == "table" and characters[guid]
    local days = type(record) == "table" and record.days
    if type(days) ~= "table" then return 0, 0, 0 end
    local today, earned, spent = Gold.LocalDay(GetServerTime()), 0, 0
    for i = #days, 1, -1 do
        local row = days[i]
        if type(row) == "table" and row.day == today and Suite.Finite(row.earned) and Suite.Finite(row.spent) then
            earned, spent = earned + row.earned, spent + row.spent
        end
    end
    return earned, spent, earned - spent
end

-- One display listener for Bags and DataTexts. The recorder keeps its own
-- events. Read after their dispatch so registration order cannot lag a gain.
local watchers, events = {}
local refresh, midnight

local function PaintToday()
    refresh = nil
    for owner, callback in pairs(watchers) do Suite.Dispatch(callback, owner) end
end

local function QueueToday()
    if recording and next(watchers) and not refresh and not Suite.InCombat() then
        refresh = Suite.Suite.ScheduleDataTick("todayGoldRefresh", 0, PaintToday)
    end
end

local function ArmMidnight()
    local now = GetServerTime()
    local nextDay = date("*t", now)
    nextDay.day = nextDay.day + 1
    nextDay.hour, nextDay.min, nextDay.sec, nextDay.isdst = 0, 0, 0, nil
    midnight = Suite.Suite.ScheduleDataTick("todayGoldMidnight", time(nextDay) - now, ArmMidnight)
    QueueToday()
end

local function PauseToday()
    events:UnregisterEvent("PLAYER_MONEY")
    events:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if refresh then
        refresh:Cancel()
        refresh = nil
    end
    if midnight then
        midnight:Cancel()
        midnight = nil
    end
end

local function ResumeToday()
    events:RegisterEvent("PLAYER_MONEY")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    ArmMidnight()
end

local function TodayEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        PauseToday()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ResumeToday()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ArmMidnight()
    else
        QueueToday()
    end
end

local function SyncToday()
    if events then
        PauseToday()
        events:UnregisterAllEvents()
    end
    if not recording or not next(watchers) then return end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", TodayEvent)
    end
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    if not Suite.InCombat() then ResumeToday() end
end

function Gold.WatchToday(owner, callback)
    if watchers[owner] == callback then return end
    local hadWatchers = next(watchers) ~= nil
    watchers[owner] = callback
    if hadWatchers ~= (next(watchers) ~= nil) then SyncToday() end
end

function Gold.SetHistoryRecording(active)
    if recording == active then return end
    recording = active
    SyncToday()
    if not active and next(watchers) and not Suite.InCombat() then PaintToday() end
end

-- Both options pages clear the shared ledger and any unmerged older balances.
function Suite.ClearCharacterGold()
    local root = Suite.RootDB
    if type(root) ~= "table" then return false end
    root.goldLedger, root.suiteBagGold = nil, nil
    QueueToday()
    return true
end
