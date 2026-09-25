local root = assert(arg[1], "repository root required")
local Suite = {
    Client = { isForever = false, isMainline = true },
    RootDB = { profiles = { Default = {} } },
    RetailFactoryModuleCompact = "MSUFM1:MSUF3:retail",
    RetailFactorySkinCompact = "MSKIN1:modern",
    ForeverFactoryModuleCompact = "MSUFM1:MSUF3:forever",
    ForeverFactorySkinCompact = "MSKIN1:forever",
    ForeverFactoryFramesCompact = "MSUF3:frames",
    SuiteOrder = { "chat", "bags", "minimap", "damageMeter", "dataTexts",
        "buffReminders", "qol", "quests", "loot", "combatLog", "xpBar",
        "skyriding", "cooldownManager", "objectives", "announcements",
        "afkScreen", "actionbars" },
    SuiteCatalog = {},
}
for _, id in ipairs(Suite.SuiteOrder) do Suite.SuiteCatalog[id] = { title = id } end
local factoryCalls, activations, scaleChanges = 0, 0, {}

Suite.IsCombatLocked = function() return false end
Suite.Print = function() end
Suite.Client.AddOnEnabled = function() return true end
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
        assert(shared == false, "installer factory was sanitized as an external import")
        assert(text == Suite.RetailFactoryModuleCompact or text == Suite.ForeverFactoryModuleCompact)
        local modules = {}
        for _, id in ipairs(Suite.SuiteOrder) do modules[id] = { enabled = true } end
        modules.bags.enabled = text == Suite.RetailFactoryModuleCompact
        modules.actionbars.enabled = text == Suite.RetailFactoryModuleCompact
        if text == Suite.RetailFactoryModuleCompact then
            modules.cooldownManager.listsData = "MSUF3:factoryRogue"
        end
        return { suite = { schema = 1, modules = modules } }
    end,
}
Suite.SuiteProfiles = {
    InstallSuiteFactory = function(name, profile, skin)
        assert(name == "Default" and skin == Suite.RetailFactorySkinCompact)
        assert(profile.suite.modules.dataTexts.bar1Point == 9
            and profile.suite.modules.dataTexts.bar1X == 0
            and profile.suite.modules.actionbars.bar1Point == 8
            and profile.suite.modules.actionbars.bar3Point == 7
            and profile.suite.modules.minimap.x == -20,
            "Modern factory positions did not use screen anchors")
        Suite.RootDB.profiles[name] = profile
        Suite.Database.Activate(name)
        return true, name
    end,
    InstallFactory = function(name, frames, profile, skin)
        factoryCalls = factoryCalls + 1
        assert(name == "MSUF Suite Forever")
        assert(frames == "MSUF3:frames")
        assert(skin == "MSKIN1:forever")
        assert(profile.suite.modules.chat.enabled)
        assert(profile.suite.modules.bags.enabled)
        assert(profile.suite.modules.actionbars.enabled,
            "Forever factory must enable ActionBars despite its old export")
        assert(profile.suite.modules.minimap.x == -20
            and profile.suite.modules.xpBar.point == 2
            and profile.suite.modules.xpBar.y == -24
            and profile.suite.modules.actionbars.bar1Point == 8,
            "Forever factory retained display-specific offsets")
        return true, name
    end,
}

MSUF_NS = { MSUF_FOREVER_FACTORY_DEFAULT_PROFILE_COMPACT = "MSUF3:frames" }
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
CreateFrame = function(_, name)
    local frame = FakeFrame()
    if name then _G[name] = frame end
    return frame
end

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
local function CheckLayout()
    local panels = { window.suite, window.forever, window.cooldowns, window.scaleToggle,
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
assert(window.intro[1].shown and window.suite.shown == false and window.forever.shown == false)
CheckLayout()
assert(window.close.x + window.close.width < window.next.x)
window.next.scripts.OnClick() -- welcome -> profile
assert(window.suite.shown and window.forever.shown and window.cooldowns.shown
    and window.cooldowns.mark.text == "ON")
CheckLayout()
assert(window.close.x + window.close.width < window.next.x)
window.forever.scripts.OnClick() -- Retail can choose the full Forever factory
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
assert(Suite.RootDB.installation.moduleOverrides.bags == true)
assert(Suite.RootDB.installation.uiScaleEnabled and Suite.RootDB.installation.uiScale == 0.75)
assert(scaleChanges[#scaleChanges][1] == "global" and scaleChanges[#scaleChanges][2] == 0.75)
assert(window.done[1].shown and window.next.caption.text == "Reload UI")
CheckLayout()
Suite.Client.isForever = true
Suite.Installer.Open()
window.next.scripts.OnClick()
assert(window.forever.mark.text == "SELECTED", "Forever did not default to its own factory")
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
print("Suite installer: profiles, module selection, optional scaling, layout, and completion passed")
