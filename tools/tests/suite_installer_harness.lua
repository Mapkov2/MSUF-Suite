-- Shared by the installer session tests (not a test itself). Loads the real
-- MSUF_Suite core in TOC order through Core/Installer.lua on a client model:
-- widget stubs that record what the installer shows, MSUF's profile and scale
-- API, and an optional Suite skin engine with the surface Profiles.lua uses.
local H = {}

local function Widget(kind)
    local w = { kind = kind, scripts = {}, shown = true, width = 0, height = 0 }
    local methods = {}
    function methods:SetScript(name, callback) self.scripts[name] = callback end
    function methods:GetScript(name) return self.scripts[name] end
    function methods:HookScript(name, callback) self.scripts[name] = callback end
    function methods:Show() self.shown = true end
    function methods:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function methods:SetShown(value) if value then self:Show() else self:Hide() end end
    function methods:IsShown() return self.shown end
    function methods:SetSize(width, height) self.width, self.height = width, height end
    function methods:SetWidth(width) self.width = width end
    function methods:SetHeight(height) self.height = height end
    function methods:GetWidth() return self.width end
    function methods:GetHeight() return self.height end
    function methods:SetText(text) self.text = text end
    function methods:GetText() return self.text end
    -- Blizzard's Slider: SetValue runs OnValueChanged when the value changes.
    function methods:SetValue(value)
        local old = self.value
        self.value = value
        if old ~= value and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value, false) end
    end
    function methods:GetValue() return self.value end
    function methods:SetScrollChild(child) self.scrollChild = child end
    function methods:GetScrollChild() return self.scrollChild end
    function methods:CreateFontString() return Widget("FontString") end
    function methods:CreateTexture() return Widget("Texture") end
    function methods:IsForbidden() return false end
    setmetatable(w, { __index = function(_, key)
        if methods[key] then return methods[key] end
        return function() end
    end })
    local function Region() return setmetatable({}, { __index = function() return function() end end }) end
    -- OptionsSliderTemplate's labels.
    w.Low, w.High, w.Text = Region(), Region(), Region()
    return w
end
H.Widget = Widget

local function TocFiles(root)
    local toc = assert(io.open(root .. "/MSUF_Suite/MSUF_Suite_Mainline.toc", "rb"))
    local text = toc:read("*a"):gsub("\r", "")
    toc:close()
    local files = {}
    for line in text:gmatch("[^\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then files[#files + 1] = (line:gsub("\\", "/")) end
    end
    return files
end

-- options: root (required), forever, msuf (MSUF_NS: LOCALE and L for a locale
-- pack), uiHeight, addons (enable state by name),
-- frameFactory() (the frame profile MSUF's import creates), afterImport(name,
-- profile) (MSUF's runtime apply after the import).
function H.Setup(options)
    H.reported, H.chat, H.combat = {}, {}, false
    securecallfunction = function(callback, ...)
        local results = { pcall(callback, ...) }
        if not results[1] then
            H.reported[#H.reported + 1] = tostring(results[2])
            return
        end
        return unpack(results, 2, table.maxn(results))
    end
    MSUF_NS = options.msuf or {}
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
    GameEvent = options.forever and { RegisterCamelotEvents = function() end } or nil
    SlashCmdList = {}
    InCombatLockdown = function() return H.combat end
    UnitAffectingCombat = function() return H.combat end
    UnitClass = function() return "Warrior", "WARRIOR" end
    C_ClassColor = { GetClassColor = function() return { r = 0.78, g = 0.61, b = 0.43 } end }
    UnitGUID = function() return "Player-1-0001" end
    UnitName = function() return "Tester" end
    GetRealmName = function() return "Realm" end
    GetServerTime = function() return 1000 end
    GetMoney = function() return 0 end
    C_EventUtils = { IsEventValid = function() return true end }
    C_CVar = { GetCVar = function() return "0" end }
    C_Timer = { After = function() end }
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) H.chat[#H.chat + 1] = message end }
    Enum = {}
    hooksecurefunc = function() end
    IsLoggedIn = function() return true end
    ReloadUI = function() end
    CreateFrame = function(kind, name)
        local w = Widget(kind)
        if name then _G[name] = w end
        return w
    end
    UIParent = Widget("Frame")
    UIParent.height = options.uiHeight or 1440
    UISpecialFrames = {}
    GameTooltip = Widget("GameTooltip")
    EventRegistry = { TriggerEvent = function() end }
    H.addons, H.loaded = options.addons or {}, {}
    C_AddOns = {
        DoesAddOnExist = function(name) return H.addons[name] ~= nil end,
        GetAddOnEnableState = function(name) return H.addons[name] and 2 or 0 end,
        IsAddOnLoaded = function(name) return H.loaded[name] or false end,
        GetAddOnMetadata = function() return "1.0" end,
        LoadAddOn = function(name)
            if name == "MSUF_Suite_Skin" and H.addons[name] and H.skin then
                _G.MapkoSkin = H.skin
                H.loaded[name] = true
                return true
            end
            return false, "MISSING"
        end,
    }
    -- MSUF's codec: every bundled Suite string decodes to a minimal valid Suite profile.
    MSUF_EncodeCompactTable = function() return "MSUF3:x" end
    MSUF_TryDecodeCompactString = function(text)
        if type(text) ~= "string" or text:sub(1, 6) ~= "MSUF3:" then return nil end
        return { addon = "MSUF_Suite", format = 1, profile = { suite = { schema = 1, revision = 0, modules = {} } } }
    end
    -- MSUF: its profile store, the scale API and the transactional import.
    MSUF_GlobalDB = { profiles = { Default = { general = {} } } }
    MSUF_ActiveProfile = "Default"
    MSUF_DB = MSUF_GlobalDB.profiles.Default
    MSUF_ResetGlobalUiScale = function() end
    MSUF_ApplyMsufScale = function() end
    MSUF_SetGlobalUiScale = function() end
    H.appliedScales = {}
    MSUF_HostAPI = { version = 1, SetResourceStack = function() return false, false end,
        ApplyUIScaleProfile = function(spec)
            H.appliedScales[#H.appliedScales + 1] = spec
            return true
        end }
    MSUF_Profiles_ExportSelectionToString = function() return "MSUF3:frames" end
    MSUF_Profiles_ImportIntoNewProfile = function(name)
        local profile = options.frameFactory and options.frameFactory() or { general = {} }
        profile.general = profile.general or {}
        MSUF_GlobalDB.profiles[name] = profile
        MSUF_ActiveProfile, MSUF_DB = name, profile
        if options.afterImport then options.afterImport(name, profile) end
        return true
    end
    MSUF_SwitchProfile = function(name)
        if not MSUF_GlobalDB.profiles[name] then return false end
        MSUF_ActiveProfile, MSUF_DB = name, MSUF_GlobalDB.profiles[name]
        local suite = _G.MSUFSuite
        if suite and suite.OnMSUFProfileChanged then suite.OnMSUFProfileChanged(name, "PROFILE_SWITCH") end
        return true
    end
    MSUF_DeleteProfile = function(name)
        MSUF_GlobalDB.profiles[name] = nil
        local suite = _G.MSUFSuite
        if suite and suite.OnMSUFProfileLifecycle then suite.OnMSUFProfileLifecycle("delete", name) end
        return true
    end
    MSUF_GetDefaultProfileForNewCharacters = function() return "Default" end
    MSUF_SetDefaultProfileForNewCharacters = function() return true end
    local Suite = {}
    for _, file in ipairs(TocFiles(options.root)) do
        if file:match("%.lua$") then assert(loadfile(options.root .. "/MSUF_Suite/" .. file))("MSUF_Suite", Suite) end
        if file == "Core/Installer.lua" then break end
    end
    _G.MSUFSuite = Suite
    assert(Suite.Database.Initialize(nil, nil))
    Suite.RootDB.installation = { revision = 3, status = "pending" }
    return Suite
end

-- A Suite skin engine: its profile store and ProfileIO.
function H.FakeSkin(profiles, active)
    local root = { profiles = profiles or { Default = { enabled = true } }, activeProfile = active or "Default" }
    local DB = {}
    function DB.GetRoot() return root end
    function DB.GetActiveProfileName() return root.activeProfile end
    function DB.GetProfile(name) return root.profiles[name] end
    function DB.SetProfile(name, profile) root.profiles[name] = profile; return true, name end
    function DB.CreateProfile(name, copy)
        if root.profiles[name] then return false, "profile-exists" end
        root.profiles[name] = { enabled = true, copied = copy == true }
        return true, name
    end
    function DB.SetActiveProfile(name)
        if not root.profiles[name] then return false, "missing-profile" end
        root.activeProfile = name
        return true, name
    end
    function DB.DeleteProfile(name)
        if not root.profiles[name] then return false, "missing-profile" end
        root.profiles[name] = nil
        return true, name
    end
    H.skin = {
        addonName = "MSUF_Suite_Skin", root = root, Database = DB,
        EnsureDatabaseReady = function() end,
        GetAPI = function() return nil end,
        ProfileIO = {
            ExportProfile = function() return "MSKIN1:x" end,
            PrepareProfile = function() return { enabled = true, icons = {} } end,
        },
        Theme = { StyleProfile = function() return true end },
    }
    return H.skin
end

-- The installer's window: Continue through the pages to the review page,
-- then Install.
function H.Install(Suite)
    assert(Suite.Installer.Open())
    local frame = assert(_G.MSUFSuiteInstallFrame, "the installer window is missing")
    for _ = 1, 4 do frame.next.scripts.OnClick() end
    frame.next.scripts.OnClick()
    return frame
end

return H
