local addonName, Suite = ...
_G.MSUFSuite = Suite

local initialized = false
local events = CreateFrame("Frame")

-- PLAYER_ENTERING_WORLD distinguishes a real login from /reload. Optional
-- modules loaded later can use this without keeping their own startup frame.
local loginEvent = CreateFrame("Frame")
loginEvent:RegisterEvent("PLAYER_ENTERING_WORLD")
loginEvent:SetScript("OnEvent", function(self, _, isInitialLogin, isReloadingUi)
    -- Only the first world entry counts; later ones are zone changes.
    self:UnregisterAllEvents()
    Suite.loginKind = isReloadingUi == true and "reload" or "login"
    Suite.CaptureSessionGold(isReloadingUi)
    -- "login": the installer waits while MSUF's own first run is pending (Installer.lua).
    if Suite.Suite.started then Suite.Installer.MaybeShow("login") end
end)

local function Initialize()
    if initialized then return true end
    Suite.freshInstall = _G.MSUFSuiteDB == nil and _G.MapkoSkinDB == nil
    -- Older Suite profiles may live inside MapkoSkinDB. Load the legacy addon
    -- as data only before choosing the Suite profile, then hand skinning to the
    -- Suite-owned engine below.
    if _G.MSUFSuiteDB == nil then Suite.Skin.LoadLegacyDatabase() end
    local ok, reason, quarantined = Suite.Database.Initialize(_G.MSUFSuiteDB, _G.MapkoSkinDB)
    if not ok then
        Suite.startupError = reason
        Suite.Print("Cannot load suite profiles: " .. tostring(reason))
        return false
    end
    -- Reported once: the saved root keeps them set aside from now on.
    if quarantined > 0 then
        Suite.Print(Suite.Text("Unreadable Suite profiles were set aside, their data is kept: %d"):format(quarantined))
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

local function Start()
    if not Initialize() then return end
    if Suite.IsCombatLocked() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local legacy = _G.MapkoSkin and _G.MapkoSkin.Suite
    if legacy and legacy.started then
        -- A manually loaded suite must not take ownership from a running old
        -- development runtime. Reloading allows the owner guard to run first.
        Suite.startupError = "legacy-runtime-active"
        Suite.Print("Reload the interface to start the standalone suite.")
        return
    end
    local profiles = Suite.SuiteProfiles
    Step(Suite.Skin, "SetEnabled", Suite.RootDB.skinEnabled ~= false)
    Step(profiles, "EnsureNewCharacterProfile")
    Step(Suite.ProfileVariants,"Register")
    Step(profiles, "SyncActive", _G.MSUF_ActiveProfile or "Default")
    Step(Suite.ProfileVariants,"Start")
    Step(profiles, "EnsureRetailForeverCooldownLayout")
    Step(Suite.Suite, "Start")
    Step(profiles, "EnsureRetailResourceStack", false)
    Step(Suite.Installer, "MaybeShow", "login")
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
            Start()
        end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterAllEvents()
        Start()
    end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
