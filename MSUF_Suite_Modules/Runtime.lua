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
-- Timers.lua adds the deferred-work methods (ctx:After, Coalesce, Ticker).
Private.Context = Context

-- Secret-safe readers, the translation lookup and error isolation are
-- defined once in MSUF_Suite/Core/Platform.lua, which is always loaded.
S.Public, S.Number, S.Finite = NS.Public, NS.Number, NS.Finite
S.PublicText, S.ReadText, S.Text = NS.PublicText, NS.ReadText, NS.Text
S.Dispatch, S.Print = NS.Dispatch, NS.Print
-- Records a character collects (MSUF_Suite/Core/CharacterData.lua).
S.CharacterData = NS.CharacterData
-- The nameplate unit tokens, nameplate1 to nameplate150 on Retail and WoW
-- Forever (UnitSharedDocumentation: NamePlate1 to NamePlate150), built once
-- for every module: S.NameplateUnits[i] is a token, S.NameplateUnit[token]
-- is true.
do
    local units, isUnit = {}, {}
    for i = 1, 150 do
        units[i] = "nameplate" .. i
        isUnit[units[i]] = true
    end
    S.NameplateUnits, S.NameplateUnit = units, isUnit
end
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
    return setmetatable({ id = id, properties = {}, points = {}, callbacks = {}, combatEvents = {} },
        Context)
end

function Context:Skin()
    return NS.Skin.Acquire(self.id)
end

-- The controller (Suite.lua ApplyModule) still calls this after every Enable
-- and Refresh. No module remembers a skin call to repeat, so there is nothing
-- to paint; drop it together with that call.
function Context:RefreshOwnedSkins() end

-- Single-value getter/setter pairs such as GetScale/SetScale.
local function SetOwnedProperty(self, frame, getter, setter, value)
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

-- Protected frames refuse these writes in combat; the module applies again
-- after it.
function Context:Property(frame, getter, setter, value)
    if NS.IsCombatLocked() then
        S.Queue(self.id)
        return
    end
    SetOwnedProperty(self, frame, getter, setter, value)
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

function Context:TextColor(frame, r, g, b, a)
    if not NS.IsCombatLocked() then return self:Tuple(frame, "GetTextColor", "SetTextColor", r, g, b, a) end
    local values = self.tuples and self.tuples[frame]
    local record = values and values.SetTextColor
    if not record or not Accessible(frame) then return end
    frame:SetTextColor(r, g, b, a)
    local applied = record.applied
    applied[1], applied[2], applied[3], applied[4] = r, g, b, a
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

------------------------------------------------------------------ muted native frames
-- A native frame Blizzard shows on its own (a pooled alert, a fading zone
-- text, a banner) is muted by moving it under one shown host with alpha zero
-- and a scale so small that the frame keeps no hit area and no room in
-- Blizzard's anchor chains. Hide() or a hidden parent would run its OnHide
-- (an alert's pool release, a banner queue) inside this addon's call and
-- taint Blizzard's state; the move and its undo happen only while they leave
-- the frame's visibility unchanged, so none of its scripts run. Unprotected
-- frames only, so muting also works in combat.
local MUTE_SCALE = .001
local muteHost

local function MuteHost()
    if not muteHost then
        muteHost = S.CreateFrame("Frame", nil, UIParent)
        muteHost:SetSize(1, 1)
        muteHost:SetPoint("CENTER")
        muteHost:SetAlpha(0)
        muteHost:SetScale(MUTE_SCALE)
        muteHost:EnableMouse(false)
    end
    return muteHost
end

local function KeepsVisibility(frame, parent)
    return frame:IsVisible() == (frame:IsShown() and parent:IsVisible())
end

function Context:Mute(frame)
    if not Accessible(frame) or frame:IsProtected() then return false end
    local host, parent = MuteHost(), frame:GetParent()
    if parent == host then return true end
    if not parent or not KeepsVisibility(frame, host) then return false end
    self.muted = self.muted or {}
    self.muted[frame] = parent
    frame:SetParent(host)
    return true
end

-- Gives a muted frame its parent back. When Blizzard moved it already, or
-- the move would change its visibility, it stays: Blizzard sets the parent
-- of its pooled frames again when it shows them.
function Context:Unmute(frame)
    local parent = self.muted and self.muted[frame]
    if not parent then return end
    self.muted[frame] = nil
    if Accessible(frame) and frame:GetParent() == muteHost and KeepsVisibility(frame, parent) then
        frame:SetParent(parent)
    end
end

-- HideControl for a native frame that is not protected: its alpha and mouse
-- are not restricted, so this applies in combat too.
function Context:HideUnprotected(frame, hidden)
    if not Accessible(frame) or frame:IsProtected() then return end
    if hidden then
        SetOwnedProperty(self, frame, "GetAlpha", "SetAlpha", 0)
        SetOwnedProperty(self, frame, "IsMouseEnabled", "EnableMouse", false)
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
-- Geometry modules re-apply after combat instead of moving frames in it.
local function DeferGeometry(ctx, event)
    if ctx.combatEvents[event] or not NS.IsCombatLocked() then return false end
    S.Queue(ctx.id)
    return true
end

-- OnEvent of every context frame: hands the event to the module callback,
-- isolated (Dispatch) like every other callback a module gives the runtime.
local function RouteEvent(frame, event, ...)
    local module = frame.module
    if not module.active then return end
    if event == "ADDON_LOADED" and module.addons and not module.addons[(...)] then return end
    if module.geometry and DeferGeometry(frame.context, event) then return end
    local callback = frame.callbacks[event]
    if callback then Dispatch(callback, module, event, ...) end
end

local function RoutingFrame(ctx)
    local frame = S.CreateFrame("Frame")
    frame.context = ctx
    -- The context keeps this table for its lifetime (Release empties it).
    frame.callbacks = ctx.callbacks
    -- Install owns this instance for the context's lifetime.
    frame.module = S.instances[ctx.id]
    frame:SetScript("OnEvent", RouteEvent)
    return frame
end

-- One RegisterUnitEvent filters at most Constants.UnitEventConstants
-- .MAX_UNIT_TOKENS_IN_EVENT (4) units, and a second call on the same frame
-- replaces the first filter. A longer unit list therefore gets one extra
-- routing frame per further chunk of four.
local UNITS_PER_FRAME = 4

local function RegisterUnitList(ctx, event, units)
    for first = 1, #units, UNITS_PER_FRAME do
        local chunk = (first - 1) / UNITS_PER_FRAME
        local frame = ctx.frame
        if chunk > 0 then
            ctx.unitFrames = ctx.unitFrames or {}
            frame = ctx.unitFrames[chunk] or RoutingFrame(ctx)
            ctx.unitFrames[chunk] = frame
        end
        frame:RegisterUnitEvent(event, unpack(units, first, math.min(#units, first + UNITS_PER_FRAME - 1)))
    end
end

-- callback(module, event, ...). options (optional) are named:
-- options.inCombat lets a geometry module (module.geometry) also get the
-- event in combat instead of re-applying after it; every other module always
-- gets its events. Callers keep one options table per file, made once and
-- never changed (IN_COMBAT = { inCombat = true }). unit (for example
-- "player", or a list such as the boss tokens) limits a unit event to those
-- units. The older positional boolean allowCombat in place of options still
-- works for the callers not moved yet.
function Context:Event(event, callback, options, unit)
    if not NS.Client.SupportsEvent(event) then return end
    -- A job (Timers.lua) registers its event function: Dispatch only runs functions.
    if type(callback) == "table" then callback = callback:EventFunction() end
    local inCombat = options
    if options and options ~= true then inCombat = options.inCombat end
    local alreadyRegistered = self.callbacks[event] ~= nil
    if not self.frame then self.frame = RoutingFrame(self) end
    self.combatEvents[event] = inCombat or nil
    self.callbacks[event] = callback
    if alreadyRegistered then return end
    if type(unit) == "table" then
        RegisterUnitList(self, event, unit)
    elseif unit and self.frame.RegisterUnitEvent then
        self.frame:RegisterUnitEvent(event, unit)
    else
        self.frame:RegisterEvent(event)
    end
end

function Context:RemoveEvent(event)
    if self.callbacks[event] == nil then return end
    self.callbacks[event] = nil
    self.combatEvents[event] = nil
    if self.frame then self.frame:UnregisterEvent(event) end
    if self.unitFrames then
        for _, frame in ipairs(self.unitFrames) do frame:UnregisterEvent(event) end
    end
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
    if self.unitFrames then
        for _, frame in ipairs(self.unitFrames) do frame:UnregisterAllEvents() end
    end
    for key in pairs(self.callbacks) do self.callbacks[key] = nil end
    for key in pairs(self.combatEvents) do self.combatEvents[key] = nil end
    if self.registryCallbacks then
        for event in pairs(self.registryCallbacks) do
            EventRegistry:UnregisterCallback(event, self)
            self.registryCallbacks[event] = nil
        end
    end
end

-- Undoes everything this context changed: native frame state, events, the
-- skin client and saved CVars. Every record (one tuple or property setter,
-- one frame's anchor points) is restored on its own through
-- Dispatch: a restore that raises is reported, every other record is still
-- restored and the CVars are always handed back. A record is dropped once
-- its restore finished, so one whose native setter raised stays for the
-- next release.
function Context:Release()
    -- Pending timers (Timers.lua) go first: nothing deferred runs after this.
    if self.timers then Dispatch(Context.CancelTimers, self) end
    if self.tuples then
        for frame, values in pairs(self.tuples) do
            for setter in pairs(values) do Dispatch(Context.RestoreTuple, self, frame, setter) end
        end
    end
    Dispatch(ReleaseEvents, self)
    for frame, properties in pairs(self.properties) do
        for setter in pairs(properties) do Dispatch(Context.RestoreProperty, self, frame, setter) end
    end
    for frame in pairs(self.points) do Dispatch(Context.RestorePoints, self, frame) end
    if self.muted then
        for frame in pairs(self.muted) do Dispatch(Context.Unmute, self, frame) end
    end
    Dispatch(NS.Skin.Release, self.id)
    S.RestoreSaved(self.id)
end

local function NoopRefresh() end

function S.Install(id, module)
    assert(S.catalog[id] and not S.instances[id], "Invalid suite module")
    -- Event-only modules keep their registrations when an active profile is reapplied.
    module.Refresh = module.Refresh or NoopRefresh
    module.id = id
    S.instances[id] = module
end
