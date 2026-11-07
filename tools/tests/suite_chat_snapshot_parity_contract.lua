-- Independent native/runtime versus owned preview contract.
local root = assert(arg[1])
local file = assert(io.open(root .. "/tools/tests/suite_chat_preview_contract.lua", "rb"))
local source = file:read("*a") file:close()
local F = assert(loadstring(source .. "\nreturn {ui=ui,P=P,env=env,mw=mw,runtime=runtime,Suite=Suite,R=R}", "@snapshot-parity-world"))()
local C, env, S, ui, P = F.runtime.Chat, F.env, F.Suite.Suite, F.ui, F.P
local c = S.Config("chat")
for _, line in ipairs(ui.parts.messageLines) do
    -- The shared widget fixture stores SetSpacing but has no GetSpacing.
    function line:GetSpacing() return self.spacing or 0 end
end
local function Upvalue(fn, wanted)
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
end
local checks, failures = 0, 0
local function Check(ok, text)
    checks = checks + 1
    if not ok then failures = failures + 1 print("FAIL " .. text) end
end
local frame = env.CreateFrame("Frame", "ParitySnapshotChat", env.UIParent)
frame:SetSize(610, 360)
frame:SetFont("NativeMessage.ttf", 18, "")
frame:SetShadowColor(.2, .3, .4, .7)
frame:SetShadowOffset(2, -3)
function frame:GetInsertMode() return "BOTTOM" end
function frame:GetSpacing() return 2 end
local tab = env.CreateFrame("Frame", "ParitySnapshotChatTab", frame)
tab:SetSize(91, 32)
tab.Text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tab.Text:SetText(ui.parts.label:GetText())
tab.Text:SetFont("NativeTab.ttf", 15, "OUTLINE")
env.ParitySnapshotChatTab = tab
local input = env.CreateFrame("Frame", "ParitySnapshotInput", frame)
input:SetSize(631, 32)
input:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -5, -2)
input:SetPoint("RIGHT", frame, "RIGHT", 16, 0)
input.header = input:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
input.header:SetFont("NativeInput.ttf", 17, "")
frame.editBox = input
env.ChatFrame1, env.SELECTED_DOCK_FRAME = frame, frame
local dock = env.CreateFrame("Frame", "ParitySnapshotDock", env.UIParent)
dock.selected, dock.DOCKED_CHAT_FRAMES = frame, { frame }
env.GENERAL_CHAT_DOCK = dock
local M = C.M
M.context, M.config, M.active = S.NewContext("chat"), c, true
c.enabled, c.lockWindowSize = true, false
c.font, c.tabFont = "__BLIZZARD_CHAT_FONT__", "__BLIZZARD_CHAT_FONT__"
c.fontSize, c.tabFontSize, c.fontOutline, c.fontRendering, c.fontShadow = 0, 0, 1, 1, 1
c.tabHeight, c.tabPadding, c.tabX, c.tabY = 24, 0, 0, 0
c.inputTop, c.inputHeight, c.inputX, c.inputY = false, 0, 0, 0
c.messageTextX, c.messageTextY, c.padding = 0, 0, 16
P.ChatPreviewPaint.Refresh(ui)
Check(ui.parts.sample:GetWidth() == 610 and ui.parts.sample:GetHeight() == 360, "native unlocked dimensions are not copied")
for i, line in ipairs(ui.parts.messageLines) do
    local path, size, flags = line:GetFont()
    Check(path == "NativeMessage.ttf" and size == 18 and flags == "", "native default message font differs on line " .. i)
    local r,g,b,a = line:GetShadowColor()
    local x,y = line:GetShadowOffset()
    Check(r == .2 and g == .3 and b == .4 and a == .7 and x == 2 and y == -3, "native asymmetric/color shadow differs on line " .. i)
    Check(line.GetSpacing and line:GetSpacing() == 2, "wrapped message line spacing differs on line " .. i)
end
local path, size, flags = ui.parts.label:GetFont()
Check(path == "NativeTab.ttf" and size == 15 and flags == "OUTLINE", "native default tab font differs")
Check(ui.parts.tabs[1]:GetWidth() == tab:GetWidth(), "native default tab width differs")
Check(ui.parts.tabs[1]:GetHeight() == tab:GetHeight(), "default tab height differs")
local p, rel, rp, x, y = ui.parts.input:GetPoint(1)
Check(p == "TOPLEFT" and rel == ui.parts.sample and rp == "BOTTOMLEFT" and x == -16 and y == -18, "input origin is not aligned to the padded panel")
Check(ui.parts.input:GetWidth() == 642 and ui.parts.input:GetHeight() == 32, "aligned input bounds or native height differ")
path, size, flags = ui.parts.prompt:GetFont()
Check(path == "NativeInput.ttf" and size == 17 and flags == "", "native input header font differs")
local _, _, _, promptX = ui.parts.prompt:GetPoint(1)
Check(promptX == 15, "native input header inset differs")

-- Native dock origins and selection are data, not always first-tab/(0,3).
local second = env.CreateFrame("Frame", "ParitySnapshotSecond", env.UIParent)
function second:GetID() return 7 end
second:SetSize(610, 360)
second:SetFont("NativeMessage.ttf", 18, "")
second:SetShadowColor(.2, .3, .4, .7)
second:SetShadowOffset(2, -3)
second.GetInsertMode, second.GetSpacing = frame.GetInsertMode, frame.GetSpacing
local secondTab = env.CreateFrame("Frame", "ParitySnapshotSecondTab", second)
secondTab:SetSize(113, 32)
secondTab.Text = secondTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
secondTab.Text:SetFont("NativeTab.ttf", 15, "OUTLINE")
tab.Text:SetText("Primary Runtime Label")
secondTab.Text:SetText("Secondary Runtime Label")
env.ParitySnapshotSecondTab = secondTab
function frame:GetLeft() return 100 end
function frame:GetTop() return 400 end
second.GetLeft, second.GetTop = frame.GetLeft, frame.GetTop
function dock:GetLeft() return 98 end
function dock:GetBottom() return 403 end
dock.selected, dock.DOCKED_CHAT_FRAMES = second, { frame, second }
env.SELECTED_DOCK_FRAME = second
c.tabPanel, c.tabAccent, c.panelAlpha, c.accentAlpha = true, true, 100, 100
c.tabActiveColor, c.tabInactiveColor, c.tabClassColor = "112233", "aabbcc", false
P.ChatPreviewPaint.Refresh(ui)
Check(not ui.parts.tabs[1].visual.tabLine:IsShown() and ui.parts.tabs[2].visual.tabLine:IsShown(), "native second-tab selection is not shown")
local _, _, _, groupX, groupY = ui.parts.tabGroup:GetPoint(1)
Check(groupX == dock:GetLeft() - second:GetLeft() and groupY == dock:GetBottom() - second:GetTop(), "native dock origin is replaced by fixed (0,3)")
Check(ui.parts.tabs[1].Text:GetText() == tab.Text:GetText() and ui.parts.tabs[2].Text:GetText() == secondTab.Text:GetText(), "native tab labels differ")
Check(ui.parts.tabs[2].previewTabID == 7 and ui.parts.tabs[2].previewTabGeneration == C.TabGeneration(7),
    "the second displayed tab did not keep its native ID and generation")
c.tabPadding = 1
C.ApplyTabGeometry(M, { tabLabel = tab.Text }, tab)
C.ApplyTabGeometry(M, { tabLabel = secondTab.Text }, secondTab)
P.ChatPreviewPaint.Refresh(ui)
Check(ui.parts.tabs[1]:GetWidth() == tab:GetWidth() and ui.parts.tabs[2]:GetWidth() == secondTab:GetWidth(), "native custom-padding widths are overwritten using sample titles")
dock.selected, env.SELECTED_DOCK_FRAME = frame, frame
c.tabPadding = 0
P.ChatPreviewPaint.Refresh(ui)

local applyFont = assert(Upvalue(C.ApplyWindow, "ApplyFont"), "real runtime ApplyFont not found")
c.fontRendering = 3
applyFont(M, frame, nil)
local _, _, nativeFlags = frame:GetFont()
P.ChatPreviewPaint.Refresh(ui)
local _, _, previewFlags = ui.parts.lines:GetFont()
Check(previewFlags == nativeFlags, "resolved native SLUG flags are resolved again: preview=" .. previewFlags .. " runtime=" .. nativeFlags)

-- Native scale is measured against UIParent; the dock and sidebar need not
-- inherit the selected message frame's scale. Coordinates below use the
-- native region's own units, as GetLeft/GetTop and SetPoint do in WoW.
local oldRootScale = env.UIParent.GetEffectiveScale
env.UIParent.GetEffectiveScale = function() return .8 end
frame.GetEffectiveScale = function() return 1.2 end
dock.GetEffectiveScale = function() return .8 end
dock:ClearAllPoints()
dock:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -2, 3)
dock:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 3)
function dock:GetLeft()
    local _, _, _, x = self:GetPoint(1)
    return frame:GetLeft() * frame:GetEffectiveScale() / self:GetEffectiveScale() + x
end
function dock:GetBottom()
    local _, _, _, _, y = self:GetPoint(1)
    return frame:GetTop() * frame:GetEffectiveScale() / self:GetEffectiveScale() + y
end
c.tabX, c.tabY = 29, -11
C.OffsetNative(M, dock, c.tabX, c.tabY)
P.ChatPreviewPaint.Refresh(ui)
Check(math.abs(ui.parts.nativeScale - 1.5) < .00001 and ui.parts.dockScale == 1,
    "native message/dock scale ratio differs")
Check(math.abs(ui.parts.sample:GetScale() - 1.5) < .00001 and ui.parts.tabGroup:GetScale() == 1,
    "sample and dock inherit the wrong native scale")
Check(ui.parts.sidebar:GetParent() == ui.stage and ui.parts.sidebar:GetScale() == 1,
    "sidebar inherits message-frame scale instead of UIParent scale")
local _, _, _, nativeDockX, nativeDockY = dock:GetPoint(1)
local _, _, _, previewDockX, previewDockY = ui.parts.tabGroup:GetPoint(1)
Check(previewDockX == nativeDockX and previewDockY == nativeDockY,
    "owned native dock offset is applied twice in sample")
Check(ui.parts.dockX == -2 and ui.parts.dockY == 3, "owned dock baseline lost native multi-anchor origin")
-- A native reanchor invalidates the old ownership record. Capture this new
-- baseline, without subtracting an offset no longer present in native art.
dock:ClearAllPoints()
dock:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 7, 9)
dock:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 9)
P.ChatPreviewPaint.Refresh(ui)
Check(ui.parts.dockX == 7 and ui.parts.dockY == 9, "stale dock ownership corrupts fresh native anchors")
C.OffsetNative(M, dock, c.tabX, c.tabY)
P.ChatPreviewPaint.Refresh(ui)
local _, _, _, appliedX, appliedY = dock:GetPoint(1)
local _, _, _, drawnX, drawnY = ui.parts.tabGroup:GetPoint(1)
Check(drawnX == appliedX and drawnY == appliedY, "reacquired native dock offset is doubled")

-- Match native text height and the shared configured rectangle at the
-- captured scale. A live explicit height must not replace the native baseline.
c.inputX, c.inputY, c.inputWidth, c.inputHeight = 13, -9, 312, 38
local inputVisual = { frame = frame }
C.ApplyInputLayout(M, inputVisual, frame, input)
P.ChatPreviewPaint.Refresh(ui)
local _, _, _, liveInputX, liveInputY = input:GetPoint(1)
local _, _, _, sampleInputX, sampleInputY = ui.parts.input:GetPoint(1)
Check(sampleInputX == liveInputX and sampleInputY == liveInputY, "aligned input offsets differ from live")
Check(input:GetWidth() == 312 and ui.parts.input:GetWidth() == 312, "explicit input width differs from live")
Check(ui.parts.input:GetHeight() == 38 and ui.parts.nativeInputHeight == 32, "custom input height replaced the native baseline")
c.inputWidth, c.inputHeight = 0, 0
C.ApplyInputLayout(M, inputVisual, frame, input)
P.ChatPreviewPaint.Refresh(ui)
Check(ui.parts.input:GetWidth() == input:GetWidth() and ui.parts.input:GetHeight() == input:GetHeight(),
    "input reset differs between live and preview")
-- Actual mouse callbacks must convert physical deltas using each element's
-- own native scale; a scaled chat body must not scale the sidebar/dock edit.
local mouseX, mouseY = 100, 100
env.GetCursorPosition = function() return mouseX, mouseY end
c.sidebarPanel, c.panelAlpha = true, 100
for _, case in ipairs({ { "messageText", 1.5 }, { "tab", 1 }, { "sidebarButton1", 1 } }) do
    local key, factor = case[1], case[2]
    if key == "sidebarButton1" then c.sidebarButton1Moved, c.sidebarButton1X, c.sidebarButton1Y = true, 0, 0 end
    local target = ui.targets[key]
    P.ChatPreviewPaint.Refresh(ui)
    P.ChatPreview.Select(ui, target)
    local original = c[key .. "X"]
    target:GetScript("OnMouseDown")(target, "LeftButton")
    mouseX = mouseX + 12 * ui.stage:GetEffectiveScale() * factor
    target:GetScript("OnMouseUp")(target, "LeftButton")
    Check(c[key .. "X"] == original + 12, "native-scaled drag delta differs for " .. key)
end
c.tabX, c.tabY, c.inputX, c.inputY = 0, 0, 0, 0
C.OffsetNative(M, dock, 0, 0)
C.OffsetNative(M, input, 0, 0)
env.UIParent.GetEffectiveScale = oldRootScale
frame.GetEffectiveScale = function() return 1 end
dock.GetEffectiveScale = function() return 1 end
P.ChatPreviewPaint.Refresh(ui)

-- Exercise the actual observer callback installed on the native frame.
c.sidebarPanel = true
P.ChatPreviewPaint.Refresh(ui)
local handle = ui.targets.sidebarButton1
handle:GetScript("OnMouseDown")(handle, "LeftButton")
Check(ui.kit.drag ~= nil, "native-change drag fixture did not start")
frame:SetSize(720, 300)
frame:GetScript("OnSizeChanged")(frame, 720, 300)
Check(ui.kit.drag == nil, "native geometry change does not cancel held preview drag")
Check(ui.parts.sample:GetWidth() == 720 and ui.parts.sample:GetHeight() == 300, "native resize observer does not repaint geometry")
local listeners = assert(Upvalue(S.ChatWatchPreview, "listeners"), "preview observer registry missing")
ui.ctx.wrapper:Hide()
local hidden = ui.ctx.wrapper:GetScript("OnHide")
if hidden then hidden(ui.ctx.wrapper) end
Check(listeners[ui.viewport] == nil, "hidden preview remains subscribed")
local oldEpoch = ui.parts.nativeEpoch
frame:SetSize(730, 310)
frame:GetScript("OnSizeChanged")(frame, 730, 310)
Check(ui.parts.nativeEpoch == oldEpoch, "hidden native observer still paints")
ui.ctx.wrapper:Show()
local shown = ui.ctx.wrapper:GetScript("OnShow")
if shown then shown(ui.ctx.wrapper) end
F.mw:RunTimers()
Check(listeners[ui.viewport] ~= nil, "reopened preview does not resubscribe")
Check(ui.parts.sample:GetWidth() == 730 and ui.parts.sample:GetHeight() == 310, "reopened preview retains stale native dimensions")
-- Extra native tabs use the same painter and interactive group. Preserve
-- each native tab's position/scale and the title's -5 vertical center inset.
local third = env.CreateFrame("Frame", "ParitySnapshotThird", env.UIParent)
third:SetSize(730, 310)
third:SetFont("ThirdMessage.ttf", 16, "")
third.GetInsertMode, third.GetSpacing = frame.GetInsertMode, frame.GetSpacing
third.GetLeft, third.GetTop = frame.GetLeft, frame.GetTop
local thirdTab = env.CreateFrame("Frame", "ParitySnapshotThirdTab", dock)
thirdTab:SetSize(127, 32)
thirdTab.Text = thirdTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
thirdTab.Text:SetText("Third native title")
thirdTab.Text:SetFont("ThirdTab.ttf", 14, "")
thirdTab.GetEffectiveScale = function() return .75 end
thirdTab.GetLeft = function() return (dock:GetLeft() + 220) / .75 end
thirdTab.GetBottom = function() return (dock:GetBottom() + 2) / .75 end
thirdTab.GetCenter = function() return 410, 540 end
thirdTab.Text.GetCenter = function() return 410, 535 end
env.ParitySnapshotThirdTab = thirdTab
dock.selected, dock.DOCKED_CHAT_FRAMES = third, { frame, second, third }
third.CombatLogQuickButtonFrame = env.CreateFrame("Frame", nil, third)
third.CombatLogQuickButtonFrame:SetHeight(22)
ui.runtimeRefresh()
local sampleThird = ui.parts.tabs[3]
Check(sampleThird and sampleThird:IsShown(), "third native tab is absent")
Check(sampleThird.Text:GetText() == "Third native title" and sampleThird:GetWidth() == 127,
    "third native tab label or width differs")
Check(sampleThird:GetScale() == .75, "third native tab scale differs")
local _, _, _, thirdX, thirdY = sampleThird:GetPoint(1)
Check(math.abs(thirdX * .75 - 220) < .00001 and math.abs(thirdY * .75 - 2) < .00001,
    "third native tab dock-relative position differs")
local _, _, _, textX, textY = sampleThird.Text:GetPoint(1)
Check(textX == 0 and textY == -5, "native tab title center offset differs")
Check(sampleThird.visual.tabLine:IsShown() and not ui.parts.tabs[1].visual.tabLine:IsShown(),
    "third native selected tab is not selected in sample")
Check(C.HeaderTop(c, ui.parts.sample) == C.HeaderTop(c, third), "combat-log quick bar height differs")
local thirdHandle
for _, handle in ipairs(ui.handles) do if handle.region == sampleThird then thirdHandle = handle end end
Check(thirdHandle and thirdHandle.canMove, "third native tab lacks the shared interactive handle")
P.ChatPreview.Select(ui, thirdHandle)
dock.selected, dock.DOCKED_CHAT_FRAMES = frame, { frame, second }
ui.runtimeRefresh()
Check(not sampleThird:IsShown() and not thirdHandle:IsVisible(), "removed native tab remains selectable")
Check(ui.viewport._selectedHandle ~= thirdHandle, "removed native tab retains active selection")
Check(C.HeaderTop(c, ui.parts.sample) == C.HeaderTop(c, frame), "old combat-log row survives source switch")
c.tabPanel, c.hideTabArt, c.minimalChrome = false, false, false
tab.Text:SetTextColor(.3, .4, .5, .6)
C.ColorTab(M, { tabLabel = tab.Text, tabLine = tab:CreateTexture(nil, "ARTWORK") }, false)
ui.runtimeRefresh()
local nr, ng, nb, na = tab.Text:GetTextColor()
local pr, pg, pb, pa = ui.parts.tabs[1].Text:GetTextColor()
Check(pr == nr and pg == ng and pb == nb and pa == na,
    "native unstyled tab color is replaced by hardcoded sample gold")
-- A native color-only change must invalidate the snapshot and repaint without
-- requiring a geometry, font or profile change.
P.ChatPreviewPaint.Refresh(ui)
tab.Text:SetTextColor(.12, .34, .56, .78)
P.ChatPreviewPaint.Refresh(ui)
pr, pg, pb, pa = ui.parts.tabs[1].Text:GetTextColor()
Check(pr == .12 and pg == .34 and pb == .56 and pa == .78,
    "native color-only change did not repaint the sample tab")
c.tabPanel = true
ui.runtimeRefresh()

-- Bounds are measured in stage units even when the panel texture inherits
-- message scaling and an offset icon inherits UIParent scaling.
local function Rectangle(kind, parent, scale, x, y, width, height)
    local region = env.CreateFrame("Frame", nil, parent)
    region:SetSize(width, height)
    function region:GetEffectiveScale()
        assert(kind ~= "Texture", "native Texture has no GetEffectiveScale")
        return scale
    end
    function region:GetRect() return x, y, width, height end
    function region:GetLeft() return x end
    function region:GetTop() return y + height end
    function region:IsObjectType(value) return value == kind end
    return region
end
local boundStage = Rectangle("Frame", env.UIParent, .5, 0, 0, 100, 100)
local boundSample = Rectangle("Frame", boundStage, .75, 100, 200, 200, 100)
local boundPanel = Rectangle("Texture", boundSample, .75, 98, 198, 204, 104)
local boundIcon = Rectangle("Frame", boundStage, .5, -200, 200, 24, 24)
local boundInput = Rectangle("Frame", boundSample, .75, 100, 50, 230, 32)
local empty = Rectangle("Frame", boundStage, .5, 0, 0, 0, 0)
empty:Hide()
local boundParts = { sample = boundSample, nativeScale = 1.5, visual = { panel = boundPanel, edges = {} },
    sidebar = boundIcon, icons = { boundIcon }, input = boundInput, inputEdges = {}, tabs = {} }
local left, right, top, bottom = S.ChatPreviewBounds(boundParts, boundStage)
Check(left == -350 and right == 345 and top == 3 and bottom == -375,
    "off-panel art bounds ignore native scale or shifted regions")
local boundUI = { parts = boundParts, stage = boundStage, width = 720, viewport = empty }
assert(S.ChatFitPreview, "real Fit missing")(boundUI)
local _, _, _, fitX, fitY = boundSample:GetPoint(1)
Check(math.abs(fitX - 362 / 1.5) < .00001 and fitY == -10,
    "fitting does not shift the entire sample inside its canvas")
Check(boundStage:GetWidth() == 719 and boundStage:GetHeight() == 402 and boundUI.canvasHeight == 216,
    "fitting does not contain shifted sidebar/input art")
-- Gradient painters intentionally hide the solid panel. Its independently
-- visible replacement textures must still contribute the padded bounds.
boundPanel:Hide()
boundParts.sidebar, boundParts.icons, boundParts.input = empty, {}, nil
boundParts.visual.gradientLeft = Rectangle("Texture", boundSample, .75, 50, 198, 150, 104)
boundParts.visual.gradientRight = Rectangle("Texture", boundSample, .75, 200, 198, 150, 104)
left, right, top, bottom = S.ChatPreviewBounds(boundParts, boundStage)
Check(left == -75 and right == 375 and top == 3 and bottom == -153,
    "hidden solid panel causes visible gradient bounds to be omitted")

-- Compare actual runtime and preview complete-message clipping for identical
-- line rectangles; fonts/word wrapping are tested separately above.
local nativeMessages = env.CreateFrame("Frame", "ParityClippedMessages", env.UIParent)
function nativeMessages:GetTop() return 100 end
function nativeMessages:GetBottom() return 0 end
function ui.parts.sample:GetTop() return 100 end
function ui.parts.sample:GetBottom() return 0 end
local function LineBottom(line)
    local point, relative, relativePoint, _, offset = line:GetPoint(1)
    local y = relativePoint == "TOPLEFT" and relative:GetTop() or relative:GetBottom()
    return y + (offset or 0) - (point == "TOPLEFT" and 40 or 0)
end
nativeMessages.visibleLines = {}
for i = 1, 2 do
    local line = nativeMessages:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.GetBottom = LineBottom
    function line:GetTop() return LineBottom(self) + 40 end
    nativeMessages.visibleLines[i] = line
end
for _, line in ipairs(ui.parts.messageLines) do
    line.GetBottom = LineBottom
    function line:GetTop() return LineBottom(self) + 40 end
end
for _, case in ipairs({ { false, -5, true }, { false, 0, true }, { false, -5, false }, { true, 5, true } }) do
    local top, offset, complete = unpack(case)
    c.messageTextX, c.messageTextY, c.completeMessages = 0, offset, complete
    ui.parts.insertTop, ui.parts.messageSpacing, ui.parts.text = top, 2, "older\nnewer"
    local point, opposite = top and "TOPLEFT" or "BOTTOMLEFT", top and "BOTTOMLEFT" or "TOPLEFT"
    for i, line in ipairs(nativeMessages.visibleLines) do
        line:ClearAllPoints()
        if i == 1 then line:SetPoint(point, nativeMessages, point, 0, 0)
        else line:SetPoint(point, nativeMessages.visibleLines[i-1], opposite, 0, top and -2 or 2) end
        line:SetTextColor(1, 1, 1, 1)
    end
    C.PaintMessageLines(M, nativeMessages)
    S.ChatPaintMenuPreview(ui.parts, c)
    for i, line in ipairs(nativeMessages.visibleLines) do
        local _, _, _, nativeAlpha = line:GetTextColor()
        local _, _, _, previewAlpha = ui.parts.messageLines[i]:GetTextColor()
        Check(nativeAlpha == previewAlpha, "native/sample complete-message alpha differs for line " .. i)
    end
    Check(ui.parts.lines:GetPoint(1) == point, "sample insertion corner differs from native")
end
print("Independent snapshot parity: " .. checks .. " checks, " .. failures .. " failures")
if failures > 0 then error("runtime/preview snapshot parity regression") end
