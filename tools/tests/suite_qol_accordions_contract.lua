local suiteRoot = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local root = arg[3] or (suiteRoot:match("^(.*)/[^/]+$") .. "/MidnightSimpleUnitFrames")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function AddNativeLineMethods(world)
    for _, key in ipairs({ "SetThickness", "SetStartPoint", "SetEndPoint" }) do
        world.widgets.Methods[key] = world.widgets.Methods[key] or function() end
    end
end
local mw = MenuWorld.Open(root, flavor, {
    page = "gameplay", clientScriptBindings = true, tocMetadata = true, beforeCore = AddNativeLineMethods,
})
local env, M, core = mw.env, mw.M, mw.core
env.GetCurrentKeyBoardFocus = function() return nil end
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
-- The host window precedes Suite initialization in this fixture.
M.SyncExternalHistoryState()

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
-- Independent acceptance follows native public host entries, not row internals.
local publicWidgets=P.W
local sectionSwitchCalls={}
local realSectionSwitch=publicWidgets.SectionSwitch
publicWidgets.SectionSwitch=function(body,...)
    local button=realSectionSwitch(body,...)
    sectionSwitchCalls[body]=button
    return button
end
local contexts={}
for _,page in ipairs({"suite_qualityOfLife","gameplay","suite_hud","suite_bags","opt_misc"}) do
    local build=M.pages[page].build
    M.pages[page].build=function(ctx,...)
        contexts[page]=ctx
        return build(ctx,...)
    end
    M.InvalidatePage(page)
end
local function Feature(id)
    return assert(P.QoLView.FindFeature(id), "missing feature "..id)
end
local function Section(id)
    local feature=Feature(id)
    return P.QoLView.FeatureSectionId(feature)
end
local function Native(id)
    local body=M.cache[M.activeKey].sections[Section(id)]
    local entry=body and P.HM.GetSectionEntry(body)
    Check(entry and entry.kind=="collapsible" and entry.header and entry.builder,
        "missing real native accordion: "..id)
    Check(sectionSwitchCalls[body]==entry.featureSwitch and entry.featureSwitch~=nil,
        "header does not use native SectionSwitch: "..id)
    Check(entry.header:GetParent()==entry.outer,"header lost native parent")
    return entry
end
local function ClickHeader(entry)
    entry.header:GetScript("OnClick")(entry.header,"LeftButton")
    Settle()
end
local function CountWidgets()
    return #(M.cache[M.activeKey].searchWidgets or {})
end
local function CheckGeometry(entry)
    Check(entry.outer:GetHeight()==entry.headerHeight+(entry.open and entry.contentHeight or 0),
        "accordion outer height does not track expanded content")
    local builder=entry.builder
    local priorBottom
    for _,row in ipairs(builder.layoutEntries) do
        if row.kind=="collapsible" and row.outer:IsShown() then
            local _,parent,_,_,y=row.outer:GetPoint(1)
            Check(parent==builder.parent and type(y)=="number","native flow lost its parent or coordinate")
            if priorBottom then Check(y<=priorBottom,"native accordion headers overlap") end
            priorBottom=y-row.outer:GetHeight()
        end
    end
end
local function FindDetail(id)
    for _,rule in ipairs(P.catalog[id].controls) do
        if rule.key~="enabled" and not rule.hidden and not rule.color and not rule.requires
            and not rule.requiresChoice and not rule.enableKey and not rule.disabledBy
            and type(rule.default)=="boolean" then return rule end
    end
end
local function Exact(target,why)
    local called,opened,focused=M.SearchBridge.OpenSearchTarget(target.pageKey,"",nil,nil,{},target)
    Settle()
    Check(called and opened and focused,why)
end
S.Config("dailyComfort").enabled=false
S.Config("quietPopups").enabled=false
Select("suite_qualityOfLife")
local view=M.cache.suite_qualityOfLife.qualityOfLifeView
Check(view and view.selector,"existing category navigation missing")
view:SelectCategory(Feature("dailyComfort").category)
Settle()
local first,second=Native("dailyComfort"),Native("quietPopups")
Check(not first.open and not second.open,"fresh accordions did not default closed")
Check(not assert(first._msufSuiteResetButton, "missing QoL reset action"):IsShown(),
    "closed QoL section exposes its action button")
Check(not Widget("msufsuite.dailyComfort."..FindDetail("dailyComfort").key),"closed content eagerly instantiated")
local before=CountWidgets()
ClickHeader(first)
Check(first.open and not S.Config("dailyComfort").enabled,"opening enabled disabled feature")
do
    local setting = "msufsuite.parallelWindows.enabled"
    local toggle = Widget(setting)
    Check(toggle and toggle:IsVisible() and toggle:IsEnabled(), "independent window toggle is missing")
    Check(not toggle:GetChecked(), "parallel windows defaulted on")
    local limit = Widget("msufsuite.parallelWindows.windowLimit")
    Check(limit and limit:IsVisible() and not limit:IsEnabled() and S.Config("parallelWindows").windowLimit == 0,
        "parallel windows limit did not default to disabled and unlimited")
    toggle:GetScript("OnClick")(toggle, "LeftButton")
    Settle()
    Check(S.Config("parallelWindows").enabled and not S.Config("dailyComfort").enabled,
        "parallel windows toggle changed unrelated helpers")
    Check(limit:IsEnabled(), "window limit did not enable with parallel windows")
    MenuWorld.FireScript(limit, "OnValueChanged", 3, true)
    Settle()
    Check(S.Config("parallelWindows").windowLimit == 3, "window limit did not save from the slider")
    toggle:GetScript("OnClick")(toggle, "LeftButton")
    Settle()
    Check(not S.Config("parallelWindows").enabled, "parallel windows toggle did not turn off")
end
local detailRule=assert(FindDetail("dailyComfort"))
local detail=Widget("msufsuite.dailyComfort."..detailRule.key)
Check(detail and detail:IsVisible(),"open disabled feature did not show its options")
Check(detail:IsEnabled(),"off-state independent stored option is not editable")
local oldDetailValue=S.Config("dailyComfort")[detailRule.key]
detail:SetChecked(not oldDetailValue)
detail:GetScript("OnClick")(detail,"LeftButton")
Settle()
Check(S.Config("dailyComfort")[detailRule.key]==not oldDetailValue and not S.Config("dailyComfort").enabled,
    "editing stored option while off failed or enabled runtime")
Check(M.Undo(),"stored option edit has no Undo")
Check(S.Config("dailyComfort")[detailRule.key]==oldDetailValue and not S.Config("dailyComfort").enabled,
    "Undo did not restore independent option")
Check(M.Redo(),"stored option edit has no Redo")
mw.world:EnterCombat()
Settle()
Check(P.Combat() and not P.RuleEnabled("dailyComfort",detailRule,nil,false,true),"off-state policy bypassed combat gate")
Check(not mw.win:IsShown(),"native menu did not close at combat start")
Check(not P.Set("dailyComfort",detailRule.key,oldDetailValue),"off-state edit committed during combat")
Check(S.Config("dailyComfort")[detailRule.key]==not oldDetailValue,"combat edit changed stored option")
mw.world:LeaveCombat()
Check(P.Suite.Menu.Open("suite_qualityOfLife"),"menu failed to reopen after combat")
Settle()
local built=CountWidgets()
Check(built>before,"opening did not instantiate lazy controls")
ClickHeader(second)
Check(first.open and second.open,"opening second accordion closed the first")
CheckGeometry(first)
CheckGeometry(second)
local stableCount=CountWidgets()
ClickHeader(first)
Check(not first.open and second.open,"closing one accordion changed another")
ClickHeader(first)
Check(first.open and CountWidgets()==stableCount,"reopening duplicated detail controls")
-- Direct master click must not open/close its header.
local wasOpen=first.open
first.featureSwitch:SetChecked(true)
first.featureSwitch:GetScript("OnClick")(first.featureSwitch,"LeftButton")
Settle()
Check(S.Config("dailyComfort").enabled and first.open==wasOpen,"master toggle changed accordion state")
first.featureSwitch:SetChecked(false)
first.featureSwitch:GetScript("OnClick")(first.featureSwitch,"LeftButton")
Settle()
Check(not S.Config("dailyComfort").enabled,"master did not switch back off")
Check(first.open and second.open,"master change closed an accordion")
-- Host persistence survives page reconstruction while module remains off.
M.InvalidatePage("suite_qualityOfLife")
Select("suite_qualityOfLife")
view=M.cache.suite_qualityOfLife.qualityOfLifeView
view:SelectCategory(Feature("dailyComfort").category)
Settle()
first,second=Native("dailyComfort"),Native("quietPopups")
Check(first.open and second.open,"native open state was lost on rebuild")
Check(not S.Config("dailyComfort").enabled,"rebuild enabled an off feature")
-- Deprecated actions are navigation-only, including control-only favourites.
for _,action in ipairs({"settings","reset"}) do
    local old=P.Meta("suite_qualityOfLife","dailyComfort","action."..action..".enabled","action",Section("dailyComfort"))
    Select("home")
    Exact({pageKey="suite_qualityOfLife",controlId=old.controlId},"old control-only "..action.." bookmark failed")
    Check(not S.Config("dailyComfort").enabled,"old action bookmark enabled a feature")
    Check(S.Config("dailyComfort")[detailRule.key]==not oldDetailValue,"old reset bookmark actually reset a setting")
end
-- The reset moved into the lazily created header menu and remains undoable.
do
    first = Native("dailyComfort")
    local more = assert(first._msufSuiteResetButton, "QoL feature has no header actions")
    Check(first._msuf2SectionActions == more and more:GetParent() == first.header, "reset is not a header action")
    Check(not more._msuf2GetSectionPopup(), "QoL reset popup was built before use")
    Check(not more:IsShown(), "an open QoL header exposes actions without interaction")
    first.header.mouseOver = true
    local tooltip = env.GameTooltip
    env.GameTooltip = nil
    MenuWorld.FireScript(first.header, "OnEnter")
    env.GameTooltip = tooltip
    Check(more:IsShown(), "hover did not reveal the open QoL section's actions")
    more:GetScript("OnClick")(more)
    local popup = assert(more._msuf2GetSectionPopup(), "QoL reset popup did not open")
    MenuWorld.FireVisibilityScripts(popup)
    first.header.mouseOver = false
    MenuWorld.FireScript(first.header, "OnLeave")
    Check(more:IsShown(), "moving off the header hid the active QoL action")
    local reset
    for _, child in ipairs({ popup:GetChildren() }) do
        if child:GetObjectType() == "Button" and child:GetText() == P.Tr("Reset section") then reset = child end
    end
    Check(reset and popup:IsShown(), "QoL popup has no Reset section action")
    reset:GetScript("OnClick")(reset)
    Settle()
    Check(not popup:IsShown() and not more:IsShown(), "reset did not close and hide the section menu")
    Check(S.Config("dailyComfort")[detailRule.key] == detailRule.default and not S.Config("dailyComfort").enabled,
        "QoL reset did not restore the feature's settings while preserving its switch")
    Check(M.Undo(), "QoL header reset has no Undo")
    Check(S.Config("dailyComfort")[detailRule.key] == not oldDetailValue and not S.Config("dailyComfort").enabled,
        "Undo did not restore the QoL option after reset")
    local target = P.HM.GetControlSearchMeta(more)
    first.SetOpenByUser(false)
    Select("home")
    Exact({ pageKey = "suite_qualityOfLife", sectionId = Section("dailyComfort"), controlId = target.controlId,
        prepareKind = target.searchPrepareKind, prepareValue = target.searchPrepareValue },
        "exact reset search did not reach the header menu")
    first = Native("dailyComfort")
    more = first._msufSuiteResetButton
    popup = more._msuf2GetSectionPopup()
    Check(first.open and popup and popup:IsShown() and more:IsShown(), "exact reset search left the menu hidden")
    Check(S.Config("dailyComfort")[detailRule.key] == not oldDetailValue, "search activated the reset")
    popup:Hide()
    first.SetOpenByUser(false)
    first.SetOpenByUser(true)
end
-- Every relocated feature opens native controls and reveals a hidden owner tab.
for _,case in ipairs({
    {id="xpBar",page="suite_hud",context="_msufSuiteHUDWorkspace",other="objectives",wanted="extras"},
    {id="inventoryProtection",page="suite_bags",other="bags",wanted="inventory"},
    {id="actionTracker",page="gameplay"},
    {id="tooltipVisibility",page="opt_misc"},
}) do
    if P.Available(case.id) then
        Select(case.page)
        Check(not M.cache[case.page].qualityOfLifeView.filterControl,"embedded helper group exposed redundant filters")
        local native=Native(case.id)
        Check(not Widget("msufsuite."..case.id.."."..assert(FindDetail(case.id)).key),"relocated details eager "..case.id)
        ClickHeader(native)
        Check(native.open,"relocated native header did not open "..case.id)
        local ctx=contexts[case.page]
        local workspace=case.context and ctx[case.context]
        if case.id=="inventoryProtection" then
            for _,value in pairs(ctx) do
                if type(value)=="table" and value.groups and value.groups.inventory then workspace=value end
            end
        end
        if workspace then workspace.select(case.other) end
        Select("home")
        local rule=FindDetail(case.id)
        Exact({pageKey=case.page,settingKey="msufsuite."..case.id.."."..rule.key,sectionId=Section(case.id)},
            "warm detail search failed "..case.id)
        Check(Widget("msufsuite."..case.id.."."..rule.key):IsVisible(),"search left detail hidden "..case.id)
        if workspace then Check(workspace.selected==case.wanted,"search did not reveal owner tab "..case.id) end
        CheckGeometry(Native(case.id))
    end
end
-- Both Forever additions use the existing menu and exact setting search.
for _, case in ipairs({
    { id = "foreverWorldMap", category = "travel", key = "zoneLevels" },
    { id = "gatheringTooltips", category = "questsProfessions", key = "worldTooltips" },
}) do
    Check(Feature(case.id).category == case.category, "Forever helper is in the wrong menu group")
    Check((P.Available(case.id) == true) == (flavor == "Forever"), "Forever helper lost its client gate")
    if flavor == "Forever" then
        Select("home")
        local key = "msufsuite." .. case.id .. "." .. case.key
        Exact({ pageKey = "suite_qualityOfLife", settingKey = key, sectionId = Section(case.id) },
            "exact Forever setting search failed " .. case.id)
        Check(Widget(key):IsVisible() and Native(case.id).open, "Forever search did not reveal its option")
        Check(not S.Config(case.id).enabled, "revealing a Forever setting activated the module")
    end
end
-- Unavailable client features are omitted by default, but explicitly discoverable.
Select("suite_qualityOfLife")
view=M.cache.suite_qualityOfLife.qualityOfLifeView
local unavailable=flavor=="Forever" and "mailRecipients" or "fishingComfort"
view:SetFilter("all")
view:SelectCategory(Feature(unavailable).category)
Settle()
local unavailableBody=M.cache.suite_qualityOfLife.sections[Section(unavailable)]
local unavailableEntry=unavailableBody and P.HM.GetSectionEntry(unavailableBody)
Check(not unavailableEntry or not unavailableEntry.outer:IsVisible(),"unavailable feature shown by default")
view:SetFilter("unavailable")
Settle()
unavailableEntry=Native(unavailable)
Check(unavailableEntry.outer:IsVisible(),"Unavailable filter did not reveal client-limited feature")
Check(unavailableEntry.featureSwitch:IsEnabled(),"unavailable master lost stored preference editing")
local unavailableBefore=S.Config(unavailable).enabled
unavailableEntry.featureSwitch:GetScript("OnClick")(unavailableEntry.featureSwitch,"LeftButton")
Settle()
Check(S.Config(unavailable).enabled~=unavailableBefore,"unavailable preference was not saved")
Check(not S.instances[unavailable] or not S.instances[unavailable].active,"unavailable preference started a runtime")
if not unavailableEntry.open then ClickHeader(unavailableEntry) end
local unavailableRule=assert(FindDetail(unavailable))
local unavailableDetail=Widget("msufsuite."..unavailable.."."..unavailableRule.key)
Check(unavailableDetail and not unavailableDetail:IsEnabled(),"unavailable detail bypassed its client gate")
unavailableEntry.featureSwitch:GetScript("OnClick")(unavailableEntry.featureSwitch,"LeftButton")
Settle()
if P.Available("skyriding") then
    S.Config("skyriding").enabled=false
    S.Config("skyriding").showSpeed=false
    Select("suite_hud")
    Check(S.Open("skyriding"),"skyriding detail shortcut failed")
    Settle()
    local limit=Widget("msufsuite.skyriding.speedMax")
    local show=Widget("msufsuite.skyriding.showSpeed")
    Check(limit and not limit:IsEnabled(),"off-state policy bypassed dependent option gate")
    Check(show and show:IsEnabled(),"off-state parent option is not editable")
    show:SetChecked(true)
    show:GetScript("OnClick")(show,"LeftButton")
    Settle()
    Check(limit:IsEnabled() and not S.Config("skyriding").enabled,"dependent option did not follow stored parent")
end


-- A no-option feature stays a plain master row, not an empty accordion.
Select("suite_qualityOfLife")
view=M.cache.suite_qualityOfLife.qualityOfLifeView
view:SetFilter("all")
local plain
for _,feature in ipairs(P.QualityOfLifeSearchFeatures) do
    local _,rules=P.QoLView.FeatureRules(feature)
    if P.QoLView.GetFeaturePage(feature)=="suite_qualityOfLife" and P.Available(feature.id)
        and not P.QoLView.HasDetails(feature,rules) then plain=feature break end
end
Check(plain,"fixture has no plain feature")
view:SelectCategory(plain.category)
Settle()
Check(not M.cache.suite_qualityOfLife.sections[P.QoLView.FeatureSectionId(plain)],"plain feature acquired empty accordion")
Check(Widget("msufsuite."..plain.id.."."..plain.switch):IsVisible(),"plain master is hidden")
-- Empty filtered flows must not fall back to all native collapsibles.
view:SelectCategory("interface")
for _,feature in ipairs(view.categories.interface.features) do S.Config(feature.id).enabled=false end
view:SetFilter("all")
first=Native("dailyComfort")
first.SetOpenByUser(true)
Settle()
view:SetFilter("enabled")
Settle()
Check(view.emptyShown,"probe did not produce empty filter")
Check(view.body:GetHeight()<=view.top+100,"empty filter retained invisible heights")
M.InvalidatePage("suite_qualityOfLife")
Select("suite_qualityOfLife")
view=M.cache.suite_qualityOfLife.qualityOfLifeView
Check(view.emptyShown,"saved enabled filter was lost")
Check(not Widget("msufsuite.dailyComfort.hideTutorials"),"saved-open filtered-out content eagerly rebuilt")
view:SetFilter("all")
Settle()
first=Native("dailyComfort")
Check(first.open and Widget("msufsuite.dailyComfort.hideTutorials"),"revealing saved-open content did not build it")
-- A switch remains in the current filter for the change that was just made.
view:SetFilter("disabled")
first.featureSwitch:GetScript("OnClick")(first.featureSwitch,"LeftButton")
Settle()
Check(S.Config("dailyComfort").enabled and first.outer:IsVisible(),"changed feature vanished under disabled filter")
view:SetFilter("disabled")
Settle()
Check(not first.outer:IsVisible(),"clearing retained row did not reapply disabled filter")
-- Warm native headers must not displace the feature master aliases.
Select("gameplay")
for _,feature in ipairs(P.QoLView.GameplayCategory.features) do
    if P.Available(feature.id) then
        S.Config(feature.id).enabled=false
        P.QoLView.RevealFeature(feature,M.cache.gameplay,true)
    end
end
Settle()
Select("home")
P.InvalidateSearch()
local api=M.Search._CoreAPI
api.GetSearchRecords()
if api.WhenIndexReady then
    local ready=false
    api.WhenIndexReady(function()ready=true end)
    for i=1,1000 do if ready then break end mw:RunTimers() end
    Check(ready,"native search index did not finish")
end
for _,case in ipairs({{"enemy casts","enemyCastStack"},{"cast list","enemyCastStack"},{"action tracker","actionTracker"}}) do
    if P.Available(case[2]) then
        local found
        for rank,result in ipairs(api.SearchPages(case[1]) or {}) do
            local key=result.exactTarget and result.exactTarget.settingKey or result.settingKey
            if key=="msufsuite."..case[2]..".enabled" then found=rank break end
        end
        Check(found and found<=6,"warm master rank exceeds6: "..case[1].." rank="..tostring(found))
    end
end
do
    local meta = P.Meta("suite_qualityOfLife", "parallelWindows", "enabled", "setting", Section("dailyComfort"))
    local found
    for _, result in ipairs(api.SearchPages("Keep Blizzard windows open") or {}) do
        local target = result.exactTarget or result
        if target.controlId == meta.controlId then found = target break end
    end
    Check(found, "search did not find the Suite window toggle")
    Exact(found, "search could not open the Suite window toggle")
    Check(not S.Config("parallelWindows").enabled, "search changed the window setting")
    local limitTarget
    for _, result in ipairs(api.SearchPages("Blizzard window limit") or {}) do
        local target = result.exactTarget or result
        if target.settingKey == "msufsuite.parallelWindows.windowLimit" then limitTarget = target break end
    end
    Check(limitTarget, "search did not find the window limit")
    Exact(limitTarget, "search could not open the window limit")
end
-- Indicator samples use ordinary menu hit areas and exact real control routes.
-- Stand in only for the renderers; the pages, lazy content and search/focus
-- machinery above remain the shipped host + Suite implementations.
local previewCases = {
    { "xpBar", "DrawExperienceBarPreview", "suiteXPPreview", "displayStyle" },
    { "glimmer", "DrawGlimmerPreview", nil, "size" },
    { "skyriding", "DrawSkyridingPreview", "suiteFlightPreview", "width", "speedHeight", "fontSize", "displayStyle" },
    { "actionTracker", "DrawActionTrackerPreview", nil, "rowHeight" },
    { "battleRes", "DrawBattleResPreview", nil, "scale" },
    { "enemyCastStack", "DrawEnemyCastStackPreview", nil, "rowHeight" },
}
local createPreviewFrame, previewFrames = env.CreateFrame, 0
env.CreateFrame = function(...)
    previewFrames = previewFrames + 1
    return createPreviewFrame(...)
end
local openPreviewTarget, lastPreviewTarget = M.SearchBridge.OpenSearchTarget, nil
M.SearchBridge.OpenSearchTarget = function(page, label, anchor, section, route, exact)
    local called, opened, focused, matched = openPreviewTarget(page, label, anchor, section, route, exact)
    lastPreviewTarget = { key = exact.settingKey, matched = matched, called = called, opened = opened, focused = focused }
    return called, opened, focused, matched
end
for _, case in ipairs(previewCases) do
    local id, export, field = case[1], case[2], case[3]
    if P.Available(id) then
        S.Config(id).enabled = false
        S[export] = function(parent)
            local host = parent.testIndicatorHost
            if not host then
                host = env.CreateFrame("Frame", nil, parent)
                host:SetSize(220, 36)
                parent.testIndicatorHost = host
                if field then
                    local regions = { host = host }
                    for _, key in ipairs({ "rested", "levelText", "xpText", "percentText", "sessionText", "rateText", "etaText",
                        "details", "speed", "title", "state", "icon", "count" }) do
                        regions[key] = host:CreateTexture(nil, "ARTWORK")
                        regions[key]:SetSize(20, 12)
                    end
                    parent[field] = regions
                end
            end
            return host
        end
        local page = P.QoLView.GetFeaturePage(Feature(id))
        Select(page)
        Check(S.Open(id), "preview feature route failed " .. id)
        Settle()
        local ui = assert(contexts[page].qolIndicatorPreviews[id], "indicator preview missing " .. id)
        ui.Paint()
        for index = 4, #case do
            local key = case[index]
            local handle = assert(ui.targets and ui.targets[key], "indicator lacks exact click target " .. id .. "." .. key)
            Check(handle:IsVisible(), "indicator click target hidden " .. key)
            lastPreviewTarget = nil
            handle:GetScript("OnClick")(handle, "LeftButton")
            Settle()
            Check(lastPreviewTarget and lastPreviewTarget.key == "msufsuite." .. id .. "." .. key
                and lastPreviewTarget.called and lastPreviewTarget.opened and lastPreviewTarget.focused
                and lastPreviewTarget.matched, "preview did not focus exact control " .. id .. "." .. key)
            local widget = Widget("msufsuite." .. id .. "." .. key)
            Check(widget and widget:IsVisible(), "preview did not reveal exact setting " .. id .. "." .. key)
            Check(not S.Config(id).enabled, "preview click enabled a module " .. id)
        end
        local stable = previewFrames
        ui.Paint()
        ui.Paint()
        Check(previewFrames == stable, "warm indicator paint created hit areas")
        if id == "xpBar" then
            Check(ui.targets.percent:GetFrameLevel() > ui.targets.displayStyle:GetFrameLevel(),
                "movable text did not sit above the background target")
            ui.xpEditor.kit:Select(ui.targets.level)
            Check(ui.xpEditor.properties.selected == "level", "text selection did not select its own properties")
            ui.stage.suiteXPPreview.sessionText:Hide()
            ui.Paint()
            Check(not ui.targets.session:IsShown(), "hidden session text retained its hit area")
            ui.stage.suiteXPPreview.sessionText:Show()
            ui.Paint()
            local before = S.Config(id).displayStyle
            ui.sliders.xp:SetValue(12)
            Check(S.Config(id).displayStyle == before and not S.Config(id).enabled, "sample slider changed stored settings")
        end
        ui.stage:Hide()
        lastPreviewTarget = nil
        local handle = ui.targets[case[4]]
        handle:GetScript("OnClick")(handle, "LeftButton")
        Check(lastPreviewTarget == nil, "hidden preview navigated")
    end
end
env.CreateFrame = createPreviewFrame
M.SearchBridge.OpenSearchTarget = openPreviewTarget
if arg[4] == "xp-editor" then
    assert(loadfile(suiteRoot .. "/tools/tests/xp_editor_acceptance.lua"))()(mw, P,
        function() return contexts.suite_hud.qolIndicatorPreviews.xpBar end, Settle)
end
print("independent_native_accordion_acceptance: "..flavor.." "..checks.." checks")
