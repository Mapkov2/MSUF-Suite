-- Exercise the actual editor and both hosts' chip flow with resolved anchors.
-- The menu contract's fixed-size widgets cannot detect children escaping the
-- fixed preview into the settings viewport.
local root = assert(arg[1], "Suite root required")
local unpack = unpack
local function Noop() end
local function Axis(point, axis)
    if point:find(axis == 1 and "LEFT" or "BOTTOM", 1, true) then return 0 end
    if point:find(axis == 1 and "RIGHT" or "TOP", 1, true) then return 1 end
    return 0.5
end
local Rect
local function Resolve(frame, axis)
    local size = frame[axis == 1 and "width" or "height"] or 0
    if #frame.points == 0 then return 0, size end
    local low, high, first, firstRatio
    for _, p in ipairs(frame.points) do
        local parent = p[2] or frame.parent
        local a, b = Resolve(parent, axis)
        local target = a + (b - a) * Axis(p[3], axis) + (p[axis + 3] or 0)
        local ratio = Axis(p[1], axis)
        if ratio == 0 then low = target elseif ratio == 1 then high = target end
        first, firstRatio = first or target, firstRatio or ratio
    end
    if low and high then return low, high end
    local start = (low or high and high - size) or first - size * firstRatio
    return start, start + size
end
Rect = function(frame)
    local left, right = Resolve(frame, 1)
    local bottom, top = Resolve(frame, 2)
    return left, bottom, right, top
end
local Frame
Frame = function(parent)
    local f = { parent = parent, points = {}, scripts = {}, shown = true, width = 100, height = 20 }
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:ClearAllPoints() self.points = {} end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:SetWidth(w) self.width = w end
    function f:SetHeight(h) self.height = h end
    function f:GetWidth() local a, b = Resolve(self, 1); return b - a end
    function f:GetHeight() local a, b = Resolve(self, 2); return b - a end
    function f:SetText(t) self.text = t end
    function f:GetText() return self.text or "" end
    function f:GetStringWidth() return #self:GetText() * 6 end
    function f:SetScript(key, fn) self.scripts[key] = fn end
    function f:GetScript(key) return self.scripts[key] end
    function f:HookScript(key, fn)
        local previous = self.scripts[key]
        self.scripts[key] = function(...) if previous then previous(...) end; fn(...) end
    end
    function f:GetParent() return self.parent end
    function f:SetParent(parent) self.parent = parent end
    function f:GetPoint(i) return unpack(self.points[i or 1] or {}) end
    function f:SetShown(shown) self.shown = shown == true end
    function f:Show()
        local changed = not self.shown
        self.shown = true
        if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function f:Hide()
        local changed = self.shown
        self.shown = false
        if changed and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function f:IsShown() return self.shown end
    function f:IsVisible()
        local frame = self
        while frame do
            if not frame.shown then return false end
            frame = frame.parent
        end
        return true
    end
    -- Event registration, as the client keeps it per frame.
    f.events = {}
    function f:RegisterEvent(event) self.events[event] = true end
    function f:UnregisterEvent(event) self.events[event] = nil end
    function f:GetEffectiveScale() return 1 end
    function f:GetFrameLevel() return 1 end
    function f:CreateTexture() return Frame(self) end
    function f:CreateFontString() return Frame(self) end
    return setmetatable(f, { __index = function(_, key)
        if key:match("^Set") or key:match("^Enable") or key:match("^Register") then return Noop end
    end })
end

local function LoadFixedHeaderAPI(host, M, W, T)
    -- Classic moved the docked-preview widgets into their own file; Retail
    -- still keeps them in MSUF_Menu2_Widgets.lua.
    local dir = root .. "/../" .. host .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/"
    local path = dir .. "MSUF_Menu2_Widgets_PreviewDock.lua"
    local file = io.open(path, "rb")
    if not file then
        path = dir .. "MSUF_Menu2_Widgets.lua"
        file = assert(io.open(path, "rb"))
    end
    local source = file:read("*a"); file:close()
    local first = assert(source:find("function W.AttachStickyPageHeader(", 1, true))
    local last = assert(source:find("function M.CloseFixedPreviewExpander(", first, true))
    -- Load the production header/expander functions with only their lexical
    -- theme/registration dependencies supplied by the geometry fixture.
    local prelude = [[
        local M, W, T, Tr = ...
        local max, min = math.max, math.min
        local RegisterSearchObject = function() end
        local PixelLayoutRegion = function(region) return region end
    ]]
    assert(loadstring(prelude .. source:sub(first, last - 1), "@" .. path))(M, W, T, function(v) return v end)
end
CreateFrame = function(_, _, parent) return Frame(parent) end
IsInInstance = function() return false, "none" end
local function CheckInside(child, parent, message)
    local l, b, r, t = Rect(child)
    local pl, pb, pr, pt = Rect(parent)
    assert(l >= pl and b >= pb and r <= pr and t <= pt, message)
end
local function CheckAbove(upper, lower, gap, message)
    local _, ub = Rect(upper)
    local _, _, _, lt = Rect(lower)
    assert(ub >= lt + gap, message)
end

for _, host in ipairs({ "MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames-Classic" }) do
    local shared = { Fallbacks = { Identity = function(v) return v end } }
    assert(loadfile(root .. "/../" .. host
        .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua"))("MSUF", {
            MSUF2 = shared, UF = { Clamp01 = function(value, fallback) return value or fallback end },
        })
    for _, useShared in ipairs({ true, false }) do
        local M, W, T = {}, {}, { colors = { muted = {}, text = {} } }
        M.PreviewHelpers = useShared and {
            FlowLayerChips = shared.PreviewHelpers.FlowLayerChips,
            CreateLayerButton = shared.PreviewHelpers.CreateLayerButton,
        } or {}
        T.Font = function(parent, _, text) local f = Frame(parent); f:SetText(text); return f end
        T.Button = function(parent, text, width, height)
            local f = Frame(parent); f:SetText(text); f:SetSize(width, height); return f
        end
        M.TrackRefresh = Noop
        M.PreviewSelectionBar = {
            Create = function(body)
                local bar = Frame(body); bar:SetHeight(24); body.selection = bar; return bar
            end,
            SetShown = function(body, shown) body.selection:SetShown(shown) end,
            Refresh = Noop,
        }
        LoadFixedHeaderAPI(host, M, W, T)
        local wrapper, headerHost = Frame(), Frame()
        wrapper:SetSize(941, 900)
        headerHost:SetSize(941, 600)
        local ctx = { key = "suite_nameplates", wrapper = wrapper, entry = {} }
        local builder = { y = -12, width = 913 }
        function builder:Section(title, height)
            local section = Frame(wrapper)
            section:SetSize(self.width, height)
            section:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 12, self.y)
            section.title = T.Font(section, nil, title)
            self.y = self.y - height - 12
            return section
        end
        local style = {
            CreateBorder = function() return {} end, PaintBorder = Noop,
            NativeBit = function() return false end, NativeToggle = function() return false end,
            ClassicNativePlate = function() return false end,
            AuraCVar = {}, AuraBits = {},
        }
        local P = { M = M, W = W, T = T, Tr = function(v) return v end,
            Get = function() return 1 end, Combat = function() return false end,
            Suite = { NameplateStyle = style, Client = {}, Public = function() return true end },
            NameplatesEditorMarkers = { TargetActive = function() return false end },
            NameplatesSize = { Build = Noop },
        }
        local bridge = { HostBridge = {} }
        assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeMenu.lua"))("MSUF_Suite", bridge)
        P.HM = bridge.HostBridge.Menu2(M)
        assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesPreviewLayout.lua"))("Options", P)
        assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesEditorLayers.lua"))("Options", P)
        assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesEditor.lua"))("Options", P)
        local ui = P.NameplatesEditor.Create(ctx, builder, {})
        local body, section = ui.body, ui.body.parent
        -- Combat start drops the selection only while the preview shows: with
        -- the menu closed the event stays unregistered, and no pull repaints.
        assert(not body.events.PLAYER_REGEN_DISABLED == not body:IsVisible(),
            "combat start registration does not follow the preview's visibility")
        body:Hide()
        assert(not body.events.PLAYER_REGEN_DISABLED, "a hidden preview still repaints on every combat start")
        body:Show()
        assert(body.events.PLAYER_REGEN_DISABLED, "a preview shown again does not end its drag on combat start")
        local fixed = assert(ctx.entry.pageHeaders[1], "preview was not registered in the fixed header")
        local expander = assert(fixed.previewExpander)
        assert(builder.y == 0, "fixed preview still consumes scrolling content height")
        assert(section:GetHeight() == 162, "compact preview kept the expanded 416px reservation")
        assert(not ui.layerRail:IsShown() and not ui.samples:IsShown() and not ui.raidPalette:IsShown(),
            "compact preview retained expanded controls")
        CheckInside(ui.canvas, body, "compact canvas escaped its body")
        M.SetFixedPreviewExpandedPreference(false)
        fixed:Activate(headerHost, 0)
        fixed.onActivate()
        assert(section:GetParent() == headerHost and ui.compact,
            "Compact preference did not activate the preview in its fixed host")
        local anchorY = select(4, Rect(section))
        wrapper:SetPoint("TOPLEFT", headerHost, "TOPLEFT", 0, -300)
        assert(select(4, Rect(section)) == anchorY, "scrolling the settings moved the preview")
        M.SetFixedPreviewExpandedPreference(true)
        fixed.onActivate()
        assert(expander.expanded and section:GetHeight() == 416 and not ui.compact,
            "page activation did not expand the fixed header")
        local originalWidths = {}
        for i, button in ipairs(ui.layerButtons) do originalWidths[i] = button:GetWidth() end
        for _, width in ipairs({ 640, 885, 1120, 700, 885 }) do
            section:SetWidth(width + 28)
            fixed.originalWidth = width + 28
            expander:Open()
            body.scripts.OnSizeChanged(body)
            for _, fontScale in ipairs({ 1, 1.35 }) do
                for i, button in ipairs(ui.layerButtons) do button:SetWidth(originalWidths[i] * fontScale) end
                ui:Paint()
                if not useShared and fontScale ~= 1 then
                    -- The legacy fallback has fixed-width buttons.
                    for i, button in ipairs(ui.layerButtons) do button:SetWidth(originalWidths[i]) end
                    ui:Paint()
                end
                CheckInside(ui.layerRail, body, "layer rail overlaps settings at width " .. width)
                CheckInside(ui.canvas, body, "canvas escaped preview at width " .. width)
                CheckAbove(ui.selection, ui.layerRail, 6, "selection overlaps layers")
                CheckAbove(ui.tools, ui.selection, 5, "zoom tools overlap selection")
                CheckAbove(ui.canvas, ui.tools, 4, "canvas overlaps toolbar")
                assert(ui.canvas:GetHeight() > 80, "layer flow left no usable canvas")
                for _, button in ipairs(ui.layerButtons) do
                    CheckInside(button, ui.layerRail, "layer button escapes its rail: " .. button.layerKey)
                    CheckInside(button, body, "layer button is clipped by the preview: " .. button.layerKey)
                end
            end
            expander:Close()
            CheckInside(ui.canvas, body, "collapse retained expanded canvas anchors")
            assert(not ui.selection:IsShown() and not ui.tools:IsShown() and not ui.layerRail:IsShown(),
                "collapse retained interactive controls over the settings")
        end
        fixed:Deactivate()
        assert(not section:IsShown() and not expander.expanded, "leaving the page retained its fixed preview")
        fixed:Activate(headerHost, 0)
        fixed.onActivate()
        assert(section:IsShown() and expander.expanded and section:GetParent() == headerHost,
            "returning to the page did not restore the fixed preview")
        print("ok " .. host .. (useShared and " shared chip flow" or " legacy chip flow"))
    end
end
