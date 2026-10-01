local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Cooldowns displayed as timer bars ("Display cooldowns as timer bars"):
-- a status bar beside the icon fed the icon's own native duration objects,
-- and optional charge segments (a count fill and the recharge segment).
local K = C.Const
local B = {}
C.TrackingBars = B
local emptyDuration

-- Presentation of the existing cooldown entry; the native duration, event
-- routing, ownership, binding and tooltip stay with the icon owner.
function B.Style(icon, view)
    local wanted = view.kind == 1 and view.cooldownDuration == true
    local bar = icon.timerBar
    if not bar and wanted then
        bar = S.CreateFrame("StatusBar", nil, icon)
        bar:SetFrameLevel(icon:GetFrameLevel())
        bar.bg = S.CreateTexture(bar, nil, "BACKGROUND")
        bar.bg:SetAllPoints(bar)
        bar.name = S.CreateFontString(icon.over, nil, "OVERLAY")
        icon.timerBar = bar
    end
    icon.durationBar = wanted
    if not bar then return end
    bar:SetShown(wanted)
    bar.name:SetShown(wanted and view.barName ~= false)
    if not wanted then
        local countdown = icon.cd:GetCountdownFontString()
        if countdown then
            countdown:ClearAllPoints()
            countdown:SetPoint("CENTER", icon.cd, "CENTER", 0, 0)
        end
        return
    end
    local inset, h = icon.border or 0, icon.h
    local shown = view.barIcon ~= false
    local right = view.barIconSide == 2
    icon.tex:SetShown(shown)
    icon.tex:ClearAllPoints()
    icon.tex:SetSize(h - inset * 2, h - inset * 2)
    icon.tex:SetPoint(right and "TOPRIGHT" or "TOPLEFT", icon, right and "TOPRIGHT" or "TOPLEFT", right and -inset or inset, -inset)
    icon.tex:SetTexCoord(.08, .92, .08, .92)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", icon, "TOPLEFT", shown and not right and h + 2 or inset, -inset)
    bar:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", shown and right and -h - 2 or -inset, inset)
    local texture = S.ResolveTexture(view.barTexture, K.BAR_TEXTURE)
    bar:SetStatusBarTexture(texture)
    -- The class color while it is readable, else the bar's own color (the
    -- charge segments shade what is stored here).
    local r, g, b
    if view.barClass then r, g, b = K.ClassRGB() end
    local fill = K.BAR_RGB
    if not r then r, g, b = view.barR or fill[1], view.barG or fill[2], view.barB or fill[3] end
    bar:SetStatusBarColor(r, g, b)
    bar.r, bar.g, bar.b, bar.texture = r, g, b, texture
    bar.innerWidth, bar.innerHeight = icon.w - (shown and h + 2 or 0) - inset * 2, h - inset * 2
    bar.chargeSegments, bar.chargeDim = view.barChargeSegments == true, view.barChargeDim ~= false
    bar.segmentStyle = nil
    bar.bg:SetColorTexture(0, 0, 0, (view.barBgAlpha or K.BAR_BG_ALPHA) / 100)
    bar.direction = view.barFill == 2 and Enum.StatusBarTimerDirection.ElapsedTime or Enum.StatusBarTimerDirection.RemainingTime
    local label = bar.name
    S.SetStyledFont(label, C.state.font, K.TextSize(nil, K.FONT.barText, h), C.state.fontFlags,
        C.state.fontRendering, C.state.fontShadow, C.state.fontShadowOpacity, C.state.fontShadowDistance)
    label:ClearAllPoints()
    label:SetPoint("LEFT", bar, "LEFT", 4, 0)
    label:SetWidth(math.max(1, icon.w - (shown and h + 2 or 0) - 48))
    label:SetWordWrap(false)
    label:SetJustifyH("LEFT")
    label:SetText(icon.entry and icon.entry.name or "")
    local countdown = icon.cd:GetCountdownFontString()
    if countdown then
        countdown:ClearAllPoints()
        countdown:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    end
end

function B.Duration(icon, duration)
    local bar = icon.durationBar and icon.timerBar
    if not bar then return end
    bar.duration = duration
    if bar.segmentMode then return end
    if not duration then
        if not emptyDuration then
            emptyDuration = C_DurationUtil.CreateDuration()
            emptyDuration:SetTimeFromStart(0, 0)
        end
        duration = emptyDuration
    end
    bar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, bar.direction)
end

function B.Charges(icon, charges, duration)
    local bar = icon.durationBar and icon.timerBar
    if not bar then return end
    local maximum = charges and charges.maxCharges
    local wanted = bar.chargeSegments and S.Public(maximum) and type(maximum) == "number"
        and maximum > 1 and maximum <= 20 and maximum == math.floor(maximum)
    if not wanted then
        if bar.segmentMode then
            bar.segmentMode = false
            bar.countFill:Hide()
            bar:GetStatusBarTexture():SetAlpha(1)
            bar.recharge:Hide()
            for _, mark in ipairs(bar.separators) do mark:Hide() end
            B.Duration(icon, bar.duration)
        end
        return
    end
    if not bar.recharge then
        -- Segment fills above the bar, under the countdown (K.LEVEL).
        local level = icon:GetFrameLevel() + K.LEVEL.fill
        bar.countFill = S.CreateFrame("StatusBar", nil, bar)
        bar.countFill:SetAllPoints(bar)
        bar.countFill:SetFrameLevel(level)
        bar.recharge = S.CreateFrame("StatusBar", nil, bar)
        bar.recharge:SetFrameLevel(level)
        bar.separators = {}
    end
    bar.segmentMode = true
    bar:GetStatusBarTexture():SetAlpha(0)
    bar.countFill:Show()
    bar.countFill:SetMinMaxValues(0, maximum)
    bar.countFill:SetValue(charges.currentCharges)
    local recharge = bar.recharge
    if bar.segmentStyle ~= maximum then
        bar.segmentStyle = maximum
        bar.countFill:SetStatusBarTexture(bar.texture)
        bar.countFill:SetStatusBarColor(bar.r, bar.g, bar.b)
        recharge:ClearAllPoints()
        recharge:SetPoint("LEFT", bar.countFill:GetStatusBarTexture(), "RIGHT", 0, 0)
        recharge:SetSize(bar.innerWidth / maximum, bar.innerHeight)
        recharge:SetStatusBarTexture(bar.texture)
        local shade = bar.chargeDim and .5 or 1
        recharge:SetStatusBarColor(bar.r * shade, bar.g * shade, bar.b * shade)
        for n = 1, math.max(#bar.separators, maximum - 1) do
            local mark = bar.separators[n]
            if not mark then
                mark = S.CreateTexture(bar.countFill, nil, "OVERLAY")
                bar.separators[n] = mark
            end
            mark:SetShown(n < maximum)
            if n < maximum then
                mark:ClearAllPoints()
                mark:SetPoint("TOPLEFT", bar, "TOPLEFT", K.Snap(bar.innerWidth * n / maximum), 0)
                mark:SetSize(K.Px(), bar.innerHeight)
                mark:SetColorTexture(0, 0, 0, .8)
            end
        end
    end
    local active = charges.isActive
    recharge:SetShown(S.Public(active) and active == true and duration ~= nil)
    if duration then recharge:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime) end
end
