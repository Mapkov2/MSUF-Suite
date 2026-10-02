local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders
local Public = S.Public
local PREP_EVENTS = { "CHALLENGE_MODE_START", "CHALLENGE_MODE_RESET", "CHALLENGE_MODE_COMPLETED" }

-- Instance changes are cold. Blizzard's difficulty metadata avoids hardcoded
-- raid sizes; Timewalking and keystone preparation use its named difficulty IDs.
-- The time limit of the keystone dungeon the player is in, in seconds: the
-- challenge map whose instance is this one (C_ChallengeMode.GetMapUIInfo).
local function KeystoneLimit(instanceID)
    if not Public(instanceID) or type(instanceID) ~= "number" then return end
    local maps = C_ChallengeMode.GetMapTable()
    if not Public(maps) or type(maps) ~= "table" then return end
    for _, challengeMapID in ipairs(maps) do
        local _, _, timeLimit, _, _, mapID = C_ChallengeMode.GetMapUIInfo(challengeMapID)
        if Public(mapID) and mapID == instanceID and Public(timeLimit) and type(timeLimit) == "number"
            and timeLimit > 0 then
            return timeLimit
        end
    end
end

function R.ReadEnvironment(self, event)
    local _, kind, difficulty, _, _, _, _, instanceID = GetInstanceInfo()
    self.instanceType = Public(kind) and kind or false
    self.preKey, self.keystoneSeconds = false, nil
    local key = "showWorld"
    local ids = DifficultyUtil.ID
    local timewalking = ids and Public(difficulty) and type(difficulty) == "number" and
        (difficulty == ids.DungeonTimewalker or difficulty == ids.RaidTimewalker)
    local heroic, challenge, mythic, lfr
    if Public(difficulty) and type(difficulty) == "number" then
        local _, _, h, ch, _, m, _, finder = GetDifficultyInfo(difficulty)
        heroic, challenge, mythic, lfr = Public(h) and h == true, Public(ch) and ch == true,
            Public(m) and m == true, Public(finder) and finder == true
    end
    if timewalking then
        key = "showTimewalking"
    elseif self.instanceType == "raid" then
        key = lfr and "showRaidFinder" or mythic and "showRaidMythic" or heroic and "showRaidHeroic" or "showRaidNormal"
    elseif self.instanceType == "party" then
        key = challenge and "showMythicPlus" or mythic and "showDungeonMythic" or heroic and "showDungeonHeroic" or "showDungeonNormal"
        if NS.Client.modernEquipment and (challenge or mythic) then
            local active = C_ChallengeMode.IsChallengeModeActive()
            if event == "CHALLENGE_MODE_START" or event == "CHALLENGE_MODE_COMPLETED" then
                self.challengeStarted = true
            elseif event == "CHALLENGE_MODE_RESET" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
                self.challengeStarted = nil
            end
            self.preKey = Public(active) and active == false and not self.challengeStarted
            if self.preKey and self.config.keystoneCover == 2 then self.keystoneSeconds = KeystoneLimit(instanceID) end
        end
    elseif self.instanceType == "scenario" then
        key = "showScenarios"
    end
    self.environmentKey = key
end

-- Seconds a buff must still last. Before a keystone starts, the dungeon's
-- timer or the chosen minutes replace the normal warning time.
function R.Threshold(self)
    local c = self.config
    if self.preKey then
        if c.keystoneCover == 2 and self.keystoneSeconds then return self.keystoneSeconds end
        if c.keystoneCover == 3 then return c.keystoneMinutes * 60 end
    end
    return (c.remindBeforeMinutes or 0) * 60
end

function R.SyncPreparationEvents(self, callback)
    local listen = not self.suspended
    if listen and self.config.readyCheckMana then
        R.Listen(self, "READY_CHECK", callback)
    else
        self.context:RemoveEvent("READY_CHECK")
    end
    for i = 1, #PREP_EVENTS do
        local event = PREP_EVENTS[i]
        if listen and NS.Client.modernEquipment and self.config.keystoneCover ~= 1 then
            R.Listen(self, event, callback)
        else
            self.context:RemoveEvent(event)
        end
    end
end

function R.HideReadyCheck(self)
    if self.readyCheckTimer then self.readyCheckTimer:Cancel() end
    self.readyCheckTimer = nil
    if self.readyCheckWarning then self.readyCheckWarning:Hide() end
end

function R.ReadyCheck(self)
    R.HideReadyCheck(self)
    if not self.config.readyCheckMana or NS.IsCombatLocked() then return end
    local role = UnitGroupRolesAssigned("player")
    if not Public(role) or role ~= "HEALER" then return end
    local mana = Enum.PowerType.Mana
    local power, maximum = UnitPower("player", mana), UnitPowerMax("player", mana)
    if not Public(power) or not Public(maximum) or type(power) ~= "number" or type(maximum) ~= "number"
        or maximum <= 0 or power < 0 then return end
    if power / maximum * 100 >= (self.config.readyCheckManaPercent or 80) then return end
    local text = self.readyCheckWarning
    if not text then
        text = S.CreateFontString(self.host, nil, "OVERLAY", "GameFontNormalLarge")
        text:SetPoint("BOTTOM", self.host, "TOP", 0, 8)
        self.readyCheckWarning = text
    end
    -- The note turns red once the mana is below half of the chosen limit.
    local percent = power / maximum * 100
    text:SetText(S.Text("Mana at the ready check: %d%%"):format(math.floor(percent + .5)))
    if percent < self.config.readyCheckManaPercent / 2 then
        text:SetTextColor(1, .3, .25)
    else
        text:SetTextColor(1, .82, 0)
    end
    text:Show()
    local timer
    timer = C_Timer.NewTimer(self.config.readyCheckDuration or 10, function()
        if self.readyCheckTimer ~= timer then return end
        self.readyCheckTimer = nil
        text:Hide()
    end)
    self.readyCheckTimer = timer
end

function R.StyleCount(button, config)
    local point = NS.AnchorPoints[config.countPosition or 9] or "BOTTOMRIGHT"
    button.count:ClearAllPoints()
    button.count:SetPoint(point, button, point, config.countX or -2, config.countY or 2)
    S.SetFont(button.count, S.ResolveFont(config.countFont), config.countSize or 12, "OUTLINE")
end
