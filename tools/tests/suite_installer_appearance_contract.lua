-- Real Suite installer plus the actually loaded Classic shared UI/skin
-- bridge: cold fallback, provider transitions, late Menu2 and view-only paint.
local root = assert(arg[1], "Suite root required")
local classic = root .. "/../MidnightSimpleUnitFrames-Classic"
local H = dofile(root .. "/tools/tests/suite_installer_harness.lua")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function SameColor(actual, expected, message)
    Check(type(actual) == "table", message .. " is missing")
    for index = 1, 4 do
        Check(math.abs((actual[index] or 1) - (expected[index] or 1)) < 0.00001,
            message .. " differs at " .. index .. ": " .. tostring(actual[index]) .. " / " .. tostring(expected[index]))
    end
end
local function Hex(suite, value)
    local r, g, b = suite.RGB(value)
    return { r, g, b, 1 }
end

local function Instrument()
    local made = {}
    local deferred = {}
    C_Timer.After = function(delay, callback)
        Check(delay == 0, "appearance started a delayed timer")
        deferred[#deferred + 1] = callback
    end
    local function Flush()
        local jobs = deferred
        deferred = {}
        for _, callback in ipairs(jobs) do callback() end
        return #jobs
    end
    local function Wrap(frame, parent)
        local index = getmetatable(frame).__index
        setmetatable(frame, { __index = function(self, key)
            if key:sub(1, 1) == "_" then return nil end
            return index(self, key)
        end })
        frame.parent, frame.font, frame.events = parent, { "Fonts\\FRIZQT__.TTF", 13, "" }, {}
        local scripts, hooks = {}, {}
        local function Bind(name)
            frame.scripts[name] = function(self, ...)
                if scripts[name] then scripts[name](self, ...) end
                for _, hook in ipairs(hooks[name] or {}) do hook(self, ...) end
            end
        end
        function frame:SetScript(name, callback) scripts[name] = callback; Bind(name) end
        function frame:GetScript(name) return scripts[name] end
        function frame:HookScript(name, callback)
            hooks[name] = hooks[name] or {}
            hooks[name][#hooks[name] + 1] = callback
            Bind(name)
        end
        function frame:Show()
            local previous = self.shown
            self.shown = true
            if not previous and self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetBackdrop(value) self.backdrop = value end
        function frame:GetBackdropColor() return unpack(rawget(self, "fill") or { 1, 1, 1, 1 }) end
        function frame:GetBackdropBorderColor() return unpack(rawget(self, "edge") or { 1, 1, 1, 1 }) end
        function frame:SetBackdropColor(...) self.fill = { ... } end
        function frame:SetBackdropBorderColor(...) self.edge = { ... } end
        function frame:SetColorTexture(...) self.color = { ... } end
        function frame:SetVertexColor(...) self.color = { ... } end
        function frame:SetTextColor(...) self.textColor = { ... } end
        function frame:SetFont(path, size, flags) self.font = { path, size, flags }; return true end
        function frame:GetFont() return unpack(self.font) end
        function frame:SetFontObject() end
        function frame:IsEnabled() return self.enabled ~= false end
        function frame:CreateFontString() return Wrap(H.Widget("FontString"), self) end
        function frame:CreateTexture() return Wrap(H.Widget("Texture"), self) end
        return frame
    end
    CreateFrame = function(kind, name, parent)
        local frame = Wrap(H.Widget(kind), parent)
        if name then _G[name] = frame end
        made[#made + 1] = frame
        return frame
    end
    return function(addon)
        for _, frame in ipairs(made) do
            if frame.events.ADDON_LOADED then frame.scripts.OnEvent(frame, "ADDON_LOADED", addon) end
        end
        Flush()
    end, Flush
end

local function Setup(forever)
    MSUF2, MSUF_UI, MapkoSkin = nil, nil, nil
    MSUF_AddUIThemeListener, MSUF_GetUITheme = nil, nil
    H.skin = nil
    local suite = H.Setup({ root = root, forever = forever })
    local emit, flush = Instrument()
    local loads = 0
    C_AddOns.LoadAddOn = function() loads = loads + 1; return false, "MISSING" end
    return suite, emit, function() return loads end, flush
end

local function SharedUI()
    MSUF_SetFontChecked = function(label, path, size, flags) return label:SetFont(path, size, flags) end
    local host = { Translate = function(value) return value end,
        ExportPublic = function(name, value) _G[name] = value end }
    assert(loadfile(classic .. "/MidnightSimpleUnitFrames/Shell/UI/MSUF_Widgets.lua"))(
        "MidnightSimpleUnitFrames", host)
    return host
end

local function SkinProvider(suite, host)
    local enabled, palette, hooks = true, {}, {}
    local fields = { background = "bgColor", popup = "bgColor", input = "bgColor",
        ink = "headerColor", surface = "headerColor", raised = "headerColor", card = "headerColor",
        buttonFill = "headerColor", buttonFillAlt = "headerColor", blue = "headerColor",
        hover = "trackColor", active = "headerColor", rim = "borderColor", border = "borderColor",
        borderSoft = "borderColor", buttonBorder = "borderColor", accent = "barColor",
        accentBright = "barColor", checkmark = "barColor", accentAlt = "barColor",
        text = "leftColor", title = "titleColor", muted = "rightColor", dim = "rightColor", disabled = "rightColor" }
    local surfaces = {}
    local client = { ReleaseAll = function() end }
    function client:SkinFrame(frame, spec)
        surfaces[frame] = { role = spec.role, activeRole = spec.activeRole, active = spec.active }
        return true, "applied"
    end
    function client:SkinButton(frame, spec) return self:SkinFrame(frame, spec) end
    function client:SetActive(frame, active)
        assert(surfaces[frame], "active state before material attachment").active = active
        return true, "applied"
    end
    local api = {
        RegisterAddon = function() return client end,
        IsEnabled = function() return enabled end,
        GetAppearanceSnapshot = function() return {} end,
        GetColor = function(_, key) return unpack((assert(palette[key], key))) end,
        OnAppearanceChanged = function() end,
    }
    hooksecurefunc = function(owner, key, callback)
        Check(owner == api and key == "OnAppearanceChanged", "unexpected shared UI hook")
        hooks[#hooks + 1] = callback
        owner[key] = function(self, ...)
            for _, hook in ipairs(hooks) do hook(self, ...) end
        end
    end
    local engine = { addonName = "MSUF_Suite_Skin", GetAPI = function(major, minor)
        if major == 2 and minor <= 1 then return api end
    end }
    local function SetLook(index, active)
        enabled = active ~= false
        local preset = suite.DamageMeterLookPresets[index]
        for key, field in pairs(fields) do palette[key] = Hex(suite, preset[field]) end
    end
    SetLook(1)
    -- This file is in the core TOC; the unused UIThemeBridge is deliberately absent.
    assert(loadfile(classic .. "/MidnightSimpleUnitFrames/Shell/UI/MSUF_MapkoSkin.lua"))(
        "MidnightSimpleUnitFrames", host)
    return engine, api, SetLook, hooks, surfaces
end

for _, forever in ipairs({ false, true }) do
    local suite, _, loads = Setup(forever)
    Check(suite.Installer.Open(), "older host could not open setup")
    local frame = MSUFSuiteInstallFrame
    local preset = suite.DamageMeterLookPresets[forever and 3 or 2]
    SameColor(frame.next.edge, Hex(suite, preset.barColor), "catalog fallback action")
    Check(frame.backdrop.edgeFile == "Interface\\Buttons\\WHITE8X8" and frame.backdrop.edgeSize == 1,
        "cold installer kept its separate tooltip frame")
    Check(loads() == 0, "appearance loaded an optional addon")
end

do
    local suite, emit, loads, flush = Setup(false)
    local host = SharedUI()
    Check(suite.Installer.Open(), "cold shared UI installer could not open")
    local frame = MSUFSuiteInstallFrame
    SameColor(frame.fill, host.UI.colors.popup, "cold shared popup")
    SameColor(frame.next._msufUIEdge.edge, host.UI.colors.pillEdgeActive, "cold shared action")
    Check(frame.title.font[2] == host.UI.FontSize("hero") and frame.next.caption.font[2] == host.UI.FontSize("control"),
        "cold installer ignored shared font roles")
    Check(MSUF2 == nil and MSUF_AddUIThemeListener == nil and loads() == 0,
        "cold appearance needed the dormant bridge or loaded Options")
    local installation = suite.RootDB.installation
    local engine, api, setLook, hooks, surfaces = SkinProvider(suite, host)
    MapkoSkin = engine
    emit("MSUF_Suite_Skin")
    Check(host.MenuSkin.IsActive() and #hooks == 2, "late provider did not join both actual bridges once")
    emit("MSUF_Suite_Skin")
    Check(#hooks == 2, "appearance hooks accumulated")
    local refresh, refreshes = suite.InstallerAppearance.Refresh, 0
    suite.InstallerAppearance.Refresh = function() refreshes = refreshes + 1; refresh() end
    for _, index in ipairs({ 1, 2, 3, 1 }) do
        local before = refreshes
        setLook(index)
        api:OnAppearanceChanged("theme", "look")
        api:OnAppearanceChanged("color", "accent")
        Check(flush() == 1, "appearance did not coalesce one native repaint job")
        Check(refreshes > before, "appearance continuation did not run")
        Check(#H.reported == 0, "shared provider repaint raised: " .. tostring(H.reported[1]))
        Check(frame:IsShown(), "provider transition hid the installer")
        Check(surfaces[frame].role == "popup", "live shared popup got the wrong material")
        Check(surfaces[frame.next].role == "button" and surfaces[frame.next].active == true,
            "live shared primary lost its active material state")
        Check(frame.next.suiteSelectionMarker:IsShown(), "skin hid the primary action marker")
        SameColor(frame.next.suiteSelectionMarker.color, host.UI.colors.accent, "live primary marker")
        SameColor(frame.progress[1].color, host.UI.colors.accent, "live shared progress")
    end
    setLook(3, false)
    api:OnAppearanceChanged("adapter", "master")
    flush()
    Check(not host.MenuSkin.IsActive(), "disabled skin still owns the cold palette")
    SameColor(frame.fill, host.UI.colors.popup, "disabled provider fallback")
    -- A late Menu2 must replace the cold accessor; an absent theme is never cached.
    local colors = { popup = { .12, .13, .14, .99 }, panel2 = { .17, .18, .19, .88 },
        pillBase = { .20, .21, .22, .91 }, pillHover = { .30, .31, .32, .95 },
        pillActive = { .40, .41, .42, .96 }, border = { .5, .51, .52, .9 },
        borderSoft = { .6, .61, .62, .7 }, pillEdgeActive = { .8, .7, .3, 1 },
        accent = { .9, .8, .4, 1 }, text = { .9, .91, .92, 1 }, muted = { .7, .71, .72, 1 } }
    MSUF2 = { Theme = { colors = colors,
        ApplyBackdrop = function(panel, fill, edge)
            panel:SetBackdropColor(unpack(fill)); panel:SetBackdropBorderColor(unpack(edge))
        end,
        StyleFontString = function(label, color, _, role)
            label.role = role
            label:SetTextColor(unpack(color))
        end } }
    emit("MidnightSimpleUnitFrames_Options")
    SameColor(frame.fill, colors.popup, "late Menu2 popup")
    Check(frame.title.role == "hero" and frame.next.caption.role == "control", "late Menu2 font roles were not applied")
    frame.next.scripts.OnEnter(frame.next)
    SameColor(frame.next._msufUIFill.color, colors.pillActive, "primary hovered action")
    frame.next.scripts.OnLeave(frame.next)
    SameColor(frame.next._msufUIEdge.edge, colors.pillEdgeActive, "primary after leave")
    frame.next.scripts.OnClick()
    Check(frame.classic.mark:GetText() == suite.Text("SELECTED"), "appearance changed the layout selection")
    Check(frame.classic.suiteSelectionMarker:IsShown() and not frame.forever.suiteSelectionMarker:IsShown(),
        "layout selection has no independent accent marker")
    local selected = frame.colors[1]
    local swatch = selected.swatches[3]
    local previewColor = { unpack(swatch.color) }
    colors.accent[1] = .13
    suite.Installer.Refresh()
    SameColor(swatch.color, previewColor, "profile color swatch after menu accent edit")
    selected.scripts.OnEnter(selected)
    selected.scripts.OnLeave(selected)
    SameColor(selected._msufUIFill.color, colors.pillActive, "selected palette after hover")
    frame.colors[2].scripts.OnClick()
    Check(frame.colorChoice == "midnight", "appearance changed the chosen install palette")
    Check(frame.colors[2].suiteSelectionMarker:IsShown() and not selected.suiteSelectionMarker:IsShown(),
        "palette marker did not follow the staged choice")
    frame.next.scripts.OnClick()
    frame.moduleTabs.qol.scripts.OnEnter(frame.moduleTabs.qol)
    frame.moduleTabs.qol.scripts.OnClick()
    frame.moduleTabs.qol.scripts.OnLeave(frame.moduleTabs.qol)
    SameColor(frame.moduleTabs.qol._msufUIFill.color, colors.pillActive, "selected module tab after hover")
    Check(frame.moduleTabs.qol.suiteSelectionMarker:IsShown() and not frame.moduleTabs.modules.suiteSelectionMarker:IsShown(),
        "module tab marker did not follow the active group")
    Check(suite.RootDB.installation == installation and installation.status == "pending" and loads() == 0,
        "appearance changed saved installation state or loaded dependencies")
    Check(#H.reported == 0, "appearance raised through the error boundary")
end

do
    local suite, emit, loads = Setup(false)
    local tint, popup = { .71, .64, .23, 1 }, { .04, .045, .05, .95 }
    -- Older hosts may publish colors plus only the core font renderer.
    -- Unsupported or absent renderer entries use owned chrome instead.
    MSUF_UI = { colors = { popup = popup }, Color = function() return tint end,
        Button = false, ApplyMaterial = "legacy",
        ApplyFontRole = function(label, role) label.role = role end }
    Check(suite.Installer.Open(), "partial older appearance prevented setup")
    local frame = MSUFSuiteInstallFrame
    SameColor(frame.fill, popup, "partial older popup")
    SameColor(frame.next.edge, tint, "partial older color getter")
    Check(frame.title.role == "hero" and frame.next.caption.role == "control",
        "partial older font renderer was not bound")
    local menuPopup = { .11, .12, .13, .98 }
    MSUF2 = { Theme = { colors = { popup = menuPopup }, StyleFontString = function(label, color, _, role)
        label.menuRole = role
        label:SetTextColor(unpack(color))
    end } }
    emit("MidnightSimpleUnitFrames_Options")
    SameColor(frame.fill, menuPopup, "late partial Menu2 popup")
    Check(frame.title.menuRole == "hero" and frame.next.caption.menuRole == "control",
        "late partial Menu2 renderer did not replace core font roles")
    Check(#H.reported == 0 and loads() == 0, "partial appearance raised or loaded dependencies")
end

do
    local suite, emit, _, flush = Setup(false)
    SharedUI()
    local registrations, callback = 0
    local legacy = { OnThemeChanged = function(_, fn) registrations, callback = registrations + 1, fn end }
    MapkoSkin = { GetAPI = function(major) if major == 1 then return legacy end end }
    Check(suite.Installer.Open(), "legacy skin API prevented setup")
    emit("MapkoSkin")
    Check(registrations == 1, "legacy theme listeners accumulated")
    callback()
    flush()
    Check(#H.reported == 0, "legacy theme callback raised")
end
print("installer appearance: " .. checks .. " shared UI/provider/Menu2/state checks passed")
