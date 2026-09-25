local _, P = ...
local NS, S = P.NS, P.Suite
-- Standalone combat timer: the Current-session duration while combat is
-- live, updated by a one-shot timer only while visible (whole seconds,
-- memoized). After
-- combat it hides, or keeps the frozen last duration when timerKeep is on.
local D = P.DamageMeter
local M = D.M
local floor = math.floor
local SAMPLE_SECONDS = 95

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
        frame.text = S.CreateFontString(frame, nil, "OVERLAY")
        frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
        frame:Hide()
        M.timerFrame = frame
    end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", c.timerX, c.timerY)
    frame:SetSize(c.timerSize * 4, c.timerSize + 8)
    D.FontStyle(frame.text, c.timerSize)
    frame.text:ClearAllPoints()
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, M.style.baseline)
    frame.text:SetTextColor(1, 1, 1)
    M.timerSecond = false
    D.UpdateTimer()
end

function D.UpdateTimer(liveDuration, liveResolved)
    local frame, c = M.timerFrame, M.config
    if not frame or not c.combatTime or not c.timer then return end
    local seconds
    -- Edit Mode and the options preview need a visible, placeable value.
    if M.forced then
        seconds = M.lastDuration or SAMPLE_SECONDS
    elseif M.inCombat then
        if liveResolved then seconds = liveDuration else seconds = D.LiveDuration() end
    elseif c.timerKeep then
        seconds = M.lastDuration
    end
    if not seconds then
        if frame:IsShown() then frame:Hide() end
        return
    end
    seconds = floor(seconds)
    if seconds ~= M.timerSecond then
        M.timerSecond = seconds
        frame.text:SetText(D.Clock(seconds))
    end
    if not frame:IsShown() then frame:Show() end
end
