-- Shared-account login lifecycle through the real database, startup and installer.
local root = assert(arg[1], "Suite root required")
local H = dofile(root .. "/tools/tests/suite_installer_harness.lua")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

local function Login(stored, guid, forever, options)
    options = options or {}
    local suite = H.Setup({ root = root, forever = forever })
    MSUFSuiteInstallFrame = nil
    MSUFSuiteDB, MapkoSkinDB, MapkoSkin = stored, nil, nil
    MSUF_ProfileWasUnboundAtLogin = options.unbound == true
    local identity = guid
    if options.lateIdentity then identity = nil end
    UnitGUID = function() return identity end
    local default = options.default
    if options.appliedDefault then
        MSUF_GlobalDB.profiles[default] = { general = {} }
        MSUF_ActiveProfile, MSUF_DB = default, MSUF_GlobalDB.profiles[default]
    end
    local defaultWrites, switches = 0, 0
    MSUF_GetDefaultProfileForNewCharacters = function() return default end
    MSUF_SetDefaultProfileForNewCharacters = function(name)
        Check(name == nil, "Suite assigned a default for another character")
        default, defaultWrites = name, defaultWrites + 1
        return true
    end
    MSUF_SwitchProfile = function() switches = switches + 1; return false end
    -- Only unrelated runtime modules are inert; profile sync and installer stay real.
    suite.Skin.EnsureEngine, suite.Skin.SetEnabled, suite.Skin.SettleChatColors = Noop, Noop, Noop
    suite.Menu = { Watch = Noop }
    suite.Suite.Start = function() suite.Suite.started = true end
    suite.ProfileVariants.Register, suite.ProfileVariants.Start = Noop, Noop
    suite.SuiteProfiles.EnsureModernPanelLayout = Noop
    suite.SuiteProfiles.EnsureModernDarkTooltips = Noop
    suite.SuiteProfiles.EnsureModernDarkMinimap = Noop
    suite.SuiteProfiles.EnsureRetailForeverCooldownLayout = Noop
    suite.SuiteProfiles.EnsureRetailResourceStack = Noop
    local frames, deferred = {}, {}
    local create = CreateFrame
    CreateFrame = function(...)
        local frame = create(...)
        frames[#frames + 1] = frame
        return frame
    end
    C_Timer.After = function(_, callback) deferred[#deferred + 1] = callback end
    local function FlushTimers()
        local queued = deferred
        deferred = {}
        for _, callback in ipairs(queued) do callback() end
    end
    local loggedIn = false
    IsLoggedIn = function() return loggedIn end
    assert(loadfile(root .. "/MSUF_Suite/Core/Startup.lua"))("MSUF_Suite", suite)
    frames[1].scripts.OnEvent(frames[1], "ADDON_LOADED", "MSUF_Suite")
    loggedIn = true
    H.combat = options.combat == true
    frames[1].scripts.OnEvent(frames[1], "PLAYER_LOGIN")
    local function EnterWorld(nextIdentity)
        identity = nextIdentity or identity
        frames[2].scripts.OnEvent(frames[2], "PLAYER_ENTERING_WORLD", true, false)
        if options.combatBeforeDeferred then H.combat = true end
        FlushTimers()
    end
    EnterWorld(options.lateIdentity and guid or nil)
    Check(#H.reported == 0, "startup raised: " .. tostring(H.reported[1]))
    Check(switches == 0, "startup switched the character into another profile")
    return suite, function() return default, defaultWrites end, EnterWorld,
        function()
            H.combat = false
            frames[1].scripts.OnEvent(frames[1], "PLAYER_REGEN_ENABLED")
            FlushTimers()
        end
end

for _, forever in ipairs({ false, true }) do
    -- A's legacy account receipt must not certify either A or an already-bound alt.
    local seed = H.Setup({ root = root, forever = forever })
    local stored = seed.RootDB
    local accountReceipt = { revision = 4, status = "complete", profile = "classic",
        frameProfileName = "Old layout", newCharacterProfileOwned = true, newCharacterProfileRevision = 1 }
    stored.installation = accountReceipt
    stored.profiles.Default.suite.modules.chat.enabled = false
    local a, defaults = Login(stored, "Player-A", forever, { default = "Old layout" })
    Check(a.Installer.IsOpen(), "legacy completion suppressed character setup")
    local default, writes = defaults()
    Check(default == nil and writes == 1, "old Suite-owned default was not retired")
    local window = H.Install(a)
    Check(a.Database.GetCharacterInstallationStatus() == "complete", "A did not record its own completion")
    local account = a.RootDB
    local aReceipt, aProfile = account.installation, account.profiles[account.activeProfile]
    window:Hide()

    local b = Login(account, "Player-B", forever, { unbound = true })
    Check(b.Installer.IsOpen(), "new character inherited A's installer completion")
    Check(b.RootDB.characterInstallations["Player-A"] == "complete", "B changed A's completion")
    Check(b.RootDB.installation == aReceipt, "opening B replaced account metadata")
    Check(b.RootDB.profiles[aReceipt.frameProfileName].suite.globalLook == aProfile.suite.globalLook,
        "B's login replaced A's profile")
    MSUFSuiteInstallFrame:Hide() -- Escape/close without explicitly skipping.
    local reload = Login(b.RootDB, "Player-B", forever)
    Check(reload.Installer.IsOpen(), "bound character lost unfinished setup after reload")
    MSUFSuiteInstallFrame.close.scripts.OnClick()
    Check(reload.Database.GetCharacterInstallationStatus() == "skipped", "B did not skip only its own setup")
    Check(reload.RootDB.installation == aReceipt, "B's skip erased A's layout metadata")
    local skipped = Login(reload.RootDB, "Player-B", forever)
    Check(not skipped.Installer.IsOpen(), "B's skipped setup reopened")
    local resumed = Login(skipped.RootDB, "Player-A", forever)
    Check(not resumed.Installer.IsOpen(), "A's completed setup reopened after B skipped")

    local c = Login(resumed.RootDB, "Player-C", forever)
    Check(c.Installer.IsOpen(), "already-bound affected character inherited the old completion")
    H.Install(c)
    Check(c.Database.GetCharacterInstallationStatus() == "complete"
        and c.RootDB.characterInstallations["Player-A"] == "complete"
        and c.RootDB.characterInstallations["Player-B"] == "skipped", "C overwrote other character receipts")
    local completed = Login(c.RootDB, "Player-C", forever)
    Check(not completed.Installer.IsOpen(), "C's completed setup did not survive reload")
    local combat, _, _, leaveCombat = Login(completed.RootDB, "Player-D", forever, { combat = true })
    Check(not combat.Installer.IsOpen(), "new character setup opened during combat")
    leaveCombat()
    Check(combat.Installer.IsOpen(), "new character setup did not resume after combat")

    local delayed, _, enter = Login(combat.RootDB, nil, forever)
    Check(delayed.Installer.IsFirstRunPending(), "unknown identity inherited a completed setup")
    local before = delayed.RootDB.installation
    Check(not delayed.Installer.Apply() and delayed.RootDB.installation == before,
        "unknown identity applied a profile without an own receipt")
    enter("Player-E")
    Check(delayed.Installer.IsOpen(), "late character identity lost setup")
    MSUFSuiteInstallFrame.close.scripts.OnClick()
    Check(delayed.RootDB.characterInstallations["Player-E"] == "skipped", "late identity was not stored separately")

    delayed.RootDB.installation.newCharacterProfileOwned = true
    local explicit, userDefault = Login(delayed.RootDB, "Player-F", forever, { default = "User preference" })
    default, writes = userDefault()
    Check(default == "User preference" and writes == 0, "changed user preference was cleared")
    Check(explicit.Installer.IsOpen(), "an unapplied host default suppressed character setup")
    for _, late in ipairs({ false, true }) do
        local inherited, configured, _, finishCombat = Login(explicit.RootDB, late and "Player-H" or "Player-G", forever,
            { default = "User preference", appliedDefault = true, lateIdentity = late, combatBeforeDeferred = late })
        Check(not inherited.Installer.IsOpen(), "an applied explicit default still opened setup")
        -- A combat edge before the first startup frame delays profile sync;
        -- finish that startup before checking its character receipt.
        if late then
            Check(not inherited.Suite.started, "module startup ignored combat before its queued callback")
            local beforeDefault, beforeWrites = configured()
            Check(beforeDefault == "User preference" and beforeWrites == 0, "combat startup changed the explicit default")
            finishCombat()
            Check(not inherited.Installer.IsOpen(), "resuming an explicit default opened setup")
        end
        Check(inherited.Database.GetCharacterInstallationStatus() == "complete",
            "explicit default was not recorded after character identity became ready")
        local savedDefault, changed = configured()
        Check(savedDefault == "User preference" and changed == 0, "explicit default was changed")
        local finished = Login(inherited.RootDB, late and "Player-H" or "Player-G", forever)
        Check(not finished.Installer.IsOpen(), "removing the global default reopened an already configured character")
    end
    -- Restore this session before exercising its factory reset and its own window.
    explicit = Login(explicit.RootDB, "Player-F", forever)
    Check(explicit.Database.StageFactoryReset() and explicit.RootDB.characterInstallations == nil,
        "factory reset retained completed character setup")
    Check(explicit.Installer.IsFirstRunPending(), "factory reset did not reopen setup")
    explicit.RootDB.installation = 7
    MSUFSuiteInstallFrame.close.scripts.OnClick()
    Check(explicit.Database.GetCharacterInstallationStatus() == "skipped",
        "malformed legacy receipt prevented skipping character setup")
    Check(#H.reported == 0, "installer raised: " .. tostring(H.reported[1]))
end
-- An unreadable identity cannot become a saved key or certify another player.
local Secrets = dofile(root .. "/../MidnightSimpleUnitFrames/tools/tests/classpower_secrets.lua")
Secrets.Install()
local secretSuite = H.Setup({ root = root, forever = false })
local secret = Secrets.New("string")
UnitGUID = function() return secret end
local stop = Secrets.Watch(root .. "/MSUF_Suite/Core/Database.lua", { strict = true })
Check(secretSuite.Database.GetCharacterInstallationStatus() == nil, "secret identity resolved a status")
Check(not secretSuite.Database.SetCharacterInstallationStatus("complete"), "secret identity was saved")
Check(secretSuite.RootDB.characterInstallations == nil, "secret identity created a record")
local violations = stop()
Check(#violations == 0, "installer identity secret misuse: " .. table.concat(violations, "; "))
print("Suite character setup: " .. checks .. " checks passed")
