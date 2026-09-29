local root = assert(arg[1], "repository root required")
local amount, guid, name = 12345, "Player-1", "Alice"
UnitGUID = function() return guid end
UnitName = function() return name end
GetRealmName = function() return "Realm" end
GetMoney = function() return amount end
local suite = {
    PublicText = function(value) return type(value) == "string" and value ~= "secret" and value or nil end,
    Finite = function(value) return type(value) == "number" and value == value end,
}
local ns = { RootDB = {} }
local package = { NS = ns, Suite = suite }
assert(loadfile(root .. "/MSUF_Suite_DataTexts/GoldLedger.lua"))("MSUF_Suite_DataTexts", package)
local ledger = assert(package.GoldLedger)
ledger.Capture()
assert(ns.RootDB.goldLedger["Player-1"].money == 12345,
    "login money was not remembered")
guid, name, amount = "Player-2", "Bob", 33333
ledger.Capture()
local rows, total = ledger.Snapshot()
assert(total == 45678 and #rows == 2 and rows[1].name == "Bob - Realm",
    "account snapshot did not total and sort characters")
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
ns.RootDB.goldLedger = nil
assert(ledger.Snapshot() == nil, "clearing the ledger left stale rows")
print("Suite account gold ledger passed")
