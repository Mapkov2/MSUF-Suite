local _, P = ...
local NS, S = P.NS, P.Suite
local Ledger = {}

function Ledger.Capture()
    local root = NS.RootDB
    if type(root) ~= "table" then return end
    local guid = S.PublicText(UnitGUID("player"))
    local name = S.PublicText(UnitName("player"))
    local realm = S.PublicText(GetRealmName())
    local amount = GetMoney()
    if not guid or not name or not realm or not S.Finite(amount) or amount < 0 then return end
    local entries = root.goldLedger
    if type(entries) ~= "table" then entries = {}; root.goldLedger = entries end
    -- PLAYER_MONEY: the character's entry is updated in place.
    local entry = entries[guid]
    if type(entry) ~= "table" then
        entry = {}
        entries[guid] = entry
    end
    entry.name, entry.money = name .. " - " .. realm, math.floor(amount)
end

function Ledger.Snapshot()
    local root = NS.RootDB
    local entries = type(root) == "table" and root.goldLedger
    if type(entries) ~= "table" then return nil end
    local rows, total = {}, 0
    for guid, entry in pairs(entries) do
        if type(guid) == "string" and type(entry) == "table"
            and S.PublicText(entry.name) and S.Finite(entry.money) and entry.money >= 0 then
            rows[#rows + 1] = { guid = guid, name = entry.name, money = entry.money }
            total = total + entry.money
        end
    end
    if #rows == 0 or not S.Finite(total) then return nil end
    table.sort(rows, function(a, b)
        return a.money == b.money and a.name < b.name or a.money > b.money
    end)
    return rows, total
end

function Ledger.AppendTooltip(tooltip, moneyText, labels)
    local rows, total = Ledger.Snapshot()
    if not rows then return end
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(labels.knownTotal, moneyText(total), .8, .82, .86, 1, .85, .45)
    local current = S.PublicText(UnitGUID("player"))
    local shown, remaining = 0, 0
    for i = 1, #rows do
        local row = rows[i]
        if not current or row.guid ~= current then
            if shown < 8 then
                tooltip:AddDoubleLine(row.name, moneyText(row.money), .8, .82, .86, 1, 1, 1)
                shown = shown + 1
            else
                remaining = remaining + 1
            end
        end
    end
    if remaining > 0 then tooltip:AddLine(labels.moreCharacters:format(remaining), .7, .75, .8) end
end

P.GoldLedger = Ledger
