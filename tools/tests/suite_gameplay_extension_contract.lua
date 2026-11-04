local suiteRoot = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local root = arg[3] or (suiteRoot:match("^(.*)/[^/]+$") .. "/MidnightSimpleUnitFrames")
local flavor = arg[2] or "Mainline"
local Open = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))().Open
local mw = Open(root, flavor, { page = "gameplay", clientScriptBindings = true, tocMetadata = true })
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
assert(not (M.cache.gameplay and M.cache.gameplay.qualityOfLifeView),
    "standalone MSUF already exposed Suite controls")
assert(mw:Select("opt_castbar"))
mw:RunTimers()
for _, widget in ipairs(M.cache.opt_castbar.searchWidgets or {}) do
    local record = widget._msuf2RuntimeControlRecord
    assert(not (record and (record.settingKey or ""):find("msufsuite.", 1, true)),
        "standalone MSUF already exposed Suite castbar artwork")
end
if flavor ~= "Forever" then assert(mw:Select("gameplay")) end
local NS = {}
Load("MSUF_Suite", NS)
assert(NS.Database.Initialize(nil))
local S, W = NS.Suite, core.ProfileWorkbench
local defaults = core.ProfileFields.CopySnapshot(M.EnsureDB())
core.MSUF_CreateFactoryDefaultProfile = function() return core.ProfileFields.CopySnapshot(defaults) end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
local originalContext = M.Search.Text.ControlContext
local finishCalls = 0
local originalRegister = NS.HostBridge.RegisterPageExtension
NS.HostBridge.RegisterPageExtension = function(menu, pageKey, name, provider)
    local finish = provider.finish
    provider.finish = function(key)
        finishCalls = finishCalls + 1
        return finish(key)
    end
    return originalRegister(menu, pageKey, name, provider)
end
local P = {}
Load("MSUF_Suite_Options", P)
NS.HostBridge.RegisterPageExtension = originalRegister

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
if flavor == "Forever" then
    Check(M.activeKey == "opt_castbar" and Widget("msufsuite.castbarArt.enabled"),
        "attaching Suite did not update the already visible Cast Bars page")
end
Check(P.GameplayPage.registered, "Suite Gameplay extension not registered")
if originalContext then
    local context = M.Search.Text.ControlContext
    Check(context("msufsuite.enemyCastStack.enabled") == "", "Suite setting leaked raw search words")
    Check(context("suite_qualityOfLife_enemyCastStack_dungeon_casts") == "", "Suite section leaked raw search words")
    for _, key in ipairs({ "gameplay.enableCombatTimer", "gameplay_crosshair", "msufsuiteX.foo", 42, false }) do
        Check(context(key) == originalContext(key), "Suite adapter changed another search context")
    end
    Check(context(nil) == originalContext(nil), "Suite adapter changed nil search context")
else
    Check(M.Search.Text.ControlContext == nil, "host without context helper acquired a shim")
end
if M.HasPageExtension then
    Check(M.HasPageExtension("gameplay", "MSUF_Suite.Gameplay"), "host lost extension")
end
local gameplayNav
for _, item in ipairs(M.navItems) do if item.key == "gameplay" then gameplayNav = item end end
Check(gameplayNav and gameplayNav.group == "general", "Suite helpers must use General > Gameplay")
Check(#P.QoLView.GetCategories() == 6, "Gameplay helpers remained in QoL")
P.SortQualityOfLifeCategories()
local features = {}
for _, feature in ipairs(P.QoLView.GameplayCategory.features) do features[feature.id] = feature end
local moved = 0
for id in pairs(features) do
    moved = moved + 1
    Check(P.GameplayPage.Relocated(id), "module not relocated: " .. id)
end
Check(moved == 14, "wrong Gameplay inventory")
local rows = {}
for _, row in ipairs(P.SearchRows()) do
    local id = row.suiteModuleId
    if features[id] then
        Check(row.pageKey == "gameplay", "search points to old page: " .. id)
        Check(P.Available(id), "search exposed an unavailable Suite action: " .. id)
        rows[row.settingKey or row.controlId or row.sectionId] = row
    end
end
local key = "msufsuite.actionTracker.enabled"
Check(rows[key], "combat feature missing from cold search")
local original = { pageKey = "suite_qualityOfLife", settingKey = key,
    sectionId = "suite_qualityOfLife_actionTracker_action_tracker" }
local page, target = P.GameplayPage.Resolve(original.pageKey, original)
Check(page == "gameplay" and target.settingKey == key, "saved search did not move")
Check(original.pageKey == "suite_qualityOfLife", "saved search was mutated")
Select("gameplay")
Check(Widget("gameplay.enableCombatTimer"), "extension replaced core Gameplay controls")
Check(Widget(key), "Suite feature toggle missing")
local contextFunction = M.Search.Text.ControlContext
local version = M.pages.gameplay.version
P.GameplayPage.Register()
Check(M.pages.gameplay.version == version, "repeat registration duplicated Gameplay")
Check(M.Search.Text.ControlContext == contextFunction, "repeat registration wrapped search twice")
Select("suite_qualityOfLife")
local view = M.cache.suite_qualityOfLife.qualityOfLifeView
Check(view and #view.selector.buttons == 6 and type(view.selector.GetLayoutMetrics) == "function",
    "QoL must use the same directly clickable groups as Unitframes")
if M.cache.suite_qualityOfLife.resizeCallbacks then
    local savedWidth = view.selector:GetWidth()
    local savedTop = view.top
    view.selector:SetWidth(360)
    for _, callback in ipairs(M.cache.suite_qualityOfLife.resizeCallbacks or {}) do callback() end
    view:SetFilter(view.filter)
    Check(view.top > savedTop, "retained selector did not wrap")
    Check(view.body:GetHeight() == view.top + view.panels[view.selected].height + 12, "retained body height lost wrapped header")
    view:SelectCategory("lootMerchants")
    Check(view.body:GetHeight() == view.top + view.panels[view.selected].height + 12, "category switch lost wrapped height")
    view.selector:SetWidth(savedWidth)
    for _, callback in ipairs(M.cache.suite_qualityOfLife.resizeCallbacks or {}) do callback() end
    view:SetFilter(view.filter)
    Check(view.top == savedTop, "selector unwrap did not restore top")
    Check(view.body:GetHeight() == view.top + view.panels[view.selected].height + 12, "unwrapped body height wrong")
end
local history = M.CanUndo and M.CanUndo()
view.selector.buttons[2]:GetScript("OnClick")(view.selector.buttons[2])
Check(view.selected == "lootMerchants", "native group click did not select its contents")
Check(not history or M.CanUndo(), "navigation disturbed history")

M.InvalidatePage("gameplay")
Select("home")
Check(S.Open("actionTracker"), "cold runtime shortcut failed")
Settle()
Check(M.activeKey == "gameplay" and Widget(key), "runtime shortcut opened wrong page")
Select("home")
local api = M.Search._CoreAPI
local ok, focused, exact = api.OpenSearchTarget(original.pageKey, "Action tracker", nil, nil, nil, original)
Settle()
Check(ok and focused and exact and M.activeKey == "gameplay", "legacy toggle failed exact navigation")
local oldCategory = { pageKey = "suite_qualityOfLife", sectionId = "suite_qualityOfLife_category_combatAlerts" }
Select("home")
ok, focused = api.OpenSearchTarget(oldCategory.pageKey, "Combat & Alerts", nil, nil, nil, oldCategory)
Settle()
Check(ok and focused and M.activeKey == "gameplay", "legacy category failed navigation")
local detail
for _, row in pairs(rows) do
    if row.suiteModuleId == "actionTracker" and row.settingKey ~= key and row.kind ~= "button" then
        detail = row
        break
    end
end
Check(detail, "detail search row missing")
Select("home")
ok, focused, exact = api.OpenSearchTarget(detail.pageKey, detail.label, nil, nil, nil, detail)
Settle()
Check(ok and focused and exact and Widget(detail.settingKey), "detail failed exact navigation")

-- QoL reset preserves the moved settings; Gameplay reset includes both stores.
S.Config("actionTracker").enabled = not P.catalog.actionTracker.rules.enabled.default
local saved = S.Config("actionTracker").enabled
S.Config("actionTracker").width = 370
Check(M.ResetPageToDefaults("suite_qualityOfLife"), "QoL reset failed")
Check(S.Config("actionTracker").enabled == saved, "QoL reset changed moved settings")
Check(S.Config("actionTracker").width == 370, "QoL reset changed moved layout")
local gameplay = M.AdvancedPage.Gameplay()
gameplay.enableCombatTimer = true
local warning = M.BuildPageResetWarning("gameplay")
Check(warning and warning:find("Suite", 1, true), "combined reset warning omitted Suite")
Check(M.ResetPageToDefaults("gameplay"), "combined Gameplay reset failed")
Check(S.Config("actionTracker").enabled == saved, "page reset changed module enablement")
Check(S.Config("actionTracker").width == P.catalog.actionTracker.rules.width.default, "Suite reset incomplete")
Check(M.Undo(), "combined reset cannot be undone")
Check(S.Config("actionTracker").enabled == saved, "Undo did not restore Suite settings")
Check(S.Config("actionTracker").width == 370, "Undo did not restore Suite layout")
Check(M.AdvancedPage.Gameplay().enableCombatTimer == true, "Undo did not restore host settings")
-- A partial extension failure must keep host and Suite changes undoable.
local beforeFinish = finishCalls
local originalReset = P.S.Reset
P.S.Reset = function(id)
    local result = originalReset(id)
    if id == "actionTracker" then return false end
    return result
end
Check(not M.ResetPageToDefaults("gameplay"), "partial Suite failure was reported as success")
P.S.Reset = originalReset
Check(finishCalls == beforeFinish + 1, "partial reset skipped refresh/cleanup")
Check(M.Undo(), "partial Gameplay reset lost its undo entry")
Check(S.Config("actionTracker").width == 370 and M.AdvancedPage.Gameplay().enableCombatTimer == true,
    "partial reset Undo did not restore both owners")
local combat = env.UnitAffectingCombat
env.UnitAffectingCombat = function() return true end
Check(not M.ResetPageToDefaults("gameplay"), "reset allowed during combat")
env.UnitAffectingCombat = combat

-- Artwork belongs to the existing Cast Bars page, including old search links.
local function CheckCastbarArtwork()
    Check(P.CastbarArtworkPage and P.CastbarArtworkPage.registered, "Castbar artwork was not moved to Cast Bars")
    Check(not P.QoLView.FindFeature("castbarArt"), "Castbar artwork remains a QoL feature")
    local artRows = {}
    for _, row in ipairs(P.SearchRows()) do
        if row.suiteModuleId == "castbarArt" then
            Check(row.pageKey == "opt_castbar", "artwork search retained the QoL destination")
            artRows[row.settingKey] = row
        end
    end
    local master, panel = "msufsuite.castbarArt.enabled", "msufsuite.castbarArt.namePanel"
    Check(artRows[master] and artRows[panel], "artwork lost a setting in cold search")
    Select("suite_qualityOfLife")
    local qos = M.cache.suite_qualityOfLife.qualityOfLifeView
    qos:SelectCategory("interface")
    Check(not qos.rows.suite_qualityOfLife_castbarArt_castbar_art, "QoL still draws the moved artwork row")
    S.Config("castbarArt").enabled, S.Config("castbarArt").namePanel = true, false
    M.InvalidatePage("opt_castbar")
    Select("home")
    Check(S.Open("castbarArt"), "cold artwork shortcut failed")
    Settle()
    Check(M.activeKey == "opt_castbar" and Widget(master) and Widget(panel), "artwork shortcut missed its settings")
    Check(S.Config("castbarArt").enabled and S.Config("castbarArt").namePanel == false,
        "moving to Cast Bars changed the saved artwork settings")
    local currentVersion = M.pages.opt_castbar.version
    P.CastbarArtworkPage.Register()
    Check(M.pages.opt_castbar.version == currentVersion, "artwork registration duplicated the host page")
    local oldSection = "suite_qualityOfLife_castbarArt_castbar_art"
    local oldControl = P.Meta("suite_qualityOfLife", "castbarArt", "namePanel", "setting", oldSection).controlId
    for _, legacy in ipairs({
        { pageKey = "suite_qualityOfLife", settingKey = panel, sectionId = oldSection },
        { pageKey = "suite_qualityOfLife", sectionId = oldSection },
        { pageKey = "suite_qualityOfLife", controlId = oldControl },
        { pageKey = "suite_qualityOfLife", controlId =
            P.Meta("suite_qualityOfLife", "castbarArt", "action.settings.enabled", "action", oldSection).controlId },
        { pageKey = "suite_qualityOfLife", controlId =
            P.Meta("suite_qualityOfLife", "castbarArt", "action.reset.enabled", "action", oldSection).controlId },
    }) do
        Select("home")
        local called, opened, focused = api.OpenSearchTarget(legacy.pageKey, "Castbar artwork", nil, nil, nil, legacy)
        Settle()
        Check(called and opened and focused and M.activeKey == "opt_castbar", "legacy artwork search did not focus Cast Bars")
        Check(legacy.pageKey == "suite_qualityOfLife", "artwork resolver mutated a saved search target")
        Check(S.Config("castbarArt").namePanel == false, "opening an old artwork action performed a reset")
    end
    for _, row in pairs(artRows) do
        Select("home")
        local called, opened, focused = api.OpenSearchTarget(row.pageKey, row.label, nil, nil, nil, row)
        Settle()
        Check(called and opened and focused and Widget(row.settingKey), "new artwork search did not resolve exactly")
    end
    Check(M.ResetPageToDefaults("suite_qualityOfLife"), "QoL reset failed with moved artwork")
    Check(S.Config("castbarArt").namePanel == false, "QoL reset changed artwork owned by Cast Bars")
    Check(M.ResetPageToDefaults("gameplay"), "Gameplay reset failed with a second embedded page")
    Check(S.Config("castbarArt").namePanel == false, "Gameplay reset changed Cast Bars settings")
    M.EnsureDB().general.castbarShakeStrength = 19
    local hostDefault = defaults.general.castbarShakeStrength
    local resetWarning = M.BuildPageResetWarning("opt_castbar")
    Check(resetWarning and resetWarning:find("Castbar artwork", 1, true), "Cast Bars reset warning omitted artwork")
    Check(M.ResetPageToDefaults("opt_castbar"), "combined Cast Bars reset failed")
    Check(M.EnsureDB().general.castbarShakeStrength == hostDefault, "Cast Bars reset lost the host settings")
    Check(S.Config("castbarArt").namePanel == true and S.Config("castbarArt").enabled,
        "Cast Bars reset lost artwork defaults or changed its enabled preference")
    Check(M.Undo(), "Cast Bars reset cannot be undone")
    Check(M.EnsureDB().general.castbarShakeStrength == 19 and S.Config("castbarArt").namePanel == false,
        "Cast Bars Undo did not restore both owners")
    env.UnitAffectingCombat = function() return true end
    Check(not M.ResetPageToDefaults("opt_castbar"), "Cast Bars reset allowed during combat")
    Check(not S.Open("castbarArt"), "artwork shortcut reported success during combat")
    env.UnitAffectingCombat = combat
end
CheckCastbarArtwork()

print("suite_gameplay_extension_contract: " .. flavor .. " " .. checks .. " checks")
