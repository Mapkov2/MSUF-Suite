local root = assert(arg[1], "repository root required")
local now, epoch, checks = 100, 0, 0
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = Copy(entry) end
    return result
end
GetTime = function() return now end
local suiteRoot = { activeProfile = "Default", skinEnabled = true,
    profiles = { Default = { suite = { modules = {} } } } }
local skinRoot = { activeProfile = "Default", profiles = { Default = { accent = 1 } } }
MSUFSuite = {
    RootDB = suiteRoot, DB = suiteRoot.profiles.Default,
    Database = { ROOT_SETTINGS = { "activeProfile", "skinEnabled" },
        PROFILE_SETTINGS = { "modules" }, PROFILE_LAYOUT_STATE = {},
        GetActiveProfileName = function() return suiteRoot.activeProfile end,
        IsProfileName = function(name) return type(name) == "string" end },
    HostBridge = { Menu2 = function() return {} end, ProfileWorkbench = function() end }, SuiteCatalog = {}, SuiteOrder = {},
    ProfileVariants = { BaseSettings = function() return Copy(suiteRoot.profiles.Default.suite) end,
        LiftOverlay = function() return false end, Register = function() end },
    CopyValue = Copy, IsCombatLocked = function() return false end,
    Skin = { enabled = true }, Registry = { AddListener = function() end },
    Suite = { Normalize = function() end, ApplyAll = function() end },
    ProfileIO = { PrepareTable = function(value) return Copy(value) end },
    OnProfileChanged = function() end,
}
MSUF2 = { Widgets = {}, Theme = {} }
MapkoSkin = { addonName = "MSUF_Suite_Skin", Database = {
    GetRoot = function() return skinRoot end,
    GetHistoryProfile = function() return "Default" end,
    GetHistoryEpoch = function() return epoch end,
    SetActiveProfile = function(name) skinRoot.activeProfile = name return true end,
    SetProfile = function(name, profile) skinRoot.profiles[name] = Copy(profile) return true end,
} }
local function Load()
    -- Reload the actual canonical owner, whose session stamp belongs to this
    -- load. Recording codec/database dependencies remain this epoch fixture's.
    MSUFSuite.SuiteProfiles = { WorkbenchSkinEngine = function() return MapkoSkin end }
    assert(loadfile(root .. "/MSUF_Suite/Core/ProfileWorkbenchBridge.lua"))("MSUF_Suite", MSUFSuite)
    local page = {}
    assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Bridge.lua"))("MSUF_Suite_Options", page)
    page.Refresh = function() end
    return page
end
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end
local page = Load()
local saved = assert(page.CaptureHistoryState())
skinRoot.profiles.Default.accent = 2
Check(page.RestoreHistoryState(saved) and skinRoot.profiles.Default.accent == 1,
    "same-load history lost its skin profile")
epoch, skinRoot.profiles.Default.accent = 1, 3
Check(page.RestoreHistoryState(saved) and skinRoot.profiles.Default.accent == 3,
    "same-load history replaced a skin profile changed since the snapshot")
-- A saved guided-tour point outlives the Lua chunk. The numeric epoch from
-- that load cannot decide whether the new load may restore its skin profile.
now, epoch = 200, 2
page = Load()
Check(page.RestoreHistoryState(saved) and skinRoot.profiles.Default.accent == 1,
    "history from an earlier load skipped its skin profile because its epoch differed")
skinRoot.profiles.Default.accent = 4
saved.skinSession = nil
Check(page.RestoreHistoryState(saved) and skinRoot.profiles.Default.accent == 1,
    "a saved point predating session stamps lost its skin profile")
print("suite_options_skin_history_contract: " .. checks .. " checks passed")
