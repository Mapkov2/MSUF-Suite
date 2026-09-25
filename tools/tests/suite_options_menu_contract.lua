-- Loads MSUF_Suite and MSUF_Suite_Options against a stand-in of Menu2's public
-- surface (the functions both MSUF builds share) and checks navigation
-- placement, page registration, control coverage of every catalog setting,
-- per-bar/per-window key mapping, enable gating and the locale merge.
local root = assert(arg[1], "repository root required")
local function Frame(kind)
    local f = { kind = kind, shown = true, scripts = {}, points = {}, text = "", width = 100, height = 20, enabled = true }
    return setmetatable(f, { __index = function(_, key)
        if type(key) == "string" and key:sub(1, 1) == "_" then return nil end
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
    function w:SetSize(a, b) self.width, self.height = a, b end
    function w:StartMoving() self.moving = true end
    function w:StopMovingOrSizing() self.moving = false end
    function w:EnableKeyboard(v) self.keyboardEnabled = v and true or false end
    function w:SetPropagateKeyboardInput(v) self.propagateKeyboard = v and true or false end
    function w:GetStringHeight() return 14 end
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
    return w
end
CreateFrame = function(kind) return Widget(kind) end

-- WoW client stand-ins
SlashCmdList = {}
IsLoggedIn = function() return false end
InCombatLockdown = function() return false end
LoggingCombat = function() return false end
GetInstanceInfo = function() return "outside", "none", 0 end
GetLocale = function() return "deDE" end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
GameFontHighlightSmall = {}
local loaded = { MidnightSimpleUnitFrames = true, MidnightSimpleUnitFrames_Options = true }
local function LoadTOC(addon, flavor, ns)
    local toc = assert(io.open(root .. "/" .. addon .. "/" .. addon .. "_" .. flavor .. ".toc"))
    for line in toc:lines() do
        line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            assert(loadfile(root .. "/" .. addon .. "/" .. line:gsub("\\", "/")))(addon, ns)
        end
    end
    toc:close()
end
C_AddOns = {
    IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
    DoesAddOnExist = function(name) return name ~= "MapkoSkin" end,
    LoadAddOn = function(name)
        if name == "MSUF_Suite_Options" then loaded[name] = true; LoadTOC(name, "Mainline", {}); return true end
        return false, "MISSING"
    end,
}

-- MSUF host (Main build shape: no MSUF.Client) with its locale table.
local L = setmetatable({ ["Enable module"] = "MSUF-eigene Übersetzung" }, { __index = function(_, k) return k end })
MSUF_NS = { L = L, GetEffectiveLocale = function() return "deDE" end }

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
    { title = "Features", id = "features" }, { key = "gameplay", label = "Gameplay", group = "features" },
    { key = "profiles", label = "Profiles", group = "features" },
}
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
LoadTOC("MSUF_Suite", "Mainline", {})
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

-- Navigation: suite group right before MSUF's Features group, rows in order.
local expected = { "suite_actionbars", "suite_minimap", "suite_damageMeter", "suite_bags", "suite_dataTexts", "suite_qualityOfLife", "suite_hud", "suite_buffReminders", "suite_chat", "suite_cooldownManager", "suite_skin" }
local at
for i, item in ipairs(M.navItems) do if item.id == "suite_modules" then at = i end end
assert(at and M.navItems[at].title == "UI Suite", "suite title row missing")
for offset, key in ipairs(expected) do
    local item = M.navItems[at + offset]
    assert(item and item.key == key and item.group == "suite_modules", "nav row " .. offset .. " is " .. tostring(item and item.key))
end
assert(M.navItems[at + #expected + 1].id == "features", "suite group must sit right before Features")
assert(M.navItems[#M.navItems].key == "profiles", "MSUF profiles row moved")
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
UnitGUID = function() return "Player-Test" end
C_AddOns.GetAddOnEnableState = function(name, guid)
    assert(guid == "Player-Test", "AddOn enable state must use the current character")
    return name == "MSUF_Suite_ActionBars" and 0 or 1
end
assert(rows.suite_actionbars.availability() == false
    and rows.suite_minimap.availability() == true
    and rows.suite_qualityOfLife.availability() == true,
    "Suite navigation does not reflect Blizzard's disabled AddOn state")
C_AddOns.GetAddOnEnableState = nil
assert(M.ALIASES.meter == "opt_bars", "suite overrode an MSUF alias")
assert(M.ALIASES.damage_meter == "suite_damageMeter" and M.ALIASES.minimap == "suite_minimap")
assert(M.ALIASES.chat == "suite_chat", "chat page alias is missing")
-- Attaching twice must not duplicate rows.
Suite.Menu.attached = false
assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Register.lua"))("MSUF_Suite_Options", {
    Suite = Suite, M = M, T = T, pages = {}, Tr = M.Tr, host = MSUF_NS, Refresh = function() end,
})
local count = 0
for _, item in ipairs(M.navItems) do if item.id == "suite_modules" then count = count + 1 end end
assert(count == 1, "suite navigation inserted twice")

-- The suite ships English pages and never writes into MSUF's locale table.
assert(rawget(L, "UI Suite") == nil, "suite wrote a translation into MSUF's locale table")
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
local focusedColor, category
M.ColorsSetPainterCategory = function(key) category = key end
M.cache = { opt_colors = { sections = {
    colors_suite_objectives = { name = "objectives" },
    colors_suite_announcements = { name = "announcements" },
} } }
W.FocusCollapsibleSection = function(section) focusedColor = section.name end
for _, id in ipairs({ "objectives", "announcements" }) do
    local button = registeredControls["menu2.suite_hud." .. id .. ".action.colors"]
    assert(button and button.scripts.OnClick, id .. " has no link to Colors")
    button.scripts.OnClick()
    assert(M.selectedPage == "opt_colors" and category == "suite" and focusedColor == id,
        id .. " color link did not open its own Colors section")
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
local secureRef = SecureHandlerSetFrameRef
SecureHandlerSetFrameRef = nil
current = contexts.suite_actionbars
M.RequestRefresh()
assert(S.Availability("actionbars") == false and actionBarsHeader.enabled,
    "unavailable action bars locked their module switch")
actionBarsHeader.set(false)
actionBarsHeader.set(true)
assert(S.Config("actionbars").enabled and not S.states.actionbars.active,
    "unavailable action bars started or failed to save their enabled preference")
actionBarsHeader.set(false)
SecureHandlerSetFrameRef = secureRef
M.RequestRefresh()
local qolHeader = contexts.suite_qualityOfLife.sections[3].headerSwitch
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
C_AddOns.GetAddOnEnableState = nil
M.RequestRefresh()
assert(contexts.suite_minimap.pageItems[1] == "fixed-preview"
    and contexts.suite_minimap.pageItems[2] == "suite_minimap_minimap_module"
    and contexts.suite_minimap.fixedPreview.section.expander.expanded,
    "minimap preview must stay fixed above Frame Basics")
assert(contexts.suite_minimap.sections[1].title == "Frame Basics"
    and contexts.suite_minimap.sections[1].headerSwitch,
    "minimap enable switch is not in the Frame Basics header")
local dataPage = contexts.suite_dataTexts
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
local qolPage = contexts.suite_qualityOfLife
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
local qolGroups = { "xpBar_xp_bar", "skyriding_flight_hud", "qol_repair", "qol_junk", "quests_automation", "loot_collection",
    "loot_history", "combatLog_log_dungeons" }
assert(#qolPage.sections == #qolGroups, "Quality of Life retained Module Basics or nested accordions")
for i, name in ipairs(qolGroups) do
    local section = qolPage.sections[i]
    assert(section.sectionId == "suite_qualityOfLife_" .. name and section.headerSwitch,
        "Quality of Life feature has no independent header switch: " .. name)
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
assert(routed == 12, "Quality of Life settings lost their search routes")
local xpBar = qolPage.sections[1].headerSwitch
xpBar.set(true)
assert(xpBar.get() and S.Config("xpBar").enabled, "XP bar header switch did not enable its module")
xpBar.set(false)
assert(not xpBar.get(), "XP bar header switch did not disable its module")
local skyride = qolPage.sections[2].headerSwitch
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
for _, target in ipairs(qolPage.sections[2].colorShortcut.options.getTargets()) do
    if target.settingKey == "msufsuite.skyriding.panelColor" then skyPanelColor = target; break end
end
assert(skyPanelColor, "Skyriding panel color is missing from its three-dot picker")
assert(skyControls.font.row.values()[1].text == "MSUF Expressway (default)",
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
local repair, junk = qolPage.sections[3].headerSwitch, qolPage.sections[4].headerSwitch
repair.set(true)
assert(repair.get() and S.Config("qol").enabled and S.Config("qol").repair)
junk.set(true)
repair.set(false)
assert(not repair.get() and junk.get() and S.Config("qol").enabled,
    "turning off repair disabled active junk selling")
junk.set(false)
assert(not S.Config("qol").enabled, "inactive merchant helpers retained their runtime gate")
local collect, history = qolPage.sections[6].headerSwitch, qolPage.sections[7].headerSwitch
collect.set(true)
history.set(true)
collect.set(false)
assert(not collect.get() and history.get() and S.Config("loot").enabled,
    "turning off collection disabled active loot history")
history.set(false)
assert(not S.Config("loot").enabled, "inactive loot helpers retained their runtime gate")
local quests, combatLog = qolPage.sections[5].headerSwitch, qolPage.sections[8].headerSwitch
quests.set(true)
combatLog.set(true)
assert(quests.get() and combatLog.get() and S.Config("quests").enabled
    and S.Config("combatLog").enabled, "quest or combat logging header switch did not enable its module")
quests.set(false)
combatLog.set(false)
assert(not quests.get() and not combatLog.get(), "quest or combat logging header switch did not disable its module")
local colorContext = { key = "opt_colors", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
current = colorContext
Suite.Options.BuildColorsCategory(colorContext, W.PageBuilder(colorContext))
local colorSections = {}
for _, section in ipairs(colorContext.sections) do colorSections[section.sectionId] = true end
assert(colorSections.colors_suite_minimap and colorSections.colors_suite_actionbars
    and colorSections.colors_suite_damageMeter and colorSections.colors_suite_buffReminders
    and colorSections.colors_suite_chat and colorSections.colors_suite_dataTexts
    and colorSections.colors_suite_objectives and colorSections.colors_suite_announcements,
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
local skin = { addonName = "MSUF_Suite_Skin", L = setmetatable({}, { __index = function(_, key) return key end }) }
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
assert(skinContext.sections[3].sectionId == "suite_skin_micro"
    and skinContext.sections[4].sectionId == "suite_skin_micro_details"
    and skinContext.sections[5].sectionId == "suite_skin_hud",
    "Micro Bar and tracker setup must be immediately visible after the main look")
local skinControls = {}
for _, widget in ipairs(skinContext.widgets) do
    if widget.meta and widget.meta.settingKey then skinControls[widget.meta.settingKey] = widget end
end
assert(skinControls["msufsuite.skin.theme.look"] and skinControls["msufsuite.skin.theme.shellOpacity"]
    and skinControls["msufsuite.skin.icons.windowActions.style"]
    and skinControls["msufsuite.skin.icons.microMenu.layoutMode"]
    and skinControls["msufsuite.skin.enabled"], "native Skinning controls missing")
assert(skinControls["msufsuite.skin.icons.microMenu.preset"]
    and skinControls["msufsuite.skin.hud.objectiveTrackerStyle"],
    "authored Micro Bar and tracker controls missing")
local microPreset = skinControls["msufsuite.skin.icons.microMenu.preset"]
local blizzardChoice = false
for _, entry in ipairs(microPreset.row.values) do
    if entry.value == "blizzard" and entry.text == "Blizzard original" then
        blizzardChoice = true
    end
end
assert(blizzardChoice, "Skinning menu did not offer the original Blizzard Micro Bar")
microPreset.set("blizzard")
assert(skin.DB.icons.microMenu.layoutMode == "blizzard"
    and skin.DB.icons.microMenu.iconStyle == "blizzard",
    "Blizzard menu preset did not select Blizzard layout and icons")
microPreset.set("modern")
assert(skin.DB.icons.microMenu.layoutMode == "owned",
    "Suite menu preset did not restore its movable layout")
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
local skinPaletteSection
for _, section in ipairs(skinContext.sections) do
    if section.sectionId == "suite_skin_colors" then skinPaletteSection = section; break end
end
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
local checked = 0
for _, id in ipairs(Suite.SuiteOrder) do
    for key, rule in pairs(Suite.SuiteCatalog[id].rules) do
        local template = key:gsub("^bar%d+", "bar1"):gsub("^w%d+", "w1")
        if id == "cooldownManager" and rule.suffix then template = "c1_" .. rule.suffix end
        if not rule.hidden and not rule.previewOnly then
            assert(covered["msufsuite." .. id .. "." .. template], "no menu control for " .. id .. "." .. key)
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
    compass = "behavior", tracking = "elements", battlefield = "elements", queue = "elements", worldMap = "elements",
    calendar = "elements", mail = "elements", crafting = "elements", difficulty = "elements",
    compartment = "elements", drawer = "addons", infoFPS = "info_fps",
    infoLatency = "info_latency", infoCoordinates = "info_coordinates",
    infoDurability = "info_durability", infoLocation = "info_location",
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
IsShiftKeyDown = nil
assert(S.Config("minimap").infoLocationY == arrowY + 5 and selectionBox.selectionY == arrowY + 5,
    "Shift+Up did not move the selected preview element by five")
IsControlKeyDown = function() return true end
arrowBinding.spec.onClick(selectionBox, -1, 0)
IsControlKeyDown = nil
assert(S.Config("minimap").infoLocationX == arrowX - 10,
    "Ctrl+Left secure preview binding did not move the selected element by ten")
GetCurrentKeyBoardFocus = function() return { IsObjectType = function(_, kind) return kind == "EditBox" end } end
selectionBox.scripts.OnKeyDown(selectionBox, "RIGHT")
GetCurrentKeyBoardFocus = nil
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
GameTooltip = nil
GetZoneText = nil
for _, id in ipairs({ "minimap", "actionbars", "damageMeter", "bags", "dataTexts", "xpBar", "skyriding", "chat" }) do
    S.Config(id).enabled = true
end
local beforeStyle = historyProvider.capture()
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

print("Suite options menu: navigation, no inline Suite colors, complete section shortcuts and global Colors, per-bar/window keys, gating and locale isolation passed")
