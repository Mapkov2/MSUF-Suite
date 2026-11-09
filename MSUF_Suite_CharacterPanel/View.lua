local _, NS = ...
local S = MSUFSuite.Suite
local CharacterHeader = S.CharacterHeader
local Window, ModelControls, TabOverflow, GroupLayout = NS.Window, NS.ModelControls, NS.TabOverflow, NS.GroupLayout
local View = {}
View.__index = View
NS.View = View

local WIDTH, HEIGHT = CharacterHeader.Width, 552
local HEADER, TABS, FOOTER, PAD = CharacterHeader.Height, 39, 28, 12
local CAPTION_WIDTH, CAPTION_SIZE, CLOSE_OFFSET = CharacterHeader.CaptionWidth, 22, 8
local BODY_W, BODY_H = WIDTH - 2 * PAD, HEIGHT - HEADER - TABS - FOOTER - 2 * PAD
local RAIL_W = 202
local DOLL_W = BODY_W - PAD - RAIL_W
local SLOT_W, SLOT_H, SLOT_STEP, INSET, ICON = 215, 38, 42, 8, 30
local WEAPON_Y, GROUP_HEADER, GROUP_ROW, GROUP_GAP = 353, 30, 24, 8
local BODY_Y, MODEL_X = HEADER + TABS + PAD, SLOT_W + INSET + 7
local MODEL_W, MODEL_H = DOLL_W - 2 * MODEL_X, WEAPON_Y - 2 * INSET
local WIDE_SLOT_W = (DOLL_W - 2 * INSET - GROUP_GAP) / 2
local BG, PANEL, RAISED = { .078, .098, .118 }, { .110, .137, .165 }, { .145, .176, .208 }
local LINE, SLOT, MODEL = { .224, .263, .294 }, { .137, .169, .196 }, { .125, .157, .184 }
local TEXT, MUTED, GOLD = { .941, .922, .886 }, { .682, .714, .733 }, { .922, .784, .553 }
local GOLD_LINE, GOLD_LOW = { .663, .525, .337 }, { .227, .200, .157 }
local HOVER = { .922, .784, .553, .10 }
local GROUP_EMPTY = {}
local TOKENS = {
    [BG] = "ink", [PANEL] = "surface", [RAISED] = "raised", [LINE] = "borderSoft",
    [SLOT] = "buttonFill", [MODEL] = "input", [TEXT] = "text", [MUTED] = "muted",
    [GOLD] = "accentBright", [GOLD_LINE] = "accent", [GOLD_LOW] = "active", [HOVER] = "hover",
}
local SHELL = { role = "shell", ownedArt = true }
local PANEL_STYLE = { role = "panel", ownedArt = true }
local CARD = { role = "card", ownedArt = true }
local CONTROL = { role = "button", activeRole = "navigationActive", useControlShape = true, ownedArt = true }
local NAVIGATION = { role = "navigation", activeRole = "navigationActive", useControlShape = true, ownedArt = true, motion = true }
local CreateFrame, CreateTexture, CreateFontString = S.CreateFrame, S.CreateTexture, S.CreateFontString
local ceil, floor, max, min = math.ceil, math.floor, math.max, math.min
local function Tint(view, target, fallback, isText)
    local tints = isText and view.textTints or view.textureTints
    tints[target] = fallback
    local color = view.palette[fallback] or fallback
    if isText then target:SetTextColor(unpack(color))
    elseif target == view.artMask or target == view.reportMask or target == view.gearMask then
        target:SetColorTexture(color[1], color[2], color[3], 1)
    else target:SetColorTexture(unpack(color)) end
end

local function Fill(view, parent, layer, color, inset)
    local texture = CreateTexture(parent, nil, layer)
    texture:SetPoint("TOPLEFT", inset or 0, -(inset or 0))
    texture:SetPoint("BOTTOMRIGHT", -(inset or 0), inset or 0)
    Tint(view, texture, color)
    return texture
end

local function ApplySurface(skin, frame, record)
    local applied, reason
    if skin then applied, reason = skin:SkinFrame(frame, record.style) end
    local themed = applied == true and reason == "applied"
    if record.border then record.border:SetShown(not themed) end
    if record.fill then record.fill:SetShown(not themed) end
    if record.hover then record.hover:SetShown(not themed) end
    if frame.underline then frame.underline:SetShown(frame.selected == true and not themed) end
    if themed and frame.selected then skin:SetActive(frame, true) end
    record.themed = themed
end

local function TrackSurface(view, frame, border, fill, style, hover)
    local record = { border = border, fill = fill, style = style, hover = hover }
    view.surfaces[frame] = record
    if view.skin then ApplySurface(view.skin, frame, record) end
end

local function Surface(view, parent, color, kind, style)
    local frame = Window.CreateChild(view, kind or "Frame", parent)
    local border = Fill(view, frame, "BACKGROUND", LINE)
    local fill = Fill(view, frame, "BORDER", color, 1)
    local hover = kind == "Button" and Fill(view, frame, "HIGHLIGHT", HOVER, 1) or nil
    TrackSurface(view, frame, border, fill, style or PANEL_STYLE, hover)
    return frame, fill
end

local function Rule(view, parent, point, color)
    local texture = CreateTexture(parent, nil, "ARTWORK")
    texture:SetPoint(point .. "LEFT")
    texture:SetPoint(point .. "RIGHT")
    texture:SetHeight(1)
    Tint(view, texture, color)
    return texture
end

local function Font(view, parent, size, color, justify)
    local text = CreateFontString(parent, nil, "OVERLAY", "GameFontHighlightSmall")
    S.SetFont(text, view.fontPath, size, "")
    Tint(view, text, color, true)
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    view.fonts[text] = size
    return text
end

-- The runtime and its data providers supply readable values to this painter.
local function Text(text, value)
    if text.panelText ~= value then
        text.panelText = value
        text:SetText(value)
    end
end

local function Visible(frame, shown)
    if frame.panelShown ~= shown then
        frame.panelShown = shown
        frame:SetShown(shown)
    end
end

local function Place(frame, x, y, width, height)
    if frame.panelX ~= x or frame.panelY ~= y then
        frame.panelX, frame.panelY = x, y
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", x, -y)
    end
    if frame.panelWidth ~= width or frame.panelHeight ~= height then
        frame.panelWidth, frame.panelHeight = width, height
        frame:SetSize(width, height)
    end
end

local function ClickLabel(view, parent, text, action)
    local button = Surface(view, parent, RAISED, "Button", CONTROL)
    local label = Font(view, button, 12, TEXT, "CENTER")
    label:SetPoint("LEFT", 4, 0)
    label:SetPoint("RIGHT", -4, 0)
    label:SetText(text)
    button:SetScript("OnClick", action)
    return button, label
end

local function ShowWindowTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(button.tooltip)
    GameTooltip:Show()
end

local function HideWindowTooltip(button)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function WindowTooltip(button, label)
    button.tooltip = label
    button:HookScript("OnEnter", ShowWindowTooltip)
    button:HookScript("OnLeave", HideWindowTooltip)
    button:HookScript("OnHide", HideWindowTooltip)
end

local function Caption(view, header, text, title, offset, action)
    local button, label = ClickLabel(view, header, text, not view.embedded and action or nil)
    button.view = view
    button:SetSize(CAPTION_SIZE, CAPTION_SIZE)
    button:SetPoint("TOPRIGHT", -offset, -CLOSE_OFFSET)
    WindowTooltip(button, title)
    return button, label
end

local function CaptionButtons(view, header)
    local window = view.window
    local actions = view.nativeLayout and Window.NativeCaptionActions or Window.CaptionActions
    local close = Caption(view, header, "X", NS.Text("Close"), CLOSE_OFFSET, not view.nativeLayout and view.callbacks.close or nil)
    if view.nativeLayout then Window.PlaceCloseArt(view, close) end
    window.maximize, window.maximizeLabel = Caption(view, header, "+", NS.Text("Maximize window"), 34, actions.maximize)
    window.minimize, window.minimizeLabel = Caption(view, header, "−", NS.Text("Minimize window"), 60, actions.minimize)
    window.dockRight = Caption(view, header, ">", NS.Text("Dock window right"), 86, actions.dockRight)
    window.dockLeft = Caption(view, header, "<", NS.Text("Dock window left"), 112, actions.dockLeft)
end

local function Header(view)
    local frame = view.frame
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER - 1)
    Fill(view, header, "BACKGROUND", PANEL)
    Rule(view, header, "TOP", GOLD_LINE)

    if not view.embedded and (not view.nativeRoot or view.nativeLayout) then
        local drag = CreateFrame("Button", nil, header)
        drag:SetPoint("TOPLEFT")
        drag:SetPoint("BOTTOMRIGHT", -CAPTION_WIDTH, 0)
        drag:RegisterForDrag("LeftButton")
        Window.BindTitleDrag(view, drag)
    end

    view.header = CharacterHeader.Create(header, view.callbacks)
    view.header.frame:SetPoint("TOPLEFT")
    if not view.nativeRoot or view.nativeLayout then CaptionButtons(view, header) end
end

local function NewTab(view)
    local tab = Window.CreateChild(view, "Button", view.tabBar)
    tab.view = view
    tab.label = Font(view, tab, 12, MUTED, "CENTER")
    tab.label:SetPoint("LEFT", 5, 1)
    tab.label:SetPoint("RIGHT", -5, 1)
    tab.underline = Rule(view, tab, "BOTTOM", GOLD)
    TrackSurface(view, tab, nil, nil, NAVIGATION, Fill(view, tab, "HIGHLIGHT", HOVER, 1))
    tab:SetScript("OnClick", TabOverflow.Click)
    return tab
end

local tabLayout = { height = TABS, pad = PAD, new = NewTab, place = Place, text = Text, visible = Visible }

local function RefreshFonts(view)
    if view.fontRevision == S.FontRevision then return false end
    view.fontRevision, view.fontPath = S.FontRevision, S.GlobalFontPath()
    for font, size in pairs(view.fonts) do S.SetFont(font, view.fontPath, size, "") end
    return true
end

local function RefreshPalette(view, skin)
    local palette, changed = view.palette, view.changedTints
    wipe(changed)
    for fallback, token in pairs(TOKENS) do
        local r, g, b, a
        if skin then r, g, b, a = skin:GetColor(token) end
        if fallback == HOVER then a = HOVER[4] end
        local old = palette[fallback]
        if not r then
            if old then palette[fallback], changed[fallback] = nil, true end
        elseif not old or old[1] ~= r or old[2] ~= g or old[3] ~= b or old[4] ~= a then
            palette[fallback], changed[fallback] = { r, g, b, a }, true
        end
    end
    if not next(changed) then return end
    for region, fallback in pairs(view.textureTints) do
        if changed[fallback] then Tint(view, region, fallback) end
    end
    for region, fallback in pairs(view.textTints) do
        if changed[fallback] then Tint(view, region, fallback, true) end
    end
end

function View:RefreshAppearance(skin, headerConfig)
    if skin and not skin:IsEnabled() then skin = nil end
    RefreshPalette(self, skin)
    if self.skin ~= skin then
        if self.skin then self.skin:ReleaseAll() end
        self.skin = skin
        -- Authored window: share Basic's opening fade without discovering its children.
        if not self.embedded and skin and skin.RegisterMenu then skin:RegisterMenu(self.frame, true) end
        for frame, record in pairs(self.surfaces) do ApplySurface(skin, frame, record) end
    elseif skin then
        skin:RefreshAll()
        for frame, record in pairs(self.surfaces) do
            if not record.themed then ApplySurface(skin, frame, record) end
        end
    end
    if RefreshFonts(self) and self.tabs then self:SetTabs(self.tabs, self.tab, true) end
    self:ApplyHeaderSettings(headerConfig)
end

local function ActiveTab(view, tab, active)
    if tab.selected == active then return end
    tab.selected = active
    Tint(view, tab.label, active and GOLD or MUTED, true)
    local themed = view.surfaces[tab].themed
    tab.underline:SetShown(active and not themed)
    if themed then view.skin:SetActive(tab, active) end
end

function View:SetTabs(tabs, selected, forceLayout)
    local fontChanged = RefreshFonts(self)
    if self.tabs ~= tabs or fontChanged or forceLayout or TabOverflow.SelectionMovesTab(self, tabs, selected) then
        self.tabs = tabs
        TabOverflow.Layout(self, tabs, selected, tabLayout)
    end
    local moreActive = false
    for i = 1, #tabs do
        local tab = self.tabButtons[i]
        local active = tab.id == selected
        if active and not tab.panelShown then moreActive = true end
        ActiveTab(self, tab, active)
    end
    if self.moreTab then ActiveTab(self, self.moreTab, moreActive) end
    self.tab = selected
end

local function PaintModel(view)
    local model, unit = view.model, view.unit
    if not unit then
        if model.unit then model:ClearModel() end
        model.unit, model.identity, model.ready = nil, nil, nil
        Visible(model, false)
        return
    end
    if model.unit ~= unit or model.identity ~= view.identity or not model.ready then
        if not ModelControls.CanBindUnit(unit) then Visible(model, false) return end
        model.unit, model.identity = unit, view.identity
        Visible(model, true)
        model.ready = model:SetUnit(unit) == true
        if model.ready then ModelControls.Apply(view) else model:ClearModel() end
    end
    Visible(model, model.ready == true)
end

function View:ApplyHeaderSettings(config)
    if config then self.headerConfig = config end
    local reserve = self.nativeRoot and not self.nativeLayout and 0 or CAPTION_WIDTH
    self.header:Settings(self.headerConfig, self.skin, self.frame:GetWidth() - 2, reserve, self.previewLayers)
    self.header:Paint(self.headerData, self:IsMinimized())
end

function View:SetHeader(name, subtitle, average, unit, identity, data)
    local header = data or self.headerData
    if not data then header.class = subtitle end
    header.name, header.itemLevel = name, average
    header.portrait, header.identity = unit, identity
    self.unit, self.identity, self.headerData = unit, identity, header
    self.header:Paint(header, self:IsMinimized())
end

function View:RefreshModel()
    if not self.model or not self.frame:IsShown() or self:IsMinimized()
        or not self.gear.panelShown or not self.modelHost.panelShown then return end
    if self.model.ready and self.model.unit == self.unit and self.model.identity == self.identity then
        if not ModelControls.CanBindUnit(self.unit) then return end
        self.model:RefreshUnit()
        ModelControls.Apply(self)
    else PaintModel(self) end
end

local function GearClick(button, mouse)
    button.view.callbacks.slot(button.slot, button, mouse)
end

local function GearEnter(button)
    button.view.callbacks.enter(button, button.slot)
end

local function GearLeave(button)
    button.view.callbacks.leave(button)
end

local function GearDrag(button)
    button.view.callbacks.drag(button.slot)
end

local function GearDrop(button)
    button.view.callbacks.drop(button.slot)
end

local function NewSlot(view)
    local native = view.nativeLayout ~= nil
    local button, fill = Surface(view, view.plate, SLOT, "Button", CONTROL)
    button.view, button.fill = view, fill
    if native then
        button:RegisterForClicks("LeftButtonUp")
        button:SetHitRectInsets(5 + ICON, 0, 0, 0)
    else button:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    if not native and view.callbacks.drag then button:RegisterForDrag("LeftButton") end
    button:SetScript("OnClick", GearClick)
    button:SetScript("OnEnter", GearEnter)
    button:SetScript("OnLeave", GearLeave)
    button:SetScript("OnDragStart", not native and view.callbacks.drag and GearDrag or nil)
    button:SetScript("OnReceiveDrag", not native and view.callbacks.drop and GearDrop or nil)
    local rim = CreateTexture(button, nil, "ARTWORK")
    rim:SetPoint("LEFT", 5, 0)
    rim:SetSize(ICON, ICON)
    button.rim = rim
    button.icon = CreateTexture(button, nil, "ARTWORK", nil, 1)
    button.icon:SetPoint("TOPLEFT", rim, "TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", rim, "BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(.07, .93, .07, .93)
    button.level = Font(view, button, 12, GOLD, "RIGHT")
    button.level:SetPoint("RIGHT", -7, 0)
    button.level:SetWidth(34)
    button.label = Font(view, button, 10, MUTED)
    button.label:SetPoint("TOPLEFT", 42, -5)
    button.label:SetPoint("TOPRIGHT", -47, -5)
    button.name = Font(view, button, 12, TEXT)
    button.name:SetPoint("BOTTOMLEFT", 42, 5)
    button.name:SetPoint("BOTTOMRIGHT", -47, 5)
    button.marker = CreateTexture(button, nil, "OVERLAY")
    button.marker:SetPoint("TOPLEFT", 1, -1)
    button.marker:SetPoint("BOTTOMLEFT", 1, 1)
    button.marker:SetWidth(2)
    Tint(view, button.marker, GOLD)
    return button
end

local function PaintSlot(button, item, selected)
    button.slot = item.slot
    Text(button.label, item.label)
    Text(button.name, item.name or "—")
    Text(button.level, item.level or "—")
    if button.texture ~= item.icon then
        button.texture = item.icon
        button.icon:SetTexture(item.icon)
    end
    if button.quality ~= item.quality or not button.qualitySet then
        button.quality, button.qualitySet = item.quality, true
        local color = item.quality and ITEM_QUALITY_COLORS[item.quality]
        if color then
            button.view.textureTints[button.rim] = nil
            button.view.textTints[button.level] = nil
            button.rim:SetColorTexture(color.r, color.g, color.b)
            button.level:SetTextColor(color.r, color.g, color.b)
        else
            Tint(button.view, button.rim, LINE)
            Tint(button.view, button.level, MUTED, true)
        end
    end
    if button.selected ~= selected then
        button.selected = selected
        local view = button.view
        Tint(view, button.fill, selected and GOLD_LOW or SLOT)
        if view.surfaces[button].themed then view.skin:SetActive(button, selected) end
    end
    Visible(button.marker, item.marked == true)
    Visible(button, true)
end

local function PaintSlots(view, buttons, items, startX, startY, width, stepX, stepY, selected)
    for i = 1, #items do
        local item = items[i]
        local button = buttons[i]
        if not button then
            button = NewSlot(view)
            buttons[i] = button
        end
        if view.gearArtLevel and button.nativeLevel ~= view.gearArtLevel then
            button.nativeLevel = view.gearArtLevel
            button:SetFrameLevel(view.frame:GetFrameLevel() + view.gearArtLevel)
        end
        Place(button, startX + (i - 1) * stepX, startY + (i - 1) * stepY, width, SLOT_H)
        PaintSlot(button, item, item.slot == selected)
    end
    for i = #items + 1, #buttons do Visible(buttons[i], false) end
end

local function GroupClick(button)
    if button.action then button.view.callbacks.group(button.action) end
end

local function NewCard(list)
    local card = Surface(list.view, list.canvas, PANEL, nil, CARD)
    local title = Window.CreateChild(list.view, "Button", card)
    title.view = list.view
    title:SetPoint("TOPLEFT", 7, -1)
    title:SetPoint("TOPRIGHT", -7, -1)
    title:SetHeight(GROUP_HEADER - 1)
    title:EnableMouse(false)
    title:SetScript("OnClick", GroupClick)
    title.label = Font(list.view, title, 12, GOLD)
    title.sign = Font(list.view, title, 12, GOLD, "CENTER")
    title.sign:SetPoint("RIGHT", -3, 0)
    card.title, card.rows = title, {}
    return card
end

local function NewValueRow(list, card)
    local row = Window.CreateChild(list.view, "Button", card)
    row.view = list.view
    row:EnableMouse(false)
    row:SetScript("OnClick", GroupClick)
    Fill(list.view, row, "HIGHLIGHT", HOVER, 1)
    row.left = Font(list.view, row, 11, MUTED)
    row.left:SetPoint("LEFT", 10, 0)
    row.left:SetPoint("RIGHT", row, "CENTER", 18, 0)
    row.right = Font(list.view, row, 11, TEXT, "RIGHT")
    row.right:SetPoint("LEFT", row, "CENTER", 20, 0)
    row.right:SetPoint("RIGHT", -10, 0)
    Rule(list.view, row, "TOP", LINE)
    return row
end

local function PaintCard(list, card, group, offset)
    local title = card.title
    if title.action ~= group.action then
        title.action = group.action
        title:EnableMouse(group.action ~= nil)
    end
    local depth = min(3, group.depth or 0)
    if title.depth ~= depth then
        title.depth = depth
        title.label:ClearAllPoints()
        title.label:SetPoint("LEFT", 3 + depth * 8, 0)
        title.label:SetPoint("RIGHT", -19, 0)
    end
    Text(title.label, group.title)
    Text(title.sign, group.action and (group.collapsed and "+" or "−") or "")

    local top = card.panelY + GROUP_HEADER
    local position = group.layout
    local above, below = position and position.rowUp or 0, position and position.rowDown or 0
    local first = max(1, floor((offset - top - below) / GROUP_ROW) + 1)
    local last = min(#group.rows, ceil((offset + list.height - top + above) / GROUP_ROW))
    local used = 0
    for i = first, last do
        used = used + 1
        local row = card.rows[used]
        if not row then
            row = NewValueRow(list, card)
            card.rows[used] = row
        end
        local values = group.rows[i]
        if row.action ~= values.action then
            row.action = values.action
            row:EnableMouse(values.action ~= nil)
            Tint(list.view, row.right, values.action and GOLD or TEXT, true)
        end
        local movement = values.layout
        local x, y = list.rowInset, GROUP_HEADER + (i - 1) * GROUP_ROW
        if movement then x, y = x + movement.x, y - movement.y end
        Place(row, x, y, list.rowWidth, GROUP_ROW)
        Text(row.left, values.label)
        Text(row.right, values.value)
        Visible(row, true)
    end
    for i = used + 1, #card.rows do Visible(card.rows[i], false) end
    return first
end

local function PaintList(list, offset)
    local preview = list.preview
    if preview then
        if preview.definition then
            preview:ContentChanging()
        else
            list.previewDefinition, preview = nil, nil
        end
    end
    local groups = list.groups
    local used = 0
    local bottom = offset + list.height
    for i = GroupLayout.FirstCard(list, offset), #groups do
        local y, height, position = list.offsets[i], list.heights[i], groups[i].layout
        if y >= bottom + list.above then break end
        local top, endY = y, y + height
        if position then
            y = y - position.y
            top, endY = y - position.rowUp, y + height + position.rowDown
        end
        if top < bottom and endY > offset then
            used = used + 1
            local card = list.cards[used]
            if not card then
                card = NewCard(list)
                list.cards[used] = card
            end
            local x = list.cardInset + ((i - 1) % list.columns) * (list.cardWidth + GROUP_GAP)
                + (position and position.x or 0)
            Place(card, x, y, list.cardWidth, height)
            local firstRow = PaintCard(list, card, groups[i], offset)
            if preview then card.previewCardIndex, card.previewFirstRow = i, firstRow end
            Visible(card, true)
        end
    end
    for i = used + 1, #list.cards do Visible(list.cards[i], false) end
    if preview then
        list.previewDefinition, list.previewOffset = preview.definition, offset
        preview:ContentChanged()
    end
end

function View:VisitReport(visitor)
    local list = self.report
    local offset = list.previewOffset
    local bottom = offset + list.height
    for _, card in ipairs(list.cards) do
        if not card.panelShown then break end
        local index = card.previewCardIndex
        if card.panelY + 1 < bottom and card.panelY + GROUP_HEADER > offset then
            visitor("card", card.title, index, nil, card, list.canvas)
        end
        for i, row in ipairs(card.rows) do
            if not row.panelShown then break end
            local top = card.panelY + row.panelY
            if top < bottom and top + GROUP_ROW > offset then
                local rowIndex = card.previewFirstRow + i - 1
                row.previewRowIndex = rowIndex
                visitor("row", row, index, rowIndex, row, list.canvas)
            end
        end
    end
end

local function VerticalScroll(scroll, offset)
    local list = scroll.panelList
    if not list.layingOut then PaintList(list, offset) end
end

local function NewList(view, parent, width, height, columns)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT")
    scroll:SetSize(width - 16, height)
    local canvas = CreateFrame("Frame", nil, scroll)
    canvas:SetSize(width - 16, 1)
    scroll:SetScrollChild(canvas)
    local list = {
        view = view, scroll = scroll, canvas = canvas, groups = GROUP_EMPTY,
        columns = columns, height = height, width = width - 16, cards = {}, offsets = {}, heights = {},
    }
    scroll.panelList = list
    scroll:HookScript("OnVerticalScroll", VerticalScroll)
    return list
end

local function PaintGroups(list, groups, reset)
    local content = GroupLayout.Build(list, groups, GROUP_HEADER, GROUP_ROW, GROUP_GAP)
    list.layingOut = true
    if list.content ~= content then
        list.content = content
        list.canvas:SetHeight(content)
    end
    local oldOffset = list.scroll:GetVerticalScroll()
    local offset = reset and 0 or min(oldOffset, max(0, content - list.height))
    if offset ~= oldOffset then list.scroll:SetVerticalScroll(offset) end
    list.layingOut = false
    PaintList(list, offset)
end

local function CloseDetails(button)
    button.view.callbacks.slot(nil)
end

local function GearBody(view)
    view.gear = CreateFrame("Frame", nil, view.body)
    view.gear:SetAllPoints()
    view.plate = Surface(view, view.gear, BG)
    view.plate:SetPoint("TOPLEFT")
    view.plate:SetSize(DOLL_W, BODY_H)
    if view.nativeLayout then view.gearMask = Fill(view, view.plate, "BACKGROUND", BG) end
    view.modelHost = Surface(view, view.plate, MODEL)
    view.modelHost:SetPoint("TOPLEFT", MODEL_X, -INSET)
    view.modelHost:SetSize(MODEL_W, MODEL_H)
    if not view.nativeLayout then
        view.model = CreateFrame("PlayerModel", nil, view.modelHost)
        view.model:SetPoint("TOPLEFT", 3, -28)
        view.model:SetPoint("BOTTOMRIGHT", -3, 3)
        view.model:SetScript("OnHide", function(model) model.ready = nil end)
    end
    ModelControls.Attach(view, ClickLabel)

    local divider = CreateTexture(view.plate, nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", INSET, -WEAPON_Y + 5)
    divider:SetPoint("TOPRIGHT", -INSET, -WEAPON_Y + 5)
    divider:SetHeight(1)
    Tint(view, divider, LINE)

    local rail = CreateFrame("Frame", nil, view.gear)
    rail:SetPoint("TOPRIGHT")
    rail:SetSize(RAIL_W, BODY_H)
    view.rail = NewList(view, rail, RAIL_W, BODY_H - 32, 1)
    view.dismiss = ClickLabel(view, rail, NS.Text("Close"), CloseDetails)
    view.dismiss.view = view
    view.dismiss:SetPoint("BOTTOMLEFT")
    view.dismiss:SetSize(82, 24)
end

function View:ShowGear(left, right, weapons, groups, selectedSlot, detailGroups, withModel)
    if self.nativeLayout then Window.ApplyNativeGearMode(self, right, withModel, GearClick, GearEnter, GearLeave) end
    local reset = self.contentTab ~= self.tab or self.detailSlot ~= selectedSlot
    self.contentTab, self.detailSlot = self.tab, selectedSlot
    Visible(self.reportCover or self.report.scroll, false)
    Visible(self.gear, true)
    Visible(self.modelHost, withModel == true)
    if self.model and withModel and self.frame:IsShown() then PaintModel(self) end
    local columnWidth = withModel and SLOT_W or WIDE_SLOT_W
    local weaponWidth = (DOLL_W - 2 * INSET - (#weapons - 1) * GROUP_GAP) / max(1, #weapons)
    PaintSlots(self, self.left, left, INSET, INSET, columnWidth, 0, SLOT_STEP, selectedSlot)
    PaintSlots(self, self.right, right, DOLL_W - INSET - columnWidth, INSET, columnWidth, 0, SLOT_STEP, selectedSlot)
    PaintSlots(self, self.weapons, weapons, INSET, WEAPON_Y, weaponWidth, weaponWidth + GROUP_GAP, 0, selectedSlot)
    local detailsShown = selectedSlot ~= nil and detailGroups ~= nil and #detailGroups > 0
    PaintGroups(self.rail, detailsShown and detailGroups or groups or GROUP_EMPTY, reset)
    Visible(self.dismiss, detailsShown)
    Text(self.hint, self.gearHint)
end

function View:RefreshInspectSummary(groups, relayout)
    local rail = self.rail
    if relayout then return PaintGroups(rail, groups, false) end
    rail.groups = groups
    PaintList(rail, rail.scroll:GetVerticalScroll())
end

function View:ShowGroups(groups)
    local reset = self.contentTab ~= self.tab
    self.contentTab, self.detailSlot = self.tab, nil
    if self.gear then Visible(self.gear, false) end
    Visible(self.reportCover or self.report.scroll, true)
    PaintGroups(self.report, groups or GROUP_EMPTY, reset)
    Text(self.hint, "")
end

function View:FitScreen()
    if self.nativeLayout then return end
    if self.nativeRoot then Window.FitHosted(self.window, self.nativeRoot) else Window.Fit(self.window) end
end

function View:ApplyWindowPreferences(preferences)
    if not self.nativeRoot then Window.ApplyPreferences(self.window, preferences) end
end

function View:IsMinimized()
    return self.window.minimized == true
end

function View:SetMinimized(minimized, tab, silent)
    if self.nativeRoot or not Window.SetMinimized(self.window, minimized) then return end
    self.body:SetShown(not minimized)
    self.tabBar:SetShown(not minimized)
    self.footer:SetShown(not minimized)
    self:ApplyHeaderSettings()
    if not silent then self.callbacks.minimized(minimized, tab) end
end

function View:SetContextAction(label)
    Visible(self.contextAction, label ~= nil)
    if label and (self.contextLabel.panelText ~= label or self.contextAction.fontRevision ~= self.fontRevision) then
        Text(self.contextLabel, label)
        self.contextAction.fontRevision = self.fontRevision
        local width = math.min(420, math.ceil(self.contextLabel:GetUnboundedStringWidth()) + 14)
        if self.contextAction.panelWidth ~= width then
            self.contextAction.panelWidth = width
            self.contextAction:SetWidth(width)
        end
    end
end

function View:CancelWindowGestures()
    Window.CancelGestures(self.window)
end

function View.NativeLayout(gear)
    return Window.NativeLayout(gear, WIDTH, HEIGHT, {
        left = PAD + INSET + 5, right = PAD + DOLL_W - INSET - SLOT_W + 5,
        alternateRight = PAD + DOLL_W - INSET - WIDE_SLOT_W + 5,
        close = { x = WIDTH - 1 - CLOSE_OFFSET - CAPTION_SIZE, y = 1 + CLOSE_OFFSET, size = CAPTION_SIZE },
        top = BODY_Y + INSET, slotHeight = SLOT_H, slotSize = ICON, slotStep = SLOT_STEP,
        weaponTop = BODY_Y + WEAPON_Y, weaponSpan = DOLL_W - 2 * INSET, weaponGap = GROUP_GAP,
        model = { x = PAD + MODEL_X + 3, y = BODY_Y + INSET + 28, width = MODEL_W - 6, height = MODEL_H - 31 },
        ammo = { x = WIDTH - PAD - ICON, y = BODY_Y + BODY_H - ICON },
    })
end

function View.New(callbacks, parent, nativeRoot, nativeLayout)
    local width = nativeLayout and nativeLayout.width or nativeRoot and 464 or WIDTH
    local height = nativeLayout and nativeLayout.height or HEIGHT
    local frame = CreateFrame("Frame", not nativeRoot and callbacks.frameName or nil, nativeRoot and UIParent or parent or UIParent)
    local view = setmetatable({
        frame = frame, callbacks = callbacks, fonts = {}, tabButtons = {}, left = {}, right = {}, weapons = {},
        fontRevision = S.FontRevision, fontPath = S.GlobalFontPath(),
        palette = {}, changedTints = {}, textTints = {}, textureTints = {}, surfaces = {},
        headerConfig = {}, headerData = {}, embedded = parent ~= nil, nativeRoot = nativeRoot,
        nativeLayout = nativeLayout, bodyWidth = width - 2 * PAD,
    }, View)
    frame:Hide()
    frame:SetSize(width, height)
    if not nativeRoot then frame:SetPoint(parent and "TOPLEFT" or "CENTER") end
    if not parent then frame:SetFrameStrata(nativeLayout and nativeLayout.strata or nativeRoot and "MEDIUM" or "DIALOG") end
    if nativeLayout then frame:SetFrameLevel((nativeLayout.rootLevel or 0) + nativeLayout.artLevel) end
    if not parent and not nativeRoot then
        frame:SetClampedToScreen(true)
        frame:SetMovable(true)
    end
    frame:EnableMouse(not nativeRoot)
    view.window = Window.New(frame, width, height, HEADER)
    if nativeLayout then view.artMask = Fill(view, frame, "BACKGROUND", BG, 1) end
    local border = Fill(view, frame, "BACKGROUND", LINE)
    local fill = Fill(view, frame, "BORDER", BG, 1)
    TrackSurface(view, frame, border, fill, SHELL)
    Header(view)
    view:ApplyHeaderSettings()

    local bar = CreateFrame("Frame", nil, frame)
    view.tabBar = bar
    bar:SetPoint("TOPLEFT", 1, -HEADER)
    bar:SetPoint("TOPRIGHT", -1, -HEADER)
    bar:SetHeight(TABS)
    Fill(view, bar, "BACKGROUND", PANEL)
    Rule(view, bar, "BOTTOM", LINE)

    view.body = CreateFrame("Frame", nil, frame)
    view.body:SetPoint("TOPLEFT", PAD, -BODY_Y)
    view.body:SetSize(view.bodyWidth, BODY_H)
    if not nativeRoot or nativeLayout then GearBody(view) end
    local reportParent = Window.ReportParent(view)
    if view.reportCover then view.reportMask = Fill(view, reportParent, "BACKGROUND", BG) end
    view.report = NewList(view, reportParent, view.bodyWidth, BODY_H, nativeRoot and not nativeLayout and 1 or 2)

    local footer = CreateFrame("Frame", nil, frame)
    view.footer = footer
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER - 1)
    Rule(view, footer, "TOP", LINE)
    view.hint = Font(view, footer, 11, MUTED, "RIGHT")
    view.hint:SetPoint("LEFT", 10, 0)
    view.hint:SetPoint("RIGHT", -25, 0)
    view.contextAction, view.contextLabel = ClickLabel(view, footer, "", callbacks.contextAction)
    view.contextAction.view = view
    view.contextAction:SetHeight(22)
    view.contextAction:SetPoint("LEFT", 8, 0)
    Visible(view.contextAction, false)
    view.gearHint = NS.Text("Click an item for details")
    if not nativeRoot or nativeLayout then Window.CreateGrip(view, WindowTooltip, function(texture) Tint(view, texture, MUTED) end) end
    if nativeLayout then Window.HostNativeView(view) elseif not parent then view:FitScreen() end
    return view
end
