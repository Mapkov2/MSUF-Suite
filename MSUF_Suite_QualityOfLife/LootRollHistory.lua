local _, P = ...
local NS, S = P.NS, P.Suite
local Field = NS.AppearancePrimitives.Safety.Field
local H = {}
P.LootRollHistory = H

function H.Location()
    local _, kind, difficulty, _, _, _, _, id = GetInstanceInfo()
    kind = S.PublicText(kind)
    if kind == "none" then return kind end
    if kind and S.Finite(id) and S.Finite(difficulty) then
        return ("%s:%d:%d"):format(kind, id, difficulty)
    end
end

function H.Time()
    local clock = Field(C_LootHistory, "GetLootHistoryTime")
    if type(clock) ~= "function" then return end
    local time = clock()
    if S.Finite(time) then return time end
end

function H.Reset(self)
    self.archive, self.archiveOrder, self.lootWins = {}, {}, {}
end

local function WinnerKey(entry)
    return entry and entry.winner and entry.winner.key
end

function H.Record(self, entry)
    local token = entry.token
    local old = self.archive[token]
    if not old then
        local order = self.archiveOrder
        local position = #order + 1
        if entry.startedAt then
            while position > 1 do
                local previous = self.archive[order[position - 1]].startedAt
                if not previous or previous <= entry.startedAt then break end
                position = position - 1
            end
        end
        table.insert(order, position, token)
    elseif old.finished and not entry.finished then
        return
    end
    self.archive[token] = entry
    local previous, winner = WinnerKey(old), WinnerKey(entry)
    if previous == winner then return end
    if previous then
        local count = self.lootWins[previous] - 1
        self.lootWins[previous] = count > 0 and count or nil
    end
    if winner then self.lootWins[winner] = (self.lootWins[winner] or 0) + 1 end
end

local function GroupChannel()
    local instance = IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    if S.Public(instance) and instance == true then return "INSTANCE_CHAT" end
    local raid = IsInRaid()
    if S.Public(raid) and raid == true then return "RAID" end
    local party = IsInGroup()
    if S.Public(party) and party == true then return "PARTY" end
end

function H.Share(entry)
    if not entry or not entry.finished or not entry.link then return end
    local winner = entry.winner
    local result = winner and winner.name or entry.statusText
    if not result then return end
    local channel = GroupChannel()
    if not channel then
        S.Print(S.Text("Join a group to share a loot result."))
        return
    end
    if NS.ChatLocked() then
        S.Print(S.Text("Chat messages are blocked here right now."))
        return
    end
    if winner and winner.label and winner.roll then
        result = ("%s (%s %d)"):format(result, winner.label, winner.roll)
    end
    local message = ("%s — %s"):format(entry.link, result)
    -- Chat accepts at most 255 bytes. Keep hyperlinks intact.
    if #message > 255 then message = ("%s — %s"):format(entry.name or entry.link, result) end
    if #message > 255 then
        if #result > 255 then return end
        message = result
    end
    C_ChatInfo.SendChatMessage(message, channel)
end

function H.Link(entry)
    if entry and entry.link and IsModifiedClick("CHATLINK") and not NS.ChatLocked() then
        return HandleModifiedItemClick(entry.link)
    end
end
