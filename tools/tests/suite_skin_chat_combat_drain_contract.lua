-- The chat chrome after combat (raid trace 2026-10-11 capture 6 frame
-- 3681: one combat-end drain re-skinned all ten chat windows, 23.7 ms, for
-- two tab-colour repaints during combat). Real Safety.lua, CombatGate.lua,
-- AdapterKit.lua, Checkmarks.lua and ChatFrames.lua.
--   * The skin follows Suite.ChatState's reports (MSUF_Suite/Core), never a
--     hook in Blizzard's chat code. A report in combat records the objects
--     it touched; after combat the drain replays exactly their out-of-combat
--     work: a dock layout gives tab skins and no full pass. A tab keeps its
--     latest selected state; a window report keeps its full pass, and what
--     was asked for after it wins over it. Disable drops the records.
--   * A recapture leaves a texture that still shows the skin's colour alone
--     (no colour or desaturation write) and retracks one Blizzard repainted;
--     a theme change still repaints (Checkmarks.StillApplied).
--   * The drain runs about 4 ms of jobs per frame and the rest on the next
--     frames, in request order, each job once; CombatGate.IsPending.
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
local locked = false
InCombatLockdown = function() return locked end
-- The frame clock in milliseconds; a job advances it by what it costs.
local now = 0
debugprofilestop = function() return now end
local timers = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local function NextFrame()
    local queued = timers
    timers = {}
    for _, callback in ipairs(queued) do callback() end
end
local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
issecretvalue = function(value) return value == SECRET end
local frames = {}
CreateFrame = function()
    local frame = { events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(_, script) self.script = script end
    frames[#frames + 1] = frame
    return frame
end

local palette = {
    background = { 0.1, 0.1, 0.15, 1 }, border = { 0.3, 0.3, 0.35, 1 }, active = { 0.2, 0.5, 0.9, 1 },
    hover = { 0.4, 0.6, 0.9, 1 }, buttonFillAlt = { 0.2, 0.2, 0.25, 1 }, warning = { 0.9, 0.3, 0.2, 1 },
    title = { 1, 1, 1, 1 }, text = { 0.75, 0.75, 0.8, 1 }, input = { 0.15, 0.15, 0.2, 1 },
}
local NS = {
    IsCombatLocked = function() return locked end,
    DB = { enabled = true },
    Theme = { GetColor = function(role)
        local color = palette[role] or { 0.5, 0.5, 0.5, 1 }
        return color[1], color[2], color[3], color[4]
    end },
    Registry = { AddListener = Noop, QueueJob = Noop },
    SuiteCore = function() return _G.MSUFSuite end, -- Core/Bootstrap.lua
    WindowActionSkin = { Apply = function() return nil, "owned by another adapter" end, DisableOwner = Noop },
}
_G.MSUFSuite = { ChatState = dofile(root .. "/tools/tests/suite_test_support.lua").ChatStateMock() }
local chatState = _G.MSUFSuite.ChatState
local Report = chatState.Report
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Safety.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/CombatGate.lua"))("MSUF_Suite_Skin", NS)
local Gate, gateFrame = NS.CombatGate, frames[#frames]
for _, file in ipairs({ "Adapters/AdapterKit.lua", "Core/Checkmarks.lua", "Adapters/ChatFrames.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
local Checkmarks, Chat = NS.Checkmarks, NS.ChatFramesSkin
local function EndCombat()
    locked = false
    gateFrame.script(gateFrame, "PLAYER_REGEN_ENABLED")
end

-------------------------------------------------------------- the chat UI
-- Textures count their reads and writes; a mark sets the counts to zero.
local textures = {}
local function Texture(r, g, b)
    local texture = { vertex = { r or 1, g or 0.82, b or 0, 1 }, desaturated = false, reads = 0, writes = 0 }
    function texture:GetVertexColor()
        self.reads = self.reads + 1
        if self.secret then return SECRET, SECRET, SECRET, 1 end
        return unpack(self.vertex)
    end
    function texture:SetVertexColor(red, green, blue, alpha)
        self.writes = self.writes + 1
        self.vertex = { red, green, blue, alpha or 1 }
    end
    function texture:IsDesaturated() return self.desaturated end
    function texture:SetDesaturated(value)
        self.writes = self.writes + 1
        self.desaturated = value == true
    end
    function texture:GetObjectType() return "Texture" end
    function texture:IsShown() return self.shown ~= false end
    function texture:Show() self.shown = true end
    function texture:Hide() self.shown = false end
    textures[#textures + 1] = texture
    return texture
end
local function Mark()
    for _, texture in ipairs(textures) do texture.reads, texture.writes = 0, 0 end
end
local function FontString()
    local text = { color = { 1, 0.82, 0, 1 } }
    function text:GetTextColor() return unpack(self.color) end
    function text:SetTextColor(r, g, b, a) self.color = { r, g, b, a or 1 } end
    return text
end
local function Is(color, expected)
    for index = 1, 4 do
        if math.abs((color[index] or 1) - (expected[index] or 1)) > 1e-6 then return false end
    end
    return true
end

local BORDERS = { "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
    "LeftTexture", "RightTexture", "BottomTexture", "TopTexture" }
local TAB_TINTED = { "ActiveLeft", "ActiveMiddle", "ActiveRight", "HighlightLeft", "HighlightMiddle",
    "HighlightRight", "glow" }
local function Chrome(object)
    object.Background = Texture()
    for _, suffix in ipairs(BORDERS) do object[suffix] = Texture() end
    return object
end
local windows, tabs = {}, {}
CHAT_FRAMES = {}
for index = 1, 10 do
    local name = "ChatFrame" .. index
    local frame = Chrome({ buttonFrame = Chrome({}) })
    function frame:GetName() return name end
    function frame:IsProtected() return false, false end
    local editBox = { UpdateHeader = function() error("the chat skin hooked UpdateHeader") end }
    for _, suffix in ipairs({ "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }) do
        editBox[suffix] = Texture()
    end
    frame.editBox = editBox
    local tab = { Text = FontString() }
    for _, suffix in ipairs({ "Left", "Middle", "Right" }) do tab[suffix] = Texture() end
    for _, suffix in ipairs(TAB_TINTED) do tab[suffix] = Texture(1, 0.5, 0.25) end
    function tab:GetName() return name .. "Tab" end
    _G[name], _G[name .. "Tab"] = frame, tab
    windows[index], tabs[index] = frame, tab
    CHAT_FRAMES[index], frame.isDocked = name, 1
end
GENERAL_CHAT_DOCK = { selected = windows[1], DOCKED_CHAT_FRAMES = windows }
-- A Blizzard dock layout (FCFDock_UpdateTabs): every docked tab repainted
-- in the native colour, selected by the dock; ChatState reports it after.
local function DockLayout(selected, kind)
    GENERAL_CHAT_DOCK.selected = selected
    for _, tab in ipairs(tabs) do FCFTab_UpdateColors(tab, _G[tab:GetName():sub(1, -4)] == selected) end
    Report(kind or "layout")
end

-- Blizzard's own functions (live FloatingChatFrame.lua FCFTab_UpdateColors,
-- FCF_SetWindowColor): the tab shows or hides its active art and repaints
-- its tinted regions in the native colour.
function FCFTab_UpdateColors(tab, selected)
    for _, suffix in ipairs({ "ActiveLeft", "ActiveMiddle", "ActiveRight" }) do
        if selected then tab[suffix]:Show() else tab[suffix]:Hide() end
    end
    tab.Text:SetTextColor(1, 0.82, 0)
    for _, suffix in ipairs(TAB_TINTED) do tab[suffix]:SetVertexColor(1, 0.5, 0.25) end
end
function FCF_SetWindowColor(frame, r, g, b)
    frame.Background:SetVertexColor(r, g, b)
    for _, suffix in ipairs(BORDERS) do frame[suffix]:SetVertexColor(r, g, b) end
end
local hooked = {}
local hook = hooksecurefunc
hooksecurefunc = function(target, method, callback)
    hooked[#hooked + 1] = type(target) == "string" and target or method
    return hook(target, method, callback)
end
ChangeChatColor = Noop

Check(Chat.Apply(windows[1], "chat"), "the chat skin did not apply")
Check(#hooked == 1 and hooked[1] == "ChangeChatColor" and chatState.owners[Chat],
    "the chat skin hooked Blizzard's chat code instead of following ChatState: " .. table.concat(hooked, ", "))
Check(Is(tabs[1].ActiveLeft.vertex, palette.active) and Is(windows[10].Background.vertex, palette.background),
    "the chat skin did not theme the windows")

-- Tabs whose tinted art the last drain read: the tabs it skinned.
local function SkinnedTabs()
    local skinned = {}
    for index, tab in ipairs(tabs) do
        if tab.ActiveLeft.reads > 0 then skinned[#skinned + 1] = index end
    end
    return skinned
end
-- Windows whose chrome the last drain read; a full pass reads all of them.
local function VisitedWindows()
    local visited = 0
    for _, frame in ipairs(windows) do
        if frame.Background.reads > 0 or frame.editBox.FocusLeft.reads > 0 then visited = visited + 1 end
    end
    return visited
end

------------------------------------------------------- scoped deferral
-- A dock layout in combat: tab skins after it, no full pass.
Mark()
locked = true
DockLayout(windows[1])
Check(Gate.IsPending("chat-frames:refresh") and Is(tabs[1].ActiveLeft.vertex, { 1, 0.5, 0.25, 1 }),
    "the tab reports did not defer their work in combat")
Check(#SkinnedTabs() == 0 and VisitedWindows() == 0, "combat chat reports read chrome before their deferred drain")
Mark()
EndCombat()
local skinned = SkinnedTabs()
Check(#skinned == 10, "a dock layout in combat skinned " .. #skinned .. " of its ten tabs after it")
Check(VisitedWindows() == 0, "a dock layout in combat ran a full pass after it")
Check(Is(tabs[1].ActiveLeft.vertex, palette.active) and tabs[1].ActiveLeft.desaturated
    and Is(tabs[2].glow.vertex, palette.warning), "a deferred tab skin did not repaint its tab")
Check(Is(tabs[1].Text.color, palette.title) and Is(tabs[2].Text.color, palette.text),
    "a deferred tab skin lost the dock's selected state")
Check(not Gate.IsPending("chat-frames:refresh"), "the drain left its job pending")

-- A tab keeps its latest selected state; an edit box header replays its
-- own work, on the next frame after its focus report (after UpdateHeader).
locked = true
DockLayout(windows[3], "selection")
DockLayout(windows[1])
Report("box", "focus", windows[4].editBox)
Check(windows[4].editBox.FocusLeft.reads == 0, "the box report skinned before Blizzard's UpdateHeader ran")
NextFrame()
Mark()
EndCombat()
Check(Is(tabs[3].Text.color, palette.text) and Is(tabs[1].Text.color, palette.title),
    "a tab lost its latest selected state from combat")
Check(windows[4].editBox.FocusLeft.reads > 0 and windows[4].Background.reads == 0,
    "an edit box header from combat was not replayed alone")
Check(VisitedWindows() == 1, "the drain visited windows nobody asked for")
Report("key", windows[6].editBox, "A")
Report("key", windows[6].editBox, "SPACE")
Mark()
NextFrame()
Check(windows[6].editBox.FocusLeft.reads > 0 and VisitedWindows() == 1,
    "a chat type typed with Space did not skin its box once")

-- A window report (a temporary window, a window colour) keeps its full
-- pass. A tab asked for before it gets the full pass's state; one asked for
-- after it keeps its own.
locked = true
FCF_SetWindowColor(windows[5], 0.2, 0.3, 0.4)
DockLayout(windows[4])
for _, suffix in ipairs({ "ActiveLeft", "ActiveMiddle", "ActiveRight" }) do tabs[4][suffix]:Hide() end
Report("windows")
GENERAL_CHAT_DOCK.selected = windows[1]
Report("layout")
Mark()
EndCombat()
Check(VisitedWindows() == 10, "a window report from combat lost its full pass")
Check(Is(tabs[4].Text.color, palette.text) and Is(tabs[1].Text.color, palette.title),
    "the full pass overrode a tab asked for after it")
Check(Is(windows[5].Background.vertex, palette.background)
    and Is(Checkmarks.states[windows[5].Background].original, { 0.2, 0.3, 0.4, 1 }),
    "a window colour from combat was not recaptured after it")

-- Disable drops what combat recorded and the watch: after a new Apply, a
-- later drain replays only what was asked for since.
locked = true
DockLayout(windows[1])
locked = false
Check(Chat.Disable(nil, "chat") and not Gate.IsPending("chat-frames:refresh") and not chatState.owners[Chat],
    "disable kept the deferred chat job or the ChatState watch")
Check(Chat.Apply(windows[1], "chat") and chatState.owners[Chat], "the chat skin did not apply again")
locked = true
Report("box", "focus", windows[10].editBox)
NextFrame()
Mark()
EndCombat()
skinned = SkinnedTabs()
Check(#skinned == 0 and VisitedWindows() == 1, "a drain replayed a tab recorded before disable")

------------------------------------------------- recapture of unchanged art
-- A full pass recaptures: art that still shows the skin's colour gets no
-- colour or desaturation write; art Blizzard repainted is retracked.
local repainted, unchanged = windows[7].Background, windows[8].Background
repainted:SetVertexColor(0.5, 0.5, 0.5)
local unchangedState = Checkmarks.states[unchanged]
Mark()
Report("windows")
Check(VisitedWindows() == 10, "a window report did not run the full pass")
local recaptureWrites = 0
for index, frame in ipairs(windows) do
    for _, object in ipairs({ frame, frame.buttonFrame }) do
        recaptureWrites = recaptureWrites + object.Background.writes
        for _, suffix in ipairs(BORDERS) do recaptureWrites = recaptureWrites + object[suffix].writes end
    end
    for _, suffix in ipairs(TAB_TINTED) do recaptureWrites = recaptureWrites + tabs[index][suffix].writes end
    for _, suffix in ipairs({ "FocusLeft", "FocusMid", "FocusRight" }) do
        recaptureWrites = recaptureWrites + frame.editBox[suffix].writes
    end
end
recaptureWrites = recaptureWrites - repainted.writes
Check(recaptureWrites == 0, "a recapture wrote " .. recaptureWrites .. " times to art showing the skin's colour")
Check(Checkmarks.states[unchanged] == unchangedState and Is(unchanged.vertex, palette.background)
    and unchanged.desaturated, "a recapture changed unchanged art")
Check(repainted.writes > 0 and Is(repainted.vertex, palette.background) and repainted.desaturated
    and Is(Checkmarks.states[repainted].original, { 0.5, 0.5, 0.5, 1 }),
    "a recapture did not retrack art Blizzard repainted")

-- The predicate: exact owner, role, colour, desaturation and theme; any
-- unreadable value answers false.
Check(Checkmarks.StillApplied(unchanged, "chat", "background", false), "applied art did not count as applied")
Check(not Checkmarks.StillApplied(unchanged, "other", "background", false)
    and not Checkmarks.StillApplied(unchanged, "chat", "border", false)
    and not Checkmarks.StillApplied(unchanged, "chat", "background", true)
    and not Checkmarks.StillApplied(Texture(), "chat", "background"),
    "art of another owner, role, native desaturation or untracked art counted as applied")
unchanged.secret = true
Check(not Checkmarks.StillApplied(unchanged, "chat", "background", false), "a secret colour counted as applied")
unchanged.secret = nil
unchanged.desaturated = false
Check(not Checkmarks.StillApplied(unchanged, "chat", "background", false), "lost desaturation counted as applied")
unchanged.desaturated = SECRET
Check(not Checkmarks.StillApplied(unchanged, "chat", "background", false),
    "a secret desaturation counted as applied")
unchanged.desaturated = true
NS.DB.enabled = false
Check(not Checkmarks.StillApplied(unchanged, "chat", "background", false), "a disabled skin counted as applied")
NS.DB.enabled = true
locked = true
local combatWrites = unchanged.writes
Check(Checkmarks.StillApplied(unchanged, "chat", "background", false) and unchanged.writes == combatWrites,
    "safe combat ownership predicate lost unchanged art or wrote to it")
unchanged.IsProtected = function() return true, false end
Check(not Checkmarks.StillApplied(unchanged, "chat", "background", false), "protected combat art counted as safe")
unchanged.IsProtected = nil
locked = false

-- A theme change still repaints on the next recapture.
palette.background = { 0.05, 0.2, 0.1, 1 }
Check(not Checkmarks.StillApplied(unchanged, "chat", "background", false), "a stale theme colour counted as applied")
Mark()
Report("windows")
Check(Is(unchanged.vertex, palette.background) and unchanged.writes > 0 and unchanged.desaturated,
    "a recapture after a theme change kept the previous colour")
Check(#reported == 0, "the chat skin raised: " .. table.concat(reported, "; "))

------------------------------------------------------------ drain budget
-- About 4 ms per frame, at least one job, the rest on the next frames in
-- request order, each job once.
local ran = {}
locked = true
for index = 1, 5 do
    Gate.RunOrDefer("budget" .. index, function()
        ran[#ran + 1] = index
        now = now + 3
    end)
end
Check(Gate.IsPending("budget3") and not Gate.IsPending("budget9") and Gate.GetPendingCount() == 5,
    "IsPending did not report the deferred jobs")
EndCombat()
Check(#ran == 2 and ran[1] == 1 and ran[2] == 2 and #timers == 1, "the drain ignored its budget")
Check(not Gate.IsPending("budget2") and Gate.IsPending("budget3") and gateFrame.events.PLAYER_REGEN_ENABLED,
    "the drain dropped the jobs over its budget")
NextFrame()
Check(#ran == 4 and ran[3] == 3 and ran[4] == 4 and #timers == 1, "the next frame did not go on in order")
NextFrame()
Check(#ran == 5 and ran[5] == 5 and #timers == 0 and Gate.GetPendingCount() == 0
    and not gateFrame.events.PLAYER_REGEN_ENABLED, "the drain did not finish or kept its event")

-- Combat again before the next frame: the rest waits for its end, and a
-- job asked for again meanwhile runs once, with its latest callback, in the
-- order of its latest request.
ran = {}
locked = true
for index = 1, 4 do
    Gate.RunOrDefer("again" .. index, function()
        ran[#ran + 1] = "a" .. index
        now = now + 3
    end)
end
EndCombat()
locked = true
NextFrame()
Check(#ran == 2 and #timers == 0, "the drain ran jobs during combat")
Gate.RunOrDefer("again3", function()
    ran[#ran + 1] = "a3-latest"
    now = now + 3
end)
Gate.RunOrDefer("extra", function() ran[#ran + 1] = "x" end)
EndCombat()
Check(table.concat(ran, " ") == "a1 a2 a4 a3-latest" and #timers == 1,
    "a drain resumed after combat ran out of order or twice: " .. table.concat(ran, " "))
NextFrame()
Check(table.concat(ran, " ") == "a1 a2 a4 a3-latest x" and Gate.GetPendingCount() == 0
    and not gateFrame.events.PLAYER_REGEN_ENABLED, "the resumed drain did not finish in order")

-- A request out of combat while jobs wait for the next frame runs after
-- them, as if the drain had finished at the end of combat.
ran = {}
locked = true
for index = 1, 4 do
    Gate.RunOrDefer("flush" .. index, function()
        ran[#ran + 1] = "f" .. index
        now = now + 3
    end)
end
EndCombat()
Check(Gate.RunOrDefer("flush4", function() ran[#ran + 1] = "new4" end), "an out-of-combat request did not run")
Check(table.concat(ran, " ") == "f1 f2 f3 f4 new4",
    "an out-of-combat request overtook the jobs of the drain: " .. table.concat(ran, " "))
NextFrame()
Check(#ran == 5 and Gate.GetPendingCount() == 0 and not gateFrame.events.PLAYER_REGEN_ENABLED,
    "the next frame ran a job twice or kept the event")

-- IsPending takes any key the way RunOrDefer does.
locked = true
Gate.RunOrDefer(42, Noop)
Check(Gate.IsPending(42) and Gate.IsPending("42"), "IsPending did not take the key as RunOrDefer does")
Gate.Cancel(42)
Check(not Gate.IsPending(42), "a cancelled job stayed pending")
locked = false
Check(#reported == 0, "the gate raised: " .. table.concat(reported, "; "))

print("Suite skin chat combat drain: " .. checks .. " checks passed")
