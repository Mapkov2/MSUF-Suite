local _, P = ...
local D, S = P.DamageMeter, P.Suite
local M = D.M
local CORNERS = { [2] = "TOPLEFT", [3] = "TOPRIGHT", [4] = "BOTTOMLEFT", [5] = "BOTTOMRIGHT" }
local ATTACH = { [2] = "BOTTOMLEFT", [3] = "BOTTOMRIGHT", [4] = "TOPLEFT", [5] = "TOPRIGHT" }
local ALIGN = { "LEFT", "CENTER", "RIGHT" }

function D.NewTimer(parent)
    local frame = S.CreateFrame("Frame", nil, parent)
    frame.background = S.CreateTexture(frame, nil, "BACKGROUND")
    frame.background:SetAllPoints(frame)
    frame.edges = {}
    for i = 1, 4 do frame.edges[i] = S.CreateTexture(frame, nil, "BORDER") end
    frame.text = S.CreateFontString(frame, nil, "OVERLAY")
    frame:Hide()
    return frame
end

function D.PaintTimerStyle(frame)
    local c = M.config
    frame:SetSize(c.timerSize * (c.timerDecimals and 5.5 or 4), c.timerSize + 8)
    local r, g, b = S.RGB(c.timerBackground)
    frame.background:SetColorTexture(r, g, b, c.timerBackgroundAlpha / 100)
    r, g, b = S.RGB(c.timerBorderColor)
    S.PlaceEdges(frame.edges, frame, c.timerBorderSize, r, g, b, 1)
    r, g, b = S.RGB(c.timerTextColor)
    frame.liveR, frame.liveG, frame.liveB = r, g, b
    frame.dim = c.timerDesaturate and r * .299 + g * .587 + b * .114 or nil
    D.FontStyle(frame.text, c.timerSize, "timer")
    frame.text:ClearAllPoints()
    frame.text:SetPoint("LEFT", frame, "LEFT", 4, M.style.baseline)
    frame.text:SetPoint("RIGHT", frame, "RIGHT", -4, M.style.baseline)
    frame.text:SetJustifyH(ALIGN[c.timerAlign] or "CENTER")
    frame.textR, frame.textG, frame.textB = nil, nil, nil
end

function D.AnchorTimer(frame, win)
    local c, anchor = M.config, M.config.timerAnchor
    frame:ClearAllPoints()
    if CORNERS[anchor] and win then
        local target = anchor <= 3 and c.headerVisible ~= false and win.header or win.frame
        frame:SetPoint(ATTACH[anchor], target, CORNERS[anchor], c.timerDockX, c.timerDockY)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", c.timerX, c.timerY)
    end
end

function D.TimerAnchorShown()
    local c = M.config
    if M.uiHidden then return false end
    if c.timerAnchor == 1 then return true end
    local win = D.windows[c.timerWindow]
    return c.timerWindow <= c.windowCount and win and win.shown and not win.faded
end

-- The menu sample uses the real painter and docking anchors. Free screen
-- coordinates belong to Edit Mode; here a free timer is shown above the sample.
function D.LayoutMenuTimer(win, parent)
    local c = M.config
    local width, height = c[D.KEYS[win.index].Width], c[D.KEYS[win.index].Height]
    local outside = c.headerVisible ~= false and c.headerOutside and c.headerHeight or 0
    local border = M.style.windowBorder
    local pad = border.size > 0 and math.max(0, border.size + border.gap) or 0
    local left, right, top, bottom = -pad, width + pad, -outside - pad, height + pad
    local enabled = c.combatTime and c.timer and (c.timerAnchor == 1
        or c.timerWindow == win.index and win.index <= c.windowCount)
    local frame = win.sampleTimer
    if enabled then
        frame = frame or D.NewTimer(parent)
        win.sampleTimer = frame
        D.PaintTimerStyle(frame)
        local tw, th = frame:GetWidth(), frame:GetHeight()
        local x, y = (width - tw) / 2, -outside - th - 8
        local anchor = c.timerAnchor
        if anchor ~= 1 then
            x = (anchor == 3 or anchor == 5) and width - tw + c.timerDockX or c.timerDockX
            y = anchor <= 3 and -outside - th - c.timerDockY or height - c.timerDockY
        end
        left, right = math.min(left, x), math.max(right, x + tw)
        top, bottom = math.min(top, y), math.max(bottom, y + th)
        frame.previewX, frame.previewY = x, y
        frame.text:SetText(c.timerDecimals and "1:35.0" or "1:35")
        frame.text:SetTextColor(frame.liveR, frame.liveG, frame.liveB)
        frame:Show()
    elseif frame then frame:Hide() end
    win.previewTimerShown = enabled == true
    win.previewWidth, win.previewHeight = right - left, bottom - top
    win.frame:ClearAllPoints()
    win.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", -left, top)
    if enabled then
        if c.timerAnchor == 1 then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", win.frame, "TOPLEFT", frame.previewX, -frame.previewY)
        else D.AnchorTimer(frame, win) end
    end
end
