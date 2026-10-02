local _, P = ...
local NS, S = P.NS, P.Suite
-- Forever has no Mythic+.
if NS.Client.isForever then return end

-- The Mythic+ view replaces the objective list while a keystone runs. The
-- objectives module owns the frame and calls these helpers from its events;
-- the clock ticks once per second only while a run is active.
local H = {}
local WHITE = "Interface\\Buttons\\WHITE8X8"
local TEXT_RGB, MUTED_RGB = { .95, .96, .98 }, { .78, .81, .85 }
local COMPLETE_RGB, SCENARIO_RGB, FOCUSED_RGB, LATE_RGB = { .39, .86, .54 }, { .39, .64, .90 }, { .98, .84, .42 },
    { .92, .36, .36 }

local Public, Finite, Text = S.Public, S.Finite, S.PublicText
-- Criteria and completion info are plain tables whose fields may be secret.
local Field, Clock = S.PublicField, S.ClockText
local Tr = S.Text
-- Translated once: the clock and its rows repaint every second.
local L = {
    waiting = Tr("WAITING FOR TIMER"), left = Tr("%s left"), missed = Tr("missed"),
    complete = Tr("COMPLETE"), completeUpgrades = Tr("COMPLETE  +%d"),
    timeLeft = Tr("%s LEFT"), timeOver = Tr("%s OVER"),
    deaths = Tr("DEATHS  %s     TIME PENALTY  +%s"), affixes = Tr("AFFIXES  %s"),
    dungeon = Tr("MYTHIC+ DUNGEON"), forces = Tr("ENEMY FORCES  %s"),
    bosses = Tr("BOSSES / OBJECTIVES"), loading = Tr("OBJECTIVES LOADING"),
}
-- Blizzard's check mark atlas; WoW's stock fonts have no check mark glyph.
local DONE = "|A:common-icon-checkmark:12:12|a  "
local OPEN = "\194\183  "

local function SetText(widget, value)
    if widget.cachedText ~= value then
        widget:SetText(value)
        widget.cachedText = value
    end
end

-- Bracket 3/2/1 are the +3/+2/+1 chest windows; 0 is over time.
local function BracketColor(owner, bracket)
    local groups = owner.groupRGB
    if bracket == 3 then return owner.completeRGB or COMPLETE_RGB end
    if bracket == 2 then return groups and groups.scenario or SCENARIO_RGB end
    if bracket == 1 then return groups and groups.focused or FOCUSED_RGB end
    return LATE_RGB
end

local function StyleText(fontString, font, size)
    S.SetStyledFont(fontString, font, size, "OUTLINE", 1, true, 70, 1)
end

local function NewText(parent, size, right)
    local fontString = S.CreateFontString(parent, nil, "OVERLAY")
    StyleText(fontString, S.GlobalFontPath(), size)
    fontString:SetJustifyH(right and "RIGHT" or "LEFT")
    fontString:SetWordWrap(false)
    return fontString
end

local function NewBar(parent, y, height, maximum)
    local bar = S.CreateFrame("StatusBar", nil, parent)
    bar:SetPoint("TOPLEFT", 4, y)
    bar:SetPoint("TOPRIGHT", -4, y)
    bar:SetHeight(height)
    bar:SetStatusBarTexture(WHITE)
    bar:SetMinMaxValues(0, maximum)
    bar:SetValue(0)
    local back = S.CreateTexture(parent, nil, "BACKGROUND")
    back:SetAllPoints(bar)
    back:SetColorTexture(.15, .17, .20, .55)
    return bar, back
end

local function NewLine(parent, size, y)
    local line = NewText(parent, size)
    line:SetPoint("TOPLEFT", 4, y)
    line:SetPoint("TOPRIGHT", -4, y)
    return line
end

local function Create(owner)
    if owner.mplus then return owner.mplus end
    local panel = S.CreateFrame("Frame", nil, owner.content)
    panel:SetPoint("TOPLEFT", owner.content, "TOPLEFT", 0, 0)
    panel:SetPoint("TOPRIGHT", owner.content, "TOPRIGHT", 0, 0)
    local view = { frame = panel, bosses = {}, height = 282 }
    view.dungeon = NewLine(panel, 15, -4)
    view.clock = NewText(panel, 25)
    view.clock:SetPoint("TOPLEFT", 4, -30)
    view.remaining = NewText(panel, 13, true)
    view.remaining:SetPoint("TOPRIGHT", -4, -42)
    view.bar, view.barBack = NewBar(panel, -69, 7, 1)
    view.barText = NewText(view.bar, 11)
    view.barText:SetPoint("CENTER", 0, 0)
    view.thresholds = {}
    for i = 1, 2 do
        local tick = S.CreateTexture(view.bar, nil, "OVERLAY")
        tick:SetColorTexture(1, 1, 1, .75)
        tick:SetWidth(1)
        view.thresholds[i] = tick
    end
    view.bar:SetScript("OnSizeChanged", function(_, width)
        if not Finite(width) or width <= 0 then return end
        for i, tick in ipairs(view.thresholds) do
            tick:ClearAllPoints()
            tick:SetPoint("CENTER", view.bar, "LEFT", width * (i == 1 and .6 or .8), 0)
        end
    end)
    view.chests = {}
    for i = 1, 3 do
        local y = -88 - (i - 1) * 22
        local row = { label = NewText(panel, 13), remaining = NewText(panel, 13, true) }
        row.label:SetPoint("TOPLEFT", 4, y)
        row.remaining:SetPoint("TOPRIGHT", -4, y)
        view.chests[i] = row
    end
    view.deaths = NewLine(panel, 13, -158)
    view.affixes = NewLine(panel, 12, -180)
    view.forces = NewLine(panel, 13, -204)
    view.forcesBar, view.forcesBack = NewBar(panel, -227, 5, 100)
    view.observedPull = NewLine(panel, 12, -246)
    view.bossHeader = NewText(panel, 12)
    view.bossHeader:SetPoint("TOPLEFT", 4, -246)
    panel:Hide()
    owner.mplus = view
    return view
end

local function NewBossRow(view, index)
    local row = S.CreateFrame("Frame", nil, view.frame)
    local y = (view.bossY or -268) - (index - 1) * 21
    row:SetHeight(21)
    row:SetPoint("TOPLEFT", view.frame, "TOPLEFT", 4, y)
    row:SetPoint("TOPRIGHT", view.frame, "TOPRIGHT", -4, y)
    row.name = NewText(row, 12)
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -57, 0)
    row.time = NewText(row, 12, true)
    row.time:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.time:SetWidth(55)
    view.bosses[index] = row
    return row
end

local CHEST_GROUPS = { "complete", "scenario", "focused" }

local function ThemeBars(owner)
    local view, c = owner.mplus, owner.config
    local barHeight = c.timerBarHeight or 7
    view.bar:SetHeight(barHeight)
    view.barText:SetShown(c.timerBarText == true)
    StyleText(view.barText, owner.font or S.GlobalFontPath(), 11)
    SetText(view.barText, Clock(view.lastElapsed) .. " / " .. Clock(view.limit))
    local width = view.bar:GetWidth()
    if not Finite(width) or width <= 0 then width = math.max(1, (c.width or 310) - 8) end
    for i, tick in ipairs(view.thresholds) do
        tick:ClearAllPoints()
        tick:SetPoint("CENTER", view.bar, "LEFT", width * (i == 1 and .6 or .8), 0)
        tick:SetHeight(barHeight + 4)
        tick:SetShown(c.timerThresholds == true)
    end
    local gap = c.chestSpacing or 22
    local chestY = -81 - barHeight
    for i, row in ipairs(view.chests) do
        row.label:ClearAllPoints()
        row.remaining:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", 4, chestY - (i - 1) * gap)
        row.remaining:SetPoint("TOPRIGHT", -4, chestY - (i - 1) * gap)
    end
    local deathY = chestY - 3 * gap - 4
    local pullSpace = c.showObservedPull and 22 or 0
    for _, spec in ipairs({ { view.deaths, deathY }, { view.affixes, deathY - 22 },
        { view.forces, deathY - 46 }, { view.observedPull, deathY - 88 },
        { view.bossHeader, deathY - 88 - pullSpace } }) do
        spec[1]:ClearAllPoints()
        spec[1]:SetPoint("TOPLEFT", 4, spec[2])
        spec[1]:SetPoint("TOPRIGHT", -4, spec[2])
    end
    view.observedPull:SetShown(c.showObservedPull == true and not view.completed)
    StyleText(view.observedPull, owner.font or S.GlobalFontPath(), 12)
    view.bossY = deathY - 110 - pullSpace
    for i, row in ipairs(view.bosses) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", view.frame, "TOPLEFT", 4, view.bossY - (i - 1) * 21)
        row:SetPoint("TOPRIGHT", view.frame, "TOPRIGHT", -4, view.bossY - (i - 1) * 21)
    end
    view.forces:SetShown(c.showForcesText ~= false)
    view.forcesBar:SetShown(c.showForcesBar ~= false)
    view.forcesBack:SetShown(c.showForcesBar ~= false)
    view.forcesBar:SetHeight(c.forcesBarHeight or 5)
    local inset = 4 + width * (1 - (c.forcesBarWidth or 100) / 100) / 2
    view.forcesBar:ClearAllPoints()
    view.forcesBar:SetPoint("TOPLEFT", inset, deathY - 69)
    view.forcesBar:SetPoint("TOPRIGHT", -inset, deathY - 69)
    StyleText(view.forces, owner.font or S.GlobalFontPath(), c.forcesTextSize or c.objectiveSize or 13)
end

function H.Theme(owner)
    local view = owner.mplus
    if not view then return end
    ThemeBars(owner)
    S.MythicPlusPull.Sync(owner)
    local font, c = owner.font or S.GlobalFontPath(), owner.config
    local text = owner.textRGB or TEXT_RGB
    local muted = owner.mutedRGB or MUTED_RGB
    local accent = owner.groupRGB and owner.groupRGB.scenario or SCENARIO_RGB
    local objectiveSize = c.objectiveSize or 13
    local smallSize = math.max(10, objectiveSize - 1)
    StyleText(view.dungeon, font, c.entrySize or 15)
    StyleText(view.clock, font, math.max(23, (c.titleSize or 18) + 6))
    StyleText(view.remaining, font, objectiveSize)
    StyleText(view.deaths, font, objectiveSize)
    StyleText(view.forces, font, c.forcesTextSize or objectiveSize)
    StyleText(view.affixes, font, smallSize)
    StyleText(view.bossHeader, font, smallSize)
    view.dungeon:SetTextColor(unpack(text))
    view.clock:SetTextColor(unpack(text))
    view.remaining:SetTextColor(unpack(muted))
    view.deaths:SetTextColor(unpack(text))
    view.affixes:SetTextColor(unpack(muted))
    view.forces:SetTextColor(unpack(text))
    view.observedPull:SetTextColor(unpack(muted))
    view.bossHeader:SetTextColor(unpack(accent))
    view.forcesBar:SetStatusBarColor(unpack(accent))
    if view.barBracket then view.bar:SetStatusBarColor(unpack(BracketColor(owner, view.barBracket))) end
    for i = 1, 3 do
        local row = view.chests[i]
        StyleText(row.label, font, objectiveSize)
        StyleText(row.remaining, font, objectiveSize)
        local chestColor = owner.groupRGB and owner.groupRGB[CHEST_GROUPS[i]] or text
        row.label:SetTextColor(unpack(chestColor))
        row.remaining:SetTextColor(unpack(muted))
    end
    for i = 1, #view.bosses do
        local row = view.bosses[i]
        StyleText(row.name, font, smallSize)
        StyleText(row.time, font, smallSize)
        row.name:SetTextColor(unpack(text))
        row.time:SetTextColor(unpack(muted))
    end
end

------------------------------------------------------------------ Blizzard data
-- Blizzard's challenge timer is one of the world elapsed timers.
local function ReadTimerID(view, id, wanted)
    if not Finite(id) then return nil end
    local _, elapsed, timerType = GetWorldElapsedTime(id)
    if Finite(elapsed) and Public(timerType) and timerType == wanted then
        view.timerID = id
        return elapsed
    end
end

local function ScanTimerIDs(view, wanted, ...)
    for i = 1, select("#", ...) do
        local elapsed = ReadTimerID(view, (select(i, ...)), wanted)
        if elapsed then return elapsed end
    end
end

local function ReadTimer(view)
    local wanted = Enum.WorldElapsedTimerTypes.ChallengeMode
    local elapsed = ReadTimerID(view, view.timerID, wanted)
    if elapsed then return elapsed end
    view.timerID = nil
    return ScanTimerIDs(view, wanted, GetWorldElapsedTimers())
end

local function PaintChests(view, limit, elapsed)
    for i = 3, 1, -1 do
        local row = view.chests[4 - i]
        local cutoff = Finite(limit) and limit > 0 and limit * (1 - (i - 1) * .2) or nil
        if not elapsed then
            SetText(row.label, "+" .. i .. "  " .. Clock(cutoff))
            SetText(row.remaining, "--")
        else
            if view.cutoffLimit ~= limit then SetText(row.label, "+" .. i .. "  " .. Clock(cutoff)) end
            local remaining = cutoff - elapsed
            SetText(row.remaining, remaining >= 0 and L.left:format(Clock(remaining)) or L.missed)
        end
    end
end

local function PaintClock(owner, elapsed)
    local view = owner.mplus
    if not view then return end
    local limit = view.limit
    if view.cachedLimit ~= limit then
        view.cachedLimit, view.limitText = limit, Clock(limit)
    end
    SetText(view.clock, Clock(elapsed) .. " / " .. (view.limitText or Clock(limit)))
    SetText(view.barText, Clock(elapsed) .. " / " .. (view.limitText or Clock(limit)))
    if not Finite(limit) or limit <= 0 or not Finite(elapsed) then
        SetText(view.remaining, L.waiting)
        view.bar:SetValue(0)
        PaintChests(view, limit, nil)
        return
    end
    local left = limit - elapsed
    local bracket = left < 0 and 0 or elapsed < limit * .6 and 3 or elapsed < limit * .8 and 2 or 1
    if view.barLimit ~= limit then
        view.bar:SetMinMaxValues(0, limit)
        view.barLimit = limit
    end
    view.bar:SetValue(math.min(limit, elapsed))
    if view.barBracket ~= bracket then
        view.bar:SetStatusBarColor(unpack(BracketColor(owner, bracket)))
        view.barBracket = bracket
    end
    if view.completed then
        local upgrades = view.upgrades
        SetText(view.remaining, upgrades and upgrades > 0 and L.completeUpgrades:format(upgrades) or L.complete)
    else
        SetText(view.remaining, left >= 0 and L.timeLeft:format(Clock(left)) or L.timeOver:format(Clock(-left)))
    end
    PaintChests(view, limit, elapsed)
    view.cutoffLimit = limit
end

function H.UpdateDeaths(owner)
    local view = owner.mplus
    if not view then return end
    local count, lost = C_ChallengeMode.GetDeathCount()
    local countText = Finite(count) and tostring(count) or "--"
    local lostText = Finite(lost) and Clock(lost) or "--:--"
    SetText(view.deaths, L.deaths:format(countText, lostText))
end

local function ReadAffixes(view)
    local challenge = C_ChallengeMode
    local level, affixes = challenge.GetActiveKeystoneInfo()
    view.level = Finite(level) and level or nil
    if not Public(affixes) or type(affixes) ~= "table" then
        SetText(view.affixes, L.affixes:format("--"))
        return
    end
    local names = {}
    for i = 1, math.min(#affixes, 8) do
        local id = affixes[i]
        if Finite(id) then
            local name = Text((challenge.GetAffixInfo(id)))
            if name then names[#names + 1] = name end
        end
    end
    SetText(view.affixes, L.affixes:format(#names > 0 and table.concat(names, " \194\183 ") or "--"))
end

local function ReadMapInfo(view)
    if not Finite(view.mapID) then return end
    local name, _, limit = C_ChallengeMode.GetMapUIInfo(view.mapID)
    if Text(name) then view.name = name end
    if Finite(limit) and limit > 0 then view.limit = limit end
end

local function DungeonTitle(view)
    return (view.name or L.dungeon) .. (view.level and ("  +" .. view.level) or "")
end

-- Weighted criteria are enemy forces; every other named criterion is a boss
-- or objective row with its split time.
-- The character's records (MSUF_Suite/Core/CharacterData.lua) contain only
-- public, completed runs. References stay fixed during a run.
local function BucketKey(view, sameLevel)
    if not Finite(view.mapID) or not Finite(view.level) then return nil end
    return tostring(view.mapID) .. ":" .. (sameLevel and tostring(view.level) or "all")
end

local function RecordBucket(view, sameLevel)
    local key = BucketKey(view, sameLevel)
    local data = key and S.CharacterData("objectives")
    if not data then return nil end
    local records = data.mythicSplits
    if type(records) ~= "table" then
        records = {}
        data.mythicSplits = records
    end
    return records, key, data
end

-- bossPace: 2/3 compare with the best time of each boss, 4/5 with the
-- splits of the fastest whole run; 2/4 at this keystone level, 3/5 at any.
local function Reference(owner, criterion)
    local c, view = owner.config, owner.mplus
    local pace = c.bossPace or 1
    if pace == 1 then return nil end
    local sameLevel = pace == 2 or pace == 4
    local key = BucketKey(view, sameLevel)
    if not key then return nil end
    local cache = view.referenceRecords or {}
    view.referenceRecords = cache
    if cache[key] == nil then
        -- The character's records are read once per bucket and run.
        local records = RecordBucket(view, sameLevel)
        if not records then return nil end
        local stored = records[key]
        local copy = false
        if stored then
            copy = { individual = {}, run = {} }
            for _, kind in ipairs({ "individual", "run" }) do
                for id, value in pairs(stored[kind] or {}) do copy[kind][id] = value end
            end
        end
        cache[key] = copy
    end
    local record = cache[key]
    local splits = record and (pace >= 4 and record.run or record.individual)
    return splits and splits[criterion]
end

local function SaveSplits(owner)
    local view = owner.mplus
    if view.savedSplits or not Finite(view.lastElapsed) or not view.splits or not next(view.splits) then return end
    local info = C_ChallengeMode.GetChallengeCompletionInfo()
    if Field(info, "practiceRun") == true then return end
    for _, sameLevel in ipairs({ true, false }) do
        local records, key, state = RecordBucket(view, sameLevel)
        if records then
            -- At most 160 map/level buckets, with deterministic oldest-write eviction.
            state.mythicSplitSerial = (state.mythicSplitSerial or 0) + 1
            local record = records[key] or { individual = {} }
            record.individual = record.individual or {}
            for criterion, split in pairs(view.splits) do
                local old = record.individual[criterion]
                if not Finite(old) or split < old then record.individual[criterion] = split end
            end
            if not Finite(record.time) or view.lastElapsed < record.time then
                record.time, record.run = view.lastElapsed, {}
                for criterion, split in pairs(view.splits) do record.run[criterion] = split end
            end
            record.serial, records[key] = state.mythicSplitSerial, record
            local count, oldestKey, oldest = 0, nil, math.huge
            for candidate, data in pairs(records) do
                count = count + 1
                local serial = type(data) == "table" and data.serial or 0
                if serial < oldest then oldest, oldestKey = serial, candidate end
            end
            if count > 160 and oldestKey then records[oldestKey] = nil end
        end
    end
    view.savedSplits = true
end

local function PaintCriterion(owner, info, bossCount, elapsed)
    local view = owner.mplus
    if Field(info, "isWeightedProgress") == true then
        -- Blizzard's scenario tracker treats weighted quantity as a percent,
        -- not a count to divide by totalQuantity (live and ptr2).
        local quantity = Field(info, "quantity")
        if Finite(quantity) then
            return bossCount, math.max(0, math.min(100, quantity)), false
        end
        return bossCount, nil, false
    end
    local name = Text(Field(info, "description"))
    if not name then return bossCount, nil, false end
    bossCount = bossCount + 1
    local row, created = view.bosses[bossCount], false
    if not row then
        row = NewBossRow(view, bossCount)
        created = true
    end
    local complete = Field(info, "completed") == true
    local quantity, total = Field(info, "quantity"), Field(info, "totalQuantity")
    local label = name
    if not complete and Finite(quantity) and Finite(total) and total > 1 then
        label = name .. "  " .. quantity .. "/" .. total
    end
    SetText(row.name, (complete and DONE or OPEN) .. label)
    local since = Field(info, "elapsed")
    local split = complete and Finite(since) and Finite(elapsed) and elapsed - since or nil
    local id = Field(info, "criteriaID")
    local criterion = Finite(id) and id > 0 and tostring(id) or name
    view.splits = view.splits or {}
    if Finite(split) and split >= 0 and not view.splits[criterion] then view.splits[criterion] = split end
    split = complete and view.splits[criterion] or nil
    local reference = Reference(owner, criterion)
    local display = Finite(split) and Clock(split) or ""
    if Finite(reference) then
        if Finite(split) then
            local delta = split - reference
            display = display .. "  " .. (delta >= 0 and "+" or "-") .. Clock(math.abs(delta))
        elseif owner.config.bossTargets == true then display = Clock(reference) end
    end
    local compare = (owner.config.bossPace or 1) ~= 1
    row.time:SetWidth(compare and 116 or 55)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", compare and -120 or -57, 0)
    SetText(row.time, display)
    row:Show()
    return bossCount, nil, created
end

function H.UpdateObjectives(owner)
    local view = owner.mplus
    if not view then return end
    local _, _, count = C_Scenario.GetStepInfo()
    if not Finite(count) or count < 0 then return end
    local bossCount, forcesPercent, newRows = 0, nil, false
    for i = 1, math.min(count, 40) do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if Public(info) and type(info) == "table" then
            local forces, created
            bossCount, forces, created = PaintCriterion(owner, info, bossCount, view.lastElapsed)
            forcesPercent = forces or forcesPercent
            newRows = newRows or created
        end
    end
    for i = bossCount + 1, #view.bosses do view.bosses[i]:Hide() end
    view.bossCount = bossCount
    view.forcesPercent = forcesPercent
    if Finite(forcesPercent) then
        SetText(view.forces, L.forces:format(string.format("%.1f%%", forcesPercent)))
        view.forcesBar:SetValue(forcesPercent)
    else
        SetText(view.forces, L.forces:format("--"))
        view.forcesBar:SetValue(0)
    end
    S.MythicPlusPull.Update(owner)
    SetText(view.bossHeader, bossCount > 0 and L.bosses or L.loading)
    view.height = -(view.bossY or -268) + 8 + math.max(1, bossCount) * 21
    view.frame:SetHeight(view.height)
    owner.content:SetHeight(view.height)
    local headerHeight = owner.headerHeight or 41
    owner.host:SetHeight(math.min(owner.config.height, math.max(headerHeight + 5, headerHeight + view.height + 5)))
    if newRows then H.Theme(owner) end
end

function H.Tick(owner)
    local view = owner.mplus
    if not owner.active or not owner.mplusActive or not view or view.completed then return end
    if not view.limit or not view.name then
        local hadLimit = view.limit
        ReadMapInfo(view)
        if view.limit ~= hadLimit then view.lastElapsed = nil end
        SetText(view.dungeon, DungeonTitle(view))
    end
    if not view.level then
        ReadAffixes(view)
        if view.level then
            SetText(view.dungeon, DungeonTitle(view))
            if owner.count then owner.count:SetText("+" .. view.level) end
        end
    end
    local elapsed = ReadTimer(view)
    if Finite(elapsed) and elapsed >= 0 then
        if view.lastElapsed ~= elapsed then
            view.lastElapsed = elapsed
            PaintClock(owner, elapsed)
        end
    elseif view.lastElapsed ~= nil then
        view.lastElapsed = nil
        PaintClock(owner, nil)
    else
        SetText(view.remaining, L.waiting)
    end
end

-- Returns the active keystone's map ID when the M+ view should replace the list.
function H.Detect(owner)
    local challenge = C_ChallengeMode
    if not owner.config.showMythicPlus then return nil end
    local active = challenge.IsChallengeModeActive()
    if not Public(active) or active ~= true then return nil end
    local mapID = challenge.GetActiveChallengeMapID()
    return Finite(mapID) and mapID > 0 and mapID or nil
end

-- The run clock ticks once a second on the owner's context (ctx:Ticker).
local function StopTicker(owner)
    owner.context:Cancel(H.Tick)
end

function H.Start(owner, mapID)
    local view = Create(owner)
    StopTicker(owner)
    S.MythicPlusPull.Stop(owner)
    view.forcesPercent = nil
    view.mapID, view.timerID, view.lastElapsed = mapID, nil, nil
    view.cachedLimit, view.limitText, view.cutoffLimit = nil, nil, nil
    view.barLimit, view.barBracket = nil, nil
    view.completed, view.upgrades, view.bossCount = false, nil, 0
    view.splits, view.savedSplits, view.referenceRecords = {}, nil, {}
    view.limit, view.name = nil, nil
    view.height = 297
    view.frame:SetHeight(view.height)
    for i = 1, #view.bosses do view.bosses[i]:Hide() end
    view.forcesBar:SetValue(0)
    SetText(view.forces, L.forces:format("--"))
    SetText(view.deaths, L.deaths:format("--", "--:--"))
    SetText(view.affixes, L.affixes:format("--"))
    SetText(view.bossHeader, L.loading)
    ReadMapInfo(view)
    ReadAffixes(view)
    SetText(view.dungeon, DungeonTitle(view))
    owner.mplusActive = true
    view.frame:Show()
    H.UpdateDeaths(owner)
    PaintClock(owner, nil)
    H.Tick(owner)
    ThemeBars(owner)
    S.MythicPlusPull.Sync(owner)
    H.UpdateObjectives(owner)
    owner.context:Ticker(1, H.Tick)
end

function H.Complete(owner)
    local view = owner.mplus
    if not view or not owner.mplusActive then return end
    StopTicker(owner)
    view.completed = true
    S.MythicPlusPull.Stop(owner)
    view.observedPull:Hide()
    local info = C_ChallengeMode.GetChallengeCompletionInfo()
    local milliseconds = Field(info, "time")
    local upgrades = Field(info, "keystoneUpgradeLevels")
    if Finite(milliseconds) and milliseconds > 0 then view.lastElapsed = milliseconds / 1000 end
    view.upgrades = Finite(upgrades) and upgrades or nil
    H.UpdateDeaths(owner)
    H.UpdateObjectives(owner)
    PaintClock(owner, view.lastElapsed)
    SaveSplits(owner)
end

function H.Stop(owner)
    local view = owner.mplus
    if not view then return end
    StopTicker(owner)
    S.MythicPlusPull.Stop(owner)
    view.frame:Hide()
    owner.mplusActive = false
end

S.MythicPlus = H
