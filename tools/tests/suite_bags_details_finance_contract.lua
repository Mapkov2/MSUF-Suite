local root = assert(arg[1])
local calls, combat, guid, money, now = 0, false, "one", 100, 100 * 86400
local M = { active = true, config = { groupEquipmentSets = true, showEquipmentSetNames = true,
    showUpgradeTrack = true, showGoldHistory = true } }
local optIn = false
local S = { Public = function(v) return v ~= "secret" end, Finite = function(v) return type(v) == "number" end,
    PublicText = function(v) return type(v) == "string" and v ~= "" and v or nil end,
    -- DataTexts' "Remember this character's gold" is the one opt-in for balances.
    Config = function(id) return id == "dataTexts" and { trackAltGold = optIn } or M.config end }
local NS = { Client = { isForever = false }, RootDB = {}, IsCombatLocked = function() return combat end }
local P = { NS = NS, Suite = S, BagsModule = M,
    InventoryView = { SuiteLayout = function() return true end, CombatLine = function() return false end } }
C_EquipmentSet = {
    GetEquipmentSetIDs = function() calls = calls + 1; return { 4, 2 } end,
    GetEquipmentSetInfo = function(id) return id == 2 and "Tank" or "Damage" end,
    GetItemLocations = function(id) return id == 2 and { 201 } or { 201, 202 } end,
}
EquipmentManager_GetLocationData = function(location) return { isBags = true, bag = 0, slot = location - 200 } end
C_Item = { GetItemUpgradeInfo = function() return { currentLevel = 3, maxLevel = 8, trackString = "Hero" } end }
Enum = { TooltipDataType = { Item = 0 } }
-- Blizzard_SharedXMLGame defines the tooltip data processor at startup.
TooltipDataProcessor = { AddTooltipPostCall = function() end }
assert(loadfile(root .. "/MSUF_Suite_Bags/SlotCache.lua"))("Bags", P)
assert(loadfile(root .. "/MSUF_Suite_Bags/InventoryDetails.lua"))("Bags", P)
local index = { items = { { itemID = 10, link = "item:10", bag = 0, slot = 1, equipLoc = "HEAD" },
    { itemID = 10, link = "item:10", bag = 0, slot = 2, equipLoc = "HEAD" } } }
P.InventoryDetails.Index(index)
assert(index.items[1].setName == "Tank" and index.items[2].setName == "Damage", "sets match physical items, not identical item IDs")
assert(#index.items[1].setNames == 2 and index.items[1].setNames[2] == "Damage"
    and index.items[1].setLabel == "Tank / Damage", "shared items retain every set membership and label")
assert(index.items[1].upgrade == "3/8" and index.items[1].upgradeTrack == "Hero")
P.InventoryDetails.Index(index)
assert(calls == 1, "set membership is cached until an inventory/set event")
P.InventoryDetails.Invalidate(); P.InventoryDetails.Index(index)
assert(calls == 2)
M.config.groupEquipmentSets, M.config.showEquipmentSetNames = false, false
P.InventoryDetails.Index(index)
assert(not index.items[1].setName and not index.items[1].setNames and not index.items[1].setLabel,
    "disabled set labels do not retain stale values")
-- The keystone's dungeon tag comes from Blizzard's localized map name.
do
    local names = { "The Stonevault", "Ara-Kara, City of Echoes", "\229\141\131\228\184\157\228\185\139\229\159\142",
        "Operation: Floodgate", "Uldaman" }
    local expected = { "STO", "ARA", "\229\141\131\228\184\157", "OPE", "ULD" }
    local owned
    C_MythicPlus = { GetOwnedKeystoneLevel = function() return 12 end,
        GetOwnedKeystoneChallengeMapID = function() return owned end }
    C_ChallengeMode = { GetMapUIInfo = function(id) return names[id] end }
    C_Item.IsItemKeystoneByID = function(id) return id == 180653 end
    M.config.showKeystoneDetails = true
    for id = 1, #names do
        owned = id
        local keystone = { items = { { itemID = 180653, link = "item:180653", bag = 0, slot = 1 } } }
        P.InventoryDetails.Index(keystone)
        assert(keystone.items[1].keyLevel == 12 and keystone.items[1].keyMap == expected[id],
            "keystone tag of " .. names[id] .. " is " .. tostring(keystone.items[1].keyMap))
    end
    M.config.showKeystoneDetails = nil
end
UnitGUID = function() return guid end
UnitFullName = function() return guid, "Realm" end
GetMoney = function() return money end
GetServerTime = function() return now end
hooksecurefunc = function() end
UISpecialFrames = {}
assert(loadfile(root .. "/MSUF_Suite_Bags/GridView.lua"))("Bags", P)
-- A client in UTC: local calendar days are the UTC days below.
date = function(format, time)
    if format == "*t" then return os.date("!*t", time) end
    return os.date(format, time)
end
assert(loadfile(root .. "/MSUF_Suite_Bags/Finance.lua"))("Bags", P)
local F = P.BagFinance
F.Record()
money = 150; F.Record()
money = 125; F.Record()
local one = NS.RootDB.suiteBagGold.characters.one
assert(one.days[1].earned == 50 and one.days[1].spent == 25 and one.money == 125)
F.Record()
assert(one.days[1].earned == 50, "unchanged settings/refreshes never duplicate transactions")
for day = 101, 140 do now = day * 86400; money = money + 1; F.Record() end
assert(#one.days == 30 and one.days[1].day == 111, "gold history is bounded to 30 calendar days")
guid, money = "two", 999; F.Record()
assert(NS.RootDB.suiteBagGold.characters.one.money == 165 and NS.RootDB.suiteBagGold.characters.two.money == 999)
money = "secret"; F.Record()
assert(NS.RootDB.suiteBagGold.characters.two.money == 999, "restricted money never enters saved state")
M.config.showGoldHistory = false
money = 111; F.Record()
assert(NS.RootDB.suiteBagGold.characters.two.money == 999, "disabled history stops recording")
M.config.showGoldHistory = true
F.Record()
local two = NS.RootDB.suiteBagGold.characters.two
assert(two.money == 111 and two.days[1].earned == 0 and two.days[1].spent == 0,
    "re-enabling starts a new baseline without counting untracked money changes")
money = 121; F.Record()
assert(two.days[1].earned == 10 and two.days[1].spent == 0)
F.Disable()
money = 501; F.Record()
assert(two.days[1].earned == 10 and two.days[1].spent == 0, "module disable also releases transaction baseline")
assert(loadfile(root .. "/MSUF_Suite_Bags/Finance.lua"))("Bags", P)
F = P.BagFinance
money = 800; F.Record()
assert(two.money == 800 and two.days[1].earned == 10, "new session starts without extrapolating offline transactions")
S.Text = function(v) return v end
S.MoneyText = tostring
assert(NS.RootDB.goldLedger == nil, "the Bags wrote the shared gold ledger around the DataTexts opt-in")
NS.RootDB.goldLedger = { old = { name = "Old character", money = 700 }, one = { name = "One - DataTexts", money = 5 } }
-- The Gold history lists every character's balance the Bags recorded
-- ("Record gold history and character balances"); DataTexts' own list joins
-- only while its opt-in is on, and a character the Bags know is listed once.
local function Rows()
    local seen, daily, total = {}, 0, nil
    for _, row in ipairs(F.BuildRows()) do
        seen[row.left .. "=" .. row.right] = true
        if row.left:match("^%d%d%d%d%-%d%d%-%d%d$") then daily = daily + 1 end
        if row.left == "Recorded character gold" then total = row.right end
    end
    return seen, daily, total
end
local seen, daily, total = Rows()
assert(seen["one - Realm=165"] and seen["two - Realm=800"] and total == "965" and daily == 1,
    "the Gold history lost the character balances the Bags recorded")
assert(not seen["Old character=700"] and not seen["One - DataTexts=5"],
    "DataTexts' character list shows in the Bags without its opt-in")
optIn = true
seen, daily, total = Rows()
assert(seen["Old character=700"] and seen["one - Realm=165"] and not seen["One - DataTexts=5"]
    and total == "1665" and daily == 1, "existing account gold participates without invented history")
-- One clear removes the balances and the history; the history starts again.
NS.ClearCharacterGold = function() NS.RootDB.goldLedger, NS.RootDB.suiteBagGold = nil, nil end
NS.ClearCharacterGold()
money = 820; F.Record()
assert(NS.RootDB.suiteBagGold.characters.two.days[1].earned == 0 and NS.RootDB.goldLedger == nil,
    "a clear must not leave old history behind")
optIn = false
-- Days that left the 30-day window leave the history; a character keeps
-- its last recorded balance, one with neither is removed.
NS.RootDB.suiteBagGold.characters.stale = { days = { { day = 50, earned = 1, spent = 0 } } }
NS.RootDB.suiteBagGold.characters.away = { name = "Away - Realm", money = 900,
    days = { { day = 50, earned = 1, spent = 0 } } }
assert(loadfile(root .. "/MSUF_Suite_Bags/Finance.lua"))("Bags", P)
F = P.BagFinance
F.Record()
local away = NS.RootDB.suiteBagGold.characters.away
assert(NS.RootDB.suiteBagGold.characters.stale == nil and NS.RootDB.suiteBagGold.characters.two,
    "old characters must be pruned from the gold history")
assert(away and away.money == 900 and #away.days == 0, "a character away for 30 days lost its last balance")
seen = Rows()
assert(seen["Away - Realm=900"], "the Gold history does not list a character away for 30 days")
-- Days follow the local calendar: a client eight hours behind UTC.
do
    local saved, savedNow = date, now
    local zone = -8 * 3600
    date = function(format, time)
        if format:sub(1, 1) == "!" then return os.date(format, time) end
        return os.date("!" .. format, time + zone)
    end
    local base = 1790726400 -- 2026-09-30 00:00 UTC
    now, money = base + 18 * 3600, 1000 -- 10:00 local on 2026-09-30
    NS.RootDB.suiteBagGold = nil
    assert(loadfile(root .. "/MSUF_Suite_Bags/Finance.lua"))("Bags", P)
    F = P.BagFinance
    F.Record()
    money = 1100; F.Record()
    now, money = base + 31 * 3600, 1150 -- 23:00 local, already 2026-10-01 in UTC
    F.Record()
    local days = NS.RootDB.suiteBagGold.characters[guid].days
    local labels = {}
    for _, row in ipairs(F.BuildRows()) do
        if row.left:match("^%d%d%d%d%-%d%d%-%d%d$") then labels[#labels + 1] = row.left end
    end
    assert(#days == 1 and days[1].earned == 150 and #labels == 1 and labels[1] == "2026-09-30",
        "gold history must group and label by the local calendar date: " .. table.concat(labels, ", "))
    date, now = saved, savedNow
end
-- A default/unknown font resolves to nil. Fresh FontStrings must still receive
-- the Suite global font before their first SetText, in the footer and window.
do
    local fontCalls, globalFont = 0, "SuiteDefault.ttf"
    local function Noop() end
    local function Frame()
        return { SetPoint = Noop, ClearAllPoints = Noop, SetSize = Noop, SetHeight = Noop, SetFrameStrata = Noop,
            SetClampedToScreen = Noop, SetFrameLevel = Noop, SetScript = Noop,
            SetMovable = Noop, EnableMouse = Noop, RegisterForDrag = Noop, StartMoving = Noop,
            StopMovingOrSizing = Noop,
            RegisterForClicks = Noop, SetScrollChild = Noop, GetFrameLevel = function() return 1 end,
            IsShown = function(self) return self.shown ~= false end,
            Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
            SetShown = function(self, value) self.shown = value end,
            TitleText = { SetText = Noop } }
    end
    S.CreateFrame = Frame
    S.CreateFontString = function()
        return { SetPoint = Noop, SetWidth = Noop, SetAllPoints = Noop,
            SetJustifyH = Noop, SetWordWrap = Noop, Show = Noop, Hide = Noop,
            SetText = function(self, value)
                assert(self.font, "FontString:SetText(): Font not set")
                self.text = value
            end }
    end
    S.ResolveFont = function(key) return key == "custom" and "Custom.ttf" or nil end
    S.GlobalFontPath = function() return globalFont end
    S.SetFont = function(label, path, size)
        label.font, label.size = path or globalFont, size
        fontCalls = fontCalls + 1
    end
    C_CurrencyInfo = { GetCurrencyInfo = function() return nil end }
    M.frame = Frame()
    M.config.font = nil
    F.Refresh()
    assert(F.label.font == globalFont and F.label.text == "Gold history",
        "default font must initialize the footer before text is set")
    F.Show()
    assert(#F.labels > 0 and F.labels[1].left.font == globalFont
        and F.labels[1].right.font == globalFont, "history rows need initial default fonts")
    local stable = fontCalls
    F.Refresh()
    assert(fontCalls == stable, "unchanged finance redraws must not reapply fonts")
    M.config.font = "unknown-font"
    globalFont = "UpdatedDefault.ttf"
    F.Refresh()
    assert(F.label.font == globalFont and F.labels[1].left.font == globalFont,
        "unresolved fonts must follow global font changes")
    M.config.font = "custom"
    F.Refresh()
    assert(F.label.font == "Custom.ttf" and F.labels[1].right.font == "Custom.ttf",
        "explicit fonts must refresh both finance surfaces")
    F.Disable()
end
local timers, shown, refreshes = {}, true, 0
M.frame = { IsShown = function() return shown end }
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
F.Refresh = function() refreshes = refreshes + 1 end
money = 1000; F.Event(nil, "PLAYER_MONEY")
money = 1002; F.Event(nil, "PLAYER_MONEY")
F.Event(nil, "CURRENCY_DISPLAY_UPDATE")
assert(#timers == 1 and NS.RootDB.suiteBagGold.characters.two.money == 1002,
    "event bursts coalesce drawing while preserving each gold transaction")
table.remove(timers, 1)()
assert(refreshes == 1)
shown = false; F.Event(nil, "CURRENCY_DISPLAY_UPDATE")
assert(#timers == 0, "hidden finance has no scheduled rendering")
print("equipment identity/cache, upgrade data, bounded gold history and event coalescing passed")
