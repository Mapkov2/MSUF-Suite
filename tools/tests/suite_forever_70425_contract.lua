-- Forever 70425 changed native minimap ownership and removed two widgets.
-- Keep the legacy fixture tests too; this scenario models the new native shape.
local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local external, ring, nativeClick, oldParent
local W = H.New(root, "Forever", { beforeModules = function(world)
    local G, cluster, container = world.G, world.cluster, world.container
    cluster.BorderTop, cluster.InstanceDifficulty, cluster.IndicatorFrame.CraftingOrderFrame = nil, nil, nil
    ring = cluster.DielFrame
    ring:SetParent(container)
    container:SetScale(2)
    ring:SetScale(.5)
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", container, "CENTER", 110, 172)
    oldParent = container
    -- Camelot/Diel.lua SetDielFrameTransform: inverse container scale, 55/86.
    function cluster:SetEditModeScale(scale)
        container:SetScale(scale)
        ring:SetScale(1 / scale)
        ring:ClearAllPoints()
        ring:SetPoint("CENTER", 55 * scale, 86 * scale)
    end
    external = world.Button(nil, world.backdrop, 32, 32, true)
    world.backdrop.ExternalEventURLButton = external
    external:ClearAllPoints()
    external:SetPoint("TOPLEFT", 9, -110)
    nativeClick = function() world.externalClicks = (world.externalClicks or 0) + 1 end
    external:SetScript("OnClick", nativeClick)
    assert(world.Suite.MinimapElements.Available("ExternalEvent"), "native reader must work before runtime loads")
    assert(not world.Suite.MinimapElements.Available("Crafting"))
    assert(not world.Suite.MinimapElements.Available("Difficulty"))
end })
W.editModeReady = true
H.Enable(W, { captured = true, size = 300, shape = 2, showDayNight = true })
W.Step()
local S, MM = W.S, W.MM
assert(not S.MinimapElementAvailable("Crafting") and not S.MinimapElementAvailable("Difficulty"))
assert(S.MinimapDifficultyPreviewSource() == nil)
assert(ring:GetParent() == MM.host and ring:GetEffectiveScale() == W.UIParent:GetEffectiveScale(),
    "70425 Diel ring must keep its visible size")
for _, size in ipairs({ 100, 300, 600 }) do
    for _, shape in ipairs({ 1, 2, 3 }) do
        assert(S.Set("minimap", "size", size))
        assert(S.Set("minimap", "shape", shape))
        W.Step()
        assert(ring:GetScale() == 1, "map dimensions must not enlarge/shrink Diel")
        local _, _, _, x, y = ring:GetPoint(1)
        assert(x > 0 and y > x)
        if shape == 2 then
            local radius = math.sqrt(x*x+y*y)
            assert(H.Near(radius, size/2, 1))
            assert(H.Near(x/radius, 55/math.sqrt(55*55+86*86), .01), "native 70425 direction changed")
        else assert(H.Near(y, MM.height/2, 1)) end
    end
end
MM.host:SetScale(1.25)
MM.LayoutElements()
assert(H.Near(ring:GetEffectiveScale(), W.UIParent:GetEffectiveScale()), "host scale must be canceled")
MM.host:SetScale(1)
MM.LayoutElements()
W.Blizzard(function() W.cluster:SetEditModeScale(.75) end)
W.Step()
assert(ring:GetParent() == MM.host and ring:GetScale() == 1, "native Edit Mode transform must be reasserted")

assert(external:GetParent() ~= W.backdrop and MM.owned[external], "event button must join normal ownership")
local count = MM.rowCount
W.Blizzard(function() external:Show() end)
assert(MM.rowCount == count, "native Show must only queue layout")
W.Step()
assert(MM.rowCount == count + 1 and external:IsVisible(), "shown event button must occupy one row slot")
assert(external:GetScript("OnClick") == nativeClick)
external:GetScript("OnClick")(external)
assert(W.externalClicks == 1, "event button native click was replaced")
W.Blizzard(function() external:Hide() end)
W.Step()
assert(MM.rowCount == count, "hidden event button must leave no row gap")
-- A protected borrowed button still obeys the existing combat deferral.
external.protected = true
W.SetCombat(true)
W.Blizzard(function() external:SetPoint("CENTER", W.backdrop, "CENTER", 12, 13) end)
W.Step()
W.SetCombat(false)
W.Step()
assert(external:GetParent() ~= W.backdrop and MM.owned[external])
assert(S.Set("minimap", "enabled", false))
assert(ring:GetParent() == oldParent and H.Near(ring:GetScale(), 1/.75), "Diel current native transform must restore")
assert(H.Near(ring:GetEffectiveScale(), W.UIParent:GetEffectiveScale()), "Diel restored native visible size changed")
local _, relative, _, rx, ry = ring:GetPoint(1)
assert(relative == oldParent and H.Near(rx, 55*.75) and H.Near(ry, 86*.75), "Diel restored stale native anchor")
assert(external:GetParent() == W.backdrop and external:GetScale() == 1, "event button original parent/scale must restore")
local point, _, _, x, y = external:GetPoint(1)
assert(point == "TOPLEFT" and x == 9 and y == -110, "event button original anchor must restore")
assert(external:GetScript("OnClick") == nativeClick)
-- A later owner can take the native ring; Disable must leave that transfer intact.
assert(S.Set("minimap", "enabled", true))
W.Step()
local foreign = W.Button(nil, W.UIParent, 10, 10)
W.Blizzard(function()
    ring:SetParent(foreign)
    ring:SetScale(3)
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", foreign, "CENTER", 17, 19)
end)
assert(S.Set("minimap", "enabled", false))
assert(ring:GetParent() == foreign and ring:GetScale() == 3, "Diel release overwrote a later owner")
local _, owner, _, fx, fy = ring:GetPoint(1)
assert(owner == foreign and fx == 17 and fy == 19)
print("suite_forever_70425_contract: passed")
