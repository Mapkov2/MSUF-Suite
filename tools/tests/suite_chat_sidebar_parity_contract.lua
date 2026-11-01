-- Independent native/runtime versus owned preview contract.
local root = assert(arg[1])
local file = assert(io.open(root .. "/tools/tests/suite_chat_preview_contract.lua", "rb"))
local source = file:read("*a") file:close()
local F = assert(loadstring(source .. "\nreturn {ui=ui,P=P,env=env,mw=mw,runtime=runtime,Suite=Suite,R=R}", "@sidebar-parity-world"))()
local C, env, S = F.runtime.Chat, F.env, F.Suite.Suite
local c = S.Config("chat")
c.sidebarPanel, c.panelAlpha, c.sidebarClassColor = true, 100, false
local frame = env.CreateFrame("Frame", "ParityNativeChat", env.UIParent)
frame:SetSize(420, 180)
function frame:GetInsertMode() return "BOTTOM" end
function frame:GetSpacing() return 0 end
frame.buttonFrame = env.CreateFrame("Frame", "ParityNativeButtonFrame", frame)
env.ChatFrame1 = frame
env.GENERAL_CHAT_DOCK = env.CreateFrame("Frame", "ParitySidebarDock", env.UIParent)
env.GENERAL_CHAT_DOCK.selected = frame
env.GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES = { frame }
env.SELECTED_DOCK_FRAME = frame
local names = { "QuickJoinToastButton", "ChatFrameChannelButton", "TextToSpeechButton", "ChatFrameMenuButton" }
for _, name in ipairs(names) do env[name] = env.CreateFrame("Button", name, frame.buttonFrame) end
env.BNGetNumFriends = function() return 0, 0 end
env.C_FriendList = { GetNumOnlineFriends = function() return 0 end }
local M, visual = C.M, { frame = frame }
M.context, M.config, M.active = S.NewContext("chat"), c, true
M.visuals[frame] = visual
C.ApplySidebar(M, visual, frame)
S.ChatPaintMenuPreview(F.ui.parts, c)
local checks, failures = 0, 0
local function Check(ok, text)
    checks = checks + 1
    if not ok then failures = failures + 1 print("FAIL " .. text) end
end
local function XY(region)
    local _, _, _, x, y = region:GetPoint(1)
    return x or 0, y or 0
end
for i, native in ipairs(visual.buttons) do
    local preview = F.ui.parts.icons[i]
    Check(preview:GetWidth() == native.button:GetWidth() and preview:GetHeight() == native.button:GetHeight(), "icon " .. i .. " button dimensions differ")
    Check(preview.glyph:GetWidth() == native.glyph:GetWidth() and preview.glyph:GetHeight() == native.glyph:GetHeight(),
        "icon " .. i .. " glyph dimensions preview=" .. preview.glyph:GetWidth() .. " runtime=" .. native.glyph:GetWidth())
    local px, py = XY(preview.glyph)
    local nx, ny = XY(native.glyph)
    Check(px == nx and py == ny, "icon " .. i .. " glyph center preview=" .. px .. "," .. py .. " runtime=" .. nx .. "," .. ny)
    local p1,p2,p3,p4 = preview.glyph:GetTexCoord()
    local n1,n2,n3,n4 = native.glyph:GetTexCoord()
    Check(p1 == n1 and p2 == n2 and p3 == n3 and p4 == n4, "icon " .. i .. " atlas order differs")
end
Check(F.ui.parts.friendCount ~= nil, "preview omits runtime friends count badge")
env.QuickJoinToastButton, env.TextToSpeechButton = nil, nil
local metatable = getmetatable(env)
local originalIndex = metatable and metatable.__index
if metatable then
    metatable.__index = function(t, key)
        if key == "QuickJoinToastButton" or key == "TextToSpeechButton" then return nil end
        if type(originalIndex) == "function" then return originalIndex(t, key) end
        return originalIndex and originalIndex[key]
    end
end
C.ApplySidebar(M, visual, frame)
S.ChatPaintMenuPreview(F.ui.parts, c)
for i, native in ipairs(visual.buttons) do
    Check(F.ui.parts.icons[i]:IsShown() == native.button:IsShown(), "icon " .. i .. " native availability visibility differs")
end
if metatable then metatable.__index = originalIndex end
-- Model native anchor-derived centers (the menu fixture normally supplies
-- arbitrary centers). A first drag must preserve the live automatic origin.
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
function F.ui.parts.sidebar:GetCenter() return SidebarCenter(self, F.ui.parts.sample) end
F.ui.parts.icons[1].GetCenter = function(self)
    local _, _, _, x, top = F.ui.parts.sidebar:GetPoint(1)
    local _, _, _, bx, by = self:GetPoint(1)
    return (x or 0) + (bx or 0), (top or 0) + (by or 0) - self:GetHeight() / 2
end
local _, nativeCenter = SidebarCenter(visual.sidebarFrame, frame)
local _, _, _, _, nativeTop = visual.sidebarFrame:GetPoint(1)
local _, _, _, _, buttonTop = visual.buttons[1].button:GetPoint(1)
local nativeOriginY = nativeTop + buttonTop - visual.buttons[1].button:GetHeight()/2 - nativeCenter
local _, previewOriginY = F.R.Read(F.ui, F.ui.targets.sidebarButton1.spec)
Check(F.ui.parts.sample:GetWidth() == frame:GetWidth() and F.ui.parts.sample:GetHeight() == frame:GetHeight(),
    "unlocked sample dimensions differ from native frame (sample=" .. F.ui.parts.sample:GetWidth() .. "x" .. F.ui.parts.sample:GetHeight() .. ")")
Check(previewOriginY == nativeOriginY, "first icon drag origin preview=" .. previewOriginY .. " runtime=" .. nativeOriginY .. " (native icon would jump)")
print("Independent sidebar parity: " .. checks .. " checks, " .. failures .. " failures")
if failures > 0 then error("runtime/preview sidebar parity regression") end
