local _, P = ...
-- The live editor borrows the runtime's anchors and shares the dock's icon controls.
local Page, S = P.CDMPage, P.S
local slots, kit = P.Suite.CDM.SLOTS, P.Suite.PreviewKit
local EDIT_LEVEL = 360 -- Above MSUF movers in FULLSCREEN, below the options window.
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

-- Switching to an offline specialization does not move or select the live bars.
function Page.SyncScreenEditor(page)
    local wanted = Wants(page) == true
    if page.screenEditor == wanted then return end
    page.screenEditor = wanted
    Page.RefreshScreenEditor(wanted)
    if page.PaintPreviewNote then page.PaintPreviewNote() end
end
