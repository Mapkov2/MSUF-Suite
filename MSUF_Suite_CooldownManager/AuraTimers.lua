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
-- Cold spell identities only; duration and activity still come from Blizzard.
-- Shaman casts must enter the same route even when they have no player aura.
local CAST = {
    [325197] = 325197, [406220] = 325197, [322118] = 322118, [389422] = 322118,
    [2484] = 2484, -- Earthbind
    [5394] = 5394, -- Healing Stream
    [8143] = 8143, -- Tremor
    [16191] = 16191, -- Mana Tide
    [51485] = 51485, -- Earthgrab
    [98008] = 98008, -- Spirit Link
    [108270] = 108270, -- Stone Bulwark
    [108280] = 108280, -- Healing Tide
    [157153] = 157153, -- Cloudburst
    [192058] = 192058, -- Capacitor
    [192077] = 192077, -- Wind Rush
    [192222] = 192222, -- Liquid Magma
    [198838] = 198838, -- Earthen Wall
    [204331] = 204331, -- Counterstrike
    [204336] = 204336, [8178] = 204336, -- Grounding / aura
    [207399] = 207399, -- Ancestral Protection
    [355580] = 355580, -- Static Field
    [383013] = 383013, -- Poison Cleansing
    [383017] = 383017, -- Stoneskin
    [383019] = 383019, -- Tranquil Air
    [444995] = 444995, -- Surging
}
local rows, routes, hidden, pool, slots = {}, {}, {}, {}, {}
local manualRoutes, castStates = {}, {}
local barSources = setmetatable({}, { __mode = "k" })
Timers.slots = slots
local serial, emptyDuration, sourceWanted = 0, nil, false
Timers.generation = 0
Timers.hasManual = false
local direction = Enum.StatusBarTimerDirection
local immediate = Enum.StatusBarInterpolation.Immediate

local function Summon(entry)
    -- Follow the current talent override, as Blizzard's GetSpellID does.
    local id = CAST[entry.tooltip] or CAST[entry.spell] or CAST[entry.base]
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
    local source = barSources[row.barSource or row.source]
    if source then source.generation = nil end
    row.active, row.totemSlot, row.shown, row.source, row.mirror, row.barSource = false, nil, false, nil, nil, nil
    row.frame:Hide()
    row.frame:SetAlpha(1)
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
    if row.active and not row.mirror then Stop(row) end
end

local function Paint(row, duration)
    if row.mirror then row.frame:SetAlpha(1) row.mirror = nil end
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
local function SourceRows(item)
    local id = item.cooldownID
    if not Public(id) or type(id) ~= "number" then return end
    local rec = C.Catalog.records[id]
    if not rec then return end
    local spell
    local info = item.cooldownInfo
    if Public(info) and type(info) == "table" then
        local linked = info.linkedSpellID
        if Public(linked) and CAST[linked] then spell = linked end
    end
    if not spell then
        spell = CAST[rec.tooltip] and rec.tooltip or CAST[rec.override] and rec.override or rec.spell
    end
    local cast = CAST[spell]
    return cast and routes[cast], cast ~= nil and (spell == cast or rec.tooltip == cast or rec.override == cast or rec.spell == cast)
end

function Timers.Source(item)
    if not Public(item) or type(item) ~= "table" then return end
    local list = SourceRows(item)
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

local function RetireBar(item, list)
    for i = 1, #(list or C.EMPTY) do
        local row = list[i]
        if row.mirror == item then Stop(row) end
    end
end

-- A native buff bar can have a usable clock even when the totem association
-- is unreadable. Forward its existing writes, never reconstruct secret time.
-- This fallback follows Blizzard's draining fill and integer timer; duration
-- objects above retain Suite's elapsed fill and countdown formatting.
function Timers.SourceBar(item, bind)
    if not Public(item) or type(item) ~= "table" then return end
    local bar = item.Bar
    if not Public(bar) or type(bar) ~= "table" then return end
    local source = barSources[item]
    if not source then
        if not bind then return end
        source = {}
        barSources[item] = source
    elseif source.generation ~= Timers.generation then
        bind = true
    end
    local list = source.list
    if bind then
        local current, summon = SourceRows(item)
        -- Aura aliases are consumers of the summon clock, not native summon
        -- sources: a permanent Chi Cocoon bar must not become that clock.
        if not summon then current = nil end
        if list ~= current then RetireBar(item, list) end
        list = current
        source.list, source.generation = list, Timers.generation
    end
    if not list then return end
    local active = item.isActive
    if Public(active) and active ~= true then
        RetireBar(item, list)
        source.list = nil
        return
    end
    local needed = false
    local minimum, maximum = bar:GetMinMaxValues()
    local value = bar:GetValue()
    for i = 1, #list do
        local row = list[i]
        -- A working duration object or explicit manual duration owns its row.
        -- An inactive duplicate never takes an existing clock away.
        if row.seconds == 0 then row.barSource = item end
        if row.seconds == 0 and (not row.active or row.mirror == item) then
            needed = true
            if row.mirror ~= item then
                Stop(row)
                row.active, row.source, row.mirror, row.barSource = true, item, item, item
            end
            local part = row.frame.part
            part.bar:SetMinMaxValues(minimum, maximum)
            part.bar:SetValue(value, immediate)
            if row.time then part.dur:SetFormattedText("%.0f", value) end
            row.frame:SetAlphaFromBoolean(active, 1, 0)
            Show(row)
        end
    end
    source.list = needed and list or nil
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
    C.wipe(barSources)
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
