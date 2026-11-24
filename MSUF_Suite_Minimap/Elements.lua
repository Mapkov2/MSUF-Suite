local _, P = ...
local NS, S = P.NS, P.Suite
local MM = P.Minimap
local M = MM.M
local LANDING, LANDING_ICON = NS.MinimapLanding, NS.MinimapLandingIcon
local SHAPE = NS.MinimapShape
local Native = NS.MinimapElements
-- Blizzard's own minimap buttons, moved into suite slots around the map.
-- Missing buttons are skipped. Blizzard keeps deciding when each button is
-- shown (nothing here force-shows a button): a hidden button keeps an empty
-- slot outside the row, and its show/hide re-packs the row one frame later.
local Finite = S.Finite
local weak = { __mode = "k" }
local mine, watched = setmetatable({}, weak), setmetatable({}, weak)
local slots, items = {}, {}
local BASE_SIZE = 21
local landingBadge, landingButton, queueFrame
local mailFallback, mailFallbackSource, mailFallbackAtlas
local trackingButton
local QUEUE = { key = "QueueStatus", frame = Native.QueueStatus }

-- Retail and WoW Forever share these names: MinimapCluster's parent keys
-- and a few globals.
local DIFFICULTY = {
    key = "Difficulty",
    toggle = "showDifficulty",
    corner = "TOPRIGHT",
    frame = Native.Difficulty,
}
-- Row order, then the two corner buttons.
local SPECS = {
    { key = "Tracking", toggle = "showTracking", frame = Native.Tracking },
    { key = "Calendar", toggle = "showCalendar", frame = Native.Calendar },
    { key = "Mail", toggle = "showMail", frame = Native.Mail },
    {
        key = "Crafting",
        toggle = "showCrafting",
        frame = Native.Crafting,
    },
    { key = "Compartment", toggle = "showCompartment", frame = Native.Compartment },
    { key = "ExternalEvent", frame = Native.ExternalEvent },
    DIFFICULTY,
    -- WoW Forever's landing refresh path fails with foreign placement; left alone there.
    {
        key = "Landing",
        toggle = "showLanding",
        corner = "BOTTOMLEFT",
        frame = Native.Landing,
    },
}

local function Spec(key)
    if key == "QueueStatus" then return QUEUE end
    for i = 1, #SPECS do
        if SPECS[i].key == key then return SPECS[i] end
    end
end

function S.MinimapElementAvailable(key)
    local spec = Spec(key)
    return spec ~= nil and spec.frame() ~= nil
end

-- Read-only preview hint. `nil` means Blizzard has not made this button yet;
-- `false` means it exists but its owner currently hides it (mail, crafting, etc.).
-- The second return preserves a native row slot hidden by Suite's mouseover rule.
-- Blizzard's difficulty widget keeps its outer frame shown even when all
-- content modes are hidden. The preview needs the visible mode, not the
-- outer frame's visibility or a generic replacement icon.
-- ContentModes is the widget's parentArray on both clients (InstanceDifficulty.xml).
local function ActiveDifficulty(frame)
    local modes = frame.ContentModes
    for i = 1, #modes do
        local mode = modes[i]
        if MM.Usable(mode) then
            local shown = mode:IsShown()
            if S.Public(shown) and shown then return mode end
        end
    end
end
-- GetInstanceInfo difficulty IDs: tag and colour tier (1 normal, 2 heroic, 3
-- mythic, 4 raid finder/follower, 5 timewalking, 6 keystone). Bare tags carry
-- no group size. Unknown IDs fall back to GetDifficultyInfo's heroic/mythic flags.
local TAGS = {
    [1] = { "N", 1 },
    [2] = { "H", 2 },
    [23] = { "M", 3 },
    [14] = { "N", 1 },
    [15] = { "H", 2 },
    [16] = { "M", 3 },
    [233] = { "M", 3 },
    [3] = { "N", 1 },
    [4] = { "N", 1 },
    [5] = { "H", 2 },
    [6] = { "H", 2 },
    [9] = { "N", 1 },
    [148] = { "N", 1 },
    [173] = { "N", 1 },
    [174] = { "H", 2 },
    [242] = { "N", 1 },
    [243] = { "N", 1 },
    [7] = { "LFR", 4 },
    [17] = { "LFR", 4 },
    [205] = { "F", 4, true },
    [24] = { "TW", 5 },
    [33] = { "TW", 5 },
    [151] = { "TW", 5 },
    [18] = { "EVT", 1 },
    [19] = { "EVT", 1 },
    [30] = { "EVT", 1 },
    [25] = { "PvP", 1 },
    [29] = { "PvP", 1 },
    [32] = { "PvP", 1 },
    [34] = { "PvP", 1 },
    [45] = { "PvP", 1 },
    [12] = { "S", 1 },
    [38] = { "S", 1 },
    [11] = { "HS", 2 },
    [39] = { "HS", 2 },
    [40] = { "MS", 3 },
    [8] = { "M+", 6, true },
    [208] = { "D", 1, true },
}
-- Flexible raids show the current group size instead of the maximum.
local FLEX = { [14] = true, [15] = true, [17] = true, [33] = true }

-- Group size and difficulty letter, e.g. "20M", "5H", "M+12", "25LFR".
function MM.ReadDifficultyText()
    local _, kind, difficulty, _, maxPlayers, _, dynamic, _, groupSize = GetInstanceInfo()
    if not S.Public(kind) or kind == "none" or kind == "interior" or kind == "neighborhood"
        or not Finite(difficulty) then
        return ""
    end
    local tag, letter, tier = TAGS[difficulty], nil, 1
    if tag then
        letter, tier = tag[1], tag[2]
    else
        local _, _, heroic, _, displayHeroic, displayMythic = GetDifficultyInfo(difficulty)
        if S.Public(displayMythic) and displayMythic then
            letter, tier = "M", 3
        elseif S.Public(heroic) and S.Public(displayHeroic) and (heroic or displayHeroic) then
            letter, tier = "H", 2
        else
            letter = "N"
        end
    end
    if difficulty == 8 then
        local level = C_ChallengeMode.GetActiveKeystoneInfo()
        return Finite(level) and level > 0 and letter .. math.floor(level) or letter, tier
    end
    if tag and tag[3] then return letter, tier end
    local flexible = FLEX[difficulty] or (S.Public(dynamic) and dynamic == true)
    local size = flexible and Finite(groupSize) and groupSize > 0 and groupSize or maxPlayers
    return (Finite(size) and size > 0 and math.floor(size) or "") .. letter, tier
end

function S.MinimapDifficultyPreviewSource()
    local frame = DIFFICULTY.frame()
    if not frame then return end
    return frame, ActiveDifficulty(frame)
end

function S.MinimapElementPreviewShown(key)
    local spec = Spec(key)
    local frame = spec and spec.frame()
    if not frame then return nil end
    local shown
    if spec == DIFFICULTY then
        shown = ActiveDifficulty(frame) ~= nil
    else
        shown = frame:IsShown()
    end
    if S.Public(shown) then
        local slot = M.active and mine[frame] and slots[key]
        return shown and (not slot or slot:IsShown()), shown
    end
    return nil
end

local function Wanted(spec, c)
    if not spec.toggle then return true end -- Native conditional visibility.
    local value = c[spec.toggle]
    if spec.key == "Landing" then return value ~= LANDING.NEVER end
    -- The difficulty and calendar day texts replace Blizzard's flag and button.
    if spec == DIFFICULTY then return value and not c.infoDifficulty end
    if spec.key == "Calendar" then return value and not c.infoCalendarDay end
    return value
end
-- The addon button drawer holds the compartment (Drawer.lua); this file keeps
-- it in its records so disabling the module returns it to Blizzard.
local function InDrawer(spec, c)
    return spec.key == "Compartment" and c.showCompartment and MM.CollectsButtons()
end

local function RowsChanged()
    if M.active then MM.Queue("rows") end
end
local function OwnedVisibilityChanged(frame)
    if mine[frame] then RowsChanged() end
end
local function Watch(frame)
    if watched[frame] then return end
    watched[frame] = true
    frame:HookScript("OnShow", OwnedVisibilityChanged)
    frame:HookScript("OnHide", OwnedVisibilityChanged)
end
local function Slot(key)
    local slot = slots[key]
    if slot then return slot end
    slot = S.CreateFrame("Frame", nil, MM.host)
    slot:SetFrameLevel(MM.mapLevel + 14)
    slot:EnableMouse(false)
    slot:SetSize(1, 1)
    -- Settings prefix of the row offsets (MM.LayoutRow).
    if key ~= "ExternalEvent" then slot.minimapOffsetKey = "button" .. key end
    -- Blizzard's mail and crafting indicators call their parent's Layout().
    slot.Layout = RowsChanged
    slots[key] = slot
    return slot
end
local function Fit(frame, size)
    local width, height = frame:GetSize()
    if not Finite(width) or not Finite(height) then return 1 end
    local larger = math.max(width, height)
    return larger > 0 and size / larger or 1
end
MM.Fit = Fit

local function Own(frame, parent, point, relative, relativePoint, x, y, scale)
    if frame and MM.Place(frame, parent, point, relative, relativePoint, x, y, scale, nil, MM.mapLevel + 15) then
        mine[frame] = true
        Watch(frame)
    end
end
local function Park(frame)
    local park = MM.park
    Own(frame, park, "CENTER", park, "CENTER", 0, 0)
end

-- A plain book badge covers Blizzard's artwork without changing the native
-- button or its click handler. Hiding the badge restores Blizzard's look.
local function StyleLanding(button, c)
    if NS.IsCombatLocked() and (button and button:IsProtected() or landingButton and landingButton:IsProtected()) then
        MM.Defer()
        return
    end
    if landingButton ~= button then
        if landingBadge then landingBadge:Hide() end
        landingBadge, landingButton = nil, button
    end
    if not button or c.landingIcon ~= LANDING_ICON.BOOK or c.showLanding == LANDING.NEVER then
        if landingBadge then landingBadge:Hide() end
        return
    end
    if not landingBadge then
        local badge = S.CreateFrame("Frame", nil, button)
        badge:EnableMouse(false)
        badge:SetAllPoints(button)
        local back = S.CreateTexture(badge, nil, "BACKGROUND")
        back:SetAllPoints(badge)
        back:SetColorTexture(0.08, 0.1, 0.14, 1)
        local left = S.CreateTexture(badge, nil, "ARTWORK")
        left:SetSize(7, 13)
        left:SetPoint("RIGHT", badge, "CENTER", -1, 0)
        left:SetColorTexture(0.91, 0.81, 0.56, 1)
        local right = S.CreateTexture(badge, nil, "ARTWORK")
        right:SetSize(7, 13)
        right:SetPoint("LEFT", badge, "CENTER", 1, 0)
        right:SetColorTexture(0.98, 0.92, 0.74, 1)
        local spine = S.CreateTexture(badge, nil, "OVERLAY")
        spine:SetSize(2, 15)
        spine:SetPoint("CENTER", badge, "CENTER", 0, 0)
        spine:SetColorTexture(0.35, 0.28, 0.18, 1)
        landingBadge = badge
        MM.landingBadge = badge
    end
    landingBadge:SetFrameLevel(button:GetFrameLevel() + 1)
    landingBadge:Show()
end

-- Forever 70425's Diel ring belongs to MinimapContainer and keeps its visible
-- size when the map scales. Place it on our rim in Blizzard's 55/86 direction;
-- on rectangular maps the same direction meets the nearest edge.
local DIEL_X, DIEL_Y = 55, 86
local DIEL_LENGTH = math.sqrt(DIEL_X * DIEL_X + DIEL_Y * DIEL_Y)
local function LayoutDiel(c)
    local ring, width, height = Native.DayNight(), MM.width, MM.height
    if not ring or not width or not height then return end
    if not c.showDayNight then
        Park(ring)
        return
    end
    local ux, uy = DIEL_X / DIEL_LENGTH, DIEL_Y / DIEL_LENGTH
    local reach = c.shape == SHAPE.CIRCLE and width / 2 or math.min(width / 2 / ux, height / 2 / uy)
    -- Cancel only the Suite host's scale, like Blizzard cancels its container.
    local scale, uiScale = MM.host:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not Finite(scale) or scale <= 0 or not Finite(uiScale) or uiScale <= 0 then return end
    Own(ring, MM.host, "CENTER", MM.host, "CENTER", MM.Snap(ux * reach), MM.Snap(uy * reach), uiScale / scale)
end

-- Eight row modes: corner of the map, growth direction, and the outward side.
-- { item point, map point, outward x, outward y, step x, step y }
local ROWS = NS.MinimapRowGeometry
MM.ROWS = ROWS
local function PointX(point, width)
    return point:find("LEFT", 1, true) and -width / 2
        or point:find("RIGHT", 1, true) and width / 2 or 0
end
local function PointY(point, height)
    return point:find("TOP", 1, true) and height / 2
        or point:find("BOTTOM", 1, true) and -height / 2 or 0
end
-- Places count frames from index start on; distances start at the border edge.
function MM.LayoutRow(mode, frames, count, size, spacing, distance, start, extentKey)
    local row, host, pixel = ROWS[mode] or ROWS[1], MM.host, MM.Pixel()
    local out = MM.Snap(distance + M.config.borderSize * pixel, pixel)
    local step = MM.Snap(size + spacing, pixel)
    local combat = NS.IsCombatLocked()
    local reach = (start + count) > 0 and math.max(0, out + size) or 0
    local left, right = row[3] < 0 and reach or 0, row[3] > 0 and reach or 0
    local top, bottom = row[4] > 0 and reach or 0, row[4] < 0 and reach or 0
    for i = 1, count do
        local index = start + i - 1
        local frame = frames[i]
        local prefix = frame.minimapOffsetKey
        local dx = prefix and (M.config[prefix .. "X"] or 0) or 0
        local dy = prefix and (M.config[prefix .. "Y"] or 0) or 0
        -- Snap the final coordinate too: per-button offsets may be fractional
        -- in host units even when the row's base spacing is pixel aligned.
        local x = MM.Snap(row[3] * out + row[5] * index * step + dx, pixel)
        local y = MM.Snap(row[4] * out + row[6] * index * step + dy, pixel)
        -- A slot holding a protected button is protected itself until combat ends.
        if combat and frame:IsProtected() then
            MM.Defer()
        else
            frame:ClearAllPoints()
            frame:SetPoint(row[1], host, row[2], x, y)
        end
        if (dx ~= 0 or dy ~= 0) and MM.width and MM.height then
            local cx = PointX(row[2], MM.width) + x - PointX(row[1], size)
            local cy = PointY(row[2], MM.height) + y - PointY(row[1], size)
            left = math.max(left, -MM.width / 2 - (cx - size / 2))
            right = math.max(right, cx + size / 2 - MM.width / 2)
            top = math.max(top, cy + size / 2 - MM.height / 2)
            bottom = math.max(bottom, -MM.height / 2 - (cy - size / 2))
        end
    end
    MM.SetExtent(extentKey, left, right, top, bottom)
end

-- Slots holding a protected button are protected themselves during combat.
local function Locked(frame)
    if frame and NS.IsCombatLocked() and frame:IsProtected() then
        MM.Defer()
        return true
    end
    return false
end
local function HideSlot(key)
    local slot = slots[key]
    if slot and not Locked(slot) then slot:Hide() end
end

local function MailAnimationPlaying(animation)
    if not MM.Usable(animation) then return false end
    local playing = animation:IsPlaying()
    return not S.Public(playing) or playing
end

-- Blizzard resets the artwork on OnHide, even when only an ancestor hides.
-- For a visible mail frame, keep its native icon available after that reset.
local function MissingMailArtwork(slot)
    local frame = slot and Native.Mail()
    if not frame or frame:GetParent() ~= slot then return end
    local visible, icon = frame:IsVisible(), frame.MailIcon
    if not S.Public(visible) or not visible or not MM.Usable(icon) then return end
    local shown = icon:IsShown()
    if not S.Public(shown) or shown or MailAnimationPlaying(frame.NewMailAnim)
        or MailAnimationPlaying(frame.MailReminderAnim) then return end
    return frame, icon, S.PublicText(icon:GetAtlas())
end

local function RefreshMailArtwork(slot)
    local frame, icon, atlas = MissingMailArtwork(slot)
    if not atlas or mailFallback and mailFallback:GetParent() ~= frame then
        if mailFallback then mailFallback:Hide() end
        if not atlas then return end
        mailFallback, mailFallbackSource, mailFallbackAtlas = nil, nil, nil
    end
    if not mailFallback then
        if Locked(frame) then return end
        mailFallback = S.CreateTexture(frame, nil, "BACKGROUND")
    end
    if mailFallbackSource ~= icon then
        mailFallback:SetAllPoints(icon)
        mailFallbackSource = icon
    end
    if mailFallbackAtlas ~= atlas then
        mailFallback:SetAtlas(atlas)
        mailFallbackAtlas = atlas
    end
    mailFallback:Show()
end

local function RevealTracking()
    local slot = slots.Tracking
    if not M.active or not slot or Locked(slot) then return end
    local open = trackingButton and trackingButton:IsMenuOpen()
    slot:SetShown(not trackingButton or MM.Revealed() or S.Public(open) and open == true)
end

local function TrackingClose()
    MM.HoverLeave()
    RevealTracking()
end

local function ObserveTracking(c)
    local frame = c and c.showTracking and c.trackingMouseover and not S.GamepadUI() and Native.Tracking()
    local button = MM.Usable(frame) and frame.Button
    if not (MM.Usable(button) and button.RegisterCallback and button.UnregisterCallback and button.IsMenuOpen) then
        button = nil
    end
    if trackingButton == button then return end
    if trackingButton then trackingButton:UnregisterCallback("OnMenuClose", MM) end
    trackingButton = button
    if button then
        button:RegisterCallback("OnMenuClose", TrackingClose, MM)
        MM.HookHover(button)
    end
end

-- Blizzard keeps deciding when its queue eye shows. On the group finder button
-- the eye sits in the button's eye holder, which follows the button's show
-- rule; the button hides while the eye shows (DungeonShortcut.lua), and its
-- own extent already covers the eye.
local function LayoutQueue()
    local frame, c = Native.QueueStatus(), M.config
    local placement = frame and Native.QueuePlacement(c)
    local button = placement == "finder" and MM.dungeonButton
    if placement == "finder" and not button then placement = nil end
    if queueFrame and (queueFrame ~= frame or not placement) then
        MM.Release(queueFrame)
        mine[queueFrame], queueFrame = nil, nil
    end
    if placement ~= "minimap" then MM.SetExtent("queue", 0, 0, 0, 0) end
    if not placement then return end
    queueFrame = frame
    if placement == "hidden" then
        Park(frame)
        return
    end
    if button then
        local holder = MM.dungeonEyeHolder
        Own(frame, holder, "CENTER", holder, "CENTER", 0, 0, Fit(frame, math.min(c.dungeonWidth, c.dungeonHeight)))
        return
    end
    local size, x, y = Native.QueueLayout(c)
    Own(frame, MM.host, "CENTER", MM.host, "TOPLEFT", x, y, Fit(frame, size))
    local width, height = MM.Dimensions()
    MM.SetExtent("queue", math.max(0, size / 2 - x), math.max(0, x + size / 2 - width),
        math.max(0, y + size / 2), math.max(0, -y + size / 2 - height))
end

local function PlaceCorner(spec, c, frame)
    local slot, corner = Slot(spec.key), spec.corner
    if Locked(slot) then return end
    local scale = c.elementSize / BASE_SIZE
    local inset = corner == "TOPRIGHT" and -2 or 2
    local x = inset + (spec.key == "Landing" and c.landingX or c.difficultyButtonX or 0)
    local y = inset + (spec.key == "Landing" and c.landingY or c.difficultyButtonY or 0)
    if spec.key == "Landing" then scale = scale * 0.8 end
    slot:ClearAllPoints()
    slot:SetPoint(corner, MM.host, corner, x, y)
    Own(frame, slot, corner, slot, corner, 0, 0, scale)
    -- Mouseover mode shows the slot on hover; Blizzard still decides the button.
    slot:SetShown(spec.key ~= "Landing" or c.showLanding == LANDING.ALWAYS or MM.Revealed())
end

function MM.LayoutElements()
    -- The queue eye may stand on the group finder button: place the button first.
    MM.ApplyDungeonShortcut()
    LayoutQueue()
    local c = M.config
    ObserveTracking(c)
    local size, count = MM.Snap(c.elementSize, MM.Pixel()), 0
    for i = 1, #SPECS do
        local spec = SPECS[i]
        local frame = spec.frame()
        if spec.key == "Landing" then StyleLanding(frame, c) end
        if not frame then
            HideSlot(spec.key)
        elseif InDrawer(spec, c) then
            HideSlot(spec.key)
            mine[frame] = true
            Watch(frame)
        elseif not Wanted(spec, c) then
            Park(frame)
            HideSlot(spec.key)
        elseif spec.corner then
            PlaceCorner(spec, c, frame)
        else
            local slot = Slot(spec.key)
            local shown = frame:IsShown()
            shown = not S.Public(shown) or shown
            if not Locked(slot) then
                slot:SetSize(size, size)
                if spec.key ~= "Tracking" then slot:Show() end
                Own(frame, slot, "CENTER", slot, "CENTER", 0, 0, Fit(frame, size))
                if not shown then
                    -- Kept shown so Blizzard's later Show still fires OnShow.
                    slot:ClearAllPoints()
                    slot:SetPoint("CENTER", MM.host, "CENTER")
                end
            end
            if shown then
                count = count + 1
                items[count] = slot
            end
        end
    end
    for i = count + 1, #items do items[i] = nil end
    RefreshMailArtwork(c.showMail and slots.Mail)
    LayoutDiel(c)
    MM.LayoutRow(c.elementRow, items, count, size, c.elementSpacing, c.elementDistance, 0, "elements")
    if MM.rowCount ~= count then
        MM.rowCount = count
        if MM.CollectsButtons() and c.drawerRow == c.elementRow then MM.Queue("drawer") end
    end
    if c.showTracking then RevealTracking() end
end

MM.flushers.rows = MM.LayoutElements

MM.OnHover(function(shown)
    local slot = slots.Landing
    if slot and M.active and M.config.showLanding == LANDING.MOUSEOVER and not Locked(slot) then slot:SetShown(shown) end
    if trackingButton then RevealTracking() end
end)

-- Blizzard re-anchors some of these buttons after loading screens.
function MM.ReassertElements()
    for frame in pairs(mine) do MM.Reassert(frame) end
    RowsChanged()
end

-- Blizzard may change its container scale while the ring is borrowed. 70425
-- cancels that current scale, so the original snapshot would restore stale
-- size/coordinates. Keep older cluster-parented rings and foreign owners intact.
local function ReleaseDiel(ring)
    local record = MM.owned[ring]
    local parent = record and record.parent
    local restore = record and record.want and ring:GetParent() == record.want.parent
    MM.Release(ring)
    if not restore or parent ~= Native.DayNightContainer() then return end
    local scale = parent:GetScale()
    if not Finite(scale) or scale <= 0 then return end
    ring:SetScale(1 / scale)
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", parent, "CENTER", DIEL_X * scale, DIEL_Y * scale)
end

function MM.ReleaseElements()
    ObserveTracking()
    if landingBadge then landingBadge:Hide() end
    if mailFallback then mailFallback:Hide() end
    local ring = Native.DayNight()
    for frame in pairs(mine) do
        if frame == ring then ReleaseDiel(frame) else MM.Release(frame) end
        mine[frame] = nil
    end
    for _, slot in pairs(slots) do slot:Hide() end
    MM.rowCount = nil
    MM.SetExtent("elements", 0, 0, 0, 0)
    queueFrame = nil
    MM.SetExtent("queue", 0, 0, 0, 0)
end
