local _, P = ...
-- The live editor borrows the runtime's anchors and shares the dock's icon controls.
local Page, S = P.CDMPage, P.S
local slots, kit = P.Suite.CDM.SLOTS, P.Suite.PreviewKit
local EDIT_LEVEL = 360 -- Above MSUF movers in FULLSCREEN, below the options window.
-- Popup gaps beside a live bar; above clears the bar's name label.
local ABOVE_GAP, BELOW_GAP = 22, 6
local floor = math.floor
local Public = Page.Public
local surfaces, data = {}, {}
local owner

local function BuildSurface(slot, anchor)
    -- Layout.EnsureBar keeps the same owned root for a slot across style and type changes.
    local canvas = CreateFrame("Frame", nil, anchor)
    canvas:SetAllPoints(anchor)
    canvas:Hide()
    local surface = { slot = slot, canvas = canvas }
    surface.host = kit.NewHost(nil, { frame = canvas,
        pools = { hit = function(_, index) return Page.NewPreviewHit(surface, index) end } })
    Page.BuildPreviewIcons(surface)
    return surface
end

local function Hide(surface)
    if not surface or not surface.shown then return end
    surface.shown = false
    Page.PaintPreviewIcons(surface, nil, false)
    Page.FollowPreviewPopover(surface)
    surface.host:Deactivate()
    surface.canvas:Hide()
    Page.CloseOrphans()
end

local function Release()
    if not owner then return end
    for _, surface in pairs(surfaces) do Hide(surface) end
    owner = nil
end

local function PaintBar(slot, page, get)
    local record = data[slot]
    if not record then
        record = { items = {}, keys = {}, tiles = {} }
        data[slot] = record
    end
    local surface = surfaces[slot]
    if not get(slot, record) or not P.Suite.Safety.CanAnchor(record.anchor) then
        Hide(surface)
        return
    end
    local anchor = record.anchor
    if not surface then
        surface = BuildSurface(slot, anchor)
        surfaces[slot] = surface
    end
    surface.tips = page.tips
    local canvas = surface.canvas
    if not surface.shown then
        surface.shown = true
        surface.host:Activate()
        canvas:Show()
    end
    local strata, level = anchor:GetFrameStrata(), anchor:GetFrameLevel() + 24
    if S.editMode then strata, level = "FULLSCREEN", EDIT_LEVEL end
    if canvas:GetFrameStrata() ~= strata then canvas:SetFrameStrata(strata) end
    if canvas:GetFrameLevel() ~= level then canvas:SetFrameLevel(level) end
    Page.PaintPreviewIcons(surface, record, true)
    Page.FollowPreviewPopover(surface)
end

local function Wants(page)
    return page and page.live and page.previewBody:IsVisible() and not P.Combat()
        and S.CooldownManagerEditorBar ~= nil and not Page.ForeignSpec() and not Page.EditorBlocked()
end

-- Called after a live layout settles, and when the menu enters or leaves the editor.
function Page.RefreshScreenEditor(ready)
    local page = Page.ui
    if not ready or not Wants(page) then
        Release()
        return
    end
    owner = page
    for _, slot in ipairs(slots) do PaintBar(slot.key, page, S.CooldownManagerEditorBar) end
end

-- A frame edge in screen units; nil while the client does not answer it.
local function Edge(value, scale)
    if Public(value) and type(value) == "number" then return value * scale end
end

-- A popup of a live icon or + tile opens on the side of its bar with more
-- room, so the bar it edits stays in sight while changes apply. Writes only
-- when the side or the offset changed.
function Page.PlaceLivePopup(popup, anchor)
    local ui = anchor and anchor.ui
    local surface = ui and ui.slot and surfaces[ui.slot]
    if not surface or surface ~= ui or not surface.shown then return false end
    local canvas, scale = surface.canvas, Page.Scale(surface.canvas)
    local top, bottom = Edge(canvas:GetTop(), scale), Edge(canvas:GetBottom(), scale)
    local left, from = Edge(anchor:GetLeft(), Page.Scale(anchor)), Edge(canvas:GetLeft(), scale)
    local screen = Edge(UIParent:GetTop(), Page.Scale(UIParent))
    if not (top and bottom and left and from and screen) then return false end
    local above = screen - top > bottom
    local x = floor((left - from) / Page.Scale(popup) + 0.5)
    if popup.liveCanvas == canvas and popup.liveAbove == above and popup.liveX == x then return true end
    popup.liveCanvas, popup.liveAbove, popup.liveX = canvas, above, x
    popup:ClearAllPoints()
    if above then
        popup:SetPoint("BOTTOMLEFT", canvas, "TOPLEFT", x, ABOVE_GAP)
    else
        popup:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", x, -BELOW_GAP)
    end
    return true
end

-- The other live bar under a dragged icon, of the same family, and where the
-- drop lands there: one of its spells, or its + tile (the end of the bar).
local function DropOn(surface)
    local plus = surface.plus
    if plus.pvShown and plus:IsMouseOver() then return plus end
    if not surface.canvas:IsMouseOver() then return nil end
    for i = 1, surface.hitCount do
        local hit = surface.hits[i]
        if hit.key and hit:IsMouseOver() then return hit end
    end
    return plus.pvShown and plus or false
end
function Page.ScreenDropTarget(except, family)
    if not owner then return nil end
    for _, info in ipairs(slots) do
        local surface = surfaces[info.key]
        if surface and surface.shown and info.key ~= except then
            local target = DropOn(surface)
            if target ~= nil and Page.Family(info.key) == family then return surface, target or nil end
        end
    end
end

-- Switching to an offline specialization does not move or select the live bars.
function Page.SyncScreenEditor(page)
    local wanted = Wants(page) == true
    if page.screenEditor == wanted then return end
    page.screenEditor = wanted
    Page.RefreshScreenEditor(wanted)
    if page.PaintPreviewNote then page.PaintPreviewNote() end
end
