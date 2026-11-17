local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local CHAT_LIMIT = 64
local CVARS = { "chatMouseScroll", "chatClassColorOverride", "whisperMode" }
local WHISPER = { [2] = "popout", [3] = "popout_and_inline" }

local function SetCVar(self, key, value)
    if not value then
        S.RestoreCVar(self.id, key)
        self.applied[key] = nil
    elseif self.applied[key] ~= value and self.context:CVar(key, value) then
        self.applied[key] = value
    end
end

local function ReleaseFading()
    for frame, record in pairs(S.chatFading) do
        if record.keep and not NS.Safety.IsForbidden(frame) then
            S.HoldChatFading(frame, "keep", nil)
        end
    end
end

local function ChatWindowsChanged()
    if not M.active or not M.config.noChatFade then return end
    -- Suite.ChatState reports can arrive in combat.
    if NS.InCombat() then
        S.Queue("chatComfort")
        return
    end
    local count = 0
    for _, name in pairs(CHAT_FRAMES) do
        if count >= CHAT_LIMIT then break end
        count = count + 1
        local frame = _G[name]
        if frame and not NS.Safety.IsForbidden(frame) then
            S.HoldChatFading(frame, "keep", true)
        end
    end
end

-- New and temporary windows arrive with Suite.ChatState's window report
-- (chat window events, whisper events and the open-window check), never
-- through a post-hook on FCF_OpenNewWindow or FCF_OpenTemporaryWindow,
-- which run inside the tab menu and the whisper router.
local COMFORT_WATCH = { windows = ChatWindowsChanged }

local function SyncFading(self)
    if not self.config.noChatFade then
        ReleaseFading()
        NS.ChatState.Unwatch(self)
        return
    end
    ChatWindowsChanged()
    NS.ChatState.Watch(self, COMFORT_WATCH)
end

function M:Refresh()
    SetCVar(self, CVARS[1], self.config.chatWheel and "1")
    SetCVar(self, CVARS[2], self.config.chatClassColors and "0")
    SetCVar(self, CVARS[3], WHISPER[self.config.whisperWindows])
    SyncFading(self)
end

function M:Enable()
    for _, key in ipairs(CVARS) do S.RestoreCVar("dailyComfort", key) end
    self.applied = {}
    self:Refresh()
end

function M:Disable()
    NS.ChatState.Unwatch(self)
    ReleaseFading()
    self.applied = nil
end

S.Install("chatComfort", M)
