local _, P = ...
local K, Tr, Interaction = P.PreviewCanvas, P.Tr, P.PreviewInteraction
local STAGE_TOP = 74
local function Jump(ctx, section, key)
    local sectionId = "suite_skin_" .. section
    local bridge = P.Suite.HostBridge
    if key and bridge and bridge.OpenExactMenuSetting
        and bridge.OpenExactMenuSetting(P.M, "suite_skin", sectionId, "msufsuite.skin." .. key) then return end
    local ui = ctx.suiteWorkspace
    if ui then ui:Focus(sectionId) end
end

local function Link(preview, frame, label, section, key, action)
    local function Open() return Jump(preview.ctx, section, key) end
    preview.links[frame] = Open
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" and action then return action() end
        return Open()
    end)
    if P.M.AddTooltip then
        local hint = action and Tr("Click for settings. Right-click to try it in the preview.")
            or Tr("Click an element to open its settings.")
        P.M.AddTooltip(frame, Tr(label), hint, { hook = true })
    end
end

local function Place(frame, parent, x, y, width, height)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:SetSize(width, height)
end

local function Stretch(frame, parent, left, top, right, height)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top)
    frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -right, top)
    frame:SetHeight(height)
end
local function VisibleRefresh(preview, frame, state)
    if not state or state.target ~= frame then return end
    local refresh = state.refresh
    state.refresh = function(value)
        if frame:IsVisible() then refresh(value) end
    end
    frame:HookScript("OnShow", function() state.refresh(state) end)
    preview.surfaces[#preview.surfaces + 1] = frame
end

local function Box(preview, skin, parent, x, y, w, h, role)
    local frame = K.Button(parent, x, y, w, h)
    local button = role == "buttonPrimary" or role == "button"
    local spec = { role = role, ownedArt = true, motion = true, useControlShape = button }
    local state
    if button then
        state = skin.Surface.SkinOwnedButton(frame, spec, false)
    else state = skin.Surface.Attach(frame, spec) end
    VisibleRefresh(preview, frame, state)
    return frame
end
local function Label(preview, frame, text, x, y, right, token)
    local template = token == "title" and "GameFontNormal" or "GameFontHighlightSmall"
    local label = frame:CreateFontString(nil, "OVERLAY", template)
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -right, y)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    P.SetTranslatedText(label, Tr(text))
    local fontObject = token == "title" and GameFontNormal or GameFontHighlightSmall
    preview.labels[#preview.labels + 1] = { region = label, token = token or "text", fontObject = fontObject }
    return label
end

local function SampleAction(preview, skin, parent, x, kind)
    local cell = K.Button(parent, x, 0, 24, 24)
    local template = kind == "close" and "UIPanelCloseButtonNoScripts" or kind == "minimize" and "UIPanelHideButtonNoScripts"
    local native = CreateFrame("Button", nil, cell, template or nil)
    native:SetAllPoints(cell)
    native:SetFrameLevel(cell:GetFrameLevel() + 1)
    native:EnableMouse(false)
    native:Hide()
    if not template then native:SetNormalTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Up") end
    local record = { cell = cell, kind = kind }
    local function Paint()
        local state = record.down and "pushed" or record.hover and "highlight" or "normal"
        local custom = skin.WindowActionSkin.PaintCaption(cell, record.kind, state)
        native:SetShown(not custom)
    end
    local close = kind == "close"
    Link(preview, cell, close and "Window action style" or "Maximize/minimize symbols", "icons",
        close and "icons.windowActions.style" or "icons.windowActions.glyphMode")
    record.paint = Paint
    cell:HookScript("OnEnter", function() record.hover = true Paint() end)
    cell:HookScript("OnLeave", function() record.hover, record.down = nil, nil Paint() end)
    cell:HookScript("OnMouseDown", function() record.down = true Paint() end)
    cell:HookScript("OnMouseUp", function() record.down = nil Paint() end)
    preview.captions[#preview.captions + 1] = record
    return record
end

local function SampleIcon(preview, skin, parent)
    local button = K.Button(parent, 0, 0, 26, 26)
    button:ClearAllPoints()
    button:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    Link(preview, button, "Item icon border", "icons", "theme.iconBorderStyle")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(135274)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints(icon)
    border:SetColorTexture(1, 1, 1, 1)
    border:SetVertexColor(.64, .21, .93, 1)
    if skin.IconSkin then skin.IconSkin.Apply(button, preview, { icon = icon, nativeBorder = border }) end
    preview.item = button
end

local function SampleValue(preview, card)
    local value = Label(preview, card, "Item level", 8, -25, 42)
    P.SetTranslatedText(value, Tr("Item level") .. "  42")
    preview.labels[#preview.labels].value = true
end

local function PreviewFont(skin)
    local config, typography = skin.DB.typography, skin.Typography
    if config and config.enabled and typography then
        return typography.GetSelectionPath(typography.GetSelection())
    end
end

local function PaintLabel(row, skin, font)
    local region = row.region
    local r, g, b = skin.Theme.GetColor(row.token)
    if row.r ~= r or row.g ~= g or row.b ~= b then
        row.r, row.g, row.b = r, g, b
        region:SetTextColor(r, g, b)
    end
    local larger = row.value and skin.DB.theme.readableValues == true
    if row.font == font and row.larger == larger then return end
    if not row.originalFont then row.originalFont, row.size, row.flags = region:GetFont() end
    if not row.originalFont then return end
    local nativeFont = row.fontObject and row.fontObject:GetFont() or row.originalFont
    local size = larger and row.size + 2 or row.size
    if region:SetFont(font or nativeFont, size, row.flags) == false then
        region:SetFont(nativeFont, size, row.flags)
    end
    row.font, row.larger = font, larger
end

local SCROLL_ROWS = { "Equipment", "Reputation", "Skills", "Currency", "Statistics", "Character and equipment" }
local function BuildScroll(preview, skin, parent)
    local list = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    list:SetPoint("TOPLEFT", 4, -25)
    list:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -19, 6)
    local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", list, "TOPRIGHT", 3, 0)
    bar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 3, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(22)
    view:SetElementInitializer("Frame", function(row, item)
        if not row.skinPreviewLabel then
            row.skinPreviewLabel = Label(preview, row, item.label, 2, -3, 4)
            PaintLabel(preview.labels[#preview.labels], skin, PreviewFont(skin))
        end
        P.SetTranslatedText(row.skinPreviewLabel, Tr(item.label))
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(list, bar, view)
    local data = {}
    for i, label in ipairs(SCROLL_ROWS) do data[i] = { label = label } end
    list:SetDataProvider(CreateDataProvider(data))
    skin.ScrollMotion.Track(list, preview, true)
end

local function FillVeil(parent, level)
    local shade = CreateFrame("Frame", nil, parent)
    shade:SetAllPoints(parent)
    shade:SetFrameLevel(level)
    shade:EnableMouse(false)
    local fill = shade:CreateTexture(nil, "OVERLAY")
    fill:SetAllPoints(shade)
    fill:SetColorTexture(0, 0, 0, .42)
    shade:Hide()
    return shade
end

local function RefreshInteraction(preview, skin)
    if not preview.menu then return end
    local theme = skin.DB.theme
    local showMenu = preview.menuOpen == true and preview.panel:IsShown() and preview.layers.controls
    preview.menu:SetShown(showMenu)
    preview.dropdownVeil:SetShown(showMenu and theme.dropdownDimming ~= false)
    preview.focusVeil:SetShown(not preview.focused and theme.windowFocusDimming ~= false)
    if preview.captions then
        for _, record in ipairs(preview.captions) do record.paint() end
    end
end

local function Element(preview, skin, parent, role, label, section, key, action)
    local frame = Box(preview, skin, parent, 0, 0, 1, 1, role)
    Link(preview, frame, label, section, key, action)
    return frame
end

local function CaptionLabel(preview, frame, label, token, y, right)
    Label(preview, frame, label, 8, y or -5, right or 8, token)
end

local function BuildDropdown(preview, skin)
    local shell, panel = preview.shell, preview.panel
    local level = panel:GetFrameLevel() + 5
    preview.dropdownVeil = FillVeil(shell, level + 1)
    preview.focusVeil = FillVeil(panel, level)
    preview.menu = Element(preview, skin, shell, "popup", "Dim background for dropdowns", "shape", "theme.dropdownDimming")
    preview.menu:SetFrameLevel(level + 3)
    CaptionLabel(preview, preview.menu, "Dim background for dropdowns", "title")
    local close = K.Button(preview.menu, 6, -30, 70, 24, function()
        preview.menuOpen = false
        RefreshInteraction(preview, skin)
    end)
    CaptionLabel(preview, close, "Close")
end

local function Contents(preview, skin)
    local shell = preview.shell
    local panel = Element(preview, skin, shell, "panel", "Glass and surfaces", "material", "theme.materialDepth")
    preview.panel = panel
    local nav = Element(preview, skin, panel, "card", "Scroll behavior", "shape", "theme.smoothScrolling")
    CaptionLabel(preview, nav, "Scroll", "accent")
    if preview.forever and skin.ScrollMotion then BuildScroll(preview, skin, nav)
    else
        CaptionLabel(preview, nav, "Bags and bank", nil, -44)
        CaptionLabel(preview, nav, "Group Finder and PvE", nil, -73)
    end
    local search = Element(preview, skin, panel, "button", "Dim background for dropdowns", "shape", "theme.dropdownDimming", function()
        preview.menuOpen = not preview.menuOpen
        RefreshInteraction(preview, skin)
        if preview.menuOpen and skin.ContentMotion then skin.ContentMotion.Play(preview.menu, preview, {}) end
    end)
    CaptionLabel(preview, search, "Menu")
    local card = Element(preview, skin, panel, "card", "Readable values and status symbols", "shape", "theme.readableValues")
    CaptionLabel(preview, card, "Equipment", "title", -6, 42)
    SampleValue(preview, card)
    SampleIcon(preview, skin, card)
    local font = Element(preview, skin, panel, "button", "Fonts", "fonts", "font.face")
    CaptionLabel(preview, font, "Fonts")
    local hover = Element(preview, skin, panel, "buttonPrimary", "Hover highlight", "shape", "theme.hoverStyle")
    CaptionLabel(preview, hover, "Hover highlight", "accent")
    preview.nav, preview.search, preview.card, preview.fontSample, preview.hoverSample = nav, search, card, font, hover
    BuildDropdown(preview, skin)
end
local function Refresh(preview, skin)
    if not preview.section:IsVisible() or P.Combat() then return end
    RefreshInteraction(preview, skin)
    Interaction.RefreshLayerRail(preview)
    for _, frame in ipairs(preview.surfaces) do skin.Surface.Refresh(frame) end
    for _, cell in ipairs(preview.titleButtons) do P.S.WindowCaption.Paint(cell) end
    if preview.item and skin.IconSkin then skin.IconSkin.Repaint(preview.item) end
    local font = PreviewFont(skin)
    for _, row in ipairs(preview.labels) do
        PaintLabel(row, skin, font)
    end
end

local LAYERS = {
    { "content", "Equipment" }, { "controls", "Buttons" }, { "item", "Item icon border" },
    { "actions", "Window action style" },
}

local function SetLayers(preview)
    local layers = preview.layers
    if preview.shellHeight then preview.shell:SetHeight(preview.minimized and 35 or preview.shellHeight) end
    preview.panel:SetShown(layers.content and not preview.minimized)
    preview.search:SetShown(layers.controls)
    preview.fontSample:SetShown(layers.controls)
    preview.hoverSample:SetShown(layers.controls)
    preview.item:SetShown(layers.item)
    if preview.actionBar then preview.actionBar:SetShown(layers.actions) end
end

local function RevealSample(preview, layer)
    preview.shell:Show()
    if layer then
        preview.minimized = false
        preview.layers.content = true
        preview.layers[layer] = true
        if layer == "controls" or layer == "item" then preview.menuOpen = false end
    end
    SetLayers(preview)
end

local ITEM_BORDER_SETTINGS = {
    iconBorder = true, iconBorderStyle = true, iconBorderThickness = true,
    iconBorderPadding = true, iconBorderOpacity = true,
}

local function AddWindowDemo(preview, skin)
    local function Replay()
        preview.shell:Show()
        preview.minimized, preview.wide, preview.menuOpen = false, false, false
        preview.focused = true
        SetLayers(preview)
        preview.Layout()
        preview.Paint()
        if skin.ContentMotion then
            skin.ContentMotion.StopOwner(preview, preview.shell)
            skin.ContentMotion.Play(preview.shell, preview, {})
        end
    end
    preview.reopen = Element(preview, skin, preview.footer, "button", "Menu animations", "shape", "theme.menuAnimations", Replay)
    CaptionLabel(preview, preview.reopen, "Preview")
    preview.focus = Element(preview, skin, preview.footer, "button", "Dim inactive windows", "shape", "theme.windowFocusDimming", function()
        preview.focused = not preview.focused
        RefreshInteraction(preview, skin)
    end)
    CaptionLabel(preview, preview.focus, "Focus")
    local caption = P.S.WindowCaption
    local function TitleButton(x, kind, label, action)
        local cell = K.Button(preview.shell, 0, 0, 24, 24)
        cell:ClearAllPoints()
        cell:SetPoint("TOPRIGHT", preview.shell, "TOPRIGHT", x, -6)
        if kind == "close" then
            Link(preview, cell, label, "icons", "icons.windowActions.style", action)
        else
            Link(preview, cell, label, "window_controls", "windowControls.enabled", action)
        end
        caption.Dress(cell, kind, function() return skin.Theme.GetColor("text") end)
        preview.titleButtons[#preview.titleButtons + 1] = cell
        return cell
    end
    TitleButton(-64, "minimize", "Minimize window", function()
        preview.minimized = not preview.minimized
        preview.menuOpen = false
        SetLayers(preview)
        RefreshInteraction(preview, skin)
    end)
    preview.maximize = TitleButton(-38, "maximize", "Maximize window", function()
        preview.wide = not preview.wide
        preview.Layout()
    end)
    TitleButton(-10, "close", "Close", function()
        preview.menuOpen = false
        RefreshInteraction(preview, skin)
        preview.shell:Hide()
    end)
end

local function AddActionSamples(preview, skin)
    local bar = CreateFrame("Frame", nil, preview.footer)
    preview.actionBar = bar
    SampleAction(preview, skin, bar, 0, "minimize")
    SampleAction(preview, skin, bar, 29, "maximize")
    SampleAction(preview, skin, bar, 58, "close")
end

local function LayoutWindow(preview, width)
    local shell, panel = preview.shell, preview.panel
    local shellWidth = preview.wide and width or math.min(width, math.max(238, math.floor(width * .85)))
    local stacked = shellWidth < 270
    local height = stacked and 228 or 182
    local left = stacked and shellWidth - 36 or math.floor(math.min(164, (shellWidth - 20) * .34))
    local x, y = stacked and 8 or left + 16, stacked and -62 or -8
    local room = shellWidth - x - 28
    preview.shellHeight = height
    Place(shell, preview.section, 16, -STAGE_TOP, shellWidth, preview.minimized and 35 or height)
    Stretch(panel, shell, 10, -36, 10, height - 46)
    Place(preview.nav, panel, 8, -8, left, stacked and 48 or 120)
    Place(preview.search, panel, x, y, room, 24)
    Place(preview.card, panel, x, y - 30, room, 45)
    local half = math.floor((room - 6) / 2)
    Place(preview.fontSample, panel, x, y - 83, half, 28)
    Place(preview.hoverSample, panel, x + half + 6, y - 83, room - half - 6, 28)
    Place(preview.menu, shell, x + 10, y - 63, room, 62)
    if preview.maximize then P.S.WindowCaption.SetKind(preview.maximize, preview.wide and "restore" or "maximize") end
end

local function Layout(preview, fallbackWidth)
    local section = preview.section
    local actual = section:GetWidth()
    local width = math.min(1000, math.max(120, (actual and actual > 100 and actual or fallbackWidth) - 32))
    local sidebar = width >= 680
    local controlsWidth = sidebar and math.floor(width * .37) or width
    local stageWidth = sidebar and width - controlsWidth - 12 or width
    if preview.laidOutWidth ~= stageWidth or preview.laidOutWide ~= preview.wide then
        preview.laidOutWidth, preview.laidOutWide = stageWidth, preview.wide
        LayoutWindow(preview, stageWidth)
    end
    local x = sidebar and 16 + stageWidth + 12 or 16
    local footerHeight = preview.actionBar and controlsWidth < 290 and 55 or 26
    local footerY = sidebar and -STAGE_TOP or -STAGE_TOP - preview.shellHeight - 8
    Place(preview.footer, section, x, footerY, controlsWidth, footerHeight)
    local available = controlsWidth - (preview.actionBar and footerHeight == 26 and 92 or 0)
    local buttonWidth = math.floor(math.min(116, (available - 6) / 2))
    Place(preview.reopen, preview.footer, 0, 0, buttonWidth, 26)
    Place(preview.focus, preview.footer, buttonWidth + 6, 0, buttonWidth, 26)
    if preview.actionBar then
        local below = footerHeight > 26
        Place(preview.actionBar, preview.footer, below and 0 or controlsWidth - 82, below and -30 or -1, 82, 24)
    end
    local y = footerY - 6 - footerHeight
    preview.chips:SetPoint("TOPLEFT", section, "TOPLEFT", x, y)
    Interaction.LayoutLayerRail(preview, controlsWidth)
    local height = math.max(STAGE_TOP + preview.shellHeight, -y + preview.chips:GetHeight()) + 8
    local ui = preview.ctx.suiteWorkspace
    if ui then P.MenuWorkspace.FitHeader(ui, height)
    elseif section:GetHeight() ~= height then
        P.HM.SetFixedPreviewHeight(section, height)
        section:SetHeight(height)
    end
end

local function BuildControls(preview, skin)
    local section = preview.section
    local specs = {}
    for _, spec in ipairs(LAYERS) do
        if spec[1] ~= "actions" or preview.actionBar then specs[#specs + 1] = spec end
    end
    local targets = { content = preview.panel, controls = preview.hoverSample, item = preview.item,
        actions = preview.captions[3] and preview.captions[3].cell }
    Interaction.BuildLayerRail(preview, section, specs, function(key, enabled)
        preview.layers[key] = enabled
        SetLayers(preview)
        preview.Paint()
        return true
    end, function(spec)
        local open = preview.links[targets[spec[1]]]
        if open then return open() end
    end, function(key)
        if key == "item" and skin.DB.theme.iconBorderStyle == "off" then return "theme.iconBorderStyle" end
    end)
    if P.M.AddTooltip then
        for index, button in ipairs(preview.layerButtons) do
            P.M.AddTooltip(button, Tr(specs[index][2]), Tr("Right-click to open its settings."), { hook = true,
                enabled = function() return not button._suiteLayerBlocked or not button._suiteLayerBlocked() end })
        end
    end
end

local function TrackPreview(preview, skin)
    local section, ctx = preview.section, preview.ctx
    local function Paint() Refresh(preview, skin) end
    preview.Paint = Paint
    local function OnThemeChanged(owner, domain, key)
        if not section:IsVisible() or P.Combat() then return end
        if domain == "windowAction" then
            owner.layers.actions = true
            SetLayers(owner)
            if key == "glyphMode" then RevealSample(owner) end
        elseif key == "hoverStyle" or key == "hoverIntensity" or key == "hover" then
            RevealSample(owner, "controls")
            owner.hoverSample:LockHighlight()
        elseif domain == "readability" then
            RevealSample(owner, "content")
        elseif ITEM_BORDER_SETTINGS[key] then
            RevealSample(owner, "item")
        elseif domain == "appearance" or domain == "geometry" or domain == "theme" or domain == "color"
            or domain == "typography" or domain == "profile" then
            RevealSample(owner, key == "controlShape" and "controls" or "content")
            owner.hoverSample:UnlockHighlight()
        elseif domain == "motion" then
            if key == "dropdownDimming" then
                RevealSample(owner, "controls")
                owner.menuOpen = true
            elseif key == "windowFocusDimming" then
                RevealSample(owner, "content")
                owner.focused = false
            elseif key == "menuAnimations" or key == "reduceMotion" then
                RevealSample(owner, "content")
                if skin.ContentMotion then
                    skin.ContentMotion.StopOwner(owner, owner.shell)
                    skin.ContentMotion.Play(owner.shell, owner, {})
                end
            else
                RevealSample(owner, "content")
            end
        end
        Paint()
        -- Theme listeners run in arbitrary order. Repaint action surfaces
        -- once the renderer has invalidated their cached geometry.
        if domain == "profile" or domain == "geometry" or domain == "theme" and key ~= "gradient" then
            skin.Registry.QueueJob(Paint)
        end
    end
    local function OnShow()
        skin.Registry.AddListener(preview, OnThemeChanged)
        preview.Layout()
        Paint()
    end
    P.M.TrackRefresh(ctx, Paint)
    section:HookScript("OnShow", OnShow)
    section:HookScript("OnHide", function() skin.Registry.RemoveListener(preview) end)
    if section:IsVisible() then OnShow() end
end

function P.BuildSkinMenuPreview(ctx, b, skin)
    if not P.W.FixedPreviewSection then return end
    local section, toolbar = P.W.FixedPreviewSection(ctx, b, { title = Tr("Skin preview"), height = 62 })
    if not section then return end
    local preview = { ctx = ctx, section = section, labels = {}, surfaces = {}, links = {}, titleButtons = {},
        captions = {}, layers = { content = true, controls = true, item = true, actions = true }, focused = true }
    preview.forever = skin.Client and skin.Client.isForever
    ctx.skinPreview = preview
    preview.footer = CreateFrame("Frame", nil, section)
    preview.Layout = function() Layout(preview, P.HM.GetSectionWidth(section) or b.width or 720) end
    preview.shell = Element(preview, skin, section, "shell", "Window corners", "shape", "geometry.family")
    CaptionLabel(preview, preview.shell, "Window shell", "title", -10, 92)
    Contents(preview, skin)
    AddWindowDemo(preview, skin)
    if preview.forever and skin.WindowActionSkin and skin.WindowActionSkin.PaintCaption then
        AddActionSamples(preview, skin)
    end
    BuildControls(preview, skin)
    SetLayers(preview)
    section:HookScript("OnSizeChanged", function(_, width)
        if preview.lastWidth == width then return end
        preview.lastWidth = width
        preview.Layout()
    end)
    TrackPreview(preview, skin)
    return section, toolbar
end
