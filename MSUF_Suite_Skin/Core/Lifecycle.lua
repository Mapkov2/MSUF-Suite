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
    if NS.PublicAPI then NS.PublicAPI.OnDatabaseReady() end
    initialized = true
end

-- LoadAddOn exposes the provider before its ADDON_LOADED notification reaches
-- this frame. The Suite can need profiles during that gap.
NS.EnsureDatabaseReady = InitializeDatabase

local function ApplyLogin()
    if loginApplied then return end
    InitializeDatabase()
    loginApplied = true
    -- A Suite user can enable skinning after PLAYER_LOGIN. The same startup
    -- path must work whether the load-on-demand engine starts early or late.
    NS.Theme.RefreshDynamicLook()
    NS.BlizzardYellow.Apply()
    NS.Checkmarks.Apply()
    NS.Typography.ApplyConfigured()
    NS.Adapters.ApplyAll()
    if NS.PublicAPI then NS.PublicAPI.OnPlayerLogin() end
end

eventFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" then
        if loadedAddon ~= addonName then
            return
        end
        InitializeDatabase()
        self:UnregisterEvent("ADDON_LOADED")
        if type(IsLoggedIn) == "function" and IsLoggedIn() then ApplyLogin() end
        return
    end

    if event == "PLAYER_LOGIN" then
        ApplyLogin()
        self:UnregisterEvent("PLAYER_LOGIN")
        return
    end

    if event == "PLAYER_LOGOUT" then
        local chatFrames = NS.ChatFramesSkin
        if chatFrames and type(chatFrames.RestoreBlizzardMessageColors) == "function" then
            chatFrames.RestoreBlizzardMessageColors()
        end
    end
end)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
