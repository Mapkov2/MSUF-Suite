local addonName, NS = ...

local initialized = false
local loginApplied = false
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

-- A Suite user can enable skinning after PLAYER_LOGIN. The same startup
-- path must work whether the load-on-demand engine starts early or late.
-- Each stage is its own boundary: login runs once, so a stage that raises
-- is reported and the later stages (and API clients) still start.
local function ApplyLogin()
    if loginApplied then return end
    InitializeDatabase()
    loginApplied = true
    local dispatch = NS.Safety.Dispatch
    dispatch(NS.Theme.RefreshDynamicLook)
    dispatch(NS.BlizzardYellow.Apply)
    dispatch(NS.Checkmarks.Apply)
    dispatch(NS.Typography.ApplyConfigured)
    dispatch(NS.Adapters.ApplyAll)
    dispatch(NS.PublicAPI.OnPlayerLogin)
end

eventFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" then
        if loadedAddon ~= addonName then
            return
        end
        InitializeDatabase()
        self:UnregisterEvent("ADDON_LOADED")
        if IsLoggedIn() then ApplyLogin() end
        return
    end

    if event == "PLAYER_LOGIN" then
        ApplyLogin()
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
