local _, P = ...
local NS = P.NS
local AB = P.ActionBars
local Native = AB.SnapshotNative
local Transfers = {}
NS.ActionBarSnapshots = Transfers

local PREFIX, KIND = "MSUFAB1:", "MSUF_Suite_ActionBars"
local LIMIT, MAX_BYTES, MAX_KEYS = 64, 200000, 256
local IN_COMBAT = { inCombat = true }
local LOADOUT_EVENT, LOGOUT_EVENT = "SELECTED_LOADOUT_CHANGED", "PLAYER_LOGOUT"
local context, job, store, target, watching, dirty, busy, pendingIdentity

local function Store(create)
    local root = NS.RootDB
    if not root then return end
    local data = root.actionBarTransfers
    if not data and create then
        data = { saved = {}, pending = {}, results = {}, backups = {}, serial = 0 }
        root.actionBarTransfers = data
    end
    return data
end

local function Text(value, limit)
    return type(value) == "string" and #value > 0 and #value <= limit and not value:find("%c")
end

local function PositiveID(value)
    return type(value) == "number" and value > 0 and value < 2147483648 and value == math.floor(value)
end

local function Count(entries)
    local count = 0
    for _ in pairs(entries) do count = count + 1 end
    return count
end

local function Flavor()
    return NS.Client.isForever and "forever" or "retail"
end

local function CharacterKey(name, realm)
    return (name .. "-" .. realm):gsub("[%s']", ""):lower()
end

local function SetupKey(identity)
    return identity.guid .. "/" .. identity.setup
end

local function Current()
    if AB.M.active and NS.loginKind then return Native.Identity() end
end

local function ParseTarget(text, realm)
    if not Text(text, 160) then return end
    local name, explicitRealm = text:match("^%s*([^%s%-]+)%s*%-%s*(.-)%s*$")
    if not name then name = text:match("^%s*([^%s%-]+)%s*$") end
    local destination = explicitRealm or realm
    if name and Text(destination, 100) then return name, destination end
end

local function SameKeys(left, right)
    for key, command in pairs(left) do
        if right[key] ~= command then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function CleanSlots(source, allowed)
    if type(source) ~= "table" then return end
    local slots = {}
    for slot, spell in pairs(source) do
        if not PositiveID(slot) or not allowed(slot) or not PositiveID(spell) then return end
        slots[slot] = spell
    end
    return slots
end

local function CleanKeys(source)
    if type(source) ~= "table" then return end
    local keys, count = {}, 0
    for key, command in pairs(source) do
        count = count + 1
        if count > MAX_KEYS or not Native.ValidKey(key) or not Native.AllowedCommand(command) then return end
        keys[key] = command
    end
    return keys
end

local function CleanRecord(row)
    if type(row) ~= "table" or not Text(row.name, 80) or not Text(row.realm, 100)
        or not Text(row.class, 20) or not row.class:match("^[A-Z]+$") or not Text(row.setupLabel, 120)
        or (row.spec ~= nil and not PositiveID(row.spec)) or (row.loadout ~= nil and not Text(row.loadout, 120)) then return end
    if row.group ~= nil and not Native.AllowedGroup(row.group) then return end
    if row.scope ~= "account" and row.scope ~= "character" then return end
    local slots, keys = CleanSlots(row.slots, Native.AllowedSlot), CleanKeys(row.keys)
    if not slots or not keys then return end
    local independentSlots
    if row.independentSlots ~= nil then
        independentSlots = CleanSlots(row.independentSlots, Native.AllowedIndependentSlot)
        if not independentSlots then return end
    end
    return {
        name = row.name, realm = row.realm, class = row.class, spec = row.spec, group = row.group,
        setupLabel = row.setupLabel, loadout = row.loadout, scope = row.scope, slots = slots, keys = keys,
        independentSlots = independentSlots,
    }
end

local function CleanPacket(packet)
    if type(packet) ~= "table" or packet.kind ~= KIND or packet.version ~= 1 or type(packet.records) ~= "table" then
        return nil, "invalid"
    end
    if packet.flavor ~= Flavor() then return nil, "client" end
    local rows, shared = {}, nil
    for index, row in pairs(packet.records) do
        if not PositiveID(index) or index > LIMIT then return nil, "invalid" end
        local clean = CleanRecord(row)
        if not clean then return nil, "invalid" end
        if clean.scope == "account" then
            if shared and not SameKeys(shared, clean.keys) then return nil, "invalid" end
            shared = clean.keys
        end
        rows[index] = clean
    end
    if #rows == 0 or Count(rows) ~= #rows then return nil, "invalid" end
    return { kind = KIND, version = 1, flavor = packet.flavor, records = rows }
end

local function WriteCapture(data, identity)
    local id = SetupKey(identity)
    if not data.saved[id] and Count(data.saved) >= LIMIT then return nil, "limit" end
    local snapshot, reason = Native.Capture()
    if not snapshot then return nil, reason end
    local row = {
        name = identity.name, realm = identity.realm, class = identity.class, spec = identity.spec, group = identity.group,
        setupLabel = identity.setupLabel, loadout = identity.group == nil and identity.loadout or nil,
        scope = snapshot.scope, slots = snapshot.slots, keys = snapshot.keys, independentSlots = snapshot.independentSlots,
    }
    row = CleanRecord(row)
    if not row then return nil, "unavailable" end
    if row.scope == "account" then
        data.accountKeys, row.keys = row.keys, nil
    end
    data.saved[id] = row
    return true
end

local function Rows(data)
    local rows = {}
    for id, row in pairs(data.saved) do
        local keys = row.keys or data.accountKeys or {}
        rows[#rows + 1] = {
            id = id, name = row.name, realm = row.realm, class = row.class, spec = row.spec, group = row.group,
            setupLabel = row.setupLabel, loadout = row.loadout, scope = row.scope, slots = row.slots, keys = keys,
            independentSlots = row.independentSlots,
            slotCount = Count(row.slots) + (row.independentSlots and Count(row.independentSlots) or 0), keyCount = Count(keys),
        }
    end
    table.sort(rows, function(a, b) return a.id < b.id end)
    return rows
end

function Transfers.Decode(value)
    if type(value) ~= "string" or #value > MAX_BYTES or value:sub(1, #PREFIX) ~= PREFIX then
        return nil, "invalid"
    end
    local decode = _G.MSUF_TryDecodeCompactString
    if not decode then return nil, "codec" end
    return CleanPacket(decode("MSUF3:" .. value:sub(#PREFIX + 1)))
end

function Transfers.Capture()
    local identity = Current()
    if not identity then return nil, "unavailable" end
    local data = Store(true)
    if not data then return nil, "unavailable" end
    local ok, reason = WriteCapture(data, identity)
    if ok then dirty = false end
    return ok, reason
end

function Transfers.Export()
    local encode = _G.MSUF_EncodeCompactTable
    if not encode then return nil, "codec" end
    local ok, reason = Transfers.Capture()
    local data = Store()
    if not ok then return nil, reason or "unavailable" end
    local records = {}
    for _, row in ipairs(Rows(data)) do records[#records + 1] = CleanRecord(row) end
    local encoded = encode({ kind = KIND, version = 1, flavor = Flavor(), records = records }, "MSUF3")
    if type(encoded) ~= "string" or encoded:sub(1, 6) ~= "MSUF3:" then return nil, "codec" end
    if #encoded + #PREFIX - 6 > MAX_BYTES then return nil, "limit" end
    return PREFIX .. encoded:sub(7)
end

local function Match(row, identity)
    return row.record.class == identity.class and (row.record.spec == nil or row.record.spec == identity.spec)
        and (row.record.group == nil or row.record.group == identity.group)
        and (row.loadout == nil or row.loadout == identity.loadout)
end

local function VisibleRow(row)
    return { id = row.id, name = row.name, realm = row.realm, label = row.label, waiting = row.waiting }
end

local function ReadStatus(data, identity)
    local result = { current = identity, saved = {}, pending = {}, results = {}, capture = false, canRestore = false }
    if not data then return result end
    result.capture = data.capture == true
    for _, row in ipairs(Rows(data)) do
        row.slots, row.keys, row.independentSlots = nil, nil, nil
        result.saved[#result.saved + 1] = row
    end
    for _, jobs in pairs(data.pending) do
        for _, row in ipairs(jobs) do result.pending[#result.pending + 1] = VisibleRow(row) end
    end
    table.sort(result.pending, function(a, b) return a.id < b.id end)
    for i = 1, #data.results do
        local row = data.results[i]
        local view = VisibleRow(row)
        view.slots, view.keys, view.skippedSlots, view.skippedKeys = row.slots, row.keys, row.skippedSlots, row.skippedKeys
        view.error = row.error
        result.results[i] = view
    end
    result.canRestore = identity ~= nil and data.backups[SetupKey(identity)] ~= nil
    return result
end

function Transfers.Status()
    return ReadStatus(Store(), Current())
end

local function Request()
    if not context or busy then return end
    if not job then job = context:Coalesce(0, AB.FlushSnapshots) end
    job:Request()
end

local function CaptureChanged()
    dirty = true
    Request()
end

local function Ready()
    if dirty or pendingIdentity or (target and store.pending[target]) then Request() end
end

function Transfers.Retry()
    if context and store then Ready() end
end

local function LoadoutChanged()
    if store.capture then dirty = true end
    Ready()
end

local function FlushOnLogout()
    if dirty and not busy then Transfers.Capture() end
end

local function Sync(data, identity)
    store = data
    if not context then return end
    if identity then target = CharacterKey(identity.name, identity.realm) end
    local capture = data and data.capture == true
    local pending = data and target and data.pending[target]
    pendingIdentity = data and target == nil and next(data.pending) ~= nil
    AB.snapshotChanged = capture and CaptureChanged or nil
    AB.snapshotReady = (capture or pending or pendingIdentity) and Ready or nil
    local shouldWatch = capture or pending ~= nil or pendingIdentity == true
    AB.snapshotSetupChanged = shouldWatch and NS.Client.isForever and LoadoutChanged or nil
    if watching ~= shouldWatch then
        watching = shouldWatch
        if shouldWatch then
            context:Event(LOADOUT_EVENT, LoadoutChanged, IN_COMBAT)
            context:Event(LOGOUT_EVENT, FlushOnLogout, IN_COMBAT)
        else
            context:RemoveEvent(LOADOUT_EVENT)
            context:RemoveEvent(LOGOUT_EVENT)
        end
    end
end

function Transfers.SetCapture(enabled)
    if not Current() then return nil, "unavailable" end
    local data = Store(true)
    if not data then return nil, "unavailable" end
    data.capture = enabled == true
    dirty = data.capture
    Sync(data)
    if dirty then Request() end
    return true
end

local function RecordResult(data, row, report, reason)
    local view = VisibleRow(row)
    view.slots, view.keys = report and report.slots or 0, report and report.keys or 0
    view.skippedSlots, view.skippedKeys = report and report.skippedSlots or 0, report and report.skippedKeys or 0
    view.error = reason or (report and report.reason)
    table.insert(data.results, 1, view)
    if #data.results > LIMIT then table.remove(data.results) end
end

local function Execute(data, identity, row)
    local plan, reason = NS.Dispatch(Native.Plan, row.record, row.applySlots, row.applyKeys)
    if not plan then return false, reason end
    local id = SetupKey(identity)
    local prior = data.backups[id]
    if plan.backup then data.backups[id] = plan.backup end
    -- Consume the confirmed import before touching native state. If a native
    -- write raises, the preflight backup can still reverse verified writes.
    local report, problem = NS.Dispatch(Native.Apply, plan)
    if not report and (problem == "combat" or problem == "cursor" or problem == "stale" or problem == "unavailable") then
        data.backups[id] = prior
        return false, problem
    end
    if report then data.backups[id] = report.backup or prior end
    RecordResult(data, row, report, problem or (not report and "interrupted" or nil))
    return true
end

local function ApplyMatching(data, identity)
    local key = CharacterKey(identity.name, identity.realm)
    local jobs = data.pending[key]
    if not jobs or Native.Blocked() then return end
    for i, row in ipairs(jobs) do
        if Match(row, identity) then
            if row.applyKeys and Native.BindingScope() ~= row.record.scope then
                row.waiting = row.record.scope
                return
            end
            row.waiting = nil
            table.remove(jobs, i)
            if #jobs == 0 then data.pending[key] = nil end
            local applied = Execute(data, identity, row)
            if not applied then
                data.pending[key] = jobs
                table.insert(jobs, i, row)
            end
            return applied
        end
    end
end

function AB.FlushSnapshots()
    if not context or busy then return end
    local identity = Current()
    local data = Store()
    if not identity or not data then return end
    busy = true
    local applied = ApplyMatching(data, identity)
    if data.capture and (dirty or applied) then
        if NS.Dispatch(WriteCapture, data, identity) then dirty = false end
    end
    busy = false
    Sync(data, identity)
end

function AB.StartSnapshots(owner)
    context = owner
    local data = Store()
    if not data then return end
    dirty = data.capture == true
    local identity = Current()
    Sync(data, identity)
    Ready()
end

function AB.StopSnapshots()
    if job then job:Cancel() end
    AB.snapshotChanged, AB.snapshotReady, AB.snapshotSetupChanged = nil, nil, nil
    context, job, store, target = nil, nil, nil, nil
    watching, dirty, busy, pendingIdentity = nil, nil, nil, nil
end

-- A named source loadout maps to the same name by default. The receiver
-- can supply the exact destination name after | when it differs.
local function Destination(text, realm, sourceLoadout)
    if not Text(text, 285) then return end
    local address, loadout = text:match("^([^|]+)|%s*(.-)%s*$")
    if not address then address, loadout = text, sourceLoadout end
    if loadout ~= nil and not Text(loadout, 120) then return end
    local name, destinationRealm = ParseTarget(address, realm)
    return name, destinationRealm, loadout
end

local function Overlaps(first, second)
    return first.target == second.target
        and (first.record.spec == second.record.spec or first.record.spec == nil or second.record.spec == nil)
        and (first.record.group == second.record.group or first.record.group == nil or second.record.group == nil)
        and (first.loadout == second.loadout or first.loadout == nil or second.loadout == nil)
end

local function BuildJobs(packet, assignments, identity, applySlots, applyKeys)
    local jobs, shared = {}, nil
    local current = CharacterKey(identity.name, identity.realm)
    for index, row in ipairs(packet.records) do
        if assignments[index] ~= nil then
            local name, realm, loadout = Destination(assignments[index], identity.realm, row.loadout)
            if not name then return nil, "target" end
            local key = CharacterKey(name, realm)
            if key == current and identity.class ~= row.class then return nil, "class" end
            local entry = {
                target = key, name = name, realm = realm, label = row.setupLabel, record = row, loadout = loadout,
                applySlots = applySlots, applyKeys = applyKeys and row.scope == "character",
            }
            for _, queued in ipairs(jobs) do
                if Overlaps(queued, entry) then return nil, "duplicate" end
            end
            jobs[#jobs + 1] = entry
            if applyKeys and row.scope == "account" and (not shared
                or (key == current and Match(entry, identity) and Native.BindingScope() == "account")) then
                shared = entry
            end
        end
    end
    if shared then shared.applyKeys = true end
    for index = #jobs, 1, -1 do
        if not jobs[index].applySlots and not jobs[index].applyKeys then table.remove(jobs, index) end
    end
    return jobs
end

local function Stage(data, jobs)
    local total = #jobs
    local shared = false
    for _, row in ipairs(jobs) do
        if row.applyKeys and row.record.scope == "account" then shared = true end
    end
    for _, existing in pairs(data.pending) do
        total = total + #existing
        if shared then
            for _, pending in ipairs(existing) do
                if pending.applyKeys and pending.record.scope == "account" then return nil, "pending" end
            end
        end
    end
    if total > LIMIT then return nil, "limit" end
    for _, row in ipairs(jobs) do
        local existing = data.pending[row.target]
        if existing then
            for _, pending in ipairs(existing) do
                if Overlaps(pending, row) then return nil, "pending" end
            end
        end
    end
    for _, row in ipairs(jobs) do
        data.serial = data.serial + 1
        row.id = data.serial
        local existing = data.pending[row.target]
        if not existing then
            existing = {}
            data.pending[row.target] = existing
        end
        existing[#existing + 1] = row
    end
    return true
end

function Transfers.Queue(packet, assignments, applySlots, applyKeys)
    if busy then return nil, "busy" end
    local clean, reason = CleanPacket(packet)
    if not clean then return nil, reason end
    local identity = Current()
    if not identity then return nil, "unavailable" end
    if type(assignments) ~= "table" or not (applySlots == true or applyKeys == true) then return nil, "selection" end
    local jobs, problem = BuildJobs(clean, assignments, identity, applySlots == true, applyKeys == true)
    if not jobs then return nil, problem end
    if #jobs == 0 then return nil, "target" end
    local data = Store(true)
    if not data then return nil, "unavailable" end
    local staged, stageReason = Stage(data, jobs)
    if not staged then return nil, stageReason end
    Sync(data, identity)
    Ready()
    return true
end

function Transfers.Cancel(id)
    local data = Store()
    if not data or busy then return nil, "unavailable" end
    for key, jobs in pairs(data.pending) do
        for i, row in ipairs(jobs) do
            if row.id == id then
                table.remove(jobs, i)
                if #jobs == 0 then data.pending[key] = nil end
                Sync(data)
                return true
            end
        end
    end
    return nil, "empty"
end

function Transfers.Restore()
    if busy then return nil, "busy" end
    local data, identity = Store(), Current()
    if not data or not identity then return nil, "unavailable" end
    local id = SetupKey(identity)
    local backup = data.backups[id]
    if not backup then return nil, "empty" end
    busy = true
    local report, reason = NS.Dispatch(Native.Restore, backup)
    busy = false
    if not report then return nil, reason or "interrupted" end
    data.backups[id] = report.backup
    if data.capture then CaptureChanged() end
    return true, report
end

-- Profile strings (MSUF_Suite/Core/ProfileIO.lua) carry the key map of the
-- action bar commands when the player chose so (actionbars.profileKeybinds).
-- An import writes it into the binding set this character uses now, as a
-- confirmed keys-only transfer: it is listed under Transfer results, and
-- Restore previous setup undoes it.
function Transfers.ProfileKeys()
    local keys, reason = Native.CaptureKeys()
    if not keys then return nil, reason end
    return CleanKeys(keys)
end

function Transfers.ImportProfileKeys(keys)
    if busy then return nil, "busy" end
    local identity = Current()
    local data = identity and Store(true)
    if not data then return nil, "unavailable" end
    keys = CleanKeys(keys)
    if not keys or not next(keys) then return nil, "invalid" end
    local blocked = Native.Blocked()
    if blocked then return nil, blocked end
    local scope = Native.BindingScope()
    if not scope then return nil, "unavailable" end
    local row = { name = identity.name, realm = identity.realm, label = identity.setupLabel, applyKeys = true,
        record = { scope = scope, slots = {}, keys = keys } }
    busy = true
    local applied, reason = NS.Dispatch(Execute, data, identity, row)
    busy = false
    return applied == true, reason
end
