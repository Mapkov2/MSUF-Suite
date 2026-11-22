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

local function PlaceHandle(handle, marker, size)
    handle:SetShown(marker ~= nil)
    if not marker then return end
    handle:ClearAllPoints()
    handle:SetPoint("CENTER", marker, "CENTER", 0, 0)
    handle:SetSize(size, size)
    handle:SetFrameLevel(marker:GetFrameLevel() + 1)
end

function Markers.PaintTarget(sample, targeted, rightGap, leftGap, positionSample, bars)
    local config = P.S.Config(ID)
    local prefix = sample.prefix
    local editArrow = positionSample == "target" or positionSample == "targetRight" or positionSample == "targetPair"
    local visible = targeted and config.look ~= 2 and config[prefix] and (config.enemyTargetMarker or editArrow)
        and (editArrow or prefix == "enemy" or not config.enemyTargetHideFriendly)
    local target = visible and Style.TargetConfig(config, bars, prefix)
    if target and positionSample == "targetRight" and target.bossTargetLayout == "SINGLE" then
        target.bossTargetLayout = "BOTH_IN"
    end
    local marker = Style.PaintTarget(sample.targetVisual, sample.bar, visible, target, sample.cell, rightGap, leftGap)
    local size = target and target.bossTargetSize
    PlaceHandle(sample.primaryArrow, marker, size)
    local right
    if marker and target.bossTargetLayout ~= "SINGLE" then right = marker.mirror end
    PlaceHandle(sample.rightArrow, right, size)
    local pair = sample.targetPair
    if not pair then return end
    PlaceHandle(pair, positionSample == "targetPair" and marker or nil, size)
    if positionSample == "targetPair" then
        sample.primaryArrow:Hide()
        sample.rightArrow:Hide()
    end
end

function Markers.TargetActive(ui)
    return P.Get(ID, "enemyTargetMarker")
        and (ui.sampleKind == "enemy" or not P.Get(ID, "enemyTargetHideFriendly"))
end
