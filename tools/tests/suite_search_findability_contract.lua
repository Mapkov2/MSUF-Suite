-- Suite options are found in MSUF's menu search by the name a player sees.
--
-- Boots the sibling Classic MSUF checkout's real core, Options and search layer
-- (its tools/tests/client_world.lua) and loads MSUF_Suite and MSUF_Suite_Options
-- into the same client, like suite_search_provider_contract.lua. Then:
--   * every Suite row whose shown name no other search record shares is in the
--     first six results (the dropdown shows six) when that name is typed;
--   * controls that once had no row are found by name: the chat timestamps, the
--     addon-button arrangement, the potion map, the bag gold reset, the action bar
--     switches and the cooldown manager's per-spell options;
--   * exact names the host's control boost used to bury stay on top (a section,
--     an FAQ question), and labels the parser rewrites ("global cooldown",
--     "interrupt is ready") are still found;
--   * rows of controls a client never builds stay out (WoW Forever: the Mainline
--     consumables of Buff Reminders, the Mythic+ run history).
--   lua suite_search_findability_contract.lua <suiteRoot> [Mainline|Forever]
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local classic = root .. "/../MidnightSimpleUnitFrames-Classic"
local flavor = arg[2] or "Mainline"
assert(flavor == "Mainline" or flavor == "Forever", "the Suite supports Retail and WoW Forever only")

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local function Read(path)
    local file = assert(io.open(path, "rb"), "cannot open " .. path)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

------------------------------------------------------------------ one client, both addons
local World = assert(loadfile(classic .. "/tools/tests/client_world.lua"),
    "the Classic MSUF checkout is required next to the Suite (" .. classic .. ")")()
local world = World.New(classic, flavor)
world:Boot()
local failure = world:FirstFailure()
assert(failure == nil, "MSUF did not boot: " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
local env = world.env
local M = world.core.MSUF2
M.frame = { IsShown = function() return true end }
env.InCombatLockdown = function() return false end
env.UnitAffectingCombat = function() return false end
env.C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
-- The Bags module needs Blizzard's combined bags.
local getCVar = env.C_CVar.GetCVar
env.C_CVar.GetCVar = function(name) if name == "combinedBags" then return "1" end return getCVar(name) end
local loaded ={ MidnightSimpleUnitFrames = true, MidnightSimpleUnitFrames_Options = true }
env.C_AddOns = {
    GetAddOnMetadata = function() return nil end,
    IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
    DoesAddOnExist = function(name) return name:find("^MSUF_Suite") ~= nil end,
    GetAddOnEnableState = function() return 2 end,
    LoadAddOn = function() return false, "MISSING" end,
    GetNumAddOns = function() return 0 end,
}
local function LoadAddOn(addon, namespace)
    for line in Read(root .. "/" .. addon .. "/" .. addon .. "_Mainline.toc"):gmatch("[^\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local ok, message = world:LoadFile(root .. "/" .. addon .. "/" .. line:gsub("\\", "/"), addon, namespace)
            assert(ok, addon .. "/" .. line .. ": " .. tostring(message))
        end
    end
    loaded[addon] = true
end
LoadAddOn("MSUF_Suite", {})
local Suite = env.MSUFSuite
assert(Suite.Database.Initialize(nil), "Suite test profile did not initialize")
for _, id in ipairs(Suite.SuiteOrder) do Suite.Suite.Config(id).enabled = true end
local P = {}
LoadAddOn("MSUF_Suite_Options", P)
for _, feature in ipairs(P.QualityOfLifeSearchFeatures or {}) do
    Suite.Suite.Config(feature.id)[feature.switch] = true
end
P.InvalidateSearch()
local api = M.Search._CoreAPI
local PALETTE = 6

local function Rank(query, wanted)
    local rows = api.SearchPages(query)
    for i = 1, #rows do
        if wanted(rows[i]) then return i, rows end
    end
    return nil, rows
end
local function Got(rows)
    local got = {}
    for i = 1, math.min(4, #rows) do got[#got + 1] = tostring(rows[i].key) .. ":" .. tostring(rows[i].label) end
    return table.concat(got, ", ")
end

------------------------------------------------------------------ every uniquely named Suite row
local rows = P.SearchRows()
local Normalize = M.Search.Text.NormalizeSearchText
local byName = {}
for _, rec in ipairs(api.GetSearchRecords()) do
    local name = Normalize(rec.label or "")
    byName[name] = (byName[name] or 0) + 1
end
local tested, missed = 0, {}
for _, row in ipairs(rows) do
    local name = row.label and Normalize(row.label) or ""
    if name ~= "" and byName[name] == 1 then
        tested = tested + 1
        local rank = Rank(row.label, function(rec) return rec.key == row.pageKey and rec.label == row.label end)
        if not rank or rank > PALETTE then
            missed[#missed + 1] = string.format("%s \"%s\" (%s)", row.pageKey, row.label, rank and ("rank " .. rank) or "not found")
        end
    end
end
Check(tested > 800, flavor .. ": only " .. tested .. " uniquely named Suite rows")
if #missed > 0 then
    Check(false, flavor .. ": " .. #missed .. " uniquely named Suite options miss the first " .. PALETTE
        .. " results for their own name, e.g. " .. table.concat(missed, "; ", 1, math.min(8, #missed)))
end

------------------------------------------------------------------ named cases
local function HasRow(pageKey, label)
    for _, row in ipairs(rows) do
        if row.pageKey == pageKey and row.label == label then return true end
    end
    return false
end
local function Expect(query, pageKey, label, limit)
    if not Check(HasRow(pageKey, label), flavor .. ": no search row for " .. pageKey .. " \"" .. label .. "\"") then return end
    local rank, results = Rank(query, function(rec) return rec.key == pageKey and rec.label == label end)
    Check(rank and rank <= limit, string.format("%s: \"%s\" ranks %s \"%s\" at %s, want <= %d (got %s)",
        flavor, query, pageKey, label, tostring(rank), limit, Got(results)))
end
Expect("Timestamps (Blizzard setting)", "suite_chat", "Timestamps (Blizzard setting)", 1)
Expect("arrange addon buttons", "suite_minimap", "Arrange individual addon buttons", 1)
Expect("Add this map to the potion maps", "suite_buffReminders", "Add this map to the potion maps", 1)
Expect("Clear saved character gold", "suite_bags", "Clear saved character gold", PALETTE)
Expect("pet bar", "suite_actionbars", "Pet bar", 1)
Expect("stance bar", "suite_actionbars", "Stance bar", 1)
Expect("sound when ready", "suite_cooldownManager", "Sound when ready", 1)
Expect("Say the name when ready", "suite_cooldownManager", "Say the name when ready", 1)
Expect("Copy to all specs", "suite_cooldownManager", "Copy to all specs", 1)
Expect("When to show", "suite_buffReminders", "When to show", 1)
Expect("Move selected bar", "suite_actionbars", "Move selected bar", 1)
Expect("Where are the nameplate settings?", "suite_nameplates", "Where are the nameplate settings?", 1)
Expect("Where is the cooldown manager?", "suite_cooldownManager", "Where is the cooldown manager?", 2)
if HasRow("suite_qualityOfLife", "Global cooldown") then
    Expect("Global cooldown", "suite_qualityOfLife", "Global cooldown", 1)
end
local interruptLabel = "Mark interruptible casts while your interrupt is ready"
if HasRow("suite_qualityOfLife", interruptLabel) then Expect(interruptLabel, "suite_qualityOfLife", interruptLabel, 1) end

------------------------------------------------------------------ only controls this client builds
local modern = P.Requires.modernEquipment and P.Requires.modernEquipment()
local mythicPlus = P.catalog.runSummary and P.catalog.runSummary.rules.showMythicPlus ~= nil
for _, row in ipairs(rows) do
    if row.suiteRuleKey == "autoFlask" then
        Check(modern, flavor .. ": a Buff Reminders consumable rule is searchable where the page never builds it")
    end
    if row.label == "Clear run history" then
        Check(mythicPlus, flavor .. ": Clear run history is searchable where the button never exists")
    end
end

if #failures > 0 then
    error("suite_search_findability_contract failed:\n  " .. table.concat(failures, "\n  "))
end
print(string.format("suite_search_findability_contract: ok (%s, %d uniquely named Suite options in the first %d)",
    flavor, tested, PALETTE))
