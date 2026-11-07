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
world.widgets.Methods.SetPointsOffset = function(self,x,y) self.pointsOffset={x,y} end
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
            local ok, message = world:LoadFile(root .. "/" .. addon .. "/" .. line:gsub("\\", "/"), addon, namespace)
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
local preview, interruptLink
local CreateEditor, Button = P.NameplatesEditor.Create, P.Button
P.NameplatesEditor.Create = function(...)
    preview = CreateEditor(...)
    return preview
end
P.Button = function(ctx, parent, label, ...)
    local button = Button(ctx, parent, label, ...)
    if label == "Open interrupt settings" then interruptLink = button end
    return button
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
    if id=='nameplates' then for _,entry in ipairs(entries) do if entry.widget then widgets[entry.rule.key]=entry.widget end end end
    return y,entries
end
local links = {}
local Button = P.Button
P.Button = function(ctx, parent, label, x, y, width, click, enabled, meta, options)
    local button = Button(ctx, parent, label, x, y, width, click, enabled, meta, options)
    if meta and meta.sectionId == "suite_nameplates_nameText" then links[label] = button end
    return button
end

local function OpenNameTextCard()
    assert(M.SelectPage("suite_nameplates"))
    local body = assert(M.cache.suite_nameplates.sections.suite_nameplates_nameText)
    M.Widgets.FocusCollapsibleSection(body, { scroll = false, flash = false })
    mw:RunTimers(1000)
end

local records={}
for _,record in ipairs(Ready()) do
    local setting=record.exactTarget and record.exactTarget.settingKey
    if setting and setting:find('^msufsuite%.nameplates%.') then records[setting]=record end
end
local cases={
    {'enemyTextMode','enemy:text'}, {'enemyTargetStyle','enemy:target'},
    {'friendlyCastHeight','friendly:castbar'}, {'friendlyCastWidthDelta','friendly:castbar'},
    {'selectionBorder','signals:selection'},
    {'friendlyNpcDebuffs','auras:general'},
}
local saved={}
for _,case in ipairs(cases) do
    assert(records['msufsuite.nameplates.'..case[1]],'missing cold record '..case[1])
    saved[case[1]]=P.Get('nameplates',case[1])
end
assert(not M.cache.suite_nameplates,'target page was prebuilt by cold search')
if enforce then
    local record=records['msufsuite.nameplates.enemyTextMode']
    local selected,anchored,exact=(M.Search._RoutingAPI or api).OpenSearchTarget(record.key,record.label,record.label,record.anchor,record.route,record.exactTarget)
    mw:RunTimers(1000)
    assert(selected and anchored and exact,'first cold page target failed')
    assert(widgets.enemyTextMode and widgets.enemyTextMode:IsVisible(),'first cold page target hidden')
end
assert(M.SelectPage('suite_nameplates'))
mw:RunTimers(1000)
local bySection={}
for key in pairs(built) do local section=key:match('^([^:]+)'); bySection[section]=(bySection[section] or 0)+1 end
for section,n in pairs(bySection) do
    print('initial '..section..' grids='..n)
    if enforce then assert(n<=1,'opening one section built hidden tabs: '..section..' '..n) end
end
local function Open(case)
    assert(M.SelectPage('home'))
    Ready()
    local record=records['msufsuite.nameplates.'..case[1]]
    local selected,anchored,exact=(M.Search._RoutingAPI or api).OpenSearchTarget(record.key,record.label,record.label,record.anchor,record.route,record.exactTarget)
    mw:RunTimers(1000)
    assert(selected and anchored and exact,'cold target did not resolve exactly: '..case[1])
    if widgets[case[1]] and not widgets[case[1]]:IsVisible() then
        local p=widgets[case[1]]
        for i=1,12 do if not p then break end
            print('HIDDEN',i,p:GetName(),p:IsShown(),p.sectionId,p._msufSuiteArea,p._msuf2ExactTabView and p._msuf2ExactTabView.value)
            p=p:GetParent()
        end
    end
    assert(widgets[case[1]] and widgets[case[1]]:IsVisible(),'target is hidden: '..case[1])
    assert(panels[case[2]] and panels[case[2]]:IsVisible(),'correct tab did not become visible: '..case[2])
    assert(built[case[2]]==1,'tab was rebuilt: '..case[2])
end
for _,case in ipairs(cases) do Open(case); Open(case) end
do
    local record = assert(records["msufsuite.nameplates.hideHealthBarBorders"], "the border switch has no cold search route")
    local selected, anchored, exact = (M.Search._RoutingAPI or api).OpenSearchTarget(record.key,
        record.label, record.label, record.anchor, record.route, record.exactTarget)
    mw:RunTimers(1000)
    assert(selected and anchored and exact and widgets.hideHealthBarBorders:IsVisible(),
        "search did not reveal the border switch in General")
end
-- Direct preview handles retain the legacy enemy aliases.
assert(P.SelectNameplatesEnemyTab('appearance'))
assert(panels['enemy:bar']:IsVisible(),'legacy appearance did not select bar')
assert(P.SelectNameplatesEnemyTab('elements'))
assert(panels['enemy:markers']:IsVisible(),'legacy elements did not select markers')
assert(built['enemy:markers']==1,'preview alias rebuilt markers')
for key,value in pairs(saved) do assert(P.Get('nameplates',key)==value,'navigation changed setting '..key) end
for key,n in pairs(built) do assert(n==1,'one panel built multiple times '..key) end
assert(M.SelectPage('home'))
M.InvalidatePage('suite_nameplates')
built,widgets,panels={},{},{}
Open({'enemyOuterFrame','enemy:frame'})

-- Clicking a movable sample can reveal a settings section on the same page.
-- Reflow must preserve the selected handle and the X/Y edit that owns focus.
do
    M.SetFixedPreviewExpandedPreference(true)
    assert(M.SelectPage("suite_nameplates"))
    mw:RunTimers(1000)
    assert(not preview.compact, "fixture did not expand the nameplate preview")
    preview:ShowSample("enemy")
    local arrow = assert(preview.kit.entries["enemy.target"]).region
    local bar = preview.selection
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
        Click("Colors", "fonts_name_power_colors")
        assert(not widgets.enemyNameFormat and not widgets.friendlyNameFormat, "legacy disabled name rows are still built")
        assert(config.nameFormattingEnabled == before, "opening Fonts changed a Suite setting")
        assert(db.nameplates == nil or not db.nameplates.fontOverride, "opening Fonts enabled an override")

        for key, section in pairs({ enemyNameMaxChars = "fonts_name_shortening", friendlyNameColor = "fonts_name_power_colors" }) do
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
        assert(tails == 0, "Fonts appended separate Suite Nameplate blocks")
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
        assert(look.enabled and look.max == 5 and look.formatID == "CUT" and not look.customColor,
            "hidden legacy Suite switches override the ordinary Fonts scope")
        GP.ScopeSetOverride("nameplates", "fontOverride", false)
        local shared = formatter.Nameplates({})
        assert(shared.nameFormat == "ABBREV_CUT" and shared.nameShortenMax == 8 and shared.fontTextAlpha == .85,
            "scope reset does not return nameplates to Shared")
        assert(db.nameplates.nameFormat == "CUT", "turning off override destroyed stored local values")
    else
        OpenNameTextCard()
        assert(widgets.enemyNameFormat and widgets.friendlyNameFormat, "legacy host lost its name formatting controls")
        assert(not next(links), "legacy host received unusable Fonts links")
        assert(M.SelectPage("opt_fonts") ~= false)
        mw:RunTimers(1000)
        assert(tails == 0, "legacy host appended rejected Nameplate columns")
    end
end

print('PASS real host Nameplates cold tab/exact search/legacy preview parity '..flavor)
