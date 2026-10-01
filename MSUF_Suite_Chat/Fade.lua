local _, P = ...
local S = P.Suite
local C = P.Chat
-- Idle fade (idleSeconds > 0): a chat window that got no new line and no
-- pointer for that long fades to idleAlpha together with its tab, its input
-- line and, for the primary window, the sidebar. A new line or Blizzard's
-- own mouse-over fade-in (FCF_FadeInChatFrame) wakes it; the countdown
-- starts again when Blizzard fades its chrome out (FCF_FadeOutChatFrame).
-- Chat frames, tabs and edit boxes are not protected, so this also runs in
-- combat and never waits for the module to apply again. Each part's alpha
-- before the fade is kept here and handed back on waking, unless Blizzard
-- set another one meanwhile. One timer per window and idle period: a line
-- only moves the deadline the pending timer checks when it fires.
local M = C.M
local Finite = S.Finite
local TAB = 2
local delay = 0

-- The countdown never ends before Blizzard's own tab fade-out
-- (CHAT_FRAME_FADE_OUT_TIME), which would otherwise paint over the tab.
local function Delay(seconds)
    return math.max(seconds, CHAT_FRAME_FADE_OUT_TIME)
end

local function FadeOut(visual)
    local alpha = M.config.idleAlpha / 100
    local parts, before, applied = visual.fadeParts, visual.fadeBefore, visual.fadeApplied
    for i = 1, 4 do
        local part = parts[i]
        if part then
            if before[i] == nil then
                local current = part:GetAlpha()
                if Finite(current) then before[i] = current end
            end
            if before[i] ~= nil then
                part:SetAlpha(alpha)
                applied[i] = part:GetAlpha()
            end
        end
    end
    visual.faded = true
end

-- keepTab: Blizzard's fade-in already animates the tab from its alpha.
local function Wake(visual, keepTab)
    if not visual.faded then return end
    visual.faded = nil
    local parts, before, applied = visual.fadeParts, visual.fadeBefore, visual.fadeApplied
    for i = 1, 4 do
        local part, value = parts[i], before[i]
        if part and value ~= nil and not (keepTab and i == TAB) then
            local current = part:GetAlpha()
            if Finite(current) and current == applied[i] then part:SetAlpha(value) end
        end
        before[i], applied[i] = nil, nil
    end
end

local function Expired(visual)
    visual.fadeTimer = nil
    if not (M.active and visual.fadeArmed) or visual.hovered then return end
    local remaining = visual.idleAt - GetTime()
    if remaining > 0.05 then
        visual.fadeTimer = C_Timer.NewTimer(remaining, visual.fadeCallback)
        return
    end
    FadeOut(visual)
end

-- Activity: a new line (in or out of combat) or the end of a mouse-over.
function C.ChatActivity(frame)
    local visual = M.visuals[frame]
    if not (visual and visual.fadeArmed) then return end
    visual.idleAt = GetTime() + delay
    if visual.faded then Wake(visual) end
    if not visual.fadeTimer and not visual.hovered then
        visual.fadeTimer = C_Timer.NewTimer(delay, visual.fadeCallback)
    end
end

-- Blizzard shows the window's chrome while the pointer is over it.
local function HoverStarted(chatFrame)
    local visual = M.active and M.visuals[chatFrame]
    if not (visual and visual.fadeArmed) then return end
    visual.hovered = true
    Wake(visual, true)
end

local function HoverEnded(chatFrame)
    local visual = M.active and M.visuals[chatFrame]
    if not (visual and visual.fadeArmed) then return end
    visual.hovered = nil
    C.ChatActivity(chatFrame)
end

function C.ReleaseFade(visual)
    visual.fadeArmed, visual.hovered = nil, nil
    if visual.fadeTimer then
        visual.fadeTimer:Cancel()
        visual.fadeTimer = nil
    end
    Wake(visual)
end

-- Cold path (Window.lua, out of combat): arms or releases one window. A
-- settings change counts as activity, so the window wakes and counts anew.
function C.ApplyInactivity(self, visual)
    local seconds = self.config.idleSeconds
    if not (Finite(seconds) and seconds > 0) then
        C.ReleaseFade(visual)
        return
    end
    delay = Delay(seconds)
    if not M.hookedFade then
        -- FloatingChatFrame.lua defines both at login on Retail and Forever.
        hooksecurefunc("FCF_FadeInChatFrame", HoverStarted)
        hooksecurefunc("FCF_FadeOutChatFrame", HoverEnded)
        M.hookedFade = true
    end
    local frame = visual.frame
    if not visual.fadeCallback then
        visual.fadeParts, visual.fadeBefore, visual.fadeApplied = {}, {}, {}
        visual.fadeCallback = function() Expired(visual) end
    end
    Wake(visual)
    local parts = visual.fadeParts
    parts[1], parts[TAB], parts[3], parts[4] =
        frame, _G[frame:GetName() .. "Tab"], frame.editBox, visual.sidebarFrame
    if visual.fadeTimer then
        visual.fadeTimer:Cancel()
        visual.fadeTimer = nil
    end
    visual.fadeArmed = true
    C.ChatActivity(frame)
end

function C.FadeDisable()
    for _, visual in pairs(M.visuals) do C.ReleaseFade(visual) end
end
