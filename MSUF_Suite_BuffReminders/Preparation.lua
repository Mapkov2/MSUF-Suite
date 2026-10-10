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
    local environment = self.environment
    local _, kind, difficulty, _, _, _, _, instanceID = GetInstanceInfo()
    local instanceType = Public(kind) and kind or false
    environment.instanceType = instanceType
    environment.preKey, environment.keystoneSeconds = false, nil
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
    elseif instanceType == "raid" then
        key = lfr and "showRaidFinder" or mythic and "showRaidMythic" or heroic and "showRaidHeroic" or "showRaidNormal"
    elseif instanceType == "party" then
        key = challenge and "showMythicPlus" or mythic and "showDungeonMythic" or heroic and "showDungeonHeroic" or "showDungeonNormal"
        if NS.Client.modernEquipment and (challenge or mythic) then
            local active = C_ChallengeMode.IsChallengeModeActive()
            if event == "CHALLENGE_MODE_START" or event == "CHALLENGE_MODE_COMPLETED" then
                environment.challengeStarted = true
            elseif event == "CHALLENGE_MODE_RESET" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
                environment.challengeStarted = nil
            end
            environment.preKey = Public(active) and active == false and not environment.challengeStarted
            if environment.preKey and self.config.keystoneCover == 2 then
                environment.keystoneSeconds = KeystoneLimit(instanceID)
            end
        end
    elseif instanceType == "scenario" then
        key = "showScenarios"
    end
    environment.key = key
end

-- A profile saved before a setting existed lacks its key; the catalog default
-- (MSUF_Suite/Core/Catalog/BuffReminders.lua) is the one source of its value.
-- Hot paths write `config.key or R.Default("key")`: the default is read only
-- when the key is missing, so a present setting costs what it always did.
local function Default(key)
    return NS.Defaults.suite.modules.buffReminders[key]
end
R.Default = Default
local function NumberSetting(config, key)
    local value = config[key]
    if type(value) == "number" then return value end
    return Default(key)
end

-- Seconds a buff must still last. Before a keystone starts, the dungeon's
-- timer or the chosen minutes replace the normal warning time.
function R.Threshold(self)
    local c, environment = self.config, self.environment
    if environment.preKey then
        if c.keystoneCover == 2 and environment.keystoneSeconds then return environment.keystoneSeconds end
        if c.keystoneCover == 3 then return (c.keystoneMinutes or Default("keystoneMinutes")) * 60 end
    end
    return (c.remindBeforeMinutes or Default("remindBeforeMinutes")) * 60
end

function R.SyncPreparationEvents(self, callback)
    local listen = not self.listen.suspended
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

-- The note hides after config.readyCheckDuration seconds (a context wait).
function R.HideReadyCheck(self)
    self.context:Cancel(R.HideReadyCheck)
    local label = self.readyCheck.label
    if label then label:Hide() end
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
    local limit = NumberSetting(self.config, "readyCheckManaPercent")
    if power / maximum * 100 >= limit then return end
    local readyCheck = self.readyCheck
    local text = readyCheck.label
    if not text then
        local host = self.view.host
        text = S.CreateFontString(host, nil, "OVERLAY", "GameFontNormalLarge")
        text:SetPoint("BOTTOM", host, "TOP", 0, 8)
        readyCheck.label = text
    end
    -- The note turns red once the mana is below half of the chosen limit.
    local percent = power / maximum * 100
    text:SetText(S.Text("Mana at the ready check: %d%%"):format(math.floor(percent + .5)))
    if percent < limit / 2 then
        text:SetTextColor(1, .3, .25)
    else
        text:SetTextColor(1, .82, 0)
    end
    text:Show()
    self.context:After(NumberSetting(self.config, "readyCheckDuration"), R.HideReadyCheck)
end

function R.StyleCount(button, config)
    local point = NS.AnchorPoints[config.countPosition or 9] or "BOTTOMRIGHT"
    button.count:ClearAllPoints()
    button.count:SetPoint(point, button, point, config.countX or -2, config.countY or 2)
    S.SetFont(button.count, S.ResolveFont(config.countFont), config.countSize or 12, "OUTLINE")
end
