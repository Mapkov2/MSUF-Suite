local root = assert(arg[1])
local secret, inaccessible = {}, {}
local playerFaction, flavor, loaded = "Alliance", "Forever", false
local checks, names, lookups = 0, 0, 0
local function Public(value) return value ~= secret end
local function Finite(value) return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge end
local locale = {
    Mailbox = "Briefkasten",
    ["Auction House"] = "Auktionshaus",
    Bank = "Bank",
    Innkeeper = "Gastwirt",
    ["Class trainer"] = "Klassenlehrer",
    ["Profession trainer"] = "Berufslehrer",
}
local private = {
    NS = { Client = { isForever = true, IsAddOnLoaded = function(name)
        assert(name == "QuestieDB")
        return loaded
    end } },
    Suite = {
        Public = Public,
        Finite = Finite,
        PublicText = function(value) return Public(value) and type(value) == "string" and value or nil end,
        Text = function(key) return assert(locale[key]) end,
        Dispatch = function(fn, ...) return fn(...) end,
    },
}

function UnitFactionGroup(unit)
    assert(unit == "player")
    return playerFaction
end
function canaccesstable(value) return value ~= inaccessible end
function wipe(table)
    for key in pairs(table) do table[key] = nil end
end
C_AddOns = { GetAddOnMetadata = function(name, key)
    assert(name == "QuestieDB" and key == "X-Flavor")
    return flavor
end }

assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/NavigationHUDServices.lua"))("MSUF_Suite_QualityOfLife", private)
local read = private.NavigationHUDServices.Read
local function Add(output, x, y, label, atlas, kind)
    output[#output + 1] = { x = x, y = y, label = label, atlas = atlas, kind = kind }
end
local useQuestieDB = false
local function Read(mapID)
    local output = {}
    read(output, mapID, Add, useQuestieDB)
    return output
end

local ironforge = Read(1455)
assert(#ironforge == 7 and ironforge[1].x == .32 and ironforge[1].y == .66)
assert(ironforge[1].kind == "mailbox" and ironforge[1].label == "Briefkasten" and ironforge[1].atlas == "ui-hud-minimap-mail-icon")
assert(ironforge[2].kind == "service" and ironforge[2].label == "Auctioneer Buckler (Auktionshaus)" and ironforge[2].x == .24)
assert(ironforge[3].label == "Bank" and ironforge[3].x == .35)
assert(ironforge[5].label == "Firebrew (Gastwirt)")
assert(ironforge[6].label == "Bilban Tosslespanner (Klassenlehrer)")
assert(ironforge[7].label == "Balthus Stoneflayer (Berufslehrer)")
assert(#Read(1437) == 1)
local function CheckCapital(mapID, inn, trainer, profession, mailCount)
    local counts = {}
    for _, point in ipairs(Read(mapID)) do
        counts[point.label] = (counts[point.label] or 0) + 1
        assert(point.kind == "mailbox" or point.kind == "service")
    end
    assert(counts.Briefkasten == mailCount)
    assert(counts[inn .. " (Gastwirt)"] == 1)
    assert(counts[trainer .. " (Klassenlehrer)"] == 1)
    assert(counts[profession .. " (Berufslehrer)"] == 1)
end
CheckCapital(1453, "Allison", "Arthur the Faithful", "Arnold Leland", 2)
CheckCapital(1455, "Firebrew", "Bilban Tosslespanner", "Balthus Stoneflayer", 2)
CheckCapital(1457, "Saelienne", "Denatharion", "Firodren Mooncaller", 1)
assert(#Read(1456) == 0 and #Read(0) == 0 and #Read(secret) == 0)
playerFaction = "Horde"
assert(#Read(1455) == 0 and Read(1456)[1].x == .47 and Read(1456)[2].x == .45)
CheckCapital(1454, "Gryshka", "Kardris Dreamseeker", "Makaru", 2)
CheckCapital(1456, "Pala", "Beram Skychaser", "Komin Winterhoof", 1)
CheckCapital(1458, "Norman", "Angela Curthas", "Brom Killian", 1)
playerFaction = secret
assert(#Read(1455) == 0)
playerFaction = "Alliance"
private.NS.Client.isForever = false
assert(#Read(1455) == 0)
private.NS.Client.isForever = true

local function DB(mode, supported)
    return {
        RequireContract = function(version)
            assert(version == 1)
            checks = checks + 1
            return supported
        end,
        readMode = mode,
        ModeIndicator = { GetStatus = function() return { expansion = flavor } end },
        Npc = {
            name = function(id)
                names = names + 1
                if id == 8671 then return "Auktionator Buckler" end
                if id == 5111 then return "Schankwirt Feuerbräu" end
                assert(id == 6291)
                return secret
            end,
            spawns = function(id)
                lookups = lookups + 1
                if id == 8671 then
                    return { [1537] = { inaccessible, { secret, 72 }, { 80, 80 }, { 25.5, 71.5 }, { 24.1, 72.1 } } }
                elseif id == 2460 then
                    return { [1537] = { { 87, 90 }, { 1 / 0, 50 } }, [1519] = { { 35, 59 } } }
                elseif id == 5111 then
                    return { [1537] = { { 19.2, 51.8 } } }
                elseif id == 6291 then
                    return { [1537] = { { 40.3, 33.1 } } }
                end
                assert(id == 5114)
            end,
        },
    }
end

LibQuestieDB = DB("baked", true)
local providerX, providerY = 24.1 / 100, 72.1 / 100
assert(Read(1455)[2].x == .24 and checks == 0 and lookups == 0)
loaded = true
assert(Read(1455)[2].x == .24 and checks == 0 and lookups == 0, "the disabled provider was still consulted")
useQuestieDB = true
ironforge = Read(1455)
assert(ironforge[2].x == providerX and ironforge[2].y == providerY and ironforge[2].label == "Auktionator Buckler (Auktionshaus)")
assert(ironforge[3].x == .35 and ironforge[3].label == "Bank")
assert(ironforge[5].label == "Schankwirt Feuerbräu (Gastwirt)")
assert(ironforge[7].label == "Balthus Stoneflayer (Berufslehrer)")
assert(Read(1455)[2].x == providerX and checks == 1 and lookups == 5 and names == 3)

flavor = "Vanilla"
LibQuestieDB = DB("baked", true)
assert(Read(1455)[2].x == .24 and checks == 2 and lookups == 5)
assert(Read(1455)[2].x == .24 and checks == 2 and lookups == 5)
LibQuestieDB = DB("source", true)
assert(Read(1455)[2].x == .24 and checks == 3 and lookups == 5)
flavor = "Forever"
LibQuestieDB = DB("source", false)
assert(Read(1455)[2].x == .24 and checks == 4 and lookups == 5)
LibQuestieDB = DB("source", true)
assert(Read(1455)[2].x == providerX and checks == 5 and lookups == 10)
LibQuestieDB = inaccessible
assert(Read(1455)[2].x == .24 and checks == 5 and lookups == 10)

useQuestieDB = false
assert(Read(1455)[2].x == .24 and checks == 5 and lookups == 10, "a disabled provider still affected the service layer")
print("suite navigation HUD services contract passed")
