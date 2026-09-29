local _, P = ...
-- Minimap page preview, the canvas: selectable, draggable elements whose
-- offsets write the minimap settings, the keyboard nudges, zoom and layer
-- chips. MinimapPreviewPaint.lua (loaded first) draws the elements.
local Suite, S, W, M, T, Tr = P.Suite, P.S, P.W, P.M, P.T, P.Tr
local ID, PAGE = "minimap", "suite_minimap"
local PREVIEW_SECTION = "suite_minimap_preview"
local COMPACT_HEIGHT, EXPANDED_HEIGHT = 112, 316
local HANDLE_COLOR = { 0.30, 0.74, 1.00 }
local DEFAULT_HINT = "Click to select; drag or use arrow keys; edit exact X/Y below."
local Data = P.MinimapPreviewData
local TEXTS, ICONS, LAYERS, ORNAMENT_EDGES = Data.TEXTS, Data.ICONS, Data.LAYERS, Data.ORNAMENT_EDGES
local Clamp, Tint, SetIcon = Data.Clamp, Data.Tint, Data.SetIcon
local OffsetPrefix, OffsetKeys, PaintElements = Data.OffsetPrefix, Data.OffsetKeys, Data.PaintElements

-- Right-clicking a layer chip opens the accordion that styles it.
local LAYER_SECTIONS = { map = "layout", border = "shape", shadow = "shape", ornament = "style_art",
    glow = "style_glow", backdrop = "style_backdrop", text = "info_colors", blizzard = "elements",
    folio = "landing", addons = "addons" }
------------------------------------------------------------------ offsets
local function WriteOffsets(key, x, y)
    if P.Combat() then return false end
    local xKey, yKey = OffsetKeys(key)
    if not xKey then return false end
    local rules = Suite.SuiteCatalog[ID].rules
    local xRule, yRule = rules[xKey], rules[yKey]
    if not xRule or not yRule then return false end
    x = Clamp(math.floor((tonumber(x) or 0) + 0.5), xRule.min, xRule.max)
    y = Clamp(math.floor((tonumber(y) or 0) + 0.5), yRule.min, yRule.max)
    return P.SetMany(ID, { [xKey] = x, [yKey] = y }) ~= false
end

local function NudgeHandle(handle, dx, dy)
    local xKey, yKey = OffsetKeys(handle._key)
    if not xKey then return false end
    return WriteOffsets(handle._key, P.Get(ID, xKey) + dx, P.Get(ID, yKey) + dy)
end

------------------------------------------------------------------ selection and focus
local function UpdateHint(ui)
    local handle = ui.hovered or ui.body._selectedHandle
    if handle then
        ui.hint:SetText(Tr(handle._label) .. "  -  " .. Tr("Drag or use arrows to move; click for settings."))
    else
        ui.hint:SetText(Tr(DEFAULT_HINT))
    end
end

local function SetArrowBindings(ui, enabled)
    if M.SetPreviewArrowBindings then M.SetPreviewArrowBindings(ui.body, enabled, ui.arrowBindings) end
end

local function Select(ui, handle)
    local body, chrome = ui.body, ui.chrome
    local previous = body._selectedHandle
    if previous and previous ~= handle then previous:EnableKeyboard(false) end
    body._selectedHandle = handle
    local active = handle and handle:IsShown() and body:IsShown() and not P.Combat() and true or false
    if handle then handle:EnableKeyboard(active) end
    SetArrowBindings(ui, active)
    if active and chrome and chrome.FocusKeyboardTarget then
        chrome.FocusKeyboardTarget(body, handle, false, { selectedField = "_selectedHandle" })
    elseif not active and chrome and chrome.ReleaseKeyboardCapture then
        chrome.ReleaseKeyboardCapture(body)
    end
    if M.PreviewSelectionBar and M.PreviewSelectionBar.Refresh then M.PreviewSelectionBar.Refresh(body) end
    UpdateHint(ui)
end

local function FocusSection(ui, section)
    local target = ui.sections[section]
    if target and W.FocusCollapsibleSection then W.FocusCollapsibleSection(target, { persist = true, flash = true }) end
end

-- Selects a preview element and opens the accordion that edits it.
local function Focus(ui, section, key, handle)
    ui.state.selected = { key = key, section = section }
    Select(ui, handle)
    if handle and ui.chrome and ui.chrome.ShowPreviewMoveCue then ui.chrome.ShowPreviewMoveCue(ui.body, handle) end
    ui.Paint()
    FocusSection(ui, section)
end

local function NudgeSelected(ui, owner, dx, dy)
    local body, chrome = ui.body, ui.chrome
    if owner ~= body or P.Combat() or not body:IsShown() then return false end
    if chrome and chrome.IsTextInputFocused and chrome.IsTextInputFocused() then return false end
    local keyboardFocus = GetCurrentKeyBoardFocus()
    if keyboardFocus and keyboardFocus:IsObjectType("EditBox") then return false end
    local handle = body._selectedHandle
    if not handle or not handle:IsShown() or not OffsetKeys(handle._key) then return false end
    local step = chrome and chrome.NudgeStep and chrome.NudgeStep()
        or (IsControlKeyDown() and 10 or IsShiftKeyDown() and 5 or 1)
    dx, dy = dx * step, dy * step
    if chrome and chrome.ShouldSkipDuplicateNudge and chrome.ShouldSkipDuplicateNudge(body, dx, dy) then return true end
    return NudgeHandle(handle, dx, dy)
end

local ARROW_DELTAS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }

-- Shared by the preview body and every handle (self.previewUI).
local function HandleKeyDown(self, key)
    local ui = self.previewUI
    local chrome = ui.chrome
    if chrome and chrome.ArrowKeyDown then
        return chrome.ArrowKeyDown(self, key, ui.arrowKeySpec)
    end
    local delta = ARROW_DELTAS[key]
    local moved = delta and NudgeSelected(ui, ui.body, delta[1], delta[2]) or false
    self:SetPropagateKeyboardInput(not moved)
    return moved
end

------------------------------------------------------------------ handles
local function HandleEnter(self)
    local ui = self.previewUI
    ui.hovered = self
    if self._hoverFill then self._hoverFill:Show() end
    UpdateHint(ui)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(Tr(self._label), 1, 1, 1)
    GameTooltip:AddLine(Tr("Drag or use arrows to move; Shift: 5, Ctrl: 10."), 0.82, 0.82, 0.82, true)
    GameTooltip:Show()
end

local function HandleLeave(self)
    local ui = self.previewUI
    if ui.hovered == self then ui.hovered = nil end
    if self._hoverFill then self._hoverFill:Hide() end
    UpdateHint(ui)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

-- Drags move the element's offsets; a click without movement selects it.
-- MouseDown/Up mirrors the UF/GF handles. OnDragStart/Stop remain as a
-- fallback on clients that deliver only the drag events to a Button.
local function StartDrag(self, mouseButton)
    if mouseButton and mouseButton ~= "LeftButton" then return end
    if type(self.dragX) == "number" or P.Combat() then return end
    self.dragX, self.dragY = GetCursorPosition()
    self:StartMoving()
end

local function CommitDrag(self, dx, dy)
    local kind = self.dragKind
    local rules = Suite.SuiteCatalog[ID].rules
    if kind == "map" then
        local x = Clamp(math.floor((P.Get(ID, "x") or 0) + dx + 0.5), rules.x.min, rules.x.max)
        local y = Clamp(math.floor((P.Get(ID, "y") or 0) + dy + 0.5), rules.y.min, rules.y.max)
        P.SetMany(ID, { x = x, y = y })
        self:ClearAllPoints()
        self:SetPoint("CENTER", self:GetParent(), "CENTER", 0, 0)
    else
        local key = self.dragConfigKey
        local xRule, yRule = rules[key .. "X"], rules[key .. "Y"]
        local x = Clamp(math.floor((P.Get(ID, key .. "X") or 0) + dx + 0.5), xRule.min, xRule.max)
        local y = Clamp(math.floor((P.Get(ID, key .. "Y") or 0) + dy + 0.5), yRule.min, yRule.max)
        P.SetMany(ID, { [key .. "X"] = x, [key .. "Y"] = y })
    end
end

local function StopDrag(self, mouseButton)
    if mouseButton and mouseButton ~= "LeftButton" then return end
    if type(self.dragX) ~= "number" then return end
    self:StopMovingOrSizing()
    local ui = self.previewUI
    local cx, cy = GetCursorPosition()
    local uiScale = self:GetEffectiveScale()
    if uiScale <= 0 then uiScale = 1 end
    local scale = ui.art.scale or 1
    local dx, dy = (cx - self.dragX) / uiScale / scale, (cy - self.dragY) / uiScale / scale
    self.dragX, self.dragY = nil, nil
    if not P.Combat() and math.abs(dx) + math.abs(dy) >= 2 then
        if M.PreviewHelpers and M.PreviewHelpers.NotePreviewElementMoved then
            M.PreviewHelpers.NotePreviewElementMoved()
        end
        CommitDrag(self, dx, dy)
    end
    Focus(ui, self.previewSection, self.previewKey, self)
end

local function DragHide(self)
    if type(self.dragX) == "number" then
        self:StopMovingOrSizing()
        self.dragX, self.dragY = nil, nil
    end
end

-- kind: "map" moves the map; "offset" moves `configKey`X/Y.
local function MakeDraggable(button, kind, configKey)
    button.dragKind, button.dragConfigKey = kind, configKey
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnMouseDown", StartDrag)
    button:SetScript("OnMouseUp", StopDrag)
    button:SetScript("OnDragStart", StartDrag)
    button:SetScript("OnDragStop", StopDrag)
    button:SetScript("OnHide", DragHide)
end

local function BindHandle(ui, button, key, label, section)
    button.previewUI = ui
    button.previewKey, button.previewSection = key, section
    button._key, button._label, button._color = key, label, HANDLE_COLOR
    button:SetScript("OnEnter", HandleEnter)
    button:SetScript("OnLeave", HandleLeave)
    button:SetScript("OnKeyDown", HandleKeyDown)
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(button, P.Meta(PAGE, ID, "preview." .. key, "action", PREVIEW_SECTION), label, "button")
    end
end

-- A clickable preview element that selects `key` and opens `section`.
local function Target(ui, key, label, section, w, h)
    local canvas = ui.canvas
    local button = CreateFrame("Button", nil, canvas)
    button:SetFrameLevel((tonumber((canvas:GetFrameLevel())) or 0) + 5)
    button:SetSize(w, h)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    local hover = button:CreateTexture(nil, "OVERLAY", nil, -1)
    hover:SetAllPoints(button)
    Tint(hover, HANDLE_COLOR[1], HANDLE_COLOR[2], HANDLE_COLOR[3], 0.18)
    hover:Hide()
    button._hoverFill = hover
    BindHandle(ui, button, key, label, section)
    local movable = OffsetKeys(key) ~= nil
    if movable then ui.handles[#ui.handles + 1] = button end
    button:SetScript("OnClick", function(self)
        Focus(ui, section, key, movable and self or nil)
    end)
    return button
end

------------------------------------------------------------------ build steps
local function BuildCanvas(ui, ctx, b)
    local section, toolbar, fixedRecord = W.FixedPreviewSection(ctx, b, {
        title = Tr("Minimap preview"), height = 180, gap = 8,
    })
    if not section then return false end
    ui.section, ui.toolbar, ui.fixedRecord = section, toolbar, fixedRecord
    ui.hint = T.Font(toolbar, "GameFontDisableSmall", Tr(DEFAULT_HINT), T.colors.muted)
    ui.hint:SetPoint("LEFT", toolbar, "LEFT", 145, 0)
    ui.hint:SetPoint("RIGHT", toolbar, "RIGHT", -145, 0)
    ui.hint:SetJustifyH("LEFT")
    ui.width = math.max(260, (section._msuf2Width or b.width or 720) - 28)

    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", 14, -40)
    body:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, -40)
    body:SetHeight(132)
    body:SetClipsChildren(true)
    body.previewUI = ui
    body._handleList = ui.handles
    ui.body = body

    local canvas = CreateFrame("Frame", nil, body)
    canvas:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    canvas:SetSize(ui.width, COMPACT_HEIGHT)
    local background = canvas:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetAllPoints(canvas)
    Tint(background, 0.07, 0.09, 0.12, 0.97)
    ui.chrome = M.PreviewHelpers
    if ui.chrome and ui.chrome.ApplyPreviewChrome then ui.chrome.ApplyPreviewChrome(canvas, "canvas", T) end
    ui.canvas = canvas
    ui.art = P.CreateMinimapPreviewArt(canvas)
    ui.map = ui.art.map
    return true
end

local function BuildKeyboard(ui)
    local body, chrome = ui.body, ui.chrome
    ui.arrowBindings = {
        ownerName = "MSUF_SuiteMinimapPreview_NudgeOwner",
        activeName = "MSUF_SuiteMinimapPreview_ActiveNudgeBox",
        buttonPrefix = "MSUF_SuiteMinimapPreview_Nudge",
        onClick = function(owner, dx, dy) return NudgeSelected(ui, owner, dx, dy) end,
    }
    ui.arrowKeySpec = {
        owner = function() return body end,
        selectedField = "_selectedHandle",
        nudge = ui.arrowBindings.onClick,
    }
    body:EnableKeyboard(true)
    body:SetPropagateKeyboardInput(true)
    body:SetScript("OnKeyDown", HandleKeyDown)
    body:SetScript("OnHide", function(self)
        SetArrowBindings(ui, false)
        if chrome and chrome.ReleaseKeyboardCapture then
            chrome.ReleaseKeyboardCapture(self)
        else
            self:SetPropagateKeyboardInput(true)
        end
        local selected = self._selectedHandle
        if selected then selected:EnableKeyboard(false) end
    end)
    body:SetScript("OnShow", function(self)
        local selected = self._selectedHandle
        if selected and selected:IsShown() and not P.Combat() then
            selected:EnableKeyboard(true)
            SetArrowBindings(ui, true)
            if chrome and chrome.FocusKeyboardTarget then
                chrome.FocusKeyboardTarget(self, selected, false, { selectedField = "_selectedHandle" })
            end
        end
    end)
end

-- The map itself, the thin rim target below it and the four artwork edges.
local function BuildMapTargets(ui)
    local map = ui.map
    BindHandle(ui, map, "map", "Minimap", "layout")
    ui.handles[#ui.handles + 1] = map
    map:SetScript("OnClick", function(self) Focus(ui, "layout", "map", self) end)
    MakeDraggable(map, "map")

    -- Selectable map and border use separate hit areas; texts and icons sit above them.
    ui.style = Target(ui, "style", "Shape, border and shadow", "shape", 1, 8)
    ui.style:SetPoint("TOP", map, "BOTTOM")

    -- Four narrow hit areas follow the visible rim. The centre stays clickable
    -- as the map, while any edge opens the artwork controls directly.
    ui.ornamentEdges = {}
    for index, point in ipairs(ORNAMENT_EDGES) do
        local key = index == 1 and "ornament" or ("ornament_" .. point:lower())
        local edge = Target(ui, key, "Decorative border", "style_art", index == 1 and 1 or 16, 16)
        edge:SetPoint("CENTER", map, point)
        MakeDraggable(edge, "offset", "style")
        ui.ornamentEdges[index] = edge
    end
end

local function BuildTextTargets(ui)
    local canvasLevel = tonumber((ui.canvas:GetFrameLevel())) or 0
    ui.textItems = {}
    for _, spec in ipairs(TEXTS) do
        local name = spec[1]
        local key = "info" .. name
        local button = Target(ui, key, name, "info_" .. name:lower(), 100, 20)
        local box = button:CreateTexture(nil, "BACKGROUND")
        box:SetPoint("CENTER", button, "CENTER")
        box:SetSize(100, 19)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetAllPoints(button)
        label:SetJustifyV("MIDDLE")
        -- The location field can be 220px wide while its visible zone name is
        -- only a few glyphs. Keep its click target on the rendered text so it
        -- cannot steal FPS/latency clicks, or be stolen by their wide fields.
        if name == "Location" then button:SetFrameLevel(canvasLevel + 7) end
        MakeDraggable(button, "offset", key)
        ui.textItems[#ui.textItems + 1] = { spec = spec, button = button, box = box, label = label }
    end
end

local function AddDrawerDots(button)
    for index = 1, 4 do
        local dot = button:CreateTexture(nil, "ARTWORK")
        dot:SetSize(4, 4)
        dot:SetPoint("CENTER", button, "CENTER", index % 2 == 1 and -4 or 4, index <= 2 and 4 or -4)
        Tint(dot, 0.9, 0.9, 0.9, 1)
    end
end

-- A simple open book for the "Simple book" landing icon.
local function AddBook(button)
    local book = {}
    for index = 1, 3 do book[index] = button:CreateTexture(nil, "OVERLAY") end
    book[1]:SetPoint("RIGHT", button, "CENTER", -1, 0)
    book[2]:SetPoint("LEFT", button, "CENTER", 1, 0)
    book[3]:SetPoint("CENTER", button, "CENTER")
    book[1]:SetSize(7, 13)
    book[2]:SetSize(7, 13)
    book[3]:SetSize(2, 15)
    Tint(book[1], 0.91, 0.81, 0.56, 1)
    Tint(book[2], 0.98, 0.92, 0.74, 1)
    Tint(book[3], 0.35, 0.28, 0.18, 1)
    button.previewBook = book
end

local function IconTarget(ui, spec)
    local key = spec[1]
    local button = Target(ui, key, spec[2], spec[3], 24, 24)
    local backdrop = button:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints(button)
    Tint(backdrop, 0.025, 0.035, 0.045, 0.8)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    SetIcon(icon, spec[6], spec[7])
    button.previewIcon = icon
    if key == "drawer" then
        icon:Hide()
        AddDrawerDots(button)
    elseif key == "folio" then
        AddBook(button)
    elseif key == "difficulty" then
        button.previewNative = {
            background = button:CreateTexture(nil, "BACKGROUND"),
            border = button:CreateTexture(nil, "BORDER"),
            emblem = button:CreateTexture(nil, "ARTWORK"),
            glyph = button:CreateTexture(nil, "OVERLAY"),
            text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
        }
    end
    local edge = button:CreateTexture(nil, "OVERLAY")
    edge:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT")
    edge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT")
    edge:SetHeight(2)
    Tint(edge, 0.6, 0.74, 0.83, 0.65)
    MakeDraggable(button, "offset", OffsetPrefix(key))
    return { spec = spec, button = button, backdrop = backdrop, edge = edge }
end

local function BuildIconTargets(ui)
    ui.iconItems = {}
    for _, spec in ipairs(ICONS) do
        ui.iconItems[#ui.iconItems + 1] = IconTarget(ui, spec)
    end
    ui.zoomItems = {}
    for _, spec in ipairs({ { "zoomIn", "Zoom in", "+" }, { "zoomOut", "Zoom out", "-" } }) do
        local button = Target(ui, spec[1], spec[2], "behavior", 20, 20)
        local back = button:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints(button)
        Tint(back, 0.035, 0.05, 0.065, 0.9)
        local sign = T.Font(button, "GameFontHighlightSmall", spec[3], T.colors.text)
        sign:SetPoint("CENTER", button, "CENTER")
        MakeDraggable(button, "offset", spec[1])
        ui.zoomItems[#ui.zoomItems + 1] = button
    end
    ui.compass = Target(ui, "compass", "Compass and rotation", "behavior", 17, 17)
    ui.compass:SetPoint("TOP", ui.map, "TOP", 0, -2)
    local north = T.Font(ui.compass, "GameFontHighlightSmall", "N", T.colors.text)
    north:SetPoint("CENTER", ui.compass, "CENTER")
end

local function FitZoom(ui)
    local size = math.max(100, P.Get(ID, "size") or 190)
    return Clamp(math.min((ui.width - 160) / size, 250 / size), 0.2, 1)
end

-- Center guides, zoom readout and the zoom buttons.
local function BuildCanvasTools(ui)
    local canvas, map = ui.canvas, ui.map
    ui.guides = {}
    for i = 1, 2 do
        local line = canvas:CreateTexture(nil, "OVERLAY")
        Tint(line, 0.65, 0.78, 0.87, 0.2)
        line:SetPoint("CENTER", map, "CENTER")
        ui.guides[i] = line
    end
    ui.guides[1]:SetSize(1, 300)
    ui.guides[2]:SetSize(500, 1)
    ui.zoomLabel = T.Font(canvas, "GameFontHighlightSmall", "100%", T.colors.muted)
    ui.zoomLabel:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -56, -12)

    local function ZoomButton(label, offset, width, zoom)
        local button = T.Button(canvas, label, width, 23)
        button:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", offset, -7)
        button:SetScript("OnClick", function()
            ui.state.zoom = zoom()
            ui.Paint()
        end)
    end
    ZoomButton("-", -96, 28, function() return Clamp(ui.state.zoom - 0.1, 0.2, 1.5) end)
    ZoomButton("+", -12, 28, function() return Clamp(ui.state.zoom + 0.1, 0.2, 1.5) end)
    ZoomButton("Fit", -130, 35, function() return FitZoom(ui) end)
    ZoomButton("1:1", -168, 33, function() return 1 end)
end

local function BuildSelectionBar(ui)
    local body = ui.body
    ui.selection = M.PreviewSelectionBar.Create(body, {
        Tr = Tr,
        Theme = function() return T end,
        HandleList = function() return ui.handles end,
        HandleLabel = function(handle) return handle._label end,
        IsPlaced = function(handle) return handle.IsShown and handle:IsShown() or false end,
        ReadOffsets = function(_, handle)
            local xKey, yKey = OffsetKeys(handle._key)
            return xKey and P.Get(ID, xKey) or 0, yKey and P.Get(ID, yKey) or 0
        end,
        WriteOffsets = function(_, handle, x, y) return WriteOffsets(handle._key, x, y) end,
        NudgeDelta = function(_, dx, dy)
            local handle = body._selectedHandle
            if not handle then return false end
            return NudgeHandle(handle, dx, dy)
        end,
        ResetOffsets = function(_, handle)
            local xKey, yKey = OffsetKeys(handle._key)
            if not xKey then return false end
            local rules = Suite.SuiteCatalog[ID].rules
            return WriteOffsets(handle._key, rules[xKey].default, rules[yKey].default)
        end,
        OpenSettings = function(_, handle)
            if handle then FocusSection(ui, handle.previewSection) end
        end,
        SelectHandle = function(_, handle)
            if not handle then return false end
            Focus(ui, handle.previewSection, handle.previewKey, handle)
            return true
        end,
        UpdateHint = function() end,
    })
    ui.selection:SetPoint("TOPLEFT", ui.canvas, "BOTTOMLEFT", 0, -8)
    ui.selection:SetPoint("TOPRIGHT", ui.canvas, "BOTTOMRIGHT", 0, -8)
end

-- Layer chips: left-click toggles a layer, right-click opens its settings.
local function BuildLayerChips(ui)
    local width = ui.width
    local chips = CreateFrame("Frame", nil, ui.body)
    chips:SetPoint("TOPLEFT", ui.selection, "BOTTOMLEFT", 0, -8)
    local perRow = math.max(1, math.floor((width - 63) / 78))
    ui.chipRows = math.ceil(#LAYERS / perRow)
    chips:SetSize(width, 8 + ui.chipRows * 25)
    local layersTitle = T.Font(chips, "GameFontHighlightSmall", "LAYERS", T.colors.muted)
    layersTitle:SetPoint("TOPLEFT", chips, "TOPLEFT", 7, -8)
    ui.layerButtons = {}
    for i, entry in ipairs(LAYERS) do
        local layer = entry[1]
        local button = T.Button(chips, entry[2], 76, 20)
        local row, col = math.floor((i - 1) / perRow), (i - 1) % perRow
        button:SetPoint("TOPLEFT", chips, "TOPLEFT", 61 + col * 78, -2 - row * 25)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" and LAYER_SECTIONS[layer] then
                Focus(ui, LAYER_SECTIONS[layer], layer)
            else
                ui.state.layers[layer] = not ui.LayerOn(layer)
                ui.Paint()
            end
        end)
        if M.RegisterControlMetadata then
            M.RegisterControlMetadata(button, P.Meta(PAGE, ID, "preview.layer." .. layer, "action", PREVIEW_SECTION),
                Tr("%s preview layer"):format(Tr(entry[2])), "button")
        end
        ui.layerButtons[i] = button
    end
    ui.chips = chips
end

local function Paint(ui)
    local config = S.Config(ID)
    local state = ui.state
    local base = state.compact and math.min(state.zoom, 94 / math.max(100, config.size or 190))
        or Clamp(state.zoom, 0.2, 1.5)
    ui.art:Paint(config, base, ui.LayerOn)
    ui.style:SetWidth(ui.art.width + (config.borderSize or 0) * base * 2)
    PaintElements(ui, config)
    ui.zoomLabel:SetText(string.format("%d%%", math.floor(base * 100 + 0.5)))
    for i, entry in ipairs(LAYERS) do ui.layerButtons[i]:SetAlpha(ui.LayerOn(entry[1]) and 1 or 0.42) end
    local selected = ui.body._selectedHandle
    if selected and not selected:IsShown() then Select(ui, nil) end
    M.PreviewSelectionBar.Refresh(ui.body)
end

------------------------------------------------------------------ fixed preview wiring
local function BuildExpander(ui, ctx)
    local body = ui.body
    function body:ApplyCompactPreviewPresentation(compact)
        ui.state.compact = compact == true
        ui.canvas:SetHeight(ui.state.compact and COMPACT_HEIGHT or EXPANDED_HEIGHT)
        M.PreviewSelectionBar.SetShown(body, not ui.state.compact)
        ui.chips:SetShown(not ui.state.compact)
        ui.Paint()
    end
    body:ApplyCompactPreviewPresentation(true)
    local expandedHeight = EXPANDED_HEIGHT + 8 + 24 + 8 + (8 + ui.chipRows * 25) + 8
    local expander = W.AttachFixedPreviewExpander(ui.section, ui.toolbar, body, {
        pageKey = ctx.key,
        wrapper = ctx.wrapper,
        compactHeight = 132,
        compactTop = -40,
        expandedHeight = expandedHeight,
        expandedTop = -40,
        expandedSectionHeight = 40 + expandedHeight + 8,
        onStateChanged = ui.Paint,
    })
    if ui.fixedRecord then
        ui.fixedRecord.onActivate = function()
            if expander and M.ShouldExpandFixedPreview and M.ShouldExpandFixedPreview() then
                expander:Open("SUITE_MINIMAP_PREVIEW_ACTIVE")
            end
            ui.Paint()
        end
    end
end

-- The docked minimap preview: a static canvas with selectable, draggable
-- elements whose offsets write the minimap settings.
function P.BuildMinimapPreview(ctx, b, sections)
    local ui = { sections = sections, handles = {} }
    if not BuildCanvas(ui, ctx, b) then return end
    local initialSize = math.max(100, P.Get(ID, "size") or 190)
    ui.state = {
        selected = nil,
        zoom = Clamp(math.min((ui.width - 160) / initialSize, 250 / initialSize), 0.2, 1),
        compact = true,
        layers = {},
    }
    for _, entry in ipairs(LAYERS) do ui.state.layers[entry[1]] = true end
    ui.state.layers.guides = false
    ui.state.layers.hidden = false
    ui.LayerOn = function(key) return ui.state.layers[key] ~= false end
    ui.Paint = function() Paint(ui) end

    BuildKeyboard(ui)
    BuildMapTargets(ui)
    BuildTextTargets(ui)
    BuildIconTargets(ui)
    BuildCanvasTools(ui)
    BuildSelectionBar(ui)
    BuildLayerChips(ui)
    ui.style:SetScript("OnClick", function() Focus(ui, "shape", "style") end)
    BuildExpander(ui, ctx)
    M.TrackRefresh(ctx, ui.Paint)
end
