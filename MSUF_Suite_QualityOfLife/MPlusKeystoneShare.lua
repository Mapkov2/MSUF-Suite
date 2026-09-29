local _, P = ...
local S = P.Suite

local M = {}
local COMMAND = "MSUFSUITEKEYS"
local PREFIX = "MSUFKEY1"

local function AliasInUse(alias)
    for key, callback in pairs(SlashCmdList) do
        if key ~= COMMAND and type(callback) == "function" then
            for index = 1, 12 do
                local value = _G["SLASH_" .. key .. index]
                if type(value) == "string" and value:lower() == alias then return true end
            end
        end
    end
    return false
end

local function OwnKeystone()
    local mythic, challenge = C_MythicPlus, C_ChallengeMode
    local mapID = mythic.GetOwnedKeystoneChallengeMapID()
    local level = mythic.GetOwnedKeystoneLevel()
    if not S.Finite(mapID) or mapID < 1 or not S.Finite(level) or level < 2 then return nil end
    local name = S.PublicText(challenge.GetMapUIInfo(mapID))
    if not name then return nil end
    return string.format(S.Text("Keystone: %s +%d"), name, math.floor(level)), mapID, level
end

local function GroupChannel()
    local inParty, inRaid, inInstance = IsInGroup(), IsInRaid(), IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    if not S.Public(inParty) or not S.Public(inRaid) or not S.Public(inInstance) then return nil end
    if inInstance == true then return "INSTANCE_CHAT" end
    if inRaid == true then return "RAID" end
    if inParty == true then return "PARTY" end
end

local function OnAddonMessage(self, _, prefix, payload, channel, sender)
    if not self.active or not S.PublicText(prefix) or prefix ~= PREFIX
        or not S.PublicText(payload) or not S.PublicText(channel)
        or not S.PublicText(sender) then return end
    if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then return end
    local ownName, ownRealm = UnitFullName("player")
    if S.PublicText(ownName) and (sender == ownName
        or (S.PublicText(ownRealm) and sender == ownName .. "-" .. ownRealm)) then return end
    local current = GroupChannel()
    if not current or channel ~= current then return end
    local now = GetTime()
    if not S.Finite(now) then return end
    if payload == "Q" then
        if self.lastResponseAt and now - self.lastResponseAt < 5 then return end
        local _, mapID, level = OwnKeystone()
        if not mapID then return end
        self.lastResponseAt = now
        C_ChatInfo.SendAddonMessage(PREFIX, string.format("K:%d:%d", mapID, math.floor(level)), channel)
        return
    end
    if not self.requestExpiresAt or now > self.requestExpiresAt then return end
    local mapText, levelText = payload:match("^K:(%d+):(%d+)$")
    local mapID, level = tonumber(mapText), tonumber(levelText)
    if not S.Finite(mapID) or mapID < 1 or mapID > 100000
        or not S.Finite(level) or level < 2 or level > 99
        or self.seen[sender] then return end
    local name = S.PublicText(C_ChallengeMode.GetMapUIInfo(mapID))
    if not name then return end
    self.seen[sender] = true
    S.Print(string.format(S.Text("%s: %s +%d"), sender, name, level))
end

local function Command(message)
    if not M.active then return end
    if not S.Public(message) or type(message) ~= "string" then return end
    local mode = message:lower():match("^%s*(.-)%s*$")
    if mode == "group" then
        local channel = GroupChannel()
        if not channel then
            S.Print(S.Text("Join a group to request Suite keystones"))
            return
        end
        local now = GetTime()
        if not S.Finite(now) or (M.lastRequestAt and now - M.lastRequestAt < 2) then return end
        M.lastRequestAt, M.requestExpiresAt, M.seen = now, now + 5, {}
        local own = OwnKeystone()
        if own then S.Print(own) end
        C_ChatInfo.SendAddonMessage(PREFIX, "Q", channel)
        return
    end
    local text = OwnKeystone()
    if not text then
        S.Print(S.Text("No owned keystone found"))
        return
    end
    if mode == "" or mode == "self" then
        S.Print(text)
        return
    end
    local channel
    local inParty, inRaid, inInstance = IsInGroup(), IsInRaid(), IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    if mode == "party" and S.Public(inParty) and inParty == true then channel = "PARTY"
    elseif mode == "raid" and S.Public(inRaid) and inRaid == true then channel = "RAID"
    elseif mode == "instance" and S.Public(inInstance) and inInstance == true then channel = "INSTANCE_CHAT" end
    if not channel then
        S.Print(S.Text("Usage: /keys [self|party|raid|instance|group]"))
        return
    end
    C_ChatInfo.SendChatMessage(text, channel)
end

function M:Enable()
    _G["SLASH_" .. COMMAND .. "1"] = "/msufkeys"
    _G["SLASH_" .. COMMAND .. "2"] = not AliasInUse("/keys") and "/keys" or nil
    SlashCmdList[COMMAND] = Command
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    self.context:Event("CHAT_MSG_ADDON", OnAddonMessage, true)
end

function M:Refresh()
    if AliasInUse("/keys") then
        _G["SLASH_" .. COMMAND .. "2"] = nil
    elseif not _G["SLASH_" .. COMMAND .. "2"] then
        _G["SLASH_" .. COMMAND .. "2"] = "/keys"
    end
end

function M:Disable()
    self.context:RemoveEvent("CHAT_MSG_ADDON")
    self.requestExpiresAt, self.seen, self.lastResponseAt, self.lastRequestAt = nil, nil, nil, nil
    SlashCmdList[COMMAND] = nil
    _G["SLASH_" .. COMMAND .. "1"] = nil
    _G["SLASH_" .. COMMAND .. "2"] = nil
end

S.Install("mythicKeyShare", M)
