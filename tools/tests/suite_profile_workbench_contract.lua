-- MSUF's profile workbench (host API v1 GetProfileWorkbench) and the Suite's
-- provider (Core/ProfileWorkbenchBridge.lua): restore points, history undo and
-- staged imports of Suite strings, through a recording workbench.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local Suite, combat, encodings, padding = {}, false, {}, ""
local overlay, recording, external = false, false, nil
-- The client clock; a /reload starts a new load at a later time.
local now = 100
GetTime = function() return now end
local frame = { general = {} }
local core = { UF = {}, ProfileRuntime = { Apply = function() overlay = true end }, L = {} }
MSUF_NS = core
MSUF_GlobalDB, MSUF_DB, MSUF_ActiveProfile = { profiles = { Default = frame } }, frame, "Default"
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
InCombatLockdown = function() return combat end
C_AddOns = { DoesAddOnExist = function() return false end, IsAddOnLoaded = function() return false end }
Minimap = { SetMaskTexture = function() end }
securecallfunction = function(fn, ...) return fn(...) end
MSUF_EncodeCompactTable = function(value, prefix)
    assert(prefix == "MSUF3")
    encodings[#encodings + 1] = value
    return "MSUF3:" .. #encodings .. padding
end
MSUF_TryDecodeCompactString = function(text) return encodings[tonumber(text:match("^MSUF3:(%d+)"))] end
MSUF_Profiles_ExportSelectionToString = function() return "MSUF3:frames" end
MSUF_Profiles_ImportIntoNewProfile = function() return false, "not used here" end
MSUF_SwitchProfile = function() return false end
MSUF_DeleteProfile = function() return false end
core.ProfileFields = { RegisterExternal = function(_, value) external = value end }
core.ProfileVariants = {
    BaseSnapshot = function() return { suiteModules = external.Snapshot(Suite.DB.suite.modules) } end,
    HasExternalOverlay = function() return overlay end,
    IsRecording = function() return recording end,
    IsMaterialized = function() return overlay end,
    Restore = function() overlay = false end,
    ResolveCurrent = function() overlay = true end,
}
core.ProfileSync = { RegisterModule = function() end, RebaseExternal = function() end }
local providers, checkpoints, refusal = {}, {}, nil
local workbench = {
    RegisterProvider = function(id, provider) providers[id] = provider return true end,
    Checkpoint = function(label)
        if refusal then return false, refusal end
        checkpoints[#checkpoints + 1] = label
        return true, #checkpoints
    end,
}
MSUF_HostAPI = { version = 1, ApplyUIScaleProfile = function() end, SetResourceStack = function() end,
    GetProfileWorkbench = function() return workbench end }
Support.Load(root, "MSUF_Suite", Suite, "Core/ProfileVariants.lua")
local P, IO = Suite.SuiteProfiles, Suite.ProfileIO
local provider = assert(providers.suiteSkin, "the Suite did not register its workbench provider")

-- Every case runs; the failures are reported together at the end.
local failures = {}
local function Case(name, body)
    local ok, why = pcall(body)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(why) end
end

-- The Suite profiles failed to load (Startup.lua startupError): MSUF's own
-- restore points, resets and imports must still go ahead.
Case("E2 no store", function()
    local snapshot, why = provider.Capture()
    assert(snapshot, "a Suite without its store refused MSUF's restore point: " .. tostring(why))
    assert(provider.Restore(snapshot), "a Suite without its store refused MSUF's restore")
end)

assert(Suite.Database.Initialize(nil))
Suite.Suite.Normalize(Suite.DB)
local live = Suite.DB.suite.modules
local skinCalls = {}
Suite.Skin.enabled, Suite.RootDB.skinEnabled = true, true
Suite.Skin.SetEnabled = function(enabled, deferApply)
    skinCalls[#skinCalls + 1] = { enabled = enabled, deferApply = deferApply }
    Suite.Skin.enabled, Suite.RootDB.skinEnabled = enabled, enabled
    return true
end
local skinProfile, skinActive, epoch = { accent = 1 }, "Default", 0
local fakeSkin = { Database = {
    GetActiveProfileName = function() return skinActive end,
    SetProfile = function(_, value) skinProfile = value return true end,
    SetActiveProfile = function(name) skinActive = name return true end,
    GetHistoryEpoch = function() return epoch end,
} }
local engine
P.WorkbenchSkinEngine = function() return engine end
P.WorkbenchSkinSnapshot = function() return Suite.CopyValue(skinProfile) end

Case("E2 old restore point without store", function()
    local point = assert(provider.Capture())
    local rootDB, db = Suite.RootDB, Suite.DB
    Suite.RootDB, Suite.DB = nil, nil
    local done, ok, why = pcall(provider.Restore, point)
    Suite.RootDB, Suite.DB = rootDB, db
    assert(done and ok, "a restore point with Suite settings failed without the Suite store: " .. tostring(ok or why))
end)

Case("E2 skin addon disabled since", function()
    engine = fakeSkin
    local point = assert(provider.Capture())
    assert(point.present, "the skin profile was not captured")
    engine = nil
    local width = live.objectives.width
    live.objectives.width = width + 30
    local ok, why = provider.Restore(Suite.CopyValue(point))
    assert(ok, "a restore point with skin settings failed without the skin addon: " .. tostring(why))
    assert(Suite.DB.suite.modules.objectives.width == width, "the Suite part was not restored")
end)

Case("SR1-2 skin switch", function()
    engine = fakeSkin
    local point = assert(provider.Capture())
    Suite.Skin.SetEnabled(false)
    skinCalls = {}
    assert(provider.Restore(Suite.CopyValue(point)))
    assert(Suite.RootDB.skinEnabled == true and Suite.Skin.enabled == true,
        "the restore wrote the stored skin switch but left the running skin off")
    assert(#skinCalls == 1 and skinCalls[1].deferApply == true,
        "the skin switch did not defer its pass to the profile listeners")
    engine = nil
end)

-- Without the Suite store nothing was captured, the skin included; a skin
-- write then could be neither undone nor rolled back.
Case("review 2 no store, skin engine loaded", function()
    engine, skinProfile = fakeSkin, { accent = 1 }
    local point = assert(provider.Capture())
    skinProfile = { accent = 2 }
    local rootDB, db = Suite.RootDB, Suite.DB
    Suite.RootDB, Suite.DB = nil, nil
    local done, ok = pcall(provider.Restore, Suite.CopyValue(point))
    Suite.RootDB, Suite.DB = rootDB, db
    engine = nil
    assert(done and ok and skinProfile.accent == 2, "a restore without the Suite store wrote the skin profile")
end)

-- MSUF calls the provider with a reason from its history and its guided tour;
-- a skin store changed since keeps its profiles, as in the Suite's own history
-- provider. A restore point (no reason) restores them.
Case("E3 history epoch", function()
    engine, skinProfile, epoch = fakeSkin, { accent = 1 }, 0
    local point = assert(provider.Capture())
    skinProfile, epoch = { accent = 2 }, 1
    assert(provider.Restore(Suite.CopyValue(point), "MSUF2_HISTORY_UNDO", "settings"))
    assert(skinProfile.accent == 2, "an undo wrote the skin profile over a skin store changed since")
    assert(provider.Restore(Suite.CopyValue(point)))
    assert(skinProfile.accent == 1, "a restore point did not restore its skin profile")
    engine = nil
end)

-- The skin epoch counts from 0 again after a /reload, and the guided tour's
-- snapshot outlives the load that took it: its epoch number means nothing now.
Case("review 1 epoch from an earlier load", function()
    for _, earlier in ipairs({ 3, 0 }) do
        engine, skinProfile, epoch, now = fakeSkin, { accent = 1 }, earlier, now + 100
        assert(loadfile(root .. "/MSUF_Suite/Core/ProfileWorkbenchBridge.lua"))("MSUF_Suite", Suite)
        local point = assert(providers.suiteSkin.Capture())
        now = now + 100
        assert(loadfile(root .. "/MSUF_Suite/Core/ProfileWorkbenchBridge.lua"))("MSUF_Suite", Suite)
        provider = providers.suiteSkin
        skinProfile, epoch = { accent = 2 }, 0
        assert(provider.Restore(Suite.CopyValue(point), "MSUF2_GUIDED_TOUR_RESTORE", "guided_tour:restore_point"))
        assert(skinProfile.accent == 1, "a snapshot from an earlier load skipped its skin profile (epoch "
            .. earlier .. ")")
    end
    engine = nil
end)

-- A restore writes copies: read the live module settings again.
live = Suite.DB.suite.modules
live.groupFinderDoubleClick.note = "Alt of Mapko"
live.loadoutReminder.expectedCharacterGUID = "Player-1-00000001"
live.loadoutReminder.expectedConfigID = 7

Case("SR1-1 module export", function()
    local text = assert(IO.ExportModule("objectives"))
    assert(provider.AcceptsImport(text) and provider.AcceptsImport(" \n" .. text),
        "the workbench does not take the Suite's own module export")
    assert(provider.PrepareImport(text), "the workbench did not read the Suite's own module export")
    assert(not provider.AcceptsImport(IO.prefix .. "MSUF3:1"),
        "the workbench claims a string no Suite parser reads on its own")
end)

Case("E4 untrimmed module string", function()
    local text = assert(IO.ExportModule("objectives"))
    assert(IO.PrepareModuleProfile(" \r\n" .. text .. " \n", true) == "objectives",
        "a module string with surrounding whitespace was refused")
end)

Case("E1 module import keeps personal and unrelated settings", function()
    local text = assert(IO.ExportModule("groupFinderDoubleClick"))
    local incoming = assert(provider.PrepareImport(text))
    assert(incoming.provider.suite.modules.groupFinderDoubleClick.note == "Alt of Mapko",
        "a workbench module import reset the active profile's note")
    live.minimap.size, live.minimap.enabled = 244, false
    local legacy = "MSUFM2:" .. MSUF_EncodeCompactTable({ addon = "MSUF_Suite", format = 2, module = "mapQuickSwitch",
        settings = { enabled = true, showSpec = true, showLoot = false, corner = 4, size = 28, x = 5, y = 6 } }, "MSUF3")
    incoming = assert(provider.PrepareImport(legacy))
    local minimap = incoming.provider.suite.modules.minimap
    assert(minimap.size == 244 and minimap.enabled == false and minimap.specButton and minimap.specSize == 28,
        "an old helper string replaced the whole Minimap module")
end)

Case("E1 bundle import keeps personal settings", function()
    local text = "MSUFS2:MSUF3:frames\n" .. assert(IO.ExportProfile())
    local incoming = assert(provider.PrepareImport(text))
    local modules = incoming.provider.suite.modules
    assert(modules.groupFinderDoubleClick.note == "Alt of Mapko"
        and modules.loadoutReminder.expectedCharacterGUID == "Player-1-00000001"
        and modules.loadoutReminder.expectedConfigID == 7,
        "a workbench bundle import reset the active profile's character-bound settings")
    live.groupFinderDoubleClick.note = "Exported"
    text = "MSUFS2:MSUF3:frames\n" .. assert(IO.ExportProfile(nil, { characterBound = true }))
    live.groupFinderDoubleClick.note, live.groupFinderDoubleClick.exportNote = "Alt of Mapko", true
    modules = assert(provider.PrepareImport(text)).provider.suite.modules
    live.groupFinderDoubleClick.exportNote = false
    assert(modules.groupFinderDoubleClick.note == "Exported" and modules.groupFinderDoubleClick.exportNote == true,
        "a marked bundle lost its note, or the export choice travelled")
end)

-- A refused restore point leaves the variant overlay as it was.
Case("SR1-3 refused checkpoint", function()
    local text = assert(IO.ExportModule("objectives"))
    overlay, refusal = true, "Restore point exceeds the storage limit."
    local ok = P.ImportModule(text)
    local laid = overlay
    overlay, refusal = false, nil
    assert(not ok and laid, "a refused restore point left the variant overlay lifted")
    assert(P.ImportModule(text) and checkpoints[#checkpoints] == "Before importing Suite settings")
    overlay = false
end)

-- MSUF's profile string box holds 200,000 characters (Menu2 W.TextInput).
Case("E5 export larger than any import", function()
    padding = string.rep("A", 200000)
    local module, moduleWhy = IO.ExportModule("objectives")
    local bundle, bundleWhy = P.Export()
    padding = ""
    assert(module == nil and moduleWhy == "Suite module profile is too large",
        "a module export no import can take was made")
    assert(bundle == nil and bundleWhy == "Suite profile is too large", "a profile export no import can take was made")
    assert(IO.ExportModule("objectives") and P.Export(), "ordinary exports were refused")
end)

assert(#failures == 0, "\n" .. table.concat(failures, "\n"))
print("suite_profile_workbench_contract: OK")
