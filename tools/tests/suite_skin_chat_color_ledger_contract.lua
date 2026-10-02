-- The skin's chat message colours are a persistent client setting. The Suite
-- keeps a ledger, in its saved variables, of what a clean logout could not
-- put back; the skin or, once the skin is off, the Suite settles it at the
-- next login. The ledger never overwrites a colour the player chose: a
-- category is restored only when it shows exactly what the last saved
-- logout left, and a clean logout that restored everything leaves no
-- ledger behind. A session that ends without PLAYER_LOGOUT saves nothing
-- (documented limit: only the skin itself recognises its theme colour when
-- it runs again). Real MSUF_Suite/Core/CharacterData.lua,
-- MSUF_Suite/Integrations/MapkoSkin.lua and the skin's Safety.lua,
-- AdapterKit.lua and ChatFrames.lua.
--
-- Modelled as in the client: ChangeChatColor writes the chat cache at once;
-- saved variables are written only by a clean logout or reload, after the
-- PLAYER_LOGOUT handlers ran, and only while MSUF_Suite is loaded.
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

-- The chat cache stores 8 bits per channel.
local function Stored(value) return math.floor(value * 255 + 0.5) / 255 end
local DEFAULTS = { SYSTEM = { 1, 1, 0 }, MONSTER_SAY = { 1, 1, Stored(159 / 255) },
    MONSTER_PARTY = { Stored(170 / 255), Stored(170 / 255), 1 } }
local THEME = { 0.84, 0.68, 0.44 }

local disk = { chat = DeepCopy(DEFAULTS), saved = nil }
local writes, raising = 0, {}

local function CacheIs(chatType, color)
    local stored = disk.chat[chatType]
    return math.abs(stored[1] - color[1]) < 1e-6 and math.abs(stored[2] - color[2]) < 1e-6
        and math.abs(stored[3] - color[3]) < 1e-6
end

-- Blizzard's own function: the colour reaches ChatTypeInfo (UPDATE_CHAT_COLOR
-- runs inside the call) and the chat cache at once, 8 bits per channel.
local function NativeChangeChatColor(chatType, r, g, b)
    if raising[chatType] then error("contract: ChangeChatColor raised") end
    writes = writes + 1
    r, g, b = Stored(r), Stored(g), Stored(b)
    local info = ChatTypeInfo[chatType]
    info.r, info.g, info.b = r, g, b
    disk.chat[chatType] = { r, g, b }
end

local function LoadChatCache()
    ChatTypeInfo = {}
    for chatType, color in pairs(disk.chat) do
        ChatTypeInfo[chatType] = { r = color[1], g = color[2], b = color[3] }
    end
    _G.ChangeChatColor = NativeChangeChatColor
end

-- One game session with MSUF_Suite loaded: the saved variables and the chat
-- cache load, the skin (when on) applies at PLAYER_LOGIN, the Suite settles
-- at the first PLAYER_ENTERING_WORLD.
local function Session(skinOn)
    LoadChatCache()
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
                if role == "blizzardYellow" then return THEME[1], THEME[2], THEME[3], 1 end
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

-- A session without MSUF_Suite: the player may change chat colours; no Suite
-- code runs and the Suite's saved variables are not written.
local function SessionWithoutSuite(change)
    LoadChatCache()
    if change then change() end
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

-- 1. A clean session: themed, put back at logout, no ledger left behind.
local session = Session(true)
Check(session.settled == 0 and CacheIs("SYSTEM", { Stored(THEME[1]), Stored(THEME[2]), Stored(THEME[3]) }),
    "the skin did not theme the chat colours or the Suite settled a claimed session")
Logout(session)
Check(CacheIs("SYSTEM", DEFAULTS.SYSTEM) and CacheIs("MONSTER_SAY", DEFAULTS.MONSTER_SAY),
    "logout did not put Blizzard's colours back")
Check(Ledger() == nil, "a clean logout that put everything back left a ledger")

-- 2. Across sessions: in a session without the Suite the player picks the
-- skin's old theme colour on purpose. When the Suite returns (skin off), it
-- must not overwrite that choice.
SessionWithoutSuite(function() ChangeChatColor("SYSTEM", THEME[1], THEME[2], THEME[3]) end)
session = Session(false)
Check(session.settled == 0 and writes == 0, "the Suite rewrote a chat colour the player picked")
Logout(session)
session = Session(false)
Check(writes == 0 and CacheIs("SYSTEM", { Stored(THEME[1]), Stored(THEME[2]), Stored(THEME[3]) }),
    "the player's colour did not survive the Suite")
Logout(session)
disk.chat = DeepCopy(DEFAULTS)

-- 3. A crash before the first save: nothing reached the saved variables, so
-- the Suite (skin off) leaves the colour alone (documented limit) ...
session = Session(true)
-- crash: no logout, nothing saved
session = Session(false)
Check(session.settled == 0 and writes == 0, "the Suite settled colours no saved ledger recorded")
Logout(session)
-- ... and the skin, when it runs again, recognises its own theme colour and
-- puts Blizzard's default back at logout.
session = Session(true)
Logout(session)
Check(CacheIs("SYSTEM", DEFAULTS.SYSTEM) and Ledger() == nil, "the skin did not clean up its own leftover")

-- 4. A logout whose restore fails leaves a ledger; the next login with the
-- skin off puts the colour back exactly and drops the entry.
session = Session(true)
raising.SYSTEM = true
Logout(session)
raising.SYSTEM = nil
local ledger = Ledger()
Check(ledger and ledger.colors and ledger.colors.SYSTEM and ledger.colors.SYSTEM.generation == ledger.generation
    and not ledger.colors.MONSTER_SAY, "a failed logout restore was not recorded with its generation")
session = Session(false)
Check(session.settled == 1 and CacheIs("SYSTEM", DEFAULTS.SYSTEM), "the Suite did not put back what the logout left")
Logout(session)
Check(Ledger() == nil, "the settled ledger stayed in the saved variables")

-- 5. The same leftover with the skin on: the skin takes it over, themes it
-- and puts the recorded original back at its own clean logout.
session = Session(true)
raising.SYSTEM = true
Logout(session)
raising.SYSTEM = nil
session = Session(true)
Check(session.settled == 0, "the Suite settled a ledger the skin had claimed")
Logout(session)
Check(CacheIs("SYSTEM", DEFAULTS.SYSTEM) and Ledger() == nil, "the skin did not settle the leftover it took over")

-- 6. A leftover the player changed afterwards (a session without the
-- Suite): ambiguous, so nothing is written and the entry goes.
session = Session(true)
raising.SYSTEM = true
Logout(session)
raising.SYSTEM = nil
SessionWithoutSuite(function() ChangeChatColor("SYSTEM", 0.2, 0.9, 0.3) end)
session = Session(false)
Check(session.settled == 0 and writes == 0 and CacheIs("SYSTEM", { Stored(0.2), Stored(0.9), Stored(0.3) }),
    "the Suite overwrote a colour the player changed after the leftover")
Logout(session)
Check(Ledger() == nil, "an ambiguous entry stayed in the ledger")

-- 7. An entry without the ledger's generation is stale: dropped unwritten.
disk.chat = DeepCopy(DEFAULTS)
disk.chat.SYSTEM = { Stored(THEME[1]), Stored(THEME[2]), Stored(THEME[3]) }
disk.saved.suiteCharacters = { ["Player-1"] = { skinChatColors = { generation = 3, colors = {
    SYSTEM = { original = { 1, 1, 0 }, left = DeepCopy(disk.chat.SYSTEM), generation = 2 } } } } }
session = Session(false)
Check(session.settled == 0 and writes == 0, "a stale ledger entry was settled by colour equality")
Logout(session)
Check(Ledger() == nil, "a stale ledger entry stayed")
disk.chat = DeepCopy(DEFAULTS)

-- 8. Disable puts the colours back; the next clean logout leaves no ledger.
session = Session(true)
session.chat.Disable(session.frame, "chat")
Check(CacheIs("SYSTEM", DEFAULTS.SYSTEM), "disable kept the skin's colour")
Logout(session)
Check(Ledger() == nil, "disable left a ledger behind")

Check(#reported == 3, "the chat colour ledger raised more than the three failed restores: "
    .. table.concat(reported, "; "))
print("Suite skin chat colour ledger: " .. checks .. " checks passed")
