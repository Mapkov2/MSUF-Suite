local root = assert(arg[1], "repository root required")
local module, hook, now, leader, raid = nil, nil, 100, true, false
local sent, secret, notices = {}, {}, {}
local chatLocked = false
INSTANCE_RESET_SUCCESS = "%s has been reset."
GetTime = function() return now end
IsInGroup = function() return true end
IsInRaid = function() return raid end
UnitIsGroupLeader = function() return leader end
hooksecurefunc = function(name, fn) assert(name == "ResetInstances"); hook = fn end
-- A SendChatMessage call during chat lockdown is blocked and cannot be caught.
C_ChatInfo = { SendChatMessage = function(message, channel)
        assert(not chatLocked, "SendChatMessage called during chat messaging lockdown")
        sent[#sent + 1] = { message, channel }
    end,
    InChatMessagingLockdown = function() return chatLocked end }
local NS = assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().Platform(root,
    { C_ChatInfo = C_ChatInfo })
local S = { Install = function(_, m) module = m end, Public = function(v) return v ~= secret end,
    PublicText = function(v) return type(v) == "string" and v or nil end,
    Print = function(v) notices[#notices + 1] = v end,
    Text = function(v) return v end }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/MPlusResetReminder.lua"))("test", { NS = NS, Suite = S })
module.active, module.config = true, { announceReset = true }
module.context = { events = {}, Event = function(self, event, fn) self.events[event] = fn end,
    RemoveEvent = function(self, event) self.events[event] = nil end }
module:Enable()
local function Fire(message) module.context.events.CHAT_MSG_SYSTEM(module, "CHAT_MSG_SYSTEM", message) end
Fire("Test has been reset."); assert(#sent == 0, "other player's reset must not announce")
hook(); Fire("Test cannot be reset."); Fire(secret); assert(#sent == 0)
Fire("Test has been reset."); Fire("Test has been reset.")
assert(#sent == 1 and sent[1][2] == "PARTY", "confirmed reset should announce once")
now = 106; Fire("Second has been reset."); assert(#sent == 1, "late system messages must not be attributed")
hook(); leader = false; Fire("Second has been reset."); assert(#sent == 1)
leader, raid = true, true; Fire("Second has been reset.")
assert(#sent == 2 and sent[2][2] == "RAID")
hook(); chatLocked = true; Fire("Third has been reset.")
assert(#sent == 2 and notices[#notices] == "Chat messages are blocked here right now; the reset was not announced.",
    "a reset during chat lockdown was sent or went unexplained")
chatLocked = false
INSTANCE_RESET_SUCCESS = nil; module:Refresh()
assert(not module.context.events.CHAT_MSG_SYSTEM, "unknown native localization must fail closed")
module:Disable(); assert(not module.context.events.CHALLENGE_MODE_RESET)
print("Instance reset announcement: own request, native success template, dedup, leader, lockdown and timeout passed")
