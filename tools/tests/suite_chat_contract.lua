local root = assert(arg[1])
local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return false end,
}
local S = {}
S.Public = function(value) return value ~= "secret" end
-- Readable-number helpers as defined by MSUF_Suite_Modules/Runtime.lua.
S.Number = function(value) return S.Public(value) and type(value) == "number" and value == value end
S.Finite = function(value) return S.Number(value) and value > -math.huge and value < math.huge end
-- securecallfunction: a raising callback is reported and its caller goes on.
local reports = {}
S.Dispatch = function(callback, ...)
    local results = { coroutine.resume(coroutine.create(callback), ...) }
    if not results[1] then
        reports[#reports + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2, table.maxn(results))
end
S.Text = function(value) return value end
S.RGB = function(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
S.CreateFrame = function(...) return CreateFrame(...) end
S.CreateTexture = function(parent, ...) return parent:CreateTexture(...) end
S.CreateFontString = function(parent, ...) return parent:CreateFontString(...) end
S.ResolveFont = function(key) return key == "TestFont" and "Test.ttf" or nil end
S.FontFlags = function(outline, rendering)
    if rendering == 3 then return outline == "" and "SLUG" or "OUTLINE,SLUG" end
    if rendering == 2 then return outline == "" and "MONOCHROME" or outline .. ",MONOCHROME" end
    return outline
end
local textures = {}
local function Texture()
    local texture = { shown = true, alpha = 1 }
    function texture:SetTexture(path) self.path = path end
    function texture:SetVertexColor(...) self.color = { ... } end
    function texture:SetColorTexture(...) self.path = nil; self.color = { ... }; self.colorUpdates = (self.colorUpdates or 0) + 1 end
    function texture:ClearAllPoints() self.points = {} end
    function texture:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
    function texture:SetHeight(height) self.height = height end
    function texture:SetWidth(width) self.width = width end
    function texture:SetSize(width, height) self.width, self.height = width, height end
    function texture:SetTexCoord(...) self.coords = { ... } end
    function texture:SetAllPoints(owner) self.allPoints = owner end
    function texture:SetShown(shown) self.shown = shown end
    function texture:IsShown() return self.shown end
    function texture:IsVisible() return self.shown and (not self.owner or self.owner:IsShown()) end
    function texture:SetAlpha(alpha) self.alpha = alpha end
    function texture:GetAlpha() return self.alpha end
    function texture:Show() self.shown = true end
    function texture:Hide() self.shown = false end
    textures[#textures + 1] = texture
    return texture
end
local function Frame(name)
    local frame = { name = name, font = { "Fonts/FRIZQT__.TTF", 12, "" }, shown = true, alpha = 1, mouse = true }
    function frame:CreateTexture() local texture = Texture(); texture.owner = self; return texture end
    function frame:CreateFontString()
        return { SetPoint = function() end, SetText = function(label, value) label.value = value end,
            GetText = function(label) return label.value end,
            SetTextColor = function(label, ...) label.color = { ... } end,
            GetTextColor = function(label) return unpack(label.color or { 1, 1, 1, 1 }) end,
            SetJustifyH = function() end, SetWidth = function(label, width) label.width = width end,
            SetHeight = function(label, height) label.height = height end,
            GetHeight = function(label) return label.height or 12 end,
            SetFont = function(label, ...) label.font = { ... } end,
            GetFont = function(label) return unpack(label.font or { "Fonts/FRIZQT__.TTF", 12, "" }) end,
            SetAlpha = function(label, alpha) label.alpha = alpha end,
            GetAlpha = function(label) return label.alpha or 1 end,
            SetMaxLines = function(label, lines) label.maxLines = lines end }
    end
    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent end
    function frame:GetFont() return unpack(self.font) end
    function frame:SetFont(path, size, flags) self.font = { path, size, flags } end
    function frame:GetShadowColor() return unpack(self.shadowColor or { 0, 0, 0, 0 }) end
    function frame:SetShadowColor(...) self.shadowColor = { ... } end
    function frame:GetShadowOffset() return unpack(self.shadowOffset or { 0, 0 }) end
    function frame:SetShadowOffset(...) self.shadowOffset = { ... } end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:GetWidth() return self.width or 64 end
    function frame:GetHeight() return self.height or 32 end
    function frame:SetAllPoints() end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:ClearAllPoints() self.points = {} end
    function frame:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
    function frame:SetShown(shown) self.shown = shown end
    function frame:IsShown() return self.shown end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetFrameStrata(strata) self.strata = strata end
    function frame:GetFrameStrata() return self.strata or "LOW" end
    function frame:SetFrameLevel(level) self.level = level end
    function frame:GetFrameLevel() return self.level or 1 end
    function frame:EnableMouse(enabled) self.mouse = enabled end
    function frame:IsMouseEnabled() return self.mouse end
    function frame:SetMovable(value) self.movable = value end
    function frame:RegisterForDrag(button) self.dragButton = button end
    function frame:StartMoving() self.moving = true end
    function frame:StopMovingOrSizing() self.moving = false end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:GetAlpha() return self.alpha end
    function frame:RegisterForClicks() end
    function frame:SetClampedToScreen(value) self.clamped = value end
    function frame:SetAutoFocus(value) self.autoFocus = value end
    function frame:SetFocus() self.focused = true end
    function frame:ClearFocus() self.focused = false end
    function frame:HighlightText() self.highlighted = true end
    function frame:SetText(value) self.text = value end
    function frame:GetText() return self.text end
    function frame:GetNumMessages() return #(self.messages or {}) end
    function frame:GetMessageInfo(index) return self.messages and self.messages[index] end
    function frame:SetScript(script, callback) self.scripts = self.scripts or {}; self.scripts[script] = callback end
    function frame:Click(mouseButton)
        self.clicks = (self.clicks or 0) + 1
        if self.scripts and self.scripts.OnClick then self.scripts.OnClick(self, mouseButton) end
    end
    function frame:ScrollToBottom() self.scrolled = (self.scrolled or 0) + 1 end
    return frame
end
CreateFrame = function(_, _, parent)
    local frame = Frame(nil)
    frame.parent = parent
    return frame
end
UIParent = Frame("UIParent")
ChatFrame1 = Frame("ChatFrame1")
ChatFrame1.isDocked = true
ChatFrame1.isStaticDocked = true
ChatFrame1.Background = Texture()
ChatFrame1TopLeftTexture = Texture()
-- The button frame's chrome is a named texture of ChatFrame1.buttonFrame.
ChatFrame1.buttonFrame = Frame("ChatFrame1ButtonFrame")
ChatFrame1ButtonFrameBackground = Texture()
ChatFrame1Tab = Frame("ChatFrame1Tab")
ChatFrame1Tab.Left = Texture()
ChatFrame1Tab.noMouseAlpha = 0.4
ChatFrame1Tab.mouseOverAlpha = 1
ChatFrame1Tab.Text = ChatFrame1Tab:CreateFontString()
ChatFrame1Tab.Text:SetText("General")
ChatFrame1EditBox = Frame("ChatFrame1EditBox")
ChatFrame1EditBox.Left = Texture()
ChatFrame1.editBox = ChatFrame1EditBox
QuickJoinToastButton = Frame("QuickJoinToastButton")
ChatFrameChannelButton = Frame("ChatFrameChannelButton")
TextToSpeechButton = Frame("TextToSpeechButton")
ChatFrameMenuButton = Frame("ChatFrameMenuButton")
ChatFrameToggleVoiceDeafenButton = Frame("ChatFrameToggleVoiceDeafenButton")
ChatFrameToggleVoiceMuteButton = Frame("ChatFrameToggleVoiceMuteButton")
BNGetNumFriends = function() return 5, 3 end
C_FriendList = { GetNumOnlineFriends = function() return 2 end }
SELECTED_CHAT_FRAME = ChatFrame1
GENERAL_CHAT_DOCK = Frame("GeneralDockManager")
GENERAL_CHAT_DOCK.selected = ChatFrame1
CHAT_FRAMES = { "ChatFrame1" }
-- One built-in window, so later windows arrive through CHAT_FRAMES like
-- Blizzard's temporary windows. NUM_CHAT_WINDOWS is only a deprecation alias.
Constants = { ChatFrameConstants = { MaxChatWindows = 1 } }
-- Blizzard_GameTooltip builds GameTooltip at startup on both clients.
GameTooltip = Frame("GameTooltip")
GameTooltip.shown = false
function GameTooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
local temporaryHook, selectHook, newWindowHook, tabAlphaHook, tabColorsHook
FCF_OpenTemporaryWindow = function() end
FCF_OpenNewWindow = function() end
FCFDock_SelectWindow = function() end
FCFTab_UpdateAlpha = function() end
FCFTab_UpdateColors = function() end
hooksecurefunc = function(name, callback)
    assert(name == "FCF_OpenTemporaryWindow" or name == "FCF_OpenNewWindow"
        or name == "FCFDock_SelectWindow" or name == "FCFTab_UpdateAlpha"
        or name == "FCFTab_UpdateColors",
        "chat touched the message path")
    if name == "FCF_OpenTemporaryWindow" then temporaryHook = callback
    elseif name == "FCF_OpenNewWindow" then newWindowHook = callback
    elseif name == "FCFTab_UpdateAlpha" then tabAlphaHook = callback
    elseif name == "FCFTab_UpdateColors" then tabColorsHook = callback
    else selectHook = callback end
end

function S.Install(id, module)
    assert(id == "chat")
    S.module = module
end
function S.Queue() error("chat update should not poll or queue out of combat") end
local private = { NS = NS, Suite = S }
-- The runtime files load in TOC order into one private table (Bootstrap only
-- fills it from _G.MSUFSuite, which this fixture passes in directly).
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local CHAT_FILES = { "Bootstrap.lua", "Shared.lua", "Sidebar.lua", "Copy.lua", "Window.lua", "Controller.lua" }
local tocFiles = Support.TocFiles(root, "MSUF_Suite_Chat")
assert(#tocFiles == #CHAT_FILES, "the Chat TOC must list " .. #CHAT_FILES .. " files")
for i = 1, #CHAT_FILES do
    assert(tocFiles[i] == CHAT_FILES[i], "Chat TOC order: expected " .. CHAT_FILES[i] .. " at " .. i)
end
Support.Load(root, "MSUF_Suite_Chat", private, nil, { ["Bootstrap.lua"] = true })
local module = assert(S.module)
assert(module == private.Chat.M, "Controller.lua did not install the shared module table")
local ctx = { callbacks = {}, restored = 0, original = {}, properties = {}, fields = {} }
function ctx:Event(event, fn) self.callbacks[event] = fn end
function ctx:Property(frame, getter, setter, value)
    local record = self.properties[frame] or {}
    self.properties[frame] = record
    if record[setter] == nil then record[setter] = frame[getter](frame) end
    frame[setter](frame, value)
end
function ctx:RestoreProperty(frame, setter)
    local record = self.properties[frame]
    if record and record[setter] ~= nil then
        frame[setter](frame, record[setter]); record[setter] = nil
    end
end
function ctx:Alpha(frame, value) self:Property(frame, "GetAlpha", "SetAlpha", value) end
function ctx:Field(frame, key, value)
    local record = self.fields[frame] or {}
    self.fields[frame] = record
    if record[key] == nil then record[key] = frame[key] end
    frame[key] = value
end
function ctx:RestoreFields(frame)
    local record = self.fields[frame]
    if record then for key, value in pairs(record) do frame[key] = value end; self.fields[frame] = nil end
end
function ctx:HideControl(frame, hidden)
    if hidden then
        if not self.hidden then self.hidden = {} end
        if not self.hidden[frame] then self.hidden[frame] = { frame:GetAlpha(), frame:IsMouseEnabled() } end
        frame:SetAlpha(0); frame:EnableMouse(false)
    elseif self.hidden and self.hidden[frame] then
        frame:SetAlpha(self.hidden[frame][1]); frame:EnableMouse(self.hidden[frame][2]); self.hidden[frame] = nil
    end
end
function ctx:Tuple(frame, getter, setter, ...)
    local record = self.original[frame] or {}
    self.original[frame] = record
    record[setter] = record[setter] or { before = { frame[getter](frame) } }
    frame[setter](frame, ...)
    record[setter].applied = { frame[getter](frame) }
end
function ctx:RestoreTuple(frame, setter)
    self.restored = self.restored + 1
    local record = self.original[frame]
    if record and record[setter] then frame[setter](frame, unpack(record[setter].before)); record[setter] = nil end
end
-- The runtime's contract (MSUF_Suite_Modules/Runtime.lua): the module never
-- reaches into the context's private tuple records.
function ctx:UpdateTupleBefore(frame, setter, index, current)
    local record = self.original[frame] and self.original[frame][setter]
    if not record then return false end
    if record.applied and current ~= record.applied[index] then record.before[index] = current end
    return true, unpack(record.before)
end
module.context = ctx
module.active = true
module.config = {
    panelColor = "0a1220", panelAlpha = 74, borderColor = "41627a", borderAlpha = 78,
    borderSize = 1, accentColor = "57c7df", accentAlpha = 88, tabAccent = true,
    tabActiveColor = "f4f7fb", tabInactiveColor = "aab5c2",
    tabPanel = true, sidebarPanel = true, sidebarWidth = 28,
    inputPanel = true, inputColor = "0a1522", inputAlpha = 86, padding = 4, fontSize = 15,
    font = "", fontOutline = 1, fontRendering = 3, fontShadow = 1,
    copyMessages = false,
}
module:Enable()
-- Regression: the dock texture must join the body and border exactly. The
-- dock itself is offset above ChatFrame1, so matching its own bounds leaves
-- the short right corner and the gap seen in the live client.
local function AssertJoinedDockShell()
    local shell = module.visuals[ChatFrame1]
    local strip = module.dockStrip
    local bodyLeft, bodyRight = shell.panel.points[1], shell.panel.points[2]
    local edgeLeft, edgeRight = shell.edges[1].points[1], shell.edges[1].points[2]
    local stripLeft, stripRight = strip.points[1], strip.points[2]
    assert(strip and strip.owner == GENERAL_CHAT_DOCK and strip:IsVisible()
        and strip.color[4] > 0,
        "Suite dock background disappears when the primary chat frame is hidden")
    assert(stripLeft[1] == "TOPLEFT" and stripLeft[2] == ChatFrame1 and stripLeft[3] == "TOPLEFT"
        and stripRight[1] == "BOTTOMRIGHT" and stripRight[2] == ChatFrame1
        and stripRight[3] == "TOPRIGHT" and stripLeft[4] == bodyLeft[4]
        and stripLeft[4] == edgeLeft[4] and stripRight[4] == bodyRight[4]
        and stripRight[4] == edgeRight[4] and stripLeft[5] == edgeLeft[5]
        and stripRight[5] == bodyLeft[5],
        "Suite tab strip leaves a gap or short corner beside the chat body")
end
assert(ChatFrame1.font[3] == "SLUG" and ChatFrame1.shadowColor[4] == 0,
    "default chat messages did not use Slug")
assert(ctx.callbacks.UPDATE_CHAT_WINDOWS and ctx.callbacks.UPDATE_FLOATING_CHAT_WINDOWS
    and temporaryHook and newWindowHook and selectHook and tabAlphaHook and tabColorsHook)
assert(not ctx.callbacks.CHAT_MSG_SAY and not ctx.callbacks.CHAT_MSG_CHANNEL)
assert(ChatFrame1.font[2] == 15)
assert(module.visuals[ChatFrame1].panel.shown and module.visuals[ChatFrame1].tabLine.shown)
assert(module.visuals[ChatFrame1].panel.owner == ChatFrame1
    and module.visuals[ChatFrame1].panel.points[1][5] == 0,
    "Suite chat body did not stay on the chat frame below its tabs")
AssertJoinedDockShell()
assert(ChatFrame1Tab.noMouseAlpha == 0.8 and ChatFrame1Tab:GetAlpha() >= 0.8,
    "ordinary chat tabs were left unreadably dim")
assert(module.visuals[ChatFrame1].input.shown)
assert(module.visuals[ChatFrame1].sidebar.shown
    and module.visuals[ChatFrame1].headerRule.shown)
local sidebar = module.visuals[ChatFrame1]
assert(sidebar.sidebarFrame.shown and #sidebar.buttons == 5, "MSUF sidebar did not replace the native buttons")
assert(sidebar.sidebarFrame.strata == "MEDIUM", "sidebar icons render behind native chat")
assert(sidebar.sidebar.owner == sidebar.sidebarFrame and sidebar.sidebar.allPoints == sidebar.sidebarFrame,
    "sidebar background disappears when General is not the active tab")
assert(private.Chat.HeaderTop(module.config, ChatFrame1) == 24,
    "default chat header height changed")
assert(not ChatFrame1.Background.shown and not ChatFrame1TopLeftTexture.shown,
    "Blizzard frame chrome covers the MSUF panel")
assert(not ChatFrame1ButtonFrameBackground.shown,
    "Blizzard button frame covers the MSUF icons")
assert(ChatFrame1Tab.Left.alpha == 0 and ChatFrame1Tab.Text.alpha == 1
    and sidebar.tabLabel == ChatFrame1Tab.Text and sidebar.tabLabel.value == "General"
    and sidebar.tabLabel.color[4] == 1 and sidebar.tabLine.owner == ChatFrame1Tab
    and not sidebar.tabOverlay,
    "Suite must style the native tab title without drawing a duplicate")
assert(ChatFrame1EditBox.Left.alpha == 0, "native input art covers the MSUF input")
assert(sidebar.input.points[1][2] == ChatFrame1 and sidebar.input.points[1][3] == "BOTTOMLEFT"
    and sidebar.input.points[2][2] == ChatFrame1 and sidebar.input.points[2][3] == "BOTTOMRIGHT"
    and sidebar.inputEdges[1].points[1][2] == sidebar.input,
    "input backdrop and border do not align with the chat panel width")
-- Another addon may give the tab a longer title and repaint Blizzard's native
-- color. Suite must keep that one FontString and recolor it after Blizzard.
ChatFrame1Tab.Text:SetText("General Chat")
ChatFrame1Tab.Text:SetTextColor(0.1, 0.2, 0.3, 1)
tabColorsHook(ChatFrame1Tab, true)
local activeR, activeG, activeB = S.RGB(module.config.tabActiveColor)
assert(sidebar.tabLabel == ChatFrame1Tab.Text and sidebar.tabLabel:GetText() == "General Chat"
    and not sidebar.tabOverlay and math.abs(sidebar.tabLabel.color[1] - activeR) < 0.001
    and math.abs(sidebar.tabLabel.color[2] - activeG) < 0.001
    and math.abs(sidebar.tabLabel.color[3] - activeB) < 0.001,
    "a renamed tab gained duplicate text or lost its configured color")
ChatFrame1Tab.Text:SetText("General")
assert(sidebar.buttons[1].glyph.path == "Interface\\AddOns\\MSUF_Suite_Chat\\Media\\MSUFChatGlyphs.png",
    "MSUF glyph texture was replaced by a solid color")
UnitClass = function() return "Mage", "MAGE" end
S.ClassRGB = function(token)
    assert(token == "MAGE")
    return 0.2, 0.4, 0.8
end
module.config.sidebarClassColor = true
module:Refresh()
assert(math.abs(sidebar.buttons[1].glyph.color[1] - 0.2) < 0.01
    and math.abs(sidebar.friendCount.color[3] - 0.8) < 0.01,
    "sidebar icon and friend count did not use the player class color")
module.config.sidebarClassColor = false
module:Refresh()
assert(not sidebar.copyButton, "copy UI must be absent by default")
ChatFrame1.messages = {
    "|cffaaaaaa[15:38]|r First message",
    "secret",
    "|cff00ff00[15:39]|r |Hplayer:Mapko|h[Mapko]|h: Good point!",
}
module.config.copyMessages = true
module:Refresh()
assert(sidebar.copyButton and sidebar.copyButton.shown, "opt-in Copy button is missing")
local copyX, copyY = sidebar.copyButton.points[1][4], sidebar.copyButton.points[1][5]
module.config.copyButtonX, module.config.copyButtonY = 18, -12
module:Refresh()
assert(sidebar.copyButton.points[1][4] == copyX + 18
    and sidebar.copyButton.points[1][5] == copyY - 12,
    "Copy button X/Y settings did not move the button")
sidebar.copyButton.scripts.OnEnter(sidebar.copyButton)
assert(GameTooltip.owner == sidebar.copyButton and GameTooltip.text == "Copy a recent chat message"
    and GameTooltip.shown, "the Copy button did not explain itself")
sidebar.copyButton.scripts.OnLeave(sidebar.copyButton)
assert(not GameTooltip.shown, "leaving the Copy button kept its tooltip")
sidebar.copyButton:Click("LeftButton")
assert(module.copyDialog and module.copyDialog.shown and module.copyDialog.rows[1].message == "[15:39] [Mapko]: Good point!"
    and module.copyDialog.rows[2].message == "[15:38] First message"
    and not module.copyDialog.rows[3].shown, "copy chooser did not show recent public chat lines")
local copyDialog = module.copyDialog
assert(copyDialog.movable and copyDialog.dragHandle.dragButton == "LeftButton"
    and copyDialog.dragHandle.scripts.OnDragStart and copyDialog.dragHandle.scripts.OnDragStop,
    "copy chooser title is not draggable")
copyDialog.dragHandle.scripts.OnDragStart(copyDialog.dragHandle)
assert(copyDialog.moving, "dragging the title did not move the chooser")
copyDialog.dragHandle.scripts.OnDragStop(copyDialog.dragHandle)
assert(not copyDialog.moving and copyDialog.shown, "releasing the title did not stop moving")
module.copyDialog.rows[1]:Click("LeftButton")
assert(module.copyDialog.edit.text == "[15:39] [Mapko]: Good point!"
    and module.copyDialog.edit.focused and module.copyDialog.edit.highlighted,
    "choosing a line did not prepare its text for Ctrl+C")
module.config.copyMessages = false
module:Refresh()
assert(not sidebar.copyButton.shown and not module.copyDialog.shown,
    "turning off Copy left the button or chooser visible")
assert(module.copyDialog.rows[1].message == nil and module.copyDialog.edit.text == "",
    "turning off Copy retained the selected chat text")
assert(QuickJoinToastButton.alpha == 0 and not QuickJoinToastButton.mouse)
assert(ChatFrameToggleVoiceMuteButton.alpha == 0 and not ChatFrameToggleVoiceMuteButton.mouse)
assert(sidebar.friendCount.value == "5", "friend count did not use the live Blizzard data")
sidebar.buttons[1].button:Click("LeftButton")
sidebar.buttons[2].button:Click("LeftButton")
sidebar.buttons[3].button:Click("LeftButton")
sidebar.buttons[4].button:Click("LeftButton")
sidebar.buttons[5].button:Click("LeftButton")
assert(QuickJoinToastButton.clicks == 1 and ChatFrameChannelButton.clicks == 1
    and TextToSpeechButton.clicks == 1 and ChatFrameMenuButton.clicks == 1
    and ChatFrame1.scrolled == 1, "sidebar controls did not retain their actions")
-- Hovering a sidebar button lights its glyph in the accent color and names it.
local channels = sidebar.buttons[2]
channels.button.scripts.OnEnter(channels.button)
assert(GameTooltip.owner == channels.button and GameTooltip.text == "Channels and voice" and GameTooltip.shown
    and channels.glyph.color[4] == 1 and channels.highlight.color[4] == 0.2,
    "sidebar hover did not show the button's tooltip and highlight")
channels.button.scripts.OnLeave(channels.button)
assert(not GameTooltip.shown and channels.glyph.color[4] == 0.94 and channels.highlight.color[4] == 0,
    "leaving a sidebar button kept its tooltip or highlight")
-- Friend events update the count in combat too; it caps at 99+ and keeps
-- the last public value when Blizzard's counts are unreadable.
BNGetNumFriends = function() return 90, 60 end
C_FriendList.GetNumOnlineFriends = function() return 40 end
ctx.callbacks.BN_FRIEND_ACCOUNT_ONLINE(module, "BN_FRIEND_ACCOUNT_ONLINE")
assert(sidebar.friendCount.value == "99+", "friend count did not cap at 99+")
BNGetNumFriends = function() return 5, "secret" end
ctx.callbacks.FRIENDLIST_UPDATE(module, "FRIENDLIST_UPDATE")
assert(sidebar.friendCount.value == "99+", "an unreadable friend count replaced the last public count")
BNGetNumFriends = function() return 5, 3 end
C_FriendList.GetNumOnlineFriends = function() return 2 end
ctx.callbacks.FRIENDLIST_UPDATE(module, "FRIENDLIST_UPDATE")
assert(sidebar.friendCount.value == "5", "friend count did not follow Blizzard's counts again")
assert(module.visuals[ChatFrame1].panel.color[1] < 0.1
    and module.visuals[ChatFrame1].panel.color[2] < 0.1
    and module.visuals[ChatFrame1].panel.color[3] < 0.2,
    "chat panel must use the dark preset color")
local edges = module.visuals[ChatFrame1].edges
assert(edges[1].height == 1 and edges[2].height == 1
    and edges[3].width == 1 and edges[4].width == 1,
    "border must be four narrow lines, not full-window overlays")
assert(edges[1].points[2][1] == "TOPRIGHT" and edges[2].points[2][1] == "BOTTOMRIGHT",
    "horizontal borders were anchored to the opposite corner")
local count = #textures
module:Refresh()
assert(#textures == count, "refresh created another visual layer")
-- Focused or unreadable edit-box sizes keep only the cosmetic panel compact.
ChatFrame1EditBox:SetHeight(math.huge)
module:Refresh()
assert(sidebar.input.points[2][5] == -30, "an unreadable input height reached the input backdrop")
ChatFrame1EditBox:SetHeight(60)
module:Refresh()
assert(sidebar.input.points[2][5] == -30, "focused edit box enlarged the input backdrop")
ChatFrame1EditBox.height = nil
module:Refresh()
module.config.sidebarPanel = false
module:Refresh()
assert(not sidebar.sidebarFrame.shown and QuickJoinToastButton.alpha == 1 and QuickJoinToastButton.mouse,
    "turning off the sidebar did not restore native buttons")
module.config.sidebarPanel = true
module:Refresh()
module.config.fontSize = 0
module.config.fontRendering = 1
module.config.tabAccent = false
module:Refresh()
assert(ChatFrame1.font[2] == 12 and ctx.restored > 0)
assert(not module.visuals[ChatFrame1].tabLine.shown)
module.config.font, module.config.fontOutline = "TestFont", 3
module.config.fontRendering, module.config.fontShadow = 2, 2
module.config.fontShadowOpacity, module.config.fontShadowDistance = 60, 2
module:Refresh()
assert(ChatFrame1.font[1] == "Test.ttf" and ChatFrame1.font[2] == 12
    and ChatFrame1.font[3] == "THICKOUTLINE,MONOCHROME"
    and ChatFrame1.shadowColor[4] == 0.6 and ChatFrame1.shadowOffset[1] == 2,
    "chat font effects were not applied")
-- Blizzard's chat menu resizes the font we set. With size 0 that size stays,
-- an explicit size still wins, and size 0 then follows Blizzard's size again.
ChatFrame1:SetFont(ChatFrame1.font[1], 16, ChatFrame1.font[3])
module:Refresh()
assert(ChatFrame1.font[2] == 16, "font size 0 reverted Blizzard's chat font size")
module.config.fontSize = 20
module:Refresh()
assert(ChatFrame1.font[2] == 20, "an explicit chat font size did not apply")
module.config.fontSize = 0
module:Refresh()
assert(ChatFrame1.font[2] == 16, "font size 0 did not return to Blizzard's chat font size")
module.config.fontRendering = 3
module:Refresh()
assert(ChatFrame1.font[3] == "OUTLINE,SLUG" and ChatFrame1.shadowColor[4] == 0
    and ChatFrame1.shadowOffset[1] == 0, "Slug must suppress native chat shadow")
module.config.font, module.config.fontOutline = "", 1
module.config.fontRendering, module.config.fontShadow = 1, 1
module:Refresh()
assert(ChatFrame1.font[1] == "Fonts/FRIZQT__.TTF" and ChatFrame1.font[2] == 16 and ChatFrame1.font[3] == ""
    and ChatFrame1.shadowColor[4] == 0, "chat text ownership did not restore Blizzard's font and size")
ChatFrame2 = Frame("ChatFrame2")
ChatFrame2.isDocked = true
-- Synthetic second static tab covers the native title selection contract;
-- Retail's additional tabs use the dynamic path exercised by ChatFrame3.
ChatFrame2.isStaticDocked = true
ChatFrame2.editBox = Frame("ChatFrame2EditBox")
ChatFrame2Tab = Frame("ChatFrame2Tab")
ChatFrame2Tab.Left = Texture()
ChatFrame2Tab.Text = ChatFrame2Tab:CreateFontString()
ChatFrame2Tab.Text:SetText("Combat Log")
CHAT_FRAMES[2] = "ChatFrame2"
temporaryHook()
assert(module.visuals[ChatFrame2], "new Blizzard chat window was not styled")
assert(module.visuals[ChatFrame2].tabLabel == ChatFrame2Tab.Text
    and module.visuals[ChatFrame2].tabLabel.value == "Combat Log"
    and not module.visuals[ChatFrame2].tabOverlay,
    "Combat Log gained duplicate tab text")
-- Retail whisper targets can be secret. The temporary whisper tab must keep
-- Blizzard's native title without copying its text.
ChatFrame2.chatType = "WHISPER"
ChatFrame2.isTemporary = true
ChatFrame2Tab.Text:SetText("secret")
temporaryHook()
assert(ChatFrame2Tab.Text.value == "secret" and ChatFrame2Tab.Text.alpha == 1
    and ChatFrame2Tab.Left.alpha == 0
    and not module.visuals[ChatFrame2].tabOverlay,
    "a secret whisper target lost Blizzard's native title")
ChatFrame2.chatType = "BN_WHISPER"
temporaryHook()
assert(ChatFrame2Tab.Text.alpha == 1 and not module.visuals[ChatFrame2].tabOverlay,
    "a Battle.net whisper lost Blizzard's visible native tab")
ChatFrame2.chatType = nil
ChatFrame2.isTemporary = nil
ChatFrame2Tab.Text:SetText("Combat Log")
temporaryHook()
assert(module.visuals[ChatFrame2].tabLabel.value == "Combat Log"
    and ChatFrame2Tab.Text.alpha == 1 and ChatFrame2Tab.Left.alpha == 0
    and not module.visuals[ChatFrame2].tabOverlay,
    "a reused whisper tab kept its previous title")
CombatLogQuickButtonFrame_Custom = Frame("CombatLogQuickButtonFrame_Custom")
CombatLogQuickButtonFrame_Custom:SetHeight(24)
CombatLogQuickButtonFrame_CustomTexture = Texture()
ChatFrame2.CombatLogQuickButtonFrame = CombatLogQuickButtonFrame_Custom
ctx.callbacks.ADDON_LOADED(module, "ADDON_LOADED", "Blizzard_CombatLog")
assert(private.Chat.HeaderTop(module.config, ChatFrame2) == 51
    and CombatLogQuickButtonFrame_CustomTexture.alpha == 0,
    "Combat Log filter row did not join the MSUF header")
CombatLogQuickButtonFrame_Custom:SetHeight(math.huge)
module:Refresh()
assert(private.Chat.HeaderTop(module.config, ChatFrame2) == 24, "an unreadable Combat Log row height reached the chat header")
CombatLogQuickButtonFrame_Custom:SetHeight(24)
module:Refresh()
GENERAL_CHAT_DOCK.selected = ChatFrame2
module.config.tabAccent = true
local panelColorUpdates = sidebar.panel.colorUpdates
ChatFrame1:Hide()
selectHook()
assert(module.visuals[ChatFrame2].tabLine.shown and not sidebar.tabLine.shown,
    "selected tab accent did not follow Blizzard tab selection")
assert(module.visuals[ChatFrame2].tabLabel.color[4] == 1,
    "selected Combat Log tab is dimmed")
assert(sidebar.tabLabel.color[4] == 1 and sidebar.panel.colorUpdates == panelColorUpdates,
    "selecting a chat tab unnecessarily restyled the whole chat panel")
assert(sidebar.sidebar.shown and sidebar.sidebarFrame.shown
    and sidebar.sidebarFrame.points[1][2] == ChatFrame2
    and sidebar.sidebarFrame.points[1][5] == 51,
    "the MSUF sidebar did not follow the selected docked tab")
SELECTED_CHAT_FRAME = ChatFrame2
selectHook()
assert(sidebar.panel.colorUpdates == panelColorUpdates,
    "changing the active chat target restyled the whole panel")
ChatFrame1:Show()
GENERAL_CHAT_DOCK.selected = ChatFrame1
SELECTED_CHAT_FRAME = ChatFrame1
selectHook()
assert(sidebar.sidebarFrame.points[1][2] == ChatFrame1 and sidebar.tabLine.shown,
    "switching back to General lost the MSUF shell")
GENERAL_CHAT_DOCK.selected = ChatFrame2
SELECTED_CHAT_FRAME = ChatFrame2
selectHook()
assert(sidebar.sidebarFrame.points[1][2] == ChatFrame2
    and module.visuals[ChatFrame2].tabLine.shown
    and sidebar.panel.colorUpdates == panelColorUpdates,
    "switching again to Combat Log lost the MSUF shell")
ChatFrame3 = Frame("ChatFrame3")
ChatFrame3.isDocked = true
ChatFrame3.editBox = Frame("ChatFrame3EditBox")
ChatFrame3Tab = Frame("ChatFrame3Tab")
ChatFrame3Tab.Left = Texture()
ChatFrame3Tab.Text = ChatFrame3Tab:CreateFontString()
ChatFrame3Tab.Text:SetText("Loot")
CHAT_FRAMES[3] = "ChatFrame3"
GENERAL_CHAT_DOCK.selected = ChatFrame3
newWindowHook()
assert(module.visuals[ChatFrame3] and module.visuals[ChatFrame3].panel.shown
    and private.Chat.HeaderTop(module.config, ChatFrame3) == 24
    and ChatFrame3Tab.Text.value == "Loot" and ChatFrame3Tab.Text:GetAlpha() == 1
    and ChatFrame3Tab.Left.alpha == 0 and not module.visuals[ChatFrame3].tabOverlay
    and sidebar.sidebarFrame.points[1][2] == ChatFrame3,
    "a newly opened dynamic chat tab lost Blizzard's native title")
-- A chat window that fails to style is reported; the later windows are styled.
assert(#reports == 0, "chat styling raised: " .. tostring(reports[1]))
ChatFrame4 = Frame("ChatFrame4")
ChatFrame4.isDocked = true
ChatFrame4.isTemporary = true
ChatFrame4.chatType = "WHISPER"
ChatFrame4.editBox = Frame("ChatFrame4EditBox")
ChatFrame4Tab = Frame("ChatFrame4Tab")
ChatFrame4Tab.Left = Texture()
ChatFrame4Tab.Text = ChatFrame4Tab:CreateFontString()
ChatFrame4Tab.Text:SetText("secret")
ChatFrame4Tab.noMouseAlpha = 0.2
ChatFrame4Tab.mouseOverAlpha = 0.6
ChatFrame4Tab:SetAlpha(0.2)
CHAT_FRAMES[4] = "ChatFrame4"
local getName = ChatFrame2.GetName
ChatFrame2.GetName = function() error("another addon replaced a chat frame part") end
temporaryHook()
ChatFrame2.GetName = getName
assert(#reports == 1 and module.visuals[ChatFrame4] and module.visuals[ChatFrame4].panel.shown,
    "a chat window that failed to style stopped the later windows")
assert(ChatFrame4Tab.Text:GetAlpha() == 1 and ChatFrame4Tab.Left.alpha == 0
    and not module.visuals[ChatFrame4].tabOverlay,
    "a new whisper window hid its native tab")
assert(ChatFrame4Tab.noMouseAlpha == 0.8 and ChatFrame4Tab.mouseOverAlpha == 1
    and ChatFrame4Tab:GetAlpha() == 0.8,
    "an idle whisper tab remained too dark to find")
-- Regression: selecting a new whisper hides the primary chat frame. The Suite
-- body must follow the selected window; the dock strip must remain on the
-- Blizzard dock; and no replacement overlay may intercept its native tab.
GENERAL_CHAT_DOCK.selected = ChatFrame4
SELECTED_CHAT_FRAME = ChatFrame4
ChatFrame1:Hide()
selectHook()
assert(not sidebar.panel:IsVisible() and module.visuals[ChatFrame4].panel:IsVisible()
    and module.visuals[ChatFrame4].panel.owner == ChatFrame4
    and module.visuals[ChatFrame4].panel.color[4] > 0
    and sidebar.sidebarFrame.points[1][2] == ChatFrame4,
    "selecting a whisper removed the Suite chat body or sidebar")
AssertJoinedDockShell()
assert(ChatFrame4Tab:IsMouseEnabled() and ChatFrame4Tab.Text:GetAlpha() == 1
    and ChatFrame4Tab:GetAlpha() >= 0.8 and not module.visuals[ChatFrame4].tabOverlay,
    "selected whisper tab is hidden, dimmed or covered")
ChatFrame4Tab:Click("LeftButton")
assert(ChatFrame4Tab.clicks == 1, "selected whisper tab cannot be clicked")
-- The corner must remain joined after the user changes Suite padding.
module.config.padding = 9
module:Refresh()
AssertJoinedDockShell()
assert(module.dockStrip.points[1][4] == -9 and module.dockStrip.points[2][4] == 9,
    "Suite dock strip did not follow the changed padding")
module.config.padding = 4
module:Refresh()
AssertJoinedDockShell()
ChatFrame4.chatType = "BN_WHISPER"
temporaryHook()
assert(ChatFrame4Tab.Text:GetAlpha() == 1 and ChatFrame4Tab.Left.alpha == 0
    and not module.visuals[ChatFrame4].tabOverlay,
    "Battle.net whisper title was hidden by Suite tab styling")
ChatFrame4.chatType = "WHISPER"
-- Blizzard resets these fields on dock changes. Its post-hook must restore
-- the Suite minimum without affecting the title or message path.
ChatFrame4Tab.noMouseAlpha = 0.2
ChatFrame4Tab.mouseOverAlpha = 0.6
ChatFrame4Tab:SetAlpha(0.2)
tabAlphaHook(ChatFrame4)
assert(ChatFrame4Tab.noMouseAlpha == 0.8 and ChatFrame4Tab:GetAlpha() == 0.8,
    "Blizzard's tab update dimmed the whisper again")
module:Disable()
assert(ChatFrame4Tab.noMouseAlpha == 0.2 and ChatFrame4Tab.mouseOverAlpha == 0.6
    and ChatFrame4Tab:GetAlpha() == 0.2,
    "disabling Chat did not restore Blizzard's whisper-tab fading")
assert(not module.visuals[ChatFrame1].panel.shown and not module.visuals[ChatFrame2].panel.shown
    and not module.visuals[ChatFrame3].panel.shown and not module.dockStrip.shown)
assert(not module.visuals[ChatFrame1].input.shown)
assert(not module.visuals[ChatFrame1].sidebar.shown)
assert(not sidebar.sidebarFrame.shown and QuickJoinToastButton.alpha == 1 and QuickJoinToastButton.mouse)
assert(ChatFrame1.Background.shown and ChatFrame1TopLeftTexture.shown
    and ChatFrame1ButtonFrameBackground.shown,
    "disabling chat did not restore Blizzard chrome")
assert(ChatFrame1Tab.Left.alpha == 1 and ChatFrame1Tab.noMouseAlpha == 0.4
    and ChatFrame1Tab.Text.alpha == 1 and ChatFrame1EditBox.Left.alpha == 1
    and CombatLogQuickButtonFrame_CustomTexture.alpha == 1,
    "disabling chat did not restore Blizzard tab/input")
-- Every runtime file starts with the shared private-table header, and
-- Suite-created regions go through the shared S.CreateTexture/S.CreateFontString.
for i = 2, #CHAT_FILES do
    local file = CHAT_FILES[i]
    local sourceFile = assert(io.open(root .. "/MSUF_Suite_Chat/" .. file, "rb"))
    local source = sourceFile:read("*a"):gsub("\r", "")
    sourceFile:close()
    local first, _, third = source:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n")
    assert(first == "local _, P = ...", file .. " does not start with the Chat file header")
    if file == "Shared.lua" then
        assert(source:find("\nlocal C = {}\nP.Chat = C\n", 1, true), "Shared.lua does not create P.Chat")
    else
        assert(third == "local C = P.Chat", file .. " does not read P.Chat in its header")
    end
    assert(not source:find(":CreateTexture%(") and not source:find(":CreateFontString%("),
        file .. " creates regions without S.CreateTexture/S.CreateFontString")
    -- Retail and WoW Forever always have the APIs, widget methods and frames
    -- Chat calls (GameTooltip, the chat templates' tab, Text and editBox),
    -- and the FCF_* hook targets exist at login on both clients.
    source = source:gsub("%-%-[^\n]*", "")
    local guarded = source:match("type%(([^)]*)%)%s*[~=]=%s*\"function\"") or source:match("([%w_]+%.GetName) and")
        or source:match("if not (_G%.GameTooltip)") or source:match("if (_G%.GameTooltip) then")
        or source:match("(NUM_CHAT_WINDOWS)") or source:match("(GetFontString)")
    assert(not guarded, file .. " guards " .. tostring(guarded) .. " as if a client lacked it")
    assert(file == "Controller.lua" or not source:find("S.Install(", 1, true), file .. " installs the module")
end
print("Chat styling, whisper tab and joined dock regression, native font restore and event-only refresh passed")
