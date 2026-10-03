-- The skin's chat message colours are a persistent client setting. These
-- scenarios drive the per-category state machine documented in
-- MSUF_Suite/Integrations/MapkoSkin.lua:
--   a change is measured against the colour the category showed before the
--   edit began: a write that leaves it as it was is a no-op, a colour picker
--   session is tentative until the picker hides and is no change when it
--   ends where it started, and a session open at logout is unfinished
--   session: unowned -> owned (shows Blizzard's default, our own write)
--            unowned -> released (any other colour, or an external change)
--            owned   -> released (any change the skin did not make; no
--                       colour equality brings ownership back)
--            owned   -> gone (logout/disable restore) | recorded (it failed)
--   ledger:  recorded -> ambiguous (next session) -> gone only through the
--            explicit "Restore chat colors" (a failed write keeps it)
-- Scenarios: 1 normal path; 2/3 the CX-R6 counterexamples B and A; 4 the
-- explicit restore; 5 a crash before the first save; 6 disable; 7 an
-- in-session pick of the theme colour; 8 an ambiguous original through a
-- normal and a failed logout; 9 the restore reconciles a pending leftover;
-- 10 restore failures reported and kept; 11 picker Cancel (and the same
-- colour picked again); 12 picker OK on another colour; 13 the CX-R8 P0
-- two-step through the picker; 14 a no-op write; 15 the picker open at
-- logout. Real MSUF_Suite/Core/
-- CharacterData.lua, MSUF_Suite/Integrations/MapkoSkin.lua and the skin's
-- Safety.lua, AdapterKit.lua and ChatFrames.lua.
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

-- Blizzard's colour picker as the chat settings use it (Blizzard_ColorPickerFrame
-- Mainline SetupColorPickerAndShow and its OK and Cancel buttons;
-- ChatConfigFrame.lua MessageTypeColor_OpenColorPicker and
-- messageTypeColorSwatch/Cancel). Opening sets the picker to the category's
-- colour, which already runs the swatch function once, before Show. Every
-- move previews live through ChangeChatColor. Cancel writes the opening
-- colour back and OK the last one, then both hide. OnShow and OnHide run
-- the scripts added with HookScript.
local function NewColorPicker()
    local frame, scripts = { shown = false }, { OnShow = {}, OnHide = {} }
    local function Run(script)
        for _, callback in ipairs(scripts[script]) do callback(frame) end
    end
    function frame:HookScript(script, callback) table.insert(scripts[script], callback) end
    function frame:IsForbidden() return false end
    function frame:IsShown() return self.shown end
    function frame:Show() if not self.shown then self.shown = true;Run("OnShow") end end
    function frame:Hide() if self.shown then self.shown = false;Run("OnHide") end end
    return frame
end
local Picker = {}
function Picker.Open(chatType)
    local info = ChatTypeInfo[chatType]
    Picker.chatType = chatType
    Picker.previous, Picker.color = { info.r, info.g, info.b }, { info.r, info.g, info.b }
    ChangeChatColor(chatType, info.r, info.g, info.b)
    ColorPickerFrame:Show()
end
function Picker.Drag(r, g, b)
    Picker.color = { r, g, b }
    ChangeChatColor(Picker.chatType, r, g, b)
end
function Picker.Cancel()
    local previous = Picker.previous
    ChangeChatColor(Picker.chatType, previous[1], previous[2], previous[3])
    ColorPickerFrame:Hide()
end
function Picker.Okay()
    local color = Picker.color
    ChangeChatColor(Picker.chatType, color[1], color[2], color[3])
    ColorPickerFrame:Hide()
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
    ColorPickerFrame = NewColorPicker()
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
            SuiteCore = function() return MSUFSuite end, -- Core/Bootstrap.lua
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

-- 7. owned -> released by an external change, and no equality reclaim: with
-- skinning on the player picks another SYSTEM colour, then the theme colour
-- on purpose. A theme change does not repaint it and logout writes nothing.
disk.chat = DeepCopy(DEFAULTS)
session = Session(true)
ChangeChatColor("SYSTEM", 0.2, 0.9, 0.3)
ChangeChatColor("SYSTEM", THEME[1], THEME[2], THEME[3])
local before = writes
Logout(session)
Check(writes == before + 2 and CacheIs("SYSTEM", THEMED) and CacheIs("MONSTER_SAY", DEFAULTS.MONSTER_SAY),
    "logout overwrote the player's in-session pick of the theme colour")
Check(Ledger() == nil, "a released category was recorded in the ledger")
disk.chat = DeepCopy(DEFAULTS)

-- 8. An ambiguous entry survives a normal session: SYSTEM was recorded with
-- the original { 0.6, 0.6, 0.6 } and now shows Blizzard's default; the skin
-- owns it again this session and restores it at a clean logout. The entry
-- stays, and a failed restore later does not replace it either. Only the
-- explicit restore consumes it.
local GREY = { 0.6, 0.6, 0.6 }
disk.saved.suiteCharacters = { ["Player-1"] = { skinChatColors = { colors = {
    SYSTEM = { original = DeepCopy(GREY), left = DeepCopy(THEMED) } } } } }
session = Session(true)
Logout(session)
ledger = Ledger()
Check(CacheIs("SYSTEM", DEFAULTS.SYSTEM) and ledger and ledger.colors.SYSTEM
    and ledger.colors.SYSTEM.original[1] == GREY[1], "a clean logout removed the ambiguous recorded original")
session = Session(true)
raising.SYSTEM = true
Logout(session)
raising.SYSTEM = nil
Check(Ledger().colors.SYSTEM.original[1] == GREY[1], "a failed restore replaced the earlier recorded original")
session = Session(false)
Check(session.Suite.Skin.RestoreChatColors() and CacheIs("SYSTEM", { Stored(GREY[1]), Stored(GREY[2]), Stored(GREY[3]) }),
    "Restore chat colors did not write the recorded original")
Logout(session)
Check(Ledger() == nil, "the consumed entry stayed")
disk.chat = DeepCopy(DEFAULTS)

-- 9. A successful explicit restore reconciles the skin's pending leftover:
-- the disable cannot put SYSTEM back, "Restore chat colors" then writes all
-- three, and logout records nothing.
session = Session(true)
raising.SYSTEM = true
session.chat.Disable(session.frame, "chat")
raising.SYSTEM = nil
Check(CacheIs("SYSTEM", THEMED), "the injected disable failure did not leave the theme colour")
Check(session.Suite.Skin.RestoreChatColors() and CacheIs("SYSTEM", DEFAULTS.SYSTEM), "Restore chat colors failed")
Logout(session)
Check(Ledger() == nil, "logout recorded a leftover the explicit restore had already put back")

-- 10. Restore reports what failed and keeps those entries: every write
-- raises; then one of three.
disk.saved.suiteCharacters = { ["Player-1"] = { skinChatColors = { colors = {
    SYSTEM = { original = DeepCopy(GREY), left = DeepCopy(THEMED), ambiguous = true } } } } }
session = Session(false)
raising.SYSTEM, raising.MONSTER_SAY, raising.MONSTER_PARTY = true, true, true
local okAll, writtenAll, failedAll = session.Suite.Skin.RestoreChatColors()
raising.MONSTER_SAY, raising.MONSTER_PARTY = nil, nil
Check(okAll == false and writtenAll == 0 and failedAll == 3, "Restore chat colors reported success when every write failed")
local okSome, writtenSome, failedSome = session.Suite.Skin.RestoreChatColors()
raising.SYSTEM = nil
Check(okSome == false and writtenSome == 2 and failedSome == 1, "a partly failed restore was not reported as such")
Logout(session)
Check(Ledger() and Ledger().colors.SYSTEM and Ledger().colors.SYSTEM.original[1] == GREY[1],
    "the entry whose write failed was dropped")
session = Session(false)
Check(session.Suite.Skin.RestoreChatColors(), "the retry did not restore")
Logout(session)
Check(Ledger() == nil, "the retried entry stayed")
disk.chat = DeepCopy(DEFAULTS)

-- 11. A picker session that ends where it started is no change: open,
-- drag, Cancel. SYSTEM stays owned. A theme change during the session does
-- not paint over the preview, the next one repaints SYSTEM, and logout puts
-- the original back. The same for picking the opening colour again and OK.
local GREEN = { 0.2, 0.9, 0.3 }
local STORED_GREEN = { Stored(GREEN[1]), Stored(GREEN[2]), Stored(GREEN[3]) }
local function SetTheme(r, g, b) THEME[1], THEME[2], THEME[3] = r, g, b end
session = Session(true)
Picker.Open("SYSTEM")
Picker.Drag(GREEN[1], GREEN[2], GREEN[3])
SetTheme(0.5, 0.6, 0.7)
session.chat:OnThemeChanged("color", "blizzardYellow")
Check(CacheIs("SYSTEM", STORED_GREEN) and CacheIs("MONSTER_SAY", { Stored(0.5), Stored(0.6), Stored(0.7) }),
    "a theme change painted over the picker's live preview")
Picker.Cancel()
Check(CacheIs("SYSTEM", THEMED), "Cancel did not write the opening colour back")
session.chat:OnThemeChanged("color", "blizzardYellow")
Check(CacheIs("SYSTEM", { Stored(0.5), Stored(0.6), Stored(0.7) }),
    "a cancelled picker session released the category")
Picker.Open("SYSTEM")
Picker.Drag(GREEN[1], GREEN[2], GREEN[3])
Picker.Drag(Stored(0.5), Stored(0.6), Stored(0.7))
Picker.Okay()
SetTheme(0.84, 0.68, 0.44)
Logout(session)
Check(CacheIs("SYSTEM", DEFAULTS.SYSTEM) and CacheIs("MONSTER_SAY", DEFAULTS.MONSTER_SAY) and Ledger() == nil,
    "logout did not put the original back after picker sessions that ended where they started")

-- 12. A picker session that ends on another colour (OK) releases the
-- category: no repaint, logout keeps the player's colour, no ledger.
session = Session(true)
Picker.Open("SYSTEM")
Picker.Drag(0.4, 0.4, 0.4)
Picker.Drag(GREEN[1], GREEN[2], GREEN[3])
Picker.Okay()
session.chat:OnThemeChanged("color", "blizzardYellow")
Check(CacheIs("SYSTEM", STORED_GREEN), "a theme change repainted the colour the player picked")
Logout(session)
Check(CacheIs("SYSTEM", STORED_GREEN) and CacheIs("MONSTER_SAY", DEFAULTS.MONSTER_SAY) and Ledger() == nil,
    "logout replaced the colour the player picked with OK")
disk.chat = DeepCopy(DEFAULTS)

-- 13. The CX-R8 P0 two-step through the picker: another colour (OK), then
-- the theme colour again (OK). Released by the first session; the second
-- brings no ownership back, and logout writes nothing.
session = Session(true)
Picker.Open("SYSTEM")
Picker.Drag(GREEN[1], GREEN[2], GREEN[3])
Picker.Okay()
Picker.Open("SYSTEM")
Picker.Drag(THEME[1], THEME[2], THEME[3])
Picker.Okay()
Logout(session)
Check(CacheIs("SYSTEM", THEMED) and Ledger() == nil,
    "logout overwrote the player's re-pick of the theme colour")
disk.chat = DeepCopy(DEFAULTS)

-- 14. A write the skin did not make that leaves the colour as it was is a
-- no-op: both categories stay owned and logout restores them.
session = Session(true)
ChangeChatColor("SYSTEM", THEMED[1], THEMED[2], THEMED[3])
ChangeChatColor("MONSTER_SAY", THEME[1], THEME[2], THEME[3])
Logout(session)
Check(CacheIs("SYSTEM", DEFAULTS.SYSTEM) and CacheIs("MONSTER_SAY", DEFAULTS.MONSTER_SAY) and Ledger() == nil,
    "a write that changed nothing released the category")

-- 15. The picker still open at logout: an unfinished session, so SYSTEM
-- keeps its start state (owned) and logout puts the original back.
session = Session(true)
Picker.Open("SYSTEM")
Picker.Drag(GREEN[1], GREEN[2], GREEN[3])
Logout(session)
Check(CacheIs("SYSTEM", DEFAULTS.SYSTEM) and Ledger() == nil,
    "logout with the picker open left the preview colour instead of the original")
disk.chat = DeepCopy(DEFAULTS)

Check(#reported == 7, "the chat colour ledger raised other than the 7 injected failures: "
    .. #reported .. ": " .. table.concat(reported, "; "))
print("Suite skin chat colour ledger: " .. checks .. " checks passed")
