local root = assert(arg[1])
local secret = setmetatable({}, {
    __index = function() error("secret table read") end,
    __lt = function() error("secret value compared") end,
})
local inaccessible = setmetatable({}, { __index = function() error("inaccessible table read") end })
local function Public(value) return not rawequal(value, secret) end
local function Finite(value) return Public(value) and type(value) == "number" and value - value == 0 end
local function PublicText(value) if Public(value) and type(value) == "string" and value ~= "" then return value end end
canaccesstable = function(value) return not rawequal(value, inaccessible) end
Enum = {
    UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3 },
    QuestLineFloorLocation = { Above = 0, Below = 1, Same = 2 },
    QuestClassification = { Normal = 1, Campaign = 2, Important = 3 },
}
local called = { request = {}, classification = {}, info = {}, maps = {}, list = 0 }
local maps = {
    [66] = { mapType = 3 }, [67] = { mapType = 3, parentMapID = 66 },
    [68] = { mapType = 3, parentMapID = 67 }, [70] = { mapType = 3 }, [71] = { mapType = 2 },
    [72] = { mapType = 3, parentMapID = secret }, [73] = { mapType = secret }, [74] = inaccessible,
}
local rows, forced, byID = {}, {}, {}
local hidden, completed, story
C_Map = { GetMapInfo = function(id)
    assert(Finite(id))
    called.maps[id] = (called.maps[id] or 0) + 1
    return maps[id]
end }
C_QuestLine = {
    GetAvailableQuestLines = function(map) assert(map == 66 or map == 70); called.list = called.list + 1; return rows end,
    RequestQuestLinesForMap = function(map) called.request[#called.request + 1] = map end,
    GetForceVisibleQuests = function() return forced end,
    GetQuestLineInfo = function(id, map)
        assert(Finite(id) and map == 66)
        called.info[id] = (called.info[id] or 0) + 1
        return byID[id]
    end,
    QuestLineIgnoresAccountCompletedFiltering = function(map, id) assert(map == 66); return id == 102 end,
}
C_Minimap = { IsTrackingHiddenQuests = function() return hidden end,
    IsTrackingAccountCompletedQuests = function() return completed end }
C_CVar = { GetCVarBool = function(name) assert(name == "questPOILocalStory"); return story end }
C_QuestLog = { QuestIgnoresAccountCompletedFiltering = function(id) return id == 12 end }
C_QuestInfoSystem = { GetQuestClassification = function(id)
    called.classification[id] = (called.classification[id] or 0) + 1
    if id == 1 then return 2 end
    if id == 18 then return secret end
    return 1
end }
local private = { Suite = { Public = Public, Finite = Finite, PublicText = PublicText } }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/NavigationHUDQuestOffers.lua"))("Suite", private)
local Offers = assert(private.NavigationHUDQuestOffers)
local output
local function Read(map)
    output = {}
    Offers.Read(output, map or 66, function(list, x, y, label, atlas, kind)
        assert(list == output and Finite(x) and Finite(y) and PublicText(label) and PublicText(atlas) and kind == "questOffer")
        assert(list[label] == nil, "duplicate quest label in test fixture")
        list[label] = { x = x, y = y, atlas = atlas }
    end)
    return output
end
local function Offer(id, changes)
    local row = { questID = id, questName = "Quest " .. id, x = id / 100, y = .6,
        startMapID = 66, floorLocation = 2, isHidden = false, isAccountCompleted = false, isLocalStory = false, inProgress = false }
    for key, value in pairs(changes or {}) do row[key] = value end
    return row
end

local api = C_QuestLine
C_QuestLine = nil
assert(not next(Read()) and #called.request == 0)
C_QuestLine = api
for _, map in ipairs({ -1, 71, 73, 74, secret }) do assert(not next(Read(map))) end
assert(#called.request == 0 and called.list == 0, "unreadable or broad maps queried quest offers")

-- Initial request may yield no data. Ordinary refresh consumes the late data
-- without requesting again. A native request-required edge rearms precisely once.
assert(not next(Read()) and #called.request == 1 and called.request[1] == 66)
rows = {
    Offer(1), Offer(1, { questName = "Duplicate ID", x = .9 }),
    Offer(2, { x = .01 }), Offer(3, { inProgress = true }), Offer(4, { isHidden = true }),
    Offer(5, { isAccountCompleted = true }), Offer(6, { isLocalStory = true }),
    Offer(7, { floorLocation = 0 }), Offer(8, { startMapID = 67 }),
    Offer(9, { startMapID = 68 }), Offer(10, { startMapID = 70 }), Offer(11, { startMapID = 72 }),
    Offer(12, { isAccountCompleted = true }), Offer(13, { isAccountCompleted = true, questLineID = 102 }),
    Offer(14, { isHidden = secret }), Offer(15, { x = secret }), Offer(16, { questID = secret }),
    Offer(17, { x = 1.001 }), Offer(18), Offer(19, { startMapID = 68 }),
    Offer(20, { questName = secret }), secret, inaccessible,
}
forced = { 1, 21, 21, 22, 22, 23, secret }
byID[23] = Offer(25)
byID[21] = Offer(21)
byID[22] = Offer(22, { floorLocation = 1 })
local initial = Read()
assert(#called.request == 1 and initial["Quest 1"].atlas == "Quest-Campaign-Available")
assert(initial["Quest 8"] and initial["Quest 9"] and initial["Quest 19"], "same-floor child maps should match")
assert(called.maps[68] == 1, "child-map ancestry was walked twice")
assert(initial["Quest 12"] and initial["Quest 13"] and initial["Quest 18"].atlas == "QuestNormal" and initial["Quest 21"])
assert(called.info[1] == nil and called.info[21] == 1 and called.info[22] == 1, "force-visible repeated a known quest")
assert(called.classification[1] == 1 and called.classification[2] == nil)
for _, id in ipairs({ 2, 3, 4, 5, 6, 7, 10, 11, 14, 15, 16, 17, 20, 22, 25 }) do
    assert(not initial["Quest " .. id], "invalid quest survived: " .. id)
end
assert(not initial["Duplicate ID"])

hidden, completed, story = true, true, true
local switched = Read()
assert(switched["Quest 4"] and switched["Quest 5"] and switched["Quest 6"], "user's native tracking flags were ignored")
hidden, completed, story = secret, secret, secret
switched = Read()
assert(not switched["Quest 4"] and not switched["Quest 5"] and not switched["Quest 6"], "secret preferences enabled filtered offers")
Offers.Invalidate()
Read()
Read()
assert(#called.request == 2)
rows, forced = {}, {}
Read(70)
Read(66)
assert(#called.request == 4 and called.request[3] == 70 and called.request[4] == 66)
for id = 1, 130 do rows[id] = Offer(id, { x = id / 1000 }) end
local bounded = Read()
assert(bounded["Quest 128"] and not bounded["Quest 129"], "a quest-offer refresh exceeded its API list limit")
print("Navigation HUD quest offers passed")
