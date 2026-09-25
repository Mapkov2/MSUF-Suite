local root = assert(arg[1])
local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return false end,
}
local S = {}
S.Public = function(value) return value ~= "secret" end
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
            SetJustifyH = function() end, SetWidth = function(label, width) label.width = width end,
            SetFont = function(label, ...) label.font = { ... } end,
            GetFont = function(label) return unpack(label.font or { "Fonts/FRIZQT__.TTF", 12, "" }) end,
            SetAlpha = function(label, alpha) label.alpha = alpha end,
            GetAlpha = function(label) return label.alpha or 1 end }
    end
    function frame:GetName() return self.name end
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
CreateFrame = function(_, _, _) return Frame(nil) end
UIParent = Frame("UIParent")
ChatFrame1 = Frame("ChatFrame1")
ChatFrame1.isDocked = true
ChatFrame1.Background = Texture()
ChatFrame1TopLeftTexture = Texture()
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
GENERAL_CHAT_DOCK = { selected = ChatFrame1 }
CHAT_FRAMES = { "ChatFrame1" }
NUM_CHAT_WINDOWS = 1
local temporaryHook, selectHook, newWindowHook
FCF_OpenTemporaryWindow = function() end
FCF_OpenNewWindow = function() end
FCFDock_SelectWindow = function() end
hooksecurefunc = function(name, callback)
    assert(name == "FCF_OpenTemporaryWindow" or name == "FCF_OpenNewWindow"
        or name == "FCFDock_SelectWindow",
        "chat touched the message path")
    if name == "FCF_OpenTemporaryWindow" then temporaryHook = callback
    elseif name == "FCF_OpenNewWindow" then newWindowHook = callback
    else selectHook = callback end
end

function S.Install(id, module)
    assert(id == "chat")
    S.module = module
end
function S.Queue() error("chat update should not poll or queue out of combat") end
local private = { NS = NS, Suite = S }
assert(loadfile(root .. "/MSUF_Suite_Chat/Chat.lua"))("MSUF_Suite_Chat", private)
local module = assert(S.module)
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
    self.tuples = self.original
    frame[setter](frame, ...)
end
function ctx:RestoreTuple(frame, setter)
    self.restored = self.restored + 1
    local record = self.original[frame]
    if record and record[setter] then frame[setter](frame, unpack(record[setter].before)); record[setter] = nil end
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
assert(ChatFrame1.font[3] == "SLUG" and ChatFrame1.shadowColor[4] == 0,
    "default chat messages did not use Slug")
assert(ctx.callbacks.UPDATE_CHAT_WINDOWS and ctx.callbacks.UPDATE_FLOATING_CHAT_WINDOWS
    and temporaryHook and newWindowHook and selectHook)
assert(not ctx.callbacks.CHAT_MSG_SAY and not ctx.callbacks.CHAT_MSG_CHANNEL)
assert(ChatFrame1.font[2] == 15)
assert(module.visuals[ChatFrame1].panel.shown and module.visuals[ChatFrame1].tabLine.shown)
assert(module.visuals[ChatFrame1].input.shown)
assert(module.visuals[ChatFrame1].sidebar.shown and module.visuals[ChatFrame1].header.shown
    and module.visuals[ChatFrame1].headerRule.shown)
local sidebar = module.visuals[ChatFrame1]
assert(sidebar.sidebarFrame.shown and #sidebar.buttons == 5, "MSUF sidebar did not replace the native buttons")
assert(sidebar.sidebarFrame.strata == "MEDIUM", "sidebar icons render behind native chat")
assert(sidebar.sidebar.owner == sidebar.sidebarFrame and sidebar.sidebar.allPoints == sidebar.sidebarFrame,
    "sidebar background disappears when General is not the active tab")
assert(sidebar.header.points[1][1] == "TOPLEFT" and sidebar.header.points[2][1] == "TOPRIGHT"
    and sidebar.header.height == 24,
    "default chat header is not a straight full-width strip")
assert(not ChatFrame1.Background.shown and not ChatFrame1TopLeftTexture.shown,
    "Blizzard frame chrome covers the MSUF panel")
assert(not ChatFrame1ButtonFrameBackground.shown,
    "Blizzard button frame covers the MSUF icons")
assert(ChatFrame1Tab.Left.alpha == 0 and ChatFrame1Tab.Text.alpha == 0
    and sidebar.tabOverlay.strata == "MEDIUM" and sidebar.tabLabel.value == "General"
    and sidebar.tabLabel.color[4] == 1 and not sidebar.tabOverlay.mouse,
    "native tab fading still dims or hides the MSUF label")
assert(ChatFrame1EditBox.Left.alpha == 0, "native input art covers the MSUF input")
assert(sidebar.input.points[1][2] == ChatFrame1 and sidebar.input.points[1][3] == "BOTTOMLEFT"
    and sidebar.input.points[2][2] == ChatFrame1 and sidebar.input.points[2][3] == "BOTTOMRIGHT"
    and sidebar.inputEdges[1].points[1][2] == sidebar.input,
    "input backdrop and border do not align with the chat panel width")
ChatFrame1Tab:SetAlpha(0.4)
assert(sidebar.tabLabel.value == "General" and sidebar.tabOverlay.alpha == 1,
    "Blizzard tab refresh dimmed the independent MSUF label")
assert(sidebar.buttons[1].glyph.path == "Interface\\AddOns\\MSUF_Suite_Chat\\Media\\MSUFChatGlyphs.png",
    "MSUF glyph texture was replaced by a solid color")
assert(not sidebar.copyButton, "copy UI must be absent by default")
ChatFrame1.messages = {
    "|cffaaaaaa[15:38]|r First message",
    "secret",
    "|cff00ff00[15:39]|r |Hplayer:Mapko|h[Mapko]|h: Good point!",
}
module.config.copyMessages = true
module:Refresh()
assert(sidebar.copyButton and sidebar.copyButton.shown, "opt-in Copy button is missing")
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
module.config.fontRendering = 3
module:Refresh()
assert(ChatFrame1.font[3] == "OUTLINE,SLUG" and ChatFrame1.shadowColor[4] == 0
    and ChatFrame1.shadowOffset[1] == 0, "Slug must suppress native chat shadow")
module.config.font, module.config.fontOutline = "", 1
module.config.fontRendering, module.config.fontShadow = 1, 1
module:Refresh()
assert(ChatFrame1.font[1] == "Fonts/FRIZQT__.TTF" and ChatFrame1.font[3] == ""
    and ChatFrame1.shadowColor[4] == 0, "chat text ownership did not restore")
ChatFrame2 = Frame("ChatFrame2")
ChatFrame2.isDocked = true
ChatFrame2Tab = Frame("ChatFrame2Tab")
ChatFrame2Tab.Text = ChatFrame2Tab:CreateFontString()
ChatFrame2Tab.Text:SetText("Combat Log")
CHAT_FRAMES[2] = "ChatFrame2"
temporaryHook()
assert(module.visuals[ChatFrame2], "new Blizzard chat window was not styled")
assert(module.visuals[ChatFrame2].tabLabel.value == "Combat Log",
    "Combat Log did not receive a readable MSUF tab label")
CombatLogQuickButtonFrame_Custom = Frame("CombatLogQuickButtonFrame_Custom")
CombatLogQuickButtonFrame_Custom:SetHeight(24)
CombatLogQuickButtonFrame_Custom.Texture = Texture()
ChatFrame2.CombatLogQuickButtonFrame = CombatLogQuickButtonFrame_Custom
ctx.callbacks.ADDON_LOADED(module, "ADDON_LOADED", "Blizzard_CombatLog")
assert(module.visuals[ChatFrame2].header.height == 51
    and CombatLogQuickButtonFrame_Custom.Texture.alpha == 0,
    "Combat Log filter row did not join the MSUF header")
GENERAL_CHAT_DOCK.selected = ChatFrame2
module.config.tabAccent = true
local panelColorUpdates = sidebar.panel.colorUpdates
ChatFrame1:Hide()
selectHook()
assert(module.visuals[ChatFrame2].tabLine.shown and not sidebar.tabLine.shown,
    "selected tab accent did not follow Blizzard tab selection")
assert(module.visuals[ChatFrame2].tabLabel.color[4] == 1,
    "selected Combat Log tab is dimmed")
assert(sidebar.tabLabel.color[4] == 0.78 and sidebar.panel.colorUpdates == panelColorUpdates,
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
ChatFrame3Tab = Frame("ChatFrame3Tab")
ChatFrame3Tab.Text = ChatFrame3Tab:CreateFontString()
ChatFrame3Tab.Text:SetText("Loot")
CHAT_FRAMES[3] = "ChatFrame3"
GENERAL_CHAT_DOCK.selected = ChatFrame3
newWindowHook()
assert(module.visuals[ChatFrame3] and module.visuals[ChatFrame3].panel.shown
    and module.visuals[ChatFrame3].header.height == 24
    and module.visuals[ChatFrame3].tabLabel.value == "Loot"
    and sidebar.sidebarFrame.points[1][2] == ChatFrame3,
    "a newly opened chat tab did not inherit the General styling")
module:Disable()
assert(not module.visuals[ChatFrame1].panel.shown and not module.visuals[ChatFrame2].panel.shown
    and not module.visuals[ChatFrame3].panel.shown)
assert(not module.visuals[ChatFrame1].input.shown)
assert(not module.visuals[ChatFrame1].sidebar.shown)
assert(not sidebar.sidebarFrame.shown and QuickJoinToastButton.alpha == 1 and QuickJoinToastButton.mouse)
assert(ChatFrame1.Background.shown and ChatFrame1TopLeftTexture.shown
    and ChatFrame1ButtonFrameBackground.shown,
    "disabling chat did not restore Blizzard chrome")
assert(ChatFrame1Tab.Left.alpha == 1 and ChatFrame1Tab.noMouseAlpha == 0.4
    and ChatFrame1Tab.Text.alpha == 1 and ChatFrame1EditBox.Left.alpha == 1
    and CombatLogQuickButtonFrame_Custom.Texture.alpha == 1,
    "disabling chat did not restore Blizzard tab/input")
print("Chat styling, native font restore and event-only refresh passed")
