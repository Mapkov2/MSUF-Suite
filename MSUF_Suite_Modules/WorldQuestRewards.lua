local _, P = ...
local S = P.Suite
local Field, Finite, Text = S.PublicField, S.Finite, S.PublicText

local Rewards = {}
P.WorldQuestRewards = Rewards

local function Positive(value)
    return Finite(value) and value > 0
end

local function Readable(value)
    return S.Public(value) and type(value) == "table" and canaccesstable(value)
end

local function ReadCurrencies(id, classes, lines)
    local currencies = C_QuestLog.GetQuestRewardCurrencies(id)
    if not Readable(currencies) then return end
    for i = 1, #currencies do
        local entry = currencies[i]
        local currencyID = Readable(entry) and Field(entry, "currencyID")
        if Positive(currencyID) then
            local faction = C_CurrencyInfo.GetFactionGrantedByCurrency(currencyID)
            if S.Public(faction) then
                local key = Positive(faction) and "reputation" or "currency"
                classes[key] = true
                local name, count = Text(Field(entry, "name")), Field(entry, "totalRewardAmount")
                if name then
                    lines[#lines + 1] = Positive(count) and S.Text("%s × %s"):format(BreakUpLargeNumbers(count), name) or name
                end
            end
        end
    end
end

local function ReadReputation(id, classes, lines)
    local rewards = C_QuestLog.GetQuestLogMajorFactionReputationRewards(id)
    if not Readable(rewards) then return end
    for i = 1, #rewards do
        local entry = rewards[i]
        local factionID = Readable(entry) and Field(entry, "factionID")
        if Positive(factionID) then
            classes.reputation = true
            local faction, amount = C_MajorFactions.GetMajorFactionData(factionID), Field(entry, "rewardAmount")
            local name = Readable(faction) and Text(Field(faction, "name"))
            if name and Positive(amount) then
                lines[#lines + 1] = S.Text("%s × %s"):format(BreakUpLargeNumbers(amount), name)
            end
        end
    end
end

local function ReadTaskFaction(id, factionID, classes, lines)
    if classes.reputation or not Positive(factionID) then return end
    local awards = C_QuestLog.DoesQuestAwardReputationWithFaction(id, factionID)
    if not S.Public(awards) or awards ~= true then return end
    classes.reputation = true
    local faction = C_Reputation.GetFactionDataByID(factionID)
    local name = Readable(faction) and Text(Field(faction, "name"))
    if name then lines[#lines + 1] = name end
end

local function ReadItems(id, classes, lines, count, getInfo)
    if not Positive(count) then return end
    for i = 1, count do
        local name, _, amount, _, _, itemID = getInfo(i, id)
        if Positive(itemID) then
            local _, _, _, slot = C_Item.GetItemInfoInstant(itemID)
            if Text(slot) then classes.gear = true end
        end
        name = Text(name)
        if name then
            lines[#lines + 1] = Positive(amount) and amount > 1
                and S.Text("%s × %s"):format(BreakUpLargeNumbers(amount), name) or name
        end
    end
end

-- Retail 297d7aaa: WorldQuestDataProvider requests missing rewards; QuestUtils
-- renders loaded money/currencies/items, and QuestInfo reads major-faction rep.
function Rewards.Read(id, taskFactionID)
    local ready = HaveQuestRewardData(id)
    if not S.Public(ready) or ready ~= true then return end
    local classes, lines = {}, {}
    local money = GetQuestLogRewardMoney(id)
    if Positive(money) then
        classes.gold = true
        local display = Text(GetMoneyString(money, true))
        if display then lines[#lines + 1] = display end
    end
    ReadCurrencies(id, classes, lines)
    ReadReputation(id, classes, lines)
    ReadTaskFaction(id, taskFactionID, classes, lines)
    ReadItems(id, classes, lines, GetNumQuestLogRewards(id), GetQuestLogRewardInfo)
    ReadItems(id, classes, lines, GetNumQuestLogChoices(id), GetQuestLogChoiceInfo)
    local search = table.concat(lines, " ")
    if classes.gold then search = search .. " " .. S.Text("Gold") end
    if classes.reputation then search = search .. " " .. S.Text("Reputation") end
    if classes.currency then search = search .. " " .. S.Text("Currency") end
    if classes.gear then search = search .. " " .. S.Text("Gear") end
    return classes, table.concat(lines, "\n"), search
end
