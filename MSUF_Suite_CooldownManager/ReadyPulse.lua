local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- The ready pulse ("Pulse ready cooldowns in the screen center"): when a
-- cooldown on a bar that asks for it comes off cooldown, its icon pops up
-- in the middle of the screen, holds, then grows and fades away. One pooled
-- frame, made on the first pulse; an AnimationGroup plays it, so no script
-- runs per frame. The edge is the one that plays the ready sound
-- (Alerts.Ready), so no cooldown is polled for it; the bar's visibility does
-- not matter, a hidden bar still pulses. A pulse that arrives while one
-- plays waits in a short queue that drops its oldest first. Size, place,
-- hold time and "only in combat" are the General settings (state.pulse*).
local K = C.Const
local Pulse = {}
C.Pulse = Pulse
local QUEUE, POP, FADE, GROW = 3, .12, .45, 1.35
local frame
local waiting, count = {}, 0 -- icons that wait their turn, and how many
local playing = false

local function Play(icon)
    local state = C.state
    local size, y, hold = state.pulseSize or 96, state.pulseY or 120, state.pulseHold or .5
    if frame.laySize ~= size then
        frame.laySize = size
        frame:SetSize(size, size)
    end
    if frame.layY ~= y then
        frame.layY = y
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, y)
    end
    if frame.layHold ~= hold then
        frame.layHold = hold
        frame.hold:SetDuration(hold)
    end
    frame.icon:SetTexture(icon)
    playing = true
    frame:Show()
    frame.group:Play()
end

-- The next waiting icon starts when the one on screen has faded.
local function Finished()
    playing = false
    frame:Hide()
    if count == 0 then return end
    local icon = waiting[1]
    for i = 2, count do waiting[i - 1] = waiting[i] end
    waiting[count] = nil
    count = count - 1
    Play(icon)
end

local function New()
    local pulse = S.CreateFrame("Frame", nil, UIParent)
    pulse:SetFrameStrata("HIGH")
    pulse:EnableMouse(false)
    pulse.icon = S.CreateTexture(pulse, nil, "ARTWORK")
    pulse.icon:SetAllPoints(pulse)
    pulse.icon:SetTexCoord(.08, .92, .08, .92)
    local group = pulse:CreateAnimationGroup()
    -- Pops in, holds, then grows and fades.
    local pop = group:CreateAnimation("Scale")
    pop:SetOrder(1)
    pop:SetScaleFrom(.7, .7)
    pop:SetScaleTo(1, 1)
    pop:SetDuration(POP)
    pop:SetOrigin("CENTER", 0, 0)
    local hold = group:CreateAnimation("Alpha")
    hold:SetOrder(2)
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    local grow = group:CreateAnimation("Scale")
    grow:SetOrder(3)
    grow:SetScaleFrom(1, 1)
    grow:SetScaleTo(GROW, GROW)
    grow:SetDuration(FADE)
    grow:SetOrigin("CENTER", 0, 0)
    local fade = group:CreateAnimation("Alpha")
    fade:SetOrder(3)
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(FADE)
    group:SetScript("OnFinished", Finished)
    pulse.group, pulse.hold = group, hold
    pulse:Hide()
    return pulse
end

-- A cooldown on a bar with the pulse switched on became ready (entry: the
-- plan's entry; its texture is a plain value).
function Pulse.Ready(entry)
    local state = C.state
    if state.pulseCombat and not state.inCombat then return end
    local icon = entry.texture or K.QUESTION_ICON
    if not frame then frame = New() end
    if not playing then return Play(icon) end
    if count == QUEUE then
        for i = 2, QUEUE do waiting[i - 1] = waiting[i] end
        count = QUEUE - 1
    end
    count = count + 1
    waiting[count] = icon
end

-- The module let go (Effects.ReleaseAll): what is on screen and what waits go.
function Pulse.Release()
    if not frame then return end
    for i = 1, count do waiting[i] = nil end
    count, playing = 0, false
    frame.group:Stop()
    frame:Hide()
end
