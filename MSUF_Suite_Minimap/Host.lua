local _, P = ...
local NS, S = P.NS, P.Suite
-- Minimap runtime. The files share P.Minimap and load in this order: Host,
-- Input, Elements, Drawer, Info, Tooltips, Controller (Controller installs M).
-- The suite owns a host frame and borrows Blizzard's Minimap: the map moves one
-- frame after a request (a synchronous reparent inside a Blizzard panel path
-- taints that path), MinimapCluster stays shown at alpha 0 so Edit Mode and its
-- children keep running, and every write to a Blizzard frame is recorded so
-- Disable can put it back.
local MM = {}
P.Minimap = MM
-- rotateMinimap is declared on the catalog entry (restored on disable).
local M = {}
MM.M = M
local weak = { __mode = "k" }
local MEDIA = "Interface\\AddOns\\MSUF_Suite_Modules\\Media\\Minimap\\"
MM.ANCHORS = NS.MinimapAnchorPoints
-- Square: a solid texture. Circle: Blizzard's own round mask. Wide (3:2): the band
-- mask crops terrain, the clipping parent confines blips (they ignore the mask).
local MASKS = { "Interface\\ChatFrame\\ChatFrameBackground", MEDIA .. "Circle.tga", MEDIA .. "Wide.tga" }
MM.MASKS = MASKS
local SHAPES = { "SQUARE", "ROUND", "SQUARE" }
local WIDE = 2 / 3
local SHADOW_STRENGTHS = { 0.45, 0.25, 0.12 }
local HYBRID_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WRAP = "CLAMPTOBLACKADDITIVE"
local DRIVERS = { [2] = "[combat] show; hide", [3] = "[combat] hide; show" }
-- The underlay exists on WoW Forever's Camelot skin only.
local TEXTURES = { "MinimapCompassTexture", "MinimapCompassTextureUnderlay" }

local Finite, Dispatch = S.Finite, S.Dispatch
local function Usable(frame)
    return type(frame) == "table" and not NS.Safety.IsForbidden(frame)
end
MM.Usable = Usable


-- One physical pixel in host units; 1 when the client cannot tell.
function MM.Pixel()
    local host = MM.host
    local factor = PixelUtil.GetPixelToUIUnitFactor()
    local scale = host and host:GetEffectiveScale()
    if Finite(factor) and factor > 0 and Finite(scale) and scale > 0 then return factor / scale end
    return 1
end

function MM.Snap(value, pixel)
    pixel = pixel or MM.Pixel()
    return math.floor(value / pixel + 0.5) * pixel
end

-- Marks an apply category for the next Refresh (e.g. the one queued after combat).
function MM.Force(category)
    if M.force then M.force[category] = true end
end

-- One hover state serves every mouseover option (Input owns the catcher).
MM.hovered = false
local hoverListeners = {}
function MM.OnHover(callback) hoverListeners[#hoverListeners + 1] = callback end

function MM.Revealed() return MM.hovered or S.editMode == true end

-- Listeners belong to different features (zoom buttons, rows, drawer, texts,
-- mouseover size); one that raises must not leave the others stale.
function MM.NotifyHover()
    local shown = MM.Revealed()
    for i = 1, #hoverListeners do Dispatch(hoverListeners[i], shown) end
end

-- Several files need the same events; one context callback routes them, and
-- a handler that raises does not stop the other features' handlers.
local routes = {}
local function Route(module, event, ...)
    local set = routes[event]
    if not set then return end
    for i = 1, #set do
        local handler = set[i].handler
        if handler then Dispatch(handler, module, event, ...) end
    end
end
function MM.Listen(event, key, handler)
    local set = routes[event]
    if not set then
        set = {}
        routes[event] = set
    end
    local found
    for i = 1, #set do if set[i].key == key then found = set[i] end end
    if found then found.handler = handler else set[#set + 1] = { key = key, handler = handler } end
    M.context:Event(event, Route, true)
end

function MM.Unlisten(event, key)
    local set = routes[event]
    if not set then return end
    local live = false
    for i = 1, #set do
        if set[i].key == key then set[i].handler = nil end
        if set[i].handler then live = true end
    end
    if not live then
        routes[event] = nil
        M.context:RemoveEvent(event)
    end
end

function MM.UnlistenAll()
    for event in pairs(routes) do
        routes[event] = nil
        M.context:RemoveEvent(event)
    end
end

-- Deferred work runs once per frame in a fixed order. Hooks only queue, so no
-- suite code runs inside a Blizzard call chain. A kind that raises does not
-- strand the later kinds: nothing re-arms the flush for work already queued.
local pending, flushers = {}, {}
MM.flushers = flushers
local ORDER = { "claim", "mask", "rotate", "stale", "hoverSize", "rows", "drawer", "hover" }
local scheduled = false
local function Flush()
    scheduled = false
    for i = 1, #ORDER do
        local kind = ORDER[i]
        if pending[kind] then
            pending[kind] = nil
            if M.active and flushers[kind] then Dispatch(flushers[kind]) end
        end
    end
end
function MM.Queue(kind)
    pending[kind] = true
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, Flush)
end

-- Frames the suite moves (Blizzard buttons, zoom buttons, addon buttons). The
-- original placement is recorded once; the wanted placement is re-asserted
-- one frame after anyone else calls SetPoint or SetParent on the frame.
local owned, hooked, stale = setmetatable({}, weak), setmetatable({}, weak), setmetatable({}, weak)
MM.owned = owned
MM.placing, MM.placingMap = false, false
local function Moved(frame)
    if MM.placing or not M.active or not owned[frame] then return end
    stale[frame] = true
    MM.Queue("stale")
end
local function Record(frame)
    local record = {
        parent = frame:GetParent(),
        scale = frame:GetScale(),
        strata = frame:GetFrameStrata(),
        level = frame:GetFrameLevel(),
        points = {}
    }
    for i = 1, frame:GetNumPoints() do
        local point, relative, relativePoint, x, y = frame:GetPoint(i)
        if not (S.Public(point) and S.Public(relative) and Finite(x) and Finite(y)) then
            record.points = nil
            break
        end
        record.points[i] = { point, relative, relativePoint, x, y }
    end
    return record
end
-- Strata and level changes respect frames that lock them (LibDBIcon does).
local function SetLayer(frame, strata, level)
    if strata then
        local fixed = frame:HasFixedFrameStrata() == true
        if fixed then frame:SetFixedFrameStrata(false) end
        frame:SetFrameStrata(strata)
        if fixed then frame:SetFixedFrameStrata(true) end
    end
    if level then
        local fixed = frame:HasFixedFrameLevel() == true
        if fixed then frame:SetFixedFrameLevel(false) end
        frame:SetFrameLevel(level)
        if fixed then frame:SetFixedFrameLevel(true) end
    end
end
MM.SetLayer = SetLayer
-- The hooks on owned frames and on the map ignore the suite's own writes
-- while MM.placing or MM.placingMap is set. Those writes go to Blizzard and
-- addon frames and may raise: Dispatch reports the error and the flag is
-- cleared either way, or no later move would be re-asserted.
local function Placing(flag, write, ...)
    MM[flag] = true
    Dispatch(write, ...)
    MM[flag] = false
end
-- Offsets are given in parent units; SetPoint works in the frame's own scale.
local function WriteWant(frame, want)
    if frame:GetParent() ~= want.parent then frame:SetParent(want.parent) end
    SetLayer(frame, want.strata, want.level)
    if want.scale and frame:GetScale() ~= want.scale then frame:SetScale(want.scale) end
    local scale = frame:GetScale()
    if not Finite(scale) or scale <= 0 then scale = 1 end
    frame:ClearAllPoints()
    frame:SetPoint(want.point, want.relative, want.relativePoint, want.x / scale, want.y / scale)
end
local function Put(frame, want)
    Placing("placing", WriteWant, frame, want)
end
-- A protected frame cannot move in combat; the refresh after combat lays out again.
local function Defer()
    MM.Force("elements")
    MM.Force("drawer")
    S.Queue("minimap")
end
MM.Defer = Defer
function MM.Place(frame, parent, point, relative, relativePoint, x, y, scale, strata, level)
    if not Usable(frame) then return false end
    x, y = x or 0, y or 0
    if NS.IsCombatLocked() and frame:IsProtected() then
        Defer()
        return false
    end
    local record = owned[frame]
    if not record then
        record = Record(frame)
        owned[frame] = record
        if not hooked[frame] then
            hooked[frame] = true
            hooksecurefunc(frame, "SetPoint", Moved)
            hooksecurefunc(frame, "SetParent", Moved)
        end
    end
    local want = record.want
    if want and not stale[frame] and frame:GetParent() == parent and want.point == point and want.relative == relative
        and want.relativePoint == relativePoint and want.x == x and want.y == y and want.scale == scale
        and want.strata == strata and want.level == level then
        return true
    end
    want = want or {}
    record.want = want
    want.parent, want.point, want.relative, want.relativePoint = parent, point, relative, relativePoint
    want.x, want.y, want.scale, want.strata, want.level = x, y, scale, strata, level
    stale[frame] = nil
    Put(frame, want)
    MM.HookHover(frame)
    local children = { frame:GetChildren() }
    for i = 1, #children do MM.HookHover(children[i]) end
    return true
end

function MM.Reassert(frame)
    if owned[frame] then
        stale[frame] = true
        MM.Queue("stale")
    end
end

flushers.stale = function()
    local combat = NS.IsCombatLocked()
    for frame in pairs(stale) do
        local record = owned[frame]
        if not record or not record.want or not Usable(frame) then
            stale[frame] = nil
        elseif combat and frame:IsProtected() then
            Defer()
        else
            stale[frame] = nil
            Put(frame, record.want)
        end
    end
end
local function WriteRecord(frame, record)
    frame:SetParent(record.parent)
    SetLayer(frame, record.strata, record.level)
    if Finite(record.scale) and record.scale > 0 then frame:SetScale(record.scale) end
    if record.points then
        frame:ClearAllPoints()
        for i = 1, #record.points do
            local point = record.points[i]
            frame:SetPoint(point[1], point[2], point[3], point[4], point[5])
        end
    end
end
-- Returns the frame to its recorded placement unless another owner took it.
function MM.Release(frame)
    local record = owned[frame]
    if not record then return end
    owned[frame], stale[frame] = nil, nil
    if not Usable(frame) or (record.want and frame:GetParent() ~= record.want.parent) then return end
    Placing("placing", WriteRecord, frame, record)
end

local function HostShown()
    -- Buttons may have changed while the host was hidden; their scripts stayed quiet.
    if M.active then
        MM.Queue("rows")
        MM.Queue("drawer")
    end
end
function MM.EnsureFrames()
    if MM.host then return MM.host end
    local host = S.CreateFrame("Frame", "MSUFSuiteMinimap", UIParent)
    host:SetFrameStrata("LOW")
    host:EnableMouse(false)
    host:SetClampedToScreen(true)
    host:Hide()
    -- UI modes hide frames by roleset; tag the host like Blizzard's cluster.
    host:AddRoleset("minimap")
    host:SetScript("OnShow", HostShown)
    local level = host:GetFrameLevel()
    local border = S.CreateFrame("Frame", nil, host)
    border:SetAllPoints(host)
    border:SetFrameLevel(level + 1)
    border:EnableMouse(false)
    local edges = {}
    for i = 1, 4 do edges[i] = S.CreateTexture(border, nil, "BORDER") end
    local disc = S.CreateTexture(border, nil, "BACKGROUND")
    disc:SetTexture(MEDIA .. "Circle.tga")
    disc:SetPoint("CENTER", host, "CENTER")
    local clip = S.CreateFrame("Frame", nil, host)
    clip:SetAllPoints(host)
    clip:SetFrameLevel(level + 2)
    clip:EnableMouse(false)
    -- Unwanted Blizzard buttons wait here: hidden, without mouse or OnUpdate.
    local park = S.CreateFrame("Frame", nil, host)
    park:SetSize(1, 1)
    park:SetPoint("CENTER", host, "CENTER")
    park:Hide()
    MM.host, MM.borderFrame, MM.edges, MM.disc, MM.clip, MM.park = host, border, edges, disc, clip, park
    MM.mapLevel = level + 3
    if NS.MinimapStyle then MM.style = NS.MinimapStyle.Create(host, level + 1, level + 8) end
    return host
end

function MM.Dimensions()
    local c, pixel = M.config, MM.Pixel()
    local hovered = c.hoverResize and MM.hovered and not S.editMode
    local width = MM.Snap(hovered and c.hoverWidth or c.size, pixel)
    local height = hovered and c.shape ~= 2 and MM.Snap(c.hoverHeight, pixel)
        or c.shape == 3 and MM.Snap(c.size * WIDE, pixel) or width
    return width, height, hovered and true or false
end

function MM.ApplyHost()
    local host, c = MM.host, M.config
    local pixel = MM.Pixel()
    local width, height, hovered = MM.Dimensions()
    MM.width, MM.height, MM.hoverGeometryActive = width, height, hovered
    host:SetSize(width, height)
    local anchor = MM.ANCHORS[c.point] or "TOPRIGHT"
    host:ClearAllPoints()
    host:SetPoint(anchor, UIParent, anchor, MM.Snap(c.x, pixel), MM.Snap(c.y, pixel))
    -- Keep the original map footprint in the hover area when a smaller
    -- mouseover size would otherwise put the cursor outside the new host.
    local baseWidth = MM.Snap(c.size, pixel)
    local baseHeight = c.shape == 3 and MM.Snap(c.size * WIDE, pixel) or baseWidth
    local dw, dh = math.max(0, baseWidth - width), math.max(0, baseHeight - height)
    local left = anchor:find("RIGHT", 1, true) and dw or anchor:find("LEFT", 1, true) and 0 or dw / 2
    local top = anchor:find("BOTTOM", 1, true) and dh or anchor:find("TOP", 1, true) and 0 or dh / 2
    MM.SetExtent("hoverSize", left, dw - left, top, dh - top)
end

local function BorderRGB()
    local c = M.config
    if c.borderClassColor then
        local _, token = UnitClass("player")
        if S.Public(token) then
            local r, g, b = S.ClassRGB(token)
            if r then return r, g, b end
        end
    end
    return S.RGB(c.borderColor)
end
MM.BorderRGB = BorderRGB
function MM.BorderWidth() return M.config.borderSize * MM.Pixel() end

local function EnsureShadows()
    if MM.shadows then return MM.shadows end
    local shadows = {}
    for step = 1, 3 do
        local ring = { edges = {} }
        -- CreateTexture(name, layer, template, subLevel): the fourth argument
        -- is a template name, so leave it nil before the negative draw level.
        for side = 1, 4 do ring.edges[side] = S.CreateTexture(MM.borderFrame, nil, "BACKGROUND", nil, -8 + step) end
        ring.disc = S.CreateTexture(MM.borderFrame, nil, "BACKGROUND", nil, -8 + step)
        ring.disc:SetTexture(MEDIA .. "Circle.tga")
        ring.disc:SetPoint("CENTER", MM.host, "CENTER")
        shadows[step] = ring
    end
    MM.shadows = shadows
    return shadows
end
-- Four edges of a square ring outside the host, from inner to outer distance
-- (the border is the ring from 0 to its thickness), plus the matching disc
-- behind a round map, whose own mask cuts the ring.
local function PlaceRing(edges, disc, inner, outer, r, g, b, alpha, shown, round)
    local host = MM.host
    local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
    local band = outer - inner
    top:ClearAllPoints()
    top:SetPoint("BOTTOMLEFT", host, "TOPLEFT", -outer, inner)
    top:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", outer, inner)
    top:SetHeight(band)
    bottom:ClearAllPoints()
    bottom:SetPoint("TOPLEFT", host, "BOTTOMLEFT", -outer, -inner)
    bottom:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", outer, -inner)
    bottom:SetHeight(band)
    left:ClearAllPoints()
    left:SetPoint("TOPRIGHT", host, "TOPLEFT", -inner, inner)
    left:SetPoint("BOTTOMRIGHT", host, "BOTTOMLEFT", -inner, -inner)
    left:SetWidth(band)
    right:ClearAllPoints()
    right:SetPoint("TOPLEFT", host, "TOPRIGHT", inner, inner)
    right:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", inner, -inner)
    right:SetWidth(band)
    for i = 1, 4 do
        edges[i]:SetColorTexture(r, g, b, alpha)
        edges[i]:SetShown(shown and not round)
    end
    disc:SetSize(MM.width + outer * 2, MM.height + outer * 2)
    disc:SetVertexColor(r, g, b, alpha)
    disc:SetShown(shown and round)
end

-- Three fading rings past the border; created the first time a shadow shows.
local function ApplyShadows(c, thickness, shadow, round)
    local shadows = shadow > 0 and EnsureShadows() or MM.shadows
    if not shadows then return end
    local r, g, b = S.RGB(c.shadowColor)
    for step = 1, 3 do
        local ring = shadows[step]
        local alpha = c.shadowAlpha / 100 * SHADOW_STRENGTHS[step]
        PlaceRing(ring.edges, ring.disc, thickness + shadow * (step - 1) / 3, thickness + shadow * step / 3,
            r, g, b, alpha, shadow > 0 and alpha > 0, round)
    end
end

-- The clamp rect includes the border, the shadow and the ornament outside the map.
local function ClampOutside(c, reach)
    if not MM.style then return reach end
    MM.style:Paint(c, 1, nil, true, MM.width, MM.height)
    local extent = math.max(MM.width, MM.height)
    if c.styleTexture ~= 1 and c.styleAlpha > 0 then
        reach = math.max(reach, math.max(0, extent * (c.styleScale / 100 - 1) / 2)
            + math.max(math.abs(c.styleX), math.abs(c.styleY)))
    end
    if c.styleGlow and c.styleGlowAlpha > 0 then
        reach = math.max(reach, math.max(0, extent * (c.styleGlowScale / 100 - 1) / 2))
    end
    if c.styleBackdrop then reach = math.max(reach, c.styleBackdropPadding) end
    return reach
end

function MM.ApplyBorder()
    local c = M.config
    local thickness = MM.BorderWidth()
    local r, g, b = BorderRGB()
    local round = c.shape == 2
    PlaceRing(MM.edges, MM.disc, 0, thickness, r, g, b, c.borderAlpha / 100, thickness > 0, round)
    local shadow = c.shadowSize * MM.Pixel()
    ApplyShadows(c, thickness, shadow, round)
    local outer = ClampOutside(c, thickness + shadow)
    MM.host:SetClampRectInsets(-outer, outer, outer, -outer)
end

local function Nudge(map)
    -- The engine re-renders terrain only on a zoom change after a size or mask change.
    local zoom, levels = map:GetZoom(), map:GetZoomLevels()
    if not Finite(zoom) or not Finite(levels) or levels < 2 then return end
    map:SetZoom(zoom > 0 and zoom - 1 or zoom + 1)
    map:SetZoom(zoom)
end
local function BlobScalars(map, value)
    map:SetArchBlobRingScalar(value)
    map:SetQuestBlobRingScalar(value)
    map:SetTaskBlobRingScalar(value)
end
-- Blizzard_HybridMinimap loads on demand (AddonLoaded applies this again);
-- its CircleMask is a parent key on both clients.
function MM.ApplyHybrid()
    local hybrid = _G.HybridMinimap
    if not Usable(hybrid) then return end
    local mask = hybrid.CircleMask
    if MM.hybridTexture == nil then
        local current = mask:GetTexture()
        MM.hybridTexture = S.Public(current) and current or HYBRID_MASK
    end
    local shape = M.config.shape
    local texture = shape == 2 and MM.hybridTexture or shape == 3 and MM.hoverGeometryActive and MASKS[1]
        or MASKS[shape] or MASKS[2]
    mask:SetTexture(texture, WRAP, WRAP)
    MM.hybridShaped = true
end

function MM.ReleaseHybrid()
    local hybrid = _G.HybridMinimap
    if MM.hybridShaped and Usable(hybrid) then
        hybrid.CircleMask:SetTexture(MM.hybridTexture or HYBRID_MASK, WRAP, WRAP)
    end
    MM.hybridShaped = nil
end

local function WriteMap(map, size)
    local clip = MM.clip
    map:SetFixedFrameStrata(false)
    map:SetFixedFrameLevel(false)
    if map:GetParent() ~= clip then map:SetParent(clip) end
    map:SetFrameStrata(MM.host:GetFrameStrata())
    map:SetFrameLevel(MM.mapLevel)
    map:SetFixedFrameStrata(true)
    map:SetFixedFrameLevel(true)
    if map:GetScale() ~= 1 then map:SetScale(1) end
    map:ClearAllPoints()
    map:SetPoint("CENTER", clip, "CENTER", 0, 0)
    map:SetSize(size, size)
end
-- Canvas: always square; the host and clipping frame define the visible rect.
-- Hit insets keep hidden horizontal or vertical bands from taking the mouse.
function MM.ApplyMap(nudge)
    local map, clip, c = _G.Minimap, MM.clip, M.config
    if not Usable(map) or not clip then return end
    local width, height = MM.width or MM.Snap(c.size), MM.height or MM.Snap(c.size)
    local size = math.max(width, height)
    local xBand, yBand = (size - width) / 2, (size - height) / 2
    Placing("placingMap", WriteMap, map, size)
    map:SetHitRectInsets(xBand, xBand, yBand, yBand)
    clip:SetClipsChildren(c.shape == 3 or width ~= height)
    map:SetMaskTexture(c.shape == 3 and MM.hoverGeometryActive and MASKS[1] or MASKS[c.shape] or MASKS[2])
    BlobScalars(map, c.shape == 2 and 1 or 0)
    MM.ApplyHybrid()
    if nudge then Nudge(map) end
end

local mapHooked = setmetatable({}, weak)
local function MapParentChanged(_, parent)
    if MM.placingMap or not M.active or not M.mapOwned or parent == MM.clip then return end
    M.mapOwned = false
    if NS.IsCombatLocked() then S.Queue("minimap") else MM.Queue("claim") end
end
function MM.HookMap()
    local map = _G.Minimap
    if Usable(map) and not mapHooked[map] then
        mapHooked[map] = true
        hooksecurefunc(map, "SetParent", MapParentChanged)
    end
end

-- Neutralise, never destroy: the cluster stays shown (alpha 0, no mouse), only
-- decorative textures fade, and MinimapBackdrop keeps running (encounter tools
-- read the compass rotation from it).
function MM.ApplyDecorations()
    local ctx, cluster = M.context, _G.MinimapCluster
    if Usable(cluster) then
        ctx:Alpha(cluster, 0)
        ctx:Property(cluster, "IsMouseEnabled", "EnableMouse", false)
        if Usable(cluster.ZoneTextButton) then ctx:HideControl(cluster.ZoneTextButton, true) end
        -- Emptied by the element row; hidden so it cannot stretch the cluster's layout.
        if Usable(cluster.IndicatorFrame) then ctx:Property(cluster.IndicatorFrame, "IsShown", "SetShown", false) end
        -- WoW Forever's coordinate readout polls while shown; the suite has its own.
        local container = cluster.MinimapContainer
        if Usable(container) and Usable(container.PlayerCoords) then
            ctx:Property(container.PlayerCoords, "IsShown", "SetShown", false)
        end
    end
    for i = 1, #TEXTURES do
        local texture = _G[TEXTURES[i]]
        if Usable(texture) then ctx:Alpha(texture, 0) end
    end
    -- Loaded with Blizzard_TimeManager (AddonLoaded applies this again).
    local clock = _G.TimeManagerClockButton
    if Usable(clock) then ctx:HideControl(clock, true) end
end

local mapRecord
local function MapRecord(map)
    local record = Record(map)
    record.width, record.height = map:GetSize()
    record.fixedStrata = map:HasFixedFrameStrata() == true
    record.fixedLevel = map:HasFixedFrameLevel() == true
    record.insets = { map:GetHitRectInsets() }
    return record
end

-- One-time import of Blizzard's own size and position, as the nearest of the
-- nine screen anchors so the map keeps its place across resolutions.
function MM.Capture()
    local map, values, c = _G.Minimap, { captured = true }, M.config
    if Usable(map) then
        local mapScale, uiScale = map:GetEffectiveScale(), UIParent:GetEffectiveScale()
        local width, cx, cy = map:GetWidth(), map:GetCenter()
        local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
        if Finite(mapScale) and Finite(uiScale) and uiScale > 0 and Finite(width) and width > 0 and Finite(cx)
            and Finite(cy) and Finite(screenW) and Finite(screenH) then
            local ratio = mapScale / uiScale
            local size = math.max(100, math.min(600, width * ratio))
            local halfW, halfH = size / 2, (c.shape == 3 and size * WIDE or size) / 2
            cx, cy = cx * ratio, cy * ratio
            local column = cx < screenW / 3 and 1 or cx > screenW * 2 / 3 and 3 or 2
            local row = cy > screenH * 2 / 3 and 1 or cy < screenH / 3 and 3 or 2
            values.size, values.point = math.floor(size + 0.5), (row - 1) * 3 + column
            local x = column == 1 and cx - halfW or column == 3 and cx + halfW - screenW or cx - screenW / 2
            local y = row == 1 and cy + halfH - screenH or row == 3 and cy - halfH or cy - screenH / 2
            values.x, values.y = math.floor(x + 0.5), math.floor(y + 0.5)
        end
    end
    S.SetMany("minimap", values)
end

-- Edit Mode applies the user's layout in its EDIT_MODE_LAYOUTS_UPDATED handler;
-- until then Blizzard's map is still at its default place.
function MM.PrepareCapture()
    M.captureWaiting = nil
    if M.config.captured then return end
    local manager = _G.EditModeManagerFrame
    if Usable(manager) and not manager:IsInitialized() then
        M.captureWaiting = true
        MM.Listen("EDIT_MODE_LAYOUTS_UPDATED", "capture", function()
            MM.Unlisten("EDIT_MODE_LAYOUTS_UPDATED", "capture")
            M.captureWaiting = nil
            MM.Queue("claim")
        end)
    end
end

flushers.claim = function()
    if M.mapOwned then return end
    if NS.IsCombatLocked() then
        S.Queue("minimap")
        return
    end
    local map = _G.Minimap
    if not Usable(map) or not MM.clip then return end
    if not M.config.captured then
        if M.captureWaiting then return end
        MM.Capture()
        if not M.active or M.mapOwned then return end
    end
    mapRecord = mapRecord or MapRecord(map)
    MM.ApplyMap(true)
    M.mapOwned = true
    MM.ApplyDecorations()
end

local function RestoreMap(map, record, parent, lost)
    map:SetFixedFrameStrata(false)
    map:SetFixedFrameLevel(false)
    map:SetParent(parent)
    map:SetFrameStrata(record.strata)
    map:SetFrameLevel(record.level)
    if Finite(record.scale) and record.scale > 0 then map:SetScale(record.scale) end
    map:ClearAllPoints()
    if lost then
        map:SetPoint("CENTER", parent, "CENTER")
    else
        for i = 1, #record.points do
            local point = record.points[i]
            map:SetPoint(point[1], point[2], point[3], point[4], point[5])
        end
    end
    if Finite(record.width) and Finite(record.height) then map:SetSize(record.width, record.height) end
    map:SetFixedFrameStrata(record.fixedStrata)
    map:SetFixedFrameLevel(record.fixedLevel)
end

-- Returns true when Blizzard's layout could not be restored exactly.
function MM.ReleaseMap()
    local map, record = _G.Minimap, mapRecord
    mapRecord, M.mapOwned = nil, false
    if not record then return false end
    if not Usable(map) then return true end
    local parent, lost = record.parent, record.points == nil
    if not Usable(parent) then
        local cluster = _G.MinimapCluster
        parent, lost = cluster and cluster.MinimapContainer, true
        if not Usable(parent) then return true end
    end
    Placing("placingMap", RestoreMap, map, record, parent, lost)
    local insets = record.insets
    if Finite(insets[1]) and Finite(insets[3]) then
        map:SetHitRectInsets(insets[1], insets[2], insets[3], insets[4])
    end
    -- No getter exists for masks or blob scalars: Blizzard's defaults are known.
    -- WoW Forever's Camelot skin (marked by its underlay texture) uses its own mask.
    map:SetMaskTexture(_G.MinimapCompassTextureUnderlay and "ui-hud-minimap-frame-generic-mask" or MASKS[2])
    BlobScalars(map, 1)
    Nudge(map)
    return lost
end

-- LibDBIcon and HereBeDragons ask this global for the map shape. Only defined
-- while active; a previous definition returns on disable.
local previousShape, installedShape
local function MinimapShape() return SHAPES[M.config and M.config.shape] or "ROUND" end
MM.MinimapShape = MinimapShape
function MM.InstallShape()
    if installedShape then return end
    installedShape, previousShape = true, _G.GetMinimapShape
    _G.GetMinimapShape = MinimapShape
end

function MM.RemoveShape()
    if installedShape and _G.GetMinimapShape == MinimapShape then _G.GetMinimapShape = previousShape end
    installedShape, previousShape = nil, nil
end

-- Show/Hide, never alpha: the engine draws terrain and blips regardless of
-- alpha. The map is protected, so combat conditions use a state driver that is
-- (un)registered out of combat only; mouseover waits for combat to end.
local function Mode()
    if S.editMode then return 1 end
    return M.config.visibility
end
MM.VisibilityMode = Mode
function MM.ApplyVisibility()
    local host = MM.host
    if not host or NS.IsCombatLocked() then return end
    local mode = Mode()
    local driver = DRIVERS[mode]
    if M.driver ~= driver then
        if M.driver then UnregisterStateDriver(host, "visibility") end
        M.driver = driver
        if driver then RegisterStateDriver(host, "visibility", driver) end
    end
    if driver then return end
    if mode == 5 then host:Hide() elseif mode == 4 then host:SetShown(MM.hovered) else host:Show() end
    MM.UpdateCatcherLayer()
end

MM.OnHover(function()
    if not M.active or not MM.host or Mode() ~= 4 then return end
    if NS.IsCombatLocked() then S.Queue("minimap") else MM.host:SetShown(MM.hovered) end
end)

function MM.ReleaseHost()
    local host = MM.host
    if host and M.driver then UnregisterStateDriver(host, "visibility") end
    M.driver, M.captureWaiting = nil, nil
    MM.ReleaseHybrid()
    local lost = MM.ReleaseMap()
    if host then host:Hide() end
    return lost
end
