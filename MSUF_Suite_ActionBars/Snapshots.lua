local _, P = ...
local NS, S = P.NS, P.Suite
local AB = P.ActionBars
local Native = AB.SnapshotNative
local Transfers = {}
NS.ActionBarSnapshots = Transfers

local PREFIX, KIND = "MSUFAB1:", "MSUF_Suite_ActionBars"
local LIMIT, MAX_BYTES, MAX_KEYS = 64, 200000, 256
local IN_COMBAT = { inCombat = true }
local LOADOUT_EVENT, LOGOUT_EVENT = "SELECTED_LOADOUT_CHANGED", "PLAYER_LOGOUT"
local context, job, store, target, watching, dirty, busy, pendingIdentity
-- The imported profile's action bars this session already asked about
-- (RootDB.actionBarOffer, profile strings below); AskOffer is set there.
local asked, AskOffer
local OFFER_QUESTION = "actionbars:profile-import"

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
    if NS.Client.isForever then
        -- Pre-surname jobs contain only a first name. Leave them in the queue
        -- for manual cancellation and reassignment instead of guessing a target.
        return ("forever:" .. name:gsub("%s+", " ") .. "-" .. realm:gsub("[%s']", "")):lower()
    end
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
    local name, explicitRealm = text:match("^%s*([^%-]-)%s*%-%s*(.-)%s*$")
    if not name then name = text:match("^%s*(.-)%s*$") end
    local pattern = NS.Client.isForever and "^%S+%s*%S*$" or "^%S+$"
    local destination = explicitRealm or realm
    if name:match(pattern) and Text(name, 80) and Text(destination, 100) then
        return name:gsub("%s+", " "), destination
    end
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

local function OfferWaiting()
    local offer = NS.RootDB and NS.RootDB.actionBarOffer
    return type(offer) == "table" and offer ~= asked
end

local function Ready()
    if dirty or pendingIdentity or (target and store and store.pending[target]) or OfferWaiting() then Request() end
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
    AB.snapshotReady = (capture or pending or pendingIdentity or OfferWaiting()) and Ready or nil
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
            elseif row.profileImport then
                -- The player answered a question, not the Account transfer page.
                local result = data.results[1]
                if result.error then
                    S.Print(S.Text("The profile's action bars were not applied completely. Account transfer "
                        .. "(Quick actions > Action bar setups) lists the result and can restore the previous setup."))
                else
                    S.Print(S.Text("Profile action bars applied: %d key bindings and %d spells changed, %d left as they were.")
                        :format(result.keys, result.slots, result.skippedKeys + result.skippedSlots))
                end
            end
            return applied
        end
    end
end

function AB.FlushSnapshots()
    if not context or busy then return end
    local identity = Current()
    if identity then AskOffer(identity) end
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
    -- Without a store only an imported profile's action bars can wait.
    if not data and not OfferWaiting() then return end
    dirty = data and data.capture == true
    local identity = Current()
    Sync(data, identity)
    Ready()
end

function AB.StopSnapshots()
    if job then job:Cancel() end
    -- Closed unanswered: the offer waits for the next start.
    S.HideQuestion(OFFER_QUESTION)
    AB.snapshotChanged, AB.snapshotReady, AB.snapshotSetupChanged = nil, nil, nil
    context, job, store, target, asked = nil, nil, nil, nil, nil
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

------------------------------------------------------------------ profile strings
-- Profile strings carry the exporting character's action bars
-- (MSUF_Suite/Core/ProfileClients.lua): the spells of bars 1 to 10 and of
-- the native bars, the Suite bars' own spells, and the keys of their
-- commands. The keys alone go when the bars cannot be read now (combat,
-- the cursor, an open binding editor).
function Transfers.ProfileSetup()
    local identity = Current()
    if not identity then return nil end
    local snapshot = not Native.Blocked() and Native.Capture() or nil
    local keys = CleanKeys(snapshot and snapshot.keys or Native.CaptureKeys())
    if not keys then return nil end
    local setup = { keys = keys, class = identity.class, spec = identity.spec, group = identity.group,
        label = identity.setupLabel }
    if snapshot then
        setup.slots = CleanSlots(snapshot.slots, Native.AllowedSlot)
        setup.independentSlots = CleanSlots(snapshot.independentSlots, Native.AllowedIndependentSlot)
    end
    return setup
end

-- An imported profile's action bars wait for the player's answers
-- (ProfileClients.Offer keeps them in RootDB.actionBarOffer): one question
-- for the key bindings, which come along from either WoW version and apply
-- to any character, and one for the spells, which are offered only to the
-- class and specialization they came from. What the player agreed to is
-- queued as one transfer to this character's current setup: it applies at
-- once, or once combat, the cursor or an open binding editor allow, Transfer
-- results list it, a chat line reports it and Restore previous setup undoes
-- it. No (or Escape) leaves that part as it is. When the transfer cannot be
-- queued, the offer waits and the next session asks again.
local function PendingOffer(identity)
    local root = NS.RootDB
    local offer = root and root.actionBarOffer
    if type(offer) ~= "table" then return nil end
    if offer.client ~= Flavor() or type(offer.setup) ~= "table" then
        root.actionBarOffer = nil
        return nil
    end
    -- An import whose character could not be read is for the first one asked.
    if offer.guid == nil then offer.guid = identity.guid end
    if offer.guid ~= identity.guid then return nil end
    return offer
end

local function SpellsFit(setup, identity)
    return setup.class == identity.class and (setup.spec == nil or identity.spec == nil or setup.spec == identity.spec)
end

-- The entries of an offered map this addon may write: one it does not know
-- (another build or WoW version may have more keys, commands or slots) is
-- left out, the others stay.
local function Offered(source, valid)
    local out, count = {}, 0
    if type(source) ~= "table" then return out, 0 end
    for key, value in pairs(source) do
        if count < MAX_KEYS * 2 and valid(key, value) then
            out[key] = value
            count = count + 1
        end
    end
    return out, count
end
local function OfferedKey(key, command) return Native.ValidKey(key) and Native.AllowedCommand(command) end
local function OfferedSlot(slot, spell) return PositiveID(slot) and Native.AllowedSlot(slot) and PositiveID(spell) end
local function OfferedIndependent(slot, spell)
    return PositiveID(slot) and Native.AllowedIndependentSlot(slot) and PositiveID(spell)
end

-- The parts of an offer this character can take: the key bindings, and the
-- spells when they are for this class and specialization.
local function OfferParts(setup, identity)
    local keys, keyCount = Offered(setup.keys, OfferedKey)
    local slots, independent, spellCount = {}, nil, 0
    if SpellsFit(setup, identity) then
        local more
        slots, spellCount = Offered(setup.slots, OfferedSlot)
        independent, more = Offered(setup.independentSlots, OfferedIndependent)
        spellCount = spellCount + more
        if more == 0 then independent = nil end
    end
    return keys, keyCount, slots, independent, spellCount
end

local function DropProfileJobs(data, key)
    local jobs = data.pending[key]
    if not jobs then return end
    for index = #jobs, 1, -1 do
        if jobs[index].profileImport then table.remove(jobs, index) end
    end
    if #jobs == 0 then data.pending[key] = nil end
end

local function NotNow()
    S.Print(S.Text("The profile's action bars could not be applied now. You will be asked again after the next reload."))
end

-- Queues what the player agreed to (wantKeys, wantSpells) of the offer.
local function AcceptOffer(offer, wantKeys, wantSpells)
    local root, identity = NS.RootDB, Current()
    -- A newer import replaced this offer and asks itself.
    if not root or root.actionBarOffer ~= offer then return end
    if not identity or busy then return NotNow() end
    -- scope: the key binding set this character uses; unreadable, nothing applies.
    local readable, scope = Native.CaptureKeys()
    local data = readable and Store(true)
    if not data then return NotNow() end
    local keyMap, keyCount, slots, independent, spellCount = OfferParts(offer.setup, identity)
    -- The specialization changed under the open spells question: queuing the
    -- keys alone would drop the agreed spells, so the offer waits.
    if wantSpells == true and spellCount == 0 then return NotNow() end
    local spells, keys = wantSpells == true and spellCount > 0, wantKeys == true and keyCount > 0
    local record = { class = identity.class, spec = identity.spec, group = identity.group, scope = scope,
        slots = spells and slots or {}, independentSlots = spells and independent or nil, keys = keys and keyMap or {} }
    if spells or keys then
        local key = CharacterKey(identity.name, identity.realm)
        -- A newer import replaces an earlier one still waiting here; when
        -- this one cannot be queued, the earlier one stays.
        local earlier = data.pending[key] and { unpack(data.pending[key]) }
        DropProfileJobs(data, key)
        local entry = { target = key, name = identity.name, realm = identity.realm, label = S.Text("Profile import"),
            record = record, applySlots = spells, applyKeys = keys, profileImport = true }
        if not Stage(data, { entry }) then
            data.pending[key] = earlier
            S.Print(S.Text("The profile's action bars could not be queued: other account transfers for the same bars or "
                .. "key bindings are pending, or too many transfers are. Finish or cancel them under Account transfer "
                .. "(Quick actions > Action bar setups); you will be asked again after the next reload."))
            return
        end
    end
    root.actionBarOffer = nil
    Sync(data, identity)
    Ready()
end

local function DeclineOffer(offer)
    local root = NS.RootDB
    if root and root.actionBarOffer == offer then root.actionBarOffer = nil end
end

local function UndoHint()
    return " " .. S.Text("Restore previous setup under Account transfer (Quick actions > Action bar setups) undoes it.")
end

-- scope: the key binding set the character uses ("account" or "character").
local function KeysQuestion(count, scope)
    local text = S.Text("This profile includes %d action bar key bindings. Replace this character's action bar key bindings "
        .. "with them?"):format(count) .. UndoHint()
    if scope == "account" then
        text = text .. " " .. S.Text("This character uses account-wide key bindings: they change for every character that uses them.")
    end
    return text
end

local function SpellsQuestion(setup, count)
    return S.Text("This profile includes the action bar spells of %s: %d spells. Place them on this character's action bars?")
        :format(setup.label or setup.class or "?", count) .. UndoHint()
end

-- Asks the questions of an offer one after the other and then queues what
-- the player agreed to. The next step follows a frame later: Blizzard hides
-- the answered dialog after its callback returns, and would hide a question
-- shown from inside it.
local function AskNext(offer, questions, index, answers)
    local root = NS.RootDB
    if not root or root.actionBarOffer ~= offer or asked ~= offer then return end
    local question = questions[index]
    if not question then
        if answers.keys or answers.spells then return AcceptOffer(offer, answers.keys, answers.spells) end
        return DeclineOffer(offer)
    end
    local function Answer(agreed)
        answers[question.part] = agreed
        C_Timer.After(0, function() AskNext(offer, questions, index + 1, answers) end)
    end
    S.Confirm(OFFER_QUESTION, { text = "%s", text_arg1 = question.text,
        callback = function() Answer(true) end, cancelCallback = function() Answer(false) end })
end

-- Asks about the waiting offer once per session (AB.FlushSnapshots runs it
-- once this character is readable).
function AskOffer(identity)
    local waiting = NS.RootDB and NS.RootDB.actionBarOffer
    if waiting == nil or asked == waiting then return end
    -- Once per offer and session, also an offer for another character: it
    -- waits for that one without polling here.
    asked = waiting
    local offer = PendingOffer(identity)
    if not offer then return end
    local _, keyCount, _, _, spellCount = OfferParts(offer.setup, identity)
    if spellCount == 0 and keyCount == 0 then
        NS.RootDB.actionBarOffer = nil
        return
    end
    local questions = {}
    if keyCount > 0 then
        local readable, scope = Native.CaptureKeys()
        questions[#questions + 1] = { part = "keys", text = KeysQuestion(keyCount, readable and scope) }
    end
    if spellCount > 0 then questions[#questions + 1] = { part = "spells", text = SpellsQuestion(offer.setup, spellCount) } end
    AskNext(offer, questions, 1, {})
end

-- After an import (ProfileClients.Offer). False while the Suite action bars
-- are off, so the import says how to apply them; true otherwise, also when
-- the question waits for this character to be readable.
function Transfers.AskProfileSetup()
    if not AB.M.active then return false end
    asked = nil
    local identity = Current()
    if identity then
        AskOffer(identity)
    elseif context then
        Sync(Store(), nil)
        Ready()
    end
    return true
end
