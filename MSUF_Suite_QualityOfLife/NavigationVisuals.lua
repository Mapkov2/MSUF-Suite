local _, Private = ...
local Suite, Navigation = Private.Suite, Private.Navigation
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function Shown(frame, on)
    if frame:IsShown() ~= on then frame:SetShown(on) end
end

local function Text(region, value)
    if region.navigationText ~= value then
        region.navigationText = value
        region:SetText(value)
    end
end

local function Label(parent)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    return label
end

local function Symbol(parent)
    local holder = Suite.CreateFrame("Frame", nil, parent)
    holder:SetPoint("CENTER")
    holder.icon = Suite.CreateTexture(holder, nil, "ARTWORK")
    holder.icon:SetAtlas("Waypoint-MapPin-Tracked")
    holder.icon:SetAllPoints()
    return holder
end

function Navigation.NewView(parent)
    local root = Suite.CreateFrame("Frame", nil, parent)
    root:SetSize(64, 64)
    root:EnableMouse(false)
    local view = { root = root }
    view.waypoint = Symbol(root)
    view.beam = Suite.CreateTexture(view.waypoint, nil, "BACKGROUND")
    view.beam:SetTexture(WHITE)
    view.beam:SetPoint("BOTTOM", view.waypoint, "CENTER")
    view.card = Suite.CreateFrame("Frame", nil, root)
    view.card:SetPoint("BOTTOM", root, "CENTER", 0, 22)
    view.fill = Suite.CreateTexture(view.card, nil, "BACKGROUND")
    view.fill:SetAllPoints()
    view.edges = {}
    for index = 1, 4 do view.edges[index] = Suite.CreateTexture(view.card, nil, "BORDER") end
    view.title, view.info = Label(view.card), Label(view.card)
    view.title:SetPoint("TOP", 0, -10)
    view.info:SetPoint("TOP", view.title, "BOTTOM", 0, -5)
    view.tip = Suite.CreateTexture(root, nil, "ARTWORK")
    view.tip:SetAtlas("Navigation-Tracked-Arrow")
    view.tip:SetPoint("CENTER", root, "CENTER", 0, 20)
    view.distance = Label(root)
    view.distance:SetPoint("TOP", root, "BOTTOM", 0, -2)
    view.name = Label(root)
    view.name:SetPoint("TOP", view.distance, "BOTTOM", 0, -3)
    view.root:Hide()
    return view
end

function Navigation.Style(view, config)
    local font = Suite.ResolveFont(config.font) or Suite.GlobalFontPath()
    Suite.SetStyledFont(view.title, font, config.fontSize, "OUTLINE")
    Suite.SetStyledFont(view.info, font, math.max(10, config.fontSize - 2), "OUTLINE")
    Suite.SetStyledFont(view.distance, font, math.max(10, config.fontSize - 2), "OUTLINE")
    Suite.SetStyledFont(view.name, font, config.fontSize, "OUTLINE")
    view.name:SetWidth(config.cardWidth)
    view.name:SetTextColor(1, 1, 1)
    view.title:SetTextColor(1, 1, 1)
    view.info:SetTextColor(.8, .85, .9)
    view.distance:SetTextColor(.85, .9, .95)
    view.card:SetSize(config.cardWidth, config.showInfo and config.fontSize * 2 + 30 or config.fontSize + 20)
    view.title:SetWidth(config.cardWidth - 24)
    view.info:SetWidth(config.cardWidth - 24)
    view.waypoint:SetSize(config.markerSize, config.markerSize)
    view.waypoint.icon:SetTexture(config.shape == 2 and "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" or WHITE)
    view.waypoint.icon:SetRotation(config.shape == 2 and 0 or math.pi / 4)
    view.root:SetSize(config.markerSize + 12, config.markerSize + 12)
    view.tip:SetSize(config.markerSize * .7, config.markerSize * .7)
    view.beam:SetSize(math.max(3, config.markerSize / 6), config.beamHeight)
    local r, g, b = Suite.RGB(config.beamColor)
    view.beam:SetGradient("VERTICAL", CreateColor(r, g, b, config.beamOpacity / 100), CreateColor(r, g, b, 0))
    r, g, b = Suite.RGB(config.backgroundColor)
    view.fill:SetColorTexture(r, g, b, .86)
    view.color, view.mode, view.scale, view.alpha = nil, nil, nil, nil
    view.root:EnableMouse(config.rightClickClear == true)
end

local function Color(view, value)
    if view.color == value then return end
    view.color = value
    local r, g, b = Suite.RGB(value)
    view.waypoint.icon:SetVertexColor(r, g, b)
    view.tip:SetVertexColor(r, g, b)
    Suite.PlaceEdges(view.edges, view.card, 1, r, g, b, .8)
end

function Navigation.Paint(view, model, config)
    local mode = model.mode
    if not mode then Shown(view.root, false) return end
    Color(view, model.color)
    if view.mode ~= mode then
        view.mode = mode
        Shown(view.waypoint, mode ~= Navigation.CARD)
        Shown(view.card, mode == Navigation.CARD)
        Shown(view.tip, mode ~= Navigation.WAYPOINT)
    end
    Shown(view.beam, mode == Navigation.WAYPOINT and config.beam)
    Shown(view.info, config.showInfo)
    Text(view.title, config.showName and model.title or "")
    Text(view.info, model.info or "")
    Text(view.distance, model.readout or "")
    Text(view.name, config.showName and mode ~= Navigation.CARD and model.title or "")
    local angle = mode == Navigation.DIRECTION and model.angle or math.pi
    if view.angle ~= angle then view.tip:SetRotation(angle) view.angle = angle end
    local scale = 1
    if config.worldScale and mode == Navigation.WAYPOINT then
        scale = math.max(config.minScale / 100, math.min(config.maxScale / 100, 180 / math.max(1, model.distance)))
    end
    if view.scale ~= scale then view.root:SetScale(scale) view.scale = scale end
    local alpha = config.opacity / 100 * (model.occluded and .6 or 1) * (model.hovered and .25 or 1)
    if view.alpha ~= alpha then view.root:SetAlpha(alpha) view.alpha = alpha end
    Shown(view.root, true)
end

function Suite.DrawNavigationPreview(parent, config, model)
    local view = parent.suiteNavigationPreview
    if not view then
        view = Navigation.NewView(parent)
        parent.suiteNavigationPreview = view
    end
    Navigation.Style(view, config)
    Navigation.Paint(view, model, config)
    return view
end
