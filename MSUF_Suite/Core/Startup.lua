local addonName, Suite = ...
_G.MSUFSuite = Suite

local initialized = false
local events = CreateFrame("Frame")
local function CaptureGoldStart(isReloadingUi)
    Suite.goldSessionCaptured = false
    local root = Suite.RootDB
    if type(root) ~= "table" or type(_G.UnitGUID) ~= "function" or type(_G.GetMoney) ~= "function" then return end
    local okGuid, guid = pcall(UnitGUID, "player")
    local okMoney, money = pcall(GetMoney)
    if not okGuid or not okMoney then return end
    local secret = _G.issecretvalue
    if type(secret) == "function" and (secret(guid) or secret(money)) then return end
    if type(guid) ~= "string" or guid == "" or type(money) ~= "number"
        or money ~= money or money < 0 or money == math.huge then return end
    if type(root.suiteGold) ~= "table" then root.suiteGold = {} end
    local previous = root.suiteGold[guid]
    if isReloadingUi == true and type(previous) == "number"
        and previous >= 0 and previous == previous and previous < math.huge then
        Suite.goldSessionCaptured = true
        return
    end
    root.suiteGold[guid] = money
    Suite.goldSessionCaptured = true
end
-- PLAYER_ENTERING_WORLD distinguishes a real login from /reload. Optional
-- modules loaded later can use this without keeping their own startup frame.
local loginEvent = CreateFrame("Frame")
loginEvent:RegisterEvent("PLAYER_ENTERING_WORLD")
loginEvent:SetScript("OnEvent", function(self, _, isInitialLogin, isReloadingUi)
    Suite.loginKind = isReloadingUi == true and "reload" or "login"
    CaptureGoldStart(isReloadingUi)
    if Suite.Installer and Suite.Suite.started then Suite.Installer.MaybeShow() end
    self:UnregisterAllEvents()
end)

local function Initialize()
    if initialized then return true end
    Suite.freshInstall = _G.MSUFSuiteDB == nil and _G.MapkoSkinDB == nil
    -- Older Suite profiles may live inside MapkoSkinDB. Load the legacy addon
    -- as data only before choosing the Suite profile, then hand skinning to the
    -- Suite-owned engine below.
    if _G.MSUFSuiteDB == nil and Suite.Skin and Suite.Skin.LoadLegacyDatabase then
        Suite.Skin.LoadLegacyDatabase()
    end
    local ok, reason = Suite.Database.Initialize(_G.MSUFSuiteDB, _G.MapkoSkinDB)
    if not ok then
        Suite.startupError = reason
        Suite.Print("Cannot load suite profiles: " .. tostring(reason))
        return false
    end
    _G.MSUFSuiteDB = Suite.RootDB
    initialized = true
    return true
end

local function Start()
    if not Initialize() then return end
    if Suite.IsCombatLocked and Suite.IsCombatLocked() then
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
    if Suite.Skin then Suite.Skin.SetEnabled(Suite.RootDB.skinEnabled ~= false) end
    if Suite.SuiteProfiles and Suite.SuiteProfiles.SyncActive then
        Suite.SuiteProfiles.SyncActive(_G.MSUF_ActiveProfile or "Default")
    end
    Suite.Suite.Start()
    if Suite.Installer then Suite.Installer.MaybeShow() end
end

events:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" then
        if loadedAddon ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        if not Initialize() then self:UnregisterAllEvents(); return end
        -- Load the Suite-owned skin engine before PLAYER_LOGIN so it can skin
        -- Blizzard's first visible frames without a reload.
        if Suite.Skin and Suite.RootDB.skinEnabled ~= false then Suite.Skin.EnsureEngine() end
        if Suite.Menu then Suite.Menu.Watch() end
        if type(IsLoggedIn) == "function" and IsLoggedIn() then
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
