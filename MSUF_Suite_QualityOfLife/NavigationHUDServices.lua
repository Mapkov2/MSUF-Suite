local _, private = ...
local NS, S = private.NS, private.Suite
local Services = {}
private.NavigationHUDServices = Services

local MAIL = { function() return S.Text("Mailbox") end, "ui-hud-minimap-mail-icon", "mailbox" }
local AUCTION = { function() return S.Text("Auction House") end, "coin-gold", "service" }
local BANK = { function() return S.Text("Bank") end, "coin-silver", "service" }
local INN = { function() return S.Text("Innkeeper") end, "poi-traveldirections-arrow", "service" }
local CLASS = { function() return S.Text("Class trainer") end, "Professions-Icon-Customer", "service" }
local PROFESSION = { function() return S.Text("Profession trainer") end, "Professions_Recipe_Active", "service" }
local ALLIANCE, HORDE = "Alliance", "Horde"

-- Individual sites observed in WoW Forever. Each city provides its own
-- UIMapID and QuestieDB AreaID. Nearby mail observations on NPC pages
-- refer to the mailbox location, independently of the NPC's location.
local MAPS = {
    [1437] = {
        { .11, .60, MAIL }, -- https://guide.wow4ever.se/en/objects/142094
    },
    [1453] = { area = 1519, faction = ALLIANCE,
        { .50, .87, MAIL }, -- https://guide.wow4ever.se/en/objects/696271
        { .62, .76, MAIL }, -- https://guide.wow4ever.se/en/npc/6740
        { .61, .71, AUCTION, 15659 }, -- https://guide.wow4ever.se/en/npc/15659
        { .60, .75, INN, 6740, "Allison" }, -- https://guide.wow4ever.se/en/npc/6740
        { .50, .50, CLASS, 5491, "Arthur the Faithful" }, -- https://guide.wow4ever.se/en/npc/5491
        { .55, .69, PROFESSION, 5493, "Arnold Leland" }, -- https://guide.wow4ever.se/en/npc/5493
    },
    [1454] = { area = 1637, faction = HORDE,
        { .54, .66, MAIL }, -- https://guide.wow4ever.se/en/npc/5611
        { .49, .71, MAIL }, -- https://guide.wow4ever.se/en/npc/3319
        { .54, .69, INN, 6929, "Gryshka" }, -- https://guide.wow4ever.se/en/npc/6929
        { .39, .37, CLASS, 3344, "Kardris Dreamseeker" }, -- https://guide.wow4ever.se/en/npc/3344
        { .73, .26, PROFESSION, 3357, "Makaru" }, -- https://guide.wow4ever.se/en/npc/3357
    },
    [1455] = { area = 1537, faction = ALLIANCE,
        { .32, .66, MAIL }, -- https://guide.wow4ever.se/en/objects/650593
        { .24, .72, AUCTION, 8671, "Auctioneer Buckler" }, -- https://guide.wow4ever.se/en/npc/8671
        { .35, .59, BANK, 2460 }, -- https://guide.wow4ever.se/en/npc/2460
        { .21, .52, MAIL }, -- https://guide.wow4ever.se/en/npc/5111
        { .19, .52, INN, 5111, "Firebrew" }, -- https://guide.wow4ever.se/en/npc/5111
        { .66, .89, CLASS, 5114, "Bilban Tosslespanner" }, -- https://guide.wow4ever.se/en/npc/5114
        { .40, .33, PROFESSION, 6291, "Balthus Stoneflayer" }, -- https://guide.wow4ever.se/en/npc/6291
    },
    [1456] = { area = 1638, faction = HORDE,
        { .47, .59, BANK, 8357 }, -- https://guide.wow4ever.se/en/npc/8357
        -- EG Link location matches the separate Forever Scout mailbox observation.
        { .45, .59, MAIL }, -- https://guide.wow4ever.se/en/objects/143985
        { .46, .64, INN, 6746, "Pala" }, -- https://guide.wow4ever.se/en/npc/6746
        { .22, .19, CLASS, 3032, "Beram Skychaser" }, -- https://guide.wow4ever.se/en/npc/3032
        { .50, .40, PROFESSION, 3013, "Komin Winterhoof" }, -- https://guide.wow4ever.se/en/npc/3013
    },
    [1457] = { area = 1657, faction = ALLIANCE,
        { .42, .42, MAIL }, -- https://guide.wow4ever.se/en/npc/4208
        { .67, .16, INN, 6735, "Saelienne" }, -- https://guide.wow4ever.se/en/npc/6735
        { .35, .08, CLASS, 4218, "Denatharion" }, -- https://guide.wow4ever.se/en/npc/4218
        { .45, .79, PROFESSION, 4204, "Firodren Mooncaller" }, -- https://guide.wow4ever.se/en/npc/4204
    },
    [1458] = { area = 1497, faction = HORDE,
        { .72, .61, MAIL }, -- https://guide.wow4ever.se/en/npc/4591
        { .68, .38, INN, 6741, "Norman" }, -- https://guide.wow4ever.se/en/npc/6741
        { .48, .16, CLASS, 4594, "Angela Curthas" }, -- https://guide.wow4ever.se/en/npc/4594
        { .56, .37, PROFESSION, 4598, "Brom Killian" }, -- https://guide.wow4ever.se/en/npc/4598
    },
}

local Finite, Public = S.Finite, S.Public
local PROVIDER = "QuestieDB"
-- Only accept a spawn within ten map percentage points of the independent
-- observation. A record from a different phase or coordinate frame can differ.
local MAX_DISTANCE_SQUARED, MAX_SPAWNS = .01, 16
local provider, providerLoaded, providerNPCs
local serviceCache = {}

local function Table(value)
    return Public(value) and type(value) == "table" and canaccesstable(value)
end

local function Method(owner, key)
    local callback = Table(owner) and owner[key]
    if Public(callback) and type(callback) == "function" then return callback end
end

-- QuestieDB's named getters are bounded by the NPC IDs above. Its name
-- index, full database and source-shaped support tables are never needed.
-- https://github.com/Questie/QuestieDB/blob/9cf27d6491dd80f1998aa0a846dbea9a3c5daad9/docs/api.md
local function GetProvider(db)
    local requireContract = Method(db, "RequireContract")
    if not requireContract then return end
    local accepted = requireContract(1)
    if not Public(accepted) or accepted ~= true then return end
    local mode = db.readMode
    if not Public(mode) then return end
    if mode == "baked" then
        -- This is the selected flavor in the provider's own baked TOC.
        local flavor = C_AddOns.GetAddOnMetadata(PROVIDER, "X-Flavor")
        if not Public(flavor) or flavor ~= "Forever" then return end
    elseif mode == "source" then
        local getStatus = Method(db.ModeIndicator, "GetStatus")
        local status = getStatus and getStatus()
        local flavor = Table(status) and status.expansion
        if not Public(flavor) or flavor ~= "Forever" then return end
    else
        return
    end
    local npc = db.Npc
    if Method(npc, "spawns") and Method(npc, "name") then return npc end
end

local function RefreshProvider()
    local db = _G.LibQuestieDB
    if not Table(db) then db = nil end
    local loaded = db and NS.Client.IsAddOnLoaded(PROVIDER)
    if db == provider and loaded == providerLoaded then return end
    provider, providerLoaded = db, loaded
    providerNPCs = loaded and S.Dispatch(GetProvider, db)
    wipe(serviceCache)
end

local function ClosestSpawn(spawns, x, y)
    if not Table(spawns) then return end
    local best, bestX, bestY = MAX_DISTANCE_SQUARED
    local count = #spawns
    if not Finite(count) then return end
    for index = 1, math.min(count, MAX_SPAWNS) do
        local spawn = spawns[index]
        if Table(spawn) then
            local px, py = spawn[1], spawn[2]
            if Finite(px) and Finite(py) and px >= 0 and px <= 100 and py >= 0 and py <= 100 then
                px, py = px / 100, py / 100
                local distance = (px - x) ^ 2 + (py - y) ^ 2
                if distance <= best then best, bestX, bestY = distance, px, py end
            end
        end
    end
    return bestX, bestY
end

local function ReadService(row, area)
    local id = row[4]
    local spawns = providerNPCs.spawns(id)
    local x, y = ClosestSpawn(Table(spawns) and spawns[area], row[1], row[2])
    if not x then return end
    return { x, y, S.PublicText(providerNPCs.name(id)) }
end

local function ReadProvider(row, area)
    if not providerNPCs then return end
    local result = serviceCache[row]
    if result == nil then
        result = S.Dispatch(ReadService, row, area) or false
        serviceCache[row] = result
    end
    return result
end

function Services.Read(output, mapID, add, useQuestieDB)
    if not NS.Client.isForever or not Finite(mapID) then return end
    local map = MAPS[mapID]
    if not map then return end
    local faction = map.faction and S.PublicText(UnitFactionGroup("player"))
    if map.faction and faction ~= map.faction then return end
    if useQuestieDB and map.area then RefreshProvider() end
    for _, row in ipairs(map) do
        local kind = row[3]
        local point = useQuestieDB and row[4] and ReadProvider(row, map.area)
        local x, y = row[1], row[2]
        if point then x, y = point[1], point[2] end
        local name = point and point[3]
        local label
        if row[5] then
            label = ("%s (%s)"):format(name or row[5], kind[1]())
        else
            label = name or kind[1]()
        end
        add(output, x, y, label, kind[2], kind[3])
    end
end
