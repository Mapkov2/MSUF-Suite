local root = assert(arg[1], "repository root required")

local function SecretAccess()
    error("secret value was used")
end

local secret = setmetatable({}, {
    __index = SecretAccess, __newindex = SecretAccess, __eq = SecretAccess,
    __lt = SecretAccess, __le = SecretAccess, __add = SecretAccess, __sub = SecretAccess,
    __concat = SecretAccess, __tostring = SecretAccess,
})

local function Public(value) return not rawequal(value, secret) end
local function Finite(value)
    return Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
local function PublicText(value)
    if Public(value) and type(value) == "string" and value ~= "" then return value end
end

local DPS, HPS, OTHER = 1, 3, 4
local FIRST, SECOND = 14, 15
local Alice, TwinA, TwinB, UnknownRate = "Player-1-01", "Player-1-02", "Player-1-03", "Player-1-04"
local locked = false
local D = { M = {}, perSecond = { [DPS] = true, [HPS] = true }, Clock = function() return "1:05" end }
local S = {
    Public = Public, Finite = Finite, PublicText = PublicText,
    BlizzardText = function(_, fallback) return fallback end,
}
local NS = { IsCombatLocked = function() return locked end }
local private = { DamageMeter = D, NS = NS, Suite = S }

local function Player(guid, name, rate, localPlayer)
    return {
        sourceGUID = guid, name = name, amountPerSecond = rate, classFilename = "MAGE",
        isLocalPlayer = localPlayer, specIconID = secret,
    }
end

local function Spell(id, rate) return { spellID = id, amountPerSecond = rate } end

local segments = {
    { sessionID = FIRST, name = "First boss", durationSeconds = 65 },
    { sessionID = secret, name = "Hidden segment" },
    { sessionID = SECOND, name = secret, durationSeconds = secret },
    secret,
}
local players = {
    [FIRST] = { combatSources = {
        Player(Alice, "Alice", 40, true),
        Player(TwinA, "Twin", 20),
        Player(UnknownRate, "Unknown rate", secret),
        Player("Player-1-05", secret, 50),
        Player(secret, "Secret GUID", 99),
        Player("Creature-1-01", "Creature", 200),
        secret,
    } },
    [SECOND] = { combatSources = {
        Player(Alice, "Renamed", 64, true),
        Player(TwinB, "Twin", 80),
        Player(UnknownRate, "Unknown rate", 12),
    } },
}
local spells = {
    [FIRST] = { [Alice] = { combatSpells = { Spell(3, 10), Spell(3, 15), Spell(5, 20) } },
        [TwinA] = { combatSpells = { Spell(3, 20) } } },
    [SECOND] = { [Alice] = { combatSpells = { Spell(3, 24), Spell(7, 40) } } },
}
local calls = { segments = 0, players = 0, spells = 0 }
local currentType
C_DamageMeter = {
    GetAvailableCombatSessions = function()
        calls.segments = calls.segments + 1
        return segments
    end,
    GetCombatSessionFromID = function(id, meterType)
        assert(Public(id) and Public(meterType), "secret session argument")
        calls.players, currentType = calls.players + 1, meterType
        return players[id]
    end,
    GetCombatSessionSourceFromID = function(id, meterType, guid, creature)
        assert(Public(id) and Public(meterType) and Public(guid) and creature == nil, "invalid source argument")
        calls.spells, currentType = calls.spells + 1, meterType
        return spells[id][guid]
    end,
}

assert(loadfile(root .. "/MSUF_Suite_DamageMeter/PullCompareData.lua"))("MSUF_Suite_DamageMeter", private)
assert(calls.segments + calls.players + calls.spells == 0, "comparison read data during module load")

local list = assert(D.CompareSegments())
assert(#list == 2 and list[1].id == SECOND and list[1].label == "Fight 15", "latest readable ID was not first")
assert(list[2].id == FIRST and list[2].label == "First boss [1:05]", "segment lost its name or duration")
assert(calls.segments == 1, "segment picker made extra native reads")

local rows = assert(D.ComparePlayers(FIRST, SECOND, DPS))
assert(#rows == 4 and rows[1].guid == TwinB and rows[1].rateA == nil and rows[1].rateB == 80,
    "missing side, creature or unreadable identity was treated as known")
assert(rows[2].guid == Alice and rows[2].name == "Alice" and rows[2].class == "MAGE" and rows[2].localPlayer
    and rows[2].rateA == 40 and rows[2].rateB == 64, "player was not joined by GUID across a name change")
assert(rows[3].guid == TwinA and rows[3].rateB == nil, "two players with the same name were merged")
assert(rows[4].guid == UnknownRate and rows[4].hasA and rows[4].rateA == nil and rows[4].rateB == 12,
    "a protected rate was used as zero or lost the source identity")
assert(calls.players == 2 and calls.spells == 0, "player list read a session more than once or fetched spells")

local details = assert(D.CompareSpells(FIRST, SECOND, HPS, rows[2]))
assert(calls.spells == 2 and currentType == HPS, "spell details did not read both selected HPS sources once")
assert(#details == 3 and details[1].spellID == 7 and details[1].rateA == 0 and details[1].rateB == 40,
    "missing A spell was not zero in a fully readable source")
assert(details[3].spellID == 3 and details[3].rateA == 25 and details[3].rateB == 24,
    "duplicate native spell rows were not aggregated by ID")
assert(details[2].spellID == 5 and details[2].rateA == 20 and details[2].rateB == 0,
    "spell list lost the B-side zero or did not sort by largest change")

details = assert(D.CompareSpells(FIRST, SECOND, DPS, rows[3]))
assert(calls.spells == 3 and #details == 1 and details[1].rateB == nil,
    "absent player side performed a read or was shown as zero")

spells[FIRST][Alice].combatSpells[2] = Spell(secret, 15)
details = assert(D.CompareSpells(FIRST, SECOND, DPS, rows[2]))
assert(#details == 2 and details[1].spellID == 7 and details[1].rateA == nil and details[2].rateA == nil,
    "incomplete spell source contributed a partial rate or a false zero")
spells[FIRST][Alice] = secret
spells[SECOND][Alice].combatSpells[1] = Spell(3, secret)
assert(D.CompareSpells(FIRST, SECOND, DPS, rows[2]) == nil, "unreadable sources produced a comparison")

local function AssertNoReads()
    local total = calls.segments + calls.players + calls.spells
    assert(D.CompareSegments() == nil and D.ComparePlayers(FIRST, SECOND, DPS) == nil
        and D.CompareSpells(FIRST, SECOND, DPS, rows[2]) == nil, "comparison stayed available during combat")
    assert(total == calls.segments + calls.players + calls.spells, "blocked comparison touched the native API")
end

D.M.inCombat = true
AssertNoReads()
D.M.inCombat, locked = false, true
AssertNoReads()
locked = false
local before = calls.players
assert(D.ComparePlayers(FIRST, FIRST, DPS) == nil and D.ComparePlayers(FIRST, SECOND, OTHER) == nil
    and D.ComparePlayers(FIRST, secret, DPS) == nil, "comparison accepted invalid selection")
assert(calls.players == before, "invalid selection made native reads")

players[SECOND] = { combatSources = secret }
assert(D.ComparePlayers(FIRST, SECOND, HPS) == nil and currentType == HPS and calls.players == before + 2,
    "unreadable HPS session produced a partial result")
players[SECOND] = nil
assert(D.ComparePlayers(FIRST, SECOND, DPS) == nil and calls.players == before + 4,
    "expired session was replaced with a different native fight")
segments = secret
assert(D.CompareSegments() == nil, "protected session list was indexed")

print("Suite damage meter pull comparison data contract passed")
