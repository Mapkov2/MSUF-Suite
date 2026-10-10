-- Native chat display stays owned by Blizzard; only Suite art, alpha and
-- the documented message-fade setters are changed. No Lua animation tick.
local root = assert(arg[1])
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local secret = {}
local function Public(value) return not rawequal(value, secret) end
local function Finite(value)
    return Public(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function eq(actual, expected, label) assert(actual == expected, label or "unexpected value") end
local function Texture()
    local texture = { shown = true, points = {} }
    function texture:SetTexture(value) self.texture = value end
    function texture:SetColorTexture(...) self.color = { ... } end
    function texture:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function texture:ClearAllPoints() self.points = {} end
    function texture:SetWidth(value) self.width = value end
    function texture:SetHeight(value) self.height = value end
    function texture:SetAlpha(value) self.alpha = value end
    function texture:SetGradient(direction, left, right) self.gradient = { direction, left, right } end
    function texture:Show() self.shown = true end
    function texture:Hide() self.shown = false end
    return texture
end
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
local groups = {}
local function AnimationGroup(owner)
    local group = { owner = owner }
    function group:CreateAnimation(kind)
        eq(kind, "Alpha")
        local alpha = {}
        function alpha:SetFromAlpha(value) self.from = value end
        function alpha:SetToAlpha(value) self.to = value end
        function alpha:SetDuration(value) self.duration = value end
        function alpha:SetSmoothing(value) self.smoothing = value end
        self.alpha = alpha
        return alpha
    end
    function group:SetScript(kind, fn) eq(kind, "OnFinished"); self.finished = fn end
    function group:Play() self.playing = true end
    function group:Stop() self.playing = false end
    function group:Finish()
        assert(self.playing, "a stopped fade completed")
        self.playing = false
        self.finished()
    end
    groups[#groups + 1] = group
    return group
end
local function Frame(name)
    local frame = { name = name, alpha = 1, isDocked = true, fading = false, timeVisible = 60, duration = 5, hooks = {} }
    function frame:GetName() return self.name end
    function frame:GetAlpha() return self.alpha end
    function frame:SetAlpha(value) assert(Public(value)); self.alpha = value end
    function frame:CreateAnimationGroup() return AnimationGroup(self) end
    function frame:GetFading() return self.fading end
    function frame:SetFading(value) self.fading = value end
    function frame:GetTimeVisible() return self.timeVisible end
    function frame:SetTimeVisible(value) self.timeVisible = value end
    function frame:GetFadeDuration() return self.duration end
    function frame:SetFadeDuration(value) self.duration = value end
    function frame:HasFocus() return self.focus == true end
    function frame:HookScript(kind, fn)
        assert(not self.hooks[kind], "duplicate focus hook")
        assert(kind == "OnEditFocusGained" or kind == "OnEditFocusLost", "unexpected native script hook")
        self.hooks[kind] = fn
    end
    frame.editBox = { focus = false, hooks = {}, HasFocus = frame.HasFocus, HookScript = frame.HookScript }
    return frame
end
ChatFrame1, ChatFrame2, ChatFrame3 = Frame("ChatFrame1"), Frame("ChatFrame2"), Frame("ChatFrame3")
ChatFrame1Tab, ChatFrame2Tab, ChatFrame3Tab = Frame("ChatFrame1Tab"), Frame("ChatFrame2Tab"), Frame("ChatFrame3Tab")
GENERAL_CHAT_DOCK = { selected = ChatFrame1 }
CHAT_FRAME_FADE_OUT_TIME = 2
ChatTypeInfo = { GUILD = { id = 4, r = 0.2, g = 1, b = 0.2 }, WHISPER = { id = 7, r = 1, g = 0.5, b = 1 } }
local hooks = {}
hooksecurefunc = function(name, fn)
    assert(not hooks[name], "duplicate fade hook")
    hooks[name] = fn
end
local timers = {}
local S = { Public = Public, Finite = Finite, CreateTexture = Texture, RGB = function() return 0.1, 0.2, 0.3 end }
local P = { Suite = S }
for _, file in ipairs({ "Shared.lua", "Appearance.lua", "MinimalChrome.lua", "FadeAnimation.lua", "Unread.lua", "Fade.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Chat/" .. file))("MSUF_Suite_Chat", P)
end
local Chat, module = P.Chat, P.Chat.M
local config, catalog = Support.CatalogDefaults(root, "chat")
eq(config.look, catalog.Client.isForever and 3 or 2, "Immersive silently replaced the existing default")
eq(config.panelGradient, false)
eq(config.minimalChrome, false)
eq(config.messageFading, false)
eq(config.coloredUnreadTabs, false)
eq(catalog.SuiteCatalog.chat.rules.look.choices[7], "Immersive", "preset is not selectable")
local preset = assert(catalog.ChatLookPresets[7])
assert(preset.panelGradient and preset.messageFading and preset.coloredUnreadTabs and preset.idleSeconds > 0)
eq(preset.sidebarPanel, false)
eq(preset.minimalChrome, true)
eq(preset.tabHeight, 20)
eq(preset.tabPadding, 15)
eq(preset.fontSize, 12)
eq(preset.font, "__BLIZZARD_CHAT_FONT__")
for index, other in pairs(catalog.ChatLookPresets) do
    if index ~= 7 then
        eq(other.idleSeconds, 0, "leaving Immersive retained its whole-window fade")
        eq(other.messageFading, false)
        eq(other.minimalChrome, false, "normal preset retained hover-only chrome")
    end
end
module.config, module.active = config, true
module.context = {
    After = function(_, seconds, fn) timers[fn] = seconds end,
    Cancel = function(_, fn) timers[fn] = nil end,
}
Chat.TabSelected = function(frame, _, dock) return not frame.isDocked or frame == dock end
local visual = { frame = ChatFrame3 }
module.visuals[ChatFrame3] = visual
-- Settings, focus and hover use native setters even with idle fade disabled.
config.messageFading, config.messageTimeVisible, config.messageFadeDuration = true, 20, 3
Chat.ApplyMessageFade(visual, config)
eq(ChatFrame3.fading, true)
eq(ChatFrame3.timeVisible, 20)
eq(ChatFrame3.duration, 3)
Chat.ApplyInactivity(module, visual)
ChatFrame3.editBox.hooks.OnEditFocusGained(ChatFrame3.editBox)
eq(ChatFrame3.fading, false, "typing did not keep messages visible")
ChatFrame3.editBox.hooks.OnEditFocusLost(ChatFrame3.editBox)
eq(ChatFrame3.fading, true)
hooks.FCF_FadeInChatFrame(ChatFrame3)
eq(ChatFrame3.fading, false, "hover did not keep messages visible")
Chat.ApplyMessageFade(visual, config)
Chat.ApplyInactivity(module, visual)
eq(ChatFrame3.fading, false, "refresh enabled fading under the pointer")
eq(visual.hovered, true, "idle-only release discarded message hover state")
ChatFrame3.editBox.hooks.OnEditFocusLost(ChatFrame3.editBox)
eq(ChatFrame3.fading, false, "focus release lost the ongoing hover")
hooks.FCF_FadeOutChatFrame(ChatFrame3)
eq(ChatFrame3.fading, true)
ChatFrame3.timeVisible = 33 -- another addon took this property
Chat.ReleaseMessageFade(visual)
eq(ChatFrame3.fading, false, "native fading was not restored")
eq(ChatFrame3.timeVisible, 33, "restoration overwrote a foreign setting")
eq(ChatFrame3.duration, 5)
Chat.ApplyMessageFade(visual, config)
ChatFrame3.timeVisible = 45
Chat.ApplyMessageFade(visual, config)
eq(ChatFrame3.timeVisible, 20)
Chat.ReleaseMessageFade(visual)
eq(ChatFrame3.timeVisible, 45, "refresh discarded the later native-setting owner")
local combatLog = { frame = ChatFrame2 }
Chat.ApplyMessageFade(combatLog, config)
eq(combatLog.nativeFadeBefore, nil, "the Combat Log's display was taken over")
-- The background uses two bounded textures and restores the flat surface.
local panel = Texture()
config.panelGradient = true
Chat.PaintGradient(visual, panel, config)
assert(not panel.shown and visual.gradientLeft.shown and visual.gradientRight.shown)
eq(visual.gradientLeft.gradient[2].a, 0)
eq(visual.gradientLeft.gradient[3].a, config.panelAlpha / 100)
eq(visual.gradientRight.gradient[3].a, 0)
local left, right = visual.gradientLeft, visual.gradientRight
Chat.PaintGradient(visual, panel, config)
eq(visual.gradientLeft, left, "repaint allocated another gradient")
config.panelGradient = false
Chat.PaintGradient(visual, panel, config)
assert(not left.shown and not right.shown)
-- Minimal chrome has no persistent dark box: mouse/focus reveal our art,
-- while ordinary message delivery alone leaves the game visible behind it.
config.minimalChrome, config.panelGradient, config.messageFading = true, true, false
visual.panel = panel
Chat.ApplyMessageFade(visual, config)
Chat.ApplyInactivity(module, visual)
Chat.PaintGradient(visual, panel, config)
eq(left.gradient[2].a, config.panelAlpha / 100, "Glass left margin was transparent")
eq(left.width, 50)
eq(right.gradient[3].a, 0)
Chat.UpdateMinimalChrome(visual)
eq(left.alpha, 0, "minimal background stayed visible outside chat")
Chat.ChatActivity(ChatFrame3)
eq(left.alpha, 0, "a new line revealed an empty background box")
hooks.FCF_FadeInChatFrame(ChatFrame3)
eq(left.alpha, 1, "hover did not reveal the background")
Chat.ApplyInactivity(module, visual)
Chat.UpdateMinimalChrome(visual)
eq(left.alpha, 1, "idle-only refresh lost minimal hover")
ChatFrame3.editBox.hooks.OnEditFocusLost(ChatFrame3.editBox)
eq(left.alpha, 1, "blur hid the background while still hovered")
hooks.FCF_FadeOutChatFrame(ChatFrame3)
eq(left.alpha, 0)
ChatFrame3.editBox.hooks.OnEditFocusGained(ChatFrame3.editBox)
eq(left.alpha, 1, "typing did not reveal the input's background")
ChatFrame3.editBox.hooks.OnEditFocusLost(ChatFrame3.editBox)
eq(left.alpha, 0)
-- The one dock background follows the selected window, including focus in
-- another docked chat and refreshes of the hidden primary window.
module.dockStrip = Texture()
module.visuals[ChatFrame1] = { frame = ChatFrame1 }
GENERAL_CHAT_DOCK.selected = ChatFrame3
ChatFrame3.editBox.focus = true
ChatFrame3.editBox.hooks.OnEditFocusGained(ChatFrame3.editBox)
eq(module.dockStrip.alpha, 1, "typing in a selected secondary chat did not reveal the dock")
Chat.UpdateMinimalChrome(module.visuals[ChatFrame1])
eq(module.dockStrip.alpha, 1, "primary refresh hid the focused secondary dock")
ChatFrame3.editBox.focus = false
ChatFrame3.editBox.hooks.OnEditFocusLost(ChatFrame3.editBox)
eq(module.dockStrip.alpha, 0, "secondary blur kept the shared dock visible")
hooks.FCF_FadeInChatFrame(ChatFrame3)
hooks.FCF_FadeOutChatFrame(ChatFrame1)
eq(module.dockStrip.alpha, 1, "primary mouse leave hid the hovered secondary dock")
GENERAL_CHAT_DOCK.selected = ChatFrame1
Chat.UpdateMinimalChrome(module.visuals[ChatFrame1])
eq(module.dockStrip.alpha, 0, "dock selection retained another window's hover")
hooks.FCF_FadeOutChatFrame(ChatFrame3)
local marker = Texture()
Chat.PlaceTabMarker(marker, ChatFrame3Tab, config)
eq(marker.points[1][1], "TOPLEFT", "minimal selected marker stayed below the tab")
eq(marker.height, 1)
config.minimalChrome = false
Chat.PaintGradient(visual, panel, config)
Chat.UpdateMinimalChrome(visual)
eq(left.alpha, 1, "normal style did not restore background visibility")
eq(left.gradient[2].a, 0, "normal style retained the asymmetric gradient")
eq(left.points[2][1], "BOTTOMRIGHT", "normal gradient retained minimal geometry")
Chat.PlaceTabMarker(marker, ChatFrame3Tab, config)
eq(marker.points[1][1], "BOTTOMLEFT")
eq(marker.height, 2)
-- Smooth idle fade completes through native groups, and focus interrupts it.
config.idleSeconds, config.idleAlpha, config.idleFadeDuration = 12, 0, 0.35
Chat.ApplyInactivity(module, visual)
visual.fadeCallback()
eq(ChatFrame3:GetAlpha(), 1, "idle alpha jumped before its animation")
eq(#groups, 2, "more than one native group was allocated per fade part")
assert(groups[1].playing and groups[2].playing)
for _, group in ipairs(groups) do group:Finish() end
eq(ChatFrame3:GetAlpha(), 0, "finished idle fade did not commit its final alpha")
Chat.ChatActivity(ChatFrame3)
eq(ChatFrame3:GetAlpha(), 1, "new activity did not restore visibility")
visual.fadeCallback()
ChatFrame3.editBox.hooks.OnEditFocusGained(ChatFrame3.editBox)
assert(not groups[1].playing and not groups[2].playing, "focus left an idle animation running")
eq(ChatFrame3:GetAlpha(), 1)
-- A later alpha owner wins even when a fade reaches its end.
visual.fadeCallback()
ChatFrame3:SetAlpha(0.6)
for _, group in ipairs(groups) do if group.playing then group:Finish() end end
eq(ChatFrame3:GetAlpha(), 0.6, "animation completion overwrote foreign alpha")
Chat.ChatActivity(ChatFrame3)
eq(ChatFrame3:GetAlpha(), 0.6, "waking overwrote foreign alpha")
ChatFrame3:SetAlpha(1)
-- A secret getter is never compared with an owned alpha or written back.
visual.fadeCallback()
ChatFrame3.alpha = secret
for _, group in ipairs(groups) do if group.playing then group:Finish() end end
Chat.ChatActivity(ChatFrame3)
assert(rawequal(ChatFrame3.alpha, secret), "a secret alpha was read or overwritten")
ChatFrame3.alpha = 1
-- Unread color uses a routed type ID; hidden text is never examined.
config.coloredUnreadTabs = true
Chat.CompileUnread(config)
Chat.ApplyUnread(visual, ChatFrame3Tab)
Chat.MessageUnread(ChatFrame3, 4)
eq(visual.unreadType, 4)
eq(visual.unreadLine.color[2], 1)
visual.fadeCallback()
eq(ChatFrame3Tab:GetAlpha(), 1, "idle fade hid the unread indicator")
Chat.ClearUnread(visual)
assert(not visual.unreadLine.shown and not visual.unreadType)
Chat.MessageUnread(ChatFrame3, secret)
eq(visual.unreadType, nil, "a secret chat type was used as a table key")
Chat.MessageUnread(ChatFrame3, 999)
eq(visual.unreadType, nil, "unknown message type guessed a color")
GENERAL_CHAT_DOCK.selected = ChatFrame3
Chat.MessageUnread(ChatFrame3, 7)
eq(visual.unreadType, nil, "selected tab was marked unread")
GENERAL_CHAT_DOCK.selected = ChatFrame1
ChatFrame3.isDocked = nil
Chat.MessageUnread(ChatFrame3, 7)
eq(visual.unreadType, nil, "visible floating chat was marked unread")
ChatFrame3.isDocked = true
Chat.MessageUnread(ChatFrame3, 7)
eq(visual.unreadType, 7)
local primary = { frame = ChatFrame1 }
module.visuals[ChatFrame1] = primary
Chat.ApplyUnread(primary, ChatFrame1Tab)
GENERAL_CHAT_DOCK.selected = ChatFrame3
Chat.MessageUnread(ChatFrame1, 4)
eq(primary.unreadType, 4, "the inactive General tab lost its unread indicator")
Chat.ClearUnread(primary)
GENERAL_CHAT_DOCK.selected = ChatFrame1
config.coloredUnreadTabs = false
Chat.ApplyUnread(visual, ChatFrame3Tab)
assert(not visual.unreadLine.shown and not visual.unreadType, "disabled unread colors stayed visible")
-- Disable stops animations and restores exactly the alpha we changed.
Chat.ChatActivity(ChatFrame3)
visual.fadeCallback()
Chat.ReleaseFade(visual)
for _, group in ipairs(groups) do assert(not group.playing, "disabled fade group kept running") end
eq(ChatFrame3:GetAlpha(), 1)
Chat.HideGradient(visual)
for _, file in ipairs({ "Appearance.lua", "MinimalChrome.lua", "FadeAnimation.lua", "Unread.lua" }) do
    local handle = assert(io.open(root .. "/MSUF_Suite_Chat/" .. file, "rb"))
    local source = handle:read("*a")
    handle:close()
    assert(not source:find('SetScript%("OnUpdate"') and not source:find("NewTicker", 1, true), "persistent polling")
end
print("Immersive defaults, native focus fading, gradient, smooth idle restore and routed unread colors passed")
