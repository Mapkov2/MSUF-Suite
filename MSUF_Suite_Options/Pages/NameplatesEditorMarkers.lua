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

function Markers.ToggleTarget(ui, openSetting)
    if P.Get(ID, "look") == 2 then
        openSetting("look", "Look")
        return
    end
    local visible = Markers.TargetActive(ui)
    if ui.sampleKind == "enemy" then
        P.Set(ID, "enemyTargetMarker", not visible)
    elseif visible then
        P.Set(ID, "enemyTargetHideFriendly", true)
    else
        P.SetMany(ID, { enemyTargetMarker = true, enemyTargetHideFriendly = false })
    end
    ui.layers.target = true
    ui:Paint()
end

function Markers.ToggleMarker(ui, key)
    local kind = key == "eliteMarker" and "Elite" or "Quest"
    local setting = ui.sampleKind .. kind .. "Marker"
    local enabled = P.Get(ID, setting)
    if ui.sampleKind == "friendly" then
        if not ui.friendlyElite then ui.friendlyElite = true
        elseif enabled then P.Set(ID, setting, false) end
    else
        local desired = key == "eliteMarker" and 4 or 5
        ui.enemyPlayer = false
        if (ui.previewRole or P.Get(ID, "enemyPreviewRole")) ~= desired then
            ui.previewRole, ui.previewRoleSource = desired, P.Get(ID, "enemyPreviewRole")
        elseif enabled then P.Set(ID, setting, false) end
    end
    if not enabled then P.Set(ID, setting, true) end
    ui.layers[key] = true
end
