local _, P = ...
if not P.NS.Client.isForever then return end

-- Base and Camelot skill lines and map IDs: Wago DB2 exports for 1.60.1.71091.
-- Trainer/district and secondary rank records: Warcraft Tavern's Forever
-- trainer lists, ForeverDB NPC records and Wowhead's Forever profession guides.
local Data = { recipes = P.ProfessionHintRecipes }
P.ProfessionHintData = Data

Data.baseSkillLines = {
    [2937] = 171, [2938] = 164, [2939] = 185, [2940] = 333, [2941] = 202, [2942] = 129,
    [2943] = 356, [2944] = 182, [2945] = 165, [2946] = 186, [2947] = 393, [2948] = 197,
}

Data.mapNames = {
    [1411] = "Durotar", [1412] = "Mulgore", [1413] = "The Barrens", [1416] = "Alterac Mountains",
    [1417] = "Arathi Highlands", [1418] = "Badlands", [1419] = "Blasted Lands", [1420] = "Tirisfal Glades",
    [1421] = "Silverpine Forest", [1422] = "Western Plaguelands", [1423] = "Eastern Plaguelands",
    [1424] = "Hillsbrad Foothills", [1425] = "The Hinterlands", [1426] = "Dun Morogh", [1427] = "Searing Gorge",
    [1428] = "Burning Steppes", [1429] = "Elwynn Forest", [1431] = "Duskwood", [1432] = "Loch Modan",
    [1433] = "Redridge Mountains", [1434] = "Stranglethorn Vale", [1435] = "Swamp of Sorrows", [1436] = "Westfall",
    [1437] = "Wetlands", [1438] = "Teldrassil", [1439] = "Darkshore", [1440] = "Ashenvale",
    [1441] = "Thousand Needles", [1442] = "Stonetalon Mountains", [1443] = "Desolace", [1444] = "Feralas",
    [1445] = "Dustwallow Marsh", [1446] = "Tanaris", [1447] = "Azshara", [1448] = "Felwood",
    [1449] = "Un'Goro Crater", [1450] = "Moonglade", [1451] = "Silithus", [1452] = "Winterspring",
    [1453] = "Stormwind City", [1454] = "Orgrimmar", [1455] = "Ironforge", [1456] = "Thunder Bluff",
    [1457] = "Darnassus", [1458] = "Undercity", [2482] = "Mount Hyjal", [2521] = "Zephras Isle",
    [2548] = "Riverglades",
}

local starters = { 1429, 1411, 1426, 1420, 1412, 1438, 2521 }
-- Minimum effective skill, item ID, cold-cache name, and suitable zone maps.
-- Herb/ore requirements agree with the Suite's gathering tooltip data. Zone
-- choices were built from Forever object locations and verified fishing/skinning areas.
Data.gathering = {
    [182] = {
        { 1, 2447, "Peacebloom", starters },
        { 15, 2449, "Earthroot", { 1429, 1426, 1411, 1438, 1420, 1412 } },
        { 50, 785, "Mageroyal", { 1439, 1413, 1436, 1432, 1421 } },
        { 70, 2450, "Briarthorn", { 1439, 1413, 1440, 1431, 1436, 1421 } },
        { 100, 2453, "Bruiseweed", { 1440, 1442, 1431, 1437, 1424 } },
        { 125, 3356, "Kingsblood", { 1437, 1424, 1440, 1442, 1431 } },
        { 150, 3357, "Liferoot", { 1437, 1434, 1445, 1424 } },
        { 170, 3821, "Goldthorn", { 1417, 1434, 1445, 1425 } },
        { 185, 3358, "Khadgar's Whisker", { 1425, 1434, 1444, 1435 } },
        { 205, 4625, "Firebloom", { 1446, 1427, 1419, 1428 } },
        { 230, 8838, "Sungrass", { 1425, 1444, 1447, 1419 } },
        { 250, 8846, "Gromsblood", { 1448, 1419, 1443, 1440 } },
        { 270, 13463, "Dreamfoil", { 1449, 1447, 1451, 1448, 1423 } },
        { 285, 13466, "Plaguebloom", { 1423, 1422, 1448 } },
        { 290, 13467, "Icecap", { 1452 } },
    },
    [186] = {
        { 1, 2770, "Copper Ore", { 1426, 1411, 1429, 1420, 1412, 1439, 1413, 2521 } },
        { 65, 2771, "Tin Ore", { 1432, 1413, 1439, 1433, 1421, 1442 } },
        { 125, 2772, "Iron Ore", { 1417, 1418, 1441, 1443, 1434 } },
        { 175, 3858, "Mithril Ore", { 1418, 1425, 1427, 1446, 1447, 1448 } },
        { 245, 10620, "Thorium Ore", { 1449, 1452, 1428, 1427, 1451 } },
        { 275, 10620, "Thorium Ore", { 1452, 1423, 1449, 1451, 1428 } },
    },
    [356] = {
        { 1, nil, nil, starters },
    },
    [393] = {
        { 1, nil, nil, starters },
        { 50, nil, nil, { 1436, 1439, 1413, 1421, 1432 } },
        { 100, nil, nil, { 1437, 1424, 1413, 1431, 1440 } },
        { 125, nil, nil, { 1437, 1431, 1441, 1424, 1434 } },
        { 150, nil, nil, { 1417, 1443, 1434, 1441, 1445 } },
        { 200, nil, nil, { 1434, 1418, 1444, 1445, 1446 } },
        { 225, nil, nil, { 1444, 1446, 1425, 1449 } },
        { 250, nil, nil, { 1449, 1447, 1448, 1422, 1428 } },
        { 275, nil, nil, { 1452, 1449, 1423, 1451 } },
    },
}

-- Map, NPC, faction, district and acquisition.
local A, H = "Alliance", "Horde"
local herbs = {
    { 1453, "Tannysa", A, "Mage Quarter" }, { 1454, "Jandi", H, "The Drag" },
    { 1455, "Reyna Stonebranch", A, "The Great Forge" }, { 1458, "Martha Alliestar", H, "The Apothecarium" },
    { 1457, "Firodren Mooncaller", A, "Temple Gardens" }, { 1456, "Komin Winterhoof", H, "Middle Rise" },
    { 1440, "Cylania Rootstalker", A, "Silverwind Refuge" }, { 1444, "Ruw", H, "Camp Mojache" },
    { 1434, "Flora Silverwind", nil, "Booty Bay" }, { 1450, "Malvor", nil, "Nighthaven" },
}
local mining = {
    { 1455, "Geofram Bouldertoe", A, "The Great Forge" }, { 1454, "Makaru", H, "Valley of Honor" },
    { 1453, "Gelman Stonehand", A, "Dwarven District" }, { 1458, "Brom Killian", H, "The War Quarter" },
    { 1432, "Brock Stoneseeker", A, "Thelsamar" }, { 1456, "Brek Stonehoof", H, "Middle Rise" },
    { 1439, "Kurdram Stonehammer", A, "Auberdine" }, { 1446, "Pikkle", nil, "Gadgetzan" },
}
local skinning = {
    { 1453, "Maris Granger", A, "Old Town" }, { 1454, "Thuwd", H, "The Drag" },
    { 1455, "Balthus Stoneflayer", A, "The Great Forge" }, { 1456, "Mooranta", H, "Middle Rise" },
    { 1457, "Eladriel", A, "Craftsmen's Terrace" }, { 1458, "Killian Hagey", H, "Rogues' Quarter" },
    { 1440, "Jayla", A, "Silverwind Refuge" }, { 1413, "Dranh", H, "Camp Taurajo" },
}
local aidBookVendors = {
    { 1417, "Deneb Walker", A, "Stromgarde Keep", "book" },
    { 1445, "Balai Lok'Wein", H, "Brackenwall Village", "book" },
}

-- Vendor stock from the Forever first aid records and Wowhead's Forever
-- item records. Recipes without a specific destination use the client's source.
Data.recipeVendors = {
    [7929] = aidBookVendors,
    [10840] = aidBookVendors,
    [18417] = { { 1452, "Qia", nil, "Everlook" } },
}

Data.training = {
    [129] = {
        [75] = {
            { 1453, "Shaina Fuller", A, "Cathedral Square" }, { 1454, "Arnok", H, "Valley of Spirits" },
            { 1455, "Nissa Firestone", A, "The Great Forge" }, { 1458, "Mary Edras", H, "Rogues' Quarter" },
        },
        [150] = aidBookVendors,
        [225] = {
            { 1445, "Doctor Gustaf VanHowzen", A, "Theramore Isle", "quest" },
            { 1417, "Doctor Gregory Victor", H, "Hammerfall", "quest" },
        },
    },
    [164] = {
        [75] = {
            { 1455, "Rotgath Stonebeard", A, "The Great Forge" }, { 1454, "Snarl", H, "Valley of Honor" },
            { 1453, "Therum Deepforge", A, "Dwarven District" }, { 1456, "Karn Stonehoof", H, "Middle Rise" },
        },
        [150] = {
            { 1455, "Bengus Deepforge", A, "The Great Forge" }, { 1454, "Saru Steelfury", H, "Valley of Honor" },
            { 1416, "Alard Schmied", A, "Dalaran" },
        },
        [225] = { { 1434, "Brikk Keencraft", nil, "Booty Bay" } },
    },
    [165] = {
        [75] = {
            { 1453, "Simon Tanner", A, "Old Town" }, { 1454, "Karolek", H, "The Drag" },
            { 1455, "Fimble Finespindle", A, "The Great Forge" }, { 1456, "Tarn", H, "Middle Rise" },
        },
        [150] = { { 1457, "Telonis", A, "Craftsmen's Terrace" }, { 1456, "Una", H, "Middle Rise" } },
        [225] = { { 1425, "Drakk Stonehand", A, "Aerie Peak" }, { 1444, "Hahrana Ironhide", H, "Camp Mojache" } },
    },
    [171] = {
        [75] = {
            { 1453, "Lilyssia Nightbreeze", A, "Mage Quarter" }, { 1454, "Yelmak", H, "The Drag" },
            { 1455, "Tally Berryfizz", A, "Tinker Town" }, { 1458, "Doctor Marsh", H, "The Apothecarium" },
        },
        [150] = {
            { 1457, "Ainethil", A, "Craftsmen's Terrace" },
            { 1458, "Doctor Herbert Halsey", H, "The Apothecarium" },
        },
        [225] = {
            { 1444, "Kylanna Windwhisper", A, "Feathermoon Stronghold" }, { 1435, "Rogvar", H, "Stonard" },
            { 1448, "Master Mycologist Shurome", nil, "Emerald Sanctuary" },
        },
    },
    [182] = { [75] = herbs, [150] = herbs, [225] = herbs },
    [185] = {
        [75] = {
            { 1453, "Stephen Ryback", A, "Old Town" }, { 1454, "Zamja", H, "The Drag" },
            { 1455, "Daryl Riknussun", A, "The Great Forge" }, { 1456, "Aska Mistrunner", H, "Middle Rise" },
        },
        [150] = {
            { 1440, "Shandrina", A, "Silverwind Refuge", "book" },
            { 1443, "Wulan", H, "Shadowprey Village", "book" },
        },
        [225] = { { 1446, "Dirge Quikcleave", nil, "Gadgetzan", "quest" } },
    },
    [186] = { [75] = mining, [150] = mining, [225] = mining },
    [197] = {
        [75] = {
            { 1453, "Sellandus", A, "Mage Quarter" }, { 1454, "Magar", H, "The Drag" },
            { 1455, "Jormund Stonebrow", A, "The Great Forge" }, { 1458, "Rhiannon Davis", H, "Magic Quarter" },
        },
        [150] = {
            { 1453, "Georgio Bolero", A, "Mage Quarter" }, { 1458, "Josef Gregorian", H, "Magic Quarter" },
        },
        [225] = {
            { 1445, "Timothy Worthington", A, "Theramore Isle" }, { 1424, "Daryl Stack", H, "Tarren Mill" },
        },
    },
    [202] = {
        [75] = {
            { 1455, "Trixie Quikswitch", A, "Tinker Town" }, { 1454, "Nogg", H, "Valley of Honor" },
            { 1453, "Lilliam Sparkspindle", A, "Dwarven District" },
            { 1458, "Franklin Lloyd", H, "Rogues' Quarter" },
        },
        [150] = {
            { 1455, "Springspindle Fizzlegear", A, "Tinker Town" }, { 1454, "Roxxik", H, "Valley of Honor" },
        },
        [225] = {
            { 1446, "Buzzek Bracketswing", nil, "Gadgetzan" }, { 2482, "Kaylaena Springwhisper" },
        },
    },
    [333] = {
        [75] = {
            { 1453, "Lucan Cordell", A, "Mage Quarter" }, { 1454, "Godan", H, "The Drag" },
            { 1455, "Gimble Thistlefuzz", A, "The Great Forge" }, { 1458, "Lavinia Crowe", H, "The Apothecarium" },
        },
        [150] = {
            { 1429, "Kitta Firewind", A, "Tower of Azora" }, { 1442, "Hgarth", H, "Sun Rock Retreat" },
            { 2548, "Melanie Sable", A, "Farholde Keep" },
        },
        [225] = { { 1418, "Annora", nil, "Uldaman" } },
    },
    [356] = {
        [75] = {
            { 1453, "Arnold Leland", A, "Trade District" }, { 1454, "Lumak", H, "Valley of Honor" },
            { 1455, "Grimnur Stonebrand", A, "Forlorn Cavern" }, { 1458, "Armand Cromwell", H, "Magic Quarter" },
        },
        [150] = { { 1434, "Old Man Heming", nil, "Booty Bay", "book" } },
        [225] = { { 1445, "Nat Pagle", nil, "Tidefury Cove", "quest" } },
    },
    [393] = { [75] = skinning, [150] = skinning, [225] = skinning },
}
