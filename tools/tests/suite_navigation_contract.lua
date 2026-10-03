-- Suite navigation availability, dashboard overview, first-run order and
-- /msuite routing after the redundant Suite Modules page was removed.
local root = assert(arg[1], "repository root required")
securecallfunction = function(callback, ...) return callback(...) end

local function Frame(kind)
    local f = { kind = kind, shown = true, scripts = {}, points = {}, text = "", width = 100, height = 20, enabled = true }
    return setmetatable(f, { __index = function(_, key)
        if key == "mirror" or type(key) == "string" and key:sub(1, 1) == "_" then return nil end
        return function() end
    end })
end
local fonts, buttons = {}, {}
local function Widget(kind)
    local w = Frame(kind)
    function w:SetShown(v) self.shown = v and true or false end
    function w:Show() self.shown = true end
    function w:Hide()
        local shown = self.shown
        self.shown = false
        if shown and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function w:IsShown() return self.shown end
    function w:SetText(t) self.text = t end
    function w:GetText() return self.text end
    function w:SetWidth(v) self.width = v end
    function w:GetWidth() return self.width end
    function w:SetHeight(v) self.height = v end
    function w:GetHeight() return self.height end
    function w:SetScrollChild(child) self.child = child end
    function w:GetScrollChild() return self.child end
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
UnitAffectingCombat = function() return combat end
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
T.Button = function(parent, text)
    local b = Widget("Button")
    b.text, b.label, b.parent = text, text, parent
    buttons[#buttons + 1] = b
    return b
end
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
assert(NavShape():find("#general gameplay@general suite_qualityOfLife@general opt_misc@general", 1, true),
    "Quality of Life is missing from General: " .. NavShape())
local rows = {}
for _, item in ipairs(M.navItems) do if item.key then rows[item.key] = item end end
assert(rows.suite_modules == nil and M.pages.suite_modules == nil and M.ALIASES.suite_modules == nil,
    "the removed Suite Modules page is still reachable")
assert(M.PageHasReset("suite_bags") == true and M.PageHasReset("suite_skin") == true,
    "module pages lost Reset page")

------------------------------------------------------------------ availability and unavailable pages
do
    local notice = "You need to turn on the module in Blizzard's AddOn list"
    local addonForPage = {
        suite_bags = "MSUF_Suite_Bags", suite_qualityOfLife = "MSUF_Suite_QualityOfLife",
        suite_hud = "MSUF_Suite_Modules", suite_skin = "MSUF_Suite_Skin",
        suite_nameplates = "MSUF_Suite_Nameplates", suite_minimap = "MSUF_Suite_Minimap",
        suite_actionbars = "MSUF_Suite_ActionBars", suite_chat = "MSUF_Suite_Chat",
        suite_dataTexts = "MSUF_Suite_DataTexts", suite_damageMeter = "MSUF_Suite_DamageMeter",
        suite_cooldownManager = "MSUF_Suite_CooldownManager", suite_buffReminders = "MSUF_Suite_BuffReminders",
    }
    for key, addon in pairs(addonForPage) do
        for _, state in ipairs({ disabled, missing }) do
            state[addon] = true
            local ok, reason, hide = rows[key].availability()
            assert(ok == false and reason == notice and not hide, key .. ": unavailable row must stay grey and clickable")
            local before, buttonsBefore = #fonts, #buttons
            local ctx = { key = key, width = 720, wrapper = Widget("Page"), refreshers = {}, widgets = {}, sections = {} }
            function ctx:SetContentHeight(value) self.height = value end
            M.pages[key].build(ctx)
            -- Skinning keeps its two maintenance actions under the notice:
            -- "Save setup as..." and "Restore chat colors" need no Skin addon.
            local actions = key == "suite_skin" and 2 or 0
            assert(ctx.height == (actions > 0 and 122 or 62), key .. ": notice has no content height: "
                .. tostring(ctx.height))
            assert(fonts[before + 1] and fonts[before + 1].text == notice and fonts[before + 1].parent == ctx.wrapper,
                key .. ": unavailable page must show the AddOn notice first")
            assert(#buttons - buttonsBefore == actions, key .. ": unavailable page shows the wrong actions")
            for index = buttonsBefore + 1, #buttons do
                assert(buttons[index].parent == ctx.wrapper and (buttons[index].label == "Save setup as\226\128\166"
                    or buttons[index].label == "Restore chat colors"), key .. ": unavailable page shows another action")
            end
            assert(#ctx.widgets == 0 and #ctx.sections == 0, key .. ": unavailable page built settings")
            assert(not M.PageHasReset(key) and not M.ResetPageToDefaults(key), key .. ": unavailable page can reset settings")
            state[addon] = nil
        end
    end
    -- A menu-disabled load-on-demand module still exposes the switch that
    -- turns it back on. Only the rail is dimmed, and missing runtime code is
    -- never mistaken for an active module.
    local wasEnabled, wasLoaded = S.Config("bags").enabled, loaded.MSUF_Suite_Bags
    S.Config("bags").enabled, loaded.MSUF_Suite_Bags = false, nil
    assert(rows.suite_bags.availability() == false, "Frame Basics off does not dim the rail")
    local ctx = { key = "suite_bags", width = 720, wrapper = Widget("Page"), refreshers = {}, widgets = {}, sections = {} }
    M.pages.suite_bags.build(ctx)
    assert(#ctx.sections > 0 and #ctx.widgets > 0 and M.PageHasReset("suite_bags"), "dormant module cannot be configured")
    S.Config("bags").enabled = true
    assert(rows.suite_bags.availability() == false, "unloaded module appears active")
    loaded.MSUF_Suite_Bags = true
    assert(rows.suite_bags.availability() == true, "loaded enabled module stays grey")
    S.Config("bags").enabled = false
    assert(rows.suite_bags.availability() == false, "loaded module ignores its Frame Basics switch")
    S.Config("bags").enabled, loaded.MSUF_Suite_Bags = wasEnabled, wasLoaded

    -- A multi-module destination stays active while any of its modules is on.
    local states = {}
    for _, id in ipairs({ "objectives", "runSummary", "announcements", "afkScreen" }) do
        states[id] = S.Config(id).enabled
        S.Config(id).enabled = false
    end
    local wasRuntimeLoaded = loaded.MSUF_Suite_Modules
    loaded.MSUF_Suite_Modules = true
    assert(rows.suite_hud.availability() == false, "fully disabled HUD appears active")
    S.Config("afkScreen").enabled = true
    assert(rows.suite_hud.availability() == true, "one enabled HUD module must keep its destination active")
    for id, enabled in pairs(states) do S.Config(id).enabled = enabled end
    loaded.MSUF_Suite_Modules = wasRuntimeLoaded
    -- Catalog ownership includes every QoL feature, including those added
    -- after the older page-reset list was written.
    local qolStates, wasQolLoaded = {}, loaded.MSUF_Suite_QualityOfLife
    for _, id in ipairs(Suite.SuiteOrder) do
        if P.catalog[id].page == "suite_qualityOfLife" then
            qolStates[id] = S.Config(id).enabled
            S.Config(id).enabled = false
        end
    end
    loaded.MSUF_Suite_QualityOfLife = true
    assert(rows.suite_qualityOfLife.availability() == false, "fully disabled QoL appears active")
    S.Config("actionTracker").enabled = true
    assert(rows.suite_qualityOfLife.availability() == true, "sole active QoL feature is missing from availability")
    for id, enabled in pairs(qolStates) do S.Config(id).enabled = enabled end
    loaded.MSUF_Suite_QualityOfLife = wasQolLoaded
    local wasSkinEnabled, wasSkinLoaded = Suite.Skin.enabled, loaded.MSUF_Suite_Skin
    Suite.Skin.enabled, loaded.MSUF_Suite_Skin = false, true
    assert(rows.suite_skin.availability() == false, "Skinning ignores its master switch")
    Suite.Skin.enabled = true
    assert(rows.suite_skin.availability() == true, "enabled Skinning stays grey")
    Suite.Skin.enabled, loaded.MSUF_Suite_Skin = wasSkinEnabled, wasSkinLoaded
end

------------------------------------------------------------------ overview API
do
    local count = 0
    for _, id in ipairs(S.order) do if S.Config(id).enabled then count = count + 1 end end
    Suite.RootDB.installation = nil
    local first = assert(Suite.GetOverview())
    assert(first.version == "1.0-test" and first.total == #S.order and first.enabled == count
        and first.pageKey == nil and first.needsSetup == true, "overview fields")
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
assert(opened[1] == "home" and opened[2] == "suite_bags" and opened[3] == "home",
    "/msuite must open the MSUF dashboard: " .. table.concat(opened, ","))

------------------------------------------------------------------ first-run order
do
    local startup = assert(io.open(root .. "/MSUF_Suite/Core/Startup.lua", "rb")):read("*a")
    local _, deferred = startup:gsub('C_Timer%.After%(0, ShowInstaller%)', "")
    local _, stepped = startup:gsub('Step%(Suite%.Installer, "MaybeShow", "login"%)', "")
    local _, bare = startup:gsub("MaybeShow%(%)", "")
    assert(deferred == 1 and stepped == 1 and bare == 0, "startup must ask once after world entry and keep host login ordering")
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
    assert(rawget(window, "openModules") == nil and rawget(window, "modulesHint") == nil,
        "the installer still has a link to Suite Modules")
    window:Hide()
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
    Suite.freshInstall = false
    Suite.RootDB.installation = { revision = 3, status = "pending" }
    assert(Suite.Installer.MaybeShow("login") == true,
        "a pending setup did not resume after SavedVariables were written")
    window:Hide()
    Suite.RootDB.installation = nil
    assert(Suite.Installer.MaybeShow("login") == true,
        "an earlier first login without an installation receipt never recovered its automatic setup")
    window:Hide()
    Suite.RootDB.installation = { revision = 3, status = "complete" }
    assert(Suite.Installer.MaybeShow("login") == false, "completed installations must stay closed")
end

-- Native UISpecialFrame closure follows OnHide, including Escape on Forever.
do
    local oldRegistry, finished = EventRegistry, 0
    EventRegistry = { TriggerEvent = function(_, event)
        assert(event == "MSUFSuite.Installer.Finished" and not Suite.Installer.IsOpen())
        finished = finished + 1
    end }
    Suite.RootDB.installation = { revision = 3, status = "complete" }
    assert(Suite.Installer.Open())
    MSUFSuiteInstallFrame:Hide()
    assert(finished == 1, "native setup closure did not release the deferred CDM choice")
    Suite.RootDB.installation = { revision = 3, status = "pending" }
    assert(Suite.Installer.Open())
    MSUFSuiteInstallFrame:Hide()
    assert(finished == 1, "unfinished setup released CDM consent")
    assert(Suite.Installer.Open())
    MSUFSuiteInstallFrame.close.scripts.OnClick()
    assert(finished == 2 and Suite.RootDB.installation.status == "skipped",
        "Not now did not release consent exactly once")
    EventRegistry = oldRegistry
end

print("Suite navigation, overview, first-run and dashboard routing passed")
