local _, P = ...
local S = P.Suite
local Field = P.NS.AppearancePrimitives.Safety.Field
local D = {}
P.LootRollData = D

local MAX_NAMES, MAX_ENCOUNTERS = 40, 8
local encounterTimes = {}

local function PublicTable(value)
    return S.Public(value) and type(value) == "table"
end

local function Key(value)
    return S.Finite(value) and value >= 0 and value == math.floor(value)
end

local function Positive(value)
    return S.Finite(value) and value > 0
end

local function True(value)
    return S.Public(value) and value == true
end

local function Icon(value)
    if Positive(value) then return value end
    return S.PublicText(value)
end

local function Counts()
    return { [0] = 0, 0, 0, 0, 0 }
end

-- History states are not the numeric actions accepted by RollOnLoot.
-- NoRoll is an outstanding decision, not Pass; there is no Disenchant
-- history state in the verified live/forever contracts.
local ROLL_STATES = {
    { "NeedMainSpec", 1, S.Text("Main spec") },
    { "NeedOffSpec", 1, S.Text("Off spec") },
    { "Transmog", 4, S.Text("Transmog") },
    { "Greed", 2, S.Text("Greed") },
    { "Pass", 0, S.Text("Pass") },
    { "NoRoll", nil, S.Text("Pending") },
}

local function Action(state)
    if not Key(state) or not PublicTable(Enum) then return nil end
    local states = Enum.EncounterLootDropRollState
    if not PublicTable(states) then return nil end
    for rank, definition in ipairs(ROLL_STATES) do
        local value = states[definition[1]]
        if S.Finite(value) and state == value then return definition[2], rank, definition[3] end
    end
end

local function ColoredName(name, class)
    if not class or not PublicTable(RAID_CLASS_COLORS) then return name end
    local color = RAID_CLASS_COLORS[class]
    if not PublicTable(color) then return name end
    local hex = S.PublicText(color.colorStr)
    if hex and hex:match("^%x%x%x%x%x%x%x%x$") then return "|c" .. hex .. name .. "|r" end
    return name
end

local function Player(info)
    local name = S.PublicText(info.playerName)
    if not name then return nil end
    local class = S.PublicText(info.playerClass)
    local choice, rank, label = Action(info.state)
    return {
        name = name, coloredName = ColoredName(name, class), class = class,
        key = S.PublicText(info.playerGUID) or name, choice = choice, rank = rank, label = label,
        roll = S.Finite(info.roll) and info.roll or nil, winner = True(info.isWinner),
        isSelf = True(info.isSelf),
    }
end

local function Item(entry)
    if not entry.link then return end
    local name, _, quality, level, _, _, _, _, _, texture, _, _, _, bind = C_Item.GetItemInfo(entry.link)
    if not entry.name then entry.name = S.PublicText(name) end
    if not entry.icon then entry.icon = Icon(texture) end
    if not Key(entry.quality) and Key(quality) then entry.quality = quality end
    local binds = Enum.ItemBind
    if S.Finite(bind) and binds and (bind == binds.OnAcquire or bind == binds.Quest) then
        entry.notAuctionable = true
    end
    local detailed = C_Item.GetDetailedItemLevelInfo(entry.link)
    if Positive(detailed) then entry.itemLevel = detailed
    elseif Positive(level) then
        entry.itemLevel = level
    end
end

local function AddonFunction(provider, method)
    if not PublicTable(provider) then return end
    local lookup = provider[method]
    if S.Public(lookup) and type(lookup) == "function" then return lookup end
end

local function Price(provider, method, ...)
    local lookup = AddonFunction(provider, method)
    if lookup then
        local amount = P.NS.Dispatch(lookup, ...)
        if Positive(amount) then return math.floor(amount) end
    end
end

local function TSMPrice(link)
    local api = Field(_G, "TSM_API")
    local convert = AddonFunction(api, "ToItemString")
    if not convert then return end
    local item = S.PublicText(P.NS.Dispatch(convert, link))
    if item then return Price(api, "GetCustomPriceValue", "DBMarket", item) end
end

function D.AddAuctionPrice(tooltip, entry)
    local link = entry.link
    if not link or entry.bindOnPickUp or entry.notAuctionable then return end
    local price = Price(Field(Field(_G, "AuctionMaster"), "API"), "GetMarketPrice", link)
    local source = "AuctionMaster"
    if not price then
        price = TSMPrice(link)
        source = "TradeSkillMaster"
    end
    if not price then
        price = Price(Field(Field(_G, "AucAdvanced"), "API"), "GetMarketValue", link)
        source = "Auctioneer"
    end
    if not price then
        local api = Field(Field(_G, "Auctionator"), "API")
        price = Price(Field(api, "v1"), "GetAuctionPriceByItemLink", "MSUF Suite", link)
        source = "Auctionator"
    end
    if price then
        tooltip:AddLine(S.Text("Auction price (%s): %s"):format(source, C_CurrencyInfo.GetCoinTextureString(price)))
    end
end

function D.ReadRoll(rollID, durationMilliseconds, now)
    if not Key(rollID) or not S.Finite(now) then return nil end
    local icon, name, count, quality, bind, need, greed, disenchant, _, _, _, _, transmog = GetLootRollItemInfo(rollID)
    name = S.PublicText(name)
    if not name then return nil end
    local remaining = GetLootRollTimeLeft(rollID)
    if S.Finite(remaining) then
        if remaining <= 0 then return nil end
    else
        remaining = durationMilliseconds
    end
    if not Positive(remaining) then return nil end
    local duration = Positive(durationMilliseconds) and durationMilliseconds or remaining
    local entry = {
        rollID = rollID, name = name, link = S.PublicText(GetLootRollItemLink(rollID)), icon = Icon(icon),
        quality = Key(quality) and quality or nil, count = Positive(count) and count or 1,
        bindOnPickUp = True(bind), canNeed = True(need), canGreed = True(greed),
        canDisenchant = True(disenchant), canTransmog = True(transmog),
        endsAt = now + remaining / 1000, duration = duration / 1000,
        counts = Counts(), rollNames = {}, finished = false, status = "waiting",
    }
    Item(entry)
    return entry
end

local function SortPlayers(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    local aRoll, bRoll = a.roll or -1, b.roll or -1
    if aRoll ~= bRoll then return aRoll > bRoll end
    if a.name ~= b.name then return a.name < b.name end
    return a.key < b.key
end

local function ReadParticipants(entry, rolls)
    if not PublicTable(rolls) then return end
    local names = { [0] = {}, {}, {}, {}, {} }
    local players = {}
    for index = 1, math.min(#rolls, MAX_NAMES) do
        local info = rolls[index]
        if PublicTable(info) then
            local player = Player(info)
            local choice = player and player.choice
            if not player then choice = Action(info.state) end
            if player and player.rank then players[#players + 1] = player end
            if choice ~= nil then
                entry.counts[choice] = entry.counts[choice] + 1
                if player then names[choice][#names[choice] + 1] = player.coloredName end
                if True(info.isSelf) then
                    entry.selfChoice = choice
                    if S.Finite(info.roll) then entry.selfRoll = info.roll end
                end
            end
        end
    end
    for choice = 0, 4 do entry.rollNames[choice] = table.concat(names[choice], "\n") end
    table.sort(players, SortPlayers)
    entry.players = players
end

local function ReadStatus(entry, info)
    local winner, leader = info.winner, info.currentLeader
    local result
    if PublicTable(winner) then
        entry.status, entry.finished, result = "winner", true, winner
    elseif True(info.allPassed) then
        entry.status, entry.finished = "allPassed", true
    elseif PublicTable(leader) and S.Public(info.isTied) and info.isTied ~= true then
        entry.status, result = "leader", leader
    end
    if not result then return end
    local player = Player(result)
    entry.statusName = player and player.coloredName
    entry.statusChoice = Action(result.state)
    if S.Finite(result.roll) then entry.statusRoll = result.roll end
    if entry.finished then
        entry.winner = player
        if not player then return end
        for _, participant in ipairs(entry.players or {}) do
            if participant.key == player.key then participant.winner = true end
        end
    end
end

function D.ReadDrop(encounterID, lootKey)
    if not Key(encounterID) or not Key(lootKey) then return nil end
    local info = C_LootHistory.GetSortedInfoForDrop(encounterID, lootKey)
    if not PublicTable(info) then return nil end
    local link = S.PublicText(info.itemHyperlink)
    if not link then return nil end
    local entry = {
        encounterID = encounterID, lootKey = lootKey, link = link,
        counts = Counts(), rollNames = {}, finished = false, status = "waiting",
    }
    if S.Finite(info.startTime) then entry.startedAt = info.startTime end
    if Positive(info.duration) then entry.duration = info.duration end
    Item(entry)
    if not entry.name then entry.name = entry.link end
    ReadParticipants(entry, info.rollInfos)
    entry.selfChoice = Action(info.playerRollState) or entry.selfChoice
    ReadStatus(entry, info)
    return entry
end

local function Clear(out)
    for index = #out, 1, -1 do out[index] = nil end
end

local function DropKey(info)
    local key = info.lootListKey
    if not S.Public(key) then return nil end
    if key == nil then key = info.lootListID end
    if Key(key) then return key end
end

function D.EncounterKeys(encounterID, out)
    Clear(out)
    if not Key(encounterID) then return out end
    local drops = C_LootHistory.GetSortedDropsForEncounter(encounterID)
    if not PublicTable(drops) then return out end
    for index = 1, math.min(#drops, 128) do
        local info = drops[index]
        if PublicTable(info) then
            local key = DropKey(info)
            if key ~= nil then out[#out + 1] = key end
        end
    end
    return out
end

local function InsertEncounter(out, encounterID, startedAt)
    local count = #out
    for index = 1, count do if out[index] == encounterID then return end end
    local position = count + 1
    while position > 1 and encounterTimes[position - 1] < startedAt do position = position - 1 end
    if position > MAX_ENCOUNTERS then return end
    for index = math.min(count + 1, MAX_ENCOUNTERS), position + 1, -1 do
        out[index], encounterTimes[index] = out[index - 1], encounterTimes[index - 1]
    end
    out[position], encounterTimes[position] = encounterID, startedAt
end

function D.EncounterIDs(out)
    Clear(out)
    Clear(encounterTimes)
    local infos = C_LootHistory.GetAllEncounterInfos()
    if not PublicTable(infos) then return out end
    for index = 1, #infos do
        local info = infos[index]
        if PublicTable(info) and Key(info.encounterID) then
            local time = S.Finite(info.startTime) and info.startTime or 0
            InsertEncounter(out, info.encounterID, time)
        end
    end
    return out
end
