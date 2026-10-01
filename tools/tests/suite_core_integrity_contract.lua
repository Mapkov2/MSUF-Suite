-- Saved data integrity of the Suite core (MSUF_Suite/Core): normalization
-- never keeps the modules or the profile listener from starting, imports and
-- copies take what they should, and the controller never hands out a table a
-- setter could write into by mistake. Real core files in TOC order.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

-- The client's securecallfunction reports an error and returns nothing.
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2, table.maxn(results))
end
local function Reported(text)
    for _, message in ipairs(reported) do
        if message:find(text, 1, true) then return true end
    end
    return false
end
MSUF_NS = {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
InCombatLockdown = function() return false end
Minimap = { SetMaskTexture = Noop }
UnitGUID = function() return "Player-1" end
CreateFrame = function()
    return { SetScript = Noop, RegisterEvent = Noop, UnregisterEvent = Noop, UnregisterAllEvents = Noop }
end
-- No module addon is installed: every module reports itself unavailable.
C_AddOns = { IsAddOnLoaded = function() return false end, DoesAddOnExist = function() return false end,
    GetAddOnEnableState = function() return 0 end, LoadAddOn = Noop }

-- Loads the core in TOC order through ProfileVariants.lua; before(file, ns)
-- runs ahead of each file.
local function LoadCore(before)
    local ns = {}
    for _, file in ipairs(Support.TocFiles(root, "MSUF_Suite")) do
        if file:match("%.lua$") then
            if before then before(file, ns) end
            assert(loadfile(root .. "/MSUF_Suite/" .. file))("MSUF_Suite", ns)
        end
        if file == "Core/ProfileVariants.lua" then break end
    end
    return ns
end

------------------------------------------------------------------ S1.3
-- A raising migration step, repair or prepareConfig is reported; the rest of
-- the normalization, the profile listener and every module start still run.
do
    local Suite = LoadCore(function(file, ns)
        if file == "Core/Suite.lua" then
            -- MIGRATIONS and REPAIRS take their functions when Suite.lua loads.
            ns.MoveRunRecordsToCharacter = function() error("migration step failed") end
            ns.NameplateStyle.RepairGeometry = function() error("repair failed") end
        end
    end)
    local S = Suite.Suite
    S.catalog.dataTexts.prepareConfig = function() error("prepare failed") end
    local profile = { suite = { schema = 1, revision = 0, modules = {
        objectives = { backgroundOpacity = 82 }, minimap = { enabled = "yes" }, dataTexts = { enabled = 7 },
    } } }
    S.Normalize(profile)
    local modules = profile.suite.modules
    Check(Reported("migration step failed") and Reported("repair failed") and Reported("prepare failed"),
        "a raising normalization step was not reported")
    Check(modules.objectives.backgroundOpacity == 0, "the steps before a raising one did not run")
    Check(profile.suite.revision == S.MigrationRevision - 1,
        "a raising step did not hold the revision before it: " .. tostring(profile.suite.revision))
    Check(modules.minimap.enabled == S.catalog.minimap.rules.enabled.default
        and modules.dataTexts.enabled == S.catalog.dataTexts.rules.enabled.default,
        "the catalog rules did not repair the settings after a raising step")

    Suite.RootDB = { schema = 1, activeProfile = "Main", profiles = { Main = profile } }
    Suite.DB = profile
    reported = {}
    S.Start()
    Check(S.started and Reported("migration step failed"), "the start did not normalize the active profile")
    Check(S.states.minimap.unavailable ~= nil and S.states.dataTexts.unavailable ~= nil,
        "a raising normalization kept the modules from starting")
    S.states.minimap.error = "Stopped after an error"
    Suite.Registry.NotifyListeners("profile", "Main")
    Check(S.states.minimap.error == nil, "a raising normalization kept the profile listener from starting")
end

print("Suite core integrity: " .. checks .. " checks passed")
