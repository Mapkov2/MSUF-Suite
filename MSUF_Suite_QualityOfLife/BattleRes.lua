local _, P = ...
local NS, S = P.NS, P.Suite
local ID, SPELL_ID = "battleRes", 20484 -- Rebirth exposes the shared combat-resurrection pool.
local POINTS = NS.AnchorPoints
local M = {}
-- CHALLENGE_MODE_START may precede the API's active-state transition; the
-- key state is read again once, this long after it (self.startJob).
local START_RECHECK = .2

local function EncounterActive()
    local active = C_InstanceEncounter.IsEncounterInProgress()
    return S.Public(active) and active == true
end

local function ChallengeActive()
    local active = C_ChallengeMode.IsChallengeModeActive()
    return S.Public(active) and active == true
end

local CARD = { width = 146, height = 44, fill = { .06, .07, .09, .92 }, edge = 1, line = { .54, .72, .78, .95 } }

local function Create(self)
    if self.host then return end

    local host, panel, edges = S.QoLCard(CARD)

    local icon = S.CreateTexture(host, nil, "ARTWORK")
    icon:SetPoint("LEFT", host, "LEFT", 3, 0)
    icon:SetSize(38, 38)
    icon:SetTexture(C_Spell.GetSpellTexture(SPELL_ID))

    local cooldown = S.CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(false)
    cooldown:SetMinimumCountdownDuration(0)

    local title = S.CreateFontString(host, nil, "OVERLAY")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 7, -2)
    S.SetFont(title, nil, 11, "OUTLINE")
    title:SetTextColor(.7, .84, .88)
    title:SetText(S.Text("Battle Rez"))

    local count = S.CreateFontString(host, nil, "OVERLAY")
    count:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 7, 0)
    S.SetFont(count, nil, 22, "OUTLINE")
    count:SetTextColor(1, 1, 1)

    local maximum = S.CreateFontString(host, nil, "OVERLAY")
    maximum:SetPoint("BOTTOMLEFT", count, "BOTTOMRIGHT", 2, 2)
    S.SetFont(maximum, nil, 12, "OUTLINE")
    maximum:SetTextColor(.7, .84, .88)

    host:Hide()
    self.host, self.panel, self.edges, self.cooldown, self.title, self.count, self.maximum =
        host, panel, edges, cooldown, title, count, maximum
end

local function Place(self)
    local c = self.config
    local style = S.PaintQoLCard(ID, c, self.panel, self.edges)
    self.title:SetTextColor(S.RGB(style.muted))
    self.count:SetTextColor(S.RGB(style.text))
    self.maximum:SetTextColor(S.RGB(style.muted))
    self.host:SetSize(c.width, c.height)
    S.PlaceHost(self.host, c)
end

local function InSharedPool(self)
    local _, instanceType = GetInstanceInfo()
    if instanceType == "party" then return self.challengeActive == true end
    if instanceType == "raid" then return self.encounterActive == true end
    return false
end

local Update
local function ChargesChanged(self)
    Update(self)
end

local function WatchCharges(self, watch)
    if self.watching == watch then return end
    self.watching = watch
    if watch then
        self.context:Event("SPELL_UPDATE_CHARGES", ChargesChanged, true)
    else
        self.context:RemoveEvent("SPELL_UPDATE_CHARGES")
    end
end

Update = function(self)
    if not self.active then return end

    if S.editMode and not NS.IsCombatLocked() then
        WatchCharges(self, false)
        self.count:SetText("2")
        self.maximum:SetText("/3")
        self.cooldown:SetCooldown(GetTime(), 90)
        self.host:Show()
        return
    end

    local inPool = InSharedPool(self)
    WatchCharges(self, inPool)
    if not inPool then
        self.cooldown:Clear()
        self.host:Hide()
        return
    end

    -- The table and its current charge can be secret in combat. Only public
    -- fields guide Lua branches; Blizzard's display string goes to SetText.
    local info = C_Spell.GetSpellCharges(SPELL_ID)
    if not S.Public(info) or type(info) ~= "table" then
        self.cooldown:Clear()
        self.host:Hide()
        return
    end
    local maximum = info.maxCharges
    if not S.Finite(maximum) or maximum < 1 then
        self.cooldown:Clear()
        self.host:Hide()
        return
    end

    local display = C_Spell.GetSpellDisplayCount(SPELL_ID)
    if S.Public(display) and (type(display) ~= "string" or display == "") then display = "--" end
    self.count:SetText(display)
    self.maximum:SetFormattedText("/%d", math.floor(maximum))

    if info.isActive == true then
        local duration = C_Spell.GetSpellChargeDuration(SPELL_ID)
        if duration then
            self.cooldown:SetCooldownFromDurationObject(duration, true)
        else
            self.cooldown:Clear()
        end
    else
        self.cooldown:Clear()
    end
    self.host:Show()
end

local function ContextChanged(self, event)
    if event == "ENCOUNTER_START" then
        self.encounterActive = true
    elseif event == "ENCOUNTER_END" then
        self.encounterActive = false
    elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET"
        or event == "WORLD_STATE_TIMER_STOP" then
        self.challengeActive = false
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        self.encounterActive = EncounterActive()
        self.challengeActive = ChallengeActive()
    else
        self.challengeActive = ChallengeActive()
    end
    Update(self)
    if event == "CHALLENGE_MODE_START" and not self.challengeActive then self.startJob:Request() end
end

local function RecheckStart(self)
    self.challengeActive = ChallengeActive()
    Update(self)
end

function M:Enable()
    self.startJob = self.context:Coalesce(START_RECHECK, RecheckStart)
    Create(self)
    Place(self)
    self.encounterActive = EncounterActive()
    self.challengeActive = ChallengeActive()
    local context = self.context
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
        "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
        "WORLD_STATE_TIMER_START", "WORLD_STATE_TIMER_STOP", "ENCOUNTER_START", "ENCOUNTER_END" }) do
        context:Event(event, ContextChanged, true)
    end
    Update(self)
    self:RegisterMovers()
end

function M:Refresh()
    S.SetFont(self.title, nil, 11, "OUTLINE")
    S.SetFont(self.count, nil, 22, "OUTLINE")
    S.SetFont(self.maximum, nil, 12, "OUTLINE")
    Place(self)
    Update(self)
end

-- The context's Release drops a pending key recheck.
function M:Disable()
    if self.watching then WatchCharges(self, false) end
    if self.host then
        self.cooldown:Clear()
        self.host:Hide()
    end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "charges", {
        label = "Battle resurrection", order = 636,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return POINTS[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "width", "height", "scale" },
        sizeKeys = { "width", "height", "scale" },
    })
end

S.Install(ID, M)
