local addonName, NS = ...

local initialized = false
local loginApplied = false
local loginQueued = false
local eventFrame = CreateFrame("Frame")

local function InitializeDatabase()
    if initialized then
        return
    end
    NS.InitializeLocalization()
    NS.Database.Initialize()
    NS.PublicAPI.OnDatabaseReady()
    initialized = true
end

-- LoadAddOn exposes the provider before its ADDON_LOADED notification reaches
-- this frame. The Suite can need profiles during that gap.
NS.EnsureDatabaseReady = InitializeDatabase

-- True until the login pass below has run (Database.ApplyActiveSettings
-- leaves the adapter pass to it).
NS.Database.loginPassPending = true

-- A Suite user can enable skinning after PLAYER_LOGIN. The same startup
-- path must work whether the load-on-demand engine starts early or late.
-- Each stage is its own boundary: login runs once, so a stage that raises
-- is reported and the later stages (and API clients) still start.
local function ApplyLogin()
    if loginApplied then return end
    loginQueued = false
    InitializeDatabase()
    loginApplied = true
    NS.Database.loginPassPending = false
    local dispatch = NS.Safety.Dispatch
    dispatch(NS.Theme.RefreshDynamicLook)
    dispatch(NS.BlizzardYellow.Apply)
    dispatch(NS.Checkmarks.Apply)
    dispatch(NS.Typography.ApplyConfigured)
    dispatch(NS.Adapters.ApplyAll)
    -- Prepare hidden native combat windows on the next frame, outside
    -- PLAYER_LOGIN, so their protected shells can be painted while unlocked.
    if NS.Client.isMainline then C_Timer.After(0, NS.Adapters.PrepareCombatWindows) end
    dispatch(NS.PublicAPI.OnPlayerLogin)
end
NS.EnsureLoginApplied = ApplyLogin

local function StartLogin()
    if loginApplied or loginQueued then return end
    if NS.Client.isForever and NS.IsCombatLocked() and not NS.SuiteCore().IsCombatLocked() then
        -- Let the Suite select the skin profile at world entry. Other
        -- login paths still run the usual guarded pass on the next frame.
        loginQueued = true
        C_Timer.After(0, ApplyLogin)
        return
    end
    ApplyLogin()
end

eventFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" then
        if loadedAddon ~= addonName then
            return
        end
        InitializeDatabase()
        self:UnregisterEvent("ADDON_LOADED")
        if IsLoggedIn() then StartLogin() end
        return
    end

    if event == "PLAYER_LOGIN" then
        StartLogin()
        self:UnregisterEvent("PLAYER_LOGIN")
        return
    end

    if event == "PLAYER_LOGOUT" then
        NS.ChatFramesSkin.RestoreBlizzardMessageColors()
    end
end)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
