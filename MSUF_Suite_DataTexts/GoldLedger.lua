local _, P = ...
local NS, S = P.NS, P.Suite
-- The account total of the DataTexts ("Remember this character's gold for
-- the account total"): the characters that opted in, from the one gold
-- ledger the Bags gold history shares (MSUF_Suite/Core/Catalog/Bags.lua).
local Ledger = {}
local Gold = NS.GoldLedger

-- PLAYER_MONEY and the world entry: this character's balance, updated in place.
function Ledger.Capture()
    Gold.Record("account")
end

function Ledger.Snapshot()
    local characters = Gold.Characters()
    if not characters then return nil end
    local rows, total = {}, 0
    for guid, record in pairs(characters) do
        if type(guid) == "string" and Gold.Listed(record) and record.account == true then
            rows[#rows + 1] = { guid = guid, name = record.name, money = record.money }
            total = total + record.money
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
