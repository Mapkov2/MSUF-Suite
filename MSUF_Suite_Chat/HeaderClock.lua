local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
local M = C.M
local tick

function C.ApplyClockSettings()
    if M.config.hideNativeTimestamps then
        M.context:CVar("showTimestamps", "none")
    else
        S.RestoreCVar("chat", "showTimestamps")
    end
end

function C.ClockText(config, hour, minute)
    if not S.Finite(hour) or not S.Finite(minute) then return "" end
    if config.headerClock24Hour then return ("%02d:%02d"):format(hour, minute) end
    local format = hour < 12 and TIME_TWELVEHOURAM or TIME_TWELVEHOURPM
    return format:format(hour % 12 == 0 and 12 or hour % 12, minute)
end

-- The same owned label painter is used by the window and its preview.
function C.PaintClock(visual, frame, config, top, text)
    local label = visual.headerClock
    if not config.headerClock then
        if label then label:Hide() end
        return
    end
    if not label then
        label = S.CreateFontString(frame, nil, "OVERLAY")
        visual.headerClock = label
    end
    local font = S.ResolveFont(config.tabFont) or S.GlobalFontPath()
    label:SetFont(font, config.tabFontSize > 0 and config.tabFontSize or 12, "")
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
    label:ClearAllPoints()
    label:SetPoint("RIGHT", frame, "TOPRIGHT", config.copyMessages and -56 or -8,
        math.max(21, top) - (config.tabHeight or 24) / 2 + (config.tabY or 0))
    label:SetWidth(94)
    label:SetJustifyH("RIGHT")
    label:SetTextColor(S.RGB(config.tabActiveColor))
    if text ~= nil then label:SetText(text) end
    label:Show()
end

function C.RefreshClocks()
    if tick then
        tick:Cancel()
        tick = nil
    end
    if not M.active or not M.config.headerClock then return end
    local any
    for frame, visual in pairs(M.visuals) do
        if visual.headerClock and frame:IsVisible() then
            any = true
            break
        end
    end
    if not any then return end
    local hour, minute
    if M.config.headerClockLocalTime then
        hour, minute = tonumber(date("%H")), tonumber(date("%M"))
    else
        hour, minute = S.ReadInfoSource("clockTime")
    end
    local text = C.ClockText(M.config, hour, minute)
    for frame, visual in pairs(M.visuals) do
        if visual.headerClock and frame:IsVisible() then visual.headerClock:SetText(text) end
    end
    local stamp = S.ReadInfoSource("clockStamp")
    local delay = S.Finite(stamp) and 60 - stamp % 60 or 60
    tick = S.ScheduleDataTick("chat-header-clock", delay, C.RefreshClocks)
end

function C.ApplyClock(visual, frame, config, top)
    C.PaintClock(visual, frame, config, top)
    if config.headerClock and not visual.clockHooked then
        frame:HookScript("OnShow", C.RefreshClocks)
        frame:HookScript("OnHide", C.RefreshClocks)
        visual.clockHooked = true
    end
end

function C.DisableClock()
    S.RestoreCVar("chat", "showTimestamps")
    if tick then
        tick:Cancel()
        tick = nil
    end
    for _, visual in pairs(M.visuals) do
        if visual.headerClock then visual.headerClock:Hide() end
    end
end
