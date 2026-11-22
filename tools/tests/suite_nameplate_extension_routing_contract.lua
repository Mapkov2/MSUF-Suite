local root = assert(arg[1])
local events, filters, powerCalls, textCalls = {}, {}, 0, 0
local ctx = {}
function ctx:Event(event, callback, _, units) events[event], filters[event] = callback, units end
function ctx:RemoveEvent(event) events[event], filters[event] = nil, nil end
local units = { "nameplate1", "nameplate2" }
local secretUnit = "secret"
local NS = {
    Public = function(value) return type(value) ~= "table" and value ~= secretUnit end,
    Dispatch = function(callback, ...) return callback(...) end,
    Safety = { IsForbidden = function() return false end },
    NameplateStyle = { EnemyPower = { Plan = function(config) return { enabled = config.power == true } end } },
}
local P = { NS = NS, Suite = { NameplateUnits = units }, Mode = { LOOK_BLIZZARD = 2 },
    Extensions = { OnUnit = function(_, event, unit)
        assert(event == "UNIT_MAXPOWER" and unit == "nameplate1")
        textCalls = textCalls + 1
    end } }
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Power.lua"))("Plates", P)
local owner = { active = true, config = { look = 2 }, context = ctx, activeUnits = { nameplate1 = {} } }
P.Power.Enable(owner)
P.Power.EnemyResourceChanged = function() powerCalls = powerCalls + 1 end
P.Power.ConfigureEnemy()
assert(events.UNIT_MAXPOWER == nil)
P.Power.SetExtraTextEvents(true)
assert(filters.UNIT_MAXPOWER == units, "shared maximum-power events are filtered to nameplate units")
events.UNIT_MAXPOWER(owner, "UNIT_MAXPOWER", "nameplate1")
assert(textCalls == 1 and powerCalls == 0)
owner.config.power = true
P.Power.ConfigureEnemy()
events.UNIT_MAXPOWER(owner, "UNIT_MAXPOWER", "nameplate1")
assert(textCalls == 2 and powerCalls == 1, "one module handler routes to both power consumers")
P.Power.SetExtraTextEvents(false)
events.UNIT_MAXPOWER(owner, "UNIT_MAXPOWER", "nameplate1")
assert(textCalls == 2 and powerCalls == 2, "turning off labels preserves the power row subscriber")
owner.config.power = false
P.Power.ConfigureEnemy()
assert(events.UNIT_MAXPOWER == nil, "no consumer means no shared event listener")
local order, hookCount = {}, 0
hooksecurefunc = function(object, method, callback)
    local original = object[method]
    object[method] = function(...) original(...) callback(...) end
    hookCount = hookCount + 1
end
local combat = false
NS.IsCombatLocked = function() return combat end
NS.NameplateStyle.Elements = {}
P.Geometry, P.Key = { Point = function() end }, {}
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Modes.lua"))("Plates", P)
P.Extensions.OnAnchors = function() order[#order + 1] = "extensions" end
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Layout.lua"))("Plates", P)
P.Layout.Bind(owner)
P.Layout.Reapply = function() order[#order + 1] = "layout" end
local uf = { unit = "nameplate1", isFriend = false, UpdateAnchors = function() order[#order + 1] = "native" end }
owner.activeUnits[uf.unit] = uf
P.Layout.Observe(uf)
P.Layout.Observe(uf)
uf:UpdateAnchors()
assert(hookCount == 1 and table.concat(order, ",") == "native,layout,extensions",
    "one native anchor observer applies base layout before extension anchors")
order, combat, owner.pendingPlates = {}, true, {}
uf:UpdateAnchors()
assert(owner.pendingPlates[uf] and table.concat(order, ",") == "native,layout,extensions",
    "deferred base layout still reaches the extension's per-frame protection guard")
combat = false
owner.activeUnits.nameplate1 = {}
order = {}
uf:UpdateAnchors()
assert(table.concat(order, ",") == "native,extensions", "another frame reused the active token")
owner.activeUnits[secretUnit], owner.activeUnits[1] = uf, uf
for _, unit in ipairs({ secretUnit, 1 }) do
    order, uf.unit = {}, unit
    uf:UpdateAnchors()
    assert(table.concat(order, ",") == "native,extensions", "invalid token passed the active-unit gate")
end
print("nameplate extension routing contract passed")
