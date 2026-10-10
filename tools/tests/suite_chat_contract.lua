local root = assert(arg[1])
-- Combat as the Suite core reports it (MSUF_Suite/Core/Platform.lua):
-- PLAYER_REGEN_DISABLED marks combat before InCombatLockdown() turns true.
local inCombat, lockdown = false, false
local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return lockdown end,
    InCombat = function() return inCombat or lockdown end,
    RestrictedNotice = function() return "Blizzard blocks this right now." end,
}
local S = {}
local printed = {}
S.Print = function(message) printed[#printed + 1] = message end
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
local globalFont = "MSUF.ttf"
S.GlobalFontPath = function() return globalFont end
S.FontFlags = function(outline, rendering)
    if rendering == 3 then return outline == "" and "SLUG" or "OUTLINE,SLUG" end
    if rendering == 2 then return outline == "" and "MONOCHROME" or outline .. ",MONOCHROME" end
    return outline
end
local textures = {}
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
local function Texture()
    local texture = { shown = true, alpha = 1 }
    function texture:SetTexture(path) self.path = path end
    function texture:SetVertexColor(...) self.color = { ... } end
    function texture:SetColorTexture(...) self.path = nil; self.color = { ... }; self.colorUpdates = (self.colorUpdates or 0) + 1 end
    function texture:SetGradient(direction, first, last) self.gradient = { direction, first, last } end
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
            GetUnboundedStringWidth = function(label) return #(label.value or "") * 6 end,
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
    function frame:SetAllPoints(owner) self.points = { { "TOPLEFT", owner, "TOPLEFT" }, { "BOTTOMRIGHT", owner, "BOTTOMRIGHT" } } end
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
    function frame:HasFocus() return self.focused == true end
    -- Only the input line's focus is followed (Fade.lua), never another script.
    function frame:HookScript(script, callback)
        assert(script == "OnEditFocusGained" or script == "OnEditFocusLost", "chat hooked the " .. script .. " script")
        self.hooks = self.hooks or {}
        assert(not self.hooks[script], "chat hooked " .. script .. " twice")
        self.hooks[script] = callback
    end
    function frame:HighlightText() self.highlighted = true end
    function frame:SetText(value) self.text = value end
    function frame:GetText() return self.text end
    function frame:GetNumMessages() return #(self.messages or {}) end
    function frame:GetMessageInfo(index) return self.messages and self.messages[index] end
    function frame:SetScript(script, callback) self.scripts = self.scripts or {}; self.scripts[script] = callback end
    function frame:SetAttribute(key, value) self.attributes = self.attributes or {}; self.attributes[key] = value end
    function frame:GetAttribute(key) return self.attributes and self.attributes[key] end
    function frame:IsMouseOver() return self.mouseOver == true end
    function frame:Click(mouseButton)
        self.clicks = (self.clicks or 0) + 1
        if self.scripts and self.scripts.OnClick then self.scripts.OnClick(self, mouseButton) end
    end
    function frame:ScrollToBottom() self.scrolled = (self.scrolled or 0) + 1 end
    return frame
end
CreateFrame = function(_, _, parent, template)
    local frame = Frame(nil)
    frame.parent, frame.template = parent, template
    return frame
end
local stateDrivers = {}
RegisterStateDriver = function(frame, state, values) stateDrivers[frame] = { state = state, values = values } end
-- SecureActionButton_OnClick of a "click" action (SecureTemplates.lua, live
-- and forever) clicks its clickbutton from secure code.
local secureClick = false
local function SecureClick(frame, mouseButton)
    assert(frame.template == "SecureActionButtonTemplate" and frame:GetAttribute("type") == "click",
        "the frame is no secure click button")
    secureClick = true
    frame:GetAttribute("clickbutton"):Click(mouseButton)
    secureClick = false
end
-- Blizzard's panel buttons (QuickJoinToastButton, ChatFrameChannelButton,
-- TextToSpeechButton) open their panel through ShowUIPanel from OnClick.
local panelOpens = {}
local function PanelOnClick(button) panelOpens[#panelOpens + 1] = { button = button, secure = secureClick } end
UIParent = Frame("UIParent")
ChatFrame1 = Frame("ChatFrame1")
ChatFrame1.isDocked = 1
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
for _, button in ipairs({ QuickJoinToastButton, ChatFrameChannelButton, TextToSpeechButton }) do
    button:SetScript("OnClick", PanelOnClick)
end
-- Blizzard's chat menu button is a DropdownButton (Blizzard_Menu/DropdownButton.xml
-- and .lua, live and forever): the press opens and closes its menu
-- (OnMouseDown_Intrinsic -> SetMenuOpen, ignored with Shift), its own OnClick
-- (ChatFrameMenuButtonMixin:OnClick) only hides a help tip, and Blizzard's
-- menu closes on its next frame once the button is not visible.
ChatFrameMenuButton = Frame("ChatFrameMenuButton")
ChatFrameMenuButton.parent = ChatFrame1.buttonFrame
ChatFrameMenuButton:SetScript("OnClick", function() end)
function ChatFrameMenuButton:IsMenuOpen() return self.menu ~= nil end
function ChatFrameMenuButton:SetMenuOpen(open)
    if open and not self.menu then
        self.menu = {}
        self.menuOpens = (self.menuOpens or 0) + 1
    elseif not open then
        self.menu = nil
    end
end
function ChatFrameMenuButton:IsVisible() return self.shown and ChatFrame1.shown end
local shiftDown = false
IsShiftKeyDown = function() return shiftDown end
-- A hardware click on a Suite button: the press first reaches Blizzard's menu
-- manager (GLOBAL_MOUSE_DOWN closes an open menu unless the pressed frame's
-- HandlesGlobalMouseEvent answers true, Blizzard_Menu/Menu.lua), then the
-- button's OnMouseDown, OnMouseUp and OnClick.
local function HardwareClick(button, mouseButton)
    local handled = button.HandlesGlobalMouseEvent and button:HandlesGlobalMouseEvent(mouseButton, "GLOBAL_MOUSE_DOWN")
    if not handled then ChatFrameMenuButton.menu = nil end
    local scripts = button.scripts or {}
    for _, script in ipairs({ "OnMouseDown", "OnMouseUp", "OnClick" }) do
        if scripts[script] then scripts[script](button, mouseButton) end
    end
end
ChatFrameToggleVoiceDeafenButton = Frame("ChatFrameToggleVoiceDeafenButton")
ChatFrameToggleVoiceMuteButton = Frame("ChatFrameToggleVoiceMuteButton")
BNGetNumFriends = function() return 5, 3 end
C_FriendList = { GetNumOnlineFriends = function() return 2 end }
SELECTED_CHAT_FRAME = ChatFrame1
GENERAL_CHAT_DOCK = Frame("GeneralDockManager")
GENERAL_CHAT_DOCK.selected = ChatFrame1
GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES = { ChatFrame1 }
CHAT_FRAMES = { "ChatFrame1" }
-- One built-in window, so later windows arrive through CHAT_FRAMES like
-- Blizzard's temporary windows. NUM_CHAT_WINDOWS is only a deprecation alias.
Constants = { ChatFrameConstants = { MaxChatWindows = 1 } }
-- Blizzard_GameTooltip builds GameTooltip at startup on both clients.
GameTooltip = Frame("GameTooltip")
GameTooltip.shown = false
function GameTooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
function GameTooltip:IsOwned(frame) return self.owner == frame end
local temporaryHook, selectHook, newWindowHook, tabAlphaHook, tabColorsHook, dockTabsHook
-- Blizzard's chrome fades (FCF_FadeInChatFrame, FCF_FadeOutChatFrame in
-- Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.lua) start UIFrameFadeIn
-- or UIFrameFadeOut on the tab, from its alpha toward its mouse-over or
-- no-mouse alpha. Live reads those from the tab's own fields; Forever reads
-- them from ChatFrameUtil.GetTabAlphas, side tables that only Forever's
-- FCFTab_UpdateAlpha fills (Shared/ChatFrameUtil.lua), so a field written on
-- the tab never reaches a Forever fade. The post-hooks run next, in the order
-- they were installed; UIFrameFade_OnUpdate then ends every fade still in
-- FADEFRAMES at its end alpha (Blizzard_SharedXMLBase/FrameUtil.lua).
local fadeInHooks, fadeOutHooks, FADEFRAMES = {}, {}, {}
local foreverTabAlphas = {}
UIFrameFadeRemoveFrame = function(frame) FADEFRAMES[frame] = nil end
local function ChromeFade(frame, hovered, client)
    local tab = _G[frame:GetName() .. "Tab"]
    local mouseOverAlpha, noMouseAlpha = tab.mouseOverAlpha, tab.noMouseAlpha
    if client == "forever" then mouseOverAlpha, noMouseAlpha = unpack(foreverTabAlphas[tab]) end
    FADEFRAMES[tab] = hovered and mouseOverAlpha or noMouseAlpha
    for _, hook in ipairs(hovered and fadeInHooks or fadeOutHooks) do hook(frame) end
    if FADEFRAMES[tab] then tab:SetAlpha(FADEFRAMES[tab]); FADEFRAMES[tab] = nil end
    return tab:GetAlpha()
end
FCF_OpenTemporaryWindow = function() end
FCF_OpenNewWindow = function() end
FCFDock_SelectWindow = function() end
FCFTab_UpdateAlpha = function() end
FCFTab_UpdateColors = function() end
FCFDock_UpdateTabs = function() end
IsInInstance = function() return false end
-- Blizzard_SharedXML's link registry (both clients); Chat registers msufurl once.
local linkHandlers = {}
LinkUtil = { RegisterLinkHandler = function(kind, handler)
    assert(not linkHandlers[kind], "a link handler was registered twice")
    linkHandlers[kind] = handler
end }
CHAT_FRAME_FADE_OUT_TIME = 2.0
S.RestoreCVar = function() end
-- Styling alone never hooks the message path; the opt-in idle fade adds a
-- post-hook on AddMessage and follows Blizzard's chrome fade.
local messageHooks = 0
hooksecurefunc = function(name, callback)
    if type(name) == "table" then
        assert(callback == "AddMessage", "chat hooked a native chat frame method other than AddMessage")
        messageHooks = messageHooks + 1
        return
    end
    assert(name == "FCF_OpenTemporaryWindow" or name == "FCF_OpenNewWindow"
        or name == "FCFDock_SelectWindow" or name == "FCFTab_UpdateAlpha"
        or name == "FCFTab_UpdateColors" or name == "FCFDock_UpdateTabs"
        or name == "FCF_FadeInChatFrame" or name == "FCF_FadeOutChatFrame",
        "chat touched the message path")
    if name == "FCF_OpenTemporaryWindow" then temporaryHook = callback
    elseif name == "FCF_OpenNewWindow" then newWindowHook = callback
    elseif name == "FCFTab_UpdateAlpha" then tabAlphaHook = callback
    elseif name == "FCFTab_UpdateColors" then tabColorsHook = callback
    elseif name == "FCFDock_SelectWindow" then selectHook = callback
    elseif name == "FCFDock_UpdateTabs" then dockTabsHook = callback
    elseif name == "FCF_FadeInChatFrame" then fadeInHooks[#fadeInHooks + 1] = callback
    elseif name == "FCF_FadeOutChatFrame" then fadeOutHooks[#fadeOutHooks + 1] = callback end
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
local chatDefaults, catalogNS = Support.CatalogDefaults(root, "chat")
NS.ChatBubbleSources = catalogNS.ChatBubbleSources
local CHAT_FILES = { "Bootstrap.lua", "Shared.lua", "Appearance.lua", "MinimalChrome.lua", "FadeAnimation.lua", "Unread.lua", "Sidebar.lua", "Copy.lua", "History.lua", "Fade.lua",
    "Messages.lua", "Window.lua", "Bubbles.lua", "Controller.lua" }
local tocFiles = Support.TocFiles(root, "MSUF_Suite_Chat")
assert(#tocFiles == #CHAT_FILES, "the Chat TOC must list " .. #CHAT_FILES .. " files")
for i = 1, #CHAT_FILES do
    assert(tocFiles[i] == CHAT_FILES[i], "Chat TOC order: expected " .. CHAT_FILES[i] .. " at " .. i)
end
-- The shared windows and copy dialog (MSUF_Suite_Modules/Dialogs.lua).
S.SetFont = S.SetFont or function(fontString, path, size, flags)
    fontString:SetFont(path or globalFont, size, flags or "")
    return flags
end
assert(loadfile(root .. "/MSUF_Suite_Modules/Dialogs.lua"))("MSUF_Suite_Modules", { Suite = S })
Support.Load(root, "MSUF_Suite_Chat", private, nil, { ["Bootstrap.lua"] = true })
local module = assert(S.module)
assert(module == private.Chat.M, "Controller.lua did not install the shared module table")
local ctx = { callbacks = {}, combat = {}, restored = 0, original = {}, properties = {} }
function ctx:Event(event, fn, options)
    self.callbacks[event], self.combat[event] = fn, Support.InCombatOption(options) or nil
end
function ctx:RemoveEvent(event) self.callbacks[event], self.combat[event] = nil, nil end
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
-- The plain-field writer chat tabs once used (Context:Field, since removed
-- from MSUF_Suite_Modules/Runtime.lua). It stays in the fixture so a return to
-- field writes is judged by what each client's fade does with them; the
-- module must leave it unused.
ctx.fields = {}
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
ctx.anchors = {}
function ctx:Anchor(frame, point, relative, relativePoint, x, y)
    self.anchors[frame] = self.anchors[frame] or { points = frame.points }
    frame:ClearAllPoints()
    frame:SetPoint(point, relative, relativePoint, x, y)
end
function ctx:RestorePoints(frame)
    local record = self.anchors[frame]
    if record then frame.points, self.anchors[frame] = record.points, nil end
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
    if lockdown then return end
    local record = self.original[frame] or {}
    self.original[frame] = record
    record[setter] = record[setter] or { before = { frame[getter](frame) } }
    frame[setter](frame, ...)
    record[setter].applied = { frame[getter](frame) }
end
function ctx:TextColor(frame, ...)
    if lockdown then
        local owned = self.original[frame] and self.original[frame].SetTextColor
        if owned then frame:SetTextColor(...); owned.applied = { ... } end
    else self:Tuple(frame, "GetTextColor", "SetTextColor", ...) end
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
-- The shipped context timers (MSUF_Suite_Modules/Timers.lua) on the stub.
NS.Dispatch = NS.Dispatch or S.Dispatch
module.context = Support.ModuleTimers(root, S, NS)("chat", module, ctx)
module.active = true
-- The catalog defaults, as the controller hands them over, plus this test's look.
module.config = {
    panelColor = "0a1220", panelAlpha = 74, borderColor = "41627a", borderAlpha = 78,
    borderSize = 1, accentColor = "57c7df", accentAlpha = 88, tabAccent = true,
    tabActiveColor = "f4f7fb", tabInactiveColor = "aab5c2",
    tabPanel = true, sidebarPanel = true, sidebarWidth = 28,
    tabHeight = 24, tabBorderSize = 0, tabIndividualPanels = false,
    tabActiveAlpha = 80, tabInactiveAlpha = 50,
    inputPanel = true, inputColor = "0a1522", inputAlpha = 86, padding = 4,
    fontSize = 15, tabFontSize = 0,
    font = "", tabFont = "", fontOutline = 1, fontRendering = 3, fontShadow = 1,
    copyMessages = false,
}
for key, value in pairs(chatDefaults) do
    if module.config[key] == nil then module.config[key] = value end
end
module:Enable()
-- Chat moves frames (a geometry module), so its window listeners wait for
-- the end of combat; the friend count is plain text and also updates in
-- combat (the context's allowCombat). The message and bubble contracts
-- check their own listeners.
assert(module.geometry == true, "Chat is no longer a geometry module")
for _, event in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
    "BN_FRIEND_ACCOUNT_OFFLINE", "BN_CONNECTED", "BN_DISCONNECTED" }) do
    assert(ctx.callbacks[event] and ctx.combat[event] == true, event .. " does not also run in combat")
end
for _, event in ipairs({ "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS", "ADDON_LOADED" }) do
    assert(ctx.callbacks[event] and ctx.combat[event] == nil, event .. " runs in combat")
end
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
assert(ChatFrame1.font[1] == globalFont, "default chat font did not inherit MSUF Fonts")
assert(ChatFrame1Tab.Text.font[1] == globalFont and ChatFrame1Tab.Text.font[2] == 12,
    "native chat tab title did not inherit MSUF font and Blizzard's size")
assert(ctx.callbacks.UPDATE_CHAT_WINDOWS and ctx.callbacks.UPDATE_FLOATING_CHAT_WINDOWS
    and temporaryHook and newWindowHook and selectHook and tabAlphaHook and tabColorsHook)
assert(not ctx.callbacks.CHAT_MSG_SAY and not ctx.callbacks.CHAT_MSG_CHANNEL)
assert(ChatFrame1.font[2] == 15)
assert(module.visuals[ChatFrame1].panel.shown and module.visuals[ChatFrame1].tabLine.shown)
assert(module.visuals[ChatFrame1].panel.owner == ChatFrame1
    and module.visuals[ChatFrame1].panel.points[1][5] == 0,
    "Suite chat body did not stay on the chat frame below its tabs")
AssertJoinedDockShell()
-- Blizzard's tab alphas feed UIFrameFade and its shared FADEFRAMES list
-- (FloatingChatFrame.lua; Forever keeps them in ChatFrameUtil side tables):
-- the Suite never writes them and holds the readable alpha after each fade.
-- Forever's FCFTab_UpdateAlpha gives the selected tab 1 and 0.4.
foreverTabAlphas[ChatFrame1Tab] = { 1, 0.4 }
assert(ChatFrame1Tab:GetAlpha() >= 0.8, "ordinary chat tabs were left unreadably dim")
assert(ChromeFade(ChatFrame1, false, "forever") == 0.8 and ChromeFade(ChatFrame1, true, "forever") == 1,
    "Forever's chrome fade (ChatFrameUtil side-table alphas) left the tab unreadably dim")
assert(ChromeFade(ChatFrame1, false) == 0.8 and ChromeFade(ChatFrame1, true) == 1
    and ChatFrame1Tab.noMouseAlpha == 0.4 and ChatFrame1Tab.mouseOverAlpha == 1 and next(ctx.fields) == nil,
    "Blizzard's chrome fade left the tab unreadably dim or its fade fields were written")
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
lockdown = true
tabColorsHook(ChatFrame1Tab, true)
lockdown = false
local activeR, activeG, activeB = S.RGB(module.config.tabActiveColor)
assert(sidebar.tabLabel == ChatFrame1Tab.Text and sidebar.tabLabel:GetText() == "General Chat"
    and not sidebar.tabOverlay and math.abs(sidebar.tabLabel.color[1] - activeR) < 0.001
    and math.abs(sidebar.tabLabel.color[2] - activeG) < 0.001
    and math.abs(sidebar.tabLabel.color[3] - activeB) < 0.001,
    "a renamed tab gained duplicate text or lost its configured color")
ChatFrame1Tab.Text:SetText("General")
module.config.tabFontSize = 18
module:Refresh()
assert(ChatFrame1Tab.Text.font[1] == globalFont and ChatFrame1Tab.Text.font[2] == 18
    and sidebar.tabLabel == ChatFrame1Tab.Text and sidebar.tabLabel:GetText() == "General",
    "tab size changed ownership or replaced Blizzard's native title")
module.config.tabFontSize = 0
module:Refresh()
assert(ChatFrame1Tab.Text.font[2] == 12, "tab size 0 did not follow Blizzard's tab size")
module.config.tabFont = "TestFont"
module:Refresh()
assert(ChatFrame1Tab.Text.font[1] == "Test.ttf" and ChatFrame1.font[1] == globalFont,
    "tab font choice changed message text or failed to style the native title")
module.config.tabFont = "__BLIZZARD_CHAT_FONT__"
module:Refresh()
assert(ChatFrame1Tab.Text.font[1] == "Fonts/FRIZQT__.TTF",
    "the Blizzard tab font choice did not restore its original face")
module.config.tabFont = ""
module:Refresh()
-- Numeric zero is truthy in Lua: the newly added border setting must not
-- activate separate 32px tab boxes over the original continuous dock strip.
assert(not sidebar.tabFill and not sidebar.tabEdges,
    "default chat styling gained individual tab boxes")
module.config.tabIndividualPanels = true
module.config.tabBorderSize = 1
module:Refresh()
assert(sidebar.tabFill.shown and sidebar.tabFill.height == 24
    and sidebar.tabFill.points[1][1] == "BOTTOMLEFT"
    and sidebar.tabFill.points[1][2] == ChatFrame1Tab
    and sidebar.tabFill.points[1][5] == -3
    and sidebar.tabEdges[1].points[1][2] == sidebar.tabFill,
    "opt-in tab panels escaped the Suite header row")
tabColorsHook(ChatFrame1Tab, false)
assert(sidebar.tabFill.color[4] == 0.5, "inactive tab opacity was lost")
tabColorsHook(ChatFrame1Tab, true)
assert(sidebar.tabFill.color[4] == 0.8, "active tab opacity was lost")
module.config.tabPanel = false
module:Refresh()
assert(not sidebar.tabFill.shown, "disabled tab strip kept its individual panel")
for _, edge in ipairs(sidebar.tabEdges) do assert(not edge.shown, "disabled tab strip kept its tab border") end
module.config.tabPanel = true
module.config.tabIndividualPanels = false
module.config.tabBorderSize = 0
module:Refresh()
assert(not sidebar.tabFill.shown, "turning individual tab panels off left a box")
for _, edge in ipairs(sidebar.tabEdges) do assert(not edge.shown, "turning individual panels off left a border") end
local textureCount = #textures
module.config.accentAlpha = 0
module:Refresh()
assert(not sidebar.tabLine.shown and not sidebar.headerRule.shown,
    "zero accent opacity left the chat accent visible")
module.config.accentAlpha = 35
module:Refresh()
assert(sidebar.tabLine.shown and sidebar.headerRule.shown
    and math.abs(sidebar.tabLine.color[4] - 0.35) < 0.001
    and math.abs(sidebar.headerRule.color[4] - 0.35) < 0.001
    and sidebar.headerRule.height == 2
    and #textures == textureCount,
    "accent opacity did not update the underline and full-width rule in place")
module.config.accentAlpha = 88
module:Refresh()
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
    -- 12.x item links carry the named quality token |cnIQ<quality>:.
    "|cffaaaaaa[15:37]|r You receive loot: |cnIQ4:|Hitem:246771::::::::80:::::|h[Radiant Item]|h|r.",
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
sidebar.buttons[2].button.scripts.OnLeave(sidebar.buttons[2].button)
assert(GameTooltip.shown, "leaving another button hid the Copy button's tooltip")
sidebar.copyButton.scripts.OnLeave(sidebar.copyButton)
assert(not GameTooltip.shown, "leaving the Copy button kept its tooltip")
sidebar.copyButton:Click("LeftButton")
assert(module.copyDialog and module.copyDialog.shown and module.copyDialog.rows[1].message == "[15:39] [Mapko]: Good point!"
    and module.copyDialog.rows[2].message == "[15:38] First message"
    and module.copyDialog.rows[3].message == "[15:37] You receive loot: [Radiant Item]."
    and not module.copyDialog.rows[4].shown, "copy chooser did not show recent public chat lines as plain text")
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
-- S18-K4: a panel icon clicked without its secure delegate (the pointer
-- rested on it since before combat ended) never clicks Blizzard's button
-- from the Suite's code: the click attaches the delegate, and the delegate's
-- click opens the panel from secure code.
for index, native in ipairs({ QuickJoinToastButton, ChatFrameChannelButton, TextToSpeechButton }) do
    local icon = sidebar.buttons[index].button
    icon:Click("LeftButton")
    local attached = module.panelDelegate
    assert(not native.clicks and attached and attached.shown and attached.owner == icon
        and attached:GetAttribute("clickbutton") == native,
        "a panel icon clicked without its delegate clicked Blizzard's button from the Suite's code")
    SecureClick(attached, "LeftButton")
    assert(native.clicks == 1 and panelOpens[#panelOpens].button == native and panelOpens[#panelOpens].secure,
        "the attached delegate did not open the panel from secure code")
end
module.panelDelegate.scripts.OnLeave(module.panelDelegate)
sidebar.buttons[5].button:Click("LeftButton")
assert(ChatFrame1.scrolled == 1, "sidebar controls did not retain their actions")
-- The chat menu icon opens Blizzard's chat menu and a second click closes it;
-- Shift (the icon's drag) and other mouse buttons leave it alone, as on
-- Blizzard's own button.
local menuIcon = sidebar.buttons[4].button
HardwareClick(menuIcon, "LeftButton")
assert(ChatFrameMenuButton:IsMenuOpen() and ChatFrameMenuButton.menuOpens == 1,
    "the sidebar's chat menu icon did not open Blizzard's chat menu")
HardwareClick(menuIcon, "LeftButton")
assert(not ChatFrameMenuButton:IsMenuOpen() and ChatFrameMenuButton.menuOpens == 1,
    "a second click on the chat menu icon did not close the menu")
shiftDown = true
HardwareClick(menuIcon, "LeftButton")
shiftDown = false
HardwareClick(menuIcon, "RightButton")
assert(not ChatFrameMenuButton:IsMenuOpen() and ChatFrameMenuButton.menuOpens == 1,
    "a Shift press or another mouse button opened the chat menu")
-- Another docked tab hides ChatFrame1 and its menu button: Blizzard would
-- close the menu at once, so the icon does not open it.
ChatFrame1:Hide()
HardwareClick(menuIcon, "LeftButton")
ChatFrame1:Show()
assert(not ChatFrameMenuButton:IsMenuOpen() and ChatFrameMenuButton.menuOpens == 1,
    "the chat menu opened for a hidden Blizzard menu button")
-- Under WoW Forever's Gamepad UI the menu, opened from the Suite's call,
-- would run MenuProxy.OnShow's focus code tainted: the icon opens nothing.
InputUtil = { IsGamepadUIEnabled = function() return true end }
HardwareClick(menuIcon, "LeftButton")
InputUtil = nil
assert(not ChatFrameMenuButton:IsMenuOpen() and ChatFrameMenuButton.menuOpens == 1,
    "the chat menu icon opened Blizzard's menu from the Suite's call under the Gamepad UI")
-- Hovering a sidebar button lights its glyph in the accent color and names it.
local channels = sidebar.buttons[2]
channels.button.scripts.OnEnter(channels.button)
assert(GameTooltip.owner == channels.button and GameTooltip.text == "Channels and voice" and GameTooltip.shown
    and channels.glyph.color[4] == 1 and channels.highlight.color[4] == 0.2,
    "sidebar hover did not show the button's tooltip and highlight")
channels.button.scripts.OnLeave(channels.button)
assert(not GameTooltip.shown and channels.glyph.color[4] == 0.94 and channels.highlight.color[4] == 0,
    "leaving a sidebar button kept its tooltip or highlight")
-- The panel icons (Friends, Channels, Text to speech) open Blizzard panels
-- through ShowUIPanel. Out of combat the icon under the pointer borrows one
-- secure delegate that clicks Blizzard's button from secure code; it keeps
-- the icon's hover look and tooltip and passes Shift-drags on.
panelOpens = {}
local friendsIcon = sidebar.buttons[1].button
friendsIcon.scripts.OnEnter(friendsIcon)
local delegate = module.panelDelegate
assert(delegate and delegate.template == "SecureActionButtonTemplate" and delegate.shown
    and delegate.owner == friendsIcon and delegate:GetAttribute("clickbutton") == QuickJoinToastButton
    and delegate:GetAttribute("useOnKeyDown") == false and delegate.parent == UIParent
    and delegate.level > friendsIcon:GetFrameLevel() and delegate.points[1][2] == friendsIcon,
    "hovering the Friends icon out of combat did not borrow the secure delegate")
assert(stateDrivers[delegate] and stateDrivers[delegate].values == "[combat] hide",
    "the secure delegate has no combat state driver")
assert(ctx.callbacks.PLAYER_REGEN_DISABLED and ctx.combat.PLAYER_REGEN_DISABLED == true,
    "the secure delegate is not let go at the start of combat")
delegate.mouseOver = true
friendsIcon.scripts.OnLeave(friendsIcon)
assert(friendsIcon.hovered and GameTooltip.shown and GameTooltip.owner == friendsIcon,
    "moving onto the secure delegate dropped the icon's hover look or tooltip")
local opens = #panelOpens
SecureClick(delegate, "LeftButton")
assert(#panelOpens == opens + 1 and panelOpens[#panelOpens].button == QuickJoinToastButton
    and panelOpens[#panelOpens].secure, "the Friends icon did not open Blizzard's panel from secure code")
shiftDown = true
delegate.scripts.OnDragStart(delegate)
assert(friendsIcon.moving and friendsIcon.dragging, "a Shift-drag on the delegate did not move the icon")
local saved = {}
S.CommitEditPosition = function(_, values)
    if lockdown then return false end
    for key, value in pairs(values) do saved[key] = value end
end
S.SetMany = function(...)
    if inCombat then return false end
    return S.CommitEditPosition(...)
end
friendsIcon.GetCenter = function() return 10, 20 end
sidebar.sidebarFrame.GetCenter = function() return 4, 6 end
inCombat = true
delegate.scripts.OnDragStop(delegate)
inCombat = false
shiftDown = false
assert(not friendsIcon.moving and saved.sidebarButton1X == 6 and saved.sidebarButton1Y == 14,
    "a Shift-drag through the delegate did not save the icon's place")
delegate.mouseOver = false
delegate.scripts.OnLeave(delegate)
assert(not delegate.shown and #delegate.points == 0 and not delegate.owner and not ctx.callbacks.PLAYER_REGEN_DISABLED
    and not friendsIcon.hovered and not GameTooltip.shown,
    "leaving the delegate did not let it go and end the icon's hover")
-- PLAYER_REGEN_DISABLED comes before the lockdown: the delegate lets go of
-- the sidebar then, and a panel icon clicked in combat refuses with the
-- restricted notice instead of calling ShowUIPanel from tainted code.
local channelsIcon = sidebar.buttons[2].button
channelsIcon.scripts.OnEnter(channelsIcon)
assert(delegate.shown and delegate.owner == channelsIcon
    and delegate:GetAttribute("clickbutton") == ChatFrameChannelButton, "the delegate did not move to Channels")
inCombat = true
ctx.callbacks.PLAYER_REGEN_DISABLED(module, "PLAYER_REGEN_DISABLED")
assert(not delegate.shown and #delegate.points == 0 and not delegate.owner,
    "the start of combat left the secure delegate on the sidebar")
lockdown = true
channelsIcon.scripts.OnEnter(channelsIcon)
assert(not delegate.shown and not delegate.owner, "the secure delegate was attached in combat")
local nativeClicks, printedCount = ChatFrameChannelButton.clicks, #printed
for _, index in ipairs({ 1, 2, 3 }) do
    local icon = sidebar.buttons[index].button
    icon.scripts.OnClick(icon, "LeftButton")
end
assert(ChatFrameChannelButton.clicks == nativeClicks and #panelOpens == opens + 1
    and #printed == printedCount + 3 and printed[#printed] == NS.RestrictedNotice(),
    "a panel icon clicked in combat called Blizzard's panel from tainted code")
channelsIcon.scripts.OnLeave(channelsIcon)
inCombat, lockdown = false, false
-- KS-3: a plain icon (no delegate) dragged across the combat start keeps
-- its new place: PLAYER_REGEN_DISABLED, before the lockdown, ends the drag
-- and saves it; the release in combat changes nothing.
local scrollIcon = sidebar.buttons[5].button
shiftDown = true
scrollIcon.scripts.OnDragStart(scrollIcon)
shiftDown = false
assert(scrollIcon.moving and ctx.callbacks.PLAYER_REGEN_DISABLED, "a plain icon drag does not watch the combat start")
scrollIcon.GetCenter = function() return 30, 40 end
inCombat = true
ctx.callbacks.PLAYER_REGEN_DISABLED(module, "PLAYER_REGEN_DISABLED")
lockdown = true
scrollIcon.scripts.OnDragStop(scrollIcon)
assert(not scrollIcon.moving and saved.sidebarButton5X == 26 and saved.sidebarButton5Y == 34
    and saved.sidebarButton5Moved == true, "a plain icon dragged across the combat start lost its new place")
inCombat, lockdown = false, false
-- The icon still under the pointer gets its delegate back after combat.
channelsIcon.scripts.OnEnter(channelsIcon)
inCombat = true
ctx.callbacks.PLAYER_REGEN_DISABLED(module, "PLAYER_REGEN_DISABLED")
assert(not delegate.owner, "combat kept the delegate on the sidebar")
inCombat = false
channelsIcon.mouseOver = true
ctx.callbacks.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(delegate.shown and delegate.owner == channelsIcon, "the hovered icon did not get its delegate back after combat")
channelsIcon.mouseOver = false
delegate.mouseOver = false
delegate.scripts.OnLeave(delegate)
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
module.config.font, module.config.fontOutline = "__BLIZZARD_CHAT_FONT__", 1
module.config.fontRendering, module.config.fontShadow = 1, 1
module:Refresh()
assert(ChatFrame1.font[1] == "Fonts/FRIZQT__.TTF" and ChatFrame1.font[2] == 16 and ChatFrame1.font[3] == ""
    and ChatFrame1.shadowColor[4] == 0, "chat text ownership did not restore Blizzard's font and size")
module.config.font = ""
globalFont = "MSUF-Changed.ttf"
module:Refresh()
assert(ChatFrame1.font[1] == globalFont and ChatFrame1.font[2] == 16,
    "MSUF's changed global font did not update chat while keeping Blizzard's chat size")
assert(ChatFrame1Tab.Text.font[1] == globalFont and ChatFrame1Tab.Text.font[2] == 12,
    "MSUF's changed global font did not update the native tab title")
ChatFrame2 = Frame("ChatFrame2")
ChatFrame2.isDocked = 1
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
-- Blizzard's native title without copying its text. Temporary windows are
-- frames past the built-in ones (ChatFrame2 is always the combat log).
ChatFrame11 = Frame("ChatFrame11")
ChatFrame11.isDocked = 1
ChatFrame11.editBox = Frame("ChatFrame11EditBox")
ChatFrame11Tab = Frame("ChatFrame11Tab")
ChatFrame11Tab.Left = Texture()
ChatFrame11Tab.Text = ChatFrame11Tab:CreateFontString()
ChatFrame11.chatType = "WHISPER"
ChatFrame11.isTemporary = true
ChatFrame11Tab.Text:SetText("secret")
CHAT_FRAMES[11] = "ChatFrame11"
temporaryHook()
assert(ChatFrame11Tab.Text.value == "secret" and ChatFrame11Tab.Text.alpha == 1
    and ChatFrame11Tab.Left.alpha == 0
    and not module.visuals[ChatFrame11].tabOverlay,
    "a secret whisper target lost Blizzard's native title")
ChatFrame11.chatType = "BN_WHISPER"
temporaryHook()
assert(ChatFrame11Tab.Text.alpha == 1 and not module.visuals[ChatFrame11].tabOverlay,
    "a Battle.net whisper lost Blizzard's visible native tab")
-- Blizzard reuses a closed temporary window for the next conversation.
ChatFrame11.chatType = "WHISPER"
ChatFrame11Tab.Text:SetText("Mapko")
temporaryHook()
assert(module.visuals[ChatFrame11].tabLabel.value == "Mapko"
    and ChatFrame11Tab.Text.alpha == 1 and ChatFrame11Tab.Left.alpha == 0
    and not module.visuals[ChatFrame11].tabOverlay,
    "a reused whisper tab kept its previous title")
CHAT_FRAMES[11] = nil
assert(module.visuals[ChatFrame2].tabLabel.value == "Combat Log"
    and ChatFrame2Tab.Text.alpha == 1 and ChatFrame2Tab.Left.alpha == 0,
    "the combat log tab lost Blizzard's native title")
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
ChatFrame3.isDocked = 1
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
-- tabGap spaces the docked tabs of each row after Blizzard laid them out.
GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES = { ChatFrame1, ChatFrame2, ChatFrame3 }
module.config.tabGap = 6
module:Refresh()
local gapPoint = ChatFrame2Tab.points and ChatFrame2Tab.points[1]
assert(gapPoint and gapPoint[1] == "LEFT" and gapPoint[2] == ChatFrame1Tab and gapPoint[3] == "RIGHT"
    and gapPoint[4] == 7 and not ctx.anchors[ChatFrame3Tab] and not ctx.anchors[ChatFrame1Tab],
    "docked tabs did not keep the chosen gap within their row")
module.config.tabGap = 0
module:Refresh()
assert(not ctx.anchors[ChatFrame2Tab], "turning the tab gap off kept the moved tab")
-- Blizzard stores isDocked as 1 or nil (FCFDock_AddChatFrame and
-- FCFDock_RemoveChatFrame); a floating window's tab is always selected
-- (FCFTab_UpdateColors(tab, not isDocked or ...), FloatingChatFrame.lua).
ChatFrame3.isDocked = nil
GENERAL_CHAT_DOCK.selected, SELECTED_CHAT_FRAME = ChatFrame1, ChatFrame1
module:Refresh()
assert(module.visuals[ChatFrame3].tabLine.shown and module.visuals[ChatFrame1].tabLine.shown
    and not module.visuals[ChatFrame2].tabLine.shown,
    "a floating chat window's tab was painted as an unselected docked tab")
ChatFrame3.isDocked = 1
GENERAL_CHAT_DOCK.selected, SELECTED_CHAT_FRAME = ChatFrame3, ChatFrame2
module:Refresh()
-- tabPadding widens each tab to its title plus the padding on both sides.
-- Blizzard's FCFDock_UpdateTabs sizes the docked tabs again on every dock
-- layout, a tab click included (PanelTemplates_TabResize: tab:SetWidth); the
-- padded width must come back after it, and in combat once combat ends.
local nativeTabWidth = ChatFrame1Tab:GetWidth()
module.config.tabPadding = 6
module:Refresh()
local function Padded(tab) return tab.Text:GetUnboundedStringWidth() + 12 end
assert(ChatFrame1Tab:GetWidth() == Padded(ChatFrame1Tab) and ChatFrame3Tab:GetWidth() == Padded(ChatFrame3Tab),
    "tab text padding did not widen the tabs")
ChatFrame1Tab:SetWidth(40)
ChatFrame3Tab:SetWidth(40)
dockTabsHook(GENERAL_CHAT_DOCK)
assert(ChatFrame1Tab:GetWidth() == Padded(ChatFrame1Tab) and ChatFrame3Tab:GetWidth() == Padded(ChatFrame3Tab),
    "Blizzard's dock layout (a tab click) dropped the tab text padding")
local queued, queue = {}, S.Queue
S.Queue = function(id) queued[#queued + 1] = id end
lockdown = true
ChatFrame1Tab:SetWidth(40)
dockTabsHook(GENERAL_CHAT_DOCK)
lockdown = false
S.Queue = queue
assert(queued[1] == "chat" and #queued == 1, "a dock layout in combat did not bring the tab text padding back after combat")
module.config.tabPadding = 0
module:Refresh()
assert(ChatFrame1Tab:GetWidth() == nativeTabWidth, "turning tab text padding off kept the padded width")
dockTabsHook(GENERAL_CHAT_DOCK)
assert(ChatFrame1Tab:GetWidth() == nativeTabWidth, "Blizzard's dock layout padded a tab with padding off")
-- An in-combat dock layout re-anchors every docked tab 1 px apart
-- (FCFDock_UpdateTabs); a tab gap without padding comes back after combat.
module.config.tabGap = 6
module:Refresh()
queued, queue = {}, S.Queue
S.Queue = function(id) queued[#queued + 1] = id end
lockdown = true
dockTabsHook(GENERAL_CHAT_DOCK)
lockdown = false
S.Queue = queue
assert(queued[1] == "chat" and #queued == 1, "a dock layout in combat dropped the tab gap until a later dock update")
module.config.tabGap = 0
module:Refresh()
-- A chat window that fails to style is reported; the later windows are styled.
assert(#reports == 0, "chat styling raised: " .. tostring(reports[1]))
ChatFrame4 = Frame("ChatFrame4")
ChatFrame4.isDocked = 1
ChatFrame4.isTemporary = true
ChatFrame4.chatType = "WHISPER"
ChatFrame4.editBox = Frame("ChatFrame4EditBox")
ChatFrame4Tab = Frame("ChatFrame4Tab")
ChatFrame4Tab.Left = Texture()
ChatFrame4Tab.Text = ChatFrame4Tab:CreateFontString()
ChatFrame4Tab.Text:SetText("secret")
ChatFrame4Tab.noMouseAlpha = 0.2
ChatFrame4Tab.mouseOverAlpha = 0.6
-- Forever's FCFTab_UpdateAlpha gives an unselected tab 0.6 and 0.2.
foreverTabAlphas[ChatFrame4Tab] = { 0.6, 0.2 }
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
assert(ChatFrame4Tab.noMouseAlpha == 0.2 and ChatFrame4Tab.mouseOverAlpha == 0.6
    and ChatFrame4Tab:GetAlpha() == 0.8,
    "an idle whisper tab remained too dark to find")
assert(ChromeFade(ChatFrame4, true, "forever") == 1 and ChromeFade(ChatFrame4, false, "forever") == 0.8,
    "Forever's chrome fade (ChatFrameUtil side-table alphas) dimmed the whisper tab")
assert(ChromeFade(ChatFrame4, true) == 1 and ChromeFade(ChatFrame4, false) == 0.8
    and ChatFrame4Tab.noMouseAlpha == 0.2 and ChatFrame4Tab.mouseOverAlpha == 0.6,
    "Blizzard's chrome fade dimmed the whisper tab or its fade fields were written")
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
assert(ChatFrame4Tab.noMouseAlpha == 0.2 and ChatFrame4Tab:GetAlpha() == 0.8,
    "Blizzard's tab update dimmed the whisper again")
assert(messageHooks == 0, "chat styling without message tools hooked the message path")
-- An idle-faded window keeps its faded tab when Blizzard updates the tab's
-- alpha; turning the fade off hands back the window and the Suite minimum.
local fadeTimers = {}
GetTime = function() return 0 end
C_Timer = { After = function(_, callback) fadeTimers[#fadeTimers + 1] = callback end }
module.config.idleSeconds, module.config.idleAlpha = 5, 20
module:Refresh()
GetTime = function() return 10 end
for _, callback in ipairs(fadeTimers) do callback() end
assert(math.abs(ChatFrame4Tab:GetAlpha() - 0.2) < 0.001 and math.abs(ChatFrame4:GetAlpha() - 0.2) < 0.001,
    "the idle fade did not fade the window and its tab")
-- The input line is a child of the window and fades with it, never twice.
assert(ChatFrame4.editBox:GetAlpha() == 1, "the idle fade faded the input line on its own")
assert(ChatFrame4.editBox.hooks.OnEditFocusGained and ChatFrame4.editBox.hooks.OnEditFocusLost,
    "the idle fade does not follow the input line's focus")
tabAlphaHook(ChatFrame4)
assert(math.abs(ChatFrame4Tab:GetAlpha() - 0.2) < 0.001, "Blizzard's tab update undid the idle fade")
-- The sidebar sits on the selected whisper window (PlaceSidebar) and fades
-- with it: a line into the hidden primary window leaves it faded, a line
-- into the window it sits on wakes it.
local sidebarFrame = sidebar.sidebarFrame
assert(sidebarFrame.points[1][2] == ChatFrame4 and math.abs(sidebarFrame:GetAlpha() - 0.2) < 0.001,
    "the sidebar did not fade with the window it sits on")
private.Chat.ChatActivity(ChatFrame1)
assert(math.abs(sidebarFrame:GetAlpha() - 0.2) < 0.001,
    "a line into the hidden primary window woke the sidebar of the selected window")
private.Chat.ChatActivity(ChatFrame4)
assert(sidebarFrame:GetAlpha() == 1, "a line into the window the sidebar sits on left it faded")
-- A dock selection moves the sidebar, and its fade, to the selected window.
GENERAL_CHAT_DOCK.selected, SELECTED_CHAT_FRAME = ChatFrame3, ChatFrame3
selectHook()
GetTime = function() return 30 end
for _, callback in ipairs(fadeTimers) do callback() end
assert(sidebarFrame.points[1][2] == ChatFrame3 and math.abs(sidebarFrame:GetAlpha() - 0.2) < 0.001,
    "the sidebar did not fade with the newly selected window")
private.Chat.ChatActivity(ChatFrame4)
assert(math.abs(sidebarFrame:GetAlpha() - 0.2) < 0.001, "the previous window still woke the sidebar")
private.Chat.ChatActivity(ChatFrame3)
assert(sidebarFrame:GetAlpha() == 1, "the newly selected window did not wake the sidebar")
GENERAL_CHAT_DOCK.selected, SELECTED_CHAT_FRAME = ChatFrame4, ChatFrame4
selectHook()
module.config.idleSeconds = 0
module:Refresh()
assert(ChatFrame4Tab:GetAlpha() == 0.8 and ChatFrame4:GetAlpha() == 1, "turning the fade off kept the window faded")
local speechIcon = sidebar.buttons[3].button
speechIcon.scripts.OnEnter(speechIcon)
assert(module.panelDelegate.shown and module.panelDelegate:GetAttribute("clickbutton") == TextToSpeechButton,
    "the Text to speech icon did not borrow the secure delegate")
-- The controller (Suite.lua Stop) clears active before Disable.
module.active = false
module:Disable()
assert(not module.panelDelegate.shown and not module.panelDelegate.owner and not ctx.callbacks.PLAYER_REGEN_DISABLED,
    "disabling Chat left the secure delegate on the sidebar")
assert(ChatFrame4Tab.noMouseAlpha == 0.2 and ChatFrame4Tab.mouseOverAlpha == 0.6
    and ChatFrame4Tab:GetAlpha() == 0.2 and ChromeFade(ChatFrame4, true) == 0.6
    and ChromeFade(ChatFrame4, false) == 0.2 and ChromeFade(ChatFrame4, true, "forever") == 0.6
    and ChromeFade(ChatFrame4, false, "forever") == 0.2 and next(ctx.fields) == nil,
    "disabling Chat did not restore Blizzard's whisper-tab fading")
assert(not module.visuals[ChatFrame1].panel.shown and not module.visuals[ChatFrame2].panel.shown
    and not module.visuals[ChatFrame3].panel.shown and not module.dockStrip.shown)
assert(not module.visuals[ChatFrame1].input.shown)
assert(not module.visuals[ChatFrame1].sidebar.shown)
assert(not sidebar.sidebarFrame.shown and QuickJoinToastButton.alpha == 1 and QuickJoinToastButton.mouse)
assert(ChatFrame1Tab.Text.font[1] == "Fonts/FRIZQT__.TTF" and ChatFrame1Tab.Text.font[2] == 12,
    "disabling Chat did not restore Blizzard's native tab font")
assert(ChatFrame1.Background.shown and ChatFrame1TopLeftTexture.shown
    and ChatFrame1ButtonFrameBackground.shown,
    "disabling chat did not restore Blizzard chrome")
assert(ChatFrame1Tab.Left.alpha == 1 and ChatFrame1Tab.noMouseAlpha == 0.4
    and ChatFrame1Tab.Text.alpha == 1 and ChatFrame1EditBox.Left.alpha == 1
    and CombatLogQuickButtonFrame_CustomTexture.alpha == 1,
    "disabling chat did not restore Blizzard tab/input")
-- The real window painter must match Glass's compact, frameless layout.
-- Keep native message animation off in this chrome-only fixture.
local reportedBefore = #reports
local nativeHeightBeforeImm, nativeWidthBeforeImm = ChatFrame1Tab:GetHeight(), ChatFrame1Tab:GetWidth()
GENERAL_CHAT_DOCK.selected, SELECTED_CHAT_FRAME = ChatFrame1, ChatFrame1
for key, value in pairs(catalogNS.ChatLookPresets[7]) do module.config[key] = value end
module.config.idleSeconds, module.config.messageFading, module.config.coloredUnreadTabs = 0, false, false
module.active = true
module:Enable()
local minimal = module.visuals[ChatFrame1]
assert(not minimal.headerRule.shown, "minimal chat retained the full-width separator")
assert(minimal.tabLine.points[1][1] == "TOPLEFT" and minimal.tabLine.height == 1,
    "minimal selected-tab marker is not above its native tab")
assert(ChatFrame1Tab:GetHeight() == 20 and ChatFrame1Tab:GetWidth() == minimal.tabLabel:GetUnboundedStringWidth() + 30,
    "minimal native tabs are not compact")
assert(ChatFrame1Tab.Text.font[1] == "Fonts/FRIZQT__.TTF" and ChatFrame1.font[1] == "Fonts/FRIZQT__.TTF"
    and ChatFrame1.font[2] == 12, "Immersive retained the global condensed font")
assert(minimal.gradientLeft.alpha == 0 and module.dockStrip.alpha == 0, "idle chat retained its dark rectangle")
assert(module.dockStrip.gradient[3].a == 0 and minimal.gradientLeft.gradient[2].a == 0.4,
    "minimal background did not fade black from left to right")
ChromeFade(ChatFrame1, true, "forever")
assert(minimal.gradientLeft.alpha == 1 and module.dockStrip.alpha == 1, "hover did not reveal minimal art")
module:Refresh()
assert(minimal.gradientLeft.alpha == 1, "refresh lost the active hover")
ChromeFade(ChatFrame1, false, "forever")
assert(minimal.gradientLeft.alpha == 0 and module.dockStrip.alpha == 0, "pointer leave kept minimal art")
GENERAL_CHAT_DOCK.selected, SELECTED_CHAT_FRAME = ChatFrame3, ChatFrame3
selectHook()
local secondary = module.visuals[ChatFrame3]
foreverTabAlphas[ChatFrame3Tab] = { 1, 0.4 }
ChromeFade(ChatFrame3, true, "forever")
ChromeFade(ChatFrame1, false, "forever")
assert(secondary.gradientLeft.alpha == 1 and module.dockStrip.alpha == 1,
    "hover in the selected secondary window did not retain its dock background")
GENERAL_CHAT_DOCK.selected, SELECTED_CHAT_FRAME = ChatFrame1, ChatFrame1
selectHook()
assert(module.dockStrip.alpha == 0, "tab selection retained the old window's background")
ChromeFade(ChatFrame3, false, "forever")
for key, value in pairs(catalogNS.ChatLookPresets[2]) do module.config[key] = value end
module:Refresh()
assert(minimal.headerRule.shown and minimal.panel.alpha == 1 and module.dockStrip.alpha == 1,
    "normal look did not restore its panel and separator")
assert(ChatFrame1.font[1] == globalFont and ChatFrame1Tab.Text.font[1] == globalFont,
    "leaving Immersive retained its native font override")
assert(ChatFrame1Tab:GetHeight() == nativeHeightBeforeImm and ChatFrame1Tab:GetWidth() == nativeWidthBeforeImm,
    "normal preset did not restore pre-Immersive native dimensions")
assert(minimal.tabLine.points[1][1] == "BOTTOMLEFT" and minimal.tabLine.height == 2,
    "normal look retained the minimal tab marker")
assert(module.dockStrip.gradient[2].a == module.dockStrip.gradient[3].a
    and module.dockStrip.gradient[3].a == math.min(100, module.config.panelAlpha + 12) / 100,
    "normal look retained the transparent dock gradient")
module.active = false
module:Disable()
assert(#reports == reportedBefore, "minimal window lifecycle reported an error")
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
