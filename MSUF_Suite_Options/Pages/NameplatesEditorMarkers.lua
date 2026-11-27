local _, P = ...
local ID = "nameplates"
local Markers = {}
P.NameplatesEditorMarkers = Markers
local Style, Tr = P.Suite.NameplateStyle, P.Tr

function Markers.BindTarget(editor, sample)
    local prefix, cell = sample.prefix, sample.cell
    local primary = CreateFrame("Button", nil, cell)
    local right = CreateFrame("Button", nil, cell)
    local pair = CreateFrame("Button", nil, cell)
    sample.targetVisual = {}
    sample.primaryArrow, sample.rightArrow, sample.targetPair = primary, right, pair
    editor:Bind(pair, prefix .. ".targetPair", Tr("Target arrows"), "enemyTargetOffsetX", "enemyTargetOffsetY", "enemyMarkers")
    editor:Bind(primary, prefix .. ".target", Tr("Primary target arrow"),
        "enemyTargetPrimaryOffsetX", "enemyTargetPrimaryOffsetY", "enemy")
    editor:Bind(right, prefix .. ".targetRight", Tr("Right target arrow"),
        "enemyTargetMirrorOffsetX", "enemyTargetMirrorOffsetY", "enemy")
end

local function PlaceHandle(handle, marker, size, visible)
    handle:SetShown(marker ~= nil and visible)
    handle:ClearAllPoints()
    if not marker then return end
    handle:SetPoint("CENTER", marker, "CENTER", 0, 0)
    handle:SetSize(size, size)
    handle:SetFrameLevel(marker:GetFrameLevel() + 1)
end

function Markers.PaintTarget(sample, targeted, rightGap, leftGap, positionSample, bars, previewInactive)
    local config = P.S.Config(ID)
    local prefix = sample.prefix
    local editArrow = positionSample == "target" or positionSample == "targetRight" or positionSample == "targetPair"
    local canDraw = config.look ~= 2 and config[prefix] and (config.enemyTargetMarker or editArrow)
        and (editArrow or prefix == "enemy" or not config.enemyTargetHideFriendly)
    local visible = targeted and canDraw
    local place = canDraw and (visible or previewInactive)
    local target = place and Style.TargetConfig(config, bars, prefix)
    if target and positionSample == "targetRight" and target.bossTargetLayout == "SINGLE" then
        target.bossTargetLayout = "BOTH_IN"
    end
    local marker = Style.PaintTarget(sample.targetVisual, sample.bar, place, target, sample.cell, rightGap, leftGap)
    if place and not visible and sample.targetVisual.targetHost then sample.targetVisual.targetHost:Hide() end
    local size = target and target.bossTargetSize
    PlaceHandle(sample.primaryArrow, marker, size, visible)
    local right
    if marker and target.bossTargetLayout ~= "SINGLE" then right = marker.mirror end
    PlaceHandle(sample.rightArrow, right, size, visible)
    local pair = sample.targetPair
    if not pair then return end
    PlaceHandle(pair, positionSample == "targetPair" and marker or nil, size, visible)
    if positionSample == "targetPair" then
        sample.primaryArrow:Hide()
        sample.rightArrow:Hide()
    end
end

function Markers.TargetActive(ui)
    return P.Get(ID, "enemyTargetMarker")
        and (ui.sampleKind == "enemy" or not P.Get(ID, "enemyTargetHideFriendly"))
end
