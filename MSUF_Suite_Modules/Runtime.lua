local _, Private = ...
local NS = assert(_G.MSUFSuite, "MSUF_Suite is required")
local S = NS.Suite
Private.NS, Private.Suite = NS, S
S.editMode = _G.MSUF_UnitEditModeActive == true

-- Module lifecycle helpers. Every change a module makes to a native frame or
-- a CVar goes through its context, so Release can undo exactly that change
-- and leave later changes by Blizzard or other addons alone.
local Context = {}
Context.__index = Context

-- Secret-safe readers, the translation lookup and error isolation are
-- defined once in MSUF_Suite/Core/Platform.lua, which is always loaded.
S.Public, S.Number, S.Finite = NS.Public, NS.Number, NS.Finite
S.PublicText, S.ReadText, S.Text = NS.PublicText, NS.ReadText, NS.Text
S.Dispatch = NS.Dispatch
local Public, Dispatch = S.Public, S.Dispatch

local function Accessible(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

------------------------------------------------------------------ isolated work units
-- A module's deferred work (its flush) as units, each marked in a table
-- (set[key] = value). The caller clears a mark before its unit runs, because
-- the unit may mark its own work again, then calls run(set, key, value, fn,
-- a, b): fn(a, b) runs isolated (Dispatch), so a raising unit is reported and
-- the caller goes on with the next one. settle(), after the pass, gives each
-- raising unit its mark back once (a restore inside a pairs() walk would be
-- undefined) and returns true when a unit raised; a unit that raises again on
-- that retry is dropped. reset() forgets both. Nothing allocates unless a
-- unit raises.
function S.NewUnitRunner()
    local Finish = NS.Finish
    local failSets, failKeys, failValues, failCount = {}, {}, {}, 0
    -- set -> key -> true: units whose mark came back after they raised.
    local retried, retrying = {}, 0

    local function run(set, key, value, fn, a, b)
        if Dispatch(Finish, fn, a, b) then
            if retrying > 0 then
                local seen = retried[set]
                if seen and seen[key] then
                    seen[key] = nil
                    retrying = retrying - 1
                end
            end
            return
        end
        failCount = failCount + 1
        failSets[failCount], failKeys[failCount], failValues[failCount] = set, key, value
    end

    local function remark(set, key, value)
        local seen = retried[set]
        if seen and seen[key] then
            seen[key] = nil
            retrying = retrying - 1
            return
        end
        if not seen then
            seen = {}
            retried[set] = seen
        end
        seen[key] = true
        retrying = retrying + 1
        if not set[key] then set[key] = value end
    end

    local function settle()
        if failCount == 0 then return false end
        for i = 1, failCount do
            remark(failSets[i], failKeys[i], failValues[i])
            failSets[i], failKeys[i], failValues[i] = nil, nil, nil
        end
        failCount = 0
        return true
    end

    local function reset()
        for i = 1, failCount do failSets[i], failKeys[i], failValues[i] = nil, nil, nil end
        failCount, retrying = 0, 0
        for set in pairs(retried) do retried[set] = nil end
    end

    return run, settle, reset
end

------------------------------------------------------------------ CVar ownership
-- Retail and Forever both have C_CVar; its functions are looked up per call.
local CVars = C_CVar

-- Applied CVars are recorded per character in MSUFSuiteDB.suiteRecovery, so a
-- crash or a disabled module addon can still hand them back later.
local recoveryKey
local function Recovery(create)
    local root = NS.RootDB
    if not root then return nil end
    if not recoveryKey then
        local name, realm = UnitName("player"), GetRealmName()
        if not Public(name) or not Public(realm) then return nil end
        recoveryKey = tostring(realm) .. "/" .. tostring(name)
    end
    if type(root.suiteRecovery) ~= "table" then
        if not create then return nil end
        root.suiteRecovery = {}
    end
    local recovery = root.suiteRecovery[recoveryKey]
    if type(recovery) ~= "table" then
        if not create then return nil end
        recovery = {}
        root.suiteRecovery[recoveryKey] = recovery
    end
    return recovery
end

-- A module owns the CVars its catalog entry declares (always loaded, so a
-- record can be restored while the module addon is disabled) plus the ones
-- its runtime lists in M.cvars.
local function OwnsCVar(id, key)
    local spec = S.catalog[id]
    if spec and spec.cvars and spec.cvars[key] then return true end
    local instance = S.instances[id]
    return instance ~= nil and instance.cvars ~= nil and instance.cvars[key] == true
end

local function ValidRecord(entry)
    return type(entry) == "table" and type(entry.before) == "string" and #entry.before < 64
        and type(entry.applied) == "string"
end

-- Hands saved CVars back to their previous value. A record is dropped only
-- once it is resolved: restored, overridden by a later change, or malformed.
-- Unknown owners and unreadable values keep their record for a later attempt.
function S.RestoreSaved(id, onlyKey)
    local recovery = Recovery(false)
    local saved = recovery and recovery[id]
    if saved == nil then return end
    if type(saved) ~= "table" then
        recovery[id] = nil
    else
        for key, entry in pairs(saved) do
            if not onlyKey or key == onlyKey then
                if not ValidRecord(entry) then
                    saved[key] = nil
                elseif OwnsCVar(id, key) then
                    local current = CVars.GetCVar(key)
                    if Public(current) and type(current) == "string" then
                        if current == entry.applied then CVars.SetCVar(key, entry.before) end
                        saved[key] = nil
                    end
                end
            end
        end
        if not next(saved) then recovery[id] = nil end
    end
    if not next(recovery) then NS.RootDB.suiteRecovery[recoveryKey] = nil end
end

function S.RestoreCVar(id, key)
    S.RestoreSaved(id, key)
end

-- Sets a CVar the module declared. The first value seen is kept as the one
-- to restore; later calls only update the value this module applied.
function Context:CVar(key, value)
    if not OwnsCVar(self.id, key) then return false end
    local current = CVars.GetCVar(key)
    if not Public(current) or current == nil then return false end
    local recovery = Recovery(true)
    if not recovery then return false end
    value = tostring(value)
    local owned = recovery[self.id]
    if type(owned) ~= "table" then
        owned = {}
        recovery[self.id] = owned
    end
    local record = owned[key]
    if type(record) ~= "table" then
        record = { before = current }
        owned[key] = record
    end
    record.applied = value
    if current ~= value then CVars.SetCVar(key, value) end
    local applied = CVars.GetCVar(key)
    if Public(applied) and type(applied) == "string" then record.applied = applied end
    return true
end

------------------------------------------------------------------ contexts
function S.NewContext(id)
    return setmetatable({ id = id, properties = {}, points = {}, callbacks = {}, fields = {} }, Context)
end

-- Plain Lua fields on native frames (for example a mixin flag).
function Context:Field(frame, key, value, refresh)
    if NS.IsCombatLocked() then
        S.Queue(self.id)
        return false
    end
    if not Accessible(frame) or not Public(frame[key]) or value == nil then return false end
    local record = self.fields[frame]
    if not record then
        record = { values = {}, refresh = refresh }
        self.fields[frame] = record
    end
    local saved = record.values[key]
    if not saved then
        saved = { before = frame[key] }
        record.values[key] = saved
    end
    local changed = frame[key] ~= value
    if changed then frame[key] = value end
    saved.applied = value
    return changed
end

-- Plain field writes cannot raise, so the record is finished once the values
-- are back; the module's refresh runs after that and has nothing to redo.
function Context:RestoreFields(frame)
    local record = self.fields[frame]
    if not record then return end
    local changed = false
    if Accessible(frame) then
        for key, saved in pairs(record.values) do
            if Public(frame[key]) and frame[key] == saved.applied then
                frame[key] = saved.before
                changed = true
            end
        end
    end
    self.fields[frame] = nil
    if changed and record.refresh then record.refresh(frame) end
end

function Context:Skin()
    return NS.Skin.Acquire(self.id)
end

-- MapkoSkin is another addon: every call into it runs through Dispatch, so
-- its error is reported and never stops the module that owns the frame.
local function AcquireSkin(self)
    return Dispatch(NS.Skin.Acquire, self.id)
end

local function PaintOwnedSkin(skin, method, target, options)
    skin[method](skin, target, options)
end

-- Remembers a MapkoSkin call so it is repeated after the skin is re-enabled.
function Context:OwnSkin(method, target, options)
    self.ownedSkins = self.ownedSkins or {}
    self.ownedSkins[target] = { method = method, options = options }
    local skin = AcquireSkin(self)
    if skin then Dispatch(PaintOwnedSkin, skin, method, target, options) end
end

function Context:RefreshOwnedSkins()
    if not self.ownedSkins then return end
    local skin = AcquireSkin(self)
    if not skin then return end
    for target, entry in pairs(self.ownedSkins) do
        Dispatch(PaintOwnedSkin, skin, entry.method, target, entry.options)
    end
end

-- Single-value getter/setter pairs such as GetScale/SetScale.
function Context:Property(frame, getter, setter, value)
    if NS.IsCombatLocked() then
        S.Queue(self.id)
        return
    end
    if not Accessible(frame) or type(frame[getter]) ~= "function" or type(frame[setter]) ~= "function" then
        return
    end
    local current = frame[getter](frame)
    if not Public(current) then return end
    local properties = self.properties[frame]
    if not properties then
        properties = {}
        self.properties[frame] = properties
    end
    local record = properties[setter]
    if not record then
        record = { getter = getter, before = current }
        properties[setter] = record
    end
    if current ~= value then frame[setter](frame, value) end
    local applied = frame[getter](frame)
    record.applied = Public(applied) and applied or value
end

function Context:Scale(frame, value)
    self:Property(frame, "GetScale", "SetScale", value)
end

function Context:Alpha(frame, value)
    self:Property(frame, "GetAlpha", "SetAlpha", value)
end

-- Leaves a later foreign change alone: only our applied value is undone.
function Context:RestoreProperty(frame, setter)
    local properties = self.properties[frame]
    local record = properties and properties[setter]
    if not record then return end
    if Accessible(frame) then
        local current = frame[record.getter](frame)
        if Public(current) and current == record.applied then frame[setter](frame, record.before) end
    end
    properties[setter] = nil
    if not next(properties) then self.properties[frame] = nil end
end

local function Pack(...)
    return { n = select("#", ...), ... }
end

local function SameTuple(a, b)
    if a.n ~= b.n then return false end
    for i = 1, a.n do
        if not Public(a[i]) or not Public(b[i]) or a[i] ~= b[i] then return false end
    end
    return true
end

-- Font triples and texture coordinates are cold configuration, never sampled
-- from action/cooldown events. Preserve foreign changes when releasing ownership.
function Context:Tuple(frame, getter, setter, ...)
    if NS.IsCombatLocked() then
        S.Queue(self.id)
        return
    end
    if not Accessible(frame) or type(frame[getter]) ~= "function" or type(frame[setter]) ~= "function" then
        return
    end
    local before, wanted = Pack(frame[getter](frame)), Pack(...)
    for i = 1, before.n do
        if not Public(before[i]) then return end
    end
    self.tuples = self.tuples or {}
    local values = self.tuples[frame]
    if not values then
        values = {}
        self.tuples[frame] = values
    end
    local record = values[setter]
    if not record then
        record = { getter = getter, before = before }
        values[setter] = record
    end
    if not SameTuple(before, wanted) then frame[setter](frame, unpack(wanted, 1, wanted.n)) end
    record.applied = Pack(frame[getter](frame))
end

function Context:RestoreTuple(frame, setter)
    local values = self.tuples and self.tuples[frame]
    local record = values and values[setter]
    if not record then return end
    if Accessible(frame) and SameTuple(Pack(frame[record.getter](frame)), record.applied) then
        frame[setter](frame, unpack(record.before, 1, record.before.n))
    end
    values[setter] = nil
    if not next(values) then self.tuples[frame] = nil end
end

-- Adopts a foreign change of one owned tuple value as the value to restore:
-- when value `index` of the tuple differs from the one this context applied
-- (for example Blizzard's chat menu resizing a font we set), `current`
-- replaces the saved original. Returns true and the saved original values,
-- or false while this context does not own the tuple.
function Context:UpdateTupleBefore(frame, setter, index, current)
    local values = self.tuples and self.tuples[frame]
    local record = values and values[setter]
    if not record then return false end
    local before, applied = record.before, record.applied
    if applied and Public(current) and Public(applied[index]) and current ~= applied[index] then
        before[index] = current
    end
    return true, unpack(before, 1, before.n)
end

-- Hides a native control without Hide(), so Blizzard's own show logic keeps
-- working and the control returns exactly as it was.
function Context:HideControl(frame, hidden)
    if not frame then return end
    if hidden then
        self:Alpha(frame, 0)
        self:Property(frame, "IsMouseEnabled", "EnableMouse", false)
    else
        self:RestoreProperty(frame, "SetAlpha")
        self:RestoreProperty(frame, "EnableMouse")
    end
end

function Context:Anchor(frame, point, relative, relativePoint, x, y)
    if NS.IsCombatLocked() then
        S.Queue(self.id)
        return
    end
    if not Accessible(frame) or not frame.GetNumPoints then return end
    local record = self.points[frame]
    if not record then
        record = { before = {} }
        for i = 1, frame:GetNumPoints() do record.before[i] = { frame:GetPoint(i) } end
        self.points[frame] = record
    end
    frame:ClearAllPoints()
    frame:SetPoint(point, relative, relativePoint, x, y)
    local actualPoint, actualRelative, actualRelativePoint, actualX, actualY = frame:GetPoint(1)
    if Public(actualPoint) and Public(actualX) and Public(actualY) then
        record.point, record.x, record.y = actualPoint, actualX, actualY
        record.relative, record.relativePoint = actualRelative, actualRelativePoint
    end
end

function Context:Position(frame, point, x, y)
    self:Anchor(frame, point, UIParent, point, x, y)
end

function Context:RestorePoints(frame)
    local record = self.points[frame]
    if not record or not Accessible(frame) then return end
    local point, relative, relativePoint, x, y = frame:GetPoint(1)
    if Public(point) and Public(relative) and Public(relativePoint) and Public(x) and Public(y)
        and frame:GetNumPoints() == 1 and point == record.point and relative == record.relative
        and relativePoint == record.relativePoint and x == record.x and y == record.y then
        frame:ClearAllPoints()
        for i = 1, #record.before do frame:SetPoint(unpack(record.before[i])) end
    end
    self.points[frame] = nil
end

------------------------------------------------------------------ events
-- OnEvent of every context frame: hands the event to the module callback.
local function RouteEvent(frame, event, ...)
    local ctx = frame.context
    local module = S.instances[ctx.id]
    if not module.active then return end
    if event == "ADDON_LOADED" and module.addons and not module.addons[(...)] then return end
    -- Geometry modules re-apply after combat instead of moving frames in it.
    if module.geometry and not (ctx.combatEvents and ctx.combatEvents[event]) and NS.IsCombatLocked() then
        S.Queue(ctx.id)
        return
    end
    local callback = ctx.callbacks[event]
    if callback then callback(module, event, ...) end
end

-- callback(module, event, ...). allowCombat lets geometry modules receive the
-- event in combat; unit (for example "player") limits a unit event to that unit.
function Context:Event(event, callback, allowCombat, unit)
    if not NS.Client.SupportsEvent(event) then return end
    local alreadyRegistered = self.callbacks[event] ~= nil
    if not self.frame then
        self.frame = S.CreateFrame("Frame")
        self.frame.context = self
        self.frame:SetScript("OnEvent", RouteEvent)
    end
    self.combatEvents = self.combatEvents or {}
    self.combatEvents[event] = allowCombat or nil
    self.callbacks[event] = callback
    if alreadyRegistered then return end
    if unit and self.frame.RegisterUnitEvent then
        self.frame:RegisterUnitEvent(event, unit)
    else
        self.frame:RegisterEvent(event)
    end
end

function Context:RemoveEvent(event)
    if self.callbacks[event] == nil then return end
    self.callbacks[event] = nil
    if self.combatEvents then self.combatEvents[event] = nil end
    if self.frame then self.frame:UnregisterEvent(event) end
end

-- EventRegistry callbacks. callback(module).
function Context:Callback(event, callback)
    self.registryCallbacks = self.registryCallbacks or {}
    if self.registryCallbacks[event] then return true end
    local id = self.id
    local function Invoke()
        local module = S.instances[id]
        if not module.active then return end
        if module.geometry and NS.IsCombatLocked() then
            S.Queue(id)
            return
        end
        callback(module)
    end
    self.registryCallbacks[event] = Invoke
    EventRegistry:RegisterCallback(event, Invoke, self)
    return true
end

------------------------------------------------------------------ release
local function ReleaseEvents(self)
    if self.frame then self.frame:UnregisterAllEvents() end
    for key in pairs(self.callbacks) do self.callbacks[key] = nil end
    if self.combatEvents then
        for key in pairs(self.combatEvents) do self.combatEvents[key] = nil end
    end
    if self.registryCallbacks then
        for event in pairs(self.registryCallbacks) do
            EventRegistry:UnregisterCallback(event, self)
            self.registryCallbacks[event] = nil
        end
    end
end

-- Undoes everything this context changed: native frame state, events, the
-- skin client and saved CVars. Every record (one tuple or property setter,
-- one frame's fields or anchor points) is restored on its own through
-- Dispatch: a restore that raises is reported, every other record is still
-- restored and the CVars are always handed back. A record is dropped once
-- its restore finished, so one whose native setter raised stays for the
-- next release.
function Context:Release()
    if self.tuples then
        for frame, values in pairs(self.tuples) do
            for setter in pairs(values) do Dispatch(Context.RestoreTuple, self, frame, setter) end
        end
    end
    Dispatch(ReleaseEvents, self)
    for frame in pairs(self.fields) do Dispatch(Context.RestoreFields, self, frame) end
    for frame, properties in pairs(self.properties) do
        for setter in pairs(properties) do Dispatch(Context.RestoreProperty, self, frame, setter) end
    end
    for frame in pairs(self.points) do Dispatch(Context.RestorePoints, self, frame) end
    Dispatch(NS.Skin.Release, self.id)
    S.RestoreSaved(self.id)
end

function S.Install(id, module)
    assert(S.catalog[id] and not S.instances[id], "Invalid suite module")
    module.id = id
    S.instances[id] = module
end
