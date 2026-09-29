-- Loads MSUF_Suite and MSUF_Suite_Options against a stand-in of Menu2's public
-- surface (the functions both MSUF builds share) and checks navigation
-- placement, page registration, control coverage of every catalog setting,
-- per-bar/per-window key mapping, enable gating and the locale merge.
local root = assert(arg[1], "repository root required")
-- The client's securecallfunction reports an error and returns nothing;
-- this stand-in lets errors raise, so a failing callback fails the test.
securecallfunction = function(callback, ...) return callback(...) end
local flavor = arg[2] or "Mainline"
assert(flavor == "Mainline" or flavor == "Forever", "the Suite supports Retail and WoW Forever only")
local function Frame(kind)
    local f = { kind = kind, shown = true, scripts = {}, points = {}, text = "", width = 100, height = 20, enabled = true }
    return setmetatable(f, { __index = function(_, key)
        if key == "mirror" or type(key) == "string" and key:sub(1, 1) == "_" then return nil end
        return function() end
    end })
end
local function Widget(kind)
    local w = Frame(kind)
    function w:SetShown(v) self.shown = v and true or false end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:IsShown() return self.shown end
    function w:SetText(t) self.text = t end
    function w:GetText() return self.text end
    function w:SetWidth(v) self.width = v end
    function w:GetWidth() return self.width end
    function w:SetHeight(v) self.height = v end
    function w:GetHeight() return self.height end
    function w:GetFrameLevel() return rawget(self, "level") or 1 end
    function w:SetFrameLevel(value) self.level = value end
    function w:CreateLine() return Widget("Line") end
    function w:SetSize(a, b) self.width, self.height = a, b end
    function w:ClearAllPoints() self.points = {} end
    function w:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function w:StartMoving() self.moving = true end
    function w:StopMovingOrSizing() self.moving = false end
    function w:EnableKeyboard(v) self.keyboardEnabled = v and true or false end
    function w:SetPropagateKeyboardInput(v) self.propagateKeyboard = v and true or false end
    function w:GetStringHeight() return 14 end
    -- An unloaded font measures 0; the preview then estimates the width.
    function w:GetStringWidth() return 0 end
    function w:CreateMaskTexture() return Widget("MaskTexture") end
    function w:GetEffectiveScale() return 1 end
    function w:SetScript(name, fn) self.scripts[name] = fn end
    function w:GetScript(name) return self.scripts[name] end
    function w:SetEnabled(v) self.enabled = v and true or false end
    function w:SetAlpha(v) self.alpha = v end
    function w:GetAlpha() return self.alpha end
    function w:SetActive(v) self.active = v and true or false end
    function w:SetAtlas(v) self.atlas = v end
    function w:SetTexture(v) self.texture = v end
    function w:CreateTexture() return Widget("Texture") end
    function w:CreateFontString() return Widget("FontString") end
    function w:SetValue(v) self.value = v end
    function w:SetMinMaxValues(lo, hi) self.minValue, self.maxValue = lo, hi end
    function w:SetStatusBarTexture(path)
        self.statusTexture = rawget(self, "statusTexture") or Widget("Texture")
        self.statusTexture:SetTexture(path)
    end
    function w:GetStatusBarTexture() return self.statusTexture end
    function w:SetStatusBarColor(...) self.barColor = { ... } end
    return w
end
CreateFrame = function(kind, _, parent) local widget = Widget(kind); widget.parent = parent; return widget end

-- WoW client stand-ins. The neutral ones: no class, zone, map position,
-- atlas, modifier key, keyboard focus or rotating minimap.
local neutralTooltip = setmetatable({}, { __index = function() return function() end end })
GameTooltip = neutralTooltip
-- Blizzard_EditMode loads at startup; until a step allows it, Edit Mode
-- cannot be entered.
local lockedEditMode = { CanEnterEditMode = function() return false end }
EditModeManagerFrame = lockedEditMode
UnitClass = function() return nil end
UnitIsPlayer = function() return false end
GetZoneText = function() return "" end
GetGameTime = function() return 12, 34 end
GetCVarBool = function() return false end
IsInInstance = function() return false, "none" end
C_Texture = { GetAtlasInfo = function() return nil end }
C_Map = { GetBestMapForUnit = function() return nil end }
IsShiftKeyDown, IsControlKeyDown = function() return false end, function() return false end
GetCurrentKeyBoardFocus = function() return nil end
time = os.time
TimeUtil = { BetterDate = function(format) return format end }
SlashCmdList = {}
IsLoggedIn = function() return false end
InCombatLockdown = function() return false end
LoggingCombat = function() return false end
GetInstanceInfo = function() return "outside", "none", 0 end
GetLocale = function() return "deDE" end
-- The specialization is not known yet at this point of the login.
C_SpecializationInfo = { GetSpecialization = function() return nil end }
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
-- Forever loads the Mainline TOCs; Blizzard's camelot marker tells it apart.
GameEvent = flavor == "Forever" and { RegisterCamelotEvents = function() end } or nil
GameFontHighlightSmall = {}
local loaded = { MidnightSimpleUnitFrames = true, MidnightSimpleUnitFrames_Options = true }
local optionsNS
local function LoadTOC(addon, ns)
    local toc = assert(io.open(root .. "/" .. addon .. "/" .. addon .. "_Mainline.toc"))
    for line in toc:lines() do
        line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            assert(loadfile(root .. "/" .. addon .. "/" .. line:gsub("\\", "/")))(addon, ns)
        end
    end
    toc:close()
end
-- No combinedBags setting: the Bags module stays unavailable in this fixture.
C_CVar = { GetCVar = function() return nil end }
-- Every installed AddOn is enabled for every character unless a step says otherwise.
local function AllEnabled() return 2 end
UnitGUID = function() return "Player-Test" end
C_AddOns = {
    IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
    DoesAddOnExist = function(name) return name ~= "MapkoSkin" end,
    GetAddOnEnableState = AllEnabled,
    LoadAddOn = function(name)
        if name == "MSUF_Suite_Options" then
            loaded[name] = true
            optionsNS = {}
            LoadTOC(name, optionsNS)
            return true
        end
        return false, "MISSING"
    end,
}

-- MSUF host (Main build shape: no MSUF.Client) with its locale table.
local L = setmetatable({ ["Enable module"] = "MSUF-eigene Übersetzung" }, { __index = function(_, k) return k end })
MSUF_NS = { L = L, GetEffectiveLocale = function() return "deDE" end }
assert(loadfile(root .. "/../MidnightSimpleUnitFrames-Classic/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_BossTargetIndicator.lua"))("MidnightSimpleUnitFrames", MSUF_NS)

-- Menu2 public surface
local M, W, T = {}, {}, {}
MSUF2 = M
local historyProvider, historyWrites = nil, 0
M.RegisterHistoryProvider = function(_, capture, restore)
    if type(capture) ~= "function" or type(restore) ~= "function" then return false end
    historyProvider = { capture = capture, restore = restore }
    return true
end
local arrowBinding
M.SetPreviewArrowBindings = function(box, enabled, spec)
    arrowBinding = { box = box, enabled = enabled == true, spec = spec }
    return true
end
M.RunWithHistory = function(_, _, fn) historyWrites = historyWrites + 1; return fn() end
M.Widgets, M.Theme = W, T
M.PreviewSelectionBar = {
    Create = function(box, deps)
        box.selectionDeps = deps
        local bar = Widget("SelectionBar")
        bar:SetSize(785, 24)
        bar.axisY, bar.label = Widget("AxisY"), Widget("SelectionLabel")
        bar.axisY.plusButton = Widget("YPlus")
        bar.openButton, bar.resetButton = Widget("OpenSettings"), Widget("Reset")
        bar.resetButton.SetPoint = function(self, ...) self.lastPoint = { ... } end
        box.selectionBar = bar
        return bar
    end,
    Refresh = function(box)
        local handle = box._selectedHandle
        if handle then
            box.selectionX, box.selectionY = box.selectionDeps.ReadOffsets(box, handle)
        else
            box.selectionX, box.selectionY = nil, nil
        end
    end,
    SetShown = function(box, shown)
        if box.selectionBar then box.selectionBar:SetShown(shown) end
    end,
}
M.ShouldExpandFixedPreview = function() return true end
M.pages, M.bound = {}, {}
M.Tr = function(text) return L[text] end
T.colors = { muted = {}, text = {}, dim = {} }
T.navIconGrid = { home = { 0, 0 }, gameplay = { 7, 1 } }
T.navIconColors = { home = { 1 }, gameplay = { 2 }, profiles = { 3 } }
T.Font = function(parent, template, text) local fs = Widget("FontString"); fs.text = text; return fs end
T.Button = function(parent, text) local b = Widget("Button"); b.text = text; return b end
T.Panel = function() return Widget("Panel") end
T.CenterButtonLabel = function() end
M.navItems = {
    { key = "home", label = "Dashboard" },
    { title = "Frames", id = "frames" }, { key = "uf_player", label = "Unitframes", group = "frames" },
    { title = "Combat", id = "combat" }, { title = "Interface", id = "interface" },
    { title = "Style", id = "style" }, { key = "opt_colors", label = "Colors", group = "style" },
    { title = "General", id = "general" }, { key = "gameplay", label = "Gameplay", group = "general" },
    { key = "opt_misc", label = "Miscellaneous", group = "general" },
    { key = "profiles", label = "Profiles", group = "general" },
}
-- MSUF's shared Copy To popup; the stub keeps the page's options for the checks below.
local copyPopups = {}
M.UnitSectionsShared = { MakeScopeCopyPopup = function(button, opts)
    local api = { button = button, opts = opts }
    function api.Show() api.shown = true end
    function api.Hide() api.shown = false end
    function api.Refresh() api.refreshed = (api.refreshed or 0) + 1 end
    copyPopups[#copyPopups + 1] = api
    return api
end }
M.navPrimaryForKey = { home = "home", profiles = "profiles" }
M.ALIASES = { meter = "opt_bars" }
M.GlobalPage = { FontValues = function() return { { value = "Expressway", text = "Expressway" } } end }
M.StatusBarTextureItems = function(follow) return { { value = "", text = follow }, { value = "Flat", text = "Flat" } } end
M.RegisterPage = function(key, spec) M.pages[key] = spec end
M.ControlMeta = function(page, domain, path, classification, exact)
    local meta = { controlId = "menu2." .. page .. "." .. path, classification = classification }
    for k, v in pairs(exact or {}) do meta[k] = v end
    return meta
end
local previewControls, registeredControls = {}, {}
M.RegisterControlMetadata = function(widget, meta)
    if meta and meta.controlId then registeredControls[meta.controlId] = widget end
    if meta and meta.controlId and meta.controlId:find("%.preview%.") then previewControls[meta.controlId] = widget end
end
M.SelectPage = function(key) M.selectedPage = key end
local current
M.TrackRefresh = function(ctx, fn) ctx.refreshers[#ctx.refreshers + 1] = fn end
M.RequestRefresh = function()
    if current then for _, fn in ipairs(current.refreshers) do fn() end end
end
local function Bind(ctx, widget, get, set, meta, label)
    widget.get, widget.set, widget.meta, widget.label = get, set, meta, label
    ctx.widgets[#ctx.widgets + 1] = widget
    return widget
end
M.BindSwitchAt = function(ctx, parent, label, x, y, w, get, set, meta) return Bind(ctx, Widget("Switch"), get, set, meta, label) end
M.BindBoolWidget = function(ctx, widget, get, set, meta) return Bind(ctx, widget, get, set, meta, widget.label) end
M.BindDropdownAt = function(ctx, parent, label, x, y, values, w, get, set, meta) return Bind(ctx, Widget("Dropdown"), get, set, meta, label) end
M.BindTextInputAt = function(ctx, parent, label, x, y, w, get, set, blur, meta) return Bind(ctx, Widget("EditBox"), get, set, meta, label) end
M.BindDropdownWidget = function(ctx, widget, get, set, meta) return Bind(ctx, widget, get, set, meta, widget.label) end
W.Dropdown = function(parent, label) local d = Widget("Dropdown"); d.label = label; return d end
W.MoveWidget = function() end
W.SegmentTabs = function(ctx, parent, opts)
    local segment = Widget("SegmentTabs")
    local function Refresh()
        local tab = opts.get and opts.get() or opts.defaultTab
        for key, panel in pairs(opts.frames) do panel:SetShown(key == tab) end
        segment:SetValue(tab)
        if opts.afterRefresh then opts.afterRefresh(tab) end
    end
    function segment:Choose(tab) opts.set(tab); Refresh() end
    ctx.tabControls = ctx.tabControls or {}
    ctx.tabControls[#ctx.tabControls + 1] = { segment = segment, frames = opts.frames }
    M.TrackRefresh(ctx, Refresh)
    return segment, Refresh, function() return opts.get() end, function(tab) segment:Choose(tab) end
end
W.ControlCard = function() return Widget("Card") end
W.SectionSwitch = function(section, label)
    local widget = Widget("Switch")
    widget.label = label
    section.headerSwitch = widget
    return widget
end
W.AttachContextColorShortcut = function(section, opts)
    local shortcut = Widget("ColorShortcut")
    shortcut.options = opts
    section.colorShortcut = shortcut
    return shortcut
end
W.SetControlEnabled = function(widget, enabled) widget.enabled = enabled and true or false end
W.SettingsRows = function(ctx, parent, spec)
    local controls, y = {}, spec.y
    for _, row in ipairs(spec.rows) do
        local widget = Bind(ctx, Widget(row.kind), row.get, row.set, row, row.label)
        widget.rowKind, widget.row = row.kind, row
        controls[row.id] = widget
        y = y - 40
    end
    return { controls = controls, bottomY = y }
end
W.RoleButton = function(_, text, role) local button = Widget("RoleButton"); button.text, button.role = text, role; return button end
W.PageBuilder = function(ctx)
    local b = { width = ctx.width, y = -12 }
    function b:Header() ctx.headers = (ctx.headers or 0) + 1 end
    function b:CollapsibleSection(id, title)
        local body = Widget("Section")
        body.sectionId, body.title = id, title
        body._msuf2Width = ctx.width
        body._msuf2CollapsibleEntry = {}
        ctx.sections[#ctx.sections + 1] = body
        ctx.pageItems[#ctx.pageItems + 1] = id
        return body
    end
    function b:FinishSection(body) body.finished = true end
    return b
end
W.FixedPreviewSection = function(ctx, b, spec)
    local section, toolbar, record = Widget("FixedPreview"), Widget("Toolbar"), {}
    section._msuf2Width = ctx.width
    section.title = Widget("FontString")
    ctx.fixedPreview = { section = section, toolbar = toolbar, record = record }
    ctx.pageItems[#ctx.pageItems + 1] = "fixed-preview"
    return section, toolbar, record
end
W.AttachFixedPreviewExpander = function(section, toolbar, box, opts)
    local expander = { section = section, toolbar = toolbar, box = box, opts = opts }
    function expander:Open()
        self.expanded = true
        box:ApplyCompactPreviewPresentation(false)
        return true
    end
    function expander:Close()
        self.expanded = false
        box:ApplyCompactPreviewPresentation(true)
        return true
    end
    section.expander = expander
    return expander
end

-- Capabilities the catalogs probe, so every module counts as available.
SecureHandlerExecute, SecureHandlerSetFrameRef, RegisterStateDriver =
    function() end, function() end, function() end
C_DamageMeter = { GetCombatSessionFromType = function() end }
Enum = { DamageMeterType = { DamageDone = 0 } }
Minimap = { SetMaskTexture = function() end }

-- Boot the suite core as the client would, then attach the menu.
LoadTOC("MSUF_Suite", {})
local Suite = assert(MSUFSuite)
local S = Suite.Suite
Suite.Database.Initialize(nil)
S.Start()
local globalsBefore = {}
for k in pairs(_G) do globalsBefore[k] = true end
assert(Suite.Menu.Attach(), "suite menu did not attach")
assert(Suite.Menu.attached == true)
assert(historyProvider and Suite.Options.BuildColorsCategory, "Suite did not register MSUF history and colors")
for k in pairs(_G) do assert(globalsBefore[k], "options addon created global " .. tostring(k)) end
if flavor == "Forever" then
    local plates = S.Config("nameplates")
    assert(plates.enemyLevelEnabled == true, "Forever Jundies default omitted enemy levels")
    plates.enabled, plates.look = false, 2
    assert(optionsNS.Set("nameplates", "look", 1)
        and plates.enabled and plates.look == 1 and plates.enemyLevelEnabled,
        "selecting Jundies on Forever did not enable nameplates and levels")
    assert(M.PageHasReset("suite_dataTexts") and M.PageHasReset("suite_skin"),
        "Forever Suite pages lack Reset page")
    local rule = S.catalog.dataTexts.rules.bar1X
    assert(rule and optionsNS and optionsNS.ResetRules)
    assert(S.Set("dataTexts", "bar1X", 47))
    assert(optionsNS.ResetRules("dataTexts", { rule })
        and S.Config("dataTexts").bar1X == rule.default,
        "Forever section reset missed its setting")
    assert(S.Set("dataTexts", "bar1X", 47))
    assert(M.ResetPageToDefaults("suite_dataTexts")
        and S.Config("dataTexts").bar1X == rule.default,
        "Forever Reset page missed its module")
    print("Suite options reset: Forever page and accordion contracts passed")
    return
end

-- Navigation: suite pages join MSUF's groups by id and MSUF rows keep their places.
local expected = { "suite_actionbars", "suite_minimap", "suite_damageMeter", "suite_bags", "suite_dataTexts", "suite_qualityOfLife", "suite_hud", "suite_buffReminders", "suite_chat", "suite_nameplates", "suite_cooldownManager", "suite_skin" }
local function NavShape(items)
    local out = {}
    for _, item in ipairs(items) do
        out[#out + 1] = item.key and (item.key .. "@" .. tostring(item.group)) or ("#" .. tostring(item.id))
    end
    return table.concat(out, " ")
end
local COMBAT_ROWS = "#combat suite_nameplates@combat suite_cooldownManager@combat suite_buffReminders@combat suite_hud@combat"
local INTERFACE_ROWS = "#interface suite_actionbars@interface suite_minimap@interface suite_damageMeter@interface"
    .. " suite_bags@interface suite_chat@interface suite_dataTexts@interface"
local hostShape = "home@nil #frames uf_player@frames " .. COMBAT_ROWS .. " " .. INTERFACE_ROWS
    .. " #style opt_colors@style suite_skin@style"
    .. " #general gameplay@general suite_modules@general suite_qualityOfLife@general opt_misc@general profiles@general"
assert(NavShape(M.navItems) == hostShape, "suite navigation: " .. NavShape(M.navItems))
for _, key in ipairs(expected) do
    assert(M.pages[key], "page not registered: " .. key)
    assert(M.navPrimaryForKey[key] == key)
    assert(T.navIconGrid[key] and T.navIconColors[key], "nav icon missing: " .. key)
end
assert(M.pages.suite_skin, "Suite-owned skinning page is missing")
local rows = {}
for _, item in ipairs(M.navItems) do if item.key then rows[item.key] = item end end
assert(Suite.SuiteCatalog.qol.addon == "MSUF_Suite_QualityOfLife"
    and Suite.SuiteCatalog.quests.addon == Suite.SuiteCatalog.qol.addon
    and Suite.SuiteCatalog.loot.addon == Suite.SuiteCatalog.qol.addon,
    "Quality of Life should have one Blizzard AddOn checkbox")
assert(Suite.SuiteCatalog.dataTexts.addon == "MSUF_Suite_DataTexts",
    "DataTexts should have its own Blizzard AddOn checkbox")
C_AddOns.GetAddOnEnableState = function(name, guid)
    assert(guid == "Player-Test", "AddOn enable state must use the current character")
    return name == "MSUF_Suite_ActionBars" and 0 or 1
end
assert(rows.suite_actionbars.availability() == false
    and rows.suite_minimap.availability() == true
    and rows.suite_qualityOfLife.availability() == true,
    "Suite navigation does not reflect Blizzard's disabled AddOn state")
C_AddOns.GetAddOnEnableState = AllEnabled
assert(M.ALIASES.meter == "opt_bars", "suite overrode an MSUF alias")
assert(M.ALIASES.damage_meter == "suite_damageMeter" and M.ALIASES.minimap == "suite_minimap")
assert(M.ALIASES.chat == "suite_chat", "chat page alias is missing")
-- Attaching twice must not duplicate rows.
local function Reattach()
    Suite.Menu.attached = false
    assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Register.lua"))("MSUF_Suite_Options", {
        Suite = Suite, M = M, T = T, pages = optionsNS.pages, Tr = M.Tr, host = MSUF_NS, Refresh = function() end,
        BuildColorsCategory = optionsNS.BuildColorsCategory, ApplyForeverStyle = optionsNS.ApplyForeverStyle,
        ForgetAvailability = optionsNS.ForgetAvailability,
    })
end
Reattach()
assert(NavShape(M.navItems) == hostShape, "suite navigation inserted twice: " .. NavShape(M.navItems))
-- A host without those groups (Retail MSUF) keeps its own: Skinning joins
-- Appearance, Quality of Life joins Features after Gameplay, and Combat and
-- Interface are created in front of Features.
local hostItems = M.navItems
M.navItems = {
    { key = "home", label = "Dashboard" },
    { title = "Frames", id = "frames" }, { key = "uf_player", label = "Unitframes", group = "frames" },
    { title = "Appearance", id = "appearance" }, { key = "opt_bars", label = "Bars", group = "appearance" },
    { key = "opt_misc", label = "Miscellaneous", group = "appearance" },
    { title = "Features", id = "features" }, { key = "classpower", label = "Class Resources", group = "features" },
    { key = "gameplay", label = "Gameplay", group = "features" },
    { key = "profiles", label = "Profiles", group = "features" },
}
Reattach()
local legacyShape = "home@nil #frames uf_player@frames"
    .. " #appearance opt_bars@appearance opt_misc@appearance suite_skin@appearance "
    .. COMBAT_ROWS .. " " .. INTERFACE_ROWS
    .. " #features classpower@features gameplay@features suite_modules@features suite_qualityOfLife@features profiles@features"
assert(NavShape(M.navItems) == legacyShape, "suite navigation on a legacy host: " .. NavShape(M.navItems))
M.navItems = hostItems

-- The suite ships English pages and never writes into MSUF's locale table.
assert(rawget(L, "Interface") == nil, "suite wrote a translation into MSUF's locale table")
assert(rawget(L, "Enable module") == "MSUF-eigene Übersetzung", "suite changed an MSUF translation")

-- Build every page and collect the keys its controls read.
local contexts = {}
for _, key in ipairs(expected) do
    local ctx = { key = key, width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
    current = ctx
    M.pages[key].build(ctx)
    if ctx.fixedPreview and ctx.fixedPreview.record.onActivate then ctx.fixedPreview.record.onActivate() end
    for _, fn in ipairs(ctx.refreshers) do fn() end
    for _, section in ipairs(ctx.sections) do assert(section.finished, key .. " section not finished: " .. section.sectionId) end
    assert(not ctx.headers, key .. " still has a redundant page header")
    contexts[key] = ctx
end
do
    local plates = S.Config("nameplates")
    local enabled, look = plates.enabled, plates.look
    plates.enabled, plates.look = false, 2
    assert(optionsNS.Set("nameplates", "look", 1)
        and plates.enabled and plates.look == 1,
        "choosing Jundies left an older Forever nameplate module disabled")
    plates.enabled, plates.look = enabled, look
end
-- A page refresh asks for module availability once per module, not once per
-- control; the next refresh asks again.
do
    local availability, calls = S.Availability, {}
    S.Availability = function(id)
        calls[id] = (calls[id] or 0) + 1
        return availability(id)
    end
    current = contexts.suite_damageMeter
    M.RequestRefresh()
    assert(calls.damageMeter == 1, "one Damage Meter refresh asked its availability "
        .. tostring(calls.damageMeter) .. " times")
    M.RequestRefresh()
    assert(calls.damageMeter == 2, "a second Damage Meter refresh asked its availability "
        .. tostring(calls.damageMeter - 1) .. " times")
    S.Availability = availability
end
(function()
    assert(S.Config("nameplates").look == 1
        and S.Config("nameplates").enemyEliteMarker == false
        and S.Config("nameplates").enemyQuestMarker == true
        and S.Config("nameplates").enemyNeutralEnabled == true
        and S.Config("nameplates").enemyNeutralColor == "e5db00"
        and S.Config("nameplates").enemyTextOutline == 4,
        "fresh Jundies nameplates must match DEFAULT neutral color and SLUG without extra elite markers")
    local function Control(key) return assert(registeredControls["menu2.suite_nameplates.nameplates.preview." .. key], key) end
    local name, cast, health = Control("enemy.Name"), Control("enemy.Cast"), Control("enemy.Health")
    local ui = name.previewUI
    assert(ui.previewRole == nil, "nameplate preview must start with the saved enemy type")
    local plates = S.Config("nameplates")
    if flavor == "Forever" then
        assert(plates.levelAppearance == 1,
            "Forever Jundies did not default to the plain level number")
    end
    local originalSize = plates.nativeSize
    plates.nativeSize = 2
    ui:Paint()
    local smallWidth = health.width
    plates.nativeSize = 6
    ui:Paint()
    assert(health.width > smallWidth, "Blizzard plate size did not scale preview health bars")
    plates.nativeSize = originalSize
    ui:Paint()
    local nativeWidth, nativeHeight, castWidth = health.width, health.height, cast.width
    plates.enemyHealthWidthDelta, plates.enemyHealthHeightDelta = 73, 7
    ui:Paint()
    assert(health.width == nativeWidth + 73 and health.height == nativeHeight + 7
        and cast.width == castWidth,
        "enemy health dimensions diverged from the native preview geometry")
    plates.enemyHealthWidthDelta, plates.enemyHealthHeightDelta = 0, 0
    ui:Paint()
    local debuffs = Control("enemy.Auras")
    local buffs, control = Control("enemy.Buffs"), Control("enemy.ControlAura")
    local debuffBaseY = debuffs.points[1][5]
    local buffBaseX, controlBaseY = buffs.points[1][4], control.points[1][5]
    assert(debuffs.points[1][1] == "BOTTOMLEFT" and debuffs.points[1][2] == health
        and debuffs.points[1][3] == "TOPLEFT" and debuffs.points[1][4] == 0,
        "debuff preview must start at Blizzard's health container left edge")
    assert(buffs.points[1][1] == "RIGHT" and buffBaseX == -5
        and control.points[1][1] == "LEFT" and control.points[1][2] == health,
        "buff and control preview lost their native side anchors")
    plates.enemyAurasOffsetX, plates.enemyAurasOffsetY = -14, 9
    plates.enemyBuffsOffsetX, plates.enemyControlAuraOffsetY = 13, -7
    plates.enemyNameOffsetX, plates.enemyNameOffsetY = 25, -8
    ui:Paint()
    assert(debuffs.points[1][4] == -14 and debuffs.points[1][5] == debuffBaseY + 9
        and buffs.points[1][4] == buffBaseX + 13
        and control.points[1][5] == controlBaseY - 7,
        "aura preview positions must follow their own saved offsets")
    plates.enemyAurasOffsetX, plates.enemyAurasOffsetY = 0, 0
    plates.enemyBuffsOffsetX, plates.enemyControlAuraOffsetY = 0, 0
    plates.enemyNameOffsetX, plates.enemyNameOffsetY = 0, 0
    ui:Paint()
    if flavor == "Forever" then
        local level = Control("enemy.Level")
        assert(health.width == 133 and cast.width == 166 and cast.height == 6 and level.width == 24,
            "Forever preview ignored Jundies' plain number or Camelot bar width")
        assert(level:IsShown() and level.points[1][1] == "RIGHT"
            and level.points[1][2] == health,
            "Forever Jundies preview did not place the plain number left of health")
        plates.levelAppearance = 2
        ui:Paint()
        assert(level.width == 28 and level.points[1][1] == "LEFT"
            and level.points[1][2] == health,
            "Forever Blizzard badge option did not move the preview level right")
        plates.levelAppearance = 1
        ui:Paint()
        local oldSetup = NamePlateSetupOptions
        NamePlateSetupOptions = { useClassicHealthBar = true, horizontalScale = 1,
            verticalScale = 1, classificationScale = 1, insetWidth = 12,
            playerLevelDiffWidth = 28 }
        ui:Paint()
        assert(health.width == 70.75 and cast.width == 103.75
            and Suite.NameplateStyle.ClassicNativePlate(2),
            "Forever preview ignored the effective Classic layout")
        assert(debuffs.points[1][4] == -3.5,
            "Classic debuffs must start at the container edge, left of the inset bar")
        NamePlateSetupOptions = oldSetup
        ui:Paint()
    end
    for _, prefix in ipairs({ "enemy", "friendly" }) do
        for _, element in ipairs(Suite.NameplateStyle.Elements) do
            local handle = Control(prefix .. "." .. element.key)
            assert(handle.keyX == prefix .. element.key .. "OffsetX"
                and handle.keyY == prefix .. element.key .. "OffsetY"
                and handle.scripts.OnMouseDown and handle.scripts.OnMouseUp
                and handle.scripts.OnKeyDown,
                "nameplate element has no interactive drag or keyboard editor: " .. prefix .. "." .. element.key)
        end
    end
    assert(cast._npProgress.kind == "StatusBar" and cast._npProgress.minValue == 0
        and cast._npProgress.maxValue == 100 and cast._npProgress.value == 65
        and cast._npProgress:GetStatusBarTexture().texture,
        "cast preview must have an actual Blizzard StatusBar fill")
    assert(cast._npProgress:GetStatusBarTexture().texture == "ui-castingbar-filling-standard",
        "cast preview must show Blizzard's cast appearance")
    for _, element in ipairs({ "Classification", "CastIcon", "CastShield", "CastTarget" }) do
        assert(Control("enemy." .. element).scripts.OnMouseDown, "missing native icon drag handle: " .. element)
    end
    assert(S.catalog.nameplates.rules.friendlyNamesOnly.section == "friendly"
        and S.catalog.nameplates.rules.friendlyGroupOnly == nil,
        "friendly player display must be one control in Friendly appearance")
    S.Set("nameplates", "friendlyNamesOnly", 3)
    assert(ui.sampleCells.enemy:IsShown() and not ui.sampleCells.friendly:IsShown(),
        "preview must show only one plate at a time")
    Control("plateKind").scripts.OnClick()
    assert(not ui.sampleCells.enemy:IsShown() and ui.sampleCells.friendly:IsShown(),
        "friendly sample did not replace the enemy sample")
    ui:Paint()
    assert(Control("friendly.Name"):IsShown())
    local groupButton = Control("friendlyGroup")
    groupButton.scripts.OnClick(groupButton)
    assert(not Control("friendly.Name"):IsShown(), "outsider name survived group-only preview")
    groupButton.scripts.OnClick(groupButton)
    assert(Control("friendly.Name"):IsShown(), "group member name missing in preview")
    S.Set("nameplates", "friendlyNamesOnly", 2)
    assert(ui.body.selectionDeps and ui.body.selectionBar:IsShown()
        and name.scripts.OnMouseDown and cast.scripts.OnMouseDown
        and Control("friendly.Name").scripts.OnDragStart,
        "nameplate preview must expose the UF/GF selection strip and direct drag handles")
    ui:Select(health)
    assert(ui.sizeFields[1].frame:IsShown() and ui.sizeFields[2].frame:IsShown()
        and ui.sizeFields[1].caption.text == "W" and ui.sizeFields[2].caption.text == "H"
        and tonumber(ui.sizeFields[1].edit.text) == nativeWidth
        and tonumber(ui.sizeFields[2].edit.text) == nativeHeight
        and ui.body.selectionBar.height == 24 and ui.body.selectionBar.openButton:IsShown(),
        "health selection did not reveal width and height beside X/Y")
    local selectionBar = ui.body.selectionBar
    selectionBar:SetWidth(640)
    selectionBar.scripts.OnSizeChanged()
    assert(selectionBar.label.width == 108 and not selectionBar.openButton:IsShown()
        and selectionBar.resetButton.lastPoint[2] == selectionBar,
        "narrow selection bar did not make room for inline width and height")
    selectionBar:SetWidth(785)
    selectionBar.scripts.OnSizeChanged()
    assert(selectionBar.label.width == 132 and selectionBar.openButton:IsShown()
        and selectionBar.resetButton.lastPoint[2] == selectionBar.openButton,
        "wide selection bar did not restore Open settings")
    ui.sizeFields[1].plus.scripts.OnClick()
    ui.sizeFields[2].edit:SetText(tostring(nativeHeight + 5))
    ui.sizeFields[2].edit.scripts.OnEnterPressed(ui.sizeFields[2].edit)
    assert(plates.enemyHealthWidthDelta == 1 and plates.enemyHealthHeightDelta == 5
        and health.width == nativeWidth + 1 and health.height == nativeHeight + 5,
        "selected health size controls did not change runtime settings and preview")
    ui.body.selectionDeps.ResetOffsets(ui.body, health)
    assert(plates.enemyHealthWidthDelta == 0 and plates.enemyHealthHeightDelta == 0,
        "selected health reset did not restore its dimensions")
    S.Set("nameplates", "friendlyNamesOnly", 4)
    ui:Paint()
    local friendlyHealth = Control("friendly.Health")
    local friendlyNativeWidth, friendlyNativeHeight = friendlyHealth.width, friendlyHealth.height
    ui:Select(friendlyHealth)
    assert(ui.sizeFields[1].frame:IsShown() and ui.sizeFields[2].frame:IsShown()
        and tonumber(ui.sizeFields[1].edit.text) == friendlyNativeWidth
        and tonumber(ui.sizeFields[2].edit.text) == friendlyNativeHeight,
        "friendly health selection did not expose its native dimensions")
    ui.sizeFields[1].plus.scripts.OnClick()
    assert(plates.friendlyHealthWidthDelta == 1 and friendlyHealth.width == friendlyNativeWidth + 1,
        "friendly health width did not update its preview and runtime setting: "
            .. tostring(plates.friendlyHealthWidthDelta) .. "/" .. tostring(friendlyHealth.width)
            .. "/" .. tostring(friendlyNativeWidth) .. "/" .. tostring(friendlyHealth:IsShown()))
    ui.body.selectionDeps.ResetOffsets(ui.body, friendlyHealth)
    assert(plates.friendlyHealthWidthDelta == 0, "friendly health size reset failed")
    S.Set("nameplates", "friendlyNamesOnly", 2)
    ui:Select(name)
    assert(ui.sizeFields[1].frame:IsShown() and not ui.sizeFields[2].frame:IsShown()
        and ui.sizeFields[1].caption.text == "Font",
        "name selection showed an unsupported independent width or height")
    ui:Select(cast)
    assert(not ui.sizeFields[1].frame:IsShown() and not ui.sizeFields[2].frame:IsShown(),
        "native cast geometry was advertised as independently resizable")
    ui:Select(Control("enemy.Auras"))
    assert(ui.sizeFields[1].caption.text == "Size %" and not ui.sizeFields[2].frame:IsShown(),
        "Blizzard aura scale did not appear as a single uniform size")
    ui.sizeFields[1].plus.scripts.OnClick()
    assert(plates.auraScaleMode == 2 and plates.auraScalePercent == 110,
        "aura size control did not activate the shared Blizzard scale")
    ui.body.selectionDeps.ResetOffsets(ui.body, Control("enemy.Auras"))
    assert(plates.auraScalePercent == 100 and plates.auraScaleMode == 1,
        "aura reset did not restore the Blizzard size mode")
    ui:Select(nil)
    Control("plateKind").scripts.OnClick()
    local elite = Control("enemy.Classification")
    local ex, ey = 10, 20
    GetCursorPosition = function() return ex, ey end
    elite.scripts.OnMouseDown(elite, "LeftButton")
    ex, ey = 30, 11
    elite.scripts.OnMouseUp(elite, "LeftButton")
    assert(S.Config("nameplates").enemyClassificationOffsetX == 20
        and S.Config("nameplates").enemyClassificationOffsetY == -9, "native elite icon drag did not save")
    ui.body.selectionDeps.ResetOffsets(ui.body, elite)
    assert(S.Config("nameplates").enemyClassificationOffsetX == 0)
    local cx, cy = 100, 200
    GetCursorPosition = function() return cx, cy end
    name.GetEffectiveScale = function() return 0.75 end
    name.scripts.OnMouseDown(name, "LeftButton")
    assert(ui.body._selectedHandle == name and name.moving, "click/drag did not select the element")
    cx, cy = 115, 194
    name.scripts.OnMouseUp(name, "LeftButton")
    assert(S.Config("nameplates").enemyNameOffsetX == 20 and S.Config("nameplates").enemyNameOffsetY == -8,
        "scaled mouse drag did not persist name offsets")
    local historyBefore = historyWrites
    name.scripts.OnMouseDown(name, "LeftButton")
    name.scripts.OnMouseUp(name, "LeftButton")
    assert(historyWrites == historyBefore, "selection-only click wrote a profile/history entry")
    name.scripts.OnKeyDown(name, "RIGHT")
    assert(S.Config("nameplates").enemyNameOffsetX == 21, "arrow key did not nudge selected name")
    ui.body.selectionDeps.ResetOffsets(ui.body, name)
    assert(S.Config("nameplates").enemyNameOffsetX == 0, "selected-element reset failed")
    local previousSampleKind, previousPersonal = ui.sampleKind, ui.personal
    ui.sampleKind, ui.personal = "enemy", false
    ui:Paint()
    local target, targetLayer = Control("enemy.target"), Control("layer.target")
    assert(plates.enemyTargetMarker and target:IsShown()
        and target._npSettingKey == "enemyTargetMarker",
        "target arrows did not start from the saved nameplate setting")
    targetLayer.scripts.OnClick(targetLayer, "LeftButton")
    assert(plates.enemyTargetMarker == false and not target:IsShown()
        and not ui:LayerActive("target"),
        "target arrow preview toggle did not save the live setting")
    local savedRoot = assert(Suite.Database.Prepare(Suite.CopyValue(Suite.RootDB), nil))
    S.Normalize(savedRoot.profiles[savedRoot.activeProfile])
    assert(savedRoot.profiles[savedRoot.activeProfile].suite.modules.nameplates.enemyTargetMarker == false,
        "target arrow setting was lost while preparing a reload")
    targetLayer.scripts.OnClick(targetLayer, "LeftButton")
    assert(plates.enemyTargetMarker and target:IsShown() and ui:LayerActive("target"),
        "re-enabled target arrows did not return in the preview")
    target.scripts.OnMouseDown(target, "LeftButton")
    cx = cx + 20
    target.scripts.OnMouseUp(target, "LeftButton")
    assert(plates.enemyTargetOffsetX == 20, "target arrow drag did not save its position")
    savedRoot = assert(Suite.Database.Prepare(Suite.CopyValue(Suite.RootDB), nil))
    S.Normalize(savedRoot.profiles[savedRoot.activeProfile])
    assert(savedRoot.profiles[savedRoot.activeProfile].suite.modules.nameplates.enemyTargetOffsetX == 20,
        "target arrow position was lost while preparing a reload")
    ui.body.selectionDeps.ResetOffsets(ui.body, target)
    assert(plates.enemyTargetOffsetX == 0, "target arrow reset did not restore its position")
    ui.sampleKind, ui.personal = previousSampleKind, previousPersonal
    ui:Paint()
    cast.scripts.OnMouseDown(cast, "LeftButton")
    cx = cx + 12
    cast.scripts.OnKeyDown(cast, "ESCAPE")
    cast.scripts.OnMouseUp(cast, "LeftButton")
    assert(S.Config("nameplates").enemyCastOffsetX == 0 and not ui.dragging,
        "Escape must cancel an unfinished drag")
    local oldZoom = ui.zoom
    ui.canvas.scripts.OnMouseWheel(ui.canvas, 1)
    assert(ui.zoom > oldZoom, "preview wheel must zoom the canvas")
    ui.canvas.scripts.OnMouseDown(ui.canvas, "LeftButton")
    cx = cx + 20
    ui.canvas.scripts.OnMouseUp(ui.canvas, "LeftButton")
    assert(ui.panX == 20 and S.Config("nameplates").enemyCastOffsetX == 0,
        "background pan must move only the viewport")
    Control("context").scripts.OnClick()
    assert(ui.inDungeon, "outdoor/dungeon sample control failed")
    for role = 2, 12 do
        Control("role").scripts.OnClick()
        assert(S.Config("nameplates").enemyPreviewRole == role, "preview did not reach every EQoL role")
    end
    Control("role").scripts.OnClick()
    assert(S.Config("nameplates").enemyPreviewRole == 1)
    local friendly = Control("friendly.Name")
    Control("plateKind").scripts.OnClick()
    friendly.GetEffectiveScale = function() return 1 end
    friendly.scripts.OnMouseDown(friendly, "LeftButton")
    cx = cx + 15
    friendly.scripts.OnMouseUp(friendly, "LeftButton")
    assert(S.Config("nameplates").friendlyNameOffsetX == 15, "friendly preview was not directly draggable")
    Control("friendlyType").scripts.OnClick()
    assert(Control("friendly.Classification"):IsShown(),
        "friendly elite NPC sample must expose Blizzard's classification handle")
    for _, kind in ipairs({ "Elite", "Quest" }) do
        S.Set("nameplates", "friendly" .. kind .. "Marker", true)
        ui:Paint()
        local handle = Control("friendly." .. kind:lower())
        assert(handle:IsShown(), "friendly marker missing from preview")
        local before = S.Config("nameplates")["friendly" .. kind .. "OffsetX"]
        handle.scripts.OnMouseDown(handle, "LeftButton")
        cx = cx + 9
        handle.scripts.OnMouseUp(handle, "LeftButton")
        assert(S.Config("nameplates")["friendly" .. kind .. "OffsetX"] == before + 9,
            "friendly marker drag did not write its runtime setting")
        ui.body.selectionDeps.ResetOffsets(ui.body, handle)
        S.Set("nameplates", "friendly" .. kind .. "Marker", false)
    end
    Control("plateKind").scripts.OnClick()
    cast.GetEffectiveScale = function() return 1 end
    cast.scripts.OnMouseDown(cast, "LeftButton")
    cy = cy - 9
    cast.scripts.OnMouseUp(cast, "LeftButton")
    assert(S.Config("nameplates").enemyCastOffsetY == -9, "cast drag did not save the live offset")
    name.scripts.OnMouseDown(name, "LeftButton")
    ui.body.scripts.OnHide(ui.body)
    assert(not ui.dragging and not ui.body._selectedHandle, "hidden preview retained a drag or keyboard capture")
    S.Set("nameplates", "look", 1)

end)()
-- The extra-action control delegates to Blizzard's Edit Mode only when that
-- manager allows entry; the Suite never reparents the protected button.
local extraButton = registeredControls["menu2.suite_actionbars.actionbars.editor.extraAbility"]
assert(extraButton and not extraButton.enabled, "extra-action move control was not gated")
local editModeOpens = 0
EditModeManagerFrame = { CanEnterEditMode = function() return true end }
ShowUIPanel = function(frame)
    assert(frame == EditModeManagerFrame)
    editModeOpens = editModeOpens + 1
end
extraButton.scripts.OnClick()
assert(editModeOpens == 1, "extra-action move did not open Blizzard Edit Mode")
EditModeManagerFrame.CanEnterEditMode = function() return false end
extraButton.scripts.OnClick()
assert(editModeOpens == 1, "blocked Edit Mode was opened")
EditModeManagerFrame, ShowUIPanel = lockedEditMode, nil
local sliderCount = 0
for pageKey, ctx in pairs(contexts) do
    for _, widget in ipairs(ctx.widgets) do
        if widget.rowKind == "slider" then
            sliderCount = sliderCount + 1
            local row = widget.row
            assert(row.step == 1 or row.step == 0.01,
                pageKey .. " has a slider without single-unit or one-percent-point steps: " .. row.id)
            if row.step == 0.01 then assert(row.roundStep == false, "fractional slider rounds to a whole number") end
            if pageKey == "suite_actionbars" and row.id == "iconZoom" then
                assert(row.step == 1 and row.format(3.5) == "3.50",
                    "old half-step icon zoom value must remain visible until edited")
            end
        end
    end
end
assert(sliderCount > 0, "suite pages contain no sliders")
-- Suite pages have no inline color boxes. Every visible catalog color must
-- remain in its section's three-dot picker, including selected-bar templates.
local shortcutColors, shortcutColorCount = {}, 0
for pageKey, ctx in pairs(contexts) do
    for _, widget in ipairs(ctx.widgets) do
        assert(widget.rowKind ~= "color", pageKey .. " still renders an inline color box")
    end
    for _, section in ipairs(ctx.sections) do
        if type(section.colorShortcut) == "table" then
            local targets = section.colorShortcut.options.getTargets()
            assert(section.colorShortcut.options.maxTargets >= #targets,
                pageKey .. " color shortcut truncates its targets: " .. section.sectionId)
            for _, target in ipairs(targets) do
                assert(type(target.get) == "function" and type(target.set) == "function",
                    pageKey .. " has an unbound color shortcut target")
                shortcutColors[target.sourceSettingKey or target.settingKey] = true
                shortcutColorCount = shortcutColorCount + 1
            end
        end
    end
end
assert(shortcutColorCount > 0, "suite color shortcut audit did not cover the catalog")
local hudSections = {}
for _, section in ipairs(contexts.suite_hud.sections) do
    hudSections[section.sectionId] = true
    local appearance = section.sectionId == "suite_hud_objectives_type"
        or section.sectionId == "suite_hud_announcements_type"
    assert((type(section.colorShortcut) == "table") == appearance,
        "HUD appearance accordion is missing its three-dot colors")
end
assert(hudSections.suite_hud_objectives_type and hudSections.suite_hud_announcements_type
    and not hudSections.suite_hud_objectives_quest_groups
    and not hudSections.suite_hud_announcements_event_colors,
    "HUD appearance was not condensed")
assert(hudSections.suite_hud_objectives_raid == (flavor == "Mainline"),
    "raid encounter accordion must exist only on Retail")
local raidPause
for _, widget in ipairs(contexts.suite_hud.widgets) do
    if widget.meta and widget.meta.controlId == "menu2.suite_hud.objectives.showRaid" then
        hudSections.raidControl = widget
    end
    if widget.meta and widget.meta.controlId == "menu2.suite_hud.objectives.pauseInRaidCombat" then
        raidPause = widget
    end
end
assert(raidPause and raidPause.row and raidPause.row.kind == "toggle"
    and raidPause.meta.sectionId == "suite_hud_objectives_content"
    and Suite.SuiteCatalog.objectives.rules.pauseInRaidCombat.default == false,
    "raid combat tracker pause must be an optional HUD toggle")
local focusedColor, category
M.ColorsSetPainterCategory = function(key) category = key end
M.cache = { opt_colors = { sections = {
    colors_suite_objectives = { name = "objectives" },
    colors_suite_announcements = { name = "announcements" },
    colors_suite_nameplates = { name = "nameplates" },
} } }
W.FocusCollapsibleSection = function(section) focusedColor = section.name end
for _, id in ipairs({ "objectives", "announcements" }) do
    local page = id == "nameplates" and "suite_nameplates" or "suite_hud"
    local button = registeredControls["menu2." .. page .. "." .. id .. ".action.colors"]
    assert(button and button.scripts.OnClick, id .. " has no link to Colors")
    button.scripts.OnClick()
    assert(M.selectedPage == "opt_colors" and category == "suite" and focusedColor == id,
        id .. " color link did not open its own Colors section")
end
local plateSections = {}
for _, section in ipairs(contexts.suite_nameplates.sections) do
    plateSections[section.sectionId] = section
end
assert((hudSections.raidControl ~= nil) == (flavor == "Mainline")
    and (not hudSections.raidControl
        or hudSections.raidControl.meta.sectionId == "suite_hud_objectives_raid"),
    "raid encounter option must resolve to its own exact accordion")
do
    local plateControls = {}
    for _, widget in ipairs(contexts.suite_nameplates.widgets) do
        if widget.meta and widget.meta.settingKey then plateControls[widget.meta.settingKey] = true end
    end
    for feature, keys in pairs(dofile(root .. "/tools/fixtures/nameplates_eqol_features.lua")) do
        for _, key in ipairs(keys) do
            local path = "msufsuite.nameplates." .. key
            local rule = assert(Suite.SuiteCatalog.nameplates.rules[key], feature .. ": " .. key)
            assert(rule.color and shortcutColors[path] or plateControls[path],
                "EQoL nameplate setting has no menu control: " .. feature .. " / " .. key)
        end
    end
end
assert(plateSections.suite_nameplates_enemy and plateSections.suite_nameplates_enemy.colorShortcut
    and plateSections.suite_nameplates_roleColors and plateSections.suite_nameplates_roleColors.colorShortcut
    and plateSections.suite_nameplates_castbar and plateSections.suite_nameplates_castbar.colorShortcut
    and plateSections.suite_nameplates_friendly and plateSections.suite_nameplates_friendly.colorShortcut,
    "nameplate section lost its three-dot color shortcut")
do
    local tabs = assert(contexts.suite_nameplates.tabControls[1], "enemy tabs missing")
    assert(tabs.segment.value == "appearance" and tabs.frames.appearance.shown
        and not tabs.frames.elements.shown, "enemy appearance tab did not open")
    tabs.segment:Choose("elements")
    assert(tabs.frames.elements.shown and not tabs.frames.appearance.shown,
        "Blizzard elements tab did not switch")
    local elite = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.enemy.Classification"])
    local raid = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.enemy.RaidIcon"])
    assert(not elite:IsShown() and not raid:IsShown(),
        "opening Blizzard elements changed the normal enemy sample")
    elite.previewUI:Paint()
    assert(not elite:IsShown() and elite.previewUI.previewRole == nil,
        "the inactive friendly renderer changed the normal enemy sample")
    tabs.segment:Choose("appearance")
    local eliteLayer = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.layer.classification"])
    local raidLayer = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.layer.raidIcon"])
    assert(elite.previewUI.layerRail:IsShown() and elite.previewUI.layerRail.parent == elite.previewUI.body,
        "UF/GF layer rail must stay visible below the nameplate canvas")
    eliteLayer.scripts.OnClick(eliteLayer, "RightButton")
    assert(tabs.segment.value == "elements", "elite layer did not open Blizzard elements")
    tabs.segment:Choose("appearance")
    local function Setting(key)
        for _, widget in ipairs(contexts.suite_nameplates.widgets) do
            if widget.meta and widget.meta.settingKey == "msufsuite.nameplates." .. key then return widget end
        end
        error("missing Blizzard element control: " .. key)
    end
    local raritySetting, raidSetting = Setting("enemyRarityIcon"), Setting("enemyRaidIcon")
    elite.previewUI.previewRole, elite.previewUI.raidMarked = nil, false
    S.Set("nameplates", "enemyPreviewRole", 3)
    elite.previewUI:Paint()
    assert(elite:IsShown() and not raid:IsShown(), "rare preview did not follow Blizzard's icon conditions")
    local exactSetting
    M.OpenExactSettingControl = function(key, _, page)
        exactSetting = key
        assert(page == "suite_nameplates")
        return true
    end
    local healthLayer = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.layer.health"])
    healthLayer.scripts.OnClick(healthLayer, "RightButton")
    assert(exactSetting == "msufsuite.nameplates.enemyHealthWidthDelta",
        "enemy health preview did not open its width control")
    local levelLayer = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.layer.level"])
    levelLayer.scripts.OnClick(levelLayer, "RightButton")
    assert(exactSetting == "msufsuite.nameplates."
        .. (flavor == "Forever" and "levelAppearance" or "enemyLevelEnabled"),
        "level preview opened the wrong client-specific setting")
    local beforeDisplay = S.Config("nameplates").friendlyNamesOnly
    local displayButton = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.friendlyMode"])
    displayButton.scripts.OnClick(displayButton)
    assert(exactSetting == "msufsuite.nameplates.friendlyNamesOnly"
        and S.Config("nameplates").friendlyNamesOnly == beforeDisplay,
        "friendly preview button must open its sole display control without changing the mode")
    GetCursorPosition = function() return 40, 40 end
    elite.scripts.OnMouseDown(elite, "LeftButton")
    elite.scripts.OnMouseUp(elite, "LeftButton")
    elite.scripts.OnClick(elite, "LeftButton")
    assert(tabs.segment.value == "elements" and tabs.frames.elements.shown,
        "clicking the native elite icon did not open its Blizzard settings tab")
    assert(exactSetting == "msufsuite.nameplates.enemyRarityIcon",
        "clicking the elite icon did not link its exact setting")
    M.OpenExactSettingControl = nil
    tabs.segment:Choose("appearance")
    current = contexts.suite_nameplates
    raritySetting.set(3)
    assert(not elite:IsShown(), "preview elite icon did not follow its Blizzard visibility setting")
    raritySetting.set(1)
    assert(elite:IsShown(), "preview elite icon did not return after re-enabling it")
    elite.previewUI.raidMarked = false
    raidLayer.scripts.OnClick(raidLayer)
    assert(raid:IsShown() and not elite:IsShown(),
        "Blizzard hides the classification icon on raid-marked nameplates")
    tabs.segment:Choose("appearance")
    raid.previewUI.body.selectionDeps.OpenSettings(raid.previewUI.body, raid)
    assert(tabs.segment.value == "elements", "Open settings did not route the raid icon to its switch")
    raidSetting.set(false)
    assert(not raid:IsShown(), "preview raid icon did not follow its runtime switch")
    raidSetting.set(true)
    assert(raid:IsShown(), "preview raid icon did not return after re-enabling it")
    raidLayer.scripts.OnClick(raidLayer)
    assert(not raid:IsShown() and elite:IsShown(), "removing the raid mark did not restore the elite icon")
    local skullChoice = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.raidMark.8"])
    local squareChoice = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.raidMark.6"])
    assert(#raid.previewUI.raidChoices == 8, "preview must offer all Blizzard raid markers")
    skullChoice.scripts.OnClick(skullChoice)
    assert(raid:IsShown() and raid._npTexture.texture:match("UI%-RaidTargetingIcon_8$"),
        "raid preview palette did not show Blizzard's skull marker")
    squareChoice.scripts.OnClick(squareChoice)
    assert(raid:IsShown() and raid._npTexture.texture:match("UI%-RaidTargetingIcon_6$"),
        "raid preview palette did not show Blizzard's blue square marker")
    squareChoice.scripts.OnClick(squareChoice)
    assert(not raid:IsShown() and elite:IsShown(), "raid preview palette did not restore the elite example")
    local auras = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.enemy.Auras"])
    local auraLayer = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.layer.auras"])
    local auraOffset = S.Config("nameplates").enemyAurasOffsetX
    auraLayer.scripts.OnClick(auraLayer)
    assert(not auras:IsShown() and S.Config("nameplates").enemyAurasOffsetX == auraOffset,
        "preview layer wrote a runtime setting")
    auraLayer.scripts.OnClick(auraLayer)
    assert(auras:IsShown(), "preview layer did not restore the aura sample")
    local nameHandle = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.enemy.Name"])
    local valueHandle = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.enemy.HealthText"])
    local nameLayer = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.layer.name"])
    local valueLayer = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.layer.healthText"])
    nameLayer.scripts.OnClick(nameLayer)
    assert(not nameHandle:IsShown() and valueHandle:IsShown(), "name layer also hid Blizzard's health text")
    nameLayer.scripts.OnClick(nameLayer)
    valueLayer.scripts.OnClick(valueLayer)
    assert(nameHandle:IsShown() and not valueHandle:IsShown(), "health text layer also hid the name")
    valueLayer.scripts.OnClick(valueLayer)
    local spellIcon = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.enemy.CastIcon"])
    local spellLayer = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.layer.castIcon"])
    assert(not spellIcon:IsShown() and S.Config("nameplates").enemyCastSpellIcon == false)
    tabs.segment:Choose("appearance")
    spellLayer.scripts.OnClick(spellLayer)
    assert(tabs.segment.value == "elements" and S.Config("nameplates").enemyCastSpellIcon == false,
        "a disabled Blizzard layer should open its switch without altering runtime settings")
    S.Set("nameplates", "enemyCastSpellIcon", true)
    elite.previewUI:Paint()
    assert(spellIcon:IsShown(), "enabling Blizzard's spell icon did not update the preview")
    S.Set("nameplates", "enemyCastSpellIcon", false)
    S.Set("nameplates", "enemyPreviewRole", 1)
    elite.previewUI:Paint()
    assert(not elite:IsShown() and not raid:IsShown(), "normal enemy preview showed special icons")
    eliteLayer.scripts.OnClick(eliteLayer)
    assert(elite:IsShown() and elite.previewUI.previewRole == 4 and not elite.previewUI.raidMarked,
        "elite preview layer did not summon the native elite scenario: " .. tostring(elite:IsShown())
        .. "/" .. tostring(elite.previewUI.previewRole) .. "/" .. tostring(elite.previewUI.raidMarked))
    elite.previewUI.previewRole = nil
    local nativeGet = C_CVar.GetCVar
    C_CVar.GetCVar = function(key)
        if key == "nameplateShowCastBars" then return "0" end
        if key == "nameplateInfoDisplay" or key == "nameplateCastBarDisplay" then return string.char(1, 64) end
    end
    S.Set("nameplates", "enemyPreviewRole", 3)
    S.Set("nameplates", "enemyTextMode", 1)
    S.Set("nameplates", "enemyCastEnabled", 1)
    S.Set("nameplates", "enemyCastDisplay", 1)
    elite.previewUI:Paint()
    local cast = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.enemy.Cast"])
    assert(not elite:IsShown() and not cast:IsShown(),
        "Keep Blizzard setting preview ignored native rarity or castbar flags")
    S.Set("nameplates", "enemyRarityIcon", 2)
    S.Set("nameplates", "enemyCastEnabled", 2)
    S.Set("nameplates", "enemyCastDisplay", 2)
    elite.previewUI:Paint()
    assert(elite:IsShown() and cast:IsShown(), "preview did not show forced Blizzard elements")
    C_CVar.GetCVar = nativeGet
    S.Set("nameplates", "enemyPreviewRole", 1)
    S.Set("nameplates", "enemyTextMode", 4)
    S.Set("nameplates", "enemyRarityIcon", 1)
    S.Set("nameplates", "enemyCastEnabled", 2)
    S.Set("nameplates", "enemyCastDisplay", 2)
    elite.previewUI:Paint()
    for _, key in ipairs({ "enemyTextMode", "enemyRarityIcon", "enemyRaidIcon",
        "enemyCastEnabled", "enemyCastDisplay", "enemyCastSpellName", "enemyCastSpellIcon",
        "enemyCastSpellTarget" }) do
        local control
        for _, widget in ipairs(contexts.suite_nameplates.widgets) do
            if widget.meta and widget.meta.settingKey == "msufsuite.nameplates." .. key then
                control = widget; break
            end
        end
        assert(control and control.meta.sectionId == "suite_nameplates_enemy", key .. " is absent from enemy tabs")
    end
end
assert(not plateSections.suite_nameplates_general and plateSections.suite_nameplates_nameplates_module,
    "Start here must be merged into the existing Frame Basics card")
for _, key in ipairs({ "look", "nativeSize", "friendlyNPCs", "playerGuildNames", "playerTitles", "protectImport" }) do
    local control
    for _, widget in ipairs(contexts.suite_nameplates.widgets) do
        if widget.meta and widget.meta.controlId == "menu2.suite_nameplates.nameplates." .. key then control = widget; break end
    end
    assert(control, key)
    assert(control.meta.sectionId == "suite_nameplates_nameplates_module", key .. " escaped Frame Basics")
end
assert(not registeredControls["menu2.suite_nameplates.nameplates.action.colors"], "standalone color button survived")
for section, key in pairs({ enemy = "enemyTargetColor", roleColors = "enemyCasterColor", friendly = "friendlyBorderColor" }) do
    local found
    for _, target in ipairs(plateSections["suite_nameplates_" .. section].colorShortcut.options.getTargets()) do
        if target.sourceSettingKey == "msufsuite.nameplates." .. key then found = true; break end
    end
    assert(found, key .. " is absent from its three-dot color menu")
end
for _, id in ipairs(Suite.SuiteOrder) do
    for _, rule in ipairs(Suite.SuiteCatalog[id].controls) do
        if rule.color and not rule.hidden and not rule.previewOnly then
            local template = rule.key:gsub("^bar%d+", "bar1"):gsub("^w%d+", "w1")
            if id == "cooldownManager" and rule.suffix then template = "c1_" .. rule.suffix end
            assert(shortcutColors["msufsuite." .. id .. "." .. template],
                "Suite accordion dots omit " .. id .. "." .. rule.key)
        end
    end
end
local cdmLook
for _, section in ipairs(contexts.suite_cooldownManager.sections) do
    if section.sectionId == "suite_cooldownManager_look" then cdmLook = section; break end
end
assert(cdmLook and cdmLook.colorShortcut, "Cooldown bar colors lost their accordion shortcut")
local cdmBorder
for _, target in ipairs(cdmLook.colorShortcut.options.getTargets()) do
    if target.sourceSettingKey == "msufsuite.cooldownManager.c1_borderColor" then cdmBorder = target; break end
end
assert(cdmBorder and cdmBorder.settingKey == "msufsuite.cooldownManager.ess_borderColor",
    "Cooldown color shortcut does not follow the selected bar")
local previousCDMColor = S.Config("cooldownManager").ess_borderColor
cdmBorder.set(0x12/255, 0x34/255, 0x56/255)
assert(S.Config("cooldownManager").ess_borderColor == "123456",
    "Cooldown color shortcut wrote to the wrong bar")
S.Config("cooldownManager").ess_borderColor = previousCDMColor
-- An unavailable module must still let users change its saved switch. The
-- runtime stays off until its client capability or AddOn is available.
local actionBarsHeader = contexts.suite_actionbars.sections[1].headerSwitch
loaded.Bartender4 = true
current = contexts.suite_actionbars
M.RequestRefresh()
assert(S.Availability("actionbars") == false and actionBarsHeader.enabled,
    "unavailable action bars locked their module switch")
actionBarsHeader.set(false)
actionBarsHeader.set(true)
assert(S.Config("actionbars").enabled and not S.states.actionbars.active,
    "unavailable action bars started or failed to save their enabled preference")
actionBarsHeader.set(false)
loaded.Bartender4 = nil
M.RequestRefresh()
local qolPage = contexts.suite_qualityOfLife
function qolPage.Section(name)
    local id = "suite_qualityOfLife_" .. name
    for _, section in ipairs(qolPage.sections) do
        if section.sectionId == id then return section end
    end
    error("missing Quality of Life section: " .. name)
end
local qolHeader = qolPage.Section("qol_repair").headerSwitch
C_AddOns.GetAddOnEnableState = function(name)
    return name == "MSUF_Suite_QualityOfLife" and 0 or 1
end
current = contexts.suite_qualityOfLife
M.RequestRefresh()
assert(S.Availability("qol") == false and qolHeader.enabled,
    "disabled Quality of Life AddOn locked its feature switch")
qolHeader.set(true)
assert(S.Config("qol").enabled and S.Config("qol").repair and not S.states.qol.active,
    "unavailable Quality of Life feature did not save its switch")
qolHeader.set(false)
C_AddOns.GetAddOnEnableState = AllEnabled
M.RequestRefresh()
-- The Edit Mode buttons call S.OpenEditMode, an export of the load-on-demand
-- runtime: until MSUF_Suite_Modules loads they stay disabled and do nothing.
do
    local EDIT_BUTTONS = {
        { "suite_bags", "bags.action.move", "bags", "combined" },
        { "suite_buffReminders", "buffReminders.action.edit", "buffReminders", "buffs" },
        { "suite_dataTexts", "dataTexts.bar1.move", "dataTexts", "bar1" },
        { "suite_dataTexts", "dataTexts.action.move", "dataTexts", "bar1" },
        { "suite_qualityOfLife", "xpBar.action.edit", "xpBar", "experience" },
        { "suite_qualityOfLife", "skyriding.action.edit", "skyriding", "flight" },
    }
    local status, availability = S.Status, S.Availability
    assert(S.OpenEditMode == nil, "this fixture must not load the Suite runtime")
    S.Status, S.Availability = function() return "Active" end, function() return true end
    local bagsEnabled, bar1Enabled = S.Config("bags").enabled, S.Config("dataTexts").bar1Enabled
    S.Config("bags").enabled, S.Config("dataTexts").bar1Enabled = true, true
    OpenAllBags = function() end
    local opened
    for _, entry in ipairs(EDIT_BUTTONS) do
        local button = assert(registeredControls["menu2." .. entry[1] .. "." .. entry[2]], entry[2] .. " is missing")
        current = contexts[entry[1]]
        S.OpenEditMode = nil
        M.RequestRefresh()
        assert(button.enabled == false, entry[2] .. " stayed enabled without the Suite runtime")
        button.scripts.OnClick(button)
        S.OpenEditMode = function(id, element) opened = { id, element }; return true end
        M.RequestRefresh()
        assert(button.enabled == true, entry[2] .. " stayed disabled with the Suite runtime")
        opened = nil
        button.scripts.OnClick(button)
        assert(opened and opened[1] == entry[3] and opened[2] == entry[4],
            entry[2] .. " did not open Edit Mode on its element")
    end
    S.OpenEditMode, OpenAllBags = nil, nil
    S.Status, S.Availability = status, availability
    S.Config("bags").enabled, S.Config("dataTexts").bar1Enabled = bagsEnabled, bar1Enabled
    M.RequestRefresh()
end
assert(contexts.suite_minimap.pageItems[1] == "fixed-preview"
    and contexts.suite_minimap.pageItems[2] == "suite_minimap_minimap_module"
    and contexts.suite_minimap.fixedPreview.section.expander.expanded,
    "minimap preview must stay fixed above Frame Basics")
assert(contexts.suite_minimap.sections[1].title == "Frame Basics"
    and contexts.suite_minimap.sections[1].headerSwitch,
    "minimap enable switch is not in the Frame Basics header")
local dataPage = contexts.suite_dataTexts
do
    local original = Suite.Client.modernEquipment
    for _, modern in ipairs({ false, true }) do
        Suite.Client.modernEquipment = modern
        local ctx = { key = "suite_buffReminders", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
        M.pages.suite_buffReminders.build(ctx)
        local recommended = false
        for _, section in ipairs(ctx.sections) do
            if section.sectionId == "suite_buffReminders_recommended" then recommended = true end
        end
        assert(recommended == modern,
            "Retail consumables section should appear only with modern equipment")
    end
    Suite.Client.modernEquipment = original
end
assert(dataPage.sections[1].title == "Frame Basics"
    and dataPage.sections[2].title == "Shared bar style"
    and dataPage.sections[3].title == "Shared text style",
    "DataTexts styling lost its shared sections")
for index = 1, 3 do
    assert(dataPage.sections[index + 3].headerSwitch,
        "DataTexts bar " .. index .. " has no accordion enable switch")
end
local ownStyle
for _, widget in ipairs(dataPage.widgets) do
    if widget.meta and widget.meta.settingKey == "msufsuite.dataTexts.bar1StyleOverride" then ownStyle = widget end
end
assert(ownStyle and ownStyle.rowKind == "toggle", "DataTexts own-style control is missing")
assert(Suite.Suite.Set("dataTexts", "backgroundOpacity", 55))
ownStyle.set(true)
assert(Suite.Suite.Config("dataTexts").bar1StyleOverride
    and Suite.Suite.Config("dataTexts").bar1BackgroundOpacity == 55,
    "own style did not copy the current shared settings")
ownStyle.set(false)
assert(not Suite.Suite.Config("dataTexts").bar1StyleOverride,
    "own style did not return to shared settings")
-- A place tile opens Blizzard's context menu (Blizzard_Menu's MenuUtil exists
-- on every supported client) with one radio per data source.
do
    local tile = assert(registeredControls["menu2.suite_dataTexts.dataTexts.bar1Slot2.preview"],
        "DataTexts place tile is missing")
    local menuOwner, radios
    MenuUtil = { CreateContextMenu = function(owner, generator)
        menuOwner, radios = owner, {}
        generator(owner, { CreateRadio = function(_, text, isSelected, select)
            radios[#radios + 1] = { text = text, isSelected = isSelected, select = select }
        end })
    end }
    local before = S.Config("dataTexts").bar1Slot2
    tile.scripts.OnClick(tile)
    assert(menuOwner == tile and #radios == #Suite.DataTextSources, "a place tile did not open its source menu")
    radios[3].select()
    assert(S.Config("dataTexts").bar1Slot2 == 3 and radios[3].isSelected() and not radios[2].isSelected(),
        "choosing a source in the place menu did not set the place")
    assert(S.Set("dataTexts", "bar1Slot2", before))
    MenuUtil = nil
end
-- Shadow opacity and distance follow the shadow switch, in the shared text
-- style and in a bar's own style, like every other module's text settings.
do
    local config, rules = Suite.Suite.Config("dataTexts"), Suite.SuiteCatalog.dataTexts.rules
    local keys = { "enabled", "fontRendering", "fontShadow", "bar1Enabled", "bar1StyleOverride",
        "bar1FontRendering", "bar1FontShadow" }
    local saved = {}
    for _, key in ipairs(keys) do saved[key] = config[key] end
    config.enabled, config.fontRendering = true, 1
    config.bar1Enabled, config.bar1StyleOverride, config.bar1FontRendering = true, true, 1
    for _, prefix in ipairs({ "font", "bar1Font" }) do
        for _, shadow in ipairs({ false, true }) do
            config[prefix .. "Shadow"] = shadow
            for _, suffix in ipairs({ "ShadowOpacity", "ShadowDistance" }) do
                assert(optionsNS.RuleEnabled("dataTexts", rules[prefix .. suffix]) == shadow,
                    "DataTexts " .. prefix .. suffix .. " ignores the text shadow switch")
            end
        end
    end
    for _, key in ipairs(keys) do config[key] = saved[key] end
end
for _, id in ipairs({ "actionbars", "cooldownManager", "bags", "dataTexts", "skyriding", "chat" }) do
    local rules = Suite.SuiteCatalog[id].rules
    for _, key in ipairs({ "font", "fontRendering", "fontShadow", "fontShadowOpacity", "fontShadowDistance" }) do
        assert(rules[key], id .. " is missing the shared text effect " .. key)
    end
    assert(rules.fontRendering.default == 3 and S.Config(id).fontRendering == 3,
        id .. " did not start with Slug rendering")
end
assert(Suite.SuiteCatalog.damageMeter.rules.rendering.default == 3
    and Suite.SuiteCatalog.damageMeter.rules.outline.default == 2
    and S.Config("damageMeter").rendering == 3,
    "Damage Meter default is not outlined Slug")
assert(Suite.SuiteCatalog.bags.rules.fontShadow.default == false,
    "Bags default enables a shadow that Slug cannot render")
local savedChat = S.Config("chat")
assert(Suite.SuiteCatalog.chat.rules.copyMessages.default == false and savedChat.copyMessages == false,
    "chat message copying must be off by default")
local timestampWidget
for _, widget in ipairs(contexts.suite_chat.widgets) do
    if widget.meta and widget.meta.settingKey == "showTimestamps" then timestampWidget = widget end
end
assert(timestampWidget and timestampWidget.rowKind == "dropdown"
    and timestampWidget.meta.sectionId == "suite_chat_tools",
    "chat timestamps must be a dropdown bound to Blizzard's setting")
local nativeTimestamp = "none"
C_CVar = {
    GetCVar = function(key)
        if key == "combinedBags" then return nil end
        assert(key == "showTimestamps")
        return nativeTimestamp
    end,
    SetCVar = function(key, value) assert(key == "showTimestamps"); nativeTimestamp = value end,
}
TIMESTAMP_FORMAT_HHMM = "format-hm"
TIMESTAMP_FORMAT_HHMMSS = "format-hms"
TIMESTAMP_FORMAT_HHMM_AMPM = "format-hm-ampm"
TIMESTAMP_FORMAT_HHMMSS_AMPM = "format-hms-ampm"
TIMESTAMP_FORMAT_HHMM_24HR = "format-hm-24"
TIMESTAMP_FORMAT_HHMMSS_24HR = "format-hms-24"
assert(#timestampWidget.meta.values() == 7 and timestampWidget.get() == "none")
timestampWidget.set(TIMESTAMP_FORMAT_HHMM_24HR)
assert(nativeTimestamp == TIMESTAMP_FORMAT_HHMM_24HR and timestampWidget.get() == nativeTimestamp
    and savedChat.timestamp == nil, "Suite timestamp dropdown did not update the native CVar")
savedChat.fontRendering = 1
S.Normalize(Suite.DB)
assert(savedChat.fontRendering == 1, "normalization overwrote an existing Smooth selection")
savedChat.fontRendering = 3
for _, name in ipairs(Suite.MinimapInfoFields) do
    for _, suffix in ipairs({ "Font", "Outline", "Rendering", "Shadow", "ShadowOpacity", "ShadowDistance" }) do
        assert(Suite.SuiteCatalog.minimap.rules["info" .. name .. suffix],
            "Minimap " .. name .. " is missing " .. suffix)
    end
    assert(Suite.SuiteCatalog.minimap.rules["info" .. name .. "Rendering"].default == 3
        and S.Config("minimap")["info" .. name .. "Rendering"] == 3,
        "Minimap " .. name .. " did not start with Slug")
end
for _, suffix in ipairs({ "Font", "Outline", "Rendering", "Shadow", "ShadowOpacity", "ShadowDistance" }) do
    assert(Suite.SuiteCatalog.minimap.rules["infoDifficulty" .. suffix],
        "Minimap difficulty text is missing " .. suffix)
end
assert(Suite.SuiteCatalog.minimap.rules.infoDifficultyRendering.default == 3,
    "Minimap difficulty text did not default to Slug")
for bar = 1, 3 do
    for _, key in ipairs({ "fontRendering", "fontShadow", "fontShadowOpacity", "fontShadowDistance" }) do
        assert(Suite.SuiteCatalog.dataTexts.rules["bar" .. bar .. key:sub(1, 1):upper() .. key:sub(2)],
            "DataText bar " .. bar .. " is missing " .. key)
    end
    assert(Suite.SuiteCatalog.dataTexts.rules["bar" .. bar .. "FontRendering"].default == 3,
        "DataText bar " .. bar .. " did not default to Slug")
end
local qolGroups = { "battleRes_battle_res", "loot_collection", "combatLog_log_dungeons", "xpBar_xp_bar",
    "vaultSpec_vault_spec", "innervateCue_innervate_cue", "loot_history", "durabilityAlert_durability_warning",
    "merchantLevel_merchant_level", "quests_automation", "qol_repair", "qol_junk", "skyriding_flight_hud",
    "tooltipIDs_tooltip_ids" }
assert(#qolPage.sections == #qolGroups, "Quality of Life retained Module Basics or nested accordions")
for i, name in ipairs(qolGroups) do
    local section = qolPage.sections[i]
    assert(section.sectionId == "suite_qualityOfLife_" .. name and section.headerSwitch,
        "Quality of Life feature has no independent header switch: " .. name)
    assert(i == 1 or qolPage.sections[i - 1].title < section.title,
        "Quality of Life feature names are not alphabetically sorted")
end
local route = {
    ["msufsuite.xpBar.width"] = "xpBar_xp_bar",
    ["msufsuite.skyriding.width"] = "skyriding_flight_hud",
    ["msufsuite.skyriding.font"] = "skyriding_flight_hud",
    ["msufsuite.skyriding.barTexture"] = "skyriding_flight_hud",
    ["msufsuite.skyriding.barHeight"] = "skyriding_flight_hud",
    ["msufsuite.skyriding.panelOpacity"] = "skyriding_flight_hud",
    ["msufsuite.qol.repairLimit"] = "qol_repair",
    ["msufsuite.qol.junkReport"] = "qol_junk",
    ["msufsuite.quests.onlyIDs"] = "quests_automation",
    ["msufsuite.loot.lootModifier"] = "loot_collection",
    ["msufsuite.loot.historyMode"] = "loot_history",
    ["msufsuite.combatLog.raidNormal"] = "combatLog_log_dungeons",
    ["msufsuite.durabilityAlert.threshold"] = "durabilityAlert_durability_warning",
    ["msufsuite.battleRes.point"] = "battleRes_battle_res",
}
local routed = 0
for _, widget in ipairs(qolPage.widgets) do
    local meta = widget.meta
    if meta and route[meta.settingKey] then
        assert(meta.sectionId == "suite_qualityOfLife_" .. route[meta.settingKey],
            "Quality of Life search route points at a removed accordion")
        routed = routed + 1
    end
end
assert(routed == 14, "Quality of Life settings lost their search routes")
local xpBar = qolPage.Section("xpBar_xp_bar").headerSwitch
xpBar.set(true)
assert(xpBar.get() and S.Config("xpBar").enabled, "XP bar header switch did not enable its module")
xpBar.set(false)
assert(not xpBar.get(), "XP bar header switch did not disable its module")
local skyride = qolPage.Section("skyriding_flight_hud").headerSwitch
skyride.set(true)
assert(skyride.get() and S.Config("skyriding").enabled, "Skyriding switch did not save its preference")
local skyControls = {}
for _, widget in ipairs(qolPage.widgets) do
    local key = widget.meta and widget.meta.settingKey
    if key and key:match("^msufsuite%.skyriding%.") then
        skyControls[key:match("%.([^.]+)$")] = widget
    end
end
assert(skyControls.font.rowKind == "dropdown" and skyControls.barTexture.rowKind == "dropdown"
    and not skyControls.panelColor and skyControls.fontSize.rowKind == "slider",
    "Skyriding styling controls are missing from the Quality of Life accordion")
local skyPanelColor
for _, target in ipairs(qolPage.Section("skyriding_flight_hud").colorShortcut.options.getTargets()) do
    if target.settingKey == "msufsuite.skyriding.panelColor" then skyPanelColor = target; break end
end
assert(skyPanelColor, "Skyriding panel color is missing from its three-dot picker")
assert(skyControls.font.row.values()[1].text == "MSUF global font (default)",
    "Skyriding font picker does not describe its real default")
skyControls.font.set("Test font")
skyControls.barTexture.set("Test bars")
skyControls.fontSize.set(15)
skyControls.panelOpacity.set(45)
assert(S.Config("skyriding").font == "Test font" and S.Config("skyriding").barTexture == "Test bars"
    and S.Config("skyriding").fontSize == 15 and S.Config("skyriding").panelOpacity == 45,
    "Skyriding styling changes were not saved")
skyControls.look.set(2)
assert(S.Config("skyriding").look == 2 and S.Config("skyriding").panelColor == "151719"
    and S.Config("skyriding").accentColor == "b9ab86",
    "Skyriding preset did not apply its colors")
skyPanelColor.set(1, 0, 0)
assert(S.Config("skyriding").look == 4 and S.Config("skyriding").panelColor == "ff0000",
    "Changing a Skyriding color did not keep it as Custom")
skyride.set(false)
assert(not skyride.get(), "Skyriding switch did not turn off")
local repair, junk = qolPage.Section("qol_repair").headerSwitch, qolPage.Section("qol_junk").headerSwitch
repair.set(true)
assert(repair.get() and S.Config("qol").enabled and S.Config("qol").repair)
junk.set(true)
repair.set(false)
assert(not repair.get() and junk.get() and S.Config("qol").enabled,
    "turning off repair disabled active junk selling")
junk.set(false)
assert(not S.Config("qol").enabled, "inactive merchant helpers retained their runtime gate")
local collect, history = qolPage.Section("loot_collection").headerSwitch, qolPage.Section("loot_history").headerSwitch
collect.set(true)
history.set(true)
collect.set(false)
assert(not collect.get() and history.get() and S.Config("loot").enabled,
    "turning off collection disabled active loot history")
history.set(false)
assert(not S.Config("loot").enabled, "inactive loot helpers retained their runtime gate")
local quests, combatLog = qolPage.Section("quests_automation").headerSwitch, qolPage.Section("combatLog_log_dungeons").headerSwitch
quests.set(true)
combatLog.set(true)
assert(quests.get() and combatLog.get() and S.Config("quests").enabled
    and S.Config("combatLog").enabled, "quest or combat logging header switch did not enable its module")
quests.set(false)
combatLog.set(false)
assert(not quests.get() and not combatLog.get(), "quest or combat logging header switch did not disable its module")
do
    local durability = qolPage.Section("durabilityAlert_durability_warning").headerSwitch
    durability.set(true)
    assert(durability.get() and S.Config("durabilityAlert").enabled,
        "durability warning switch did not enable its module")
    durability.set(false)
    assert(not durability.get(), "durability warning switch did not disable its module")
end
do
    local battleRes = qolPage.Section("battleRes_battle_res").headerSwitch
    assert(S.Availability("battleRes") == (flavor == "Mainline"),
        "shared battle resurrection must be Retail-only")
    battleRes.set(true)
    assert(battleRes.get() and S.Config("battleRes").enabled,
        "battle resurrection switch did not enable its module")
    battleRes.set(false)
    assert(not battleRes.get(), "battle resurrection switch did not disable its module")
end
local colorContext = { key = "opt_colors", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
current = colorContext
Suite.Options.BuildColorsCategory(colorContext, W.PageBuilder(colorContext))
local colorSections = {}
for _, section in ipairs(colorContext.sections) do colorSections[section.sectionId] = true end
assert(colorSections.colors_suite_minimap and colorSections.colors_suite_actionbars
    and colorSections.colors_suite_damageMeter and colorSections.colors_suite_buffReminders
    and colorSections.colors_suite_chat and colorSections.colors_suite_dataTexts
    and colorSections.colors_suite_objectives and colorSections.colors_suite_announcements
    and colorSections.colors_suite_nameplates,
    "MSUF Colors missed Suite module colors")
local globalColors = {}
for _, widget in ipairs(colorContext.widgets) do
    if widget.rowKind == "color" and widget.meta then globalColors[widget.meta.settingKey] = widget end
end
local expectedColorCount = 0
for _, id in ipairs(Suite.SuiteOrder) do
    for _, rule in ipairs(Suite.SuiteCatalog[id].controls) do
        if rule.color and not rule.hidden then
            local key = "msufsuite." .. id .. "." .. rule.key
            assert(globalColors[key], "MSUF Colors missed Suite color: " .. key)
            expectedColorCount = expectedColorCount + 1
        end
    end
end
local actualColorCount = 0
for _ in pairs(globalColors) do actualColorCount = actualColorCount + 1 end
assert(actualColorCount == expectedColorCount, "MSUF Colors has incomplete or duplicate Suite color rows")
assert(globalColors["msufsuite.dataTexts.bar1BackgroundColor"]
    and globalColors["msufsuite.cooldownManager.c1_borderColor"],
    "MSUF Colors omits individual bar colors")
local dataTextBarColor = globalColors["msufsuite.dataTexts.bar2BackgroundColor"]
local previousDataTextColor = S.Config("dataTexts").bar2BackgroundColor
dataTextBarColor.set(0x12/255, 0x34/255, 0x56/255)
assert(S.Config("dataTexts").bar2BackgroundColor == "123456",
    "MSUF Colors did not write the individual DataText bar color")
S.Config("dataTexts").bar2BackgroundColor = previousDataTextColor
local skinColor = { 0.4, 0.5, 0.6, 0.7 }
MapkoSkin = {
    addonName = "MSUF_Suite_Skin", ColorOrder = { { "accent", "ACCENT" } }, L = { ACCENT = "Accent" },
    Theme = {
        GetColorTable = function() return skinColor end,
        SetColor = function(_, r, g, blue, alpha) skinColor = { r, g, blue, alpha }; return true end,
    },
}
local skinColorContext = { key = "opt_colors", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
current = skinColorContext
Suite.Options.BuildColorsCategory(skinColorContext, W.PageBuilder(skinColorContext))
local skinWidget
for _, widget in ipairs(skinColorContext.widgets) do
    if widget.meta and widget.meta.settingKey == "msufsuite.skin.accent" then skinWidget = widget; break end
end
assert(skinWidget and select(4, skinWidget.get()) == 0.7, "Skin palette omitted alpha in MSUF Colors")
skinWidget.set(0.1, 0.2, 0.3, 0.4)
assert(skinColor[1] == 0.1 and skinColor[4] == 0.4, "MSUF Colors did not write Skin palette")
MapkoSkin = nil
-- The primary Skinning page owns native MSUF controls and a fixed preview;
-- it must not mount the old second navigation rail or require its options addon.
-- Core/Client.lua loads before Core/Defaults.lua in the skin's TOC.
local skin = { addonName = "MSUF_Suite_Skin", Client = { isMainline = true, isForever = false },
    L = setmetatable({}, { __index = function(_, key) return key end }) }
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", skin)
assert(skin.Defaults.theme.look == "midnightDark" and skin.Defaults.theme.preset == "midnightDark")
skin.DB = skin.CopyValue(skin.Defaults)
local previewSurfaces = {}
skin.Surface = { Attach = function(frame, spec) previewSurfaces[#previewSurfaces + 1] = spec.role; return frame end }
skin.Theme = {
    GetColor = function(key) return unpack(skin.DB.theme.colors[key]) end,
    GetColorTable = function(key) return skin.DB.theme.colors[key] end,
    ApplyLook = function(key) skin.DB.theme.look = key; return true end,
    SetAppearance = function(key, value) skin.DB.theme[key] = value; skin.DB.theme.look = "custom"; return true end,
    SetGeometry = function(key, value) skin.DB.geometry[key] = value; return true end,
    SetColor = function(key, r, g, b, a) skin.DB.theme.colors[key] = { r, g, b, a }; return true end,
}
skin.Adapters = {
    SetMasterEnabled = function(value) skin.DB.enabled = value; return true end,
    SetEnabled = function(key, value) skin.DB.skins[key] = value; return true end,
    GetDefinitions = function() return { "settings" }, { settings = { labelKey = "SETTINGS" } } end,
    Refresh = function() return true end,
}
skin.GenericWindows = {
    GetCategories = function() return { { id = "character" } } end,
    SetCategoryEnabled = function(key, value) skin.DB.skinCategories[key] = value; return true end,
}
skin.Typography = {
    GetSelectionValues = function() return { "friz" } end,
    GetSelectionLabel = function(key) return key end,
    GetSelection = function() return skin.DB.typography.face end,
    SetEnabled = function(value) skin.DB.typography.enabled = value; return true end,
    SetSelection = function(value) skin.DB.typography.face = value; return true end,
    SetApplyChat = function(value) skin.DB.typography.applyChat = value; return true end,
    SetIncludeSpecial = function(value) skin.DB.typography.includeSpecial = value; return true end,
    SetCustomPath = function(value) skin.DB.typography.customPath = value; return true end,
}
skin.WindowActionSkin = { SetOption = function(key, value) skin.DB.icons.windowActions[key] = value; return true end }
skin.MicroMenuSkin = {
    SetOption = function(key, value) skin.DB.icons.microMenu[key] = value; return true end,
    ApplyPreset = function(value)
        local preset = skin.MicroMenuPresetValues[value]
        if not preset then return false end
        for key, item in pairs(preset) do skin.DB.icons.microMenu[key] = item end
        skin.DB.icons.microMenu.preset = value
        return true
    end,
    SetPositionPreset = function(value) skin.DB.icons.microMenu.positionPreset = value; return true end,
}
skin.CharacterDetails = {
    SetView = function(value) skin.DB.characterDetails.view = value; return true end,
    SetOption = function(key, value) skin.DB.characterDetails[key] = value; return true end,
}
skin.CharacterStats = { SetOption = function(key, value) skin.DB.characterStats[key] = value; return true end }
skin.Registry = { NotifyListeners = function() end }
skin.Database = {
    GetProfileNames = function() return { "Default" } end,
    GetActiveProfileName = function() return "Default" end,
    CreateProfile = function(name) return true, name end,
    SetActiveProfile = function() return true end,
    DeleteProfile = function() return true end,
}
skin.ProfileIO = {
    maxEncodedBytes = 1024 * 1024,
    ExportProfile = function() return "MSKIN1:profile" end,
    ExportAll = function() return "MSKIN1:all" end,
    ImportProfile = function() return true end,
    ImportAll = function() return true end,
}
MapkoSkin = skin
-- This harness cannot load the meter runtime; a failed module owns nothing.
-- Skinning is checked with the meter running as in the client.
local meterLoadError = S.states.damageMeter.error
S.states.damageMeter.error = nil
local skinContext = { key = "suite_skin", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
current = skinContext
M.pages.suite_skin.build(skinContext)
for _, fn in ipairs(skinContext.refreshers) do fn() end
for _, widget in ipairs(skinContext.widgets) do
    assert(widget.rowKind ~= "color", "Skinning still renders an inline color box")
end
assert(skinContext.pageItems[1] == "fixed-preview"
    and skinContext.pageItems[2] == "suite_skin_frame_basic",
    "Skin preview must own the fixed header before Frame Basics")
assert(table.concat(previewSurfaces, ",") == "shell,panel,card,buttonPrimary",
    "Skin preview must render with the same engine surfaces as the runtime")
assert(skinContext.sections[1].sectionId == "suite_skin_frame_basic"
    and skinContext.sections[1].headerSwitch
    and skinContext.sections[2].sectionId == "suite_skin_basic", "Skin Frame Basics is not first")
-- The default Suite meter owns Blizzard's damage meter, so Skinning has no
-- section for it; Glass follows the Micro Bar directly.
assert(S.Config("damageMeter").enabled == true and S.OwnsBlizzardSurface("damageMeter"),
    "the default Suite meter must own Blizzard's damage meter")
assert(skinContext.sections[3].sectionId == "suite_skin_micro"
    and skinContext.sections[4].sectionId == "suite_skin_micro_load_conditions"
    and skinContext.sections[5].sectionId == "suite_skin_micro_details"
    and skinContext.sections[6].sectionId == "suite_skin_material",
    "Micro Bar setup must be immediately visible after the main look")
local skinControls = {}
for _, widget in ipairs(skinContext.widgets) do
    if widget.meta and widget.meta.settingKey then skinControls[widget.meta.settingKey] = widget end
end
assert(skinControls["msufsuite.skin.theme.look"] and skinControls["msufsuite.skin.theme.shellOpacity"]
    and skinControls["msufsuite.skin.icons.windowActions.style"]
    and skinControls["msufsuite.skin.icons.microMenu.layoutMode"]
    and skinControls["msufsuite.skin.icons.microMenu.loadHideMounted"]
    and skinControls["msufsuite.skin.icons.microMenu.loadShowWhenInjured"]
    and skinControls["msufsuite.skin.enabled"], "native Skinning controls missing")
assert(not skinControls["msufsuite.skin.hud.objectiveTrackerStyle"]
    and not skinControls["msufsuite.skin.skins.objectiveTracker"],
    "retired Blizzard tracker controls remain in Skinning")
assert(not skinControls["msufsuite.skin.skins.damageMeter"],
    "Skinning styles Blizzard's damage meter while the Suite meter owns it")
-- The preset buttons choose the Micro Bar style; details has no second picker.
assert(not skinControls["msufsuite.skin.icons.microMenu.preset"],
    "Micro Bar details still duplicates the preset buttons")
do
local blizzardPreset = registeredControls["menu2.suite_skin.skin.micro.preset.blizzard"]
assert(blizzardPreset and blizzardPreset.text == "Blizzard original",
    "Skinning menu did not offer the original Blizzard Micro Bar")
blizzardPreset.scripts.OnClick()
assert(skin.DB.icons.microMenu.layoutMode == "blizzard"
    and skin.DB.icons.microMenu.iconStyle == "blizzard",
    "Blizzard menu preset did not select Blizzard layout and icons")
registeredControls["menu2.suite_skin.skin.micro.preset.modern"].scripts.OnClick()
assert(skin.DB.icons.microMenu.layoutMode == "owned",
    "Suite menu preset did not restore its movable layout")
skin.DB.icons.microMenu.preset = "custom"
skin.Database.CreateFactoryProfile = function() return skin.CopyValue(skin.Defaults) end
skin.Typography.ApplyConfigured = function() end
skin.Adapters.ApplyAll = function() end
skin.Registry.RefreshAll = function() end
local microDetails
for _, section in ipairs(skinContext.sections) do
    if section.sectionId == "suite_skin_micro_details" then microDetails = section end
end
assert(microDetails and microDetails._msufSuiteSectionReset and microDetails._msufSuiteSectionReset(),
    "Micro Bar details has no section reset")
assert(skin.DB.icons.microMenu.preset == skin.Defaults.icons.microMenu.preset,
    "Micro Bar details reset kept a stale preset name")
end
skinControls["msufsuite.skin.enabled"].set(false)
assert(skin.DB.enabled == false and Suite.Skin.enabled == false,
    "Skinning header switch did not disable Blizzard and Suite surfaces")
skinControls["msufsuite.skin.enabled"].set(true)
assert(skin.DB.enabled == true and Suite.Skin.enabled == true,
    "Skinning header switch did not restore the module")
assert(not skinControls["msufsuite.skin.icons.microMenu.layoutX"]
    and not skinControls["msufsuite.skin.icons.microMenu.layoutY"],
    "Micro Bar position controls duplicate the MSUF Edit Mode mover")
skinControls["msufsuite.skin.icons.windowActions.style"].set("soft")
assert(skin.DB.icons.windowActions.style == "soft", "window action control did not reach nested setting")
skinControls["msufsuite.skin.theme.shellOpacity"].set(0.7)
assert(skin.DB.theme.shellOpacity == 0.7, "glass opacity did not update")
skinControls["msufsuite.skin.skins.settings"].set(false)
assert(skin.DB.skins.settings == false, "Blizzard adapter control did not update")
for _, section in ipairs(skinContext.sections) do
    assert(section.finished and section.sectionId ~= "suite_skin_editor", "old nested Skinning editor remains")
end
-- MSUF Colors is the page for skin colors; Skinning keeps the palette choice
-- and the full palette behind the three dots of Choose a look.
local skinPaletteSection
for _, section in ipairs(skinContext.sections) do
    assert(section.sectionId ~= "suite_skin_colors", "Main colors duplicates MSUF Colors > Suite skin")
    if section.sectionId == "suite_skin_basic" then skinPaletteSection = section end
end
assert(skinControls["msufsuite.skin.theme.preset"]
    and skinControls["msufsuite.skin.theme.preset"].meta.sectionId == "suite_skin_basic",
    "Choose a look lost the color palette choice")
assert(skinPaletteSection and skinPaletteSection.colorShortcut, "Skin colors lost their accordion shortcut")
local skinPaletteTargets = skinPaletteSection.colorShortcut.options.getTargets()
assert(#skinPaletteTargets == #skin.ColorOrder and #skinPaletteTargets > 4,
    "Skin accordion color shortcut truncates the palette")
local skinPaletteKeys = {}
for _, target in ipairs(skinPaletteTargets) do skinPaletteKeys[target.settingKey] = target end
local orderedSkinKeys = {}
for _, entry in ipairs(skin.ColorOrder) do
    orderedSkinKeys[entry[1]] = true
    assert(skinPaletteKeys["msufsuite.skin.color." .. entry[1]],
        "Skin accordion omitted color " .. entry[1])
end
for key in pairs(skin.Defaults.theme.colors) do
    assert(orderedSkinKeys[key], "Skin theme color is absent from ColorOrder: " .. key)
end
skinPaletteKeys["msufsuite.skin.color.microIconHover"].set(0.1, 0.2, 0.3, 0.4)
assert(skin.DB.theme.colors.microIconHover[1] == 0.1
    and skin.DB.theme.colors.microIconHover[4] == 0.4,
    "Skin accordion picker did not save a color outside the former inline swatches")
local fullSkinColors = { key = "opt_colors", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
current = fullSkinColors
Suite.Options.BuildColorsCategory(fullSkinColors, W.PageBuilder(fullSkinColors))
local fullSkinKeys = {}
for _, widget in ipairs(fullSkinColors.widgets) do
    if widget.meta then fullSkinKeys[widget.meta.settingKey] = true end
end
for _, entry in ipairs(skin.ColorOrder) do
    assert(fullSkinKeys["msufsuite.skin." .. entry[1]], "MSUF Colors omitted Skin color " .. entry[1])
end
-- Switching the Suite meter off hands Blizzard's meter back: the next Suite
-- refresh drops the built page, and the rebuilt page styles Blizzard's meter.
-- (The header switch above re-applied every module, and the harness failed to
-- load the meter again.)
do
S.states.damageMeter.error = nil
local invalidated
M.InvalidatePage = function(key) invalidated = key end
local ownedSkinContext = { key = "suite_skin", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
current = ownedSkinContext
M.pages.suite_skin.build(ownedSkinContext)
optionsNS.Refresh()
assert(invalidated == nil, "Skinning rebuilt without a damage meter change")
S.Config("damageMeter").enabled = false
assert(not S.OwnsBlizzardSurface("damageMeter"), "a disabled Suite meter still owns Blizzard's meter")
optionsNS.Refresh()
assert(invalidated == "suite_skin", "Skinning kept the Suite meter shape after the meter was switched off")
local meterSkinContext = { key = "suite_skin", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
current = meterSkinContext
M.pages.suite_skin.build(meterSkinContext)
assert(meterSkinContext.sections[6].sectionId == "suite_skin_hud"
    and meterSkinContext.sections[7].sectionId == "suite_skin_material",
    "Blizzard damage meter styling is missing while Blizzard's meter is in use")
local meterToggle
for _, widget in ipairs(meterSkinContext.widgets) do
    if widget.meta and widget.meta.settingKey == "msufsuite.skin.skins.damageMeter" then meterToggle = widget end
end
assert(meterToggle, "Blizzard damage meter toggle missing")
S.Config("damageMeter").enabled = true
invalidated = nil
optionsNS.Refresh()
assert(invalidated == "suite_skin", "Skinning kept Blizzard's meter section after the Suite meter returned")
M.InvalidatePage = nil
end
S.states.damageMeter.error = meterLoadError
current = skinContext
MapkoSkin = nil
local covered = {}
for _, ctx in pairs(contexts) do
    for _, widget in ipairs(ctx.widgets) do
        local meta = widget.meta
        local path = meta and meta.settingKey
        if path then covered[path] = true end
    end
end
for key in pairs(shortcutColors) do covered[key] = true end
for key in pairs(globalColors) do covered[key] = true end
covered._nameplatePreviewPositions = {}
for _, widget in pairs(registeredControls) do
    if widget.previewUI and widget.keyX and widget.keyY then
        covered._nameplatePreviewPositions[widget.keyX] = true
        covered._nameplatePreviewPositions[widget.keyY] = true
    end
end
local checked = 0
for _, id in ipairs(Suite.SuiteOrder) do
    for key, rule in pairs(Suite.SuiteCatalog[id].rules) do
        local template = key:gsub("^bar%d+", "bar1"):gsub("^w%d+", "w1")
        if id == "cooldownManager" and rule.suffix then template = "c1_" .. rule.suffix end
        if not rule.hidden and not rule.previewOnly then
            if id == "nameplates" and key:match("Offset[XY]$") then
                assert(covered._nameplatePreviewPositions[key], "nameplate position has no preview handle: " .. key)
                assert(not covered["msufsuite.nameplates." .. key],
                    "nameplate X/Y slider survived outside the preview: " .. key)
            else
                assert(covered["msufsuite." .. id .. "." .. template], "no menu control for " .. id .. "." .. key)
            end
            checked = checked + 1
        end
    end
end
assert(checked > 500 and not covered["msufsuite.actionbars.bar2Size"], "coverage check is vacuous")
assert(not covered["msufsuite.minimap.buttonTrackingX"]
    and not covered["msufsuite.minimap.infoClockY"]
    and not covered["msufsuite.minimap.styleX"],
    "minimap preview position values leaked back into the accordion")

-- Per-bar controls follow the selected bar.
local function Find(ctx, predicate)
    for _, widget in ipairs(ctx.widgets) do if predicate(widget) then return widget end end
end
local function ColorTarget(ctx, sectionId, settingKey)
    for _, section in ipairs(ctx.sections) do
        if section.sectionId == sectionId and type(section.colorShortcut) == "table" then
            for _, target in ipairs(section.colorShortcut.options.getTargets()) do
                if target.sourceSettingKey == settingKey or target.settingKey == settingKey then return target end
            end
        end
    end
end
local bars = contexts.suite_actionbars
current = bars
local quick2 = Find(bars, function(w) return w.meta and tostring(w.meta.controlId):find("quick%.bar2") end)
local quick3 = Find(bars, function(w) return w.meta and tostring(w.meta.controlId):find("quick%.bar3") end)
local quick6 = Find(bars, function(w) return w.meta and tostring(w.meta.controlId):find("quick%.bar6") end)
assert(quick2 and quick3 and quick6 and quick3.get() and quick6.get(), "quick bar switches missing")
assert(quick3.meta.settingKey == "msufsuite.actionbars.bar3Visibility", "quick switch search route")
quick3.set(false)
assert(S.Config("actionbars").bar3Visibility == 6 and S.Config("actionbars").bar3ResumeVisibility == 4,
    "turning off a bar lost mouseover visibility")
quick3.set(true)
assert(S.Config("actionbars").bar3Visibility == 4, "turning on a bar did not restore mouseover")
S.Config("actionbars").bar2Visibility = 2
quick2.set(false)
assert(S.Config("actionbars").bar2ResumeVisibility == 2 and not quick2.get(), "combat visibility not saved")
quick2.set(true)
assert(S.Config("actionbars").bar2Visibility == 2, "combat visibility not restored")
quick6.set(false)
assert(S.Config("actionbars").bar6Visibility == 6, "unused bar did not turn off")
quick6.set(true)
assert(S.Config("actionbars").bar6Visibility == 4, "bar did not restore mouseover")
local picker = Find(bars, function(w) return w.meta and tostring(w.meta.controlId):find("editor%.selected") end)
local size = Find(bars, function(w) return w.meta and w.meta.settingKey == "msufsuite.actionbars.bar1Size" end)
assert(picker and size, "action bar editor controls missing")
picker.set(12)
assert(size.get() == S.Config("actionbars").bar12Size, "per-bar control did not follow the selection")
local barBackground
for _, section in ipairs(bars.sections) do
    if section.sectionId == "suite_actionbars_bar_background" then barBackground = section; break end
end
local barColor = barBackground and barBackground.colorShortcut
    and barBackground.colorShortcut.options.getTargets()[1]
assert(barColor and barColor.settingKey == "msufsuite.actionbars.bar12BackgroundColor",
    "Action bar color shortcut does not follow the selected bar")
local previousBarColor = S.Config("actionbars").bar12BackgroundColor
barColor.set(0x12/255, 0x34/255, 0x56/255)
assert(S.Config("actionbars").bar12BackgroundColor == "123456",
    "Action bar color shortcut wrote to the wrong bar")
S.Config("actionbars").bar12BackgroundColor = previousBarColor
size.set(44)
assert(S.Config("actionbars").bar12Size == 44 and S.Config("actionbars").bar1Size ~= 44, "per-bar write hit the wrong bar")
local macro = Find(bars, function(w) return w.meta and w.meta.settingKey == "msufsuite.actionbars.bar1Macro" end)
S.Config("actionbars").enabled = true
M.RequestRefresh()
assert(size.enabled == true, "per-bar size locked on an enabled module")
assert(macro.enabled == false, "hidden per-bar option stays editable on the pet bar")
picker.set(1)
M.RequestRefresh()
assert(macro.enabled == true, "macro option locked on action bar 1")

-- Windows of the damage meter follow the window picker.
local dm = contexts.suite_damageMeter
current = dm
local windowPicker = Find(dm, function(w) return w.meta and tostring(w.meta.controlId):find("window%.selected") end)
local windowType = Find(dm, function(w) return w.meta and w.meta.settingKey == "msufsuite.damageMeter.w1Type" end)
windowPicker.set(3)
assert(windowType.get() == S.Config("damageMeter").w3Type)
local dmConfig = S.Config("damageMeter")
local meterLook = Find(dm, function(w) return w.meta and w.meta.settingKey == "msufsuite.damageMeter.look" end)
local meterBorder = ColorTarget(dm, "suite_damageMeter_window", "msufsuite.damageMeter.borderColor")
assert(meterLook and meterBorder and dmConfig.look == 2 and dmConfig.borderColor == "575b58",
    "Midnight Dark damage meter look is missing from the menu")
meterLook.set(2)
assert(dmConfig.look == 2 and dmConfig.bgColor == "151719" and dmConfig.borderColor == "575b58",
    "Midnight Dark damage meter preset did not apply its complete palette")
meterLook.set(3)
assert(dmConfig.look == 3 and dmConfig.bgColor == "14181b" and dmConfig.borderColor == "9f8960",
    "Forever damage meter preset did not apply its complete palette")
meterBorder.set(0x12/255, 0x34/255, 0x56/255)
assert(dmConfig.look == 4 and dmConfig.borderColor == "123456",
    "changing a meter color did not mark the look Custom")
meterLook.set(1)
assert(dmConfig.look == 1 and dmConfig.borderColor == "41627a",
    "Midnight damage meter preset did not restore its palette")
local combatTime = Find(dm, function(w) return w.meta and w.meta.settingKey == "msufsuite.damageMeter.combatTime" end)
local headerTimer = Find(dm, function(w) return w.meta and w.meta.settingKey == "msufsuite.damageMeter.headerTimer" end)
local floatingTimer = Find(dm, function(w) return w.meta and w.meta.settingKey == "msufsuite.damageMeter.timer" end)
local timerSize = Find(dm, function(w) return w.meta and w.meta.settingKey == "msufsuite.damageMeter.timerSize" end)
local rendering = Find(dm, function(w) return w.meta and w.meta.settingKey == "msufsuite.damageMeter.rendering" end)
local showRealm = Find(dm, function(w) return w.meta and w.meta.settingKey == "msufsuite.damageMeter.showRealm" end)
local shadowOpacity = Find(dm, function(w) return w.meta and w.meta.settingKey == "msufsuite.damageMeter.shadowOpacity" end)
local ellipsis = Find(dm, function(w) return w.meta and w.meta.settingKey == "msufsuite.damageMeter.nameEllipsis" end)
local gradientSwitch = Find(dm, function(w) return w.meta and w.meta.settingKey == "msufsuite.damageMeter.gradientEnabled" end)
local gradientStrength = Find(dm, function(w) return w.meta and w.meta.settingKey == "msufsuite.damageMeter.gradientStrength" end)
local gradientColor = ColorTarget(dm, "suite_damageMeter_bars", "msufsuite.damageMeter.gradientColor")
local gradientButtons = {}
for _, key in ipairs({ "gradientDirLeft", "gradientDirRight", "gradientDirUp", "gradientDirDown" }) do
    gradientButtons[key] = registeredControls["menu2.suite_damageMeter.damageMeter." .. key]
    assert(gradientButtons[key] and gradientButtons[key].scripts.OnClick,
        "gradient D-pad direction missing: " .. key)
end
assert(combatTime and headerTimer and floatingTimer and timerSize and rendering and showRealm and shadowOpacity and ellipsis,
    "damage meter time and text controls missing")
assert(gradientSwitch and gradientStrength and gradientColor and dmConfig.gradientEnabled==false
    and dmConfig.gradientDirRight==true,"gradient controls or defaults missing")
assert(dmConfig.showRealm==false,"server-name toggle must default to hidden")
dmConfig.enabled = true
M.RequestRefresh()
assert(not gradientStrength.enabled
    and not gradientButtons.gradientDirRight.enabled,"disabled gradient still editable")
gradientSwitch.set(true)
assert(gradientStrength.enabled and gradientColor
    and gradientButtons.gradientDirRight.enabled and gradientButtons.gradientDirRight.active,
    "enabled gradient did not activate strength, color and D-pad")
gradientButtons.gradientDirRight.scripts.OnClick()
assert(dmConfig.gradientDirRight,"D-pad removed its last active direction")
gradientButtons.gradientDirLeft.scripts.OnClick()
assert(dmConfig.gradientDirLeft and dmConfig.gradientDirRight,"D-pad did not support multiple directions")
gradientButtons.gradientDirRight.scripts.OnClick()
assert(dmConfig.gradientDirLeft and not dmConfig.gradientDirRight,"D-pad failed to turn off one of several directions")
gradientSwitch.set(false)
assert(not gradientButtons.gradientDirLeft.enabled and dmConfig.gradientDirLeft,
    "disabling the gradient lost the chosen direction")
dmConfig.combatTime = false
M.RequestRefresh()
assert(not headerTimer.enabled and not floatingTimer.enabled and not timerSize.enabled,
    "master combat time switch did not disable subordinate controls")
dmConfig.combatTime = true
dmConfig.rendering = 3
dmConfig.nameMaxChars = 0
M.RequestRefresh()
assert(headerTimer.enabled and floatingTimer.enabled and not shadowOpacity.enabled and not ellipsis.enabled,
    "Slug shadow or name shortening dependencies are wrong")
dmConfig.rendering = 1
dmConfig.outline = 1
dmConfig.nameMaxChars = 8
M.RequestRefresh()
assert(shadowOpacity.enabled and ellipsis.enabled, "text controls did not re-enable")

-- Enable gating: module off disables its controls; dependencies apply.
local mm = contexts.suite_minimap
current = mm
local zoomReset = Find(mm, function(w) return w.meta and w.meta.settingKey == "msufsuite.minimap.zoomResetSeconds" end)
local landing = Find(mm, function(w) return w.meta and w.meta.settingKey == "msufsuite.minimap.showLanding" end)
local landingIcon = Find(mm, function(w) return w.meta and w.meta.settingKey == "msufsuite.minimap.landingIcon" end)
S.Config("minimap").enabled = false
M.RequestRefresh()
assert(zoomReset.enabled == false, "control of a disabled module is editable")
S.Config("minimap").enabled = true
S.Config("minimap").scrollZoom = true
local priorLandingAvailable = S.MinimapElementAvailable
S.MinimapElementAvailable = function() return false end
M.RequestRefresh()
assert(zoomReset.enabled == true, "control of an enabled module stays disabled")
assert(landing and landing.enabled and landingIcon and landingIcon.enabled,
    "Retail expansion button controls must be editable before Blizzard creates the button")
S.MinimapElementAvailable = priorLandingAvailable
S.Config("minimap").scrollZoom = false
M.RequestRefresh()
assert(zoomReset.enabled == false, "enableKey dependency ignored")
local stylePreset = Find(mm, function(w) return w.meta and w.meta.settingKey == "msufsuite.minimap.stylePreset" end)
local styleColor = ColorTarget(mm, "suite_minimap_style_art", "msufsuite.minimap.styleColor")
local stylePath = Find(mm, function(w) return w.meta and w.meta.settingKey == "msufsuite.minimap.styleTexturePath" end)
assert(stylePreset and styleColor and stylePath, "minimap style editor controls missing")
stylePreset.set(3)
assert(S.Config("minimap").shape == 2 and S.Config("minimap").styleTexture == 2
    and S.Config("minimap").styleGlow and stylePreset.get() == 3, "Arcane preset did not apply a complete style")
styleColor.set(0.2, 0.4, 0.6)
assert(S.Config("minimap").stylePreset == 1 and S.Config("minimap").styleColor == "336699",
    "tuning a preset did not preserve edits as Custom")
S.Config("minimap").styleTexture = 6
M.RequestRefresh()
assert(stylePath.enabled, "custom artwork path did not unlock")
stylePreset.set(2)
M.RequestRefresh()
assert(S.Config("minimap").shape == 1 and S.Config("minimap").styleTexture == 1 and not stylePath.enabled,
    "Clean preset failed to restore default style")
stylePreset.set(9)
assert(S.Config("minimap").stylePreset == 9
    and S.Config("minimap").borderColor == "575b58",
    "Midnight Dark minimap preset did not apply")
assert(registeredControls["menu2.suite_minimap.minimap.style.preset.10"],
    "Antique Map tile is missing from the minimap page")
registeredControls["menu2.suite_minimap.minimap.style.preset.10"].scripts.OnClick()
assert(S.Config("minimap").stylePreset == 10 and S.Config("minimap").styleTexture == 7
    and S.Config("minimap").styleScale == 130 and S.Config("minimap").styleX == 0
    and S.Config("minimap").borderSize == 0 and S.Config("minimap").shape == 1,
    "Antique Map tile did not apply its complete style")
assert(stylePreset.get() == 10, "Antique Map selection did not persist in the menu")
stylePreset.set(2)
local barsLook = Find(contexts.suite_actionbars, function(w)
    return w.meta and w.meta.settingKey == "msufsuite.actionbars.look"
end)
local bagsLook = Find(contexts.suite_bags, function(w)
    return w.meta and w.meta.settingKey == "msufsuite.bags.look"
end)
assert(barsLook and bagsLook, "Action Bars or Bags look selector missing")
barsLook.set(2)
assert(S.Config("actionbars").look == 2 and S.Config("actionbars").borderColor == "575b58")
barsLook.set(1)
assert(S.Config("actionbars").look == 1 and S.Config("actionbars").borderColor == "41627a")
bagsLook.set(2)
assert(S.Config("bags").look == 2 and S.Config("bags").backgroundColor == "151719")
bagsLook.set(3)
assert(S.Config("bags").look == 3 and S.Config("bags").accentColor == "9f8960")
-- The minimap preview draws an information text in its chosen font through
-- the core resolver, also while the module runtime is not loaded.
do
    assert(S.ResolveFont == nil, "this check needs the module runtime unloaded")
    local config, styled, fonts = S.Config("minimap"), optionsNS.StylePreviewFont, {}
    local shown, font = config.infoClock, config.infoClockFont
    config.infoClock, config.infoClockFont = true, "Interface\\AddOns\\Test\\Clock.ttf"
    optionsNS.StylePreviewFont = function(label, path, ...)
        fonts[#fonts + 1] = path
        return styled(label, path, ...)
    end
    current = mm
    M.RequestRefresh()
    optionsNS.StylePreviewFont = styled
    config.infoClock, config.infoClockFont = shown, font
    local found = false
    for _, path in ipairs(fonts) do if path == "Interface\\AddOns\\Test\\Clock.ttf" then found = true end end
    assert(found, "the minimap preview ignored the clock's chosen font")
end
local focusedSection, focusOpts
W.FocusCollapsibleSection = function(section, opts)
    focusedSection, focusOpts = section.sectionId, opts
    return true
end
local folioPreview = previewControls["menu2.suite_minimap.minimap.preview.folio"]
local stylePreview = previewControls["menu2.suite_minimap.minimap.preview.style"]
local clockPreview = previewControls["menu2.suite_minimap.minimap.preview.infoClock"]
local locationPreview = previewControls["menu2.suite_minimap.minimap.preview.infoLocation"]
assert(folioPreview and stylePreview and clockPreview and locationPreview, "minimap preview targets missing")
for key, section in pairs({ map = "layout", style = "shape", ornament = "style_art", ornament_bottom = "style_art",
    ornament_left = "style_art", ornament_right = "style_art", zoomIn = "behavior", zoomOut = "behavior",
    compass = "behavior", tracking = "elements",
    calendar = "elements", mail = "elements", crafting = "elements", difficulty = "elements",
    compartment = "elements", drawer = "addons", infoFPS = "info_fps",
    infoLatency = "info_latency", infoCoordinates = "info_coordinates",
    infoDurability = "info_durability", infoLocation = "info_location", infoWeather = "info_weather",
    infoDifficulty = "info_difficulty", folio = "landing" }) do
    local target = previewControls["menu2.suite_minimap.minimap.preview." .. key]
    assert(target and target.scripts.OnClick, "minimap preview lacks " .. key)
    target.scripts.OnClick(target)
    assert(focusedSection == "suite_minimap_" .. section, "minimap preview routed " .. key .. " incorrectly")
end
local fixed = mm.fixedPreview
local selectionBox = fixed.section.expander.box
local selectedButton = previewControls["menu2.suite_minimap.minimap.preview.tracking"]
selectedButton.scripts.OnClick(selectedButton)
assert(fixed.section.expander.expanded and selectionBox._selectedHandle == selectedButton,
    "jumping to Blizzard settings lost the fixed preview or its selection")
assert(rawget(selectionBox, "picker") == nil, "minimap has a duplicate element picker")
local offsets = selectionBox.selectionDeps
local originalX, originalY = offsets.ReadOffsets(selectionBox, selectedButton)
assert(offsets.WriteOffsets(selectionBox, selectedButton, originalX + 3, originalY - 2)
    and selectionBox.selectionX == originalX + 3 and selectionBox.selectionY == originalY - 2,
    "exact X/Y fields did not write through the minimap controller")
assert(offsets.NudgeDelta(selectionBox, -1, 1)
    and S.Config("minimap").buttonTrackingX == originalX + 2
    and S.Config("minimap").buttonTrackingY == originalY - 1,
    "selection bar plus/minus did not nudge the Blizzard button")
assert(offsets.ResetOffsets(selectionBox, selectedButton)
    and S.Config("minimap").buttonTrackingX == Suite.SuiteCatalog.minimap.rules.buttonTrackingX.default
    and S.Config("minimap").buttonTrackingY == Suite.SuiteCatalog.minimap.rules.buttonTrackingY.default,
    "selection bar reset did not restore defaults")
offsets.OpenSettings(selectionBox, selectedButton)
assert(focusedSection == "suite_minimap_elements" and fixed.section.expander.expanded,
    "selection bar settings jump displaced the fixed preview")
local glowLayer = previewControls["menu2.suite_minimap.minimap.preview.layer.glow"]
assert(glowLayer and glowLayer.scripts.OnClick, "glow preview layer missing")
glowLayer.scripts.OnClick(glowLayer, "RightButton")
assert(focusedSection == "suite_minimap_style_glow", "right-clicking a layer did not open its settings")
local drawerPreview = previewControls["menu2.suite_minimap.minimap.preview.drawer"]
local originalIsAddOnLoaded = Suite.Client.IsAddOnLoaded
Suite.Client.IsAddOnLoaded = function(name)
    if name == "MinimapButtonButton" then return true end
    return originalIsAddOnLoaded(name)
end
M.RequestRefresh()
assert(not drawerPreview.shown, "MBB should hide the Suite drawer preview")
Suite.Client.IsAddOnLoaded = originalIsAddOnLoaded
M.RequestRefresh()
assert(drawerPreview.shown, "Suite drawer preview did not return without MBB")
S.Config("minimap").showLanding = 3
M.RequestRefresh()
assert(not folioPreview.shown, "disabled Folio still appears in the normal preview")
local hiddenLayer = previewControls["menu2.suite_minimap.minimap.preview.layer.hidden"]
assert(hiddenLayer and hiddenLayer.scripts.OnClick, "hidden-element layer missing")
hiddenLayer.scripts.OnClick()
assert(folioPreview.shown and folioPreview.alpha == 0.38, "hidden Folio cannot be selected in the Hidden layer")
local folioLayer = previewControls["menu2.suite_minimap.minimap.preview.layer.folio"]
assert(folioLayer and folioLayer.scripts.OnClick, "Folio preview layer missing")
folioLayer.scripts.OnClick()
assert(not folioPreview.shown, "Folio preview layer did not hide its icon")
folioLayer.scripts.OnClick()
assert(folioPreview.shown and folioPreview.alpha == 0.38, "Folio preview layer did not restore its ghost icon")
local mapPreview = previewControls["menu2.suite_minimap.minimap.preview.map"]
local mapX, mapY = S.Config("minimap").x, S.Config("minimap").y
local mapCursorX, mapCursorY = 100, 100
GetCursorPosition = function() return mapCursorX, mapCursorY end
mapPreview.scripts.OnDragStart(mapPreview)
mapCursorX, mapCursorY = 110, 94
mapPreview.scripts.OnDragStop(mapPreview)
assert(S.Config("minimap").x > mapX and S.Config("minimap").y < mapY
    and fixed.section.expander.box._selectedHandle == mapPreview,
    "dragging the map did not update its position")
S.Config("minimap").shape = 3
M.RequestRefresh()
assert(mapPreview.width == 190 and mapPreview.height == 127, "wide preview did not follow runtime map aspect")
S.Config("minimap").shape = 1
M.RequestRefresh()
folioPreview.scripts.OnClick()
assert(focusedSection == "suite_minimap_landing" and focusOpts.persist and focusOpts.flash,
    "Folio preview did not reveal its accordion")
stylePreview.scripts.OnClick()
assert(focusedSection == "suite_minimap_shape", "style preview did not reveal border and shadow")
hiddenLayer.scripts.OnClick()
local priorPreviewShown = S.MinimapElementPreviewShown
S.MinimapElementPreviewShown = function(key) if key == "Mail" then return false end return nil end
M.RequestRefresh()
assert(not previewControls["menu2.suite_minimap.minimap.preview.mail"].shown,
    "Blizzard-hidden mail indicator remained in the normal preview")
local difficultyPreview = previewControls["menu2.suite_minimap.minimap.preview.difficulty"]
local priorDifficultySource = S.MinimapDifficultyPreviewSource
local function NativeTexture(atlas)
    return {
        IsShown = function() return true end,
        GetAtlas = function() return atlas end,
        GetTexCoord = function() return 0, 1, 0, 1 end,
        GetVertexColor = function() return 1, 1, 1, 1 end,
        GetAlpha = function() return 1 end,
        GetSize = function() return 35.5, 36.5 end,
        GetCenter = function() return 100, 100 end,
    }
end
local difficultyFrame = { GetSize = function() return 35.5, 36.5 end,
    GetCenter = function() return 100, 100 end }
local difficultyMode = { Background = NativeTexture("ui-hud-minimap-guildbanner-background-top"),
    Border = NativeTexture("ui-hud-minimap-guildbanner-border-top"),
    DifficultyTextures = { NativeTexture("ui-hud-minimap-guildbanner-mythic-large") } }
S.MinimapDifficultyPreviewSource = function() return difficultyFrame, difficultyMode end
S.MinimapElementPreviewShown = function(key) if key == "Difficulty" then return true end return nil end
M.RequestRefresh()
assert(difficultyPreview.previewNative.background.atlas == "ui-hud-minimap-guildbanner-background-top"
    and difficultyPreview.previewNative.glyph.atlas == "ui-hud-minimap-guildbanner-mythic-large"
    and difficultyPreview.previewIcon.shown == false and math.abs(difficultyPreview.width - 35.5) < 0.01,
    "difficulty preview did not mirror the native banner art: "
        .. tostring(difficultyPreview.previewNative.background.atlas) .. "/"
        .. tostring(difficultyPreview.previewNative.glyph.atlas) .. "/"
        .. tostring(difficultyPreview.previewIcon.shown) .. "/"
        .. tostring(S.Config("minimap").showDifficulty) .. "/"
        .. tostring(S.Config("minimap").infoDifficulty))
S.MinimapElementPreviewShown = function(key) if key == "Difficulty" then return false end return nil end
M.RequestRefresh()
assert(not difficultyPreview.shown, "difficulty preview showed a banner hidden by Blizzard")
S.MinimapDifficultyPreviewSource = priorDifficultySource
S.MinimapElementPreviewShown = priorPreviewShown
M.RequestRefresh()
local cursorX, cursorY = 100, 100
GetCursorPosition = function() return cursorX, cursorY end
local oldX, oldY = S.Config("minimap").infoClockX, S.Config("minimap").infoClockY
clockPreview.scripts.OnDragStart(clockPreview)
cursorX, cursorY = 109, 96
clockPreview.scripts.OnDragStop(clockPreview)
assert(S.Config("minimap").infoClockX > oldX and S.Config("minimap").infoClockY < oldY,
    "dragging a preview text did not save both offsets")
assert(focusedSection == "suite_minimap_info_clock", "dragging a text did not reveal its accordion")
previewControls["menu2.suite_minimap.minimap.preview.map"].GetCenter = function() return 100, 100 end
local trackingPreview = previewControls["menu2.suite_minimap.minimap.preview.tracking"]
local calendarPreview = previewControls["menu2.suite_minimap.minimap.preview.calendar"]
local calendarX = S.Config("minimap").buttonCalendarX
cursorX, cursorY = 100, 100
trackingPreview.scripts.OnDragStart(trackingPreview)
cursorX, cursorY = 140, 100
trackingPreview.scripts.OnDragStop(trackingPreview)
assert(S.Config("minimap").buttonTrackingX == 40 and S.Config("minimap").buttonCalendarX == calendarX
    and focusedSection == "suite_minimap_elements",
    "dragging a Blizzard button did not save an independent position")
cursorX, cursorY = 100, 100
calendarPreview.scripts.OnDragStart(calendarPreview)
cursorX, cursorY = 85, 120
calendarPreview.scripts.OnDragStop(calendarPreview)
assert(S.Config("minimap").buttonCalendarX == calendarX - 15
    and S.Config("minimap").buttonCalendarY == 20,
    "second Blizzard button did not keep its own position")
cursorX, cursorY = 100, 100
drawerPreview.scripts.OnDragStart(drawerPreview)
cursorX, cursorY = 125, 90
drawerPreview.scripts.OnDragStop(drawerPreview)
assert(S.Config("minimap").drawerX == 25 and S.Config("minimap").drawerY == -10,
    "dragging the addon drawer did not save a free position")
local zoomPreview = previewControls["menu2.suite_minimap.minimap.preview.zoomIn"]
cursorX, cursorY = 100, 100
zoomPreview.scripts.OnDragStart(zoomPreview)
cursorX, cursorY = 120, 110
zoomPreview.scripts.OnDragStop(zoomPreview)
assert(S.Config("minimap").zoomInX == 20 and S.Config("minimap").zoomInY == 10,
    "dragging a zoom button did not save its position")
local ornamentPreview = previewControls["menu2.suite_minimap.minimap.preview.ornament"]
S.Config("minimap").styleTexture = 2
M.RequestRefresh()
cursorX, cursorY = 100, 100
ornamentPreview.scripts.OnDragStart(ornamentPreview)
cursorX, cursorY = 110, 107
ornamentPreview.scripts.OnDragStop(ornamentPreview)
assert(S.Config("minimap").styleX == 10 and S.Config("minimap").styleY == 7
    and S.Config("minimap").stylePreset == 1
    and selectionBox._selectedHandle == ornamentPreview,
    "decorative border preview did not save its position")
hiddenLayer.scripts.OnClick()
local folioStartX, folioStartY = S.Config("minimap").landingX, S.Config("minimap").landingY
cursorX, cursorY = 100, 100
folioPreview.scripts.OnDragStart(folioPreview)
cursorX, cursorY = 80, 80
folioPreview.scripts.OnDragStop(folioPreview)
assert(S.Config("minimap").landingX ~= folioStartX and S.Config("minimap").landingY ~= folioStartY
    and focusedSection == "suite_minimap_landing", "dragging Folio did not save its corner offsets")
GetZoneText = function() return "Dornogal" end
M.RequestRefresh()
assert(locationPreview.width < S.Config("minimap").infoLocationWidth * 0.75,
    "location preview click area still spans neighbouring FPS/latency text")
local tooltip = { shown = false }
function tooltip:SetOwner(owner) self.owner = owner end
function tooltip:SetText(value) self.text = value end
function tooltip:AddLine(value) self.detail = value end
function tooltip:Show() self.shown = true end
function tooltip:IsOwned(owner) return self.owner == owner end
function tooltip:Hide() self.shown = false end
GameTooltip = tooltip
locationPreview.scripts.OnEnter(locationPreview)
assert(tooltip.shown and tooltip.text == "Location" and locationPreview._hoverFill.shown,
    "location preview has no guided hover target")
locationPreview.scripts.OnLeave(locationPreview)
assert(not tooltip.shown and not locationPreview._hoverFill.shown,
    "location preview hover guidance did not clear")
local locationX, locationY = S.Config("minimap").infoLocationX, S.Config("minimap").infoLocationY
cursorX, cursorY = 100, 100
locationPreview.scripts.OnMouseDown(locationPreview, "LeftButton")
assert(locationPreview.moving, "mouse press did not start the preview drag")
cursorX, cursorY = 113, 92
locationPreview.scripts.OnMouseUp(locationPreview, "LeftButton")
assert(not locationPreview.moving and S.Config("minimap").infoLocationX > locationX
    and S.Config("minimap").infoLocationY < locationY
    and focusedSection == "suite_minimap_info_location", "real mouse drag did not move Dornogal")
assert(arrowBinding and arrowBinding.enabled and arrowBinding.box == selectionBox
    and locationPreview.keyboardEnabled, "selected minimap element did not capture arrow keys")
local arrowX, arrowY = S.Config("minimap").infoLocationX, S.Config("minimap").infoLocationY
selectionBox.scripts.OnKeyDown(selectionBox, "RIGHT")
assert(S.Config("minimap").infoLocationX == arrowX + 1 and selectionBox.selectionX == arrowX + 1,
    "right arrow did not move the selected preview element and refresh X")
locationPreview.scripts.OnKeyDown(locationPreview, "LEFT")
assert(S.Config("minimap").infoLocationX == arrowX,
    "focused location handle did not accept arrow keys")
IsShiftKeyDown = function() return true end
selectionBox.scripts.OnKeyDown(selectionBox, "UP")
IsShiftKeyDown = function() return false end
assert(S.Config("minimap").infoLocationY == arrowY + 5 and selectionBox.selectionY == arrowY + 5,
    "Shift+Up did not move the selected preview element by five")
IsControlKeyDown = function() return true end
arrowBinding.spec.onClick(selectionBox, -1, 0)
IsControlKeyDown = function() return false end
assert(S.Config("minimap").infoLocationX == arrowX - 10,
    "Ctrl+Left secure preview binding did not move the selected element by ten")
GetCurrentKeyBoardFocus = function() return { IsObjectType = function(_, kind) return kind == "EditBox" end } end
selectionBox.scripts.OnKeyDown(selectionBox, "RIGHT")
GetCurrentKeyBoardFocus = function() return nil end
assert(S.Config("minimap").infoLocationX == arrowX - 10,
    "preview arrow key moved an element while a text field had focus")
selectionBox.shown = false
selectionBox.scripts.OnHide(selectionBox)
assert(not arrowBinding.enabled and not locationPreview.keyboardEnabled,
    "hiding the minimap preview left its arrow binding active")
selectionBox.shown = true
selectionBox.scripts.OnShow(selectionBox)
assert(arrowBinding.enabled and locationPreview.keyboardEnabled,
    "showing the minimap preview did not restore its selected arrow target")
stylePreview.scripts.OnClick(stylePreview)
assert(not arrowBinding.enabled and not locationPreview.keyboardEnabled,
    "selecting a non-movable layer did not release preview arrow keys")
selectionBox.scripts.OnKeyDown(selectionBox, "RIGHT")
assert(S.Config("minimap").infoLocationX == arrowX - 10,
    "arrow key moved an element after the preview selection was cleared")
GameTooltip = neutralTooltip
GetZoneText = function() return "" end
for _, id in ipairs({ "minimap", "actionbars", "damageMeter", "bags", "dataTexts", "xpBar", "skyriding", "chat" }) do
    S.Config(id).enabled = true
end
-- A history snapshot copies the active profile and root flags only; other
-- profiles and runtime logs are neither copied nor rolled back.
Suite.RootDB.profiles.Other = { suite = { schema = 1, modules = {} } }
Suite.RootDB.suiteChat = { lines = { "kept" } }
local beforeStyle = historyProvider.capture()
assert(beforeStyle.root.profiles.Other == nil and beforeStyle.root.suiteChat == nil
    and beforeStyle.root.profiles[Suite.RootDB.activeProfile],
    "Suite history copied more than the active profile")
Suite.RootDB.profiles.Other.marker = true
local clockVisible, barVisibility, meterType = S.Config("minimap").infoClock,
    S.Config("actionbars").bar1Visibility, S.Config("damageMeter").w1Type
assert(Suite.Options.ApplyForeverStyle(), "Suite Forever style did not apply")
assert(S.Config("minimap").stylePreset == 7 and S.Config("minimap").styleGlowColor == "d8b66a"
    and S.Config("actionbars").borderColor == "9f8960"
    and S.Config("damageMeter").bgColor == "14181b"
    and S.Config("bags").backgroundColor == "14181b"
    and S.Config("dataTexts").look == 3 and S.Config("xpBar").look == 3
    and S.Config("skyriding").look == 3
    and S.Config("skyriding").panelColor == "14181b",
    "Forever style missed a core module")
assert(S.Config("minimap").infoClock == clockVisible
    and S.Config("actionbars").bar1Visibility == barVisibility
    and S.Config("damageMeter").w1Type == meterType, "Forever style changed behavior or layout")
assert(historyWrites > 0 and historyProvider.restore(beforeStyle), "Suite history restore failed")
assert(S.Config("minimap").stylePreset == beforeStyle.root.profiles[beforeStyle.root.activeProfile].suite.modules.minimap.stylePreset,
    "Suite history did not restore the minimap style")
assert(Suite.RootDB.profiles.Other.marker and Suite.RootDB.suiteChat.lines[1] == "kept",
    "Suite history restore touched another profile or the chat log")
Suite.RootDB.profiles.Other, Suite.RootDB.suiteChat = nil, nil
local skinRoot = { activeProfile = "Default", profiles = { Default = { theme = { look = "dark" } } },
    optionsUI = { lastPage = "colors" } }
MapkoSkin = {
    addonName = "MSUF_Suite_Skin",
    Database = { GetRoot = function() return skinRoot end, SetActiveProfile = function() return true end },
    Theme = { ApplyLook = function(look) skinRoot.profiles.Default.theme.look = look; return true end },
}
local beforeSkinStyle = historyProvider.capture()
assert(Suite.Options.ApplyForeverStyle() and skinRoot.profiles.Default.theme.look == "foreverGlass",
    "Forever suite look did not style the embedded Skinning engine")
assert(historyProvider.restore(beforeSkinStyle)
    and skinRoot.profiles.Default.theme.look == "dark"
    and skinRoot.optionsUI.lastPage == "colors", "Skinning undo lost the palette or editor state")
MapkoSkin = nil
-- A Skinning preset updates enabled visual modules and follows a module
-- enabled afterwards, without changing placement or visibility.
local globalModules = { "actionbars", "minimap", "damageMeter", "bags", "dataTexts", "chat", "buffReminders", "cooldownManager" }
for _, id in ipairs(globalModules) do S.Config(id).enabled = true end
local xp = S.Config("xpBar")
xp.enabled, xp.look = false, 3
local data = S.Config("dataTexts")
data.customColors = true
data.bar1StyleOverride, data.bar1CustomColors = true, true
local cooldowns = S.Config("cooldownManager")
cooldowns.ess_borderColor, cooldowns.ess_glowColor, cooldowns.bar_barColor = "ffffff", "ffffff", "ffffff"
local savedVisibility = S.Config("actionbars").bar1Visibility
local savedPosition = S.Config("minimap").x
assert(S.ApplyGlobalLook("midnightDark"), "Dark global look was rejected")
assert(S.Config("actionbars").look == 2 and S.Config("actionbars").borderColor == "575b58"
    and S.Config("minimap").stylePreset == 9
    and S.Config("damageMeter").look == 2 and S.Config("damageMeter").bgColor == "151719"
    and S.Config("bags").look == 2 and S.Config("bags").backgroundColor == "151719"
    and S.Config("chat").look == 2 and S.Config("chat").panelColor == "151719"
    and S.Config("actionbars").bar1BackgroundColor == "151719"
    and S.Config("buffReminders").borderColor == "575b58"
    and cooldowns.cdColor == "e9e9e4" and cooldowns.ess_borderColor == "575b58"
    and cooldowns.ess_glowColor == "b9ab86" and cooldowns.bar_barColor == "b9ab86"
    and S.Config("skyriding").look == 2
    and S.Config("skyriding").panelColor == "151719"
    and data.look == 2 and not data.customColors
    and data.bar1Look == 2 and not data.bar1CustomColors,
    "Dark global look missed an enabled Suite module or retained overriding colors")
assert(not xp.enabled and xp.look == 3 and S.Config("actionbars").bar1Visibility == savedVisibility
    and S.Config("minimap").x == savedPosition,
    "Global look enabled a module or changed layout and visibility")
assert(S.Set("xpBar", "enabled", true) and xp.look == 2,
    "newly enabled XP bar did not adopt the selected global look")

assert(S.ApplyGlobalLook("midnight"), "Blue global look was rejected")
assert(S.Config("minimap").stylePreset == 8 and S.Config("actionbars").look == 1
    and S.Config("xpBar").look == 1 and S.Config("skyriding").look == 1
    and S.Config("dataTexts").look == 1
    and S.Config("buffReminders").borderColor == "41627a"
    and cooldowns.bar_barColor == "57c7df",
    "Midnight Blue did not update Suite modules")

-- Suite pages join Menu2's Reset page toolbar; section resets touch only the
-- keys of that accordion, including dynamic bar keys.
assert(M.PageHasReset("suite_dataTexts") and M.PageHasReset("suite_hud")
    and M.PageHasReset("suite_skin") and not M.PageHasReset("unknown-suite-page"),
    "Suite page reset was not registered precisely")
local bar1X = S.catalog.dataTexts.rules.bar1X
assert(bar1X and optionsNS and optionsNS.ResetRules)
assert(S.SetMany("dataTexts", { bar1X = 47, bar2X = 58 }))
assert(optionsNS.ResetRules("dataTexts", { bar1X })
    and S.Config("dataTexts").bar1X == bar1X.default
    and S.Config("dataTexts").bar2X == 58,
    "section reset changed another bar")
assert(M.ResetPageToDefaults("suite_dataTexts")
    and S.Config("dataTexts").bar2X == S.catalog.dataTexts.rules.bar2X.default,
    "Reset page did not restore the module defaults")
assert(S.Config("actionbars").look == 1,
    "Suite page reset changed another page")
local actionRules = S.catalog.actionbars.rules
assert(actionRules.bar1X and actionRules.bar10X)
assert(S.SetMany("actionbars", { bar1X = 17, bar10X = 18 }))
assert(optionsNS.ResetPrefix("actionbars", "bar1")
    and S.Config("actionbars").bar1X == actionRules.bar1X.default
    and S.Config("actionbars").bar10X == 18,
    "bar 1 reset also changed bar 10")
local defaultLook = actionRules.look.default
assert(S.SetMany("actionbars", { look = 4, borderColor = "ffffff" }))
assert(optionsNS.ResetRules("actionbars", { actionRules.look })
    and S.Config("actionbars").look == defaultLook
    and S.Config("actionbars").borderColor == S.catalog.actionbars.look.presets[defaultLook].borderColor,
    "look section reset left custom visuals under a preset label")
-- The per-bar section menus copy the selected bar's section to another bar;
-- position never moves and other sections stay as they were.
;(function()
local barSections = {}
for _, section in ipairs(contexts.suite_actionbars.sections) do barSections[section.sectionId] = section end
for _, group in ipairs({ "visibility", "layout", "text", "background" }) do
    assert(barSections["suite_actionbars_bar_" .. group]._msufSuiteSectionCopy, group .. " section has no Copy section")
end
local layoutCopy = barSections.suite_actionbars_bar_layout._msufSuiteSectionCopy
assert(barSections.suite_actionbars_editor._msufSuiteSectionCopy == nil,
    "Customize a bar copies through Copy To, like the Unit and Group pages, not its section menu")
local source = layoutCopy.source()
local target = source == 3 and 4 or 3
local offered = false
for _, item in ipairs(layoutCopy.targets(source)) do
    assert(item.value ~= source, "a bar is offered as its own copy target")
    offered = offered or item.value == target
end
assert(offered, "another bar is missing from the copy targets")
local p, q = "bar" .. source, "bar" .. target
assert(S.SetMany("actionbars", { [p .. "Size"] = 52, [p .. "X"] = 21, [q .. "X"] = 33,
    [p .. "Background"] = true, [q .. "Background"] = false }))
assert(layoutCopy.run(source, target) == true)
local copiedConfig = S.Config("actionbars")
assert(copiedConfig[q .. "Size"] == 52, "Layout copy missed the button size")
assert(copiedConfig[q .. "X"] == 33, "Layout copy moved the target bar")
assert(copiedConfig[q .. "Background"] == false, "Layout copy changed the Background section")
assert(layoutCopy.run(source, source) == false, "a bar copied onto itself")
assert(S.SetMany("actionbars", { [q .. "Visibility"] = 6 }))
assert(layoutCopy.targetOff(target) == true and layoutCopy.targetOff(source) == false,
    "a switched-off bar is not marked like a disabled frame")
assert(S.SetMany("actionbars", { [q .. "Visibility"] = S.catalog.actionbars.rules[q .. "Visibility"].default }))

-- Copy To next to the bar choice uses MSUF's own popup: a destination row
-- without the source, one switch per section, Copy Selected, and a
-- confirmation before All.
local copyTo
for _, api in ipairs(copyPopups) do if api.opts.controlPath == "actionbars.copy" then copyTo = api end end
assert(copyTo, "Customize a bar has no Copy To")
local o = copyTo.opts
assert(o.runLabel == "Copy Selected" and o.sourceKey() == source, "Copy To does not copy from the selected bar")
local categoryKeys = {}
for _, category in ipairs(o.categories) do categoryKeys[#categoryKeys + 1] = category.key end
assert(table.concat(categoryKeys, " ") == "visibility layout text background", "Copy To categories: " .. table.concat(categoryKeys, " "))
assert(o.isTargetVisible(source, source) == false and o.isTargetVisible(target, source) == true
    and o.isTargetVisible("all", source) == true, "Copy To destinations are wrong")
o.onTargetClick(target)
assert(o.selectedTarget(source) == target, "Copy To lost the chosen destination")
for key in pairs(o.scopes) do o.scopes[key] = key == "background" end
assert(S.SetMany("actionbars", { [p .. "Background"] = true, [q .. "Background"] = false, [q .. "Size"] = 40 }))
local popupHidden
local popupStub = { Hide = function() popupHidden = true end }
o.onRun(nil, popupStub)
copiedConfig = S.Config("actionbars")
assert(popupHidden and copiedConfig[q .. "Background"] == true, "Copy Selected missed the chosen section")
assert(copiedConfig[q .. "Size"] == 40 and copiedConfig[q .. "X"] == 33, "Copy Selected copied an unchosen section or the position")
for key in pairs(o.scopes) do o.scopes[key] = false end
popupHidden = false
o.onRun(nil, popupStub)
assert(not popupHidden, "Copy Selected ran without a category")
for key in pairs(o.scopes) do o.scopes[key] = true end
local previousShow, previousInstall = _G.StaticPopup_Show, M.InstallStaticPopup
local confirmed
M.InstallStaticPopup = function() end
_G.StaticPopup_Show = function(name, _, _, accept) confirmed = name; accept() end
o.onTargetClick("all")
assert(S.SetMany("actionbars", { [p .. "Size"] = 44 }))
o.onRun(nil, popupStub)
_G.StaticPopup_Show, M.InstallStaticPopup = previousShow, previousInstall
assert(confirmed == "MSUF_SUITE_COPY_BARS_CONFIRM", "Copy to All did not ask first")
for index = 1, Suite.ActionBarCount do
    if index ~= source and (not S.ActionBarAvailable or S.ActionBarAvailable(index)) then
        assert(S.Config("actionbars")["bar" .. index .. "Size"] == 44, "Copy to All missed bar " .. index)
    end
end
o.onTargetClick(target)
end)()
local sectionButtons = {}
W.TopButton = function(_, text)
    local button = Widget("SectionAction")
    button.text = text
    sectionButtons[#sectionButtons + 1] = button
    return button
end
-- The newest section button with this text.
local function SectionButton(text)
    for i = #sectionButtons, 1, -1 do
        if sectionButtons[i].text == text then return sectionButtons[i] end
    end
end
M.CreateMenuPopupPanel = function() return Widget("SectionPopup") end
local header, outer = Widget("SectionHeader"), Widget("SectionOuter")
header.GetFrameLevel = function() return 1 end
local sectionBody = { _msuf2CollapsibleEntry = { header = header, outer = outer,
    _msuf2RefreshLayout = function() end } }
local resetCalls = 0
local sectionContext = { refreshers = {} }
local more = optionsNS.AttachSectionReset(sectionContext, sectionBody, "Test section", function()
    resetCalls = resetCalls + 1
    return true
end)
assert(more and sectionButtons[1] == more and sectionBody._msuf2CollapsibleEntry._msuf2SectionActions == more,
    "accordion reset action was not attached to its header")
more.scripts.OnClick()
local resetButton = SectionButton(optionsNS.Tr("Reset section"))
assert(resetButton and resetButton.scripts.OnClick, "Reset section menu is missing")
assert(SectionButton("x"), "the section menu has no close button like the Unit and Group menus")
resetButton.scripts.OnClick()
assert(resetCalls == 1, "Reset section action did not run")
-- With a copy spec the popup preselects the first target that is switched on,
-- lists a switched-off one as locked, copies to the chosen one, and refuses
-- once the source changed after it opened.
;(function()
local dropdowns = {}
W.Dropdown = function(_, label)
    local dropdown = Widget("Dropdown")
    dropdown.label = label
    function dropdown:SetValues(values) self.values = values end
    function dropdown:SetValue(value) self.value = value end
    function dropdown:SetOnValueChanged(fn) self.onChange = fn end
    dropdowns[#dropdowns + 1] = dropdown
    return dropdown
end
W.MoveWidget = function() end
local copySource, copied = 1, {}
local copyBody = { _msuf2CollapsibleEntry = { header = header, outer = outer,
    _msuf2RefreshLayout = function() end } }
local copyMore = optionsNS.AttachSectionReset(sectionContext, copyBody, "Copy test", function() return true end, {
    source = function() return copySource end,
    sourceLabel = function(index) return "Bar " .. index end,
    targets = function(from)
        return { { value = from + 1, text = "next" }, { value = from + 2, text = "after" }, { value = from + 3, text = "last" } }
    end,
    targetOff = function(value) return value == 2 end,
    offLabel = "Bar disabled",
    run = function(from, to) copied[#copied + 1] = from .. ">" .. to; return true end,
})
copyMore.scripts.OnClick()
local targetSelect = assert(dropdowns[1], "Copy section has no target dropdown")
assert(targetSelect.value == 3 and #targetSelect.values == 3, "the first switched-on target was not preselected")
assert(targetSelect.values[1].disabled == true and targetSelect.values[1].text:find("Bar disabled", 1, true),
    "a switched-off target is not listed as locked")
local copyButton = assert(SectionButton(optionsNS.Tr("Copy section")), "Copy section button is missing")
targetSelect.onChange(2)
copyButton.scripts.OnClick()
assert(#copied == 0, "Copy section copied onto a switched-off target")
copyMore.scripts.OnClick()
targetSelect.onChange(4)
copyButton.scripts.OnClick()
assert(copied[1] == "1>4", "Copy section did not copy to the chosen target")
copyMore.scripts.OnClick()
copySource = 2
copyButton.scripts.OnClick()
assert(#copied == 1, "Copy section used a source that changed after the popup opened")
end)()

-- Undo applies the restored settings to the modules once, also when it
-- switches the Suite profile back (the controller's profile listener applies
-- them then). Functions keep the main chunk under Lua's local limit.
;(function()
    local applies, applyAll = 0, S.ApplyAll
    S.ApplyAll = function(...)
        applies = applies + 1
        return applyAll(...)
    end
    local original = Suite.RootDB.activeProfile
    local snapshot = assert(historyProvider.capture())
    assert(historyProvider.restore(snapshot) and applies == 1, "undo applied the modules more than once")
    assert(Suite.Database.Create("Undo test", true) and Suite.Database.Activate("Undo test"))
    applies = 0
    assert(historyProvider.restore(snapshot) and Suite.RootDB.activeProfile == original,
        "undo did not switch the profile back")
    assert(applies == 1, "undoing a profile switch applied the modules more than once")
    -- An undo that also switches the skin (on in this snapshot) still applies
    -- the modules once.
    assert(snapshot.root.skinEnabled == true and Suite.Skin.enabled)
    assert(Suite.Database.Activate("Undo test") and Suite.Skin.SetEnabled(false) and not Suite.Skin.enabled)
    applies = 0
    assert(historyProvider.restore(snapshot) and Suite.RootDB.activeProfile == original
        and Suite.Skin.enabled, "undo did not restore the profile and the skin switch")
    assert(applies == 1, "undoing a profile and skin switch applied the modules more than once")
    assert(Suite.Skin.SetEnabled(false))
    applies = 0
    assert(historyProvider.restore(snapshot) and Suite.Skin.enabled and applies == 1,
        "undoing a skin switch applied the modules more than once")
    S.ApplyAll = applyAll
end)()

-- Statuses are English source text; the menu translates them when it shows
-- them, exactly once.
;(function()
    local shown
    for _, id in ipairs(S.order) do
        if not shown and S.Availability(id) then shown = id end
    end
    assert(shown, "no module is available in this fixture")
    local state = S.states[shown]
    local error = state.error
    state.error = "Stopped after an error"
    rawset(L, "Stopped after an error", "Nach einem Fehler gestoppt")
    assert(optionsNS.StatusText(shown) == "Nach einem Fehler gestoppt", "the menu did not translate the status")
    rawset(L, "Stopped after an error", nil)
    state.error = error
end)()

;(function()
    local button = assert(registeredControls["menu2.suite_dataTexts.dataTexts.bar2.antiqueFooter"],
        "Antique Footer action is missing from DataTexts bar 2")
    local c = S.Config("dataTexts")
    local untouchedWidth = c.bar1Width
    button.scripts.OnClick()
    assert(c.bar2Enabled and c.bar2StyleOverride and c.bar2BagBadge
        and c.bar2BagsPercent and not c.bar2ClockLabel and c.bar2Width == 380
        and c.bar2Height == 36 and c.bar2BagBadgeSize == 38
        and c.bar2Slot1 == 3 and c.bar2Slot2 == 4 and c.bar2Slot3 == 5
        and c.bar1Width == untouchedWidth,
        "Antique Footer menu action changed the wrong bar or missed its settings")
end)()

;(function()
    local chatFont
    for _, widget in ipairs(contexts.suite_chat.widgets) do
        if widget.meta and widget.meta.settingKey == "msufsuite.chat.font" then chatFont = widget end
    end
    assert(chatFont and chatFont.row.values()[1].text == "MSUF global font (default)",
        "chat font picker must show the inherited MSUF default")
    local count = 0
    for _, entry in ipairs(chatFont.row.values()) do
        if entry.value == "__BLIZZARD_CHAT_FONT__" then count = count + 1 end
    end
    assert(count == 1, "chat font picker must offer Blizzard's font once")
end)()

print("Suite options menu: navigation, page and section reset, no inline Suite colors, color shortcuts and global Colors, per-bar/window keys, gating and locale isolation passed")
