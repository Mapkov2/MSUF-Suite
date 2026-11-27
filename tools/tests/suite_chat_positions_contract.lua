local root, mode = assert(arg[1]), arg[4]
local savedArgs = arg
arg = { root, arg[2], arg[3], "positions" }
local F = dofile(root .. "/tools/tests/suite_chat_preview_contract.lua")
arg = savedArgs
local C, env, S = F.runtime.Chat, F.env, F.Suite.Suite
local mutations = {
    nativeBaseline = { "Positions", "        m.nativePositionContext = m.context", "" },
    pendingNative = { "Positions", "    C.NoteNativeWindowPosition()\n    local repaired", "    local repaired" },
    messageRestore = { "Positions", "        self.context:RestorePoints(line)", "" },
    tabRecovery = { "Window", '        S.Queue("chat")\n        return\n    end\n    -- A width change',
        '        return\n    end\n    -- A width change' },
    floatingGap = { "Window", "\n        C.PositionTabs(M)\n", "\n" },
    messageOffset = { "Positions", 'local x, y = self.config.messageTextX or 0, self.config.messageTextY or 0', 'local x, y = 0, 0' },
    inputOffset = { "Window", 'local x, y = -c.padding + c.inputX, c.inputY', 'local x, y = -c.padding, 0' },
    inputOverhang = { "Window", 'return width + 2 * c.padding', 'return width + 28' },
}
local mutation = mutations[mode]
if mutation then
    local file = assert(io.open(root .. "/MSUF_Suite_Chat/" .. mutation[1] .. ".lua", "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n") file:close()
    local a, b = assert(source:find(mutation[2], 1, true))
    local chunk = assert(loadstring(source:sub(1, a - 1) .. mutation[3] .. source:sub(b + 1)))
    setfenv(chunk, env)("MSUF_Suite_Chat", F.runtime)
end
local checks, failures = 0, 0
local function Check(ok, message)
    checks = checks + 1
    if not ok then failures = failures + 1 print("FAIL " .. message) end
end
local function Region(name, width)
    local o = env.CreateFrame("Frame", name, env.UIParent)
    o.reviewPoints, o.reviewWidth = {}, width or 100
    function o:IsClampedToScreen() return self.reviewClamped == true end
    function o:SetClampedToScreen(value) self.reviewClamped = value end
    function o:GetNumPoints() return #self.reviewPoints end
    function o:ClearAllPoints() self.reviewPoints = {} end
    function o:SetPoint(p, r, rp, x, y)
        for i, v in ipairs(self.reviewPoints) do
            if v[1] == p then self.reviewPoints[i] = { p, r, rp, x or 0, y or 0 } return end
        end
        self.reviewPoints[#self.reviewPoints + 1] = { p, r, rp, x or 0, y or 0 }
    end
    function o:GetPoint(i) return unpack(self.reviewPoints[i or 1] or {}) end
    function o:SetWidth(w) self.reviewWidth = w end
    function o:GetWidth()
        if #self.reviewPoints == 2 then
            local a, b = self.reviewPoints[1], self.reviewPoints[2]
            if a[1]:find("LEFT") and b[1]:find("RIGHT") and a[2] == b[2] then
                return a[2]:GetWidth() + b[4] - a[4]
            end
        end
        return self.reviewWidth
    end
    return o
end
local function At(o, p, relative, rp, x, y, label)
    local ap, ar, arp, ax, ay = o:GetPoint(1)
    Check(ap == p and ar == relative and arp == rp and ax == x and ay == y,
        label .. " got " .. tostring(ap) .. "/" .. tostring(arp) .. "/" .. tostring(ax) .. "/" .. tostring(ay))
end
local M, c = C.M, F.c
M.context, M.config, M.active = S.NewContext("chat"), c, true
local frame, line, other = Region("ReviewChat", 400), Region("ReviewLine"), Region("ReviewOtherLine")
line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
frame.visibleLines = { line, other }
c.messageTextX, c.messageTextY = 17, -11
C.PositionMessages(M, frame)
At(line, "BOTTOMLEFT", frame, "BOTTOMLEFT", 17, -11, "initial text offset")
line:ClearAllPoints() line:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
C.PositionMessages(M, frame)
c.messageTextX, c.messageTextY = 0, 0
C.PositionMessages(M, frame)
At(line, "TOPLEFT", frame, "TOPLEFT", 0, 0, "insertion corner after reset")
c.messageTextX, c.messageTextY = 17, -11
C.PositionMessages(M, frame)
other:ClearAllPoints() other:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
line:ClearAllPoints() line:SetPoint("TOPLEFT", other, "BOTTOMLEFT", 0, -2)
frame.visibleLines = { other, line }
C.PositionMessages(M, frame)
At(line, "TOPLEFT", other, "BOTTOMLEFT", 0, -2, "recycled first line retains new chain")
At(other, "TOPLEFT", frame, "TOPLEFT", 17, -11, "new first line gets offset")
C.ReleaseMessagePosition(M, frame)
At(other, "TOPLEFT", frame, "TOPLEFT", 0, 0, "new first line release")

local dock, nextFrame = Region("ReviewDock"), Region("ReviewNextChat", 700)
dock:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -2, 3)
dock:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 2, 3)
for i = 1, 3 do
    C.OffsetNative(M, dock, 19, 7)
    Check(dock:GetWidth() == 404, "dock preserves stretched width on pass " .. i)
end
At(dock, "BOTTOMLEFT", frame, "TOPLEFT", 17, 10, "dock repeated offset has no drift")
Check(dock:GetWidth() == 404, "dock preserved initial stretched width")
frame:SetWidth(600)
C.OffsetNative(M, dock, 19, 7)
Check(dock:GetWidth() == 604, "dock follows native primary resize")
dock:ClearAllPoints()
dock:SetPoint("BOTTOMLEFT", nextFrame, "TOPLEFT", 0, 0)
dock:SetPoint("BOTTOMRIGHT", nextFrame, "TOPRIGHT", 0, 0)
C.OffsetNative(M, dock, 19, 7)
At(dock, "BOTTOMLEFT", nextFrame, "TOPLEFT", 19, 7, "dock captures new native primary")
Check(dock:GetWidth() == 700, "dock captures new primary width")
C.OffsetNative(M, dock, 0, 0)
Check(dock:GetNumPoints() == 2, "dock restores both native anchors")
At(dock, "BOTTOMLEFT", nextFrame, "TOPLEFT", 0, 0, "dock reset retains latest primary")

local first, second = Region("ReviewChat1"), Region("ReviewChat2")
local firstTab, secondTab = Region("ReviewChat1Tab"), Region("ReviewChat2Tab")
env.ReviewChat1Tab, env.ReviewChat2Tab = firstTab, secondTab
env.GENERAL_CHAT_DOCK = dock
dock.DOCKED_CHAT_FRAMES = { first, second }
first.isDocked, second.isDocked, first.isStaticDocked, second.isStaticDocked = true, true, true, true
firstTab:SetPoint("BOTTOMLEFT", dock, "BOTTOMLEFT", 0, 0)
secondTab:SetPoint("LEFT", firstTab, "RIGHT", 1, 0)
M.visuals[first], M.visuals[second] = { tab = firstTab, frame = first }, { tab = secondTab, frame = second }
M.tabs[firstTab], M.tabs[secondTab] = M.visuals[first], M.visuals[second]
c.tabX, c.tabY, c.tabGap, c.tabPadding = 20, 10, 5, 0
C.DockGeometry()
At(secondTab, "LEFT", firstTab, "RIGHT", 6, 0, "docked gap applied")
second.isDocked = false
dock.DOCKED_CHAT_FRAMES = { first }
secondTab:ClearAllPoints() secondTab:SetPoint("BOTTOMLEFT", second, "TOPLEFT", 2, 0)
C.DockGeometry()
At(secondTab, "BOTTOMLEFT", second, "TOPLEFT", 22, 10, "undocked tab offset")
-- Blizzard rebuilt the floating anchor before the new settings apply.
secondTab:ClearAllPoints() secondTab:SetPoint("BOTTOMLEFT", second, "TOPLEFT", 2, 0)
c.tabGap = 0
C.DockGeometry()
At(secondTab, "BOTTOMLEFT", second, "TOPLEFT", 22, 10, "gap reset retains independent floating offset")

local input = Region("ReviewInput", 5)
input:SetHeight(32)
input:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -5, -2)
input:SetPoint("RIGHT", frame, "RIGHT", 23, 0)
local visual = { frame = frame }
M.visuals[frame], frame.editBox = visual, input
c.padding, c.inputTop, c.inputHeight, c.inputX, c.inputY = 4, false, 0, 0, 0
C.ApplyInputLayout(M, visual, frame, input)
At(input, "TOPLEFT", frame, "BOTTOMLEFT", -4, -6, "default input aligns with padded panel")
Check(input:GetWidth() == 608, "default input overhangs the chat panel")
Check(visual.input.allPoints == input or select(2, visual.input:GetPoint(1)) == input, "input art ignores the native edit rectangle")
c.inputX, c.inputY = 30, 12
C.ApplyInputLayout(M, visual, frame, input)
At(input, "TOPLEFT", frame, "BOTTOMLEFT", 26, 6, "input offset preserves aligned origin")
-- Suite.ChatState reports the resize (Controller ResizedReported); no
-- script hook on Blizzard's chat frame.
Check(not frame:GetScript("OnSizeChanged"), "the input hooked the native frame's size script")
frame:SetWidth(650)
C.ResizeInput(frame)
Check(input:GetWidth() == 658, "automatic input width did not follow resize")
c.inputWidth, c.inputHeight = 312, 38
C.ApplyInputLayout(M, visual, frame, input)
Check(not frame:GetScript("OnSizeChanged"), "the input hooked the native frame's size script")
Check(input:GetWidth() == 312 and input:GetHeight() == 38, "custom dimensions did not reach native input")
frame:SetWidth(700)
C.ResizeInput(frame)
Check(input:GetWidth() == 312, "chat resize overwrote the explicit input width")
c.inputTop, c.inputWidth = true, 0
C.ApplyInputLayout(M, visual, frame, input)
At(input, "BOTTOMLEFT", frame, "TOPLEFT", 26, C.HeaderTop(c, frame) + 14, "top input uses configured offset")
Check(input:GetWidth() == 708, "top input did not restore matched width")
c.inputTop, c.inputX, c.inputY, c.inputHeight = false, 0, 0, 0
C.ApplyInputLayout(M, visual, frame, input)
Check(input:GetHeight() == 32, "height reset lost native height")
M.context:RestoreProperty(input, "SetWidth")
M.context:RestorePoints(input)
Check(input:GetNumPoints() == 2, "input release did not restore both native anchors")
At(input, "TOPLEFT", frame, "BOTTOMLEFT", -5, -2, "input release lost the native origin")
Check(input:GetWidth() == 728, "input release lost the native stretch")
C.ApplyInputLayout(M, visual, frame, input)
local callbacks = 0
local complete = assert(loadfile(root .. "/MSUF_Suite_Chat/CompleteMessages.lua"))
setfenv(complete, env)("MSUF_Suite_Chat", F.runtime)
function frame:AddOnDisplayRefreshedCallback(fn) callbacks = callbacks + 1 self.displayCallback = fn end
function frame:MarkDisplayDirty() self.displayDirty = true end
function frame:GetTop() return 100 end
function frame:GetBottom() return 0 end
function line:GetTop() return select(5, self:GetPoint(1)) + 12 end
function line:GetBottom() return select(5, self:GetPoint(1)) end
function line:GetTextColor() return 1, 1, 1, 1 end
function line:SetTextColor(_, _, _, alpha) self.lineAlpha = alpha end
frame.visibleLines = { line }
line:ClearAllPoints() line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
c.messageTextX, c.messageTextY, c.completeMessages = 8, -10, true
C.ApplyCompleteMessages(M, frame)
C.ApplyCompleteMessages(M, frame)
Check(callbacks == 1 and frame.displayDirty, "message callback registration/repaint failed")
frame.displayCallback(frame)
At(line, "BOTTOMLEFT", frame, "BOTTOMLEFT", 8, -10, "display callback applies message position")
Check(line.lineAlpha == 0, "complete-message clipping ran before translation")
C.ReleaseCompleteMessages(frame)
At(line, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0, "disable restores message position")
local queued, originalQueue = 0, S.Queue
local originalCombat, originalLockdown = F.Suite.InCombat, F.Suite.IsCombatLocked
F.Suite.InCombat, F.Suite.IsCombatLocked = function() return true end, function() return false end
S.Queue = function(id) if id == "chat" then queued = queued + 1 end end
c.tabPadding, c.tabGap, c.tabX, c.tabY = 0, 0, 20, 10
C.DockGeometry()
Check(queued > 0, "combat native tab rebuild schedules offset recovery without padding/gap")
local beforeQueue = queued
frame:SetWidth(650)
C.ResizeInput(frame)
Check(queued > beforeQueue and input:GetWidth() == 708, "input resize wrote at combat start")
frame.displayCallback(frame)
At(line, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0, "message display moved at combat start")
S.Queue, F.Suite.InCombat, F.Suite.IsCombatLocked = originalQueue, originalCombat, originalLockdown
local messageX, messageY, completeMessages = c.messageTextX, c.messageTextY, c.completeMessages
local frameHeight = frame:GetHeight()
frame:SetHeight(100)
c.messageTextX, c.messageTextY, c.completeMessages = 0, 0, false
c.inputPushMessages = true
c.inputAnimationDuration = .2
input.chatFrame = frame
local draft, inputTop, inputScale = "", 30, 1
input:SetHeight(30)
function input:GetText() return draft end
function input:GetTop() return inputTop end
function input:GetEffectiveScale() return inputScale end
function frame:GetEffectiveScale() return 1 end
frame.visibleLines = { line }
local pushDriver
local createSuiteFrame = S.CreateFrame
S.CreateFrame = function(...)
    pushDriver = createSuiteFrame(...)
    return pushDriver
end
C.ApplyCompleteMessages(M, frame)
C.InputAnimationEvent("focus", input)
S.CreateFrame = createSuiteFrame
local function PushStep(seconds)
    local step = pushDriver and pushDriver:GetScript("OnUpdate")
    assert(step, "native input event did not start message shift")
    step(pushDriver, seconds)
end
PushStep(.1)
At(line, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 16, "opening interpolates")
PushStep(.1)
At(line, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 32, "open clears the actual edit box")
Check(not pushDriver:GetScript("OnUpdate"), "focused input kept ticking after settling")
frame.visibleLines = { other }
other:ClearAllPoints() other:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
frame.displayCallback(frame)
At(line, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0, "recycled line released during input")
At(other, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 32, "native refresh preserves open offset")
draft = "draft to keep"
C.InputAnimationEvent("release", input)
Check(not pushDriver:GetScript("OnUpdate"), "visible draft ended the message shift")
local secret, public = {}, S.Public
draft = secret
S.Public = function(value) return value ~= secret and public(value) end
C.InputAnimationEvent("release", input)
S.Public = public
Check(not pushDriver:GetScript("OnUpdate"), "unreadable input collapsed before native hide")
C.InputAnimationEvent("hide", input)
PushStep(.1)
At(other, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 16, "closing interpolates")
C.InputAnimationEvent("focus", input)
PushStep(.1)
At(other, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 24, "quick reopen continues from the current offset")
draft = ""
C.InputAnimationEvent("release", input)
PushStep(.2)
At(other, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0, "release restores native anchor")
Check(not pushDriver:GetScript("OnUpdate"), "closed input kept ticking")

input:SetHeight(32)
inputTop = -5
C.InputAnimationEvent("focus", input)
PushStep(.2)
At(other, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 34, "bottom input outside the transcript still slides messages")
C.InputAnimationEvent("hide", input)
PushStep(.2)
At(other, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0, "non-overlapping input restores the transcript on close")

inputTop, inputScale = -4, 1.25
C.InputAnimationEvent("focus", input)
PushStep(.2)
At(other, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 42, "minimum travel uses the input height in chat coordinates")
C.InputAnimationEvent("hide", input)
PushStep(.2)

inputTop, inputScale, c.messageTextY = 37, 1, -8
C.InputAnimationEvent("focus", input)
PushStep(.2)
At(other, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 39, "negative message offset still clears the top of the input")
C.InputAnimationEvent("hide", input)
PushStep(.2)
At(other, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, -8, "closing retains the configured message offset")

inputTop, c.messageTextY = 100, 0
C.InputAnimationEvent("focus", input)
PushStep(.2)
At(other, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 50, "movement stays bounded in small chat windows")
C.InputAnimationEvent("hide", input)
PushStep(.2)

inputTop = 30
input:SetHeight(30)
local dockedLine = Region("ReviewDockedVisibleLine")
dockedLine:SetPoint("BOTTOMLEFT", second, "BOTTOMLEFT", 0, 0)
second.visibleLines = { dockedLine }
second:SetHeight(100)
second.GetEffectiveScale = frame.GetEffectiveScale
second.GetBottom = frame.GetBottom
second.MarkDisplayDirty = frame.MarkDisplayDirty
local oldSelected = dock.selected
dock.selected, frame.isDocked = second, true
C.InputAnimationEvent("focus", input)
PushStep(.2)
At(dockedLine, "BOTTOMLEFT", second, "BOTTOMLEFT", 0, 32, "General input clears the displayed dock tab")
At(other, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0, "hidden dock tab keeps its original anchor")
dock.selected, frame.isDocked = oldSelected, nil
C.InputAnimationEvent("hide", input)
PushStep(.2)
At(dockedLine, "BOTTOMLEFT", second, "BOTTOMLEFT", 0, 0, "changed tab selection still restores the shifted tab")
C.InputAnimationEvent("focus", input)
local originalDirty = frame.MarkDisplayDirty
frame.MarkDisplayDirty = function() error("input animation requested a native refresh in combat") end
F.Suite.InCombat = function() return true end
S.Queue = function(id) if id == "chat" then queued = queued + 1 end end
local previousQueue = queued
PushStep(.1)
At(other, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0, "input animation leaves native combat anchors alone")
Check(queued > previousQueue and not pushDriver:GetScript("OnUpdate"), "combat defers placement without a ticker")
S.Queue, F.Suite.InCombat, frame.MarkDisplayDirty = originalQueue, originalCombat, originalDirty
frame.displayCallback(frame)
At(other, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 32, "post-combat display applies the focused offset")
C.InputAnimationEvent("focus", input)
PushStep(.2)
c.inputPushMessages = false
C.ApplyCompleteMessages(M, frame)
At(other, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0, "toggle off restores immediately")
c.messageTextX, c.messageTextY, c.completeMessages = messageX, messageY, completeMessages
frame:SetHeight(frameHeight)
-- Native layout rewrites happen after ApplyAll (login/layout/UI changes).
-- Exercise the actual reversible context, and defer until the complete
-- multi-anchor burst has finished instead of rewriting inside SetPoint.
local primary = Region("ReviewPrimaryChat")
primary:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, 160)
local primaryVisual = { frame = primary }
M.visuals[primary] = primaryVisual
local timers, hookCount, writes = {}, 0, 0
local positionHook
local oldHook, oldTimer = env.hooksecurefunc, env.C_Timer
local oldManager = env.EditModeManagerFrame
local hiddenManager = Region("ReviewHiddenNativeEditMode")
hiddenManager:Hide()
env.EditModeManagerFrame = hiddenManager
local rawPoint = primary.SetPoint
function primary:SetPoint(...)
    writes = writes + 1
    return rawPoint(self, ...)
end
-- No SetPoint hook on Blizzard's window: Suite.ChatState asks again after
-- Blizzard's window updates, dock layouts, drags and Edit Mode exit.
env.hooksecurefunc = function(object, method)
    hookCount = hookCount + 1
    error("chat hooked " .. tostring(method) .. " of " .. tostring(object))
end
positionHook = function() C.CheckWindowPosition() end
env.C_Timer = { After = function(delay, callback)
    Check(delay == 0, "position recovery must be a one-shot layout drain")
    timers[#timers + 1] = callback
end }
local function Drain()
    local callbacks = timers
    timers = {}
    for _, callback in ipairs(callbacks) do callback() end
    Check(#timers == 0, "own anchor scheduled another correction")
end
-- Blizzard re-anchors the window and ChatState reports it.
local function Native(y)
    primary:ClearAllPoints()
    primary:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, y)
    C.CheckWindowPosition()
end
c.lockWindowPosition, c.windowX, c.windowY = true, 12, 52
S.editMode = false
C.ApplyWindowPosition(M, primaryVisual, primary, true)
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 12, 52, "initial window placement")
for _ = 1, 100 do C.ApplyWindowPosition(M, primaryVisual, primary, true) end
Check(hookCount == 0 and #timers == 0, "warm refresh hooks the anchor or schedules recovery")
local stableWrites = writes
for i = 1, 20 do Native(120 + i) end
local instructions = 0
local function CountInstruction() instructions = instructions + 1 end
debug.sethook(CountInstruction, "", 1)
for _ = 1, 1000 do positionHook(primary) end
debug.sethook()
Check(instructions < 90000, "coalesced layout callback exceeded 90 VM instructions per call")
local allocated = math.huge
for _ = 1, 2 do
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 1000 do positionHook(primary) end
    allocated = math.min(allocated, collectgarbage("count") - before)
    collectgarbage("restart")
end
Check(allocated < 1, "coalesced layout callback allocates per event")
print("Chat anchor burst budget: " .. instructions .. " VM/1000, " .. allocated .. " KB/1000")
Check(#timers == 1 and writes == stableWrites + 20, "native layout burst was not deferred/coalesced")
primary:SetPoint("TOPRIGHT", env.UIParent, "TOPRIGHT", -40, -100)
C.CheckWindowPosition()
Drain()
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 12, 52, "native late layout recovers without Edit Mode")
Check(primary:GetNumPoints() == 1, "late second native point survived recovery")
c.lockWindowPosition = false
C.ApplyWindowPosition(M, primaryVisual, primary, true)
Check(primary:GetNumPoints() == 2, "unlock lost latest complete native anchor set")
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, 140, "unlock restores latest native layout")
Native(180)
Check(#timers == 0, "unlocked chat still schedules corrections")
c.lockWindowPosition = true
C.ApplyWindowPosition(M, primaryVisual, primary, true)
Native(200)
S.editMode = true
Drain()
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, 200, "pending correction yields to Edit Mode")
Native(210)
Check(#timers == 0, "mover drag scheduled a snap-back")
c.windowX, c.windowY = 44, 66
S.editMode = false
C.ApplyWindowPosition(M, primaryVisual, primary, true)
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 44, 66, "committed mover position retained")
-- The real mover uses direct SetPoint during preview, then refreshes the
-- saved coordinates on commit. It must not become the native restore base.
c.lockWindowPosition = false
C.ApplyWindowPosition(M, primaryVisual, primary, true)
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, 180, "mover commit preserves native restore base")
c.lockWindowPosition = true
C.ApplyWindowPosition(M, primaryVisual, primary, true)
S.editMode = true
Native(212.345)
c.windowX, c.windowY = 30, 212.3
C.ApplyWindowPosition(M, primaryVisual, primary, true)
S.editMode = false
c.lockWindowPosition = false
C.ApplyWindowPosition(M, primaryVisual, primary, true)
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, 180, "rounded mover commit preserves native restore base")
c.lockWindowPosition, c.windowX, c.windowY = true, 44, 66
C.ApplyWindowPosition(M, primaryVisual, primary, true)
local manager = Region("ReviewNativeEditMode")
env.EditModeManagerFrame = manager
manager:Hide()
C.ApplyWindowPosition(M, primaryVisual, primary, true)
manager:Show()
Native(215)
Check(#timers == 0, "native Edit Mode drag scheduled a snap-back")
manager:Hide()
Check(not manager:GetScript("OnHide"), "chat hooked Blizzard's Edit Mode manager")
C.CheckWindowPosition() -- ChatState: EditMode.Exit, then the window report
Check(#timers == 1, "native Edit Mode exit did not schedule recovery")
Drain()
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 44, 66, "native Edit Mode exit restores Suite anchor")
env.EditModeManagerFrame = hiddenManager
-- A native no-op layout burst must not cause extra position writes.
primary:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 44, 66)
C.CheckWindowPosition()
stableWrites = writes
Drain()
Check(writes == stableWrites, "already-correct native layout rewrote the anchor")
Native(220)
F.Suite.InCombat = function() return true end
S.Queue = function(id) Check(id == "chat", "wrong combat recovery owner") queued = queued + 1 end
stableWrites = writes
local priorQueue = queued
Drain()
Check(writes == stableWrites and queued == priorQueue + 1, "pending correction writes at combat edge")
Native(230)
Check(#timers == 0 and queued == priorQueue + 2, "combat layout does not defer through existing queue")
F.Suite.InCombat = originalCombat
C.ApplyWindowPosition(M, primaryVisual, primary, true)
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 44, 66, "combat replay recovers position")
c.lockWindowPosition = false
C.ApplyWindowPosition(M, primaryVisual, primary, true)
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, 230, "combat replay retains latest native restore base")
c.lockWindowPosition = true
C.ApplyWindowPosition(M, primaryVisual, primary, true)
Native(235)
C.ApplyWindowPosition(M, primaryVisual, primary, true)
Drain()
c.lockWindowPosition = false
C.ApplyWindowPosition(M, primaryVisual, primary, true)
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, 235, "refresh before timer retains native restore base")
c.lockWindowPosition = true
C.ApplyWindowPosition(M, primaryVisual, primary, true)
Native(240)
c.lockWindowPosition = false
Drain()
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, 240, "unlock cancels pending correction")
c.lockWindowPosition = true
Native(250)
M.active = false
Drain()
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, 250, "disable cancels pending correction")
M.active = true
Native(260)
local oldContext = M.context
M.context = S.NewContext("chat")
Drain()
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, 260, "old context cannot write into replacement")
M.context = oldContext
S.Queue, env.hooksecurefunc, env.C_Timer = originalQueue, oldHook, oldTimer
env.EditModeManagerFrame = oldManager
-- A chat at the lower edge still has a visible, matching native input.
do
    c.lockWindowPosition, c.inputTop, c.inputX, c.inputY = true, false, 0, 0
    C.ApplyInputLayout(M, visual, frame, input)
    Check(input:IsClampedToScreen(), "anchored input may disappear below screen")
    local _, relative = visual.input:GetPoint(1)
    Check(relative == input or visual.input.allPoints == input, "input backdrop ignores the clamped native rectangle")
    c.lockWindowPosition = false
    C.ApplyInputLayout(M, visual, frame, input)
    Check(not input:IsClampedToScreen(), "unlocked chat retained Suite input clamping")
end

-- A synchronous native window refresh paints before its later position
-- callback. Its preflight must capture the latest foreign base first.
M.context, M.active, S.editMode = S.NewContext("chat"), true, false
env.EditModeManagerFrame = hiddenManager
c.lockWindowPosition, c.windowX, c.windowY = true, 44, 66
primary:ClearAllPoints()
primary:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, 280)
C.ApplyWindowPosition(M, primaryVisual, primary, true)
primary:ClearAllPoints()
primary:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, 330)
C.NoteNativeWindowPosition()
C.ApplyWindowPosition(M, primaryVisual, primary, true)
c.lockWindowPosition = false
C.ApplyWindowPosition(M, primaryVisual, primary, true)
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, 330, "native refresh preflight retains latest restore base")

-- The primary can change after an input-only callback scheduled the drain.
c.lockWindowPosition = true
C.ApplyWindowPosition(M, primaryVisual, primary, true)
frame.editBox, M.visuals[frame] = input, visual
C.ApplyInputLayout(M, visual, frame, input)
env.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
input:SetWidth(input:GetWidth() + 40)
C.CheckWindowGeometry(frame)
primary:ClearAllPoints()
primary:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, 370)
Drain()
c.lockWindowPosition = false
C.ApplyWindowPosition(M, primaryVisual, primary, true)
At(primary, "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 30, 370, "pending input drain captures later native primary base")

-- The deferred toolbar refresh uses the productive Context and Timers
-- prototype, not just the controller's lightweight context fixture.
local timerContext = S.NewContext("chat")
local loadTimers = assert(loadfile(root .. "/MSUF_Suite_Modules/Timers.lua"))
setfenv(loadTimers, env)("MSUF_Suite_Modules", { NS = F.Suite, Suite = S, Context = getmetatable(timerContext) })
Check(type(timerContext.After) == "function", "productive context has no deferred After method")
local oldInstance, oldRefresh, oldPrimary = S.instances.chat, M.Refresh, env.ChatFrame1
local refreshed = 0
S.instances.chat, env.ChatFrame1 = M, primary
M.Refresh = function() refreshed = refreshed + 1 end
M.context, M.config, M.active = timerContext, c, true
local proxy = Region("NativeTimerToolbarProxy")
function proxy:StopMovingOrSizing() end
function proxy:UnregisterEvent() end
M.toolbarProxy = proxy
for _ = 1, 2 do
    M.toolbarGesture, M.toolbarRefreshPending = { context = timerContext, config = c }, true
    timerContext:Anchor(primary, "BOTTOMLEFT", proxy, "BOTTOMLEFT", 0, 0)
    C.StopToolbarGesture(false)
    Drain()
end
Check(refreshed == 2 and not M.toolbarRefreshContext, "productive timer lost or repeated the deferred toolbar refresh")
S.instances.chat, M.Refresh, env.ChatFrame1 = oldInstance, oldRefresh, oldPrimary

print("Chat native positions: " .. checks .. " checks, " .. failures .. " failures")
if failures > 0 then error("native ownership regression") end
