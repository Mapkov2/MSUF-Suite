local root = assert(arg[1], "repository root required")
local secret, units, queue, reads, threatReads = {}, {}, {}, 0, 0
local function Public(value) return value ~= secret end
local function Finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function Frame()
    return { events = {}, RegisterEvent = function(self, event) self.events[event] = true end,
        UnregisterAllEvents = function(self) self.events = {} end,
        SetScript = function(self, _, fn) self.onEvent = fn end }
end
local S = { Public = Public, Finite = Finite,
    PublicText = function(value) return Public(value) and type(value) == "string" and value or nil end,
    Text = function(value) return value end, CreateFrame = Frame }
UnitExists = function(unit) return units[unit] ~= nil end
UnitIsDeadOrGhost = function(unit) return units[unit] and units[unit].dead or false end
UnitCanAttack = function(_, unit) return units[unit] ~= nil end
UnitAffectingCombat = function(unit) return units[unit] and units[unit].combat ~= false or false end
UnitGUID = function(unit) return units[unit] and units[unit].guid end
-- The projection needs no party threat walk: in a keystone only the party fights.
UnitThreatSituation = function() threatReads = threatReads + 1 end
C_ScenarioInfo = { GetUnitCriteriaProgressValues = function(unit)
    reads = reads + 1
    local data = units[unit]
    if data and data.none then return end
    return data and data.actual, data and data.percent
end }
local timerCallbacks = {}
C_Timer = { After = function(delay, callback)
    assert(delay >= .25, "observed pull paints more often than every 0.25 s")
    timerCallbacks[callback] = true
    queue[#queue + 1] = callback
end }
-- The Suite's one nameplate token list (MSUF_Suite_Modules/Runtime.lua).
S.NameplateUnits, S.NameplateUnit = dofile(root .. "/tools/tests/suite_test_support.lua").NameplateUnits(root)
assert(#S.NameplateUnits == 150 and S.NameplateUnits[150] == "nameplate150" and S.NameplateUnit.nameplate150
    and not S.NameplateUnit.nameplate151, "the shared nameplate tokens must run from nameplate1 to nameplate150")
local NS = { Client = {}, Dispatch = function(callback, ...) return callback(...) end }
assert(loadfile(root .. "/MSUF_Suite_Modules/MythicPlusPull.lua"))("test", { NS = NS, Suite = S })
local owner = { active = true, config = {}, mplusActive = true, mplus = { forcesPercent = 25,
    observedPull = { SetText = function(self, value) self.text = value end } } }
-- The pull paints through a job of its owner's (the objectives module's) context.
owner.context = dofile(root .. "/tools/tests/suite_test_support.lua").ModuleTimers(root, S, NS)("objectives", owner)
local H = S.MythicPlusPull
H.Sync(owner); assert(not owner.observedPull and reads == 0, "disabled projection is cold")
local function Mob(guid, percent)
    return { guid = guid, actual = 3, percent = percent }
end
units.nameplate1 = Mob("Creature-A", 1.25)
units.target = units.nameplate1
units.nameplate2 = Mob("Creature-B", 2)
owner.config.showObservedPull = true; H.Sync(owner)
assert(owner.observedPull.sum == 3.25, "target and nameplate deduplicate by public identity")
assert(owner.mplus.observedPull.text:find("28.3%%"), "projection adds only observed living contributions")
assert(reads == 2, "each GUID reads its criteria value once")
local function Fire(event, unit)
    local frame = owner.observedPull.frame
    assert(frame.events[event], event); frame.onEvent(frame, event, unit)
end
local function Flush()
    local pending = queue; queue = {}
    for _, callback in ipairs(pending) do callback() end
end
-- Unit events coalesce into one timer; no closure per event.
for _ = 1, 20 do
    Fire("UNIT_THREAT_LIST_UPDATE", "nameplate2"); Fire("UNIT_FLAGS", "nameplate2")
end
Fire("UNIT_FLAGS", "party1")
assert(#queue == 1, "bursts coalesce into one throttled paint")
Flush()
local callbacks = 0
for _ in pairs(timerCallbacks) do callbacks = callbacks + 1 end
assert(callbacks == 1 and reads == 2, "repeated paints allocated callbacks or re-read cached values")
-- A new enemy with a secret value hides the sum; the cached ones stay cached.
units.nameplate3 = Mob("Creature-S", secret)
Fire("NAME_PLATE_UNIT_ADDED", "nameplate3"); Flush()
assert(owner.observedPull.sum == nil and owner.mplus.observedPull.text == "Observed enemies  --",
    "a secret contribution must hide the sum")
units.nameplate3.percent, units.nameplate3.guid = 2, secret
H.Update(owner); assert(owner.observedPull.sum == nil, "secret identity cannot deduplicate")
-- A unit without criteria progress (a boss) adds nothing and keeps the sum known.
units.nameplate3 = { guid = "Creature-Boss", none = true }
H.Update(owner)
assert(owner.observedPull.sum == 3.25 and owner.mplus.observedPull.text:find("28.3%%"),
    "a unit without criteria progress must count as zero, not unknown")
units.nameplate3 = nil
Fire("NAME_PLATE_UNIT_REMOVED", "nameplate3"); Flush()
units.nameplate2.dead = true
owner.mplus.forcesPercent = 27
H.Update(owner)
assert(owner.observedPull.sum == 1.25 and owner.mplus.observedPull.text:find("28.3%%"),
    "confirmed death progress must not double-count the dead enemy")
units.nameplate1.dead = true; Fire("UNIT_FLAGS", "nameplate1"); Flush()
assert(owner.observedPull.sum == 0, "dead target alias cannot keep the contribution alive")
units.target = nil; units.nameplate1 = nil
Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1"); Flush()
units.nameplate1 = Mob("Creature-C", 4)
Fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); Flush()
assert(owner.observedPull.sum == 4, "reused nameplate token reads the new identity")
units.nameplate1 = nil; Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1"); Flush()
assert(owner.observedPull.sum == 0, "removed enemies leave the observed subset")
units.nameplate1 = Mob("Creature-C", 4)
Fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); Flush()
assert(owner.observedPull.sum == 4, "returning units re-enter without duplicate retained history")
Fire("PLAYER_REGEN_ENABLED"); Flush()
assert(owner.observedPull.sum == 4, "player combat ending must not declare ongoing party combat empty")
units.nameplate1.combat = false
Fire("PLAYER_REGEN_ENABLED"); Flush()
assert(owner.observedPull.sum == 0, "actual enemy combat stop removes stale contribution")
units.nameplate1.combat = true
Fire("PLAYER_REGEN_DISABLED"); Flush(); assert(owner.observedPull.sum == 4)
units.nameplate4 = Mob("Creature-D", math.huge)
Fire("NAME_PLATE_UNIT_ADDED", "nameplate4"); Flush()
assert(owner.observedPull.sum == nil, "an invalid contribution must hide the sum")
units.nameplate4 = nil
Fire("NAME_PLATE_UNIT_REMOVED", "nameplate4")
Fire("UNIT_FLAGS", "nameplate1"); H.Stop(owner); Flush()
assert(not next(owner.observedPull.frame.events) and owner.observedPull.sum == nil, "stop cancels queued updates")
assert(threatReads == 0, "the observed pull walked party threat")
-- A wait from before Stop stays stale after a restart: the new run's first
-- request waits its own full delay instead of painting on the old wait.
H.Sync(owner)
Fire("UNIT_FLAGS", "nameplate1")
local stale = queue[#queue]
H.Stop(owner)
H.Sync(owner)
assert(owner.observedPull.sum == 4, "a restart did not paint at once")
units.nameplate5 = Mob("Creature-E", 1)
Fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
local fresh = queue[#queue]
assert(stale and fresh and fresh ~= stale or #queue == 2, "the restart reused the stale wait")
stale()
assert(owner.observedPull.sum == 4, "a wait from before Stop painted the new run's request early")
fresh()
assert(owner.observedPull.sum == 5, "the new run's request did not paint after its delay")
queue = {}
units.nameplate5 = nil
H.Stop(owner)
-- A new run reads its values again (the cache belongs to one run).
local before = reads
H.Sync(owner)
assert(owner.observedPull.sum == 4 and reads == before + 1, "a new run must not reuse the previous run's values")
-- Every nameplate token counts, up to nameplate150: the run's start snapshot
-- and the plate events of a large pull past nameplate60.
H.Stop(owner)
units.nameplate150 = Mob("Creature-F", 2)
H.Sync(owner)
assert(owner.observedPull.sum == 6, "the snapshot missed a nameplate token up to 150")
units.nameplate97 = Mob("Creature-G", .5)
Fire("NAME_PLATE_UNIT_ADDED", "nameplate97"); Flush()
assert(owner.observedPull.sum == 6.5, "a nameplate event past nameplate60 was ignored")
units.nameplate97, units.nameplate150 = nil, nil
Fire("NAME_PLATE_UNIT_REMOVED", "nameplate97"); Flush()
owner.mplus.completed = true; H.Sync(owner); assert(not owner.observedPull.active)
print("Observed Mythic+ pull: throttled paints, per-GUID values, zero for no progress, secrets unknown, dedupe, deaths, remove/reentry and cleanup passed")
