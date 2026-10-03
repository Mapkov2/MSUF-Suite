-- State exploration of the skin's chat colour ledger: every event sequence
-- up to length 5 over a reduced alphabet, plus seeded random sequences up
-- to length 10 over the full alphabet, each closed by a clean logout and run
-- against the real MSUF_Suite/Core/CharacterData.lua,
-- MSUF_Suite/Integrations/MapkoSkin.lua and the skin's Safety.lua,
-- AdapterKit.lua and ChatFrames.lua in a persistence model:
--   - the chat cache stores one byte per channel and persists every
--     ChangeChatColor at once; Blizzard's chat settings open the colour
--     picker with one write of the current colour before Show, preview every
--     move, Cancel writes the opening colour back and OK the last one;
--   - saved variables are written only by a clean logout (PLAYER_LOGOUT
--     handlers first); a crash keeps the chat cache and loses them;
--   - combat refuses the skin's enable and disable and "Restore chat
--     colors", and holds queued repaints until it ends;
--   - "Restore chat colors" is a click in the Suite's options, so it first
--     cancels an open picker (Blizzard cancels on a click outside it).
-- An independent provenance model knows who wrote each category's stored
-- bytes (Blizzard's default, the Suite, the explicit Restore, the player,
-- or a picker preview) and decides what the player chose by the rule in
-- MSUF_Suite/Integrations/MapkoSkin.lua: a picker session that ends on
-- different stored bytes than it opened with, or an outside write that
-- changes the stored bytes while no picker is open. After every step:
--   I1 a colour the player chose is never overwritten by the Suite, except
--      by the explicit Restore (checked at the write itself);
--   I2 after any logout, a category shows a theme colour the Suite wrote
--      only while the ledger records it as unrestored (or it survived a
--      crash: the documented limit);
--   I3 Cancel and a no-op write change no category's ownership, and a
--      logout with the picker open restores every category the skin owned
--      when the picker opened (or records it);
--   I4 a successful Restore leaves no ledger entry, and the next clean
--      logout creates none for the categories it restored;
--   and nothing raises but the injected ChangeChatColor failures.
-- arg[2] "--collect" runs everything and lists the failures instead of
-- stopping at the first (for checks against older revisions).
local root = assert(arg[1], "Suite root required")
local COLLECT = arg[2] == "--collect"

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
local function Noop() end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = DeepCopy(item) end
    return copy
end

local CHUNKS = {}
for _, file in ipairs({ "MSUF_Suite/Core/CharacterData.lua", "MSUF_Suite/Integrations/MapkoSkin.lua",
    "MSUF_Suite_Skin/Core/Safety.lua", "MSUF_Suite_Skin/Adapters/AdapterKit.lua",
    "MSUF_Suite_Skin/Adapters/ChatFrames.lua" }) do
    CHUNKS[file] = assert(loadfile(root .. "/" .. file))
end

local function Byte(value) return math.floor(value * 255 + 0.5) end
local function Bytes(r, g, b) return { Byte(r), Byte(g), Byte(b) } end
local function SameBytes(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
local function Key(bytes) return bytes[1] .. "," .. bytes[2] .. "," .. bytes[3] end
local CATEGORIES = { "SYSTEM", "MONSTER_SAY", "MONSTER_PARTY" }
local DEFAULTS = { SYSTEM = { 255, 255, 0 }, MONSTER_SAY = { 255, 255, 159 }, MONSTER_PARTY = { 170, 170, 255 } }
local THEMES = { { 0.84, 0.68, 0.44 }, { 0.5, 0.6, 0.7 } }
local THEME_BYTES = {}
for _, theme in ipairs(THEMES) do THEME_BYTES[Key(Bytes(theme[1], theme[2], theme[3]))] = true end
local GREEN = { 0.2, 0.9, 0.3 }

-- The world that persists across sessions, the session, and the model.
local world, S, model
local failure

local function Fail(message)
    if not failure then failure = message end
end

-- Who makes the current ChangeChatColor call: "player" (the picker and
-- outside writes), "restore" (the explicit Restore); nil is the Suite.
local actor
local failingWrites = false

local function NativeChangeChatColor(chatType, r, g, b)
    if failingWrites then error("exploration: ChangeChatColor raised") end
    local bytes = Bytes(r, g, b)
    local before = world.chat[chatType]
    world.chat[chatType] = bytes
    local info = ChatTypeInfo[chatType]
    info.r, info.g, info.b = bytes[1] / 255, bytes[2] / 255, bytes[3] / 255
    if not model.writer[chatType] or SameBytes(before, bytes) then return end
    local who = actor or "suite"
    if who == "suite" and model.writer[chatType] == "player" then
        Fail("I1: the Suite overwrote the colour the player chose for " .. chatType)
    end
    if who == "player" then
        model.writer[chatType] = model.session and "preview" or "player"
    else
        model.writer[chatType] = who
    end
    model.residue[chatType] = nil
end

local function PlayerWrite(chatType, r, g, b)
    actor = "player"
    ChangeChatColor(chatType, r, g, b)
    actor = nil
    -- Inside a picker session the player's last write decides its end.
    if model.session then
        model.session.last[chatType] = Bytes(r, g, b)
    end
end

-- Blizzard's colour picker as the chat settings drive it.
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

local function OwnershipMap()
    local map = {}
    local chat = S.chat
    if not chat then return map end
    for _, state in pairs(chat.owners) do
        for chatType, colorState in pairs(state.messageColors) do
            if colorState.released then
                map[chatType] = "released"
            elseif colorState.original then
                map[chatType] = { original = Bytes(colorState.original[1], colorState.original[2], colorState.original[3]) }
            end
        end
    end
    return map
end

local function SameOwnership(before, after)
    for chatType, value in pairs(before) do
        local now = after[chatType]
        if type(value) == "table" then
            if type(now) ~= "table" or not SameBytes(value.original, now.original) then return false end
        elseif now ~= value then
            return false
        end
    end
    return true
end

local function RunJobs()
    while not S.locked and #S.jobs > 0 do
        local jobs = S.jobs
        S.jobs = {}
        for _, job in ipairs(jobs) do job() end
    end
end

local THEME = { THEMES[1][1], THEMES[1][2], THEMES[1][3] }

local function LoadSkin()
    local NS = {
        IsCombatLocked = function() return S.locked end,
        SuiteCore = function() return MSUFSuite end,
        Theme = { GetColor = function(role)
            if role == "blizzardYellow" then return THEME[1], THEME[2], THEME[3], 1 end
            return 1, 1, 1, 1
        end },
        Registry = { AddListener = Noop, QueueJob = function(job)
            for _, pending in ipairs(S.jobs) do if pending == job then return end end
            S.jobs[#S.jobs + 1] = job
        end },
        Checkmarks = { TrackTexture = Noop, UntrackTexture = Noop, UntrackOwner = Noop },
        WindowActionSkin = { Apply = function() return nil, "owned by another adapter" end },
        CombatGate = { Cancel = Noop, RunOrDefer = Noop },
    }
    CHUNKS["MSUF_Suite_Skin/Core/Safety.lua"]("MSUF_Suite_Skin", NS)
    CHUNKS["MSUF_Suite_Skin/Adapters/AdapterKit.lua"]("MSUF_Suite_Skin", NS)
    CHUNKS["MSUF_Suite_Skin/Adapters/ChatFrames.lua"]("MSUF_Suite_Skin", NS)
    S.chat = NS.ChatFramesSkin
end

local chatFrame = {}
function chatFrame:IsForbidden() return false end
function chatFrame:IsProtected() return false, false end
function chatFrame:GetName() return "ChatFrame1" end

-- The skin's rule (MapkoSkin.lua): when the skin starts observing (a login,
-- or enabling it in a session that had not loaded it), a category that
-- shows Blizzard's default is the clean profile, whoever set it.
local function CleanDefaults()
    for _, chatType in ipairs(CATEGORIES) do
        if SameBytes(world.chat[chatType], DEFAULTS[chatType]) then model.writer[chatType] = "blizzard" end
    end
end

local function Login()
    ChatTypeInfo = {}
    for chatType, bytes in pairs(world.chat) do
        ChatTypeInfo[chatType] = { r = bytes[1] / 255, g = bytes[2] / 255, b = bytes[3] / 255 }
    end
    CleanDefaults()
    _G.ChangeChatColor = NativeChangeChatColor
    CHAT_FRAMES = {}
    ColorPickerFrame = NewColorPicker()
    S = { locked = false, jobs = {} }
    local Suite = {
        RootDB = DeepCopy(world.saved) or {},
        IsCombatLocked = function() return S.locked end,
        Dispatch = securecallfunction,
        Finish = function(callback, ...) return true, callback(...) end,
    }
    function Suite.PublicText(value) return type(value) == "string" and value ~= "" and value or nil end
    function Suite.Finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
    _G.MSUFSuite = Suite
    CHUNKS["MSUF_Suite/Core/CharacterData.lua"]("MSUF_Suite", Suite)
    CHUNKS["MSUF_Suite/Integrations/MapkoSkin.lua"]("MSUF_Suite", Suite)
    S.Suite = Suite
    if world.skinOn then
        LoadSkin()
        if not S.chat.Apply(chatFrame, "chat") then Fail("the skin did not apply at login") end
    end
    Suite.Skin.SettleChatColors()
    RunJobs()
end

local function Ledger(saved)
    local characters = saved and saved.suiteCharacters
    local own = characters and characters["Player-1"]
    local ledger = own and own.skinChatColors
    return ledger and ledger.colors or {}
end

------------------------------------------------------------------ the model
local function PickerEnd()
    -- After Hide (and whatever the skin did in OnHide): a category the
    -- player wrote in the session is theirs when the session ended on other
    -- bytes than it opened with; else it returns to its owner at the open.
    local session = model.session
    model.session = nil
    for chatType, last in pairs(session.last) do
        if model.writer[chatType] == "preview" then
            if SameBytes(last, session.start[chatType]) then
                model.writer[chatType] = session.writer[chatType]
                model.residue[chatType] = session.residue[chatType]
            else
                model.writer[chatType] = "player"
            end
        end
    end
end

-- A session that ends without the picker closing (logout, crash): what the
-- preview left is the player's unfinished edit, neither chosen nor the Suite's.
local function PickerAbandoned()
    if not model.session then return end
    model.session = nil
    for _, chatType in ipairs(CATEGORIES) do
        if model.writer[chatType] == "preview" then model.writer[chatType] = "unfinished" end
    end
end

local function CheckI2(saved)
    local ledger = Ledger(saved)
    for _, chatType in ipairs(CATEGORIES) do
        if THEME_BYTES[Key(world.chat[chatType])] and model.writer[chatType] == "suite"
            and not ledger[chatType] and not model.residue[chatType] then
            Fail("I2: after logout " .. chatType .. " shows the Suite's theme colour without a ledger entry")
        end
    end
end

local function CheckErrors()
    for _, message in ipairs(reported) do
        if not message:find("exploration: ChangeChatColor raised", 1, true) then
            Fail("unexpected error: " .. message)
        end
    end
    reported = {}
end

------------------------------------------------------------------ the events
local picker = {}

local function Cancel()
    if not ColorPickerFrame.shown then return false end
    local before = OwnershipMap()
    local previous = picker.previous
    PlayerWrite(picker.chatType, previous[1], previous[2], previous[3])
    ColorPickerFrame:Hide()
    PickerEnd()
    RunJobs()
    if not SameOwnership(before, OwnershipMap()) then Fail("I3: Cancel changed a category's ownership") end
    return true
end

local function Open(chatType)
    if ColorPickerFrame.shown then Cancel() end
    local info = ChatTypeInfo[chatType]
    picker.chatType = chatType
    picker.previous, picker.color = { info.r, info.g, info.b }, { info.r, info.g, info.b }
    PlayerWrite(chatType, info.r, info.g, info.b)
    local session = { start = {}, writer = {}, residue = {}, last = {}, owned = {} }
    for _, category in ipairs(CATEGORIES) do
        session.start[category] = world.chat[category]
        session.writer[category] = model.writer[category]
        session.residue[category] = model.residue[category]
    end
    for category, value in pairs(OwnershipMap()) do
        if type(value) == "table" then session.owned[category] = value.original end
    end
    model.session = session
    ColorPickerFrame:Show()
    return true
end

local function Drag(color)
    if not ColorPickerFrame.shown then return false end
    picker.color = color
    PlayerWrite(picker.chatType, color[1], color[2], color[3])
    return true
end

local function Logout(failing)
    local session = model.session
    if S.chat then
        failingWrites = failing
        S.chat.RestoreBlizzardMessageColors()
        failingWrites = false
    end
    world.saved = DeepCopy(S.Suite.RootDB)
    PickerAbandoned()
    CheckErrors()
    CheckI2(world.saved)
    local ledger = Ledger(world.saved)
    if session then
        for chatType, original in pairs(session.owned) do
            if not SameBytes(world.chat[chatType], original) and not ledger[chatType] then
                Fail("I3: logout with the picker open neither restored nor recorded " .. chatType)
            end
        end
    end
    if model.restored and not failing and next(ledger) ~= nil then
        Fail("I4: the logout after a successful Restore created a ledger entry")
    end
    model.restored = nil
    Login()
    return true
end

local function NearOf(bytes)
    local red = bytes[1] < 255 and bytes[1] + 1 or bytes[1] - 1
    return { red / 255, bytes[2] / 255, bytes[3] / 255 }
end

local EVENTS = {}
EVENTS.open = function() return Open("SYSTEM") end
EVENTS.openSay = function() return Open("MONSTER_SAY") end
-- A drag one stored byte away from the opening colour (the smallest edit).
EVENTS.drag = function()
    if not ColorPickerFrame.shown then return false end
    return Drag(NearOf(Bytes(picker.previous[1], picker.previous[2], picker.previous[3])))
end
EVENTS.dragFar = function() return Drag(GREEN) end
EVENTS.dragTheme = function() return Drag({ THEME[1], THEME[2], THEME[3] }) end
EVENTS.ok = function()
    if not ColorPickerFrame.shown then return false end
    local color = picker.color
    PlayerWrite(picker.chatType, color[1], color[2], color[3])
    ColorPickerFrame:Hide()
    PickerEnd()
    return true
end
EVENTS.cancel = Cancel
EVENTS.theme = function()
    local target = THEME[1] == THEMES[1][1] and THEMES[2] or THEMES[1]
    THEME[1], THEME[2], THEME[3] = target[1], target[2], target[3]
    if S.chat then S.chat:OnThemeChanged("color", "blizzardYellow") end
    return true
end
EVENTS.disable = function()
    if not world.skinOn or S.locked then return false end
    if not S.chat.Disable(chatFrame, "chat") then Fail("the skin refused to disable") end
    world.skinOn = false
    return true
end
EVENTS.enable = function()
    if world.skinOn or S.locked then return false end
    if not S.chat then
        CleanDefaults()
        LoadSkin()
    end
    if not S.chat.Apply(chatFrame, "chat") then Fail("the skin did not apply") end
    world.skinOn = true
    return true
end
-- An outside write that changes one stored byte by one.
local function WriteNear(chatType)
    local near = NearOf(world.chat[chatType])
    PlayerWrite(chatType, near[1], near[2], near[3])
    return true
end
EVENTS.write = function() return WriteNear("SYSTEM") end
EVENTS.writeSay = function() return WriteNear("MONSTER_SAY") end
-- An outside write that leaves the stored bytes as they are (a value within
-- the same byte), so ownership must not change.
EVENTS.noop = function()
    local bytes = world.chat.SYSTEM
    local before = OwnershipMap()
    local nudge = bytes[1] < 255 and 0.4 or -0.4
    PlayerWrite("SYSTEM", (bytes[1] + nudge) / 255, bytes[2] / 255, bytes[3] / 255)
    if not SameOwnership(before, OwnershipMap()) then Fail("I3: a no-op write changed a category's ownership") end
    return true
end
EVENTS.combat = function()
    S.locked = not S.locked
    return true
end
EVENTS.logout = function() return Logout(false) end
-- A clean logout whose PLAYER_LOGOUT writes all fail.
EVENTS.failLogout = function() return Logout(true) end
EVENTS.crash = function()
    PickerAbandoned()
    for _, chatType in ipairs(CATEGORIES) do
        if THEME_BYTES[Key(world.chat[chatType])] and model.writer[chatType] == "suite" then
            model.residue[chatType] = true
        end
    end
    -- The saved variables of this session are lost, the restore with them.
    model.restored = nil
    CheckErrors()
    Login()
    return true
end
EVENTS.restore = function()
    if ColorPickerFrame.shown then Cancel() end
    actor = "restore"
    local ok = S.Suite.Skin.RestoreChatColors()
    actor = nil
    if ok then
        for _, chatType in ipairs(CATEGORIES) do model.writer[chatType] = "restore" end
        if next(Ledger(S.Suite.RootDB)) ~= nil then Fail("I4: a successful Restore left a ledger entry") end
        model.restored = true
    end
    return true
end

local function Start(skinOn)
    world = { chat = DeepCopy(DEFAULTS), saved = nil, skinOn = skinOn }
    model = { writer = {}, residue = {} }
    for _, chatType in ipairs(CATEGORIES) do model.writer[chatType] = "blizzard" end
    THEME[1], THEME[2], THEME[3] = THEMES[1][1], THEMES[1][2], THEMES[1][3]
    failure, actor, failingWrites, reported = nil, nil, false, {}
    picker = {}
    Login()
end

-- Runs one sequence; returns nil, or the failure. Inapplicable events (a
-- drag without a picker, enabling an enabled skin) make the sequence a
-- duplicate of a shorter one: it is skipped ("skip").
local function Run(sequence, skinOn, prune)
    Start(skinOn)
    for index = 1, #sequence do
        local applied = EVENTS[sequence[index]]()
        if not applied and prune then return "skip" end
        RunJobs()
        CheckErrors()
        if failure then return failure .. " at step " .. index end
    end
    Logout(false)
    if failure then return failure .. " at the closing logout" end
    return nil
end

-- arg[2] "--trace", arg[3] "event,event,..." (arg[4] "off": skin off at the
-- start): one sequence, with the stored bytes and their writers per step.
if arg[2] == "--trace" then
    local function Show(label)
        local parts = {}
        for _, chatType in ipairs(CATEGORIES) do
            parts[#parts + 1] = chatType .. "=" .. Key(world.chat[chatType]) .. "/" .. model.writer[chatType]
        end
        print(label, table.concat(parts, " "), "skin " .. tostring(world.skinOn), failure or "")
    end
    Start(arg[4] ~= "off")
    Show("start")
    for event in arg[3]:gmatch("[^,]+") do
        EVENTS[event]()
        RunJobs()
        CheckErrors()
        Show(event)
    end
    Logout(false)
    Show("closing logout")
    return
end

local failures, checked, skipped = {}, 0, 0
local function Record(sequence, skinOn, result)
    if result == "skip" then
        skipped = skipped + 1
        return
    end
    checked = checked + 1
    if result then
        local text = (skinOn and "" or "[skin off] ") .. table.concat(sequence, ", ") .. ": " .. result
        if not COLLECT then error("chat colour exploration failed: " .. text, 0) end
        failures[#failures + 1] = text
    end
end

-- Exhaustive: every sequence up to length 5 over the reduced alphabet.
local REDUCED = { "open", "drag", "ok", "cancel", "theme", "disable", "enable", "write", "noop", "logout" }
local MAX_LENGTH = 5
local sequence = {}
local function Explore(depth)
    Record(sequence, true, Run(sequence, true, true))
    if depth == MAX_LENGTH then return end
    for _, event in ipairs(REDUCED) do
        sequence[depth + 1] = event
        Explore(depth + 1)
        sequence[depth + 1] = nil
    end
end
Explore(0)
local exhaustive = checked

-- Seeded random: sequences up to length 10 over the full alphabet, from
-- both initial skin states (a fixed linear congruential generator, so the
-- sequences are the same on every platform).
local FULL = { "open", "openSay", "drag", "dragFar", "dragTheme", "ok", "cancel", "theme", "disable", "enable",
    "write", "writeSay", "noop", "combat", "logout", "failLogout", "crash", "restore" }
local RANDOM_COUNT, RANDOM_LENGTH = 4000, 10
local seed = 20261003
local function Random(n)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed % n + 1
end
for _ = 1, RANDOM_COUNT do
    local random = {}
    for index = 1, Random(RANDOM_LENGTH) do random[index] = FULL[Random(#FULL)] end
    local skinOn = Random(2) == 1
    Record(random, skinOn, Run(random, skinOn, false))
end

-- The CX-R12 counterexamples, named (all are among the sequences above).
local NAMED = {
    { "P0 a one-byte outside edit", { "write" } },
    { "P0 a one-byte picker edit", { "open", "drag", "ok" } },
    { "P1 a theme change before the first drag, then Cancel", { "open", "theme", "cancel" } },
    { "P1 disable, then Cancel", { "open", "drag", "disable", "cancel" } },
    { "P1 disable, enable, then Cancel", { "open", "drag", "disable", "enable", "cancel" } },
}
local named = {}
for _, case in ipairs(NAMED) do
    local result = Run(case[2], true, false)
    named[#named + 1] = ("  %s (%s): %s"):format(case[1], table.concat(case[2], ", "), result or "holds")
    if result and not COLLECT then error("chat colour exploration failed: " .. case[1] .. ": " .. result, 0) end
end

print(("Suite skin chat colour exploration: %d sequences checked (%d exhaustive up to length %d over %d events,"
    .. " %d pruned as duplicates; %d seeded random up to length %d over %d events)"):format(
    checked, exhaustive, MAX_LENGTH, #REDUCED, skipped, RANDOM_COUNT, RANDOM_LENGTH, #FULL))
if COLLECT then
    print(("%d failing sequences"):format(#failures))
    local kinds, order = {}, {}
    for _, text in ipairs(failures) do
        local kind = text:match(": ([^:]+: [^:]-) at ") or text
        if not kinds[kind] then
            kinds[kind] = { count = 0, example = text }
            order[#order + 1] = kind
        end
        kinds[kind].count = kinds[kind].count + 1
    end
    for _, kind in ipairs(order) do
        print(("  %d x %s"):format(kinds[kind].count, kind))
        print("      e.g. " .. kinds[kind].example)
    end
    print("named counterexamples:")
    for _, line in ipairs(named) do print(line) end
end
