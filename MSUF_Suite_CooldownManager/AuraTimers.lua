local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Summons have a totem duration, not necessarily a timed player aura.
-- These rows are ours, outside sealed AuraContainer buttons. Native clocks
-- paint the fill/text and emit the completion edge; no Lua ticking.
local K = C.Const
local Public, type, pairs = S.Public, type, pairs
local Timers = {}
C.AuraTimers = Timers
local CAST = { [325197] = 325197, [406220] = 325197, [322118] = 322118, [389422] = 322118 }
local rows, routes, hidden, pool, slots = {}, {}, {}, {}, {}
local manualRoutes, castStates = {}, {}
Timers.slots = slots
local serial, emptyDuration, sourceWanted = 0, nil, false
Timers.generation = 0
Timers.hasManual = false
local direction = Enum.StatusBarTimerDirection
local immediate = Enum.StatusBarInterpolation.Immediate

local function Summon(entry)
    local id = CAST[entry.base] or CAST[entry.spell]
    if id then return id end
    for spell in pairs(entry.auraIDs or C.EMPTY) do
        id = CAST[spell]
        if id then return id end
    end
end

function Timers.Classify(entry)
    entry.timer = entry.family == K.FAMILY.AURA and entry.src ~= "p" and entry.unit ~= "target" and entry.unit ~= "both"
        and (Summon(entry) ~= nil or ((entry.ov or C.EMPTY).timerDuration or 0) > 0)
end

function Timers.Wants(entry, view)
    return entry.timer == true and view.kind == K.KIND.AURA_BAR and view.barStacks ~= true
end

function Timers.Wanted()
    for slot, plan in pairs(C.plans) do
        local view = C.views[slot]
        if plan.hasTimers and view and view.on then
            for i = 1, #plan.entries do
                if Timers.Wants(plan.entries[i], view) then return true end
            end
        end
    end
    return false
end

local function Show(row)
    local shown = row.active == true and not hidden[row.slot] and not C.state.preview
    if row.shown ~= shown then
        row.shown = shown
        row.frame:SetShown(shown)
    end
end

local function Stop(row)
    row.active, row.totemSlot, row.shown, row.source = false, nil, false, nil
    row.frame:Hide()
    row.binding:SetEnabled(false)
    row.gate:Clear()
    if not emptyDuration then
        emptyDuration = C_DurationUtil.CreateDuration()
        emptyDuration:SetTimeFromStart(0, 0)
    end
    row.frame.part.bar:SetTimerDuration(emptyDuration, immediate, row.direction)
    row.duration = nil
end

local function Done(gate)
    local row = gate.timerRow
    if row.active then Stop(row) end
end

local function Paint(row, duration)
    row.duration, row.active = duration, true
    row.binding:SetDuration(duration)
    row.binding:SetEnabled(row.time == true)
    row.frame.part.bar:SetTimerDuration(duration, immediate, row.direction)
    row.gate:SetCooldownFromDurationObject(duration, true)
    Show(row)
end

local function RebuildRoutes()
    C.wipe(routes)
    C.wipe(manualRoutes)
    sourceWanted = false
    Timers.hasManual = false
    for _, row in pairs(rows) do
        local cast = row.cast
        if cast then
            if CAST[cast] == cast then sourceWanted = true end
            local list = routes[cast]
            if not list then list = {} routes[cast] = list end
            list[#list + 1] = row
            if row.seconds > 0 then
                manualRoutes[cast] = list
                Timers.hasManual = true
            end
        end
    end
    for cast in pairs(castStates) do
        if not manualRoutes[cast] then castStates[cast] = nil end
    end
    for cast in pairs(manualRoutes) do
        if castStates[cast] == nil then
            local info = C_Spell.GetSpellCooldown(cast)
            castStates[cast] = Public(info) and type(info) == "table" and Public(info.isActive) and info.isActive == true
        end
    end
    Timers.generation = Timers.generation + 1
end

function Timers.NeedsSources() return sourceWanted end

local function ManualCooldown(cast, list)
    local info = C_Spell.GetSpellCooldown(cast)
    if not Public(info) or type(info) ~= "table" then return end
    local active, gcd, enabled = info.isActive, info.isOnGCD, info.isEnabled
    if not Public(active) or not Public(gcd) or not Public(enabled) then return end
    if gcd == true then
        castStates[cast] = false
        return
    end
    active = active == true and enabled ~= false
    local previous = castStates[cast]
    castStates[cast] = active
    if not active or previous then return end
    for i = 1, #list do
        local row = list[i]
        if row.seconds > 0 then
            row.manual:SetTimeFromStart(GetTime(), row.seconds)
            Paint(row, row.manual)
        end
    end
end

-- isActive/isOnGCD/isEnabled are NeverSecret in SpellSharedDocumentation.
-- Observe a real cooldown's rising edge, never its protected timestamps.
-- This also starts configured durations when cast identity/native viewers
-- are unavailable. A late enable seeds state above without inventing a cast.
function Timers.Cooldown(spell, base)
    if not Timers.hasManual then return end
    if not Public(spell) or spell == nil then
        for cast, list in pairs(manualRoutes) do ManualCooldown(cast, list) end
        return
    end
    local cast = manualRoutes[spell] and spell or (Public(base) and manualRoutes[base] and base)
    if cast then ManualCooldown(cast, manualRoutes[cast]) end
end

-- Blizzard's RefreshTotemData associates a public cooldownID with a slot
-- before this observer runs. GetTotemInfo/UNIT_SPELLCAST_SUCCEEDED may hide
-- spell identity throughout M+, so route by our cold catalog instead.
-- Read native records only; their spellID and haveTotem are never inspected.
function Timers.Source(item)
    if not Public(item) or type(item) ~= "table" then return end
    local id = item.cooldownID
    if not Public(id) or type(id) ~= "number" then return end
    local rec = C.Catalog.records[id]
    local cast = rec and (CAST[rec.spell] or CAST[rec.override])
    local list = cast and routes[cast]
    if not list then return end
    local data = item.totemData
    if not Public(data) then return end
    if data == nil then
        for i = 1, #list do
            local row = list[i]
            if row.source == item then Stop(row) end
        end
        return
    end
    if type(data) ~= "table" then return end
    local slot = data.slot
    if not Public(slot) or type(slot) ~= "number" or slot < 1 then return end
    local duration = GetTotemDuration(slot)
    if not Public(duration) or duration == nil then return end
    local start
    local expires, length = data.expirationTime, data.duration
    if Public(expires) and type(expires) == "number" and Public(length) and type(length) == "number" then
        start = expires - length
    end
    for i = 1, #list do
        local row, object = list[i], duration
        row.totemSlot, row.source = slot, item
        if row.seconds > 0 then
            if start then
                row.manual:SetTimeFromStart(start, row.seconds)
                object = row.manual
            elseif row.active and row.duration == row.manual then
                object = row.manual
            end
        end
        Paint(row, object)
    end
end

-- One public slot read per PLAYER_TOTEM_UPDATE. All identities are guarded
-- before branching or indexing. The duration object itself goes to C sinks.
function Timers.Totem(_, _, slot)
    if not Public(slot) or type(slot) ~= "number" or slot < 1 then return end
    local have, _, start, _, _, _, spell = GetTotemInfo(slot)
    if not Public(have) or not Public(spell) then return end
    local cast = have == true and CAST[spell] or nil
    for _, row in pairs(rows) do
        if row.totemSlot == slot and row.cast ~= cast then Stop(row) end
    end
    local list = cast and routes[cast]
    if not list then return end
    local duration = GetTotemDuration(slot)
    if not Public(duration) or duration == nil then return end
    for i = 1, #list do
        local row = list[i]
        row.totemSlot = slot
        local object = duration
        if row.seconds > 0 and Public(start) and type(start) == "number" then
            row.manual:SetTimeFromStart(start, row.seconds)
            object = row.manual
        end
        Paint(row, object)
    end
end

function Timers.Cast(_, _, unit, _, spell)
    if not Public(unit) or unit ~= "player" or not Public(spell) then return end
    local list = routes[spell]
    if not list then return end
    for i = 1, #list do
        local row = list[i]
        if row.seconds > 0 then
            row.manual:SetTimeFromStart(GetTime(), row.seconds)
            Paint(row, row.manual)
        end
    end
end

local function Seed()
    if next(rows) == nil then return end
    local count = GetNumTotemSlots()
    if not Public(count) or type(count) ~= "number" or count < 0 or count > 16 then return end
    for slot = 1, count do Timers.Totem(nil, nil, slot) end
end

local function Style(row, entry, view)
    local ov = entry.ov or C.EMPTY
    local seconds = ov.timerDuration or 0
    local cast = ov.timerSpell or Summon(entry) or entry.base
    if row.cast ~= cast or row.seconds ~= seconds then Stop(row) end
    row.cast, row.seconds = cast, seconds
    if seconds > 0 and not row.manual then row.manual = C_DurationUtil.CreateDuration() end
    C.AuraButtons.Sample(row.frame:GetParent(), row.frame, view, ov, ov.icon or entry.texture, entry.name)
    -- Leave native aura stacks, glows, sounds and mouse/tooltip ownership
    -- intact. The matching static icon/name also serve a summon without an
    -- aura. Only the duration regions have an independent clock owner.
    row.frame:SetMouseMotionEnabled(false)
    row.frame.part.bg:Hide()
    row.frame.part.count:Hide()
    local level = C.bars[row.slot].frame:GetFrameLevel() + 5
    row.frame:SetFrameLevel(level)
    row.frame.part.bar:SetFrameLevel(level + K.AURA_LEVEL.fill)
    row.frame.part.timeFrame:SetFrameLevel(level + (K.Choice(ov.textTop, K.BarStacksTop(view)) and K.AURA_LEVEL.text or K.AURA_LEVEL.stacks))
    row.time = K.Choice(ov.timeText, K.BarTime(view))
    row.frame.part.dur:SetShown(row.time)
    row.direction = view.barFill == K.BAR_FILL.FILL and direction.ElapsedTime or direction.RemainingTime
    local opts = C.AuraButtons.TextOpts(ov.threshold or C.state.threshold)
    if row.opts ~= opts then
        row.opts = opts
        row.binding:Assign(opts.binding)
        row.binding:SetFontString(row.frame.part.dur)
    end
    if row.duration then
        row.binding:SetDuration(row.duration)
        row.binding:SetEnabled(row.time)
        row.frame.part.bar:SetTimerDuration(row.duration, immediate, row.direction)
    else
        row.binding:SetEnabled(false)
        row.frame.part.dur:SetText("")
    end
    Show(row)
end

function Timers.Sync(slot, view, plan)
    if not plan.hasTimers and not slots[slot] then return end
    serial = serial + 1
    slots[slot] = nil
    local cap = view.maxIcons
    if type(cap) ~= "number" or cap <= 0 then cap = #plan.entries end
    for i = 1, math.min(cap, #plan.entries) do
        local entry = plan.entries[i]
        if Timers.Wants(entry, view) then
            slots[slot] = true
            local cell = C.Layout.Cell(slot, i)
            local row = rows[entry.key]
            if row and (row.slot ~= slot or row.cell ~= cell) then
                Stop(row)
                rows[entry.key] = nil
                row = nil
            end
            if not row then
                row = pool[cell]
                if row then
                    Stop(row)
                    if row.key and rows[row.key] == row then rows[row.key] = nil end
                end
            end
            if not row then
                local frame = C.AuraButtons.Sample(cell, nil, view, entry.ov, entry.texture, entry.name)
                frame:SetAllPoints(cell)
                frame:Hide()
                local gate = S.CreateFrame("Cooldown", nil, frame)
                gate:SetAllPoints(frame)
                gate:SetAlpha(0)
                gate:SetHideCountdownNumbers(true)
                local binding = C_DurationUtil.CreateDurationTextBinding()
                row = { frame = frame, gate = gate, binding = binding, slot = slot, cell = cell, direction = direction.RemainingTime }
                gate.timerRow = row
                gate:SetScript("OnCooldownDone", Done)
                pool[cell] = row
            end
            row.key = entry.key
            rows[entry.key] = row
            row.mark = serial
            Style(row, entry, view)
        end
    end
    for key, row in pairs(rows) do
        if row.slot == slot and row.mark ~= serial then Stop(row) rows[key] = nil end
    end
    RebuildRoutes()
    Seed()
end

function Timers.Release(slot)
    if not slots[slot] then return end
    slots[slot] = nil
    for key, row in pairs(rows) do
        if row.slot == slot then Stop(row) rows[key] = nil end
    end
    RebuildRoutes()
end

function Timers.ReleaseAll()
    for key, row in pairs(rows) do Stop(row) rows[key] = nil end
    C.wipe(routes)
    C.wipe(manualRoutes)
    C.wipe(castStates)
    C.wipe(hidden)
    C.wipe(slots)
    sourceWanted = false
    Timers.hasManual = false
    Timers.generation = Timers.generation + 1
end

function Timers.SetBarMouse(slot, on)
    hidden[slot] = on ~= true or nil
    for _, row in pairs(rows) do
        if row.slot == slot then Show(row) end
    end
end

function Timers.SetPreview()
    for _, row in pairs(rows) do Show(row) end
end
