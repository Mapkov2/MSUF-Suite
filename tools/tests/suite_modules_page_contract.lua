-- Suite Modules page, navigation availability, the dashboard overview API and
-- the first-run order. Loads MSUF_Suite and MSUF_Suite_Options against a
-- stand-in of Menu2's public surface (the one suite_options_menu_contract
-- uses) and checks:
--   * the page sits in General before Quality of Life, has no Reset page,
--     lists every catalog module once in its sidebar group, switches through
--     the module setter (one history entry), opens module pages, retries a
--     failed module and runs the presets and the installer;
--   * nav availability returns ok, reason, hide; hide only while nothing is
--     installed;
--   * MSUFSuite.GetOverview();
--   * the installer waits at login while MSUF's own welcome is due, and
--     /msuite opens Suite Modules.
local root = assert(arg[1], "repository root required")
securecallfunction = function(callback, ...) return callback(...) end

local function Frame(kind)
    local f = { kind = kind, shown = true, scripts = {}, points = {}, text = "", width = 100, height = 20, enabled = true }
    return setmetatable(f, { __index = function(_, key)
        if key == "mirror" or type(key) == "string" and key:sub(1, 1) == "_" then return nil end
        return function() end
    end })
end
local fonts = {}
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
    function w:ClearAllPoints() self.points = {} end
    function w:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function w:GetStringHeight() return 14 end
    function w:GetStringWidth() return 0 end
    function w:GetEffectiveScale() return 1 end
    function w:GetFrameLevel() return rawget(self, "level") or 1 end
    function w:SetFrameLevel(value) self.level = value end
    function w:SetScript(name, fn) self.scripts[name] = fn end
    function w:GetScript(name) return self.scripts[name] end
    function w:SetEnabled(v) self.enabled = v and true or false end
    function w:SetAlpha(v) self.alpha = v end
    function w:SetValue(v) self.value = v end
    function w:CreateTexture() return Widget("Texture") end
    function w:CreateFontString()
        local fs = Widget("FontString")
        fs.parent = self
        return fs
    end
    function w:CreateMaskTexture() return Widget("MaskTexture") end
    function w:CreateLine() return Widget("Line") end
    return w
end
CreateFrame = function(kind, name, parent, template)
    local widget = Widget(kind)
    widget.parent = parent
    if template == "OptionsSliderTemplate" then widget.Low, widget.High, widget.Text = Widget("F"), Widget("F"), Widget("F") end
    if name then _G[name] = widget end
    return widget
end

GameTooltip = setmetatable({}, { __index = function() return function() end end })
EditModeManagerFrame = { CanEnterEditMode = function() return false end }
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
local loggedIn, combat = false, false
IsLoggedIn = function() return loggedIn end
InCombatLockdown = function() return combat end
LoggingCombat = function() return false end
GetInstanceInfo = function() return "outside", "none", 0 end
GetLocale = function() return "enUS" end
C_SpecializationInfo = { GetSpecialization = function() return nil end }
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
GameFontHighlightSmall = {}
UIParent = Widget("UIParent")
ReloadUI = function() end
YES, NO = "Yes", "No"
C_CVar = { GetCVar = function() return nil end }
SecureHandlerExecute, SecureHandlerSetFrameRef, RegisterStateDriver = function() end, function() end, function() end
C_DamageMeter = { GetCombatSessionFromType = function() end }
Enum = { DamageMeterType = { DamageDone = 0 } }
Minimap = { SetMaskTexture = function() end }

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
-- AddOns a step marks missing do not exist; disabled ones exist but are off.
local missing, disabled, metadataReads = { MapkoSkin = true }, {}, 0
UnitGUID = function() return "Player-Test" end
C_AddOns = {
    IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
    DoesAddOnExist = function(name) return not missing[name] end,
    GetAddOnEnableState = function(name) return disabled[name] and 0 or 2 end,
    GetAddOnMetadata = function(name, field)
        metadataReads = metadataReads + 1
        return name == "MSUF_Suite" and field == "Version" and "1.0-test" or nil
    end,
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

-- Main MSUF host shape (no MSUF.Client); the locale table returns English.
local L = setmetatable({}, { __index = function(_, k) return k end })
MSUF_NS = { L = L, GetEffectiveLocale = function() return "enUS" end }
assert(loadfile(root .. "/../MidnightSimpleUnitFrames-Classic/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_BossTargetIndicator.lua"))("MidnightSimpleUnitFrames", MSUF_NS)

-- Menu2 public surface
local M, W, T = {}, {}, {}
MSUF2 = M
local historyWrites, opened = 0, {}
MSUF2_Open = function(page) opened[#opened + 1] = page end
M.RegisterHistoryProvider = function() return true end
M.RunWithHistory = function(_, _, fn) historyWrites = historyWrites + 1; return fn() end
M.Widgets, M.Theme = W, T
M.pages = {}
M.Tr = function(text) return L[text] end
T.colors = { muted = {}, text = {}, dim = {} }
T.navIconGrid = { home = { 0, 0 }, gameplay = { 7, 1 } }
T.navIconColors = { home = { 1 }, gameplay = { 2 }, profiles = { 3 } }
T.Font = function(parent, _, text)
    local fs = Widget("FontString")
    fs.text, fs.parent = text, parent
    fonts[#fonts + 1] = fs
    return fs
end
T.Button = function(_, text) local b = Widget("Button"); b.text = text; return b end
T.Panel = function() return Widget("Panel") end
M.navItems = {
    { key = "home", label = "Dashboard" },
    { title = "Frames", id = "frames" }, { key = "uf_player", label = "Unitframes", group = "frames" },
    { title = "Combat", id = "combat" }, { title = "Interface", id = "interface" },
    { title = "Style", id = "style" }, { key = "opt_colors", label = "Colors", group = "style" },
    { title = "General", id = "general" }, { key = "gameplay", label = "Gameplay", group = "general" },
    { key = "opt_misc", label = "Miscellaneous", group = "general" },
    { key = "profiles", label = "Profiles", group = "general" },
}
M.navPrimaryForKey = { home = "home" }
M.ALIASES = {}
M.RegisterPage = function(key, spec) M.pages[key] = spec end
M.ControlMeta = function(page, _, path, classification, exact)
    local meta = { controlId = "menu2." .. page .. "." .. path, classification = classification }
    for k, v in pairs(exact or {}) do meta[k] = v end
    return meta
end
local controls = {}
M.RegisterControlMetadata = function(widget, meta) if meta and meta.controlId then controls[meta.controlId] = widget end end
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
M.BindBoolWidget = function(ctx, widget, get, set, meta) return Bind(ctx, widget, get, set, meta, widget.label) end
M.BindTextInputAt = function(ctx, _, label, _, _, _, get, set, _, meta) return Bind(ctx, Widget("EditBox"), get, set, meta, label) end
W.SectionSwitch = function(section, label) local s = Widget("Switch"); s.label = label; section.headerSwitch = s; return s end
W.SetControlEnabled = function(widget, enabled) widget.enabled = enabled and true or false end
W.SettingsRows = function(ctx, parent, spec)
    local list, y = {}, spec.y
    for _, row in ipairs(spec.rows) do
        local widget = Bind(ctx, Widget(row.kind), row.get, row.set, row, row.label)
        widget.parent = parent
        list[row.id] = widget
        y = y - 40
    end
    return { controls = list, bottomY = y }
end
W.PageBuilder = function(ctx)
    local b = { width = ctx.width }
    function b:Header() ctx.headers = (ctx.headers or 0) + 1 end
    function b:CollapsibleSection(id, title, _, open)
        local body = Widget("Section")
        body.sectionId, body.title, body.open = id, title, open
        body._msuf2Width = ctx.width
        body._msuf2CollapsibleEntry = {}
        ctx.sections[#ctx.sections + 1] = body
        return body
    end
    function b:FinishSection(body) body.finished = true end
    return b
end

-- Boot the core as the client would, then attach the menu.
LoadTOC("MSUF_Suite", {})
local Suite = assert(MSUFSuite)
local S = Suite.Suite
Suite.Database.Initialize(nil)
S.Start()
assert(Suite.Menu.Attach() and Suite.Menu.attached == true, "suite menu did not attach")
local P = assert(optionsNS)

------------------------------------------------------------------ navigation
local function NavShape()
    local out = {}
    for _, item in ipairs(M.navItems) do
        out[#out + 1] = item.key and (item.key .. "@" .. tostring(item.group)) or ("#" .. tostring(item.id))
    end
    return table.concat(out, " ")
end
assert(NavShape():find("#general gameplay@general suite_modules@general suite_qualityOfLife@general opt_misc@general", 1, true),
    "Suite Modules must open General, ahead of Quality of Life: " .. NavShape())
local rows = {}
for _, item in ipairs(M.navItems) do if item.key then rows[item.key] = item end end
assert(rows.suite_modules.availability == nil, "Suite Modules is always available")
assert(M.pages.suite_modules and M.pages.suite_modules.title == "Suite Modules", "page not registered")
assert(T.navIconGrid.suite_modules[1] == 4 and T.navIconGrid.suite_modules[2] == 2
    and T.navIconColors.suite_modules == T.navIconColors.home, "Suite Modules has no accent icon")
for _, alias in ipairs({ "modules", "suite", "suite modules", "module overview", "suite_modules" }) do
    assert(M.ALIASES[alias] == "suite_modules", "missing alias " .. alias)
end
assert(P.navGroupTitles.general == "General" and P.navGroupTitles.style == "Style",
    "the page does not know the sidebar's group titles")

-- Reset page: every Suite page but the overview.
assert(M.PageHasReset("suite_modules") == false, "Suite Modules offers a page reset")
assert(M.PageHasReset("suite_bags") == true and M.PageHasReset("suite_skin") == true, "module pages lost Reset page")
local writes = historyWrites
assert(M.ResetPageToDefaults("suite_modules") == false and M.ShowPageResetConfirm("suite_modules") == false
    and historyWrites == writes, "Suite Modules ran a page reset")

------------------------------------------------------------------ availability: ok, reason, hide
do
    local ok, reason, hide = Suite.Client.AddOnEnabled("MSUF_Suite_Bags")
    assert(ok == true and reason == nil and hide == nil)
    disabled.MSUF_Suite_Bags = true
    ok, reason, hide = rows.suite_bags.availability()
    assert(ok == false and reason == "Disabled in Blizzard's AddOns list: MSUF_Suite_Bags" and not hide,
        "a disabled AddOn must stay listed with its reason")
    assert(select(3, Suite.Client.AddOnEnabled("MSUF_Suite_Bags")) == nil, "a disabled AddOn reported missing")
    missing.MSUF_Suite_Bags = true
    ok, reason, hide = rows.suite_bags.availability()
    assert(ok == false and reason == "Install MSUF_Suite_Bags to use this module" and hide == true,
        "an AddOn that is not installed must hide its page")
    missing.MSUF_Suite_Bags, disabled.MSUF_Suite_Bags = nil, nil
    assert(rows.suite_bags.availability() == true)
    -- Pages of several modules: hidden only when none is installed.
    missing.MSUF_Suite_QualityOfLife = true
    ok, reason, hide = rows.suite_qualityOfLife.availability()
    assert(ok == false and hide == true and reason == "Install MSUF_Suite_QualityOfLife to use this module")
    missing.MSUF_Suite_QualityOfLife, disabled.MSUF_Suite_QualityOfLife = nil, true
    ok, reason, hide = rows.suite_qualityOfLife.availability()
    assert(ok == false and not hide and reason:find("Disabled in Blizzard's AddOns list", 1, true))
    disabled.MSUF_Suite_QualityOfLife = nil
    missing.MSUF_Suite_Modules = true
    assert(select(3, rows.suite_hud.availability()) == true, "HUD without its AddOn must hide")
    missing.MSUF_Suite_Modules = nil
    missing.MSUF_Suite_Skin = true
    ok, reason, hide = rows.suite_skin.availability()
    assert(ok == false and hide == true, "Skinning without its AddOn must hide")
    missing.MSUF_Suite_Skin, disabled.MSUF_Suite_Skin = nil, true
    ok, reason, hide = rows.suite_skin.availability()
    assert(ok == false and not hide and reason == "Disabled in Blizzard's AddOns list: MSUF_Suite_Skin")
    disabled.MSUF_Suite_Skin = nil
end

------------------------------------------------------------------ the page
missing.MSUF_Suite_Chat = true -- a module whose AddOn is not installed
for _, id in ipairs(S.order) do S.states[id].error = nil end
local ctx = { key = "suite_modules", width = 720, refreshers = {}, widgets = {}, sections = {} }
current = ctx
M.pages.suite_modules.build(ctx)
M.RequestRefresh()
assert(not ctx.headers, "the page has a redundant header")
local order = {}
for _, section in ipairs(ctx.sections) do
    assert(section.finished and section.open, "section not finished or closed: " .. section.sectionId)
    order[#order + 1] = section.sectionId .. "=" .. section.title
end
assert(table.concat(order, " ") == "suite_modules_overview=Overview suite_modules_combat=Combat"
    .. " suite_modules_interface=Interface suite_modules_style=Style suite_modules_general=General",
    "sections do not follow the sidebar: " .. table.concat(order, " "))

local GROUP_OF_PAGE = {
    suite_nameplates = "combat", suite_cooldownManager = "combat", suite_buffReminders = "combat", suite_hud = "combat",
    suite_actionbars = "interface", suite_minimap = "interface", suite_damageMeter = "interface",
    suite_bags = "interface", suite_chat = "interface", suite_dataTexts = "interface",
    suite_qualityOfLife = "general",
}
local switches, switchOrder = {}, {}
for _, widget in ipairs(ctx.widgets) do
    local id = widget.meta and widget.meta.controlId and widget.meta.controlId:match("^menu2%.suite_modules%.([%w]+)%.enabled$")
    if id then
        assert(not switches[id], "module listed twice: " .. id)
        switches[id] = widget
        switchOrder[widget.meta.sectionId] = (switchOrder[widget.meta.sectionId] or "") .. id .. " "
    end
end
local function Texts(sectionId)
    local out = {}
    for _, fs in ipairs(fonts) do
        if fs.parent and fs.parent.sectionId == sectionId then out[fs.text] = (out[fs.text] or 0) + 1 end
    end
    return out
end
for _, id in ipairs(S.order) do
    local spec = S.catalog[id]
    local sectionId = "suite_modules_" .. assert(GROUP_OF_PAGE[spec.page], "no group for " .. id)
    if id == "chat" then
        assert(not switches.chat and not controls["menu2.suite_modules.chat.open"],
            "a module that is not installed must show its status only")
        local texts = Texts(sectionId)
        assert(texts.Chat and texts["Install MSUF_Suite_Chat to use this module"],
            "a module that is not installed lost its name or status")
    else
        local switch = assert(switches[id], "module has no switch on Suite Modules: " .. id)
        assert(switch.meta.sectionId == sectionId and switch.meta.settingKey == "msufsuite." .. id .. ".enabled"
            and switch.meta.kind == "toggle" and switch.label == spec.title,
            "module switch in the wrong group or with the wrong identity: " .. id)
        assert(Texts(sectionId)[spec.description], "module description missing: " .. id)
        assert(controls["menu2.suite_modules." .. id .. ".open"], "module has no page button: " .. id)
    end
end
assert(switchOrder.suite_modules_combat
    == "nameplates cooldownManager buffReminders objectives announcements afkScreen ",
    "Combat does not follow the sidebar: " .. tostring(switchOrder.suite_modules_combat))
assert(switches.skin and switches.skin.meta.sectionId == "suite_modules_style"
    and Texts("suite_modules_style").Off, "Skinning row missing from Style")

-- The switch is the module's own setter: one history entry per change.
writes = historyWrites
switches.minimap.set(false)
assert(S.Config("minimap").enabled == false and historyWrites == writes + 1 and not switches.minimap.get())
switches.minimap.set(true)
assert(S.Config("minimap").enabled == true and historyWrites == writes + 2 and switches.minimap.get())
assert(switches.minimap.enabled, "switch locked outside combat")
combat = true
M.RequestRefresh()
assert(not switches.minimap.enabled, "switch editable in combat")
combat = false
M.RequestRefresh()

-- Page buttons open the module's page.
controls["menu2.suite_modules.bags.open"].scripts.OnClick()
assert(M.selectedPage == "suite_bags")
controls["menu2.suite_modules.quests.open"].scripts.OnClick()
assert(M.selectedPage == "suite_qualityOfLife")
controls["menu2.suite_modules.skin.open"].scripts.OnClick()
assert(M.selectedPage == "suite_skin")

-- Retry: shown only after an error; clears it and applies the module again.
-- (This fixture cannot load module AddOns, so enabling one above failed it.)
for _, id in ipairs(S.order) do S.states[id].error = nil end
M.RequestRefresh()
local retry = assert(controls["menu2.suite_modules.minimap.retry"])
assert(not retry.shown and not controls["menu2.suite_modules.bags.retry"].shown)
S.states.minimap.error = "Stopped after an error"
M.RequestRefresh()
assert(retry.shown and retry.enabled and Texts("suite_modules_interface")["Stopped after an error"],
    "a failed module shows no status or Retry")
local apply, applied = S.Apply, {}
S.Apply = function(id) applied[#applied + 1] = { id, S.states[id].error } end
combat = true
retry.scripts.OnClick()
assert(#applied == 0 and S.states.minimap.error, "Retry ran in combat")
combat = false
retry.scripts.OnClick()
S.Apply = apply
assert(#applied == 1 and applied[1][1] == "minimap" and applied[1][2] == nil and S.states.minimap.error == nil,
    "Retry must clear the error before applying the module again")
assert(not retry.shown, "Retry stayed after the error cleared")

-- Presets: confirmation first, one history entry, refused in combat.
local dialogs, shown = {}, nil
M.InstallStaticPopup = function(key, spec) dialogs[key] = dialogs[key] or spec; return dialogs[key] end
StaticPopup_Show = function(key, text, _, data) shown = { key = key, text = text, data = data } end
local turnOff = assert(controls["menu2.suite_modules.suite.preset.off"])
local coreOn = assert(controls["menu2.suite_modules.suite.preset.core"])
combat = true
turnOff.scripts.OnClick()
assert(shown == nil, "a preset asked for confirmation in combat")
combat = false
S.Config("qol").enabled = true
writes = historyWrites
turnOff.scripts.OnClick()
assert(shown and shown.data.kind == "off" and S.Config("minimap").enabled and historyWrites == writes,
    "Turn all off changed modules before the confirmation")
assert(shown.text == "Turn off every Suite module? Their settings stay saved. Skinning keeps its own switch.")
dialogs[shown.key].OnAccept(nil, shown.data)
local anyOn = false
for _, id in ipairs(S.order) do anyOn = anyOn or S.Config(id).enabled end
assert(not anyOn and historyWrites == writes + 1, "Turn all off must be one history entry that disables every module")
assert(Texts("suite_modules_overview")["0 of " .. #S.order .. " Suite modules are on"], "overview count not refreshed")
shown = nil
coreOn.scripts.OnClick()
assert(shown and shown.data.kind == "core")
dialogs[shown.key].OnAccept(nil, shown.data)
assert(S.Config("minimap").enabled and S.Config("objectives").enabled and not S.Config("qol").enabled
    and historyWrites == writes + 2, "core preset must enable core modules and leave opt-in modules alone")
-- A confirmation accepted after combat started changes nothing.
shown = nil
turnOff.scripts.OnClick()
combat, writes = true, historyWrites
dialogs[shown.key].OnAccept(nil, shown.data)
combat = false
assert(historyWrites == writes and S.Config("minimap").enabled, "a preset ran in combat")

-- Run setup again opens the installer and steps the menu aside.
local installerOpen, setupRuns = Suite.Installer.Open, 0
Suite.Installer.Open = function() setupRuns = setupRuns + 1; return true end
M.frame = Widget("Menu")
controls["menu2.suite_modules.suite.setup"].scripts.OnClick()
assert(setupRuns == 1 and not M.frame.shown, "Run setup again did not open the installer")
Suite.Installer.Open, M.frame = installerOpen, nil
missing.MSUF_Suite_Chat = nil

------------------------------------------------------------------ overview API
do
    local count = 0
    for _, id in ipairs(S.order) do if S.Config(id).enabled then count = count + 1 end end
    Suite.RootDB.installation = nil
    local first = assert(Suite.GetOverview())
    assert(first.version == "1.0-test" and first.total == #S.order and first.enabled == count
        and first.pageKey == "suite_modules" and first.needsSetup == true, "overview fields")
    combat = true
    local second = assert(Suite.GetOverview(), "overview refused in combat")
    combat = false
    assert(second ~= first and metadataReads == 1, "overview must return a new table and read the version once")
    Suite.RootDB.installation = { revision = 2, status = "skipped" }
    assert(Suite.GetOverview().needsSetup == true, "a skipped setup still needs setup")
    Suite.RootDB.installation = { revision = 2, status = "complete", profile = "suite" }
    assert(Suite.GetOverview().needsSetup == false, "a completed setup needs none")
    Suite.Menu.attached = false
    assert(Suite.GetOverview().pageKey == nil, "pageKey without registered pages")
    Suite.Menu.attached = true
    Suite.startupError = "boom"
    assert(Suite.GetOverview() == nil, "a failed start must return nil")
    Suite.startupError = nil
    S.started = false
    assert(Suite.GetOverview() == nil, "an unstarted Suite must return nil")
    S.started = true
end

------------------------------------------------------------------ /msuite and S.Open
opened = {}
SlashCmdList.MSUFSUITE("")
S.Open("bags")
assert(Suite.Menu.Open())
assert(opened[1] == "suite_modules" and opened[2] == "suite_bags" and opened[3] == "suite_modules",
    "/msuite must open Suite Modules: " .. table.concat(opened, ","))

------------------------------------------------------------------ first-run order
do
    local startup = assert(io.open(root .. "/MSUF_Suite/Core/Startup.lua", "rb")):read("*a")
    local _, direct = startup:gsub('Installer%.MaybeShow%("login"%)', "")
    local _, stepped = startup:gsub('Step%(Suite%.Installer, "MaybeShow", "login"%)', "")
    local _, bare = startup:gsub("MaybeShow%(%)", "")
    assert(direct == 1 and stepped == 1 and bare == 0, "startup must ask the installer as a login")
    loggedIn = true
    Suite.freshInstall, Suite.RootDB.installation = true, nil
    Suite.Host.build = "Classic"
    local due, asked = true, 0
    MSUF_NS.FirstLoad6 = { IsFirstRunPending = function(self)
        assert(self == MSUF_NS.FirstLoad6)
        asked = asked + 1
        return due
    end }
    assert(Suite.Installer.MaybeShow("login") == false and MSUFSuiteInstallFrame == nil and asked == 1,
        "the installer opened while MSUF's own first run is pending")
    -- The host calls MaybeShow() when its first run resolves; it never asks.
    assert(Suite.Installer.MaybeShow() == true and MSUFSuiteInstallFrame.shown and asked == 1,
        "the host hook did not open the installer")
    local window = MSUFSuiteInstallFrame
    assert(window:GetFrameLevel() > 400, "the installer opens under MSUF's menu and its popups")
    assert(Suite.Installer.MaybeShow() == false, "MaybeShow opened a second time while shown")
    assert(not window.openModules.shown and not window.modulesHint.shown, "Complete-page controls shown too early")
    assert(window.openModules.caption.text == "Open Suite Modules")
    opened = {}
    window.openModules.scripts.OnClick(window.openModules)
    assert(opened[1] == "suite_modules" and not window.shown, "Open Suite Modules did not open the page")
    due = false
    assert(Suite.Installer.MaybeShow("login") == true, "a completed MSUF welcome must not hold the installer")
    window:Hide()
    due = true
    Suite.Host.build = "Main"
    assert(Suite.Installer.MaybeShow("login") == true, "Main MSUF must keep today's login behavior")
    window:Hide()
    Suite.Host.build = "Classic"
    MSUF_NS.FirstLoad6 = nil
    assert(Suite.Installer.MaybeShow("login") == true, "a host without first-load state keeps today's behavior")
    window:Hide()
    Suite.RootDB.installation = { revision = 2, status = "skipped" }
    assert(Suite.Installer.MaybeShow() == false, "a recorded setup must not reopen the installer")
end

print("Suite Modules: page, availability contract, overview API and first-run order passed")
