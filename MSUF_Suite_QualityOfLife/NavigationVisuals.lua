local _, Private = ...
local Suite, Navigation = Private.Suite, Private.Navigation
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- The client's cast bar spark: a soft vertical streak on black, made to be
-- drawn additively (Blizzard_NamePlateCastingBar.lua, live and forever).
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local PULSE_LIGHT, PULSE_SECONDS, PULSE_PAUSE = .35, 2.4, 1.4

local function Text(region, value)
    if region.navigationText ~= value then
        region.navigationText = value
        region:SetText(value)
    end
end

-- The distance and travel time (Navigation.Readout): written when a number
-- the text shows changed, and built by the client. The model's stamp says
-- whether the text shown is still that model's. The client gets exactly the
-- numbers the format takes.
local function Readout(view, model)
    local stamp = model.readoutStamp
    if view.readoutStamp == stamp and view.readoutModel == model then return end
    view.readoutStamp, view.readoutModel = stamp, model
    local format, a, b, c = model.readoutFormat, model.readoutA, model.readoutB, model.readoutC
    if not format then view.distance:SetText("")
    elseif c ~= nil then view.distance:SetFormattedText(format, a, b, c)
    elseif b ~= nil then view.distance:SetFormattedText(format, a, b)
    else view.distance:SetFormattedText(format, a) end
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

local function Additive(parent, level, file)
    local texture = Suite.CreateTexture(parent, nil, "BACKGROUND", nil, level)
    texture:SetTexture(file)
    texture:SetBlendMode("ADD")
    return texture
end

-- The light beam, behind the symbol: a wide soft glow (the upper half of the
-- spark, brightest at the symbol), a thin core that fades upward, and a pulse
-- of light that rises along both. The pulse is an animation group, so the
-- client moves it and no Lua runs while it plays. It rests invisible.
-- All three are drawn additively: light on the world, never a dark shape.
local function Beam(view)
    local holder = view.waypoint
    view.beam = Additive(holder, 0, SPARK)
    view.beam:SetTexCoord(0, 1, 0, .5)
    view.beam:SetPoint("BOTTOM", holder, "CENTER")
    view.core = Additive(holder, 1, WHITE)
    view.core:SetPoint("BOTTOM", holder, "CENTER")
    view.pulse = Additive(holder, 2, SPARK)
    view.pulse:SetPoint("CENTER", holder, "CENTER")
    view.pulse:SetAlpha(0)
    -- Two steps, the way Blizzard's alert frames sequence a fade
    -- (AlertFrameSystems.xml): the pulse lights up at the symbol, then rises
    -- and fades, and the loop waits before the next one.
    local group = view.pulse:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    local light = group:CreateAnimation("Alpha")
    light:SetOrder(1)
    light:SetFromAlpha(0)
    light:SetToAlpha(1)
    light:SetDuration(PULSE_LIGHT)
    view.rise = group:CreateAnimation("Translation")
    view.rise:SetOrder(2)
    view.rise:SetDuration(PULSE_SECONDS)
    local fade = group:CreateAnimation("Alpha")
    fade:SetOrder(2)
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetSmoothing("IN")
    fade:SetDuration(PULSE_SECONDS)
    fade:SetEndDelay(PULSE_PAUSE)
    view.pulseGroup = group
end

-- The pulse plays while the beam shows it and the marker is really on screen
-- (view.visible, the root's OnShow and OnHide). So it starts after the marker
-- is shown, the order Blizzard's spell alerts use, and it stops when the
-- marker is hidden by itself or with a parent (the interface, the options
-- page): a hidden marker leaves the client nothing to animate.
local function Animate(view)
    local play = view.pulses == true and view.visible == true
    if play == view.playing then return end
    view.playing = play
    if play then view.pulseGroup:Play() else view.pulseGroup:Stop() end
end

-- Shows or hides the beam; only a change touches the client.
local function ShowBeam(view, on, pulse)
    if view.beamOn == on then return end
    view.beamOn = on
    view.beam:SetShown(on)
    view.core:SetShown(on)
    view.pulse:SetShown(on)
    view.pulses = on and pulse == true
    Animate(view)
end

function Navigation.NewView(parent)
    local root = Suite.CreateFrame("Frame", nil, parent)
    root:SetSize(64, 64)
    root:EnableMouse(false)
    local view = { root = root }
    view.waypoint = Symbol(root)
    Beam(view)
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
    view.shown, view.visible = false, false
    root:SetScript("OnShow", function()
        view.visible = true
        Animate(view)
    end)
    root:SetScript("OnHide", function()
        view.visible = false
        Animate(view)
    end)
    return view
end

-- Every hide of the marker goes through here: it also stops the beam pulse,
-- so a hidden marker leaves the client nothing to animate.
function Navigation.Hide(view)
    if view.shown ~= false then
        view.shown = false
        view.root:Hide()
    end
    ShowBeam(view, false)
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
    view.info:SetShown(config.showInfo == true)
    local width, height, opacity = math.max(24, config.markerSize * 1.5), config.beamHeight, config.beamOpacity / 100
    local r, g, b = Suite.RGB(config.beamColor)
    view.beam:SetSize(width, height)
    view.beam:SetVertexColor(r, g, b, opacity)
    view.core:SetSize(math.max(3, config.markerSize / 6), height)
    view.core:SetGradient("VERTICAL", CreateColor(r, g, b, opacity), CreateColor(r, g, b, 0))
    -- Drawn additively, the pulse takes its strength from its colour; its
    -- alpha belongs to the animation.
    local strength = math.min(1, opacity * 1.5)
    view.pulse:SetSize(width * .8, height * .3)
    view.pulse:SetVertexColor(r * strength, g * strength, b * strength)
    view.rise:SetOffset(0, height * .8)
    view.pulseGroup:Stop()
    -- The marker may have a new parent (Module:Refresh): whether it is on
    -- screen is read here, in case the client ran no script for that.
    view.playing, view.visible = false, view.root:IsVisible() == true
    r, g, b = Suite.RGB(config.backgroundColor)
    view.fill:SetColorTexture(r, g, b, .86)
    view.color, view.mode, view.scale, view.alpha = nil, nil, nil, nil
    view.beamOn, view.shown = nil, nil
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

-- What a mode shows. For a destination off screen (DIRECTION) the player
-- chooses the arrow, the symbol or both (navigatorStyle); the arrow alone
-- takes the symbol's place and size.
local function Layout(view, mode, config)
    view.mode = mode
    local edge = mode == Navigation.DIRECTION and config.navigatorStyle or 1
    local size = config.markerSize * (edge == 2 and 1 or .7)
    view.arrow = mode ~= Navigation.WAYPOINT and edge ~= 3
    view.waypoint:SetShown(mode ~= Navigation.CARD and edge ~= 2)
    view.card:SetShown(mode == Navigation.CARD)
    view.tip:SetShown(view.arrow)
    view.tip:SetSize(size, size)
    view.tip:SetPoint("CENTER", view.root, "CENTER", 0, edge == 2 and 0 or 20)
end

-- A repeated paint of an unchanged marker makes no client call: every state
-- it sets is remembered on the view. The 2026-11-10 idle trace spent a
-- twentieth of the marker's time asking the client what was shown.
function Navigation.Paint(view, model, config)
    local mode = model.mode
    if not mode then Navigation.Hide(view) return end
    Color(view, model.color)
    if view.mode ~= mode then Layout(view, mode, config) end
    ShowBeam(view, mode == Navigation.WAYPOINT and config.beam == true, config.beamPulse)
    Text(view.title, config.showName and model.title or "")
    Text(view.info, model.info or "")
    Readout(view, model)
    Text(view.name, config.showName and mode ~= Navigation.CARD and model.title or "")
    local angle = mode == Navigation.DIRECTION and model.angle or math.pi
    if view.arrow and view.angle ~= angle then view.tip:SetRotation(angle) view.angle = angle end
    local scale = 1
    if config.worldScale and mode == Navigation.WAYPOINT then
        scale = math.max(config.minScale / 100, math.min(config.maxScale / 100, 180 / math.max(1, model.distance)))
    end
    if view.scale ~= scale then view.root:SetScale(scale) view.scale = scale end
    local alpha = config.opacity / 100 * (model.occluded and .6 or 1) * (model.hovered and .25 or 1)
    if view.alpha ~= alpha then view.root:SetAlpha(alpha) view.alpha = alpha end
    if not view.shown then
        view.shown = true
        view.root:Show()
    end
end

-- The direction arrow turned between two samples (Navigation.lua).
function Navigation.Turn(view, angle)
    if view.arrow and view.angle ~= angle then view.tip:SetRotation(angle) view.angle = angle end
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
