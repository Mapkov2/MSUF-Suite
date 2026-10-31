local suiteRoot = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local root = suiteRoot:match("^(.*)/[^/]+$") .. "/MidnightSimpleUnitFrames-7.0"
local flavor = arg[2] or "Mainline"
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(world)
        local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
        MW.InstallNativeUnitInputs(world)
    end }, arg[4])
local env, M, core = mw.env, mw.M, mw.core
local methods = getmetatable(env.UIParent).__index
for _, key in ipairs({ "SetDrawBling", "SetSwipeColor", "SetSwipeTexture", "SetReverse", "SetEdgeScale", "SetMotionScriptsWhileDisabled" }) do
    methods[key] = methods[key] or function() end
end
methods.GetUnboundedStringWidth = methods.GetUnboundedStringWidth or function(self) return self:GetStringWidth() end
methods.GetCountdownFontString = methods.GetCountdownFontString or function(self)
    if not self.countdownFont then self.countdownFont = self:CreateFontString(nil, "OVERLAY") end
    return self.countdownFont
end
local loaded = { MidnightSimpleUnitFrames = true, MidnightSimpleUnitFrames_Options = true }
local disabled = {}
local Support = assert(loadfile(suiteRoot .. "/tools/tests/suite_test_support.lua"))()
env.C_SpecializationInfo.GetNumSpecializationsForClassID = function() return 0 end
env.C_SpecializationInfo.GetSpecialization = env.C_SpecializationInfo.GetSpecialization or function() return nil end
local getCVar = env.C_CVar.GetCVar
env.C_CVar.GetCVar = function(key) if key == "combinedBags" then return "1" end return getCVar(key) end
env.C_AddOns = {
    GetAddOnMetadata = function() end,
    IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
    DoesAddOnExist = function() return true end,
    GetAddOnEnableState = function(name) return disabled[name] and 0 or 2 end,
    LoadAddOn = function(name)
        if Support.LoadLocaleAddon(suiteRoot, name, env) then loaded[name] = true; return true end
        return false, "MISSING"
    end,
    GetNumAddOns = function() return 0 end,
}
local function Load(addon, ns)
    for _, file in ipairs(Support.TocFiles(suiteRoot, addon, "Mainline")) do
        if file:match("%.lua$") then
            local ok, why = mw.world:LoadFile(suiteRoot .. "/" .. addon .. "/" .. file, addon, ns)
            assert(ok, file .. ": " .. tostring(why))
        end
    end
    loaded[addon] = true
end
local NS = {}
Load("MSUF_Suite", NS)
assert(NS.Database.Initialize(nil))
local S, W = NS.Suite, core.ProfileWorkbench
local before = M.AurasPage.AppearanceValues()
assert(#before == 4 and M.AurasPage.BlizzardVisibilityType() == nil, "bare host changed")
assert(mw:Select("auras3_styling") ~= false)
mw:RunTimers()
local P = {}
Load("MSUF_Suite_Options", P)

local checks = 0
local function Check(value, why)
    checks = checks + 1
    assert(value, why)
end
local function Settle()
    mw:RunTimers()
    M.Theme.StopAllMenuAnimations()
end
local function Select(page)
    Check(mw:Select(page) ~= false, "failed to open " .. page)
    Settle()
end
local function Widget(key)
    local entry = M.cache[M.activeKey]
    for _, widget in ipairs(entry.searchWidgets or {}) do
        local record = widget._msuf2RuntimeControlRecord
        if record then
            if record.settingKey == key or (widget._msuf2ControlSchema or {}).setting == key then return widget end
            for _, setting in ipairs(record.searchSettingKeys or {}) do if setting == key then return widget end end
        end
    end
end
for _, feature in ipairs(P.QualityOfLifeSearchFeatures) do
    Check(feature.id ~= "playerAuras" and feature.id ~= "playerAuraSkins", "player auras remain in Quality of Life")
end
Check(P.PlayerAurasPage.registered, "Suite did not register optional Aura type")
local foundRows = {}
for _, row in ipairs(P.SearchRows()) do
    local owner = (row.settingKey or ""):match("^msufsuite%.([^.]+)%.")
    if owner == "playerAuras" or owner == "playerAuraSkins" then
        Check(row.pageKey == "auras3_styling", "cold search still points to Quality of Life")
        foundRows[row.settingKey] = row
    end
end
Check(foundRows["msufsuite.playerAuras.iconWidth"], "cold search lost layout controls")
Check(foundRows["msufsuite.playerAuraSkins.enabled"], "cold search lost skin switch")
local values = M.AurasPage.AppearanceValues()
Check(#values == 5 and values[5].value == "blizzardPlayer", "extension replaced original Aura types")
Check(#before == 4, "registration mutated base selector")
Check(M.AurasPage.BlizzardVisibilityType() == "blizzardPlayer", "visibility owner missing")
Check(M.AurasPage.AppearanceResetProvider("auras3_styling") == nil, "extension claimed normal Aura reset")
S.Config("playerAuras").iconWidth = 61
S.Config("playerAuraSkins").enabled = false
Check(M.ResetPageToDefaults("suite_qualityOfLife"), "QoL reset failed")
Check(S.Config("playerAuras").iconWidth == 61 and S.Config("playerAuraSkins").enabled == false,
    "QoL reset still owns relocated Aura modules")
local metricHeight = select(2, M.GetContentMetrics())
M.GetContentMetrics = function() return 520, metricHeight end
Check(P.PlayerAurasPage.Open("playerAuras"), "QoL link did not open Aura view")
Settle()
Check(M.activeKey == "auras3_styling" and M.auraAppearanceContainer == "blizzardPlayer", "wrong Aura view")
Check(S.Config("playerAuras").iconWidth == 61, "opening menu rewrote existing profile")
local function CheckSelectorBounds(frame)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child._msuf2Rows and child.buttons then
            Check(child:GetParent():GetHeight() > -child._msuf2BottomY, "wrapped Aura selector extends below its header")
        end
        CheckSelectorBounds(child)
    end
end
CheckSelectorBounds(M.cache.auras3_styling.wrapper)
Check(Widget("auras3.shared.hideBlizzardBuffFrame"), "missing host Buff visibility")
Check(Widget("auras3.shared.hideBlizzardDebuffFrame"), "missing host Debuff visibility")
local width = Widget("msufsuite.playerAuras.iconWidth")
Check(width, "missing Suite layout control")
assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))().FireScript(width, "OnValueChanged", 63)
Check(S.Config("playerAuras").iconWidth == 63, "layout control wrote wrong owner")
Check(Widget("msufsuite.playerAuras.enabled"), "layout header switch missing")
Check(Widget("msufsuite.playerAuraSkins.enabled"), "skin header switch missing")
local original = { pageKey = "suite_qualityOfLife", settingKey = "msufsuite.playerAuras.iconWidth",
    sectionId = "suite_qualityOfLife_playerAuras_player_auras" }
local page, target = P.PlayerAurasPage.Resolve(original.pageKey, original)
Check(page == "auras3_styling" and target.sectionId == "auras3_styling_playerAuras_module", "legacy target did not move")
Check(original.pageKey == "suite_qualityOfLife" and original.sectionId:find("suite_qualityOfLife", 1, true), "target was mutated")
Select("home")
local api = M.Search._CoreAPI
local ok, focused, exact = api.OpenSearchTarget(original.pageKey, "Icon width", nil, nil, nil, original)
Settle()
Check(ok and focused and exact, "saved Suite setting failed exact opening")
Check(M.activeKey == "auras3_styling" and M.auraAppearanceContainer == "blizzardPlayer", "saved link missed Aura view")
local coreTarget = { pageKey = "auras3_styling", settingKey = "auras3.shared.hideBlizzardBuffFrame" }
Select("home")
ok, focused, exact = api.OpenSearchTarget(coreTarget.pageKey, "Hide Blizzard Buff Frame", nil, nil, nil, coreTarget)
Settle()
Check(ok and focused and exact, "old visibility target failed exact opening")
Check(M.auraAppearanceContainer == "blizzardPlayer", "visibility target selected old Buff view")
-- Real cold index rows identify these controls by ID, without a settingKey.
for _, oldPage in ipairs({ "auras3_buffs", "auras3_debuffs", "auras3_styling" }) do
    for _, lane in ipairs({ "buffs", "debuffs" }) do
        local legacy = { pageKey = oldPage, settingKey = "",
            controlId = "menu2." .. oldPage .. ".auras.style.appearance.blizzard-aura-frames.hide-" .. lane,
            sectionId = "aura_style_appearance_debuff_blizzard_aura_frames" }
        Select("home")
        local a, b, c = api.OpenSearchTarget(oldPage, "Hide Blizzard " .. lane, nil, nil, nil, legacy)
        Settle()
        Check(a and b and c, "real cold visibility target failed: " .. oldPage .. " / " .. lane)
        Check(M.auraAppearanceContainer == "blizzardPlayer", "cold visibility target selected normal Aura view")
    end
end

Check(M.PageHasReset("auras3_styling"), "extension toolbar reset missing")
local warning = M.BuildPageResetWarning("auras3_styling")
Check(warning and warning:find("Suite", 1, true), "extension reset used core Buff warning")
local model = core.MSUF_Auras3.MenuModel
model.WriteHideBlizzardBuffFrame(true)
model.WriteHideBlizzardDebuffFrame(true)
local beforeShape = model.EnsureDB().shared.appearanceIconShapes
beforeShape = beforeShape and beforeShape.buff
Check(M.ResetPageToDefaults("auras3_styling"), "extension reset failed")
Check(S.Config("playerAuras").iconWidth == P.catalog.playerAuras.rules.iconWidth.default, "reset missed Suite layout")
Check(not model.ReadHideBlizzardBuffFrame() and not model.ReadHideBlizzardDebuffFrame(), "reset missed visibility")
Check((model.EnsureDB().shared.appearanceIconShapes or {}).buff == beforeShape, "extension reset changed UnitFrame appearance")
Check(core.History.Undo(), "Aura reset was not undoable")
Settle()
Check(S.Config("playerAuras").iconWidth == 63, "undo did not restore Suite layout")
Check(model.ReadHideBlizzardBuffFrame() and model.ReadHideBlizzardDebuffFrame(), "undo did not restore core visibility")
Check(core.History.Redo(), "Aura reset was not redoable")
Settle()
Check(S.Config("playerAuras").iconWidth == P.catalog.playerAuras.rules.iconWidth.default, "redo missed Suite layout")
local affectingCombat = env.UnitAffectingCombat
env.UnitAffectingCombat = function() return true end
Check(not M.ResetPageToDefaults("auras3_styling"), "Aura reset allowed combat")
Check(not P.PlayerAurasPage.Open("playerAuras"), "Aura shortcut allowed combat")
env.UnitAffectingCombat = affectingCombat

M.SetMenuStateValue("auraAppearanceContainer", "buff")
Select("auras3_styling")
Check(M.AurasPage.AppearanceResetProvider("auras3_styling") == nil, "reset owner did not follow selection")
Check(not Widget("auras3.shared.hideBlizzardBuffFrame"), "Suite duplicated Blizzard visibility in Buff appearance")
Check(M.PageHasReset("auras3_styling"), "normal Buff reset disappeared")
local factory = core.MSUF_CreateFactoryDefaultProfile
core.MSUF_CreateFactoryDefaultProfile = core.DefaultsSchema.BuildRecoveryDefaults
for _, kind in ipairs({ "buff", "debuff" }) do
    M.SetMenuStateValue("auraAppearanceContainer", kind)
    Select("auras3_styling")
    model.WriteHideBlizzardBuffFrame(true)
    model.WriteHideBlizzardDebuffFrame(true)
    Check(not M.BuildPageResetWarning("auras3_styling"):find("visibility", 1, true), "normal reset warning still claims Blizzard visibility")
    Check(M.ResetPageToDefaults("auras3_styling"), "normal Aura reset failed")
    Check(model.ReadHideBlizzardBuffFrame() and model.ReadHideBlizzardDebuffFrame(), "normal Aura reset changed Suite-view visibility")
end
core.MSUF_CreateFactoryDefaultProfile = factory

local oldHost = { AurasPage = {} }
Check(not NS.HostBridge.RegisterPlayerAuraMenu(oldHost, {}), "old host acquired extension")
Check(not NS.HostBridge.SelectPlayerAuraMenu(oldHost), "old host selection changed")
Check(#mw.world.failures == 0, "client reported a script failure")
print("Player aura menu: " .. checks .. " checks passed (" .. flavor .. ")")
