-- Chat message colours are the player's persistent Blizzard setting. The skin
-- themes a category only while it shows Blizzard's default, adopts every colour the player picks,
-- puts back the colour each category had before the skin, and writes a theme
-- drag once per frame. Real ChatFrames.lua, Safety.lua and AdapterKit.lua.
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

local DEFAULTS = { SYSTEM = { 1, 1, 0 }, MONSTER_SAY = { 1, 1, 159 / 255 }, MONSTER_PARTY = { 170 / 255, 170 / 255, 1 } }
local THEME = { 0.84, 0.68, 0.44 }
local function SetTheme(r, g, b) THEME[1], THEME[2], THEME[3] = r, g, b end
local writes = {}
local function Reset(colors)
    ChatTypeInfo = {}
    for chatType, color in pairs(colors) do
        ChatTypeInfo[chatType] = { r = color[1], g = color[2], b = color[3] }
    end
    writes = {}
end
-- Blizzard's own function: it stores the colour (UPDATE_CHAT_COLOR runs
-- synchronously and fills ChatTypeInfo before ChangeChatColor returns).
local function NativeChangeChatColor(chatType, r, g, b)
    writes[#writes + 1] = chatType
    local info = ChatTypeInfo[chatType]
    info.r, info.g, info.b = r, g, b
end
local function Is(chatType, color)
    local info = ChatTypeInfo[chatType]
    return math.abs(info.r - color[1]) < 1e-6 and math.abs(info.g - color[2]) < 1e-6
        and math.abs(info.b - color[3]) < 1e-6
end
local function Writes(chatType)
    local count = 0
    for _, written in ipairs(writes) do if written == chatType then count = count + 1 end end
    return count
end

local queued = {}
local function RunQueued()
    local jobs = queued
    queued = {}
    for _, job in ipairs(jobs) do job() end
end

-- One fresh engine per scenario: Blizzard's chat functions are hooked once
-- per load, like one game session. Each starts from fresh saved variables,
-- so the Suite's chat colour ledger is empty (its own contract covers it).
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local function Session(colors)
    Support.SuiteSkinBoundary(root, {})
    Reset(colors)
    _G.ChangeChatColor = NativeChangeChatColor
    CHAT_FRAMES = {}
    local NS = {
        IsCombatLocked = function() return false end,
        SuiteCore = function() return MSUFSuite end, -- Core/Bootstrap.lua
        Theme = { GetColor = function(role)
            if role == "blizzardYellow" then return THEME[1], THEME[2], THEME[3], 1 end
            return 1, 1, 1, 1
        end },
        Registry = {
            AddListener = Noop,
            QueueJob = function(job)
                for _, pending in ipairs(queued) do if pending == job then return end end
                queued[#queued + 1] = job
            end,
        },
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
    return NS.ChatFramesSkin, chatFrame
end

-- A clean profile: every category shows Blizzard's default and is themed;
-- logout puts the defaults back.
local chat = Session(DEFAULTS)
Check(Is("SYSTEM", THEME) and Is("MONSTER_SAY", THEME) and Is("MONSTER_PARTY", THEME),
    "the skin did not theme Blizzard's default message colors")
chat.RestoreBlizzardMessageColors()
Check(Is("SYSTEM", DEFAULTS.SYSTEM) and Is("MONSTER_SAY", DEFAULTS.MONSTER_SAY),
    "logout did not put the colors the categories had before the skin back")

-- A colour the player picked before the Suite stays theirs, and survives
-- logout and disable untouched.
local custom = { SYSTEM = { 0.2, 0.9, 0.3 }, MONSTER_SAY = DEFAULTS.MONSTER_SAY, MONSTER_PARTY = DEFAULTS.MONSTER_PARTY }
local chatFrame
chat, chatFrame = Session(custom)
Check(Is("SYSTEM", custom.SYSTEM) and Writes("SYSTEM") == 0, "the skin painted over the player's system color")
Check(Is("MONSTER_SAY", THEME), "a default category beside a custom one was not themed")
chat.RestoreBlizzardMessageColors()
Check(Is("SYSTEM", custom.SYSTEM) and Writes("SYSTEM") == 0,
    "logout replaced the player's system color with Blizzard's default")

-- The player sets a colour in Blizzard's chat settings: adopted at once,
-- never repainted by a theme change, kept at logout.
chat, chatFrame = Session(DEFAULTS)
ChangeChatColor("SYSTEM", 0.5, 0.4, 0.3)
SetTheme(0.7, 0.6, 0.5)
chat:OnThemeChanged("color", "blizzardYellow")
RunQueued()
Check(Is("SYSTEM", { 0.5, 0.4, 0.3 }), "a theme change painted over the color the player picked")
Check(Is("MONSTER_SAY", THEME), "a theme change did not repaint the categories the skin still owns")
chat.Disable(chatFrame, "chat")
Check(Is("SYSTEM", { 0.5, 0.4, 0.3 }) and Is("MONSTER_SAY", DEFAULTS.MONSTER_SAY),
    "disable reset the player's color or kept the skin's own")

-- The colour picker's Cancel restores the colour it opened with (the skin's):
-- the category is the skin's again and logout restores Blizzard's default.
chat, chatFrame = Session(DEFAULTS)
ChangeChatColor("SYSTEM", 0.1, 0.1, 0.1)
ChangeChatColor("SYSTEM", THEME[1], THEME[2], THEME[3])
chat.RestoreBlizzardMessageColors()
Check(Is("SYSTEM", DEFAULTS.SYSTEM), "a cancelled color pick left the skin's color behind at logout")

-- A category that shows the theme colour is the player's: a theme colour
-- proves nothing (the player may have picked it while the skin was off).
-- No write, and logout keeps it.
local left = { SYSTEM = THEME, MONSTER_SAY = DEFAULTS.MONSTER_SAY, MONSTER_PARTY = DEFAULTS.MONSTER_PARTY }
chat = Session(left)
Check(Writes("SYSTEM") == 0 and Is("SYSTEM", THEME), "the skin rewrote a colour equal to its theme")
chat.RestoreBlizzardMessageColors()
Check(Is("SYSTEM", THEME) and Writes("SYSTEM") == 0, "logout replaced a colour equal to the theme with Blizzard's default")

-- A change through a path the hook does not see is the player's too.
chat = Session(DEFAULTS)
ChatTypeInfo.MONSTER_PARTY.r, ChatTypeInfo.MONSTER_PARTY.g = 0.3, 0.3
chat:OnThemeChanged("theme", "look")
RunQueued()
Check(ChatTypeInfo.MONSTER_PARTY.r == 0.3 and Writes("MONSTER_PARTY") == 1,
    "the skin painted over a color another path had set")

-- A colour drag writes the persistent colours once per frame.
chat = Session(DEFAULTS)
for step = 1, 8 do
    SetTheme(0.5 + step * 0.05, 0.5, 0.5)
    chat:OnThemeChanged("color", "blizzardYellow")
end
Check(Writes("SYSTEM") == 1 and #queued == 1, "a frame of theme writes queued more than one repaint")
RunQueued()
Check(Writes("SYSTEM") == 2 and Is("SYSTEM", THEME), "the coalesced repaint did not write the theme color once")
chat:OnThemeChanged("color", "accent")
Check(#queued == 0, "an unrelated color queued a chat repaint")
Check(#reported == 0, "the chat colors raised: " .. table.concat(reported, "; "))

print("Suite skin chat colors: " .. checks .. " checks passed")
