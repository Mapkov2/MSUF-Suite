local root = assert(arg[1])
local baseline = arg[2] == "baseline"
Enum = { ReputationSortType = { None = 0 } }
GetTime = function() return 1 end
local secret = {}
canaccesstable = function(t) return t ~= secret end
local complete = { "Home", "Hidden", "Last" }
local sort, reads, writes, incomplete = 2, 0, 0
local byIDReads, reversed = 0
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local ns = {
    Public = function(value) return value ~= secret end,
    Number = function(value) return type(value) == "number" and value or nil end,
    String = function(value) return type(value) == "string" and value or nil end,
    Host = { Client = { isForever = true } },
    Suite = {
        Dispatch = function(fn, ...) return fn(...) end,
        Finish = function(fn, ...) fn(...); return true end,
    },
}
local function Visible()
    if reversed and sort ~= 0 then return { complete[3], complete[1] } end
    return sort == 0 and complete or { complete[1], complete[3] }
end
local ids = { Home = 1, Hidden = 2, Last = 3, New = 4 }
C_Reputation = {
    GetReputationSortType = function() return sort end,
    SetReputationSortType = function(value) sort, writes = value, writes + 1 end,
    GetSelectedFaction = function() return 0 end,
    GetNumFactions = function() return #Visible() end,
    GetFactionDataByIndex = function(i)
        reads = reads + 1
        local name = Visible()[i]
        local result = { name = name, factionID = ids[name], isHeader = false, isCollapsed = false,
            currentStanding = ids[name] * 10, reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 3000 }
        if i == 2 and incomplete then
            local field = incomplete
            incomplete = nil
            if field == "missing row" then return nil end
            if field == "restricted row" then return secret end
            result[field] = secret
        end
        return result
    end,
    GetFactionDataByID = function(id)
        byIDReads = byIDReads + 1
        return { factionID = id, currentStanding = id * 10 }
    end,
}
-- A ScrollBox post-hook may publish plausible but unrelated rows after native updates.
ReputationFrame = setmetatable({}, { __index = function() error("read someone else's display projection") end })
assert(loadfile(root .. "/MSUF_Suite_CharacterPanel/ReputationList.lua"))("MSUF_Suite_CharacterPanel", ns)
local state = {}
local function Open(expectedReads)
    local oldSort = sort
    reads, writes = 0, 0
    ns.ReputationList.Rows(state)
    assert(sort == oldSort and writes == (sort == 0 and 0 or 2), "changed the native filter")
    local keys = {}
    for i, name in ipairs(Visible()) do keys[i] = ids[name] .. ":" .. name .. "+" end
    if type(state.visible) == "table" then
        assert(#state.visible == #keys * 3)
        for i, name in ipairs(Visible()) do
            local index = (i - 1) * 3
            assert(state.visible[index + 1] == ids[name] and state.visible[index + 2] == name and state.visible[index + 3] == false)
        end
    else
        assert(state.visible == table.concat(keys, "\031"), "wrong native structure after a scan")
    end
    local expected = baseline and #complete + #Visible() or expectedReads
    assert(reads == expected, ("expected %d native row reads, got %d"):format(expected, reads))
end
Open(5)
complete[#complete + 1] = "New"
Open(6)
assert(state.ids[4] and state.rows[4].name == "New", "missed a faction gained behind the filter while closed")
sort = 0
Open(4)
for _, field in ipairs({ "name", "factionID", "isCollapsed" }) do
    incomplete = field
    Open(5)
end
for _, field in ipairs({ "missing row", "restricted row" }) do
    incomplete = field
    Open(8)
end
if baseline then return end
sort = 2
Open(6)
assert(ns.ReputationList.Update(state, "UPDATE_FACTION"))
writes, reads = 0, 0
ns.ReputationList.Rows(state)
assert(reads == 2 and writes == 0 and byIDReads == 2, "reread a visible standing or missed a hidden one")
for i, info in ipairs(state.rows) do assert(state.progress[i].currentStanding == info.factionID * 10) end
incomplete = "currentStanding"
byIDReads = 0
assert(ns.ReputationList.Update(state, "MAJOR_FACTION_RENOWN_LEVEL_CHANGED"))
ns.ReputationList.Rows(state)
assert(byIDReads == 3 and state.progress[3].currentStanding == 30, "restricted native standing skipped the by-ID fallback")
-- A real change to order at the same count still takes the full transaction.
reversed = true
assert(ns.ReputationList.Update(state, "MAJOR_FACTION_RENOWN_LEVEL_CHANGED"))
ns.ReputationList.Rows(state)
assert(writes == 2 and state.rows[1].name == "Home" and state.rows[3].name == "Last")
print("Fresh native rows, complete filtered reopen, transient missing rows and restricted fields passed")
