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
    function f:SetClipsChildren(value) self.clipsChildren = value end
    function f:DoesClipChildren() return self.clipsChildren == true end
    function f:GetWidth() local a, b = Resolve(self, 1); return b - a end
    function f:GetHeight() local a, b = Resolve(self, 2); return b - a end
    function f:SetText(t) self.text = t end
    function f:GetText() return self.text or "" end
    function f:GetStringWidth() return #self:GetText() * (self.charWidth or 6) end
    f.GetUnboundedStringWidth = f.GetStringWidth
    function f:SetWordWrap(wrap) self.wordWrap = wrap end
    function f:EnableMouseWheel(enabled) self.mouseWheel = enabled end
    function f:SetScrollChild(child)
        self.scrollChild = child
        child:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    end
    function f:GetVerticalScroll() return self.scrollOffset or 0 end
    function f:GetVerticalScrollRange() return math.max(0, self.scrollChild:GetHeight() - self:GetHeight()) end
    function f:SetVerticalScroll(offset)
        self.scrollOffset = offset
        self.scrollChild:ClearAllPoints()
        self.scrollChild:SetPoint("TOPLEFT", self, "TOPLEFT", 0, offset)
    end
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
    function f:GetFrameLevel() return self.frameLevel or 1 end
    function f:SetFrameLevel(level) self.frameLevel = level end
    function f:CreateTexture() return Frame(self) end
    function f:CreateFontString() return Frame(self) end
    return setmetatable(f, { __index = function(_, key)
        if key:match("^Set") or key:match("^Enable") or key:match("^Register") then return Noop end
    end })
end

local function LoadFixedHeaderAPI(host, M, W, T)
    local dir = root .. "/../" .. host .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/"
    local path = dir .. "MSUF_Menu2_Widgets_PreviewDock.lua"
    local file = io.open(path, "rb")
    if file then
        file:close()
        M.Widgets, M.Theme = W, T
        W.RegisterSearchObject = Noop
        T.ReducedMotionEnabled = function() return true end
        assert(loadfile(path))("MSUF", { MSUF2 = M, Require = function() return function(region) return region end end })
        return
    end
    path = dir .. "MSUF_Menu2_Widgets.lua"
    file = assert(io.open(path, "rb"))
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
local function CheckSeparate(first, second, message)
    local l, b, r, t = Rect(first)
    local sl, sb, sr, st = Rect(second)
    assert(r <= sl or sr <= l or t <= sb or st <= b, message)
end
local function CheckButtonLabel(button, expected)
    local label = button._msuf2Label
    assert(label:GetText() == expected, "unexpected button caption: " .. label:GetText())
    assert(label.wordWrap == false, "button label can wrap: " .. expected)
    assert(label:GetWidth() >= label:GetUnboundedStringWidth(), "button label clips: " .. expected)
    CheckInside(label, button, "button label escaped its frame: " .. expected)
end

for _, host in ipairs({ "_repo_backups/6.22", "MidnightSimpleUnitFrames-7.0" }) do
    local shared = { Fallbacks = { Identity = function(v) return v end } }
    assert(loadfile(root .. "/../" .. host
        .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua"))("MSUF", {
            MSUF2 = shared, UF = { Clamp01 = function(value, fallback) return value or fallback end },
        })
    for _, useShared in ipairs({ true, false }) do
        local M, W, T = {}, {}, { colors = { muted = {}, text = {} } }
        function M.AddTooltip(widget, _, body) widget.tooltipText = body end
        M.PreviewHelpers = useShared and {
            FlowLayerChips = shared.PreviewHelpers.FlowLayerChips,
            CreateLayerButton = shared.PreviewHelpers.CreateLayerButton,
        } or {}
        T.Font = function(parent, _, text) local f = Frame(parent); f:SetText(text); return f end
        T.Button = function(parent, text, width, height)
            local f = Frame(parent)
            f:SetSize(width, height)
            local label = T.Font(f, nil, text)
            label:SetHeight(14)
            label:SetPoint("LEFT", f, "LEFT", 12, 0)
            label:SetPoint("RIGHT", f, "RIGHT", -12, 0)
            f._msuf2Label = label
            return f
        end
        M.TrackRefresh = Noop
        M.SetMenuStateValue = function(field, value) M[field] = value end
        M.PreviewSelectionBar = {
            Create = function(body, options)
                body.selectionOptions = options
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
        local styleProvider = { AnchorPoints = {}, AnchorLabels = {} }
        assert(loadfile(root .. "/MSUF_Suite/Core/NameplateStyle.lua"))("MSUF_Suite", styleProvider)
        local style = {
            LevelMode = styleProvider.NameplateStyle.LevelMode,
            OutlineSize = styleProvider.NameplateStyle.OutlineSize,
            AggroHighlightEnabled = styleProvider.NameplateStyle.AggroHighlightEnabled,
            BarSettings = styleProvider.NameplateStyle.BarSettings,
            SharedBars = styleProvider.NameplateStyle.SharedBars,
            CreateBorder = function() return {} end, PaintBorder = Noop,
            NativeBit = function() return false end, NativeToggle = function() return false end,
            ClassicNativePlate = function() return false end,
            AuraCVar = {}, AuraBits = {},
        }
        local values, writes = {}, 0
        -- The Suite's preview kit, from the shipped file, on the core namespace it needs.
        local core = { IsSecret = function() return false end, Number = function(v) return type(v) == "number" end,
            InCombat = function() return false end }
        assert(loadfile(root .. "/MSUF_Suite/Core/PreviewKit.lua"))("MSUF_Suite", core)
        local opened
        local P = { M = M, W = W, T = T, Tr = function(v) return v end,
            Get = function(_, key) if values[key] ~= nil then return values[key] end; return 1 end,
            Set = function(_, key, value) values[key] = value; writes = writes + 1 end,
            Combat = function() return false end,
            SetTranslatedText = function(label, text) label:SetText(text) end,
            SetButtonText = function(button, text) button._msuf2Label:SetText(text) end,
            Suite = { NameplateStyle = style, Client = {}, Public = function() return true end,
                PreviewKit = core.PreviewKit },
            S = { Config = function() return values end },
            NameplatesEditorMarkers = { TargetActive = function() return false end },
            NameplatesSize = { Build = Noop },
            OpenNameplateSetting = function(key) opened = key return true end,
            OpenNameplateStatusSection = function(side) opened = side .. ".status" end,
            OpenNameplateStatusItem = Noop,
            OpenNameplateCastDetail = function(side, tab) opened = side .. "." .. tab return true end,
        }
        assert(loadfile(root .. "/MSUF_Suite/Core/NameplateAuraDisplay.lua"))("MSUF_Suite", P.Suite)
        local bridge = { HostBridge = {} }
        assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeMenu.lua"))("MSUF_Suite", bridge)
        P.HM = bridge.HostBridge.Menu2(M)
        assert(loadfile(arg[2] or root .. "/MSUF_Suite_Options/Pages/NameplatesPreviewLayout.lua"))("Options", P)
        assert(loadfile(arg[4] or root .. "/MSUF_Suite_Options/Menu/PreviewInteraction.lua"))("Options", P)
        assert(loadfile(arg[3] or root .. "/MSUF_Suite_Options/Pages/NameplatesEditorLayers.lua"))("Options", P)
        assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesEditor.lua"))("Options", P)
        assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesMultiPreview.lua"))("Options", P)
        assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesPreviewDecor.lua"))("Options", P)
        local ui = P.NameplatesEditor.Create(ctx, builder, {})
        local sample = { cell = Frame(ui.stage), bar = Frame(ui.stage), cast = Frame(ui.stage), progress = Frame(ui.stage) }
        P.NameplatesPreviewDecor.Build(ui, sample)
        local body, section = ui.body, ui.body.parent
        local function Layer(key)
            for _, button in ipairs(ui.layerButtons) do if button.layerKey == key then return button end end
            error("missing layer " .. key)
        end
        values.look, ui.sampleKind = 4, "enemy"
        values.enemyGlowMode, values.enemyGlowEnabled = 2, true
        local glow = Layer("glow")
        glow.scripts.OnClick(glow, "LeftButton")
        glow.scripts.OnClick(glow, "LeftButton")
        assert(values.enemyGlowMode == 2 and values.enemyGlowEnabled, "live layer toggle replaced selected glow mode")
        for _, button in ipairs(ui.layerButtons) do assert(button.layerKey ~= "fillTexture", "retired texture chip remains") end
        ui.sampleKind = "friendly"
        local before = writes
        for _, key in ipairs({ "focusMarker", "threshold" }) do
            local button = Layer(key)
            button.scripts.OnClick(button, "LeftButton")
        end
        assert(writes == before, "unavailable friendly sample changed enemy settings")
        -- NPC world names have no movable or adjustable nameplate elements.
        P.NameplatesEditorMarkers.ToggleTarget = function() writes = writes + 1 end
        values.friendlyNPCs, ui.friendlyElite = 4, true
        for _, key in ipairs({ "level", "target", "name", "targetScale", "raidIcon" }) do
            local button = Layer(key)
            button.scripts.OnClick(button, "LeftButton")
            assert(not ui:LayerAvailable(key), "NPC world-name layer remained editable: " .. key)
        end
        assert(writes == before, "NPC world-name layer chips changed nameplate settings")
        local function Upvalue(fn, name)
            for index = 1, 60 do
                local key, value = debug.getupvalue(fn, index)
                if key == name then return value end
                if not key then break end
            end
            error("missing editor helper " .. name)
        end
        local handle = { previewUI = ui }
        assert(not Upvalue(P.NameplatesEditor.Bind, "Write")(ui, handle, 20, 30),
            "NPC world-name nudge wrote nameplate offsets")
        assert(not Upvalue(P.NameplatesEditor.Bind, "CanEdit")(handle), "NPC world name remained selectable")
        handle.IsShown = function() return true end
        assert(not ui.body.selectionOptions.IsPlaced(handle), "NPC world name remained in the element picker")
        local savedSelect = ui.kit.Select
        ui.kit.Select = function(_, selected) assert(selected == nil, "NPC world name accepted a picker selection") end
        ui:Select(handle)
        ui.kit.Select = savedSelect
        assert(ui.body.selectionOptions.ResetOffsets(nil, handle) == false, "NPC world-name reset changed nameplate offsets")
        values.friendlyNPCs, ui.friendlyElite = 1, false
        assert(Upvalue(P.NameplatesEditor.Bind, "CanEdit")(handle), "switching back did not restore nameplate interaction")
        ui.sampleKind = "enemy"
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
        fixed:Activate(headerHost, 0)
        if host == "MidnightSimpleUnitFrames-7.0" then
            fixed.onActivate()
            assert(not expander.expanded and ui.compact, "Suite Nameplates did not open compact by default")
            expander:Close("FIXED_PREVIEW_COMMAND")
        else
            M.SetFixedPreviewExpandedPreference(false)
        end
        -- Pinned ownership checks can hide the body before the page wrapper
        -- shows. Compact activation must recover without opening the expander.
        body:Hide()
        fixed.onActivate()
        assert(body:IsVisible() and ui.canvas:IsVisible() and ui.stage:IsVisible(),
            "compact activation left the renderer hidden until Expand")
        assert(body:GetFrameLevel() > section:GetFrameLevel(),
            "compact renderer stayed beneath its docked section")
        assert(section:GetParent() == headerHost and ui.compact,
            "Compact preference did not activate the preview in its fixed host")
        local anchorY = select(4, Rect(section))
        wrapper:SetPoint("TOPLEFT", headerHost, "TOPLEFT", 0, -300)
        assert(select(4, Rect(section)) == anchorY, "scrolling the settings moved the preview")
        M.SetFixedPreviewExpandedPreference(true)
        fixed.onActivate()
        assert(ui.compact, "global preference overrode the compact nameplate default")
        ui:Edit("anchor")
        assert(expander.expanded and section:GetHeight() == 526 and not ui.compact,
            "Edit in preview did not expand the fixed header")
        assert(Layer("castTarget"):IsShown() and Layer("enemyPower"):IsShown() and Layer("status"):IsShown(),
            "editable layers are hidden behind a context filter")
        CheckButtonLabel(ui.elementPicker, "Select")
        local status = Layer("status")
        local content = status:GetParent()
        local scroll = content:GetParent()
        assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesPreview.lua"))("Options", P)
        local RenderTarget = Upvalue(P.NameplatesPreview.Render, "RenderTarget")
        local targetSample = { level = Frame(), state = { target = true } }
        local targeted
        P.NameplatesEditorMarkers.PaintTarget = function(_, shown) targeted = shown end
        local statusKeys = { "level", "classification", "raidIcon", "target", "eliteMarker", "questMarker",
            "focusMarker", "threshold", "softTarget", "threatFlash", "threatHighlight" }
        status.scripts.OnClick(status, "LeftButton")
        for _, key in ipairs(statusKeys) do
            assert(not Layer(key):IsShown(), "individual status chip still shown: " .. key)
            assert(not ui:LayerOn(key), "Status icons toggle missed " .. key)
        end
        RenderTarget(ui, targetSample, {})
        assert(not targeted, "target arrows remained visible with Status icons disabled")
        assert(ui:LayerOn("cast") and ui:LayerOn("name"), "Status icons toggle hid other elements")
        status.scripts.OnClick(status, "LeftButton")
        for _, key in ipairs(statusKeys) do assert(ui:LayerOn(key), "Status icons toggle did not restore " .. key) end
        RenderTarget(ui, targetSample, {})
        assert(targeted, "Status icons toggle did not restore the target arrows")
        local beforeStatus = writes
        status.settingsLink.scripts.OnClick(status.settingsLink)
        assert(opened == "enemy.status" and writes == beforeStatus, "Status icons link did not open its settings")

        P.PreviewNameplateStatus("RaidIcon")
        assert(ui.statusSample == "RaidIcon", "previewing a status icon stopped selecting it")
        ui.aggroSample = false
        P.PreviewNameplateStatus("Aggro")
        assert(ui.aggroSample and not ui.statusSample and writes == beforeStatus, "Aggro isolated the status sample or changed settings")
        assert(Layer("name"):IsShown() and Layer("castTarget"):IsShown() and Layer("status"):IsShown(),
            "Aggro changed which layers are offered")
        P.PreviewNameplateStatus("RaidIcon")
        local aggro = Layer("aggroBorder")
        aggro.scripts.OnClick(aggro, "LeftButton")
        assert(ui.highlightSample == "aggro" and not ui.statusSample, "Aggro border left an isolated status sample")
        local link = assert(Layer("castTarget").settingsLink, "the layer lacks a visible settings link")
        local beforeLink = writes
        link.scripts.OnClick(link)
        assert(opened == "enemyCastSpellTarget" and writes == beforeLink, "settings link toggled a layer or opened the wrong control")
        ui.sampleKind = "friendly"
        ui:Paint()
        assert(not Layer("enemyPower"):IsShown() and not Layer("aggroBorder"):IsShown() and Layer("castTarget"):IsShown(),
            "friendly scope shows enemy controls or misses its own layers")
        link.scripts.OnClick(link)
        assert(opened == "friendly.spell" and writes == beforeLink, "friendly cast link jumped to enemy settings")
        ui.sampleKind = "enemy"
        ui:Edit("anchor")
        if host == "MidnightSimpleUnitFrames-7.0" then
            local click = expander.button:GetScript("OnClick")
            click()
            assert(ui.compact and section:GetHeight() == 162 and not section:DoesClipChildren())
            click()
            assert(not ui.compact and section:GetHeight() == 526 and not section:DoesClipChildren())
            assert(select(4, Rect(section)) == anchorY, "toggling the preview moved the fixed header")
        end
        for _, width in ipairs({ 280, 360, 525, 640, 885, 1120, 360 }) do
            section:SetWidth(width + 28)
            fixed.originalWidth = width + 28
            expander:Open()
            body.scripts.OnSizeChanged(body)
            local pickerCaption = "Enemy Name"
            local targetCaption, focusCaption = "Target / non-target", "Focus sample"
            local fit = ui.zoomControls[1][1]
            handle._label = pickerCaption
            for _, fontScale in ipairs({ 1, 1.35 }) do
                body._selectedHandle = nil
                ui:RefreshSelection()
                for _, button in ipairs({ ui.elementPicker, ui.targetStateButton, ui.focusStateButton, fit }) do
                    button._msuf2Label.charWidth = 6 * fontScale
                end
                local fitCaption = fontScale > 1 and "Einpassen" or "Fit"
                fit._msuf2Label:SetText(fitCaption)
                if fontScale > 1 then
                    targetCaption, focusCaption = "Bersaglio / altro", "Aperçu de focalisation"
                    ui.targetStateButton._msuf2Label:SetText(targetCaption)
                    ui.focusStateButton._msuf2Label:SetText(focusCaption)
                end
                body._selectedHandle = handle
                ui:RefreshSelection()
                CheckButtonLabel(ui.elementPicker, pickerCaption)
                for _, button in ipairs(ui.layerButtons) do
                    if button.fs then button.fs.charWidth = 6 * fontScale end
                end
                local label = Layer("health").fs
                if label then label:SetText(fontScale > 1 and "Langer lokalisierter Lebensbalken" or "Blizzard health") end
                ui:Paint()
                CheckButtonLabel(ui.targetStateButton, targetCaption)
                CheckButtonLabel(ui.focusStateButton, focusCaption)
                CheckButtonLabel(fit, fitCaption)
                CheckInside(ui.layerRail, body, "layer rail overlaps settings at width " .. width)
                CheckInside(ui.canvas, body, "canvas escaped preview at width " .. width)
                CheckInside(scroll, ui.layerRail, "scroll viewport escapes its rail")
                CheckInside(ui.raidPalette, ui.canvas, "raid marker palette clipped")
                CheckAbove(ui.selection, ui.layerRail, 6, "selection overlaps layers")
                CheckAbove(ui.tools, ui.selection, 5, "zoom tools overlap selection")
                CheckAbove(ui.canvas, ui.tools, 4, "canvas overlaps toolbar")
                assert(ui.canvas:GetHeight() > 80, ("canvas was %.0f at width %d, font scale %.2f (tools %.0f, layers %.0f)")
                    :format(ui.canvas:GetHeight(), width, fontScale, ui.tools:GetHeight(), ui.layerRail:GetHeight()))
                assert(not ui.contextButton, "preview still has the outdoor/dungeon switch")
                for _, control in ipairs({ ui.targetStateButton, ui.focusStateButton, ui.elementPicker }) do
                    CheckInside(control, ui.tools, "preview toolbar child clipped")
                end
                CheckSeparate(ui.targetStateButton, ui.elementPicker, "target control overlaps the element picker")
                CheckSeparate(ui.focusStateButton, ui.elementPicker, "focus control overlaps the element picker")
                CheckSeparate(ui.targetStateButton, ui.focusStateButton, "target and focus controls overlap")
                local previous
                for _, entry in ipairs(ui.zoomControls) do
                    local control = entry[1]
                    CheckInside(control, ui.tools, "zoom control clips")
                    CheckSeparate(control, ui.elementPicker, "zoom control overlaps the element picker")
                    if previous then CheckSeparate(previous, control, "zoom controls overlap") end
                    previous = control
                end
                for _, button in ipairs(ui.visibleLayerButtons or ui.layerButtons) do
                    CheckInside(button, content, "layer button escapes its scroll content: " .. button.layerKey)
                    if button.settingsLink then CheckInside(button.settingsLink, button, "settings link was clipped") end
                end
                local scrollRange = scroll:GetVerticalScrollRange()
                if width == 280 then assert(scrollRange > 0, "narrow layers did not scroll") end
                if width >= 885 then assert(scrollRange == 0, "wide layers still require scrolling") end
                assert(scroll:GetVerticalScroll() <= scrollRange, "resize retained an out-of-range scroll offset")
                assert(scroll.mouseWheel == (scrollRange > 0), "rail grabs the wheel without overflow")
                scroll:SetVerticalScroll(scrollRange)
                CheckInside(ui.visibleLayerButtons[#ui.visibleLayerButtons], scroll, "last layer cannot be reached by scrolling")
                for _, button in ipairs(ui.sampleButtons) do
                    if button:IsShown() then CheckInside(button, ui.canvas, "sample toolbar clipped") end
                end
            end
            ui.targetStateButton._msuf2Label:SetText("Target / non-target")
            ui.focusStateButton._msuf2Label:SetText("Focus sample")
            body._selectedHandle = nil
            expander:Close()
            CheckInside(ui.canvas, body, "collapse retained expanded canvas anchors")
            assert(not ui.selection:IsShown() and not ui.tools:IsShown() and not ui.layerRail:IsShown(),
                "collapse retained interactive controls over the settings")
            M.SetFixedPreviewExpandedPreference(false)
            fixed:Deactivate()
            headerHost:SetFrameLevel(headerHost:GetFrameLevel() + 7)
            fixed:Activate(headerHost, 0)
            body:Hide()
            fixed.onActivate()
            assert(ui.compact and body:IsVisible() and ui.stage:IsVisible(),
                "cached compact activation did not restore the renderer")
            assert(body:GetFrameLevel() > section:GetFrameLevel(),
                "cached compact renderer did not follow its new header level")
            M.SetFixedPreviewExpandedPreference(true)
        end
        fixed:Deactivate()
        assert(not section:IsShown() and not expander.expanded, "leaving the page retained its fixed preview")
        fixed:Activate(headerHost, 0)
        fixed.onActivate()
        assert(section:IsShown() and ui.compact and section:GetParent() == headerHost,
            "returning to the page did not restore the fixed preview")
        print("ok " .. host .. (useShared and " shared chip flow" or " legacy chip flow"))
    end
end
