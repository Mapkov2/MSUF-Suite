local _, P = ...
-- The battle resurrection preview's element editor (Pages/QoLLayerEditor.lua):
-- background and border lie under the icon and the texts.
local S = P.S

local function Region(view, key)
    if key == "background" then return view.panel end
    if key == "border" then return view.borderBounds end
    if key == "timer" then return view.compact and view.time or view.cooldown end
    return view[key]
end

P.BattleResEditor = P.QoLLayerEditor("battleRes", {
    view = "suiteBattleResPreview", region = Region, behind = 2,
    move = function(view, key, x, y) S.MoveBattleResPreviewLayer(view, key, x, y) end,
    hide = function(stage) S.HideBattleResPreview(stage) end,
    -- Blizzard's cooldown frame draws at its own scale.
    scale = function(view, region) return region == view.cooldown and region:GetEffectiveScale() end,
})
