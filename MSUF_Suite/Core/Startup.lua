local addonName, Suite = ...
_G.MSUFSuite = Suite

local initialized = false
local events = CreateFrame("Frame")

local function ShowInstaller()
    if Suite.startupError or not Suite.Suite.started then return end
    if Suite.InCombat() and Suite.Installer.IsFirstRunPending() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    Suite.Dispatch(Suite.Installer.MaybeShow, "login")
end

-- PLAYER_ENTERING_WORLD distinguishes a real login from /reload. Optional
-- modules loaded later can use this without keeping their own startup frame.
local loginEvent = CreateFrame("Frame")
loginEvent:RegisterEvent("PLAYER_ENTERING_WORLD")
loginEvent:SetScript("OnEvent", function(self, _, isInitialLogin, isReloadingUi)
    -- Only the first world entry counts; later ones are zone changes.
    self:UnregisterAllEvents()
    Suite.loginKind = isReloadingUi == true and "reload" or "login"
    Suite.CaptureSessionGold(isReloadingUi)
    -- After the skin's PLAYER_LOGIN pass: chat colours an off skin left.
    Suite.Dispatch(Suite.Skin.SettleChatColors)
    -- The next frame follows client login readiness and all startup listeners.
    -- One attempt only; unfinished setup remains pending for the next login.
    C_Timer.After(0, ShowInstaller)
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

local profilesPrepared = false
local function PrepareProfiles()
    if not Initialize() then return end
    if Suite.InCombat() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
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

local function Start()
    if not PrepareProfiles() then return end
    local profiles = Suite.SuiteProfiles
    Suite.startingModules = true
    Step(Suite.Suite, "Start")
    Suite.startingModules = nil
    Step(profiles, "EnsureModernPanelLayout")
    Step(profiles, "EnsureModernDarkTooltips")
    Step(profiles, "EnsureModernDarkMinimap")
    Step(profiles, "EnsureRetailResourceStack", false)
    Step(Suite.Installer, "MaybeShow", "login")
end

-- Finish the login dispatch before loading optional addons. AceAddon may
-- enable unrelated addons on a nested ADDON_LOADED while login is in flight.
local startQueued = false
local function RunStart()
    startQueued = false
    Start()
end
local function QueueStart(beforeSkinLogin)
    if startQueued then return end
    -- An already loaded skin must see the selected profile on its login pass.
    -- An unloaded skin stays in the deferred path: profile sync may load it.
    if beforeSkinLogin and Suite.Client.IsAddOnLoaded("MSUF_Suite_Skin") and Suite.Skin.IsAvailable() then
        if not PrepareProfiles() then return end
    end
    startQueued = true
    C_Timer.After(0, RunStart)
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
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterAllEvents()
        if event == "PLAYER_REGEN_ENABLED" and Suite.Suite.started then ShowInstaller() else QueueStart(event == "PLAYER_LOGIN") end
    end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
