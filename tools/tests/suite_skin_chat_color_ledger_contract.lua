-- The skin's chat message colours are a persistent client setting. The Suite
-- keeps a ledger of what the skin wrote in its saved variables, so a colour
-- left behind by a session that ended without PLAYER_LOGOUT is put back on
-- the next login: by the skin, which knows its leftover even after the theme
-- changed, and by the Suite itself once the skin is off. Real
-- MSUF_Suite/Core/CharacterData.lua, MSUF_Suite/Integrations/MapkoSkin.lua
-- and the skin's Safety.lua, AdapterKit.lua and ChatFrames.lua.
--
-- Worst case modelled: ChangeChatColor writes the chat cache at once, while
-- saved variables are written only by a clean logout or reload, after the
-- PLAYER_LOGOUT handlers ran.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2, table.maxn(results))
end
function hooksecurefunc(target, method, callback)
    if type(target) == "string" then target, method, callback = _G, target, method end
    local original = target[method]
    target[method] = function(...)
        original(...)
        callback(...)
    end
end
UnitGUID = function() return "Player-1" end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = DeepCopy(item) end
    return copy
end

local DEFAULTS = { SYSTEM = { 1, 1, 0 }, MONSTER_SAY = { 1, 1, 159 / 255 }, MONSTER_PARTY = { 170 / 255, 170 / 255, 1 } }
local THEME_A = { 0.84, 0.68, 0.44 }
local THEME_B = { 0.30, 0.55, 0.90 }
local PICKED = { 0.2, 0.9, 0.3 }

-- What survives a session: the character's chat cache and the saved
-- variables of the last clean logout.
local disk = { chat = DeepCopy(DEFAULTS), saved = nil }
local writes = 0
local theme = THEME_A

local function Is(chatType, color)
    local info = ChatTypeInfo[chatType]
    return math.abs(info.r - color[1]) < 1e-6 and math.abs(info.g - color[2]) < 1e-6
        and math.abs(info.b - color[3]) < 1e-6
end
local function CacheIs(chatType, color)
    local stored = disk.chat[chatType]
    return math.abs(stored[1] - color[1]) < 1e-6 and math.abs(stored[2] - color[2]) < 1e-6
        and math.abs(stored[3] - color[3]) < 1e-6
end

-- Blizzard's own function: the colour reaches ChatTypeInfo (UPDATE_CHAT_COLOR
-- runs inside the call) and the chat cache at once.
local function NativeChangeChatColor(chatType, r, g, b)
    writes = writes + 1
    local info = ChatTypeInfo[chatType]
    info.r, info.g, info.b = r, g, b
    disk.chat[chatType] = { r, g, b }
end

-- One game session: the saved variables and the chat cache load, the skin
-- (when on) applies at PLAYER_LOGIN, the Suite settles at the first
-- PLAYER_ENTERING_WORLD.
local function Session(skinOn)
    ChatTypeInfo = {}
    for chatType, color in pairs(disk.chat) do
        ChatTypeInfo[chatType] = { r = color[1], g = color[2], b = color[3] }
    end
    _G.ChangeChatColor = NativeChangeChatColor
    CHAT_FRAMES = {}
    writes = 0
    local Suite = {
        RootDB = DeepCopy(disk.saved) or {},
        Dispatch = securecallfunction,
        Finish = function(callback, ...) return true, callback(...) end,
    }
    function Suite.PublicText(value) return type(value) == "string" and value ~= "" and value or nil end
    function Suite.Finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
    _G.MSUFSuite = Suite
    assert(loadfile(root .. "/MSUF_Suite/Core/CharacterData.lua"))("MSUF_Suite", Suite)
    assert(loadfile(root .. "/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite", Suite)
    local session = { Suite = Suite }
    if skinOn then
        local NS = {
            IsCombatLocked = function() return false end,
            Theme = { GetColor = function(role)
                if role == "blizzardYellow" then return theme[1], theme[2], theme[3], 1 end
                return 1, 1, 1, 1
            end },
            Registry = { AddListener = Noop, QueueJob = function(job) job() end },
            Checkmarks = { TrackTexture = Noop, UntrackTexture = Noop, UntrackOwner = Noop },
            WindowActionSkin = { Apply = function() return nil, "owned by another adapter" end },
            CombatGate = { Cancel = Noop, RunOrDefer = Noop },
        }
        for _, file in ipairs({ "Core/Safety.lua", "Adapters/AdapterKit.lua", "Adapters/ChatFrames.lua" }) do
            assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
        end
        local chatFrame = {}
        function chatFrame:IsForbidden() return false end
        function chatFrame:IsProtected() return false, false end
        function chatFrame:GetName() return "ChatFrame1" end
        assert(NS.ChatFramesSkin.Apply(chatFrame, "chat"), "the chat skin did not apply")
        session.chat, session.frame = NS.ChatFramesSkin, chatFrame
    end
    session.settled = Suite.Skin.SettleChatColors()
    return session
end

-- A clean logout or reload: PLAYER_LOGOUT, then the saved variables.
local function Logout(session)
    if session.chat then session.chat.RestoreBlizzardMessageColors() end
    disk.saved = DeepCopy(session.Suite.RootDB)
end

local function Ledger()
    local characters = disk.saved and disk.saved.suiteCharacters
    local own = characters and characters["Player-1"]
    return own and own.skinChatColors
end

-- 1. A clean session: themed, put back at logout. The saved ledger keeps
-- what the skin wrote for the next session's sake.
local session = Session(true)
Check(Is("SYSTEM", THEME_A) and session.settled == 0, "the skin did not theme or the Suite settled a claimed ledger")
Logout(session)
Check(CacheIs("SYSTEM", DEFAULTS.SYSTEM) and CacheIs("MONSTER_SAY", DEFAULTS.MONSTER_SAY),
    "logout did not put Blizzard's colours back")
Check(Ledger() and Ledger().SYSTEM and Ledger().SYSTEM.applied[1] == THEME_A[1],
    "the saved ledger did not record the colour the skin wrote")

-- 2. A crash, then the skin is off: the Suite puts the colours back alone.
session = Session(true)
Check(CacheIs("SYSTEM", THEME_A), "the session did not write the theme colour")
-- crash: no logout, nothing saved
session = Session(false)
Check(session.settled == 3 and CacheIs("SYSTEM", DEFAULTS.SYSTEM) and CacheIs("MONSTER_SAY", DEFAULTS.MONSTER_SAY)
    and CacheIs("MONSTER_PARTY", DEFAULTS.MONSTER_PARTY),
    "with the skin off, the colours a crash left stayed in the chat cache")
Logout(session)
Check(Ledger() == nil, "the settled ledger stayed in the saved variables")
-- The next session without the skin writes nothing.
session = Session(false)
Check(session.settled == 0 and writes == 0, "a settled ledger wrote chat colours again")
Logout(session)

-- 3. Re-enabled after that: themed again and put back at logout.
session = Session(true)
Check(Is("SYSTEM", THEME_A), "the re-enabled skin did not theme the chat colours")
Logout(session)
Check(CacheIs("SYSTEM", DEFAULTS.SYSTEM), "the re-enabled skin left its colour at logout")

-- 4. A crash, and before the next login the shared skin theme changed (on
-- another character): the skin still knows its leftover from the ledger,
-- owns it, themes it and puts Blizzard's default back at logout.
session = Session(true)
-- crash
theme = THEME_B
session = Session(true)
Check(Is("SYSTEM", THEME_B), "the skin took its own leftover colour for the player's")
Logout(session)
Check(CacheIs("SYSTEM", DEFAULTS.SYSTEM) and CacheIs("MONSTER_PARTY", DEFAULTS.MONSTER_PARTY),
    "the leftover of the old theme survived logout")
-- The skin's theme is saved with the ledger: it stays THEME_B from here.

-- 5. The player picks a colour, then the session crashes: the saved ledger
-- is older than the pick, so nothing may paint over it, skin off or on.
session = Session(true)
ChangeChatColor("SYSTEM", PICKED[1], PICKED[2], PICKED[3])
-- crash
session = Session(false)
Check(CacheIs("SYSTEM", PICKED), "the Suite replaced the colour the player picked")
Check(CacheIs("MONSTER_SAY", DEFAULTS.MONSTER_SAY), "the Suite left the skin's other colours behind")
Logout(session)
session = Session(true)
Check(Is("SYSTEM", PICKED) and Is("MONSTER_SAY", THEME_B), "the skin painted over the player's colour")
Logout(session)
Check(CacheIs("SYSTEM", PICKED), "logout replaced the player's colour")

-- 6. Disabling the chat skin puts the colours back and empties the ledger.
disk.chat = DeepCopy(DEFAULTS)
session = Session(true)
session.chat.Disable(session.frame, "chat")
Check(Is("SYSTEM", DEFAULTS.SYSTEM), "disable kept the skin's colour")
Logout(session)
Check(Ledger() == nil, "disable left the ledger in the saved variables")

Check(#reported == 0, "the chat colour ledger raised: " .. table.concat(reported, "; "))
print("Suite skin chat colour ledger: " .. checks .. " checks passed")
