-- Loads MSUF_Suite and MSUF_Suite_Options against a stand-in of Menu2's public
-- surface (the functions both MSUF builds share) and checks navigation
-- placement, page registration, control coverage of every catalog setting,
-- per-bar/per-window key mapping, enable gating and the locale merge.
local root = assert(arg[1], "repository root required")
-- The client's securecallfunction reports an error and returns nothing;
-- this stand-in lets errors raise, so a failing callback fails the test.
securecallfunction = function(callback, ...) return callback(...) end
local flavor = arg[2] or "Mainline"
C_PetBattles = { GetAbilityInfoByID = function() return nil end }
StaticPopup_ShowCustomGenericConfirmation = function() end
StaticPopup_Hide = function() end
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
    function w:IsVisible()
        local parent = rawget(self, "parent")
        return self.shown and (not parent or parent:IsVisible())
    end
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
    function w:GetUnboundedStringWidth() return #self.text * 7 end
    function w:CreateMaskTexture() return Widget("MaskTexture") end
    function w:GetEffectiveScale() return 1 end
    function w:SetScript(name, fn) self.scripts[name] = fn end
    function w:GetScript(name) return self.scripts[name] end
    function w:HookScript(name, fn)
        local previous = self.scripts[name]
        self.scripts[name] = function(...)
            if previous then previous(...) end
            fn(...)
        end
    end
    function w:SetEnabled(v) self.enabled = v and true or false end
    function w:IsEnabled() return self.enabled ~= false end
    function w:SetAlpha(v) self.alpha = v end
    function w:GetAlpha() return self.alpha end
    function w:SetActive(v) self.active = v and true or false end
    function w:SetAtlas(v) self.atlas = v end
    function w:SetTexture(v) self.texture = v end
    function w:SetFont(path, size, flags) self.font = { path, size, flags }; return true end
    function w:SetTextColor(...) self.textColor = { ... } end
    function w:RegisterEvent(event) self._events = self._events or {}; self._events[event] = true end
    function w:UnregisterAllEvents() self._events = {} end
    function w:SetUnit(unit) self._modelUnit = unit; self._modelReads = (self._modelReads or 0) + 1 end
    function w:CreateAnimationGroup() return Widget("AnimationGroup") end
    function w:CreateAnimation(kind)
        local animation = Widget(kind)
        self._animations = self._animations or {}
        self._animations[#self._animations + 1] = animation
        return animation
    end
    function w:SetOrder(value) self.order = value end
    function w:SetDuration(value) self.duration = value end
    function w:SetFromAlpha(value) self.fromAlpha = value end
    function w:SetToAlpha(value) self.toAlpha = value end
    function w:SetToFinalAlpha(value) self.toFinalAlpha = value end
    function w:Play() self.playCount = (rawget(self, "playCount") or 0) + 1; self.playing = true end
    function w:Stop() self.playing = false end
    function w:SetTexCoord(...) self.texCoords = { ... } end
    function w:SetScale(v) self.scale = v end
    function w:SetClipsChildren(v) self.clipsChildren = v end
    function w:SetCooldownFromDurationObject(v) self.durationObject = v end
    function w:SetCooldown(start, duration) self.cooldown = { start, duration } end
    function w:Clear() self.durationObject, self.cooldown = nil, nil end
    function w:SetColorTexture(...) self.color = { ... } end
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
UIParent = Widget("Root")
UIParent:SetSize(1920, 1080)

-- WoW client stand-ins. The neutral ones: no class, zone, map position,
-- atlas, modifier key, keyboard focus or rotating minimap.
local neutralTooltip = setmetatable({}, { __index = function() return function() end end })
GameTooltip = neutralTooltip
-- Blizzard_EditMode loads at startup; until a step allows it, Edit Mode
-- cannot be entered.
local lockedEditMode = { CanEnterEditMode = function() return false end }
EditModeManagerFrame = lockedEditMode
UnitName = function() return "Preview Player" end
GetInventoryItemTexture = function() return 134400 end
GetInventoryItemLink = function() return "|Hitem:1|h[Preview item]|h" end
UnitClass = function() return nil end
UnitIsPlayer = function() return false end
GetZoneText = function() return "" end
GetGameTime = function() return 12, 34 end
GetCVarBool = function() return false end
IsInInstance = function() return false, "none" end
C_Texture = { GetAtlasInfo = function() return nil end }
local actionPreview = { actions = {}, bindings = {}, page = 1, reads = 0, forms = {}, pet = {} }
GetActionBarPage = function() return actionPreview.page end
GetBindingKey = function(command) return actionPreview.bindings[command] end
GetBindingText = function(key) return key end
GetNumShapeshiftForms = function() return #actionPreview.forms end
GetShapeshiftFormInfo = function(index) return actionPreview.forms[index] end
GetShapeshiftFormCooldown = function() return 10, 20, 1 end
GetPetActionCooldown = function() return 30, 40, 1 end
GetPetActionInfo = function(index)
    local action = actionPreview.pet[index]
    if action then return action.name, action.icon, false end
end
C_ActionBar = {
    GetActionTexture = function(slot)
        actionPreview.reads = actionPreview.reads + 1
        return (actionPreview.actions[slot] or {}).icon
    end,
    HasAction = function(slot) return actionPreview.actions[slot] ~= nil end,
    GetActionDisplayCount = function(slot) return (actionPreview.actions[slot] or {}).count end,
    UsesActionText = function(slot) return (actionPreview.actions[slot] or {}).name ~= nil end,
    GetActionText = function(slot) return (actionPreview.actions[slot] or {}).name end,
    GetActionCooldownDuration = function(slot) return (actionPreview.actions[slot] or {}).duration end,
    GetActionCharges = function(slot) return (actionPreview.actions[slot] or {}).charges end,
    GetActionChargeDuration = function(slot) return (actionPreview.actions[slot] or {}).recharge end,
}
CreateColor = function(...) return { ... } end
C_Map = { GetBestMapForUnit = function() return nil end }
IsShiftKeyDown, IsControlKeyDown = function() return false end, function() return false end
GetCurrentKeyBoardFocus = function() return nil end
time = os.time
TimeUtil = { BetterDate = function(format) return format end }
SlashCmdList = {}
IsLoggedIn = function() return false end
InCombatLockdown = function() return false end
-- The player's combat flag follows the lockdown here (no combat start).
UnitAffectingCombat = function(unit) return unit == "player" and InCombatLockdown() == true end
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
-- Blizzard_NamePlates is always loaded, and CvarUtil is SharedXMLBase.
NamePlateSetupOptions = {}
NamePlateConstants = { DEBUFF_PADDING_CVAR = "nameplateDebuffPadding" }
GetCVarNumberOrDefault = function(name) return tonumber((C_CVar.GetCVar(name))) end
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
M.CreateMenuPopupPanel = function() return Widget("SectionPopup") end
W.TopButton = function(parent, text)
    local button = Widget("SectionAction")
    button.parent, button.text = parent, text
    return button
end
MSUF2 = M
local layerProvider
M.RegisterLayerOverviewProvider = function(id, provider)
    assert(id == "suite-owned-surfaces" and type(provider) == "function")
    layerProvider = provider
    return true
end
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
T.colors = { muted = {}, text = {}, dim = {}, panel = { .08, .09, .1, 1 },
    panel2 = { .1, .11, .12, 1 }, pillHover = { .13, .14, .15, 1 } }
T.navIconGrid = { home = { 0, 0 }, gameplay = { 7, 1 } }
T.navIconColors = { home = { 1 }, gameplay = { 2 }, profiles = { 3 } }
T.Font = function(parent, template, text) local fs = Widget("FontString"); fs.text = text; return fs end
T.Button = function(parent, text)
    local b = Widget("Button")
    b.text, b.parent = text, parent
    if parent then
        parent._testButtons = parent._testButtons or {}
        parent._testButtons[#parent._testButtons + 1] = b
    end
    return b
end
T.Panel = function() return Widget("Panel") end
T.ApplySurface = function() end
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
    if meta and meta.prepareExactSearchTarget and meta.searchPrepareKind and meta.searchPrepareValue then
        widget._msuf2ExactTargetKinds = { [meta.searchPrepareKind] = true }
        widget._msuf2ExactTargetContracts = { [meta.searchPrepareKind] = { [meta.searchPrepareValue] = true } }
        widget._msuf2PrepareExactSearchTarget = meta.prepareExactSearchTarget
    end
    if meta and meta.controlId then
        registeredControls[meta.controlId] = widget
        widget.registeredMeta = meta
    end
    if meta and meta.controlId and meta.controlId:find("%.preview%.") then previewControls[meta.controlId] = widget end
end

-- Compare cold provider targets with metadata produced by real page builders.
-- This catches nonexistent sections and controls that moved into custom UI.
local function CheckSearchTargets(searchRows, pageContexts, requireReverse)
    local bySetting, byId, sections, indexed = {}, {}, {}, {}
    local function Collect(meta)
        if not meta then return end
        if meta.settingKey then bySetting[meta.settingKey] = meta end
        if meta.controlId then byId[meta.controlId] = meta end
    end
    for _, widget in pairs(registeredControls) do Collect(widget.registeredMeta) end
    for pageKey, ctx in pairs(pageContexts) do
        sections[pageKey] = {}
        for _, section in ipairs(ctx.sections) do sections[pageKey][section.sectionId] = true end
        for _, id in ipairs(ctx.qualityOfLifeFeatureOrder or {}) do sections[pageKey][id] = true end
        if ctx.fixedPreview then sections[pageKey][pageKey .. "_preview"] = true end
        for _, widget in ipairs(ctx.widgets) do Collect(widget.meta) end
    end
    local checked = 0
    for _, row in ipairs(searchRows) do
        if pageContexts[row.pageKey] then
            local target = row.controlId or row.settingKey
            if target then
                local actual = row.controlId and byId[row.controlId] or bySetting[row.settingKey]
                assert(actual, "cold search target has no built control: " .. target)
                assert(actual.sectionId == row.sectionId,
                    "cold search target points to the wrong section: " .. target)
                if row.settingKey then indexed[row.settingKey] = true end
                checked = checked + 1
            end
            if row.sectionId then
                assert(sections[row.pageKey][row.sectionId],
                    "cold search target has no built section: " .. row.sectionId)
            end
        end
    end
    if requireReverse then
        for _, ctx in pairs(pageContexts) do
            for _, widget in ipairs(ctx.widgets) do
                local key = widget.meta and widget.meta.settingKey
                assert(not key or indexed[key], "built setting has no cold search target: " .. tostring(key))
            end
        end
    end
    return checked
end
M.RegisterSearchWidget = function(widget, meta)
    assert(widget and type(meta) == "table" and type(meta.pageKey) == "string")
    widget.searchMeta = meta
    return widget
end
M.AddTooltip = function(widget, title, body, opts)
    assert(widget)
    widget.tooltip = { title = title, body = body, options = opts }
    return widget
end
M.SelectPage = function(key) M.selectedPage = key end
local current
M.TrackRefresh = function(ctx, fn) ctx.refreshers[#ctx.refreshers + 1] = fn end
M.RequestRefresh = function()
    if current then for _, fn in ipairs(current.refreshers) do fn() end end
end
local function Bind(ctx, widget, get, set, meta, label)
    widget.get, widget.set, widget.meta, widget.label = get, set, meta, label
    if ctx.key == "suite_actionbars" or ctx.key == "suite_hud" then widget._msuf2SearchMeta = { label = label } end
    ctx.widgets[#ctx.widgets + 1] = widget
    return widget
end
M.BindSwitchAt = function(ctx, parent, label, x, y, w, get, set, meta)
    local switch = Widget("Switch")
    switch._msuf2Label, switch._msuf2LabelHit = Widget("FontString"), Widget("Button")
    switch._msuf2Label.parent, switch._msuf2LabelHit.parent = parent, parent
    return Bind(ctx, switch, get, set, meta, label)
end
M.BindBoolWidget = function(ctx, widget, get, set, meta) return Bind(ctx, widget, get, set, meta, widget.label) end
M.BindDropdownAt = function(ctx, parent, label, x, y, values, w, get, set, meta)
    local dropdown = Widget("Dropdown")
    dropdown._msuf2Title = Widget("FontString")
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 24)
    return Bind(ctx, dropdown, get, set, meta, label)
end
M.BindTextInputAt = function(ctx, parent, label, x, y, w, get, set, blur, meta)
    local box = Widget("EditBox")
    function box:SetMaxBytes(value) self.maxBytes = value end
    function box:SetMaxLetters(value) self.maxLetters = value end
    return Bind(ctx, box, get, set, meta, label)
end
M.BindDropdownWidget = function(ctx, widget, get, set, meta) return Bind(ctx, widget, get, set, meta, widget.label) end
W.Dropdown = function(parent, label) local d = Widget("Dropdown"); d.label = label; return d end
W.SwitchAt = function() return Widget("Switch") end
W.MoveWidget = function() end
W.SegmentTabs = function(ctx, parent, opts)
    local segment = Widget("SegmentTabs")
    segment.values = opts.values
    segment._msuf2Title = Widget("FontString")
    segment:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.x or 0, (opts.y or 0) - 24)
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
W.SetControlDisabledReason = function(widget, reason) widget.disabledReason = reason end
W.SetControlEnabled = function(widget, enabled) widget.enabled = enabled and true or false end
W.SetControlShown = function(widget, shown)
    widget:SetShown(shown)
    for _, key in ipairs({ "_msuf2Title", "_msuf2Label", "_msuf2LabelHit" }) do
        if widget[key] then widget[key]:SetShown(shown) end
    end
end
W.SetCollapsibleSummary = function(body, text)
    body.summary = text
    body._msuf2CollapsibleEntry._msuf2UXSummary = true
end
W.SettingsRows = function(ctx, parent, spec)
    local controls, y = {}, spec.y
    for _, row in ipairs(spec.rows) do
        local widget = Bind(ctx, Widget(row.kind), row.get, row.set, row, row.label)
        widget.rowKind, widget.row = row.kind, row
        if ctx.key == "suite_dataTexts" then widget.parent = parent end
        controls[row.id] = widget
        y = y - 40
    end
    return { controls = controls, bottomY = y }
end
W.RoleButton = function(parent, text, role)
    local button = Widget("RoleButton")
    button.text, button.role, button.parent = text, role, parent
    return button
end
W.PageBuilder = function(ctx)
    local b = { width = ctx.width, y = -12, collapsibles = {}, layoutEntries = {} }
    function b:Header() ctx.headers = (ctx.headers or 0) + 1 end
    if ctx.key == "suite_dataTexts" then
        function b:RelayoutCollapsibles() self.relayouts = (self.relayouts or 0) + 1 end
    end
    if ctx.key == "suite_actionbars" or ctx.key == "suite_dataTexts" or ctx.key == "suite_hud" then
        function b:Section(title, height)
            local body = Widget("Panel")
            body.title, body.parent = Widget("FontString"), ctx.wrapper
            body._msuf2Width = ctx.width
            body:SetHeight(height)
            self.y = self.y - height - 12
            if ctx.key == "suite_dataTexts" then ctx.pageItems[#ctx.pageItems + 1] = body end
            return body
        end
    end
    function b:CollapsibleSection(id, title, _, defaultOpen)
        local body = Widget("Section")
        body.sectionId, body.title, body.defaultOpen = id, title, defaultOpen
        body._msuf2Width = ctx.width
        body.parent = ctx.wrapper
        body._msuf2CollapsibleEntry = { label = Widget("FontString"), body = body, builder = self, open = defaultOpen == true }
        self.collapsibles[#self.collapsibles + 1] = body._msuf2CollapsibleEntry
        self.layoutEntries[#self.layoutEntries + 1] = body._msuf2CollapsibleEntry
        if ctx.key == "suite_dataTexts" then
            body._msuf2CollapsibleEntry.header = Widget("SectionHeader")
            body._msuf2CollapsibleEntry.outer = Widget("SectionOuter")
            body.shown = defaultOpen == true
            body._msuf2CollapsibleEntry.open = body.shown
            function body:IsVisible() return self.shown ~= false and (not self.parent or self.parent:IsVisible()) end
            if ctx.entry then ctx.entry.sections[id] = body end
        end
        ctx.sections[#ctx.sections + 1] = body
        ctx.pageItems[#ctx.pageItems + 1] = id
        return body
    end
    function b:FinishSection(body)
        body.finished = true
        body:SetHeight(-(body._msuf2CursorY or -80) + 12)
        if ctx.SetContentHeight then ctx:SetContentHeight(body:GetHeight() + 48) end
    end
    return b
end
W.FixedPreviewSection = function(ctx, b, spec)
    local section, toolbar, record = Widget("FixedPreview"), Widget("Toolbar"), {}
    local height = math.min(180, spec.height or 180)
    section:SetHeight(height)
    record.heightResolver = function() return section._msuf2FixedPreviewActiveHeight or height end
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
Enum = { DamageMeterType = { DamageDone = 0 }, SpellBookSpellBank = { Player = 0 } }
C_SpellBook = { IsSpellKnown = function() return true end, IsSpellInSpellBook = function() return true end }
issecretvalue = function(value) return actionPreview.secret ~= nil and rawequal(value, actionPreview.secret) end
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
-- suite_options_pages_contract.lua reuses this client and menu fixture.
if SUITE_OPTIONS_FIXTURE then
    return { M = M, W = W, T = T, S = S, Suite = Suite, optionsNS = optionsNS, L = L, Widget = Widget,
        actionPreview = actionPreview, registeredControls = registeredControls,
        SetCurrent = function(ctx) current = ctx end }
end
-- The first action after a cold options attach must also offer the reload.
do
    local previousConfirm, previous = S.Confirm, S.Config("objectives").enabled
    local asked = 0
    S.Confirm = function() asked = asked + 1 end
    assert(optionsNS.Set("objectives", "enabled", not previous) and asked == 1,
        "the first tracker switch after a cold menu attach missed its reload prompt")
    assert(S.Set("objectives", "enabled", previous))
    S.Confirm = previousConfirm
end
-- Exercise the actual Edit Mode callback through the core menu bridge, including
-- a cold page and repeated jumps across the refactored categories and tabs.
do (function()
    local previousOpen, previousFocus, previousCache = MSUF2_Open, W.FocusCollapsibleSection, M.cache
    local previousAPI, previousCurrent = MSUF_EditModeAPI, current
    local previousBridge = M.SearchBridge
    local previousPrint = Suite.Print
    local records, ctx, focused = {}, nil, nil
    MSUF_EditModeAPI = { RegisterElement = function(owner, record) records[owner] = record; return true end }
    local movers = setmetatable({ Text = Suite.Text }, { __index = S })
    assert(loadfile(root .. "/MSUF_Suite_Modules/EditMode.lua"))("MSUF_Suite_Modules", { NS = Suite, Suite = movers })
    M.cache = {}
    MSUF2_Open = function(page)
        assert(page == "suite_qualityOfLife", "QoL mover opened another page")
        if not ctx then
            ctx = { key = page, width = 720, refreshers = {}, widgets = {}, sections = {},
                pageItems = {}, entry = { sections = {} } }
            current = ctx
            M.pages[page].build(ctx)
            M.cache[page] = ctx.entry
        end
        return true
    end
    W.FocusCollapsibleSection = function(section)
        local entry = assert(section._msuf2CollapsibleEntry, "mover target has no category accordion")
        entry.open = true
        focused = section
        return true
    end
    M.SearchBridge = { OpenSearchTarget = function(page, query, fallback, anchor, route)
        assert(page == "suite_qualityOfLife" and query == "" and fallback == nil
            and type(route) == "table" and next(route) == nil,
            "Edit Mode details must use their frame directly, without a text search or setting change")
        return true, true, W.FocusCollapsibleSection(anchor)
    end }
    local targets = {
        { "combatStatsHUD", "combat", "secondary_stats" },
        { "durabilityAlert", "warning", "durability_warning" },
        { "xpBar", "experience", "xp_bar" },
        { "actionTracker", "actions", "action_tracker" },
        { "battleRes", "charges", "battle_res" },
        { "groupBloodlust", "lockout", "bloodlust_lockout" },
        { "innervateCue", "alert", "innervate_cue" },
        { "combatPetStatus", "warning", "pet_status" },
        { "combatMovementCue", "combat", "movement_cue" },
        { "burningRushCue", "combat", "burning_rush_cue" },
        { "skyriding", "flight", "flight_hud" },
    }
    for _, target in ipairs(targets) do
        assert(movers.RegisterOwnedMover(target[1], target[2], { quickPosition = false,
            label = target[1], getFrame = function() end }))
    end
    for pass = 1, 2 do
        for _, target in ipairs(targets) do
            focused = nil
            local record = records["MSUFSuite." .. target[1]]
            assert(record.openSettings() == true, "Edit Mode settings failed: " .. target[1])
            local row = assert(ctx.qualityOfLifeFeatureRows["suite_qualityOfLife_" .. target[1] .. "_" .. target[3]])
            assert(row.details and focused == row.details and row.details.shown and row.row._msufSuiteSelected
                and row.details._msuf2CollapsibleEntry.open, "Edit Mode did not reveal the exact feature: " .. target[1])
            for _, tabs in ipairs(ctx.tabControls) do
                if tabs.frames[row.tab] then
                    assert(tabs.frames[row.tab].shown and tabs.segment.value == row.tab,
                        "Edit Mode did not select the feature's tab: " .. target[1])
                end
            end
            row.details._msuf2CollapsibleEntry.open = false
        end
    end
    Suite.Print = function() end
    local resolve = ctx.entry._msuf2ResolveMissingSection
    ctx.entry._msuf2ResolveMissingSection = function() return nil end
    assert(records["MSUFSuite.combatStatsHUD"].openSettings() == false,
        "Edit Mode reported success for a missing feature target")
    ctx.entry._msuf2ResolveMissingSection = resolve
    MSUF2_Open = function() return false end
    assert(records["MSUFSuite.combatStatsHUD"].openSettings() == false,
        "Edit Mode reported success when the host could not open")
    MSUF2_Open = previousOpen
    W.FocusCollapsibleSection, M.cache = previousFocus, previousCache
    M.SearchBridge = previousBridge
    MSUF_EditModeAPI, current = previousAPI, previousCurrent
    Suite.Print = previousPrint
end)() end

do
    local previous = current
    local ctx = { key = "suite_bags", width = 720, refreshers = {}, widgets = {}, sections = {},
        pageItems = {}, entry = { sections = {} } }
    current = ctx
    M.pages.suite_bags.build(ctx)
    local bankSection = false
    for _, section in ipairs(ctx.sections) do
        if section.sectionId == "suite_bags_bank" then bankSection = true end
    end
    assert(bankSection == (flavor == "Mainline"),
        "Bank organisation must render only when this client has visible bank controls")
    -- Reset section restores the visible organisation settings only; the
    -- player's custom categories are data, not a setting of that section.
    local organisation
    for _, section in ipairs(ctx.sections) do
        if section.sectionId == "suite_bags_organisation" then organisation = section end
    end
    local bags = S.Config("bags")
    local savedCategories, savedColumns = bags.customCategories, bags.inventoryColumns
    bags.customCategories, bags.inventoryColumns = "1|Raid mats|12", 9
    assert(organisation and organisation._msufSuiteSectionReset and organisation._msufSuiteSectionReset(),
        "Inventory organisation has no section reset")
    assert(S.Config("bags").inventoryColumns == S.catalog.bags.rules.inventoryColumns.default
        and S.Config("bags").customCategories == "1|Raid mats|12",
        "Reset section must keep the player's custom categories")
    bags.customCategories, bags.inventoryColumns = savedCategories, savedColumns
    -- One clear for remembered character gold: DataTexts balances and the Bags history.
    local clear = registeredControls["menu2.suite_bags.bags.action.clearGold"]
    local savedLedger, savedHistory = Suite.RootDB.goldLedger, Suite.RootDB.suiteBagGold
    Suite.RootDB.goldLedger = { alt = { name = "Alt", money = 5 } }
    Suite.RootDB.suiteBagGold = { characters = { alt = { days = {} } } }
    assert(clear and clear.scripts.OnClick, "the Bags page has no Clear saved character gold action")
    -- It cannot be undone: it asks first, and only Yes clears.
    local previousGeneric, previousConfirm, asked = _G.StaticPopup_ShowCustomGenericConfirmation, S.Confirm, nil
    S.Confirm = nil
    _G.StaticPopup_ShowCustomGenericConfirmation = function(data) asked = data end
    clear.scripts.OnClick(clear)
    assert(asked and asked.text_arg1 == optionsNS.Tr(
        "Clear the saved gold balances of all your characters and their gold history? This cannot be undone.")
        and Suite.RootDB.goldLedger ~= nil and Suite.RootDB.suiteBagGold ~= nil,
        "Clear saved character gold cleared without asking")
    asked.callback()
    assert(Suite.RootDB.goldLedger == nil and Suite.RootDB.suiteBagGold == nil,
        "Clear saved character gold must remove the balances and the gold history")
    Suite.RootDB.goldLedger, Suite.RootDB.suiteBagGold = savedLedger, savedHistory
    -- With the runtime installed but not loaded yet, a page on WoW Forever
    -- loads it (out of combat) and asks through S.Confirm and S.ContextMenu,
    -- which show the Suite's own list under the Gamepad UI; Blizzard's dialog
    -- code would run its frame controls manager in the page's call there.
    -- Retail has no Gamepad UI: a page loads nothing for a question there and
    -- keeps Blizzard's dialog and menu, as before.
    local previousLoad, previousContext, previousMenuUtil = C_AddOns.LoadAddOn, S.ContextMenu, _G.MenuUtil
    local runtimeQuestion, runtimeMenu, loaded, blizzardQuestion, blizzardMenu
    S.Confirm, S.ContextMenu = nil, nil
    _G.StaticPopup_ShowCustomGenericConfirmation = function(data) blizzardQuestion = data end
    _G.MenuUtil = { CreateContextMenu = function(owner) blizzardMenu = owner end }
    C_AddOns.LoadAddOn = function(name)
        if name ~= "MSUF_Suite_Modules" then return previousLoad(name) end
        loaded = true
        S.Confirm = function(key, data) runtimeQuestion = { key = key, data = data } end
        S.ContextMenu = function(owner) runtimeMenu = owner end
        return true
    end
    optionsNS.Confirm("probe", "Question?", function() end)
    optionsNS.ContextMenu("owner", function() end)
    if flavor == "Forever" then
        assert(loaded and runtimeQuestion and runtimeQuestion.key == "options:probe"
            and runtimeQuestion.data.text_arg1 == "Question?" and runtimeMenu == "owner"
            and not blizzardQuestion and not blizzardMenu,
            "a Forever page asked through Blizzard's dialog or menu instead of loading the Suite runtime")
    else
        assert(not loaded and blizzardQuestion and blizzardQuestion.text_arg1 == "Question?" and blizzardMenu == "owner",
            "a Retail page loaded the Suite runtime for a question instead of Blizzard's dialog and menu")
    end
    C_AddOns.LoadAddOn, S.ContextMenu, _G.MenuUtil = previousLoad, previousContext, previousMenuUtil
    _G.StaticPopup_ShowCustomGenericConfirmation, S.Confirm = previousGeneric, previousConfirm
    -- WoW Forever's Gamepad UI: OpenAllBags from the page's call would run
    -- Blizzard's frame controls manager in it (ContainerFrame.OpenBag); there
    -- the gamepad's bag button opens the bags and Open bags stays off.
    local open = assert(registeredControls["menu2.suite_bags.bags.action.open"], "the Bags page has no Open bags action")
    local previousGamepad, previousOpenAll, bagOpens = S.GamepadUI, _G.OpenAllBags, 0
    _G.OpenAllBags = function() bagOpens = bagOpens + 1 end
    open.scripts.OnClick(open)
    assert(bagOpens == 1, "Open bags stopped opening the bags outside the Gamepad UI")
    S.GamepadUI = function() return true end
    open.scripts.OnClick(open)
    assert(bagOpens == 1, "Open bags ran OpenAllBags from the Suite's call under the Gamepad UI")
    S.GamepadUI, _G.OpenAllBags = previousGamepad, previousOpenAll
    -- disabledCategories was read but never written; per-category switches cover it.
    assert(S.catalog.bags.rules.disabledCategories == nil, "the dead disabledCategories setting returned")
    -- The look help names every preset of the look choice.
    local page = assert(io.open(root .. "/MSUF_Suite_Options/Pages/Bags.lua", "rb")):read("*a")
    local lookHelp = page:match('"suite_bags_look".-help = "(.-)"')
    for _, name in ipairs(S.catalog.bags.rules.look.choices) do
        assert(name == "Custom" or (lookHelp and lookHelp:find(name, 1, true)),
            "the look help does not name the preset " .. name)
    end
    current = previous
end

-- Healclassic: moving the manual countdown-size slider must not remain
-- masked by the selected bar's automatic fit cap (18 vs 16 on a 40px button).
do
    local previous=current
    local bars={key="suite_actionbars",width=720,refreshers={},widgets={},sections={},pageItems={},entry={sections={}}}
    current=bars
    M.pages.suite_actionbars.build(bars)
    -- The bar workspace changes only the view. Exact search reveals its tab
    -- and fine settings before focus, retaining the original section identity.
    do
        local workspace = assert(bars._msufSuiteActionBarWorkspace, "action bar settings still use a flat accordion")
        assert(bars.pageItems[1] == "fixed-preview" and bars.fixedPreview,
            "selected bar preview does not precede the scrolling settings")
        assert(bars.fixedPreview.record.heightResolver() == 256 and bars.fixedPreview.section:GetHeight() == 256,
            "host compact-preview clamp leaves actionbar controls overlapping the settings viewport")
        local function Control(path)
            for _, widget in ipairs(bars.widgets) do
                if widget.meta and widget.meta.controlId == "menu2.suite_actionbars.actionbars." .. path then return widget end
            end
            return registeredControls["menu2.suite_actionbars.actionbars." .. path]
        end
        local function Section(id)
            for _, body in ipairs(bars.sections) do if body.sectionId == "suite_actionbars_" .. id then return body end end
        end
        local cfg, previousCurrent = S.Config("actionbars"), current
        current = bars
        local before, oldBar, historyBefore = {}, Control("editor.selected").get(), historyWrites
        for key, value in pairs(cfg) do before[key] = value end
        assert(workspace.groups.shared.frame:IsShown() and not workspace.groups.layout.frame:IsShown()
            and bars.tabControls[1].segment.values[1].value == "shared",
            "All action bars must be the first tab and the initial workspace")
        local preview = bars._msufSuiteActionBarPreview
        local copy = Control("editor.copyTo")
        assert(Control("editor.selected")._msuf2Title.text == optionsNS.Tr("Preview bar")
            and preview.status.text == optionsNS.Tr("Shared settings affect every action bar.")
            and not Control("selected.enabled").shown and not copy.shown,
            "shared settings misleadingly expose selected-bar editing controls")
        assert(not Control("selected.enabled")._msuf2Label.shown and not Control("selected.enabled")._msuf2LabelHit.shown,
            "shared settings retain the native switch's sibling label or clickable hit area")
        assert(Section("actionbars_module").title == optionsNS.Tr("Enable action bars"),
            "module switch still duplicates the All action bars category label")
        assert(not Section("quick") and Control("quick.bar3").meta.sectionId == "suite_actionbars_actionbars_module",
            "individual bar switches must live inside Enable action bars")
        workspace.select("text")
        Control("quick.bar3"):_msuf2PrepareExactSearchTarget()
        assert(workspace.selected == "shared", "search cannot reveal the merged individual bar switches")
        copy:_msuf2PrepareExactSearchTarget()
        assert(workspace.selected == "layout" and copy.shown,
            "search could not reveal the scoped Copy To control")
        copy.scripts.OnClick(copy)
        local copyPopup
        for _, candidate in ipairs(copyPopups) do if candidate.button == copy then copyPopup = candidate end end
        assert(copyPopup.shown)
        workspace.select("shared")
        assert(not copyPopup.shown and not copy.shown, "scoped copy popup remained open in shared settings")
        Control("selected.enabled"):_msuf2PrepareExactSearchTarget()
        assert(workspace.selected == "visibility" and Control("selected.enabled").shown,
            "search could not reveal the selected-bar switch")
        assert(Control("selected.enabled")._msuf2Label.shown and Control("selected.enabled")._msuf2LabelHit.shown,
            "returning to individual settings did not restore the whole switch")
        assert(not Section("editor").defaultOpen and Section("bar_layout").defaultOpen,
            "primary layout controls should start open and optional tools collapsed")
        assert(not Section("bar_layout")._msufSuiteActionBarDetails.panel:IsShown(), "fine offsets start expanded")
        workspace.select("text")
        assert(workspace.groups.text.frame:IsShown() and not workspace.groups.layout.frame:IsShown(), "tab selection did not update")
        assert(Control("editor.selected")._msuf2Title.text == optionsNS.Tr("Selected bar")
            and preview.status.text == string.format(optionsNS.Tr("Editing: %s"), optionsNS.Tr("Action bar 1")),
            "individual-bar settings do not identify the editing scope")
        local details = Section("bar_layout")._msufSuiteActionBarDetails
        local modeOwners = 0
        for _, widget in ipairs(bars.widgets) do
            if widget.meta and widget.meta.settingKey == "msufsuite.actionbars.bar1Visibility" then modeOwners = modeOwners + 1 end
        end
        assert(modeOwners == 1, "visibility-mode search can resolve to a fixed-bar switch")
        Control("bar1X"):_msuf2PrepareExactSearchTarget()
        assert(workspace.selected == "layout" and details.panel:IsShown(), "exact search left a fine setting hidden")
        assert(workspace.body:GetHeight() >= workspace.groups.layout.height, "fine settings were clipped by the workspace")
        assert(workspace.navigation == bars.fixedPreview.section and workspace.inset == 0,
            "category navigation is not above the live preview in the fixed header")
        assert(bars.tabControls[1].segment.points[1][5] == -12 and not bars.tabControls[1].segment._msuf2Title.shown,
            "native category title inset overlaps the selected-bar label")
        details.toggle:GetScript("OnClick")()
        assert(not details.panel:IsShown(), "fine settings cannot collapse again")
        workspace.select("text")
        local exact = Control("bar1X").registeredMeta
        assert(type(exact) == "table", "warm search row lost its stable metadata")
        assert(exact.searchPrepareKind == "actionbarWorkspace" and exact.searchPrepareValue == "bar1X",
            "warm search row lacks its workspace prepare contract")
        assert(exact.settingKey == "msufsuite.actionbars.bar1X" and exact.sectionId == "suite_actionbars_bar_layout"
            and exact.controlId == "menu2.suite_actionbars.actionbars.bar1X",
            "label-only host metadata discarded the stable exact search identity")
        assert(exact.prepareExactSearchTarget(Control("bar1X"), exact) == true and details.panel:IsShown()
            and workspace.selected == "layout", "warm exact control identity left its target hidden")
        details.show(false)
        workspace.select("text")
        Section("bar_background")._msuf2CollapsibleEntry._msuf2EnsureVisible()
        assert(workspace.selected == "appearance", "section search cannot reveal a hidden tab")
        assert(historyWrites == historyBefore, "workspace view changes wrote profile history")
        for key, value in pairs(before) do assert(cfg[key] == value, "view navigation changed " .. key) end
        local picker, toggle = Control("editor.selected"), Control("selected.enabled")
        assert(toggle.meta.classification == "action" and toggle.meta.settingKey == nil,
            "selected bar switch shadows the exact visibility-mode search target")
        picker.set(3)
        cfg.bar3Visibility = 4
        toggle.set(false)
        assert(cfg.bar3Visibility == 6 and cfg.bar3ResumeVisibility == 4 and cfg.enabled == before.enabled,
            "selected bar switch disabled the module or lost the visibility rule")
        toggle.set(true)
        assert(cfg.bar3Visibility == 4 and cfg.bar1Visibility == before.bar1Visibility, "selected switch hit the wrong bar")
        assert(historyWrites == historyBefore + 2, "selected bar switches do not form independent undo steps")
        local previousTabs, previousFixed = W.SegmentTabs, W.FixedPreviewSection
        W.SegmentTabs, W.FixedPreviewSection = nil, nil
        local narrow = { key = "suite_actionbars", width = 430, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
        M.pages.suite_actionbars.build(narrow)
        local fallback = assert(narrow._msufSuiteActionBarWorkspace.selector, "old or narrow host lacks the settings selector")
        assert(fallback.get() == "appearance", "reopening the actionbar menu forgot the last category")
        assert(fallback.points[1][5] == -12 and not fallback._msuf2Title.shown,
            "native category dropdown overlaps the selected-bar label")
        fallback.set("visibility")
        assert(fallback.get() == "visibility" and narrow._msufSuiteActionBarWorkspace.groups.visibility.frame:IsShown(),
            "narrow selector did not switch the visible settings")
        W.SegmentTabs, W.FixedPreviewSection = previousTabs, previousFixed
        local narrowDocked = { key = "suite_actionbars", width = 430, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
        M.pages.suite_actionbars.build(narrowDocked)
        assert(narrowDocked.fixedPreview.record.heightResolver() == 294
            and narrowDocked._msufSuiteActionBarWorkspace.selector.points[1][5] == -12,
            "narrow host did not reserve the stacked controls and preview height")
        picker.set(oldBar)
        for key, value in pairs(before) do cfg[key] = value end
        details.show(false)
        workspace.select("layout")
        current = previousCurrent
    end
    -- Live action-bar preview: actual action data, immediate style changes,
    -- navigation-only clicks and bounded subscriptions on the visible page.
    do
        local ui = assert(bars._msufSuiteActionBarPreview, "action bar preview is still a sample grid")
        local picker
        for _, widget in ipairs(bars.widgets) do
            if widget.meta and widget.meta.controlId == "menu2.suite_actionbars.actionbars.editor.selected" then picker = widget end
        end
        local c, saved, previousBar = S.Config("actionbars"), {}, picker.get()
        for key, value in pairs(c) do saved[key] = value end
        local duration, recharge = {}, {}
        actionPreview.actions[1] = { icon = 135810, count = "4", name = "Live macro", duration = duration,
            charges = { isActive = true, maxCharges = 2, currentCharges = 1 }, recharge = recharge }
        actionPreview.bindings.ACTIONBUTTON1 = "SHIFT-1"
        picker.set(1)
        c.bar1Buttons, c.bar1Rows, c.bar1Size, c.bar1Spacing = 12, 2, 42, 3
        c.bar1Keybind, c.bar1Macro, c.bar1ShowEmpty, c.iconZoom = true, true, true, 12
        ui.Paint()
        local tile = ui.tiles[1]
        assert(tile.icon.texture == 135810 and tile.count.text == "4" and tile.name.text == "Live macro",
            "preview does not show the actual spell, stack count and macro name")
        assert(tile.key.text == optionsNS.ActionBarPreview.Key(1, 1) and tile.cooldown.durationObject == duration
            and tile.chargeCooldown.durationObject == recharge,
            "preview lost live key bindings or the native cooldown duration")
        assert(tile.width == 42 and tile.icon.texCoords[1] == .12 and ui.tiles[7].points[1][5] == -45,
            "preview did not repaint size, icon crop and row layout")
        local initialScale = ui.canvas.scale
        c.bar1KeybindY = 80
        ui.Paint()
        assert(ui.canvas.scale < initialScale and ui.host.clipsChildren,
            "offset text can escape the preview into the header controls")
        -- SetPoint offsets use the canvas scale natively. The decorated bar
        -- must fit even when its background extends only towards one side.
        do
            local beforeBounds = {}
            for key, value in pairs(c) do beforeBounds[key] = value end
            c.bar1Rows, c.bar1Size, c.bar1Spacing = 1, 64, 6
            c.bar1Keybind, c.bar1Macro, c.cooldownNumbers = false, false, false
            c.bar1CountX, c.bar1CountY, c.borderExpansion, c.borderScale = 0, 0, 0, 100
            c.bar1LeftEndcap, c.bar1RightEndcap = 1, 1
            c.bar1Background, c.bar1BackgroundPaddingX, c.bar1BackgroundPaddingY = true, 80, 80
            c.bar1BackgroundX, c.bar1BackgroundY = 80, 80
            ui.Paint()
            local point, scale = ui.canvas.points[1], ui.canvas.scale
            local x, y = point[4] * scale, point[5] * scale
            local back = ui.background
            local bx, by = x + 80 * scale, y + 80 * scale
            local halfWidth, halfHeight = back.width * scale / 2, back.height * scale / 2
            assert(scale < 1 and bx - halfWidth >= -ui.width / 2 - .001
                and bx + halfWidth <= ui.width / 2 + .001
                and by - halfHeight >= -(ui.height - 44) / 2 + 2 - .001
                and by + halfHeight <= (ui.height - 44) / 2 + 2 + .001,
                "asymmetric decorated preview escapes its bounds after native anchor scaling")
            for key, value in pairs(beforeBounds) do c[key] = value end
        end
        c.bar1KeybindY = saved.bar1KeybindY
        c.bar1ShowEmpty = false
        ui.Paint()
        assert(tile.shown and not ui.tiles[2].shown, "empty-slot setting does not affect the live preview")
        local historyBefore = historyWrites
        tile.textHit.scripts.OnClick()
        assert(bars._msufSuiteActionBarWorkspace.selected == "text", "preview key text did not open text settings")
        tile.scripts.OnClick()
        assert(bars._msufSuiteActionBarWorkspace.selected == "shared" and historyWrites == historyBefore,
            "preview icon did not open button appearance without writing settings")
        local copy
        for _, candidate in ipairs(copyPopups) do
            if candidate.opts.controlPath == "actionbars.copy" and candidate.button.parent == bars.fixedPreview.section then copy = candidate end
        end
        assert(copy and copy.button.points[1][1] == "TOPRIGHT" and copy.button.points[1][5] == -68,
            "Copy To is not in the fixed header's upper-right corner")
        local timers, previousTimer = {}, C_Timer
        C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
        ui.host.events = {}
        function ui.host:RegisterEvent(event) self.events[event] = true end
        function ui.host:UnregisterAllEvents() self.events = {} end
        ui.host.scripts.OnShow()
        assert(ui.host.events.UPDATE_BINDINGS and ui.host.events.ACTIONBAR_SLOT_CHANGED, "live preview is not listening while visible")
        assert(ui.host.events.UPDATE_SHAPESHIFT_COOLDOWN and ui.host.events.PET_UI_UPDATE and ui.host.events.UNIT_PET,
            "preview misses stance cooldown or pet replacement updates")
        assert(ui.host.events.SPELL_UPDATE_ICON and ui.host.events.UPDATE_SUMMONPETS_ACTION,
            "preview misses icon changes that do not replace the action slot")
        ui.host.scripts.OnEvent(ui.host, "UNIT_PET", "party1")
        assert(#timers == 0, "another player's pet repainted the actionbar preview")
        actionPreview.actions[1].icon = 136048
        ui.host.scripts.OnEvent(ui.host, "SPELL_UPDATE_ICON")
        ui.host.scripts.OnEvent(ui.host, "UPDATE_SUMMONPETS_ACTION")
        assert(#timers == 1, "preview events are not coalesced")
        table.remove(timers, 1)()
        assert(tile.icon.texture == 136048, "an action change did not repaint the preview")
        ui.host.scripts.OnEvent()
        ui.host.scripts.OnHide()
        local reads = actionPreview.reads
        table.remove(timers, 1)()
        assert(not next(ui.host.events) and actionPreview.reads == reads and not ui.host:GetScript("OnUpdate"),
            "hidden preview retained subscriptions or background painting")
        C_Timer = previousTimer
        actionPreview.forms[1] = 132276
        picker.set(11); ui.Paint()
        assert(tile.icon.texture == 132276 and tile.cooldown.cooldown[1] == 10,
            "stance preview used action-bar slots or omitted its cooldown")
        actionPreview.pet[1] = { name = "Attack", icon = 132152 }
        picker.set(12); ui.Paint()
        assert(tile.icon.texture == 132152 and tile.cooldown.cooldown[2] == 40,
            "pet preview used action-bar slots or omitted its cooldown")
        local petCooldown = GetPetActionCooldown
        actionPreview.secret = 987654321
        for secretIndex = 1, 3 do
            GetPetActionCooldown = function()
                local values = { 30, 40, 1 }
                values[secretIndex] = actionPreview.secret
                return unpack(values)
            end
            ui.Paint()
            assert(rawget(tile.cooldown, "cooldown") == nil, "legacy preview passed protected cooldown data to SetCooldown")
        end
        GetPetActionCooldown, actionPreview.secret = petCooldown, nil
        actionPreview.actions[1], actionPreview.forms[1], actionPreview.pet[1] = nil, nil, nil
        actionPreview.bindings.ACTIONBUTTON1 = nil
        for key, value in pairs(saved) do c[key] = value end
        picker.set(previousBar)
        bars._msufSuiteActionBarWorkspace.select("layout")
    end
    local function Find(ctx,predicate)
        for _,widget in ipairs(ctx.widgets) do if predicate(widget) then return widget end end
    end
    local picker=assert(Find(bars,function(w) return w.meta and tostring(w.meta.controlId):find("editor%.selected") end))
    local original=historyProvider.capture()
    assert(S.SetMany("actionbars", {bar1CooldownSize=16,bar1CooldownAutoSize=true,
        bar12CooldownSize=16,bar12CooldownAutoSize=true}))
    local countdown=assert(Find(bars, function(w)
        return w.meta and w.meta.settingKey == "msufsuite.actionbars.bar1CooldownSize"
    end))
    local autoFit=assert(Find(bars, function(w)
        return w.meta and w.meta.settingKey == "msufsuite.actionbars.bar1CooldownAutoSize"
    end))
    for _, index in ipairs({1,12}) do
        picker.set(index)
        assert(S.SetMany("actionbars", { ["bar"..index.."CooldownSize"]=16,
            ["bar"..index.."CooldownAutoSize"]=true }))
        local snapshot=historyProvider.capture()
        local before=historyWrites
        countdown.set(18)
        local config=S.Config("actionbars")
        assert(config["bar"..index.."CooldownSize"]==18 and not autoFit.get(),
            "manual cooldown size remained capped by auto fit on bar "..index)
        assert(historyWrites==before+1,"manual countdown size and fit must form one undo step")
        local other=index==1 and 12 or 1
        assert(config["bar"..other.."CooldownSize"]==16 and config["bar"..other.."CooldownAutoSize"],
            "manual countdown size changed another bar")
        assert(historyProvider.restore(snapshot))
        assert(countdown.get()==16 and autoFit.get(),"undo did not restore both countdown settings")
        countdown.set(16)
        assert(autoFit.get(),"an unchanged size disabled automatic fitting")
        autoFit.set(true)
        InCombatLockdown=function() return true end
        countdown.set(20)
        InCombatLockdown=function() return false end
        assert(countdown.get()==16 and autoFit.get(),"combat refusal partially changed countdown settings")
        countdown.set(18)
        autoFit.set(true)
        assert(countdown.get()==18 and autoFit.get(),"explicit automatic fitting could not be restored")
        assert(historyProvider.restore(snapshot))
    end
    picker.set(1)
    assert(historyProvider.restore(original))
    current=previous
end


-- Each HUD switch changes only its feature; changing trackers offers an
-- optional reload after saving, including refusal and repeated-click paths.
do (function()
    local previousCurrent = current
    local hudCtx = { key = "suite_hud", width = 1000, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
    current = hudCtx
    M.pages.suite_hud.build(hudCtx)
-- Embedded HUD examples work with every module disabled, never activate the
-- real surfaces, and stop reading the character when the preview is hidden.
do (function()
    local hud = hudCtx
    local hudSections = {}
    for _, section in ipairs(hud.sections) do hudSections[section.sectionId] = section end
    local ui = assert(hud._msufSuiteHUDWorkspace)
    local preview = assert(ui.preview)
    local saved, historyBefore = {}, historyWrites
    local timerAPI, now, pending = C_Timer, 0, {}
    C_Timer = { NewTimer = function(delay, callback)
        local timer = { due = now + delay, callback = callback }
        function timer:Cancel() self.cancelled = true end
        pending[#pending + 1] = timer
        return timer
    end }
    local function Advance(seconds)
        now = now + seconds
        for _, timer in ipairs(pending) do
            if not timer.cancelled and not timer.fired and timer.due <= now then
                timer.fired = true
                timer.callback()
            end
        end
    end
    local function ActiveTimers()
        local count = 0
        for _, timer in ipairs(pending) do
            if not timer.cancelled and not timer.fired then count = count + 1 end
        end
        return count
    end
    for id in pairs(ui.groups) do
        saved[id] = {}
        for key, value in pairs(S.Config(id)) do saved[id][key] = value end
        S.Config(id).enabled = false
    end
    local function Control(id, key)
        for _, w in ipairs(hud.widgets) do
            if w.meta and w.meta.controlId == "menu2.suite_hud." .. id .. "." .. key then return w end
        end
        error("missing HUD control " .. id .. "." .. key)
    end
    assert(hud.fixedPreview.record.heightResolver() == 326 and hud.fixedPreview.section:GetHeight() == 326,
        "HUD preview overlaps settings through the native compact height cap")
    for id, group in pairs(ui.groups) do
        ui.select(id)
        assert(preview.id == id and group.frame.shown, "HUD feature selection did not select its preview")
        for other, sibling in pairs(ui.groups) do assert(sibling.frame.shown == (other == id)) end
        assert(#preview.labels > 0 and preview.canvas:GetWidth() > 0, "disabled module has no preview")
        for other, picker in pairs(preview.pickers) do assert(picker.shown == (other == id)) end
        ui.select(id == "objectives" and "announcements" or "objectives")
        local switch = Control(id, "enabled")
        switch:_msuf2PrepareExactSearchTarget()
        assert(ui.selected == id and switch.registeredMeta.prepareExactSearchTarget,
            "warm exact search cannot reveal an independent HUD enable switch")
    end
    local announcement = S.Config("announcements")
    ui.select("announcements")
    preview.pickers.announcements.set("quest")
    announcement.colorStyle, announcement.questColor = 2, "ff0000"
    announcement.titleSize, announcement.backgroundOpacity = 40, 20
    preview:Paint()
    assert(preview.labels[1].font[2] == 40 and preview.labels[1].textColor[1] == 1
        and preview.labels[1].textColor[2] == 0 and preview.fills[1].color[4] == .2,
        "banner example does not follow font size, type color and background opacity")
    assert(preview.fills[2].color[4] == .95 and preview.fills[3].color[4] == .62,
        "banner accents differ from the real feature")
    assert(preview.playButton.shown and not preview.playing, "banner playback must be explicitly started")
    -- The setting measures from playback start to fade-out start, just like
    -- the real banner. Exercise minimum/default/maximum without relying on
    -- native rendering; only the client can prove the actual alpha curve.
    for _, duration in ipairs({ 2, 4, 8 }) do
        announcement.duration = duration
        preview.playButton.scripts.OnClick()
        assert(preview.playing and preview.animation.playing, "Play preview did not start the banner animation")
        assert(preview.animation._animations[1].duration == .22 and preview.leave._animations[1].duration == .36,
            "preview fade timings differ from the real banner")
        assert(ActiveTimers() == 1 and preview.dismissTimer.due == now + duration,
            "preview must wait the configured display time before starting fade-out")
        local leaves = rawget(preview.leave, "playCount") or 0
        Advance(.22)
        -- Native animated alpha and the canvas base alpha are separate.
        -- Inject a cleared base at completion: the visible hold must be
        -- explicitly established, regardless of the preceding frame value.
        preview.canvas:SetAlpha(0)
        preview.animation.playing = false
        if preview.animation.scripts.OnFinished then preview.animation.scripts.OnFinished() end
        assert(preview.canvas.alpha == 1 and preview.playing and ActiveTimers() == 1,
            "fade-in completion did not establish a visible hold until the display deadline")
        assert(preview.animation.toFinalAlpha == true and preview.leave.toFinalAlpha == true,
            "native preview fades must retain their final alpha between phases")
        Advance(duration - .22 - .125)
        optionsNS.Refresh()
        assert((rawget(preview.leave, "playCount") or 0) == leaves and preview.playing and preview.canvas.alpha == 1,
            "preview disappeared before the configured display time")
        Advance(.125)
        assert(preview.leave.playCount == leaves + 1 and preview.playing and ActiveTimers() == 0,
            "preview did not start fading at its deadline")
        -- Deliver the native completion separately: elapsed display time
        -- starts the fade and must not finish/hide the preview immediately.
        preview.leave.scripts.OnFinished()
        assert(not preview.playing and preview.canvas.alpha == 0, "finished example did not fade away")
        preview.animation.scripts.OnFinished()
        assert(preview.canvas.alpha == 0, "late fade-in completion revived a finished preview")
        optionsNS.Refresh()
        assert(preview.canvas.alpha == 0, "menu refresh resurrected a completed preview")
    end
    preview.playButton.scripts.OnClick()
    local previousTimer = preview.dismissTimer
    local plays = preview.animation.playCount
    Advance(1)
    Control("announcements", "duration").set(7)
    assert(historyWrites == historyBefore + 1, "duration edit must be the only history write")
    historyBefore = historyWrites
    assert(preview.animation.playCount == plays + 1 and previousTimer.cancelled
        and preview.dismissTimer.due == now + 7 and ActiveTimers() == 1,
        "duration slider did not restart animation with the new time")
    local nextTimer, leaves = preview.dismissTimer, preview.leave.playCount
    previousTimer.callback()
    assert(preview.dismissTimer == nextTimer and preview.leave.playCount == leaves,
        "an old deadline interrupted restarted playback")
    preview:Paint()
    assert(preview.animation.playCount == plays + 1, "unchanged duration restarts the animation")
    Advance(6.875)
    assert(preview.leave.playCount == leaves and preview.playing, "edited preview faded too early")
    Advance(.125)
    assert(preview.leave.playCount == leaves + 1 and preview.playing, "edited preview ignored its new deadline")
    preview.host.scripts.OnHide()
    assert(not preview.playing and not preview.leave.playing, "closing the menu did not stop fade-out")
    preview.playButton.scripts.OnClick()
    local hiddenTimer = preview.dismissTimer
    preview.host.scripts.OnHide()
    assert(not preview.playing and not preview.animation.playing and hiddenTimer.cancelled and ActiveTimers() == 0,
        "closing the menu did not stop playback and cancel its deadline")
    preview.playButton.scripts.OnClick()
    local focused, oldFocus = nil, W.FocusCollapsibleSection
    W.FocusCollapsibleSection = function(body) focused = body end
    preview.canvas.scripts.OnClick()
    W.FocusCollapsibleSection = oldFocus
    assert(focused == hudSections.suite_hud_announcements_type,
        "clicking the example does not reveal appearance settings")
    local tracker = S.Config("objectives")
    ui.select("objectives")
    assert(not preview.playing and not preview.playButton.shown and preview.canvas.alpha == 1 and ActiveTimers() == 0,
        "changing HUD category leaves playback running or the new preview invisible")
    hiddenTimer.callback()
    Advance(10)
    assert(not preview.playing and preview.canvas.alpha == 1, "a cancelled deadline faded the next HUD category")
    tracker.showHeader, tracker.width = false, 480
    preview:Paint()
    assert(preview.labels[1].text ~= optionsNS.Tr("OBJECTIVES") and preview.canvas:GetWidth() == 480,
        "tracker preview does not reflect heading or width")
    preview.pickers.objectives.set("world")
    tracker.showWorldQuests = false
    preview:Paint()
    assert(preview.used == 0, "disabled tracker content still appears in the sample")
    ui.select("runSummary")
    local summary = S.Config("runSummary")
    summary.showDuration, summary.showBest, summary.showGroupSize, summary.showKills = false, false, false, false
    preview:Paint()
    assert(preview.used == 2, "result details do not follow content switches")
    assert(#optionsNS.HUDPreview.Choices.runSummary == (flavor == "Forever" and 1 or 2),
        "Forever exposes a Mythic+ result example")
    ui.select("afkScreen")
    assert(preview.afk.model._modelUnit == "player" and preview.host._events.PLAYER_EQUIPMENT_CHANGED,
        "AFK preview lacks the character or visible event refresh")
    assert(preview.afk.icons[1].texture == 134400, "AFK preview lacks equipment")
    local reads = preview.afk.model._modelReads
    preview.host:Hide()
    preview.host.scripts.OnHide()
    assert(next(preview.host._events) == nil, "closing HUD leaves character event listeners registered")
    for _, refresh in ipairs(hud.refreshers) do refresh() end
    assert(preview.afk.model._modelReads == reads and next(preview.host._events) == nil,
        "hidden HUD preview still reads the character or watches events")
    preview.host:Show()
    preview.host.scripts.OnShow()
    assert(preview.afk.model._modelReads > reads)
    ui.select("objectives")
    assert(next(preview.host._events) == nil and not preview.afk.host.shown,
        "leaving AFK retains its model/event work")
    assert(historyWrites == historyBefore, "HUD navigation or preview wrote undo history")
    for id, config in pairs(saved) do
        assert(S.Config(id).enabled == false, "preview enabled a runtime feature")
        for key, value in pairs(config) do S.Config(id)[key] = value end
    end
    preview.pickers.objectives.set("quests")
    optionsNS.Refresh()
    C_Timer = timerAPI
end)() end
    for _, refresh in ipairs(hudCtx.refreshers) do refresh() end
    assert(#hudCtx.sections == (flavor == "Forever" and 13 or 17),
        "HUD topics must be separate accordions beneath four feature categories")
    local previousTabs = W.SegmentTabs
    W.SegmentTabs = nil
    local textBuilder = optionsNS.Text
    optionsNS.Text = function(parent, text, ...)
        local label = textBuilder(parent, text, ...)
        if text == "Sample preview. Changes update here even when the feature is off." then
            function label:GetStringHeight() return 28 end
        end
        return label
    end
    local legacy = { key = "suite_hud", width = 520, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
    M.pages.suite_hud.build(legacy)
    optionsNS.Text = textBuilder
    W.SegmentTabs = previousTabs
    local workspace = legacy._msufSuiteHUDWorkspace
    assert(legacy.fixedPreview.record.heightResolver() == 326,
        "wrapped preview hint overlaps the settings on narrow hosts")
    assert(workspace.selector and not legacy.tabControls,
        "older/narrow hosts need a single HUD feature selector")
    workspace.select("announcements")
    assert(workspace.selector.value == "announcements" and workspace.groups.announcements.frame.shown,
        "older host feature selector displays a different feature")
    assert(workspace.selector.meta.classification == "ephemeral", "feature selector writes settings")
    for _, widget in ipairs(legacy.widgets) do
        if widget.meta and widget.meta.controlId == "menu2.suite_hud.objectives.x" then
            widget:_msuf2PrepareExactSearchTarget()
            assert(workspace.selected == "objectives", "narrow exact search cannot reveal tracker settings")
        end
    end
    local ids = { "objectives", "runSummary", "announcements", "afkScreen" }
    local saved, questions, reloads = {}, {}, 0
    local oldConfirm, oldReload, oldCombat = S.Confirm, ReloadUI, InCombatLockdown
    S.Confirm = function(key, data) questions[#questions + 1] = { key = key, data = data } end
    ReloadUI = function() reloads = reloads + 1 end
    for _, id in ipairs(ids) do saved[id] = S.Config(id).enabled; assert(S.Set(id, "enabled", true)) end
    local function Switch(id)
        for _, widget in ipairs(hudCtx.widgets) do
            if widget.meta and widget.meta.controlId == "menu2.suite_hud." .. id .. ".enabled" then return widget end
        end
        error("HUD switch missing: " .. id)
    end
    local tracker = Switch("objectives")
    tracker.set(false)
    assert(not S.Config("objectives").enabled, "tracker value=" .. tostring(tracker.get()) .. " feedback=" .. tostring(optionsNS.feedback.objectives))
    for i = 2, #ids do assert(S.Config(ids[i]).enabled, "tracker switch disabled " .. ids[i]) end
    assert(#questions == 1 and questions[1].key == "options:quest-tracker-reload",
        "changing the quest tracker must offer a reload")
    assert(reloads == 0, "tracker switch reloaded before the user accepted")
    tracker.set(false)
    assert(#questions == 1, "unchanged tracker switch reopened the reload prompt")
    questions[1].data.callback()
    assert(reloads == 1, "accepting the tracker prompt did not reload")
    tracker.set(true)
    assert(#questions == 2 and S.Config("objectives").enabled)
    InCombatLockdown = function() return true end
    questions[2].data.callback()
    assert(reloads == 1, "reload prompt bypassed combat refusal")
    tracker.set(false)
    assert(S.Config("objectives").enabled)
    assert(#questions == 2, "refused edit opened a reload prompt")
    InCombatLockdown = oldCombat
    for i = 2, #ids do
        local switch = Switch(ids[i])
        switch.set(false)
        assert(not S.Config(ids[i]).enabled)
        assert(S.Config("objectives").enabled, ids[i] .. " disabled the tracker")
    end
    assert(#questions == 2, "another HUD switch prompted a tracker reload")
    local beforeDisable = optionsNS.CaptureHistoryState()
    tracker.set(false)
    assert(#questions == 3)
    assert(optionsNS.ResetRules("objectives", {}, nil, { "enabled" }))
    assert(S.Config("objectives").enabled and #questions == 4,
        "resetting the tracker switch bypassed the reload prompt")
    tracker.set(false)
    assert(#questions == 5)
    assert(optionsNS.RestoreHistoryState(beforeDisable))
    assert(S.Config("objectives").enabled and #questions == 6,
        "undoing a tracker change bypassed the reload prompt")
    for _, id in ipairs(ids) do assert(S.Set(id, "enabled", saved[id])) end
    S.Confirm, ReloadUI, InCombatLockdown = oldConfirm, oldReload, oldCombat
    current = previousCurrent
    optionsNS.Refresh()
end)() end
if flavor == "Forever" then
    local plates = S.Config("nameplates")
    assert(plates.look == 4 and plates.barGeometry == 2 and plates.enemyLevelEnabled == false,
        "Forever Mapko factory must share Retail's geometry and hidden level")
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
    .. " #general gameplay@general suite_qualityOfLife@general opt_misc@general profiles@general"
assert(NavShape(M.navItems) == hostShape, "suite navigation: " .. NavShape(M.navItems))
for _, key in ipairs(expected) do
    assert(M.pages[key], "page not registered: " .. key)
    assert(M.navPrimaryForKey[key] == key)
    assert(T.navIconGrid[key] and T.navIconColors[key], "nav icon missing: " .. key)
end
assert(M.pages.suite_skin, "Suite-owned skinning page is missing")
do
    assert(type(layerProvider) == "function", "Suite layer overview provider was not registered")
    local layers = {}
    layerProvider({ Layer = function(_, row) layers[row.id] = row end })
    local action = layers["suite.actionbars.bar1Layer"]
    local meter = layers["suite.damageMeter.w1Layer"]
    local data = layers["suite.dataTexts.bar1Layer"]
    assert(action and meter and data and action.automatic and action.value == 0,
        "Suite-owned layer rows did not expose legacy Auto without loading a module")
    assert(action.edit.kind == "external" and action.edit.module == "actionbars"
        and action.edit.key == "bar1Layer" and type(action.edit.set) == "function",
        "Suite layer row cannot write through its module controller")
    -- Every configured DataText bar is listed under its name, dynamic bars too.
    local dataConfig = S.Config("dataTexts")
    local savedData = Suite.CopyValue(dataConfig)
    assert(S.SetMany("dataTexts", Suite.DataTextBarCreationValues(dataConfig, 13))
        and S.Set("dataTexts", "bar13Name", "Raid info"), "could not configure a dynamic DataText bar")
    layers = {}
    layerProvider({ Layer = function(_, row) layers[row.id] = row end })
    local dynamic = layers["suite.dataTexts.bar13Layer"]
    assert(dynamic and dynamic.scope == "Raid info" and dynamic.edit.key == "bar13Layer",
        "a configured DataText bar beyond the first three has no layer row")
    local listed = 0
    for id in pairs(layers) do
        if id:match("^suite%.dataTexts%.bar%d+Layer$") then listed = listed + 1 end
    end
    assert(listed == #Suite.DataTextBarIDs(S.Config("dataTexts")),
        "the layer overview lists other DataText bars than the configured ones")
    Suite.DB.suite.modules.dataTexts = savedData
end
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
    and select(2, rows.suite_actionbars.availability()) == "You need to turn on the module in Blizzard's AddOn list"
    and not select(3, rows.suite_actionbars.availability()),
    "Suite navigation must keep Blizzard-disabled AddOns grey and visible")
assert(Suite.Client.AddOnEnabled("MSUF_Suite_Minimap")
    and Suite.Client.AddOnEnabled("MSUF_Suite_QualityOfLife"), "unrelated AddOns were disabled")
C_AddOns.GetAddOnEnableState = AllEnabled
assert(M.ALIASES.meter == "opt_bars", "suite overrode an MSUF alias")
assert(M.ALIASES.damage_meter == "suite_damageMeter" and M.ALIASES.minimap == "suite_minimap")
assert(M.ALIASES.chat == "suite_chat", "chat page alias is missing")
-- Attaching twice must not duplicate rows.
local function Reattach()
    Suite.Menu.attached = false
    assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Register.lua"))("MSUF_Suite_Options", {
        Suite = Suite, M = M, T = T, HM = optionsNS.HM, pages = optionsNS.pages, Tr = M.Tr, host = MSUF_NS,
        Refresh = function() end,
        BuildColorsCategory = optionsNS.BuildColorsCategory, ApplyForeverStyle = optionsNS.ApplyForeverStyle,
        ForgetAvailability = optionsNS.ForgetAvailability,
        S = optionsNS.S, catalog = optionsNS.catalog, Text = optionsNS.Text, SkinningEnabled = optionsNS.SkinningEnabled,
    })
end
Reattach()
assert(NavShape(M.navItems) == hostShape, "suite navigation inserted twice: " .. NavShape(M.navItems))
-- HD hosts get twelve distinct destinations; legacy hosts keep page cells.
;(function()
    local legacy = T.navIconGrid
    for _, page in ipairs(optionsNS.pages) do
        if page.icon then assert(legacy[page.key] == page.icon, "older host received an unavailable icon") end
    end
    T.navIconGrid, T.navIconAtlasVersion = {}, 2
    Reattach()
    local cells, count = {}, 0
    for _, page in ipairs(optionsNS.pages) do
        local cell = assert(T.navIconGrid[page.key], "HD icon missing: " .. page.key)
        assert(cell[1] >= 0 and cell[1] < 8 and (cell[2] == 3 or cell[2] == 4), "invalid HD atlas cell")
        local key = cell[1] .. ":" .. cell[2]
        assert(not cells[key], "unrelated Suite pages share a navigation symbol")
        cells[key], count = true, count + 1
    end
    assert(count == 12, "Suite navigation coverage changed")
    local chosen = T.navIconGrid.suite_bags
    Reattach()
    assert(T.navIconGrid.suite_bags == chosen, "reattaching replaces registered icons")
    T.navIconGrid, T.navIconAtlasVersion = legacy, nil
end)()
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
    .. " #features classpower@features gameplay@features suite_qualityOfLife@features profiles@features"
assert(NavShape(M.navItems) == legacyShape, "suite navigation on a legacy host: " .. NavShape(M.navItems))
M.navItems = hostItems

-- The suite ships English pages and never writes into MSUF's locale table.
assert(rawget(L, "Interface") == nil, "suite wrote a translation into MSUF's locale table")
assert(rawget(L, "Enable module") == "MSUF-eigene Übersetzung", "suite changed an MSUF translation")

-- Build every page and collect the keys its controls read.
local contexts = {}
for _, key in ipairs(expected) do
    local ctx = { key = key, width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
    if key == "suite_qualityOfLife" or key == "suite_dataTexts" then ctx.entry = { sections = {} } end
    current = ctx
    M.pages[key].build(ctx)
    if ctx.fixedPreview and ctx.fixedPreview.record.onActivate then ctx.fixedPreview.record.onActivate() end
    for _, fn in ipairs(ctx.refreshers) do fn() end
    for _, section in ipairs(ctx.sections) do assert(section.finished, key .. " section not finished: " .. section.sectionId) end
    assert(not ctx.headers, key .. " still has a redundant page header")
    contexts[key] = ctx
end
-- Selected DataText views are constructed on demand. Navigation and preview
-- selection never write settings and have no timer or runtime source queries.
do
    local ctx = contexts.suite_dataTexts
    local previousCurrent, previousTimer = current, C_Timer
    current = ctx
    C_Timer = { After = function() error("DataText navigation queued a timer") end }
    local workspace = assert(ctx.dataTextWorkspace)
    local navigation = assert(workspace.navigation, "DataTexts has no bar navigation strip")
    assert(ctx.pageItems[1] == navigation and ctx.pageItems[2] == "suite_dataTexts_dataTexts_module",
        "bar navigation must precede the DataTexts module switch")
    for _, button in pairs(workspace.buttons) do
        assert(button.parent == navigation, "bar tabs and Add bar must belong to the navigation strip")
    end
    assert(workspace.deck.views[1] and not workspace.deck.views[2], "cold page eagerly built other bars")
    local barView = workspace.deck.views[1]
    assert(barView.frame.parent ~= navigation and barView.frame.points[1][5] == 0,
        "the bar editor must scroll separately without space reserved for the moved selector")
    for _, suffix in ipairs({ "slot1", "slot1_details", "appearance", "visibility" }) do
        local body = assert(ctx.entry.sections["suite_dataTexts_bar1_" .. suffix], "bar accordion header is missing: " .. suffix)
        assert(body.parent:IsVisible(), "bar accordion header is hidden behind another view: " .. suffix)
    end
    assert(not barView.sections.appearance.body:IsShown() and not barView.sections.visibility.body:IsShown(),
        "secondary bar accordions must start collapsed")
    for _, widget in ipairs(ctx.widgets) do
        assert(not (widget.meta and widget.meta.settingKey == "msufsuite.dataTexts.bar1Width"),
            "cold page eagerly built collapsed appearance controls")
        assert(widget.text ~= "More settings", "bar settings are still hidden behind More settings")
    end
    local config, oldSource = S.Config("dataTexts"), S.Config("dataTexts").bar1Slot2
    local preview = workspace.deck.views[1].preview
    assert(#preview.entries == 3, "preview does not show configured DataTexts")
    preview.slots[2].scripts.OnClick(preview.slots[2])
    assert(config.bar1Slot2 == oldSource and workspace.deck.views[1].deck.selected == "slot2",
        "preview click changed the source instead of selecting its inspector")
    local coldCount = #ctx.widgets
    local section = ctx.entry._msuf2ResolveMissingSection("suite_dataTexts_bar2_slot12")
    assert(section and workspace.deck.selected == 2 and workspace.deck.views[2].deck.selected == "slot12",
        "cold exact search did not reveal the correct bar and slot")
    local count = #ctx.widgets
    ctx.entry._msuf2ResolveMissingSection("suite_dataTexts_bar2_slot12")
    assert(#ctx.widgets == count and count > coldCount, "warm navigation rebuilt controls")
    for _, suffix in ipairs({ "slot12", "slot12_details", "appearance", "visibility" }) do
        local body = assert(ctx.entry.sections["suite_dataTexts_bar2_" .. suffix], "selected bar lost an accordion: " .. suffix)
        assert(body.parent:IsVisible(), "selecting a slot hid another accordion: " .. suffix)
    end
    local appearance = ctx.entry.sections.suite_dataTexts_bar2_appearance
    appearance._msuf2CollapsibleEntry.open = true
    appearance._msuf2CollapsibleEntry._msuf2RefreshState()
    local extra = assert(registeredControls["menu2.suite_dataTexts.dataTexts.bar2BackgroundOpacity"],
        "opening Appearance did not expose the formerly hidden advanced settings")
    assert(extra.parent == appearance, "advanced appearance is still hidden in a nested panel")
    local expandedCount = #ctx.widgets
    appearance._msuf2CollapsibleEntry._msuf2RefreshState()
    assert(#ctx.widgets == expandedCount, "reopening an accordion rebuilt its controls")
    assert(ctx.entry._msuf2ResolveMissingSection("suite_dataTexts_bar999") == nil,
        "unconfigured bar can be selected through search")
    -- Materialize the cold index through its own targets, then the ordinary
    -- all-page contract below proves each advertised exact control resolves.
    for _, rule in ipairs(Suite.SuiteCatalog.dataTexts.getControls(config)) do
        local target = optionsNS.DataTextSearchTarget(rule)
        if target then ctx.entry._msuf2ResolveMissingSection(target) end
    end
    ctx.entry._msuf2ResolveMissingSection("suite_dataTexts_presets")
    local gallery = workspace.deck.views.add
    assert(#gallery.cards == 6, "starter gallery lost an EUI purpose or the Antique preset")
    local before, historyBefore = {}, historyWrites
    for key, value in pairs(config) do before[key] = value end
    local picker
    for _, widget in ipairs(ctx.widgets) do
        if widget.meta and widget.meta.controlId == "menu2.suite_dataTexts.dataTexts.presets.look" then picker = widget end
    end
    assert(picker, "preset style chooser missing")
    picker.set(1)
    for _, card in ipairs(gallery.cards) do
        local preview = card.preview
        assert(card.config ~= config and preview.options.interactive == false and preview.options.compact,
            "preset card is not an isolated static preview")
        local expectedLook = card.preset.id == "antique" and config.look or 1
        assert(card.config["bar" .. card.bar .. "Look"] == expectedLook,
            "preset thumbnail ignored chosen MSUF style or replaced Antique styling")
    end
    assert(historyWrites == historyBefore, "previewing a style created an undo checkpoint")
    for key, value in pairs(config) do assert(before[key] == value, "preset preview mutated saved configuration: " .. key) end
    workspace.choose(1, "content", 2)
    local real = Suite.DataTextEffectiveStyle
    local painted
    Suite.DataTextEffectiveStyle = function(settings, bar)
        painted = bar
        return real(settings, bar)
    end
    preview:Refresh()
    Suite.DataTextEffectiveStyle = real
    assert(painted == 1, "preview did not resolve the selected bar's actual style")
    C_Timer, current = previousTimer, previousCurrent
end

do
    local qol = contexts.suite_qualityOfLife
    local rows = assert(qol.qualityOfLifeFeatureRows)
    local resolver = assert(qol.entry and qol.entry._msuf2ResolveMissingSection,
        "Quality of Life lost exact navigation to virtual feature sections")
    local actionId = "suite_qualityOfLife_actionTracker_action_tracker"
    local action = assert(rows[actionId])
    assert(action.hasDetails and not action.details and not action.colorShortcut,
        "Quality of Life built hidden action tracker settings eagerly")
    local resolved = resolver(actionId)
    assert(resolved == action.details and action.colorShortcut,
        "Quality of Life search did not lazily reveal action tracker settings")
    local cachedDetails = action.details
    assert(resolver(actionId) == cachedDetails and action.details == cachedDetails,
        "Quality of Life rebuilt already materialized settings")
    local combatLogId = "suite_qualityOfLife_combatLog_log_dungeons"
    local combatLog = assert(rows[combatLogId])
    assert(action.row._msufSuiteSelected and action.row._msufSuiteStripe.shown,
        "opened Quality of Life submenu has no selected-row highlight")
    resolver(combatLogId)
    assert(combatLog.row._msufSuiteSelected and combatLog.row._msufSuiteStripe.shown
        and not action.row._msufSuiteSelected and not action.row._msufSuiteStripe.shown,
        "Quality of Life submenu highlight did not follow the selected feature")
    do
        local colors = T.colors
        local raised, hover = colors.panel2, colors.pillHover
        colors.panel2, colors.pillHover = { .21, .19, .15, .88 }, { .32, .28, .20, .95 }
        action.row.scripts.OnLeave(action.row)
        local shade = action.row._msufSuiteShade.color
        assert(shade[1] == .21 and shade[2] == .19 and shade[3] == .15,
            "Quality of Life idle row retained a fixed blue shade")
        action.row.scripts.OnEnter(action.row)
        shade = action.row._msufSuiteShade.color
        assert(shade[1] == .32 and shade[2] == .28 and shade[3] == .20 and shade[4] == .55,
            "Quality of Life hover row ignored the active theme")
        colors.pillHover = { .16, .17, .18, .95 }
        action.row.scripts.OnEnter(action.row)
        shade = action.row._msufSuiteShade.color
        assert(shade[1] == .16 and shade[2] == .17 and shade[3] == .18,
            "Quality of Life cached the old hover theme")
        colors.panel2, colors.pillHover = raised, hover
        action.row.scripts.OnLeave(action.row)
    end
    resolver(actionId)
    local finderId = "suite_qualityOfLife_groupFinderDoubleClick_group_finder_double_click"
    local finder = assert(rows[finderId])
    assert(finder.hasDetails and resolver(finderId) == finder.details,
        "group finder quick apply and saved note settings must remain reachable")
    local simpleId = "suite_qualityOfLife_tooltipClassColors_class_colors"
    local simple = assert(rows[simpleId])
    assert(not simple.hasDetails and not simple.details and not simple.settings
        and resolver(simpleId) == simple.row,
        "one-switch Quality of Life feature should remain a direct compact row")
    assert(qol.entry.sections[simpleId] == nil and qol.entry.sections[actionId] == nil,
        "old Quality of Life feature IDs must remain virtual search routes")
    local repairId = "suite_qualityOfLife_qol_repair"
    local repair = assert(rows[repairId])
    assert(resolver(repairId) == repair.details and repair.details,
        "old merchant feature route did not open its settings")
    local merchantTabs
    for _, control in ipairs(qol.tabControls or {}) do
        if control.frames.loot and control.frames.merchants then merchantTabs = control end
    end
    assert(merchantTabs and merchantTabs.segment.value == "merchants"
        and merchantTabs.frames.merchants.shown and not merchantTabs.frames.loot.shown,
        "old merchant feature route did not switch to its submenu")
    for sectionId, record in pairs(rows) do
        if record.hasDetails then
            assert(resolver(sectionId) == record.details and record.details,
                "Quality of Life detail panel could not be opened by its stable section ID")
        end
    end
    for _, refresh in ipairs(qol.refreshers) do refresh() end
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
    -- New installs use Mapko; switching to the retained preset still restores
    -- all legacy offsets and native sizing tested below.
    assert(optionsNS.Set("nameplates", "look", 4))
    local mapkoHealth = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.enemy.Health"])
    local mapkoCast = assert(registeredControls["menu2.suite_nameplates.nameplates.preview.enemy.Cast"])
    mapkoHealth.previewUI:Paint()
    assert(mapkoHealth.width == 206 and mapkoHealth.height == 20
        and mapkoCast.width == 206 and mapkoCast.height == 10,
        "Mapko preview bar dimensions differ between Retail and Forever")
    assert(optionsNS.Set("nameplates", "look", 1))
    assert(optionsNS.Set("nameplates", "enemyPreviewRole", 1))
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
    assert(plates.enemyTargetOffsetX == S.catalog.nameplates.rules.enemyTargetOffsetX.default,
        "target arrow reset did not restore its Mapko factory position")
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
-- Blizzard enters its Edit Mode only from secure code (the game menu,
-- /editmode: Blizzard_GameMenu, SlashCommandsOverrides.lua). The action bar
-- page's "Move extra action button" runs /editmode from one secure overlay
-- in UIParent that covers the hovered button out of combat (P.SecureMacroButton);
-- the page never opens Edit Mode itself, which would run EnterEditMode
-- tainted, and the Suite never reparents the protected button.
do
    local extra = assert(registeredControls["menu2.suite_actionbars.actionbars.editor.extraAbility"],
        "the action bar page lost its extra action button")
    local function RefreshBars() for _, fn in ipairs(contexts.suite_actionbars.refreshers) do fn() end end
    RefreshBars()
    assert(not extra.enabled, "the extra action button ignores Blizzard's Edit Mode gate")
    -- A hover while Blizzard refuses Edit Mode attaches nothing.
    local created = {}
    local createFrame = CreateFrame
    CreateFrame = function(kind, name, parent, template)
        local frame = createFrame(kind, name, parent, template)
        frame.template, frame.attributes, frame.events = template, {}, {}
        function frame:SetAttribute(key, value) self.attributes[key] = value end
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetAllPoints(target) self.points = { { "ALL", target } } end
        created[#created + 1] = frame
        return frame
    end
    extra.scripts.OnEnter(extra)
    assert(#created == 0, "the secure overlay attached while Edit Mode was unavailable")
    EditModeManagerFrame = { CanEnterEditMode = function() return true end }
    RefreshBars()
    assert(extra.enabled, "the extra action button stayed disabled")
    local uiParent = UIParent
    UIParent = Widget("Frame")
    extra.scripts.OnEnter(extra)
    local overlay = assert(created[1], "hovering the extra action button attached no secure overlay")
    CreateFrame = createFrame
    assert(#created == 1 and overlay.template == "SecureActionButtonTemplate" and rawget(overlay, "parent") == UIParent,
        "the overlay is not one secure button in UIParent")
    UIParent = uiParent
    assert(overlay.attributes.type1 == "macro" and overlay.attributes.macrotext1 == "/editmode"
        and overlay.attributes.useOnKeyDown == false, "the overlay does not run /editmode on the click release")
    assert(overlay.shown and overlay.points[1][2] == extra and overlay.owner == extra,
        "the overlay does not cover the hovered button")
    -- The covered button keeps its hover look: the overlay forwards to it.
    local entered, left = 0, 0
    extra:HookScript("OnEnter", function() entered = entered + 1 end)
    extra:HookScript("OnLeave", function() left = left + 1 end)
    overlay.scripts.OnEnter(overlay)
    assert(entered == 1 and overlay.shown, "the overlay hides the button's hover look")
    -- Leaving releases it.
    overlay.scripts.OnLeave(overlay)
    assert(not overlay.shown and #overlay.points == 0 and rawget(overlay, "owner") == nil and left == 1,
        "leaving the button kept the secure overlay on the menu")
    -- PLAYER_REGEN_DISABLED comes before the lockdown: the overlay lets go of
    -- the menu then and no hover takes it back until combat ends.
    extra.scripts.OnEnter(extra)
    assert(overlay.shown and overlay.events.PLAYER_REGEN_DISABLED, "the overlay does not watch the combat start")
    overlay.scripts.OnEvent(overlay, "PLAYER_REGEN_DISABLED")
    assert(not overlay.shown and #overlay.points == 0, "the combat start left the secure overlay on the menu")
    extra.scripts.OnEnter(extra)
    assert(not overlay.shown, "a hover in the combat start attached the secure overlay")
    overlay.scripts.OnEvent(overlay, "PLAYER_REGEN_ENABLED")
    InCombatLockdown = function() return true end
    extra.scripts.OnEnter(extra)
    assert(not overlay.shown, "a hover in combat attached the secure overlay")
    InCombatLockdown = function() return false end
    extra.scripts.OnEnter(extra)
    assert(overlay.shown, "the overlay stayed off after combat")
    -- Closing the menu under the pointer releases it as well.
    extra.scripts.OnHide(extra)
    assert(not overlay.shown and #overlay.points == 0, "a hidden menu kept the secure overlay")
    EditModeManagerFrame = lockedEditMode
    RefreshBars()
    -- The Bags page's Open bags: under WoW Forever's Gamepad UI the same
    -- overlay clicks Blizzard's backpack button (P.SecureClick; S.PanelButton,
    -- MSUF_Suite_Modules/MicroMenu.lua), so the bags open from secure code;
    -- elsewhere the page keeps OpenAllBags and takes no overlay.
    local open = assert(registeredControls["menu2.suite_bags.bags.action.open"], "the Bags page has no Open bags action")
    local status, availability, gamepadUI, panelButton = S.Status, S.Availability, S.GamepadUI, S.PanelButton
    local bagsEnabled, openAll, previous = S.Config("bags").enabled, OpenAllBags, current
    S.Status, S.Availability = function() return "Active" end, function() return true end
    S.Config("bags").enabled = true
    local gamepad, backpack, bagOpens = false, Widget("Button"), 0
    S.GamepadUI = function() return gamepad end
    S.PanelButton = function(panel) return panel == "bags" and backpack or nil end
    OpenAllBags = function() bagOpens = bagOpens + 1 end
    local function RefreshBags()
        current = contexts.suite_bags
        M.RequestRefresh()
    end
    -- A pointer resting on the page button (it has no hover script of its own).
    local function Hover(button)
        local enter = button.scripts.OnEnter
        if enter then enter(button) end
    end
    RefreshBags()
    assert(open.enabled, "Open bags is off outside the Gamepad UI")
    Hover(open)
    assert(not (overlay.shown and rawget(overlay, "owner") == open), "Open bags took the secure overlay outside the Gamepad UI")
    open.scripts.OnClick(open)
    assert(bagOpens == 1, "Open bags stopped opening the bags outside the Gamepad UI")
    gamepad = true
    RefreshBags()
    assert(open.enabled, "Open bags stayed off although Blizzard's backpack button opens the bags")
    Hover(open)
    assert(overlay.shown and rawget(overlay, "owner") == open and overlay.attributes.type1 == "click"
        and overlay.attributes.clickbutton1 == backpack and overlay.attributes.macrotext1 == nil,
        "Open bags does not click Blizzard's backpack button from the secure overlay")
    -- The pad's A on the page button is the page's own (addon) call.
    open.scripts.OnClick(open)
    assert(bagOpens == 1, "Open bags ran OpenAllBags from the Suite's call under the Gamepad UI")
    overlay.scripts.OnLeave(overlay)
    -- The macro buttons keep their macro on the same overlay.
    EditModeManagerFrame = { CanEnterEditMode = function() return true end }
    RefreshBars()
    extra.scripts.OnEnter(extra)
    assert(rawget(overlay, "owner") == extra and overlay.attributes.type1 == "macro" and overlay.attributes.clickbutton1 == nil
        and overlay.attributes.macrotext1 == "/editmode", "the click delegate stayed on the overlay of a macro button")
    overlay.scripts.OnLeave(overlay)
    EditModeManagerFrame = lockedEditMode
    RefreshBars()
    -- Without Blizzard's button Open bags stays off and takes no overlay.
    backpack = nil
    RefreshBags()
    Hover(open)
    assert(not open.enabled and not overlay.shown, "Open bags offered a click with no Blizzard button to take it")
    S.Status, S.Availability, S.GamepadUI, S.PanelButton = status, availability, gamepadUI, panelButton
    S.Config("bags").enabled, OpenAllBags = bagsEnabled, openAll
    RefreshBags()
    current = previous
    local handle = assert(io.open(root .. "/MSUF_Suite_Options/Pages/ActionBars.lua", "rb"))
    local source = handle:read("*a")
    handle:close()
    assert(not source:find("ShowUIPanel", 1, true) and not source:find("SetParent", 1, true),
        "the action bar page opens Blizzard's Edit Mode from insecure code")
end
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
    if pageKey == "suite_qualityOfLife" then
        for sectionId, record in pairs(ctx.qualityOfLifeFeatureRows or {}) do
            if record.colorShortcut then
                local targets = record.colorShortcut.options.getTargets()
                assert(record.colorShortcut.options.maxTargets >= #targets,
                    "Quality of Life color shortcut truncates its targets: " .. sectionId)
                for _, target in ipairs(targets) do
                    assert(type(target.get) == "function" and type(target.set) == "function",
                        "Quality of Life has an unbound color shortcut target")
                    shortcutColors[target.sourceSettingKey or target.settingKey] = true
                    shortcutColorCount = shortcutColorCount + 1
                end
            end
        end
    end
end
assert(shortcutColorCount > 0, "suite color shortcut audit did not cover the catalog")
local hudSections = {}
for _, section in ipairs(contexts.suite_hud.sections) do
    hudSections[section.sectionId] = section
    local appearance = section.sectionId:match("_type$") or section.sectionId:match("_module$") and section.sectionId ~= "suite_hud_afkScreen_module"
    assert((type(section.colorShortcut) == "table") == (appearance and true or false),
        "HUD feature header lost its three-dot colors")
end
assert(#contexts.suite_hud.sections == 17, "HUD topics lost their separate accordions")
assert(hudSections.suite_hud_objectives_raid, "Retail raid encounter accordion missing")
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
do (function()
    local workspace = contexts.suite_hud._msufSuiteHUDWorkspace
    for _, id in ipairs({ "objectives", "runSummary", "announcements" }) do
        local prefix = id == "runSummary" and "summary" or id
        for _, kind in ipairs({ "content", "layout", "type" }) do
            local section = assert(hudSections["suite_hud_" .. prefix .. "_" .. kind])
            assert(section.parent == workspace.groups[id].frame,
                "HUD topic accordion belongs to a different feature")
        end
        local exact
        for _, widget in ipairs(contexts.suite_hud.widgets) do
            if widget.meta and widget.meta.controlId == "menu2.suite_hud." .. id .. ".x" then exact = widget end
        end
        assert(exact and exact._msuf2PrepareExactSearchTarget)
        exact:_msuf2PrepareExactSearchTarget()
        assert(workspace.selected == id and exact.meta.sectionId == "suite_hud_" .. prefix .. "_layout",
            "exact search did not select the HUD feature/layout accordion")
    end
end)() end
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
    "Start here must be merged into the existing Basics card")
for _, key in ipairs({ "look", "nativeSize", "friendlyNPCs", "playerGuildNames", "playerTitles", "protectImport" }) do
    local control
    for _, widget in ipairs(contexts.suite_nameplates.widgets) do
        if widget.meta and widget.meta.controlId == "menu2.suite_nameplates.nameplates." .. key then control = widget; break end
    end
    assert(control, key)
    assert(control.meta.sectionId == "suite_nameplates_nameplates_module", key .. " escaped Basics")
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
    local spec = Suite.SuiteCatalog[id]
    local controls = spec.getControls and spec.getControls(S.Config(id)) or spec.controls
    for _, rule in ipairs(controls) do
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
    local rows = qolPage.qualityOfLifeFeatureRows
        or (qolPage.entry and qolPage.entry.qualityOfLifeFeatureRows)
    local row = rows and rows["suite_qualityOfLife_" .. name]
    assert(row and row.toggle, "missing Quality of Life feature: " .. name)
    -- The old tests exercise the same independent feature switches and color
    -- actions after the feature rows move into category accordions.
    return {
        headerSwitch = row.toggle,
        colorShortcut = row.colorShortcut or (row.body and row.body.colorShortcut),
    }
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
        { "suite_qualityOfLife", "xpBar.action.edit", "xpBar", "experience" },
        { "suite_qualityOfLife", "combatMovementCue.action.edit", "combatMovementCue", "combat" },
        { "suite_qualityOfLife", "burningRushCue.action.edit", "burningRushCue", "combat" },
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
    "minimap preview must stay fixed above Basics")
assert(contexts.suite_minimap.sections[1].title == "Basics"
    and contexts.suite_minimap.sections[1].headerSwitch,
    "minimap enable switch is not in the Basics header")
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
assert(dataPage.sections[1].title == "DataTexts", "DataTexts lost its module switch")
for index = 1, 3 do
    local body = dataPage.entry._msuf2ResolveMissingSection("suite_dataTexts_bar" .. index)
    assert(body and body.headerSwitch, "DataTexts bar has no visible enable switch")
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
-- Source choices require a deliberate selection; opening an inspector does
-- not silently populate a place with the first unused source.
do
    local tile = assert(registeredControls["menu2.suite_dataTexts.dataTexts.bar1Slot2.preview"])
    local before = S.Config("dataTexts").bar1Slot2
    tile.scripts.OnClick(tile)
    assert(S.Config("dataTexts").bar1Slot2 == before, "preview selected an unsolicited source")
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
assert(contexts.suite_chat.fixedPreview and contexts.suite_chat.pageItems[1] == "fixed-preview",
    "chat preview must stay visible while other chat sections are edited")
-- Clearing saved chat history works for a character whose Chat module is
-- off: the load-on-demand addon (and its per-character saved variables) is
-- loaded for it, nothing is enabled.
do
    local clearHistory
    for id, widget in pairs(registeredControls) do
        if id:find("suite_chat", 1, true) and id:find("clearHistory", 1, true) then clearHistory = widget end
    end
    assert(clearHistory and clearHistory.scripts.OnClick, "the Chat page has no Clear saved chat history action")
    local loadAddOn, cleared, loadedChat = C_AddOns.LoadAddOn, 0, false
    local chatInstance = S.instances.chat
    S.instances.chat = nil
    C_AddOns.LoadAddOn = function(name)
        if name ~= "MSUF_Suite_Chat" then return loadAddOn(name) end
        loadedChat = true
        S.instances.chat = { ClearHistory = function() cleared = cleared + 1 end }
        return true
    end
    -- It cannot be undone: it asks first, and only Yes clears.
    local previousGeneric, previousConfirm, asked = _G.StaticPopup_ShowCustomGenericConfirmation, S.Confirm, nil
    S.Confirm = nil
    _G.StaticPopup_ShowCustomGenericConfirmation = function(data) asked = data end
    clearHistory.scripts.OnClick(clearHistory)
    assert(asked and asked.text_arg1 == optionsNS.Tr(
        "Clear the saved chat history of this character in every chat window? This cannot be undone.")
        and not loadedChat and cleared == 0, "Clear saved chat history cleared without asking")
    asked.callback()
    assert(loadedChat and cleared == 1, "clearing chat history needed the Chat module to be running")
    C_AddOns.LoadAddOn, S.instances.chat = loadAddOn, chatInstance
    _G.StaticPopup_ShowCustomGenericConfirmation, S.Confirm = previousGeneric, previousConfirm
end
local timestampWidget
local chatFontSizes = {}
for _, widget in ipairs(contexts.suite_chat.widgets) do
    if widget.meta and widget.meta.settingKey == "showTimestamps" then timestampWidget = widget end
    if type(widget.row) == "table" and (widget.row.id == "tabFontSize" or widget.row.id == "fontSize") then
        chatFontSizes[widget.row.id] = widget.row
    end
end
for _, key in ipairs({ "tabFontSize", "fontSize" }) do
    local row = assert(chatFontSizes[key], "missing chat font size control: " .. key)
    assert(row.format and row.format(0) == optionsNS.Tr("Default") and row.format(18) == "18",
        "chat font size does not explain its inherited default value: " .. key)
end
do
local chatTabs
for _, section in ipairs(contexts.suite_chat.sections) do
    if section.sectionId == "suite_chat_tabs" then chatTabs = section end
end
assert(chatTabs and type(chatTabs.summary) == "string" and chatTabs.summary ~= "",
    "closed chat section does not expose its current settings")
local originalTabSize, originalSummary = savedChat.tabFontSize, chatTabs.summary
savedChat.tabFontSize = 18
for _, refresh in ipairs(contexts.suite_chat.refreshers) do refresh() end
assert(chatTabs.summary ~= originalSummary and chatTabs.summary:find("18", 1, true),
    "section summary stayed stale after a setting changed")
savedChat.tabFontSize = originalTabSize
for _, refresh in ipairs(contexts.suite_chat.refreshers) do refresh() end
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
do
local qolFeaturesByCategory = {
    everydayAutomation = {
        "collectionNewMarkers_collection_markers", "dailyComfort_daily_comfort",
        "delveSolePower_delve_sole_power", "trainerLearnAll_trainer_all", "quests_automation",
    },
    lootMerchants = {
        "loot_collection", "lootToastFilter_filtered_loot", "vaultSpec_vault_spec",
        "loot_history", "merchantLevel_merchant_level", "lootContainers_open_containers",
        "qol_repair", "qol_junk", "lootVendorRules_marked_sales", "merchantList_merchant_list",
    },
    characterGear = {
        "chatProfileLinks_profile_links", "characterUpgradeWindow_upgrade_equipment",
        "xpBar_xp_bar", "socketGemSuggestions_socket_gems", "loadoutReminder_loadout_reminder",
        "durabilityAlert_durability_warning", "professionAppearance_profession_outfits",
        "combatStatsHUD_secondary_stats",
        "targetDistance_target_distance", "characterExtras_character_extras",
    },
    groupRaid = {
        "battleRes_battle_res", "groupBloodlust_bloodlust_lockout",
        "groupDeathAlert_group_death_alert", "innervateCue_innervate_cue",
        "groupRaidShortcuts_raid_shortcuts", "trustedPartyInvites_trusted_invites", "releaseProtection_release_protection",
    },
    groupFinderMythic = {
        "groupFinderExitReminder_group_finder_exit", "groupFinderDoubleClick_group_finder_double_click",
        "mythicKeyShare_keystone_command", "groupFinderApplicantSort_group_finder_applicant_sort",
        "mythicResetReminder_mythic_reset", "tooltipMPlusScore_mplus_score",
        "enemyCastStack_dungeon_casts", "dungeonPortals_dungeon_portals",
    },
    combatAlerts = {
        "selfCombatText_self_combat_text",
        "actionTracker_action_tracker", "burningRushCue_burning_rush_cue",
        "combatLog_log_dungeons", "macroBuilder_macro_builder",
        "combatMovementCue_movement_cue", "combatPetStatus_pet_status", "threatMeter_threat_meter",
    },
    mapTravel = {
        "mapLandingShortcuts_expansion_shortcuts",
        "skyriding_flight_hud", "waypoints_waypoint_command", "flightTimer_flight_route",
    },
    interfaceChat = {
        "cursorEffects_cursor_effects", "guildChatPrivacy_guild_privacy",
        "quietPopups_quiet_popups", "uiErrorFilter_ui_error_filter", "popupAttention_popup_attention",
    },
    tooltips = {
        "tooltipClassColors_class_colors", "tooltipSpellCopy_copy_spell_id",
        "itemCounts_item_counts", "tooltipIDs_tooltip_ids", "tooltipVisibility_tooltip_visibility", "tooltipDetails_tooltip_details",
    },
}
local qolRows = assert(qolPage.qualityOfLifeFeatureRows
    or (qolPage.entry and qolPage.entry.qualityOfLifeFeatureRows),
    "Quality of Life feature rows were not exposed to direct navigation")
assert(qolRows.suite_qualityOfLife_partyEffects_party_effects == nil, "Celebrations row is still visible")
assert(#qolPage.sections == 9, "Quality of Life should have nine category accordions")
local categoriesSeen = {}
for i, section in ipairs(qolPage.sections) do
    local category = section.sectionId:match("^suite_qualityOfLife_category_(.+)$")
    assert(category and qolFeaturesByCategory[category] and not categoriesSeen[category],
        "unexpected or duplicate Quality of Life category accordion: " .. tostring(section.sectionId))
    categoriesSeen[category] = true
    assert(rawget(section, "headerSwitch") == nil,
        "category must not turn all features on or off: " .. category)
    assert(i == 1 or qolPage.sections[i - 1].title < section.title,
        "Quality of Life categories are not alphabetically sorted")
end
local expectedQolFeatureCount = 0
local expectedQolFeatures = {}
for category, features in pairs(qolFeaturesByCategory) do
    assert(categoriesSeen[category], "missing Quality of Life category: " .. category)
    for _, name in ipairs(features) do
        assert(not expectedQolFeatures[name], "duplicate expected Quality of Life feature: " .. name)
        expectedQolFeatures[name] = category
        expectedQolFeatureCount = expectedQolFeatureCount + 1
        local oldSectionId = "suite_qualityOfLife_" .. name
        local row = assert(qolRows[oldSectionId], "missing Quality of Life feature row: " .. name)
        assert(row.category == category and row.toggle and row.toggle.meta
            and row.toggle.meta.sectionId == oldSectionId,
            "Quality of Life feature has wrong category or no independent switch: " .. name)
        local search = row.toggle.searchMeta
        assert(search and search.pageKey == "suite_qualityOfLife" and search.kind == "toggle"
            and search.sectionId == oldSectionId
            and search.settingKey == row.toggle.meta.settingKey
            and row.row.tooltip and row.toggle.tooltip
            and (not row.settings or row.settings.tooltip)
            and type(row.row.tooltip.title) == "string",
            "Quality of Life feature lost its direct search entry or help: " .. name)
    end
end
-- Owner decision (2026-10-03): both cinematic skips stay, off by default,
-- and their controls warn that skipping ends Blizzard's movie or cinematic
-- from addon code.
;(function()
    local record = assert(qolRows["suite_qualityOfLife_dailyComfort_daily_comfort"], "Daily UI comforts has no row")
    record.reveal(true)
    local warning = optionsNS.Tr("Skipping ends Blizzard's movie or cinematic from addon code, which can rarely cause"
        .. " an \"Interface action blocked\" message later.")
    local found = {}
    for _, widget in ipairs(qolPage.widgets) do
        local meta = rawget(widget, "meta")
        local key = type(meta) == "table" and meta.settingKey
        if key == "msufsuite.dailyComfort.skipCinematicConfirm" or key == "msufsuite.dailyComfort.autoSkipCinematic" then
            local tooltip = rawget(widget, "tooltip")
            assert(tooltip and tooltip.body == warning, key .. " has no cinematic warning")
            found[#found + 1] = key
        end
    end
    assert(#found == 2, "the cinematic skip controls were not built")
    local rules = S.catalog.dailyComfort.rules
    assert(rules.skipCinematicConfirm.default == false and rules.autoSkipCinematic.default == false
        and rules.autoSkipCinematic.automation and S.catalog.dailyComfort.defaultEnabled == false,
        "a cinematic skip is on by default")
end)()
local actualQolFeatureCount = 0
for name in pairs(qolRows) do
    actualQolFeatureCount = actualQolFeatureCount + 1
    assert(expectedQolFeatures[name:gsub("^suite_qualityOfLife_", "")],
        "Quality of Life feature was not assigned to the proposed categories: " .. name)
end
assert(expectedQolFeatureCount == 63 and actualQolFeatureCount == expectedQolFeatureCount,
    "Quality of Life features are missing or duplicated")
local sourceCategories = assert(optionsNS.QualityOfLifeCategories,
    "Quality of Life category source was not published for search")
assert(#sourceCategories == 9, "Quality of Life source should define nine categories")
local sourceSeen, sourceCount, tabbedCount, expectedRenderedOrder = {}, 0, 0, {}
local function CheckFeatureList(features, category, tab, appendRenderedOrder)
    local previousTitle
    for _, feature in ipairs(features) do
        local title = optionsNS.Tr(feature.title)
        assert(not previousTitle or previousTitle < title,
            "Quality of Life features are not alphabetic inside " .. category .. "/" .. tostring(tab))
        previousTitle = title
        local name = feature.id .. "_" .. feature.sections[1]
        assert(expectedQolFeatures[name] == category
            and feature.category == category and (tab == false or feature.tab == tab),
            "Quality of Life feature source has the wrong category or tab: " .. name)
        if appendRenderedOrder then
            assert(not sourceSeen[name], "Quality of Life feature rendered twice: " .. name)
            sourceSeen[name] = true
            sourceCount = sourceCount + 1
            expectedRenderedOrder[#expectedRenderedOrder + 1] = "suite_qualityOfLife_" .. name
        end
    end
end
for i, category in ipairs(sourceCategories) do
    assert(categoriesSeen[category.id], "unknown Quality of Life source category: " .. tostring(category.id))
    assert(qolPage.sections[i].sectionId == "suite_qualityOfLife_category_" .. category.id,
        "Quality of Life source order differs from the rendered accordions")
    CheckFeatureList(category.features, category.id, false, false)
    if category.tabs then
        tabbedCount = tabbedCount + 1
        assert(#category.tabs == 2, "Quality of Life category has an unexpected tab count")
        for j, tab in ipairs(category.tabs) do
            assert(j == 1 or optionsNS.Tr(category.tabs[j - 1].title) < optionsNS.Tr(tab.title),
                "Quality of Life submenus are not alphabetically sorted")
            CheckFeatureList(tab.features, category.id, tab.id, true)
        end
    else
        CheckFeatureList(category.features, category.id, nil, true)
    end
end
assert(tabbedCount == 3 and sourceCount == expectedQolFeatureCount,
    "Quality of Life source tabs or rendered feature inventory changed")
local renderedOrder = assert(qolPage.qualityOfLifeFeatureOrder,
    "Quality of Life page did not record the rendered feature order")
assert(#renderedOrder == #expectedRenderedOrder,
    "Quality of Life rendered feature count differs from its source")
for i, sectionId in ipairs(expectedRenderedOrder) do
    assert(renderedOrder[i] == sectionId,
        "Quality of Life rendered feature order differs from its sorted source: " .. sectionId)
end
local route = {
    ["msufsuite.actionTracker.rows"] = "actionTracker_action_tracker",
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
            "Quality of Life search route lost its stable feature section ID")
        local live = widget.searchMeta
        assert(live and live.pageKey == "suite_qualityOfLife"
            and live.settingKey == meta.settingKey and live.sectionId == meta.sectionId,
            "opened Quality of Life setting will duplicate its search-provider result")
        routed = routed + 1
    end
end
assert(routed == 15, "Quality of Life settings lost their search routes: " .. routed)
end
do
    local actionToggle = qolPage.Section("actionTracker_action_tracker").headerSwitch
    assert(S.Config("actionTracker").look == 6 and S.Config("actionTracker").rows == 5,
        "Action tracker must start with the Suite factory look")
    actionToggle.set(true)
    assert(actionToggle.get() and S.Config("actionTracker").enabled,
        "Action tracker header switch did not enable its module")
    local actionControls = {}
    for _, widget in ipairs(qolPage.widgets) do
        local key = widget.meta and widget.meta.settingKey
        if key and key:match("^msufsuite%.actionTracker%.") then
            actionControls[key:match("%.([^.]+)$")] = widget
        end
    end
    assert(actionControls.look and actionControls.displayPreset and actionControls.rows and actionControls.fontSize
        and not actionControls.x and not actionControls.y and not actionControls.point,
        "Action tracker styling controls are missing")
    actionControls.displayPreset.set(2)
    assert(S.Config("actionTracker").displayPreset == 2,
        "Icon-only preset was not saved")
    actionControls.look.set(2)
    assert(S.Config("actionTracker").look == 2 and S.Config("actionTracker").panelColor == "0a1220",
        "Action tracker preset did not apply its palette")
    local colorTarget
    for _, target in ipairs(qolPage.Section("actionTracker_action_tracker").colorShortcut.options.getTargets()) do
        if target.settingKey == "msufsuite.actionTracker.panelColor" then colorTarget = target; break end
    end
    assert(colorTarget, "Action tracker row color is missing from its picker")
    colorTarget.set(1, 0, 0)
    assert(S.Config("actionTracker").look == 5 and S.Config("actionTracker").panelColor == "ff0000",
        "Action tracker custom color did not retain its Custom style")
    actionToggle.set(false)
    assert(not actionToggle.get(), "Action tracker header switch did not disable its module")
end
local xpBar = qolPage.Section("xpBar_xp_bar").headerSwitch
xpBar.set(true)
assert(xpBar.get() and S.Config("xpBar").enabled, "XP bar header switch did not enable its module")
xpBar.set(false)
assert(not xpBar.get(), "XP bar header switch did not disable its module")
do
    -- The XP bar's Custom style paints its own colors, so every style is offered.
    assert(optionsNS.ChoiceGates.xpBar == nil, "the XP bar hid one of its styles")
end
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
    local spec = Suite.SuiteCatalog[id]
    local controls = spec.getControls and spec.getControls(S.Config(id)) or spec.controls
    for _, rule in ipairs(controls) do
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
assert(not globalColors["msufsuite.dataTexts.bar4Slot1Background"],
    "MSUF Colors exposed a color setting for an unconfigured DataTexts bar")
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
    SourceText = function(key) return key == "ACCENT" and "Accent" or key end,
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
    L = setmetatable({}, { __index = function(_, key) return key end }), SourceText = function(key) return key end }
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", skin)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", skin)
assert(skin.Defaults.theme.look == "cleanModern" and skin.Defaults.theme.preset == "cleanModern")
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
    "Skin preview must own the fixed header before Basics")
assert(table.concat(previewSurfaces, ",") == "shell,panel,card,buttonPrimary",
    "Skin preview must render with the same engine surfaces as the runtime")
assert(skinContext.sections[1].sectionId == "suite_skin_frame_basic"
    and skinContext.sections[1].headerSwitch
    and skinContext.sections[2].sectionId == "suite_skin_basic", "Skin Basics is not first")
-- The default Suite meter owns Blizzard's damage meter, so Skinning has no
-- section for it; Glass follows the Micro Bar directly.
assert(S.Config("damageMeter").enabled == true and S.OwnsBlizzardSurface("damageMeter"),
    "the default Suite meter must own Blizzard's damage meter")
assert(skinContext.sections[3].sectionId == "suite_skin_micro"
    and skinContext.sections[4].sectionId == "suite_skin_material",
    "Micro Bar setup must be immediately visible after the main look")
for _, section in ipairs(skinContext.sections) do
    assert(section.sectionId ~= "suite_skin_micro_load_conditions" and section.sectionId ~= "suite_skin_micro_details",
        "Micro Bar tabs still have separate accordions")
end
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
do
    local microTabs
    for _, record in ipairs(skinContext.tabControls or {}) do
        if record.frames.general and record.frames.visibility and record.frames.details then microTabs = record end
    end
    assert(microTabs and microTabs.frames.general:IsShown() and not microTabs.frames.visibility:IsShown()
        and not microTabs.frames.details:IsShown(), "Micro Bar must start with only General visible")
    local generalBottom = skinContext.sections[3]._msuf2CursorY
    local function Reveal(widget, tab)
        assert(widget and type(widget._msuf2PrepareExactSearchTarget) == "function",
            "Micro Bar search target lacks tab preparation")
        widget:_msuf2PrepareExactSearchTarget()
        assert(microTabs.segment.value == tab, "Micro Bar search opened the wrong tab")
        for key, panel in pairs(microTabs.frames) do
            assert(panel:IsShown() == (key == tab), "Micro Bar tabs show overlapping settings")
        end
    end
    local scale = skinControls["msufsuite.skin.icons.microMenu.scale"].get()
    Reveal(skinControls["msufsuite.skin.icons.microMenu.visibility"], "visibility")
    Reveal(skinControls["msufsuite.skin.icons.microMenu.loadHideMounted"], "visibility")
    Reveal(skinControls["msufsuite.skin.icons.microMenu.layoutMode"], "details")
    assert(skinContext.sections[3]._msuf2CursorY < generalBottom,
        "Micro Bar accordion did not grow for its Details tab")
    Reveal(registeredControls["menu2.suite_skin.skin.micro.reset"], "details")
    Reveal(registeredControls["menu2.suite_skin.skin.micro.move"], "general")
    Reveal(registeredControls["menu2.suite_skin.skin.micro.preset.modern"], "general")
    assert(skinControls["msufsuite.skin.icons.microMenu.scale"].get() == scale
        and skinContext.sections[3]._msuf2CursorY == generalBottom,
        "changing Micro Bar tabs changed settings or kept the Details height")
end
do
    local createFrame = CreateFrame
    CreateFrame = function() error("cold Skinning search must not create widgets") end
    local searchRows = optionsNS.SkinSearchRows()
    CreateFrame = createFrame
    assert(CheckSearchTargets(searchRows, { suite_skin = skinContext }, true) > 90,
        "cold Skinning search omitted settings or actions")
end
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
skin.DB.icons.microMenu.scale = 1.2
skin.DB.icons.microMenu.loadHideMounted = not skin.Defaults.icons.microMenu.loadHideMounted
skin.DB.icons.microMenu.spacing = 11
skin.Database.CreateFactoryProfile = function() return skin.CopyValue(skin.Defaults) end
skin.Typography.ApplyConfigured = function() end
skin.Adapters.ApplyAll = function() end
skin.Registry.RefreshAll = function() end
local microSection
for _, section in ipairs(skinContext.sections) do
    if section.sectionId == "suite_skin_micro" then microSection = section end
end
assert(microSection and microSection._msufSuiteSectionReset and microSection._msufSuiteSectionReset(),
    "Micro Bar has no combined section reset")
for _, key in ipairs({ "preset", "scale", "loadHideMounted", "spacing" }) do
    assert(skin.DB.icons.microMenu[key] == skin.Defaults.icons.microMenu[key],
        "Micro Bar reset omitted a tab setting: " .. key)
end
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
assert(meterSkinContext.sections[4].sectionId == "suite_skin_hud"
    and meterSkinContext.sections[5].sectionId == "suite_skin_material",
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
for _, widget in pairs(registeredControls) do
    local meta = widget.registeredMeta
    if meta and meta.settingKey then covered[meta.settingKey] = true end
end
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
-- Options that cannot apply on this client are hidden there: the gamepad
-- bar rule outside Forever, the assisted-combat recommendation on Forever
-- (no assisted combat there); the recommendation look needs a Suite style.
do
    local abRules = Suite.SuiteCatalog.actionbars.rules
    local forever = flavor == "Forever"
    assert((abRules.bar1HideGamepad.hidden == true) == not forever, "the gamepad bar rule shows on the wrong client")
    for _, key in ipairs({ "assistStyle", "assistColor", "assistAlpha", "assistExpansion", "assistX", "assistY" }) do
        assert((abRules[key].hidden == true) == forever, "the recommendation option shows on the wrong client: " .. key)
    end
    assert(abRules.assistColor.requiresChoice and abRules.assistColor.requiresChoice.key == "assistStyle"
        and not abRules.assistColor.requiresChoice.values[1], "the recommendation color ignores the Blizzard style")
end
-- Settings that only act below a parent switch or choice are gated by it,
-- and the stance and pet bars hide the macro name settings they cannot use.
do
    local ab, dm = Suite.SuiteCatalog.actionbars.rules, Suite.SuiteCatalog.damageMeter.rules
    for _, suffix in ipairs({ "BackgroundPaddingX", "BackgroundPaddingY", "BackgroundX", "BackgroundY", "BackgroundBorder" }) do
        assert(ab["bar1" .. suffix].enableKey == "bar1Background", "bar background setting without its switch: " .. suffix)
    end
    for _, key in ipairs({ "bar1LeftEndcapSize", "bar1LeftEndcapX", "bar3RightEndcapY" }) do
        local choice = ab[key].requiresChoice
        assert(choice and choice.key == key:gsub("Size$", ""):gsub("[XY]$", "") and not choice.values[1],
            "endcap setting without its shape: " .. key)
    end
    assert(ab.pageArrowSide.enableKey == "pageArrows", "the page arrow side ignores the page arrows switch")
    assert(ab.bar11MacroPoint.hidden and ab.bar12MacroX.hidden and ab.bar12MacroY.hidden and not ab.bar1MacroPoint.hidden,
        "stance or pet bars offer macro name anchors")
    for _, key in ipairs({ "timerDecimals", "timerDesaturate", "timerTextColor", "timerBackground", "timerBackgroundAlpha",
        "timerBorderSize", "timerBorderColor" }) do
        assert(dm[key].enableKey == "timer", "floating timer setting without its switch: " .. key)
    end
    local choice = dm.rowBorderIcon.requiresChoice
    assert(choice and choice.key == "rowBorderMode" and not choice.values[1], "the icon joins a row border that is off")
    -- The separate icon border draws with the row border thickness and
    -- color, so both stay editable while Row border is None.
    for _, key in ipairs({ "rowBorderSize", "rowBorderColor" }) do
        assert(not dm[key].requiresChoice and not dm[key].enableKey,
            "the icon border look is locked behind the row border: " .. key)
    end
end
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
assert(quick3.meta.classification == "action" and quick3.meta.settingKey == nil,
    "fixed bar switches shadow the selected bar's visibility-mode search route")
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
;(function()
    local function Prepare(widget, config)
        local before, historyBefore = {}, historyWrites
        for key, value in pairs(config) do before[key] = value end
        assert(type(widget._msuf2PrepareExactSearchTarget) == "function", "shared editor lacks search preparation")
        widget:_msuf2PrepareExactSearchTarget()
        for key, value in pairs(before) do assert(config[key] == value, "search changed " .. key) end
        for key in pairs(config) do assert(before[key] ~= nil, "search added " .. key) end
        assert(historyWrites == historyBefore, "search preparation wrote history")
    end

    current = bars
    local barConfig = S.Config("actionbars")
    picker.set(12)
    Prepare(size, barConfig)
    assert(picker.get() == 12, "generic bar search changed a compatible selection")
    Prepare(macro, barConfig)
    assert(picker.get() == 1 and macro.enabled, "macro search remained on an incompatible pet bar")
    picker.set(2)
    Prepare(size, barConfig)
    assert(picker.get() == 2, "bar search reset the current bar to its metadata template")
    local sizeBefore, templateBefore = barConfig.bar2Size, barConfig.bar1Size
    size.set(sizeBefore + 1)
    assert(barConfig.bar2Size == sizeBefore + 1 and barConfig.bar1Size == templateBefore,
        "searched bar control wrote the metadata template instead of the selected bar")
    barConfig.bar2Size = sizeBefore
    picker.set(1)

    current = dm
    local countBefore = dmConfig.windowCount
    dmConfig.windowCount = 3
    windowPicker.set(3)
    Prepare(windowType, dmConfig)
    assert(windowPicker.get() == 3, "window search changed an active selection")
    dmConfig.windowCount = 1
    Prepare(windowType, dmConfig)
    assert(windowPicker.get() == 1, "window search stayed on a disabled extra window")
    dmConfig.windowCount = countBefore

    current = contexts.suite_cooldownManager
    local page, config = optionsNS.CDMPage, S.Config("cooldownManager")
    local function Control(key)
        return assert(Find(current, function(widget)
            return widget.meta and widget.meta.settingKey == "msufsuite.cooldownManager." .. key
        end), key)
    end
    local name, iconSize, timerWidth = Control("c1_name"), Control("c1_size"), Control("c1_barWidth")
    page.Select("ess")
    Prepare(iconSize, config)
    assert(page.selected == "ess", "cooldown search changed a compatible built-in selection")
    local oldSize, customSize = config.ess_size, config.c1_size
    iconSize.set(oldSize + 1)
    assert(config.ess_size == oldSize + 1 and config.c1_size == customSize,
        "searched cooldown control wrote the custom template instead of the selected bar")
    config.ess_size = oldSize
    Prepare(name, config)
    assert(page.SlotInfo(page.selected).custom and page.Relevant(page.selected, "name"),
        "bar name search stayed on an unrenameable built-in bar")
    local custom = page.selected
    Prepare(name, config)
    assert(page.selected == custom, "bar name search changed an already compatible custom bar")
    page.Select("ess")
    Prepare(timerWidth, config)
    assert(page.selected ~= "ess" and page.Relevant(page.selected, "barWidth"),
        "timer bar search stayed on an incompatible icon bar")
    page.Select("ess")
    current = dm
end)()
local meterLook = Find(dm, function(w) return w.meta and w.meta.settingKey == "msufsuite.damageMeter.look" end)
local meterBorder = ColorTarget(dm, "suite_damageMeter_window", "msufsuite.damageMeter.borderColor")
assert(meterLook and meterBorder and dmConfig.look == 5 and dmConfig.borderColor == "333333",
    "Clean Modern damage meter factory look is missing from the menu")
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
do
local specPreview = previewControls["menu2.suite_minimap.minimap.preview.specialization"]
assert(not S.catalog.mapQuickSwitch, "QoL must no longer own specialization settings")
if flavor == "Forever" then
    assert(not specPreview, "Forever must not offer a Retail specialization preview")
else
    assert(specPreview and not specPreview.shown, "specialization preview must start hidden with its setting")
    local config = S.Config("minimap")
    config.specButton, config.specSize, config.specCorner = true, 32, 3
    current = mm
    M.RequestRefresh()
    assert(specPreview.shown, "enabled specialization button missing from minimap preview")
    specPreview.scripts.OnClick(specPreview)
    assert(focusedSection == "suite_minimap_specialization", "specialization preview must open its own accordion")
    local deps, body = mm.fixedPreview.section.expander.box.selectionDeps, mm.fixedPreview.section.expander.box
    assert(deps.WriteOffsets(body, specPreview, 31, -17) and config.specX == 31 and config.specY == -17,
        "specialization selection editor must write independent minimap offsets")
    local cursorX, cursorY = 100, 100
    local originalCursor = GetCursorPosition
    GetCursorPosition = function() return cursorX, cursorY end
    specPreview.scripts.OnDragStart(specPreview)
    cursorX, cursorY = 110, 90
    specPreview.scripts.OnDragStop(specPreview)
    GetCursorPosition = originalCursor
    assert(config.specX > 31 and config.specY < -17, "specialization preview drag must save both offsets")
    config.specShowSpec, config.specShowLoot = false, false
    M.RequestRefresh()
    assert(not specPreview.shown, "preview must hide an empty specialization menu")
    config.specButton, config.specShowSpec, config.specShowLoot = false, true, true
end
end
local stylePreview = previewControls["menu2.suite_minimap.minimap.preview.style"]
local clockPreview = previewControls["menu2.suite_minimap.minimap.preview.infoClock"]
local locationPreview = previewControls["menu2.suite_minimap.minimap.preview.infoLocation"]
assert(folioPreview and stylePreview and clockPreview and locationPreview, "minimap preview targets missing")
do
    local config = S.Config("minimap")
    local original = { config.infoWeather, config.infoWeatherDisplay, config.infoWeatherIconStyle,
        config.infoWeatherIconSize, config.infoWeatherBox, config.infoWeatherBoxColor }
    local weather = previewControls["menu2.suite_minimap.minimap.preview.infoWeather"]
    local item
    for _, candidate in ipairs(weather.previewUI.textItems) do
        if candidate.spec[1] == "Weather" then item = candidate end
    end
    local function Control(key)
        return assert(Find(mm, function(w) return w.meta and w.meta.settingKey == "msufsuite.minimap." .. key end))
    end
    local display, icons, size = Control("infoWeatherDisplay"), Control("infoWeatherIconStyle"), Control("infoWeatherIconSize")
    config.infoWeather, config.infoWeatherBox = true, 2
    current = mm
    display.set(2); icons.set(2); size.set(48)
    M.RequestRefresh()
    local scale = weather.previewUI.art.scale
    local pixels = math.max(1, math.floor(48 * scale + .5))
    assert(item.label.text == "" and not item.label.shown and item.icon.shown
        and item.icon.texture == "Interface\\AddOns\\MSUF_Suite\\Media\\Weather\\Clear.tga"
        and item.icon.width == pixels and item.icon.height == pixels
        and math.abs(weather.height - math.max(18, 56 * scale)) < .001
        and math.abs(item.box.height - 52 * scale) < .001,
        "weather preview must scale the original icon, hit area and background without the module runtime")
    assert(not Control("infoWeatherFont").enabled and icons.enabled and size.enabled,
        "icon-only mode should disable unused text controls")
    display.set(3); icons.set(1)
    M.RequestRefresh()
    assert(item.icon.texture == 535593 and item.icon.shown and item.label.shown and item.label.text == "Clear",
        "weather preview ignored the native symbol or combined display")
    display.set(1)
    M.RequestRefresh()
    assert(item.label.text == "Clear" and item.label.shown and not item.icon.shown and not icons.enabled and not size.enabled
        and Control("infoWeatherFont").enabled, "text-only mode must disable unused icon controls")
    local boxColor = ColorTarget(mm, "suite_minimap_info_weather", "msufsuite.minimap.infoWeatherBoxColor")
    assert(boxColor and globalColors["msufsuite.minimap.infoWeatherBoxColor"],
        "weather background color must exist in both the section shortcut and MSUF Colors")
    boxColor.set(0x12 / 255, 0x34 / 255, 0x56 / 255)
    assert(config.infoWeatherBox == 3 and config.infoWeatherBoxColor == "123456",
        "section color picker must choose the custom box color immediately")
    M.RequestRefresh()
    assert(item.box.shown and math.abs(item.box.color[1] - 0x12 / 255) < .001,
        "preview ignored the section's custom background color")
    config.infoWeatherBox = 2
    globalColors["msufsuite.minimap.infoWeatherBoxColor"].set(0x65 / 255, 0x43 / 255, 0x21 / 255)
    assert(config.infoWeatherBox == 3 and config.infoWeatherBoxColor == "654321",
        "global Colors did not use the same custom background path")
    config.infoWeatherBox = 1
    boxColor.set(0x12 / 255, 0x34 / 255, 0x56 / 255)
    assert(config.infoWeatherBox == 1, "preparing a background color must not enable a hidden box")
    config.infoWeather, config.infoWeatherDisplay, config.infoWeatherIconStyle,
        config.infoWeatherIconSize, config.infoWeatherBox, config.infoWeatherBoxColor = unpack(original)
    M.RequestRefresh()
end
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
-- MBB owns the addon buttons while loaded and the arrangement menu refuses
-- to open: its button is disabled then.
do
    local arrange = registeredControls["menu2.suite_minimap.minimap.action.button_positions"]
    local config = S.Config("minimap")
    local layoutMenu, enabledBefore, collectBefore = S.MinimapButtonLayoutMenu, config.enabled, config.collectButtons
    S.MinimapButtonLayoutMenu = function() return true end
    config.enabled, config.collectButtons = true, true
    M.RequestRefresh()
    assert(arrange and arrange.enabled, "harness: the arrangement button stays disabled without MBB")
    Suite.Client.IsAddOnLoaded = function(name)
        if name == "MinimapButtonButton" then return true end
        return originalIsAddOnLoaded(name)
    end
    M.RequestRefresh()
    assert(not arrange.enabled, "the arrangement button stays enabled while MBB owns the addon buttons")
    Suite.Client.IsAddOnLoaded = originalIsAddOnLoaded
    S.MinimapButtonLayoutMenu = layoutMenu
    config.enabled, config.collectButtons = enabledBefore, collectBefore
    M.RequestRefresh()
end
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
-- Runtime data never rides undo. Data that existed at the snapshot, changed
-- afterwards or was created afterwards (saved chat lines, gold ledgers, bag
-- gold, run and XP history, module state) survives a restore unchanged.
;(function()
    local root = Suite.RootDB
    root.chatHistory = { Player = { lines = { "first" } } }
    root.goldLedger = { Player = 100 }
    root.suiteBagRecent = { guid = "Player", items = { [5] = true }, order = { 5 }, dismissed = {} }
    root.suiteBagSort = { Player = { before = false, applied = true } }
    root.suiteCharacters = { ["Player-1"] = { runSummary = { history = { { historyID = 1 } } } } }
    -- Detached minimap addon buttons are Edit Mode layout and ride undo.
    local placed = { LibDBIcon10_Test = { x = 10, y = 20 } }
    Suite.DB.suite.moduleState = { runSummary = { history = { "run 1" } },
        minimap = { detachedButtons = placed } }
    local size = S.Config("minimap").size
    local snapshot = historyProvider.capture()
    local captured = snapshot.root.profiles[root.activeProfile].suite
    assert(snapshot.root.chatHistory == nil and snapshot.root.goldLedger == nil
        and snapshot.root.suiteBagRecent == nil and snapshot.root.suiteBagSort == nil
        and snapshot.root.suiteCharacters == nil and captured.moduleState == nil
        and captured.modules.minimap.size == size,
        "Suite history copied runtime data or missed the settings")
    root.chatHistory.Player.lines[2] = "second"
    root.goldLedger.Player = 250
    root.suiteBagRecent.items[6], root.suiteBagSort.Player.applied = true, false
    table.insert(root.suiteCharacters["Player-1"].runSummary.history, 1, { historyID = 2 })
    root.suiteBagGold, root.suiteRuns, root.suiteXP = { Player = 7 }, { { map = 1 } }, { session = 5 }
    Suite.DB.suite.moduleState.runSummary.history[2] = "run 2"
    placed.LibDBIcon10_Test.x, placed.LibDBIcon10_Other = 99, { x = 1, y = 1 }
    S.Config("minimap").size = size + 10
    assert(historyProvider.restore(snapshot) and S.Config("minimap").size == size,
        "Suite history did not restore a setting")
    assert(root.chatHistory.Player.lines[2] == "second" and root.goldLedger.Player == 250
        and root.suiteBagGold.Player == 7 and root.suiteRuns[1].map == 1 and root.suiteXP.session == 5
        and root.suiteBagRecent.items[6] and root.suiteBagSort.Player.applied == false
        and Suite.DB.suite.moduleState.runSummary.history[2] == "run 2"
        and #root.suiteCharacters["Player-1"].runSummary.history == 2,
        "Suite history restore rolled back or deleted runtime data")
    local restored = Suite.DB.suite.moduleState.minimap.detachedButtons
    assert(restored ~= placed and restored.LibDBIcon10_Test.x == 10 and restored.LibDBIcon10_Test.y == 20
        and restored.LibDBIcon10_Other == nil and snapshot.root.profiles[root.activeProfile].layoutState
        .minimap.detachedButtons.LibDBIcon10_Test.x == 10, "undo did not restore the detached minimap buttons")
    root.chatHistory, root.goldLedger, root.suiteBagGold, root.suiteRuns, root.suiteXP = nil, nil, nil, nil, nil
    root.suiteBagRecent, root.suiteBagSort = nil, nil
    root.suiteCharacters = nil
    Suite.DB.suite.moduleState = nil
end)()
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

assert(S.ApplyGlobalLook("cleanModern"), "Clean Modern global look was rejected")
assert(S.Config("actionbars").look == 5 and S.Config("actionbars").interactionColor == "e6ecf2"
    and S.Config("minimap").stylePreset == 11
    and S.Config("damageMeter").look == 5 and S.Config("damageMeter").bgColor == "101010"
    and S.Config("bags").look == 5 and S.Config("bags").accentColor == "e6ecf2"
    and S.Config("chat").look == 5 and S.Config("chat").accentColor == "e6ecf2"
    and S.Config("dataTexts").look == 5 and S.Config("xpBar").look == 5
    and S.Config("skyriding").look == 5
    and cooldowns.ess_glowColor == "e6ecf2"
    and S.Config("actionbars").bar1Visibility == savedVisibility
    and S.Config("minimap").x == savedPosition,
    "Clean Modern did not style Suite modules or changed layout/visibility")

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
-- The toolbar's Reset page asks first, in Blizzard's generic confirmation,
-- without an entry in Blizzard's StaticPopupDialogs.
do
    local previousGeneric, previousDialogs = _G.StaticPopup_ShowCustomGenericConfirmation, _G.StaticPopupDialogs
    local asked
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_ShowCustomGenericConfirmation = function(data) asked = data end
    assert(S.SetMany("dataTexts", { bar2X = 58 }))
    assert(M.ShowPageResetConfirm("suite_dataTexts") and asked and asked.text == "%s"
        and asked.text_arg1 == M.BuildPageResetWarning("suite_dataTexts") and S.Config("dataTexts").bar2X == 58,
        "Reset page did not ask first")
    asked.callback()
    assert(S.Config("dataTexts").bar2X == S.catalog.dataTexts.rules.bar2X.default,
        "confirming Reset page did not reset the page")
    assert(next(_G.StaticPopupDialogs) == nil, "Reset page wrote into Blizzard's StaticPopupDialogs")
    _G.StaticPopup_ShowCustomGenericConfirmation, _G.StaticPopupDialogs = previousGeneric, previousDialogs
end
-- One question per key: a repeated question closes the earlier one (the
-- generic dialog allows several, and an earlier destructive Yes would stay
-- live), also when the Modules runtime loads between two questions.
do
    local shown = {}
    local previousGeneric, previousHide, previousConfirm =
        _G.StaticPopup_ShowCustomGenericConfirmation, _G.StaticPopup_Hide, S.Confirm
    S.Confirm = nil
    _G.StaticPopup_ShowCustomGenericConfirmation = function(data) shown[#shown + 1] = data end
    _G.StaticPopup_Hide = function(which, data)
        assert(which == "GENERIC_CONFIRMATION", "closed another dialog type")
        for i = #shown, 1, -1 do if shown[i] == data then table.remove(shown, i) end end
    end
    local resets = 0
    local reset = M.ResetPageToDefaults
    M.ResetPageToDefaults = function() resets = resets + 1; return true end
    assert(M.ShowPageResetConfirm("suite_dataTexts") and M.ShowPageResetConfirm("suite_dataTexts"))
    assert(#shown == 1, "a repeated Reset page question left the earlier one open")
    table.remove(shown) -- the player cancels the question on screen
    assert(#shown == 0 and resets == 0, "a cancelled Reset page question left a live Yes")
    optionsNS.Confirm("contract-a", "A", function() end)
    optionsNS.Confirm("contract-b", "B", function() end)
    assert(#shown == 2, "questions under different keys replaced each other")
    local runtimeKey
    S.Confirm = function(key) runtimeKey = key end
    optionsNS.Confirm("contract-a", "A again", function() end)
    assert(runtimeKey == "options:contract-a" and #shown == 1 and shown[1].text_arg1 == "B",
        "the runtime's question left the page's earlier one open")
    M.ResetPageToDefaults = reset
    -- Blizzard's StaticPopup_Hide exists on every client.
    _G.StaticPopup_ShowCustomGenericConfirmation, _G.StaticPopup_Hide, S.Confirm =
        previousGeneric, previousHide or function() end, previousConfirm
end
-- Text settings count bytes (Suite.lua ValidText): every bound text input of
-- a rule with a length limit takes as many bytes as the setter accepts, so a
-- CJK or Cyrillic text it takes is never refused afterwards.
;(function()
    local inputs = 0
    for _, ctx in pairs(contexts) do
        for _, widget in ipairs(ctx.widgets) do
            local meta = rawget(widget, "meta")
            local key = type(meta) == "table" and meta.settingKey
            local id, ruleKey
            if type(key) == "string" then id, ruleKey = key:match("^msufsuite%.([^.]+)%.(.+)$") end
            local spec = id and S.catalog[id]
            local rule = spec and spec.rules[ruleKey]
            if rawget(widget, "kind") == "EditBox" and rule and type(rule.default) == "string" and rule.maxLength then
                inputs = inputs + 1
                assert(rawget(widget, "maxBytes") == rule.maxLength + 1 and rawget(widget, "maxLetters") == nil,
                    key .. ": the text input is limited in letters, not in the bytes the setter counts")
            end
        end
    end
    assert(inputs > 0, "no rule text input was checked")
end)()
-- "Save setup as..." asks for a name in Blizzard's generic input box and
-- saves the MSUF frames, the Suite and the skin under it; refused in combat.
do
    local previousShow, previousSaveAs = _G.StaticPopup_Show, Suite.SuiteProfiles.SaveAs
    local asked, saved
    -- Blizzard's shared dialog edit box: its own code sets no byte limit.
    local edit = { maxBytes = 0 }
    function edit:SetMaxBytes(value) self.maxBytes = value end
    function edit:GetMaxBytes() return self.maxBytes end
    local dialog = { GetEditBox = function() return edit end }
    _G.StaticPopup_Show = function(which, _, _, data, _, onHide)
        asked = { which = which, data = data, onHide = onHide }
        return dialog
    end
    Suite.SuiteProfiles.SaveAs = function(name) saved = name; return true end
    assert(optionsNS.SaveSetupAs() and asked and asked.which == "GENERIC_INPUT_BOX"
        and asked.data.maxLetters == Suite.Database.MAX_PROFILE_NAME_BYTES, "Save setup as did not ask for a name")
    -- The name rule counts bytes: the box takes no more (the limit counts the
    -- terminating zero byte), and gives the shared box its own limit back.
    assert(edit.maxBytes == Suite.Database.MAX_PROFILE_NAME_BYTES + 1 and asked.onHide,
        "the name box takes a name in bytes the profile name rule refuses")
    asked.onHide(dialog)
    assert(edit.maxBytes == 0, "the shared dialog edit box kept the Suite's byte limit")
    asked.data.callback("Raid setup")
    assert(saved == "Raid setup", "Save setup as did not save the setup under the name")
    local appearance = assert(io.open(root .. "/MSUF_Suite_Options/Pages/Appearance.lua", "rb"))
    local source = appearance:read("*a")
    appearance:close()
    assert(source:find("P.SaveSetupAs", 1, true), "the Skinning page lost the Save setup as button")
    local lockdown = InCombatLockdown
    InCombatLockdown = function() return true end
    asked, saved = nil, nil
    assert(not optionsNS.SaveSetupAs() and not asked, "Save setup as asked in combat")
    InCombatLockdown = lockdown
    _G.StaticPopup_Show, Suite.SuiteProfiles.SaveAs = previousShow, previousSaveAs
end
-- "Restore chat colors" asks in Blizzard's generic confirmation (no
-- StaticPopupDialogs entry), naming every chat category it changes and
-- how, then puts exactly those back through the Suite core and reports what
-- failed; with nothing to restore it only says so; refused in combat. (One
-- state table: this chunk is near Lua's 200-local limit.)
do
    local rc = { previous = { _G.StaticPopup_ShowCustomGenericConfirmation, _G.StaticPopupDialogs,
        Suite.Skin.RestoreChatColors, S.Confirm, M.ShowStatusFeedback, InCombatLockdown,
        Suite.Skin.ChatColorRestorePlan },
        restores = 0, result = { true, 3, 0 } }
    M.ShowStatusFeedback = function(text, kind) rc.feedback = { text = text, kind = kind } end
    S.Confirm = nil
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_ShowCustomGenericConfirmation = function(data) rc.asked = data end
    rc.plan = { { chatType = "SYSTEM", color = { 1, 1, 0 }, recorded = true },
        { chatType = "MONSTER_PARTY", color = { 0.6, 0.6, 1 } } }
    Suite.Skin.ChatColorRestorePlan = function() return rc.plan end
    Suite.Skin.RestoreChatColors = function(asked)
        rc.restores, rc.restoredTypes = rc.restores + 1, asked
        return rc.result[1], rc.result[2], rc.result[3]
    end
    assert(optionsNS.RestoreChatColors() and rc.asked and rc.restores == 0, "Restore chat colors did not ask first")
    rc.text = rc.asked.text_arg1
    assert(rc.text:find(M.Tr("Restore these chat colors?"), 1, true)
        and rc.text:find(M.Tr("%s: back to the color it had before the skin"):format(M.Tr("System messages")), 1, true)
        and rc.text:find(M.Tr("%s: back to Blizzard's default color"):format(M.Tr("NPC party chat")), 1, true)
        and not rc.text:find(M.Tr("NPC speech"), 1, true)
        and rc.text:find(M.Tr("Your other chat colors stay as they are."), 1, true),
        "the question does not say exactly what Restore chat colors changes: " .. rc.text)
    rc.asked.callback()
    assert(rc.restores == 1 and next(_G.StaticPopupDialogs) == nil, "Restore chat colors did not restore through the core")
    assert(rc.restoredTypes and rc.restoredTypes.SYSTEM and rc.restoredTypes.MONSTER_PARTY
        and not rc.restoredTypes.MONSTER_SAY, "Yes may change a category the question did not name")
    assert(rc.feedback and rc.feedback.kind == "ok", "a full restore did not report success")
    -- Every write failed, then some: the feedback says so.
    rc.result = { false, 0, 3 }
    optionsNS.RestoreChatColors()
    rc.asked.callback()
    assert(rc.feedback.kind == "warning" and rc.feedback.text == M.Tr("Chat colors could not be restored"),
        "a restore where every write failed reported success")
    rc.result = { false, 2, 1 }
    optionsNS.RestoreChatColors()
    rc.asked.callback()
    assert(rc.feedback.kind == "warning" and rc.feedback.text == M.Tr("Some chat colors could not be restored"),
        "a partly failed restore was not reported")
    -- Combat began between the question and Yes: the core refuses before
    -- any write (false, "combat"), which is not a partial restore.
    rc.result = { false, "combat" }
    optionsNS.RestoreChatColors()
    rc.asked.callback()
    assert(rc.feedback.kind == "warning" and rc.feedback.text == M.Tr("Finish combat first."),
        "a restore refused in combat was reported as a partial restore")
    -- Nothing shows the skin's colour and nothing was recorded: no question.
    rc.plan, rc.asked, rc.restores = {}, nil, 0
    assert(optionsNS.RestoreChatColors() and not rc.asked and rc.restores == 0 and rc.feedback.text
        == M.Tr("No chat color needs restoring: none shows the skin's color, and none was recorded."),
        "Restore chat colors asked although nothing would change")
    rc.plan = { { chatType = "SYSTEM", color = { 1, 1, 0 } } }
    InCombatLockdown = function() return true end
    rc.asked = nil
    assert(not optionsNS.RestoreChatColors() and not rc.asked, "Restore chat colors asked in combat")
    -- Both actions are built in every state of the Skinning page: its
    -- Maintenance, the engine-unavailable Basics and the Skin addon's notice.
    local appearance = assert(io.open(root .. "/MSUF_Suite_Options/Pages/Appearance.lua", "rb"))
    rc.source = appearance:read("*a"):gsub("\r\n", "\n")
    appearance:close()
    rc.buttons = select(2, rc.source:gsub("\n%s+[%w%s=]-MaintenanceButtons%(ctx, ", ""))
    assert(rc.buttons == 4 and rc.source:find("run = function() return P.RestoreChatColors() end", 1, true)
        and rc.source:find("run = function() return P.SaveSetupAs() end", 1, true)
        and rc.source:find("notice = BuildNotice", 1, true),
        "Restore chat colors or Save setup as is missing from a state of the Skinning page")
    _G.StaticPopup_ShowCustomGenericConfirmation, _G.StaticPopupDialogs, Suite.Skin.RestoreChatColors,
        S.Confirm, M.ShowStatusFeedback, InCombatLockdown, Suite.Skin.ChatColorRestorePlan = unpack(rc.previous, 1, 7)
end
-- The combat start: inside PLAYER_REGEN_DISABLED, before the lockdown, the
-- pages refuse like in combat (P.Combat is Suite.InCombat), and so do an
-- older menu's wrapped page reset and its confirmation.
do
    local edge = { flag = UnitAffectingCombat, previousGeneric = _G.StaticPopup_ShowCustomGenericConfirmation,
        previousShow = _G.StaticPopup_Show }
    _G.StaticPopup_ShowCustomGenericConfirmation = function(data) edge.asked = data end
    _G.StaticPopup_Show = function(_, _, _, data) edge.asked = data; return {} end
    assert(S.SetMany("dataTexts", { bar2X = 58 }))
    UnitAffectingCombat = function(unit) return unit == "player" end
    local watcher = { events = { PLAYER_REGEN_DISABLED = true } }
    local function OnEvent(_, event)
        assert(event == "PLAYER_REGEN_DISABLED" and not InCombatLockdown())
        edge.combat = optionsNS.Combat()
        edge.reset = M.ResetPageToDefaults("suite_dataTexts")
        edge.confirm = M.ShowPageResetConfirm("suite_dataTexts")
        edge.saveSetup = optionsNS.SaveSetupAs()
        edge.restore = optionsNS.RestoreChatColors()
    end
    OnEvent(watcher, "PLAYER_REGEN_DISABLED")
    UnitAffectingCombat = edge.flag
    assert(edge.combat == true and edge.reset == false and edge.confirm == false and not edge.saveSetup
        and not edge.restore and edge.asked == nil and S.Config("dataTexts").bar2X == 58,
        "a Suite page action went through at the combat start")
    _G.StaticPopup_ShowCustomGenericConfirmation, _G.StaticPopup_Show = edge.previousGeneric, edge.previousShow
end
-- Register.lua's real canReset handler (here through the legacy wrap, the
-- same handler a v1 provider gets) allocates nothing per call.
do
    assert(optionsNS.pageResetMode == "legacy", "this host took the v1 provider path")
    M.PageHasReset("suite_dataTexts")
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 100 do M.PageHasReset("suite_dataTexts") end
    local grown = collectgarbage("count") - before
    collectgarbage("restart")
    assert(grown < 0.1, ("the page reset canReset handler allocated %.2f KB in 100 calls"):format(grown))
end
-- The cooldown manager page resets like every Suite page: the standard
-- confirmation, then every cooldown manager setting back to its catalog
-- default; other modules keep theirs.
do
    local previousGeneric = _G.StaticPopup_ShowCustomGenericConfirmation
    local asked
    _G.StaticPopup_ShowCustomGenericConfirmation = function(data) asked = data end
    assert(M.PageHasReset("suite_cooldownManager"), "the cooldown manager page offers no Reset page")
    assert(S.SetMany("cooldownManager", { ess_size = 50 }) and S.SetMany("dataTexts", { bar2X = 58 }))
    -- Another profile keeps its own cooldown manager settings.
    assert(Suite.Database.Create("CDM reset witness", false))
    local witness = Suite.Database.GetProfile("CDM reset witness")
    witness.suite.modules.cooldownManager = witness.suite.modules.cooldownManager or {}
    witness.suite.modules.cooldownManager.ess_size = 51
    assert(M.ShowPageResetConfirm("suite_cooldownManager") and asked
        and asked.text_arg1 == M.BuildPageResetWarning("suite_cooldownManager")
        and S.Config("cooldownManager").ess_size == 50, "the cooldown manager Reset page did not ask first")
    asked.callback()
    -- A deliberate reset is stamped current so a later enable cannot migrate
    -- new edits over the reset. All other fields follow catalog + shared look.
    local expected = {}
    for key, rule in pairs(S.catalog.cooldownManager.rules) do expected[key] = rule.default end
    expected.defaultsVersion = Suite.CDM.DEFAULTS_VERSION
    if expected.enabled then Suite.SuiteLooks.ApplyToConfig("cooldownManager", expected, Suite.DB.suite.globalLook) end
    for key in pairs(S.catalog.cooldownManager.rules) do
        assert(S.Config("cooldownManager")[key] == expected[key], "the cooldown manager Reset page left " .. key)
    end
    assert(S.Config("dataTexts").bar2X == 58, "the cooldown manager Reset page changed another module")
    assert(Suite.Database.GetProfile("CDM reset witness").suite.modules.cooldownManager.ess_size == 51,
        "the cooldown manager Reset page changed another profile")
    Suite.Database.Delete("CDM reset witness")
    assert(S.SetMany("dataTexts", { bar2X = S.catalog.dataTexts.rules.bar2X.default }))
    _G.StaticPopup_ShowCustomGenericConfirmation = previousGeneric
end
assert(S.Config("actionbars").look == 1,
    "Suite page reset changed another page")
;(function()
    local changed = {}
    for _, id in ipairs(Suite.SuiteOrder) do
        if S.catalog[id].page == "suite_qualityOfLife" then
            S.Config(id).enabled = not S.catalog[id].rules.enabled.default
            changed[#changed + 1] = id
        end
    end
    assert(#changed > 9 and M.ResetPageToDefaults("suite_qualityOfLife"), "Quality of Life page reset failed")
    for _, id in ipairs(changed) do
        assert(S.Config(id).enabled == S.catalog[id].rules.enabled.default,
            "Quality of Life page reset skipped a module of its page: " .. id)
    end
end)()
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
assert(table.concat(categoryKeys, " ") == "visibility layout text ornaments background", "Copy To categories: " .. table.concat(categoryKeys, " "))
assert(o.isTargetVisible(source, source) == false and o.isTargetVisible(target, source) == true
    and o.isTargetVisible("all", source) == true, "Copy To destinations are wrong")
local choices = o.selectedTarget(source)
for index = 1, Suite.ActionBarCount do if choices[index] then o.onTargetClick(index) end end
local another = target == 3 and 4 or 3
if another == source then another = 5 end
o.onTargetClick(target);o.onTargetClick(another)
assert(o.selectedTarget(source)[target] and o.selectedTarget(source)[another], "Copy To lost multiple chosen destinations")
for key in pairs(o.scopes) do o.scopes[key] = key == "background" end
assert(S.SetMany("actionbars", { [p .. "Background"] = true, [q .. "Background"] = false, [q .. "Size"] = 40,
    ["bar" .. another .. "Background"] = false }))
local popupHidden
local popupStub = { Hide = function() popupHidden = true end }
o.onRun(nil, popupStub)
copiedConfig = S.Config("actionbars")
assert(popupHidden and copiedConfig[q .. "Background"] == true and copiedConfig["bar" .. another .. "Background"] == true,
    "Copy Selected missed one of the chosen destination bars")
assert(copiedConfig[q .. "Size"] == 40 and copiedConfig[q .. "X"] == 33, "Copy Selected copied an unchosen section or the position")
for key in pairs(o.scopes) do o.scopes[key] = false end
popupHidden = false
o.onRun(nil, popupStub)
assert(not popupHidden, "Copy Selected ran without a category")
o.onTargetClick(target);o.onTargetClick(another)
for key in pairs(o.scopes) do o.scopes[key] = true end
o.onRun(nil, popupStub)
assert(not popupHidden, "Copy Selected ran without a destination")
for key in pairs(o.scopes) do o.scopes[key] = true end
-- Copy to All asks in Blizzard's generic confirmation and adds no entry to
-- Blizzard's StaticPopupDialogs.
local previousGeneric, previousDialogs = _G.StaticPopup_ShowCustomGenericConfirmation, _G.StaticPopupDialogs
local confirmed
_G.StaticPopupDialogs = {}
_G.StaticPopup_ShowCustomGenericConfirmation = function(data) confirmed = data; data.callback() end
o.onTargetClick("all")
assert(S.SetMany("actionbars", { [p .. "Size"] = 44 }))
o.onRun(nil, popupStub)
assert(next(_G.StaticPopupDialogs) == nil, "Copy to All wrote into Blizzard's StaticPopupDialogs")
_G.StaticPopup_ShowCustomGenericConfirmation, _G.StaticPopupDialogs = previousGeneric, previousDialogs
assert(confirmed and confirmed.text == "%s" and confirmed.text_arg1:find("ALL action bars", 1, true),
    "Copy to All did not ask first")
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
    -- The DataTexts page's gold clear asks first too, like the Bags page's.
    local goldClear = assert(registeredControls["menu2.suite_dataTexts.dataTexts.action.clearGold"],
        "the DataTexts page has no Clear saved character gold action")
    local goldAsked
    local previousGeneric, previousConfirm, previousClear =
        _G.StaticPopup_ShowCustomGenericConfirmation, S.Confirm, Suite.ClearCharacterGold
    local goldCleared = 0
    S.Confirm, Suite.ClearCharacterGold = nil, function() goldCleared = goldCleared + 1 end
    _G.StaticPopup_ShowCustomGenericConfirmation = function(data) goldAsked = data end
    goldClear.scripts.OnClick(goldClear)
    assert(goldAsked and goldCleared == 0, "the DataTexts gold clear did not ask first")
    goldAsked.callback()
    assert(goldCleared == 1, "the DataTexts gold clear did not clear after Yes")
    _G.StaticPopup_ShowCustomGenericConfirmation, S.Confirm, Suite.ClearCharacterGold =
        previousGeneric, previousConfirm, previousClear
    local button = assert(registeredControls["menu2.suite_dataTexts.dataTexts.bar2.manage"])
    button._msuf2PrepareExactSearchTarget()
    assert(button.text == optionsNS.Tr("Apply preset to this bar"), "preset action is hidden behind an unrelated menu")
    for _, action in ipairs({ "duplicate", "shared" }) do
        local control = assert(registeredControls["menu2.suite_dataTexts.dataTexts.bar2." .. action],
            "direct bar action missing: " .. action)
        assert(control:IsVisible(), "bar action hidden: " .. action)
    end
    button.scripts.OnClick(button)
    local preset = assert(registeredControls["menu2.suite_dataTexts.dataTexts.bar2.preset.antique"],
        "Antique Footer preset preview is missing")
    local apply = function() preset.scripts.OnClick(preset) end
    local c = S.Config("dataTexts")
    local untouchedWidth = c.bar1Width
    apply()
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

;(function()
    local original = M.Tr
    M.Tr = function(text)
        if text == "Tooltips" or text == "Pet status warning" then return "!" .. text end
        if text == "Everyday & Automation" or text == "Action tracker" then return "~" .. text end
        return original(text)
    end
    local ctx = { key = "suite_qualityOfLife", width = 720, refreshers = {}, widgets = {},
        sections = {}, pageItems = {}, entry = { sections = {} } }
    M.pages.suite_qualityOfLife.build(ctx)
    assert(ctx.sections[1].sectionId == "suite_qualityOfLife_category_tooltips",
        "Quality of Life categories did not re-sort after a locale change")
    local firstCombat
    for _, sectionId in ipairs(ctx.qualityOfLifeFeatureOrder) do
        if ctx.qualityOfLifeFeatureRows[sectionId].category == "combatAlerts" then
            firstCombat = sectionId
            break
        end
    end
    assert(firstCombat == "suite_qualityOfLife_combatPetStatus_pet_status",
        "Quality of Life features did not re-sort after a locale change")
    M.Tr = original
end)()

-- The action and catalog providers must be independent of visiting a page.
-- Build lazy QoL details only for the separate, authoritative widget inventory.
-- With every module and Quality of Life feature on, the cold inventory is the
-- whole catalog: more than the 1200 targets the committed contract required
-- (34f2ede). The catalog only grows, so a smaller count means lost recall.
;(function()
    M.RegisterSearchProvider = function() return true end
    assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Search.lua"))("MSUF_Suite_Options", optionsNS)
    local saved = {}
    for _, id in ipairs(Suite.SuiteOrder) do
        saved[id] = { enabled = S.Config(id).enabled }
        S.Config(id).enabled = true
    end
    for _, feature in ipairs(optionsNS.QualityOfLifeSearchFeatures) do
        local config = S.Config(feature.id)
        saved[feature.id][feature.switch] = config[feature.switch]
        config[feature.switch] = true
    end
    local searchRows = optionsNS.SearchRows()
    local qol = contexts.suite_qualityOfLife
    for _, sectionId in ipairs(qol.qualityOfLifeFeatureOrder) do
        qol.entry._msuf2ResolveMissingSection(sectionId)
    end
    local pageContexts = {}
    for key, ctx in pairs(contexts) do
        if key ~= "suite_skin" then pageContexts[key] = ctx end
    end
    local expectedTargets = 0
    for _, row in ipairs(searchRows) do
        if pageContexts[row.pageKey] and (row.controlId or row.settingKey) then
            expectedTargets = expectedTargets + 1
        end
        assert(optionsNS.SearchRowAvailable(row.pageKey, row.settingKey, row),
            "cold search retained an inactive catalog setting or editor action")
    end
    assert(expectedTargets > 1200 and CheckSearchTargets(searchRows, pageContexts) == expectedTargets,
        "cold Suite search omitted catalog settings or editor actions: " .. expectedTargets)
    local controls = {}
    for _, row in ipairs(searchRows) do if row.controlId then controls[row.controlId] = true end end
    for _, feature in ipairs(optionsNS.QualityOfLifeSearchFeatures) do
        if optionsNS.QualityOfLifeEditElements[feature.id] and optionsNS.Available(feature.id) then
            local sectionId = "suite_qualityOfLife_" .. feature.id .. "_" .. feature.sections[1]
            local wanted = optionsNS.Meta("suite_qualityOfLife", feature.id, "action.edit", "action", sectionId).controlId
            assert(controls[wanted], "the Edit Mode button of " .. feature.id .. " is not searchable")
        end
    end
    for id, values in pairs(saved) do
        for key, value in pairs(values) do S.Config(id)[key] = value end
    end
end)()

-- Summary content follows useful settings, never declaration order or offsets.
;(function()
    local ctx = { refreshers = {} }
    local body = { _msuf2CollapsibleEntry = {} }
    local value, enabled = 240, true
    local rows = {
        { id = "w1X", label = "Offset", kind = "slider", get = function() return 999 end },
        { id = "w1Session", label = "Fight", kind = "dropdown", values = {{ value = 1, text = "Current fight" }}, get = function() return 1 end },
        { id = "w1Type", label = "Meter", kind = "dropdown", values = {{ value = 1, text = "Damage" }}, get = function() return 1 end },
    }
    for _, row in ipairs(rows) do row.summary = optionsNS.SummaryPriority("damageMeter", row.id) end
    optionsNS.AttachRowsSummary(ctx, body, rows)
    for _, refresh in ipairs(ctx.refreshers) do refresh() end
    assert(body.summary == "Meter: Damage · Fight: Current fight", "summary depends on grid order or displays a raw enum/offset")
    ctx, body = { refreshers = {} }, { _msuf2CollapsibleEntry = {} }
    local row = { id = "bar2Width", label = "Width", kind = "slider", get = function() return value end,
        summary = optionsNS.SummaryPriority("dataTexts", "bar2Width"), summaryEnabled = function() return enabled end }
    optionsNS.AttachRowsSummary(ctx, body, { row })
    ctx.refreshers[1]()
    assert(body.summary == "Width: 240", "numbered bar loses its summary")
    value = 380
    ctx.refreshers[1]()
    assert(body.summary == "Width: 380", "summary reads a stale selected scope")
    enabled = false
    ctx.refreshers[1]()
    assert(body.summary == "", "inactive setting remains in summary")
end)()

-- Concise help and disabled reasons are available on demand on the real bridge.
;(function()
    local oldDetails, oldDescription = W.DescriptionDetails, W.Description
    local visible, details
    W.DescriptionDetails = true
    W.Description = function(_, text, _, _, _, _, full) visible, details = text, full; return Widget("FontString") end
    optionsNS.Description({}, optionsNS.Help("Short summary", "Complete instructions"), 0, 0, 300)
    assert(visible == "Short summary" and details == "Complete instructions", "concise help lost its details")
    W.DescriptionDetails = nil
    optionsNS.Description({}, optionsNS.Help("Short summary", "Complete instructions"), 0, 0, 300)
    assert(visible == "Complete instructions", "older host loses help instructions")
    W.DescriptionDetails, W.Description = oldDetails, oldDescription

    local config = S.Config("chat")
    local wasEnabled, wasPanel, wasRendering = config.enabled, config.inputPanel, config.fontRendering
    config.enabled, config.inputPanel, config.fontRendering = true, false, 3
    optionsNS.ForgetAvailability()
    local rule = { key = "fontSize", enableKey = "inputPanel" }
    local enabled, why = optionsNS.RuleEnabled("chat", rule, nil, true)
    assert(not enabled and why:find("Show input background", 1, true), "disabled field does not name its prerequisite")
    local _, quiet = optionsNS.RuleEnabled("chat", rule)
    assert(quiet == nil, "normal refresh formats help nobody requested")
    config.inputPanel = true
    assert(optionsNS.RuleEnabled("chat", rule), "dependent field stays disabled after enabling its prerequisite")
    rule = { key = "fontSize", requiresChoice = { key = "fontRendering", values = { [1] = true } } }
    enabled, why = optionsNS.RuleEnabled("chat", rule, nil, true)
    assert(not enabled and why:find("Smooth", 1, true) and why:find("Font rendering", 1, true),
        "choice-dependent field does not explain its available choice")
    local context, widget = { refreshers = {} }, Widget("Slider")
    optionsNS.GateControls(context, "chat", { { rule = rule, widget = widget } })
    assert(type(widget.disabledReason) == "function" and widget.disabledReason():find("Smooth", 1, true),
        "disabled reason did not reach the control")
    config.fontRendering = 1
    assert(widget.disabledReason() == nil, "tooltip kept a stale disabled reason")
    config.enabled = false
    assert(widget.disabledReason():find(optionsNS.Tr(optionsNS.catalog.chat.title), 1, true),
        "disabled module reason does not name the module")
    config.enabled, config.inputPanel, config.fontRendering = wasEnabled, wasPanel, wasRendering

    -- A cold native false result is not a reason to discard the selected face.
    local previousOwner, previousStyled = MSUF_SetFontChecked, S.SetStyledFont
    S.SetStyledFont = nil
    MSUF_SetFontChecked = function(font, path, size, flags) font:SetFont(path, size, flags); return true end
    local font = { calls = 0, SetShadowColor = function() end, SetShadowOffset = function() end }
    function font:SetFont(path) self.path, self.calls = path, self.calls + 1; return false end
    optionsNS.StylePreviewFont(font, "Selected.ttf", 14, "", 1, false)
    assert(font.path == "Selected.ttf" and font.calls == 1, "preview replaced a pending custom font")
    -- The host setter on Retail and Forever (Kernel/MSUF_Libs.lua of the
    -- Classic host) answers the client's false for a font file it cannot
    -- load; the client keeps the label without a font, so the preview falls
    -- back to the standard font. A false answer while the label shows the
    -- requested file anyway keeps the face.
    MSUF_SetFontChecked = function(label, path, size, flags) return label:SetFont(path, size, flags or "") ~= false end
    local label = { calls = 0, SetShadowColor = function() end, SetShadowOffset = function() end }
    function label:SetFont(path, size, flags)
        self.calls = self.calls + 1
        if path ~= STANDARD_TEXT_FONT and path ~= "Fonts\\FRIZQT__.TTF" then return false end
        self.font = { path, size, flags }
        return true
    end
    function label:GetFont() if self.font then return unpack(self.font) end end
    optionsNS.StylePreviewFont(label, "Interface\\AddOns\\Gone\\gone.ttf", 13, "OUTLINE", 1, false)
    assert(label.font and label.font[2] == 13 and label.calls == 2,
        "preview kept no font after the host reported the chosen font as refused")
    local shown = { font = { "interface/addons/media/selected.ttf", 14, "" }, calls = 0,
        SetShadowColor = function() end, SetShadowOffset = function() end }
    function shown:SetFont() self.calls = self.calls + 1; return false end
    function shown:GetFont() return unpack(self.font) end
    optionsNS.StylePreviewFont(shown, "Interface\\AddOns\\Media\\Selected.ttf", 14, "", 1, false)
    assert(shown.calls == 1 and shown.font[1] == "interface/addons/media/selected.ttf",
        "preview replaced a face that applied despite a false answer")
    MSUF_SetFontChecked, S.SetStyledFont = previousOwner, previousStyled
end)()

-- The maximum import remains bounded at one selected bar and one inspector.
;(function()
    local config = S.Config("dataTexts")
    local savedIds, previousCurrent, previousTimer = config.barIds, current, C_Timer
    local ids = {}
    for id = 1, Suite.DataTextBarLimit do ids[id] = tostring(id) end
    config.barIds = table.concat(ids, ",")
    for _, width in ipairs({ 430, 720 }) do
    local ctx = { key = "suite_dataTexts", width = width, refreshers = {}, widgets = {},
        sections = {}, pageItems = {}, entry = { sections = {} } }
    current = ctx
    C_Timer = { After = function() error("maximum-bar menu scheduled a bulk build") end }
    M.pages.suite_dataTexts.build(ctx)
    local workspace = ctx.dataTextWorkspace
    local count = 0
    for _ in pairs(workspace.deck.views) do count = count + 1 end
    assert(count == 1 and #ctx.widgets < 90 and ctx.dataTextBarSelector,
        "maximum-bar profile eagerly built hidden views or lost its compact selector")
    assert(ctx.pageItems[1] == workspace.navigation
        and ctx.dataTextBarSelector.points[1][2] == workspace.navigation
        and workspace.buttons.add.parent == workspace.navigation,
        "narrow and maximum-bar selectors must share the navigation above DataTexts")
    local last = "suite_dataTexts_bar" .. Suite.DataTextBarLimit .. "_slot12"
    local body = ctx.entry._msuf2ResolveMissingSection(last)
    assert(body and workspace.deck.selected == Suite.DataTextBarLimit,
        "exact search cannot reach a dynamic bar past the old twelve templates")
    local warm = #ctx.widgets
    ctx.entry._msuf2ResolveMissingSection(last)
    assert(#ctx.widgets == warm, "warm dynamic navigation rebuilt controls")
    end
    config.barIds, current, C_Timer = savedIds, previousCurrent, previousTimer
end)()

-- Both direct and section-menu deletion remain scoped; search opens the menu.
;(function()
    for _, useDirect in ipairs({ false, true }) do
    local saved, previous = Suite.CopyValue(S.Config("dataTexts")), current
    assert(S.SetMany("dataTexts", Suite.DataTextBarCreationValues(S.Config("dataTexts"), 42)))
    local ctx = { key = "suite_dataTexts", width = 720, refreshers = {}, widgets = {},
        sections = {}, pageItems = {}, entry = { sections = {} } }
    current = ctx
    M.pages.suite_dataTexts.build(ctx)
    ctx.dataTextWorkspace.choose(42)
    local more = assert(registeredControls["menu2.suite_dataTexts.dataTexts.bar42.remove"], "bar has no delete action")
    local body = assert(ctx.entry.sections.suite_dataTexts_bar42)
    local entry = body._msuf2CollapsibleEntry
    local direct
    for _, button in ipairs(body._testButtons) do
        if button.text == optionsNS.Tr("Remove bar") then direct = button end
    end
    assert(direct and direct:IsVisible(), "additional direct delete button must remain visible")
    assert(more == entry._msuf2SectionActions, "removal search must target the page-owned menu button")
    -- The section menu (a UIParent child) is built when it first opens.
    assert(more._msuf2GetSectionPopup() == nil, "the bar's section menu was built with the page")
    more.scripts.OnClick(more)
    local popup = assert(more._msuf2GetSectionPopup(), "the section menu did not open")
    local remove = assert(popup._testButtons[1], "section menu has no delete button")
    assert(remove.text == optionsNS.Tr("Remove bar"), "section menu action has the wrong label")
    assert(remove:IsVisible(), "section menu did not reveal delete action")
    more.scripts.OnClick(more)
    assert(not remove:IsVisible(), "delete action must live inside the closed section menu")
    more._msuf2PrepareExactSearchTarget()
    assert(remove:IsVisible(), "exact search did not reveal delete action")
    local action = useDirect and direct or remove
    action.scripts.OnClick(action)
    for _, id in ipairs(Suite.DataTextBarIDs(S.Config("dataTexts"))) do assert(id ~= 42, "deleted bar remained in navigation") end
    assert(S.Config("dataTexts").bar1Width == saved.bar1Width, "deleting a bar changed another bar")
    Suite.DB.suite.modules.dataTexts, current = saved, previous
    end
end)()

-- Shell-first runs: a host with b:LazyCollapsibleSection (MSUF Menu2
-- InstallLazySection) whose sections build their content only when
-- W.EnsureSectionContent asks, open or not. Every page first shows each
-- accordion header as the eager build does (switch, "...", its place, the
-- collapsed summary, the title), then, once every section is ensured, holds
-- the same controls, bodies and refreshers. CDM's card stays eager.
;(function()
    local eager, previousEnsure, previous = W.PageBuilder, W.EnsureSectionContent, current
    local pending, lazy
    -- Every section gets a header, so its "..." takes its place there.
    local function Builder(ctx)
        local b = eager(ctx)
        local section = b.CollapsibleSection
        function b:CollapsibleSection(...)
            local body = section(self, ...)
            local entry = body._msuf2CollapsibleEntry
            entry.header = entry.header or Widget("SectionHeader")
            return body
        end
        if not lazy then return b end
        function b:LazyCollapsibleSection(id, title, height, defaultOpen, build, opts)
            opts = opts or {}
            local body = self:CollapsibleSection(id, title, height, defaultOpen)
            local entry = body._msuf2CollapsibleEntry
            if opts.shell then opts.shell(body, entry) end
            local built = false
            entry._msuf2EnsureContent = function()
                if not built then
                    built = true
                    build(body, entry)
                    if opts.onBuilt then opts.onBuilt(body) end
                end
                return true
            end
            if opts.eager then entry._msuf2EnsureContent() else pending[#pending + 1] = entry end
            return body
        end
        return b
    end
    W.EnsureSectionContent = function(section)
        local entry = section and (section._msuf2CollapsibleEntry or section)
        return not (entry and entry._msuf2EnsureContent) or entry._msuf2EnsureContent()
    end
    local function Headers(ctx)
        local parts = {}
        for _, body in ipairs(ctx.sections) do
            local entry = body._msuf2CollapsibleEntry
            -- Fixture widgets answer unknown fields with a function: read raw.
            parts[#parts + 1] = table.concat({ body.sectionId, tostring(rawget(body, "summary")),
                tostring(rawget(body, "headerSwitch") ~= nil),
                tostring(body._msufSuiteSectionReset ~= nil), tostring(entry._msuf2ColorSwatchReserve),
                tostring(entry.label and entry.label.text) }, "|")
        end
        table.sort(parts)
        return table.concat(parts, "\n")
    end
    local function Shape(ctx)
        local parts = { Headers(ctx) }
        for _, widget in ipairs(ctx.widgets) do
            local meta = rawget(widget, "meta") or {}
            parts[#parts + 1] = "w|" .. tostring(meta.controlId or meta.settingKey or rawget(widget, "label")) .. "|"
                .. tostring(rawget(widget, "rowKind"))
        end
        for _, body in ipairs(ctx.sections) do
            parts[#parts + 1] = "b|" .. body.sectionId .. "|" .. tostring(rawget(body, "finished")) .. "|"
                .. tostring(body:GetHeight()) .. "|" .. tostring(rawget(body, "colorShortcut") ~= nil)
        end
        table.sort(parts)
        return table.concat(parts, "\n")
    end
    local function Run(key, lazyHost)
        pending, lazy = {}, lazyHost
        W.PageBuilder = Builder
        local ctx = { key = key, width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
        if key == "suite_qualityOfLife" or key == "suite_dataTexts" then ctx.entry = { sections = {} } end
        current = ctx
        M.pages[key].build(ctx)
        if ctx.fixedPreview and ctx.fixedPreview.record.onActivate then ctx.fixedPreview.record.onActivate() end
        for _, fn in ipairs(ctx.refreshers) do fn() end
        -- A shell is unfinished until its content is built (FinishBody).
        local headers, built = Headers(ctx), 0
        for _, entry in ipairs(pending) do
            if rawget(entry.body, "finished") then built = built + 1 end
        end
        if lazyHost and key == "suite_actionbars" then
            -- The closed card's "..." resets the quick bar switches too.
            local config, rule = S.Config("actionbars"), optionsNS.catalog.actionbars.rules.bar3Visibility
            local saved = config.bar3Visibility
            config.bar3Visibility = rule.default == 1 and 2 or 1
            for _, body in ipairs(ctx.sections) do
                if body.sectionId == "suite_actionbars_actionbars_module" then body._msufSuiteSectionReset() end
            end
            assert(config.bar3Visibility == rule.default, "the closed action bar card lost its quick-switch reset")
            config.bar3Visibility = saved
        end
        local i = 1
        while i <= #pending do
            pending[i]._msuf2EnsureContent()
            i = i + 1
        end
        for _, fn in ipairs(ctx.refreshers) do fn() end
        return ctx, headers, #pending, built
    end
    -- The client as the first page build saw it (later steps narrowed C_CVar).
    local meterLoadError, cvar = S.states.damageMeter.error, C_CVar
    S.states.damageMeter.error, MapkoSkin, C_CVar = nil, skin, { GetCVar = function() return nil end }
    for _, key in ipairs(expected) do
        local eagerCtx, eagerHeaders = Run(key, false)
        local lazyCtx, headers, closed, built = Run(key, true)
        assert(headers == eagerHeaders, key .. ": a section shell lost a header part:\n" .. headers .. "\n--- eager\n" .. eagerHeaders)
        assert(Shape(lazyCtx) == Shape(eagerCtx), key .. ": ensured lazy sections differ from the eager build")
        assert(#lazyCtx.refreshers == #eagerCtx.refreshers, key .. ": lazy sections changed the page refreshers")
        assert(closed > 0 and built == 0, key .. ": a shell-first page built section content")
    end
    S.states.damageMeter.error, MapkoSkin, C_CVar = meterLoadError, nil, cvar
    W.PageBuilder, W.EnsureSectionContent, current = eager, previousEnsure, previous
end)()

print("Suite options menu: navigation, page and section reset, no inline Suite colors, color shortcuts and global Colors, per-bar/window keys, gating and locale isolation passed")
