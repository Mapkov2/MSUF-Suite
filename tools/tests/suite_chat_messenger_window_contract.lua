-- Load the actual messenger, including its widgets. Only the native widgets
-- and the chat API are modeled here.
local root = arg and arg[1] or "."
local folder = root .. "/MSUF_Suite_Chat/"
local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end

local Frame = {}
Frame.__index = Frame
local function Noop() end
for _, method in ipairs({
    "SetAllPoints", "SetColorTexture", "SetJustifyH", "SetJustifyV", "SetWordWrap",
    "SetFrameStrata", "SetMovable", "SetClampedToScreen", "RegisterForDrag",
    "SetAutoFocus", "SetMaxBytes", "SetSpacing", "SetScrollChild", "SetTextColor",
    "UpdateScrollChildRect", "SetVerticalScroll", "SetFocus", "ClearFocus", "RegisterForClicks",
}) do Frame[method] = Noop end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:SetWidth(width) self.width = width end
function Frame:SetHeight(height) self.height = height end
function Frame:GetWidth() return self.width or 100 end
function Frame:GetStringWidth() return 60 end
function Frame:GetStringHeight() return 12 end
function Frame:GetVerticalScrollRange() return 0 end
function Frame:GetVerticalScroll() return 0 end
function Frame:GetParent() return self.parent end
function Frame:SetText(text) self.text = text end
function Frame:GetText() return self.text or "" end
function Frame:SetScript(event, callback) self.scripts[event] = callback end
function Frame:ClearAllPoints() self.placementWrites = self.placementWrites + 1 end
function Frame:SetPoint(_, _, _, x, y) self.left, self.bottom = x, y end
function Frame:GetLeft() return self.left end
function Frame:GetBottom() return self.bottom end
function Frame:StartMoving() self.moving = true end
function Frame:StopMovingOrSizing() self.moving = false end
function Frame:IsShown() return self.shown end
function Frame:Show()
    local shown = self.shown
    self.shown = true
    if not shown and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Frame:Hide()
    local shown = self.shown
    self.shown = false
    if shown and self.scripts.OnHide then self.scripts.OnHide(self) end
end

local launcher, panel, input
local function Widget(parent)
    return setmetatable({ parent = parent, shown = true, scripts = {}, placementWrites = 0 }, Frame)
end
UIParent = Widget()
local function CreateFrame(kind, _, parent)
    local frame = Widget(parent)
    if kind == "EditBox" then
        input = frame
        frame.Instructions = Widget(frame)
    elseif kind == "Button" and parent == UIParent then
        launcher = frame
    end
    return frame
end
local function CreateWindow()
    panel = Widget(UIParent)
    panel.close, panel.dragHandle = Widget(panel), Widget(panel)
    panel.dragHandle:SetScript("OnDragStart", function() panel:StartMoving() end)
    return panel
end

GetNormalizedRealmName = function() return "Home" end
IsShiftKeyDown = function() return true end
date = os.date
local sent = {}
C_ChatInfo = {
    IsChatLineCensored = function() return false end,
    SendChatMessage = function(text, _, _, recipient) sent[#sent + 1] = { text, recipient } end,
}
local bnetSent = {}
C_BattleNet = { SendWhisper = function(id, text)
    bnetSent[#bnetSent + 1] = { id, text }
    return false
end }
local locked = false
local NS = { InCombat = function(event) return event == "PLAYER_REGEN_DISABLED" end,
    ChatLocked = function() return locked end, HostBridge = { MenuEditBox = Noop } }
local M
local first = { window = { x = 15, y = 125 }, launcher = { x = 35, y = 225 } }
local second = { window = { x = 350, y = 375 }, launcher = { x = 250, y = 275 } }
local activeState = first
local S = {
    ModuleState = function() return activeState end, SetFont = Noop, QoLWindow = CreateWindow,
    QoLLabel = Widget, CreateFontString = Widget, CreateTexture = Widget, CreateFrame = CreateFrame,
    Text = function(value) return value end, Public = function() return true end,
    PublicText = function(value) return type(value) == "string" and value ~= "" and value or nil end,
    Finite = function(value) return type(value) == "number" end,
    Config = Noop, Print = Noop, HideQuestion = Noop,
    Install = function(_, module) M = module end,
}
local P = { NS = NS, Suite = S, Chat = { Fill = Widget, Tint = Noop, HideTooltip = Noop } }
for _, name in ipairs({ "MessengerData", "MessengerWindow", "Messenger" }) do
    assert(loadfile(folder .. name .. ".lua"))("MSUF_Suite_Chat", P)
end
local events = {}
M.context = {
    Event = function(_, event, handler) events[event] = handler end,
    RemoveEvent = function(_, event) events[event] = nil end,
}
M.active = true
M.config = { launcher = true, character = true, battleNet = true, openOnWhisper = true, hideInCombat = true,
    showArchive = false, width = 480, height = 360, fontSize = 12, maxTabs = 3 }
M:Enable()
local D, W = P.Messenger, P.Messenger.Window
local function Incoming(name, line)
    local event = "CHAT_MSG_WHISPER"
    events[event](M, event, "Hello", name, nil, nil, nil, nil, nil, nil, nil, nil, line)
end
local function Select(index)
    local button = panel.tabs[index]
    button.scripts.OnClick(button)
end

Incoming("Alice", 1)
input:SetText("For Alice only")
W.Hide()
Incoming("Bob", 2)
Check(D.selected.name == "Bob-Home", "incoming whisper did not select Bob")
Check(input:GetText() == "", "Alice's text appeared in Bob's conversation")
input.scripts.OnEnterPressed(input)
Check(#sent == 0, "pressing Enter sent Alice's draft to Bob")
input:SetText("For Bob only")
Select(1)
Check(input:GetText() == "For Alice only", "switching back did not restore Alice's draft")
locked = true
input.scripts.OnEnterPressed(input)
Check(input:GetText() == "For Alice only", "chat lockdown discarded Alice's draft")
locked = false
input.scripts.OnEnterPressed(input)
Check(sent[#sent] and sent[#sent][1] == "For Alice only" and sent[#sent][2] == "Alice-Home",
    "Alice's restored draft was not sent to Alice")
Select(2)
Check(input:GetText() == "For Bob only", "sending to Alice discarded Bob's draft")
W.CombatStarted(true)
W.CombatEnded()
Check(input:GetText() == "For Bob only", "combat hide and show discarded Bob's draft")
local alreadySent = #sent
D.Select(D.tabs[1])
input.scripts.OnEnterPressed(input)
Check(#sent == alreadySent, "a selection change before repaint sent the previous tab's draft")
Select(2)
local close = panel.tabs[2].close
close.scripts.OnClick(close)
Incoming("Bob", 3)
Select(2)
Check(input:GetText() == "", "a reopened conversation recovered an explicitly closed draft")
local event = "CHAT_MSG_BN_WHISPER"
events[event](M, event, "Hi", "Friend", nil, nil, nil, nil, nil, nil, nil, nil, 4, nil, 42)
Select(3)
input:SetText("Battle.net refused reply")
input.scripts.OnEnterPressed(input)
Check(bnetSent[1] and bnetSent[1][1] == 42 and input:GetText() == "Battle.net refused reply",
    "a refused Battle.net send changed its recipient or discarded the draft")
Select(2)
Incoming("Carla", 5)
Incoming("David", 6)
Check(not D.byKey["b:42"], "the evicted Battle.net tab remained open")
W.Hide()
events[event](M, event, "Hi again", "Friend", nil, nil, nil, nil, nil, nil, nil, nil, 7, nil, 42)
Check(D.selected.key == "b:42" and input:GetText() == "",
    "a new tab for a recycled Battle.net ID recovered an evicted draft")

Check(panel.left == 15 and launcher.left == 35, "initial profile placement")
local count = panel.placementWrites + launcher.placementWrites
M:Refresh()
Check(panel.placementWrites + launcher.placementWrites == count, "unchanged settings rewrote frame placement")
panel.dragHandle.scripts.OnDragStart(panel.dragHandle)
launcher.scripts.OnDragStart(launcher)
Check(panel.moving and launcher.moving, "window or launcher lost its drag start")
activeState = second
M:Refresh()
Check(panel.left == 350 and panel.bottom == 375, "window position did not follow the active profile")
Check(launcher.left == 250 and launcher.bottom == 275, "launcher position did not follow the active profile")
Check(not panel.moving and not launcher.moving, "changing profile did not stop the prior profile's drag")
panel.left, launcher.left = 51, 61
panel.dragHandle.scripts.OnDragStop(panel.dragHandle)
launcher.scripts.OnDragStop(launcher)
Check(second.window.x == 350 and second.launcher.x == 250, "an earlier profile's drag overwrote saved placement")
activeState = first
M:Refresh()
Check(panel.left == 15 and launcher.left == 35, "switching back did not restore the first profile's placement")
M:Disable()
assert(#failures == 0, table.concat(failures, "\n"))
print("PASS messenger draft recipient, active profile placement, and drag ownership")
