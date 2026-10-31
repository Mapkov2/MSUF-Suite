local root, mode = assert(arg[1]), arg[4]
local savedArgs = arg
arg = { root, arg[2], arg[3], "positions" }
local F = dofile(root .. "/tools/tests/suite_chat_preview_contract.lua")
arg = savedArgs
local C, env, S = F.runtime.Chat, F.env, F.Suite.Suite
local mutations = {
    messageRestore = { "Positions", "        self.context:RestorePoints(line)", "" },
    tabRecovery = { "Window", '        S.Queue("chat")\n        return\n    end\n    if padded then',
        '        return\n    end\n    if padded then' },
    floatingGap = { "Window", "        C.PositionTabs(M)\n        return", "        return" },
    messageOffset = { "Positions", 'local x, y = self.config.messageTextX or 0, self.config.messageTextY or 0', 'local x, y = 0, 0' },
    inputOffset = { "Window", 'local x, y = c.inputX or 0, c.inputY or 0', 'local x, y = 0, 0' },
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
c.inputTop, c.inputHeight, c.inputX, c.inputY = false, 0, 30, 12
C.ApplyInputLayout(M, visual, frame, input)
At(input, "TOPLEFT", frame, "BOTTOMLEFT", 25, 10, "input offset preserves native origin")
Check(input:GetWidth() == 628, "input offset preserves native stretched width")
local resize = frame:GetScript("OnSizeChanged")
Check(resize ~= nil, "input has no native resize callback")
frame:SetWidth(650)
resize(frame, 650, 180)
Check(input:GetWidth() == 678, "input resize follows native width")
C.ApplyInputLayout(M, visual, frame, input)
Check(frame:GetScript("OnSizeChanged") == resize, "input resize callback installed twice")
c.inputTop = true
C.PreviewInput(M, visual, frame, input)
At(input, "BOTTOMLEFT", frame, "TOPLEFT", -c.padding + 30, C.HeaderTop(c, frame) + 14, "top input uses configured offset")
c.inputTop, c.inputX, c.inputY = false, 0, 0
C.PreviewInput(M, visual, frame, input)
Check(input:GetNumPoints() == 2, "input reset restores two anchors")
At(input, "TOPLEFT", frame, "BOTTOMLEFT", -5, -2, "input reset restores native origin")
Check(input:GetWidth() == 678, "input reset restores native stretch")
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
visual.inputMoved = true
resize(frame, 700, 180)
Check(queued > beforeQueue and input:GetWidth() == 678, "input resize wrote at combat start")
frame.displayCallback(frame)
At(line, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0, "message display moved at combat start")
S.Queue, F.Suite.InCombat, F.Suite.IsCombatLocked = originalQueue, originalCombat, originalLockdown
print("Chat native positions: " .. checks .. " checks, " .. failures .. " failures")
if failures > 0 then error("native ownership regression") end
