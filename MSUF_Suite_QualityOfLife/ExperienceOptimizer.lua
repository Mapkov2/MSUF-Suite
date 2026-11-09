local _, P = ...
local NS, S = P.NS, P.Suite
local Optimizer = {}
P.ExperienceOptimizer = Optimizer
local Finite, Public = S.Finite, S.Public
local Exact, Duration = P.ExperienceBarText.Exact, P.ExperienceBarText.Duration
local IN_COMBAT = { inCombat = true }
local QUEST_EVENTS = { "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_DATA_LOAD_RESULT" }
local ITEM_EVENTS = { "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "PLAYER_EQUIPMENT_CHANGED" }
local STATUS_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UNGHOST", "PLAYER_ALIVE" }
local WARNING_LEAD, REMINDER_INTERVAL = 60, 300

-- Known Forever item and aura IDs documented by ForeverXPOptimizer (1nd1v1d).
-- Generic Well Fed auras can belong to food that grants no XP bonus.
local FOOD, SLEEP, TENT, PENDANT = 1, 2, 3, 4
local FOODS = {
    { 6290, 1 }, { 6888, 1 }, { 12224, 1 }, { 2680, 1 },
    { 21072, 10 }, { 12218, 35 }, { 13931, 35 },
}
local SOURCES = {
    { label = S.Text("XP food"), level = 1, warn = true },
    { label = S.Text("Cozy Sleeping Bag"), level = 14, item = 211527, warn = true },
    { label = S.Text("Camp Tent"), level = 1, item = 279978 },
    { label = S.Text("Undead XP pendant"), level = 30, item = 273049 },
}
local AURAS = {
    [1249519] = FOOD, [1249520] = FOOD, [1243969] = FOOD,
    [429959] = SLEEP, [1229487] = TENT, [1292997] = PENDANT, [1293736] = PENDANT,
}
local TEXT = {
    title = S.Text("Forever XP Optimizer"), quests = S.Text("Quest XP ready to turn in"),
    unknown = S.Text("Unknown"), incomplete = S.Text("Some quest rewards are unavailable."),
    active = S.Text("Active"), missing = S.Text("Missing"), inactive = S.Text("Inactive"),
    ready = S.Text("Ready"), cooldown = S.Text("Cooldown: %s"),
    stacks = S.Text("%d / 3 stacks (%s)"), lowRested = S.Text("Low rested XP"),
    afk = S.Text("AFK time"), rate = S.Text("Active XP per hour"),
    missingWarning = S.Text("XP bonus missing: %s."), expiresWarning = S.Text("XP bonus expiring soon: %s."),
}

local function ReadAuras(state, now)
    for _, row in ipairs(state.bonuses) do row.up, row.expires, row.stacks = nil, nil, nil end
    local restricted = C_Secrets.ShouldAurasBeSecret()
    if not Public(restricted) or restricted ~= false then return false end
    local complete = true
    for index = 1, 255 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
        if not Public(aura) then return false end
        if not aura then return complete end
        if not canaccesstable(aura) then return false end
        local spell = aura.spellId
        if not Finite(spell) then
            complete = false
        else
            local row = state.bonuses[AURAS[spell]]
            if row then
                local expires, stacks = aura.expirationTime, aura.applications
                local timed = Finite(expires) and expires > 0
                if (not timed or expires > now) and (not row.up or (timed and expires > (row.expires or now))) then
                    row.up = true
                    row.expires = timed and expires or nil
                    row.stacks = Finite(stacks) and stacks or nil
                end
            end
        end
    end
    return false
end

local function HasItem(id)
    local count = C_Item.GetItemCount(id)
    return Finite(count) and count > 0
end

local function Owns(source, index, level)
    if index == FOOD then
        for _, food in ipairs(FOODS) do
            if level >= food[2] and HasItem(food[1]) then return true end
        end
        return false
    end
    if index == PENDANT then
        local equipped = GetInventoryItemID("player", 2)
        if Finite(equipped) and equipped == source.item then return true end
    end
    return HasItem(source.item)
end

local function CooldownEnd(item, now)
    if not item then return nil end
    local info = C_Spell.GetItemCooldown(item)
    if not Public(info) or not info or not canaccesstable(info) then return nil, true end
    local start, duration, enabled = info.startTime, info.duration, info.isEnabled
    if not Finite(start) or not Finite(duration) or not Public(enabled) then return nil, true end
    if enabled and start > 0 and duration > 1.5 and start + duration > now then return start + duration end
end

local function CanRemind(state)
    if state.afk ~= false or NS.InCombat() or S.InstanceKind() ~= "world" then return false end
    local dead = UnitIsDeadOrGhost("player")
    return Public(dead) and not dead
end

local function Warn(row, source, state, now, canRemind)
    local warning
    if row.up then
        if row.expires and row.expires - now <= WARNING_LEAD then warning = TEXT.expiresWarning end
    elseif state.aurasReadable and row.owned and not row.cooldown and not row.cooldownUnknown then
        warning = TEXT.missingWarning
    end
    if not warning then row.warned = nil end
    if not warning or not canRemind then return end
    if row.warned ~= warning and now >= (row.nextWarning or 0) then
        S.Print(warning:format(source.label))
        row.warned, row.nextWarning = warning, now + REMINDER_INTERVAL
    elseif row.warned ~= warning then
        return row.nextWarning
    end
end

local function Earliest(previous, candidate, now)
    if candidate and candidate > now and (not previous or candidate < previous) then return candidate end
    return previous
end

local RefreshBonuses
local function BonusDeadline(self)
    local state = self.optimizer
    state.deadline, state.aurasDirty = nil, true
    RefreshBonuses(self)
end

local function QueueBonusDeadline(self, deadline, now)
    local state = self.optimizer
    if state.deadline == deadline then return end
    state.deadline = deadline
    if deadline then
        self.context:After(deadline - now, BonusDeadline)
    else
        self.context:Cancel(BonusDeadline)
    end
end

local function ReadBonuses(self, now)
    local state = self.optimizer
    local canRemind = now >= state.remindAt and CanRemind(state)
    local deadline = now < state.remindAt and state.remindAt or nil
    if state.aurasDirty then state.aurasReadable = ReadAuras(state, now) end
    for index, source in ipairs(SOURCES) do
        if state.level >= source.level then
            local row = state.bonuses[index]
            if state.itemsDirty then
                row.owned = Owns(source, index, state.level)
                row.cooldown, row.cooldownUnknown = nil, nil
                if row.owned then row.cooldown, row.cooldownUnknown = CooldownEnd(source.item, now) end
            elseif row.cooldown and row.cooldown <= now then
                row.cooldown = nil
            end
            deadline = Earliest(deadline, row.expires, now)
            deadline = Earliest(deadline, row.cooldown, now)
            if source.warn then
                deadline = Earliest(deadline, Warn(row, source, state, now, canRemind), now)
                deadline = Earliest(deadline, row.expires and row.expires - WARNING_LEAD, now)
            end
        end
    end
    state.itemsDirty, state.aurasDirty = nil, nil
    QueueBonusDeadline(self, deadline, now)
end

RefreshBonuses = function(self)
    if not self.optimizer then return end
    ReadBonuses(self, GetTime())
    self.optimizerTooltip(self)
end

local function QueueStatus(self, event)
    local state = self.optimizer
    state.aurasDirty = true
    if event == "PLAYER_REGEN_ENABLED" then state.itemsDirty = true end
    state.bonusJob:Request()
end

local function PlayerAuraChanged(self, _, unit)
    if Public(unit) and unit == "player" then QueueStatus(self) end
end

local function QueueItems(self)
    local state = self.optimizer
    state.itemsDirty = true
    state.bonusJob:Request()
end

local function ReadQuest(state, info)
    if not Public(info) or type(info) ~= "table" or not canaccesstable(info) then return false end
    local id, header, hidden = info.questID, info.isHeader, info.isHidden
    if not Public(header) or not Public(hidden) then return false end
    if header or hidden then return true end
    if not Finite(id) or id <= 0 then return false end
    if state.questSeen[id] then return true end
    state.questSeen[id] = true
    local ready = C_QuestLog.IsComplete(id)
    if not Public(ready) or type(ready) ~= "boolean" then return false end
    if not ready then return true end
    local loaded = HaveQuestRewardData(id)
    if not Public(loaded) or loaded ~= true then return false end
    local xp = GetQuestLogRewardXP(id)
    if not Finite(xp) or xp < 0 then return false end
    state.questXP = state.questXP + xp
    local title = info.title
    if xp > 0 and Public(title) and type(title) == "string" then
        local index = state.questCount + 1
        state.questCount, state.questTitles[index], state.questRewards[index] = index, title, xp
    end
    return true
end

local function RefreshQuests(self)
    local state = self.optimizer
    if not state then return end
    wipe(state.questSeen)
    state.questXP, state.questCount, state.questIncomplete = 0, 0, false
    local entries = C_QuestLog.GetNumQuestLogEntries()
    if Finite(entries) then
        for index = 1, entries do
            if not ReadQuest(state, C_QuestLog.GetInfo(index)) then state.questIncomplete = true end
        end
    else
        state.questIncomplete = true
    end
    self.optimizerPaint(self)
end

local function AFK()
    local afk = UnitIsAFK("player")
    if Public(afk) and type(afk) == "boolean" then return afk end
end

local function Times(state, now)
    local elapsed = math.max(0, now - state.lastModeChange)
    return state.activeTime + (state.afk == false and elapsed or 0), state.afkTime + (state.afk and elapsed or 0)
end

local function ApplyAFK(self, afk)
    local state = self.optimizer
    if state.afk == afk then return end
    local now = GetTime()
    state.activeTime, state.afkTime = Times(state, now)
    state.afk, state.lastModeChange = afk, now
    state.bonusJob:Request()
    self.optimizerPaint(self)
end

local function RecheckAFK(self)
    ApplyAFK(self, AFK())
end

local function FlagsChanged(self, _, unit)
    if not Public(unit) or unit ~= "player" then return end
    local afk = AFK()
    -- /afk can make the flag secret during chat lockdown. Request before
    -- repainting so an optimizer stopped by the repaint can cancel the retry.
    if afk == nil then self.optimizer.afkJob:Request() end
    ApplyAFK(self, afk)
end

function Optimizer.ResetRate(state)
    if not state then return end
    state.gained, state.activeTime, state.afkTime, state.lastModeChange = 0, 0, 0, GetTime()
end

function Optimizer.Rate(state)
    local active = Times(state, GetTime())
    if active < 60 or state.gained <= 0 then return nil end
    return state.gained * 3600 / active
end

function Optimizer.Start(self, level)
    local state = {
        level = level, bonuses = { {}, {}, {}, {} }, afk = AFK(), questXP = 0, questCount = 0,
        questSeen = {}, questTitles = {}, questRewards = {},
    }
    self.optimizer = state
    Optimizer.ResetRate(state)
    local context = self.context
    state.bonusJob = context:Coalesce(.2, RefreshBonuses)
    state.afkJob = context:Coalesce(.1, RecheckAFK)
    if state.afk == nil then state.afkJob:Request() end
    state.questJob = context:Coalesce(.2, RefreshQuests)
    for _, event in ipairs(QUEST_EVENTS) do context:Event(event, state.questJob, IN_COMBAT) end
    state.questJob:Request()
    for _, event in ipairs(ITEM_EVENTS) do context:Event(event, QueueItems, IN_COMBAT) end
    for _, event in ipairs(STATUS_EVENTS) do context:Event(event, QueueStatus, IN_COMBAT) end
    context:Event("UNIT_AURA", PlayerAuraChanged, IN_COMBAT, "player")
    context:Event("PLAYER_FLAGS_CHANGED", FlagsChanged, IN_COMBAT)
    -- Read the tooltip promptly while giving login and bags time to settle before any chat warning.
    state.remindAt = GetTime() + 15
    state.aurasDirty = true
    QueueItems(self)
end

function Optimizer.Stop(self)
    local state = self.optimizer
    if not state then return end
    local context = self.context
    self.optimizer = nil
    state.bonusJob:Cancel()
    state.afkJob:Cancel()
    state.questJob:Cancel()
    for _, event in ipairs(QUEST_EVENTS) do context:RemoveEvent(event) end
    context:Cancel(BonusDeadline)
    for _, event in ipairs(ITEM_EVENTS) do context:RemoveEvent(event) end
    for _, event in ipairs(STATUS_EVENTS) do context:RemoveEvent(event) end
    context:RemoveEvent("UNIT_AURA")
    context:RemoveEvent("PLAYER_FLAGS_CHANGED")
end

function Optimizer.Sync(self, level)
    if not level then return Optimizer.Stop(self) end
    local state = self.optimizer
    if not state then return Optimizer.Start(self, level) end
    if state.level ~= level then
        state.level = level
        QueueItems(self)
        state.questJob:Request()
    end
end

function Optimizer.WorldChanged(self)
    local state = self.optimizer
    if not state then return end
    FlagsChanged(self, nil, "player")
    if self.optimizer ~= state then return end
    QueueStatus(self)
    QueueItems(self)
    state.questJob:Request()
end

-- Thin gold strip leaves the rested fill visible on the same portion of the bar.
function Optimizer.Paint(view, fraction, maximum, xp)
    local strip = view.questXPStrip
    if not xp or xp <= 0 or fraction >= 1 then
        if strip and view.questStripShown then
            strip:Hide()
            view.questStripShown = nil
        end
        return
    end
    if not strip then
        strip = S.CreateTexture(view.bar, nil, "OVERLAY", nil, 4)
        strip:SetColorTexture(1, .76, .28, 1)
        view.questXPStrip = strip
    end
    local width = view.config.width
    local start, length = width * fraction, width * math.min(1 - fraction, xp / maximum)
    if view.questStripStart ~= start or view.questStripWidth ~= length or view.questStripPixel ~= view.pixel then
        strip:ClearAllPoints()
        strip:SetPoint("BOTTOMLEFT", view.bar, "BOTTOMLEFT", start, 0)
        strip:SetSize(length, view.pixel * 2)
        view.questStripStart, view.questStripWidth, view.questStripPixel = start, length, view.pixel
    end
    if not view.questStripShown then
        strip:Show()
        view.questStripShown = true
    end
end

local function BonusText(index, row, state, now, rested, maximum)
    if row.up then
        local duration = row.expires and Duration(math.max(0, row.expires - now)) or TEXT.active
        if index == SLEEP and row.stacks then return TEXT.stacks:format(row.stacks, duration) end
        if index == TENT and row.expires then return TEXT.cooldown:format(duration) end
        return duration
    end
    if not state.aurasReadable or row.cooldownUnknown then return TEXT.unknown end
    if row.cooldown and row.cooldown > now then return TEXT.cooldown:format(Duration(row.cooldown - now)) end
    if index == TENT and rested and rested < maximum * .05 then return TEXT.lowRested end
    if index == TENT or index == PENDANT then return row.owned and TEXT.ready or TEXT.inactive end
    return TEXT.missing
end

function Optimizer.Tooltip(state, tooltip, rested, maximum)
    local now = GetTime()
    local _, afk = Times(state, now)
    tooltip:AddLine(" ")
    tooltip:AddLine(TEXT.title, 1, .76, .28)
    tooltip:AddDoubleLine(TEXT.afk, Duration(afk), 1, 1, 1, 1, 1, 1)
    for index, source in ipairs(SOURCES) do
        if state.level >= source.level then
            tooltip:AddDoubleLine(source.label, BonusText(index, state.bonuses[index], state, now, rested, maximum),
                1, 1, 1, 1, 1, 1)
        end
    end
    tooltip:AddDoubleLine(TEXT.quests, Exact(state.questXP), 1, 1, 1, 1, .76, .28)
    for index = 1, state.questCount do
        tooltip:AddDoubleLine(state.questTitles[index], Exact(state.questRewards[index]), 1, 1, 1, 1, 1, 1)
    end
    if state.questIncomplete then tooltip:AddLine(TEXT.incomplete, 1, .76, .28, true) end
end

Optimizer.rateLabel = TEXT.rate
