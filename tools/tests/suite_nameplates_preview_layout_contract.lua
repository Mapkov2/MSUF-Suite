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
    local scale = frame:GetEffectiveScale()
    local size = (frame[axis == 1 and "width" or "height"] or 0) * scale
    if #frame.points == 0 then return 0, size end
    local low, high, first, firstRatio
    for _, p in ipairs(frame.points) do
        local parent = p[2] or frame.parent
        local a, b = Resolve(parent, axis)
        local target = a + (b - a) * Axis(p[3] or p[1], axis) + (p[axis + 3] or 0) * scale
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
    local f = { parent = parent, points = {}, scripts = {}, children = {}, shown = true, width = 100, height = 20 }
    if parent then parent.children[#parent.children + 1] = f end
    function f:GetChildren() return unpack(self.children) end
    function f:GetObjectType() return self.kind or "Frame" end
    function f:GetNumPoints() return #self.points end
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:ClearAllPoints() self.points = {} end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:SetWidth(w) self.width = w end
    function f:SetHeight(h) self.height = h end
    function f:SetClipsChildren(value) self.clipsChildren = value end
    function f:DoesClipChildren() return self.clipsChildren == true end
    function f:GetWidth() local a, b = Resolve(self, 1); return (b - a) / self:GetEffectiveScale() end
    function f:GetHeight() local a, b = Resolve(self, 2); return (b - a) / self:GetEffectiveScale() end
    function f:GetRect()
        local x, y, right, top = Rect(self)
        local scale = self:GetEffectiveScale()
        return x / scale, y / scale, (right - x) / scale, (top - y) / scale
    end
    function f:GetCenter()
        local x, y, width, height = self:GetRect()
        return x + width / 2, y + height / 2
    end
    function f:SetText(t) self.text = t end
    function f:GetText() return self.text or "" end
    function f:GetStringWidth() return #self:GetText() * (self.charWidth or 6) end
    f.GetUnboundedStringWidth = f.GetStringWidth
    function f:SetWordWrap(wrap) self.wordWrap = wrap end
    function f:EnableMouseWheel(enabled) self.mouseWheel = enabled end
    function f:SetMinMaxValues(low, high)
        self.low, self.high = low, high
        if self.value then self:SetValue(self.value) end
    end
    function f:GetMinMaxValues() return self.low, self.high end
    function f:GetValue() return self.value end
    function f:SetValue(value)
        value = math.min(self.high, math.max(self.low, value))
        if value == self.value then return end
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
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
    function f:SetScale(scale) self.scale = scale end
    function f:GetEffectiveScale()
        return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1)
    end
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
CreateFrame = function(kind, _, parent)
    local frame = Frame(parent)
    frame.kind = kind
    return frame
end
local cursorX, cursorY, controlDown, pointerHeld = 0, 0, false, true
function GetCursorPosition() return cursorX, cursorY end
function IsControlKeyDown() return controlDown end
function IsMouseButtonDown() return pointerHeld end
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
        assert(loadfile(arg[5] or root .. "/MSUF_Suite_Options/Pages/NameplatesEditor.lua"))("Options", P)
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
        local status = Layer("status")
        assert(status:GetParent() == ui.layerRail, "layer chips must be anchored to the visible rail")
        local slider, layerTitle
        for _, child in ipairs({ ui.layerRail:GetChildren() }) do
            if child:GetObjectType() == "Slider" then slider = child end
            if child:GetText() == "Preview Layers" then layerTitle = child end
        end
        assert(slider and layerTitle, "wide and narrow layouts need a common layer rail")
        layerTitle:SetWidth(layerTitle:GetStringWidth())
        values.look, ui.sampleKind = 4, "enemy"
        values.enemyGlowMode, values.enemyGlowEnabled = 2, true
        values.enemy, values.enemyPowerEnabled = true, true
        values.enemyNpcAuraMode, values.enemyNpcDebuffs = 2, true
        local beforeToggles = writes
        for _, key in ipairs({ "glow", "enemyPower", "auras" }) do
            local button = Layer(key)
            button.scripts.OnClick(button, "LeftButton")
            assert(not ui:LayerOn(key) and writes == beforeToggles, key .. " chip wrote settings instead of hiding the layer")
            button.scripts.OnClick(button, "LeftButton")
            assert(ui:LayerActive(key) and writes == beforeToggles, key .. " chip did not restore the preview")
        end
        local power = Layer("enemyPower")._msuf2CommandAction
        assert(power.set(false) and not power.get() and power.set(true) and power.get() and writes == beforeToggles,
            "power search commands did not toggle preview visibility independently")
        values.enemyPowerEnabled = false
        assert(not power.get() and not power.set(true) and not values.enemyPowerEnabled and writes == beforeToggles,
            "power search command enabled a disabled live feature")
        values.enemyGlowEnabled = false
        local glow = Layer("glow")
        glow.scripts.OnClick(glow, "LeftButton")
        assert(not ui:LayerActive("glow") and opened == "enemyGlowEnabled" and writes == beforeToggles,
            "disabled glow layer did not open its setting")
        values.enemyGlowEnabled = true
        for _, button in ipairs(ui.layerButtons) do
            assert(button.layerKey ~= "fillTexture", "retired texture chip remains")
            assert(not button.settingsLink, "right chevron remains on layer " .. button.layerKey)
        end
        ui.sampleKind = "friendly"
        local before = writes
        for _, key in ipairs({ "focusMarker", "threshold" }) do
            local button = Layer(key)
            button.scripts.OnClick(button, "LeftButton")
        end
        assert(writes == before, "unavailable friendly sample changed enemy settings")
        -- NPC world names have no movable or adjustable nameplate elements.
        values.friendlyNPCs, ui.friendlyElite = 4, true
        for _, key in ipairs({ "level", "target", "name", "targetScale", "raidIcon" }) do
            local button = Layer(key)
            button.scripts.OnClick(button, "LeftButton")
            assert(not ui:LayerAvailable(key), "NPC world-name layer remained editable: " .. key)
        end
        assert(writes == before, "NPC world-name layer chips changed nameplate settings")
        local guides = Layer("guides")
        guides.scripts.OnClick(guides, "LeftButton")
        assert(not ui:LayerActive("guides") and writes == before, "NPC world names kept preview guides on")
        guides.scripts.OnClick(guides, "LeftButton")
        assert(ui:LayerActive("guides"), "NPC world names could not restore preview guides")
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
        handle.IsVisible = function() return true end
        handle.IsShown = handle.IsVisible
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
        status.scripts.OnClick(status, "RightButton")
        assert(opened == "enemy.status" and writes == beforeStatus, "Status icons right-click did not open its settings")

        P.PreviewNameplateStatus("RaidIcon")
        assert(ui.statusSample == "RaidIcon", "previewing a status icon stopped selecting it")
        ui.aggroSample = false
        P.PreviewNameplateStatus("Aggro")
        assert(ui.aggroSample and not ui.statusSample and writes == beforeStatus, "Aggro isolated the status sample or changed settings")
        assert(Layer("name"):IsShown() and Layer("castTarget"):IsShown() and Layer("status"):IsShown(),
            "Aggro changed which layers are offered")
        P.PreviewNameplateStatus("RaidIcon")
        local aggro = Layer("aggroBorder")
        values.highlightAggro = true
        aggro.scripts.OnClick(aggro, "LeftButton")
        assert(ui.highlightSample == "aggro" and not ui.statusSample, "Aggro border left an isolated status sample")
        local castTarget = Layer("castTarget")
        local beforeLink = writes
        castTarget.scripts.OnClick(castTarget, "RightButton")
        assert(opened == "enemyCastSpellTarget" and writes == beforeLink, "right-click toggled a layer or opened the wrong setting")
        ui.sampleKind = "friendly"
        ui:Paint()
        assert(not Layer("enemyPower"):IsShown() and not Layer("aggroBorder"):IsShown() and Layer("castTarget"):IsShown(),
            "friendly scope shows enemy controls or misses its own layers")
        castTarget.scripts.OnClick(castTarget, "RightButton")
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
                if width >= 885 then
                    assert(layerTitle:GetPoint() == "LEFT", "wide layer rail did not dock its heading left")
                    CheckSeparate(layerTitle, Layer("guides"), "layer rail heading overlaps the chips")
                end
                CheckInside(ui.canvas, body, "canvas escaped preview at width " .. width)
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
                for _, button in ipairs(ui.layerButtons) do
                    if button:IsShown() then
                        CheckInside(button, ui.layerRail, "layer button escapes its rail: " .. button.layerKey)
                    end
                end
                if width == 280 then assert(slider:IsShown(), "narrow layers did not scroll") end
                if width >= 885 then assert(not slider:IsShown() and slider:GetValue() == 0, "wide layers did not reset") end
                assert(ui.layerRail.mouseWheel == slider:IsShown(), "rail grabs the wheel without overflow")
                if slider:IsShown() then
                    local _, last = slider:GetMinMaxValues()
                    slider:SetValue(0)
                    ui.layerRail.scripts.OnMouseWheel(ui.layerRail, -1)
                    assert(slider:GetValue() == 1, "rail wheel did not scroll to the next row")
                    slider:SetValue(last)
                    local guides, castTarget = Layer("guides"), Layer("castTarget")
                    assert(not guides:IsShown() and castTarget:IsShown(), "last layer is not selectable at the bottom")
                    CheckInside(castTarget, ui.layerRail, "last layer escaped the rail")
                end
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
        expander:Open()
        body.scripts.OnSizeChanged(body)
        local function SampleHandle(parent, id, x, y, w, h, scale)
            local widget = Frame(parent)
            widget:SetSize(w, h)
            widget:SetScale(scale or 1)
            widget:SetPoint("CENTER", parent, "CENTER", x, y)
            ui:Bind(widget, id, id, "x", "y", "test")
            return widget
        end
        local hp = SampleHandle(ui.stage, "enemy.Health", -35, 10, 100, 20)
        local cast = SampleHandle(ui.stage, "enemy.Cast", 260, -180, 80, 36, 1.25)
        local idleSide = Frame(ui.stage)
        idleSide:Hide()
        local hidden = SampleHandle(idleSide, "friendly.Health", 900, 1200, 100, 20)
        assert(hidden:IsShown() and not body.selectionOptions.IsPlaced(hidden), "Tab can select a hidden-side layer")
        ui:Select(hidden)
        assert(not body._selectedHandle, "an invisible frame was selected")
        ui:Select(hp)
        assert(body._selectedHandle == hp and body.selectionOptions.IsPlaced(hp), "visible health handle could not be selected")

        local fit = ui.zoomControls[1][1]
        local actual = ui.zoomControls[2][1]
        local zoomIn = ui.zoomControls[5][1]
        actual.scripts.OnClick(actual)
        ui.panX, ui.panY = 58, -27
        ui:Paint()
        zoomIn.scripts.OnClick(zoomIn)
        assert(ui.zoom == 1.25, "zoom control did not use Unit Frame steps")
        local canvasX, canvasY = ui.canvas:GetCenter()
        local function CheckStage(x, y)
            local sx, sy = ui.stage:GetCenter()
            assert(math.abs(sx * ui.zoom - canvasX - x) < .01 and math.abs(sy * ui.zoom - canvasY - y) < .01,
                "stage position drifted after zoom")
        end
        CheckStage(58, -27)
        local forwarded = 0
        M.ForwardMenuScrollWheel = function(delta) forwarded = forwarded + delta end
        hp.scripts.OnMouseWheel(hp, 1)
        assert(forwarded == 1 and ui.zoom == 1.25, "ordinary wheel failed to scroll the page")
        controlDown = true
        ui.canvas.scripts.OnMouseWheel(ui.canvas, 1)
        assert(ui.zoom == 1.50 and forwarded == 1, "Ctrl+wheel did not zoom")
        cursorX, cursorY, pointerHeld = 100, 60, true
        hp.scripts.OnMouseDown(hp, "LeftButton")
        assert(ui.panning and not ui.kit.drag, "Ctrl+drag hit the element rather than the canvas")
        cursorX, cursorY = 120, 50
        ui.canvas.scripts.OnUpdate(ui.canvas)
        hp.scripts.OnMouseUp(hp, "LeftButton")
        hp.scripts.OnClick(hp, "LeftButton")
        assert(not ui.panning and not ui.canvas.scripts.OnUpdate, "canvas pan was not released")
        CheckStage(78, -37)
        controlDown = false

        P.catalog = { nameplates = { rules = { x = { min = -1000, max = 1000 }, y = { min = -1000, max = 1000 } } } }
        local oldWrites = writes
        P.SetMany = function(_, offsets) values.x, values.y = offsets.x, offsets.y; writes = writes + 1 end
        hp.scripts.OnMouseDown(hp, "LeftButton")
        assert(not ui.dragging, "a click started moving the plate")
        local heldX, heldY = cursorX, cursorY
        cursorX = cursorX + 1
        hp.scripts.OnUpdate(hp)
        assert(not ui.dragging and writes == oldWrites, "pointer jitter started a drag")
        cursorX, cursorY = heldX + 18, heldY + 9
        hp.scripts.OnUpdate(hp)
        assert(ui.dragging == hp and writes == oldWrites, "drag wrote settings before release")
        hp.scripts.OnMouseUp(hp, "LeftButton")
        hp.scripts.OnClick(hp, "LeftButton")
        assert(writes == oldWrites + 1 and values.x == 13 and values.y == 7 and not ui.dragging, "drag committed the wrong offset")

        fit.scripts.OnClick(fit)
        assert(ui.fitMode and ui.zoom < 1 and ui.panX == 0 and ui.panY == 0, "Fit did not reset and scale the painted footprint")
        local function CheckFit()
            local left, bottom, right, top = Rect(hp)
            if cast:IsVisible() then
                local l, b, r, t = Rect(cast)
                left, bottom, right, top = math.min(left, l), math.min(bottom, b), math.max(right, r), math.max(top, t)
            end
            local x, y, r, t = Rect(ui.canvas)
            assert(left >= x + 19.99 and right <= r - 19.99 and bottom >= y + 19.99 and top <= t - ui.fitTop - 19.99,
                "Fit clipped a visible element")
            assert(math.abs((left + right - x - r) / 2) < .01, "Fit did not center the visible elements horizontally")
            assert(math.abs((bottom + top - y - t + ui.fitTop) / 2) < .01, "Fit did not center within the usable viewport")
        end
        CheckFit()
        local withCast = ui.zoom
        cast:Hide()
        ui:Paint()
        CheckFit()
        assert(ui.zoom > withCast, "Fit did not respond to a hidden layer")
        actual.scripts.OnClick(actual)
        assert(ui.zoom == 1 and not ui.fitMode, "1:1 did not exit Fit")
        CheckStage(0, 0)
        print("ok " .. host .. (useShared and " shared chip flow" or " legacy chip flow"))
    end
end
