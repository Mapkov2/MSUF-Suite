-- MSUF's profile workbench (host API v1 GetProfileWorkbench) and the Suite's
-- provider (Core/ProfileWorkbenchBridge.lua): restore points, history undo and
-- staged imports of Suite strings, through a recording workbench.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local defaultCVars = { GetCVar = function() return nil end }
C_CVar = defaultCVars
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
UnitGUID = function(unit) return unit == "player" and "Player-1-00000001" or nil end
-- Callbacks for the next frame; NextFrame runs them.
local timers = {}
C_Timer = { After = function(seconds, callback)
    assert(seconds == 0 and type(callback) == "function", "only next-frame timers are expected here")
    timers[#timers + 1] = callback
end }
local function NextFrame()
    local due = timers
    timers = {}
    for _, callback in ipairs(due) do callback() end
end
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
if arg[2] then assert(loadfile(arg[2]))("MSUF_Suite", Suite) end
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
        assert(loadfile(arg[2] or root .. "/MSUF_Suite/Core/ProfileWorkbenchBridge.lua"))("MSUF_Suite", Suite)
        local point = assert(providers.suiteSkin.Capture())
        now = now + 100
        assert(loadfile(arg[2] or root .. "/MSUF_Suite/Core/ProfileWorkbenchBridge.lua"))("MSUF_Suite", Suite)
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


Case("Blizzard nameplate settings transfer and restore", function()
    local cvars = { nameplateDebuffPadding = "3", nameplateShowEnemies = "1", UnitSurnameOwn = "0" }
    C_CVar = {
        GetCVar = function(key) return cvars[key] end,
        SetCVar = function(key, value) cvars[key] = value end,
    }
    local previous = assert(provider.Capture())
    assert(previous.nameplateCVars and previous.nameplateCVars.nameplateDebuffPadding == "3",
        "restore point omitted Blizzard's value")
    local module = assert(P.ExportModule("nameplates"))
    local bundle = assert(P.Export())
    cvars.nameplateDebuffPadding, cvars.UnitSurnameOwn = "8", "1"
    local prepared = assert(provider.PrepareImport(module))
    assert(cvars.nameplateDebuffPadding == "8", "preparing a module import wrote the native value")
    assert(provider.Restore(prepared.provider))
    assert(cvars.nameplateDebuffPadding == "3" and cvars.UnitSurnameOwn == "0",
        "applying a prepared module lost the native values")
    cvars.nameplateDebuffPadding = "9"
    assert(provider.Restore(previous, "MSUF2_HISTORY_UNDO", "suite:options"))
    assert(cvars.nameplateDebuffPadding == "9", "ordinary menu undo replaced a later Blizzard edit")
    assert(provider.Restore(previous, "MSUF2_HISTORY_UNDO", "profile-workbench"))
    assert(cvars.nameplateDebuffPadding == "3", "workbench undo lost the native value")
    cvars.nameplateDebuffPadding = "9"
    assert(provider.Restore(previous))
    assert(cvars.nameplateDebuffPadding == "3", "restoring a point lost the native value")
    Suite.DB.suite.modules.nameplates.protectImport = true
    cvars.nameplateDebuffPadding = "5"
    prepared = assert(provider.PrepareImport(bundle))
    assert(provider.Restore(prepared.provider))
    assert(cvars.nameplateDebuffPadding == "3", "retired protection still blocks native settings from the full profile")
    Suite.DB.suite.modules.nameplates.protectImport = false
    prepared = assert(provider.PrepareImport(bundle))
    assert(provider.Restore(prepared.provider))
    assert(cvars.nameplateDebuffPadding == "3", "applying a prepared bundle lost the native value")
    local oldOffset = Suite.DB.suite.modules.nameplates.enemyAurasOffsetX
    local rejected = Suite.CopyValue(previous)
    rejected.nameplateCVars.nameplateDebuffPadding = "19"
    rejected.suite.modules.nameplates.enemyAurasOffsetX = 99
    C_CVar.SetCVar = function(key, value)
        if key == "nameplateDebuffPadding" and value == "19" then return false end
        cvars[key] = value
    end
    local accepted, reason = provider.Restore(rejected)
    assert(not accepted and reason and cvars.nameplateDebuffPadding == "3"
        and Suite.DB.suite.modules.nameplates.enemyAurasOffsetX == oldOffset,
        "a rejected workbench native setting left a partial import")
    local partial = { present = false, suite = { schema = 1, modules = { nameplates = { enabled = true } } } }
    assert(provider.Restore(partial))
    assert(partial.suite.modules.nameplates.look == nil and partial.suite.modules.chat == nil,
        "workbench preparation mutated the caller's restore point")
    C_CVar = defaultCVars
end)

-- A visibility switch writes Blizzard directly. Ordinary menu history must
-- restore that native choice, without replaying unrelated native settings.
Case("Friendly visibility ordinary history undo and redo", function()
    local runtime, oldRuntime = Suite.Suite, {}
    for key, value in pairs(runtime) do oldRuntime[key] = value end
    local saved = { cvars = C_CVar, profile = Suite.OnProfileChanged,
        namespace = MSUFSuite, unit = UnitName, realm = GetRealmName,
        recovery = Suite.RootDB.suiteRecovery, instance = runtime.instances.nameplates }
    local cvars = { nameplateShowFriendlyPlayers = "0", nameplateShowFriendlyNpcs = "0",
        nameplateDebuffPadding = "7", UnitNameNPC = "0" }
    local instance = { active = true, config = Suite.DB.suite.modules.nameplates, ResetCVarBaseline = function() end }
    runtime.instances.nameplates = instance
    C_CVar = { GetCVar = function(key) return cvars[key] end, SetCVar = function(key, value)
        cvars[key] = value
        Suite.SyncFriendlyNameplates(instance, "CVAR_UPDATE", key)
    end }
    MSUFSuite, UnitName, GetRealmName = Suite, function() return "Tester" end, function() return "Realm" end
    assert(loadfile(root .. "/MSUF_Suite_Modules/Runtime.lua"))("MSUF_Suite_Modules", {})
    local private = { NS = Suite, Suite = runtime }
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/Modes.lua"))("MSUF_Suite_Nameplates", private)
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/CVars.lua"))("MSUF_Suite_Nameplates", private)
    instance.context = runtime.NewContext("nameplates")
    runtime.Apply = function() private.CVars.Apply(instance) end
    -- The controller confirms a switch's native write after the module applied
    -- the batch (MSUF_Suite/Core/Suite.lua, SetMany).
    runtime.SetMany = function(_, values, confirm)
        for key, value in pairs(values) do instance.config[key] = value end
        runtime.Apply()
        return not confirm or confirm()
    end
    Suite.OnProfileChanged = function()
        instance.config = Suite.DB.suite.modules.nameplates
        runtime.Apply()
    end
    local done, why = pcall(function()
        instance.config.enabled, instance.config.friendlySkinEnabled = true, true
        instance.config.friendlyNpcSkinEnabled, instance.config.friendlyNPCs = true, 2
        runtime.Apply()
        local offPoint = assert(provider.Capture())
        assert(Suite.SetFriendlyNameplates("friendly", true))
        local onPoint = assert(provider.Capture())
        cvars.nameplateDebuffPadding, cvars.UnitNameNPC = "9", "1"
        assert(provider.Restore(offPoint, "MSUF2_SUITE_HISTORY"))
        assert(cvars.nameplateShowFriendlyPlayers == "0" and instance.config.friendlySkinEnabled,
            "undo failed to restore native Off with an enabled skin")
        assert(cvars.nameplateDebuffPadding == "9" and cvars.UnitNameNPC == "1",
            "ordinary visibility undo replaced an unrelated Blizzard choice")
        assert(provider.Restore(onPoint, "MSUF2_SUITE_HISTORY"))
        assert(cvars.nameplateShowFriendlyPlayers == "1" and instance.config.friendlySkinEnabled,
            "redo failed to restore native On")
        assert(Suite.SetFriendlyNameplates("friendly", false))
        assert(provider.Restore(onPoint, "MSUF2_SUITE_HISTORY"))
        assert(cvars.nameplateShowFriendlyPlayers == "1" and instance.config.friendlySkinEnabled,
            "undo of Suite Off failed to enable the native plate")
        local npcOff = assert(provider.Capture())
        assert(Suite.SetFriendlyNameplates("friendlyNpc", true))
        assert(provider.Restore(npcOff, "MSUF2_SUITE_HISTORY"))
        assert(cvars.nameplateShowFriendlyNpcs == "0" and instance.config.friendlyNpcSkinEnabled,
            "NPC undo failed or its native event rewrote the restored skin flag")
        cvars.nameplateShowFriendlyNpcs, cvars.UnitNameNPC = "1", "0"
        instance.config.friendlyNPCs = 4
        runtime.Apply()
        assert(cvars.nameplateShowFriendlyNpcs == "0" and cvars.UnitNameNPC == "1")
        local importIO = IO
        if arg[3] then
            assert(loadfile(arg[3]))("MSUF_Suite", Suite)
            importIO, Suite.ProfileIO = Suite.ProfileIO, IO
        end
        assert(importIO.ApplyNameplateCVars({ nameplateShowFriendlyNpcs = "0", nameplateDebuffPadding = "6" }))
        assert(instance.config.friendlyNPCs == 4 and instance.config.friendlyNpcSkinEnabled
            and cvars.nameplateShowFriendlyNpcs == "0" and cvars.UnitNameNPC == "1",
            "own import baseline restore event exited NPC Names-only")
    end)
    for key in pairs(runtime) do runtime[key] = nil end
    for key, value in pairs(oldRuntime) do runtime[key] = value end
    runtime.instances.nameplates = saved.instance
    C_CVar, Suite.OnProfileChanged = saved.cvars, saved.profile
    MSUFSuite, UnitName, GetRealmName = saved.namespace, saved.unit, saved.realm
    Suite.RootDB.suiteRecovery = saved.recovery
    assert(done, why)
end)

-- Profile strings always carry the exporting character's action bars and
-- name their WoW version (ProfileClients.lua). Every import path offers this
-- client's action bars after the import succeeded, and only the player's
-- answer applies them (Snapshots.lua AskProfileSetup); history steps never
-- offer them. The other client's are parked in the profile and travel back.
Case("Action bars in profile strings", function()
    local asked, printed = 0, {}
    local retailSetup = { keys = { Q = "ACTIONBUTTON1", ["SHIFT-2"] = "MULTIACTIONBAR1BUTTON2" },
        slots = { [1] = 133, [13] = 116 }, independentSlots = { [2] = 120 }, class = "MAGE", spec = 63, label = "Fire" }
    local foreverSetup = { keys = { E = "ACTIONBUTTON3" }, slots = { [2] = 5143 }, class = "MAGE", group = 1, label = "Primary" }
    local live = retailSetup
    local transfers = {
        ProfileSetup = function() return Suite.CopyValue(live) end,
        AskProfileSetup = function() asked = asked + 1 return true end,
    }
    local print = Suite.Print
    Suite.Print = function(text) printed[#printed + 1] = text end
    Suite.ActionBarSnapshots = transfers
    Suite.RootDB.actionBarOffer = nil
    local bars = Suite.DB.suite.modules.actionbars
    local function Envelope(text, prefix)
        return encodings[tonumber(text:match(prefix .. "MSUF3:(%d+)"))]
    end
    local function Offered()
        local offer = Suite.RootDB.actionBarOffer
        return offer and offer.setup
    end
    bars.profileKeybinds = false
    local module, bundle = assert(P.ExportModule("actionbars")), assert(P.Export())
    local moduleEnvelope, bundleEnvelope = Envelope(module, "^MSUFM2:"), Envelope(bundle, "\nMSUFM1:")
    assert(moduleEnvelope.client == "retail" and bundleEnvelope.client == "retail", "a string did not name its WoW version")
    assert(moduleEnvelope.actionBars.retail.keys["SHIFT-2"] == "MULTIACTIONBAR1BUTTON2"
        and moduleEnvelope.actionBars.retail.slots[13] == 116 and moduleEnvelope.actionBars.retail.independentSlots[2] == 120,
        "the action bar string lost its action bars")
    assert(bundleEnvelope.actionBars.retail.keys.Q == "ACTIONBUTTON1" and bundleEnvelope.actionBars.retail.slots[1] == 133,
        "the full profile lost its action bars (the retired key choice must not stop them)")
    assert(not moduleEnvelope.actionBars.forever and moduleEnvelope.actionBarKeys == nil,
        "the string claimed action bars for the other client or kept the old key map")
    local plates = Envelope(assert(P.ExportModule("nameplates")), "^MSUFM2:")
    assert(plates.actionBars == nil and plates.client == "retail", "another module's string carried action bars")

    local prepared = assert(provider.PrepareImport(module))
    assert(asked == 0 and Offered() == nil, "preparing an import offered action bars")
    -- The workbench reviews each value of a snapshot as its own change: the
    -- offer is one value.
    for key, value in pairs(prepared.provider) do
        assert(not tostring(key):find("ction") or key == "importedActionBars" and type(value) == "string",
            "the offer is not one value of the prepared snapshot: " .. tostring(key))
    end
    assert(type(prepared.provider.importedActionBars) == "string", "the prepared import lost its offer")
    -- MSUF's workbench restores with true as the second argument (its copy's
    -- second result); its history passes a reason text.
    assert(provider.Restore(prepared.provider, true))
    assert(asked == 0 and Offered() == nil, "the import offered before the workbench committed it")
    NextFrame()
    assert(asked == 1 and Offered().slots[13] == 116 and Offered().keys.Q == "ACTIONBUTTON1",
        "the module import did not offer its action bars")
    Suite.RootDB.actionBarOffer = nil
    -- The workbench's commit failed and it restored the point before: no offer.
    local before = assert(provider.Capture())
    prepared = assert(provider.PrepareImport(bundle))
    assert(provider.Restore(prepared.provider) and provider.Restore(before))
    NextFrame()
    assert(asked == 1 and Offered() == nil, "an import the workbench rolled back offered action bars")
    prepared = assert(provider.PrepareImport(bundle))
    assert(provider.Restore(prepared.provider))
    NextFrame()
    assert(asked == 2 and Offered().spec == 63, "the full profile import did not offer")
    Suite.RootDB.actionBarOffer = nil
    assert(provider.Restore(prepared.provider, "MSUF2_HISTORY_UNDO", "profile-workbench") and asked == 2
        and Offered() == nil, "a history step offered action bars")
    NextFrame()
    assert(asked == 2 and Offered() == nil, "a history step offered action bars a frame later")
    assert(P.ImportModule(module) and asked == 3 and Offered(), "the direct module import did not offer")
    local job = assert(P.BeginImport(module))
    local done, ok
    repeat done, ok = job:Step() until done
    assert(ok and asked == 4, "the stepped module import did not offer")

    -- WoW Forever parks Retail's action bars and is offered the exporter's
    -- key bindings alone; Retail's spells come back with the next string.
    Suite.RootDB.actionBarOffer = nil
    Suite.Client.isForever = true
    prepared = assert(provider.PrepareImport(module))
    assert(provider.Restore(prepared.provider))
    NextFrame()
    assert(asked == 5 and Offered().keys.Q == "ACTIONBUTTON1" and Offered().keys["SHIFT-2"] == "MULTIACTIONBAR1BUTTON2"
        and Offered().slots == nil and Offered().independentSlots == nil and Offered().class == nil,
        "the other client's key bindings did not come along, or its spells did")
    Suite.RootDB.actionBarOffer = nil
    local parked = Suite.DB.suite.modules.actionbars.parkedSetup
    local decoded = encodings[tonumber(parked:match("^MSUF3:(%d+)"))]
    assert(decoded.client == "retail" and decoded.setup.slots[13] == 116, "WoW Forever did not park Retail's action bars")
    live = foreverSetup
    local foreverModule = assert(P.ExportModule("actionbars"))
    local foreverEnvelope = Envelope(foreverModule, "^MSUFM2:")
    assert(foreverEnvelope.client == "forever" and foreverEnvelope.actionBars.forever.slots[2] == 5143
        and foreverEnvelope.settings.parkedSetup == parked, "the WoW Forever string lost a client's action bars")
    Suite.Client.isForever = false
    live = retailSetup
    Suite.DB.suite.modules.actionbars.parkedSetup = ""
    prepared = assert(provider.PrepareImport(foreverModule))
    assert(provider.Restore(prepared.provider))
    NextFrame()
    assert(asked == 6 and Offered().slots[13] == 116 and Offered().spec == 63 and Offered().keys.E == "ACTIONBUTTON3"
        and Offered().keys.Q == nil, "Retail's own spells did not come back with the WoW Forever exporter's key bindings")
    parked = Suite.DB.suite.modules.actionbars.parkedSetup
    decoded = encodings[tonumber(parked:match("^MSUF3:(%d+)"))]
    assert(decoded.client == "forever" and decoded.setup.slots[2] == 5143, "Retail did not park WoW Forever's action bars")

    -- An older string's key map belongs to its client; without the action
    -- bars the import says how to apply them and the offer waits.
    Suite.RootDB.actionBarOffer = nil
    local legacy = "MSUFM2:" .. MSUF_EncodeCompactTable({ addon = "MSUF_Suite", format = 2, module = "actionbars",
        revision = moduleEnvelope.revision, settings = moduleEnvelope.settings, actionBarKeys = { retail = { Q = "ACTIONBUTTON2" } } }, "MSUF3")
    assert(P.ImportModule(legacy) and Offered().keys.Q == "ACTIONBUTTON2" and Offered().slots == nil,
        "an older string's key map was not offered")
    Suite.ActionBarSnapshots = nil
    local reports = #printed
    assert(P.ImportModule(module) and #printed == reports + 1 and Offered().slots[13] == 116,
        "action bars for absent Suite action bars were not reported or not kept")
    Suite.RootDB.actionBarOffer = nil
    Suite.Print = print
end)

Case("Player aura skin import review", function()
    local S = Suite.Suite
    assert(S.SetMany("playerAuras", { buffSkin = "SHADOW1", debuffSkin = "DARK2", enabled = true, x = -65 }))
    assert(S.SetMany("playerAuraSkins", { enabled = true }))
    local text = assert(P.ExportModule("playerAuraSkins"))
    assert(S.SetMany("playerAuras", { buffSkin = "CUSTOM", debuffSkin = "CUSTOM", enabled = false, x = 38 }))
    assert(S.SetMany("playerAuraSkins", { enabled = false }))
    local prepared = assert(provider.PrepareImport(text))
    assert(not S.Config("playerAuraSkins").enabled and S.Config("playerAuras").buffSkin == "CUSTOM",
        "preparing a skin import changed the active profile")
    assert(provider.Restore(prepared.provider))
    local layout = S.Config("playerAuras")
    assert(S.Config("playerAuraSkins").enabled and layout.buffSkin == "SHADOW1" and layout.debuffSkin == "DARK2",
        "import review lost the selected aura skins")
    assert(not layout.enabled and layout.x == 38, "import review changed the aura layout")
end)

assert(#failures == 0, "\n" .. table.concat(failures, "\n"))
print("suite_profile_workbench_contract: OK")
