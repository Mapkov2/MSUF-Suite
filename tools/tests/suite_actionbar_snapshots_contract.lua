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
    HideQuestion = function() end,
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
-- keysUnreadable: the binding set is neither the account's nor the character's.
local keysUnreadable
function native.CaptureKeys()
    if keysUnreadable then return nil, "unavailable" end
    return Copy(active.keys), active.scope
end
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

-- applyReason: what stopped the apply part-way (the report's reason).
local applyReason
function native.Apply(plan)
    assert(not blocked, "apply ran while blocked")
    Called("apply")
    assert(plan.identity.guid == active.identity.guid, "stale plan crossed characters")
    local backup = plan.backup
    local independentCount = backup.independentSlots and ApplyChanges(backup.independentSlots, active.independentSlots, "after")
    return {
        slots = ApplyChanges(backup.slots, active.slots, "after") + (independentCount or 0),
        keys = ApplyChanges(backup.keys, active.keys, "after"),
        skippedSlots = plan.skippedSlots, skippedKeys = plan.skippedKeys, backup = Copy(backup), reason = applyReason,
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

-- Profile strings carry the exporting character's action bars. An import
-- offers them (RootDB.actionBarOffer, MSUF_Suite/Core/ProfileClients.lua)
-- and nothing is written before the player agreed: one question for the key
-- bindings (they come along from either WoW version, for any character),
-- one for the spells (only for the class and specialization they came
-- from). What was agreed to is one transfer to the current setup (listed,
-- reported in chat, undoable); No leaves that part as it is.
local questions, printed = {}, {}
runtime.Confirm = function(key, data) questions[#questions + 1] = { key = key, data = data } end
runtime.Print = function(text) printed[#printed + 1] = text end
local hidden = 0
runtime.HideQuestion = function(key)
    for index = #questions, 1, -1 do
        if questions[index].key == key then
            table.remove(questions, index)
            hidden = hidden + 1
        end
    end
end
-- Callbacks for the next frame; NextFrame runs them.
local timers = {}
C_Timer = { After = function(seconds, callback)
    assert(seconds == 0 and type(callback) == "function", "only next-frame timers are expected here")
    timers[#timers + 1] = callback
end }
local function NextFrame()
    local due = timers
    timers = {}
    for _, callback in ipairs(due) do callback() end
end
-- Answers the shown question; the next step follows a frame later, never
-- from inside the answer (Blizzard would hide a dialog shown there).
local function Answer(yes)
    local question = table.remove(questions, 1)
    assert(question, "no question was asked")
    if yes then question.data.callback() else question.data.cancelCallback() end
    assert(#questions == 0, "a question was shown from inside the answer of the one before")
    NextFrame()
end
local function Printed(text)
    local line = table.remove(printed, 1)
    assert(line and line:find(text, 1, true), "expected a chat line with: " .. text .. ", got: " .. tostring(line))
end
local profileSource = Character("source-profile", "Profiled", "PRIEST", 258, "profile-source", 701)
profileSource.keys = { ["1"] = "ACTIONBUTTON2", ["CTRL-1"] = "ACTIONBUTTON3" }
profileSource.independentSlots = { [2] = 705 }
Login(profileSource, {})
local setup = assert(api.ProfileSetup())
assert(setup.keys["1"] == "ACTIONBUTTON2" and setup.keys["CTRL-1"] == "ACTIONBUTTON3" and setup.slots[1] == 701
    and setup.independentSlots[2] == 705 and setup.class == "PRIEST" and setup.spec == 258
    and setup.label == "PRIEST build", "the profile setup lost a part")
blocked = "cursor"
local keysOnly = assert(api.ProfileSetup())
assert(keysOnly.keys["1"] == "ACTIONBUTTON2" and keysOnly.slots == nil, "a blocked capture did not keep the keys alone")
blocked = nil
bar.M.active = false
assert(api.ProfileSetup() == nil and api.AskProfileSetup() == false,
    "the profile setup was read or asked while the Suite action bars were off")
bar.M.active = true

local thisClient = suite.Client.isForever and "forever" or "retail"
local db = {}
local function Offer(value, guid, client)
    db.actionBarOffer = { v = 1, client = client or thisClient, guid = guid, setup = Copy(value) }
    return db.actionBarOffer
end
local profileTarget = Character("dest-profile", "Keyed", "PRIEST", 258, "profile-target", 702, "account")
profileTarget.independentSlots = {}
local function Untouched()
    return profileTarget.slots[1] == 702 and profileTarget.independentSlots[2] == nil
        and profileTarget.keys["1"] == "ACTIONBUTTON1" and profileTarget.keys["CTRL-1"] == nil
end
Login(profileTarget, db)

-- Both parts, both agreed: the key bindings are asked first, then the
-- spells; nothing is written or queued before the last answer.
Offer(setup, "dest-profile")
assert(api.AskProfileSetup() and #questions == 1 and questions[1].key == "actionbars:profile-import",
    "the import did not ask about its action bars")
local question = questions[1].data.text_arg1
assert(question:find("includes 2 action bar key bindings", 1, true) and questions[1].data.text == "%s"
    and not question:find("spells", 1, true), "the first question is not the key binding question: " .. question)
assert(question:find("account-wide key bindings", 1, true), "the question hid that the key bindings are account-wide")
local applies = calls.apply or 0
Event()
assert(#questions == 1, "the same offer was asked twice in one session")
Answer(true)
assert(#questions == 1 and Untouched() and #api.Status().pending == 0 and db.actionBarOffer ~= nil,
    "the key binding answer wrote or queued before the spells were answered")
question = questions[1].data.text_arg1
assert(question:find("action bar spells of PRIEST build: 2 spells", 1, true)
    and not question:find("key bindings", 1, true), "the second question is not the spell question: " .. question)
blocked = "combat"
Answer(true)
assert(db.actionBarOffer == nil and #api.Status().pending == 1 and Untouched() and (calls.apply or 0) == applies
    and #printed == 0, "the agreed action bars were written in combat or not queued")
blocked = nil
Event()
assert(profileTarget.slots[1] == 701 and profileTarget.independentSlots[2] == 705
    and profileTarget.keys["1"] == "ACTIONBUTTON2" and profileTarget.keys["CTRL-1"] == "ACTIONBUTTON3"
    and #api.Status().pending == 0, "the agreed action bars were not applied after combat")
Printed("Profile action bars applied: 2 key bindings and 2 spells changed, 0 left as they were.")
local status = api.Status()
assert(status.results[1].label == "Profile import" and status.results[1].name == "Keyed" and status.canRestore,
    "the profile import was not listed or cannot be undone")
assert(api.Restore() and Untouched(), "undo did not restore the bars from before the profile import")

-- With key bindings, without spells; and the other way around.
Offer(setup, "dest-profile")
assert(api.AskProfileSetup())
Answer(true)
Answer(false)
Event()
assert(db.actionBarOffer == nil and profileTarget.keys["1"] == "ACTIONBUTTON2" and profileTarget.keys["CTRL-1"] == "ACTIONBUTTON3"
    and profileTarget.slots[1] == 702 and profileTarget.independentSlots[2] == nil,
    "key bindings without spells did not apply the keys alone")
Printed("Profile action bars applied: 2 key bindings and 0 spells changed")
assert(api.Restore() and Untouched())
Offer(setup, "dest-profile")
assert(api.AskProfileSetup())
Answer(false)
Answer(true)
Event()
assert(db.actionBarOffer == nil and profileTarget.slots[1] == 701 and profileTarget.independentSlots[2] == 705
    and profileTarget.keys["1"] == "ACTIONBUTTON1" and profileTarget.keys["CTRL-1"] == nil,
    "spells without key bindings did not apply the spells alone")
Printed("Profile action bars applied: 0 key bindings and 2 spells changed")
assert(api.Restore() and Untouched())

-- No to everything drops the offer; nothing changes and nothing is said.
Offer(setup, "dest-profile")
assert(api.AskProfileSetup())
Answer(false)
Answer(false)
Event()
assert(db.actionBarOffer == nil and #questions == 0 and Untouched() and #api.Status().pending == 0 and #printed == 0,
    "No still applied, kept the offer or printed")
-- Also while nothing could be applied anyway: No needs no character.
Offer(setup, "dest-profile")
assert(api.AskProfileSetup())
Answer(false)
bar.M.active = false
Answer(false)
bar.M.active = true
assert(db.actionBarOffer == nil and #printed == 0, "No kept the offer or printed while the bars could not be read")

-- Key bindings of the other WoW version, or of another class, come without
-- spells: one question, and the keys apply.
Offer({ keys = setup.keys }, "dest-profile")
assert(api.AskProfileSetup() and #questions == 1 and questions[1].data.text_arg1:find("2 action bar key bindings", 1, true))
Answer(true)
assert(#questions == 0, "key bindings without spells asked a second question")
Event()
assert(profileTarget.keys["1"] == "ACTIONBUTTON2" and profileTarget.slots[1] == 702, "the key bindings alone were not applied")
Printed("Profile action bars applied: 2 key bindings and 0 spells changed")
assert(api.Restore() and Untouched())

-- An apply that stopped part-way says so instead of counting.
Offer({ keys = setup.keys }, "dest-profile")
assert(api.AskProfileSetup())
applyReason = "combat"
Answer(true)
Event()
applyReason = nil
Printed("were not applied completely")
assert(api.Restore() and Untouched())

-- A key, command or slot this build does not know is left out; the rest
-- is offered and applied.
local mixed = Copy(setup)
mixed.keys["F13"], mixed.keys["2"] = "ACTIONBUTTON1", "MOVEFORWARD"
mixed.slots[999] = 5
Offer(mixed, "dest-profile")
assert(api.AskProfileSetup() and questions[1].data.text_arg1:find("includes 2 action bar key bindings", 1, true),
    "an unknown key or command dropped the whole key map or was counted")
Answer(true)
assert(questions[1].data.text_arg1:find(": 2 spells", 1, true), "an unknown slot dropped the spells or was counted")
Answer(true)
Event()
assert(profileTarget.keys["1"] == "ACTIONBUTTON2" and profileTarget.keys["F13"] == nil and profileTarget.keys["2"] == nil
    and profileTarget.slots[1] == 701 and profileTarget.slots[999] == nil, "an unknown key, command or slot was written")
table.remove(printed, 1)
assert(api.Restore() and Untouched())

-- Turning the Suite action bars off closes the question unanswered; the
-- offer waits and the next start asks again from the first question. An
-- offer whose character could not be read is for the first character asked.
Offer(setup, nil)
assert(api.AskProfileSetup() and #questions == 1 and db.actionBarOffer.guid == "dest-profile",
    "an offer without a character was not bound to the one asked")
local open = questions[1]
bar.StopSnapshots()
assert(#questions == 0 and hidden == 1 and db.actionBarOffer ~= nil, "stopping did not close the question or dropped the offer")
-- An answer that was already on its way when the bars stopped asks nothing more.
open.data.callback()
NextFrame()
assert(#questions == 0 and db.actionBarOffer ~= nil and #api.Status().pending == 0, "a stopped offer went on asking or queued")
Login(profileTarget, db)
assert(#questions == 1 and questions[1].data.text_arg1:find("key bindings", 1, true),
    "the offer was not asked again from its first question after a restart")
-- Agreeing while it cannot apply keeps the offer and says so.
Answer(true)
bar.M.active = false
Answer(true)
bar.M.active = true
assert(db.actionBarOffer ~= nil and #api.Status().pending == 0, "an answer that could not apply dropped the offer or queued")
Printed("asked again after the next reload")
-- So does agreeing while the key binding set cannot be read.
assert(api.AskProfileSetup() and #questions == 1)
Answer(true)
keysUnreadable = true
Answer(true)
keysUnreadable = nil
assert(db.actionBarOffer ~= nil and #api.Status().pending == 0, "an answer without a readable key binding set queued a transfer")
Printed("asked again after the next reload")
-- Agreeing while it cannot be queued keeps the offer and the earlier import
-- that still waits: another character's account-wide key bindings are pending.
local spellsOnly = Copy(setup)
spellsOnly.keys = {}
blocked = "combat"
Offer(spellsOnly, "dest-profile")
assert(api.AskProfileSetup() and #questions == 1 and questions[1].data.text_arg1:find("spells", 1, true))
Answer(true)
assert(db.actionBarOffer == nil and #api.Status().pending == 1, "the spells-only import was not queued")
assert(api.Queue(accountPacket, { [accountClass.PRIEST] = "Waitingpriest" }, false, true))
local waiting = Offer(setup, "dest-profile")
assert(api.AskProfileSetup())
Answer(true)
Answer(true)
local kept = api.Status().pending
assert(db.actionBarOffer == waiting and #kept == 2, "an import that could not be queued dropped the offer or the earlier import")
Printed("could not be queued")
for _, row in ipairs(kept) do assert(api.Cancel(row.id)) end
blocked = nil
db.actionBarOffer = nil
Event()
assert(Untouched() and #printed == 0, "a cancelled import still applied")

-- Spells agreed to after the specialization changed under the open question
-- no longer fit: nothing is queued (not even the keys), the offer waits and
-- the next session asks again.
local respec = Offer(setup, "dest-profile")
assert(api.AskProfileSetup())
Answer(true)
assert(#questions == 1 and questions[1].data.text_arg1:find("spells", 1, true), "the spells question did not follow")
profileTarget.identity.spec = 257
Answer(true)
Event()
assert(#api.Status().pending == 0 and Untouched() and db.actionBarOffer == respec,
    "spells agreed to before a specialization change were dropped or the keys were queued alone")
Printed("could not be applied now")
assert(#questions == 0 and #printed == 0, "the offer was asked again in the same session")
profileTarget.identity.spec = 258
Login(profileTarget, db)
assert(#questions == 1 and questions[1].data.text_arg1:find("key bindings", 1, true),
    "the waiting offer was not asked again after a reload")
Answer(true)
Answer(true)
Event()
assert(db.actionBarOffer == nil and profileTarget.slots[1] == 701 and profileTarget.independentSlots[2] == 705
    and profileTarget.keys["1"] == "ACTIONBUTTON2" and profileTarget.keys["CTRL-1"] == "ACTIONBUTTON3",
    "the offer asked again after a reload did not apply both parts")
Printed("Profile action bars applied: 2 key bindings and 2 spells changed")
assert(api.Restore() and Untouched())

-- An unanswered question comes back after a reload; a newer import replaces
-- an offer (answers to the old one count for nothing), and a newer agreed
-- import replaces a transfer that still waits.
local first = Offer(setup, "dest-profile")
Login(profileTarget, db)
assert(#questions == 1, "the reload did not ask again")
local stale = table.remove(questions, 1)
local newer = Copy(setup)
newer.slots[1] = 703
Offer(newer, "dest-profile")
stale.data.callback()
NextFrame()
assert(db.actionBarOffer ~= first and db.actionBarOffer ~= nil and #api.Status().pending == 0 and #questions == 0,
    "the answer to a replaced offer was applied or asked on")
assert(api.AskProfileSetup())
blocked = "combat"
Answer(true)
Answer(true)
Offer(setup, "dest-profile")
assert(api.AskProfileSetup())
Answer(true)
Answer(true)
assert(#api.Status().pending == 1, "a newer profile import did not replace the waiting one")
blocked = nil
Event()
assert(profileTarget.slots[1] == 701, "the newer profile import did not win")
table.remove(printed, 1)
assert(api.Restore() and Untouched())

-- Another class gets the key bindings only, another character nothing, and
-- an offer of the other WoW version's saved variables is dropped.
local otherClass = Character("dest-warrior-profile", "Keyedwarrior", "WARRIOR", 71, "warrior-target", 902, "account")
otherClass.independentSlots = {}
Login(otherClass, db)
Offer(setup, "dest-warrior-profile")
assert(api.AskProfileSetup() and #questions == 1)
assert(questions[1].data.text_arg1:find("2 action bar key bindings", 1, true), "another class was not asked about the key bindings")
Answer(true)
assert(#questions == 0, "another class was offered the spells")
Event()
assert(otherClass.slots[1] == 902 and otherClass.keys["1"] == "ACTIONBUTTON2", "another class got the spells or lost the keys")
table.remove(printed, 1)
assert(api.Restore() and otherClass.keys["1"] == "ACTIONBUTTON1")
Offer(setup, "dest-profile")
assert(api.AskProfileSetup() and #questions == 0 and db.actionBarOffer ~= nil, "another character was asked")
-- It waits for that character without scheduling work on every event,
-- also after a reload.
Login(otherClass, db)
if bar.snapshotReady then bar.snapshotReady() end
assert(#questions == 0 and next(jobs) == nil, "an offer for another character kept scheduling work")
Offer(setup, "dest-warrior-profile", suite.Client.isForever and "retail" or "forever")
assert(api.AskProfileSetup() and #questions == 0 and db.actionBarOffer == nil,
    "an offer of the other WoW version was kept or asked")
Offer({ keys = { ["1"] = "MOVEFORWARD" } }, "dest-warrior-profile")
assert(api.AskProfileSetup() and #questions == 0 and db.actionBarOffer == nil and otherClass.keys["1"] == "ACTIONBUTTON1",
    "an offer without a valid key or spell was asked or applied")
assert(#printed == 0, "an ordinary answer printed a message: " .. tostring(printed[1]))

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
    local sharedName = Character("dest-dual-other", "Dualdest Ember", "DRUID", 105, "group:2", 881)
    sharedName.identity.group = 2
    recipient.identity.name = "Dualdest River"
    Login(source, {})
    assert(api.Queue(dualPacket, { [2] = "  Dualdest   River - Test Realm  " }, true, false))
    Drain()
    assert(#api.Status().pending == 1, "offline full-name target did not queue")
    Login(sharedName)
    assert(sharedName.slots[1] == 881 and #api.Status().pending == 1, "a same-first-name alt consumed the transfer")
    Login(recipient)
    assert(recipient.slots[1] == 521 and #api.Status().pending == 0, "full-name destination did not receive the transfer")
    assert(api.Queue(dualPacket, { [1] = "Dualdest" }, true, false))
    local db = suite.RootDB
    local pending = db.actionBarTransfers.pending
    local key, legacyJobs = next(pending)
    pending[key], pending["dualdest-testrealm"] = nil, legacyJobs
    legacyJobs[1].target = "dualdest-testrealm"
    local withoutSurname = Character("dest-dual-legacy", "Dualdest", "DRUID", 105, "group:1", 891)
    withoutSurname.identity.group = 1
    Login(withoutSurname)
    assert(withoutSurname.slots[1] == 891 and #api.Status().pending == 1, "ambiguous legacy transfer auto-applied")
    assert(api.Cancel(api.Status().pending[1].id), "ambiguous legacy transfer cannot be cancelled")
    recipient.identity.name = "Dualdest"
    recipient.independentSlots[1] = 802
    Login(recipient, {})
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
