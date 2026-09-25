local _, P = ...
local Suite, S, W, M, T, Tr = P.Suite, P.S, P.W, P.M, P.T, P.Tr
local ID, PAGE = "minimap", "suite_minimap"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ANCHORS = Suite.MinimapAnchorPoints or { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local ROWS = Suite.MinimapRowGeometry or {}
local OUTLINES = { "", "OUTLINE", "THICKOUTLINE", "MONOCHROME,OUTLINE" }
local TEXTS = {
    { "Clock", "12:34", "clock" }, { "FPS", "60 FPS", "fps" }, { "Latency", "23 ms", "latency" },
    { "Coordinates", "42.1, 56.7", "coordinates" }, { "Durability", "100%", "durability" },
    { "Location", "Current zone", "location" }, { "Difficulty", "5H", "difficulty" },
}
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
local LAYERS = {
    { "map", "Map" }, { "border", "Border" }, { "ornament", "Artwork" }, { "glow", "Glow" },
    { "backdrop", "Plate" }, { "shadow", "Shadow" },
    { "text", "Texts" }, { "blizzard", "Blizzard" }, { "folio", "Folio" },
    { "addons", "Addons" }, { "guides", "Guides" }, { "hidden", "Hidden" },
}
local LAYER_SECTIONS = { map = "layout", border = "shape", shadow = "shape", ornament = "style_art",
    glow = "style_glow", backdrop = "style_backdrop", text = "info_colors", blizzard = "elements",
    folio = "landing", addons = "addons" }
local function Clamp(value, low, high) return math.max(low, math.min(high, value)) end
local function Public(value) return not S.Public or S.Public(value) end
local function Tint(texture, r, g, b, a)
    texture:SetColorTexture(r, g, b, a)
end
local function Sample(name, config)
    if name == "Clock" then
        if type(GetGameTime) == "function" then
            local hour, minute = GetGameTime()
            if (not S.Public or S.Public(hour) and S.Public(minute)) and type(hour) == "number" and type(minute) == "number" then
                return string.format("%02d:%02d", hour, minute)
            end
        end
        return "12:34"
    end
    if name == "Location" then
        if type(GetZoneText) == "function" then
            local zone = GetZoneText()
            if (not S.Public or S.Public(zone)) and type(zone) == "string" and zone ~= "" then return zone end
        end
        return "Current zone"
    end
    if name == "Durability" then return (config.infoDurabilityIcon and "|TInterface\\Durability\\UI-Durability-Icons:12:10|t " or "") .. "100%" end
    for _, spec in ipairs(TEXTS) do if spec[1] == name then return spec[2] end end
    return name
end
local function SetIcon(texture, atlas, path)
    if atlas and type(C_Texture) == "table" and type(C_Texture.GetAtlasInfo) == "function" then
        local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
        if ok and info and (not S.Public or S.Public(info)) then
            texture:SetAtlas(atlas)
            return
        end
    end
    texture:SetTexture(path or WHITE)
end
-- Mirror the active Blizzard difficulty banner instead of drawing a crown.
-- Its artwork and text change with instance type, guild group and client.
local function CopyNativeTexture(target, source, frame, scale, nativeScale)
    if not source then target:Hide(); return false end
    local shown = source:IsShown()
    if not Public(shown) or not shown then target:Hide(); return false end
    local atlas = source.GetAtlas and source:GetAtlas()
    if Public(atlas) and type(atlas) == "string" and atlas ~= "" then target:SetAtlas(atlas)
    else
        local file = source.GetTexture and source:GetTexture()
        if not Public(file) or type(file) ~= "string" and type(file) ~= "number" then target:Hide(); return false end
        target:SetTexture(file)
    end
    local left, right, top, bottom = source:GetTexCoord()
    if Public(left) and Public(right) and Public(top) and Public(bottom)
        and type(left) == "number" and type(right) == "number" and type(top) == "number" and type(bottom) == "number" then
        target:SetTexCoord(left, right, top, bottom)
    end
    local r, g, b, a = source:GetVertexColor()
    if Public(r) and Public(g) and Public(b) and Public(a)
        and type(r) == "number" and type(g) == "number" and type(b) == "number" then
        target:SetVertexColor(r, g, b, type(a) == "number" and a or 1)
    end
    local alpha = source:GetAlpha()
    if Public(alpha) and type(alpha) == "number" then target:SetAlpha(alpha) end
    local width, height = source:GetSize()
    if not Public(width) or not Public(height) or type(width) ~= "number" or type(height) ~= "number" then
        target:Hide(); return false
    end
    target:SetSize(width * nativeScale * scale, height * nativeScale * scale)
    local fx, fy = frame:GetCenter()
    local sx, sy = source:GetCenter()
    target:ClearAllPoints()
    target:SetPoint("CENTER", target:GetParent(), "CENTER",
        Public(fx) and Public(sx) and type(fx) == "number" and type(sx) == "number" and (sx - fx) * scale or 0,
        Public(fy) and Public(sy) and type(fy) == "number" and type(sy) == "number" and (sy - fy) * scale or 0)
    target:Show()
    return true
end
local function CopyNativeText(target, source, frame, scale, nativeScale)
    if not source then target:Hide(); return end
    local shown = source:IsShown()
    if not Public(shown) or not shown then target:Hide(); return end
    local font, size, flags = source:GetFont()
    if Public(font) and Public(size) and Public(flags) and type(font) == "string" and type(size) == "number" then
        target:SetFont(font, math.max(6, size * nativeScale * scale), flags)
    end
    target:SetText(source:GetText())
    local r, g, b, a = source:GetTextColor()
    if Public(r) and Public(g) and Public(b) and Public(a)
        and type(r) == "number" and type(g) == "number" and type(b) == "number" then
        target:SetTextColor(r, g, b, type(a) == "number" and a or 1)
    end
    local fx, fy = frame:GetCenter()
    local sx, sy = source:GetCenter()
    target:ClearAllPoints()
    target:SetPoint("CENTER", target:GetParent(), "CENTER",
        Public(fx) and Public(sx) and type(fx) == "number" and type(sx) == "number" and (sx - fx) * scale or 0,
        Public(fy) and Public(sy) and type(fy) == "number" and type(sy) == "number" and (sy - fy) * scale or 0)
    target:Show()
end
local function RowPosition(button, map, rowIndex, index, config, scale, prefix)
    local row = ROWS[rowIndex] or ROWS[1] or { "TOPRIGHT", "TOPLEFT", -1, 0, 0, -1 }
    local distance = ((config.elementDistance or 0) + (config.borderSize or 0)) * scale
    local step = ((config.elementSize or 21) + (config.elementSpacing or 0)) * scale
    button:ClearAllPoints()
    button:SetPoint(row[1], map, row[2], row[3] * distance + row[5] * index * step
        + (config[prefix .. "X"] or 0) * scale,
        row[4] * distance + row[6] * index * step + (config[prefix .. "Y"] or 0) * scale)
end
local function TextPosition(button, map, anchor, x, y, scale, border)
    button:ClearAllPoints()
    if anchor == 10 then button:SetPoint("BOTTOM", map, "TOP", x * scale, y * scale + border); return "CENTER" end
    if anchor == 11 then button:SetPoint("TOP", map, "BOTTOM", x * scale, y * scale - border); return "CENTER" end
    local point = ANCHORS[anchor] or "CENTER"
    button:SetPoint(point, map, point, x * scale, y * scale)
    return point:find("LEFT", 1, true) and "LEFT" or point:find("RIGHT", 1, true) and "RIGHT" or "CENTER"
end
local function DragTarget(button, kind, configKey, map, getScale, focus)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    local function StartDrag(self, mouseButton)
        if mouseButton and mouseButton ~= "LeftButton" then return end
        if type(self.dragX) == "number" or P.Combat() or type(GetCursorPosition) ~= "function" then return end
        self.dragX, self.dragY = GetCursorPosition()
        self:StartMoving()
    end
    local function StopDrag(self, mouseButton)
        if mouseButton and mouseButton ~= "LeftButton" then return end
        if type(self.dragX) ~= "number" then return end
        self:StopMovingOrSizing()
        local cx, cy = GetCursorPosition()
        local uiScale = self.GetEffectiveScale and self:GetEffectiveScale() or 1
        if type(uiScale) ~= "number" or uiScale <= 0 then uiScale = 1 end
        local scale = getScale()
        local dx, dy = (cx - self.dragX) / uiScale / scale, (cy - self.dragY) / uiScale / scale
        self.dragX, self.dragY = nil, nil
        if P.Combat() or math.abs(dx) + math.abs(dy) < 2 then focus(self.previewSection, self.previewKey, self); return end
        if M.PreviewHelpers and M.PreviewHelpers.NotePreviewElementMoved then
            M.PreviewHelpers.NotePreviewElementMoved()
        end
        if kind == "map" then
            local rules = Suite.SuiteCatalog[ID].rules
            local x = Clamp(math.floor((P.Get(ID, "x") or 0) + dx + 0.5), rules.x.min, rules.x.max)
            local y = Clamp(math.floor((P.Get(ID, "y") or 0) + dy + 0.5), rules.y.min, rules.y.max)
            P.SetMany(ID, { x = x, y = y })
            self:ClearAllPoints()
            self:SetPoint("CENTER", self:GetParent(), "CENTER", 0, 0)
        elseif kind == "text" or kind == "corner" or kind == "offset" then
            local key = configKey
            local rules = Suite.SuiteCatalog[ID].rules
            local xRule, yRule = rules[key .. "X"], rules[key .. "Y"]
            local x = Clamp(math.floor((P.Get(ID, key .. "X") or 0) + dx + 0.5), xRule.min, xRule.max)
            local y = Clamp(math.floor((P.Get(ID, key .. "Y") or 0) + dy + 0.5), yRule.min, yRule.max)
            P.SetMany(ID, { [key .. "X"] = x, [key .. "Y"] = y })
        end
        focus(self.previewSection, self.previewKey, self)
    end
    -- MouseDown/Up mirrors the UF/GF handles. OnDragStart/Stop remain as a
    -- fallback on clients that deliver only the drag events to a Button.
    button:SetScript("OnMouseDown", StartDrag)
    button:SetScript("OnMouseUp", StopDrag)
    button:SetScript("OnDragStart", StartDrag)
    button:SetScript("OnDragStop", StopDrag)
    button:SetScript("OnHide", function(self)
        if type(self.dragX) == "number" then self:StopMovingOrSizing(); self.dragX, self.dragY = nil, nil end
    end)
end

function P.BuildMinimapPreview(ctx, b, sections)
    local section, toolbar, fixedRecord = W.FixedPreviewSection(ctx, b, {
        title = Tr("Minimap preview"), height = 180, gap = 8,
    })
    if not section then return end
    local hint = T.Font(toolbar, "GameFontDisableSmall", Tr("Click to select; drag or use arrow keys; edit exact X/Y below."), T.colors.muted)
    hint:SetPoint("LEFT", toolbar, "LEFT", 145, 0)
    hint:SetPoint("RIGHT", toolbar, "RIGHT", -145, 0)
    hint:SetJustifyH("LEFT")
    local width = math.max(260, (section._msuf2Width or b.width or 720) - 28)
    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", 14, -40)
    body:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, -40)
    body:SetHeight(132)
    if body.SetClipsChildren then body:SetClipsChildren(true) end
    local canvas = CreateFrame("Frame", nil, body)
    canvas:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    canvas:SetSize(width, 112)
    local background = canvas:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetAllPoints(canvas)
    Tint(background, 0.07, 0.09, 0.12, 0.97)
    local chrome = M.PreviewHelpers
    if chrome and chrome.ApplyPreviewChrome then chrome.ApplyPreviewChrome(canvas, "canvas", T) end
    local art = P.CreateMinimapPreviewArt(canvas)
    local map = art.map
    local initialSize = math.max(100, P.Get(ID, "size") or 190)
    local defaultZoom = Clamp(math.min((width - 160) / initialSize, 250 / initialSize), 0.2, 1)
    local state = { selected = nil, zoom = defaultZoom, compact = true, layers = {} }
    for _, entry in ipairs(LAYERS) do state.layers[entry[1]] = true end
    state.layers.guides = false
    state.layers.hidden = false
    local function LayerOn(key) return state.layers[key] ~= false end
    local paint
    local handles = {}
    local defaultHint = Tr("Click to select; drag or use arrow keys; edit exact X/Y below.")
    local hovered
    local function UpdateHint()
        local handle = hovered or body._selectedHandle
        if handle then
            hint:SetText(Tr(handle._label) .. "  -  " .. Tr("Drag or use arrows to move; click for settings."))
        else
            hint:SetText(defaultHint)
        end
    end
    local function ResetKey(key)
        if key and key:find("^info") then return key end
        if key == "folio" then return "landing" end
        if key == "difficulty" then return "difficultyButton" end
        if key == "drawer" then return "drawer" end
        if key == "ornament" or (key and key:find("^ornament_")) then return "style" end
        if key == "zoomIn" or key == "zoomOut" then return key end
        for _, item in ipairs(ICONS) do
            if item[1] == key then return "button" .. key:sub(1, 1):upper() .. key:sub(2) end
        end
    end
    local function OffsetKeys(key)
        if key == "map" then return "x", "y" end
        local prefix = ResetKey(key)
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
        local ok = P.SetMany(ID, { [xKey] = x, [yKey] = y })
        return ok ~= false
    end
    body._handleList = handles
    local function NudgeSelected(owner, dx, dy)
        if owner ~= body or P.Combat() or not body:IsShown() then return false end
        if chrome and chrome.IsTextInputFocused and chrome.IsTextInputFocused() then return false end
        local keyboardFocus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if keyboardFocus and keyboardFocus.IsObjectType and keyboardFocus:IsObjectType("EditBox") then return false end
        local handle = body._selectedHandle
        if not handle or not handle:IsShown() then return false end
        local xKey, yKey = OffsetKeys(handle._key)
        if not xKey then return false end
        local step = chrome and chrome.NudgeStep and chrome.NudgeStep() or
            (IsControlKeyDown and IsControlKeyDown() and 10 or IsShiftKeyDown and IsShiftKeyDown() and 5 or 1)
        dx, dy = dx * step, dy * step
        if chrome and chrome.ShouldSkipDuplicateNudge and chrome.ShouldSkipDuplicateNudge(body, dx, dy) then return true end
        return WriteOffsets(handle._key, P.Get(ID, xKey) + dx, P.Get(ID, yKey) + dy)
    end
    local arrowBindings = {
        ownerName = "MSUF_SuiteMinimapPreview_NudgeOwner",
        activeName = "MSUF_SuiteMinimapPreview_ActiveNudgeBox",
        buttonPrefix = "MSUF_SuiteMinimapPreview_Nudge",
        onClick = NudgeSelected,
    }
    local function SetArrowBindings(enabled)
        if M.SetPreviewArrowBindings then M.SetPreviewArrowBindings(body, enabled, arrowBindings) end
    end
    local function HandleKeyDown(self, key)
        if chrome and chrome.ArrowKeyDown then
            return chrome.ArrowKeyDown(self, key, {
                owner = function() return body end,
                selectedField = "_selectedHandle",
                nudge = NudgeSelected,
            })
        end
        local dx, dy
        if key == "LEFT" then dx, dy = -1, 0
        elseif key == "RIGHT" then dx, dy = 1, 0
        elseif key == "UP" then dx, dy = 0, 1
        elseif key == "DOWN" then dx, dy = 0, -1 end
        local moved = dx and NudgeSelected(body, dx, dy) or false
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(not moved) end
        return moved
    end
    body:EnableKeyboard(true)
    if body.SetPropagateKeyboardInput then body:SetPropagateKeyboardInput(true) end
    body:SetScript("OnKeyDown", HandleKeyDown)
    body:SetScript("OnHide", function(self)
        SetArrowBindings(false)
        if chrome and chrome.ReleaseKeyboardCapture then chrome.ReleaseKeyboardCapture(self)
        elseif self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
        local selected = self._selectedHandle
        if selected then selected:EnableKeyboard(false) end
    end)
    body:SetScript("OnShow", function(self)
        local selected = self._selectedHandle
        if selected and selected:IsShown() and not P.Combat() then
            selected:EnableKeyboard(true)
            SetArrowBindings(true)
            if chrome and chrome.FocusKeyboardTarget then
                chrome.FocusKeyboardTarget(self, selected, false, { selectedField = "_selectedHandle" })
            end
        end
    end)
    local function Select(handle)
        local previous = body._selectedHandle
        if previous and previous ~= handle then previous:EnableKeyboard(false) end
        body._selectedHandle = handle
        local active = handle and handle:IsShown() and body:IsShown() and not P.Combat()
        if handle then handle:EnableKeyboard(active and true or false) end
        SetArrowBindings(active and true or false)
        if active and chrome and chrome.FocusKeyboardTarget then
            chrome.FocusKeyboardTarget(body, handle, false, { selectedField = "_selectedHandle" })
        elseif not active and chrome and chrome.ReleaseKeyboardCapture then
            chrome.ReleaseKeyboardCapture(body)
        end
        if M.PreviewSelectionBar and M.PreviewSelectionBar.Refresh then M.PreviewSelectionBar.Refresh(body) end
        UpdateHint()
    end
    local function Focus(section, key, handle)
        local label = key
        for _, spec in ipairs(TEXTS) do if key == "info" .. spec[1] then label = spec[1] end end
        for _, spec in ipairs(ICONS) do if key == spec[1] then label = spec[2] end end
        state.selected = { key = key, label = label, section = section }
        Select(handle)
        if handle and chrome and chrome.ShowPreviewMoveCue then chrome.ShowPreviewMoveCue(body, handle) end
        if paint then paint() end
        local target = sections[section]
        if target and W.FocusCollapsibleSection then W.FocusCollapsibleSection(target, { persist = true, flash = true }) end
    end
    local function BindHover(button)
        button:SetScript("OnEnter", function(self)
            hovered = self
            if self._hoverFill then self._hoverFill:Show() end
            UpdateHint()
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(Tr(self._label), 1, 1, 1)
                GameTooltip:AddLine(Tr("Drag or use arrows to move; Shift: 5, Ctrl: 10."), 0.82, 0.82, 0.82, true)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function(self)
            if hovered == self then hovered = nil end
            if self._hoverFill then self._hoverFill:Hide() end
            UpdateHint()
            if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
    end
    local function Target(key, label, section, parent, w, h)
        local button = CreateFrame("Button", nil, parent or canvas)
        button:SetFrameLevel((tonumber((canvas:GetFrameLevel())) or 0) + 5)
        button:SetSize(w, h)
        button:EnableMouse(true)
        button:RegisterForClicks("LeftButtonUp")
        button.previewKey, button.previewSection = key, section
        button._key, button._label, button._color = key, label, { 0.30, 0.74, 1.00 }
        local hover = button:CreateTexture(nil, "OVERLAY", nil, -1)
        hover:SetAllPoints(button)
        Tint(hover, 0.30, 0.74, 1.00, 0.18)
        hover:Hide()
        button._hoverFill = hover
        BindHover(button)
        button:SetScript("OnKeyDown", HandleKeyDown)
        if OffsetKeys(key) then handles[#handles + 1] = button end
        button:SetScript("OnClick", function(self) Focus(section, key, OffsetKeys(key) and self or nil) end)
        if M.RegisterControlMetadata then
            M.RegisterControlMetadata(button, P.Meta(PAGE, ID, "preview." .. key, "action", "suite_minimap_preview"), label, "button")
        end
        return button
    end
    map.previewKey, map.previewSection = "map", "layout"
    map._key, map._label, map._color = "map", "Minimap", { 0.30, 0.74, 1.00 }
    handles[#handles + 1] = map
    BindHover(map)
    map:SetScript("OnKeyDown", HandleKeyDown)
    map:SetScript("OnClick", function(self) Focus("layout", "map", self) end)
    DragTarget(map, "map", nil, map, function() return art.scale or 1 end, Focus)
    if M.RegisterControlMetadata then
        M.RegisterControlMetadata(map, P.Meta(PAGE, ID, "preview.map", "action", "suite_minimap_preview"), "Minimap", "button")
    end
    local style = Target("style", "Shape, border and shadow", "shape", canvas, 1, 8)
    style:SetPoint("TOP", map, "BOTTOM")
    -- Four narrow hit areas follow the visible rim. The centre stays clickable
    -- as the map, while any edge opens the artwork controls directly.
    local ornament = Target("ornament", "Decorative border", "style_art", canvas, 1, 16)
    ornament:SetPoint("CENTER", map, "TOP")
    DragTarget(ornament, "offset", "style", map, function() return art.scale or 1 end, Focus)
    local ornamentEdges = { ornament }
    for _, spec in ipairs({ { "bottom", "BOTTOM" }, { "left", "LEFT" }, { "right", "RIGHT" } }) do
        local edge = Target("ornament_" .. spec[1], "Decorative border", "style_art", canvas, 16, 16)
        edge:SetPoint("CENTER", map, spec[2])
        DragTarget(edge, "offset", "style", map, function() return art.scale or 1 end, Focus)
        ornamentEdges[#ornamentEdges + 1] = edge
    end
    local textItems = {}
    for _, spec in ipairs(TEXTS) do
        local name = spec[1]
        local key = "info" .. name
        local section = "info_" .. name:lower()
        local button = Target(key, name, section, canvas, 100, 20)
        local box = button:CreateTexture(nil, "BACKGROUND")
        box:SetPoint("CENTER", button, "CENTER")
        box:SetSize(100, 19)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetAllPoints(button)
        label:SetJustifyV("MIDDLE")
        -- The location field can be 220px wide while its visible zone name is
        -- only a few glyphs. Keep its click target on the rendered text so it
        -- cannot steal FPS/latency clicks, or be stolen by their wide fields.
        if name == "Location" then button:SetFrameLevel((tonumber((canvas:GetFrameLevel())) or 0) + 7) end
        DragTarget(button, "text", key, map, function() return art.scale or 1 end, Focus)
        textItems[#textItems + 1] = { spec = spec, button = button, box = box, label = label }
    end
    local iconItems = {}
    for _, spec in ipairs(ICONS) do
        local button = Target(spec[1], spec[2], spec[3], canvas, 24, 24)
        local backdrop = button:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints(button)
        Tint(backdrop, 0.025, 0.035, 0.045, 0.8)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
        SetIcon(icon, spec[6], spec[7])
        button.previewIcon = icon
        if spec[1] == "drawer" then
            icon:Hide()
            for index = 1, 4 do
                local dot = button:CreateTexture(nil, "ARTWORK")
                dot:SetSize(4, 4)
                dot:SetPoint("CENTER", button, "CENTER", index % 2 == 1 and -4 or 4,
                    index <= 2 and 4 or -4)
                Tint(dot, 0.9, 0.9, 0.9, 1)
            end
        elseif spec[1] == "folio" then
            local book = {}
            for index = 1, 3 do book[index] = button:CreateTexture(nil, "OVERLAY") end
            book[1]:SetPoint("RIGHT", button, "CENTER", -1, 0)
            book[2]:SetPoint("LEFT", button, "CENTER", 1, 0)
            book[3]:SetPoint("CENTER", button, "CENTER")
            book[1]:SetSize(7, 13); book[2]:SetSize(7, 13); book[3]:SetSize(2, 15)
            Tint(book[1], 0.91, 0.81, 0.56, 1)
            Tint(book[2], 0.98, 0.92, 0.74, 1)
            Tint(book[3], 0.35, 0.28, 0.18, 1)
            button.previewBook = book
        elseif spec[1] == "difficulty" then
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
        if spec[1] == "difficulty" then DragTarget(button, "corner", "difficultyButton", map, function() return art.scale or 1 end, Focus)
        elseif spec[1] == "folio" then DragTarget(button, "corner", "landing", map, function() return art.scale or 1 end, Focus)
        else
            local positionKey = spec[1] == "drawer" and "drawer"
                or "button" .. spec[1]:sub(1, 1):upper() .. spec[1]:sub(2)
            DragTarget(button, "offset", positionKey, map, function() return art.scale or 1 end, Focus)
        end
        iconItems[#iconItems + 1] = { spec = spec, button = button, backdrop = backdrop, edge = edge }
    end
    local zoomItems = {}
    for index, spec in ipairs({ { "zoomIn", "Zoom in", "+" }, { "zoomOut", "Zoom out", "-" } }) do
        local button = Target(spec[1], spec[2], "behavior", canvas, 20, 20)
        local back = button:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints(button)
        Tint(back, 0.035, 0.05, 0.065, 0.9)
        local sign = T.Font(button, "GameFontHighlightSmall", spec[3], T.colors.text)
        sign:SetPoint("CENTER", button, "CENTER")
        DragTarget(button, "offset", spec[1], map, function() return art.scale or 1 end, Focus)
        zoomItems[#zoomItems + 1] = button
    end
    local compass = Target("compass", "Compass and rotation", "behavior", canvas, 17, 17)
    compass:SetPoint("TOP", map, "TOP", 0, -2)
    local north = T.Font(compass, "GameFontHighlightSmall", "N", T.colors.text)
    north:SetPoint("CENTER", compass, "CENTER")
    local guides = {}
    for i = 1, 2 do
        local line = canvas:CreateTexture(nil, "OVERLAY")
        Tint(line, 0.65, 0.78, 0.87, 0.2)
        guides[i] = line
    end
    guides[1]:SetPoint("CENTER", map, "CENTER")
    guides[1]:SetSize(1, 300)
    guides[2]:SetPoint("CENTER", map, "CENTER")
    guides[2]:SetSize(500, 1)
    local zoomLabel = T.Font(canvas, "GameFontHighlightSmall", "100%", T.colors.muted)
    zoomLabel:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -56, -12)
    local function ZoomButton(label, offset, fn)
        local button = T.Button(canvas, label, 28, 23)
        button:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", offset, -7)
        button:SetScript("OnClick", function() fn(); paint() end)
        return button
    end
    ZoomButton("-", -96, function() state.zoom = Clamp(state.zoom - 0.1, 0.2, 1.5) end)
    ZoomButton("+", -12, function() state.zoom = Clamp(state.zoom + 0.1, 0.2, 1.5) end)
    local fit = T.Button(canvas, "Fit", 35, 23)
    fit:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -130, -7)
    fit:SetScript("OnClick", function()
        state.zoom = Clamp(math.min((width - 160) / math.max(100, P.Get(ID, "size")), 250 / math.max(100, P.Get(ID, "size"))), 0.2, 1)
        paint()
    end)
    local one = T.Button(canvas, "1:1", 33, 23)
    one:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -168, -7)
    one:SetScript("OnClick", function() state.zoom = 1; paint() end)
    local selection = M.PreviewSelectionBar.Create(body, {
        Tr = Tr,
        Theme = function() return T end,
        HandleList = function() return handles end,
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
            local xKey, yKey = OffsetKeys(handle._key)
            if not xKey then return false end
            return WriteOffsets(handle._key, P.Get(ID, xKey) + dx, P.Get(ID, yKey) + dy)
        end,
        ResetOffsets = function(_, handle)
            local xKey, yKey = OffsetKeys(handle._key)
            if not xKey then return false end
            local rules = Suite.SuiteCatalog[ID].rules
            return WriteOffsets(handle._key, rules[xKey].default, rules[yKey].default)
        end,
        OpenSettings = function(_, handle)
            local target = handle and sections[handle.previewSection]
            if target and W.FocusCollapsibleSection then W.FocusCollapsibleSection(target, { persist = true, flash = true }) end
        end,
        SelectHandle = function(_, handle)
            if not handle then return false end
            Focus(handle.previewSection, handle.previewKey, handle)
            return true
        end,
        UpdateHint = function() end,
    })
    selection:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 0, -8)
    selection:SetPoint("TOPRIGHT", canvas, "BOTTOMRIGHT", 0, -8)
    local chips = CreateFrame("Frame", nil, body)
    chips:SetPoint("TOPLEFT", selection, "BOTTOMLEFT", 0, -8)
    local perRow = math.max(1, math.floor((width - 63) / 78))
    local chipRows = math.ceil(#LAYERS / perRow)
    chips:SetSize(width, 8 + chipRows * 25)
    local layersTitle = T.Font(chips, "GameFontHighlightSmall", "LAYERS", T.colors.muted)
    layersTitle:SetPoint("TOPLEFT", chips, "TOPLEFT", 7, -8)
    local layerButtons = {}
    for i, entry in ipairs(LAYERS) do
        local button = T.Button(chips, entry[2], 76, 20)
        local row, col = math.floor((i - 1) / perRow), (i - 1) % perRow
        button:SetPoint("TOPLEFT", chips, "TOPLEFT", 61 + col * 78, -2 - row * 25)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" and LAYER_SECTIONS[entry[1]] then
                Focus(LAYER_SECTIONS[entry[1]], entry[1])
            else
                state.layers[entry[1]] = not LayerOn(entry[1]); paint()
            end
        end)
        if M.RegisterControlMetadata then
            M.RegisterControlMetadata(button, P.Meta(PAGE, ID, "preview.layer." .. entry[1], "action", "suite_minimap_preview"),
                entry[2] .. " preview layer", "button")
        end
        layerButtons[i] = button
    end
    local function PaintText(config, item)
        local name, prefix = item.spec[1], "info" .. item.spec[1]
        local on = config[prefix] == true
        if name == "Difficulty" then on = config.infoDifficulty == true end
        local shown = LayerOn("text") and (on or LayerOn("hidden"))
        local button = item.button
        button:SetShown(shown)
        if not shown then return end
        local font = config[prefix .. "Font"] or ""
        local size = config[prefix .. "Size"] or 12
        local outline = OUTLINES[config[prefix .. "Outline"]] or "OUTLINE"
        local path = S.ResolveFont and S.ResolveFont(font) or STANDARD_TEXT_FONT
        P.StylePreviewFont(item.label, path, math.max(8, size * art.scale), outline,
            config[prefix .. "Rendering"], config[prefix .. "Shadow"],
            config[prefix .. "ShadowOpacity"], config[prefix .. "ShadowDistance"])
        local sample = Sample(name, config)
        item.label:SetText(sample)
        local configuredWidth = math.max(24, (config[prefix .. "Width"] or 100) * art.scale)
        local measured = item.label.GetStringWidth and item.label:GetStringWidth()
        if type(measured) ~= "number" or measured <= 0 then
            measured = #sample * size * art.scale * 0.62
        end
        local hitWidth = math.min(configuredWidth, math.max(24, measured + 8))
        button:SetSize(hitWidth, math.max(18, (size + 8) * art.scale))
        item.box:SetWidth(hitWidth)
        local justify = TextPosition(button, map, config[prefix .. "Anchor"], config[prefix .. "X"] or 0,
            config[prefix .. "Y"] or 0, art.scale, (config.borderSize or 0) * art.scale)
        item.label:SetJustifyH(justify)
        local r, g, b = P.RGB(config[prefix .. "Color"] or "ffffff")
        if config[prefix .. "ClassColor"] and type(UnitClass) == "function" and S.ClassRGB then
            local _, token = UnitClass("player")
            if not S.Public or S.Public(token) then
                local cr, cg, cb = S.ClassRGB(token)
                if cr then r, g, b = cr, cg, cb end
            end
        end
        item.label:SetTextColor(r or 1, g or 1, b or 1)
        local box = name ~= "Difficulty" and config[prefix .. "Box"] == 2
        local br, bg, bb = P.RGB(config.borderColor)
        Tint(item.box, br, bg, bb, 0.85)
        item.box:SetShown(box or state.selected and state.selected.key == prefix)
        button:SetAlpha(on and 1 or 0.38)
    end
    local function PaintIcons(config)
        local rowCount = 0
        local size = Clamp((config.elementSize or 21) * art.scale, 12, 60)
        for _, item in ipairs(iconItems) do
            local spec, button = item.spec, item.button
            local key, layer = spec[1], spec[5]
            local wanted = key == "folio" and config.showLanding ~= 3 or spec[4] and config[spec[4]] == true
            if key == "drawer" and Suite.Client.IsAddOnLoaded("MinimapButtonButton") then wanted = false end
            if spec[4] == false then
                wanted = S.MinimapElementPreviewShown and S.MinimapElementPreviewShown(spec[2]) == true or false
            end
            if key == "difficulty" then
                wanted = config.showDifficulty and not config.infoDifficulty
                if S.MinimapElementAvailable then wanted = wanted and S.MinimapElementAvailable("Difficulty") end
                if S.MinimapElementPreviewShown and S.MinimapElementPreviewShown("Difficulty") == false then wanted = false end
            end
            if spec[3] == "elements" and key ~= "difficulty" and S.MinimapElementPreviewShown then
                local nativeShown = S.MinimapElementPreviewShown(spec[2])
                if nativeShown == false then wanted = false end
            end
            button:SetShown(LayerOn(layer) and (wanted or LayerOn("hidden")))
            button:SetAlpha(wanted and 1 or 0.38)
            button:SetSize(size, size)
            if key == "folio" then
                local simpleBook = config.landingIcon == 2
                button.previewIcon:SetShown(not simpleBook)
                for _, part in ipairs(button.previewBook) do part:SetShown(simpleBook) end
            end
            if key == "folio" then
                button:SetSize(size * 0.8, size * 0.8)
                button:ClearAllPoints()
                button:SetPoint("BOTTOMLEFT", map, "BOTTOMLEFT", (2 + (config.landingX or 0)) * art.scale,
                    (2 + (config.landingY or 0)) * art.scale)
            elseif key == "difficulty" then
                local native, mode
                if S.MinimapDifficultyPreviewSource then native, mode = S.MinimapDifficultyPreviewSource() end
                local parts = button.previewNative
                local nativeScale = (config.elementSize or 21) / 21
                local mirrored = false
                if native and mode and mode.Background and mode.Border then
                    local width, height = native:GetSize()
                    if Public(width) and Public(height) and type(width) == "number" and type(height) == "number"
                        and width > 0 and height > 0 then
                        button:SetSize(width * nativeScale * art.scale, height * nativeScale * art.scale)
                    end
                    local content = mode.Instance or mode
                    local glyph = mode.ChallengeModeTexture
                    if not glyph and type(content.DifficultyTextures) == "table" then
                        for i = 1, #content.DifficultyTextures do
                            local candidate = content.DifficultyTextures[i]
                            local shown = candidate:IsShown()
                            if Public(shown) and shown then glyph = candidate; break end
                        end
                    end
                    local background = CopyNativeTexture(parts.background, mode.Background, native, art.scale, nativeScale)
                    local border = CopyNativeTexture(parts.border, mode.Border, native, art.scale, nativeScale)
                    mirrored = background or border
                    CopyNativeTexture(parts.emblem, mode.Emblem, native, art.scale, nativeScale)
                    CopyNativeTexture(parts.glyph, glyph, native, art.scale, nativeScale)
                    CopyNativeText(parts.text, content.Text, native, art.scale, nativeScale)
                end
                if not mirrored then
                    parts.background:Hide(); parts.border:Hide(); parts.emblem:Hide(); parts.glyph:Hide(); parts.text:Hide()
                    button:SetSize(size, size)
                end
                button.previewIcon:SetShown(not mirrored)
                item.backdrop:SetShown(not mirrored)
                button:ClearAllPoints()
                button:SetPoint("TOPRIGHT", map, "TOPRIGHT", (-2 + (config.difficultyButtonX or 0)) * art.scale,
                    (-2 + (config.difficultyButtonY or 0)) * art.scale)
            else
                local index = key == "drawer" and config.drawerRow == config.elementRow and rowCount or 0
                local row = key == "drawer" and config.drawerRow or config.elementRow
                local prefix = key == "drawer" and "drawer"
                    or "button" .. key:sub(1, 1):upper() .. key:sub(2)
                RowPosition(button, map, row, key == "drawer" and index or rowCount, config, art.scale, prefix)
                if key ~= "drawer" and wanted then rowCount = rowCount + 1 end
            end
            local chosen = state.selected and state.selected.key == key
            if key == "difficulty" then item.edge:SetShown(chosen and true or false) end
            Tint(item.edge, chosen and 0.28 or 0.6, chosen and 0.74 or 0.74, chosen and 1 or 0.83, chosen and 1 or 0.65)
            Tint(item.backdrop, chosen and 0.11 or 0.025, chosen and 0.3 or 0.035, chosen and 0.43 or 0.045, 0.9)
        end
    end
    paint = function()
        local config = S.Config(ID)
        local base = state.compact and math.min(state.zoom, 94 / math.max(100, config.size or 190))
            or Clamp(state.zoom, 0.2, 1.5)
        art:Paint(config, base, LayerOn)
        style:SetWidth(art.width + (config.borderSize or 0) * base * 2)
        local rim = math.max(12, ((config.styleScale or 100) / 100 - 1) * art.width)
        local rimShown = LayerOn("ornament") and (config.styleTexture ~= 1 or LayerOn("hidden"))
        ornamentEdges[1]:SetWidth(art.width + rim)
        ornamentEdges[2]:SetWidth(art.width + rim)
        ornamentEdges[3]:SetHeight(art.height + rim)
        ornamentEdges[4]:SetHeight(art.height + rim)
        for index, point in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local edge = ornamentEdges[index]
            edge:ClearAllPoints()
            edge:SetPoint("CENTER", map, point,
                (config.styleX or 0) * art.scale, (config.styleY or 0) * art.scale)
        end
        for _, edge in ipairs(ornamentEdges) do edge:SetShown(rimShown) end
        guides[1]:SetShown(LayerOn("guides"))
        guides[2]:SetShown(LayerOn("guides"))
        for _, item in ipairs(textItems) do PaintText(config, item) end
        PaintIcons(config)
        for index, button in ipairs(zoomItems) do
            local mode = config.zoomButtons or 1
            button:SetShown(LayerOn("blizzard") and (mode ~= 3 or LayerOn("hidden")))
            button:SetAlpha(mode == 2 and 1 or mode == 1 and 0.62 or 0.38)
            local prefix = index == 1 and "zoomIn" or "zoomOut"
            button:ClearAllPoints()
            button:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT",
                (-2 + (config[prefix .. "X"] or 0)) * art.scale,
                ((index == 1 and 27 or 3) + (config[prefix .. "Y"] or 0)) * art.scale)
        end
        local rotating = config.rotate == 2
        if config.rotate == 1 and type(GetCVarBool) == "function" then
            local value = GetCVarBool("rotateMinimap")
            rotating = (not S.Public or S.Public(value)) and value == true
        end
        compass:SetShown(LayerOn("blizzard") and (rotating or LayerOn("hidden")))
        compass:SetAlpha(rotating and 1 or 0.38)
        zoomLabel:SetText(string.format("%d%%", math.floor(base * 100 + 0.5)))
        for i, entry in ipairs(LAYERS) do layerButtons[i]:SetAlpha(LayerOn(entry[1]) and 1 or 0.42) end
        if body._selectedHandle and not body._selectedHandle:IsShown() then Select(nil) end
        M.PreviewSelectionBar.Refresh(body)
    end
    -- Selectable map and border use separate hit areas; texts and icons sit above them.
    style:SetScript("OnClick", function() Focus("shape", "style") end)
    function body:ApplyCompactPreviewPresentation(compact)
        state.compact = compact == true
        canvas:SetHeight(state.compact and 112 or 316)
        M.PreviewSelectionBar.SetShown(body, not state.compact)
        chips:SetShown(not state.compact)
        paint()
    end
    body:ApplyCompactPreviewPresentation(true)
    local expandedHeight = 316 + 8 + 24 + 8 + (8 + chipRows * 25) + 8
    local expander = W.AttachFixedPreviewExpander(section, toolbar, body, {
        pageKey = ctx.key,
        wrapper = ctx.wrapper,
        compactHeight = 132,
        compactTop = -40,
        expandedHeight = expandedHeight,
        expandedTop = -40,
        expandedSectionHeight = 40 + expandedHeight + 8,
        onStateChanged = function() paint() end,
    })
    if fixedRecord then
        fixedRecord.onActivate = function()
            if expander and M.ShouldExpandFixedPreview and M.ShouldExpandFixedPreview() then
                expander:Open("SUITE_MINIMAP_PREVIEW_ACTIVE")
            end
            paint()
        end
    end
    M.TrackRefresh(ctx, paint)
end
