local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }
local M = { config = {} }

local function OnReset(self)
    if self.active then S.Print(S.Text("Keystone was reset")) end
end

local function SuccessPattern()
    local template = S.PublicText(_G.INSTANCE_RESET_SUCCESS)
    if not template or not template:find("%%s") then return nil end
    template = template:gsub("%%s", "\001")
    template = template:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    return "^" .. template:gsub("\001", ".+") .. "$"
end

local function SystemMessage(self, _, message)
    if not self.active or not self.config.announceReset or not self.resetAt
        or GetTime() - self.resetAt > 5 or not S.PublicText(message) or #message > 255
        or not self.successPattern or not message:match(self.successPattern) then return end
    local grouped, raid, leader = IsInGroup(), IsInRaid(), UnitIsGroupLeader("player")
    if not S.Public(grouped) or grouped ~= true or not S.Public(raid)
        or not S.Public(leader) or leader ~= true or self.resetMessages[message] then return end
    if self.resetCount >= 32 then return end
    self.resetMessages[message], self.resetCount = true, self.resetCount + 1
    -- A blocked SendChatMessage cannot be caught; say so locally instead.
    if NS.ChatLocked() then
        S.Print(S.Text("Chat messages are blocked here right now; the reset was not announced."))
        return
    end
    C_ChatInfo.SendChatMessage(message, raid and "RAID" or "PARTY")
end

function M:Refresh()
    self.resetAt = nil
    self.successPattern = SuccessPattern()
    if self.config.announceReset and self.successPattern then
        if not self.resetHooked then
            hooksecurefunc("ResetInstances", function()
                if self.active and self.config.announceReset then
                    self.resetAt, self.resetMessages, self.resetCount = GetTime(), {}, 0
                end
            end)
            self.resetHooked = true
        end
        self.context:Event("CHAT_MSG_SYSTEM", SystemMessage, IN_COMBAT)
    else
        self.context:RemoveEvent("CHAT_MSG_SYSTEM")
    end
end

function M:Enable()
    self.context:Event("CHALLENGE_MODE_RESET", OnReset, IN_COMBAT)
    self:Refresh()
end

function M:Disable()
    self.context:RemoveEvent("CHALLENGE_MODE_RESET")
    self.context:RemoveEvent("CHAT_MSG_SYSTEM")
    self.resetAt = nil
end

S.Install("mythicResetReminder", M)
