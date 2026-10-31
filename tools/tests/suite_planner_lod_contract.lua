-- Real Core, shared runtime, Options and standalone Planner TOCs. The optional
-- QoL addon is deliberately unavailable throughout this boot.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local host = root .. "/../MidnightSimpleUnitFrames"
assert(flavor == "Mainline" or flavor == "Forever")
local checks = 0
local function Check(value, message) assert(value, message) checks = checks + 1 end
local function Read(path)
    local file = assert(io.open(path, "rb"), path)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end
local manifest = Read(root .. "/MSUF_Suite_AdventurePlanner/MSUF_Suite_AdventurePlanner_Mainline.toc")
Check(manifest:find("## LoadOnDemand: 1", 1, true), "Planner is not load on demand")
Check(manifest:find("## Dependencies: MSUF_Suite, MSUF_Suite_Modules", 1, true), "Planner dependencies differ")
Check(not manifest:find("SavedVariables", 1, true), "a second SavedVariables owner would reload stored data")
Check(not manifest:find("MSUF_Suite_QualityOfLife", 1, true), "Planner still requires the QoL addon")
Check(not Read(root .. "/MSUF_Suite_QualityOfLife/MSUF_Suite_QualityOfLife_Mainline.toc"):find("Planning", 1, true),
    "QoL still loads Planner code")

local World = assert(loadfile(host .. "/tools/tests/client_world.lua"))()
local world = World.New(host, flavor)
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "host boot failed: " .. tostring(failure and failure.message))
local env, M = world.env, world.core.MSUF2
env.InCombatLockdown = function() return false end
env.UnitAffectingCombat = function() return false end
env.C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
local loaded = { MidnightSimpleUnitFrames = true, MidnightSimpleUnitFrames_Options = true }
local counts, namespaces = {}, {}
local function Load(addon)
    if loaded[addon] then return true end
    counts[addon] = (counts[addon] or 0) + 1
    Check(addon ~= "MSUF_Suite_QualityOfLife", "standalone Planner loaded the QoL addon")
    local namespace = {}
    namespaces[addon] = namespace
    for line in Read(root .. "/" .. addon .. "/" .. addon .. "_Mainline.toc"):gmatch("[^\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local ok, why = world:LoadFile(root .. "/" .. addon .. "/" .. line:gsub("\\", "/"), addon, namespace)
            Check(ok, addon .. "/" .. line .. ": " .. tostring(why))
        end
    end
    loaded[addon] = true
    return true
end
env.C_AddOns = {
    GetAddOnMetadata = function() return nil end,
    GetAddOnEnableState = function() return 2 end,
    GetNumAddOns = function() return 0 end,
    IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
    DoesAddOnExist = function(name)
        return name == "MSUF_Suite" or name == "MSUF_Suite_Modules"
            or name == "MSUF_Suite_Options" or name == "MSUF_Suite_AdventurePlanner"
    end,
    LoadAddOn = function(name)
        if name == "MSUF_Suite_QualityOfLife" then error("QoL load attempted") end
        if name == "MSUF_Suite_Modules" or name == "MSUF_Suite_Options" or name == "MSUF_Suite_AdventurePlanner" then
            return Load(name)
        end
        return false, "MISSING"
    end,
}
Load("MSUF_Suite")
local NS = assert(env.MSUFSuite)
Check(NS.Database.Initialize(nil), "Suite database did not initialize")
local S = NS.Suite
for _, id in ipairs(S.order) do S.Config(id).enabled = false end
S.Config("planningTools").weekly = false -- no capture timer is needed to exercise addon ownership
local previous = { name = "Prior - Realm", character = "Prior", level = 90, ilvl = 731.5, money = 670010000 }
local account = { characters = { previous = previous }, windowScale = .83, overviewFolded = { vault = true } }
NS.RootDB.suitePlanning = account
env.UnitGUID = function() return "Player-Current" end
local notes = { ["42"] = { label = "Dungeon", text = "[x] Saved task", instanceID = 42 } }
local character = { notes = notes, loadouts = { sentinel = true }, attempts = {}, runNotes = { ["7"] = "Saved run note" } }
local history = { history = { { historyID = 7, recordedAt = 100, level = 12, subtitle = "Saved run" } } }
NS.RootDB.suiteCharacters = { ["Player-Current"] = { planning = character, runSummary = history } }
S.Start()
Check(S.started, "Suite controller did not start")
Check(S.catalog.planningTools.addon == "MSUF_Suite_AdventurePlanner", "catalog still routes Planner to QoL")
Check(S.PlanningTools == nil and S.instances.planningTools == nil, "disabled Planner performed a cold load")
Check(not loaded.MSUF_Suite_Modules and not loaded.MSUF_Suite_AdventurePlanner, "disabled Planner loaded a runtime")
Check(S.Availability("planningTools"), "QoL absence made standalone Planner unavailable")

local opened
env.MSUF2_Open = function(page) opened = page return true end
env.SlashCmdList.MSUFPLANNER()
Check(opened == "suite_planningTools", "cold slash command did not route to Planner settings")
Check(loaded.MSUF_Suite_Options and NS.Menu.attached, "real Suite Options did not attach")
Check(M.pages.suite_planningTools ~= nil, "real Options loader did not register Planner page")
Check(S.PlanningTools == nil and not loaded.MSUF_Suite_AdventurePlanner, "cold settings open enabled the Planner")
Check(not loaded.MSUF_Suite_QualityOfLife, "cold settings open loaded QoL")

Check(S.Set("planningTools", "enabled", true), "standalone Planner enable failed")
Check(S.states.planningTools.active and S.instances.planningTools.active, "standalone Planner did not become active")
Check(counts.MSUF_Suite_Modules == 1 and counts.MSUF_Suite_AdventurePlanner == 1,
    "Planner did not load exactly its shared runtime and own addon")
Check(not loaded.MSUF_Suite_QualityOfLife and S.LoadoutReminder == nil, "Planner depends on QoL registration")
local Plan = assert(S.PlanningTools)
Check(Plan.Account() == account and account.characters.previous == previous, "LoD activation replaced account data")
Check(previous.money == 670010000 and previous.ilvl == 731.5, "LoD activation changed another character's values")
Check(Plan.Character() == character and Plan.Bucket("notes") == notes, "character planning namespace changed")
Check(S.CharacterData("runSummary") == history and Plan.History.Runs("")[1].note == "Saved run note",
    "saved runs or run notes moved to a new namespace")
Check(Plan.Notes.Rows(false)[1].note == notes["42"], "saved notes no longer resolve")
Check(account.windowScale == .83 and account.overviewFolded.vault, "LoD activation reset window preferences")
Check(namespaces.MSUF_Suite_AdventurePlanner.NS == NS, "Planner Bootstrap bound a different Suite owner")
Check(namespaces.MSUF_Suite_AdventurePlanner.GroupFinderFilters == nil, "Planner retained private QoL bindings")

if flavor == "Mainline" then
    env.C_SpecializationInfo = { GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 71, "Arms" end }
    env.C_ClassTalents = { GetStarterBuildActive = function() return false end,
        GetLastSelectedSavedConfigID = function() return 101 end, GetActiveConfigID = function() return 99 end }
    env.C_Traits = { GetConfigInfo = function() return { name = "Saved build" } end }
    env.GetLootSpecialization = function() return 0 end
    env.C_EquipmentSet = { GetEquipmentSetIDs = function() return {} end }
    local current = Plan.Loadouts.Current()
    Check(current and current.config == 101 and current.build == "Saved build" and current.loot == 71,
        "Planner loadouts require the optional reminder")
    Check(S.LoadoutReminder == nil, "shared snapshot silently loaded the reminder")
    local eligible, applied = 0, 0
    local helper = { active = true, config = S.Config("groupFinderTools"), Refresh = function() end,
        CanApplyFilters = function() eligible = eligible + 1 return true end,
        ApplyFilters = function() applied = applied + 1 return true end }
    helper.config.enabled, helper.config.filters = true, true
    S.instances.groupFinderTools, S.states.groupFinderTools.active = helper, true
    env.GetLFGRoles = function() return false, false, false, true end
    env.UnitGetAvailableRoles = function() return false, false, true end
    env.SetLFGRoles = function() end
    Check(Plan.LFG.Save("Standalone"), "standalone workspace save failed")
    Check(Plan.LFG.Apply("Standalone") and eligible == 1 and applied == 1,
        "workspace did not use the active helper's public filter operations")
    helper.active = false
    Check(not Plan.LFG.Apply("Standalone"), "inactive optional helper was used")
else
    Check(Plan.Loadouts.Current() == nil and not Plan.LFG.Save("Unavailable"),
        "Forever exposed Retail-only planner helpers")
end

Check(S.Set("planningTools", "enabled", false), "Planner disable failed")
Check(not S.states.planningTools.active and Plan.Account() == account and Plan.Character() == character,
    "Planner disable discarded records")
Check(S.Set("planningTools", "enabled", true), "Planner re-enable failed")
Check(counts.MSUF_Suite_AdventurePlanner == 1 and counts.MSUF_Suite_Modules == 1,
    "re-enable reloaded already registered addons")
Check(not loaded.MSUF_Suite_QualityOfLife, "standalone lifecycle loaded QoL")
Check(account.characters.previous == previous and character.notes == notes and character.runNotes["7"] == "Saved run note",
    "standalone lifecycle changed preserved records")
print("Standalone Planner LoD: " .. checks .. " checks passed (" .. flavor .. ")")
