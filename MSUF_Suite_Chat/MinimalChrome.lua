local _, P = ...
local S = P.Suite
local C = P.Chat
local M = C.M

function C.HasTabStyle(config)
    return config.tabPanel and (config.panelAlpha > 0 or config.minimalChrome)
end

-- Compact native tabs retain their titles and click/drag targets. Only our
-- marker moves above the selected tab; no line spans the whole chat window.
function C.PlaceTabMarker(line, tab, config)
    local edge = config.minimalChrome and "TOP" or "BOTTOM"
    line:ClearAllPoints()
    line:SetPoint(edge .. "LEFT", tab, edge .. "LEFT", 5, 1)
    line:SetPoint(edge .. "RIGHT", tab, edge .. "RIGHT", -5, 1)
    line:SetHeight(config.minimalChrome and 1 or 2)
end

-- Glass uses a short solid left margin followed by a fade to the right.
-- Normal gradient controls keep their symmetric transparent edges.
function C.PlaceGradient(visual, panel, minimal)
    local left, right = visual.gradientLeft, visual.gradientRight
    left:ClearAllPoints()
    right:ClearAllPoints()
    left:SetPoint("TOPLEFT", panel, "TOPLEFT")
    if minimal then
        left:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT")
        left:SetWidth(50)
        right:SetPoint("TOPLEFT", left, "TOPRIGHT")
    else
        left:SetPoint("BOTTOMRIGHT", panel, "BOTTOM")
        right:SetPoint("TOPLEFT", panel, "TOP")
    end
    right:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT")
end

function C.PaintDockGradient(strip, config)
    local r, g, b = S.RGB(config.panelColor)
    local minimal = config.minimalChrome
    local alpha = (minimal and config.panelAlpha or math.min(100, config.panelAlpha + 12)) / 100
    local first, last = CreateColor(r, g, b, alpha), CreateColor(r, g, b, minimal and 0 or alpha)
    strip:SetColorTexture(1, 1, 1, 1)
    strip:SetGradient("HORIZONTAL", first, last)
end

local function ChromeAlpha(visual, focused)
    if not M.config.minimalChrome then return 1 end
    if not visual then return 0 end
    if focused == nil then focused = visual.frame.editBox:HasFocus() end
    return (visual.hovered or focused) and 1 or 0
end

-- Background art appears only when the chat is in use. Incoming text keeps
-- Blizzard's native individual-message fading, without an empty dark box.
-- These are Suite-owned textures, so hover/focus can update them in combat.
function C.UpdateMinimalChrome(visual, focused)
    local alpha = ChromeAlpha(visual, focused)
    if visual.panel then visual.panel:SetAlpha(alpha) end
    if visual.gradientLeft then
        visual.gradientLeft:SetAlpha(alpha)
        visual.gradientRight:SetAlpha(alpha)
    end
    if M.dockStrip then
        local selected = M.visuals[C.DockSelection() or ChatFrame1]
        local dockFocus
        if selected == visual then dockFocus = focused end
        M.dockStrip:SetAlpha(ChromeAlpha(selected, dockFocus))
    end
end
