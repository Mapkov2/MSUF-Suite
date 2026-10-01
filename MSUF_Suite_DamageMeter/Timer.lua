local _, P = ...
local S = P.Suite
-- Standalone combat timer: the Current-session duration while combat is
-- live, updated by a one-shot timer only while visible (whole seconds,
-- memoized). After combat it hides, or keeps the frozen last duration when
-- timerKeep is on. The session duration counts whole seconds (Blizzard shows
-- it only through SecondsToClock), so tenths come from the combat clock that
-- PLAYER_REGEN_DISABLED starts (M.combatStart), live and kept alike.
local D = P.DamageMeter
local M = D.M
local floor = math.floor
local SAMPLE_SECONDS = 95
local function TimerTick()
    M.timerInFlight = false
    if M.active then D.UpdateTimer() end
end

function D.StyleTimer()
    local c = M.config
    local frame = M.timerFrame
    if not c.combatTime or not c.timer then
        if frame then frame:Hide() end
        return
    end
    if not frame then
        frame = S.CreateFrame("Frame", nil, UIParent)
        frame:SetClampedToScreen(true)
        frame:SetFrameStrata("HIGH")
        frame.background = S.CreateTexture(frame, nil, "BACKGROUND")
        frame.background:SetAllPoints(frame)
        frame.edges = {}
        for i = 1, 4 do frame.edges[i] = S.CreateTexture(frame, nil, "BORDER") end
        frame.text = S.CreateFontString(frame, nil, "OVERLAY")
        frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
        frame:Hide()
        M.timerFrame = frame
    end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", c.timerX, c.timerY)
    frame:SetSize(c.timerSize * (c.timerDecimals and 5.5 or 4), c.timerSize + 8)
    local br, bg, bb = S.RGB(c.timerBackground)
    frame.background:SetColorTexture(br, bg, bb, c.timerBackgroundAlpha / 100)
    br, bg, bb = S.RGB(c.timerBorderColor)
    S.PlaceEdges(frame.edges, frame, c.timerBorderSize, br, bg, bb, 1)
    -- The text color is resolved here, not on every tick: the live color and,
    -- with timerDesaturate, its gray for outside combat.
    local r, g, b = S.RGB(c.timerTextColor)
    frame.liveR, frame.liveG, frame.liveB = r, g, b
    frame.dim = c.timerDesaturate and r * .299 + g * .587 + b * .114 or nil
    D.FontStyle(frame.text, c.timerSize)
    frame.text:ClearAllPoints()
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, M.style.baseline)
    frame.textR, frame.textG, frame.textB = nil, nil, nil
    M.timerSecond = false
    D.UpdateTimer()
end

function D.UpdateTimer(liveDuration, liveResolved)
    local frame, c = M.timerFrame, M.config
    if not frame or not c.combatTime or not c.timer then return end
    if M.sessionHidden and c.toggleTimer and not M.forced then frame:Hide(); return end
    local seconds
    -- Edit Mode and the options preview need a visible, placeable value.
    if M.forced then
        seconds = M.lastDuration or SAMPLE_SECONDS
    elseif M.inCombat then
        if c.timerDecimals and M.combatStart then
            seconds = GetTime() - M.combatStart
        elseif liveResolved then
            seconds = liveDuration
        else
            seconds = D.LiveDuration()
        end
    elseif c.timerKeep then
        seconds = M.lastDuration
    end
    if not seconds then
        if frame:IsShown() then frame:Hide() end
        return
    end
    local r, g, b = frame.liveR, frame.liveG, frame.liveB
    if frame.dim and not M.inCombat then r, g, b = frame.dim, frame.dim, frame.dim end
    if frame.textR ~= r or frame.textG ~= g or frame.textB ~= b then
        frame.text:SetTextColor(r, g, b)
        frame.textR, frame.textG, frame.textB = r, g, b
    end
    local units = floor(seconds * (c.timerDecimals and 10 or 1))
    if units ~= M.timerSecond then
        M.timerSecond = units
        frame.text:SetText(c.timerDecimals and (D.Clock(seconds) .. "." .. units % 10) or D.Clock(seconds))
    end
    if c.timerDecimals and M.inCombat and not M.timerInFlight and not M.forced then
        M.timerInFlight = true
        C_Timer.After(.1, TimerTick)
    end
    if not frame:IsShown() then frame:Show() end
end
