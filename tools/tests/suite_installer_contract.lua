local root = assert(arg[1], "repository root required")
local Suite = {
    Client = { isForever = false, isMainline = true },
    Host = { build = "Classic" },
    RootDB = { profiles = { Default = {} } },
    RetailFactoryModuleCompact = "MSUFM1:MSUF3:retail",
    RetailFactorySkinCompact = "MSKIN1:modern",
    ForeverFactoryModuleCompact = "MSUFM1:MSUF3:forever",
    Defaults = { suite = { modules = { nameplates = {
        enabled = false, look = 1, nativeStyle = 2, nativeSize = 3,
    } } } },
    ForeverFactorySkinCompact = "MSKIN1:forever",
    ForeverFactoryFramesCompact = "MSUF3:frames",
    ClassicFactoryFramesCompact = "MSUF3:bundled-classic-frames",
    CDM = { DEFAULTS_VERSION = 3, FRAME_ANCHORS = { [14] = "player" } },
    SuiteOrder = { "chat", "bags", "minimap", "damageMeter", "dataTexts",
        "buffReminders", "qol", "quests", "loot", "combatLog", "xpBar",
        "skyriding", "cooldownManager", "objectives", "announcements",
        "afkScreen", "actionbars" },
    SuiteCatalog = {},
}
for _, id in ipairs(Suite.SuiteOrder) do Suite.SuiteCatalog[id] = { title = id } end
local factoryCalls, activations, scaleChanges, decodes = 0, 0, {}, 0

Suite.IsCombatLocked = function() return false end
Suite.Suite = { StyleProfile = function(profile, look)
    profile.suite.globalLook = look
    return true
end }
-- The core's translation lookup and status display (MSUF_Suite/Core/Platform.lua).
Suite.Text = function(english)
    local value = Suite.L and Suite.L[english]
    return type(value) == "string" and value ~= "" and value or english
end
Suite.StatusText = function(text, translate) return translate(text) end
Suite.RGB = function(hex)
    return tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255
end
-- MSUF_Suite/Core/Database.lua's deep copy.
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end
local copies = 0
Suite.CopyValue = function(value)
    copies = copies + 1
    return Copy(value)
end
Suite.Print = function() end
Suite.Client.AddOnEnabled = function() return true end
Suite.Client.AttachControllerWindow = function() end
Suite.Client.ResumeControllerWindow = function() end
Suite.Client.RaiseControllerCursor = function() end
Suite.Database = {
    IsProfileName = function(name) return type(name) == "string" and name ~= "" end,
    GetActiveProfileName = function() return "Default" end,
    GetProfile = function(name) return Suite.RootDB.profiles[name] end,
    Activate = function(name)
        assert(Suite.RootDB.profiles[name])
        activations = activations + 1
        Suite.DB = Suite.RootDB.profiles[name]
        return true
    end,
}
Suite.ProfileIO = {
    PrepareProfile = function(text, shared)
        decodes = decodes + 1
        assert(shared == false, "installer factory was sanitized as an external import")
        assert(text == Suite.RetailFactoryModuleCompact or text == Suite.ForeverFactoryModuleCompact)
        local modules = {}
        for _, id in ipairs(Suite.SuiteOrder) do modules[id] = { enabled = true } end
        modules.nameplates = { enabled = true, look = 4, nativeStyle = 2, barGeometry = 2 }
        modules.bags.enabled = text == Suite.RetailFactoryModuleCompact
        modules.actionbars.enabled = true
        if text == Suite.ForeverFactoryModuleCompact then
            modules.actionbars.bar1Point = 8
            modules.actionbars.bar3Point = 7
            modules.actionbars.bar3X, modules.actionbars.bar3Y = 1039, 145
            modules.cooldownManager.captured = false
            modules.cooldownManager.defaultsVersion = 0
            modules.cooldownManager.ext_anchor = 3
            modules.cooldownManager.ext_y = -380
            modules.cooldownManager.listsData = ""
        end
        if text == Suite.RetailFactoryModuleCompact then
            modules.cooldownManager.listsData = "MSUF3:factoryRogue"
        end
        return { suite = { schema = 1, modules = modules } }
    end,
}
Suite.SuiteProfiles = {
    -- The follow-up repairs belong to suite_profiles_contract.
    EnsureNewCharacterProfile = function() return false end,
    EnsureRetailResourceStack = function() return false end,
    InstallSuiteFactory = function(name, profile, skin, look)
        assert(name == "Default" and skin == (Suite.Client.isForever
            and Suite.ForeverFactorySkinCompact or Suite.RetailFactorySkinCompact))
        assert(look == (profile.suite.globalLook == "midnight" and "midnight" or "cleanModern"))
        assert(profile.suite.modules.dataTexts.bar1Point == 8
            and profile.suite.modules.dataTexts.bar1X == 0
            and profile.suite.modules.actionbars.bar1Point == 8
            and profile.suite.modules.actionbars.bar3Point == 7
            and profile.suite.modules.minimap.x == -20,
            "Modern factory positions did not use screen anchors")
        Suite.RootDB.profiles[name] = profile
        Suite.Database.Activate(name)
        return true, name
    end,
    InstallFactory = function(name, frames, profile, skin, look)
        factoryCalls = factoryCalls + 1
        if look == "midnight" then
            assert(name == (Suite.Client.isForever and "MSUF Suite Classic 2" or "MSUF Suite Classic")
                and frames == (Suite.Client.isForever and Suite.ClassicFactoryFramesCompact
                    or MSUF_NS.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT)
                and skin == (Suite.Client.isForever and Suite.ForeverFactorySkinCompact
                    or Suite.RetailFactorySkinCompact)
                and profile.suite.globalLook == "midnight",
                "Classic MSUF must install a complete frame, Suite and Skin factory")
            MSUF_GlobalDB.profiles[name] = {}
            Suite.RootDB.profiles[name] = profile
            MSUF_ActiveProfile = name
            Suite.Database.Activate(name)
            return true, name
        end
        assert(name == "MSUF Suite Forever")
        assert(frames == "MSUF3:frames")
        assert(skin == "MSKIN1:forever")
        assert(profile.suite.modules.chat.enabled)
        assert(profile.suite.modules.nameplates.enabled
            and profile.suite.modules.nameplates.look == 4
            and profile.suite.modules.nameplates.barGeometry == 2
            and profile.suite.modules.nameplates.nativeStyle == 2,
            "Forever factory omitted the portable Mapko nameplate preset")
        assert(profile.suite.modules.bags.enabled)
        assert(profile.suite.modules.actionbars.enabled
            and profile.suite.modules.actionbars.bar3Point == 7
            and profile.suite.modules.actionbars.bar3X == 1039
            and profile.suite.modules.actionbars.bar3Y == 145,
            "Forever factory must preserve exported Action Bars settings")
        assert(profile.suite.modules.minimap.x == -20
            and profile.suite.modules.xpBar.point == 2
            and profile.suite.modules.xpBar.y == -24
            and profile.suite.modules.actionbars.bar1Point == 8,
            "Forever factory retained display-specific offsets")
        local cdm = profile.suite.modules.cooldownManager
        assert(cdm.enabled and cdm.raidEssentials == true and cdm.captured == true
            and cdm.defaultsVersion == 3
            and cdm.def_anchor == 14 and cdm.def_side == 2
            and cdm.def_gap == 44 and cdm.def_align == 3 and cdm.def_y == 0
            and cdm.ext_anchor == 14 and cdm.ext_side == 1
            and cdm.ext_gap == 22 and cdm.ext_align == 2 and cdm.ext_y == 0
            and cdm.listsData == "MSUF3:factoryRogue",
            "Retail Forever did not retain CDM presets and anchor its side rows to Player")
        return true, name
    end,
}

MSUF_NS = { MSUF_FOREVER_FACTORY_DEFAULT_PROFILE_COMPACT = "MSUF3:frames",
    MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = "MSUF3:retail-classic-frames" }
MSUF_ActiveProfile = "Default"
MSUF_DB = { general = { UIScale = { Enabled = true, Scale = 0.53 }, msufUiScale = 0.9 } }
MSUF_GlobalDB = { profiles = { Default = {} } }
MSUF_ApplyMsufScale = function(value) scaleChanges[#scaleChanges + 1] = { "frame", value } end
MSUF_ResetGlobalUiScale = function()
    MSUF_DB.general.UIScale.Enabled = false
    scaleChanges[#scaleChanges + 1] = { "reset" }
    return true
end
MSUF_SetGlobalUiScale = function(value) scaleChanges[#scaleChanges + 1] = { "global", value } end
SlashCmdList = {}
UIParent = {}

local function FakeFrame()
    local frame = { scripts = {}, shown = true }
    local methods = {
        SetScript = function(self, name, callback) self.scripts[name] = callback end,
        CreateFontString = function() return FakeFrame() end,
        CreateTexture = function() return FakeFrame() end,
        SetSize = function(self, width, height) self.width, self.height = width, height end,
        SetPoint = function(self, anchor, _, _, x, y)
            if type(x) == "number" then self.x, self.y = x, y end
            self.anchor = anchor
        end,
        SetValue = function(self, value)
            self.value = value
            if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
        end,
        SetText = function(self, value) self.text = value end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetShown = function(self, shown) self.shown = shown end,
    }
    return setmetatable(frame, { __index = function(_, key) return methods[key] or function() end end })
end
CreateFrame = function(_, name, _, template)
    local frame = FakeFrame()
    if name then _G[name] = frame end
    if template == "OptionsSliderTemplate" then frame.Low, frame.High, frame.Text = FakeFrame(), FakeFrame(), FakeFrame() end
    return frame
end
GameTooltip = FakeFrame()
IsLoggedIn = function() return true end
ReloadUI = function() end
GetLocale = function() return "enUS" end
UISpecialFrames = {}

-- The scale goes through the Suite's host bridge; this MSUF has no host API v1.
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", Suite)
assert(loadfile(root .. "/MSUF_Suite/Core/Installer.lua"))("MSUF_Suite", Suite)
assert(Suite.Installer.Apply())
assert(factoryCalls == 0 and activations == 1)
assert(Suite.RootDB.profiles.Default.suite.modules.chat.enabled)
assert(Suite.RootDB.profiles.Default.suite.modules.bags.enabled)
assert(Suite.RootDB.profiles.Default.suite.modules.cooldownManager.raidEssentials == true
    and Suite.RootDB.profiles.Default.suite.modules.cooldownManager.listsData == "MSUF3:factoryRogue",
    "fresh Modern install should keep the bundled Rogue layout and use spec defaults elsewhere")
assert(MSUF_DB.general.UIScale.Enabled == false and MSUF_DB.general.msufUiScale == 1)
assert(#scaleChanges == 2 and scaleChanges[1][1] == "frame" and scaleChanges[2][1] == "reset")
assert(Suite.RootDB.installation.status == "complete"
    and Suite.RootDB.installation.profile == "suite"
    and Suite.RootDB.installation.uiScaleEnabled == false)

local resetScale = MSUF_ResetGlobalUiScale
MSUF_ResetGlobalUiScale = nil
local applied = Suite.Installer.Apply()
assert(applied == false and activations == 1 and factoryCalls == 0,
    "Missing scale controls changed a profile before failing")
MSUF_ResetGlobalUiScale = resetScale

Suite.Installer.Open()
local window = assert(MSUFSuiteInstallFrame)
copies = 0
local function CheckLayout()
    local panels = { window.suite, window.classic, window.forever, window.cooldowns, window.scaleToggle,
        window.back, window.close, window.next, window.scaleSlider }
    for _, group in ipairs({ window.intro, window.moduleRows, window.presets, window.review, window.done }) do
        for _, panel in ipairs(group) do panels[#panels + 1] = panel end
    end
    for i, a in ipairs(panels) do
        if a.shown then
            assert(a.x >= 0 and a.y >= 0 and a.x + a.width <= window.width
                and a.y + a.height <= window.height, "installer control outside frame")
            for j = i + 1, #panels do
                local b = panels[j]
                if b.shown then
                    assert(a.x + a.width <= b.x or b.x + b.width <= a.x
                        or a.y + a.height <= b.y or b.y + b.height <= a.y,
                        "installer controls overlap")
                end
            end
        end
    end
end
assert(window.intro[1].shown and window.suite.shown == false and window.classic.shown == false
    and window.forever.shown == false)
CheckLayout()
assert(window.close.x + window.close.width < window.next.x)
window.next.scripts.OnClick() -- welcome -> profile
assert(window.suite.shown and window.classic.shown and window.forever.shown and window.cooldowns.shown
    and window.cooldowns.mark.text == "ON")
CheckLayout()
assert(window.close.x + window.close.width < window.next.x)
window.forever.scripts.OnClick() -- Retail can choose the full Forever factory
assert(window.cooldowns.shown and window.cooldowns.mark.text == "ON",
    "Retail Forever hid the spec cooldown choice")
window.next.scripts.OnClick() -- profile -> modules
assert(window.moduleRows[2].shown)
CheckLayout()
window.moduleRows[2].scripts.OnClick() -- enable Bags in the Forever module profile
window.next.scripts.OnClick() -- modules -> scaling
assert(window.scaleToggle.shown and not window.scaleSlider.shown)
CheckLayout()
window.scaleToggle.scripts.OnClick()
CheckLayout()
window.presets[3].scripts.OnClick()
assert(window.scaleSlider.value == 0.7 and window.scaleLabel.text == "70%")
window.scaleSlider.scripts.OnValueChanged(nil, 0.75)
window.next.scripts.OnClick() -- scaling -> review
assert(window.review[1].shown and window.next.caption.text == "Install")
CheckLayout()
window.next.scripts.OnClick() -- install
assert(factoryCalls == 1 and Suite.RootDB.installation.profile == "forever")
-- Each factory string is decoded once, not on every module click and repaint.
assert(decodes == 2, "the installer decoded a factory profile " .. decodes .. " times")
-- The install copies the cached factory; nameplates are already bundled.
assert(copies == 1, "the installer copied the factory profile " .. copies .. " times")
assert(Suite.RootDB.installation.raidEssentials == true
    and Suite.RootDB.installation.foreverAnchorRevision == 1,
    "Retail Forever did not record its CDM spec and anchor defaults")
assert(Suite.RootDB.installation.moduleOverrides.bags == true)
assert(Suite.RootDB.installation.uiScaleEnabled and Suite.RootDB.installation.uiScale == 0.75)
assert(scaleChanges[#scaleChanges][1] == "global" and scaleChanges[#scaleChanges][2] == 0.75)
assert(window.done[1].shown and window.next.caption.text == "Reload UI")
assert(rawget(window, "openModules") == nil and rawget(window, "modulesHint") == nil,
    "the completed installer still points to the removed Suite Modules page")
CheckLayout()
Suite.Client.isForever = true
Suite.Installer.Open()
window.next.scripts.OnClick()
assert(window.suite.mark.text == "SELECTED", "Clean Modern is not the Suite setup default on Forever")
CheckLayout()
Suite.Client.isForever = false
MSUF_GetPixelPerfectScale = function() return 768 / 2160 end
Suite.Installer.Open()
window.next.scripts.OnClick() -- profile
window.next.scripts.OnClick() -- modules
window.next.scripts.OnClick() -- scaling
window.scaleToggle.scripts.OnClick()
window.presets[1].scripts.OnClick()
assert(window.scaleLabel.text == "35.56%", "4K pixel scale was clipped to slider minimum")
window.next.scripts.OnClick() -- review
window.next.scripts.OnClick() -- install
assert(Suite.RootDB.installation.uiScalePreset == "pixel"
    and Suite.RootDB.installation.uiScale == 768 / 2160
    and scaleChanges[#scaleChanges][2] == 768 / 2160,
    "pixel-perfect selection lost its exact screen scale")
Suite.RootDB.profiles.Default.suite.modules.cooldownManager.listsData = "MSUF3:rogue"
Suite.RootDB.profiles.Default.suite.modules.cooldownManager.spellsData = "MSUF3:spells"
Suite.Installer.Open()
window.next.scripts.OnClick() -- profile: Modern is selected
window.cooldowns.scripts.OnClick()
assert(window.cooldowns.mark.text == "OFF", "Retail onboarding must allow Blizzard CDM")
window.next.scripts.OnClick() -- modules
window.next.scripts.OnClick() -- scaling
window.next.scripts.OnClick() -- review
assert(window.review[2].detail.text:find("Blizzard cooldowns",1,true), "review names the CDM choice")
window.next.scripts.OnClick() -- install
assert(Suite.RootDB.installation.raidEssentials == false
    and Suite.RootDB.profiles.Default.suite.modules.cooldownManager.raidEssentials == false
    and Suite.RootDB.profiles.Default.suite.modules.cooldownManager.listsData == "MSUF3:rogue"
    and Suite.RootDB.profiles.Default.suite.modules.cooldownManager.spellsData == "MSUF3:spells",
    "Modern onboarding must retain personal CDM lists while applying the chosen default")

Suite.Installer.Open()
window.next.scripts.OnClick() -- welcome -> profile
window.classic.scripts.OnClick()
assert(window.classic.mark.text == "SELECTED"
    and window.suite.mark.text == "CHOOSE"
    and window.review[1].shown == false,
    "Classic MSUF is not a separate setup choice")
assert(Suite.Installer.Apply()
    and Suite.RootDB.installation.profile == "classic"
    and MSUF_ActiveProfile == "MSUF Suite Classic"
    and Suite.RootDB.profiles[MSUF_ActiveProfile].suite.globalLook == "midnight"
    and Suite.RootDB.profiles[MSUF_ActiveProfile].suite.modules.cooldownManager.listsData == "MSUF3:rogue",
    "Classic MSUF did not install complete frames with its palette")
Suite.Client.isForever = true
Suite.Installer.Open()
window.next.scripts.OnClick() -- welcome -> profiles
window.classic.scripts.OnClick()
assert(Suite.Installer.Apply() and MSUF_ActiveProfile == "MSUF Suite Classic 2"
    and Suite.RootDB.installation.profile == "classic",
    "Forever Classic selection did not import the bundled non-Forever MSUF frames")
Suite.Client.isForever = false

-- The profile install is the commit point: nothing after it refuses, so a
-- scale step that MSUF refuses can neither fail the install nor let a retry
-- create a second Forever profile.
local created, installFactory = {}, Suite.SuiteProfiles.InstallFactory
Suite.SuiteProfiles.InstallFactory = function(name)
    created[#created + 1] = name
    MSUF_GlobalDB.profiles[name] = {}
    return true, name
end
MSUF_ResetGlobalUiScale = function() return false end
Suite.Client.isForever = true
Suite.Installer.Open()
window.next.scripts.OnClick()
window.forever.scripts.OnClick()
if not Suite.Installer.Apply() then Suite.Installer.Apply() end
assert(#created == 1 and created[1] == "MSUF Suite Forever"
    and Suite.RootDB.installation.profile == "forever",
    "a refused step after the Forever install left a retry that installs a second profile")
Suite.SuiteProfiles.InstallFactory, MSUF_ResetGlobalUiScale = installFactory, resetScale
Suite.Client.isForever = false
MSUF_GlobalDB.profiles["MSUF Suite Forever"] = nil

-- Texts use the Suite localization in every language: MSUF's table by English
-- key, where MSUF's own wording comes first and MSUF_Suite/Locales adds the
-- Suite's strings. The client language plays no part.
local function PackTable(locale, own)
    local L = setmetatable(own, { __index = function(_, key) return key end })
    local host = MSUF_NS
    MSUF_NS = { LOCALE = locale, RegisterLocale = function(requested) return requested == locale and L or {} end }
    assert(loadfile(root .. "/MSUF_Suite/Locales/" .. locale .. ".lua"))("MSUF_Suite", {})
    MSUF_NS = host
    return L
end
local function OpenLocalized(locale, L)
    GetLocale = function() return "enUS" end
    Suite.L = L
    MSUFSuiteInstallFrame = nil
    assert(loadfile(root .. "/MSUF_Suite/Core/Installer.lua"))("MSUF_Suite", Suite)
    Suite.Installer.Open()
    return assert(MSUFSuiteInstallFrame)
end
local de = PackTable("deDE", { Continue = "Fortfahren" })
local welcome, combat = rawget(de, "Welcome to MSUF Suite"), rawget(de, "Finish combat first.")
assert(welcome and welcome ~= "Welcome to MSUF Suite" and combat, "the German Suite pack lacks the installer texts")
window = OpenLocalized("deDE", de)
assert(window.title.text == welcome and window.next.caption.text == "Fortfahren"
    and window.close.caption.text == (rawget(de, "Not now") or "Not now"),
    "the German installer does not read the Suite pack, or it replaced MSUF's own wording")
-- A refusal stays English until the status line shows it, translated once.
Suite.IsCombatLocked = function() return true end
local refused, refusal = Suite.Installer.Apply()
assert(not refused and refusal == "Finish combat first.", "the installer translated a refusal before showing it")
for _ = 1, 5 do window.next.scripts.OnClick() end
assert(window.status.text == "|cffff6666" .. combat .. "|r",
    "the installer status line did not translate the refusal")
Suite.IsCombatLocked = function() return false end
local fr = PackTable("frFR", { Continue = "Continuer" })
window = OpenLocalized("frFR", fr)
assert(window.next.caption.text == "Continuer" and rawget(fr, "Welcome to MSUF Suite")
    and window.title.text == rawget(fr, "Welcome to MSUF Suite"),
    "the installer ignored the Suite localization in another language")
-- Module rows, their tooltips and the review read the Suite localization too:
-- the catalog title and description, and one format for the enabled count.
do
    local chat = Suite.SuiteCatalog.chat
    chat.title, chat.description = "Chat", "Contract chat description"
    local L = setmetatable({ Chat = "Discussion", ["Contract chat description"] = "Description du chat",
        ["%d / %d enabled"] = "%d sur %d activés" }, { __index = function(_, key) return key end })
    window = OpenLocalized("frFR", L)
    local row = window.moduleRows[1]
    assert(row.id == "chat" and row.label.text == "Discussion", "a module row shows its English catalog title")
    local lines = {}
    GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
    Suite.Suite.Availability = function() return true end
    row.scripts.OnEnter(row)
    GameTooltip.AddLine, Suite.Suite.Availability = nil, nil
    assert(GameTooltip.text == "Discussion" and lines[1] == "Description du chat",
        "a module tooltip shows its English catalog title or description")
    for _ = 1, 4 do window.next.scripts.OnClick() end
    assert(window.review[2].detail.text:find("^%d+ sur %d+ activés"),
        "the module count is not one translated format: " .. tostring(window.review[2].detail.text))
    chat.title, chat.description = "chat", nil
end
GetLocale, Suite.L = function() return "enUS" end, nil
print("Suite installer: profiles, module selection, optional scaling, layout, localization and completion passed")
