local _, P = ...
local S = P.Suite
local Appearance = {}
P.Appearance = Appearance

-- A value on the physical pixel grid (pixel = one screen pixel in UI units).
local function Snap(value, pixel)
    return math.floor(value / pixel + 0.5) * pixel
end
Appearance.Snap = Snap

local function Color(texture, hex, alpha)
    local r, g, b = S.RGB(hex)
    texture:SetColorTexture(r, g, b, alpha)
end
Appearance.Color = Color

function Appearance.Paint(bar)
    local style, background = bar.style, bar.background
    local pixel = bar.pixelUnit or 1
    local fade = style.backgroundEnabled and style.backgroundGradient
    background:SetShown(style.backgroundEnabled == true and not fade)
    bar.gradient:SetShown(fade == true)
    if fade then
        local r, g, b = S.RGB(style.backgroundColor)
        local fr, fg, fb = S.RGB(style.backgroundFadeColor)
        local alpha = style.backgroundOpacity / 100
        bar.gradient:SetGradient("VERTICAL", CreateColor(fr, fg, fb, alpha), CreateColor(r, g, b, alpha))
    elseif style.backgroundEnabled then
        local path = style.backgroundTexture ~= "" and S.ResolveTexture(style.backgroundTexture)
        if path then
            background:SetTexture(path)
            local r, g, b = S.RGB(style.backgroundColor)
            background:SetVertexColor(r, g, b, style.backgroundOpacity / 100)
        else
            Color(background, style.backgroundColor, style.backgroundOpacity / 100)
        end
    end
    for i = 1, 4 do
        local edge = bar.border[i]
        edge:SetShown(style.borderEnabled == true)
        if style.borderEnabled then
            Color(edge, style.borderColor, .85)
            if i <= 2 then edge:SetHeight(style.borderSize * pixel) else edge:SetWidth(style.borderSize * pixel) end
        end
    end
    bar.accent:SetShown(style.accentEnabled == true)
    if style.accentEnabled then
        bar.accent:SetHeight(pixel)
        local inset = style.bagBadge and Snap(style.bagBadgeSize + 8, pixel) or 0
        bar.accent:ClearAllPoints()
        if style.accentPosition == 2 then
            bar.accent:SetPoint("TOPLEFT", bar.frame, "TOPLEFT", inset, 0)
            bar.accent:SetPoint("TOPRIGHT", bar.frame, "TOPRIGHT", 0, 0)
        else
            bar.accent:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", 0, 0)
            bar.accent:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, 0)
        end
        Color(bar.accent, style.accentColor, .9)
    end
    bar.badge:SetShown(style.bagBadge == true)
    if style.bagBadge then
        local badgeSize = Snap(style.bagBadgeSize, pixel)
        bar.badge:SetSize(badgeSize, badgeSize)
        bar.badge:ClearAllPoints()
        bar.badge:SetPoint("LEFT", bar.frame, "LEFT", Snap(4, pixel), 0)
    end
    for _, divider in pairs(bar.dividers) do Color(divider, style.separatorColor, .8) end
end
