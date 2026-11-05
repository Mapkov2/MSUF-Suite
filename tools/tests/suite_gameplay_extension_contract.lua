local suiteRoot = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local root = arg[3] or (suiteRoot:match("^(.*)/[^/]+$") .. "/MidnightSimpleUnitFrames")
local flavor = arg[2] or "Mainline"
local Open = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))().Open
local mw = Open(root, flavor, { page = "gameplay", clientScriptBindings = true, tocMetadata = true })
local env, M, core = mw.env, mw.M, mw.core
local methods = getmetatable(env.UIParent).__index
for _, key in ipairs({ "SetDrawBling", "SetSwipeColor", "SetSwipeTexture", "SetReverse", "SetEdgeScale", "SetMotionScriptsWhileDisabled", "SetCooldownFromDurationObject" }) do
    methods[key] = methods[key] or function() end
end
methods.GetUnboundedStringWidth = methods.GetUnboundedStringWidth or function(self) return self:GetStringWidth() end
methods.GetCountdownFontString = methods.GetCountdownFontString or function(self)
    if not self.countdownFont then self.countdownFont = self:CreateFontString(nil, "OVERLAY") end
    return self.countdownFont
end
methods.GetThumbTexture = function(self)
    if not self.testThumb then self.testThumb = self:CreateTexture(nil, "ARTWORK") end
    return self.testThumb
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
if flavor ~= "Forever" then
    assert(mw:Select("opt_misc"))
    for _, widget in ipairs(M.cache.opt_misc.searchWidgets or {}) do
        local record = widget._msuf2RuntimeControlRecord
        assert(not (record and (record.settingKey or ""):find("msufsuite.", 1, true)),
            "standalone MSUF already exposed Suite tooltips")
    end
end
local NS = {}
Load("MSUF_Suite", NS)
assert(NS.Database.Initialize(nil))
local S, W = NS.Suite, core.ProfileWorkbench
local defaults = core.ProfileFields.CopySnapshot(M.EnsureDB())
core.MSUF_CreateFactoryDefaultProfile = function() return core.ProfileFields.CopySnapshot(defaults) end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
-- The menu world does not initialize live unit-frame text runtimes.
env.MSUF_UFCore_NotifyConfigChanged = function() end
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
if flavor ~= "Forever" then
    Check(M.activeKey == "opt_misc" and Widget("msufsuite.tooltipVisibility.enabled"),
        "attaching Suite did not update the already visible tooltip page")
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
    Check(view.body:GetHeight() == view.top + view.panels[view.selected].height, "retained body height lost wrapped header")
    view:SelectCategory("lootMerchants")
    Check(view.body:GetHeight() == view.top + view.panels[view.selected].height, "category switch lost wrapped height")
    view.selector:SetWidth(savedWidth)
    for _, callback in ipairs(M.cache.suite_qualityOfLife.resizeCallbacks or {}) do callback() end
    view:SetFilter(view.filter)
    Check(view.top == savedTop, "selector unwrap did not restore top")
    Check(view.body:GetHeight() == view.top + view.panels[view.selected].height, "unwrapped body height wrong")
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

-- Artwork is native to MSUF; Suite must not append another owner.
local function CheckCastbarArtwork()
    local profiles = env.MSUF_GlobalDB.profiles
    profiles.ArtworkTransferTest = { general = {
        castbarTexture = "Interface\\AddOns\\MSUF_Suite\\Media\\BlizzardFrames\\CastFill.tga" } }
    local legacy = { profiles = {
        ArtworkTransferTest = { suite = { modules = { castbarArt = { enabled = true, namePanel = false } } } },
        UnmatchedArtworkTest = { suite = { modules = { castbarArt = { enabled = true } } } },
    } }
    NS.HostBridge.MigrateLegacyCastbarArtwork(legacy)
    local general = profiles.ArtworkTransferTest.general
    Check(general.castbarArtworkEnabled and general.castbarArtworkNamePanel == false
        and general.castbarTexture == "MSUF Blizzard Cast", "old Suite design did not transfer to inactive MSUF profile")
    Check(not legacy.profiles.ArtworkTransferTest.suite.modules.castbarArt,
        "successfully transferred Suite artwork settings remain active")
    Check(legacy.profiles.UnmatchedArtworkTest.suite.modules.castbarArt,
        "unmatched Suite artwork settings were discarded")
    profiles.ArtworkTransferTest = nil
    local activeName = assert(NS.HostBridge.ActiveFrameProfileName())
    local active = NS.HostBridge.CurrentFrameProfile().general
    local enabled, panel, texture = active.castbarArtworkEnabled, active.castbarArtworkNamePanel, active.castbarTexture
    active.castbarArtworkEnabled, active.castbarArtworkNamePanel = nil, nil
    active.castbarTexture = "Interface\\AddOns\\MSUF_Suite\\Media\\BlizzardFrames\\CastFill.tga"
    local activeLegacy = { profiles = { [activeName] = { suite = { modules = {
        castbarArt = { enabled = true, namePanel = false } } } } } }
    NS.HostBridge.MigrateLegacyCastbarArtwork(activeLegacy)
    Check(active.castbarArtworkEnabled and active.castbarArtworkNamePanel == false
        and active.castbarTexture == "MSUF Blizzard Cast", "active artwork settings did not transfer")
    if core.Castbars.Config then
        local current = core.Castbars.Config.Read().general
        Check(current.castbarArtworkEnabled and current.castbarArtworkNamePanel == false,
            "active artwork migration left a stale runtime snapshot")
    end
    active.castbarArtworkEnabled, active.castbarArtworkNamePanel, active.castbarTexture = enabled, panel, texture
    if core.Castbars.Config then core.Castbars.Config.Compile("style") end
    Check(not P.CastbarArtworkPage and not S.catalog.castbarArt and not S.instances.castbarArt,
        "Suite still registers a castbar artwork owner")
    Check(not P.QoLView.FindFeature("castbarArt"), "Suite still advertises castbar artwork")
    for _, row in ipairs(P.SearchRows()) do
        Check(row.suiteModuleId ~= "castbarArt", "Suite still indexes castbar artwork")
    end
    Select("opt_castbar")
    Check(not Widget("msufsuite.castbarArt.enabled") and not Widget("msufsuite.castbarArt.namePanel"),
        "Suite still appends duplicate castbar artwork controls")
    if core.MSUF_CastbarStyle and core.MSUF_CastbarStyle.ApplyCastbarArtwork then
        M.Widgets.EnsureSectionContent(assert(M.cache.opt_castbar.sections.castbar_textures))
        Settle()
        local found = {}
        local function Walk(frame)
            local action = frame._msuf2CommandAction
            if action then found[action.settingKey] = true end
            for _, child in ipairs(frame.children or {}) do if child.parent == frame then Walk(child) end end
        end
        Walk(M.cache.opt_castbar.wrapper)
        Check(found["general.castbarArtworkEnabled"] and found["general.castbarArtworkNamePanel"],
            "native MSUF castbar controls disappeared when Suite loaded")
        for _, target in ipairs({
            { pageKey = "suite_qualityOfLife", settingKey = "msufsuite.castbarArt.namePanel" },
            { pageKey = "suite_qualityOfLife", sectionId = "suite_qualityOfLife_castbarArt_castbar_art" },
            { pageKey = "opt_castbar", controlId = P.Meta("opt_castbar", "castbarArt", "enabled",
                "setting", "opt_castbar_castbarArt_module").controlId },
        }) do
            Select("home")
            local called, opened, focused = api.OpenSearchTarget(target.pageKey, "Castbar artwork", nil, nil, nil, target)
            Settle()
            Check(called and opened and focused and M.activeKey == "opt_castbar", "old artwork favourite did not open native settings")
        end
    end
end
CheckCastbarArtwork()

-- Existing destinations own all relocated settings, links and resets together.
local function CheckQoLOwners()
    Check(P.QoLOwners ~= nil, "the remaining QoL ownership map is missing")
    local expected = {
        inventoryProtection = "suite_bags", lootVendorRules = "suite_bags", guildChatPrivacy = "suite_chat",
        mapLandingShortcuts = "suite_minimap", autoUprank = "suite_actionbars",
        xpBar = "suite_hud", skyriding = "suite_hud", flightTimer = "suite_hud", lootToastFilter = "suite_hud",
        tooltipClassColors = "opt_misc", tooltipSpellCopy = "opt_misc", itemCounts = "opt_misc", tooltipIDs = "opt_misc",
        tooltipVisibility = "opt_misc", tooltipDetails = "opt_misc", tooltipMPlusScore = "opt_misc",
    }
    local legacyCategory = { pageKey = "suite_qualityOfLife", sectionId = "suite_qualityOfLife_category_tooltips" }
    local called, opened, focused = M.SearchBridge.OpenSearchTarget("suite_qualityOfLife", "", nil, nil, {}, legacyCategory)
    Check(called and opened and focused and M.activeKey == "opt_misc", "old tooltip category opened an empty QoL group")
    Check(legacyCategory.pageKey == "suite_qualityOfLife", "old category record mutated")
    local rows, available = {}, {}
    for _, row in ipairs(P.SearchRows()) do
        if expected[row.suiteModuleId] then
            Check(row.pageKey == expected[row.suiteModuleId], "cold search retained QoL: " .. row.suiteModuleId)
            if row.settingKey then rows[row.settingKey] = row end
        end
    end
    Select("suite_qualityOfLife")
    local ui = M.cache.suite_qualityOfLife.qualityOfLifeView
    for id in pairs(ui.categories) do ui:SelectCategory(id) end
    for _, row in pairs(ui.rows) do Check(not expected[row.group.id], "QoL still draws " .. row.group.id) end
    for _, id in ipairs({ "qol", "loot", "quests", "lootContainers", "socketGemSuggestions", "chatProfileLinks", "dailyComfort" }) do
        Check(not P.QoLOwners.PageFor(id), "convenience helper moved by name instead of function: " .. id)
    end
    for id, page in pairs(expected) do
        Check(P.QoLOwners.PageFor(id) == page, "incorrect owner: " .. id)
        local key, feature = "msufsuite." .. id .. ".enabled", P.QoLView.FindFeature(id)
        local section = P.QoLView.FeatureSectionId(feature)
        if P.Available(id) then
            available[#available + 1] = id
            Check(rows[key], "missing cold switch: " .. id)
            Select("home")
            Check(S.Open(id), "module shortcut failed: " .. id)
            Settle()
            Check(M.activeKey == page and Widget(key) and Widget(key):IsVisible(), "hidden or misplaced switch: " .. id)
            if page == "suite_hud" then
                local hud = M.cache[page]._msufSuiteHUDWorkspace
                -- Context fields are retained on entry.ctx by the real host.
                hud = hud or M.cache[page].ctx and M.cache[page].ctx._msufSuiteHUDWorkspace
                Check(not hud or hud.selected == "extras", "HUD search did not select its displays group")
            end
            local control = P.Meta("suite_qualityOfLife", id, "enabled", "setting", section).controlId
            for _, target in ipairs({
                { pageKey = "suite_qualityOfLife", settingKey = key },
                { pageKey = "suite_qualityOfLife", sectionId = section },
                { pageKey = "suite_qualityOfLife", controlId = control },
                { pageKey = "suite_qualityOfLife", controlId =
                    P.Meta("suite_qualityOfLife", id, "action.reset.enabled", "action", section).controlId },
            }) do
                local value = S.Config(id).enabled
                Select("home")
                local called, opened, focused = M.SearchBridge.OpenSearchTarget("suite_qualityOfLife", "", nil, nil, {}, target)
                Settle()
                Check(called and opened and focused and M.activeKey == page, "legacy link failed: " .. id)
                Check(target.pageKey == "suite_qualityOfLife" and S.Config(id).enabled == value, "legacy link mutated state: " .. id)
            end
            for _, rule in ipairs(P.catalog[id].controls) do
                local detail = rows["msufsuite." .. id .. "." .. rule.key]
                if detail then
                    local called, opened, focused = M.SearchBridge.OpenSearchTarget(page, "", nil, nil, {}, detail)
                    Settle()
                    Check(called and opened and focused, "exact detail failed: " .. id .. "." .. rule.key)
                end
            end
        else
            Check(not rows[key], "unavailable client feature was indexed: " .. id)
        end
    end
    -- Mutate one ordinary detail per available module, preserving all switches.
    local samples = {}
    for _, id in ipairs(available) do
        for _, rule in ipairs(P.catalog[id].controls) do
            if not rule.hidden and rule.key ~= "enabled" and not rule.color and type(rule.default) == "boolean" then
                samples[id] = { key = rule.key, default = rule.default, value = not rule.default }
                S.Config(id)[rule.key] = not rule.default
                break
            end
        end
    end
    Check(M.ResetPageToDefaults("suite_qualityOfLife"), "QoL reset failed")
    for id, sample in pairs(samples) do Check(S.Config(id)[sample.key] == sample.value, "QoL reset crossed owner: " .. id) end
    local checked = {}
    for id, page in pairs(expected) do
        if samples[id] and not checked[page] then
            checked[page] = true
            Select(page)
            Check(M.ResetPageToDefaults(page), "destination reset failed: " .. page)
            for module, sample in pairs(samples) do
                local value = sample.value
                if expected[module] == page then value = sample.default end
                Check(S.Config(module)[sample.key] == value, "wrong reset ownership: " .. page .. " / " .. module)
            end
            Check(M.Undo(), "destination reset has no Undo: " .. page)
            for module, sample in pairs(samples) do Check(S.Config(module)[sample.key] == sample.value, "Undo lost " .. module) end
        end
    end
    local version = M.pages.opt_misc.version
    P.QoLOwners.Register()
    Check(M.pages.opt_misc.version == version, "repeated tooltip registration duplicated the page")
    env.UnitAffectingCombat = function() return true end
    Check(not M.ResetPageToDefaults("opt_misc"), "tooltip reset allowed combat")
    Check(not S.Open("xpBar"), "relocated shortcut allowed combat")
    env.UnitAffectingCombat = combat
end
CheckQoLOwners()

print("suite_gameplay_extension_contract: " .. flavor .. " " .. checks .. " checks")
