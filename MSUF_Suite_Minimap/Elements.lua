local _, P = ...
local NS, S = P.NS, P.Suite
local MM = P.Minimap
local M = MM.M
local LANDING, LANDING_ICON = NS.MinimapLanding, NS.MinimapLandingIcon
local SHAPE = NS.MinimapShape
-- Blizzard's own minimap buttons, moved into suite slots around the map.
-- Missing buttons are skipped. Blizzard keeps deciding when each button is
-- shown (nothing here force-shows a button): a hidden button keeps an empty
-- slot outside the row, and its show/hide re-packs the row one frame later.
local Finite = S.Finite
local weak = { __mode = "k" }
local mine, watched = setmetatable({}, weak), setmetatable({}, weak)
local slots, items = {}, {}
local BASE_SIZE = 21
local landingBadge, landingButton

local function Cluster(first, second)
    local frame = _G.MinimapCluster
    frame = MM.Usable(frame) and frame[first]
    if second then frame = MM.Usable(frame) and frame[second] end
    return MM.Usable(frame) and frame or nil
end
local function Global(name)
    local frame = _G[name]
    return MM.Usable(frame) and frame or nil
end
-- Retail and WoW Forever share these names: MinimapCluster's parent keys
-- and a few globals.
local DIFFICULTY = {
    key = "Difficulty",
    toggle = "showDifficulty",
    corner = "TOPRIGHT",
    frame = function() return Cluster("InstanceDifficulty") end,
}
-- Row order, then the two corner buttons.
local SPECS = {
    { key = "Tracking", toggle = "showTracking", frame = function() return Cluster("Tracking") end },
    { key = "Calendar", toggle = "showCalendar", frame = function() return Global("GameTimeFrame") end },
    { key = "Mail", toggle = "showMail", frame = function() return Cluster("IndicatorFrame", "MailFrame") end },
    {
        key = "Crafting",
        toggle = "showCrafting",
        frame = function() return Cluster("IndicatorFrame", "CraftingOrderFrame") end,
    },
    { key = "Compartment", toggle = "showCompartment", frame = function() return Global("AddonCompartmentFrame") end },
    DIFFICULTY,
    -- WoW Forever's landing refresh path fails with foreign placement; left alone there.
    {
        key = "Landing",
        toggle = "showLanding",
        corner = "BOTTOMLEFT",
        frame = function()
            if not NS.Client.isForever then return Global("ExpansionLandingPageMinimapButton") end
        end,
    },
}

local function Spec(key)
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
    if S.Public(shown) then return shown end
    return nil
end

local function Wanted(spec, c)
    local value = c[spec.toggle]
    if spec.key == "Landing" then return value ~= LANDING.NEVER end
    -- The difficulty text replaces Blizzard's flag.
    if spec == DIFFICULTY then return value and not c.infoDifficulty end
    return value
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
    slot.minimapOffsetKey = "button" .. key
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

-- WoW Forever's day/night ring (Camelot/Diel.lua) is a child of MinimapCluster
-- and fades with it. It moves onto the border of the suite map, at the spot
-- Blizzard gives it on its default map (198 wide): 53 right of and 87 above
-- the map centre, on the rim of the circle. Beyond the circle the same
-- direction meets the rectangle's edge. Retail has no such frame.
local DIEL_MAP, DIEL_X, DIEL_Y = 198, 53, 87
local DIEL_LENGTH = math.sqrt(DIEL_X * DIEL_X + DIEL_Y * DIEL_Y)
local function LayoutDiel(c)
    local ring, width, height = Cluster("DielFrame"), MM.width, MM.height
    if not ring or not width or not height then return end
    local ux, uy = DIEL_X / DIEL_LENGTH, DIEL_Y / DIEL_LENGTH
    local reach = c.shape == SHAPE.CIRCLE and width / 2 or math.min(width / 2 / ux, height / 2 / uy)
    -- Blizzard never shrinks the ring below its own size (Diel.lua).
    Own(ring, MM.host, "CENTER", MM.host, "CENTER", MM.Snap(ux * reach), MM.Snap(uy * reach), math.max(1, width / DIEL_MAP))
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
    local c = M.config
    local size, count = MM.Snap(c.elementSize, MM.Pixel()), 0
    for i = 1, #SPECS do
        local spec = SPECS[i]
        local frame = spec.frame()
        if spec.key == "Landing" then StyleLanding(frame, c) end
        if not frame then
            HideSlot(spec.key)
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
                slot:Show()
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
    LayoutDiel(c)
    MM.LayoutRow(c.elementRow, items, count, size, c.elementSpacing, c.elementDistance, 0, "elements")
    if MM.rowCount ~= count then
        MM.rowCount = count
        if MM.CollectsButtons() and c.drawerRow == c.elementRow then MM.Queue("drawer") end
    end
end

MM.flushers.rows = MM.LayoutElements

MM.OnHover(function(shown)
    local slot = slots.Landing
    if slot and M.active and M.config.showLanding == LANDING.MOUSEOVER and not Locked(slot) then slot:SetShown(shown) end
end)

-- Blizzard re-anchors some of these buttons after loading screens.
function MM.ReassertElements()
    for frame in pairs(mine) do MM.Reassert(frame) end
    RowsChanged()
end

function MM.ReleaseElements()
    if landingBadge then landingBadge:Hide() end
    for frame in pairs(mine) do
        MM.Release(frame)
        mine[frame] = nil
    end
    for _, slot in pairs(slots) do slot:Hide() end
    MM.rowCount = nil
    MM.SetExtent("elements", 0, 0, 0, 0)
end
