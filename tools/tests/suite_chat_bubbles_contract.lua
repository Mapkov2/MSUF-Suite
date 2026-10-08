-- Speech bubbles: the client model follows Blizzard_ChatBubble on Retail
-- and Forever. GetAllChatBubbles(false) returns holder frames whose child is
-- the ChatBubbleTemplate (String, Tail, nine-slice pieces); inside instances
-- every bubble is forbidden and the API returns none of them.
local root = assert(arg[1])
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local events, cvars, restoredCVars = {}, {}, {}
local function eq(a, b, label) assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function Texture()
    local texture = { alpha = 1, shown = true }
    function texture:GetAlpha() return self.alpha end
    function texture:SetAlpha(alpha) self.alpha = alpha end
    function texture:ClearAllPoints() end
    function texture:SetPoint() end
    function texture:SetHeight() end
    function texture:SetWidth() end
    function texture:Show() self.shown = true end
    function texture:Hide() self.shown = false end
    return texture
end
local fills = 0
local CHROME = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center", "Tail" }
local function Bubble(text)
    local region = { font = "Native", size = 12, flags = "", width = 450, text = text, color = { 1, 1, 1, 1 } }
    function region:GetText() return self.text end
    function region:GetFont() return self.font, self.size, self.flags end
    function region:SetFont(p, s, f) self.font, self.size, self.flags = p, s, f end
    function region:GetWidth() return self.width end
    function region:SetWidth(w) self.width = w end
    function region:GetTextColor() return unpack(self.color) end
    function region:SetTextColor(...) self.color = { ... } end
    local content = { String = region, scripts = {}, shown = true }
    for _, key in ipairs(CHROME) do content[key] = Texture() end
    function content:IsShown() return self.shown end
    function content:HookScript(script, callback)
        assert(not self.scripts[script], "a bubble got the same hook twice")
        self.scripts[script] = callback
    end
    local holder = {}
    function holder:GetChildren() return content end
    function holder:GetRegions() error("discovery walked every region of a bubble") end
    content.holder = holder
    return content
end
local live = {}
local function Show(content, text)
    content.String.text = text
    content.shown = true
    for _, bubble in ipairs(live) do if bubble == content then return end end
    live[#live + 1] = content
end
local function Hide(content)
    content.shown = false
    for i, bubble in ipairs(live) do if bubble == content then table.remove(live, i) end end
    if content.scripts.OnHide then content.scripts.OnHide(content) end
end
local inInstance, apiCalls = false, 0
-- The client returns a new table per call; the fixture reuses one so the
-- allocation check below only sees the module's own work.
local holders = {}
C_ChatBubbles = { GetAllChatBubbles = function(includeForbidden)
    assert(includeForbidden == false, "forbidden bubbles were requested")
    apiCalls = apiCalls + 1
    for i = #holders, 1, -1 do holders[i] = nil end
    if not inInstance then
        for i, content in ipairs(live) do holders[i] = content.holder end
    end
    return holders
end }
IsInInstance = function() return inInstance end
local now = 0
GetTime = function() return now end
C_Timer = { NewTimer = function() error("bubble discovery used a timer") end, After = function() error("bubble discovery used a timer") end }
local scanner
local S = {
    Public = function() return true end,
    PublicText = function(v) return type(v) == "string" and v ~= "" and v or nil end,
    Finite = function(v) return type(v) == "number" end,
    ResolveFont = function() return "Custom" end, GlobalFontPath = function() return "Custom" end,
    RGB = function(hex) return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 end,
    RestoreCVar = function(_, name) restoredCVars[name] = true end,
    Queue = function() error("bubbles queued the module for combat end") end,
    CreateFrame = function()
        assert(not scanner, "bubble discovery made a second frame")
        scanner = { shown = true }
        function scanner:Hide() self.shown = false end
        function scanner:Show() self.shown = true end
        function scanner:IsShown() return self.shown end
        function scanner:SetScript(_, callback) self.update = callback end
        return scanner
    end,
}
local context = { combat = {} }
function context:Event(e, fn, options) events[e], self.combat[e] = fn, Support.InCombatOption(options) or nil end
function context:RemoveEvent(e) events[e], self.combat[e] = nil, nil end
function context:CVar(name, value) cvars[name] = value end
local config, catalogNS = Support.CatalogDefaults(root, "chat")
config.styleBubbles, config.bubbleFontSize, config.bubbleMaxWidth = true, 18, 200
local M = { active = true, context = context, config = config, visuals = {} }
local C = { M = M, Fill = function() fills = fills + 1; return Texture() end, Tint = function(texture, hex, alpha)
    texture.hex, texture.tint = hex, alpha
end }
local NS = { Safety = { IsForbidden = function(frame) return frame.forbidden == true end },
    IsCombatLocked = function() return true end, ChatBubbleSources = catalogNS.ChatBubbleSources }
-- The production listener helper (Shared.lua) registers the bubble events.
local shared = { NS = NS, Suite = S }
assert(loadfile(root .. "/MSUF_Suite_Chat/Shared.lua"))("MSUF_Suite_Chat", shared)
C.ListenInCombat = shared.Chat.ListenInCombat
assert(loadfile(root .. "/MSUF_Suite_Chat/Bubbles.lua"))("MSUF_Suite_Chat", { NS = NS, Suite = S, Chat = C })
-- The OnUpdate scanner runs while it is shown; each frame advances time.
local function Frames(seconds, step)
    step = step or 0.016
    local passes = apiCalls
    local elapsed = 0
    while elapsed < seconds do
        if not scanner or not scanner.shown then break end
        now = now + step
        elapsed = elapsed + step
        scanner.update(scanner, step)
    end
    return apiCalls - passes
end
local function Speech(event, text) events[event](M, event, text) end

C.BubblesRefresh(M)
assert(events.CHAT_MSG_SAY and events.CHAT_MSG_YELL and events.CHAT_MSG_PARTY and events.CHAT_MSG_RAID
    and events.CHAT_MSG_MONSTER_SAY and events.PLAYER_ENTERING_WORLD, "bubble sources are not followed")
assert(events.CHAT_MSG_EMOTE and events.CHAT_MSG_TEXT_EMOTE and events.CHAT_MSG_MONSTER_EMOTE,
    "emotes are not a bubble source")
-- Chat is a geometry module: every bubble listener must also run in combat
-- (the context's allowCombat).
for event in pairs(events) do
    assert(context.combat[event] == true, event .. " waits for the end of combat")
end
-- Styled in combat too: nothing in the bubble path waits for combat end.
local hello = Bubble()
Show(hello, "hello")
Speech("CHAT_MSG_SAY", "hello")
eq(Frames(1), 1, "a bubble found on the first pass was looked for again")
local region = hello.String
assert(region.font == "Custom" and region.size == 18 and region.width == 200 and hello.Tail.alpha == 0
    and hello.Center.alpha == 0, "native bubble not styled")
assert(not scanner.shown, "discovery kept running after every heard line found its bubble")
config.bubbleMaxWidth = 350
C.BubblesRefresh(M)
eq(region.width, 350, "larger width must restore native width before applying cap")
config.bubbleStyleNearby = false
C.BubblesRefresh(M)
assert(region.font ~= "Custom", "source toggle off did not restore native bubble")
config.bubbleStyleNearby = true
C.BubblesRefresh(M)
assert(region.font == "Custom", "same visible text did not regain its source style")
-- A line whose bubble shows late is still found within its time.
local late = Bubble()
Speech("CHAT_MSG_PARTY", "late one")
Frames(0.2)
Show(late, "late one")
Frames(0.2)
eq(late.String.font, "Custom", "a bubble that showed a moment after its line stayed native")
-- Lines that never get a bubble stop discovery once their time ran out.
Speech("CHAT_MSG_RAID", "far away")
local passes = Frames(5)
assert(not scanner.shown and passes <= 6, "discovery for a line without a bubble did not stop (" .. passes .. " passes)")
-- Continuous speech: an old line expires and never styles a later bubble.
Speech("CHAT_MSG_SAY", "old words")
for i = 1, 30 do
    Speech("CHAT_MSG_SAY", "chatter " .. i)
    Frames(0.1)
end
local stale = Bubble()
Show(stale, "old words")
Speech("CHAT_MSG_SAY", "something else")
Frames(1)
eq(stale.String.font, "Native", "a line heard long ago styled a later bubble")
-- Continuous speech keeps a bounded set of heard lines and allocates
-- nothing per pass once the bubbles are known.
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 50 do
    Speech("CHAT_MSG_SAY", "hello")
    Frames(0.05)
end
local grown = collectgarbage("count") - before
collectgarbage("restart")
assert(grown < 2, "bubble discovery allocated per pass (" .. grown .. " KB)")
-- Unchanged visible bubbles keep their source when other lines arrive.
Speech("CHAT_MSG_SAY", "different bubble")
Frames(1)
assert(region.font == "Custom" and region.width == 350,
    "later unrelated speech must retain the category of an unchanged visible bubble")
-- A hidden bubble takes its native look back at once; reused for a source
-- that keeps Blizzard's look, it stays native.
Hide(hello)
assert(region.font == "Native" and region.width == 450 and hello.Tail.alpha == 1 and region.color[1] == 1,
    "a hidden bubble kept the Suite style until the next pass")
config.bubbleStyleYell = false
Show(hello, "recycled")
Speech("CHAT_MSG_YELL", "recycled")
Frames(1)
assert(region.font == "Native" and region.width == 450 and hello.Tail.alpha == 1,
    "recycled disabled source retained old style")
-- Yells are their own source: a yell keeps Blizzard's look while nearby
-- speech uses the MSUF look.
local shout = Bubble()
Show(shout, "Charge!")
Speech("CHAT_MSG_YELL", "Charge!")
local spoken = Bubble()
Show(spoken, "Hi there")
Speech("CHAT_MSG_SAY", "Hi there")
Frames(1)
assert(shout.String.font == "Native" and spoken.String.font == "Custom",
    "yells and nearby speech did not follow their own source settings")
config.bubbleStyleYell = true
Hide(shout)
Hide(spoken)
-- A source with its own look: its own text color, size, spacing and width.
config.bubbleOwnCreature, config.bubbleTextCreature = true, "ff0000"
config.bubbleSizeCreature, config.bubbleWidthCreature = 22, 150
local npc = Bubble()
Show(npc, "You dare?")
Speech("CHAT_MSG_MONSTER_YELL", "You dare?")
Frames(1)
local color = npc.String.color
assert(math.abs(color[1] - 1) < 0.01 and color[2] == 0 and color[3] == 0, "creature bubbles ignored their own text color")
assert(npc.String.size == 22 and npc.String.width == 150, "creature bubbles ignored their own size or width")
-- Emotes are a source too, styled in the shared look.
local wave = Bubble()
Show(wave, "Mapko waves.")
Speech("CHAT_MSG_TEXT_EMOTE", "Mapko waves.")
Frames(1)
assert(wave.String.font == "Custom" and wave.String.size == 18, "an emote bubble did not take the shared MSUF look")
Hide(wave)
npc.String.font = "BlizzardChanged"
Hide(npc)
eq(npc.String.font, "BlizzardChanged", "restoring the bubble overwrote Blizzard's own font")
-- Inside instances bubbles are forbidden: nothing is heard or looked for,
-- and hideInstanceBubbles turns all three bubble settings off.
config.hideInstanceBubbles = true
inInstance = true
events.PLAYER_ENTERING_WORLD(M, "PLAYER_ENTERING_WORLD")
assert(cvars.chatBubbles == "0" and cvars.chatBubblesParty == "0" and cvars.chatBubblesRaid == "0",
    "instance hiding left a bubble setting on")
local calls = apiCalls
Speech("CHAT_MSG_SAY", "inside")
assert(not scanner.shown, "a line heard inside an instance was kept for a bubble")
Frames(1)
eq(apiCalls, calls, "bubbles were looked for inside an instance")
inInstance = false
events.ZONE_CHANGED_NEW_AREA(M, "ZONE_CHANGED_NEW_AREA")
assert(restoredCVars.chatBubbles and restoredCVars.chatBubblesParty and restoredCVars.chatBubblesRaid,
    "leaving the instance did not hand the bubble settings back")
-- A forbidden bubble is never indexed.
local locked = setmetatable({ forbidden = true }, { __index = function(_, key)
    error("a forbidden bubble was indexed: " .. tostring(key))
end })
local lockedEntry = { holder = { GetChildren = function() return locked end } }
live[#live + 1] = lockedEntry
Speech("CHAT_MSG_SAY", "x")
Frames(1)
table.remove(live)
-- A full set of heard lines (48 found within their time) stops discovery;
-- once they expired, the next line is still heard and styled.
local crowd = {}
for i = 1, 48 do
    crowd[i] = Bubble()
    Show(crowd[i], "crowd " .. i)
    Speech("CHAT_MSG_SAY", "crowd " .. i)
end
Frames(0.05)
assert(not scanner.shown and crowd[48].String.font == "Custom", "the crowd's bubbles were not found at once")
now = now + 1
local fresh = Bubble()
Show(fresh, "after the crowd")
Speech("CHAT_MSG_SAY", "after the crowd")
Frames(1)
eq(fresh.String.font, "Custom", "a full set of expired heard lines rejected every new line")
for i = 1, 48 do Hide(crowd[i]) end
Hide(fresh)
-- Disabling restores every styled bubble and stops listening.
Show(hello, "hello")
Speech("CHAT_MSG_SAY", "hello")
Frames(1)
eq(region.font, "Custom", "bubble restyled after reuse")
config.styleBubbles = false
C.BubblesRefresh(M)
assert(region.font == "Native" and region.width == 450 and hello.Tail.alpha == 1 and not events.CHAT_MSG_SAY,
    "disable failed to restore native bubble")
print("chat bubble restoration PASS")
