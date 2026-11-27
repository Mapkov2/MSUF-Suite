-- Real-host cold tabs, exact settings, legacy preview routes and rebuild ownership.
local root = assert(arg[1]):gsub("\\", "/")
local host = arg[3] or (root .. "/../MidnightSimpleUnitFrames-7.0")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(host .. "/tools/tests/menu_core_world.lua"))()
local function InstallLineMethods(world)
    local methods = world.widgets.Methods
    for _, name in ipairs({ "SetStartPoint", "SetEndPoint", "SetThickness" }) do
        if not methods[name] then methods[name] = function(self, ...) self[name .. "Args"] = { ... } end end
    end
end
local mw = MenuWorld.Open(host, flavor, { locale = "deDE", clientScriptBindings = true, beforeCore = InstallLineMethods })
local env, M, world = mw.env, mw.M, mw.world
world.widgets.Methods.SetTextHeight = function(self, value) self.textHeight=value end
world.widgets.Methods.GetUnboundedStringWidth = world.widgets.Methods.GetUnboundedStringWidth
    or function(self) return self:GetStringWidth() end
world.widgets.Methods.SetPointsOffset = function(self,x,y) self.pointsOffset={x,y} end
world.widgets.Methods.ClearTextureSlice = function() end
world.widgets.Methods.CreateMaskTexture = function(self) return self:CreateTexture() end
world.widgets.Methods.AddMaskTexture = function(self, mask) self.testMask = mask end
world.widgets.Methods.RemoveMaskTexture = function(self, mask)
    assert(self.testMask == mask, "removing a mask from the wrong texture")
    self.testMask = nil
end
world.widgets.Methods.SetVertexOffset = function() end
world.widgets.Methods.SetGradient = function(self, axis) self.gradientAxis = axis end
env.C_SpecializationInfo = {GetSpecialization=function() return 1 end,
    GetSpecializationInfo=function() return flavor=="Forever" and 1482 or 71,"Fixture specialization" end}
-- Client visibility includes every ancestor; the generic widget stubs only
-- model each region's own shown flag.
world.widgets.Methods.IsVisible = function(self)
    local parent = self:GetParent()
    return self:IsShown() and (not parent or parent:IsVisible())
end
env.InCombatLockdown, env.UnitAffectingCombat = function() return false end, function() return false end
env.GetCurrentKeyBoardFocus = function() return nil end
env.IsControlKeyDown, env.IsShiftKeyDown = function() return false end, function() return false end
env.C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
env.C_AddOns = {
    GetAddOnMetadata = function() end, IsAddOnLoaded = function(name) local loaded = name:find("^MSUF") ~= nil or name:find("^MidnightSimpleUnitFrames") ~= nil return loaded, loaded end,
    DoesAddOnExist = function(name) return name:find("^MSUF_Suite") ~= nil end,
    GetAddOnEnableState = function() return 2 end, LoadAddOn = function() return false, "MISSING" end,
    GetNumAddOns = function() return 0 end,
}
local function Load(addon, namespace)
    local file = assert(io.open(root .. "/" .. addon .. "/" .. addon .. "_Mainline.toc", "rb"))
    local source = file:read("*a"); file:close()
    for line in source:gmatch("[^\r\n]+") do
        if line:sub(1, 1) ~= "#" then
            local path = root .. "/" .. addon .. "/" .. line:gsub("\\", "/")
            if path == arg[5] then path = arg[6] end
            local ok, message = world:LoadFile(path, addon, namespace)
            assert(ok, tostring(message))
        end
    end
end
env.C_CVar.GetCVar = function() return "1" end
env.C_GameRules = { IsGameRuleActive = function() return false end }
Load("MSUF_Suite", {})
local Suite, P = env.MSUFSuite, {}
assert(Suite.Database.Initialize(nil))
Suite.Suite.Config("nameplates").enabled = true
if arg[4]=="fallback" then M.RegisterSearchTargetResolver=nil end
Load("MSUF_Suite_Options", P)


local enforce=arg[4]~='measure'
P.InvalidateSearch()
local api=M.Search._CoreAPI
local function Ready()
    api.GetSearchRecords()
    local ready=false
    if api.WhenIndexReady then assert(api.WhenIndexReady(function() ready=true end)) else mw:RunTimers(1000); ready=true end
    for i=1,1000 do if ready then break end; mw:RunTimers(1000) end
    assert(ready,'index did not settle')
    return api.GetSearchRecords()
end
local built,widgets,panels={}, {},{}
local controlsBySection = {}
local preview, interruptLink
local outlineLinks = {}
local CreateEditor, OriginalButton = P.NameplatesEditor.Create, P.Button
local BindHandle = P.NameplatesEditor.Bind
P.NameplatesEditor.Bind = function(editor, region, ...)
    assert(region:GetObjectType() == "Button", "preview handles require Button:RegisterForClicks")
    return BindHandle(editor, region, ...)
end
local RenderStatus = P.NameplatesPreviewDecor.PaintStatus
local statusSamples = {}
local PaintHealthGradient = P.NameplatesPreviewDecor.PaintHealthGradient
local healthGradient
P.NameplatesPreviewDecor.PaintHealthGradient = function(sample, metrics)
    PaintHealthGradient(sample, metrics)
    if sample.prefix == "enemy" and not sample.static then healthGradient = sample.healthGradient end
end
P.NameplatesPreviewDecor.PaintStatus = function(editor, sample, ...)
    RenderStatus(editor, sample, ...)
    if editor == preview and sample.statusSamples then statusSamples[sample.prefix] = sample.statusSamples end
end
P.NameplatesEditor.Create = function(...)
    preview = CreateEditor(...)
    return preview
end
P.Button = function(ctx, parent, label, ...)
    local button = OriginalButton(ctx, parent, label, ...)
    if label == "Open interrupt settings" then interruptLink = button end
    if label == "Frame Outline" then outlineLinks[#outlineLinks + 1] = button end
    return button
end
local GateControls = P.GateControls
P.GateControls = function(ctx, id, entries, ...)
    if id == "nameplates" then
        for _, entry in ipairs(entries) do
            if entry.widget then widgets[entry.rule.key] = widgets[entry.rule.key] or entry.widget end
        end
    end
    return GateControls(ctx, id, entries, ...)
end
local TextCards = P.NameplatesSectionsLayout.TextCards
P.NameplatesSectionsLayout.TextCards = function(ctx, parent, y, width, spec, tab, ...)
    local key = spec.key .. ":" .. tab.id
    built[key], panels[key] = (built[key] or 0) + 1, parent
    return TextCards(ctx, parent, y, width, spec, tab, ...)
end
local CastCards = P.NameplatesSectionsLayout.CastCards
P.NameplatesSectionsLayout.CastCards = function(ctx, parent, y, width, tab, sectionId, ...)
    local key = sectionId:match("^suite_nameplates_(.+)$") .. ":" .. tab.id
    built[key], panels[key] = (built[key] or 0) + 1, parent
    return CastCards(ctx, parent, y, width, tab, sectionId, ...)
end
local RuleGrid=P.RuleGrid
P.RuleGrid=function(ctx,parent,page,id,rules,...)
    if id=='nameplates' then
        for _,section in ipairs(P.NameplateSections) do
            for _,tab in ipairs(section.tabs or {}) do
                if rules==tab.rules then
                    local key=section.key..':'..tab.id
                    built[key]=(built[key] or 0)+1
                    panels[key]=parent
                end
            end
        end
    end
    local y,entries=RuleGrid(ctx,parent,page,id,rules,...)
    if id=='nameplates' then
        local _, _, _, section = ...
        local controls = section and controlsBySection[section]
        if section and not controls then controls = {}; controlsBySection[section] = controls end
        for _,entry in ipairs(entries) do
            if entry.widget then
                widgets[entry.rule.key]=entry.widget
                if controls then controls[entry.rule.key] = entry.widget end
            end
        end
    end
    return y,entries
end
local shortcuts = {}
local AttachColors = P.AttachRuleColors
P.AttachRuleColors = function(body, title, id, rules, ...)
    local colors = {}
    for _, rule in ipairs(rules) do if rule.color then colors[rule.key] = true end end
    shortcuts[body] = colors
    return AttachColors(body, title, id, rules, ...)
end
local links, statusActions, opacityActions, layoutTabs = {}, {}, {}, {}
local textColorLinks = {}
local indicatorChoices = {}
local BindDropdownAt = M.BindDropdownAt
M.BindDropdownAt = function(ctx, parent, label, x, y, values, width, get, set, ...)
    if label == P.Tr("Indicator") and values[1] and values[1].value == "raid" then
        indicatorChoices[P.NameplatesWorkspace.Kind()] = { values = values, set = set }
    end
    return BindDropdownAt(ctx, parent, label, x, y, values, width, get, set, ...)
end
local RegisterControlMetadata = M.RegisterControlMetadata
M.RegisterControlMetadata = function(widget, meta, label, ...)
    local id = meta.sectionId and meta.sectionId:match("^suite_nameplates_(%a+)$")
    if label == "Text Colors" and (id == "enemyText" or id == "friendlyText") then textColorLinks[id] = widget end
    if id and (id:match("Basics$") or id:match("Style$")) and widget.buttons and widget.values then
        layoutTabs[id] = widget
    end
    if (label == "Preview current" or label == "Show all") and meta.sectionId then
        local tab = meta.controlId:find("preview.more", 1, true) and "more" or "basic"
        statusActions[meta.sectionId .. "." .. tab .. "." .. label] = widget
    end
    return RegisterControlMetadata(widget, meta, label, ...)
end
local Button = P.Button
P.Button = function(ctx, parent, label, x, y, width, click, enabled, meta, options)
    local button = Button(ctx, parent, label, x, y, width, click, enabled, meta, options)
    if meta and meta.sectionId == "suite_nameplates_enemyText.name" then links[label] = button end
    if label == "Show in preview" and meta and meta.sectionId == "suite_nameplates_enemyOpacity" then
        opacityActions[meta.controlId:match("%.([^.]+)$")] = click
    end
    assert(not (label == "Edit in preview" and meta and meta.sectionId:match("^suite_nameplates_")),
        "Nameplates accordion still built an Edit in preview button")
    return button
end

local function SelectPreview(...)
    local function Menu()
        local items = {}
        return { items = items, CreateButton = function(_, label, callback)
            local entry = Menu()
            entry.callback = callback
            items[label] = entry
            return entry
        end }
    end
    local root, open = Menu(), P.AnchoredContextMenu
    P.AnchoredContextMenu = function(_, build) build(nil, root) end
    preview.elementPicker:Click()
    P.AnchoredContextMenu = open
    local entry = root
    for index = 1, select("#", ...) do
        local key = select(index, ...)
        entry = assert(entry.items[P.Tr(key)], "missing preview element: " .. key)
    end
    assert(entry.callback, "preview element has no selection action")()
    return preview.body._selectedHandle
end

if M.RegisterBarsScope then
    local scopeBar
    local BuildScopeBar = M.Widgets.ScopeOverrideBar
    M.Widgets.ScopeOverrideBar = function(ctx, ...)
        local bar = BuildScopeBar(ctx, ...)
        if ctx.key == "opt_bars" then scopeBar = bar end
        return bar
    end
    env.MSUF_DB.general.hpPowerTextSelectedKey = "player"
    local nativeScope = "player"
    local target = { pageKey = "opt_bars", sectionId = "suite_nameplate_health_textures",
        settingKey = "msufsuite.nameplates.nativeHealthBackgroundTexture" }
    local opened, focused, exact = (M.Search._RoutingAPI or api).OpenSearchTarget("opt_bars",
        "shared health background texture", nil, nil, nil, target)
    assert(opened and focused and exact, "cold exact search did not open Nameplates")
    local bars = M.cache.opt_bars
    local native = assert(P.HM.GetSectionEntry(bars.sections.bars_textures))
    local nameplates = assert(P.HM.GetSectionEntry(bars.sections.suite_nameplate_health_textures))
    local last = scopeBar.values[#scopeBar.values]
    assert(last.value == "suite_nameplates", "Nameplates must be the last Bars scope")
    assert(scopeBar:GetValue() == last.value and nameplates.outer:IsVisible() and not native.outer:IsVisible(),
        "the texture link did not select the dedicated Nameplates scope")
    assert(env.MSUF_DB.general.hpPowerTextSelectedKey == nativeScope, "the link overwrote the unit-frame scope")
    assert(not bars.sections.suite_nameplate_gradients, "the separate gradient accordion is still visible")
    local slantedSection = assert(P.NameplateBarTextures.Target("enemySlantedHealth")).section
    assert(bars.sections[slantedSection], "Bars lacks the dedicated Slanted Bars accordion")
    if M.BarsSlantedProvider then
        assert(slantedSection == "bars_slanted", "Nameplates still builds a separate Slanted Bars section")
    end
    assert(Suite.HostBridge.OpenExactMenuSetting(M, "opt_bars", slantedSection, "msufsuite.nameplates.enemySlantedHealth"),
        "exact targeting did not open the Slanted Bars accordion")
    local controls = controlsBySection[slantedSection]
    if slantedSection == "bars_slanted" then
        local meta = P.Meta("opt_bars", "nameplates", "enemySlantedHealth", "setting", slantedSection)
        local entry = assert(M.RuntimeControlCatalog.Get(meta.controlId), "shared Slanted Bars lacks the Nameplate switch")
        controls = { enemySlantedHealth = entry.widget }
        controlsBySection[slantedSection] = controls
        assert(scopeBar:GetValue() == last.value, "the exact Nameplate search left the Unit Frame scope selected")
        assert(scopeBar:SetValue("shared"))
        assert(P.HM.GetSectionEntry(bars.sections[slantedSection]).outer:IsVisible(),
            "the shared Slanted Bars section was hidden in the native scope")
        assert(scopeBar:SetValue(nativeScope))
        assert(scopeBar:SetValue(last.value))
        local enabled = assert(M.RuntimeControlCatalog.Get(M.ControlMeta("opt_bars", "global", "slanted.enabled").controlId)).widget
        if not enabled:GetChecked() then enabled:Click() end
        local function SharedControl(path)
            return assert(M.RuntimeControlCatalog.Get(M.ControlMeta("opt_bars", "global", "slanted." .. path).controlId)).widget
        end
        for _, path in ipairs({ "units", "groups", "class_resources", "power", "mouseover", "castbars" }) do
            assert(SharedControl(path):IsVisible(), "Nameplates lost a control from the native Slanted Bars section")
        end
        local direction = SharedControl("direction")._msuf2ControlSchema
        local previous = env.MSUF_DB.bars.slantedBarDirection
        direction.set("LEFT_UP")
        assert(direction.get() == "LEFT_UP" and P.Get("nameplates", "slantedDirection") == 5
            and env.MSUF_DB.bars.slantedBarDirection == previous, "Nameplate cut direction wrote to the Shared profile")
        direction.set("DEFAULT")
        assert(P.Get("nameplates", "slantedDirection") == 1)
        P.Set("nameplates", "enemySlantedHealth", false)
        SharedControl("apply_preset"):Click()
        assert(P.Get("nameplates", "enemySlantedHealth"), "the native preset skipped nameplates")
        P.Set("nameplates", "enemySlantedHealth", false)
    end
    local slanted = assert(controls and controls.enemySlantedHealth, "Slanted Bars lacks the Nameplate switch")
    assert(slanted:IsVisible())
    local initialSlanted = P.Get("nameplates", "enemySlantedHealth")
    assert(P.Set("nameplates", "enemySlantedHealth", not initialSlanted))
    mw:RunTimers(1000)
    assert(slanted:GetChecked() ~= initialSlanted, "the Bars toggle missed the edit from Nameplates")
    slanted:Click()
    assert(P.Get("nameplates", "enemySlantedHealth") == initialSlanted, "the Bars toggle wrote to a different setting")
    for _, key in ipairs({ "healthGradientEnabled", "powerGradientDirUp", "healthGlossEnabled", "powerGlossStrength" }) do
        assert(Suite.HostBridge.OpenExactMenuSetting(M, "opt_bars", target.sectionId, "msufsuite.nameplates." .. key),
            "search did not open the consolidated accordion for " .. key)
    end
    local reset = assert(M.BarsScopeResetProvider("opt_bars"))
    local prior = P.Get("nameplates", "nativeHealthFillTexture")
    local inherited = assert(Suite.HostBridge.SharedNameplateBars())
    local toggle = assert(P.RuleRow("opt_bars", "nameplates", P.catalog.nameplates.rules.barsOverride))
    local healthTexture = assert(P.RuleRow("opt_bars", "nameplates", P.catalog.nameplates.rules.nativeHealthFillTexture))
    assert(healthTexture.get() == inherited.nativeHealthFillTexture, "the disabled override did not show the Shared texture")
    local look = P.Get("nameplates", "look")
    toggle.set(true)
    assert(toggle.get() and P.Get("nameplates", "barsOverrideSaved")
        and P.Get("nameplates", "nativeHealthFillTexture") == inherited.nativeHealthFillTexture
        and P.Get("nameplates", "look") == look,
        "the first custom override did not start from Shared")
    P.Set("nameplates", "nativeHealthFillTexture", "Blizzard")
    P.Set("nameplates", "healthGradientEnabled", true)
    P.Set("nameplates", "powerGradientStrength", 80)
    local material, strengths = Suite.GlossMaterial, {}
    local Fill = material.Fill
    material.Fill = function(owner, fill, strength, opacity)
        if strength then strengths[strength] = true end
        return Fill(owner, fill, strength, opacity)
    end
    P.Set("nameplates", "healthGlossStrength", 75)
    P.Set("nameplates", "healthGlossEnabled", true)
    P.Set("nameplates", "powerGlossStrength", 85)
    P.Set("nameplates", "powerGlossEnabled", true)
    mw:RunTimers(1000)
    material.Fill = Fill
    assert(strengths[75] and strengths[85], "the Bars live preview did not paint both gloss settings")
    toggle.set(false)
    assert(healthTexture.get() == inherited.nativeHealthFillTexture, "turning off the override did not return to Shared")
    toggle.set(true)
    assert(healthTexture.get() == "Blizzard" and P.Get("nameplates", "powerGlossStrength") == 85,
        "turning the override back on lost the custom settings")
    P.Set("nameplates", "enemySlantedHealth", true)
    assert(M.ResetPageToDefaults("opt_bars"), "nameplate page reset failed")
    assert(not P.Get("nameplates", "enemySlantedHealth"), "the Nameplates Bars reset left Slanted on")
    assert(P.Get("nameplates", "nativeHealthFillTexture") == P.catalog.nameplates.rules.nativeHealthFillTexture.default
        and env.MSUF_DB.general.hpPowerTextSelectedKey == nativeScope, "page reset crossed scope ownership")
    assert(not P.Get("nameplates", "healthGradientEnabled") and P.Get("nameplates", "powerGradientStrength") == 45,
        "the Nameplates Bars reset left one gradient edited")
    assert(not P.Get("nameplates", "healthGlossEnabled") and P.Get("nameplates", "powerGlossStrength") == 50,
        "the Nameplates Bars reset left one gloss edited")
    P.Set("nameplates", "nativeHealthFillTexture", prior)
    assert(reset and scopeBar:SetValue("shared"))
    assert(Suite.HostBridge.OpenExactMenuSetting(M, "opt_bars", target.sectionId, target.settingKey),
        "the nameplate link did not work on the cached Bars page")
    assert(scopeBar:GetValue() == last.value and scopeBar:SetValue("shared"))
    assert(native.outer:IsVisible() and not nameplates.outer:IsVisible() and not M.BarsScopeResetProvider("opt_bars"),
        "Shared still contains nameplate textures")
    scopeBar.buttons[#scopeBar.buttons]:Click()
    assert(scopeBar:GetValue() == last.value and nameplates.outer:IsVisible(), "clicking the final Bars tab did not select it")
    assert(Suite.HostBridge.OpenExactMenuSetting(M, "opt_bars", "bars_outline", "bars.barOutlineTexture"),
        "native exact search failed from the Nameplates tab")
    assert(scopeBar:GetValue() == "shared" and native.outer:IsVisible() and not nameplates.outer:IsVisible(),
        "native search did not switch back to the native Bars view")
    M.Widgets.ScopeOverrideBar = BuildScopeBar
end

local function OpenNameTextCard()
    assert(M.SelectPage("suite_nameplates"))
    assert(P.NameplatesWorkspace.Open("enemy"))
    for _, spec in ipairs(P.NameplateSections) do
        if spec.key == "enemyText" then assert(spec.select("name")) break end
    end
    mw:RunTimers(1000)
end

local records, previewOffsets = {}, {}
for _,record in ipairs(Ready()) do
    local setting=record.exactTarget and record.exactTarget.settingKey
    if setting and setting:find('^msufsuite%.nameplates%.') then records[setting]=record end
    local section = record.exactTarget and record.exactTarget.sectionId
    local offset = section and section:match("^suite_nameplates_status_offset_(.+)$")
    if offset then previewOffsets[offset] = record end
end
local cases={
    {'enemyTextMode','enemyText:hp'}, {'enemyNameSize','enemyText:name'}, {'enemyHealthTextSize','enemyText:hp'},
    {'friendlyLevelSize'}, {'friendlyRaidIconSize'}, {'enemyStatusCombatSize'},
    {'enemyPowerBorderSize'}, {'enemyPowerSource'},
    {'enemyNameFadeIn','enemyText:name'}, {'enemyPowerTextMode','enemyText:power'}, {'friendlyHealthTextMouseover','friendlyText:hp'},
    {'enemyTargetStyle'}, {'enemyRaidRelativeAnchor'}, {'friendlyStatusAFKTimerAnchor'},
    {'enemyCastManualWidth','castbar:general'}, {'interruptFeedbackEnabled','castbar:general'},
    {'enemyCastTimeSize','castbar:time'}, {'enemyCastIconZoom','castbar:icon'},
    {'enemyCastForeground','castbar:advanced'}, {'enemyCastSpellIcon','castbar:icon'},
    {'enemyCastSpellName','castbar:spell'}, {'enemyCastTimeFormat','castbar:time'},
    {'friendlyCastHeight','friendlyCast:general'}, {'friendlyCastWidthDelta','friendlyCast:general'},
    {'friendlyCastTimeEnabled','friendlyCast:time'},
    {'interruptFeedbackDuration','castbar:advanced'},
    {'enemyNpcWorldVisible','enemyBasics:enemyNpc'}, {'enemyPlayerCastVisibility','enemyBasics:enemyPlayer'},
    {'enemyHideInCombat'}, {'enemyShowWhenInjured'},
    {'enemyFadeHealth','enemyOpacity:general'}, {'enemyFadeOutOfCombatAlpha','enemyOpacity:ooc'},
    {'enemyNpcOpacity','enemyOpacity:plate'}, {'enemyNpcScale','enemyBasics:enemyNpc'},
    {'friendlyNpcFadeHealthBackground','friendlyNpcOpacity:general'},
    {'enemyIdentityIcons'}, {'friendlyClickboxWidth','friendlyBasics:clicks'},
    {'neutralRangeAlpha'}, {'neutralRangeSpell'}, {'plateFadeDistance'}, {'friendlyNpcExtraTextTitleSize'},
    {'plateStackEnemy','enemyBasics:stacking'}, {'plateStackFriendly','friendlyBasics:stacking'},
    {'look','enemyStyle:blizzard'}, {'neutralStyleOutlineMode','neutralStyle:outline'},
    {'friendlyNpcStyleNativeHealthFillTexture','friendlyNpcStyle:textures'},
    {'enemyRangeAuto'}, {'neutralRangeAuto'}, {'friendlyRangeAuto'}, {'friendlyNpcRangeAuto'},
    {'enemySlantedHealth'}, {'enemyTargetPatternTexture','enemyStyle:frame'},
    {'neutralTargetPatternTexture','neutralStyle:frame'}, {'friendlyFocusPatternAlpha','friendlyStyle:frame'},
    {'friendlyNpcHoverPatternTexture','friendlyNpcStyle:frame'},
    {'castIconCombinedHeight','castbar:icon'}, {'castSeamLine','castbar:advanced'},
    {'targetClassResource','classResources:plate'}, {'targetUnitFrameResource','classResources:frame'},
    {'friendlyNpcDebuffs'}, {'neutralNpcHealthWidthDelta'},
    {'enemyNpcBuffs'}, {'enemyPlayerDebuffs'}, {'enemyNpcControl'}, {'auraEnemyBuffAlpha'},
}
local saved={}
for _,case in ipairs(cases) do
    assert(records['msufsuite.nameplates.'..case[1]],'missing cold record '..case[1])
    saved[case[1]]=P.Get('nameplates',case[1])
end
assert(not M.cache.suite_nameplates,'target page was prebuilt by cold search')
if enforce then
    local color = assert(records["msufsuite.nameplates.friendlyBackdropColor"])
    local opened, focused, exact = (M.Search._RoutingAPI or api).OpenSearchTarget(color.key,
        color.label, color.label, color.anchor, color.route, color.exactTarget)
    assert(opened and focused and exact and panels["friendlyStyle:frame"]:IsVisible(),
        "cold search missed the Friendly Style color action")
    local record=records['msufsuite.nameplates.enemyTextMode']
    local selected,anchored,exact=(M.Search._RoutingAPI or api).OpenSearchTarget(record.key,record.label,record.label,record.anchor,record.route,record.exactTarget)
    mw:RunTimers(1000)
    assert(selected and anchored and exact,'first cold page target failed')
    assert(widgets.enemyTextMode and widgets.enemyTextMode:IsVisible(),'first cold page target hidden')
end
assert(M.SelectPage('suite_nameplates'))
mw:RunTimers(1000)
assert(not M.cache.suite_nameplates.sections.suite_nameplates_shared, "the Shared section was still created")
assert(not records["msufsuite.nameplates.targetPatternTexture"], "the retired pattern appeared in search")
local placements = {}
local conditions
for _, section in ipairs(P.NameplateSections) do
    if section.key == "enemyVisibility" then conditions = section end
    for _, tab in ipairs(section.tabs or {}) do
        for _, key in ipairs(tab.keys or {}) do placements[key] = (placements[key] or 0) + 1 end
    end
end
assert(conditions and conditions.title == "Load Conditions" and not conditions.open
    and conditions.scopes.enemy and not conditions.scopes.neutral and not conditions.scopes.friendly
    and not conditions.scopes.friendlyNpc, "Enemy load conditions need their own collapsed section")
assert(#conditions.keys == #P.Suite.NameplateExtensions.EnemyConditions, "unexpected settings in Load Conditions")
for _, condition in ipairs(P.Suite.NameplateExtensions.EnemyConditions) do
    local key = condition.key
    local rule = assert(P.catalog.nameplates.rules[key])
    assert(not placements[key] and rule.sectionTitle == conditions.title, key .. " is outside Load Conditions")
    if P.catalog.nameplates.controlAvailable(rule) then
        local target = assert(records["msufsuite.nameplates." .. key]).exactTarget
        assert(target.sectionId == "suite_nameplates_enemyVisibility", key .. " search missed Load Conditions")
    end
end
assert(placements.plateShowAll == 1 and placements.plateEnemyMinus == 1, "native display controls disappeared")
local slantedTarget = P.NameplateBarTextures.Target("enemySlantedHealth")
if slantedTarget then
    local result = records["msufsuite.nameplates.enemySlantedHealth"]
    assert(not placements.enemySlantedHealth and result.exactTarget.pageKey == "opt_bars"
        and result.exactTarget.sectionId == slantedTarget.section,
        "Slanted must have one control with a search result under Bars > Nameplates")
else
    assert(placements.enemySlantedHealth == 1, "the fallback host lost the Slanted switch")
end
assert(not placements.protectImport and not placements.nativeProfileMode and not records["msufsuite.nameplates.protectImport"])
assert(not P.NameplatesWorkspace.Open("general"), "General remained in the type selector")
for _, key in ipairs({ "enemyTargetPatternTexture", "neutralTargetPatternTexture", "friendlyTargetPatternTexture",
    "friendlyNpcTargetPatternTexture", "neutralStyleOutlineMode", "friendlyNpcStyleNativeHealthFillTexture" }) do
    assert(placements[key] == 1, "duplicate or missing placements for " .. key)
end
local bySection={}
for key in pairs(built) do local section=key:match('^([^:]+)'); bySection[section]=(bySection[section] or 0)+1 end
for section,n in pairs(bySection) do
    print('initial '..section..' grids='..n)
    if enforce then assert(n<=1,'opening one section built hidden tabs: '..section..' '..n) end
end
do
    local text, friendlyText
    for _, spec in ipairs(P.NameplateSections) do
        if spec.key == "enemyText" then text = spec end
        if spec.key == "friendlyText" then friendlyText = spec end
    end
    local config = P.S.Config("nameplates")
    local prior = config.enemyHealthTextVisible
    config.enemyHealthTextVisible = true
    assert(P.NameplatesWorkspace.Open("enemy"))
    assert(text.select("hp"))
    local hp = assert(widgets.enemyHealthTextVisible)
    assert(hp:IsVisible() and hp:GetChecked() == true, "HP toggle did not read the current value on first show")
    config.enemyHealthTextVisible = false
    assert(text.select("name") and text.select("hp"))
    -- The fixture tracks ancestor visibility but only the client delivers
    -- the child's OnShow when a parent tab becomes visible.
    MenuWorld.FireScript(hp, "OnShow")
    local mouseover = assert(widgets.enemyHealthTextMouseover)
    MenuWorld.FireScript(mouseover, "OnShow")
    assert(hp:GetChecked() == false, "HP toggle kept its old state after switching tabs")
    assert(not mouseover:IsEnabled(), "HP mouseover kept its old availability after switching tabs")
    hp:Click()
    assert(hp:GetChecked() == true and config.enemyHealthTextVisible == true, "HP toggle differs from its written state")
    local previousFriendly = config.friendlyHealthTextVisible
    config.friendlyHealthTextVisible = false
    assert(P.NameplatesWorkspace.Open("friendly") and friendlyText.select("hp"))
    local friendlyHP = assert(widgets.friendlyHealthTextVisible)
    MenuWorld.FireScript(friendlyHP, "OnShow")
    assert(friendlyHP:IsVisible() and friendlyHP:GetChecked() == false, "Friendly HP toggle read Enemy's value")
    assert(P.NameplatesWorkspace.Open("enemy"))
    assert(P.Set("nameplates", "friendlyHealthTextVisible", previousFriendly))
    assert(P.Set("nameplates", "enemyHealthTextVisible", prior))
end
local function Open(case)
    assert(M.SelectPage('home'))
    Ready()
    local record=records['msufsuite.nameplates.'..case[1]]
    local selected,anchored,exact=(M.Search._RoutingAPI or api).OpenSearchTarget(record.key,record.label,record.label,record.anchor,record.route,record.exactTarget)
    mw:RunTimers(1000)
    assert(selected and anchored and exact,'cold target did not resolve exactly: '..case[1])
    local controls = controlsBySection[record.exactTarget.sectionId]
    local widget = controls and controls[case[1]] or widgets[case[1]]
    if widget and not widget:IsVisible() then
        local p=widget
        for i=1,12 do if not p then break end
            print('HIDDEN',i,p:GetName(),p:IsShown(),p.sectionId,p._msufSuiteArea,p._msuf2ExactTabView and p._msuf2ExactTabView.value)
            p=p:GetParent()
        end
    end
    assert(widget and widget:IsVisible(),'target is hidden: '..case[1])
    if case[2] then
        assert(panels[case[2]] and panels[case[2]]:IsVisible(),'correct tab did not become visible: '..case[2])
        assert(built[case[2]]==1,'tab was rebuilt: '..case[2])
    end
end
local function SlantedLink()
    if not slantedTarget or slantedTarget.section ~= "bars_slanted" then return end
    assert(P.OpenNameplateSetting("enemyTargetPatternTexture"))
    local meta = P.Meta("suite_nameplates", "nameplates", "link.enemySlantedHealth", "action", "suite_nameplates_enemyStyle")
    local link = assert(M.RuntimeControlCatalog.Get(meta.controlId), "Nameplate Style lacks the Slanted Bars link").widget
    assert(link:IsVisible())
    link:Click()
    assert(M.activeKey == "opt_bars" and M.SelectedBarsExtension() == "suite_nameplates")
end
local function RoundedLink()
    if not M.BarsRoundedProvider then return end
    local target = assert(P.NameplateBarTextures.Target("roundedHealth"), "Rounded Nameplates lacks a Bars target")
    assert(target.section == "bars_rounded")
    assert(not placements.roundedHealth, "the Nameplates menu built a second Rounded toggle")
    assert(P.OpenNameplateSetting("enemyTargetPatternTexture"))
    local linkMeta = P.Meta("suite_nameplates", "nameplates", "link.roundedHealth", "action", "suite_nameplates_enemyStyle")
    local link = assert(M.RuntimeControlCatalog.Get(linkMeta.controlId), "Nameplate Style lacks a Rounded link").widget
    assert(link:IsVisible())
    link:Click()
    assert(M.activeKey == "opt_bars" and M.SelectedBarsExtension() == "suite_nameplates")

    local coreBars = env.MSUF_DB.bars
    local rounded, slanted = coreBars.roundedFramesEnabled, coreBars.slantedBarsEnabled
    coreBars.roundedFramesEnabled, coreBars.slantedBarsEnabled = true, false
    local body = assert(M.cache.opt_bars.sections.bars_rounded)
    local entry = assert(P.HM.GetSectionEntry(body))
    assert(entry.outer:IsVisible())
    local setting = P.Meta("opt_bars", "nameplates", "roundedHealth", "setting", target.section)
    local toggle = assert(M.RuntimeControlCatalog.Get(setting.controlId), "the shared Rounded section lacks the Nameplates toggle").widget
    assert(toggle:IsVisible())
    controlsBySection[target.section] = { roundedHealth = toggle }
    M.RequestRefresh(M.cache.opt_bars.ctx, "rounded-nameplate-test")
    mw:RunTimers(1000)
    if toggle:GetChecked() then toggle:Click() end
    assert(not P.Get("nameplates", "roundedHealth"))
    toggle:Click()
    assert(P.Get("nameplates", "roundedHealth"), "the Rounded Nameplates switch did not update the existing profile")
    assert(M.SelectBarsExtension(nil) and entry.outer:IsVisible() and toggle:IsVisible())
    assert(Suite.HostBridge.OpenExactMenuSetting(M, "opt_bars", target.section, setting.settingKey))
    assert(M.SelectedBarsExtension() == "suite_nameplates" and M.cache.opt_bars.sections.bars_rounded == body)
    assert(M.ResetPageToDefaults("opt_bars"))
    assert(not P.Get("nameplates", "roundedHealth"), "Bars Nameplates reset skipped Rounded")
    coreBars.roundedFramesEnabled, coreBars.slantedBarsEnabled = rounded, slanted
end
local function CheckStyleColors()
    if not P.W.OpenContextColors then return end
    assert(M.SelectPage("suite_nameplates"))
    local openColors = P.OpenRuleColors
    for _, scope in ipairs({ "enemy", "neutral", "friendly", "friendlyNpc" }) do
        assert(P.NameplatesWorkspace.Open(scope))
        local section = "suite_nameplates_" .. scope .. "Style"
        local body = assert(M.cache.suite_nameplates.sections[section])
        P.HM.GetSectionEntry(body).SetOpenImmediate(true)
        P.EnsureSectionContent(body)
        local spec
        for _, candidate in ipairs(P.NameplateSections) do
            if candidate.key == scope .. "Style" then spec = candidate end
        end
        assert(spec and spec.select("frame"))
        local meta = P.Meta("suite_nameplates", "nameplates", scope .. "Style.colors", "action", section)
        local button = assert(M.RuntimeControlCatalog.Get(meta.controlId), "Style Colors has no direct link").widget
        assert(button:IsVisible() and button:GetParent() == body, "Style Colors is hidden in the overflow")
        local opened
        P.OpenRuleColors = function(anchor, title, id, palette)
            assert(anchor == button and title == "Colors" and id == "nameplates")
            local expected = (scope == "enemy" or scope == "neutral") and "enemyBackdropColor" or "friendlyBackdropColor"
            for _, rule in ipairs(palette) do if rule.key == expected then opened = true end end
        end
        button:Click()
        P.OpenRuleColors = openColors
        assert(opened, "the direct shortcut opened the wrong Nameplate palette")
    end
end
SlantedLink()
RoundedLink()
CheckStyleColors()
for _, scope in ipairs({ "neutral", "friendly" }) do
    assert(P.NameplatesWorkspace.Open(scope))
    Open({ "enemyHideInCombat" })
    assert(P.NameplatesWorkspace.Kind() == "enemy", "Load Conditions search did not switch from " .. scope)
end
for _,case in ipairs(cases) do Open(case); Open(case) end

do
    local config = P.S.Config("nameplates")
    local look, enabled, custom = config.look, config.healthGradientEnabled, config.barsOverride
    config.look, config.healthGradientEnabled, config.barsOverride = 3, true, true
    assert(P.NameplatesWorkspace.Open("enemy"))
    preview:Paint()
    local texture = assert(healthGradient and healthGradient[2], "the common preview did not paint the health gradient")
    assert(texture:IsShown() and texture.gradientAxis == "HORIZONTAL")
    config.look, config.healthGradientEnabled = look, enabled
    preview:Paint()
    assert(not texture:IsShown(), "the common preview retained a disabled gradient")
    config.barsOverride = custom
end

do
    Open({ "neutralRangeAlpha" })
    assert(P.NameplatesWorkspace.Kind() == "neutral")
    assert(records["msufsuite.nameplates.neutralRangeAlpha"].exactTarget.sectionId == "suite_nameplates_neutralRange")
    Open({ "neutralRangeSpell" })
    assert(widgets.neutralRangeSpell:GetObjectType() == "EditBox", "spell ID search did not open the input")
    Open({ "friendlyNpcExtraTextTitleSize" })
    local status
    for _, spec in ipairs(P.NameplateSections) do
        if spec.key == "friendlyNpcMarkers" then status = spec break end
    end
    assert(status and #status.tabs == 2 and status.currentStatus().key == "friendlyNpcExtraTextTitle",
        "NPC title search must select the indicator")
    local color = assert(records["msufsuite.nameplates.friendlyNpcExtraTextTitleColor"])
    assert(color.exactTarget.sectionId == "suite_nameplates_friendlyNpcMarkers")
    local opened, focused, exact = (M.Search._RoutingAPI or api).OpenSearchTarget(color.key,
        color.label, color.label, color.anchor, color.route, color.exactTarget)
    assert(opened and focused and exact, "text color did not resolve to the selected indicator")
end

do
    local cast = controlsBySection.suite_nameplates_castbar
    local widthMode, height = cast.enemyCastWidthMode:GetParent(), cast.enemyCastHeight:GetParent()
    local interrupt, surface = cast.interruptFeedbackEnabled:GetParent(), cast.enemyCastDisplay:GetParent()
    assert(widthMode == height:GetParent() and widthMode:GetWidth() > interrupt:GetWidth() and widthMode:GetWidth() > surface:GetWidth(),
        "Castbar General did not put both size columns in a full-width card")
    local friendly = controlsBySection.suite_nameplates_friendlyCast
    assert(friendly.interruptFeedbackWho and friendly.enemyCastDisplay, "Friendly Castbar lacks the shared General controls")
    local values = { enemyCastEnabled = P.Get("nameplates", "enemyCastEnabled"), enemyCastDisplay = P.Get("nameplates", "enemyCastDisplay"),
        enemyCastSpellTarget = P.Get("nameplates", "enemyCastSpellTarget"), friendlyNamesOnly = P.Get("nameplates", "friendlyNamesOnly") }
    P.NameplatesWorkspace.Open("friendly")
    Open({ "friendlyCastSize" })
    P.SetMany("nameplates", { enemyCastEnabled = 3, enemyCastDisplay = 2, enemyCastSpellTarget = false, friendlyNamesOnly = 2 })
    preview:Edit("anchor")
    local handle = SelectPreview("Castbar", "Spell target")
    assert(handle and handle.keyX == "friendlyCastTargetOffsetX" and handle.keyY == "friendlyCastTargetOffsetY",
        "Friendly cast-target preview did not reveal the disabled element for X/Y editing")
    assert(not friendly.friendlyCastTargetOffsetX and not friendly.friendlyCastTargetOffsetY
        and not cast.enemyCastOffsetX and not cast.enemyCastOffsetY, "Castbar still built X/Y sliders")
    assert(P.Get("nameplates", "enemyCastEnabled") == 3 and not P.Get("nameplates", "enemyCastSpellTarget"),
        "Castbar preview changed shared live visibility")
    local hp = assert(SelectPreview("Text", "HP Text"))
    assert(hp.keyX == "friendlyHealthTextOffsetX" and hp:IsVisible(), "name-only sample cannot edit health text")
    assert(P.Get("nameplates", "friendlyNamesOnly") == 2, "preview changed the friendly display mode")
    P.EditNameplatesPreview("anchor", "Health")
    assert(not handle:IsVisible(), "cast-target sample stayed visible after leaving Castbar preview")
    P.SetMany("nameplates", values)
end

do
    Open({ "enemyFadeOutOfCombatAlpha" })
    local general, ooc
    local oldPreview = P.PreviewNameplateOpacity
    P.PreviewNameplateOpacity = function(value)
        if value then ooc = true else general = true end
        oldPreview(value)
    end
    for key, action in pairs(opacityActions) do
        if key == "true" or key == "false" then action() end
    end
    P.PreviewNameplateOpacity = oldPreview
    assert(general and ooc, "opacity tabs did not both route to the shared preview")
    local names = { "enemyFadeHealth", "enemyFadeHealthBackground", "enemyFadeKeepText" }
    local saved = {}
    for _, key in ipairs(names) do saved[key] = P.Get("nameplates", key) end
    assert(P.NameplatesWorkspace.Open("enemy"))
    P.SetMany("nameplates", { enemyFadeHealth = 100, enemyFadeHealthBackground = 25, enemyFadeKeepText = false })
    P.PreviewNameplateOpacity(false)
    local name, hp = preview.kit.entries["enemy.Name"].region, preview.kit.entries["enemy.HealthText"].region
    assert(name:GetAlpha() == .25 and hp:GetAlpha() == .25, "background-only fade left preview text visible")
    P.Set("nameplates", "enemyFadeKeepText", true)
    preview:Paint()
    assert(name:GetAlpha() == 1 and hp:GetAlpha() == 1, "Keep Text did not restore the preview text")
    P.SetMany("nameplates", saved)
end

do
    local function StatusAction(tab, action)
        local id = "suite_nameplates_enemyMarkers." .. tab .. "." .. action
        assert(statusActions[id], id):Click()
    end
    Open({ "enemyStatusCombatSize" })
    local key = "enemy.StatusCombat"
    assert(not P.Get("nameplates", "enemyStatusCombat"), "new combat indicator should default to off")
    StatusAction("basic", "Preview current")
    assert(not preview.body._selectedHandle, "an off indicator appeared on the plate")
    assert(not P.Get("nameplates", "enemyStatusCombat"), "preview wrote the live combat switch")
    P.SetMany("nameplates", { enemyStatusCombat = true, enemyStatusDND = true, enemyStatusAFK = false })
    StatusAction("basic", "Preview current")
    local handle = assert(preview.body._selectedHandle)
    assert(handle._key == key and handle:IsVisible(), "status preview did not select the combat icon")
    local samples = assert(statusSamples.enemy)
    assert(not records["msufsuite.nameplates.enemyStatusLeaderSize"], "enemy group role leaked into search")
    assert(not records["msufsuite.nameplates.friendlyStatusBossNumberSize"], "friendly boss number leaked into search")
    Open({ "enemyStatusDNDSize" })
    StatusAction("basic", "Preview current")
    assert(preview.body._selectedHandle._key == "enemy.StatusDND", "DND text has no draggable preview handle")
    Open({ "enemyStatusCombatSize" })
    StatusAction("basic", "Preview current")
    assert(not samples.StatusDND or not samples.StatusDND.frame:IsShown(), "current displayed another enabled icon")
    StatusAction("basic", "Show all")
    assert(samples.StatusDND.frame:IsShown() and samples.StatusCombat.frame:IsShown(),
        "show all did not show both enabled NPC and player indicators")
    assert(not samples.StatusAFK or not samples.StatusAFK.frame:IsShown(), "show all displayed an off indicator")
    local spec
    for _, section in ipairs(P.NameplateSections) do
        if section.key == "enemyMarkers" then spec = section break end
    end
    assert(spec.select("more"))
    StatusAction("more", "Preview current")
    assert(preview.body._selectedHandle == handle, "More Options did not preview the same selected indicator")
    Open({ "enemyThresholdWidth" })
    Open({ "enemyFocusMarkerSize" })
    P.Set("nameplates", "enemyFocusMarker", true)
    StatusAction("basic", "Preview current")
    assert(preview.body._selectedHandle._key == "enemy.focusMarker", "focus preview has no editable handle")
    Open({ "enemyIdentityIcons" })
    P.Set("nameplates", "enemyIdentityIcons", 4)
    StatusAction("basic", "Preview current")
    assert(preview.body._selectedHandle._key == "enemy.identity", "identity preview has no editable handle")
    P.EditNameplatesPreview("text", "Name")
    assert(not samples.StatusDND.frame:IsShown(), "leaving the status preview kept forced player samples")
    P.SetMany("nameplates", { enemyStatusCombat = false, enemyStatusDND = false, enemyFocusMarker = false, enemyIdentityIcons = 1 })
end

do
    local cases = {
        { "enemy", "SoftTarget", "SoftTarget", "soft" },
        { "neutral", "quest", "quest", "quest" },
        { "enemy", "elite", "elite", "elite" },
        { "enemy", "identity", "identity", "identity" },
        { "enemy", "focusMarker", "focusMarker", "focus" },
        { "neutral", "Classification", "Classification", "classification" },
        { "friendly", "RaidIcon", "RaidIcon", "raid" },
        { "friendlyNpc", "Level", "Level", "level" },
        { "friendly", "targetRight", "target", "target", "enemy" },
    }
    local status = {}
    for _, spec in ipairs(P.NameplateSections) do
        if spec.statusItems then status[spec.plateScope] = spec end
    end
    assert(P.SetMany("nameplates", { enemyIdentityIcons = 4, enemyTargetHideFriendly = false }))
    for _, case in ipairs(cases) do
        local scope, element, sample, item, owner = unpack(case)
        local side = scope:match("^friendly") and "friendly" or "enemy"
        owner = owner or scope
        for _, button in ipairs({ "LeftButton", "RightButton" }) do
            assert(P.NameplatesWorkspace.Open(scope))
            assert(status[owner].select("basic", "raid"))
            assert(P.NameplatesWorkspace.Open(scope))
            preview:FocusStatusOffset(nil, element, sample)
            local handle = assert(preview.kit.entries[side .. "." .. element], element).region
            assert(handle:IsVisible(), "status fixture did not show " .. scope .. "." .. element)
            handle:Click(button)
            assert(P.NameplatesWorkspace.Kind() == owner and status[owner].currentStatus().key == item,
                button .. " did not open " .. owner .. " status " .. item .. " from " .. scope)
        end
    end
    assert(P.NameplatesWorkspace.Open("neutral"))
    assert(status.neutral.select("basic", "raid"))
    preview:FocusStatusOffset(nil, "quest", "quest")
    assert(preview.kit.entries["enemy.quest"].region):Click("LeftButton")
    assert(P.NameplatesWorkspace.Kind() == "neutral" and status.neutral.currentStatus().key == "quest",
        "clicking the Neutral sample did not open Neutral's quest settings")
    assert(P.SetMany("nameplates", { enemyIdentityIcons = 1, enemyTargetHideFriendly = true }))
end

do
    local ui = assert(P.NameplatesWorkspace.ui)
    local page = M.cache.suite_nameplates
    local function Header(id)
        return assert(P.HM.GetSectionEntry(assert(page.sections["suite_nameplates_" .. id])))
    end
    local function Order(scope, ids)
        assert(P.NameplatesWorkspace.Open(scope))
        mw:RunTimers(1000)
        assert(#ui.builder.layoutEntries == #ids, "wrong accordion count for " .. scope)
        for i, id in ipairs(ids) do
            assert(ui.builder.layoutEntries[i] == Header(id), "wrong accordion order for " .. scope .. " at " .. id)
        end
    end
    local chip
    for _, button in ipairs(preview.layerButtons) do
        if button.layerKey == "status" then chip = button break end
    end
    assert(chip and not preview.statusButton, "Status icons must be a preview layer")
    assert(P.NameplatesWorkspace.Open("enemy"))
    local priorCondition, priorWidth = P.Get("nameplates", "enemyHideInCombat"), P.Get("nameplates", "enemyHealthWidthDelta")
    local look = P.Get("nameplates", "look")
    assert(P.SetMany("nameplates", { enemyHideInCombat = true, enemyHealthWidthDelta = 22, look = look }))
    assert(page.sections.suite_nameplates_enemyVisibility._msufSuiteSectionReset())
    assert(not P.Get("nameplates", "enemyHideInCombat") and P.Get("nameplates", "enemyHealthWidthDelta") == 22,
        "Load Conditions reset did not stay within its section")
    assert(P.SetMany("nameplates", { enemyHideInCombat = priorCondition, enemyHealthWidthDelta = priorWidth, look = look }))
    assert(not page.sections.suite_nameplates_general and not page.sections.suite_nameplates_distance)
    local record = assert(records["msufsuite.nameplates.plateFadeDistance"])
    assert(record.exactTarget.sectionId == "suite_nameplates_enemyRange", "distance search missed Range Check")
    assert(P.OpenNameplateSetting("plateFadeDistance"))
    assert(controlsBySection.suite_nameplates_enemyRange.plateFadeDistance:IsVisible())
    Header("enemyRange").SetOpenImmediate(false)
    for _, scope in ipairs({ "enemy", "neutral", "friendly", "friendlyNpc" }) do
        P.NameplatesWorkspace.Open(scope)
        P.EditNameplatesPreview("anchor", "Health")
        local id = scope .. "Markers"
        local body = page.sections["suite_nameplates_" .. id]
        local entry = Header(id)
        entry.SetOpenImmediate(false)
        local before = preview:LayerOn("status")
        chip:Click()
        assert(preview:LayerOn("status") ~= before and not entry.open,
            "status chip click changed navigation instead of only toggling the layer")
        chip:Click()
        chip:Click("RightButton")
        mw:RunTimers(1000)
        assert(entry.open and body:IsVisible(), "status layer did not open " .. scope)
        assert(P.NameplatesWorkspace.Kind() == scope, "status layer changed the selected scope")
        assert(not preview.statusSample and not preview.allStatusSamples, "status layer changed preview mode")
    end
    Open({ "friendlyStatusLeaderSize" })
    assert(P.NameplatesWorkspace.Kind() == "friendly", "player status search did not leave Friendly NPC")
    local leader = assert(controlsBySection.suite_nameplates_friendlyMarkers.friendlyStatusLeaderSize)
    assert(leader:IsVisible())
    P.NameplatesWorkspace.Open("friendlyNpc")
    assert(not leader:IsVisible(), "NPC tab kept the previous player-only status settings")
    assert(not page.sections.suite_nameplates_enemyAnchor and not page.sections.suite_nameplates_friendlyAnchor,
        "Nameplates still registers a standalone Anchor accordion")
    local friendlyDisplay = P.Get("nameplates", "friendlyNamesOnly")
    P.Set("nameplates", "friendlyNamesOnly", 4)
    for _, side in ipairs({ "enemy", "friendly" }) do
        local rule = P.catalog.nameplates.rules[side .. "HealthOffsetX"]
        local section, scope, exact = P.NameplateSearchTarget(rule)
        assert(section == "suite_nameplates_preview_" .. side and scope == side and exact == false,
            "health position search did not move to the shared preview")
        local resolve = assert(P.HM.GetMissingSectionResolver(page))
        assert(resolve(section) == preview.body and P.NameplatesWorkspace.Side() == side,
            "health position search did not open the matching plate preview")
        P.NameplatesWorkspace.Open(side)
        P.EditNameplatesPreview("anchor", "Health")
        local handle = preview.body._selectedHandle
        assert(handle and handle.keyX == side .. "HealthOffsetX" and handle.keyY == side .. "HealthOffsetY",
            side .. " health position is no longer editable in the shared preview")
    end
    P.Set("nameplates", "friendlyNamesOnly", friendlyDisplay)
    Order("friendly", { "friendlyBasics", "plateHealthDisplay", "friendlyText", "platePersonalDisplay",
        "friendlyCast", "auraWorkspace", "auraSpellEmphasis", "friendlyMarkers", "platePvpMarkers", "friendlyStyle",
        "friendlyRange", "friendlyOpacity" })
    Order("friendlyNpc", { "friendlyNpcBasics", "plateHealthDisplay", "friendlyText", "friendlyCast",
        "auraWorkspace", "auraSpellEmphasis", "friendlyNpcMarkers", "plateNpcMarkers", "friendlyNpcStyle",
        "friendlyNpcRange", "friendlyNpcOpacity" })
    Order("neutral", { "neutralBasics", "plateHealthDisplay", "enemyText", "castbar", "enemyPower",
        "auraWorkspace", "auraSpellEmphasis", "neutralMarkers", "plateNpcMarkers", "neutralStyle", "neutralRange", "neutralOpacity" })
    Order("enemy", { "enemyBasics", "plateHealthDisplay", "enemyText", "castbar", "enemyPower",
        "classResources", "auraWorkspace", "auraSpellEmphasis", "enemyMarkers", "platePvpMarkers", "plateNpcMarkers",
        "enemyStyle", "enemyVisibility", "enemyRange", "enemyOpacity" })
    Open({ "nameplatePersonalStyle" })
    assert(P.NameplatesWorkspace.Kind() == "friendly", "personal display search missed the Friendly Players workspace")
    for _, key in ipairs({ "enemyNameMaxWidth", "friendlyNameMaxWidth", "nameplateNpcLastWord", "nameplateFirstNameOnly" }) do
        assert(not records["msufsuite.nameplates." .. key], "retired name setting appeared in search: " .. key)
    end
    assert(not page.sections.suite_nameplates_enemy and not page.sections.suite_nameplates_friendly,
        "Nameplates still registers a Texture Layer accordion")
    assert(not records["msufsuite.nameplates.enemyFillTexture"], "retired fill texture appeared in search")
    local function Choice(strip, value)
        for i, option in ipairs(strip.values) do
            if option.value == value then return strip.buttons[i] end
        end
    end
    for _, scope in ipairs({ "enemy", "neutral", "friendly", "friendlyNpc" }) do
        P.NameplatesWorkspace.Open(scope)
        local basicId, styleId = scope .. "Basics", scope .. "Style"
        local basics, style = Header(basicId), Header(styleId)
        basics.SetOpenImmediate(true)
        P.EnsureSectionContent(page.sections["suite_nameplates_" .. basicId])
        style.SetOpenImmediate(true)
        P.EnsureSectionContent(page.sections["suite_nameplates_" .. styleId])
        mw:RunTimers(1000)
        local basicTabs, styleTabs = assert(layoutTabs[basicId]), assert(layoutTabs[styleId])
        assert(not Choice(basicTabs, "appearance") and not Choice(basicTabs, "style") and not Choice(basicTabs, "colors"))
        assert(not Choice(styleTabs, "extras"), "unfiltered extras still appear in " .. styleId)
        assert(not Choice(styleTabs, "style"), "global style still repeated in " .. styleId)
        assert(Choice(styleTabs, "frame")):Click()
        assert(panels[styleId .. ":frame"]:IsVisible())
        local paletteTab = (scope == "enemy" or scope == "neutral") and "colors" or "frame"
        assert(Choice(styleTabs, paletteTab)):Click()
        if paletteTab == "frame" then assert(not Choice(styleTabs, "colors"), "empty Colors tab in " .. styleId) end
        basics.SetOpenImmediate(false)
        assert(styleTabs:GetValue() == paletteTab and panels[styleId .. ":" .. paletteTab]:IsVisible(),
            "closing Basics affected the Style accordion")
        style.SetOpenImmediate(false)
        assert(not styleTabs:IsVisible())
        local rangeId = "suite_nameplates_" .. scope .. "Range"
        local range = assert(controlsBySection[rangeId])
        assert(not range[scope .. "RangeEnabled"], "Range Check repeats its section switch")
        assert(records["msufsuite.nameplates." .. scope .. "RangeAuto"].exactTarget.sectionId == rangeId,
            "range search did not open " .. scope)
        for _, kind in ipairs({ "enemy", "neutral", "friendly", "friendlyNpc" }) do
            assert((range[kind .. "RangeAuto"] ~= nil) == (kind == scope), "range toggle leaked into " .. scope)
        end
    end
    local function Colors(id, tab)
        tab = tab or "colors"
        for _, spec in ipairs(P.NameplateSections) do
            if spec.key == id then assert(spec.select(tab)) break end
        end
        local panel = assert(panels[id .. ":" .. tab])
        for card in pairs(shortcuts) do
            assert(card ~= panel and card:GetParent() ~= panel, "a second Colors entry appeared in " .. id)
        end
        local sectionId = "suite_nameplates_" .. id
        local meta = P.Meta("suite_nameplates", "nameplates", id .. ".colors", "action", sectionId)
        local action = assert(M.RuntimeControlCatalog.Get(meta.controlId), "missing direct Colors action for " .. id)
        local opened, Open, Picker = {}, P.W.OpenContextColors, M.Widgets.OpenColorContextPicker
        local pickerOpened
        M.Widgets.OpenColorContextPicker = function() pickerOpened = true end
        P.W.OpenContextColors = function(anchor, opts, targets)
            for _, target in ipairs(targets) do
                local key = target.settingKey
                if key then opened[key:match("^msufsuite%.nameplates%.(.+)$") or key] = true end
            end
            return Open(anchor, opts, targets)
        end
        action.widget:Click()
        P.W.OpenContextColors, M.Widgets.OpenColorContextPicker = Open, Picker
        assert(next(opened) and pickerOpened, "the direct Colors action did not open the palette for " .. id)
        return opened
    end
    local enemyColors, neutralColors = Colors("enemyStyle"), Colors("neutralStyle")
    assert(not enemyColors.enemyPowerTextColor and not enemyColors.focusReminderColor,
        "Style has a second editor for a text color")
    assert(enemyColors.enemyBorderColor and neutralColors.enemyBorderColor and enemyColors.enemyBossColor
        and enemyColors.enemyTargetColor and enemyColors.enemyCastIconBorderColor, "enemy style palette is incomplete")
    assert(not page.sections.suite_nameplates_auraColors, "DoT colors still have a standalone accordion")
    for _, scope in ipairs({ "friendly", "friendlyNpc" }) do
        local colors = Colors(scope .. "Style", "frame")
        assert(colors.friendlyBackdropColor)
        for _, key in ipairs({ "questNeutralColor", "questHostileColor", "castHealthInterruptible", "castHealthLocked",
            "executePulseColor" }) do
            assert(enemyColors[key] and not colors[key], "Enemy color leaked into " .. scope .. ": " .. key)
        end
    end
    do
        local config = P.S.Config("nameplates")
        for _, scope in ipairs({ "enemy", "neutral", "friendly", "friendlyNpc" }) do
            local side = scope:match("^friendly") and "friendly" or "enemy"
            local key = scope .. "CenterName"
            local rule = assert(P.catalog.nameplates.rules[key])
            local section, targetScope = P.NameplateSearchTarget(rule)
            assert(rule.default == false and section == "suite_nameplates_" .. side .. "Text" and targetScope == scope,
                "centering search is missing from the matching Text accordion")
            P.NameplatesWorkspace.Open(scope == side and (side == "enemy" and "neutral" or "friendlyNpc") or side)
            Open({ key, side .. "Text:name" })
            assert(P.NameplatesWorkspace.Kind() == scope, "centering search opened the wrong nameplate type")
            assert(not controlsBySection["suite_nameplates_" .. scope .. "Basics"][key], "centering remained in Basics")
            if scope ~= "friendly" then
                local colorKey = scope .. "PlateNameTypeColor"
                assert(not controlsBySection["suite_nameplates_" .. side .. "Text"][colorKey],
                    "NPC name color still has a Text control")
                assert(not controlsBySection["suite_nameplates_" .. scope .. "Basics"][colorKey],
                    "NPC name color remained in Basics")
                local titleKey = scope .. "ExtraTextTitle"
                Open({ titleKey, side .. "Text:name" })
                assert(P.NameplatesWorkspace.Kind() == scope, "NPC title search opened the wrong nameplate type")
            end
        end
        for _, case in ipairs({ { "enemy", "neutral", "enemyPlateNameClassColor" },
            { "friendly", "friendlyNpc", "friendlyNameClassColor" } }) do
            local scope, alternative, key = unpack(case)
            assert(P.NameplatesWorkspace.Open(alternative))
            assert(not controlsBySection["suite_nameplates_" .. scope .. "Text"][key], "class color remained in Text")
            assert(not controlsBySection["suite_nameplates_" .. scope .. "Basics"][key], "class color remained in Basics")
            local center = alternative .. "CenterName"
            local previous = config[key]
            local custom = scope == "enemy" and true or 3
            config[key], config[center] = custom, true
            local body = assert(page.sections["suite_nameplates_" .. scope .. "Text"])
            assert(body._msufSuiteSectionReset() and config[center] == false and config[key] == custom,
                "NPC Text reset also changed the hidden player name controls")
            config[key] = previous
        end
        local originalCenter = config.friendlyNpcCenterName
        config.friendlyNpcCenterName = true
        assert(P.NameplatesWorkspace.CopyValues("friendlyNpc", "neutral", { style = true }).neutralCenterName,
            "Copy To lost the name centering preference")
        local look, display, offset = config.look, config.friendlyNPCs, config.friendlyNameOffsetX
        config.look, config.friendlyNPCs, config.friendlyNameOffsetX = 3, 5, -42
        preview:ShowSample("friendly", "friendlyNpc")
        preview:Paint()
        local name = assert(preview.kit.entries["friendly.Name"]).region
        local point, owner, relative, x = name:GetPoint(1)
        assert(point == "BOTTOM" and owner == preview.sampleCells.friendly and relative == "CENTER" and x == 0,
            "Name only preview did not center the text independently of its horizontal offset")
        local oldTitle, oldFade, oldKeep = config.friendlyNpcExtraTextTitle, config.friendlyNpcFadeHealth, config.friendlyNpcFadeKeepText
        config.friendlyNpcExtraTextTitle, config.friendlyNpcFadeHealth, config.friendlyNpcFadeKeepText = true, 40, false
        preview:Paint()
        local title = assert(preview.kit.entries["friendlyNpc.ExtraTextTitle"]).region
        local where, textOwner, from = title:GetPoint(1)
        assert(title:IsVisible() and where == "TOP" and textOwner == name and from == "BOTTOM",
            "name-only NPC title preview is not below the name")
        assert(title:GetAlpha() == .4, "NPC title stayed opaque while the name faded")
        config.friendlyNpcFadeKeepText = true
        preview:Paint()
        assert(title:GetAlpha() == 1, "Keep Text did not restore the NPC title in the preview")
        config.friendlyNpcExtraTextTitle, config.friendlyNpcFadeHealth, config.friendlyNpcFadeKeepText = oldTitle, oldFade, oldKeep
        config.look, config.friendlyNPCs, config.friendlyNameOffsetX = look, display, offset
        config.friendlyNpcCenterName = originalCenter
        local enemyTitle, enemyPlayer = config.enemyExtraTextTitle, preview.enemyPlayer
        config.enemyExtraTextTitle = true
        assert(P.NameplatesWorkspace.Open("enemy"))
        preview:Edit("anchor", "Health")
        preview.enemyPlayer = false
        preview:Paint()
        local enemySubtitle = assert(preview.kit.entries["enemy.ExtraTextTitle"]).region
        assert(enemySubtitle:IsVisible(), "enemy NPC preview lost its title")
        preview.enemyPlayer = true
        preview:Paint()
        assert(not enemySubtitle:IsVisible(), "enemy player preview showed an NPC title")
        config.enemyExtraTextTitle, preview.enemyPlayer = enemyTitle, enemyPlayer
        local neutralDisplay = P.RuleRow("suite_nameplates", "nameplates", P.catalog.nameplates.rules.neutralPlateNameOnly)
        local nameOnly, mode = config.neutralPlateNameOnly, config.neutralNameOnlyMode
        local choices = type(neutralDisplay.values) == "function" and neutralDisplay.values() or neutralDisplay.values
        assert(#choices == 4, "Neutral Display did not expose both attackability choices")
        for _, choice in ipairs({ 3, 4, 2, 1 }) do
            assert(neutralDisplay.set(choice) and neutralDisplay.get() == choice, "Neutral Display did not save choice " .. choice)
            assert(config.neutralNameOnlyMode == math.max(1, choice - 1), "Neutral Display left an obsolete attackability condition")
        end
        config.neutralPlateNameOnly, config.neutralNameOnlyMode = nameOnly, mode
        for _, scopes in ipairs({ { "enemy", "neutral" }, { "neutral", "enemy" } }) do
            local source, target = unpack(scopes)
            local sourceKey, targetKey = source .. "PlateNameOnly", target .. "PlateNameOnly"
            local original = config[sourceKey]
            local row = P.RuleRow("suite_nameplates", "nameplates", P.catalog.nameplates.rules[sourceKey])
            assert(row.kind == "dropdown" and row.label == P.Tr("Display"), source .. " is missing the Display dropdown")
            for _, nameOnly in ipairs({ true, false }) do
                config[sourceKey] = nameOnly
                local values = P.NameplatesWorkspace.CopyValues(source, target, { style = true })
                assert(values[targetKey] == nameOnly, "Copy To lost the display mode for " .. target)
            end
            config[sourceKey] = original
        end
        local saved = { friendlyNpcRangeAlpha = config.friendlyNpcRangeAlpha, friendlyNpcContextEnabled = config.friendlyNpcContextEnabled,
            neutralRangeAlpha = config.neutralRangeAlpha, neutralContextEnabled = config.neutralContextEnabled, look = config.look }
        config.friendlyNpcRangeAlpha, config.friendlyNpcContextEnabled = 63, true
        local values = P.NameplatesWorkspace.CopyValues("friendlyNpc", "neutral", { range = true })
        assert(values.neutralRangeAlpha == 63 and values.neutralContextEnabled == nil and values.enemyRangeAlpha == nil,
            "copying Friendly NPC range changed a different category or scope")
        values = P.NameplatesWorkspace.CopyValues("friendlyNpc", "neutral", { visibility = true })
        assert(values.neutralContextEnabled and values.enemyContextEnabled == nil and values.neutralRangeAlpha == nil,
            "copying Friendly NPC context changed a different category or scope")
        values = P.NameplatesWorkspace.CopyValues("friendlyNpc", "neutral", { style = true })
        assert(values.neutralPlateNameTypeColor == P.Get("nameplates", "friendlyNpcPlateNameTypeColor"),
            "copying Friendly NPC style missed the scoped name color setting")
        assert(values.neutralTargetPatternTexture == P.Get("nameplates", "friendlyNpcTargetPatternTexture"),
            "copying Friendly NPC style missed the scoped target pattern")
        for key in pairs(values) do
            local rule = P.catalog.nameplates.rules[key]
            assert(key == "neutralPlateNameTypeColor" or key == "neutralCenterName" or rule.section == "plateHighlightPatterns",
                "copying Friendly NPC style included a shared setting")
        end
        assert(P.NameplatesWorkspace.Open("friendlyNpc"))
        ui.copy:Click()
        local popup = assert(ui.copyPopup.GetPopup())
        assert(popup:IsShown())
        popup._targetBtns.neutral:Click()
        assert(popup._checks[2]:IsEnabled(), "Copy To did not offer the scoped NPC style setting")
        for index, check in ipairs(popup._checks) do
            if check:IsEnabled() then
                check:SetChecked(index == 9)
                check:Click()
            end
        end
        popup._runBtn:Click()
        assert(not popup:IsShown() and config.neutralRangeAlpha == 63 and config.neutralContextEnabled == saved.neutralContextEnabled,
            "Copy Selected did not restrict the write to the chosen destination and category")
        for key, value in pairs(saved) do config[key] = value end
    end
    local color = assert(records["msufsuite.nameplates.enemyTargetColor"])
    local opened, focused, exact = (M.Search._RoutingAPI or api).OpenSearchTarget(color.key,
        color.label, color.label, color.anchor, color.route, color.exactTarget)
    assert(opened and focused and exact and panels["enemyStyle:colors"]:IsVisible()
        and layoutTabs.enemyStyle:GetValue() == "colors", "color search missed Style > Colors")
    local basics, power = Header("enemyBasics"), Header("enemyPower")
    assert(basics.featureSwitch and power.featureSwitch and Header("castbar").featureSwitch
        and not Header("auraWorkspace").featureSwitch, "Aura visibility must be controlled by the individual rows")
    assert(basics._msuf2UXSummary and basics._msuf2UXSummary:GetText():find("×", 1, true),
        "Basics has no dimension summary")
    local enemySkin, neutralSkin = P.Get("nameplates", "enemySkinEnabled"), P.Get("nameplates", "neutralSkinEnabled")
    basics.featureSwitch:GetScript("OnClick")(basics.featureSwitch, "LeftButton")
    assert(P.Get("nameplates", "enemySkinEnabled") == not enemySkin
        and P.Get("nameplates", "neutralSkinEnabled") == neutralSkin, "Basics Enable changed a different type")
    assert(not records["msufsuite.nameplates.plateEnemies"] and not records["msufsuite.nameplates.enabled"],
        "a removed nameplate toggle is still searchable")
    assert(P.Set("nameplates", "enemySkinEnabled", enemySkin))
    local previous = P.Get("nameplates", "enemyPowerEnabled")
    power.SetOpenImmediate(false)
    local powerSwitch = power.featureSwitch
    local configPower = P.S.Config("nameplates")
    configPower.enemyPowerEnabled = not previous
    MenuWorld.FireScript(powerSwitch, "OnShow")
    assert(powerSwitch:GetChecked() == not previous, "Resource Bar header displayed a stale checked state")
    configPower.enemyPowerEnabled = previous
    MenuWorld.FireScript(powerSwitch, "OnShow")
    power.featureSwitch:GetScript("OnClick")(power.featureSwitch, "LeftButton")
    mw:RunTimers(1000)
    assert(P.Get("nameplates", "enemyPowerEnabled") == not previous and not power.open,
        "the Resource Bar switch did not change its setting while closed")
    assert(P.Set("nameplates", "enemyPowerEnabled", previous))

    local config = P.S.Config("nameplates")
    local function Row(key) return assert(P.RuleRow("suite_nameplates", "nameplates", P.catalog.nameplates.rules[key])) end
    local savedAura = {}
    for _, key in ipairs({ "auraDisplayEnabled", "auraEnemyBuffScale",
        "enemyNpcAuraMode", "enemyNpcBuffs", "enemyNpcDebuffs", "enemyNpcControl",
        "enemyPlayerAuraMode", "enemyPlayerBuffs", "enemyPlayerDebuffs", "enemyPlayerControl" }) do savedAura[key] = config[key] end
    assert(P.SetMany("nameplates", { auraDisplayEnabled = true, enemyNpcAuraMode = 1 }))
    local debuffs, control = Row("enemyNpcDebuffs").get(), Row("enemyNpcControl").get()
    Row("enemyPlayerBuffs").set(false)
    assert(preview.enemyPlayer, "editing the enemy player did not select its sample in the common preview")
    Row("enemyNpcBuffs").set(false)
    assert(not preview.enemyPlayer, "editing the enemy NPC did not select its sample in the common preview")
    assert(config.enemyNpcAuraMode == 2 and config.enemyNpcBuffs == false
        and config.enemyNpcDebuffs == debuffs and config.enemyNpcControl == control
        and not config.auraEnemyBuffUseLayout, "Buffs switch modified another row or opted into a new layout")
    local sizeRule = P.catalog.nameplates.rules.auraEnemyBuffScale
    assert(P.RuleEnabled("nameplates", sizeRule), "native size required a replacement layout")
    Row("auraEnemyBuffScale").set(135)
    Row("auraDisplayEnabled").set(false)
    assert(config.auraEnemyBuffScale == 135 and not config.auraDisplayEnabled,
        "custom tracked rows changed the Buffs layout")
    assert(P.SetMany("nameplates", savedAura))

    local oldText = config.neutralExtraTextResource
    assert(P.Set("nameplates", "neutralExtraTextResource", true))
    local paintExtra, label
    paintExtra = P.NameplatesPreviewDecor.ExtraText
    P.NameplatesPreviewDecor.ExtraText = function(editor, sample, metrics)
        paintExtra(editor, sample, metrics)
        if editor.scope == "neutral" and sample.prefix == "enemy" then
            local text = sample.extraText and sample.extraText[8]
            label = text and text.label
        end
    end
    assert(P.NameplatesWorkspace.Open("neutral"))
    preview.layers.status = true
    preview:Paint()
    assert(label and label:IsVisible() and label:GetText() == "70 / 100", "Neutral's extra text is missing from the shared preview")
    assert(P.OpenNameplateStatusSection("enemy"))
    local choices = assert(indicatorChoices.neutral)
    local count = 0
    for _, choice in ipairs(choices.values) do
        assert(not choice.value:find("ExtraText%d") and choice.value ~= "StatusThreat")
        if choice.value:find("^neutralExtraText") then count = count + 1 end
    end
    assert(count == 9, "each named text is directly selectable")
    choices.set("neutralExtraTextResource")
    local previewActions = "suite_nameplates_neutralMarkers.basic."
    assert(statusActions[previewActions .. "Preview current"]):Click()
    assert(preview.statusSample == "ExtraTextResource" and label:IsVisible(), "Preview current hid resource text")
    local handle = assert(preview.body._selectedHandle, "Preview current did not select resource text")
    assert(handle.keyX == "neutralExtraTextResourceX" and handle.keyY == "neutralExtraTextResourceY")
    local offset = assert(previewOffsets.neutralExtraTextResourceY)
    assert(M.SelectPage("home"))
    local opened, focused, exact = (M.Search._RoutingAPI or api).OpenSearchTarget(offset.key, offset.label,
        offset.anchorFallback or offset.label, offset.anchor, offset.route, offset.exactTarget)
    mw:RunTimers(1000)
    assert(opened and focused and exact and preview.body._selectedHandle == handle, "resource text search missed its preview handle")
    local x, y = config[handle.keyX], config[handle.keyY]
    assert(preview.kit:Nudge(3, -2))
    assert(config[handle.keyX] == x + 3 and config[handle.keyY] == y - 2, "preview did not move Neutral resource text")
    assert(P.SetMany("nameplates", { [handle.keyX] = x, [handle.keyY] = y }))
    handle:Click("RightButton")
    assert(P.NameplatesWorkspace.Kind() == "neutral", "preview settings changed the selected plate type")
    assert(controlsBySection.suite_nameplates_neutralMarkers.neutralExtraTextResourceSize:IsVisible(),
        "right-clicking the text did not open its settings")
    assert(statusActions[previewActions .. "Show all"]):Click()
    assert(preview.allStatusSamples and label:IsVisible(), "Show all hid the configured extra text")
    assert(P.NameplatesWorkspace.Open("enemy"))
    assert(not label:IsVisible(), "Neutral's extra text leaked into Enemy")
    for _, key in ipairs({ "enemyRaidIconOffsetX", "enemyStatusDNDOffsetY", "neutralExtraTextResourceX", "enemySoftTargetOffsetX",
        "enemyClassificationOffsetY", "enemyFocusMarkerX", "enemyIdentityIconX" }) do
        assert(not widgets[key], "status panel still built a position slider for " .. key)
        local section = P.NameplateSearchTarget(P.catalog.nameplates.rules[key])
        assert(section == "suite_nameplates_status_offset_" .. key)
    end
    P.NameplatesPreviewDecor.ExtraText = paintExtra
    assert(P.Set("nameplates", "neutralExtraTextResource", oldText))

    local oldColor, newColor = config.enemyBorderColor, "17b7cd"
    local oldPattern, oldAlpha = config.neutralTargetPatternAlpha, config.enemyTargetPatternAlpha
    assert(P.SetMany("nameplates", { enemyBorderColor = newColor, neutralTargetPatternAlpha = 73, enemyTargetPatternAlpha = 61 }))
    assert(page.sections.suite_nameplates_neutralStyle._msufSuiteSectionReset())
    assert(config.neutralTargetPatternAlpha == P.catalog.nameplates.rules.neutralTargetPatternAlpha.default,
        "Neutral Style did not reset its highlight pattern")
    assert(config.enemyBorderColor == newColor and config.enemyTargetPatternAlpha == 61,
        "Neutral Style reset an Enemy setting")
    assert(P.SetMany("nameplates", { enemyBorderColor = oldColor, neutralTargetPatternAlpha = oldPattern, enemyTargetPatternAlpha = oldAlpha }))
    local savedOffsets = {}
    local offsets = { enemyHealthTextOffsetX = 12, enemyHealthOffsetX = 27, enemyCastIconOffsetX = 33,
        friendlyCastIconOffsetX = 41, enemyBuffsOffsetX = 51, enemyCastEnabled = 3,
        interruptFeedbackEnabled = true, interruptFeedbackDuration = 3 }
    for key in pairs(offsets) do savedOffsets[key] = config[key] end
    assert(P.SetMany("nameplates", offsets))
    local function Reset(section)
        local body = assert(page.sections["suite_nameplates_" .. section])
        assert(body._msufSuiteSectionReset())
    end
    Reset("enemyText")
    assert(config.enemyHealthTextOffsetX ~= 12 and config.enemyHealthOffsetX == 27
        and config.enemyCastIconOffsetX == 33 and config.enemyBuffsOffsetX == 51, "Text reset changed another accordion")
    Reset("friendlyCast")
    assert(config.friendlyCastIconOffsetX ~= 41 and config.enemyCastIconOffsetX == 33
        and config.enemyCastEnabled == 3 and config.interruptFeedbackEnabled and config.interruptFeedbackDuration == 3,
        "Friendly Castbar reset changed shared settings or the Enemy icon")
    assert(P.SetMany("nameplates", savedOffsets))

    local previousSize, previousOverride = config.neutralNpcHealthWidthDelta, config.neutralNpcSizeOverride
    local parentSize = config.enemyHealthWidthDelta
    assert(P.SetMany("nameplates", { neutralNpcSizeOverride = true, neutralNpcHealthWidthDelta = 19 }))
    assert(P.NameplatesWorkspace.Open("neutral"))
    preview:Edit("anchor")
    local health = assert(preview.kit.entries["enemy.Health"]).region
    assert(P.NameplatesSize.Keys(health) == "neutralNpcHealthWidthDelta", "Neutral preview selected Enemy dimensions")
    local plus = preview.sizeFields[1].plus
    plus:GetScript("OnClick")(plus, "LeftButton")
    assert(config.neutralNpcHealthWidthDelta == 20 and config.enemyHealthWidthDelta == parentSize,
        "Neutral preview edited the Enemy plate size")
    assert(P.SetMany("nameplates", { neutralNpcSizeOverride = previousOverride, neutralNpcHealthWidthDelta = previousSize }))

    assert(P.NameplatesWorkspace.Open("enemy"))
    basics.SetOpenImmediate(false)
    assert(P.NameplatesWorkspace.Open("neutral") and P.NameplatesWorkspace.Open("enemy"))
    mw:RunTimers(1000)
    assert(not basics.open, "switching type reopened a deliberately closed Basics")
    basics.SetOpenImmediate(true)
end

-- Text handles open sizing, while the element eye opens visibility settings.
do
    preview:ShowSample("friendly")
    preview:Edit("cast")
    for _, case in ipairs({ { "CastText", "castText", "friendlyCastSize", "friendlyCastTextEnabled" },
        { "CastTime", "castTime", "friendlyCastTimeSize", "friendlyCastTimeEnabled" } }) do
        local element, layer, key, layerKey = unpack(case)
        local handle = assert(preview.kit.entries["friendly." .. element]).region
        local open = P.OpenNameplateSetting
        local target
        P.OpenNameplateSetting = function(setting)
            target = setting
            return open(setting)
        end
        handle:GetScript("OnClick")(handle, "RightButton")
        assert(target == key, "friendly " .. element .. " opened " .. tostring(target) .. " on right-click")
        mw:RunTimers(1000)
        assert(widgets[key] and widgets[key]:IsVisible(), "preview target is hidden: " .. key)
        target = nil
        handle:GetScript("OnClick")(handle, "LeftButton")
        assert(target == key, "friendly " .. element .. " opened " .. tostring(target) .. " on click")
        target = nil
        local chip
        for _, button in ipairs(preview.layerButtons) do
            if button.layerKey == layer then
                chip = button
                break
            end
        end
        assert(chip, "missing cast layer: " .. layer)
        chip:GetScript("OnClick")(chip, "RightButton")
        assert(target == layerKey, "friendly cast layer opened " .. tostring(target))
        P.OpenNameplateSetting = open
    end
end

do
    local config = P.S.Config("nameplates")
    preview:ShowSample("enemy")
    for _, key in ipairs({ "enemyNameOffsetX", "enemyHealthTextOffsetY", "enemyPowerOffsetX", "auraTimeY" }) do
        local rule = assert(P.catalog.nameplates.rules[key])
        assert(not P.RuleRow("suite_nameplates", "nameplates", rule), key .. " can still build a position control")
    end
    local function Move(x, y, ...)
        local beforeX, beforeY = config[x], config[y]
        local selected = assert(SelectPreview(...), x .. " has no preview handle")
        assert(selected.keyX == x and selected.keyY == y, x .. " selected the wrong coordinates")
        assert(preview.kit:Nudge(1, 1), x .. " cannot move in the preview")
        assert(config[x] == beforeX + 1 and config[y] == beforeY + 1, x .. " did not save the position")
        assert(P.SetMany("nameplates", { [x] = beforeX, [y] = beforeY }))
        assert(not widgets[x] and not widgets[y], x .. " still has position controls in its accordion")
    end
    for _, entry in ipairs({ { "Cast", "Castbar" }, { "CastIcon", "Blizzard spell icon" }, { "CastText", "Spell name" },
        { "CastTime", "Cast time" }, { "CastTarget", "Spell target" }, { "CastShield", "Blizzard interrupt shield" } }) do
        local prefix = "enemy" .. entry[1] .. "Offset"
        Move(prefix .. "X", prefix .. "Y", "Castbar", entry[2])
    end
    Move("enemyNameOffsetX", "enemyNameOffsetY", "Text", "Name")
    Move("enemyHealthTextOffsetX", "enemyHealthTextOffsetY", "Text", "HP Text")
    Move("enemyPowerTextOffsetX", "enemyPowerTextOffsetY", "Text", "Power Text")
    Move("enemyTargetOffsetX", "enemyTargetOffsetY", "Status icons", "Target arrows")
    Move("enemyTargetMirrorOffsetX", "enemyTargetMirrorOffsetY", "Status icons", "Right target arrow")
    Move("auraEnemyCustom1TimeX", "auraEnemyCustom1TimeY", "Auras", "Custom 1", "Cooldown Text")
    Move("auraTimeX", "auraTimeY", "Auras", "Aura countdown position")
    Move("auraEnemyCustom1StackX", "auraEnemyCustom1StackY", "Auras", "Custom 1", "Stack Count")
    Move("auraStackX", "auraStackY", "Auras", "Aura stack position")
end

do
    preview:ShowSample("enemy")
    for _, case in ipairs({ { "Name", "enemyNameSize" }, { "HealthText", "enemyHealthTextSize" } }) do
        local element, key = unpack(case)
        local handle = assert(preview.kit.entries["enemy." .. element]).region
        handle:GetScript("OnClick")(handle, "LeftButton")
        mw:RunTimers(1000)
        assert(widgets[key] and widgets[key]:IsVisible(), "text preview missed size control: " .. key)
    end
end

do
    local popup
    local CreatePopup = M.CreateMenuPopupPanel
    M.CreateMenuPopupPanel = function(...)
        popup = CreatePopup(...)
        return popup
    end
    for _, scope in ipairs({ "enemy", "friendly", "neutral", "friendlyNpc" }) do
        assert(P.NameplatesWorkspace.Open(scope))
        local sectionId = "suite_nameplates_" .. scope .. "Style"
        local body = assert(M.cache.suite_nameplates.sections[sectionId])
        P.HM.GetSectionEntry(body).SetOpenImmediate(true)
        for _, spec in ipairs(P.NameplateSections) do
            if spec.key == scope .. "Style" then
                assert(spec.select("outline"))
                local controls = controlsBySection[sectionId]
                assert(controls[scope .. "StyleOutlineMode"]:IsVisible())
                assert(controls[scope .. "StyleBorderSize"]._msuf2OutlineGear,
                    "no entry point to the outline overview in " .. scope)
                for key, widget in pairs(controls) do
                    local rule = P.catalog.nameplates.rules[key]
                    if rule and rule.section == scope .. "StyleOutline" and key ~= scope .. "StyleBorderSize" then
                        assert(not widget._msuf2OutlineGear, "duplicate outline gear on " .. key)
                    end
                end
                assert(spec.select("textures"))
                assert(controlsBySection[sectionId][scope .. "StyleNativeHealthFillTexture"]:IsVisible())
            end
        end
    end
    local outlineRecords = {}
    for _, record in pairs(Ready()) do
        local setting = record.exactTarget and record.exactTarget.settingKey
        if setting then outlineRecords[setting] = record end
    end
    local function CheckSetting(setting, id)
        local record = assert(outlineRecords[setting], "the border setting has no search route: " .. setting)
        local routed, revealed, exact = (M.Search._RoutingAPI or api).OpenSearchTarget(record.key,
            record.label, record.label, record.anchor, record.route, record.exactTarget)
        mw:RunTimers(1000)
        assert(routed and revealed and exact, "the border setting did not open: " .. setting)
        local _, widget = M.RuntimeControlCatalog.FindBySettingKey(setting, M.activeKey)
        local gear = assert(widget and widget._msuf2OutlineGear, "missing local gear for " .. setting)
        assert(gear:IsVisible())
        gear:Click()
        assert(popup:IsShown() and popup.select:GetValue() == id, "wrong outline selected for " .. setting)
        gear:Click()
    end
    CheckSetting("msufsuite.nameplates.enemyOutlineMode", "suite.nameplates.enemyBorderSize")
    CheckSetting("msufsuite.nameplates.friendlyOuterFrameSize", "suite.nameplates.friendlyOuterFrameSize")
    CheckSetting("msufsuite.minimap.borderSize", "suite.minimap.borderSize")
    CheckSetting("msufsuite.chat.borderSize", "suite.chat.borderSize")
    local keys = Suite.CDM.KEYS
    local rule = P.catalog.cooldownManager.rules[keys.ess.border]
    local slot = "uti"
    local row = P.RuleRow("suite_cooldownManager", "cooldownManager", rule, function() return keys[slot].border end)
    assert(row.outlineFocus() == "suite.cooldownManager." .. keys.uti.border)
    slot = "ext"
    assert(row.outlineFocus() == "suite.cooldownManager." .. keys.ext.border)
    assert(P.NameplatesWorkspace.Open("enemy"))
    M.CreateMenuPopupPanel = CreatePopup
end

do
    local record = assert(records["msufsuite.nameplates.enemyOutlineMode"], "the frame outline dropdown has no cold search route")
    local selected, anchored, exact = (M.Search._RoutingAPI or api).OpenSearchTarget(record.key,
        record.label, record.label, record.anchor, record.route, record.exactTarget)
    mw:RunTimers(1000)
    assert(selected and anchored and exact and M.activeKey == "opt_bars",
        "search did not reveal the border switch in Bars")
    local outline = assert(M.cache.opt_bars.sections.suite_nameplate_outline)
    assert(outline:IsVisible() and shortcuts[outline].enemyBorderColor)
    assert(not records["msufsuite.nameplates.hideHealthBarBorders"], "the replaced border switch remained searchable")
    local highlight = assert(records["msufsuite.nameplates.highlightFocus"], "highlight has no cold search route")
    local found, opened, matched = (M.Search._RoutingAPI or api).OpenSearchTarget(highlight.key,
        highlight.label, highlight.label, highlight.anchor, highlight.route, highlight.exactTarget)
    mw:RunTimers(1000)
    assert(found and opened and matched and outline:IsVisible() and shortcuts[outline].selectionFocusColor,
        "Frame Outline did not expose target and focus colors in Bars")
    local priority = assert(records["msufsuite.nameplates.highlightPriority"], "priority has no cold search route")
    local routed, revealed, exactPriority = (M.Search._RoutingAPI or api).OpenSearchTarget(priority.key,
        priority.label, priority.label, priority.anchor, priority.route, priority.exactTarget)
    mw:RunTimers(1000)
    assert(routed and revealed and exactPriority and widgets.highlightPriority:IsVisible(),
        "highlight search did not open the Priority tab")
    assert(not records["msufsuite.nameplates.enemyBorderEnabled"], "the replaced border toggle remained searchable")
    local rule = P.catalog.nameplates.rules.enemyOutlineMode
    local row = P.RuleRow("opt_bars", "nameplates", rule)
    local shared = Suite.HostBridge.SharedNameplateBars()
    assert(row.get() == shared.enemyOutlineMode and P.RuleEnabled("nameplates", rule),
        "the outline dropdown must show Shared until it is edited")
    local look = P.Get("nameplates", "look")
    row.set(4)
    assert(row.get() == 4 and P.Get("nameplates", "barsOverride") and P.Get("nameplates", "look") == look,
        "Off did not override Shared or changed the selected look")
    assert(M.SelectPage("suite_nameplates"))
    preview:ShowSample("enemy")
    preview:Paint()
    assert(Suite.NameplateStyle.OutlineOff(preview.barSettings, "enemy"), "Off did not reach the preview")
    assert(M.SelectPage("opt_bars"))
    P.RuleRow("opt_bars", "nameplates", P.catalog.nameplates.rules.barsOverride).set(false)
    local before = P.Get("nameplates", "hideHealthBarBorders")
    local Shared = Suite.HostBridge.SharedNameplateBars
    Suite.HostBridge.SharedNameplateBars = function()
        local inherited = Shared()
        inherited.hideHealthBarBorders = true
        return inherited
    end
    assert(not P.Get("nameplates", "barsOverride") and before == false)
    row.set(3)
    preview:Paint()
    assert(not Suite.NameplateStyle.OutlineOff(preview.barSettings, "enemy")
        and preview.barSettings.enemyOutlineMode == 3 and preview.barSettings.friendlyOutlineMode == 4,
        "Custom outline did not override inherited Hide all borders")
    Suite.HostBridge.SharedNameplateBars = Shared
    local override = P.RuleRow("opt_bars", "nameplates", P.catalog.nameplates.rules.barsOverride)
    override.set(false)
    assert(P.Set("nameplates", "hideHealthBarBorders", true))
    assert(P.Get("nameplates", "barsOverrideSaved") and not P.Get("nameplates", "barsOverride")
        and not Shared().hideHealthBarBorders, "fixture did not retain a dormant Suite outline override")
    row.set(3)
    preview:Paint()
    assert(not Suite.NameplateStyle.OutlineOff(preview.barSettings, "enemy"),
        "Custom outline reactivated a hidden saved Suite outline when leaving Shared")
    override.set(false)
    assert(P.Set("nameplates", "hideHealthBarBorders", true))
    assert(outline._msufSuiteSectionReset() and P.Get("nameplates", "hideHealthBarBorders") == false)
    assert(P.Set("nameplates", "hideHealthBarBorders", before))
    assert(M.SelectPage("suite_nameplates"))
    local configured = P.Get("nameplates", "highlightFocus")
    P.PreviewNameplateHighlight("aggro")
    assert(preview.layerContext == "highlight" and preview.highlightSample == "aggro" and preview:LayerOn("highlightBorders")
        and P.Get("nameplates", "highlightFocus") == configured, "highlight preview changed live settings")
    preview:Edit("anchor")
    -- This host fixture stores anchors but has no layout solver. Give the
    -- panel a viewport to exercise its real scroll and element callbacks.
    preview.body:SetWidth(880)
    preview.elementPanel.clip:SetSize(210, 320)
    preview:Layout()
    preview:Paint()
    local function PreviewLayer(key)
        for _, button in ipairs(preview.layerButtons) do
            if button.layerKey == key then return button end
        end
        error("missing preview layer " .. key)
    end
    local function VisiblePreviewLayer(key)
        local button = PreviewLayer(key)
        local panel, row = preview.elementPanel, button:GetParent()
        assert(button:IsVisible() and row:GetParent() == panel.content,
            ("preview layer %s is unreachable in %s at width %.0f; panel shown %s"):format(key, preview.scope,
                preview.body:GetWidth(), tostring(panel:IsShown())))
        local _, _, _, _, y = row:GetPoint()
        P.NameplatesElementPanel.Scroll(preview, -y)
        assert(-y >= panel.offset and -y + row:GetHeight() <= panel.offset + panel.clip:GetHeight(),
            "element list did not allow scrolling to " .. key)
        return button
    end
    local showCast = P.Get("nameplates", "enemyCastEnabled")
    assert(P.Set("nameplates", "enemyCastEnabled", 3))
    VisiblePreviewLayer("castIcon"):Click()
    mw:RunTimers(1000)
    assert(widgets.enemyCastEnabled and widgets.enemyCastEnabled:IsVisible()
        and P.Get("nameplates", "enemyCastEnabled") == 3, "disabled cast icon did not open its castbar enable setting")
    assert(P.Set("nameplates", "enemyCastEnabled", showCast))
    preview:Edit("anchor")
    assert(P.Set("nameplates", "highlightFocus", false))
    P.PreviewNameplateHighlight("focus")
    assert(preview:LayerActive("focusBorder"), "fixture did not show the disabled highlight example")
    VisiblePreviewLayer("focusBorder"):Click()
    mw:RunTimers(1000)
    assert(M.activeKey == "opt_bars" and widgets.highlightFocus:IsVisible()
        and P.Get("nameplates", "highlightFocus") == false, "the visible example did not open its disabled setting")
    assert(P.Set("nameplates", "highlightFocus", configured))
    assert(M.SelectPage("suite_nameplates"))
    preview:Edit("anchor")

    local highlightSettings = { "highlightTarget", "highlightFocus", "highlightMouseover", "highlightAggro", "highlightAggroOverride" }
    local savedHighlights, enabledHighlights = {}, {}
    for _, setting in ipairs(highlightSettings) do
        savedHighlights[setting] = P.Get("nameplates", setting)
        enabledHighlights[setting] = true
    end
    assert(P.SetMany("nameplates", enabledHighlights))
    local style = P.Suite.NameplateStyle
    local paintBorder = style.PaintBorder
    local health = assert(preview.kit.entries["enemy.Health"]).region
    local shown
    style.PaintBorder = function(border, owner, size, color)
        if owner == health and size ~= 0 then shown = color end
        return paintBorder(border, owner, size, color)
    end
    for key, sample in pairs({ aggroBorder = "aggro", targetBorder = "target", focusBorder = "focus", mouseoverBorder = "mouseover" }) do
        local button = VisiblePreviewLayer(key)
        shown = nil
        button:GetParent():Click()
        assert(preview.highlightSample == sample and preview:LayerActive(key) and preview.layerContext == "highlight",
            "element row did not select its highlight sample")
        assert(shown == style.CompileHighlights(preview.barSettings, sample)[sample],
            "element row did not draw the selected highlight")
        button:Click()
        assert(preview.highlightSample == sample and not preview:LayerOn(key), "element eye did not hide only the highlight layer")
    end
    style.PaintBorder = paintBorder
    assert(P.SetMany("nameplates", savedHighlights))
    VisiblePreviewLayer("focusBorder"):Click("RightButton")
    assert(M.activeKey == "opt_bars" and outline:IsVisible() and widgets.highlightFocus:IsVisible(),
        "highlight preview layer did not open its Bars settings")
    assert(M.SelectPage("suite_nameplates"))
    assert(P.Get("nameplates", "highlightFocus") == configured, "preview layer wrote to the profile")
    P.NameplatesWorkspace.Open("friendly")
    preview:Edit("anchor")
    assert(not PreviewLayer("aggroBorder"):IsVisible() and VisiblePreviewLayer("focusBorder"):IsVisible(),
        "friendly preview offered the Enemy-only Aggro border")
    P.NameplatesWorkspace.Open("enemy")
end
-- Direct preview handles retain the legacy enemy aliases.
assert(P.SelectNameplatesEnemyTab('appearance'))
assert(panels['enemyStyle:frame']:IsVisible(),'legacy appearance did not select frame settings')
assert(P.SelectNameplatesEnemyTab('elements'))
assert(widgets.enemyRaidIcon and widgets.enemyRaidIcon:IsVisible(), 'legacy elements did not select the raid marker')
assert(not widgets.enemyTargetStyle:IsVisible(), 'legacy elements left the previous icon visible')
for key,value in pairs(saved) do assert(P.Get('nameplates',key)==value,'navigation changed setting '..key) end
for key,n in pairs(built) do assert(n==1,'one panel built multiple times '..key) end
assert(M.SelectPage('home'))
M.InvalidatePage('suite_nameplates')
built,widgets,panels={},{},{}
Open({'enemyBackdropEnabled','enemyStyle:frame'})

-- Clicking a movable sample can reveal a settings section on the same page.
-- Reflow must preserve the selected handle and the X/Y edit that owns focus.
do
    local preference = M.ShouldExpandFixedPreview and M.ShouldExpandFixedPreview()
    assert(preview.compact or preference, "Suite Nameplates ignored the compact default")
    if not preview.compact then preview.expander:Close("TEST_COMPACT") end
    assert(M.SelectPage("uf_player"))
    mw:RunTimers(1000)
    if not host:match("7%.0$") then
        assert(not M._msuf2ActiveFixedPreviewExpander, "Suite's default expansion carried over to MSUF 6.5")
    end
    assert(M.SelectPage("suite_nameplates"))
    mw:RunTimers(1000)
    assert(preview.compact or preference, "Suite Nameplates ignored the compact default on return")
    preview:ShowSample("enemy")
    preview:Edit("status")
    assert(not preview.compact, "Edit in preview did not open the shared editor")
    local arrow = assert(preview.kit.entries["enemy.target"]).region
    local bar = preview.selection
    assert(not bar.openButton:IsShown() and bar.resetButton:IsVisible(), "Nameplates still shows Open settings")
    local _, resetAnchor = bar.resetButton:GetPoint()
    assert(resetAnchor == bar, "reset still anchors to the hidden settings button")
    assert(arrow:IsVisible() and bar:IsVisible(), "fixture target arrow or X/Y toolbar is hidden")
    arrow:GetScript("OnMouseDown")(arrow, "LeftButton")
    arrow:GetScript("OnMouseUp")(arrow, "LeftButton")
    arrow:GetScript("OnClick")(arrow, "LeftButton")
    mw:RunTimers(1000)
    assert(preview.body._selectedHandle == arrow and bar.editX:IsEnabled() and bar.editY:IsEnabled(),
        "same-page settings navigation dropped the preview selection and disabled X/Y")
    local x, y = P.Get("nameplates", arrow.keyX), P.Get("nameplates", arrow.keyY)
    bar.editX:GetScript("OnEditFocusGained")(bar.editX)
    bar.editX:SetText(tostring(x + 9))
    local headers = assert(M.cache.suite_nameplates.pageHeaders)
    for _, record in ipairs(headers) do
        if record.previewExpander then record.previewExpander:Relayout("XY_EDIT_TEST") end
    end
    assert(bar.editX:GetText() == tostring(x + 9), "same-mode layout overwrote a pending X edit")
    bar.editX:GetScript("OnEnterPressed")(bar.editX)
    assert(P.Get("nameplates", arrow.keyX) == x + 9 and P.Get("nameplates", arrow.keyY) == y,
        "X field did not update only the selected arrow X")
    bar.editY:GetScript("OnEditFocusGained")(bar.editY)
    bar.editY:SetText(tostring(y - 6))
    bar.editY:GetScript("OnEditFocusLost")(bar.editY)
    assert(P.Get("nameplates", arrow.keyX) == x + 9 and P.Get("nameplates", arrow.keyY) == y - 6,
        "Y field did not update only the selected arrow Y")
    assert(preview.body._selectedHandle == arrow, "committing the X/Y fields dropped the selection")
    assert(M.SelectPage("home"))
    assert(not preview.body._selectedHandle, "leaving the page retained its preview selection")
    assert(M.SelectPage("suite_nameplates"))
    mw:RunTimers(1000)
end

-- The preview Font field must edit the size that the shared renderer reads.
do
    local text = P.Suite.NameplateText
    local config, general = P.S.Config("nameplates"), M.EnsureDB().general
    local previous = general.fontSize
    general.fontSize = 17
    if text.Shared(config) then
        preview:ShowSample("enemy")
        local spell = assert(preview.kit.entries["enemy.CastText"]).region
        local field = preview.sizeFields[1].edit
        assert(spell:IsVisible(), "fixture spell name is hidden")
        local paint, drawn = P.StylePreviewFont
        P.StylePreviewFont = function(region, font, size, ...)
            if region:GetParent() == spell then drawn = size end
            return paint(region, font, size, ...)
        end
        local legacy = config.enemyCastSize
        preview:Select(spell)
        assert(field:GetText() == "17", "Font field showed a stored legacy size instead of the displayed size")
        field:GetScript("OnEditFocusGained")(field)
        field:SetText("21")
        field:GetScript("OnEnterPressed")(field)
        assert(drawn == 21 and field:GetText() == "21", "Font edit did not repaint the selected spell name")
        local shared = text.Shared(config)
        assert(text.FontStyle(config, "enemyCast", shared).size == 21 and config.enemyCastSize == legacy,
            "preview font size failed to reach runtime or overwrote the legacy setting")
        assert(text.FontStyle(config, "friendlyCast", shared).size == 17 and general.fontSize == 17,
            "enemy cast text size changed the shared or friendly size")
        local values = {}
        P.NameplatesSize.ResetValues(spell, values, P.catalog.nameplates.rules)
        assert(P.SetMany("nameplates", values))
        preview:Paint()
        assert(drawn == 17 and field:GetText() == "17", "reset did not restore the inherited font size")
        P.StylePreviewFont = paint
    end
    general.fontSize = previous
end

local function ClickLayer(key, mouse)
    for _, button in ipairs(preview.layerButtons) do
        if button.layerKey == key then return button:GetScript("OnClick")(button, mouse or "LeftButton") end
    end
    error("missing preview layer: " .. key)
end

do
    local config = P.S.Config("nameplates")
    local changes = { look = 4, enabled = true, enemy = true, friendly = true,
        neutralSkinEnabled = true, neutralPlateNameOnly = true, neutralNameOnlyMode = 1, enemyCastEnabled = 2 }
    local previous = {}
    for key in pairs(changes) do previous[key] = config[key] end
    assert(P.SetMany("nameplates", changes))
    for _, scope in ipairs({ "enemy", "friendly", "neutral" }) do
        assert(P.NameplatesWorkspace.Open(scope))
        if scope == "neutral" then assert(P.Set("nameplates", "enemyCastEnabled", 3)) end
        preview:Edit("anchor", "Health")
        ClickLayer("castShield", "RightButton")
        local shield = preview.body._selectedHandle
        assert(M.activeKey == "suite_nameplates" and preview.scope == scope and shield and shield:IsVisible()
            and shield.keyX == (scope == "friendly" and "friendly" or "enemy") .. "CastShieldOffsetX",
            "Blizzard shield chip did not open its position controls in " .. scope)
        shield:GetScript("OnClick")(shield, "RightButton")
        assert(preview.body._selectedHandle == shield and preview.castSample == "CastShield",
            "Blizzard shield handle used a different settings destination in " .. scope)
    end
    assert(P.SetMany("nameplates", previous))
    assert(P.NameplatesWorkspace.Open("enemy"))
end

-- Manual cast width and time size use the same settings in the menu and preview.
do
    local config = P.S.Config("nameplates")
    local changes = { look = 4, enemy = true, enemyCastEnabled = 2, enemyCastWidthMode = 3,
        enemyCastManualWidth = 191, enemyCastTimeEnabled = true, enemyCastTimeSize = 19 }
    local previous = {}
    for key in pairs(changes) do previous[key] = config[key] end
    assert(P.SetMany("nameplates", changes))
    preview:ShowSample("enemy")
    preview:Edit("cast", "CastTime")
    local bar = assert(preview.kit.entries["enemy.Cast"]).region
    local time = assert(preview.kit.entries["enemy.CastTime"]).region
    assert(bar:GetWidth() == 191 and P.NameplatesSize.Keys(bar) == "enemyCastManualWidth")
    assert(time:IsVisible() and P.NameplatesSize.Keys(time) == "enemyCastTimeSize" and time:GetHeight() == 19)
    ClickLayer("castTime")
    assert(not time:IsVisible() and bar:IsVisible() and config.enemyCastTimeEnabled, "cast time chip altered the edit sample or its setting")
    ClickLayer("castTime")
    assert(time:IsVisible(), "cast time chip did not restore the edit sample")
    ClickLayer("cast")
    assert(not bar:IsVisible() and config.enemyCastEnabled == 2, "cast chip did not hide the edit sample locally")
    ClickLayer("cast")
    assert(bar:IsVisible() and time:IsVisible(), "cast chip did not restore the edit sample")
    assert(P.SetMany("nameplates", previous))
end

-- The resource card switches fill modes and edits detached dimensions in the shared preview.
do
    local config = P.S.Config("nameplates")
    local changes = { look = 4, enemy = true, enemyPowerEnabled = true, enemyPowerDetached = true,
        enemyPowerDetachedWidth = 120, enemyPowerDetachedHeight = 8 }
    local previous = { enemyPowerSmooth = config.enemyPowerSmooth, enemyPowerChunked = config.enemyPowerChunked }
    for key in pairs(changes) do previous[key] = config[key] end
    assert(P.SetMany("nameplates", changes))
    local rules = P.catalog.nameplates.rules
    local chunk = P.RuleRow("suite_nameplates", "nameplates", rules.enemyPowerChunked)
    local smooth = P.RuleRow("suite_nameplates", "nameplates", rules.enemyPowerSmooth)
    chunk.set(true)
    assert(chunk.get() and not smooth.get())
    smooth.set(true)
    assert(smooth.get() and not chunk.get())
    preview:ShowSample("enemy")
    preview:Edit("power", "Power")
    local power = assert(preview.kit.entries["enemy.Power"]).region
    local width, height = P.NameplatesSize.Keys(power)
    assert(power:IsVisible() and power:GetWidth() == 120 and power:GetHeight() == 8)
    assert(width == "enemyPowerDetachedWidth" and height == "enemyPowerDetachedHeight")
    ClickLayer("enemyPower")
    assert(not power:IsVisible() and config.enemyPowerEnabled, "power chip did not hide the edit sample locally")
    ClickLayer("enemyPower")
    assert(power:IsVisible(), "power chip did not restore the edit sample")
    assert(P.SetMany("nameplates", previous))
end

-- Power Text is independently selectable in the shared preview.
do
    local config = P.S.Config("nameplates")
    local changes = { look = 4, enemy = true, enemyPowerEnabled = true, enemyPowerTextVisible = true,
        enemyPowerTextMode = 2, enemyPowerTextOffsetX = 9 }
    local previous = {}
    for key in pairs(changes) do previous[key] = config[key] end
    assert(P.SetMany("nameplates", changes))
    preview:ShowSample("enemy")
    preview:Edit("text", "PowerText")
    local text = assert(preview.kit.entries["enemy.PowerText"]).region
    assert(text:IsVisible() and P.NameplatesSize.Keys(text) == "enemyPowerTextSize")
    assert(preview.selection.editX:GetText() == "9", "preview focused the resource bar instead of its text")
    assert(P.SetMany("nameplates", previous))
end

-- The Suite's aura containers use the shared sample painter and existing
-- XY/size editor; Blizzard's own sample auras keep Blizzard's size setting.
-- Six-plate mode allocates on demand and keeps editing handles unique.
do
    local config = P.S.Config("nameplates")
    local Auras = P.Suite.NameplateAuraDisplay
    local dotsList = Auras.ListKey(Auras.Scope("enemy"), Auras.Container("dots"))
    local changes = { look = 4, enemy = true, auraDisplayEnabled = true, auraEnemyDotsVisible = true,
        auraEnemyDotsSource = 2, [dotsList] = "589,34914", auraEnemyDotsMissing = true,
        enemyNpcAuraMode = 2, enemyNpcBuffs = true, auraPandemicHighlight = true }
    local previous = {}
    for key in pairs(changes) do previous[key] = config[key] end
    previous.auraEnemyDotsOffsetX, previous.auraEnemyDotsSize = config.auraEnemyDotsOffsetX, config.auraEnemyDotsSize
    assert(P.SetMany("nameplates", changes))
    preview:ShowSample("enemy")
    preview:Paint()
    local buffs = assert(preview.kit.entries["enemy.Buffs"]).region
    local tracked = assert(preview.kit.entries["enemy.Tracked"]).region
    assert(tracked:IsVisible(), "the Dots on target container was not painted")
    assert(P.NameplatesSize.Keys(buffs) == "auraEnemyBuffScale" and P.NameplatesSize.Keys(tracked) == "auraEnemyDotsSize",
        "aura sample size fields edit a different setting")
    assert(P.NameplatesSize.Write(preview, tracked, "auraEnemyDotsSize", 40))
    assert(config.auraEnemyDotsSize == 40 and tracked:GetHeight() == 40, "aura size editor did not repaint the container")
    preview:Select(tracked)
    local editX = preview.selection.editX
    editX:GetScript("OnEditFocusGained")(editX)
    editX:SetText("17")
    editX:GetScript("OnEnterPressed")(editX)
    assert(config.auraEnemyDotsOffsetX == 17, "container drag editor did not write its X offset")
    assert(not preview.groupPreview, "six-plate sample eagerly allocated")
    local handles = #preview.handles
    preview.zoom, preview.panX, preview.panY = 1.3, 11, -7
    local toggle = assert(preview.groupPreviewButton):GetScript("OnClick")
    toggle(preview.groupPreviewButton)
    local group = assert(preview.groupPreview)
    assert(group.frame:IsVisible() and #group.samples == 4 and #preview.handles == handles,
        "comparison omitted a nameplate type or duplicated editing handles")
    preview:Select(tracked)
    assert(not preview.body._selectedHandle, "group preview selected a hidden single-plate handle")
    assert(not preview.sampleCells.enemy:IsVisible() and not preview.sampleCells.friendly:IsVisible())
    assert(group.samples[1].sample.state.target and group.samples[2].editor.scope == "neutral"
        and group.samples[3].editor.scope == "friendly" and group.samples[4].editor.friendlyElite,
        "comparison does not render the four unit types")
    do
        local npc = group.samples[4]
        local mode, tint, enabled = config.friendlyNPCs, config.friendlyNpcPlateNameTypeColor, config.friendlyNpcSkinEnabled
        local resolve = P.Suite.HostBridge.NPCNameColor
        P.Suite.HostBridge.NPCNameColor = function(kind) assert(kind == "friendly") return .1, .8, .3 end
        config.friendlyNPCs, config.friendlyNpcPlateNameTypeColor, config.friendlyNpcSkinEnabled = 5, true, true
        local label, rgb = npc.sample.nameText
        local set = label.SetTextColor
        label.SetTextColor = function(self, r, g, b, a) rgb = { r, g, b } return set(self, r, g, b, a) end
        P.NameplatesPreview.Render(npc.editor, npc.sample)
        assert(rgb and rgb[1] == .1 and rgb[2] == .8 and rgb[3] == .3, "friendly NPC preview used an enemy role color")
        config.friendlyNpcPlateNameTypeColor = false
        P.NameplatesPreview.Render(npc.editor, npc.sample)
        local red, green, blue = P.RGB(npc.sample.metrics.healthColor)
        assert(rgb[1] == red and rgb[2] == green and rgb[3] == blue, "the sample name did not inherit its own bar color")
        local text = P.Suite.NameplateText
        local compile = text.Compile
        text.Compile = function(...)
            local look = compile(...)
            look.customColor, look.r, look.g, look.b = true, .73, .21, .64
            return look
        end
        P.NameplatesPreview.Render(npc.editor, npc.sample)
        text.Compile = compile
        assert(rgb[1] == .73 and rgb[2] == .21 and rgb[3] == .64, "Name only preview ignored its custom text tint")
        label.SetTextColor, P.Suite.HostBridge.NPCNameColor = set, resolve
        config.friendlyNPCs, config.friendlyNpcPlateNameTypeColor, config.friendlyNpcSkinEnabled = mode, tint, enabled
    end
    local auraState = assert(group.samples[1].sample.auraPreviewState)
    assert(#auraState.containers.dots.icons == 2,
        "group sample bypassed the shared aura container preview")
    local create, created = env.CreateFrame, 0
    env.CreateFrame = function(...) created = created + 1 return create(...) end
    for _ = 1, 25 do preview:Paint() end
    env.CreateFrame = create
    assert(created == 0, "warm group paints allocate new frames")
    toggle(preview.groupPreviewButton)
    assert(not group.frame:IsVisible() and preview.sampleCells.enemy:IsVisible()
        and preview.zoom == 1.3 and preview.panX == 11 and preview.panY == -7,
        "leaving group mode lost the original single-plate view")
    toggle(preview.groupPreviewButton)
    assert(preview.groupPreview == group and #preview.handles == handles, "group toggle rebuilt its samples")
    toggle(preview.groupPreviewButton)
    assert(P.SetMany("nameplates", previous))
    preview.zoom, preview.panX, preview.panY = 1, 0, 0
    preview:Paint()
end

-- 7.0's generic exact link queues navigation until the static index is ready.
-- Preview and interrupt links already know the live control and must land now.
do
    local static = M.Search.StaticIndex
    local decoded, ready = static and static.IsDecoded, api.WhenIndexReady
    local queued = {}
    local sectionFocus, focuses = P.W.FocusCollapsibleSection, 0
    P.W.FocusCollapsibleSection = function(...)
        focuses = focuses + 1
        return sectionFocus(...)
    end
    if decoded then static.IsDecoded = function() return false end end
    api.WhenIndexReady = function(callback) queued[#queued + 1] = callback return true end
    for _, button in ipairs(preview.layerButtons) do
        if button.layerKey == "level" then button:GetScript("OnClick")(button, "RightButton") end
    end
    assert(widgets.enemyLevelEnabled and widgets.enemyLevelEnabled:IsVisible(),
        "cold preview link did not immediately open the enemy level toggle")
    assert(focuses == 0, "exact preview link also focused its fallback section")
    P.W.FocusCollapsibleSection = sectionFocus
    assert(P.OpenNameplateSetting("nativeSize"), "cold preview link could not reveal the Blizzard plates section")
    assert(widgets.nativeSize and widgets.nativeSize:IsVisible(), "cold preview link left its area hidden")
    assert(P.OpenNameplateSetting("enemyCastHeight"), "cold preview link could not reveal the enemy castbar section")
    assert(interruptLink, "enemy castbar lost its interrupt settings link")
    interruptLink:GetScript("OnClick")(interruptLink, "LeftButton")
    assert(M.activeKey == "opt_castbar", "cold interrupt settings link was deferred")
    local _, toggle = M.RuntimeControlCatalog.FindBySettingKey("general.kickReadyShowNameplates", "opt_castbar")
    assert(toggle and toggle:IsVisible(), "cold interrupt link did not open the nameplates toggle")
    assert(M.SelectPage("home"))
    for _, callback in ipairs(queued) do callback() end
    mw:RunTimers(1000)
    assert(#queued == 0 and M.activeKey == "home", "a delayed nameplate link overrode the newer navigation")
    api.WhenIndexReady = ready
    if decoded then static.IsDecoded = decoded end
end

do
    local tails, values = 0
    local priorGrid, priorScope = P.RuleGrid, M.GlobalPage.BuildScopeOverrideSection
    P.RuleGrid = function(ctx, parent, page, ...)
        if page == "opt_fonts" then tails = tails + 1 end
        return priorGrid(ctx, parent, page, ...)
    end
    M.GlobalPage.BuildScopeOverrideSection = function(ctx, builder, opts)
        values = opts.values
        return priorScope(ctx, builder, opts)
    end
    local formatter = P.Suite.HostBridge.NameFormatter()
    if formatter and formatter.Nameplates then
        local GP, db = M.GlobalPage, M.EnsureDB()
        local config = P.S.Config("nameplates")
        local before = config.nameFormattingEnabled
        local function Click(label, section)
            local entry = M.cache.opt_fonts
            if entry then P.HM.GetSectionEntry(entry.sections[section]).SetOpenImmediate(false) end
            db.general._fontScopeKey = "player"
            OpenNameTextCard()
            local button = assert(links[label], "missing Fonts shortcut for " .. label)
            assert(button:IsVisible() and button:IsEnabled(), "inactive Fonts shortcut for " .. label)
            button:GetScript("OnClick")(button)
            mw:RunTimers(1000)
            assert(M.activeKey == "opt_fonts" and GP.CurrentFontScope() == "nameplates",
                "shortcut did not select the Nameplates scope")
            assert(P.HM.GetSectionEntry(M.cache.opt_fonts.sections[section]).open, "shortcut did not open " .. section)
        end
        Click("Name format", "fonts_name_shortening")
        local colorSection = "fonts_name_power_colors"
        local openColors, openPicker = P.W.OpenContextColors, M.Widgets.OpenColorContextPicker
        local picker, opened
        M.Widgets.OpenColorContextPicker = function() opened = true end
        P.W.OpenContextColors = function(anchor, options, targets)
            picker = targets
            return openColors(anchor, options, targets)
        end
        local function Pick(spec, action, tab)
            spec.select(tab)
            picker, opened = nil, false
            action:Click()
            assert(M.activeKey == "suite_nameplates", "Text Colors left the Nameplates page")
            assert(opened and picker and #picker == 1, "Text Colors did not open the common picker for the active tab")
            return picker[1]
        end
        for _, scope in ipairs({ "enemy", "neutral", "friendly", "friendlyNpc" }) do
            local side = scope:match("^friendly") and "friendly" or "enemy"
            local sectionId = "suite_nameplates_" .. side .. "Text"
            db.general._fontScopeKey = "player"
            OpenNameTextCard()
            assert(P.NameplatesWorkspace.Open(scope))
            local page = M.cache.suite_nameplates
            local body = assert(page.sections[sectionId])
            local spec
            for _, entry in ipairs(P.NameplateSections) do
                if entry.key == side .. "Text" then spec = entry break end
            end
            assert(spec and spec.select("name"))
            local action = assert(textColorLinks[side .. "Text"], "missing direct Text Colors link for " .. scope)
            assert(action:GetParent() == body and action:IsVisible(), "Text Colors is hidden in a different menu or tab")
            local more = assert(P.HM.GetSectionEntry(body)._msufSuiteResetButton)
            local popup = more:_msufSuiteEnsureSectionPopup()
            for _, child in ipairs({ popup:GetChildren() }) do
                local label = child.GetText and child:GetText()
                assert(label ~= P.Tr("Colors") and label ~= P.Tr("Text Colors"), "Text actions kept a duplicate color entry")
            end
            local nameKey = (scope == "friendlyNpc" and "friendly" or scope) .. "NameColor"
            local enabledKey, priorColor = nameKey .. "Enabled", P.Get("nameplates", nameKey)
            local priorEnabled, priorLook = P.Get("nameplates", enabledKey), config.look
            local name = Pick(spec, action, "name")
            assert(name.settingKey == "msufsuite.nameplates." .. nameKey, "picker targeted the wrong Nameplate type")
            local nameState = name.captureState()
            assert(name.set(.2, .4, .6) and P.Get("nameplates", nameKey) == "336699" and P.Get("nameplates", enabledKey),
                "custom Nameplate color did not update the Fonts settings")
            name.restoreState(nameState)
            assert(P.Get("nameplates", nameKey) == priorColor and P.Get("nameplates", enabledKey) == priorEnabled
                and config.look == priorLook, "cancel did not restore the name color and mode")

            if scope == "enemy" then
                local priorTypography, context = db.nameplates, P.AnchoredContextMenu
                db.nameplates = { fontOverride = false, fontKey = "FRIZQT" }
                local activate
                P.AnchoredContextMenu = function(_, generate)
                    generate(nil, { CreateTitle = function() end,
                        CreateButton = function(_, label, click)
                            if label == P.Tr("Use custom settings for this scope") then activate = click end
                        end })
                end
                spec.select("hp")
                picker, opened = nil, false
                action:Click()
                assert(activate and not opened and db.nameplates.fontOverride == false,
                    "opening HP colors reactivated stored typography without user input")
                activate()
                P.AnchoredContextMenu = context
                assert(opened and picker and #picker == 1 and db.nameplates.fontOverride,
                    "explicit typography override did not open the HP picker")
                local hp = Pick(spec, action, "hp")
                local hpState = assert(hp.captureState())
                local sharedR = db.general.fontColorCustomR
                assert(hp.set(.25, .5, .75), "HP font color update failed")
                local painted = formatter.Nameplates({}).textColor
                assert(painted.r == .25 and painted.g == .5 and painted.b == .75,
                    "HP text color did not update the nameplate font scope")
                assert(db.general.fontColorCustomR == sharedR, "HP color changed Shared")
                assert(hp.restoreState(hpState), "HP color cancel failed")
                assert(db.nameplates.fontColorR == hpState.values.fontColorR and db.nameplates.fontOverride,
                    "HP color cancel did not restore the explicit value under the selected scope")
                local previousLook = config.look
                config.look = 1
                picker, opened = nil, false
                action:Click()
                assert(not opened, "HP picker was offered for a look that ignores font scope")
                config.look, db.nameplates = previousLook, priorTypography

                local power = Pick(spec, action, "power")
                local previous = P.Get("nameplates", "enemyPowerTextColor")
                local r, g, b = power.get()
                assert(power.settingKey == "msufsuite.nameplates.enemyPowerTextColor" and power.set(.2, .4, .6)
                    and P.Get("nameplates", "enemyPowerTextColor") == "336699", "Power Text did not edit its Fonts color")
                assert(power.set(r, g, b) and P.Get("nameplates", "enemyPowerTextColor") == previous)
            end
            assert(not links["Text Colors"], "Name card repeats the direct Text Colors link")
        end
        P.W.OpenContextColors, M.Widgets.OpenColorContextPicker = openColors, openPicker
        assert(not widgets.enemyNameFormat and not widgets.friendlyNameFormat, "legacy disabled name rows are still built")
        assert(config.nameFormattingEnabled == before, "opening Fonts changed a Suite setting")
        assert(db.nameplates == nil or not db.nameplates.fontOverride, "opening Fonts enabled an override")

        local statusColor = P.Suite.NameplateExtensions.TextKey("friendlyNpc", P.Suite.NameplateExtensions.FirstTextSource) .. "Color"
        for key, section in pairs({ enemyNameMaxChars = "fonts_name_shortening",
            friendlyNameColor = colorSection, neutralNameColor = colorSection, enemyPowerTextColor = colorSection,
            enemyPlateNameClassColor = colorSection, friendlyNameClassColor = colorSection, threatNameColor = colorSection,
            neutralPlateNameTypeColor = colorSection, focusReminderColor = colorSection, [statusColor] = colorSection,
            enemyLevelColor = colorSection, friendlyStatusAFKColor = colorSection, auraTimeColor = colorSection,
            auraStackColor = colorSection }) do
            OpenNameTextCard()
            local record = assert(records["msufsuite.nameplates." .. key], "missing Fonts search record for " .. key)
            local selected, anchored, exact = (M.Search._RoutingAPI or api).OpenSearchTarget(record.key,
                record.label, record.label, record.anchor, record.route, record.exactTarget)
            mw:RunTimers(1000)
            assert(selected and anchored and exact, "old setting did not resolve to a Fonts section: " .. key)
            assert(M.activeKey == "opt_fonts" and GP.CurrentFontScope() == "nameplates", "wrong search destination for " .. key)
            assert(P.HM.GetSectionEntry(M.cache.opt_fonts.sections[section]).open, "search did not open " .. section)
        end
        db.general._fontScopeKey = "nameplates"
        db.general.nameFormat, db.general.shortenNameMaxChars = "ABBREV_CUT", 8
        db.general.shortenNameClipSide, db.general.shortenNameShowDots = "RIGHT", false
        db.general.fontTextAlpha = .85
        db.nameplates = nil
        assert(M.SelectPage("opt_fonts") ~= false)
        mw:RunTimers(1000)
        local found
        for _, value in ipairs(values or {}) do if value.value == "nameplates" then found = true end end
        assert(found and GP.CurrentFontScope() == "nameplates", "Nameplates is absent from the standard Fonts selector")
        local sections = M.cache.opt_fonts.sections
        assert(tails > 0 and not sections.opt_fonts_host_nameplates and not sections.opt_fonts_nameplate_colors,
            "native Fonts should show all colors in one section")
        for _, scope in ipairs({ "enemy", "neutral", "friendly" }) do
            local setting = "msufsuite.nameplates." .. scope .. "NameColor"
            local _, swatch = M.RuntimeControlCatalog.FindBySettingKey(setting, "opt_fonts")
            assert(swatch and swatch:IsVisible(), "missing Fonts color swatch for " .. scope)
        end
        local inherited = formatter.Nameplates({})
        assert(inherited.nameFormat == "ABBREV_CUT" and inherited.nameShortenMax == 8,
            "native nameplate scope does not inherit Shared")
        GP.FontScopeSetFor("nameplates", "nameFormat", "CUT", nil, nil, true)
        GP.FontScopeSetFor("nameplates", "shortenNameMaxChars", 5, nil, nil, true)
        GP.FontScopeSetFor("nameplates", "fontTextAlpha", .7, nil, nil, true)
        local custom = formatter.Nameplates({})
        assert(db.nameplates.fontOverride and custom.nameFormat == "CUT" and custom.nameShortenMax == 5,
            "standard nameplate scope writes do not reach the runtime projection")
        assert(custom.fontTextAlpha == .7 and db.general.fontTextAlpha == .85, "scope opacity changed Shared")
        config.nameFormattingEnabled, config.nameTextUseCustomSettings = false, true
        config.enemyNameColorEnabled, config.enemyNameColor = true, "00ff00"
        local look = P.Suite.NameplateText.Compile(config, "enemy")
        assert(look.enabled and look.max == 5 and look.customColor and look.g == 1,
            "reaction color must override only the color of the ordinary Fonts scope")
        assert(not P.Suite.NameplateText.Compile(config, "enemy", "neutral").customColor,
            "the enemy choice leaked into neutral names")
        GP.ScopeSetOverride("nameplates", "fontOverride", false)
        local shared = formatter.Nameplates({})
        assert(shared.nameFormat == "ABBREV_CUT" and shared.nameShortenMax == 8 and shared.fontTextAlpha == .85,
            "scope reset does not return nameplates to Shared")
        assert(db.nameplates.nameFormat == "CUT", "turning off override destroyed stored local values")
    else
        OpenNameTextCard()
        assert(not widgets.enemyNameFormat and not widgets.friendlyNameFormat)
        local typography = assert(links["Nameplate typography"], "missing fallback Fonts link")
        typography:Click()
        mw:RunTimers(1000)
        assert(M.activeKey == "opt_fonts" and M.cache.opt_fonts.sections.opt_fonts_host_nameplates:IsVisible())
        assert(M.cache.opt_fonts.sections.opt_fonts_nameplate_colors:IsVisible(), "fallback Fonts lost reaction colors")
    end
end

do
    local config, rules = P.S.Config("nameplates"), P.catalog.nameplates.rules
    local look = assert(P.RuleRow("suite_nameplates", "nameplates", rules.look))
    OpenNameTextCard()
    local hostBars = assert(Suite.HostBridge.SharedNameplateBars())
    local hostFill = hostBars.nativeHealthFillTexture
    for _, customBars in ipairs({ false, true }) do
        assert(P.SetMany("nameplates", { look = 3, barsOverride = customBars, barsOverrideSaved = customBars,
            enemyNameVisible = false, enemyHealthTextMouseover = true, enemyCastWidthMode = 3,
            enemyCastManualWidth = 282, enemyCastTimeSize = 28, enemyNameSizeOverride = 29,
            nativeHealthFillTexture = "Solid", nativeFocusHealthFillTexture = "Solid", healthGlossEnabled = true,
            friendlySkinEnabled = false, enemyPowerEnabled = true, auraEnemyDotsVisible = true,
            targetScaleEnabled = true, hideHealthBarBorders = true, enemyFadeOutOfCombat = true }))
        look.set(1)
        assert(look.get() == 1, "selecting Jundies did not apply the preset")
        local typography = Suite.NameplateText
        assert(not typography.UsesSharedFont(config) and typography.FontStyle(config, "enemy").size == 14,
            "the host font replaced Jundies typography")
        assert(config.enemyNameVisible and not config.enemyHealthTextMouseover and config.enemyNameSizeOverride == 0
            and config.enemyCastWidthMode == 2 and config.enemyCastManualWidth == 160 and config.enemyCastTimeSize == 0,
            "Jundies retained the Custom text or castbar presentation")
        preview:Paint()
        assert(config.barsOverride and config.barsOverrideSaved and preview.barSettings.nativeHealthFillTexture == "Solid"
            and preview.barSettings.nativeFocusHealthFillTexture == "" and not preview.barSettings.healthGlossEnabled
            and preview.barSettings.enemyOutlineMode == 3 and not config.targetScaleEnabled and not config.hideHealthBarBorders,
            "Jundies retained Shared or Custom bar styling")
        assert(config.friendlySkinEnabled == false and config.enemyPowerEnabled and config.auraEnemyDotsVisible
            and config.enemyFadeOutOfCombat, "Jundies changed the selected units, resource bar, tracked auras or combat fading")
    end
    local shared = assert(P.RuleRow("opt_bars", "nameplates", rules.barsOverride))
    shared.set(false)
    preview:Paint()
    assert(preview.barSettings.nativeHealthFillTexture == hostFill and Suite.HostBridge.SharedNameplateBars().nativeHealthFillTexture == hostFill,
        "Jundies changed Shared or prevented switching back to it")
    look.set(4)
    preview:Paint()
    assert(config.look == 4 and config.barGeometry == 2 and preview.barSettings.nativeHealthFillTexture == "",
        "switching to Mapko from Shared did not restore its own bar appearance")
end

do
    assert(P.NameplatesWorkspace.Open("enemy"))
    preview:Edit("anchor")
    assert(P.SetMany("nameplates", { look = 3, barsOverride = true, enemySlantedHealth = true,
        enemyOutlineMode = 3, enemySkinEnabled = true, enemy = true }))
    preview:Paint()
    local bar = assert(preview.kit.entries["enemy.Health"]).region
    local masks, rim = {}, nil
    local function Assets()
        masks, rim = {}, nil
        for _, texture in ipairs({ bar:GetRegions() }) do
            local path = texture:GetTexture()
            if type(path) == "string" then
                if path:match("SlantedHealthMask%.tga$") or path:match("slanted_bar_mask.*%.png$") then masks[texture] = 0 end
                if path:match("SlantedHealthEdge%.tga$") or path:match("slanted_bar_edge.*%.png$") then rim = texture end
            end
        end
    end
    Assets()
    assert(rim and rim:IsShown(), "Slanted did not paint a shaped preview outline")
    for _, texture in ipairs({ bar:GetRegions() }) do
        local mask = texture.testMask
        if masks[mask] then masks[mask] = masks[mask] + 1 end
    end
    local progress, back
    for mask, count in pairs(masks) do
        if mask:GetPoint(1) == "TOPRIGHT" then
            progress = count >= 2 and mask:GetWidth() == bar:GetWidth()
        else
            back = count >= 3
        end
    end
    assert(progress and back, "Slanted needs a full-width moving mask and a fixed backdrop mask")
    P.Set("nameplates", "mouseoverHighlight", true)
    P.NameplatesPreviewDecor.Hover(bar, true)
    preview:Paint()
    P.NameplatesPreviewDecor.Hover(bar, false)
    assert(P.Set("nameplates", "enemyOutlineMode", 4))
    preview:Paint()
    assert(not rim:IsShown(), "Frame Outline Off left the Slanted rim shown")
    assert(P.Set("nameplates", "enemySlantedHealth", false))
    preview:Paint()
    for _, texture in ipairs({ bar:GetRegions() }) do
        assert(not masks[texture.testMask], "turning Slanted off kept a preview region clipped")
    end
end

print('PASS real host Nameplates cold tab/exact search/legacy preview parity '..flavor)
