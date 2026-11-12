local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
local implementation = arg[3] or root .. "/MSUF_Suite_ActionBars/Snapshots.lua"
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, field in pairs(value) do result[Copy(key)] = Copy(field) end
    return result
end

local function Count(entries)
    local count = 0
    for _ in pairs(entries) do count = count + 1 end
    return count
end

local encoded, serial = {}, 0
function MSUF_EncodeCompactTable(value, format)
    assert(format == "MSUF3", "unexpected wire codec")
    serial = serial + 1
    local token = "MSUF3:wire" .. serial
    encoded[token] = Copy(value)
    return token
end
function MSUF_TryDecodeCompactString(token) return Copy(encoded[token]) end

local now, calls, active, blocked = 50, {}, nil, nil
function GetTime() return now end
function time() return math.floor(now) end
function GetServerTime() return math.floor(now) end
local function Called(key) calls[key] = (calls[key] or 0) + 1 end

local function Character(guid, name, class, spec, setup, spell, scope)
    return {
        identity = {
            guid = guid, name = name, realm = "TestRealm", class = class, spec = spec,
            setup = setup, setupLabel = class .. " build",
        },
        slots = { [1] = spell }, keys = { ["1"] = "ACTIONBUTTON1" }, scope = scope or "character",
    }
end

local suite = {
    RootDB = {},
    loginKind = "login",
    Client = { isForever = flavor == "Forever" },
    Dispatch = function(callback, ...) return callback(...) end,
}
local runtime = {
    CopyValue = Copy,
    Text = function(value) return value end,
    Public = function() return true end,
    PublicText = function(value) return type(value) == "string" and value or nil end,
    Finite = function(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end,
    InCombat = function() return blocked == "combat" end,
    IsCombatLocked = function() return blocked == "combat" end,
}
suite.Suite = runtime
local bar = { M = { active = true } }
local native = {}
bar.SnapshotNative = native
local function ContractData(slots, keys, scope)
    return { slots = Copy(slots), keys = Copy(keys), scope = scope }
end

function native.Identity()
    Called("identity")
    return Copy(active.identity)
end
function native.Blocked() return blocked end
function native.BindingScope() return active.scope end
function native.AllowedSlot(slot) return type(slot) == "number" and slot > 0 and slot <= 180 end
function native.AllowedIndependentSlot(slot) return type(slot) == "number" and slot >= 1 and slot <= 12 end
function native.AllowedGroup(group) return suite.Client.isForever and (group == 1 or group == 2) end
function native.AllowedCommand(command)
    return command == "ACTIONBUTTON1" or command == "ACTIONBUTTON2" or command == "ACTIONBUTTON3"
end
function native.ValidKey(key) return key == "1" or key == "2" or key == "CTRL-1" end
function native.CaptureKeys() return Copy(active.keys), active.scope end
function native.Capture()
    assert(not blocked, "capture ran while blocked")
    Called("capture")
    local result = ContractData(active.slots, active.keys, active.scope)
    result.independentSlots = Copy(active.independentSlots)
    return result
end

local function PlanChanges(incoming, current)
    local entries = {}
    for key, value in pairs(incoming) do
        if current[key] ~= value then entries[key] = { before = current[key] or false, after = value } end
    end
    return entries
end

function native.Plan(record, applySlots, applyKeys)
    assert(not blocked, "plan ran while blocked")
    Called("plan")
    if applyKeys then Called("bindingPlan") end
    local keysMatch = active.scope == record.scope
    return {
        identity = native.Identity(),
        backup = {
            scope = active.scope,
            slots = applySlots and PlanChanges(record.slots, active.slots) or {},
            independentSlots = applySlots and record.independentSlots
                and PlanChanges(record.independentSlots, active.independentSlots),
            keys = applyKeys and keysMatch and PlanChanges(record.keys, active.keys) or {},
        },
        skippedSlots = 0,
        skippedKeys = applyKeys and not keysMatch and Count(record.keys) or 0,
    }
end

local function ApplyChanges(entries, current, field)
    for key, entry in pairs(entries) do
        current[key] = entry[field] or nil
    end
    return Count(entries)
end

function native.Apply(plan)
    assert(not blocked, "apply ran while blocked")
    Called("apply")
    assert(plan.identity.guid == active.identity.guid, "stale plan crossed characters")
    local backup = plan.backup
    local independentCount = backup.independentSlots and ApplyChanges(backup.independentSlots, active.independentSlots, "after")
    return {
        slots = ApplyChanges(backup.slots, active.slots, "after") + (independentCount or 0),
        keys = ApplyChanges(backup.keys, active.keys, "after"),
        skippedSlots = plan.skippedSlots, skippedKeys = plan.skippedKeys, backup = Copy(backup),
    }
end

function native.Restore(backup)
    assert(not blocked, "restore ran while blocked")
    Called("restore")
    local independentCount = backup.independentSlots and ApplyChanges(backup.independentSlots, active.independentSlots, "before")
    return {
        slots = ApplyChanges(backup.slots, active.slots, "before") + (independentCount or 0),
        keys = ApplyChanges(backup.keys, active.keys, "before"),
        skippedSlots = 0, skippedKeys = 0,
    }
end

local context, jobs, events = {}, {}, {}
local Job = {}
Job.__index = Job
function Job:Request()
    Called("request")
    jobs[self] = true
end
function Job:Cancel() jobs[self] = nil end
function context:Coalesce(delay, callback)
    assert(delay == 0, "snapshot work must coalesce without polling")
    return setmetatable({ callback = callback }, Job)
end
function context:Event(event, callback) events[event] = callback end
function context:RemoveEvent(event) events[event] = nil end
function context:UnregisterEvent(event) events[event] = nil end

local function Drain()
    local attempts = 0
    while next(jobs) do
        attempts = attempts + 1
        assert(attempts < 10, "snapshot work rescheduled itself")
        local job = next(jobs)
        jobs[job] = nil
        job.callback()
    end
end

local function Login(character, db, beforeWorld)
    if bar.StopSnapshots then bar.StopSnapshots() end
    events = {}
    jobs = {}
    active = character
    suite.loginKind = not beforeWorld and "login" or nil
    if db then suite.RootDB = db end
    bar.StartSnapshots(context)
    if not beforeWorld and bar.snapshotReady then bar.snapshotReady() end
    Drain()
end

local function Event()
    if bar.snapshotReady then bar.snapshotReady() end
    Drain()
end

local function ByClass(packet)
    local result = {}
    for index, record in ipairs(packet.records) do result[record.class] = index end
    return result
end

assert(loadfile(implementation))("MSUF_Suite_ActionBars", { ActionBars = bar, NS = suite, Suite = runtime })
local api = assert(suite.ActionBarSnapshots, "snapshot API missing")
local sourceWarrior = Character("source-warrior", "Armsalt", "WARRIOR", 71, "arms-source", 101, "account")
local sourcePriest = Character("source-priest", "Priestalt", "PRIEST", 258, "shadow-source", 201)
local sourceDruid = Character("source-druid", "Druidalt", "DRUID", 105, "resto-source", 301)
sourcePriest.slots[73], sourcePriest.keys["CTRL-1"] = 273, "ACTIONBUTTON3"
sourceDruid.keys["2"] = "ACTIONBUTTON2"
sourceDruid.slots[109] = 309
sourceDruid.independentSlots = { [1] = 310, [12] = 312 }

Login(sourceWarrior)
assert(not api.Status().capture, "background capture must be opt-in")
local captureBefore = calls.capture
local identityBefore = calls.identity
local requestBefore = calls.request
for _ = 1, 500 do if bar.snapshotChanged then bar.snapshotChanged() end end
Drain()
assert(calls.capture == captureBefore and calls.identity == identityBefore and calls.request == requestBefore,
    "disabled snapshot capture did work on the action update path")

assert(api.Capture())
Login(sourcePriest)
assert(api.Capture())
Login(sourceDruid)
assert(api.SetCapture(true))
assert(api.Capture())
local reads = calls.capture
active.slots[73] = 373
for _ = 1, 500 do if bar.snapshotChanged then bar.snapshotChanged() end end
Drain()
assert(calls.capture == reads + 1, "action updates did not coalesce to one capture")
assert(api.SetCapture(false))
Login(sourceWarrior)
assert(#api.Status().saved == 3, "account storage lost an offline source character")
local code = assert(api.Export())
local packet = assert(api.Decode(code))
local byClass = ByClass(packet)
assert(#packet.records == 3 and byClass.PRIEST and byClass.DRUID and byClass.WARRIOR,
    "export did not round-trip three distinct characters")
assert(packet.records[byClass.PRIEST].slots[73] == 273, "non-visible slot dropped from export")
assert(packet.records[byClass.DRUID].slots[73] == 373, "coalesced slot change missing in export")
local druid = packet.records[byClass.DRUID]
assert(druid.slots[109] == 309 and druid.independentSlots[1] == 310 and druid.independentSlots[12] == 312,
    "the wire packet lost the independent bar or form-page action")
assert(packet.records[byClass.PRIEST].independentSlots == nil, "old captures gained an independent bar")
for _, saved in ipairs(api.Status().saved) do
    if saved.class == "DRUID" then
        assert(saved.slotCount == 5 and saved.independentSlots == nil, "saved summary did not count independent actions")
    end
end
assert(packet.records[byClass.WARRIOR].scope == "account" and packet.records[byClass.PRIEST].scope == "character",
    "export combined account and character binding scopes")
assert(packet.records[byClass.PRIEST].keys["CTRL-1"] == "ACTIONBUTTON3", "modifier binding dropped")
for _, record in ipairs(packet.records) do assert(not record.guid, "source-local GUID leaked into packet") end
assert(not api.Decode("this is not a snapshot"), "accepted an invalid packet prefix")

local token = "MSUF3:" .. assert(code:match("(wire%d+)$"))
local original = encoded[token]
local bad = Copy(original)
bad.records[1].slots[999999] = 42
encoded[token] = bad
assert(not api.Decode(code), "accepted an invalid slot")
bad = Copy(original)
bad.records[byClass.DRUID].independentSlots[13] = 42
encoded[token] = bad
assert(not api.Decode(code), "accepted a nonexistent independent slot")
bad = Copy(original)
bad.records[byClass.DRUID].independentSlots[1] = false
encoded[token] = bad
assert(not api.Decode(code), "accepted a destructive empty action in an independent snapshot")
bad = Copy(original)
bad.records[1].keys["1"] = "MOVEFORWARD"
encoded[token] = bad
assert(not api.Decode(code), "accepted an unrelated binding command")
bad = Copy(original)
bad.flavor = flavor == "Forever" and "retail" or "forever"
encoded[token] = bad
assert(not api.Decode(code), "accepted a package for a different WoW client")
encoded[token] = original

local destination = {}
local destWarrior = Character("dest-warrior", "Swords", "WARRIOR", 71, "arms-destination", 911, "account")
local destPriest = Character("dest-priest", "Luminous", "PRIEST", 258, "shadow-destination", 921)
local destDruid = Character("dest-druid", "Thorn", "DRUID", 105, "resto-destination", 931)
destPriest.independentSlots = { [1] = 980 }
destDruid.independentSlots = { [1] = 982 }
destDruid.slots[109] = 983
local unrelated = Character("dest-unrelated", "Other", "PRIEST", 258, "shadow-destination", 941)
local wrongClass = Character("dest-other-thorn", "Thorn", "WARRIOR", 71, "arms-destination", 951)
local noRealmMatch = Character("dest-other-realm", "Thorn", "DRUID", 105, "resto-destination", 961)
noRealmMatch.identity.realm = "OtherRealm"
local assignments = {
    [byClass.WARRIOR] = "Swords",
    [byClass.PRIEST] = "Luminous-TestRealm",
    [byClass.DRUID] = "Thorn-TestRealm",
}

Login(destWarrior, destination)
local repeated = Copy(original)
local duplicate = Copy(repeated.records[byClass.PRIEST])
duplicate.name = "Secondpriest"
repeated.records[#repeated.records + 1] = duplicate
encoded[token] = repeated
local repeatedPacket = assert(api.Decode(code))
encoded[token] = original
local duplicateAssignments = Copy(assignments)
duplicateAssignments[#repeated.records] = "Luminous-TestRealm"
assert(not api.Queue(repeatedPacket, duplicateAssignments, true, true),
    "multiple source snapshots were staged for the same target and specialization")
duplicate.spec = nil
encoded[token] = repeated
local wildcardPacket = assert(api.Decode(code))
encoded[token] = original
assert(not api.Queue(wildcardPacket, duplicateAssignments, true, true),
    "a specialization wildcard overlapped a concrete target specialization")
assert(#api.Status().pending == 0, "rejected queue wrote a partial batch")
assert(not api.Queue(packet, {}, true, true), "empty import staged")
assert(not api.Queue(packet, assignments, false, false), "empty import mode staged")
assert(api.Queue(packet, assignments, true, true))
Drain()
assert(destWarrior.slots[1] == 101, "active target was not applied")
assert(destPriest.slots[1] == 921 and destDruid.slots[1] == 931, "offline targets were mutated")
assert(#api.Status().pending == 2, "offline imports were not persisted")
local applyBefore = calls.apply
Login(unrelated)
Login(wrongClass)
Login(noRealmMatch)
assert(calls.apply == applyBefore, "pending import matched wrong name, class or realm")
assert(#api.Status().pending == 2, "mismatched login consumed a pending import")

destPriest.identity.spec = 257
Login(destPriest)
assert(calls.apply == applyBefore and #api.Status().pending == 2, "wrong specialization consumed a pending import")
destPriest.identity.spec = 258
Login(destPriest, nil, true)
assert(calls.apply == applyBefore and #api.Status().pending == 2, "import ran before the native world state was ready")
suite.loginKind = "login"
blocked = "combat"
Event()
assert(calls.apply == applyBefore and #api.Status().pending == 2, "import ran in combat")
blocked = "cursor"
Event()
assert(calls.apply == applyBefore and #api.Status().pending == 2, "import ran while cursor held an action")
blocked = nil
Event()
assert(calls.apply == applyBefore + 1 and destPriest.slots[1] == 201 and destPriest.slots[73] == 273,
    "pending priest setup did not apply after unlocking")
assert(destPriest.keys["CTRL-1"] == "ACTIONBUTTON3", "pending character binding was not restored")
assert(destPriest.independentSlots[1] == 980, "an old packet touched the independent bar")
assert(#api.Status().pending == 1, "successful priest import was not consumed")
local savedAfter = Copy(destination)
Login(destPriest, savedAfter)
Event()
assert(calls.apply == applyBefore + 1, "completed import replayed after database reload")

Login(destDruid)
assert(destDruid.slots[1] == 301 and destDruid.slots[73] == 373 and destDruid.keys["2"] == "ACTIONBUTTON2",
    "pending druid setup was not restored")
assert(destDruid.slots[109] == 309 and destDruid.independentSlots[1] == 310 and destDruid.independentSlots[12] == 312,
    "queued import did not independently restore both slot owners")
assert(#api.Status().pending == 0 and api.Status().canRestore, "completed target has no restore point")
assert(api.Restore())
Drain()
assert(destDruid.slots[1] == 931 and destDruid.slots[73] == nil and destDruid.keys["2"] == nil,
    "restore did not restore Druid's exact previous state")
assert(destDruid.slots[109] == 983 and destDruid.independentSlots[1] == 982 and destDruid.independentSlots[12] == nil,
    "restore did not recover the previous independent actions and form page")
assert(destPriest.slots[1] == 201 and destWarrior.slots[1] == 101, "Druid restore reached another character")

local one = { [byClass.PRIEST] = "Spare-TestRealm" }
assert(api.Queue(packet, one, true, false))
Drain()
assert(#api.Status().pending == 1, "offline task missing after queue")
assert(api.Cancel(api.Status().pending[1].id))
Login(Character("dest-spare", "Spare", "PRIEST", 258, "shadow-spare", 971))
assert(active.slots[1] == 971, "cancelled import ran on target login")

-- One account has one binding map. An older account-scoped snapshot must
-- pick up the latest map and the account map must be staged for only one job.
local accountSource = {}
sourcePriest.scope = "account"
sourcePriest.keys = { ["1"] = "ACTIONBUTTON3", ["2"] = "ACTIONBUTTON2" }
Login(sourceWarrior, accountSource)
assert(api.Capture())
Login(sourcePriest)
assert(api.Capture())
local accountPacket = assert(api.Decode(assert(api.Export())))
local accountClass = ByClass(accountPacket)
assert(accountPacket.records[accountClass.WARRIOR].keys["1"] == "ACTIONBUTTON3",
    "old account-scoped record exported a stale shared map")
local sharedKeys = { ["1"] = "ACTIONBUTTON2" }
destWarrior.keys, destPriest.keys = sharedKeys, sharedKeys
destPriest.scope = "account"
Login(destWarrior, {})
local bindBefore = calls.bindingPlan or 0
local both = { [accountClass.WARRIOR] = "Swords", [accountClass.PRIEST] = "Luminous" }
assert(api.Queue(accountPacket, both, true, true))
Drain()
Login(destPriest)
assert(sharedKeys["1"] == "ACTIONBUTTON3", "account map was not applied")
assert(calls.bindingPlan == bindBefore + 1, "same account map was applied once per target")
Login(destWarrior, {})
assert(api.Queue(accountPacket, both, false, true))
Drain()
assert(#api.Status().pending == 0, "deduplicated account keys-only import left an empty alt job")

-- Saved native loadout IDs are account-local. The confirmed destination label
-- must select a loadout even when the specialization alone already matches.
sourceWarrior.identity.loadout = "Source Raid"
Login(sourceWarrior, {})
assert(api.Capture())
local loadoutPacket = assert(api.Decode(assert(api.Export())))
assert(loadoutPacket.records[1].loadout == "Source Raid", "named source loadout was not exported")
destWarrior.identity.loadout = "Dungeon"
destWarrior.identity.setup = "dest-dungeon"
destWarrior.slots[1] = 985
Login(destWarrior, {})
local loadoutBefore = calls.apply
assert(api.Queue(loadoutPacket, { "Swords | Raid" }, true, false))
Drain()
assert(calls.apply == loadoutBefore and #api.Status().pending == 1,
    "a different native loadout in the same specialization consumed the import")
destWarrior.identity.loadout = "Raid"
destWarrior.identity.setup = "dest-raid"
assert(events.SELECTED_LOADOUT_CHANGED, "a pending named loadout must watch native loadout changes")
events.SELECTED_LOADOUT_CHANGED()
Drain()
assert(calls.apply == loadoutBefore + 1 and destWarrior.slots[1] == 101,
    "named loadout did not receive the confirmed slot import")

-- Shared and character binding sets are not interchangeable. A pending
-- keys-only import should survive switching the target's binding scope.
local scopeSource = Character("source-scope", "Scoped", "PRIEST", 258, "scope-source", 601)
scopeSource.keys["CTRL-1"] = "ACTIONBUTTON3"
Login(scopeSource, {})
assert(api.Capture())
local scopePacket = assert(api.Decode(assert(api.Export())))
local scopeTarget = Character("dest-scope", "Recipient", "PRIEST", 258, "scope-target", 981, "account")
Login(scopeTarget, {})
assert(api.Queue(scopePacket, { "Recipient" }, false, true))
Drain()
assert(scopeTarget.keys["CTRL-1"] == nil and #api.Status().pending == 1,
    "a scope mismatch either consumed the transfer or wrote to the wrong binding set")
scopeTarget.scope = "character"
Event()
assert(scopeTarget.keys["CTRL-1"] == "ACTIONBUTTON3" and #api.Status().pending == 0,
    "correcting the binding scope did not resume the confirmed key import")

Login(destWarrior, {})
assert(api.Queue(accountPacket, { [accountClass.PRIEST] = "Waitingpriest" }, false, true))
Drain()
assert(#api.Status().pending == 1, "offline shared binding job did not remain queued")
local conflictingAccountPacket = Copy(accountPacket)
for _, record in ipairs(conflictingAccountPacket.records) do record.keys["1"] = "ACTIONBUTTON1" end
assert(not api.Queue(conflictingAccountPacket, { [accountClass.WARRIOR] = "Anotherwarrior" }, false, true),
    "a second account-wide key package overlapped an already queued shared map")
assert(#api.Status().pending == 1, "rejected shared binding job changed the queue")

-- Profile strings carry the action bar key map. An import writes it into the
-- binding set the character uses now, lists it as a result and can be undone.
local profileSource = Character("source-profile", "Profiled", "PRIEST", 258, "profile-source", 701)
profileSource.keys = { ["1"] = "ACTIONBUTTON2", ["CTRL-1"] = "ACTIONBUTTON3" }
Login(profileSource, {})
local carried = assert(api.ProfileKeys())
assert(carried["1"] == "ACTIONBUTTON2" and carried["CTRL-1"] == "ACTIONBUTTON3", "the profile key map lost a key")
local profileTarget = Character("dest-profile", "Keyed", "PRIEST", 258, "profile-target", 702, "account")
Login(profileTarget, {})
assert(not api.ImportProfileKeys({ ["1"] = "MOVEFORWARD" }), "an unrelated command entered the bindings")
assert(not api.ImportProfileKeys({}), "an empty key map was applied")
blocked = "combat"
assert(not api.ImportProfileKeys(carried) and profileTarget.keys["1"] == "ACTIONBUTTON1", "keys were written in combat")
blocked = nil
bar.M.active = false
assert(not api.ImportProfileKeys(carried) and profileTarget.keys["1"] == "ACTIONBUTTON1",
    "keys were written while the Suite action bars were off")
bar.M.active = true
assert(api.ImportProfileKeys(carried), "a character-scoped key map did not reach an account-scoped target")
assert(profileTarget.keys["1"] == "ACTIONBUTTON2" and profileTarget.keys["CTRL-1"] == "ACTIONBUTTON3",
    "the imported profile keys were not applied")
local status = api.Status()
assert(status.results[1].keys == 2 and status.results[1].name == "Keyed" and status.canRestore,
    "a profile key import was not listed or cannot be undone")
assert(api.Restore() and profileTarget.keys["1"] == "ACTIONBUTTON1" and profileTarget.keys["CTRL-1"] == nil,
    "undo did not restore the keys from before the profile import")

if flavor == "Forever" then
    local source = Character("source-dual", "Dual", "DRUID", 105, "group:1", 511)
    source.identity.group, source.independentSlots = 1, { [1] = 512 }
    Login(source, {})
    assert(api.SetCapture(true))
    Drain()
    source.identity.group, source.identity.setup, source.slots[1], source.independentSlots[1] = 2, "group:2", 521, 522
    assert(bar.snapshotSetupChanged, "automatic capture must watch dual spec changes")
    bar.snapshotSetupChanged()
    Drain()
    assert(#api.Status().saved == 2, "automatic capture overwrote the other spec group")
    assert(api.SetCapture(false) and not bar.snapshotSetupChanged, "disabled capture kept its group listener")
    local dualCode = assert(api.Export())
    local dualPacket = assert(api.Decode(dualCode))
    assert(#dualPacket.records == 2 and dualPacket.records[1].group == 1 and dualPacket.records[2].group == 2,
        "dual spec captures lost distinct group identity")
    local dualToken = "MSUF3:" .. assert(dualCode:match("(wire%d+)$"))
    local dualOriginal = encoded[dualToken]
    encoded[dualToken] = Copy(dualOriginal)
    encoded[dualToken].records[1].group = 3
    assert(not api.Decode(dualCode), "accepted a nonexistent dual spec group")
    encoded[dualToken] = dualOriginal

    local recipient = Character("dest-dual", "Dualdest", "DRUID", 105, "group:2", 801)
    recipient.identity.group, recipient.independentSlots = 2, { [1] = 802 }
    Login(recipient, {})
    local duplicate = Copy(dualPacket)
    duplicate.records[1].group = nil
    assert(not api.Queue(duplicate, { "Dualdest", "Dualdest" }, true, false),
        "a legacy group wildcard overlapped a specific group")
    assert(api.Queue(dualPacket, { "Dualdest", "Dualdest" }, true, false))
    Drain()
    assert(#api.Status().pending == 1 and recipient.slots[1] == 521 and recipient.independentSlots[1] == 522,
        "the active group did not receive its own snapshot")
    local secondarySlots, secondaryIndependent = recipient.slots, recipient.independentSlots
    recipient.identity.group, recipient.identity.setup = 1, "group:1"
    recipient.slots, recipient.independentSlots = { [1] = 811 }, { [1] = 812 }
    assert(bar.snapshotSetupChanged, "a pending group must watch dual spec changes")
    bar.snapshotSetupChanged()
    Drain()
    assert(#api.Status().pending == 0 and recipient.slots[1] == 511 and recipient.independentSlots[1] == 512,
        "a switch to the other talent group did not resume the import")
    assert(api.Restore() and recipient.slots[1] == 811 and recipient.independentSlots[1] == 812
        and secondarySlots[1] == 521 and secondaryIndependent[1] == 522,
        "undo crossed dual spec group boundaries")
    recipient.identity.group, recipient.identity.setup = 2, "group:2"
    recipient.slots, recipient.independentSlots = secondarySlots, secondaryIndependent
    assert(api.Restore() and recipient.slots[1] == 801 and recipient.independentSlots[1] == 802,
        "the other group's own undo was lost")
    local legacy = Copy(dualPacket)
    legacy.records[1].group, legacy.records[1].independentSlots, legacy.records[2] = nil, nil, nil
    assert(api.Queue(legacy, { "Dualdest" }, true, false))
    Drain()
    assert(recipient.slots[1] == 511 and recipient.independentSlots[1] == 802,
        "a legacy snapshot could not apply to a known group independently of Bar 10")
else
    local badGroup = Copy(original)
    badGroup.records[1].group = 1
    encoded[token] = badGroup
    assert(not api.Decode(code), "accepted a Forever group on Retail")
    encoded[token] = original
end

print("actionbar snapshots account contract passed (" .. flavor .. ")")
