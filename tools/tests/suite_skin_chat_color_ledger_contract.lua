-- The skin's chat message colours are a persistent client setting, and a
-- colour equal to a theme colour proves nothing: the player may have picked
-- it. Nothing is inferred from colours across sessions. Without a ledger the
-- colour a category shows is the player's; the Suite's ledger (in its saved
-- variables) records only what a clean logout could not put back, keeps it
-- as ambiguous and never applies it on its own; "Restore chat colors" is the
-- explicit recovery (recorded originals, else Blizzard's defaults). The
-- normal path (theme, clean logout restores, no ledger) stays as it was.
-- Real MSUF_Suite/Core/CharacterData.lua, MSUF_Suite/Integrations/
-- MapkoSkin.lua and the skin's Safety.lua, AdapterKit.lua and ChatFrames.lua.
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
local locked = false
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
        IsCombatLocked = function() return locked end,
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

-- 1. The normal path: themed, put back at a clean logout, no ledger left.
local THEMED = { Stored(THEME[1]), Stored(THEME[2]), Stored(THEME[3]) }
local session = Session(true)
Check(CacheIs("SYSTEM", THEMED) and CacheIs("MONSTER_SAY", THEMED), "the skin did not theme the chat colours")
Logout(session)
Check(CacheIs("SYSTEM", DEFAULTS.SYSTEM) and CacheIs("MONSTER_SAY", DEFAULTS.MONSTER_SAY)
    and CacheIs("MONSTER_PARTY", DEFAULTS.MONSTER_PARTY), "logout did not put Blizzard's colours back")
Check(Ledger() == nil, "a clean logout that put everything back left a ledger")
-- ... and the next session themes and restores the same way.
session = Session(true)
Check(CacheIs("SYSTEM", THEMED), "the next session did not theme again")
Logout(session)
Check(CacheIs("SYSTEM", DEFAULTS.SYSTEM) and Ledger() == nil, "the next clean logout differed")

-- 2. Counterexample B (no ledger): with the Suite off the player picks the
-- theme colour, then enables skinning and logs out. The colour is theirs.
SessionWithoutSuite(function() ChangeChatColor("SYSTEM", THEME[1], THEME[2], THEME[3]) end)
session = Session(true)
Check(writes == 2 and CacheIs("SYSTEM", THEMED), "the skin wrote over the player's colour or skipped the others")
Logout(session)
Check(CacheIs("SYSTEM", THEMED) and CacheIs("MONSTER_SAY", DEFAULTS.MONSTER_SAY),
    "logout replaced the player's theme-coloured pick with Blizzard's default")
Check(Ledger() == nil, "the player's colour went into the ledger")
disk.chat = DeepCopy(DEFAULTS)

-- 3. Counterexample A (ledger): a failed logout restore leaves an entry.
-- With the Suite off the player changes the colour, then picks the recorded
-- theme colour again on purpose. The Suite returns: nothing is written, the
-- entry stays, marked ambiguous.
session = Session(true)
raising.SYSTEM = true
Logout(session)
raising.SYSTEM = nil
local ledger = Ledger()
Check(ledger and ledger.colors.SYSTEM and not ledger.colors.MONSTER_SAY
    and CacheIs("SYSTEM", THEMED), "a failed logout restore was not recorded")
SessionWithoutSuite(function()
    ChangeChatColor("SYSTEM", 0.2, 0.9, 0.3)
    ChangeChatColor("SYSTEM", THEME[1], THEME[2], THEME[3])
end)
session = Session(false)
Check(writes == 0 and CacheIs("SYSTEM", THEMED), "the Suite overwrote the colour the player picked")
Logout(session)
Check(Ledger() and Ledger().colors.SYSTEM and Ledger().colors.SYSTEM.ambiguous == true,
    "the ambiguous entry was not kept for an explicit restore")
-- The skin on: it does not take the category either, and logout keeps the entry.
session = Session(true)
Check(CacheIs("SYSTEM", THEMED) and writes == 2, "the skin wrote over an ambiguous category")
Logout(session)
Check(CacheIs("SYSTEM", THEMED) and Ledger() and Ledger().colors.SYSTEM, "the ambiguous entry was lost")

-- 4. "Restore chat colors": the recorded original where there is one,
-- else Blizzard's default; the ledger goes. Refused in combat.
session = Session(false)
locked = true
Check(not session.Suite.Skin.RestoreChatColors() and writes == 0, "Restore chat colors ran in combat")
locked = false
disk.chat.MONSTER_PARTY = { Stored(0.5), Stored(0.5), Stored(0.5) }
LoadChatCache()
local ok, written = session.Suite.Skin.RestoreChatColors()
Check(ok and written == 3 and CacheIs("SYSTEM", DEFAULTS.SYSTEM) and CacheIs("MONSTER_PARTY", DEFAULTS.MONSTER_PARTY),
    "Restore chat colors did not put the originals and defaults back")
Logout(session)
Check(Ledger() == nil, "Restore chat colors left the ledger")
-- With a recorded original that is not Blizzard's default.
disk.saved.suiteCharacters = { ["Player-1"] = { skinChatColors = { colors = {
    MONSTER_SAY = { original = { 0.6, 0.6, 0.6 }, left = THEMED, ambiguous = true } } } } }
disk.chat.MONSTER_SAY = DeepCopy(THEMED)
session = Session(false)
ok, written = session.Suite.Skin.RestoreChatColors()
Check(ok and CacheIs("MONSTER_SAY", { Stored(0.6), Stored(0.6), Stored(0.6) }) and CacheIs("SYSTEM", DEFAULTS.SYSTEM),
    "Restore chat colors ignored the recorded original")
Logout(session)
disk.chat = DeepCopy(DEFAULTS)

-- 5. A crash before the first save leaves the theme colour with no ledger
-- (documented limit): no session infers anything, skin off or on; only the
-- explicit restore puts Blizzard's default back.
session = Session(true)
-- crash: no logout, nothing saved
session = Session(false)
Check(writes == 0 and CacheIs("SYSTEM", THEMED), "the Suite inferred a crash leftover")
Logout(session)
session = Session(true)
Logout(session)
Check(CacheIs("SYSTEM", THEMED) and Ledger() == nil, "the skin inferred a crash leftover")
session = Session(false)
Check(session.Suite.Skin.RestoreChatColors() and CacheIs("SYSTEM", DEFAULTS.SYSTEM),
    "Restore chat colors did not clear a crash leftover")
Logout(session)

-- 6. Disable puts the colours back; the next clean logout leaves no ledger.
session = Session(true)
session.chat.Disable(session.frame, "chat")
Check(CacheIs("SYSTEM", DEFAULTS.SYSTEM), "disable kept the skin's colour")
Logout(session)
Check(Ledger() == nil, "disable left a ledger behind")

Check(#reported == 1, "the chat colour ledger raised more than the one failed restore: "
    .. table.concat(reported, "; "))
print("Suite skin chat colour ledger: " .. checks .. " checks passed")
