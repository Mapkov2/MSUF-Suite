local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local inside, housing, health = false, false, 100
local W = H.New(root, flavor, { beforeModules = function(world)
    local G = world.G
    G.IsInInstance = function() return inside end
    G.C_Housing = { IsInsideHouseOrPlot = function() return housing end }
    G.GetMoney = function() return 10000 end
    G.GetInventoryItemDurability = function() return 100, 100 end
    G.GetGameTime = function() return 12, 0 end
    G.GetServerTime = function() return 1700000000 end
    G.C_Container = {
        GetContainerNumSlots = function() return 20 end,
        GetContainerNumFreeSlots = function() return 8, 0 end,
    }
    -- Retail and WoW Forever both scale UnitHealthPercent through a curve.
    G.Enum = { LuaCurveType = { Step = 1 } }
    G.C_CurveUtil = { CreateCurve = function()
        return { points = {}, SetType = function(self, value) self.kind = value end,
            AddPoint = function(self, x, y) self.points[#self.points + 1] = { x, y } end }
    end }
    G.UnitHealthPercent = function(unit, includeAbsorbs, curve)
        assert(unit == "player" and includeAbsorbs == false and curve.kind == 1)
        assert(curve.points[1][1] == 0 and curve.points[1][2] == 1
            and curve.points[2][1] == 1 and curve.points[2][2] == 0)
        return health
    end
end })
local G, S = W.G, W.S
W.LoadAddon("MSUF_Suite_DataTexts")
H.Enable(W, { infoFPS = false, infoClock = false, infoLocation = false })
assert(S.Set("dataTexts", "enabled", true))
local M, config = assert(S.instances.dataTexts), S.Config("dataTexts")
local first = assert(M.bars[1])
assert(first.visibilityDriver == nil and first.frame:IsShown(), "default bar gained a state driver")
for i = 1, 3 do
    for _, condition in ipairs(W.Suite.DataTextLoadConditions) do
        local key = "bar" .. i .. "LoadCond" .. condition[1]
        assert(config[key] == false and S.catalog.dataTexts.rules[key], "missing default/menu rule: " .. key)
    end
end

assert(S.Set("dataTexts", "bar1LoadCondHideMounted", true))
assert(first.visibilityDriver == "[mounted] hide; show", "mounted rule was not registered")
assert(S.SetMany("dataTexts", { bar2Enabled = true, bar2LoadCondHideInCombat = true }))
local second = assert(M.bars[2])
assert(second.visibilityDriver == "[combat] hide; show"
    and first.visibilityDriver == "[mounted] hide; show", "bar conditions leaked across bars")
assert(S.Set("dataTexts", "bar2Enabled", false))
assert(second.visibilityDriver == nil and not second.frame:IsShown(), "disabled bar kept a driver")

assert(S.SetMany("dataTexts", { bar1LoadCondHideNoTarget = true,
    bar1LoadCondHideOutOfCombat = true, bar1LoadCondHideOutOfCombatNoTarget = true,
    bar1LoadCondShowWhenInjured = true }))
assert(first.visibilityDriver == "[mounted] hide; show",
    "injured condition did not replace the three no-target/out-of-combat rules")
health = 0
W.Event("UNIT_HEALTH", "player")
assert(first.visual.alpha == 0, "health event did not apply the native curve")
health = W.secret
W.Event("UNIT_MAXHEALTH", "player")
assert(first.visual.alpha == W.secret, "secret health was inspected before SetAlpha")
local healthAlpha = first.visual.alpha
assert(S.Set("dataTexts", "bar1Visibility", 4))
assert(first.frame.alpha == 0 and first.visual.alpha == healthAlpha,
    "mouseover mode replaced the health gate")
W.Fire(first.frame, "OnEnter")
assert(first.frame.alpha == 1 and first.visual.alpha == healthAlpha,
    "mouseover mode overwrote the health gate")
W.Fire(first.frame, "OnLeave")
assert(S.Set("dataTexts", "bar1Visibility", 1))
assert(S.Set("dataTexts", "bar1LoadCondHideInHousing", true))
housing = true
W.Event("HOUSE_PLOT_ENTERED")
assert(first.visibilityDriver == "hide", "housing entry did not update visibility")
S.SetEditMode(true)
assert(first.visibilityDriver == "[nocombat] show; hide" and first.visual.alpha == 1,
    "Edit Mode did not reveal a condition-hidden bar")
S.SetEditMode(false)
housing = false
W.Event("HOUSE_PLOT_EXITED")
assert(first.visibilityDriver == "[mounted] hide; show", "housing exit did not restore rules")
assert(S.Set("dataTexts", "bar1LoadCondHideInInstance", true))
W.SetCombat(true)
inside = true
W.Event("ZONE_CHANGED_NEW_AREA")
assert(first.visibilityDriver == "[mounted] hide; show", "driver changed during combat")
W.SetCombat(false)
assert(first.visibilityDriver == "hide", "queued instance condition was not applied")
inside = false
W.Event("ZONE_CHANGED_NEW_AREA")
assert(first.visibilityDriver == "[mounted] hide; show", "instance exit did not restore rules")
-- Visibility macros are built on Refresh only: zone and housing events reuse
-- the cached expression (no rules table, no concat per event).
do
    local concat, built = table.concat, 0
    W.G.table = setmetatable({ concat = function(...)
        built = built + 1
        return concat(...)
    end }, { __index = table })
    for _ = 1, 5 do W.Event("ZONE_CHANGED_NEW_AREA") end
    W.Event("HOUSE_PLOT_ENTERED")
    W.Event("HOUSE_PLOT_EXITED")
    W.G.table = nil
    assert(built == 0, "visibility events rebuilt the macro expression " .. built .. " times")
    assert(first.visibilityDriver == "[mounted] hide; show", "cached visibility expression changed")
end
assert(S.Set("dataTexts", "enabled", false))
assert(first.visibilityDriver == nil and not first.frame:IsShown(), "disable kept the visibility driver")
print("Suite DataTexts load conditions passed: " .. flavor)
