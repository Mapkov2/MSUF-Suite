local _, P = ...
local NS, S = P.NS, P.Suite
local ID = "runSummary"
local Public, Finite, Text = S.Public, S.Finite, S.PublicText
local Tr = S.Text
local M = { serial = 0 }

-- Completion payloads can contain secret fields. Persist only checked scalars.
local function Field(info, key)
    if not Public(info) or type(info) ~= "table" then return nil end
    local value = info[key]
    return Public(value) and value or nil
end

local function Clock(seconds)
    if not Finite(seconds) or seconds < 0 then return "--:--" end
    seconds = math.floor(seconds)
    if seconds >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
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
    host:Hide()
end

local function Add(rows, label, value)
    if value ~= nil and #rows < 7 then rows[#rows + 1] = { label, tostring(value) } end
end

local function Rows(self, result)
    local c, rows = self.config, {}
    if result.kind == "mythic" then
        if c.showDuration then Add(rows, Tr("Run time"), Clock(result.time)) end
        if c.showTimer then
            local value = result.onTime == true and Tr("In time")
                or result.onTime == false and Tr("Over time") or Tr("Unknown")
            if Finite(result.limit) and Finite(result.time) then
                local delta = result.limit - result.time
                value = value .. "  ·  " .. (delta >= 0 and "-" or "+") .. Clock(math.abs(delta))
            end
            Add(rows, Tr("Timer"), value)
        end
        if c.showDeaths then
            Add(rows, Tr("Deaths"), Finite(result.deaths) and result.deaths or "--")
        end
        if c.showPenalty then
            Add(rows, Tr("Time penalty"), Finite(result.penalty) and ("+" .. Clock(result.penalty)) or "--")
        end
        if c.showUpgrades then
            Add(rows, Tr("Keystone"), Finite(result.upgrades) and result.upgrades > 0
                and ("+" .. result.upgrades .. " " .. Tr("upgrades")) or Tr("No upgrade"))
        end
        if c.showScore and Finite(result.scoreDelta) then
            Add(rows, Tr("Rating"), string.format("%+.0f", result.scoreDelta))
        end
        if c.showRecord and result.record then Add(rows, Tr("Record"), Tr("New dungeon record")) end
    else
        if c.showDuration then Add(rows, Tr("Kill time"), Clock(result.time)) end
        if c.showBest then
            Add(rows, Tr("Fastest kill"), Clock(result.best)
                .. (result.newBest and ("  ·  " .. Tr("New best")) or ""))
        end
        if c.showGroupSize then Add(rows, Tr("Group size"), Finite(result.groupSize) and result.groupSize or "--") end
        if c.showKills and Finite(result.kills) then Add(rows, Tr("Kills recorded"), result.kills) end
    end
    return rows
end

local function Paint(self, result)
    local c = self.config
    local skin = self.context and self.context:Skin()
    local custom = c.colorStyle == 2
    local font = S.ResolveFont(c.font) or S.GlobalFontPath()
    local titleR, titleG, titleB = .96, .97, .99
    local textR, textG, textB = .88, .92, .97
    local accentR, accentG, accentB = .39, .86, .54
    local backR, backG, backB = .05, .07, .10
    if custom then
        titleR, titleG, titleB = S.RGB(c.titleColor)
        textR, textG, textB = S.RGB(c.textColor)
        accentR, accentG, accentB = S.RGB(c.accentColor)
        backR, backG, backB = S.RGB(c.backgroundColor)
    end
    if not custom and skin then
        backR, backG, backB = skin:GetColor("surface")
        textR, textG, textB = skin:GetColor("text")
    end
    self.background:SetColorTexture(backR, backG, backB, (c.backgroundOpacity or 92) / 100)
    self.accent:SetColorTexture(accentR, accentG, accentB, 1)
    S.SetStyledFont(self.title, font, c.titleSize or 20, "OUTLINE", 1, true, 80, 1)
    S.SetStyledFont(self.subtitle, font, c.detailSize or 14, "OUTLINE", 1, true, 75, 1)
    S.SetStyledFont(self.closeText, font, 18, "OUTLINE", 1, true, 70, 1)
    self.title:SetText(result.kind == "raid" and Tr("RAID BOSS DEFEATED") or Tr("MYTHIC+ COMPLETE"))
    self.title:SetTextColor(titleR, titleG, titleB)
    self.subtitle:SetText(result.subtitle or "")
    self.subtitle:SetTextColor(accentR, accentG, accentB)
    self.closeText:SetText("×")
    self.closeText:SetTextColor(textR, textG, textB)
    local rows = Rows(self, result)
    local width = c.width or 390
    self.host:SetSize(width, 240)
    local y = -91
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
            row.label:SetTextColor(textR, textG, textB)
            row.value:SetTextColor(titleR, titleG, titleB)
            row.label:Show(); row.value:Show()
            local labelHeight = row.label.GetStringHeight and row.label:GetStringHeight() or 0
            local valueHeight = row.value.GetStringHeight and row.value:GetStringHeight() or 0
            y = y - math.max(27, math.ceil(math.max(labelHeight, valueHeight)) + 6)
        else
            row.label:Hide(); row.value:Hide()
        end
    end
    self.host:SetHeight(-y + 12)
    self.host:SetScale((c.scale or 100) / 100)
    local point = NS.AnchorPoints[c.point] or "CENTER"
    self.host:ClearAllPoints()
    self.host:SetPoint(point, UIParent, point, c.x or 0, c.y or 0)
end

local PREVIEW_MPLUS = { kind = "mythic", subtitle = "Example Dungeon  +15", time = 1422,
    limit = 1800, onTime = true, deaths = 2, penalty = 10, upgrades = 2, scoreDelta = 18 }
local PREVIEW_RAID = { kind = "raid", subtitle = "Example Boss  ·  Mythic", time = 274,
    best = 274, newBest = true, groupSize = 20, kills = 1 }

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
    self.serial = self.serial + 1
    local serial, duration = self.serial, self.config.autoHide or 0
    if automatic and duration > 0 then
        C_Timer.After(duration, function()
            if self.active and self.serial == serial and not S.editMode then self:Close() end
        end)
    end
end

function M:Close()
    self.serial = self.serial + 1
    self.visible, self.pending = false, nil
    if self.host then self.host:Hide() end
end

function M:Preview(kind)
    Show(self, kind == "raid" and PREVIEW_RAID or PREVIEW_MPLUS, false)
end

function M:ShowLast()
    local state = S.ModuleState(ID)
    if state and state.last then Show(self, state.last, false) end
end

local function MythicResult()
    local api = C_ChallengeMode
    local info = api.GetChallengeCompletionInfo()
    if not Public(info) or type(info) ~= "table" or Field(info, "practiceRun") == true then return nil end
    local mapID, level = Field(info, "mapChallengeModeID"), Field(info, "level")
    local milliseconds = Field(info, "time")
    local time = Finite(milliseconds) and milliseconds >= 0 and milliseconds / 1000 or nil
    local name, limit
    if Finite(mapID) and mapID > 0 then
        local mapName, _, mapLimit = api.GetMapUIInfo(mapID)
        name = Text(mapName)
        limit = Finite(mapLimit) and mapLimit > 0 and mapLimit or nil
    end
    local deaths, penalty = api.GetDeathCount()
    local oldScore, newScore = Field(info, "oldOverallDungeonScore"), Field(info, "newOverallDungeonScore")
    return {
        kind = "mythic", subtitle = (name or Tr("Mythic+ dungeon"))
            .. (Finite(level) and level > 0 and ("  +" .. level) or ""),
        mapID = Finite(mapID) and mapID or nil, level = Finite(level) and level or nil,
        time = time, limit = limit, onTime = Field(info, "onTime"),
        deaths = Finite(deaths) and deaths or nil,
        penalty = Finite(penalty) and penalty or nil,
        upgrades = Finite(Field(info, "keystoneUpgradeLevels")) and Field(info, "keystoneUpgradeLevels") or nil,
        scoreDelta = Finite(oldScore) and Finite(newScore) and newScore - oldScore or nil,
        record = Field(info, "isMapRecord") == true,
    }
end

local function MythicEvent(self, event)
    if event == "CHALLENGE_MODE_START" then self.lastRunKey = nil; return end
    if not self.config.showMythicPlus then return end
    local result = MythicResult()
    if not result then return end
    local key = tostring(result.mapID) .. ":" .. tostring(result.level)
    local now = GetTime()
    local repeatEvent = self.lastRunKey == key and now - (self.lastRunTime or 0) < 30
    self.lastRunKey, self.lastRunTime = key, now
    local state = S.ModuleState(ID)
    if state then state.last = result end
    if repeatEvent then
        if self.pending and self.pending.kind == "mythic" then self.pending = result end
        if self.visible and self.current and self.current.kind == "mythic" then
            self.current = result
            if not NS.IsCombatLocked() and self.host:IsVisible() then Paint(self, result) end
        end
    else
        Show(self, result, true)
    end
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
    local state = S.ModuleState(ID)
    local records = state and state.raidRecords
    if state and type(records) ~= "table" then records = {}; state.raidRecords = records end
    local previous = records and records[key]
    local best = previous and previous.best
    local newBest = elapsed and (not Finite(best) or elapsed < best)
    if newBest then best = elapsed end
    local kills = (previous and Finite(previous.kills) and previous.kills or 0) + 1
    if records then records[key] = { best = best, kills = kills } end
    local difficulty = Text(GetDifficultyInfo(difficultyID)) or (Tr("Difficulty") .. " " .. difficultyID)
    local result = { kind = "raid", subtitle = (Text(encounterName) or Tr("Raid encounter")) .. "  ·  " .. difficulty,
        time = elapsed, best = best, newBest = newBest == true,
        groupSize = Finite(groupSize) and groupSize or nil, kills = kills }
    if state then state.last = result end
    Show(self, result, true)
end

local function OnEvent(self, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        if self.pending then Show(self, self.pending, true) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if self.visible and not self.pending and not S.editMode then self:Close() end
    elseif event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
        RaidEvent(self, event, ...)
    else
        MythicEvent(self, event)
    end
end

local function SyncEvents(self)
    local context = self.context
    if self.config.showRaid then
        context:Event("ENCOUNTER_START", OnEvent, true)
        context:Event("ENCOUNTER_END", OnEvent, true)
    else
        context:RemoveEvent("ENCOUNTER_START")
        context:RemoveEvent("ENCOUNTER_END")
        self.pull = nil
    end
    if not NS.Client.isForever and self.config.showMythicPlus then
        for _, event in ipairs({ "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
            "CHALLENGE_MODE_COMPLETED_REWARDS" }) do context:Event(event, OnEvent, true) end
    else
        for _, event in ipairs({ "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
            "CHALLENGE_MODE_COMPLETED_REWARDS" }) do context:RemoveEvent(event) end
    end
    context:Event("PLAYER_REGEN_ENABLED", OnEvent, true)
    context:Event("PLAYER_REGEN_DISABLED", OnEvent, true)
end

function M:Enable()
    Create(self)
    self.visible = false
    SyncEvents(self)
    self:Refresh()
    self:RegisterMovers()
end

function M:Refresh()
    Create(self)
    SyncEvents(self)
    if S.editMode then
        Paint(self, self.current or (NS.Client.isForever and PREVIEW_RAID or PREVIEW_MPLUS))
        self.host:Show()
    elseif self.visible and self.current and not NS.IsCombatLocked() then
        Paint(self, self.current)
        self.host:Show()
    else
        self.host:Hide()
    end
end

function M:Disable()
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
