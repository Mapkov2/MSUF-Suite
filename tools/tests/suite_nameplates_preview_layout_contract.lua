-- Exercise the actual editor on both hosts with resolved anchors.
-- The menu contract's fixed-size widgets cannot detect children escaping the
-- fixed preview into the settings viewport.
local root = assert(arg[1], "Suite root required")
C_GameRules = { IsGameRuleActive = function() return false end }
Enum = { GameRule = { PlayerNameplateDifficultyIcon = 1 } }
local nextFrame = {}
C_Timer = { After = function(_, callback) nextFrame[#nextFrame + 1] = callback end }
local function RunNextFrame()
    local pending = nextFrame
    nextFrame = {}
    for _, callback in ipairs(pending) do callback() end
end
local unpack = unpack
local function Noop() end
local function Click(button, mouse)
    button.scripts.OnClick(button, mouse or "LeftButton")
end
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
    function f:GetStringHeight() return 14 * math.max(1, math.ceil(self:GetStringWidth() / math.max(1, self:GetWidth()))) end
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

local function RenderedNameCenter(sample)
    local left = sample.name:GetRect()
    local _, centerY = sample.name:GetCenter()
    local width = sample.nameText:GetWidth()
    local text = math.min(width, sample.nameText:GetStringWidth())
    local justify = sample.nameText.justify
    local inset = justify == "CENTER" and (width - text) / 2 or justify == "RIGHT" and width - text or 0
    return left + inset + text / 2, centerY
end

local function CheckCenteredNameEdits(P, config, s, m, Render)
    local get, setMany, rules = P.Get, P.SetMany, P.catalog.nameplates.rules
    P.Get = function(_, key) return config[key] end
    local writes, written = 0
    P.SetMany = function(_, changes)
        writes, written = writes + 1, changes
        for key, value in pairs(changes) do config[key] = value end
        return true
    end
    local read, write
    local editor = setmetatable({ host = { Request = Noop },
        kit = { Add = function(_, _, _, reader, writer) read, write = reader, writer end } }, { __index = P.NameplatesEditor })
    s.cell:SetScale(1.4)
    s.bar:SetSize(144, 20)
    s.bar:SetPoint("CENTER", s.cell, "CENTER", -12, -8)
    s.nameText:SetText("Preview name")
    m.namesOnly, m.nameAnchor, m.barWidth, m.horizontal = true, 2, 144, 1
    for _, scope in ipairs({ "enemy", "neutral", "friendly", "friendlyNpc" }) do
        local prefix = (scope == "enemy" or scope == "neutral") and "enemy" or "friendly"
        local keyX, keyY, center = prefix .. "NameOffsetX", prefix .. "NameOffsetY", scope .. "CenterName"
        rules[keyX], rules[keyY] = { min = -2048, max = 2048 }, { min = -2048, max = 2048 }
        config[keyX], config[keyY], config[center] = -37, -13, true
        s.prefix, m.scope, m.nameOnlyScope = prefix, scope, scope ~= "friendly" and scope or nil
        editor.sampleKind, editor.scope = prefix, scope
        editor:Bind(s.name, prefix .. ".Name", "Name", keyX, keyY, "text")
        Render()
        local x, y = read()
        assert(x == 0 and y == -13, scope .. " centered position exposed a dormant horizontal offset")
        assert(write(x, y + 6) and config[keyX] == -37 and config[keyY] == -7 and config[center],
            scope .. " vertical move left Auto center or overwrote its dormant horizontal offset")
        Render()
        local beforeX, beforeY = RenderedNameCenter(s)
        local beforeWrites = writes
        assert(write(x + 13, y + 6) and writes == beforeWrites + 1 and written[center] == false,
            scope .. " moving sideways did not exit Auto center in the same position write")
        for key in pairs(written) do
            assert(key == center or key == keyX or key == keyY, scope .. " changed another setting when moving the name")
        end
        local freeX, freeY = read()
        assert(freeX == config[keyX] and freeY == config[keyY], scope .. " still read a centered X while its repaint was pending")
        Render()
        local afterX, afterY = RenderedNameCenter(s)
        assert(math.abs(afterX - beforeX - 13) <= .5 and math.abs(afterY - beforeY) <= .5,
            scope .. " switching off Auto center shifted the name beyond the requested move")
        rules[keyX], rules[keyY] = nil, nil
    end
    P.Get, P.SetMany = get, setMany
end

local function CheckCenteredNames(P)
    local config = { look = 3, enemy = true, friendly = true, enemyCenterName = true, friendlyNpcCenterName = true,
        enemyNameOffsetY = -3, friendlyNameOffsetY = -3 }
    local function Get(_, key) return config[key] end
    local saved = P.Suite.NameplateText
    local anchor = "RIGHT"
    P.Suite.NameplateText = { Shared = Noop, ResolveSize = function() return 12 end, NameAnchor = function() return anchor end }
    local style = P.Suite.NameplateStyle
    local mirror, place = style.MirrorHeader, style.PlaceMirroredHeader
    style.MirrorHeader = function() return true end
    style.PlaceMirroredHeader = function() error("mirrored header replaced the centered name") end
    local cell = Frame()
    local s = { prefix = "enemy", cell = cell, bar = Frame(cell), name = Frame(cell), nameText = Frame(cell) }
    function s.nameText:SetJustifyH(value) self.justify = value end
    local m = { scope = "enemy", vertical = 1, nativeBarHeight = 20, heightDelta = 6, nameSpacing = 4,
        availableNameWidth = 65, nameAnchor = 1 }
    local function Render()
        P.NameplatesPreviewLayout.RenderName(s, m, Get, function(_, fallback) return fallback end,
            function(_, frame, point, anchor, relative, x, y, key)
                frame:SetPoint(point, anchor, relative, x + (config[s.prefix .. key .. "OffsetX"] or 0),
                    y + (config[s.prefix .. key .. "OffsetY"] or 0))
            end)
    end
    for _, namesOnly in ipairs({ false, true }) do
        m.namesOnly, m.nameOnlyScope = namesOnly, namesOnly and "enemy" or nil
        Render()
        local point = s.name.points[1]
        assert(m.centerName and point[2] == cell and point[4] == 0 and point[5] == 13 and s.nameText.justify == "CENTER",
            "configured name lost the unit center to a manual anchor")
        anchor = nil
        P.NameplatesPreviewDecor.PaintMirroredHeader(s, m, Get, config)
        anchor = "RIGHT"
    end
    m.scope, m.namesOnly, m.nameOnlyScope = "neutral", false, nil
    Render()
    assert(not m.centerName and s.name.points[1][2] == s.bar and s.nameText.justify == "RIGHT",
        "neutral scope inherited the enemy centering setting")
    m.scope, s.prefix = "friendlyNpc", "friendly"
    Render()
    assert(m.centerName and s.name.points[1][2] == cell)
    m.npcWorldName = true
    Render()
    assert(not m.centerName and s.name.points[1][1] == "CENTER", "world name entered the plate layout")
    m.npcWorldName, m.skinDisabled = false, true
    Render()
    assert(not m.centerName, "disabled skin entered the centered layout")
    m.skinDisabled, config.look = false, 2
    Render()
    assert(not m.centerName, "Blizzard look entered the centered layout")
    config.look = 3
    CheckCenteredNameEdits(P, config, s, m, Render)
    P.Suite.NameplateText = saved
    style.MirrorHeader, style.PlaceMirroredHeader = mirror, place
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
local altDown = false
function GetCursorPosition() return cursorX, cursorY end
function IsControlKeyDown() return controlDown end
function IsAltKeyDown() return altDown end
PixelUtil = { GetPixelToUIUnitFactor = function() return 0.5 end }
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
            LevelMode = styleProvider.NameplateStyle.LevelMode, SetSlantedSample = Noop,
            Roles = styleProvider.NameplateStyle.Roles,
            OutlineSize = styleProvider.NameplateStyle.OutlineSize,
            ScopeBars = styleProvider.NameplateStyle.ScopeBars,
            AppearanceSwitch = styleProvider.NameplateStyle.AppearanceSwitch,
            AggroHighlightEnabled = styleProvider.NameplateStyle.AggroHighlightEnabled,
            BarSettings = styleProvider.NameplateStyle.BarSettings,
            SharedBars = styleProvider.NameplateStyle.SharedBars,
            CreateBorder = function() return {} end, PaintBorder = Noop,
            NativeBit = function() return false end, NativeToggle = function() return false end,
            ClassicNativePlate = function() return false end,
            AuraCVar = {}, AuraBits = {},
        }
        local values, writes = {}, 0
        for _, scope in ipairs({ "enemy", "neutral", "friendly", "friendlyNpc" }) do
            values[style.AppearanceSwitch(scope, "outline")] = false
        end
        -- The Suite's preview kit, from the shipped file, on the core namespace it needs.
        local core = { IsSecret = function() return false end, Number = function(v) return type(v) == "number" end,
            InCombat = function() return false end }
        assert(loadfile(root .. "/MSUF_Suite/Core/PreviewKit.lua"))("MSUF_Suite", core)
        local opened, menuActions
        local function Menu()
            return { CreateButton = function(_, label, action)
                if action then menuActions[label] = action end
                return Menu()
            end }
        end
        local P = { M = M, W = W, T = T, Tr = function(v) return v end,
            Get = function(_, key) if values[key] ~= nil then return values[key] end; return 1 end,
            Set = function(_, key, value) values[key] = value; writes = writes + 1 end,
            Combat = function() return false end,
            Available = function(id) return id == "nameplates" end,
            SetTranslatedText = function(label, text) label:SetText(text) end,
            SetButtonText = function(button, text) button._msuf2Label:SetText(text) end,
            Suite = { NameplateStyle = style, Client = {}, Public = function() return true end,
                PreviewKit = core.PreviewKit, NameplateExtensions = { SkinEnabled = function() return true end,
                    SkinKeys = { enemy = "enemy", neutral = "neutralSkinEnabled", friendly = "friendly", friendlyNpc = "friendlyNpcSkinEnabled" } } },
            S = { Config = function() return values end },
            NameplatesEditorMarkers = { TargetActive = function() return false end },
            NameplatesSize = { Build = Noop },
            OpenNameplateSetting = function(key) opened = key return true end,
            OpenNameplateStatusSection = function(side) opened = side .. ".status" end,
            OpenNameplateStatusItem = Noop, NameplateStatusTarget = Noop,
            OpenNameplateCastDetail = function(side, tab) opened = side .. "." .. tab return true end,
            AnchoredContextMenu = function(button, populate)
                menuActions = {}
                populate(button, Menu())
            end,
        }
        assert(loadfile(root .. "/MSUF_Suite/Core/NameplateAuraDisplay.lua"))("MSUF_Suite", P.Suite)
        local bridge = { HostBridge = {} }
        assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeMenu.lua"))("MSUF_Suite", bridge)
        P.HM = bridge.HostBridge.Menu2(M)
        P.Suite.HostBridge = bridge.HostBridge
        assert(loadfile(arg[2] or root .. "/MSUF_Suite_Options/Pages/NameplatesPreviewLayout.lua"))("Options", P)
        assert(loadfile(arg[4] or root .. "/MSUF_Suite_Options/Menu/PreviewInteraction.lua"))("Options", P)
        assert(loadfile(root .. "/MSUF_Suite_Options/Menu/PreviewSnap.lua"))("Options", P)
        assert(loadfile(arg[3] or root .. "/MSUF_Suite_Options/Pages/NameplatesEditorLayers.lua"))("Options", P)
        P.catalog = { nameplates = { rules = {} } }
        P.RuleEnabled = function() return true end
        for _, file in ipairs({ "NameplatesElements", "NameplatesElementPanel", "NameplatesLayoutTemplates", "NameplatesInspector",
            "NameplatesEditorGhosts", "NameplatesEditorTools" }) do
            assert(loadfile(root .. "/MSUF_Suite_Options/Pages/" .. file .. ".lua"))("Options", P)
        end
        assert(loadfile(arg[5] or root .. "/MSUF_Suite_Options/Pages/NameplatesEditor.lua"))("Options", P)
        assert(loadfile(root .. "/MSUF_Suite_Options/Menu/PreviewCanvas.lua"))("Options", P)
        assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesMultiPreview.lua"))("Options", P)
        assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesPreviewDecor.lua"))("Options", P)
        CheckCenteredNames(P)
        local ui = P.NameplatesEditor.Create(ctx, builder, {})
        local sample = { cell = Frame(ui.stage), bar = Frame(ui.stage), cast = Frame(ui.stage), progress = Frame(ui.stage) }
        P.NameplatesPreviewDecor.Build(ui, sample)
        local body, section = ui.body, ui.body.parent
        local function Layer(key)
            for _, button in ipairs(ui.layerButtons) do if button.layerKey == key then return button end end
            error("missing layer " .. key)
        end
        local status = Layer("status")
        local panel = assert(ui.elementPanel, "the preview has no element panel")
        assert(status:GetParent():GetParent() == panel.content, "Status icons switch must sit on its group header")
        assert(panel.title:GetText() == "Elements", "element panel lost its heading")
        local function Row(key)
            for _, row in ipairs(panel.rows) do if row.def.key == key then return row end end
            error("missing element row " .. key)
        end
        local function CheckPanels(width)
            assert(panel:IsShown() == (width >= 640), "element panel visibility does not follow the width " .. width)
            assert(ui.inspector:IsShown() == (width >= 960), "inspector visibility does not follow the width " .. width)
            for _, column in ipairs({ panel, ui.inspector }) do
                if column:IsShown() then
                    CheckInside(column, body, "preview column escaped the preview at width " .. width)
                    for _, region in ipairs({ ui.canvas, ui.tools, ui.selection }) do
                        CheckSeparate(column, region, "preview column overlaps the center at width " .. width)
                    end
                end
            end
        end
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
        assert(not ui.elementPanel:IsShown() and not ui.inspector:IsShown() and not ui.samples:IsShown()
            and not ui.raidPalette:IsShown(), "compact preview retained expanded controls")
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
        assert(Layer("castTarget"):IsVisible() and Layer("enemyPower"):IsVisible() and Layer("status"):IsVisible(),
            "editable layers are hidden behind a context filter")
        assert(panel:IsShown() and not ui.elementPicker:IsShown(), "the docked list has a duplicate picker")
        local beforeSampleTools = writes
        ui:ShowSample("enemy", "enemy")
        ui:Edit("anchor")
        ui.aggroSample = false
        Click(ui.targetStateButton)
        assert(ui.targetSample == false, "Target did not switch the default enemy target off")
        Click(ui.focusStateButton)
        assert(ui.focusSample == true, "Focus did not change the sample")
        Click(ui.castingButton)
        assert(ui.castingSample == false and not ui.uninterruptible, "Casting did not stop the sample cast")
        Click(ui.uninterruptibleButton)
        assert(ui.castingSample and ui.uninterruptible, "Uninterruptible did not start a guarded cast")
        Click(ui.aggroButton)
        assert(ui.aggroSample == true, "Aggro did not change the sample")
        Click(ui.questButton)
        assert(ui.questSample and not ui.enemyPlayer, "Quest did not choose the quest NPC")
        Click(ui.raidButton)
        assert(ui.raidMarked and ui.raidIndex ~= 0 and ui:LayerOn("raidIcon"), "Raid mark did not show a mark")
        Click(ui.typeButton)
        assert(menuActions.Player)()
        assert(ui.enemyPlayer and not ui.questSample, "Type did not replace the quest NPC with the player sample")
        Click(ui.scenarioButton)
        assert(menuActions["Boss with aggro"])()
        assert(ui.sampleScenario.label == "Boss with aggro" and ui.previewRole == 4 and ui.targetSample and ui.aggroSample
            and ui.raidMarked and not ui.enemyPlayer and not ui.castingSample, "the boss scenario did not apply together")
        Click(ui.scenarioButton)
        assert(menuActions.Custom)()
        assert(not ui.sampleScenario and writes == beforeSampleTools, "sample controls wrote to the profile")
        -- Clear the custom example before checking the other entry points below.
        ui:ShowSample("friendly", "friendly")
        ui:ShowSample("enemy", "enemy")
        ui:Edit("anchor")
        assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesPreview.lua"))("Options", P)
        local RenderTarget = Upvalue(P.NameplatesPreview.Render, "RenderTarget")
        local targetSample = { level = Frame(), state = { target = true } }
        local targeted
        P.NameplatesEditorMarkers.PaintTarget = function(_, shown) targeted = shown end
        local statusKeys = { "level", "classification", "raidIcon", "target", "eliteMarker", "questMarker",
            "focusMarker", "threshold", "softTarget", "threatFlash", "threatHighlight" }
        status.scripts.OnClick(status, "LeftButton")
        for _, key in ipairs(statusKeys) do
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
        assert(Layer("name"):IsVisible() and Layer("castTarget"):IsVisible() and Layer("status"):IsVisible(),
            "Aggro changed which layers are offered")
        P.PreviewNameplateStatus("RaidIcon")
        local aggro = Layer("aggroBorder")
        values.highlightAggro = true
        Click(aggro:GetParent())
        assert(ui.highlightSample == "aggro" and not ui.statusSample, "the Aggro border row left an isolated status sample")
        Click(aggro)
        assert(ui.highlightSample == "aggro" and not ui:LayerOn("aggroBorder") and writes == beforeStatus,
            "the Aggro border eye changed the sample scenario or wrote the profile")
        local castTarget = Layer("castTarget")
        local beforeLink = writes
        castTarget.scripts.OnClick(castTarget, "RightButton")
        assert(opened == "enemyCastSpellTarget" and writes == beforeLink, "right-click toggled a layer or opened the wrong setting")
        ui.sampleKind = "friendly"
        ui:Paint()
        assert(not Layer("enemyPower"):IsVisible() and not Layer("aggroBorder"):IsVisible() and Layer("castTarget"):IsVisible(),
            "friendly scope shows enemy controls or misses its own layers")
        castTarget.scripts.OnClick(castTarget, "RightButton")
        assert(opened == "friendly.spell" and writes == beforeLink, "friendly cast link jumped to enemy settings")
        ui.sampleKind = "enemy"
        ui:Edit("anchor")
        -- The plate switch writes the profile and moves the row; a choice
        -- comes back with the mode it had; a locked switch writes nothing.
        local rules = P.catalog.nameplates.rules
        rules.enemyNameVisible = { key = "enemyNameVisible", default = true }
        rules.enemyCastEnabled = { key = "enemyCastEnabled", default = 2, choices = { "Keep", "Show", "Hide" } }
        values.enemyNameVisible, values.enemyCastEnabled = true, 1
        ui:Paint()
        local nameRow, castRow = Row("name"), Row("cast")
        assert(nameRow.action:IsShown() and nameRow.action._msuf2Label:GetText() == "-", "name has no plate switch")
        local beforePlate = writes
        nameRow.action.scripts.OnClick(nameRow.action)
        assert(values.enemyNameVisible == false and writes == beforePlate + 1, "- did not take the name off the plate")
        assert(nameRow.action._msuf2Label:GetText() == "+" and panel.offHeader:IsShown(),
            "the name did not move to Not on the plate")
        local offY, rowY = select(5, panel.offHeader:GetPoint(1)), select(5, nameRow:GetPoint(1))
        assert(rowY < offY, "an element off the plate is listed above Not on the plate")
        nameRow.action.scripts.OnClick(nameRow.action)
        assert(values.enemyNameVisible == true and not panel.offHeader:IsShown(), "+ did not put the name back")
        castRow.action.scripts.OnClick(castRow.action)
        assert(values.enemyCastEnabled == 3, "- did not hide the castbar")
        castRow.action.scripts.OnClick(castRow.action)
        assert(values.enemyCastEnabled == 1, "+ did not restore the castbar's previous mode")
        P.RuleEnabled = function() return false, "Locked for this look." end
        assert(P.NameplatesElements.Locked(ui, castRow.def) == "Locked for this look.", "a locked switch has no reason")
        local beforeLocked = writes
        castRow.action.scripts.OnClick(castRow.action)
        assert(values.enemyCastEnabled == 1 and writes == beforeLocked, "a locked plate switch wrote the profile")
        P.RuleEnabled = function() return true end
        assert(not Row("health").action:IsShown(), "the health bar offered to leave the plate")
        values.enemyStyleOutlineOverride = true
        for key, suffix in pairs({ glow = "GlowEnabled", shadow = "ShadowEnabled", outerFrame = "OuterFrame" }) do
            local sharedKey, scopedKey = "enemy" .. suffix, "enemyStyle" .. suffix
            values[sharedKey], values[scopedKey] = true, true
            rules[sharedKey], rules[scopedKey] = { key = sharedKey, default = true }, { key = scopedKey, default = true }
            ui:Paint()
            local action = Row(key).action
            Click(action)
            assert(values[scopedKey] == false and values[sharedKey] == true, "Remove wrote the shared " .. key .. " setting")
            Click(action)
            assert(values[scopedKey] == true and values[sharedKey] == true, "Add did not restore the scoped " .. key .. " setting")
            rules[sharedKey], rules[scopedKey] = nil, nil
        end
        values.enemyStyleOutlineOverride = false
        Click(Row("auras"))
        assert(panel.positions.auras:IsShown() and not panel.positions.icons:IsShown(),
            "position actions outside the selected group clutter the list")
        Click(panel.positions.auras)
        assert(menuActions["Aura countdown position"] and menuActions["Aura stack position"],
            "docked list lost the shared aura position actions")
        nameRow.scripts.OnClick(nameRow, "LeftButton")
        assert(ui.inspectedKey == "name", "a row click did not inspect its element")
        local selectionTools = assert(ui.selectedTools)
        local beforeSelectedActions = writes
        assert(selectionTools:IsVisible() and selectionTools.title:GetText() == "Name",
            "the selection toolbar did not show the inspected name")
        opened = nil
        Click(selectionTools.settings)
        assert(opened == "enemyNameSize" and writes == beforeSelectedActions,
            "the selected element's settings button did not open its exact control")
        assert(not selectionTools.eye:IsShown() and not selectionTools.plate:IsShown(),
            "the selected toolbar repeats the docked list's actions")
        Click(nameRow.eye)
        assert(not ui:LayerOn("name") and values.enemyNameVisible and writes == beforeSelectedActions,
            "the selection toolbar's Hide changed the profile")
        Click(nameRow.eye)
        assert(ui:LayerOn("name") and values.enemyNameVisible and writes == beforeSelectedActions,
            "the selection toolbar's Show did not restore the sample")
        Click(nameRow.action)
        assert(values.enemyNameVisible == false and writes == beforeSelectedActions + 1 and selectionTools:IsVisible()
            and nameRow.action._msuf2Label:GetText() == "+", "the list did not offer Add after removing the name")
        Click(nameRow.action)
        assert(values.enemyNameVisible and writes == beforeSelectedActions + 2
            and nameRow.action._msuf2Label:GetText() == "-", "the list's Add did not put the name back")
        ui.kit.opts.escape()
        assert(ui.inspectedKey == nil and not selectionTools:IsShown(), "Escape kept the inspected element or its toolbar")
        rules.enemyNameVisible, rules.enemyCastEnabled = nil, nil
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
            local targetCaption, focusCaption = "Target", "Focus"
            local fit = ui.zoomControls[1][1]
            handle._label = "Enemy Name"
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
                assert(ui.elementPicker:IsShown() == not panel:IsShown(), "the picker and list compete after resizing")
                if ui.elementPicker:IsShown() then CheckButtonLabel(ui.elementPicker, "Elements") end
                for _, button in ipairs(ui.layerButtons) do
                    if button.fs then button.fs.charWidth = 6 * fontScale end
                end
                local label = Layer("health").fs
                if label then label:SetText(fontScale > 1 and "Langer lokalisierter Lebensbalken" or "Blizzard health") end
                ui:Paint()
                CheckButtonLabel(ui.targetStateButton, targetCaption)
                CheckButtonLabel(ui.focusStateButton, focusCaption)
                CheckButtonLabel(fit, fitCaption)
                CheckPanels(width)
                CheckInside(ui.canvas, body, "canvas escaped preview at width " .. width)
                CheckInside(ui.raidPalette, ui.canvas, "raid marker palette clipped")
                CheckAbove(ui.tools, ui.selection, 5, "zoom tools overlap selection")
                CheckAbove(ui.canvas, ui.tools, 4, "canvas overlaps toolbar")
                assert(ui.canvas:GetHeight() > 80, ("canvas was %.0f at width %d, font scale %.2f (tools %.0f)")
                    :format(ui.canvas:GetHeight(), width, fontScale, ui.tools:GetHeight()))
                assert(not ui.contextButton, "preview still has the outdoor/dungeon switch")
                if ui.elementPicker:IsShown() then CheckInside(ui.elementPicker, ui.tools, "element picker clips") end
                CheckInside(selectionTools, ui.canvas, "selection toolbar clips")
                CheckSeparate(selectionTools, ui.samples, "selection toolbar overlaps the sample toolbar")
                local previous
                for _, entry in ipairs(ui.zoomControls) do
                    local control = entry[1]
                    CheckInside(control, ui.tools, "zoom control clips")
                    if ui.elementPicker:IsShown() then
                        CheckSeparate(control, ui.elementPicker, "zoom control overlaps the element picker")
                    end
                    if previous then CheckSeparate(previous, control, "zoom controls overlap") end
                    previous = control
                end
                if panel:IsShown() then
                    local pl, _, pr = Rect(panel)
                    for _, row in ipairs(panel.rows) do
                        if row:IsVisible() then
                            local l, _, r = Rect(row)
                            assert(l >= pl and r <= pr, "element row escapes its panel: " .. row.def.key)
                        end
                    end
                    local clip = panel.clip
                    assert(panel.contentHeight > clip:GetHeight(), "the element list should scroll at the expanded height")
                    panel.offset = 0
                    clip.scripts.OnMouseWheel(clip, -1)
                    assert(panel.offset > 0, "the wheel did not scroll the element list")
                    for _ = 1, 100 do clip.scripts.OnMouseWheel(clip, -1) end
                    assert(math.abs(panel.offset - (panel.contentHeight - clip:GetHeight())) < .01,
                        "the element list scrolled past its end")
                    clip.scripts.OnMouseWheel(clip, 100)
                    assert(panel.offset == 0, "the element list scrolled above its start")
                end
                if ui.inspector:IsShown() then
                    assert(ui.inspector.title:GetText() == "Enemy Name", "the inspector does not show the selected element")
                end
                for index, button in ipairs(ui.sampleButtons) do
                    if button:IsShown() then
                        CheckInside(button, ui.samples, "sample toolbar clipped")
                        for i = index + 1, #ui.sampleButtons do
                            local other = ui.sampleButtons[i]
                            if other:IsShown() then CheckSeparate(button, other, "sample buttons overlap") end
                        end
                    end
                end
            end
            ui.targetStateButton._msuf2Label:SetText("Target")
            ui.focusStateButton._msuf2Label:SetText("Focus")
            body._selectedHandle = nil
            if ui.inspector:IsShown() then
                rules.enemyNameVisible = { key = "enemyNameVisible", default = true }
                Click(nameRow)
                local inspector = ui.inspector
                assert(not inspector.plate and not inspector.settings and not inspector.reset and not inspector.templates,
                    "the inspector repeats actions already on the list or selection toolbar")
                rules.enemyNameVisible = nil
            end
            expander:Close()
            CheckInside(ui.canvas, body, "collapse retained expanded canvas anchors")
            assert(not ui.selection:IsShown() and not ui.tools:IsShown() and not ui.elementPanel:IsShown()
                and not ui.inspector:IsShown(), "collapse retained interactive controls over the settings")
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

        ui.sampleCells = { enemy = ui.stage }
        ui.stage.previewCastAllowed = true
        P.catalog.nameplates.rules.enemyCastEnabled = { key = "enemyCastEnabled", choices = { "Keep", "Show", "Hide" } }
        values.enemyCastEnabled, ui.castingSample = 2, false
        cast:Hide()
        ui:Paint()
        local ghost = assert(cast.previewGhost, "an enabled castbar did not leave an inactive placeholder")
        assert(ghost:IsVisible() and #ghost.dashes > 4, "inactive castbar placeholder is hidden or has no dashes")
        local beforeGhost = writes
        Click(ghost)
        assert(ui.castSample == "Cast" and writes == beforeGhost,
            "the castbar placeholder did not reveal a preview-only example")
        ui.stage.previewCastAllowed = false
        ui.castSample, ui.castingSample = nil, false
        ui:Paint()
        assert(not ghost:IsShown(), "the cast placeholder was drawn for a name-only sample")
        ui.stage.previewCastAllowed = true
        values.enemyCastEnabled = 3
        ui.castingSample, ui.castSample = false, nil
        ui:Paint()
        assert(not ghost:IsShown(), "the disabled castbar was still drawn as an inactive element")
        values.enemyCastEnabled = 2
        ui.castingSample = true
        cast:Show()
        ui:Paint()
        assert(not ghost:IsShown(), "the active castbar also drew its placeholder")
        ui:Select(cast)
        Click(ui.selectedTools.eye)
        cast:Hide()
        ui:Paint()
        assert(not body._selectedHandle and ui.inspectedKey == "cast", "hiding the cast lost the inspected element")
        Click(ui.selectedTools.eye)
        cast:Show()
        ui:Paint()
        assert(body._selectedHandle == cast, "showing the cast did not restore its exact selected handle")
        local raid = SampleHandle(ui.stage, "enemy.RaidIcon", 10, 20, 0, 18)
        raid.previewGhostWidth = 18
        raid:Hide()
        P.catalog.nameplates.rules.enemyRaidIcon = { key = "enemyRaidIcon", default = true }
        values.enemyRaidIcon, ui.raidMarked, ui.statusSample = true, false, nil
        ui:Paint()
        assert(raid.previewGhost and raid.previewGhost:IsVisible() and raid.previewGhost:GetWidth() == 18,
            "an unmarked sample did not reserve its raid mark placeholder geometry")

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
        local draggedPoints = hp.points
        hp.scripts.OnUpdate(hp)
        assert(hp.points == draggedPoints, "an unchanged pointer frame reanchored the preview handle")
        hp.scripts.OnMouseUp(hp, "LeftButton")
        hp.scripts.OnClick(hp, "LeftButton")
        assert(writes == oldWrites + 1 and values.x == 13 and values.y == 7 and not ui.dragging, "drag committed the wrong offset")
        RunNextFrame()

        fit.scripts.OnClick(fit)
        assert(ui.fitMode and ui.zoom < 1 and ui.panX == 0 and ui.panY == 0, "Fit did not reset and scale the painted footprint")
        local beforeX, beforeY, beforeZoom = ui.viewX, ui.viewY, ui.zoom
        assert(body.selectionOptions.WriteOffsets(body, hp, values.x + 5, values.y))
        RunNextFrame()
        assert(not ui.fitMode and ui.viewX == beforeX and ui.viewY == beforeY and ui.zoom == beforeZoom,
            "moving an element let Fit recenter the viewport")
        fit.scripts.OnClick(fit)
        local function CheckFit()
            local left, bottom, right, top = Rect(hp)
            for _, region in ipairs({ cast, raid.previewGhost }) do
                if region:IsVisible() then
                    local l, b, r, t = Rect(region)
                    left, bottom, right, top = math.min(left, l), math.min(bottom, b), math.max(right, r), math.max(top, t)
                end
            end
            local x, y, r, t = Rect(ui.canvas)
            assert(left >= x + 19.99 and right <= r - 19.99 and bottom >= y + ui.fitBottom + 19.99 and top <= t - ui.fitTop - 19.99,
                "Fit clipped a visible element")
            assert(math.abs((left + right - x - r) / 2) < .01, "Fit did not center the visible elements horizontally")
            assert(math.abs((bottom + top - y - t + ui.fitTop - ui.fitBottom) / 2) < .01,
                "Fit did not center within the usable viewport")
        end
        CheckFit()
        local selectedInset = ui.fitTop
        ui:Select(nil)
        assert(ui.fitTop < selectedInset and ui.fitMode, "Fit did not release the selected-element toolbar inset")
        CheckFit()
        ui:Select(hp)
        assert(ui.fitTop == selectedInset and ui.fitMode, "Fit did not reserve the selected-element toolbar inset")
        CheckFit()
        local withCast = ui.zoom
        cast:Hide()
        ui:Paint()
        CheckFit()
        assert(ui.zoom > withCast, "Fit did not respond to a hidden layer")
        actual.scripts.OnClick(actual)
        assert(ui.zoom == 1 and not ui.fitMode, "1:1 did not exit Fit")
        CheckStage(0, 0)
        print("ok " .. host .. (useShared and " shared preview helpers" or " legacy preview helpers"))
    end
end
