local _, P = ...
local S = P.Suite
-- Native chat styling. The Chat files share the private table below and load
-- in this order: Shared, Sidebar, Copy, Window, Controller (Controller
-- installs M). Work runs only when chat windows, tabs, friends or settings
-- change, never on the message path. Every change to a Blizzard frame goes
-- through the module context, so Disable hands back exactly what it changed.
local C = {}
P.Chat = C
local M = {
    visuals = setmetatable({}, { __mode = "k" }), hookedTemporary = false, hookedNewWindow = false,
    hookedSelect = false, hookedTabAlpha = false,
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

function C.Fill(owner, layer)
    local texture = S.CreateTexture(owner, nil, layer)
    texture:SetTexture(WHITE)
    return texture
end

function C.Tint(texture, hex, alpha)
    local r, g, b = RGB(hex)
    texture:SetColorTexture(r, g, b, alpha / 100)
end

function C.ShowTooltip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(text)
    GameTooltip:Show()
end

function C.HideTooltip()
    GameTooltip:Hide()
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
    local top = 24
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
