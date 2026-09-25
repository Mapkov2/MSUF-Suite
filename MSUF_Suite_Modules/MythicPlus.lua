local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client or not NS.Client.isMainline or NS.Client.isForever then return end

-- The Mythic+ view replaces the objective list while a keystone runs. The
-- objectives module owns the frame and calls these helpers from its events;
-- the clock ticks once per second only while a run is active.
local H = {}
local FONT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local TEXT_RGB, MUTED_RGB = { .95, .96, .98 }, { .78, .81, .85 }
local COMPLETE_RGB, SCENARIO_RGB, FOCUSED_RGB, LATE_RGB = { .39, .86, .54 }, { .39, .64, .90 }, { .98, .84, .42 },
    { .92, .36, .36 }

local function Public(value)
    return S.Public(value)
end

local Finite = S.Finite

local function Text(value)
    return Public(value) and type(value) == "string" and value ~= "" and value or nil
end

-- Criteria and completion info are plain tables whose fields may be secret.
local function Field(info, key)
    if not Public(info) or type(info) ~= "table" then return nil end
    local value = info[key]
    return Public(value) and value or nil
end

local function Clock(seconds)
    if not Finite(seconds) then return "--:--" end
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

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
    StyleText(fontString, FONT, size)
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
    view.tick = function() H.Tick(owner) end
    view.dungeon = NewLine(panel, 15, -4)
    view.clock = NewText(panel, 25)
    view.clock:SetPoint("TOPLEFT", 4, -30)
    view.remaining = NewText(panel, 13, true)
    view.remaining:SetPoint("TOPRIGHT", -4, -42)
    view.bar, view.barBack = NewBar(panel, -69, 7, 1)
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
    view.bossHeader = NewText(panel, 12)
    view.bossHeader:SetPoint("TOPLEFT", 4, -246)
    panel:Hide()
    owner.mplus = view
    return view
end

local function NewBossRow(view, index)
    local row = S.CreateFrame("Frame", nil, view.frame)
    local y = -268 - (index - 1) * 21
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

function H.Theme(owner)
    local view = owner.mplus
    if not view then return end
    local font, c = owner.font or FONT, owner.config
    local text = owner.textRGB or TEXT_RGB
    local muted = owner.mutedRGB or MUTED_RGB
    local accent = owner.groupRGB and owner.groupRGB.scenario or SCENARIO_RGB
    local objectiveSize = c.objectiveSize or 13
    local smallSize = math.max(10, objectiveSize - 1)
    StyleText(view.dungeon, font, c.entrySize or 15)
    StyleText(view.clock, font, math.max(23, (c.titleSize or 18) + 6))
    StyleText(view.remaining, font, objectiveSize)
    StyleText(view.deaths, font, objectiveSize)
    StyleText(view.forces, font, objectiveSize)
    StyleText(view.affixes, font, smallSize)
    StyleText(view.bossHeader, font, smallSize)
    view.dungeon:SetTextColor(unpack(text))
    view.clock:SetTextColor(unpack(text))
    view.remaining:SetTextColor(unpack(muted))
    view.deaths:SetTextColor(unpack(text))
    view.affixes:SetTextColor(unpack(muted))
    view.forces:SetTextColor(unpack(text))
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
    if type(GetWorldElapsedTime) ~= "function" then return nil end
    local wanted = Enum and Enum.WorldElapsedTimerTypes and Enum.WorldElapsedTimerTypes.ChallengeMode
    local elapsed = ReadTimerID(view, view.timerID, wanted)
    if elapsed then return elapsed end
    view.timerID = nil
    if type(GetWorldElapsedTimers) ~= "function" then return nil end
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
            SetText(row.remaining, remaining >= 0 and (Clock(remaining) .. " left") or "missed")
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
    if not Finite(limit) or limit <= 0 or not Finite(elapsed) then
        SetText(view.remaining, "WAITING FOR TIMER")
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
        SetText(view.remaining, upgrades and upgrades > 0 and ("COMPLETE  +" .. upgrades) or "COMPLETE")
    else
        SetText(view.remaining, left >= 0 and (Clock(left) .. " LEFT") or (Clock(-left) .. " OVER"))
    end
    PaintChests(view, limit, elapsed)
    view.cutoffLimit = limit
end

function H.UpdateDeaths(owner)
    local view = owner.mplus
    if not view or type(C_ChallengeMode) ~= "table" or type(C_ChallengeMode.GetDeathCount) ~= "function" then
        return
    end
    local count, lost = C_ChallengeMode.GetDeathCount()
    local countText = Finite(count) and tostring(count) or "--"
    local lostText = Finite(lost) and Clock(lost) or "--:--"
    SetText(view.deaths, "DEATHS  " .. countText .. "     TIME PENALTY  +" .. lostText)
end

local function ReadAffixes(view)
    local challenge = C_ChallengeMode
    if type(challenge) ~= "table" or type(challenge.GetActiveKeystoneInfo) ~= "function" then return end
    local level, affixes = challenge.GetActiveKeystoneInfo()
    view.level = Finite(level) and level or nil
    if not Public(affixes) or type(affixes) ~= "table" or type(challenge.GetAffixInfo) ~= "function" then
        SetText(view.affixes, "AFFIXES  --")
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
    SetText(view.affixes, #names > 0 and ("AFFIXES  " .. table.concat(names, " · ")) or "AFFIXES  --")
end

local function ReadMapInfo(view)
    local challenge = C_ChallengeMode
    if type(challenge) ~= "table" or type(challenge.GetMapUIInfo) ~= "function" or not Finite(view.mapID) then
        return
    end
    local name, _, limit = challenge.GetMapUIInfo(view.mapID)
    if Text(name) then view.name = name end
    if Finite(limit) and limit > 0 then view.limit = limit end
end

local function DungeonTitle(view)
    return (view.name or "MYTHIC+ DUNGEON") .. (view.level and ("  +" .. view.level) or "")
end

-- Weighted criteria are enemy forces; every other named criterion is a boss
-- or objective row with its split time.
local function PaintCriterion(view, info, bossCount, elapsed)
    if Field(info, "isWeightedProgress") == true then
        local quantity, total = Field(info, "quantity"), Field(info, "totalQuantity")
        if Finite(quantity) and Finite(total) and total > 0 then
            return bossCount, math.max(0, math.min(100, quantity / total * 100)), false
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
    SetText(row.name, (complete and "✓  " or "·  ") .. label)
    local since = Field(info, "elapsed")
    local split = complete and Finite(since) and Finite(elapsed) and elapsed - since or nil
    SetText(row.time, Finite(split) and split >= 0 and Clock(split) or "")
    row:Show()
    return bossCount, nil, created
end

function H.UpdateObjectives(owner)
    local view = owner.mplus
    if not view or type(C_Scenario) ~= "table" or type(C_Scenario.GetStepInfo) ~= "function"
        or type(C_ScenarioInfo) ~= "table" or type(C_ScenarioInfo.GetCriteriaInfo) ~= "function" then
        return
    end
    local _, _, count = C_Scenario.GetStepInfo()
    if not Finite(count) or count < 0 then return end
    local bossCount, forcesPercent, newRows = 0, nil, false
    for i = 1, math.min(count, 40) do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if Public(info) and type(info) == "table" then
            local forces, created
            bossCount, forces, created = PaintCriterion(view, info, bossCount, view.lastElapsed)
            forcesPercent = forces or forcesPercent
            newRows = newRows or created
        end
    end
    for i = bossCount + 1, #view.bosses do view.bosses[i]:Hide() end
    view.bossCount = bossCount
    if Finite(forcesPercent) then
        SetText(view.forces, "ENEMY FORCES  " .. string.format("%.1f%%", forcesPercent))
        view.forcesBar:SetValue(forcesPercent)
    else
        SetText(view.forces, "ENEMY FORCES  --")
        view.forcesBar:SetValue(0)
    end
    SetText(view.bossHeader, bossCount > 0 and "BOSSES / OBJECTIVES" or "OBJECTIVES LOADING")
    view.height = 276 + math.max(1, bossCount) * 21
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
        SetText(view.remaining, "WAITING FOR TIMER")
    end
end

-- Returns the active keystone's map ID when the M+ view should replace the list.
function H.Detect(owner)
    local challenge = C_ChallengeMode
    if not owner.config.showMythicPlus or type(challenge) ~= "table"
        or type(challenge.IsChallengeModeActive) ~= "function"
        or type(challenge.GetActiveChallengeMapID) ~= "function" then
        return nil
    end
    local active = challenge.IsChallengeModeActive()
    if not Public(active) or active ~= true then return nil end
    local mapID = challenge.GetActiveChallengeMapID()
    return Finite(mapID) and mapID > 0 and mapID or nil
end

local function StopTicker(view)
    if view.ticker then view.ticker:Cancel() end
    view.ticker = nil
end

function H.Start(owner, mapID)
    local view = Create(owner)
    StopTicker(view)
    view.mapID, view.timerID, view.lastElapsed = mapID, nil, nil
    view.cachedLimit, view.limitText, view.cutoffLimit = nil, nil, nil
    view.barLimit, view.barBracket = nil, nil
    view.completed, view.upgrades, view.bossCount = false, nil, 0
    view.limit, view.name = nil, nil
    view.height = 297
    view.frame:SetHeight(view.height)
    for i = 1, #view.bosses do view.bosses[i]:Hide() end
    view.forcesBar:SetValue(0)
    SetText(view.forces, "ENEMY FORCES  --")
    SetText(view.deaths, "DEATHS  --     TIME PENALTY  +--:--")
    SetText(view.affixes, "AFFIXES  --")
    SetText(view.bossHeader, "OBJECTIVES LOADING")
    ReadMapInfo(view)
    ReadAffixes(view)
    SetText(view.dungeon, DungeonTitle(view))
    owner.mplusActive = true
    view.frame:Show()
    H.UpdateDeaths(owner)
    PaintClock(owner, nil)
    H.Tick(owner)
    H.UpdateObjectives(owner)
    if C_Timer and type(C_Timer.NewTicker) == "function" then view.ticker = C_Timer.NewTicker(1, view.tick) end
end

function H.Complete(owner)
    local view = owner.mplus
    if not view or not owner.mplusActive then return end
    StopTicker(view)
    view.completed = true
    local challenge = C_ChallengeMode
    if challenge and type(challenge.GetChallengeCompletionInfo) == "function" then
        local info = challenge.GetChallengeCompletionInfo()
        local milliseconds = Field(info, "time")
        local upgrades = Field(info, "keystoneUpgradeLevels")
        if Finite(milliseconds) and milliseconds > 0 then view.lastElapsed = milliseconds / 1000 end
        view.upgrades = Finite(upgrades) and upgrades or nil
    end
    H.UpdateDeaths(owner)
    H.UpdateObjectives(owner)
    PaintClock(owner, view.lastElapsed)
end

function H.Stop(owner)
    local view = owner.mplus
    if not view then return end
    StopTicker(view)
    view.frame:Hide()
    owner.mplusActive = false
end

S.MythicPlus = H
