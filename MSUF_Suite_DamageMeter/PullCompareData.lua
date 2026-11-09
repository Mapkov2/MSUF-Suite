local _, P = ...
local D, S, NS = P.DamageMeter, P.Suite, P.NS
local M, Public, PublicText, Finite = D.M, S.Public, S.PublicText, S.Finite
local abs, max = math.abs, math.max
local EMPTY = {}

-- Comparison consumes plain copies of completed native sessions on demand.
-- Combat events, timer ticks and the regular meter repaint never call these readers.
local function Locked()
    return M.inCombat or NS.IsCombatLocked()
end

local function ReadableTable(value)
    return Public(value) and type(value) == "table"
end

local function Count(list)
    if not ReadableTable(list) then return nil end
    local count = #list
    if Finite(count) then return count end
end

function D.CompareSegments()
    if Locked() then return nil end
    local native = C_DamageMeter.GetAvailableCombatSessions()
    local count = Count(native)
    if not count then return nil end
    local segments = {}
    for i = count, 1, -1 do
        local entry = native[i]
        if ReadableTable(entry) and Finite(entry.sessionID) then
            local id = entry.sessionID
            local name = PublicText(entry.name) or S.BlizzardText("DAMAGE_METER_COMBAT_NUMBER", "Fight %d"):format(id)
            local seconds = entry.durationSeconds
            local label = Finite(seconds) and seconds > 0 and ("%s [%s]"):format(name, D.Clock(seconds)) or name
            segments[#segments + 1] = { id = id, label = label }
        end
    end
    return segments
end

local function Rate(value)
    if Finite(value) and value >= 0 then return value end
end

local function AddPlayers(players, byGUID, id, meterType, presentKey, rateKey)
    local session = C_DamageMeter.GetCombatSessionFromID(id, meterType)
    if not ReadableTable(session) then return false end
    local sources = session.combatSources
    local count = Count(sources)
    if not count then return false end
    for i = 1, count do
        local source = sources[i]
        local guid = ReadableTable(source) and PublicText(source.sourceGUID)
        if guid and guid:sub(1, 7) == "Player-" then
            local row = byGUID[guid]
            if not row then
                row = { guid = guid }
                byGUID[guid] = row
                players[#players + 1] = row
            end
            row.name = row.name or PublicText(source.name)
            row.class = row.class or PublicText(source.classFilename)
            local isLocal = source.isLocalPlayer
            row.localPlayer = row.localPlayer or (Public(isLocal) and isLocal == true)
            if row[presentKey] ~= nil then
                -- A duplicate source would make its rate and drill-down ambiguous.
                row[presentKey], row[rateKey] = false, nil
            else
                row[presentKey] = true
                row[rateKey] = Rate(source.amountPerSecond)
            end
        end
    end
    return true
end

local function TopRate(row)
    return max(row.rateA or 0, row.rateB or 0)
end

local function ByPlayerRate(a, b)
    local aRate, bRate = TopRate(a), TopRate(b)
    if aRate ~= bRate then return aRate > bRate end
    if a.name ~= b.name then return a.name < b.name end
    return a.guid < b.guid
end

local function CanCompare(idA, idB, meterType)
    return not Locked() and Finite(idA) and Finite(idB) and idA ~= idB
        and Finite(meterType) and D.perSecond[meterType] == true
end

function D.ComparePlayers(idA, idB, meterType)
    if not CanCompare(idA, idB, meterType) then return nil end
    local players, byGUID = {}, {}
    if not AddPlayers(players, byGUID, idA, meterType, "hasA", "rateA")
        or not AddPlayers(players, byGUID, idB, meterType, "hasB", "rateB") then return nil end
    local count = 0
    for i = 1, #players do
        local row = players[i]
        if row.name and (row.rateA ~= nil or row.rateB ~= nil) then
            count = count + 1
            players[count] = row
        end
    end
    for i = #players, count + 1, -1 do players[i] = nil end
    table.sort(players, ByPlayerRate)
    return players
end

local function ReadSpells(id, meterType, guid)
    local source = C_DamageMeter.GetCombatSessionSourceFromID(id, meterType, guid, nil)
    if not ReadableTable(source) then return nil end
    local spells = source.combatSpells
    local count = Count(spells)
    if not count then return nil end
    local rates = {}
    for i = 1, count do
        local spell = spells[i]
        if not ReadableTable(spell) then return nil end
        local spellID, rate = spell.spellID, Rate(spell.amountPerSecond)
        if not Finite(spellID) or spellID < 0 or not rate then return nil end
        local sum = (rates[spellID] or 0) + rate
        if not Finite(sum) then return nil end
        rates[spellID] = sum
    end
    return rates
end

local function SpellChange(row)
    if row.rateA and row.rateB then return abs(row.rateB - row.rateA) end
    return TopRate(row)
end

local function BySpellChange(a, b)
    local aChange, bChange = SpellChange(a), SpellChange(b)
    if aChange ~= bChange then return aChange > bChange end
    return a.spellID < b.spellID
end

function D.CompareSpells(idA, idB, meterType, player)
    if not player or not CanCompare(idA, idB, meterType) then return nil end
    local a = player.hasA and ReadSpells(idA, meterType, player.guid)
    local b = player.hasB and ReadSpells(idB, meterType, player.guid)
    if not a and not b then return nil end
    local spells = {}
    -- A missing spell counts as zero only on a side we could enumerate in full.
    for spellID, rate in pairs(a or EMPTY) do
        spells[#spells + 1] = { spellID = spellID, rateA = rate, rateB = b and (b[spellID] or 0) or nil }
    end
    for spellID, rate in pairs(b or EMPTY) do
        if not a or a[spellID] == nil then
            spells[#spells + 1] = { spellID = spellID, rateA = a and 0 or nil, rateB = rate }
        end
    end
    table.sort(spells, BySpellChange)
    return spells
end
