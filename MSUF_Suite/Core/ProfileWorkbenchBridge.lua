local _, Suite = ...
local P, IO = Suite.SuiteProfiles, Suite.ProfileIO
local Bridge = {}
Suite.ProfileWorkbenchBridge = Bridge
function Bridge.Checkpoint(label)
    local workbench = Suite.HostBridge.ProfileWorkbench()
    if not workbench then return true end
    return workbench.Checkpoint(label, true)
end

function Bridge.Register(provider)
    local workbench = Suite.HostBridge.ProfileWorkbench()
    if not workbench then return false end
    return workbench.RegisterProvider("suiteSkin", provider)
end

function Bridge.HistoryOwned()
    local workbench = Suite.HostBridge.ProfileWorkbench()
    return workbench and workbench.HistoryOwnsRoots and workbench.HistoryOwnsRoots("suiteSkin") == true
end

-- One canonical payload; old Options points keep their explicit profile names.
local function Canonical(snapshot)
    if type(snapshot) ~= "table" then return nil end
    if snapshot.root == nil then return snapshot end
    local root = snapshot.root
    local name = type(root) == "table" and root.activeProfile
    local profiles = type(root) == "table" and root.profiles
    local profile = type(profiles) == "table" and profiles[name]
    if type(profile) ~= "table" then return nil end
    local skinRoot = snapshot.skinRoot
    local skinName = type(skinRoot) == "table" and skinRoot.activeProfile
    local skins = type(skinRoot) == "table" and skinRoot.profiles
    local skin = type(skins) == "table" and skins[skinName]
    return { suite = profile.suite, activeProfile = name, skinEnabled = root.skinEnabled,
        legacyOptions = true, hasSkinEnabled = root.skinEnabled ~= nil, hasLayout = type(profile.layoutState) == "table",
        layout = profile.layoutState, present = skin ~= nil, profile = skin, skinProfileName = skinName,
        skinEpoch = snapshot.skinEpoch, skinSession = snapshot.skinSession }
end

local function OwnsSnapshot(snapshot)
    snapshot = Canonical(snapshot)
    if not snapshot then return nil end
    if snapshot.suite == nil then return false end
    local clean, why = IO.PrepareTable({ suite = snapshot.suite }, false)
    if not clean then return nil, why end
    return true
end
local function MergeRoots(snapshot, roots)
    snapshot = Canonical(snapshot)
    if not snapshot or not snapshot.suite then return false end
    local modules = snapshot.suite.modules
    for id, config in pairs(roots.suiteModules or {}) do
        local target = modules[id]
        if target then
            local rules = Suite.SuiteCatalog[id].rules
            for key, rule in pairs(rules) do
                if not rule.automation and id ~= "nameplates" and not Suite.SuiteCatalog[id].automation then
                    target[key] = Suite.CopyValue(config[key])
                end
            end
        end
    end
    if not OwnsSnapshot(snapshot) then return false end
    return snapshot
end

-- The skin store's history epoch (MSUF_Suite_Skin DatabaseProfiles.lua): it
-- moves when a skin profile is switched, deleted or imported, and counts from
-- 0 again in every load. The second result stamps this load.
local session
local function SkinEpoch(skin)
    session = session or GetTime()
    return skin.Database.GetHistoryEpoch(), session
end

-- Ordinary restore points include deliberate automation choices too. The
-- variant provider keeps its narrower rules and does not restore these twice.
-- Without its store (the Suite profiles failed to load, Startup.lua) the Suite
-- holds nothing here: MSUF's own restore points, resets and imports go ahead.
function P.CaptureWorkbenchSkin()
    if not Suite.RootDB then return { present = false } end
    Suite.ProfileVariants.Register()
    local settings, reason = Suite.ProfileVariants.BaseSettings(Suite.Database.GetActiveProfileName())
    if not settings then return false, reason end
    local result = { suite = settings, activeProfile = Suite.Database.GetActiveProfileName(),
        skinEnabled = Suite.RootDB.skinEnabled, layout = {} }
    local states = Suite.DB.suite.moduleState
    for id, keys in pairs(Suite.Database.PROFILE_LAYOUT_STATE) do
        local source = states and states[id]
        if source then
            local target = {}
            result.layout[id] = target
            for _, key in ipairs(keys) do target[key] = Suite.CopyValue(source[key]) end
        end
    end
    local skin = P.WorkbenchSkinEngine()
    if not skin then result.present = false return result end
    local db = skin.Database
    local name = db.GetHistoryProfile and db.GetHistoryProfile() or db.GetActiveProfileName()
    local root = db.GetRoot and db.GetRoot()
    local profile = root and root.profiles and root.profiles[name]
    if profile then profile = Suite.CopyValue(profile) else profile, reason = P.WorkbenchSkinSnapshot(skin) end
    if not profile then return false, reason end
    result.present, result.profile, result.skinProfileName = true, profile, name
    result.skinEpoch, result.skinSession = SkinEpoch(skin)
    return result
end

-- MSUF passes a reason from its history and its guided tour. As in the
-- Suite's own history provider (MSUF_Suite_Options/Menu/Bridge.lua), a skin
-- store changed since keeps its profiles; the epoch tells that only within
-- the load that took the snapshot (the tour's snapshot outlives it). A
-- restore point restores its skin profile: MSUF offers it only in its own
-- profile. Without the skin engine its part waits in the point.
local function RestoreSkin(snapshot, historyReason)
    local skin = P.WorkbenchSkinEngine()
    if not skin then return true end
    local epoch, current = SkinEpoch(skin)
    if historyReason ~= nil and snapshot.skinSession == current and snapshot.skinEpoch ~= epoch then return true end
    local name = snapshot.skinProfileName or Suite.HostBridge.ActiveFrameProfileName() or skin.Database.GetActiveProfileName()
    local ok, reason = skin.Database.SetProfile(name, Suite.CopyValue(snapshot.profile))
    if not ok then return false, reason end
    if not skin.Database.SetActiveProfile(name) then return false, "Skin profile unavailable" end
    return true
end

local function RestoreSuite(snapshot)
    local previous = Suite.Database.GetActiveProfileName()
    local name = snapshot.activeProfile or previous
    local lifted = Suite.ProfileVariants.LiftOverlay(previous)
    Suite.RootDB.profiles[name] = Suite.RootDB.profiles[name] or { suite = {} }
    Suite.RootDB.activeProfile = name
    Suite.DB = Suite.RootDB.profiles[name]
    Suite.DB.suite = Suite.DB.suite or {}
    for _, key in ipairs(Suite.Database.PROFILE_SETTINGS) do
        Suite.DB.suite[key] = Suite.CopyValue(snapshot.suite[key])
    end
    if not snapshot.legacyOptions or snapshot.hasLayout then
        Suite.DB.suite.moduleState = Suite.DB.suite.moduleState or {}
        for id, keys in pairs(Suite.Database.PROFILE_LAYOUT_STATE) do
            local target = Suite.DB.suite.moduleState[id] or {}
            Suite.DB.suite.moduleState[id] = target
            local source = snapshot.layout and snapshot.layout[id] or {}
            for _, key in ipairs(keys) do target[key] = Suite.CopyValue(source[key]) end
        end
    end
    if not snapshot.legacyOptions or snapshot.hasSkinEnabled then Suite.RootDB.skinEnabled = snapshot.skinEnabled end
    Suite.Suite.Normalize(Suite.DB)
    if lifted then Suite.ProfileVariants.LayOverlay() end
    -- The running skin follows the stored switch, as in the Suite's history
    -- restore; the profile listeners then apply both in one pass.
    local skinEnabled = Suite.RootDB.skinEnabled == true
    if Suite.Skin.enabled ~= skinEnabled then Suite.Skin.SetEnabled(skinEnabled, true) end
    Suite.OnProfileChanged(name)
end

function P.RestoreWorkbenchSkin(snapshot, historyReason)
    -- Without its store the Suite captured nothing, the skin included: a
    -- point's parts wait in it, and a skin write here could not be undone.
    if not Suite.RootDB then
        return historyReason == nil or type(snapshot) == "table" and snapshot.suite == nil and snapshot.root == nil
    end
    if Suite.IsCombatLocked() then return false, "Finish combat before restoring settings" end
    snapshot = Canonical(snapshot)
    if not snapshot then return false, "Invalid skin restore point" end
    if snapshot.activeProfile ~= nil and not Suite.Database.IsProfileName(snapshot.activeProfile) then return false, "Missing suite profile" end
    if snapshot.suite then
        local clean, why = IO.PrepareTable({ suite = snapshot.suite }, false)
        if not clean then return false, why end
        snapshot.suite = clean.suite
    end
    if snapshot.present then
        local ok, reason = RestoreSkin(snapshot, historyReason)
        if not ok then return false, reason end
    end
    if snapshot.suite then RestoreSuite(snapshot) end
    return true
end

local function PrepareWorkbenchImport(text)
    local snapshot, snapshotWhy = P.CaptureWorkbenchSkin()
    if not snapshot then return false, snapshotWhy end
    if not snapshot.suite then return false, "Missing suite profile" end
    if text:match("^%s*MSUFS") then
        local bundle, reason = P.WorkbenchPrepareBundle(text)
        if not bundle then return false, reason end
        IO.KeepPersonal(bundle.profile, snapshot.suite.modules, bundle.characterBound)
        snapshot.suite = bundle.profile.suite
        snapshot.present, snapshot.profile = bundle.provider.present, bundle.provider.profile
        return { coreText = bundle.coreText, provider = snapshot }
    end
    if text:match("^%s*MSKIN1:") then
        local skin = P.WorkbenchSkinEngine()
        if not skin then return false, "Skin engine unavailable" end
        local profile, reason = skin.ProfileIO.PrepareProfile(text)
        if not profile then return false, reason end
        snapshot.present, snapshot.profile = true, profile
        return { provider = snapshot }
    end
    local id, settings, reason = IO.PrepareModuleProfile(text, true)
    if not id then return false, reason end
    -- Only the string's settings change, as in P.ImportModule (SetMany): it
    -- leaves out character-bound ones, and an old helper string names seven
    -- Minimap settings.
    for key, value in pairs(settings) do snapshot.suite.modules[id][key] = value end
    return { provider = snapshot }
end

-- Registered at load: MSUF never unregisters a provider, and a restore point
-- holding Suite settings needs it to restore. Accepts exactly what
-- PrepareWorkbenchImport reads (a full Suite profile only inside a bundle).
Bridge.Register({
    OwnsRoots = { suiteModules = true },
    OwnsSnapshot = OwnsSnapshot,
    MergeRoots = MergeRoots,
    HistoryAliases = { "MSUF_Suite" },
    AcceptsImport = function(text)
        return type(text) == "string" and (text:match("^%s*MSUFS") or text:match("^%s*" .. IO.modulePrefix)
            or text:match("^%s*MSKIN1:")) ~= nil
    end,
    PrepareImport = PrepareWorkbenchImport,
    Capture = P.CaptureWorkbenchSkin,
    Restore = P.RestoreWorkbenchSkin,
    Inspect = function() return Suite.Suite.CDMInspectionRows() end,
})
