local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
-- One chat window: the suite panel, header, border and input bar around
-- Blizzard's own tab title. Chrome is owned through the context (shown state
-- or alpha) rather than destroyed. The primary window also gets the sidebar.
local M = C.M
local TAB_CHROME = {
    "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight",
}
local INPUT_CHROME = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }
-- fontOutline 1 keeps Blizzard's own outline.
local OUTLINES = { false, "OUTLINE", "THICKOUTLINE", "" }
local Fill, Tint, CombatLogBar, HeaderTop = C.Fill, C.Tint, C.CombatLogBar, C.HeaderTop
local OwnBorderedParts = C.OwnBorderedParts
local DockSelection, ApplySidebar, ApplyCopyButton = C.DockSelection, C.ApplySidebar, C.ApplyCopyButton
local RGB, Finite = S.RGB, S.Finite
local TAB_MIN_ALPHA = 0.8

local function CreateVisual(frame)
    local visual = { frame = frame }
    visual.panel = Fill(frame, "BACKGROUND")
    visual.headerRule = Fill(frame, "ARTWORK")
    visual.edges = {}
    for i = 1, 4 do visual.edges[i] = Fill(frame, "BORDER") end
    M.visuals[frame] = visual
    return visual
end

-- side 1 top, 2 bottom, 3 left, 4 right; the edges sit outside owner by pad.
local function ApplyEdge(edge, owner, side, size, pad, top, hex, alpha)
    if size <= 0 or alpha <= 0 then
        edge:Hide()
        return
    end
    edge:ClearAllPoints()
    if side == 1 then
        edge:SetPoint("TOPLEFT", owner, "TOPLEFT", -pad, top)
        edge:SetPoint("TOPRIGHT", owner, "TOPRIGHT", pad, top)
        edge:SetHeight(size)
    elseif side == 2 then
        edge:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", -pad, -pad)
        edge:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", pad, -pad)
        edge:SetHeight(size)
    elseif side == 3 then
        edge:SetPoint("TOPLEFT", owner, "TOPLEFT", -pad, top)
        edge:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", -pad, -pad)
        edge:SetWidth(size)
    else
        edge:SetPoint("TOPRIGHT", owner, "TOPRIGHT", pad, top)
        edge:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", pad, -pad)
        edge:SetWidth(size)
    end
    Tint(edge, hex, alpha)
    edge:Show()
end

-- Owns (alpha 0) or restores one region per part name: a parent key (tab
-- art) or a global named after the owner (edit box art).
local function OwnAlpha(context, owner, parts, globalPrefix, own)
    for i = 1, #parts do
        local suffix = parts[i]
        local texture = owner[suffix] or _G[globalPrefix .. suffix]
        if texture then
            if own then
                context:Alpha(texture, 0)
            else
                context:RestoreProperty(texture, "SetAlpha")
            end
        end
    end
end

local function OwnTab(context, tab, name, own)
    OwnAlpha(context, tab, TAB_CHROME, name .. "Tab", own)
    if own then
        context:Alpha(tab.Text, 1)
    else
        context:RestoreProperty(tab.Text, "SetAlpha")
    end
end

local function SetNativeChrome(self, frame, tab, input, enabled)
    local context, c = self.context, self.config
    local name = frame:GetName()
    -- Keep Blizzard's own FontString for every tab. Static and dynamic titles
    -- can change after this call, while whisper targets may be secret.
    local ownArt = enabled and c.tabPanel
    OwnBorderedParts(context, frame, enabled)
    OwnTab(context, tab, name, ownArt)
    OwnAlpha(context, input, INPUT_CHROME, name .. "EditBox", enabled and c.inputPanel)
    local quickTexture = CombatLogBar(frame) and _G.CombatLogQuickButtonFrame_CustomTexture
    if quickTexture then
        if enabled and c.tabPanel then
            context:Alpha(quickTexture, 0)
        else
            context:RestoreProperty(quickTexture, "SetAlpha")
        end
    end
end

function C.ColorTab(self, visual, selected)
    local c = self.config
    if c.tabPanel and c.panelAlpha > 0 then
        local r, g, b = RGB(selected and c.tabActiveColor or c.tabInactiveColor)
        self.context:Tuple(visual.tabLabel, "GetTextColor", "SetTextColor", r, g, b, 1)
    else
        self.context:RestoreTuple(visual.tabLabel, "SetTextColor")
    end
    visual.tabLine:SetShown(c.tabPanel and c.panelAlpha > 0
        and c.tabAccent and c.accentAlpha > 0 and selected)
end
local ColorTab = C.ColorTab

-- A docked window's tab is selected with its dock; a floating one always is.
function C.TabSelected(frame, chat, dock)
    if frame.isDocked == true then return frame == dock end
    if frame.isDocked == false then return true end
    return frame == chat or frame == dock
end
local TabSelected = C.TabSelected

-- Blizzard fades idle tabs to 0.2 alpha. The Suite strip keeps their labels
-- readable while leaving the native title, target and click behavior intact.
function C.KeepTabVisible(self, frame, release)
    local tab = _G[frame:GetName() .. "Tab"]
    local context = self.context
    if release or not (self.config.tabPanel and self.config.panelAlpha > 0) then
        context:RestoreFields(tab)
        context:RestoreProperty(tab, "SetAlpha")
        return
    end
    context:Field(tab, "noMouseAlpha", TAB_MIN_ALPHA)
    context:Field(tab, "mouseOverAlpha", 1)
    local alpha = tab:GetAlpha()
    if Finite(alpha) and alpha < TAB_MIN_ALPHA then
        context:Alpha(tab, TAB_MIN_ALPHA)
    end
end
local KeepTabVisible = C.KeepTabVisible

-- Underline the native tab without copying its FontString. Its text and
-- clipping stay with Blizzard even when another addon repaints the title.
local function ApplyTabVisual(self, visual, tab, selected)
    if not visual.tabLine then
        visual.tabLabel = tab.Text
        visual.tabLine = Fill(tab, "ARTWORK")
    end
    M.tabs[tab] = visual
    local line = visual.tabLine
    line:ClearAllPoints()
    line:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 5, 1)
    line:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -5, 1)
    line:SetHeight(2)
    Tint(line, self.config.accentColor, self.config.accentAlpha)
    ColorTab(self, visual, selected)
end

local function ApplyPanel(self, visual, frame, top)
    local c = self.config
    visual.panel:ClearAllPoints()
    -- The chat body's backdrop ends at the frame edge. Any texture extending
    -- into the dock row can cover native dynamic tabs in Retail.
    visual.panel:SetPoint("TOPLEFT", frame, "TOPLEFT", -c.padding, 0)
    visual.panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", c.padding, -c.padding)
    Tint(visual.panel, c.panelColor, c.panelAlpha)
    visual.panel:SetShown(c.panelAlpha > 0)
    if frame == _G.ChatFrame1 then
        local strip = M.dockStrip
        if not strip then
            strip = Fill(_G.GENERAL_CHAT_DOCK, "BACKGROUND")
            M.dockStrip = strip
        end
        -- Blizzard anchors the dock three pixels above its primary chat frame.
        -- Match the Suite body's padded width and its border top so neither
        -- side leaves a short corner or a gap above the message area.
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT", frame, "TOPLEFT", -c.padding, top)
        strip:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", c.padding, 0)
        Tint(strip, c.panelColor, math.min(100, c.panelAlpha + 12))
        strip:SetShown(c.tabPanel and c.panelAlpha > 0)
    end
    visual.headerRule:ClearAllPoints()
    visual.headerRule:SetPoint("TOPLEFT", frame, "TOPLEFT", -c.padding, 0)
    visual.headerRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", c.padding, 0)
    visual.headerRule:SetHeight(1)
    Tint(visual.headerRule, c.borderColor, math.min(55, c.borderAlpha))
    visual.headerRule:SetShown(c.tabPanel and c.panelAlpha > 0)
    for side = 1, 4 do
        ApplyEdge(visual.edges[side], frame, side, c.borderSize, c.padding, top, c.borderColor, c.borderAlpha)
    end
end

local function ApplyInput(self, visual, frame, input)
    local c = self.config
    if not visual.input then visual.input = Fill(input, "BACKGROUND") end
    -- Blizzard's edit box deliberately overhangs the chat frame on both
    -- sides. Keep its native hit area and text, but align our visible bar
    -- with the chat panel. Both anchors follow frame moves and resizes.
    local inputHeight = input:GetHeight()
    if not Finite(inputHeight) or inputHeight <= 0 then inputHeight = 26 end
    -- Blizzard can enlarge the edit box while focused; only our background
    -- stays compact. The native edit box keeps its hit area and autocomplete.
    inputHeight = math.min(inputHeight, 26)
    visual.input:ClearAllPoints()
    visual.input:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -c.padding, 0)
    visual.input:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", c.padding, -(inputHeight + 4))
    Tint(visual.input, c.inputColor, c.inputAlpha)
    visual.input:SetShown(c.inputPanel and c.inputAlpha > 0)
    if not visual.inputEdges then
        visual.inputEdges = {}
        for i = 1, 4 do visual.inputEdges[i] = Fill(input, "BORDER") end
    end
    for i = 1, 4 do
        local edge = visual.inputEdges[i]
        ApplyEdge(edge, visual.input, i, math.max(1, c.borderSize), 0, 0, c.borderColor, math.min(60, c.borderAlpha))
        edge:SetShown(c.inputPanel and c.inputAlpha > 0 and c.borderSize > 0)
    end
end

-- The catalog defines every font setting; "" (no font) resolves to nil.
local function ApplyFont(self, frame)
    local c, context = self.config, self.context
    local chosenFont = S.ResolveFont(c.font)
    local custom = chosenFont or c.fontSize > 0 or c.fontOutline ~= 1 or c.fontRendering ~= 1
    if custom then
        local path, size, flags = frame:GetFont()
        -- Blizzard's chat menu resizes the font we set. A size other than
        -- the one we applied is Blizzard's new size: fontSize 0 follows
        -- it, and disabling restores it.
        local owned, originalPath, originalSize, originalFlags =
            context:UpdateTupleBefore(frame, "SetFont", 2, size)
        if owned then path, size, flags = originalPath, originalSize, originalFlags end
        if S.Public(path) and S.Public(size) and S.Public(flags)
            and type(path) == "string" and type(size) == "number" then
            local outline = OUTLINES[c.fontOutline]
            context:Tuple(frame, "GetFont", "SetFont", chosenFont or path,
                c.fontSize > 0 and c.fontSize or size, S.FontFlags(outline or flags, c.fontRendering))
        end
    else
        context:RestoreTuple(frame, "SetFont")
    end
    -- Shadow 1 follows Blizzard, 2 is on, 3 off (Slug never draws one).
    local shadow = c.fontRendering == 3 and 3 or c.fontShadow
    if shadow == 1 then
        context:RestoreTuple(frame, "SetShadowColor")
        context:RestoreTuple(frame, "SetShadowOffset")
    elseif shadow == 2 then
        context:Tuple(frame, "GetShadowColor", "SetShadowColor", 0, 0, 0, c.fontShadowOpacity / 100)
        local distance = c.fontShadowDistance
        context:Tuple(frame, "GetShadowOffset", "SetShadowOffset", distance, -distance)
    else
        context:Tuple(frame, "GetShadowColor", "SetShadowColor", 0, 0, 0, 0)
        context:Tuple(frame, "GetShadowOffset", "SetShadowOffset", 0, 0)
    end
end

-- Every chat window is a ChatFrameN from Blizzard's floating chat frame
-- template: a ChatFrameNTab tab (created with it) and an editBox parent key.
function C.ApplyWindow(self, frame)
    if not frame or NS.Safety.IsForbidden(frame) then return end
    local c = self.config
    local visual = M.visuals[frame] or CreateVisual(frame)
    local top = HeaderTop(c, frame)
    ApplyPanel(self, visual, frame, top)
    local tab, input = _G[frame:GetName() .. "Tab"], frame.editBox
    SetNativeChrome(self, frame, tab, input, c.panelAlpha > 0)
    ApplyTabVisual(self, visual, tab, TabSelected(frame, _G.SELECTED_CHAT_FRAME, DockSelection()))
    KeepTabVisible(self, frame)
    if frame == _G.ChatFrame1 then ApplySidebar(self, visual, frame) end
    ApplyCopyButton(self, visual, frame, top)
    ApplyInput(self, visual, frame, input)
    ApplyFont(self, frame)
end

local function HideVisual(visual)
    visual.panel:Hide()
    if visual.frame == _G.ChatFrame1 and M.dockStrip then M.dockStrip:Hide() end
    visual.headerRule:Hide()
    for i = 1, 4 do visual.edges[i]:Hide() end
    if visual.tabLine then visual.tabLine:Hide() end
    if visual.sidebar then visual.sidebar:Hide() end
    if visual.sidebarFrame then visual.sidebarFrame:Hide() end
    if visual.copyButton then visual.copyButton:Hide() end
    if visual.input then visual.input:Hide() end
    if visual.inputEdges then for i = 1, 4 do visual.inputEdges[i]:Hide() end end
end

-- Hides the suite layers of one window and hands its chrome back.
function C.ReleaseWindow(self, visual)
    HideVisual(visual)
    local frame = visual.frame
    local tab = _G[frame:GetName() .. "Tab"]
    SetNativeChrome(self, frame, tab, frame.editBox, false)
    if visual.tabLabel then self.context:RestoreTuple(visual.tabLabel, "SetTextColor") end
    M.tabs[tab] = nil
    KeepTabVisible(self, frame, true)
end
