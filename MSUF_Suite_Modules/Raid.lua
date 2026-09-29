local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end

-- Encounter records belong to the Suite objective HUD. Blizzard supplies the
-- engaged boss list at ENCOUNTER_END, including bosses from earlier phases.
local H = {}
local Finite, Public, Text = S.Finite, S.Public, S.PublicText
-- 12.1 has five boss unit tokens (UnitTokenType Boss1-Boss5). Live health
-- listens to exactly these instead of every raid member's UNIT_HEALTH.
local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }
local BOSS_INDEX = {}
for index, unit in ipairs(BOSS_UNITS) do BOSS_INDEX[unit] = index end
-- Boss health changes with every damage tick. The boss row is redrawn at
-- most five times per second; the one-second ticker redraws the rest.
local LIVE_PAINT_DELAY = .2

local function SetText(widget, value)
    if widget.cachedText ~= value then
        widget:SetText(value)
        widget.cachedText = value
    end
end

local function Clock(seconds)
    if not Finite(seconds) then return "--:--" end
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function Line(parent, size, y)
    local line = S.CreateFontString(parent, nil, "OVERLAY")
    S.SetStyledFont(line, S.GlobalFontPath(), size, "OUTLINE", 1, true, 70, 1)
    line:SetPoint("TOPLEFT", 4, y)
    line:SetPoint("TOPRIGHT", -4, y)
    line:SetJustifyH("LEFT")
    line:SetWordWrap(false)
    return line
end

-- The active boss row while a pull runs, else the last result.
local function CurrentText(view)
    if not view.pull then return "LAST PULL  " .. (view.lastResult or "--") end
    local names = {}
    for i = 1, 10 do
        local boss = view.live[i]
        if boss then
            names[#names + 1] = (boss.name or ("Boss " .. i))
                .. (boss.percent and string.format(" %.1f%%", boss.percent) or "")
        end
    end
    return "ACTIVE BOSSES  " .. (#names > 0 and table.concat(names, " · ") or "HP unavailable")
end

local function PaintLive(owner)
    local view = owner.raid
    view.livePending = false
    if view.pull and owner.active and owner.raidActive then SetText(view.current, CurrentText(view)) end
end

local function Create(owner)
    if owner.raid then return owner.raid end
    local panel = S.CreateFrame("Frame", nil, owner.content)
    panel:SetPoint("TOPLEFT", owner.content, "TOPLEFT", 0, 0)
    panel:SetPoint("TOPRIGHT", owner.content, "TOPRIGHT", 0, 0)
    panel:SetHeight(230)
    local view = { frame = panel, height = 230, live = {} }
    view.name = Line(panel, 16, -5)
    view.elapsed = Line(panel, 23, -34)
    view.phase = Line(panel, 13, -72)
    view.current = Line(panel, 13, -100)
    view.best = Line(panel, 13, -148)
    view.fastest = Line(panel, 13, -205)
    view.current:SetWordWrap(true)
    view.best:SetWordWrap(true)
    view.tick = function() H.Tick(owner) end
    view.liveTick = function() PaintLive(owner) end
    panel:Hide()
    owner.raid = view
    return view
end

local function Record(view)
    local key = view.encounterID and (view.encounterID .. ":" .. view.difficultyID)
    return key and view.records and view.records[key] or nil
end

local function ProgressText(best)
    local boss = best.boss and (best.boss .. "  ") or ""
    local progress = best.defeated > 0 and (best.defeated .. " boss defeated · ") or ""
    return progress .. boss .. string.format("%.1f%%", best.remaining)
end

local function BestText(best)
    return "BEST PULL  " .. (best and ProgressText(best) or "--")
end

local function Paint(owner)
    local view = owner.raid
    if not view then return end
    local record = Record(view)
    SetText(view.name, view.encounterName or "Waiting for raid encounter")
    SetText(view.elapsed, view.pull and Clock(GetTime() - view.pull.started)
        or view.lastTime and Clock(view.lastTime) or "--:--")
    local phase = view.stage and ("PHASE  " .. view.stage
        .. (view.stageSource and ("  ·  " .. view.stageSource) or "")) or "PHASE  --"
    local phases = record and record.bestPhases
    local bestPhase = phases and (view.stageSource and phases[view.stageSource]
        or phases.DBM or phases.BigWigs)
    SetText(view.phase, phase)
    SetText(view.current, CurrentText(view))
    if bestPhase then
        local best = "BEST PULL  PHASE " .. bestPhase.stage
        if bestPhase.defeated and bestPhase.defeated > 0 then
            best = best .. " · " .. bestPhase.defeated .. " boss defeated"
        end
        if bestPhase.remaining then
            best = best .. " · " .. (bestPhase.boss and (bestPhase.boss .. " ") or "")
                .. string.format("%.1f%%", bestPhase.remaining)
        end
        SetText(view.best, best)
    else
        SetText(view.best, BestText(record and record.best))
    end
    SetText(view.fastest, "FASTEST KILL  " .. Clock(record and record.fastest))
end

function H.Theme(owner)
    local view = owner.raid
    if not view then return end
    local c, font = owner.config, owner.font or S.GlobalFontPath()
    local primary = owner.textRGB or { .95, .96, .98 }
    local muted = owner.mutedRGB or { .78, .81, .85 }
    for _, line in ipairs({ view.name, view.elapsed, view.phase, view.current, view.best, view.fastest }) do
        S.SetStyledFont(line, font, c.objectiveSize or 13, "OUTLINE", 1, true, 70, 1)
        line:SetTextColor(unpack(primary))
    end
    S.SetStyledFont(view.name, font, c.entrySize or 15, "OUTLINE", 1, true, 70, 1)
    S.SetStyledFont(view.elapsed, font, math.max(23, (c.titleSize or 18) + 5), "OUTLINE", 1, true, 70, 1)
    view.current:SetTextColor(unpack(muted))
    view.phase:SetTextColor(unpack(muted))
    view.fastest:SetTextColor(unpack(muted))
end

function H.Detect(owner)
    if not owner.config.showRaid then return false end
    local inside, kind = IsInInstance()
    return Public(inside) and Public(kind) and inside == true and kind == "raid"
end

-- Older raid records stored the encounter-end fraction as a display percent.
local function MigrateWipePercent(record)
    if type(record) ~= "table" then return end
    local function Migrate(progress)
        if type(progress) ~= "table" then return end
        local remaining = progress.remaining
        if Finite(remaining) and remaining >= 0 and remaining <= 1 then
            progress.remaining = remaining * 100
        end
    end
    Migrate(record.best)
    if type(record.bestPhases) == "table" then
        for _, phase in pairs(record.bestPhases) do Migrate(phase) end
    end
end

function H.Show(owner)
    if not H.Detect(owner) then return false end
    local view = Create(owner)
    local state = S.ModuleState("objectives") or {}
    if type(state.raidRecords) ~= "table" then state.raidRecords = {} end
    if state.raidRecordsHealthScale ~= 100 then
        for _, record in pairs(state.raidRecords) do MigrateWipePercent(record) end
        state.raidRecordsHealthScale = 100
    end
    view.records = state.raidRecords
    owner.raidActive = true
    view.frame:Show()
    H.Bind(owner)
    Paint(owner)
    return true
end

local function StopTicker(view)
    if view.ticker then view.ticker:Cancel() end
    view.ticker = nil
end

function H.Stop(owner)
    local view = owner.raid
    if not view then return end
    StopTicker(view)
    H.Unbind(owner)
    owner.context:RemoveEvent("UNIT_HEALTH")
    owner.context:RemoveEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    view.pull = nil
    view.encounterID, view.difficultyID, view.encounterName, view.difficultyName = nil, nil, nil, nil
    view.stage, view.stageStep, view.stageSource = nil, nil, nil
    view.lastTime, view.lastResult = nil, nil
    view.live = {}
    view.frame:Hide()
    owner.raidActive = false
end

-- Reads one boss unit into view.live. True when its row changed.
local function ReadBoss(view, index, unit)
    local before = view.live[index]
    local exists = UnitExists(unit)
    if Public(exists) and exists == false then
        if not before then return false end
        view.live[index] = nil
        return true
    end
    local name = Text(UnitName(unit))
    local percent = UnitHealthPercent(unit)
    percent = Finite(percent) and percent >= 0 and percent <= 100 and percent or nil
    if before and before.name == name and before.percent == percent then return false end
    if not name and not percent then
        if not before then return false end
        view.live[index] = nil
    elseif before then
        before.name, before.percent = name, percent
    else
        view.live[index] = { name = name, percent = percent }
    end
    return true
end

-- A health tick only moves the boss row; it is redrawn with the next live
-- paint instead of repainting the whole view per tick.
function H.Health(owner, unit)
    local view = owner.raid
    if not view or not view.pull or not Public(unit) then return end
    local index = BOSS_INDEX[unit]
    if not index or not ReadBoss(view, index, unit) or view.livePending then return end
    view.livePending = true
    C_Timer.After(LIVE_PAINT_DELAY, view.liveTick)
end

-- Engage changes (a boss appears or leaves) are drawn at once.
function H.UpdateBosses(owner)
    local view = owner.raid
    if not view or not view.pull then return end
    local changed = false
    for index, unit in ipairs(BOSS_UNITS) do
        changed = ReadBoss(view, index, unit) or changed
    end
    if changed then Paint(owner) end
end

-- DBM and BigWigs know fight-specific transitions from their boss modules.
-- Their public callbacks are optional; the Suite never guesses stages from HP.
function H.Stage(owner, source, stage, step)
    local view = owner.raid
    if not view or not view.pull or not Finite(stage) or stage <= 0 then return end
    if view.stageSource and view.stageSource ~= source then return end
    if view.stage ~= stage then
        view.stageStep = Finite(step) and step > 0 and step or (view.stageStep or 0) + 1
    elseif Finite(step) and step > (view.stageStep or 0) then
        view.stageStep = step
    end
    view.stageSource, view.stage = source, stage
    Paint(owner)
end

function H.Bind(owner)
    local view = owner.raid
    if not view then return end
    local dbm = _G.DBM
    if not view.dbm and type(dbm) == "table" and type(dbm.RegisterCallback) == "function" then
        view.dbmCallback = view.dbmCallback or function(_, _, _, stage, encounterID, totality)
            if view.pull and Finite(encounterID) and encounterID == view.encounterID then
                H.Stage(owner, "DBM", stage, totality)
            end
        end
        dbm:RegisterCallback("DBM_SetStage", view.dbmCallback)
        view.dbm = dbm
    end
    local loader = _G.BigWigsLoader
    if not view.bigWigs and type(loader) == "table" and type(loader.RegisterMessage) == "function" then
        view.bigWigsListener = view.bigWigsListener or {}
        view.bigWigsCallback = view.bigWigsCallback or function(_, boss, stage)
            if not view.pull or not Public(boss) or type(boss) ~= "table" then return end
            local matches = boss:IsEncounterID(view.encounterID)
            if Public(matches) and matches then H.Stage(owner, "BigWigs", stage) end
        end
        loader.RegisterMessage(view.bigWigsListener, "BigWigs_SetStage", view.bigWigsCallback)
        view.bigWigs = loader
    end
end

function H.Unbind(owner)
    local view = owner.raid
    if not view then return end
    if view.dbm and type(view.dbm.UnregisterCallback) == "function" then
        view.dbm:UnregisterCallback("DBM_SetStage", view.dbmCallback)
    end
    if view.bigWigs and type(view.bigWigs.UnregisterMessage) == "function" then
        view.bigWigs.UnregisterMessage(view.bigWigsListener, "BigWigs_SetStage")
    end
    view.dbm, view.bigWigs = nil, nil
end

function H.Tick(owner)
    local view = owner.raid
    if owner.active and owner.raidActive and view and view.pull then Paint(owner) end
end

local function ReadInitialStage(owner)
    local view = owner.raid
    local dbm = view.dbm
    if dbm and type(dbm.GetStage) == "function" then
        local stage, totality, encounterID = dbm:GetStage()
        if Finite(encounterID) and encounterID == view.encounterID then
            H.Stage(owner, "DBM", stage, totality)
        end
    end
    if view.stage then return end
    local bigWigs = _G.BigWigs
    if not bigWigs or type(bigWigs.IterateBossModules) ~= "function" then return end
    for _, boss in bigWigs:IterateBossModules() do
        if Public(boss) and type(boss) == "table" and boss:IsEncounterID(view.encounterID) then
            local engaged = boss:IsEngaged()
            if Public(engaged) and engaged == true then
                H.Stage(owner, "BigWigs", boss:GetStage())
                return
            end
        end
    end
end

function H.Start(owner, encounterID, encounterName, difficultyID)
    if not H.Detect(owner) or not Finite(encounterID) or not Finite(difficultyID) then return false end
    H.Show(owner)
    local view = owner.raid
    StopTicker(view)
    view.encounterID, view.difficultyID = encounterID, difficultyID
    view.encounterName = Text(encounterName) or "Raid encounter"
    view.difficultyName = Text(GetDifficultyInfo(difficultyID)) or ("Difficulty " .. difficultyID)
    view.lastTime, view.lastResult = nil, nil
    view.stage, view.stageStep, view.stageSource = nil, nil, nil
    view.live = {}
    view.pull = { started = GetTime() }
    ReadInitialStage(owner)
    owner.context:Event("UNIT_HEALTH", function(module, _, unit) H.Health(module, unit) end, true, BOSS_UNITS)
    owner.context:Event("INSTANCE_ENCOUNTER_ENGAGE_UNIT", function(module) H.UpdateBosses(module) end, true)
    H.UpdateBosses(owner)
    view.ticker = C_Timer.NewTicker(1, view.tick)
    Paint(owner)
    return true
end

-- A later boss at 70% beats an earlier boss at 1%. EncounterUnitStatus is
-- evaluated only after a wipe, when Blizzard supplies every engaged unit.
local function WipeProgress(status, live)
    if not Public(status) or type(status) ~= "table" then return nil end
    local defeated, remaining, boss, total = 0, nil, nil, 0
    local activeNames, activeRemaining, activeBoss = {}, nil, nil
    for i = 1, 10 do
        local active = live[i]
        if active and active.name then activeNames[active.name] = true end
    end
    for i = 1, math.min(#status, 20) do
        local unit = status[i]
        if Public(unit) and type(unit) == "table" then
            -- Encounter-end health is fractional; records and text use 0..100.
            local fraction = unit.remainingHealthPercent
            if Finite(fraction) and fraction >= 0 and fraction <= 1 then
                local percent = fraction * 100
                total = total + 1
                if percent == 0 then
                    defeated = defeated + 1
                else
                    local name = Text(unit.creatureName)
                    if not remaining or percent > remaining then remaining, boss = percent, name end
                    if name and activeNames[name] and (not activeRemaining or percent > activeRemaining) then
                        activeRemaining, activeBoss = percent, name
                    end
                end
            end
        end
    end
    if activeRemaining then remaining, boss = activeRemaining, activeBoss end
    if total == 0 or not remaining then return nil end
    return { defeated = defeated, remaining = remaining, boss = boss, total = total }
end

function H.End(owner, encounterID, _, difficultyID, _, success, status)
    local view = owner.raid
    if not view or not view.pull or view.encounterID ~= encounterID
        or view.difficultyID ~= difficultyID then return end
    StopTicker(view)
    owner.context:RemoveEvent("UNIT_HEALTH")
    owner.context:RemoveEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    local elapsed = GetTime() - view.pull.started
    view.lastTime = Finite(elapsed) and elapsed >= 0 and elapsed or nil
    view.pull = nil
    local key = view.encounterID .. ":" .. view.difficultyID
    local record = view.records[key] or {}
    view.records[key] = record
    if not Public(success) or not Finite(success) then
        view.lastResult = "RESULT UNAVAILABLE"
    elseif success == 1 then
        view.lastResult = "KILL"
        if view.lastTime and (not Finite(record.fastest) or view.lastTime < record.fastest) then
            record.fastest = view.lastTime
        end
    elseif success == 0 then
        local progress = WipeProgress(status, view.live)
        view.lastResult = progress and ("WIPE · " .. ProgressText(progress)) or "WIPE · HP unavailable"
        if view.stage and view.stageStep and view.stageSource then
            record.bestPhases = record.bestPhases or {}
            local previous = record.bestPhases[view.stageSource]
            if not previous or view.stageStep > previous.step
                or view.stageStep == previous.step and progress
                    and (not previous.remaining or progress.defeated > (previous.defeated or 0)
                        or progress.defeated == (previous.defeated or 0)
                            and progress.remaining < previous.remaining) then
                record.bestPhases[view.stageSource] = { stage = view.stage, step = view.stageStep,
                    remaining = progress and progress.remaining or nil,
                    defeated = progress and progress.defeated or nil,
                    boss = progress and progress.boss or nil }
            end
        end
        local best = record.best
        if progress and (not best or progress.defeated > best.defeated
            or progress.defeated == best.defeated and progress.remaining < best.remaining) then
            record.best = progress
        end
    else
        view.lastResult = "RESULT UNAVAILABLE"
    end
    Paint(owner)
end

S.Raid = H
