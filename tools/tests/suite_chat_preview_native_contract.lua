-- Compare the real runtime sidebar and inherited native facts with the menu
-- painter. Synthetic chat lines keep private messages outside this fixture.
local root = assert(arg[1])
local mutation = arg[4]
arg[4] = "native"
local F = assert(loadfile(root .. "/tools/tests/suite_chat_preview_contract.lua"))()
arg[4] = mutation
local C, env, S = F.runtime.Chat, F.env, F.Suite.Suite
local parts, c = F.ui.parts, S.Config("chat")
local checks = 0
local function Check(ok, text) checks = checks + 1 assert(ok, text) end
local function XY(region)
    local _, _, _, x, y = region:GetPoint(1)
    return x or 0, y or 0
end
if mutation == "snapshot" then S.ChatPreviewSnapshot = function() return false end end
if mutation == "clipping" then C.PaintMessageLines = C.PositionMessages end

c.sidebarPanel, c.panelAlpha, c.sidebarClassColor = true, 100, false
local frame = env.CreateFrame("ScrollingMessageFrame", "ParityNativeChat", env.UIParent)
frame:SetSize(420, 180)
frame.buttonFrame = env.CreateFrame("Frame", "ParityNativeButtonFrame", frame)
env.SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP = "TOP"
function frame:GetInsertMode() return "BOTTOM" end
function frame:GetSpacing() return 0 end
env.ChatFrame1, env.SELECTED_DOCK_FRAME = frame, frame
env.GENERAL_CHAT_DOCK = { selected = frame }
for _, name in ipairs({ "QuickJoinToastButton", "ChatFrameChannelButton", "TextToSpeechButton", "ChatFrameMenuButton" }) do
    env[name] = env.CreateFrame("Button", name, frame.buttonFrame)
end
env.BNGetNumFriends = function() return 0, 3 end
env.C_FriendList = { GetNumOnlineFriends = function() return 2 end }
local M, visual = C.M, { frame = frame }
M.context, M.config, M.active = S.NewContext("chat"), c, true
M.visuals[frame] = visual
C.ApplySidebar(M, visual, frame)
S.ChatPaintMenuPreview(parts, c)
for i, native in ipairs(visual.buttons) do
    local preview = parts.icons[i]
    Check(preview:GetWidth() == native.button:GetWidth() and preview:GetHeight() == native.button:GetHeight(), "sidebar hit dimensions differ")
    Check(preview.glyph:GetWidth() == native.glyph:GetWidth() and preview.glyph:GetHeight() == native.glyph:GetHeight(), "sidebar glyph dimensions differ")
    local px, py = XY(preview.glyph)
    local nx, ny = XY(native.glyph)
    Check(px == nx and py == ny, "sidebar glyph centers differ")
    local p1, p2, p3, p4 = preview.glyph:GetTexCoord()
    local n1, n2, n3, n4 = native.glyph:GetTexCoord()
    Check(p1 == n1 and p2 == n2 and p3 == n3 and p4 == n4, "sidebar atlas coordinates differ")
end
Check(parts.friendCount and parts.friendCount:GetText() == visual.buttons[1].count:GetText(), "sidebar count badge differs")
env.QuickJoinToastButton, env.TextToSpeechButton = nil, nil
local mt = getmetatable(env)
local oldIndex = mt and mt.__index
if mt then
    mt.__index = function(t, key)
        if key == "QuickJoinToastButton" or key == "TextToSpeechButton" then return nil end
        if type(oldIndex) == "function" then return oldIndex(t, key) end
        return oldIndex and oldIndex[key]
    end
end
C.ApplySidebar(M, visual, frame)
S.ChatPaintMenuPreview(parts, c)
for i, native in ipairs(visual.buttons) do
    Check(parts.icons[i]:IsShown() == native.button:IsShown(), "native sidebar source availability differs")
end
if mt then mt.__index = oldIndex end

-- Model native anchor-derived centers; the general menu fixture uses fixed
-- centers and cannot detect an automatic icon jumping on its first drag.
frame:SetSize(610, 360)
c.lockWindowSize, c.sidebarButton1Moved = false, false
F.P.ChatPreviewPaint.Refresh(F.ui)
C.PlaceSidebar(M, visual.sidebarFrame, frame)
C.PlaceSidebarButton(visual.buttons[1].button, c, 1, visual.sidebarFrame, frame, false)
local function SidebarCenter(sidebar, owner)
    local _, _, _, _, top = sidebar:GetPoint(1)
    local _, _, _, _, bottom = sidebar:GetPoint(2)
    return 0, ((top or 0) + (bottom or 0) - owner:GetHeight()) / 2
end
function parts.sidebar:GetCenter() return SidebarCenter(self, parts.sample) end
parts.icons[1].GetCenter = function(self)
    local _, _, _, x, top = parts.sidebar:GetPoint(1)
    local _, _, _, bx, by = self:GetPoint(1)
    return (x or 0) + (bx or 0), (top or 0) + (by or 0) - self:GetHeight() / 2
end
local _, nativeCenter = SidebarCenter(visual.sidebarFrame, frame)
local _, _, _, _, nativeTop = visual.sidebarFrame:GetPoint(1)
local _, _, _, _, buttonTop = visual.buttons[1].button:GetPoint(1)
local nativeOrigin = nativeTop + buttonTop - visual.buttons[1].button:GetHeight() / 2 - nativeCenter
local _, previewOrigin = F.R.Read(F.ui, F.ui.targets.sidebarButton1.spec)
Check(parts.sample:GetWidth() == frame:GetWidth() and parts.sample:GetHeight() == frame:GetHeight(), "unlocked native dimensions differ")
Check(previewOrigin == nativeOrigin, "first automatic sidebar drag would jump")

c.font, c.tabFont = "__BLIZZARD_CHAT_FONT__", "__BLIZZARD_CHAT_FONT__"
c.fontSize, c.tabFontSize, c.fontOutline, c.fontRendering, c.fontShadow = 0, 0, 1, 1, 1
c.inputTop, c.inputHeight, c.inputX, c.inputY = false, 0, 0, 0
c.messageTextX, c.messageTextY, c.tabPadding, c.tabHeight = 0, 0, 0, 24
frame:SetFont("Fonts/FRIZQT__.TTF", 18, "OUTLINE")
frame:SetShadowColor(.1, .2, .3, .6)
frame:SetShadowOffset(2, -3)
function frame:GetSpacing() return 7 end
frame.editBox = env.CreateFrame("Frame", nil, frame)
frame.editBox:SetSize(638, 32)
frame.editBox:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -5, -2)
frame.editBox.header = frame.editBox:CreateFontString(nil, "OVERLAY")
frame.editBox.header:SetFont("Fonts/FRIZQT__.TTF", 19, "OUTLINE")
local tab = env.CreateFrame("Frame", "ParityNativeChatTab", frame)
env.ParityNativeChatTab = tab
tab:SetSize(71, 32)
tab.Text = tab:CreateFontString(nil, "OVERLAY")
tab.Text:SetFont("Fonts/FRIZQT__.TTF", 17, "OUTLINE")
F.P.ChatPreviewPaint.Refresh(F.ui)
local path, size, flags = parts.lines:GetFont()
Check(path == "Fonts/FRIZQT__.TTF" and size == 18 and flags == "OUTLINE", "native message font differs")
local r, g, b, a = parts.lines:GetShadowColor()
local x, y = parts.lines:GetShadowOffset()
Check(r == .1 and g == .2 and b == .3 and a == .6 and x == 2 and y == -3, "native message shadow differs")
Check(parts.tabs[1]:GetWidth() == tab:GetWidth() and parts.tabs[1]:GetHeight() == tab:GetHeight(), "native default tab dimensions differ")
path, size, flags = parts.label:GetFont()
Check(size == 17 and flags == "OUTLINE", "native tab font differs")
Check(parts.input:GetWidth() == frame.editBox:GetWidth() and parts.input:GetHeight() == frame.editBox:GetHeight(), "native input dimensions differ")
local point, _, relativePoint, ix, iy = parts.input:GetPoint(1)
Check(point == "TOPLEFT" and relativePoint == "BOTTOMLEFT" and ix == -5 and iy == -2, "native input anchor differs")
path, size, flags = parts.prompt:GetFont()
Check(size == 19 and flags == "OUTLINE", "native input font differs")
-- An unoutlined native font returns the valid empty flags string.
frame:SetFont("Fonts/ARIALN.TTF", 20, "")
frame.editBox.header:SetFont("Fonts/ARIALN.TTF", 21, "")
tab.Text:SetFont("Fonts/ARIALN.TTF", 16, "")
F.P.ChatPreviewPaint.Refresh(F.ui)
path, size, flags = parts.lines:GetFont()
Check(path == "Fonts/ARIALN.TTF" and size == 20 and flags == "", "empty message font flags discarded the native tuple")
path, size, flags = parts.prompt:GetFont()
Check(path == "Fonts/ARIALN.TTF" and size == 21 and flags == "", "empty input font flags discarded the native tuple")
path, size, flags = parts.label:GetFont()
Check(path == "Fonts/ARIALN.TTF" and size == 16 and flags == "", "empty tab font flags discarded the native tuple")
point, _, relativePoint, x, y = parts.messageLines[2]:GetPoint(1)
Check(point == "BOTTOMLEFT" and relativePoint == "TOPLEFT" and y == 7, "bottom insertion spacing differs")
function frame:GetInsertMode() return "TOP" end
F.P.ChatPreviewPaint.Refresh(F.ui)
point, _, relativePoint, x, y = parts.lines:GetPoint(1)
Check(point == "TOPLEFT" and relativePoint == "TOPLEFT" and x == 0 and y == 0, "top insertion origin differs")
point, _, relativePoint, x, y = parts.messageLines[2]:GetPoint(1)
Check(point == "TOPLEFT" and relativePoint == "BOTTOMLEFT" and y == -7, "top insertion spacing differs")

parts.sample.GetTop = function() return 100 end
parts.sample.GetBottom = function() return 0 end
parts.messageLines[1].GetTop = function() return 105 end
parts.messageLines[1].GetBottom = function() return 85 end
parts.messageLines[2].GetTop = function() return 80 end
parts.messageLines[2].GetBottom = function() return 60 end
parts.messageLines[3].GetTop = function() return 55 end
parts.messageLines[3].GetBottom = function() return 35 end
c.completeMessages = true
S.ChatPaintMenuPreview(parts, c)
local _, _, _, clippedAlpha = parts.lines:GetTextColor()
local _, _, _, visibleAlpha = parts.messageLines[2]:GetTextColor()
Check(clippedAlpha == 0 and visibleAlpha == 1, "whole-message clipping was not painted")
c.completeMessages = false
S.ChatPaintMenuPreview(parts, c)
local _, _, _, restoredAlpha = parts.lines:GetTextColor()
Check(restoredAlpha == 1, "whole-message clipping did not restore")
print("Chat native preview " .. (arg[2] or "Mainline") .. ": " .. checks .. " checks passed")
