local _, P = ...
local ID = "nameplates"
local Markers = {}
P.NameplatesEditorMarkers = Markers

function Markers.TargetActive(ui)
    return P.Get(ID, "enemyTargetMarker")
        and (ui.sampleKind == "enemy" or not P.Get(ID, "enemyTargetHideFriendly"))
end

function Markers.ToggleTarget(ui, openSetting)
    if P.Get(ID, "look") == 2 then openSetting("look", "Look"); return end
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
