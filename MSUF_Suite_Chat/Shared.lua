local _, P = ...
local S = P.Suite
-- Native chat styling. The Chat files share the private table below and load
-- in TOC order, with Controller installing M. Native chrome updates when
-- windows, tabs or settings change. Optional message tools and speech bubbles
-- process their own events only while enabled. Changes to Blizzard frames go
-- through the module context, so Disable hands back exactly what it changed.
local C = {}
P.Chat = C
local M = {
    visuals = setmetatable({}, { __mode = "k" }), tabs = setmetatable({}, { __mode = "k" }),
    hookedTemporary = false, hookedNewWindow = false,
    hookedSelect = false, hookedTabAlpha = false, hookedTabColors = false,
}
C.M = M
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Blizzard's FloatingBorderedFrame parts, shared by every chat window and by
-- its button frame: Background is a parent key, the border textures carry
-- the frame's name.
local BORDERED_PARTS = {
    "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture",
    "BottomRightTexture", "LeftTexture", "RightTexture", "TopTexture", "BottomTexture",
}
local RGB, Finite = S.RGB, S.Finite

-- Hides (own) or restores a bordered frame's chrome through the context.
function C.OwnBorderedParts(context, frame, own)
    local name = frame:GetName()
    for i = 1, #BORDERED_PARTS do
        local suffix = BORDERED_PARTS[i]
        local texture = frame[suffix] or _G[name .. suffix]
        if texture then
            if own then
                context:Property(texture, "IsShown", "SetShown", false)
            else
                context:RestoreProperty(texture, "SetShown")
            end
        end
    end
end

-- Chat moves frames (a geometry module), so a listener waits for the end of
-- combat unless it is registered here (the context's allowCombat). These
-- handlers touch only text, sounds and speech bubbles, never a protected
-- frame.
function C.ListenInCombat(context, event, callback)
    context:Event(event, callback, true)
end

function C.Fill(owner, layer)
    local texture = S.CreateTexture(owner, nil, layer)
    texture:SetTexture(WHITE)
    return texture
end

function C.Tint(texture, hex, alpha)
    local r, g, b = RGB(hex)
    texture:SetColorTexture(r, g, b, alpha / 100)
end

-- A class token's color as "rrggbb", or nil while the token or its color is
-- unreadable. Shared by the sidebar icons and the group-name coloring.
function C.ClassHex(token)
    if not S.Public(token) then return end
    local r, g, b = S.ClassRGB(token)
    if not (Finite(r) and Finite(g) and Finite(b)) then return end
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

function C.ShowTooltip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(text)
    GameTooltip:Show()
end

-- The shared tooltip is hidden only while owner still owns it.
function C.HideTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

-- Blizzard_CombatLog gives only the combat log window (ChatFrame2) its
-- filter row, the same field Blizzard's own chat layout reads.
local function CombatLogBar(frame)
    return frame.CombatLogQuickButtonFrame
end
C.CombatLogBar = CombatLogBar

-- Height of the tab strip above a window: the combat log filter row joins it.
function C.HeaderTop(config, frame)
    if not config.tabPanel then return config.padding end
    local top = (config.tabHeight or 24) + (config.tabPanelGap or 0)
    local quickBar = CombatLogBar(frame)
    if quickBar then
        local height = quickBar:GetHeight()
        if Finite(height) and height > 0 then top = top + height + 3 end
    end
    return top
end

-- The docked window whose tab is selected; GENERAL_CHAT_DOCK exists from the
-- start on both clients (FloatingChatFrame.xml).
function C.DockSelection()
    return _G.GENERAL_CHAT_DOCK.selected or _G.SELECTED_DOCK_FRAME
end
