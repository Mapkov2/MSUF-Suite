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
    local visual = { frame = parts.sample, panel = C.Fill(parts.sample, "BACKGROUND"),
        headerRule = C.Fill(parts.sample, "ARTWORK"), edges = Edges(parts.sample) }
    parts.visual = visual
    parts.strip = C.Fill(parts.sample, "BACKGROUND")
    parts.sidebarFill = C.Fill(parts.sidebar, "BACKGROUND")
    parts.sidebarFill:SetAllPoints(parts.sidebar)
    parts.copyFill = C.Fill(parts.copy, "BACKGROUND")
    parts.copyFill:SetAllPoints(parts.copy)
    return visual
end

local function Tabs(parts, c, top)
    parts.tabGroup:ClearAllPoints()
    parts.tabGroup:SetPoint("BOTTOMLEFT", parts.sample, "TOPLEFT", 0, 3)
    C.OffsetNative(parts.previewOwner, parts.tabGroup, c.tabX or 0, c.tabY or 0)
    parts.tabGroup:SetSize(parts.sample:GetWidth(), c.tabHeight)
    for index, tab in ipairs(parts.tabs) do
        local visual = tab.visual
        if not visual then
            visual = { tabLabel = tab.Text, tabLine = C.Fill(tab, "ARTWORK"),
                tabFill = C.Fill(tab, "BACKGROUND"), tabEdges = Edges(tab) }
            tab.visual = visual
        end
        local native = parts.nativeTabs and parts.nativeTabs[index]
        tab:SetSize(native and native.width or 60, native and native.height or 32)
        visual.tabWidthOwned, visual.tabHeightOwned = nil, nil
        C.ApplyTabGeometry(parts.previewOwner, visual, tab)
        tab:ClearAllPoints()
        if index == 1 then
            tab:SetPoint("BOTTOMLEFT", parts.tabGroup, "BOTTOMLEFT", 0, 0)
        else
            tab:SetPoint("LEFT", parts.tabs[index - 1], "RIGHT", 1 + c.tabGap, 0)
        end
        C.PlaceTabMarker(visual.tabLine, tab, c)
        C.Tint(visual.tabLine, c.accentColor, c.accentAlpha)
        C.ColorTab(parts.previewOwner, visual, index == 1)
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

local function Input(parts, c, top)
    local input = parts.input
    input:ClearAllPoints()
    input:SetSize(parts.nativeInputWidth or parts.sample:GetWidth() + 28, parts.nativeInputHeight or 32)
    input:SetPoint(parts.nativeInputPoint or "TOPLEFT", parts.sample, parts.nativeInputRelativePoint or "BOTTOMLEFT",
        parts.nativeInputX or -5, parts.nativeInputY or -2)
    local fonts = parts.fonts
    if fonts.input then parts.prompt:SetFont(fonts.input, fonts.inputSize, fonts.inputFlags) end
    parts.visual.inputMoved, parts.visual.inputHeightOwned = nil, nil
    C.PreviewInput(parts.previewOwner, parts.visual, parts.sample, input)
    parts.inputFill, parts.inputEdges = parts.visual.input, parts.visual.inputEdges
end

local function Messages(parts)
    local texts = parts.messageTexts or {}
    parts.messageTexts = texts
    local count = 0
    for text in (parts.text or ""):gmatch("[^\n]+") do count = count + 1 texts[count] = text end
    count = math.min(count, #parts.messageLines)
    local point, opposite = parts.insertTop and "TOPLEFT" or "BOTTOMLEFT", parts.insertTop and "BOTTOMLEFT" or "TOPLEFT"
    for index, line in ipairs(parts.messageLines) do
        line:ClearAllPoints()
        if index == 1 then
            line:SetPoint(point, parts.sample, point, 0, 0)
        else
            line:SetPoint(point, parts.messageLines[index - 1], opposite, 0, (parts.messageSpacing or 0) * (parts.insertTop and -1 or 1))
        end
        line:SetText(index <= count and texts[count - index + 1] or "")
        line:SetTextColor(1, 1, 1, 1)
        line:SetShown(index <= count)
    end
    parts.sample.visibleLines = parts.messageLines
    C.PaintMessageLines(parts.previewOwner, parts.sample)
    local first, last = parts.lines, parts.messageLines[math.max(1, count)]
    parts.textHit:ClearAllPoints()
    parts.textHit:SetPoint("TOPLEFT", parts.insertTop and first or last, "TOPLEFT", 0, 0)
    parts.textHit:SetPoint("BOTTOMRIGHT", parts.insertTop and last or first, "BOTTOMRIGHT", 0, 0)
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
    Messages(parts)
    local top = C.HeaderTop(c, parts.sample)
    C.PreviewPanel(parts.previewOwner, visual, parts.sample, top)
    parts.strip:ClearAllPoints()
    parts.strip:SetPoint("TOPLEFT", parts.sample, "TOPLEFT", -c.padding + (c.tabX or 0), top + (c.tabY or 0))
    parts.strip:SetPoint("BOTTOMRIGHT", parts.sample, "TOPRIGHT", c.padding + (c.tabX or 0), c.tabY or 0)
    C.PaintDockGradient(parts.strip, c)
    parts.strip:SetShown(c.tabPanel and c.panelAlpha > 0)
    Tabs(parts, c, top)
    Sidebar(parts, c)
    Input(parts, c, top)
    parts.copy:ClearAllPoints()
    parts.copy:SetPoint("TOPRIGHT", parts.sample, "TOPRIGHT", -4 + c.copyButtonX, math.max(21, top) - 3 + c.copyButtonY)
    C.Tint(parts.copyFill, c.panelColor, 95)
    parts.copy:SetShown(c.copyMessages)
    -- Keep the older preview's inspection fields pointing to runtime art.
    parts.fill, parts.fadeLeft, parts.fadeRight = visual.panel, visual.gradientLeft, visual.gradientRight
end

function S.ChatPaintPreviewSidebarHover(parts, entry)
    C.RefreshSidebarButton(parts.previewOwner, entry)
end
