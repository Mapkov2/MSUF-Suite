local _, P = ...
local NS, S = P.NS, P.Suite
local ID = "runSummary"
local Public, Finite, Text = S.Public, S.Finite, S.PublicText
local Field, Clock = S.PublicField, S.ClockText
local Party = P.RunSummaryParty
local Tr = S.Text
local IN_COMBAT = { inCombat = true }
local M = {}
local DOT = "  \194\183  "
-- A first click on "Delete run" arms it for this many seconds.
local DELETE_WINDOW = 4

-- The runs, splits and raid records of the current character
-- (MSUF_Suite/Core/CharacterData.lua); nil while the character is unknown.
local function Data()
    return S.CharacterData(ID)
end

local function Disarm(self)
    local button = self.historyButtons[3]
    self.context:Cancel(Disarm)
    if not button.armed then return end
    button.armed = nil
    button.label:SetText(Tr("Delete run"))
end

-- Each arm keeps its whole window (ctx:After); deleting ends it.
local function DeleteClicked(self, button)
    if button.armed then
        Disarm(self)
        self:DeleteCurrent()
        return
    end
    button.armed = true
    button.label:SetText(Tr("Click again to delete"))
    self.context:After(DELETE_WINDOW, Disarm)
end

local function CreateHistoryButtons(self, host)
    self.historyButtons = {}
    for index, spec in ipairs({ { "Previous run", -1 }, { "Next run", 1 }, { "Delete run", 0 } }) do
        local button = S.CreateFrame("Button", nil, host)
        button:SetSize(110, 26)
        button:SetPoint("BOTTOMLEFT", 14 + (index - 1) * 115, 8)
        local label = S.CreateFontString(button, nil, "OVERLAY")
        label:SetPoint("CENTER", 0, 0)
        S.SetStyledFont(label, S.GlobalFontPath(), 12, "OUTLINE", 1, true, 70, 1)
        label:SetText(Tr(spec[1]))
        button.label = label
        button:SetScript("OnClick", function()
            if spec[2] == 0 then DeleteClicked(self, button) else self:Browse(spec[2]) end
        end)
        button:Hide()
        self.historyButtons[index] = button
    end
end

local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", "MSUFSuiteRunSummary", UIParent)
    host:SetFrameStrata("DIALOG")
    host:SetSize(390, 240)
    host:EnableMouse(true)
    local background = S.CreateTexture(host, nil, "BACKGROUND")
    background:SetAllPoints(host)
    local accent = S.CreateTexture(host, nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("TOPRIGHT", 0, 0)
    accent:SetHeight(3)
    local title = S.CreateFontString(host, nil, "OVERLAY")
    title:SetPoint("TOPLEFT", 18, -17)
    title:SetPoint("TOPRIGHT", -44, -17)
    title:SetJustifyH("LEFT")
    local subtitle = S.CreateFontString(host, nil, "OVERLAY")
    subtitle:SetPoint("TOPLEFT", 18, -51)
    subtitle:SetPoint("TOPRIGHT", -18, -51)
    subtitle:SetJustifyH("LEFT")
    local close = S.CreateFrame("Button", nil, host)
    close:SetSize(28, 28)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:RegisterForClicks("LeftButtonUp")
    close:SetScript("OnClick", function() self:Close() end)
    local closeText = S.CreateFontString(close, nil, "OVERLAY")
    closeText:SetPoint("CENTER", 0, 0)
    self.host, self.background, self.accent = host, background, accent
    self.title, self.subtitle, self.closeText = title, subtitle, closeText
    self.rows = {}
    for i = 1, 7 do
        local label = S.CreateFontString(host, nil, "OVERLAY")
        label:SetJustifyH("LEFT")
        label:SetWordWrap(true)
        local value = S.CreateFontString(host, nil, "OVERLAY")
        value:SetJustifyH("RIGHT")
        value:SetWordWrap(true)
        self.rows[i] = { label = label, value = value }
    end
    CreateHistoryButtons(self, host)
    host:Hide()
end

local function Add(rows, label, value)
    if value ~= nil and #rows < 7 then rows[#rows + 1] = { label, tostring(value) } end
end

local function MythicRows(c, result, rows)
    if c.showDuration then Add(rows, Tr("Run time"), Clock(result.time)) end
    if c.showTimer then
        local value = result.onTime == true and Tr("In time")
            or result.onTime == false and Tr("Over time") or Tr("Unknown")
        if Finite(result.limit) and Finite(result.time) then
            local delta = result.limit - result.time
            value = value .. DOT .. (delta >= 0 and "-" or "+") .. Clock(math.abs(delta))
        end
        Add(rows, Tr("Timer"), value)
    end
    if c.showDeaths then Add(rows, Tr("Deaths"), Finite(result.deaths) and result.deaths or "--") end
    if c.showPenalty then
        Add(rows, Tr("Time penalty"), Finite(result.penalty) and ("+" .. Clock(result.penalty)) or "--")
    end
    if c.showUpgrades then
        Add(rows, Tr("Keystone"), Finite(result.upgrades) and result.upgrades > 0
            and Tr("+%d upgrades"):format(result.upgrades) or Tr("No upgrade"))
    end
    if c.showScore and Finite(result.scoreDelta) then
        Add(rows, Tr("Rating"), string.format("%+.0f", result.scoreDelta))
    end
    if c.showRecord and result.record then Add(rows, Tr("Record"), Tr("New dungeon record")) end
end

local function Rows(self, result)
    local c, rows = self.config, {}
    if result.kind == "mythic" then
        MythicRows(c, result, rows)
    else
        if c.showDuration then Add(rows, Tr("Kill time"), Clock(result.time)) end
        if c.showBest then
            Add(rows, Tr("Fastest kill"), Clock(result.best) .. (result.newBest and (DOT .. Tr("New best")) or ""))
        end
        if c.showGroupSize then Add(rows, Tr("Group size"), Finite(result.groupSize) and result.groupSize or "--") end
        if c.showKills and Finite(result.kills) then Add(rows, Tr("Kills recorded"), result.kills) end
    end
    return rows
end

local function Colors(self)
    local c = self.config
    local skin = self.context and self.context:Skin()
    local colors = { title = { .96, .97, .99 }, text = { .88, .92, .97 }, accent = { .39, .86, .54 },
        back = { .05, .07, .10 } }
    if c.colorStyle == 2 then
        colors.title, colors.text = { S.RGB(c.titleColor) }, { S.RGB(c.textColor) }
        colors.accent, colors.back = { S.RGB(c.accentColor) }, { S.RGB(c.backgroundColor) }
    elseif skin then
        colors.back, colors.text = { skin:GetColor("surface") }, { skin:GetColor("text") }
    end
    return colors
end

local function PaintRows(self, rows, font, width, colors)
    local c, y = self.config, -91
    for i = 1, #self.rows do
        local row, data = self.rows[i], rows[i]
        if data then
            row.label:ClearAllPoints()
            row.label:SetPoint("TOPLEFT", 18, y)
            row.label:SetWidth(math.floor(math.max(95, math.min(142, width * .38))))
            row.value:ClearAllPoints()
            row.value:SetPoint("TOPLEFT", row.label, "TOPRIGHT", 8, 0)
            row.value:SetPoint("TOPRIGHT", self.host, "TOPRIGHT", -18, y)
            S.SetStyledFont(row.label, font, c.detailSize or 14, "OUTLINE", 1, true, 70, 1)
            S.SetStyledFont(row.value, font, c.detailSize or 14, "OUTLINE", 1, true, 70, 1)
            row.label:SetText(data[1])
            row.value:SetText(data[2])
            row.label:SetTextColor(unpack(colors.text))
            row.value:SetTextColor(unpack(colors.title))
            row.label:Show()
            row.value:Show()
            local labelHeight = row.label.GetStringHeight and row.label:GetStringHeight() or 0
            local valueHeight = row.value.GetStringHeight and row.value:GetStringHeight() or 0
            y = y - math.max(27, math.ceil(math.max(labelHeight, valueHeight)) + 6)
        else
            row.label:Hide()
            row.value:Hide()
        end
    end
    return y
end

local function Paint(self, result)
    local c = self.config
    local font = S.ResolveFont(c.font) or S.GlobalFontPath()
    local colors = Colors(self)
    self.background:SetColorTexture(colors.back[1], colors.back[2], colors.back[3], (c.backgroundOpacity or 92) / 100)
    self.accent:SetColorTexture(colors.accent[1], colors.accent[2], colors.accent[3], 1)
    S.SetStyledFont(self.title, font, c.titleSize or 20, "OUTLINE", 1, true, 80, 1)
    S.SetStyledFont(self.subtitle, font, c.detailSize or 14, "OUTLINE", 1, true, 75, 1)
    S.SetStyledFont(self.closeText, font, 18, "OUTLINE", 1, true, 70, 1)
    self.title:SetText(result.kind == "raid" and Tr("RAID BOSS DEFEATED") or Tr("MYTHIC+ COMPLETE"))
    self.title:SetTextColor(unpack(colors.title))
    self.subtitle:SetText(result.subtitle or "")
    self.subtitle:SetTextColor(unpack(colors.accent))
    self.closeText:SetText("\195\151")
    self.closeText:SetTextColor(unpack(colors.text))
    local width = c.width or 390
    self.host:SetSize(width, 240)
    local y = PaintRows(self, Rows(self, result), font, width, colors)
    local tableWidth
    local style = { font = font, size = math.min(13, c.detailSize or 14),
        r = colors.text[1], g = colors.text[2], b = colors.text[3] }
    y, tableWidth = Party.Paint(self, result, y - 6, style)
    self.host:SetWidth(math.max(width, tableWidth))
    local history = result.kind == "mythic" and result.historyID ~= nil
    for _, button in ipairs(self.historyButtons) do
        if history then button:Show() else button:Hide() end
    end
    self.host:SetHeight(-y + (history and 46 or 12))
    self.host:SetScale((c.scale or 100) / 100)
    local point = NS.AnchorPoints[c.point] or "CENTER"
    self.host:ClearAllPoints()
    self.host:SetPoint(point, UIParent, point, c.x or 0, c.y or 0)
end

local PREVIEW_MPLUS = { kind = "mythic", time = 1422,
    limit = 1800, onTime = true, deaths = 2, penalty = 10, upgrades = 2, scoreDelta = 18 }
local PREVIEW_RAID = { kind = "raid", time = 274,
    best = 274, newBest = true, groupSize = 20, kills = 1 }

-- Sample rows use the real table painter and never enter saved run history.
local function PreviewResult(kind)
    PREVIEW_MPLUS.subtitle = Tr("Example Dungeon  +%d"):format(15)
    PREVIEW_RAID.subtitle = Tr("Example Boss") .. DOT .. Tr("Mythic")
    local result = kind == "raid" and PREVIEW_RAID or PREVIEW_MPLUS
    if result == PREVIEW_MPLUS and not result.players then
        result.players = {}
        for i = 1, 5 do
            result.players[i] = {
                name = Tr("Player %d"):format(i), spec = "\226\128\148", ilvl = 220 + i,
                rating = 2100 + i * 35, scoreDelta = 18,
                damage = 1422 * (58000 - i * 6000), damagePerRunSecond = 58000 - i * 6000,
                damageTaken = 2400000 + i * 320000, interrupts = 14 - i * 2,
                deaths = i == 3 and 2 or 0,
                loot = { "|TInterface\\Icons\\INV_Misc_QuestionMark:18|t" },
            }
        end
    end
    return result
end

local function AutoClose(self)
    if not S.editMode then self:Close() end
end

local function Show(self, result, automatic)
    if not self.active or not result then return end
    if NS.IsCombatLocked() then
        if automatic then
            self.current, self.pending, self.visible = result, result, false
            self.host:Hide()
        end
        return
    end
    self.current, self.visible = result, true
    self.pending = nil
    Paint(self, result)
    self.host:Show()
    -- An automatic card closes after config.autoHide seconds; any other show
    -- or a close ends that wait.
    local duration = self.config.autoHide or 0
    if automatic and duration > 0 then
        self.context:After(duration, AutoClose)
    else
        self.context:Cancel(AutoClose)
    end
end

function M:Close()
    self.context:Cancel(AutoClose)
    self.visible, self.pending = false, nil
    if self.host then self.host:Hide() end
end

function M:Preview(kind)
    Show(self, PreviewResult(kind), false)
end

-- The character's runs, newest first, bounded by keepRuns. Reward events
-- replace the same entry.
local function History(self)
    local data = Data()
    if not data then return nil end
    if type(data.history) ~= "table" then data.history = {} end
    local limit = math.max(1, math.min(100, self.config.keepRuns or 30))
    while #data.history > limit do table.remove(data.history) end
    return data.history, data
end

-- The last result: a raid kill is stored as such, a Mythic+ run is the
-- newest history entry (never a second copy of it).
function M:ShowLast()
    local data = Data()
    if not data then return end
    if data.lastKind == "raid" then
        Show(self, data.lastRaid, false)
    elseif data.lastKind == "mythic" then
        local history = History(self)
        Show(self, history and history[1], false)
    end
end

function M:Browse(direction)
    local history = History(self)
    if not history or #history == 0 then return end
    local index = 1
    for i, result in ipairs(history) do
        if self.current and result.historyID == self.current.historyID then
            index = i
            break
        end
    end
    -- Previous means older; Next means newer.
    index = math.max(1, math.min(#history, index - (direction or 0)))
    Show(self, history[index], false)
end

function M:ShowHistory()
    local history = History(self)
    if history and history[1] then Show(self, history[1], false) end
end

function M:DeleteCurrent()
    local history, data = History(self)
    if not history or not self.current or not self.current.historyID then return end
    for i, result in ipairs(history) do
        if result.historyID == self.current.historyID then
            table.remove(history, i)
            if data.lastKind == "mythic" and #history == 0 then data.lastKind = nil end
            self:Close()
            if history[i] or history[i - 1] then Show(self, history[i] or history[i - 1], false) end
            return
        end
    end
end

function M:ClearHistory()
    local data = Data()
    if not data then return end
    data.history = {}
    if data.lastKind == "mythic" then data.lastKind = nil end
    self:Close()
end

local function SaveHistory(self, result, repeatEvent)
    local history, data = History(self)
    if not history then return end
    local index
    if repeatEvent and self.lastHistoryID then
        for i, previous in ipairs(history) do
            if previous.historyID == self.lastHistoryID then
                index = i
                break
            end
        end
    end
    if index then
        result.historyID, result.recordedAt = history[index].historyID, history[index].recordedAt
        history[index] = result
    elseif not repeatEvent then
        data.historySerial = (data.historySerial or 0) + 1
        result.historyID = data.historySerial
        result.recordedAt = GetServerTime()
        self.lastHistoryID = result.historyID
        table.insert(history, 1, result)
        History(self)
    end
end

local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local function Specialization(unit)
    local api = C_SpecializationInfo
    local specID
    if unit == "player" then
        local index = api.GetSpecialization()
        if Finite(index) then specID = api.GetSpecializationInfo(index) end
    else
        specID = api.GetInspectSpecialization(unit)
    end
    if Finite(specID) and specID > 0 then return Text(select(2, GetSpecializationInfoByID(specID))) end
end

local function PartySnapshot()
    local players = {}
    for _, unit in ipairs(PARTY_UNITS) do
        local guid = Text(UnitGUID(unit))
        if guid then
            local data = { guid = guid, name = Text(UnitFullName(unit)) }
            if not NS.IsCombatLocked() then
                data.spec = Specialization(unit)
                local ilvl
                if unit == "player" then
                    ilvl = select(2, GetAverageItemLevel())
                else
                    ilvl = C_PaperDollInfo.GetInspectItemLevel(unit)
                end
                if Finite(ilvl) and ilvl > 0 then data.ilvl = ilvl end
                local score = Field(C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit), "currentSeasonScore")
                if Finite(score) and score >= 0 then data.rating = score end
            end
            players[guid] = data
        end
    end
    return players
end

local function ReadMeters()
    if type(S.ReadDamageMeterTotals) == "function" then return S.ReadDamageMeterTotals() end
end

-- The meter totals at completion. The read returns nothing in combat or
-- while a value is secret; the run keeps asking (reward event, combat end)
-- until one read succeeds.
local function CaptureMeters(self)
    if self.meterFinish or not self.meterStart or self.meterInvalid then return end
    self.meterFinish = ReadMeters()
    self.meterCaptured = self.meterFinish ~= nil
end

local METER_FIELDS = { "damage", "damageTaken", "interrupts", "deaths" }

-- A total below its start means the meter was reset in between.
local function ValidTotals(self, totals)
    if not totals then return nil end
    for _, field in ipairs(METER_FIELDS) do
        for guid, previous in pairs(self.meterStart[field]) do
            if not totals[field][guid] or totals[field][guid] < previous then return nil end
        end
    end
    return totals
end

local function MeterFigures(self, player, totals, time)
    for _, field in ipairs(METER_FIELDS) do
        local finish, start = totals[field][player.guid] or 0, self.meterStart[field][player.guid] or 0
        if finish >= start then player[field] = finish - start end
    end
    if Finite(player.damage) and Finite(time) and time > 0 then
        player.damagePerRunSecond = player.damage / time
    end
end

local function CompletionPlayers(self, info, result)
    CaptureMeters(self)
    local totals = ValidTotals(self, not self.meterInvalid and self.meterFinish or nil)
    local members = Field(info, "members")
    if type(members) ~= "table" then return nil end
    local snapshot, players = PartySnapshot(), {}
    for i = 1, math.min(#members, 5) do
        local member = members[i]
        local guid, name = Text(Field(member, "memberGUID")), Text(Field(member, "name"))
        if guid and name then
            local player = snapshot[guid] or { guid = guid }
            player.name = name
            local before = self.partyStart and self.partyStart[guid]
            if before and Finite(before.rating) and Finite(player.rating) then
                player.scoreDelta = player.rating - before.rating
            end
            if totals then MeterFigures(self, player, totals, result.time) end
            if self.observedLoot and self.observedLoot[guid] then player.loot = self.observedLoot[guid] end
            players[#players + 1] = player
        end
    end
    return players
end

local function MythicResult(self)
    local api = C_ChallengeMode
    local info = api.GetChallengeCompletionInfo()
    if not Public(info) or type(info) ~= "table" or Field(info, "practiceRun") == true then return nil end
    local mapID, level = Field(info, "mapChallengeModeID"), Field(info, "level")
    local milliseconds = Field(info, "time")
    local time = Finite(milliseconds) and milliseconds > 0 and milliseconds / 1000 or nil
    if not Finite(mapID) or mapID <= 0 or not Finite(level) or level < 2 or not time then return nil end
    local mapName, _, mapLimit = api.GetMapUIInfo(mapID)
    local deaths, penalty = api.GetDeathCount()
    local oldScore, newScore = Field(info, "oldOverallDungeonScore"), Field(info, "newOverallDungeonScore")
    local upgrades = Field(info, "keystoneUpgradeLevels")
    local result = {
        kind = "mythic", subtitle = (Text(mapName) or Tr("Mythic+ dungeon")) .. "  +" .. level,
        mapID = mapID, level = level, time = time,
        limit = Finite(mapLimit) and mapLimit > 0 and mapLimit or nil, onTime = Field(info, "onTime"),
        deaths = Finite(deaths) and deaths or nil, penalty = Finite(penalty) and penalty or nil,
        upgrades = Finite(upgrades) and upgrades or nil,
        scoreDelta = Finite(oldScore) and Finite(newScore) and newScore - oldScore or nil,
        record = Field(info, "isMapRecord") == true,
    }
    result.players = CompletionPlayers(self, info, result)
    return result
end

local function StartRun(self)
    self.lastRunKey, self.lastHistoryID, self.lootPending = nil, nil, nil
    self.observedLoot, self.lootLines, self.lootResult, self.lootStartedAt = {}, {}, nil, nil
    self.partyStart, self.meterStart, self.meterInvalid, self.meterFinish = PartySnapshot(), ReadMeters(), nil, nil
    self.meterCaptured = nil
end

local function MythicEvent(self, event)
    if event == "CHALLENGE_MODE_START" then
        StartRun(self)
        return
    end
    if not self.config.showMythicPlus then return end
    local result = MythicResult(self)
    if not result then return end
    local key = tostring(result.mapID) .. ":" .. tostring(result.level)
    local repeatEvent = self.lastRunKey == key
    self.lastRunKey, self.lastRunTime = key, GetTime()
    SaveHistory(self, result, repeatEvent)
    self.lootResult = result
    self.lootStartedAt = self.lootStartedAt or GetTime()
    local data = Data()
    if data then data.lastKind = "mythic" end
    if repeatEvent then
        if self.lootPending then self.lootPending = result end
        if self.pending and self.pending.kind == "mythic" then self.pending = result end
        if self.visible and self.current and self.current.kind == "mythic" then
            self.current = result
            if not NS.IsCombatLocked() and self.host:IsVisible() then Paint(self, result) end
        end
    elseif (self.config.cardTiming or 1) == 2 then
        self.lootPending = result
    else
        Show(self, result, true)
    end
end

local function RaidRecord(data, key, elapsed)
    local records = data and data.raidRecords
    if data and type(records) ~= "table" then
        records = {}
        data.raidRecords = records
    end
    local previous = records and records[key]
    local best = previous and previous.best
    local newBest = elapsed and (not Finite(best) or elapsed < best)
    if newBest then best = elapsed end
    local kills = (previous and Finite(previous.kills) and previous.kills or 0) + 1
    if records then records[key] = { best = best, kills = kills } end
    return best, newBest == true, kills
end

local function RaidEvent(self, event, encounterID, encounterName, difficultyID, groupSize, success)
    if not self.config.showRaid then return end
    if not Finite(encounterID) or not Finite(difficultyID) then return end
    local inside, kind = IsInInstance()
    if not Public(inside) or not Public(kind) or inside ~= true or kind ~= "raid" then return end
    if event == "ENCOUNTER_START" then
        self.pull = { id = encounterID, difficulty = difficultyID, started = GetTime() }
        return
    end
    if not Finite(success) or success ~= 1 then
        self.pull = nil
        return
    end
    if self.pull and (self.pull.id ~= encounterID or self.pull.difficulty ~= difficultyID) then return end
    local now = GetTime()
    local key = encounterID .. ":" .. difficultyID
    if self.lastRaidKey == key and now - (self.lastRaidTime or 0) < 5 then return end
    self.lastRaidKey, self.lastRaidTime = key, now
    local elapsed = self.pull and now - self.pull.started or nil
    self.pull = nil
    if not Finite(elapsed) or elapsed < 0 then elapsed = nil end
    local data = Data()
    local best, newBest, kills = RaidRecord(data, key, elapsed)
    local difficulty = Text(GetDifficultyInfo(difficultyID)) or Tr("Difficulty %d"):format(difficultyID)
    local result = { kind = "raid", subtitle = (Text(encounterName) or Tr("Raid encounter")) .. DOT .. difficulty,
        time = elapsed, best = best, newBest = newBest,
        groupSize = Finite(groupSize) and groupSize or nil, kills = kills }
    if data then data.lastKind, data.lastRaid = "raid", result end
    Show(self, result, true)
end

-- CHAT_MSG_LOOT supplies a sender GUID. The current EncounterLootReceived
-- payload has no recipient identity, so it cannot safely populate player loot.
local function ObserveLoot(self, message, _, _, _, _, _, _, _, _, _, lineID, guid)
    local result = self.lootResult
    if not result or not result.players or not self.observedLoot or not Text(guid)
        or not Text(message) or not Finite(lineID) or self.lootLines[lineID]
        or GetTime() - (self.lootStartedAt or 0) > 300 then return end
    local link = message:match("(|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h[^|]+|h|r)")
        or message:match("(|Hitem:[^|]+|h[^|]+|h)")
    if not link or #link > 512 then return end
    for _, player in ipairs(result.players) do
        if player.guid == guid then
            local loot = self.observedLoot[guid] or {}
            if #loot >= 8 then return end
            self.lootLines[lineID] = true
            loot[#loot + 1] = link
            self.observedLoot[guid], player.loot = loot, loot
            if self.current == result and self.visible and not NS.IsCombatLocked() then Paint(self, result) end
            return
        end
    end
end

-- A completion read in combat lacked meter totals: ask again once combat ended.
local function CombatEnded(self)
    if self.lootResult and not self.meterCaptured and self.meterStart and not self.meterInvalid then
        MythicEvent(self, "CHALLENGE_MODE_COMPLETED_REWARDS")
    end
    if self.pending then Show(self, self.pending, true) end
end

local function OnEvent(self, event, ...)
    if event == "CHAT_MSG_LOOT" then
        ObserveLoot(self, ...)
    elseif event == "DAMAGE_METER_RESET" then
        if not self.meterCaptured then self.meterInvalid = true end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- A zone transition is not evidence of looting the completed dungeon.
        -- Preserve history, but discard automatic openings tied to that zone.
        self.lootResult, self.lootStartedAt, self.lootPending = nil, nil, nil
        if self.pending and self.pending.kind == "mythic" then self.pending = nil end
    elseif event == "LOOT_CLOSED" then
        if self.lootPending then
            local result = self.lootPending
            self.lootPending = nil
            Show(self, result, true)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        CombatEnded(self)
    elseif event == "PLAYER_REGEN_DISABLED" then
        if self.visible and not self.pending and not S.editMode then self:Close() end
    elseif event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
        RaidEvent(self, event, ...)
    else
        MythicEvent(self, event)
    end
end

local MYTHIC_EVENTS = { "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_COMPLETED_REWARDS",
    "DAMAGE_METER_RESET", "CHAT_MSG_LOOT", "PLAYER_ENTERING_WORLD" }

local function SyncEvents(self)
    local context = self.context
    if self.config.showRaid then
        context:Event("ENCOUNTER_START", OnEvent, IN_COMBAT)
        context:Event("ENCOUNTER_END", OnEvent, IN_COMBAT)
    else
        context:RemoveEvent("ENCOUNTER_START")
        context:RemoveEvent("ENCOUNTER_END")
        self.pull = nil
    end
    local mythic = not NS.Client.isForever and self.config.showMythicPlus
    for _, event in ipairs(MYTHIC_EVENTS) do
        if mythic then context:Event(event, OnEvent, IN_COMBAT) else context:RemoveEvent(event) end
    end
    if mythic and (self.config.cardTiming or 1) == 2 then
        context:Event("LOOT_CLOSED", OnEvent, IN_COMBAT)
    else
        context:RemoveEvent("LOOT_CLOSED")
        self.lootPending = nil
    end
    context:Event("PLAYER_REGEN_ENABLED", OnEvent, IN_COMBAT)
    context:Event("PLAYER_REGEN_DISABLED", OnEvent, IN_COMBAT)
end

-- /msufruns opens the newest saved run. The command stays registered; it
-- does nothing while the module is off.
local function RegisterCommand(self)
    SlashCmdList.MSUFSUITERUNS = function() if self.active then self:ShowHistory() end end
    _G.SLASH_MSUFSUITERUNS1 = "/msufruns"
end

function M:Enable()
    RegisterCommand(self)
    Create(self)
    self.visible = false
    SyncEvents(self)
    self:Refresh()
end

function M:Refresh()
    Create(self)
    SyncEvents(self)
    if S.editMode then
        Paint(self, self.current or PreviewResult(NS.Client.isForever and "raid" or "mythic"))
        self.host:Show()
    elseif self.visible and self.current and not NS.IsCombatLocked() then
        Paint(self, self.current)
        self.host:Show()
    else
        self.host:Hide()
    end
end

-- An armed delete ends with the module: its window is cancelled with the
-- context, and a re-enabled module must ask again.
function M:Disable()
    self.lootPending = nil
    Disarm(self)
    self:Close()
    self.pull, self.current, self.lastRunKey = nil, nil, nil
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "summary", {
        label = "Run Summary", order = 630, getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return NS.AnchorPoints[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "width", "scale" },
        extraControls = {
            { id = "width", label = "Width", kind = "number", min = 260, max = 650, step = 5,
                get = function() return S.Config(ID).width end,
                set = function(value) return S.Set(ID, "width", value) end },
            { id = "scale", label = "Scale %", kind = "number", min = 60, max = 160, step = 1,
                get = function() return S.Config(ID).scale end,
                set = function(value) return S.Set(ID, "scale", value) end },
        },
    })
end

S.Install(ID, M)
