local root = assert(arg[1], "repository root required")
local installed, deferred, notices = {}, {}, {}
local suite = {
    Install = function(id, module) installed[id] = module end,
    Public = function(value) return value ~= "secret" end,
    PublicText = function(value)
        return value ~= "secret" and type(value) == "string" and value ~= "" and value or nil
    end,
    Text = function(value) return value end,
    Print = function(value) notices[#notices + 1] = value end,
}
local combat, grouped, queueLoss = false, false, false
local ns = {
    IsCombatLocked = function() return combat end,
    Safety = { IsForbidden = function() return false end },
}
local relations = { bnet = "bnfriend", wow = "wowfriend", guild = "guild", club = "club" }
SocialQueueUtil_GetRelationshipInfo = function(guid)
    return "Name", "", relations[guid]
end
IsInGroup = function() return grouped end
WillAcceptInviteRemoveQueues = function() return queueLoss end
C_Timer = { After = function(delay, callback)
    assert(delay == 0)
    deferred[#deferred + 1] = callback
end }
local dialog = { which = "PARTY_INVITE", shown = true, text = "Name-Realm invites you to a group." }
function dialog:IsShown() return self.shown end
function dialog:GetTextFontString()
    return { GetText = function() return self.text end }
end
StaticPopup_FindVisible = function(which)
    assert(which == "PARTY_INVITE")
    return dialog.shown and dialog or nil
end
local accepts, blocked = 0, false
StaticPopup_OnClick = function(frame, index)
    assert(frame == dialog and index == 1)
    if blocked then error("restricted accept") end
    accepts = accepts + 1
    frame.shown = false
end
local function context()
    return { events = {},
        Event = function(self, event, callback) self.events[event] = callback end,
        RemoveEvent = function(self, event) self.events[event] = nil end,
    }
end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TrustedPartyInvites.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
local module = assert(installed.trustedPartyInvites)
module.active = true
module.config = { battleNet = true, wowFriends = true, guild = false }
module.context = context()
module:Enable()
assert(module.context.events.PARTY_INVITE_REQUEST and module.context.events.PARTY_INVITE_CANCEL)
local function invite(guid, tank, healer, damage, quest)
    module.context.events.PARTY_INVITE_REQUEST(module, "PARTY_INVITE_REQUEST", "Name-Realm",
        tank == true, healer == true, damage == true, false, false, guid, quest == true)
end
local function nextFrame()
    local pending = deferred
    deferred = {}
    for i = 1, #pending do pending[i]() end
end

invite("bnet")
assert(#deferred == 1 and accepts == 0, "invite was handled before Blizzard's popup")
nextFrame()
assert(accepts == 1 and not dialog.shown, "trusted Battle.net invite was not accepted")
dialog.shown = true
invite("wow")
nextFrame()
assert(accepts == 2, "trusted WoW friend invite was not accepted")
dialog.shown = true
dialog.text = "Another player invites you to a group."
invite("bnet")
nextFrame()
assert(accepts == 2, "stale popup from another inviter was accepted")
dialog.text = "Name-Realm invites you to a group."
dialog.shown = true
invite("guild")
invite("club")
nextFrame()
assert(accepts == 2, "unselected relationship was accepted")
module.config.guild = true
invite("guild")
nextFrame()
assert(accepts == 3, "selected guild relationship was ignored")

dialog.shown = true
for _, case in ipairs({
    { guid = "bnet", tank = true }, { guid = "bnet", healer = true },
    { guid = "bnet", damage = true }, { guid = "bnet", quest = true },
}) do
    invite(case.guid, case.tank, case.healer, case.damage, case.quest)
end
nextFrame()
assert(accepts == 3, "role or quest-session invite bypassed Blizzard confirmation")
queueLoss = true
invite("bnet")
nextFrame()
assert(accepts == 3, "an invite removed an active queue")
queueLoss = false
grouped = true
invite("bnet")
nextFrame()
assert(accepts == 3, "a grouped player accepted an invitation")
grouped = false
combat = true
invite("bnet")
nextFrame()
assert(accepts == 3, "an invitation was accepted in combat")
combat = false
invite("secret")
nextFrame()
assert(accepts == 3, "secret invitation identity was accepted")

invite("bnet")
module.context.events.PARTY_INVITE_CANCEL(module)
nextFrame()
assert(accepts == 3, "cancelled invitation was accepted later")
invite("bnet")
module:Refresh()
nextFrame()
assert(accepts == 3, "stale invite survived a settings refresh")

blocked = true
invite("bnet")
nextFrame()
assert(accepts == 3 and #notices == 1 and dialog.shown,
    "restricted native accept did not leave the manual dialog open")
blocked = false
invite("bnet")
module.active = false
module:Disable()
nextFrame()
assert(accepts == 3 and not module.context.events.PARTY_INVITE_REQUEST,
    "disabled helper accepted a deferred invitation")
print("Suite trusted party invitation lifecycle passed")
