local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local Secrets = dofile(root .. "/../MidnightSimpleUnitFrames/tools/tests/classpower_secrets.lua")
Secrets.Install()
Secrets.GUARD_NAMES.falsy.Public = true
local errors, calls, returned, translated = {}, 0, nil, false
local S = {
    Public = function(value) return not issecretvalue(value) end,
    Finite = function(value) return not issecretvalue(value) and type(value) == "number"
        and value == value and value > -math.huge and value < math.huge end,
    PublicText = function(value) return not issecretvalue(value) and type(value) == "string"
        and value ~= "" and value or nil end,
    Dispatch = Support.Dispatcher(errors),
}
function S.Text(value)
    if translated and value == "%s: %d/%d defeated (%s)" then return "%s: %d von %d besiegt (%s)" end
    if translated and value == "Heroic" then return "Heroisch" end
    return value
end
-- Load the real table-field reader, including its treatment of false fields.
MSUFSuite = { Suite = S, Public = S.Public }
assert(loadfile(root .. "/MSUF_Suite_Modules/Surfaces.lua"))("MSUF_Suite_Modules", {})
local function GetProfile(name)
    assert(name == "Darkbloody-Ravencrest", "profile lookup changed the native full name")
    calls = calls + 1
    return returned
end
local function API()
    -- Raider.IO exposes its public API through __index, not raw table fields.
    return setmetatable({}, { __index = { GetProfile = GetProfile },
        __newindex = function() error("provider API was modified") end })
end
RaiderIO = API()
local P = { Suite = S }
local path = root .. "/MSUF_Suite_QualityOfLife/ApplicantRaidProgress.lua"
assert(loadfile(path))("MSUF_Suite_QualityOfLife", P)
assert(calls == 0 and P.ApplicantRaidProgress, "helper queried profiles during load")
local stopWatch = Secrets.Watch(path, { strict = true })
local function Menu(name)
    local entries = {}
    local menu = {
        CreateDivider = function() entries.dividers = (entries.dividers or 0) + 1 end,
        CreateTitle = function(_, value)
            assert(type(value) == "string" and not issecretvalue(value), "non-public menu text")
            entries[#entries + 1] = value
        end,
    }
    P.ApplicantRaidProgress.Populate(menu, name)
    assert(entries[1] == "Raid progress (Raider.IO)", "missing data source header")
    return entries
end
local function Raid(name, bosses, groups)
    return { current = true, isMainProgress = false,
        raid = { name = name, shortName = "TEST", bossCount = bosses }, progress = groups }
end
local function Group(difficulty, kills)
    return { difficulty = difficulty, kills = kills, progress = {}, obsolete = false }
end
local function Profile(rows, outdated)
    return { success = true, raidProfile = { hasRenderableData = true,
        outdated = outdated, raidProgress = rows } }
end
local function Unknown(value)
    returned = value
    local before = calls
    local entries = Menu("Darkbloody-Ravencrest")
    assert(calls == before + 1, "menu did not make exactly one public getter call")
    assert(#entries == 2 and entries[2] == "No current raid data available", "unknown became progress")
end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Copy(child) end
    return result
end
local function Equal(left, right)
    assert(type(left) == type(right), "provider type changed")
    if type(left) ~= "table" then assert(left == right, "provider value changed"); return end
    for key, value in pairs(left) do Equal(value, right[key]) end
    for key, value in pairs(right) do Equal(value, left[key]) end
end

local previous = Raid("Previous", 9, { Group(3, 9) })
previous.current = false
local main = Raid("Main", 8, { Group(3, 8) })
main.isMainProgress = true
local first = Raid("First current raid", 8, { Group(3, 4), Group(1, 8), Group(2, 8) })
local second = Raid("Second current raid", 1, { Group(1, 1), Group(2, 1) })
returned = Profile({ previous, first, main, second })
local before = Copy(returned)
local entries = Menu("Darkbloody-Ravencrest")
assert(calls == 1 and #entries == 3, "current raids were collapsed or main/previous progress leaked")
assert(entries[2] == "First current raid: 4/8 defeated (Mythic)", "highest difficulty was not chosen")
assert(entries[3] == "Second current raid: 1/1 defeated (Heroic)", "second current raid was lost")
Equal(before, returned)
assert(first.progress[1].difficulty == 3, "shared difficulty list was sorted in place")
translated = true
entries = Menu("Darkbloody-Ravencrest")
assert(calls == 2 and entries[3] == "Second current raid: 1 von 1 besiegt (Heroisch)", "format/difficulty bypassed translation")
translated = false

for _, value in ipairs({ false, 7, "bad", Secrets.New("table"), {},
    { raidProfile = Secrets.New("table") }, { raidProfile = { raidProgress = Secrets.New("table") } },
    { raidProfile = { raidProgress = "bad" } }, Profile({ previous, main }), Profile({}) }) do Unknown(value) end
Unknown(nil)
Unknown(Profile({ Raid("Zero", 8, { Group(3, 0), Group(2, 0) }) }))
for _, field in ipairs({ "current", "isMainProgress", "raid", "progress" }) do
    local row = Raid("Hidden", 8, { Group(3, 4) })
    row[field] = Secrets.New((field == "current" or field == "isMainProgress") and "boolean" or "table")
    Unknown(Profile({ row }))
    row[field] = nil
    Unknown(Profile({ row }))
end
for _, bad in ipairs({ -1, 0, 1.5, math.huge, 0/0, "8", Secrets.New("number") }) do
    Unknown(Profile({ Raid("Bad count", bad, { Group(3, 1) }) }))
end
for _, bad in ipairs({ -1, 0, 1.5, 9, math.huge, 0/0, "4", Secrets.New("number") }) do
    Unknown(Profile({ Raid("Bad kills", 8, { Group(3, bad) }) }))
end
for _, bad in ipairs({ -1, 0, 1.5, 4, math.huge, 0/0, "3", Secrets.New("number") }) do
    Unknown(Profile({ Raid("Bad difficulty", 8, { Group(bad, 4) }) }))
end
for _, bad in ipairs({ false, "", 8, Secrets.New("string") }) do
    Unknown(Profile({ Raid(bad, 8, { Group(3, 4) }) }))
end
-- A malformed or secret sibling must not suppress another valid record/group.
returned = Profile({ Secrets.New("table"), Raid("Readable", 8,
    { Secrets.New("table"), Group(4, 8), Group(3, 0), Group(2, 2) }) })
entries = Menu("Darkbloody-Ravencrest")
assert(#entries == 2 and entries[2] == "Readable: 2/8 defeated (Heroic)", "invalid sibling hid public progress")
for _, outdated in ipairs({ 1, 100000 }) do
    returned = Profile({ first }, outdated)
    entries = Menu("Darkbloody-Ravencrest")
    assert(entries[3] == "Raider.IO data may be outdated", "stale data was presented without context")
end
returned = Profile({ first }, 0)
assert(Menu("Darkbloody-Ravencrest")[2] == "First current raid: 4/8 defeated (Mythic)", "zero age was marked stale")
for _, outdated in ipairs({ -1, false, "old", math.huge, 0/0, Secrets.New("number") }) do
    Unknown(Profile({ first }, outdated))
end
for _, api in ipairs({ false, "bad", Secrets.New("table"), {},
    { GetProfile = Secrets.New("function") }, { GetProfile = true } }) do
    RaiderIO = api
    local count = calls
    entries = Menu("Darkbloody-Ravencrest")
    assert(calls == count and entries[2] == "Raider.IO raid data unavailable", "unavailable API was called")
end
RaiderIO = nil
assert(Menu("Darkbloody-Ravencrest")[2] == "Raider.IO raid data unavailable", "missing addon was not explained")
RaiderIO = { GetProfile = function() calls = calls + 1; error("provider failure") end }
local count = calls
entries = Menu("Darkbloody-Ravencrest")
assert(calls == count + 1 and #errors == 1 and entries[2] == "No current raid data available", "provider failure escaped boundary")
RaiderIO = API()
for _, name in ipairs({ false, "", Secrets.New("string") }) do
    count = calls
    assert(Menu(name)[2] == "No current raid data available" and calls == count, "invalid identity reached provider")
end
count = calls
assert(Menu(nil)[2] == "No current raid data available" and calls == count, "missing identity reached provider")
local weak = setmetatable({}, { __mode = "v" })
returned = Profile({ Raid("Transient", 8, { Group(3, 1) }) })
weak[1] = returned
Menu("Darkbloody-Ravencrest")
returned = nil
collectgarbage("collect")
collectgarbage("collect")
assert(weak[1] == nil, "helper retained Raider.IO's shared profile")
local violations = stopWatch()
assert(#violations == 0, table.concat(violations, "\n"))
print("Suite applicant current-character raid progress contract passed")
