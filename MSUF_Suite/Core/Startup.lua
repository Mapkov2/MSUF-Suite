local addonName, Suite = ...
_G.MSUFSuite = Suite

local initialized = false
local events = CreateFrame("Frame")
local Start
local FinishWorldEntry
local startupFinished = false
local startedBeforeLockdown = false
local waitingForCombat = false
local combatEvent
-- True from a reload's world entry until the queued start runs. Combat that
-- begins in between still starts the modules before lockdown.
local watchingCombatStart = false

local function WatchCombatStart(watch)
    if watchingCombatStart == watch then return end
    watchingCombatStart = watch
    if watch then
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
    elseif not combatEvent then
        events:UnregisterEvent("PLAYER_REGEN_DISABLED")
    end
end

local function SetCombatWait(wait)
    if waitingForCombat == wait then return end
    waitingForCombat = wait
    if wait then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if combatEvent or watchingCombatStart then
            events:UnregisterEvent("PLAYER_REGEN_DISABLED")
            combatEvent, watchingCombatStart = nil, false
        end
    end
end

-- Starts the modules while combat is known or starting and protected writes
-- are still allowed. Profile repairs and setup keep their post-combat path.
local function StartBeforeLockdown()
    Suite.startingBeforeLockdown = true
    Suite.Dispatch(Start, "PLAYER_ENTERING_WORLD")
    Suite.startingBeforeLockdown = nil
end

local function ShowInstaller()
    if Suite.startupError or not Suite.Suite.started then return end
    if Suite.InCombat() and Suite.Installer.IsFirstRunPending() then
        SetCombatWait(true)
        return
    end
    SetCombatWait(false)
    Suite.Dispatch(Suite.Installer.MaybeShow, "login")
end

-- PLAYER_ENTERING_WORLD distinguishes a real login from /reload. Optional
-- modules loaded later can use this without keeping their own startup frame.
local loginEvent = CreateFrame("Frame")
loginEvent:RegisterEvent("PLAYER_ENTERING_WORLD")
loginEvent:SetScript("OnEvent", function(self, _, isInitialLogin, isReloadingUi)
    -- Only the first world entry counts; later ones are zone changes.
    self:UnregisterAllEvents()
    -- Mark a new login even when the optional XP module never loads. Reloads
    -- retain the generation, including legacy sessions before the first stamp.
    if isReloadingUi ~= true and not Suite.startupError then
        local root = Suite.RootDB
        local generation = root.xpSessionGeneration
        root.xpSessionGeneration = Suite.Finite(generation) and generation >= 0
            and generation < 9007199254740991 and generation + 1 or 1
    end
    Suite.loginKind = isReloadingUi == true and "reload" or "login"
    Suite.CaptureSessionGold(isReloadingUi)
    -- Settle the chat colour ledger before starting the reload layout.
    Suite.Dispatch(Suite.Skin.SettleChatColors)
    -- A reload in combat can report combat here while protected writes are
    -- still allowed. The next frame is already locked. PLAYER_LOGIN has
    -- finished, so loading modules here also avoids a nested login load.
    if isReloadingUi == true and waitingForCombat and not Suite.Suite.started and not Suite.IsCombatLocked() then
        if Suite.InCombat() then
            StartBeforeLockdown()
        else
            -- Combat can still begin before the queued start runs.
            WatchCombatStart(true)
        end
    end
    -- The next frame follows client login readiness and all startup listeners.
    C_Timer.After(0, FinishWorldEntry)
end)

local function Initialize()
    if initialized then return true end
    Suite.freshInstall = _G.MSUFSuiteDB == nil
    -- Older Suite profiles may live inside MapkoSkinDB. Load the legacy addon
    -- as data only before choosing the Suite profile, then hand skinning to the
    -- Suite-owned engine below.
    if _G.MSUFSuiteDB == nil then Suite.Skin.LoadLegacyDatabase() end
    local ok, reason, quarantined = Suite.Database.Initialize(_G.MSUFSuiteDB, _G.MapkoSkinDB)
    if not ok then
        Suite.startupError = reason
        Suite.Print(Suite.Text("Cannot load suite profiles: %s"):format(tostring(reason)))
        return false
    end
    -- Reported once: the saved root keeps them set aside from now on.
    if quarantined > 0 then
        Suite.Print(Suite.Text("Unreadable Suite profiles were set aside, their data is kept: %d"):format(quarantined))
    end
    -- No standalone SavedVariables always opens setup, including a migration.
    -- Migrated settings stay intact until the player chooses Install.
    if Suite.freshInstall then
        Suite.RootDB.installation = { revision = 3, status = "pending" }
    end
    _G.MSUFSuiteDB = Suite.RootDB
    initialized = true
    return true
end

-- Startup steps run isolated: a step that raises is reported and the others,
-- above all the module start, still run.
local function Step(owner, name, ...)
    Suite.Dispatch(owner[name], ...)
end

-- At combat end and in the reload window, the unit flag can still report
-- combat. Both paths must respect actual lockdown.
local function StartupInCombat(transition)
    if transition == "PLAYER_REGEN_ENABLED" or transition == "PLAYER_ENTERING_WORLD" then
        return Suite.IsCombatLocked()
    end
    return Suite.InCombat(transition)
end

local profilesPrepared = false
local function PrepareProfiles(transition)
    if not Initialize() then return end
    if StartupInCombat(transition) then
        SetCombatWait(true)
        return false
    end
    local legacy = _G.MapkoSkin and _G.MapkoSkin.Suite
    if legacy and legacy.started then
        -- A manually loaded suite must not take ownership from a running old
        -- development runtime. Reloading allows the owner guard to run first.
        Suite.startupError = "legacy-runtime-active"
        Suite.Print(Suite.Text("Reload the interface to start the standalone suite."))
        return false
    end
    if profilesPrepared then return true end
    local profiles = Suite.SuiteProfiles
    Step(Suite.Skin, "SetEnabled", Suite.RootDB.skinEnabled ~= false)
    Step(profiles, "EnsureNewCharacterProfile")
    Step(Suite.ProfileVariants,"Register")
    Step(profiles, "SyncActive", Suite.HostBridge.ActiveFrameProfileName() or "Default")
    Step(Suite.ProfileVariants,"Start")
    Step(profiles, "EnsureRetailForeverCooldownLayout")
    profilesPrepared = true
    return true
end

function Start(transition)
    if startupFinished or Suite.startupError then return end
    if not PrepareProfiles(transition) then
        if Suite.startupError then SetCombatWait(false) end
        return
    end
    local beforeLockdown = transition == "PLAYER_ENTERING_WORLD"
    if beforeLockdown then
        -- Settle the saved UI scale before the skin or modules measure UIParent.
        local applyScale = Suite.HostBridge.Profiles.ApplyCurrentProfileGlobalUiScale
        if applyScale then Suite.Dispatch(applyScale) end
        Step(Suite.Skin, "ApplyStartupLayout")
    else
        startupFinished = true
        SetCombatWait(false)
    end
    if not Suite.Suite.started then
        Suite.startingModules = true
        Step(Suite.Suite, "Start")
        Suite.startingModules = nil
        local ran, ok, reason = Suite.Dispatch(Suite.Finish, Suite.ProfileIO.StartNameplateProfile, transition)
        if ran and not ok and reason then Suite.Print(Suite.Text(reason)) end
    end
    -- Profile repairs and setup retain their normal post-combat start path.
    if beforeLockdown then
        Step(Suite.Skin, "FinishStartupLayout")
        startedBeforeLockdown = Suite.Suite.started == true
        return
    end
    if startedBeforeLockdown then Step(Suite.Suite, "RetryStartup") end
    local profiles = Suite.SuiteProfiles
    Step(profiles, "EnsureModernPanelLayout")
    Step(profiles, "EnsureModernDarkTooltips")
    Step(profiles, "EnsureModernDarkMinimap")
    Step(profiles, "EnsureRetailResourceStack", false)
    ShowInstaller()
end

-- Finish the login dispatch before loading optional addons. AceAddon may
-- enable unrelated addons on a nested ADDON_LOADED while login is in flight.
local startQueued = false
local function RunStart()
    startQueued = false
    WatchCombatStart(false)
    Start(combatEvent)
end

local function QueueStart(beforeSkinLogin)
    if startQueued then return end
    -- An already loaded skin must see the selected profile on its login pass.
    -- An unloaded skin stays in the deferred path: profile sync may load it.
    if beforeSkinLogin and Suite.Client.IsAddOnLoaded("MSUF_Suite_Skin") and Suite.Skin.IsAvailable() then
        if not PrepareProfiles() then return end
    end
    -- Combat can end before the queued callback reads the unit combat flag.
    SetCombatWait(true)
    startQueued = true
    C_Timer.After(0, RunStart)
end

function FinishWorldEntry()
    if waitingForCombat and not startupFinished then
        if not startQueued then RunStart() end
    else
        ShowInstaller()
    end
end

events:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" then
        if loadedAddon ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        if not Initialize() then
            self:UnregisterAllEvents()
            return
        end
        -- Load the Suite-owned skin engine before PLAYER_LOGIN so it can skin
        -- Blizzard's first visible frames without a reload.
        if Suite.RootDB.skinEnabled ~= false then Step(Suite.Skin, "EnsureEngine") end
        Step(Suite.Menu, "Watch")
        if IsLoggedIn() then
            self:UnregisterEvent("PLAYER_LOGIN")
            QueueStart()
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent(event)
        QueueStart(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if startupFinished then
            ShowInstaller()
        else
            if not combatEvent then self:RegisterEvent("PLAYER_REGEN_DISABLED") end
            combatEvent = event
            WatchCombatStart(false)
            QueueStart()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if watchingCombatStart then
            -- The client sends this event before lockdown begins.
            WatchCombatStart(false)
            if not Suite.Suite.started and not Suite.IsCombatLocked() then StartBeforeLockdown() end
        else
            combatEvent = event
        end
    end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
