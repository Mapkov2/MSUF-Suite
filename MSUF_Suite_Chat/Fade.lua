local _, P = ...
local S = P.Suite
local C = P.Chat
-- Idle fade (idleSeconds > 0): a chat window that got no new line and no
-- pointer for that long fades to idleAlpha together with its tab and, for
-- the primary window, the sidebar. Its input line is a child of the window
-- (FloatingChatFrameTemplate's editBox, live and forever), so it fades with
-- the window and is never faded on its own. A new line or Blizzard's own
-- mouse-over fade-in wakes it; the countdown starts again when Blizzard fades
-- its chrome out. Both arrive from Suite.ChatState (MSUF_Suite/Core), which
-- reads Blizzard's hasBeenFaded flag: a hook on FCF_FadeInChatFrame would run
-- inside FCF_OnUpdate and taint every window's fade state. While its input
-- line has the focus the window stays awake: gaining the focus wakes it and
-- losing it starts the countdown again (ChatState's EventRegistry callbacks,
-- never a script hook on Blizzard's edit box).
-- Chat frames, tabs and edit boxes are not protected, so this also runs in
-- combat and never waits for the module to apply again. Each part's alpha
-- before the fade is kept here and handed back on waking, unless Blizzard
-- set another one meanwhile. One context wait per window (ctx:After with
-- the window's own callback): a line only moves its deadline.
local M = C.M
local Finite = S.Finite
-- fadeParts: 1 the window, TAB its tab, 3 the sidebar (the window it sits
-- on: the selected dock window, else the primary window; PlaceSidebar).
local TAB, PARTS = 2, 6
local delay = 0
-- edit box -> its window's visual (permanent windows only).
local inputs = setmetatable({}, { __mode = "k" })

-- The countdown never ends before Blizzard's own tab fade-out
-- (CHAT_FRAME_FADE_OUT_TIME), which would otherwise paint over the tab.
local function Delay(seconds)
    return math.max(seconds, CHAT_FRAME_FADE_OUT_TIME)
end

local function FadeOut(visual)
    local alpha = M.config.idleAlpha / 100
    local parts, before = visual.fadeParts, visual.fadeBefore
    -- The held tab regions follow the tab frame for the fade (Window.lua).
    if not visual.unreadType then C.TabFollowsFrame(visual) end
    for i = 1, PARTS do
        local part = parts[i]
        if part and not (i == TAB and visual.unreadType) then
            if before[i] == nil then
                local current = part:GetAlpha()
                if Finite(current) then before[i] = current end
            end
            if before[i] ~= nil then
                C.FadePart(visual, i, alpha)
            end
        end
    end
    visual.faded = true
end

-- skip: the part whose alpha stays as it is (TAB on a mouse-over: Blizzard's
-- fade-in already animates the tab from its alpha).
local function Wake(visual, skip)
    if not visual.faded then return end
    visual.faded = nil
    local parts, before, applied = visual.fadeParts, visual.fadeBefore, visual.fadeApplied
    for i = 1, PARTS do
        local part, value = parts[i], before[i]
        C.StopFadeAnimation(visual, i)
        if part and value ~= nil and i ~= skip then
            local current = part:GetAlpha()
            if Finite(current) and current == applied[i] then part:SetAlpha(value) end
        end
        before[i], applied[i] = nil, nil
    end
    C.KeepTabVisible(M, visual.frame)
end

local function Expired(visual)
    if not (M.active and visual.fadeArmed) or visual.hovered or visual.toolbarHovered or M.toolbarGesture then return end
    if C.InputHasFocus(visual.frame) then return end
    FadeOut(visual)
end

-- Activity: a new line (in or out of combat) or the end of a mouse-over.
-- Under the pointer the window waits for the pointer to leave.
function C.ChatActivity(frame)
    local visual = M.visuals[frame]
    if not (visual and visual.fadeArmed) then return end
    if visual.faded then Wake(visual) end
    if not visual.hovered and not visual.toolbarHovered then M.context:After(delay, visual.fadeCallback) end
end

-- Blizzard shows the window's chrome while the pointer is over it.
function C.HoverStarted(chatFrame)
    local visual = M.active and M.visuals[chatFrame]
    if not visual then return end
    visual.hovered = true
    C.MessageFadeFocus(visual, true)
    C.UpdateMinimalChrome(visual)
    if visual.fadeArmed then Wake(visual, TAB) end
end

function C.HoverEnded(chatFrame)
    local visual = M.active and M.visuals[chatFrame]
    if not visual then return end
    visual.hovered = nil
    C.MessageFadeFocus(visual)
    C.UpdateMinimalChrome(visual)
    C.ChatActivity(chatFrame)
end

-- The player starts typing into the window's input line.
local function InputFocused(editBox)
    local visual = inputs[editBox]
    if not visual then return end
    visual.inputFocused = true
    if not (M.active and visual.fadeCallback) then return end
    C.MessageFadeFocus(visual, true)
    C.UpdateMinimalChrome(visual, true)
    if visual.fadeArmed then Wake(visual) end
end

local function InputReleased(editBox)
    local visual = inputs[editBox]
    if not visual then return end
    visual.inputFocused = false
    if not (M.active and visual.fadeCallback) then return end
    C.MessageFadeFocus(visual, visual.hovered == true)
    C.UpdateMinimalChrome(visual, false)
    C.ChatActivity(visual.frame)
end

-- ChatState box callback: focus and release of a permanent input line.
function C.FadeInput(kind, editBox)
    if kind == "focus" then
        InputFocused(editBox)
    elseif kind == "release" then
        InputReleased(editBox)
    end
end

local function TrackInput(visual)
    local input = visual.frame.editBox
    if input and P.NS.ChatState.IsPermanentBox(input) then inputs[input] = visual end
end

function C.ReleaseFade(visual)
    visual.fadeArmed = nil
    if not M.active or not (visual.nativeFadeBefore or M.config.minimalChrome) then visual.hovered = nil end
    if visual.fadeCallback then M.context:Cancel(visual.fadeCallback) end
    Wake(visual)
end

-- Cold path (Window.lua, out of combat): arms or releases one window. A
-- settings change counts as activity, so the window wakes and counts anew.
function C.ApplyInactivity(self, visual)
    local seconds = self.config.idleSeconds
    local idle = Finite(seconds) and seconds > 0
    local trackFade = idle or visual.nativeFadeBefore or self.config.minimalChrome
    if trackFade or self.config.headerToolbar then TrackInput(visual) end
    if not trackFade then
        C.ReleaseFade(visual)
        return
    end
    delay = Delay(seconds)
    local frame = visual.frame
    if not visual.fadeCallback then
        visual.fadeParts, visual.fadeBefore, visual.fadeApplied = {}, {}, {}
        visual.fadeCallback = function() Expired(visual) end
    end
    if not idle then
        C.ReleaseFade(visual)
        return
    end
    Wake(visual)
    local parts, primary = visual.fadeParts, M.visuals[ChatFrame1]
    local sidebar = (C.DockSelection() or ChatFrame1) == frame and primary and primary.sidebarFrame or nil
    parts[1], parts[TAB], parts[3] = frame, _G[frame:GetName() .. "Tab"], sidebar
    local selected = (C.DockSelection() or ChatFrame1) == frame and self.config.headerToolbar
    parts[4], parts[5], parts[6] = selected and M.toolbar or nil, selected and M.toolbarDrag or nil,
        selected and M.toolbarResize or nil
    C.PrepareFadeAnimations(visual, self.config.idleFadeDuration)
    M.context:Cancel(visual.fadeCallback)
    visual.fadeArmed = true
    C.ChatActivity(frame)
end

-- Idle fade, minimal chrome and message fade react to Blizzard's hover.
function C.HoverWanted()
    local c = M.config
    return c.minimalChrome == true or (c.idleSeconds or 0) > 0 or c.messageFading == true
end

function C.FadeDisable()
    for _, visual in pairs(M.visuals) do C.ReleaseFade(visual) end
end
