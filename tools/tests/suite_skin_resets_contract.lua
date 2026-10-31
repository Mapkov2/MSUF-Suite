-- The Skinning page and the Suite's page resets, as a player meets them:
--  * on WoW Forever the character controls are inert and say why;
--  * "Reset section" on Fonts restores the font choice (followMSUF, face),
--    not just the face, and the Fonts section shows a font problem;
--  * "Reset page" on Skinning restores the factory look for the Suite too and
--    keeps both Skinning switches as the player set them;
--  * the run summary repaints when the skin changes, like the other HUDs;
--  * a loaded addon that restyles Blizzard's windows is named once in chat,
--    and nothing is ever switched off;
--  * a module page reset keeps whether the module is switched on, while the
--    factory reset still starts from the catalog defaults.
-- Usage: lua suite_skin_resets_contract.lua <Suite root>
local root = assert(arg[1], "Suite root required")
SUITE_OPTIONS_FIXTURE = true
local F = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
local M, W, T, S, Suite, optionsNS = F.M, F.W, F.T, F.S, F.Suite, F.optionsNS

local checks = 0
local function Check(value, label)
    assert(value, label)
    checks = checks + 1
end
local function Noop() end

------------------------------------------------------------------ the skin engine
-- The engine of suite_options_menu_contract.lua with its real Defaults and,
-- here, the real Typography (the font choice is what the reset must restore).
local skin = { GetAPI = function() return nil end, addonName = "MSUF_Suite_Skin",
    Client = { isMainline = true, isForever = false, IsAddOnLoaded = function() return true end },
    L = setmetatable({}, { __index = function(_, key) return key end }), SourceText = function(key) return key end }
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", skin)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", skin)
skin.DB = skin.CopyValue(skin.Defaults)
skin.Surface = { Attach = function(frame) return frame end }
skin.Surface.SkinOwnedButton = skin.Surface.Attach
skin.Theme = {
    GetColor = function(key) return unpack(skin.DB.theme.colors[key]) end,
    GetColorTable = function(key) return skin.DB.theme.colors[key] end,
    ApplyLook = function(key) skin.DB.theme.look = key; return true end,
    SetAppearance = function(key, value) skin.DB.theme[key] = value; return true end,
    SetGeometry = function(key, value) skin.DB.geometry[key] = value; return true end,
    SetColor = function(key, r, g, b, a) skin.DB.theme.colors[key] = { r, g, b, a }; return true end,
}
local masterSwitches = 0
skin.Adapters = {
    SetMasterEnabled = function(value) masterSwitches = masterSwitches + 1; skin.DB.enabled = value; return true end,
    SetEnabled = function(key, value) skin.DB.skins[key] = value; return true end,
    GetDefinitions = function() return { "settings" }, { settings = { labelKey = "SETTINGS" } } end,
    Refresh = function() return true end,
    ApplyAll = Noop,
}
skin.GenericWindows = {
    GetCategories = function() return { { id = "character" } } end,
    SetCategoryEnabled = function(key, value) skin.DB.skinCategories[key] = value; return true end,
}
skin.WindowActionSkin = { SetOption = function(key, value) skin.DB.icons.windowActions[key] = value; return true end }
skin.MicroMenuSkin = {
    SetOption = function(key, value) skin.DB.icons.microMenu[key] = value; return true end,
    ApplyPreset = function() return true end,
}
skin.CharacterDetails = {
    SetView = function(value) skin.DB.characterDetails.view = value; return true end,
    SetOption = function(key, value) skin.DB.characterDetails[key] = value; return true end,
    RefreshFonts = Noop,
}
skin.CharacterStats = { SetOption = function(key, value) skin.DB.characterStats[key] = value; return true end,
    RefreshFonts = Noop }
skin.Registry = { NotifyListeners = Noop, RefreshAll = Noop }
skin.Database = {
    GetProfileNames = function() return { "Default" } end,
    GetActiveProfileName = function() return "Default" end,
    CreateFactoryProfile = function() return skin.CopyValue(skin.Defaults) end,
    ResetAll = function() skin.DB = skin.CopyValue(skin.Defaults); return skin.DB end,
}
-- The real Typography on the client pieces it reads (suite_skin_msuf_font_contract.lua).
local function Font(path, size, flags)
    local object = { path = path, size = size, flags = flags }
    function object:GetFont() return self.path, self.size, self.flags end
    function object:SetFont(nextPath, nextSize, nextFlags)
        self.path, self.size, self.flags = nextPath, nextSize, nextFlags
        return true
    end
    return object
end
GameFontNormal, ChatFrame1 = Font("Blizzard.ttf", 14, ""), Font("Chat.ttf", 12, "")
NUM_CHAT_WINDOWS, CommunitiesFrame, DeveloperConsole = 1, { Chat = {} }, {}
GetFonts = function() return { "GameFontNormal" } end
EventUtil = { ContinueAfterAllEvents = Noop }
MSUF_GetFontPath = function() return "MSUF.ttf" end
skin.BlizzardFontNames = { "GameFontNormal" }
skin.Safety = { Public = function() return true end, Call = function(object, name) return object[name](object) end }
skin.SharedMedia = { FetchFont = function(name) return name == "Skin" and "Skin.ttf" or nil end,
    GetFontNames = function() return { "Skin" } end }
skin.CombatGate = { RunOrDefer = Noop, Cancel = Noop }
skin.IsCombatLocked = function() return false end
skin.SuiteCore = function() return F.Suite end
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Typography.lua"))("MSUF_Suite_Skin", skin)
MapkoSkin = skin
-- The default Suite meter owns Blizzard's meter; the harness cannot load its runtime.
S.states.damageMeter.error = nil

local function BuildSkinPage()
    local ctx = { key = "suite_skin", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
    F.SetCurrent(ctx)
    M.pages.suite_skin.build(ctx)
    for _, refresh in ipairs(ctx.refreshers) do refresh() end
    return ctx
end
local function SectionOf(ctx, id)
    for _, section in ipairs(ctx.sections) do
        if section.sectionId == id then return section end
    end
    error("no section " .. id)
end
local function ControlsOf(ctx, sectionId)
    local list = {}
    for _, widget in ipairs(ctx.widgets) do
        if widget.meta and widget.meta.sectionId == sectionId then list[#list + 1] = widget end
    end
    return list
end

------------------------------------------------------------------ the run summary follows the skin
do
    local api = { RegisterAddon = function() return { ReleaseAll = Noop } end, OnAppearanceChanged = Noop }
    skin.GetAPI = function() return api end
    Check(Suite.Skin.SetEnabled(true), "the skin did not switch on")
    Check(Suite.Skin.Acquire("resetsContract"), "the skin gave no client")
    local applied, previous = {}, S.Apply
    S.Apply = function(id) applied[#applied + 1] = id end
    for _, id in ipairs({ "objectives", "runSummary", "announcements" }) do S.states[id].active = true end
    api:OnAppearanceChanged("theme", "look")
    S.Apply = previous
    local repainted = {}
    for _, id in ipairs(applied) do repainted[id] = true end
    Check(repainted.objectives and repainted.announcements, "a skin change did not repaint the HUDs")
    Check(repainted.runSummary, "a skin change left an open run summary on the old look")
    for _, id in ipairs({ "objectives", "runSummary", "announcements" }) do S.states[id].active = false end
    skin.GetAPI = function() return nil end
end

------------------------------------------------------------------ a clashing window skin is named once
do
    local loadedAddOns, printed = {}, {}
    local isLoaded, realPrint = C_AddOns.IsAddOnLoaded, Suite.Print
    C_AddOns.IsAddOnLoaded = function(name)
        if loadedAddOns[name] then return true, true end
        return isLoaded(name)
    end
    Suite.Print = function(message) printed[#printed + 1] = message end
    local function Named(name)
        local count = 0
        for _, message in ipairs(printed) do
            if message:find(name, 1, true) then count = count + 1 end
        end
        return count
    end
    skin.DB.enabled = true
    Check(Suite.RootDB.skinConflictNotices == nil, "fixture: a notice was recorded already")
    Suite.Skin.SetEnabled(true)
    Check(#printed == 0, "the skin named an addon that is not loaded")
    loadedAddOns.ElvUI, loadedAddOns.Aurora = true, true
    masterSwitches = 0
    Suite.Skin.SetEnabled(true)
    Check(Named("ElvUI") == 1 and Named("Aurora") == 1 and #printed == 2,
        "the clashing addons were not named once each: " .. #printed)
    -- Again, off and on, and a later login: still the one notice.
    Suite.Skin.SetEnabled(true)
    Suite.Skin.SetEnabled(false)
    Suite.Skin.SetEnabled(true)
    Check(#printed == 2 and Suite.RootDB.skinConflictNotices.ElvUI == true, "a notice was repeated or not kept")
    -- It only informs: no switch of the skin, its windows or the other addon.
    Check(Suite.Skin.enabled == true and skin.DB.enabled == true and masterSwitches == 0,
        "the conflict notice switched something off")
    -- Windows the player left unskinned clash with nothing; the notice waits.
    loadedAddOns.DarkMode = true
    skin.DB.enabled = false
    Suite.Skin.SetEnabled(true)
    Check(Named("DarkMode") == 0, "the notice came although Blizzard windows are not skinned")
    skin.DB.enabled = true
    Suite.Skin.SetEnabled(true)
    Check(Named("DarkMode") == 1 and #printed == 3 and Named("NDui") == 0, "a later clash was not named once")
    C_AddOns.IsAddOnLoaded, Suite.Print = isLoaded, realPrint
end

------------------------------------------------------------------ WoW Forever: character controls
do
    local retail = Suite.Client.modernEquipment
    Suite.Client.modernEquipment = true
    local controls = ControlsOf(BuildSkinPage(), "suite_skin_character")
    Check(#controls == 8, "the character section changed: " .. #controls .. " controls")
    for _, widget in ipairs(controls) do
        Check(widget.enabled and rawget(widget, "disabledReason") == nil,
            "a Retail character control is gated: " .. tostring(widget.meta.settingKey))
    end
    Suite.Client.modernEquipment = false
    local ctx = BuildSkinPage()
    controls = ControlsOf(ctx, "suite_skin_character")
    Check(#controls == 8, "Forever lost a character control")
    for _, widget in ipairs(controls) do
        local reason = rawget(widget, "disabledReason")
        Check(widget.enabled == false, "a Forever character control is live: " .. tostring(widget.meta.settingKey))
        Check(type(reason) == "function" and reason():find("only in Retail", 1, true),
            "a Forever character control gives no reason: " .. tostring(widget.meta.settingKey))
    end
    local help
    for _, row in ipairs(optionsNS.SkinSearchRows()) do
        if row.sectionId == "suite_skin_character" and row.kind == "section" then help = row.help end
    end
    Check(help and help:find("only in Retail", 1, true), "the Forever section does not say it is Retail only")
    Suite.Client.modernEquipment = retail
end

------------------------------------------------------------------ Fonts: section reset and status
do
    local lines = {}
    local font = T.Font
    T.Font = function(...)
        local line = font(...)
        lines[#lines + 1] = line
        return line
    end
    local typography = skin.Typography
    Check(typography.SetSelection("arial") and typography.GetSelection() == "arial"
        and skin.DB.typography.followMSUF == false, "fixture: the font choice did not change")
    skin.DB.typography.customPath = "Interface\\Fonts\\Mine.ttf"
    local ctx = BuildSkinPage()
    local reset = rawget(SectionOf(ctx, "suite_skin_fonts"), "_msufSuiteSectionReset")
    Check(type(reset) == "function" and reset(), "the Fonts section reset did not run")
    Check(typography.GetSelection() == "msuf" and skin.DB.typography.followMSUF == true,
        "Reset section left the custom font choice: " .. typography.GetSelection())
    Check(skin.DB.typography.customPath == "" and skin.DB.typography.face == skin.Defaults.typography.face,
        "Reset section left the custom path or face")
    -- An unusable font is reported on the page (the engine records why).
    local function Status()
        for _, line in ipairs(lines) do
            if type(line.text) == "string" and line.text:find("chosen font", 1, true) then return line.text end
        end
    end
    ctx = BuildSkinPage()
    Check(Status() == nil, "the Fonts section shows a problem with a working font")
    Check(typography.SetSelection("custom") and typography.GetStatus().error == "invalid-path", "fixture: no font problem")
    lines = {}
    ctx = BuildSkinPage()
    Check(Status(), "the Fonts section does not show the font problem")
    T.Font = font
end

------------------------------------------------------------------ Skinning: Reset page
do
    local factoryLook = skin.Defaults.theme.look
    for _, switches in ipairs({ { false, false }, { true, true }, { false, true }, { true, false } }) do
        local windows, suiteWindows = switches[1], switches[2]
        Check(S.ApplyGlobalLook("midnight") and Suite.DB.suite.globalLook == "midnight", "fixture: look not set")
        skin.DB.theme.look = "midnight"
        skin.DB.enabled = windows
        Check(Suite.Skin.SetEnabled(suiteWindows), "fixture: the Suite windows switch was refused")
        Check(optionsNS.ResetSkinPage(), "Reset page was refused")
        Check(skin.DB.theme.look == factoryLook, "Reset page kept the old skin look")
        Check(Suite.DB.suite.globalLook == factoryLook, "Reset page left the Suite on the old look: "
            .. tostring(Suite.DB.suite.globalLook))
        Check(skin.DB.enabled == windows and Suite.Skin.enabled == suiteWindows
            and Suite.RootDB.skinEnabled == suiteWindows,
            ("Reset page changed the Skinning switches (%s/%s)"):format(tostring(windows), tostring(suiteWindows)))
    end
    Suite.Skin.SetEnabled(true)
end

------------------------------------------------------------------ module page reset keeps "enabled"
-- The factory reset replaces the profile (Database.StageFactoryReset) and
-- starts every module from the catalog; the page reset must not.
do
    local ids = {}
    for _, id in ipairs(Suite.SuiteOrder) do
        if S.catalog[id].page == "suite_qualityOfLife" then ids[#ids + 1] = id end
    end
    Check(#ids > 9, "fixture: Quality of Life lists too few modules")
    local probe = {}
    local function Flip()
        for _, id in ipairs(ids) do
            local config, rules = S.Config(id), S.catalog[id].rules
            config.enabled = not rules.enabled.default
            for key, rule in pairs(rules) do
                if key ~= "enabled" and type(rule.default) == "boolean" and not probe[id] then
                    probe[id] = key
                    config[key] = not rule.default
                end
            end
        end
    end
    Flip()
    Check(M.ResetPageToDefaults("suite_qualityOfLife"), "Quality of Life page reset failed")
    local probed = 0
    for _, id in ipairs(ids) do
        local rule = S.catalog[id].rules.enabled
        Check(S.Config(id).enabled == not rule.default, "a page reset switched " .. id .. " back to its factory state")
        if probe[id] then
            probed = probed + 1
            Check(S.Config(id)[probe[id]] == S.catalog[id].rules[probe[id]].default,
                "a page reset left " .. id .. "." .. probe[id])
        end
    end
    Check(probed > 5, "fixture: too few modules had a second setting")
    -- One module, directly: off stays off, and on stays on.
    local id = ids[1]
    for _, state in ipairs({ false, true }) do
        S.Config(id).enabled = state
        Check(S.Reset(id) and S.Config(id).enabled == state, "S.Reset changed whether " .. id .. " runs")
    end
    -- The factory reset starts again from the catalog.
    for _, moduleId in ipairs(ids) do S.Config(moduleId).enabled = not S.catalog[moduleId].rules.enabled.default end
    Check(Suite.Database.StageFactoryReset(), "the factory reset was refused")
    for _, moduleId in ipairs(ids) do
        Check(Suite.DB.suite.modules[moduleId].enabled == S.catalog[moduleId].rules.enabled.default,
            "the factory reset kept " .. moduleId .. " switched the other way")
    end
end

print("Suite skin resets: " .. checks .. " checks passed")
