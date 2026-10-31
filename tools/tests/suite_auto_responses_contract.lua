-- Automatic responses (MSUF_Suite_QualityOfLife/AutoResponses.lua) and the
-- muted sound files of the sound profiles (SoundProfiles.lua), run on the
-- real Suite core, module runtime and timers with a stand-in client.
-- Usage: suite_auto_responses_contract.lua <root> [Mainline|Forever]
local root = assert(arg[1], "repository root required")
local forever = arg[2] == "Forever"
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local reported = {}
securecallfunction = Support.Dispatcher(reported)
local secret = {}
issecretvalue = function(value) return value == secret end

------------------------------------------------------------------ the stand-in client
local world = { combat = false, encounter = false, delay = 0, summonLeft = 120, skipsStart = false,
    canTeleport = true }
local relations = { bnet = "bnfriend", wow = "wowfriend", guild = "guild", club = "club" }
local log, lines, lookups = {}, {}, 0
local function Log(entry) log[#log + 1] = entry end
-- What the game was asked since the last call, in order.
local function Took()
    local text = table.concat(log, ",")
    log = {}
    return text
end
MSUF_NS = { Client = { Family = "Mainline", Flavor = "Mainline", IsForever = forever,
    SupportsEvent = function() return true end } }
SlashCmdList = {}
InCombatLockdown = function() return world.combat end
UnitName = function() return "Tester" end
GetRealmName = function() return "Realm" end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) lines[#lines + 1] = text end }
C_SummonInfo = {
    GetSummonConfirmTimeLeft = function() return world.summonLeft end,
    IsSummonSkippingStartExperience = function() return world.skipsStart end,
    ConfirmSummon = function() Log("ConfirmSummon") end,
}
PlayerCanTeleport = function() return world.canTeleport end
GetCorpseRecoveryDelay = function() return world.delay end
C_InstanceEncounter = { IsEncounterInProgress = function() return world.encounter end }
AcceptResurrect = function() Log("AcceptResurrect") end
CancelDuel = function() Log("CancelDuel") end
C_PetBattles = { CancelPVPDuel = function() Log("CancelPVPDuel") end }
DeclineGroup = function() Log("DeclineGroup") end
StaticPopup_Hide = function(which) Log("hide " .. which) end
SocialQueueUtil_GetRelationshipInfo = function(guid)
    lookups = lookups + 1
    if guid == "broken" then error("relationship lookup failed") end
    if guid == "hidden" then return "Name", "", secret end
    return "Name", "", relations[guid]
end
local silenced, mutes, unmutes, soundLog = {}, 0, 0, {}
MuteSoundFile = function(id)
    mutes = mutes + 1
    silenced[id] = true
    soundLog[#soundLog + 1] = "mute " .. id
end
UnmuteSoundFile = function(id)
    unmutes = unmutes + 1
    silenced[id] = nil
    soundLog[#soundLog + 1] = "unmute " .. id
end
-- Frames record what they register; the game delivers only registered events.
local function Frame()
    local frame = { scripts = {}, events = {} }
    function frame:SetScript(key, value) self.scripts[key] = value end
    function frame:GetScript(key) return self.scripts[key] end
    function frame:RegisterEvent(key) self.events[key] = true end
    function frame:UnregisterEvent(key) self.events[key] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:IsForbidden() return false end
    return frame
end
CreateFrame = Frame
MSUF_PixelLayoutRegion = function(frame) return frame end
GameFontHighlightSmall = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }

------------------------------------------------------------------ the real Suite
local clock = Support.Clock()
local Suite = {}
MSUFSuite = Suite
Support.Load(root, "MSUF_Suite", Suite, "Core/Suite.lua")
assert(Suite.Database.Initialize(nil))
local private = {}
for _, file in ipairs({ "Surfaces", "Runtime", "Timers" }) do
    assert(loadfile(root .. "/MSUF_Suite_Modules/" .. file .. ".lua"))("MSUF_Suite_Modules", private)
end
local quality = {}
for _, file in ipairs({ "Bootstrap", "SharedItems", "TrustedPartyInvites", "AutoResponses", "SoundProfiles" }) do
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua"))("MSUF_Suite_QualityOfLife", quality)
end
local S = Suite.Suite
-- The CVar and instance helpers belong to other tests; no volume changes here.
S.RestoreCVar = function() end
S.InstanceKind = function() return "other" end

local function Check(value, message)
    if not value then error("suite_auto_responses_contract: " .. message, 2) end
end

local function Start(id, overrides)
    local module = S.instances[id]
    module.config = S.Config(id)
    for key, value in pairs(overrides or {}) do module.config[key] = value end
    module.context = module.context or S.NewContext(id)
    module.active = true
    module:Enable()
    return module
end

local function Registered(module, event)
    local frame = module.context.frame
    return frame ~= nil and frame.events[event] == true
end

-- The game sends only registered events; true when this one was delivered.
local function Fire(module, event, ...)
    if not Registered(module, event) then return false end
    local frame = module.context.frame
    frame.scripts.OnEvent(frame, event, ...)
    return true
end

local function Sorted(list)
    local copy = { unpack(list) }
    table.sort(copy)
    return table.concat(copy, ",")
end

------------------------------------------------------------------ catalog
local RESPONSE_KEYS = { "acceptSummon", "acceptResurrect", "declineDuel", "declinePetDuel", "declineInvite" }
local function CatalogContract()
    local spec = S.catalog.autoResponses
    Check(spec and spec.optIn and spec.automation and spec.defaultEnabled == false,
        "the module is not an opt-in automation module that starts off")
    for _, key in ipairs(RESPONSE_KEYS) do
        Check(spec.rules[key].default == false and spec.rules[key].automation == true,
            key .. " is not an automation switch that starts off")
    end
    Check(spec.rules.report.default == true and not spec.rules.report.automation, "the chat line switch is wrong")
    local imported = { suite = { modules = { autoResponses = { enabled = true, report = true } } } }
    for _, key in ipairs(RESPONSE_KEYS) do imported.suite.modules.autoResponses[key] = true end
    S.SanitizeImport(imported)
    for _, key in ipairs(RESPONSE_KEYS) do
        Check(imported.suite.modules.autoResponses[key] == false, "a shared profile kept " .. key .. " on")
    end
    Check(imported.suite.modules.autoResponses.enabled == false and imported.suite.modules.autoResponses.report,
        "a shared profile kept the module on, or lost the chat line switch")
end

------------------------------------------------------------------ the five responses
-- Per response: the event and its arguments, what the game is asked, the
-- chat line, and the events its switch registers (RESPONSE_EVENTS).
local STRANGER = { "Stranger-Realm", false, false, false, false, false, "stranger", false }
local CASES = {
    { key = "acceptSummon", event = "CONFIRM_SUMMON", args = { 1, false },
        took = "ConfirmSummon,hide CONFIRM_SUMMON,hide CONFIRM_SUMMON_SCENARIO", line = "Accepted a summon." },
    { key = "acceptResurrect", event = "RESURRECT_REQUEST", args = { "Healer" },
        took = "AcceptResurrect,hide RESURRECT,hide RESURRECT_NO_SICKNESS,hide RESURRECT_NO_TIMER",
        line = "Accepted a resurrection." },
    { key = "declineDuel", event = "DUEL_REQUESTED", args = { "Rival" },
        took = "CancelDuel,hide DUEL_REQUESTED,hide DUEL_TO_THE_DEATH_REQUESTED", line = "Declined a duel request." },
    { key = "declinePetDuel", event = "PET_BATTLE_PVP_DUEL_REQUESTED", args = { "Rival" },
        took = "CancelPVPDuel,hide PET_BATTLE_PVP_DUEL_REQUESTED", line = "Declined a pet battle duel request." },
    { key = "declineInvite", event = "PARTY_INVITE_REQUEST", args = STRANGER,
        took = "DeclineGroup,hide PARTY_INVITE",
        line = "Declined a party invite from someone who is not a friend or guild member." },
}
local RESPONSE_EVENTS = {
    acceptSummon = { "CONFIRM_SUMMON" }, acceptResurrect = { "RESURRECT_REQUEST" },
    declineDuel = { "DUEL_REQUESTED", forever and "DUEL_TO_THE_DEATH_REQUESTED" or nil },
    declinePetDuel = { "PET_BATTLE_PVP_DUEL_REQUESTED" },
    declineInvite = { "PARTY_INVITE_REQUEST", "PARTY_INVITE_CANCEL" },
}
local ALL_EVENTS = { "CONFIRM_SUMMON", "RESURRECT_REQUEST", "DUEL_REQUESTED", "DUEL_TO_THE_DEATH_REQUESTED",
    "PET_BATTLE_PVP_DUEL_REQUESTED", "PARTY_INVITE_REQUEST", "PARTY_INVITE_CANCEL" }

-- Only the events of the switches that are on are registered.
local function OnlyEvents(module, wanted, message)
    local expected = {}
    for _, event in ipairs(wanted) do expected[event] = true end
    for _, event in ipairs(ALL_EVENTS) do
        Check(Registered(module, event) == (expected[event] == true), message .. ": " .. event)
    end
end

local function SwitchedOff(module)
    for _, key in ipairs(RESPONSE_KEYS) do module.config[key] = false end
    module.config.report = true
    module:Refresh()
end

local function ResponseContract(module, case)
    SwitchedOff(module)
    OnlyEvents(module, {}, "a switch that is off still listens")
    Check(not Fire(module, case.event, unpack(case.args)) and Took() == "", case.key .. " answered while off")
    module.config[case.key] = true
    module:Refresh()
    OnlyEvents(module, RESPONSE_EVENTS[case.key], case.key .. " registered the wrong events")
    lines = {}
    Check(Fire(module, case.event, unpack(case.args)) and Took() == "", case.key .. " answered before the next frame")
    clock.Frame()
    Check(Took() == case.took, case.key .. " asked the game for: " .. tostring(log[1]))
    Check(#lines == 1 and lines[1]:find(case.line, 1, true), case.key .. " printed no single chat line")
    -- In combat nothing is answered, and nothing leaks into the next frame.
    world.combat = true
    Fire(module, case.event, unpack(case.args))
    clock.Frame()
    Check(Took() == "", case.key .. " answered in combat")
    -- Combat that starts after the event but before the answer.
    world.combat = false
    Fire(module, case.event, unpack(case.args))
    world.combat = true
    clock.Frame()
    world.combat = false
    Check(Took() == "", case.key .. " answered after combat started")
    -- The switch turned off after the event.
    Fire(module, case.event, unpack(case.args))
    module.config[case.key] = false
    module:Refresh()
    clock.Frame()
    Check(Took() == "", case.key .. " answered after its switch went off")
    OnlyEvents(module, {}, "a switch turned off still listens")
    -- The chat line is optional.
    module.config[case.key], module.config.report = true, false
    module:Refresh()
    lines = {}
    Fire(module, case.event, unpack(case.args))
    clock.Frame()
    Check(Took() == case.took and #lines == 0, case.key .. " ignored the chat line switch")
    -- Disable drops the registration and an answer still due.
    Fire(module, case.event, unpack(case.args))
    module.active = false
    module:Disable()
    clock.Frame()
    Check(Took() == "", case.key .. " answered after Disable")
    OnlyEvents(module, {}, "Disable left events registered")
    module.active = true
end

-- Per response: states in which the dialog stays the player's.
local REFUSED = {
    acceptSummon = { { skipsStart = true }, { skipsStart = secret }, { canTeleport = false }, { canTeleport = secret },
        { summonLeft = 0 }, { summonLeft = secret } },
    acceptResurrect = { { encounter = true }, { encounter = secret }, { delay = 30 }, { delay = secret } },
}

local function RefusalContract(module, case)
    module.config[case.key], module.config.report = true, true
    module:Refresh()
    for _, change in ipairs(REFUSED[case.key]) do
        local before = {}
        for field, value in pairs(change) do before[field], world[field] = world[field], value end
        Fire(module, case.event, unpack(case.args))
        clock.Frame()
        Check(Took() == "", case.key .. " answered in a state it must leave to the player: " .. next(change))
        for field, value in pairs(before) do world[field] = value end
    end
    SwitchedOff(module)
end

------------------------------------------------------------------ party invites
local function Invite(module, guid, tank, quest, name)
    Fire(module, "PARTY_INVITE_REQUEST", name or "Stranger-Realm", tank == true, false, false, false, false,
        guid, quest == true)
    clock.Frame()
    return Took() == "DeclineGroup,hide PARTY_INVITE"
end

local function InviteContract(module)
    module.config.declineInvite = true
    module:Refresh()
    Check(Invite(module, "stranger") and Invite(module, "club"), "a stranger or community member was not declined")
    for _, guid in ipairs({ "bnet", "wow", "guild" }) do
        Check(not Invite(module, guid), "a trusted sender was declined: " .. guid)
    end
    Check(not Invite(module, "stranger", true), "a group finder role invite was declined")
    Check(not Invite(module, "stranger", false, true), "a quest session invite was declined")
    Check(not Invite(module, secret) and not Invite(module, "stranger", false, false, secret),
        "an invite with a secret guid or name was declined")
    Check(not Invite(module, "hidden"), "an invite with a secret relationship was declined")
    Check(not Invite(module, "broken"), "a failed relationship lookup declined the invite")
    Check(#reported == 1, "a failed relationship lookup was not reported")
    reported[1] = nil
    -- A cancelled invite, and a newer one from a friend, drop the answer due.
    Fire(module, "PARTY_INVITE_REQUEST", unpack(STRANGER))
    Fire(module, "PARTY_INVITE_CANCEL")
    clock.Frame()
    Check(Took() == "", "a cancelled invite was declined")
    Fire(module, "PARTY_INVITE_REQUEST", unpack(STRANGER))
    Fire(module, "PARTY_INVITE_REQUEST", "Friend-Realm", false, false, false, false, false, "bnet", false)
    clock.Frame()
    Check(Took() == "", "a stranger's invite was declined after a friend's replaced it")
    -- No relationship lookup is spent in combat.
    local before = lookups
    world.combat = true
    Invite(module, "stranger")
    world.combat = false
    Check(lookups == before, "combat still looked up the inviter")
    SwitchedOff(module)
end

-- Forever shows Blizzard's hardcore duel from its own code: one more event for the same switch.
local function DeathDuelContract(module)
    module.config.declineDuel = true
    module:Refresh()
    Check(Fire(module, "DUEL_TO_THE_DEATH_REQUESTED", "Rival"), "the duel to the death is not listened for")
    clock.Frame()
    Check(Took() == "CancelDuel,hide DUEL_REQUESTED,hide DUEL_TO_THE_DEATH_REQUESTED", "the duel to the death stayed open")
    SwitchedOff(module)
end

------------------------------------------------------------------ sound files
local function SoundContract()
    local rule = S.catalog.soundProfiles.rules.mutedFileIDs
    Check(rule.ids == true and rule.default == "", "the muted sound file list is not an empty ID list")
    Check(S.CheckProfileValue(rule, "12, 34 56") == "12, 34 56", "a list of IDs was refused")
    Check(not S.CheckProfileValue(rule, "12, abc") and not S.CheckProfileValue(rule, "1;2")
        and not S.CheckProfileValue(rule, string.rep("1", rule.maxLength + 1)) and not S.CheckProfileValue(rule, 12),
        "an invalid sound file list was accepted")
    local sound = Start("soundProfiles", { mutedFileIDs = "111, 222 333" })
    local events = 0
    for _ in pairs(sound.context.callbacks) do events = events + 1 end
    Check(events == 3, "muting registered events of its own")
    Check(Sorted(soundLog) == "mute 111,mute 222,mute 333" and silenced[222], "enable did not mute the list")
    soundLog = {}
    sound.config.mutedFileIDs = "222, 444"
    sound:Refresh()
    Check(Sorted(soundLog) == "mute 444,unmute 111,unmute 333" and silenced[222] and silenced[444]
        and not silenced[111] and not silenced[333], "a list edit did not mute the new and unmute the removed")
    soundLog = {}
    sound:Refresh()
    Check(#soundLog == 0, "a refresh without an edit muted or unmuted again")
    sound.config.mutedFileIDs = "0 -5 1.5 99999999 abc 7 7"
    sound:Refresh()
    Check(Sorted(soundLog) == "mute 7,unmute 222,unmute 444" and next(silenced) == 7 and not next(silenced, 7),
        "invalid or repeated IDs were muted")
    local many = {}
    for id = 1000, 1249 do many[#many + 1] = id end
    sound.config.mutedFileIDs = table.concat(many, ",")
    sound:Refresh()
    local count = 0
    for _ in pairs(silenced) do count = count + 1 end
    Check(count == 200, "the list was not limited to 200 files: " .. count)
    sound.active = false
    sound:Disable()
    Check(not next(silenced) and mutes == unmutes, "disable left a file muted")
    sound.active = true
    sound:Enable()
    Check(silenced[1000] and silenced[1199] and not silenced[1200], "enable after disable did not mute again")
    sound.active = false
    sound:Disable()
    Check(not next(silenced) and mutes == unmutes, "mute and unmute calls are not symmetric")
end

CatalogContract()
local responses = Start("autoResponses")
OnlyEvents(responses, {}, "the module listens with every switch off")
for _, case in ipairs(CASES) do
    ResponseContract(responses, case)
    if REFUSED[case.key] then RefusalContract(responses, case) end
end
InviteContract(responses)
if forever then DeathDuelContract(responses) end
Check(next(S.instances.autoResponses.context.callbacks) == nil, "events remain after all switches went off")
SoundContract()
Check(#reported == 0, "an unexpected error was reported: " .. tostring(reported[1]))
print("PASS automatic responses and muted sound files (" .. (forever and "Forever" or "Mainline") .. ")")
