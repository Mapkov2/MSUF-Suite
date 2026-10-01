local root = assert(arg[1], "repository root required")
-- The DataTexts account total over the one gold ledger it shares with the
-- Bags gold history (MSUF_Suite/Core/Catalog/Bags.lua).
local amount, guid, name, now = 12345, "Player-1", "Alice", 1000
UnitGUID = function() return guid end
UnitName = function() return name end
GetRealmName = function() return "Realm" end
GetMoney = function() return amount end
GetServerTime = function() return now end
local suite = {
    PublicText = function(value) return type(value) == "string" and value ~= "secret" and value ~= "" and value or nil end,
    Finite = function(value) return type(value) == "number" and value == value end,
}
local ns = { RootDB = {}, Client = { isForever = false }, Text = function(text) return text end,
    PublicText = suite.PublicText, Finite = suite.Finite }
local function LoadCore()
    for _, file in ipairs({ "SuiteCatalog", "Catalog/Bags" }) do
        assert(loadfile(root .. "/MSUF_Suite/Core/" .. file .. ".lua"))("MSUF_Suite", ns)
    end
end
LoadCore()
local package = { NS = ns, Suite = suite }
assert(loadfile(root .. "/MSUF_Suite_DataTexts/GoldLedger.lua"))("MSUF_Suite_DataTexts", package)
local ledger = assert(package.GoldLedger)
ledger.Capture()
local characters = ns.RootDB.suiteBagGold.characters
assert(characters["Player-1"].money == 12345 and characters["Player-1"].account and not characters["Player-1"].bags,
    "login money was not remembered as an account balance")
guid, name, amount = "Player-2", "Bob", 33333
ledger.Capture()
local rows, total = ledger.Snapshot()
assert(total == 45678 and #rows == 2 and rows[1].name == "Bob - Realm",
    "account snapshot did not total and sort characters")
-- PLAYER_MONEY updates the character's entry in place: no table per event.
local entry = characters["Player-2"]
amount = 33334
ledger.Capture()
assert(characters["Player-2"] == entry and entry.money == 33334,
    "a money change replaced the character's ledger entry")
amount = 33333
ledger.Capture()
-- A character only the Bags gold history recorded is not an account balance.
characters["Player-3"] = { name = "Carol - Realm", money = 5, days = {}, bags = true }
rows, total = ledger.Snapshot()
assert(total == 45678 and #rows == 2, "the account total listed a character that never opted in")
local tooltip = { lines = {} }
function tooltip:AddLine(label) self.lines[#self.lines + 1] = { label } end
function tooltip:AddDoubleLine(label, value) self.lines[#self.lines + 1] = { label, value } end
ledger.AppendTooltip(tooltip, tostring,
    { knownTotal = "Known account gold", moreCharacters = "%d more characters" })
assert(#tooltip.lines == 3 and tooltip.lines[2][2] == "45678"
    and tooltip.lines[3][1] == "Alice - Realm",
    "hover details did not show the known total and other character")
amount = "secret"
ledger.Capture()
rows, total = ledger.Snapshot()
assert(total == 45678 and #rows == 2, "secret money changed the ledger")
-- NS.ClearCharacterGold (SessionGold.lua) removes the ledger.
ns.RootDB.suiteBagGold, ns.RootDB.goldLedger = nil, nil
assert(ledger.Snapshot() == nil, "clearing the ledger left stale rows")

-- Older builds: the Bags history and the DataTexts balances apart. Both
-- join the one ledger without losing a balance or a day of history.
ns.RootDB = {
    suiteBagGold = { characters = {
        ["Player-1"] = { name = "Alice - Realm", money = 500, updated = 900,
            days = { { day = 1, earned = 10, spent = 2 } } },
    } },
    goldLedger = {
        ["Player-1"] = { name = "Alice - Realm", money = 400 },
        ["Player-9"] = { name = "Zed - Other", money = 70 },
    },
}
LoadCore()
characters = ns.GoldLedger.Characters()
local alice, zed = characters["Player-1"], characters["Player-9"]
assert(ns.RootDB.goldLedger == nil and ns.RootDB.suiteBagGold.version == 1, "the old balances were not moved")
assert(alice.bags and alice.account and alice.money == 500 and #alice.days == 1 and alice.days[1].earned == 10,
    "a character in both lists lost its history or its account balance")
assert(zed.account and not zed.bags and zed.money == 70 and zed.name == "Zed - Other",
    "an account balance of older builds was lost")
rows, total = ledger.Snapshot()
assert(#rows == 2 and total == 570, "migrated balances are missing from the account total")
print("Suite account gold ledger passed")
