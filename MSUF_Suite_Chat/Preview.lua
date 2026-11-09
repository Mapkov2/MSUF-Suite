local _, P = ...
local S = P.Suite
local C = P.Chat
-- Only sample regions supplied by Options enter this painter. No live chat
-- frame, dock, delegate or saved message is created or changed here.
local function Edges(owner)
    local edges = {}
    for i = 1, 4 do edges[i] = C.Fill(owner, "BORDER") end
    return edges
end

local function Surface(parts)
    if parts.visual then return parts.visual end
    local visual = { frame = parts.sample, previewToolbar = true, panel = C.Fill(parts.sample, "BACKGROUND"),
        headerRule = C.Fill(parts.sample, "ARTWORK"), edges = Edges(parts.sample) }
    parts.visual = visual
    parts.strip = C.Fill(parts.tabGroup, "BACKGROUND")
    parts.sidebarFill = C.Fill(parts.sidebar, "BACKGROUND")
    parts.sidebarFill:SetAllPoints(parts.sidebar)
    parts.copyFill = C.Fill(parts.copy, "BACKGROUND")
    parts.copyFill:SetAllPoints(parts.copy)
    return visual
end

local function Tabs(parts, c, top)
    parts.tabGroup:ClearAllPoints()
    parts.tabGroup:SetScale(parts.dockScale or 1)
    parts.tabGroup:SetPoint("BOTTOMLEFT", parts.sample, "TOPLEFT", parts.dockX or 0, parts.dockY or 3)
    C.OffsetNative(parts.previewOwner, parts.tabGroup, c.tabX or 0, c.tabY or 0)
    parts.tabGroup:SetSize(parts.dockWidth or parts.sample:GetWidth(), parts.dockHeight or c.tabHeight)
    if c.headerToolbar and not C.ToolbarWrap(c, parts.sample) then
        parts.tabGroup:SetWidth(parts.sample:GetWidth() - 108 - (c.headerClock and 80 or 0))
    end
    for index, tab in ipairs(parts.tabs) do
        local visual = tab.visual
        if not visual then
            visual = { tabLabel = tab.Text, tabLine = C.Fill(tab, "ARTWORK"),
                tabFill = C.Fill(tab, "BACKGROUND"), tabEdges = Edges(tab) }
            tab.visual = visual
        end
        local native = parts.nativeTabs and parts.nativeTabs[index]
        tab.previewTabID, tab.previewTabGeneration = native and native.tabID, native and native.generation
        tab:SetShown(not parts.nativeTabCount or index <= parts.nativeTabCount)
        tab:SetScale(native and native.scale or 1)
        tab.Text:ClearAllPoints()
        tab.Text:SetPoint("CENTER", tab, "CENTER", native and native.textX or 0, native and native.textY or -5)
        tab:SetSize(native and native.width or 60, native and native.height or 32)
        visual.tabWidthOwned, visual.tabHeightOwned = nil, nil
        C.ApplyTabGeometry(parts.previewOwner, visual, tab)
        tab:ClearAllPoints()
        if native and native.x then
            tab:SetPoint("BOTTOMLEFT", parts.tabGroup, "BOTTOMLEFT", native.x / (native.scale or 1), native.y / (native.scale or 1))
        elseif index == 1 then
            tab:SetPoint("BOTTOMLEFT", parts.tabGroup, "BOTTOMLEFT", 0, 0)
        else
            tab:SetPoint("LEFT", parts.tabs[index - 1], "RIGHT", 1 + c.tabGap, 0)
        end
        C.PlaceTabMarker(visual.tabLine, tab, c)
        C.Tint(visual.tabLine, c.accentColor, c.accentAlpha)
        C.ColorTab(parts.previewOwner, visual, native and native.selected or not native and index == 1)
        if native and native.r and not C.HasTabStyle(c) then tab.Text:SetTextColor(native.r, native.g, native.b, native.a) end
    end
end

local function Sidebar(parts, c)
    local sidebar = parts.sidebar
    C.PlaceSidebar(parts.previewOwner, sidebar, parts.sample)
    C.Tint(parts.sidebarFill, c.sidebarColor, c.sidebarAlpha)
    local shown = c.sidebarPanel and c.panelAlpha > 0
    sidebar:SetShown(shown)
    parts.previewOwner.sidebarClassColor = C.SidebarClassColor(c)
    for index, icon in ipairs(parts.icons) do
        if not icon.entry then
            local entry = C.CreateSidebarArt(icon, index)
            icon.glyph = entry.glyph
        end
        C.PlaceSidebarButton(icon, c, index, sidebar, parts.sample, index == 5)
        C.RefreshSidebarButton(parts.previewOwner, icon.entry)
        icon:SetShown(shown and C.SidebarButtonAvailable(index))
    end
    parts.friendCount = parts.icons[1].entry.count
    local r, g, b = S.RGB(parts.previewOwner.sidebarClassColor or c.tabActiveColor)
    parts.friendCount:SetTextColor(r, g, b, 1)
    local count = C.SidebarFriendsText()
    if count then parts.friendCount:SetText(count) end
end

local function Input(parts)
    local input = parts.input
    input:SetHeight(parts.nativeInputHeight or 32)
    local fonts = parts.fonts
    if fonts.input then parts.prompt:SetFont(fonts.input, fonts.inputSize, fonts.inputFlags) end
    C.PreviewInput(parts.previewOwner, parts.visual, parts.sample, input)
    parts.inputFill, parts.inputEdges = parts.visual.input, parts.visual.inputEdges
end

local function Messages(parts, config)
    local texts = parts.messageTexts or {}
    parts.messageTexts = texts
    local count = 0
    for text in (parts.text or ""):gmatch("[^\n]+") do count = count + 1 texts[count] = text end
    count = math.min(count, #parts.messageLines)
    local spacing = C.MessageSpacing(config, parts.messageSpacing or 0)
    local point, opposite = parts.insertTop and "TOPLEFT" or "BOTTOMLEFT", parts.insertTop and "BOTTOMLEFT" or "TOPLEFT"
    for index, line in ipairs(parts.messageLines) do
        line:ClearAllPoints()
        if index == 1 then line:SetPoint(point, parts.sample, point, 0, 0)
        else
            line:SetPoint(point, parts.messageLines[index - 1], opposite, 0,
                spacing * (parts.insertTop and -1 or 1))
        end
        line:SetSpacing(spacing)
        line:SetText(index <= count and texts[count - index + 1] or "")
        line:SetTextColor(1, 1, 1, 1)
        line:SetShown(index <= count)
    end
    parts.sample.visibleLines = parts.messageLines
    C.PaintMessageLines(parts.previewOwner, parts.sample)
end

local function PreviewOwner()
    return { preview = true, context = {
        TextColor = function(_, label, ...) label:SetTextColor(...) end,
        RestoreTuple = function(_, label) label:SetTextColor(1, .82, 0) end,
        Anchor = function(_, frame, ...) frame:ClearAllPoints() frame:SetPoint(...) end,
        Property = function(_, frame, _, setter, value) frame[setter](frame, value) end,
        RestorePoints = function() end,
        RestoreProperty = function() end,
    } }
end

function S.ChatPaintMenuPreview(parts, c)
    local visual = Surface(parts)
    parts.previewOwner = parts.previewOwner or PreviewOwner()
    parts.previewOwner.config = c
    Messages(parts, c)
    if parts.quickHeight and parts.quickHeight > 0 then
        parts.quickBar = parts.quickBar or CreateFrame("Frame", nil, parts.sample)
        parts.quickBar:SetHeight(parts.quickHeight)
        parts.sample.CombatLogQuickButtonFrame = parts.quickBar
    else
        parts.sample.CombatLogQuickButtonFrame = false
    end
    local top = C.HeaderTop(c, parts.sample, true)
    C.PreviewPanel(parts.previewOwner, visual, parts.sample, top)
    parts.strip:ClearAllPoints()
    parts.strip:SetPoint("TOPLEFT", parts.sample, "TOPLEFT", -c.padding + (c.tabX or 0), top + (c.tabY or 0))
    parts.strip:SetPoint("BOTTOMRIGHT", parts.sample, "TOPRIGHT", c.padding + (c.tabX or 0), c.tabY or 0)
    C.PaintDockGradient(parts.strip, c)
    parts.strip:SetShown(c.tabPanel and c.panelAlpha > 0)
    Tabs(parts, c, top)
    Sidebar(parts, c)
    Input(parts)
    if c.animateInput ~= parts.inputAnimationEnabled
        or c.animateInput and c.inputAnimationDuration ~= parts.inputAnimationDuration then
        if c.animateInput or parts.inputAnimationEnabled then S.ChatPreviewInputAnimation(parts.input, c) end
        parts.inputAnimationEnabled, parts.inputAnimationDuration = c.animateInput, c.inputAnimationDuration
    end
    parts.copy:ClearAllPoints()
    parts.copy:SetPoint("TOPRIGHT", parts.sample, "TOPRIGHT", -4 + c.copyButtonX, math.max(21, top) - 3 + c.copyButtonY)
    C.Tint(parts.copyFill, c.panelColor, 95)
    parts.copy:SetShown(c.copyMessages and not c.headerToolbar)
    if c.headerToolbar then
        parts.toolbar = parts.toolbar or S.CreateFrame("Frame", nil, parts.sample)
        C.PaintToolbar(parts.toolbar, c, false)
        parts.toolbar:ClearAllPoints()
        parts.toolbar:SetPoint("TOPRIGHT", parts.sample, "TOPRIGHT", c.padding + (c.tabX or 0),
            math.max(22, top) + (c.tabY or 0))
        parts.toolbar:Show()
        parts.resizeGrip = parts.resizeGrip or S.CreateFrame("Frame", nil, parts.sample)
        C.PaintChatResizeGrip(parts.resizeGrip)
        parts.resizeGrip:SetPoint("BOTTOMRIGHT", parts.sample, "BOTTOMRIGHT", c.padding, -c.padding)
        parts.resizeGrip:SetSize(16, 16)
        parts.resizeGrip:SetShown(not c.toolbarLocked)
    elseif parts.toolbar then
        parts.toolbar:Hide()
        if parts.resizeGrip then parts.resizeGrip:Hide() end
    end
    C.PaintClock(visual, parts.sample, c, top, c.headerClock and C.ClockText(c, 9, 28) or "")
    -- Keep the older preview's inspection fields pointing to runtime art.
    parts.fill, parts.fadeLeft, parts.fadeRight = visual.panel, visual.gradientLeft, visual.gradientRight
end

-- Fit the already-painted regions together; every element keeps its runtime scale.
function S.ChatPreviewBounds(parts, stage)
    local sample, visual = parts.sample, parts.visual
    local stageScale, sampleScale = stage:GetEffectiveScale(), sample:GetEffectiveScale()
    local sx, sy = sample:GetLeft(), sample:GetTop()
    if not S.Finite(stageScale) or stageScale <= 0 or not S.Finite(sampleScale)
        or not S.Finite(sx) or not S.Finite(sy) then return end
    sx, sy = sx * sampleScale / stageScale, sy * sampleScale / stageScale
    local left, right, top, bottom = 0, sample:GetWidth() * sampleScale / stageScale, 0, -sample:GetHeight() * sampleScale / stageScale
    local function Include(region)
        if not region or not region:IsShown() then return end
        local owner = region:IsObjectType("Texture") and region:GetParent() or region
        local scale = owner:GetEffectiveScale() / stageScale
        local x, y, width, height = region:GetRect()
        if not S.Finite(x) or not S.Finite(y) or not S.Finite(width) or not S.Finite(height) then return end
        left, right = math.min(left, x * scale - sx), math.max(right, (x + width) * scale - sx)
        bottom, top = math.min(bottom, y * scale - sy), math.max(top, (y + height) * scale - sy)
    end
    Include(visual.panel)
    Include(visual.gradientLeft)
    Include(visual.gradientRight)
    Include(parts.strip)
    Include(parts.sidebar)
    Include(parts.input)
    Include(parts.inputFill)
    Include(parts.copy)
    Include(visual.headerClock)
    for _, edge in ipairs(visual.edges) do Include(edge) end
    for _, edge in ipairs(parts.inputEdges) do Include(edge) end
    if parts.sidebar:IsShown() then for _, icon in ipairs(parts.icons) do Include(icon) end end
    for _, tab in ipairs(parts.tabs) do Include(tab) end
    return left, right, top, bottom
end

function S.ChatPaintPreviewSidebarHover(parts, entry)
    C.RefreshSidebarButton(parts.previewOwner, entry)
end

function S.ChatFitPreview(ui)
    local parts = ui.parts
    local left, right, top, bottom = S.ChatPreviewBounds(parts, ui.stage)
    if not left then return end
    local width, height = right - left + 24, top - bottom + 24
    local scale = math.min(1, (ui.width - 24) / width, 216 / height)
    local native = parts.nativeScale or 1
    ui.stage:SetSize(width, height)
    parts.sample:ClearAllPoints()
    parts.sample:SetPoint("TOPLEFT", ui.stage, "TOPLEFT", (12 - left) / native, -(12 + top) / native)
    ui.stage:SetScale(scale)
    ui.canvasHeight = height * scale
    ui.viewport:SetHeight(ui.canvasHeight)
end
