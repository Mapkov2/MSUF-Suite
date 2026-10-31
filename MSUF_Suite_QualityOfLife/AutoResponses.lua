local _, P = ...
local NS, S = P.NS, P.Suite

-- Automatic answers to Blizzard's popups: a summon, a resurrection, a duel, a
-- pet battle duel and a party invite from a stranger. Each has its own switch
-- (autoResponses.<key>) and its events are registered only while that switch
-- is on. A request is answered on the next frame, since the event can reach
-- addons before Blizzard shows its dialog, and only out of combat; in combat
-- the dialog stays the player's. The answer is the game's own call, then
-- Blizzard's dialog is hidden with StaticPopup_Hide (a call: StaticPopupDialogs
-- is never written).
local M = {}

local SUMMON_POPUPS = { "CONFIRM_SUMMON", "CONFIRM_SUMMON_SCENARIO" }
local RESURRECT_POPUPS = { "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }
local DUEL_POPUPS = { "DUEL_REQUESTED", "DUEL_TO_THE_DEATH_REQUESTED" }
local PET_DUEL_POPUPS = { "PET_BATTLE_PVP_DUEL_REQUESTED" }
local INVITE_POPUPS = { "PARTY_INVITE" }
-- The relationships (SocialQueueUtil_GetRelationshipInfo) never declined.
local SPARED = { bnfriend = true, wowfriend = true, guild = true }

local DUEL_EVENTS = { "DUEL_REQUESTED" }
-- Forever only: Blizzard shows this hardcore duel from its Vanilla and
-- Camelot code (upstream/forever Blizzard_Game); Retail never sends it.
if NS.Client.isForever then DUEL_EVENTS[2] = "DUEL_TO_THE_DEATH_REQUESTED" end

local function Exactly(value, expected)
    return S.Public(value) and value == expected
end

-- The switch is on and the player is out of combat (NS.InCombat counts the
-- moment combat starts, before InCombatLockdown does).
local function Allowed(self, key)
    return self.config[key] == true and not NS.InCombat()
end

local function Hide(popups)
    for i = 1, #popups do StaticPopup_Hide(popups[i]) end
end

local function Report(self, text)
    if self.config.report then S.Print(text) end
end

local function AnswerSummon(self)
    if not Allowed(self, "acceptSummon") then return end
    local left = C_SummonInfo.GetSummonConfirmTimeLeft()
    -- A summon that ran out or was withdrawn needs no answer. One that skips
    -- a starting area, and one the player cannot take right now (Blizzard
    -- turns its accept button off then too), stay manual.
    if not (S.Finite(left) and left > 0)
        or not Exactly(C_SummonInfo.IsSummonSkippingStartExperience(), false)
        or not Exactly(PlayerCanTeleport(), true) then return end
    C_SummonInfo.ConfirmSummon()
    Hide(SUMMON_POPUPS)
    Report(self, S.Text("Accepted a summon."))
end

local function AnswerResurrect(self)
    if not Allowed(self, "acceptResurrect") then return end
    -- A dead player is out of combat while the raid still fights, so the
    -- encounter is checked as well: a resurrection offered then is a battle
    -- resurrection, and taking it stays a choice. Blizzard's dialog also keeps
    -- its accept button off until the corpse recovery delay is over.
    local delay = GetCorpseRecoveryDelay()
    if not Exactly(C_InstanceEncounter.IsEncounterInProgress(), false)
        or not (S.Finite(delay) and delay <= 0) then return end
    AcceptResurrect()
    Hide(RESURRECT_POPUPS)
    Report(self, S.Text("Accepted a resurrection."))
end

local function AnswerDuel(self)
    if not Allowed(self, "declineDuel") then return end
    CancelDuel()
    Hide(DUEL_POPUPS)
    Report(self, S.Text("Declined a duel request."))
end

local function AnswerPetDuel(self)
    if not Allowed(self, "declinePetDuel") then return end
    C_PetBattles.CancelPVPDuel()
    Hide(PET_DUEL_POPUPS)
    Report(self, S.Text("Declined a pet battle duel request."))
end

local function AnswerInvite(self)
    if not Allowed(self, "declineInvite") then return end
    DeclineGroup()
    Hide(INVITE_POPUPS)
    Report(self, S.Text("Declined a party invite from someone who is not a friend or guild member."))
end

local ANSWERS = {
    CONFIRM_SUMMON = AnswerSummon,
    RESURRECT_REQUEST = AnswerResurrect,
    DUEL_REQUESTED = AnswerDuel,
    DUEL_TO_THE_DEATH_REQUESTED = AnswerDuel,
    PET_BATTLE_PVP_DUEL_REQUESTED = AnswerPetDuel,
}

local function OnRequest(self, event)
    self.context:After(0, ANSWERS[event])
end

-- Only an ordinary invite from a stranger is declined, and only when the
-- relationship lookup worked: an invite that asks for a group finder role, a
-- quest session invite, or a failed lookup stays the player's.
local function OnInvite(self, _, name, tank, healer, damage, _, _, guid, questSession)
    self.context:Cancel(AnswerInvite)
    if not Allowed(self, "declineInvite") or not S.PublicText(name) or not S.PublicText(guid)
        or not S.PlainInvite(tank, healer, damage, questSession) then return end
    local ok, relation = S.InviteRelation(guid, name)
    if ok and not SPARED[relation] then self.context:After(0, AnswerInvite) end
end

local function OnInviteCancel(self)
    self.context:Cancel(AnswerInvite)
end

local CALLBACKS = { PARTY_INVITE_REQUEST = OnInvite, PARTY_INVITE_CANCEL = OnInviteCancel }
-- The events each switch needs.
local RESPONSES = {
    acceptSummon = { "CONFIRM_SUMMON" },
    acceptResurrect = { "RESURRECT_REQUEST" },
    declineDuel = DUEL_EVENTS,
    declinePetDuel = { "PET_BATTLE_PVP_DUEL_REQUESTED" },
    declineInvite = { "PARTY_INVITE_REQUEST", "PARTY_INVITE_CANCEL" },
}

local function Listen(self, active)
    for key, events in pairs(RESPONSES) do
        local on = active and self.config[key] == true
        for i = 1, #events do
            local event = events[i]
            if on then
                self.context:Event(event, CALLBACKS[event] or OnRequest)
            else
                self.context:RemoveEvent(event)
            end
        end
    end
end

function M:Enable() Listen(self, true) end
M.Refresh = M.Enable
function M:Disable() Listen(self, false) end

S.Install("autoResponses", M)
