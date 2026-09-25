local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client or not NS.Client.isMainline or NS.Client.isForever then return end
local H = {}
local FONT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function Public(value) return S.Public(value) end
local function Number(value)
    return Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
local function Text(value)
    return Public(value) and type(value) == "string" and value ~= "" and value or nil
end
local function Field(info, key)
    if not Public(info) or type(info) ~= "table" then return nil end
    local ok, value = pcall(function() return info[key] end)
    return ok and Public(value) and value or nil
end
local function Clock(seconds)
    if not Number(seconds) then return "--:--" end
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(seconds / 3600),
            math.floor(seconds / 60) % 60, seconds % 60)
    end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
local function SetText(widget, value)
    if widget.cachedText ~= value then widget:SetText(value); widget.cachedText = value end
end
local function BracketColor(owner, bracket)
    if bracket == 3 then return owner.completeRGB or { .39, .86, .54 } end
    if bracket == 2 then return owner.groupRGB and owner.groupRGB.scenario or { .39, .64, .90 } end
    if bracket == 1 then return owner.groupRGB and owner.groupRGB.focused or { .98, .84, .42 } end
    return { .92, .36, .36 }
end
local function NewText(parent, size, right)
    local fontString = S.CreateFontString(parent, nil, "OVERLAY")
    S.SetStyledFont(fontString, FONT, size, "OUTLINE", 1, true, 70, 1)
    fontString:SetJustifyH(right and "RIGHT" or "LEFT")
    fontString:SetWordWrap(false)
    return fontString
end

local function Create(owner)
    if owner.mplus then return owner.mplus end
    local panel = S.CreateFrame("Frame", nil, owner.content)
    panel:SetPoint("TOPLEFT", owner.content, "TOPLEFT", 0, 0)
    panel:SetPoint("TOPRIGHT", owner.content, "TOPRIGHT", 0, 0)
    local view = { frame = panel, bosses = {}, height = 282 }
    view.dungeon = NewText(panel, 15)
    view.dungeon:SetPoint("TOPLEFT", 4, -4)
    view.dungeon:SetPoint("TOPRIGHT", -4, -4)
    view.clock = NewText(panel, 25)
    view.clock:SetPoint("TOPLEFT", 4, -30)
    view.remaining = NewText(panel, 13, true)
    view.remaining:SetPoint("TOPRIGHT", -4, -42)
    view.bar = S.CreateFrame("StatusBar", nil, panel)
    view.bar:SetPoint("TOPLEFT", 4, -69)
    view.bar:SetPoint("TOPRIGHT", -4, -69)
    view.bar:SetHeight(7)
    view.bar:SetStatusBarTexture(WHITE)
    view.bar:SetMinMaxValues(0, 1)
    view.bar:SetValue(0)
    view.barBack = S.CreateTexture(panel, nil, "BACKGROUND")
    view.barBack:SetAllPoints(view.bar)
    view.barBack:SetColorTexture(.15, .17, .20, .55)
    view.chests = {}
    for i = 1, 3 do
        local y = -88 - (i - 1) * 22
        local row = { label = NewText(panel, 13), remaining = NewText(panel, 13, true) }
        row.label:SetPoint("TOPLEFT", 4, y)
        row.remaining:SetPoint("TOPRIGHT", -4, y)
        view.chests[i] = row
    end
    view.deaths = NewText(panel, 13)
    view.deaths:SetPoint("TOPLEFT", 4, -158)
    view.deaths:SetPoint("TOPRIGHT", -4, -158)
    view.affixes = NewText(panel, 12)
    view.affixes:SetPoint("TOPLEFT", 4, -180)
    view.affixes:SetPoint("TOPRIGHT", -4, -180)
    view.forces = NewText(panel, 13)
    view.forces:SetPoint("TOPLEFT", 4, -204)
    view.forces:SetPoint("TOPRIGHT", -4, -204)
    view.forcesBar = S.CreateFrame("StatusBar", nil, panel)
    view.forcesBar:SetPoint("TOPLEFT", 4, -227)
    view.forcesBar:SetPoint("TOPRIGHT", -4, -227)
    view.forcesBar:SetHeight(5)
    view.forcesBar:SetStatusBarTexture(WHITE)
    view.forcesBar:SetMinMaxValues(0, 100)
    view.forcesBar:SetValue(0)
    view.forcesBack = S.CreateTexture(panel, nil, "BACKGROUND")
    view.forcesBack:SetAllPoints(view.forcesBar)
    view.forcesBack:SetColorTexture(.15, .17, .20, .55)
    view.bossHeader = NewText(panel, 12)
    view.bossHeader:SetPoint("TOPLEFT", 4, -246)
    panel:Hide()
    owner.mplus = view
    return view
end

local function NewBossRow(view, index)
    local row = S.CreateFrame("Frame", nil, view.frame)
    row:SetHeight(21)
    row:SetPoint("TOPLEFT", view.frame, "TOPLEFT", 4, -268 - (index - 1) * 21)
    row:SetPoint("TOPRIGHT", view.frame, "TOPRIGHT", -4, -268 - (index - 1) * 21)
    row.name = NewText(row, 12)
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -57, 0)
    row.time = NewText(row, 12, true)
    row.time:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.time:SetWidth(55)
    view.bosses[index] = row
    return row
end

function H.Theme(owner)
    local view = owner.mplus
    if not view then return end
    local font, c = owner.font or FONT, owner.config
    local text = owner.textRGB or { .95, .96, .98 }
    local muted = owner.mutedRGB or { .78, .81, .85 }
    local accent = owner.groupRGB and owner.groupRGB.scenario or { .39, .64, .90 }
    S.SetStyledFont(view.dungeon, font, c.entrySize or 15, "OUTLINE", 1, true, 70, 1)
    S.SetStyledFont(view.clock, font, math.max(23, (c.titleSize or 18) + 6), "OUTLINE", 1, true, 70, 1)
    S.SetStyledFont(view.remaining, font, c.objectiveSize or 13, "OUTLINE", 1, true, 70, 1)
    S.SetStyledFont(view.deaths, font, c.objectiveSize or 13, "OUTLINE", 1, true, 70, 1)
    S.SetStyledFont(view.forces, font, c.objectiveSize or 13, "OUTLINE", 1, true, 70, 1)
    S.SetStyledFont(view.affixes, font, math.max(10, (c.objectiveSize or 13) - 1), "OUTLINE", 1, true, 70, 1)
    S.SetStyledFont(view.bossHeader, font, math.max(10, (c.objectiveSize or 13) - 1), "OUTLINE", 1, true, 70, 1)
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
        local chest = 4 - i
        S.SetStyledFont(row.label, font, c.objectiveSize or 13, "OUTLINE", 1, true, 70, 1)
        S.SetStyledFont(row.remaining, font, c.objectiveSize or 13, "OUTLINE", 1, true, 70, 1)
        local chestColor = owner.groupRGB and owner.groupRGB[chest == 3 and "complete"
            or chest == 2 and "scenario" or "focused"] or text
        row.label:SetTextColor(unpack(chestColor))
        row.remaining:SetTextColor(unpack(muted))
    end
    for i = 1, #view.bosses do
        local row = view.bosses[i]
        S.SetStyledFont(row.name, font, math.max(10, (c.objectiveSize or 13) - 1), "OUTLINE", 1, true, 70, 1)
        S.SetStyledFont(row.time, font, math.max(10, (c.objectiveSize or 13) - 1), "OUTLINE", 1, true, 70, 1)
        row.name:SetTextColor(unpack(text))
        row.time:SetTextColor(unpack(muted))
    end
end

local function ReadTimerID(view, id, wanted)
    if not Number(id) then return nil end
    local ok, _, elapsed, timerType = pcall(_G.GetWorldElapsedTime, id)
    if ok and Number(elapsed) and Public(timerType) and timerType == wanted then
        view.timerID = id
        return elapsed
    end
end
local function ScanTimerIDs(view, wanted, ok, ...)
    if not ok then return nil end
    for i = 1, select("#", ...) do
        local elapsed = ReadTimerID(view, select(i, ...), wanted)
        if elapsed then return elapsed end
    end
end
local function ReadTimer(view)
    if type(_G.GetWorldElapsedTime) ~= "function" then return nil end
    local wanted = Enum and Enum.WorldElapsedTimerTypes and Enum.WorldElapsedTimerTypes.ChallengeMode
    local elapsed = ReadTimerID(view, view.timerID, wanted)
    if elapsed then return elapsed end
    view.timerID = nil
    if type(_G.GetWorldElapsedTimers) ~= "function" then return nil end
    return ScanTimerIDs(view, wanted, pcall(_G.GetWorldElapsedTimers))
end

local function PaintClock(owner, elapsed)
    local view = owner.mplus
    if not view then return end
    local limit = view.limit
    if view.cachedLimit ~= limit then
        view.cachedLimit, view.limitText = limit, Clock(limit)
    end
    SetText(view.clock, Clock(elapsed) .. " / " .. (view.limitText or Clock(limit)))
    if not Number(limit) or limit <= 0 or not Number(elapsed) then
        SetText(view.remaining, "WAITING FOR TIMER")
        view.bar:SetValue(0)
        for i = 3, 1, -1 do
            local row = view.chests[4 - i]
            local cutoff = Number(limit) and limit > 0 and limit * (1 - (i - 1) * .2) or nil
            SetText(row.label, "+" .. i .. "  " .. Clock(cutoff))
            SetText(row.remaining, "--")
        end
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
    for i = 3, 1, -1 do
        local row = view.chests[4 - i]
        local cutoff = limit * (1 - (i - 1) * .2)
        if view.cutoffLimit ~= limit then SetText(row.label, "+" .. i .. "  " .. Clock(cutoff)) end
        local remaining = cutoff - elapsed
        SetText(row.remaining, remaining >= 0 and (Clock(remaining) .. " left") or "missed")
    end
    view.cutoffLimit = limit
end

function H.UpdateDeaths(owner)
    local view = owner.mplus
    if not view or type(C_ChallengeMode) ~= "table" or type(C_ChallengeMode.GetDeathCount) ~= "function" then return end
    local ok, count, lost = pcall(C_ChallengeMode.GetDeathCount)
    if not ok then return end
    local countText = Number(count) and tostring(count) or "--"
    local lostText = Number(lost) and Clock(lost) or "--:--"
    SetText(view.deaths, "DEATHS  " .. countText .. "     TIME PENALTY  +" .. lostText)
end

local function ReadAffixes(view)
    local challenge = C_ChallengeMode
    if type(challenge) ~= "table" or type(challenge.GetActiveKeystoneInfo) ~= "function" then return end
    local ok, level, affixes = pcall(challenge.GetActiveKeystoneInfo)
    view.level = ok and Number(level) and level or nil
    if not ok or not Public(affixes) or type(affixes) ~= "table"
        or type(challenge.GetAffixInfo) ~= "function" then
        SetText(view.affixes, "AFFIXES  --")
        return
    end
    local names = {}
    for i = 1, math.min(#affixes, 8) do
        local id = affixes[i]
        if Number(id) then
            local good, name = pcall(challenge.GetAffixInfo, id)
            if good and Text(name) then names[#names + 1] = name end
        end
    end
    SetText(view.affixes, #names > 0 and ("AFFIXES  " .. table.concat(names, " · ")) or "AFFIXES  --")
end

local function ReadMapInfo(view)
    local challenge = C_ChallengeMode
    if type(challenge) ~= "table" or type(challenge.GetMapUIInfo) ~= "function" then return end
    local ok, name, _, limit = pcall(challenge.GetMapUIInfo, view.mapID)
    if not ok then return end
    if Text(name) then view.name = name end
    if Number(limit) and limit > 0 then view.limit = limit end
end

function H.UpdateObjectives(owner)
    local view = owner.mplus
    if not view or type(C_Scenario) ~= "table" or type(C_Scenario.GetStepInfo) ~= "function"
        or type(C_ScenarioInfo) ~= "table" or type(C_ScenarioInfo.GetCriteriaInfo) ~= "function" then return end
    local ok, _, _, count = pcall(C_Scenario.GetStepInfo)
    if not ok or not Number(count) or count < 0 then return end
    local bossCount, forcesPercent, newRows = 0, nil, false
    local elapsed = view.lastElapsed
    for i = 1, math.min(count, 40) do
        local good, info = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
        if good and Public(info) and type(info) == "table" then
            local weighted = Field(info, "isWeightedProgress") == true
            if weighted then
                local quantity, total = Field(info, "quantity"), Field(info, "totalQuantity")
                if Number(quantity) and Number(total) and total > 0 then
                    forcesPercent = math.max(0, math.min(100, quantity / total * 100))
                end
            else
                local name = Text(Field(info, "description"))
                if name then
                    bossCount = bossCount + 1
                    local row = view.bosses[bossCount]
                    if not row then row = NewBossRow(view, bossCount); newRows = true end
                    local complete = Field(info, "completed") == true
                    local quantity, total = Field(info, "quantity"), Field(info, "totalQuantity")
                    local label = name
                    if not complete and Number(quantity) and Number(total) and total > 1 then
                        label = name .. "  " .. quantity .. "/" .. total
                    end
                    SetText(row.name, (complete and "✓  " or "·  ") .. label)
                    local since = Field(info, "elapsed")
                    local split = complete and Number(since) and Number(elapsed) and elapsed - since or nil
                    SetText(row.time, Number(split) and split >= 0 and Clock(split) or "")
                    row:Show()
                end
            end
        end
    end
    for i = bossCount + 1, #view.bosses do view.bosses[i]:Hide() end
    view.bossCount = bossCount
    if Number(forcesPercent) then
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
    owner.host:SetHeight(math.min(owner.config.height,
        math.max(headerHeight + 5, headerHeight + view.height + 5)))
    if newRows then H.Theme(owner) end
end

function H.Tick(owner)
    local view = owner.mplus
    if not owner.active or not owner.mplusActive or not view or view.completed then return end
    if not view.limit or not view.name then
        local hadLimit = view.limit
        ReadMapInfo(view)
        if view.limit ~= hadLimit then view.lastElapsed = nil end
        SetText(view.dungeon, (view.name or "MYTHIC+ DUNGEON")
            .. (view.level and ("  +" .. view.level) or ""))
    end
    if not view.level then
        ReadAffixes(view)
        if view.level then
            SetText(view.dungeon, (view.name or "MYTHIC+ DUNGEON") .. "  +" .. view.level)
            if owner.count then owner.count:SetText("+" .. view.level) end
        end
    end
    local elapsed = ReadTimer(view)
    if Number(elapsed) and elapsed >= 0 then
        if view.lastElapsed ~= elapsed then
            view.lastElapsed = elapsed
            PaintClock(owner, elapsed)
        end
    else
        if view.lastElapsed ~= nil then
            view.lastElapsed = nil
            PaintClock(owner, nil)
        else
            SetText(view.remaining, "WAITING FOR TIMER")
        end
    end
end

function H.Detect(owner)
    if not owner.config.showMythicPlus or type(C_ChallengeMode) ~= "table"
        or type(C_ChallengeMode.IsChallengeModeActive) ~= "function"
        or type(C_ChallengeMode.GetActiveChallengeMapID) ~= "function" then return nil end
    local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
    if not ok or not Public(active) or active ~= true then return nil end
    local good, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
    return good and Number(mapID) and mapID > 0 and mapID or nil
end

function H.Start(owner, mapID)
    local view = Create(owner)
    if view.ticker and view.ticker.Cancel then view.ticker:Cancel() end
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
    SetText(view.dungeon, (view.name or "MYTHIC+ DUNGEON")
        .. (view.level and ("  +" .. view.level) or ""))
    owner.mplusActive = true
    view.frame:Show()
    H.UpdateDeaths(owner)
    PaintClock(owner, nil)
    H.Tick(owner)
    H.UpdateObjectives(owner)
    SetText(view.bossHeader, view.bossCount > 0 and "BOSSES / OBJECTIVES" or "OBJECTIVES LOADING")
    if C_Timer and type(C_Timer.NewTicker) == "function" then
        view.ticker = C_Timer.NewTicker(1, function() H.Tick(owner) end)
    end
end

function H.Complete(owner)
    local view = owner.mplus
    if not view or not owner.mplusActive then return end
    if view.ticker and view.ticker.Cancel then view.ticker:Cancel() end
    view.ticker, view.completed = nil, true
    local challenge = C_ChallengeMode
    if challenge and type(challenge.GetChallengeCompletionInfo) == "function" then
        local ok, info = pcall(challenge.GetChallengeCompletionInfo)
        if ok then
            local milliseconds = Field(info, "time")
            local upgrades = Field(info, "keystoneUpgradeLevels")
            if Number(milliseconds) and milliseconds > 0 then view.lastElapsed = milliseconds / 1000 end
            view.upgrades = Number(upgrades) and upgrades or nil
        end
    end
    H.UpdateDeaths(owner)
    H.UpdateObjectives(owner)
    PaintClock(owner, view.lastElapsed)
end

function H.Stop(owner)
    local view = owner.mplus
    if not view then return end
    if view.ticker and view.ticker.Cancel then view.ticker:Cancel() end
    view.ticker = nil
    view.frame:Hide()
    owner.mplusActive = false
end

S.MythicPlus = H
