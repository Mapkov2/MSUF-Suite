local _, P = ...
local Suite, S, W, M, T, Tr = P.Suite, P.S, P.W, P.M, P.T, P.Tr
local ID, PAGE = "minimap", "suite_minimap"
local PREVIEW_SECTION = "suite_minimap_preview"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ANCHORS = Suite.MinimapAnchorPoints or { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local ROWS = Suite.MinimapRowGeometry or {}
local DEFAULT_ROW = { "TOPRIGHT", "TOPLEFT", -1, 0, 0, -1 }
local OUTLINES = { "", "OUTLINE", "THICKOUTLINE", "MONOCHROME,OUTLINE" }
local COMPACT_HEIGHT, EXPANDED_HEIGHT = 112, 316
local HANDLE_COLOR = { 0.30, 0.74, 1.00 }
local DEFAULT_HINT = "Click to select; drag or use arrow keys; edit exact X/Y below."
-- { name, sample text, key } of every info text.
local TEXTS = {
    { "Clock", "12:34", "clock" }, { "FPS", "60 FPS", "fps" }, { "Latency", "23 ms", "latency" },
    { "Coordinates", "42.1, 56.7", "coordinates" }, { "Durability", "100%", "durability" },
    { "Location", "Current zone", "location" }, { "Weather", "Clear", "weather" },
    { "Difficulty", "5H", "difficulty" },
}
-- { key, label, section, visibility setting (false: native state), layer, atlas, file }
local ICONS = {
    { "tracking", "Tracking", "elements", "showTracking", "blizzard", "ui-hud-minimap-tracking-up", "Interface\\Minimap\\Tracking\\None" },
    { "calendar", "Calendar", "elements", "showCalendar", "blizzard", "ui-hud-minimap-calendar-up", "Interface\\Calendar\\UI-Calendar-Button" },
    { "mail", "Mail", "elements", "showMail", "blizzard", "ui-hud-minimap-mail-up", "Interface\\Minimap\\Tracking\\Mailbox" },
    { "crafting", "Crafting", "elements", "showCrafting", "blizzard", "UI-HUD-Minimap-CraftingOrder-Up", "Interface\\Icons\\INV_Hammer_20" },
    { "battlefield", "Battlefield", "elements", false, "blizzard", nil, "Interface\\Icons\\INV_Banner_02" },
    { "queue", "Queue", "elements", false, "blizzard", nil, "Interface\\Icons\\INV_Misc_GroupLooking" },
    { "worldMap", "WorldMap", "elements", false, "blizzard", nil, "Interface\\Icons\\INV_Misc_Map_01" },
    { "compartment", "Compartment", "elements", "showCompartment", "blizzard", "ui-hud-minimap-button", "Interface\\Buttons\\UI-OptionsButton" },
    { "difficulty", "Difficulty", "elements", "showDifficulty", "blizzard", nil, "Interface\\GroupFrame\\UI-Group-LeaderIcon" },
    { "folio", "Omnium Folio", "landing", "showLanding", "folio", "GarrLanding-MinimapIcon-Alliance-Up", "Interface\\Icons\\INV_Misc_Book_09" },
    { "drawer", "Addon drawer", "addons", "collectButtons", "addons", nil, "Interface\\Buttons\\UI-OptionsButton" },
}
local ICON_KEYS = {}
for _, spec in ipairs(ICONS) do ICON_KEYS[spec[1]] = true end
local LAYERS = {
    { "map", "Map" }, { "border", "Border" }, { "ornament", "Artwork" }, { "glow", "Glow" },
    { "backdrop", "Plate" }, { "shadow", "Shadow" },
    { "text", "Texts" }, { "blizzard", "Blizzard" }, { "folio", "Folio" },
    { "addons", "Addons" }, { "guides", "Guides" }, { "hidden", "Hidden" },
}
-- Right-clicking a layer chip opens the accordion that styles it.
local LAYER_SECTIONS = { map = "layout", border = "shape", shadow = "shape", ornament = "style_art",
    glow = "style_glow", backdrop = "style_backdrop", text = "info_colors", blizzard = "elements",
    folio = "landing", addons = "addons" }
local ORNAMENT_EDGES = { "TOP", "BOTTOM", "LEFT", "RIGHT" }

local function Clamp(value, low, high) return math.max(low, math.min(high, value)) end
local function Public(value) return not S.Public or S.Public(value) end
local function PublicNumber(value) return Public(value) and type(value) == "number" end
local function Tint(texture, r, g, b, a) texture:SetColorTexture(r, g, b, a) end

local function PlayerClassColor(r, g, b)
    if type(UnitClass) ~= "function" or not S.ClassRGB then return r, g, b end
    local _, token = UnitClass("player")
    if not Public(token) then return r, g, b end
    local cr, cg, cb = S.ClassRGB(token)
    if cr then return cr, cg, cb end
    return r, g, b
end

------------------------------------------------------------------ samples and native art
local function Sample(name, config)
    if name == "Clock" then
        if type(GetGameTime) == "function" then
            local hour, minute = GetGameTime()
            if PublicNumber(hour) and PublicNumber(minute) then
                return string.format("%02d:%02d", hour, minute)
            end
        end
        return "12:34"
    end
    if name == "Location" then
        if type(GetZoneText) == "function" then
            local zone = GetZoneText()
            if Public(zone) and type(zone) == "string" and zone ~= "" then return zone end
        end
        return Tr("Current zone")
    end
    if name == "Durability" then
        return (config.infoDurabilityIcon and "|TInterface\\Durability\\UI-Durability-Icons:12:10|t " or "") .. "100%"
    end
    for _, spec in ipairs(TEXTS) do
        if spec[1] == name then return spec[2] end
    end
    return name
end

-- GetAtlasInfo returns nil for an atlas this client does not have.
local function SetIcon(texture, atlas, path)
    local getAtlasInfo = type(C_Texture) == "table" and C_Texture.GetAtlasInfo
    if atlas and type(getAtlasInfo) == "function" then
        local info = getAtlasInfo(atlas)
        if info and Public(info) then
            texture:SetAtlas(atlas)
            return
        end
    end
    texture:SetTexture(path or WHITE)
end

-- Offset of a native region's center from its frame's center, in preview units.
local function CenterOffset(frame, source, scale)
    local fx, fy = frame:GetCenter()
    local sx, sy = source:GetCenter()
    local x = PublicNumber(fx) and PublicNumber(sx) and (sx - fx) * scale or 0
    local y = PublicNumber(fy) and PublicNumber(sy) and (sy - fy) * scale or 0
    return x, y
end

-- Mirror the active Blizzard difficulty banner instead of drawing a crown.
-- Its artwork and text change with instance type, guild group and client.
local function CopyNativeTexture(target, source, frame, scale, nativeScale)
    if not source then
        target:Hide()
        return false
    end
    local shown = source:IsShown()
    if not Public(shown) or not shown then
        target:Hide()
        return false
    end
    local atlas = source.GetAtlas and source:GetAtlas()
    if Public(atlas) and type(atlas) == "string" and atlas ~= "" then
        target:SetAtlas(atlas)
    else
        local file = source.GetTexture and source:GetTexture()
        if not Public(file) or type(file) ~= "string" and type(file) ~= "number" then
            target:Hide()
            return false
        end
        target:SetTexture(file)
    end
    local left, right, top, bottom = source:GetTexCoord()
    if PublicNumber(left) and PublicNumber(right) and PublicNumber(top) and PublicNumber(bottom) then
        target:SetTexCoord(left, right, top, bottom)
    end
    local r, g, b, a = source:GetVertexColor()
    if PublicNumber(r) and PublicNumber(g) and PublicNumber(b) and Public(a) then
        target:SetVertexColor(r, g, b, type(a) == "number" and a or 1)
    end
    local alpha = source:GetAlpha()
    if PublicNumber(alpha) then target:SetAlpha(alpha) end
    local width, height = source:GetSize()
    if not PublicNumber(width) or not PublicNumber(height) then
        target:Hide()
        return false
    end
    target:SetSize(width * nativeScale * scale, height * nativeScale * scale)
    target:ClearAllPoints()
    target:SetPoint("CENTER", target:GetParent(), "CENTER", CenterOffset(frame, source, scale))
    target:Show()
    return true
end

local function CopyNativeText(target, source, frame, scale, nativeScale)
    if not source then
        target:Hide()
        return
    end
    local shown = source:IsShown()
    if not Public(shown) or not shown then
        target:Hide()
        return
    end
    local font, size, flags = source:GetFont()
    if Public(font) and Public(size) and Public(flags) and type(font) == "string" and type(size) == "number" then
        target:SetFont(font, math.max(6, size * nativeScale * scale), flags)
    end
    target:SetText(source:GetText())
    local r, g, b, a = source:GetTextColor()
    if PublicNumber(r) and PublicNumber(g) and PublicNumber(b) and Public(a) then
        target:SetTextColor(r, g, b, type(a) == "number" and a or 1)
    end
    target:ClearAllPoints()
    target:SetPoint("CENTER", target:GetParent(), "CENTER", CenterOffset(frame, source, scale))
    target:Show()
end

local function RowPosition(button, map, rowIndex, index, config, scale, prefix)
    local row = ROWS[rowIndex] or ROWS[1] or DEFAULT_ROW
    local distance = ((config.elementDistance or 0) + (config.borderSize or 0)) * scale
    local step = ((config.elementSize or 21) + (config.elementSpacing or 0)) * scale
    button:ClearAllPoints()
    button:SetPoint(row[1], map, row[2],
        row[3] * distance + row[5] * index * step + (config[prefix .. "X"] or 0) * scale,
        row[4] * distance + row[6] * index * step + (config[prefix .. "Y"] or 0) * scale)
end

-- Anchors 10 and 11 sit above and below the map; returns the text justify.
local function TextPosition(button, map, anchor, x, y, scale, border)
    button:ClearAllPoints()
    if anchor == 10 then
        button:SetPoint("BOTTOM", map, "TOP", x * scale, y * scale + border)
        return "CENTER"
    end
    if anchor == 11 then
        button:SetPoint("TOP", map, "BOTTOM", x * scale, y * scale - border)
        return "CENTER"
    end
    local point = ANCHORS[anchor] or "CENTER"
    button:SetPoint(point, map, point, x * scale, y * scale)
    return point:find("LEFT", 1, true) and "LEFT" or point:find("RIGHT", 1, true) and "RIGHT" or "CENTER"
end

------------------------------------------------------------------ offsets
-- Setting prefix of a preview element's X/Y offsets (nil: not movable).
local function OffsetPrefix(key)
    if not key then return nil end
    if key:find("^info") then return key end
    if key == "folio" then return "landing" end
    if key == "difficulty" then return "difficultyButton" end
    if key == "drawer" or key == "zoomIn" or key == "zoomOut" then return key end
    if key == "ornament" or key:find("^ornament_") then return "style" end
    if ICON_KEYS[key] then return "button" .. key:sub(1, 1):upper() .. key:sub(2) end
end

local function OffsetKeys(key)
    if key == "map" then return "x", "y" end
    local prefix = OffsetPrefix(key)
    if prefix then return prefix .. "X", prefix .. "Y" end
end

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
    local keyboardFocus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if keyboardFocus and keyboardFocus.IsObjectType and keyboardFocus:IsObjectType("EditBox") then return false end
    local handle = body._selectedHandle
    if not handle or not handle:IsShown() or not OffsetKeys(handle._key) then return false end
    local step = chrome and chrome.NudgeStep and chrome.NudgeStep()
        or (IsControlKeyDown and IsControlKeyDown() and 10 or IsShiftKeyDown and IsShiftKeyDown() and 5 or 1)
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
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(not moved) end
    return moved
end

------------------------------------------------------------------ handles
local function HandleEnter(self)
    local ui = self.previewUI
    ui.hovered = self
    if self._hoverFill then self._hoverFill:Show() end
    UpdateHint(ui)
    if GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Tr(self._label), 1, 1, 1)
        GameTooltip:AddLine(Tr("Drag or use arrows to move; Shift: 5, Ctrl: 10."), 0.82, 0.82, 0.82, true)
        GameTooltip:Show()
    end
end

local function HandleLeave(self)
    local ui = self.previewUI
    if ui.hovered == self then ui.hovered = nil end
    if self._hoverFill then self._hoverFill:Hide() end
    UpdateHint(ui)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

-- Drags move the element's offsets; a click without movement selects it.
-- MouseDown/Up mirrors the UF/GF handles. OnDragStart/Stop remain as a
-- fallback on clients that deliver only the drag events to a Button.
local function StartDrag(self, mouseButton)
    if mouseButton and mouseButton ~= "LeftButton" then return end
    if type(self.dragX) == "number" or P.Combat() or type(GetCursorPosition) ~= "function" then return end
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
    local uiScale = self.GetEffectiveScale and self:GetEffectiveScale() or 1
    if type(uiScale) ~= "number" or uiScale <= 0 then uiScale = 1 end
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
    if body.SetClipsChildren then body:SetClipsChildren(true) end
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
    if body.SetPropagateKeyboardInput then body:SetPropagateKeyboardInput(true) end
    body:SetScript("OnKeyDown", HandleKeyDown)
    body:SetScript("OnHide", function(self)
        SetArrowBindings(ui, false)
        if chrome and chrome.ReleaseKeyboardCapture then
            chrome.ReleaseKeyboardCapture(self)
        elseif self.SetPropagateKeyboardInput then
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
                entry[2] .. " preview layer", "button")
        end
        ui.layerButtons[i] = button
    end
    ui.chips = chips
end

------------------------------------------------------------------ painting
local function PaintText(ui, config, item)
    local name, prefix = item.spec[1], "info" .. item.spec[1]
    local on = config[prefix] == true
    local shown = ui.LayerOn("text") and (on or ui.LayerOn("hidden"))
    local button = item.button
    button:SetShown(shown)
    if not shown then return end
    local scale = ui.art.scale
    local size = config[prefix .. "Size"] or 12
    local path = S.ResolveFont and S.ResolveFont(config[prefix .. "Font"] or "") or STANDARD_TEXT_FONT
    P.StylePreviewFont(item.label, path, math.max(8, size * scale), OUTLINES[config[prefix .. "Outline"]] or "OUTLINE",
        config[prefix .. "Rendering"], config[prefix .. "Shadow"],
        config[prefix .. "ShadowOpacity"], config[prefix .. "ShadowDistance"])
    local sample = Sample(name, config)
    item.label:SetText(sample)
    -- The hit area hugs the rendered text, up to the configured field width.
    local configuredWidth = math.max(24, (config[prefix .. "Width"] or 100) * scale)
    local measured = item.label.GetStringWidth and item.label:GetStringWidth()
    if type(measured) ~= "number" or measured <= 0 then
        measured = #sample * size * scale * 0.62
    end
    local hitWidth = math.min(configuredWidth, math.max(24, measured + 8))
    button:SetSize(hitWidth, math.max(18, (size + 8) * scale))
    item.box:SetWidth(hitWidth)
    local justify = TextPosition(button, ui.map, config[prefix .. "Anchor"], config[prefix .. "X"] or 0,
        config[prefix .. "Y"] or 0, scale, (config.borderSize or 0) * scale)
    item.label:SetJustifyH(justify)
    local r, g, b = P.RGB(config[prefix .. "Color"] or "ffffff")
    if config[prefix .. "ClassColor"] then r, g, b = PlayerClassColor(r, g, b) end
    item.label:SetTextColor(r or 1, g or 1, b or 1)
    local boxed = name ~= "Difficulty" and config[prefix .. "Box"] == 2
    local br, bg, bb = P.RGB(config.borderColor)
    Tint(item.box, br, bg, bb, 0.85)
    item.box:SetShown(boxed or ui.state.selected and ui.state.selected.key == prefix)
    button:SetAlpha(on and 1 or 0.38)
end

-- Whether an icon's element would show in game (the preview may still show
-- it dimmed through the Hidden layer).
local function IconWanted(config, spec)
    local key = spec[1]
    if key == "difficulty" then
        local wanted = config.showDifficulty and not config.infoDifficulty
        if S.MinimapElementAvailable then wanted = wanted and S.MinimapElementAvailable("Difficulty") end
        if S.MinimapElementPreviewShown and S.MinimapElementPreviewShown("Difficulty") == false then wanted = false end
        return wanted
    end
    local wanted = key == "folio" and config.showLanding ~= 3 or spec[4] and config[spec[4]] == true
    if key == "drawer" and Suite.Client.IsAddOnLoaded("MinimapButtonButton") then wanted = false end
    if spec[4] == false then
        wanted = S.MinimapElementPreviewShown and S.MinimapElementPreviewShown(spec[2]) == true or false
    end
    if spec[3] == "elements" and S.MinimapElementPreviewShown and S.MinimapElementPreviewShown(spec[2]) == false then
        wanted = false
    end
    return wanted
end

-- Mirrors Blizzard's difficulty banner, or falls back to the plain icon.
local function PaintDifficulty(ui, config, item, size)
    local button, parts, scale = item.button, item.button.previewNative, ui.art.scale
    local native, mode
    if S.MinimapDifficultyPreviewSource then native, mode = S.MinimapDifficultyPreviewSource() end
    local nativeScale = (config.elementSize or 21) / 21
    local mirrored = false
    if native and mode and mode.Background and mode.Border then
        local width, height = native:GetSize()
        if PublicNumber(width) and PublicNumber(height) and width > 0 and height > 0 then
            button:SetSize(width * nativeScale * scale, height * nativeScale * scale)
        end
        local content = mode.Instance or mode
        local glyph = mode.ChallengeModeTexture
        if not glyph and type(content.DifficultyTextures) == "table" then
            for i = 1, #content.DifficultyTextures do
                local candidate = content.DifficultyTextures[i]
                local shown = candidate:IsShown()
                if Public(shown) and shown then
                    glyph = candidate
                    break
                end
            end
        end
        local background = CopyNativeTexture(parts.background, mode.Background, native, scale, nativeScale)
        local border = CopyNativeTexture(parts.border, mode.Border, native, scale, nativeScale)
        mirrored = background or border
        CopyNativeTexture(parts.emblem, mode.Emblem, native, scale, nativeScale)
        CopyNativeTexture(parts.glyph, glyph, native, scale, nativeScale)
        CopyNativeText(parts.text, content.Text, native, scale, nativeScale)
    end
    if not mirrored then
        for _, part in pairs(parts) do part:Hide() end
        button:SetSize(size, size)
    end
    button.previewIcon:SetShown(not mirrored)
    item.backdrop:SetShown(not mirrored)
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", ui.map, "TOPRIGHT", (-2 + (config.difficultyButtonX or 0)) * scale,
        (-2 + (config.difficultyButtonY or 0)) * scale)
end

local function PaintFolio(ui, config, button, size)
    local simpleBook = config.landingIcon == 2
    button.previewIcon:SetShown(not simpleBook)
    for _, part in ipairs(button.previewBook) do part:SetShown(simpleBook) end
    local scale = ui.art.scale
    button:SetSize(size * 0.8, size * 0.8)
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", ui.map, "BOTTOMLEFT", (2 + (config.landingX or 0)) * scale,
        (2 + (config.landingY or 0)) * scale)
end

local function PaintIcons(ui, config)
    local rowCount = 0
    local scale = ui.art.scale
    local size = Clamp((config.elementSize or 21) * scale, 12, 60)
    local selectedKey = ui.state.selected and ui.state.selected.key
    for _, item in ipairs(ui.iconItems) do
        local spec, button = item.spec, item.button
        local key = spec[1]
        local wanted = IconWanted(config, spec)
        button:SetShown(ui.LayerOn(spec[5]) and (wanted or ui.LayerOn("hidden")))
        button:SetAlpha(wanted and 1 or 0.38)
        button:SetSize(size, size)
        if key == "folio" then
            PaintFolio(ui, config, button, size)
        elseif key == "difficulty" then
            PaintDifficulty(ui, config, item, size)
        elseif key == "drawer" then
            local index = config.drawerRow == config.elementRow and rowCount or 0
            RowPosition(button, ui.map, config.drawerRow, index, config, scale, "drawer")
        else
            RowPosition(button, ui.map, config.elementRow, rowCount, config, scale, OffsetPrefix(key))
            if wanted then rowCount = rowCount + 1 end
        end
        local chosen = selectedKey == key
        if key == "difficulty" then item.edge:SetShown(chosen) end
        if chosen then
            Tint(item.edge, 0.28, 0.74, 1, 1)
            Tint(item.backdrop, 0.11, 0.3, 0.43, 0.9)
        else
            Tint(item.edge, 0.6, 0.74, 0.83, 0.65)
            Tint(item.backdrop, 0.025, 0.035, 0.045, 0.9)
        end
    end
end

local function PaintOrnament(ui, config)
    local art = ui.art
    local rim = math.max(12, ((config.styleScale or 100) / 100 - 1) * art.width)
    local shown = ui.LayerOn("ornament") and (config.styleTexture ~= 1 or ui.LayerOn("hidden"))
    local edges = ui.ornamentEdges
    edges[1]:SetWidth(art.width + rim)
    edges[2]:SetWidth(art.width + rim)
    edges[3]:SetHeight(art.height + rim)
    edges[4]:SetHeight(art.height + rim)
    for index, point in ipairs(ORNAMENT_EDGES) do
        local edge = edges[index]
        edge:ClearAllPoints()
        edge:SetPoint("CENTER", ui.map, point, (config.styleX or 0) * art.scale, (config.styleY or 0) * art.scale)
        edge:SetShown(shown)
    end
end

local function PaintMapControls(ui, config)
    local scale = ui.art.scale
    local mode = config.zoomButtons or 1
    for index, button in ipairs(ui.zoomItems) do
        button:SetShown(ui.LayerOn("blizzard") and (mode ~= 3 or ui.LayerOn("hidden")))
        button:SetAlpha(mode == 2 and 1 or mode == 1 and 0.62 or 0.38)
        local prefix = index == 1 and "zoomIn" or "zoomOut"
        button:ClearAllPoints()
        button:SetPoint("BOTTOMRIGHT", ui.map, "BOTTOMRIGHT",
            (-2 + (config[prefix .. "X"] or 0)) * scale,
            ((index == 1 and 27 or 3) + (config[prefix .. "Y"] or 0)) * scale)
    end
    local rotating = config.rotate == 2
    if config.rotate == 1 and type(GetCVarBool) == "function" then
        local value = GetCVarBool("rotateMinimap")
        rotating = Public(value) and value == true
    end
    ui.compass:SetShown(ui.LayerOn("blizzard") and (rotating or ui.LayerOn("hidden")))
    ui.compass:SetAlpha(rotating and 1 or 0.38)
end

local function Paint(ui)
    local config = S.Config(ID)
    local state = ui.state
    local base = state.compact and math.min(state.zoom, 94 / math.max(100, config.size or 190))
        or Clamp(state.zoom, 0.2, 1.5)
    ui.art:Paint(config, base, ui.LayerOn)
    ui.style:SetWidth(ui.art.width + (config.borderSize or 0) * base * 2)
    PaintOrnament(ui, config)
    ui.guides[1]:SetShown(ui.LayerOn("guides"))
    ui.guides[2]:SetShown(ui.LayerOn("guides"))
    for _, item in ipairs(ui.textItems) do PaintText(ui, config, item) end
    PaintIcons(ui, config)
    PaintMapControls(ui, config)
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
