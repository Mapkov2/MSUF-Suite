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

-- enabled: the Suite panel shows, so its parts replace Blizzard's chrome.
local function SetNativeChrome(self, frame, tab, input, enabled, ownTabArt)
    local context, c = self.context, self.config
    local name = frame:GetName()
    -- Keep Blizzard's own FontString for every tab. Static and dynamic titles
    -- can change after this call, while whisper targets may be secret.
    local ownArt = (enabled or ownTabArt) and (c.tabPanel or c.hideTabArt)
    OwnBorderedParts(context, frame, enabled)
    OwnTab(context, tab, name, ownArt)
    OwnAlpha(context, input, INPUT_CHROME, name .. "EditBox", enabled and c.inputPanel)
    local quickTexture = CombatLogBar(frame) and _G.CombatLogQuickButtonFrame_CustomTexture
    if quickTexture then
        if ownArt then
            context:Alpha(quickTexture, 0)
        else
            context:RestoreProperty(quickTexture, "SetAlpha")
        end
    end
end

-- Hands every native chrome part of the window back.
local function ReleaseNativeChrome(self, frame, tab)
    SetNativeChrome(self, frame, tab, frame.editBox, false)
end

function C.ColorTab(self, visual, selected)
    if selected then C.ClearUnread(visual) end
    local c = self.config
    if C.HasTabStyle(c) then
        local r, g, b = RGB(selected and c.tabActiveColor or c.tabInactiveColor)
        if selected and c.tabClassColor then
            local _, class = UnitClass("player")
            local cr, cg, cb = S.ClassRGB(class)
            if cr then r, g, b = cr, cg, cb end
        end
        self.context:TextColor(visual.tabLabel, r, g, b, 1)
    else
        self.context:RestoreTuple(visual.tabLabel, "SetTextColor")
    end
    visual.tabLine:SetShown(C.HasTabStyle(c)
        and c.tabAccent and c.accentAlpha > 0 and selected)
    if visual.tabFill then
        local panels = c.tabIndividualPanels and c.tabPanel and c.panelAlpha > 0
        local fill = selected and (c.tabActiveBackground or c.panelColor) or (c.tabInactiveBackground or c.panelColor)
        Tint(visual.tabFill, fill, selected and (c.tabActiveAlpha or c.panelAlpha) or (c.tabInactiveAlpha or c.panelAlpha))
        visual.tabFill:SetShown(panels == true)
        local border = selected and (c.tabActiveBorder or c.borderColor) or (c.tabInactiveBorder or c.borderColor)
        for i, edge in ipairs(visual.tabEdges) do
            ApplyEdge(edge, visual.tabFill, i, panels and (c.tabBorderSize or 0) or 0, 0, 0, border, c.borderAlpha)
            if c.borderTexture and c.borderTexture ~= "" then
                edge:SetTexture(S.ResolveTexture(c.borderTexture) or c.borderTexture)
                local r, g, b = RGB(selected and c.tabActiveBorder or c.tabInactiveBorder)
                edge:SetVertexColor(r, g, b, c.borderAlpha / 100)
            end
        end
    end
end
local ColorTab = C.ColorTab

-- A docked window's tab is selected with its dock; a floating one always is.
-- Blizzard stores isDocked as 1 or nil (FCFDock_AddChatFrame/RemoveChatFrame).
function C.TabSelected(frame, _, dock)
    if frame.isDocked then return frame == dock end
    return true
end
local TabSelected = C.TabSelected

-- Blizzard fades the tab frame itself: FCF_FadeIn/OutChatFrame run
-- UIFrameFade on it from FCF_OnUpdate toward its mouse-over or no-mouse alpha
-- (Forever keeps those in ChatFrameUtil side tables), and FCFTab_UpdateAlpha
-- sets it in each dock layout. With the tab style, the tab's regions -- its
-- label, its art and the Suite strip -- ignore that alpha and show at their
-- own, so neither a hook on those fades nor a poll is needed: idle chat runs
-- no Suite code. The glow keeps Blizzard's alert flash. Ignore-parent-alpha
-- is a widget state of unprotected regions, set in or out of combat and
-- handed back on release; no Blizzard field or fade list is written. An
-- idle-faded window's regions follow the tab frame again (Fade.lua).
local function ReleaseTabRegions(visual)
    local held = visual.heldTab
    if not held then return end
    for region, ignore in pairs(held) do
        region:SetIgnoreParentAlpha(ignore)
        held[region] = nil
    end
end

local function HoldTabRegions(visual, tab)
    local held = visual.heldTab or {}
    visual.heldTab = held
    local regions, glow = { tab:GetRegions() }, tab.glow
    for _, region in ipairs(regions) do
        if region ~= glow then
            if held[region] == nil then
                local ignore = region:IsIgnoringParentAlpha()
                if S.Public(ignore) then held[region] = ignore == true end
            end
            if held[region] ~= nil then region:SetIgnoreParentAlpha(true) end
        end
    end
end

-- Hands the tab's alpha back to Blizzard (the tab frame and its regions).
local function ReleaseTabAlpha(context, tab, visual)
    context:RestoreProperty(tab, "SetAlpha")
    if visual then ReleaseTabRegions(visual) end
end

-- Cold path (ApplyWindow) and Fade.lua's wake.
function C.KeepTabVisible(self, frame)
    local tab, visual = _G[frame:GetName() .. "Tab"], self.visuals[frame]
    if not (visual and C.HasTabStyle(self.config)) then
        ReleaseTabAlpha(self.context, tab, visual)
        return
    end
    -- An idle-faded window keeps its faded tab (Fade.lua hands it back).
    if visual.faded then return end
    HoldTabRegions(visual, tab)
end
local KeepTabVisible = C.KeepTabVisible

-- Fade.lua, before an idle fade: the regions follow the tab frame again,
-- and the fade starts from the alpha they showed (1). The context owns that
-- alpha (an unprotected tab, also in combat) and hands Blizzard's back.
function C.TabFollowsFrame(visual)
    local tab = visual.tab
    if not (tab and visual.heldTab and next(visual.heldTab)) then return end
    ReleaseTabRegions(visual)
    M.context:UnprotectedProperty(tab, "GetAlpha", "SetAlpha", 1)
end

local function ChosenFont(key)
    if key == "__BLIZZARD_CHAT_FONT__" then return nil end
    return S.ResolveFont(key) or S.GlobalFontPath()
end

function S.ChatStylePreviewFonts(parts, fonts, c)
    for index, tab in ipairs(parts.tabs) do
        local native = parts.nativeTabs and parts.nativeTabs[index]
        local path = ChosenFont(c.tabFont) or native and native.font or fonts.tab
        local size = c.tabFontSize > 0 and c.tabFontSize or native and native.fontSize or fonts.tabSize
        tab.Text:SetFont(path, size, native and native.fontFlags or fonts.tabFlags)
        if native and native.label then tab.Text:SetText(native.label) end
    end
    local path = ChosenFont(c.font) or fonts.message
    local outline = OUTLINES[c.fontOutline] or fonts.messageFlags
    local shadow = c.fontRendering ~= 3 and (c.fontShadow == 2 or c.fontShadow == 1 and fonts.shadowAlpha > 0)
    local opacity = c.fontShadow == 1 and fonts.shadowAlpha * 100 or c.fontShadowOpacity
    local distance = c.fontShadow == 1 and fonts.shadowX or c.fontShadowDistance
    for _, line in ipairs(parts.messageLines) do
        S.SetStyledFont(line, path, c.fontSize > 0 and c.fontSize or fonts.messageSize,
            outline, c.fontRendering, shadow, opacity, distance)
        if c.fontRendering ~= 3 and c.fontShadow == 1 and fonts.shadowY then
            line:SetShadowColor(fonts.shadowR, fonts.shadowG, fonts.shadowB, fonts.shadowAlpha)
            line:SetShadowOffset(fonts.shadowX, fonts.shadowY)
        end
    end
end

-- Keep Blizzard's tab FontString and title updates. Only its font tuple is
-- owned, so disabling Chat hands its original face and size back.
local function ApplyTabFont(self, label, chosenFont)
    local c, context = self.config, self.context
    local custom = chosenFont or c.tabFontSize > 0
    if not custom then
        context:RestoreTuple(label, "SetFont")
        return
    end
    local path, size, flags = label:GetFont()
    local owned, originalPath, originalSize, originalFlags =
        context:UpdateTupleBefore(label, "SetFont", 2, size)
    if owned then path, size, flags = originalPath, originalSize, originalFlags end
    if S.Public(path) and S.Public(size) and S.Public(flags)
        and type(path) == "string" and type(size) == "number" then
        context:Tuple(label, "GetFont", "SetFont", chosenFont or path,
            c.tabFontSize > 0 and c.tabFontSize or size, flags)
    end
end

-- tabPadding > 0: the tab is as wide as its title plus the padding on both
-- sides. Blizzard sizes docked tabs again whenever it lays the dock out
-- (FCFDock_UpdateTabs -> PanelTemplates_TabResize -> tab:SetWidth, also on
-- a tab click), so C.DockGeometry puts the padded width back after it.
-- Temporary tabs anchor their title 24px from the left for the conversation
-- icon. Keep their native width: it includes that offset and fits the dock,
-- while Blizzard bounds whisper text without measuring a secret name.
local function ApplyTabWidth(self, visual, tab)
    local c, context = self.config, self.context
    if c.tabPadding and c.tabPadding > 0 and not tab.conversationIcon then
        local width = visual.tabLabel:GetUnboundedStringWidth()
        if Finite(width) then
            context:Property(tab, "GetWidth", "SetWidth", width + 2 * c.tabPadding)
            visual.tabWidthOwned = true
        end
    elseif visual.tabWidthOwned then
        context:RestoreProperty(tab, "SetWidth")
        visual.tabWidthOwned = nil
    end
end

-- ChatTabTemplate centers ordinary text at -5. Temporary tabs hang their
-- title and conversation icon off the fixed-height left art instead.
local function ApplyWhisperBaseline(self, visual, tab)
    local label = visual.tabLabel
    if not (self.config.tabPanel and visual.frame.isDocked and tab.conversationIcon) then
        if visual.whisperBaseline then self.context:RestorePoints(label) end
        visual.whisperBaseline = nil
        return
    end
    if not NS.Safety.CanAnchor(label) then return end
    local points = label:GetNumPoints()
    if not Finite(points) or points ~= 1 then return end
    local point, relative, edge, x, y = label:GetPoint(1)
    if not (S.Public(point) and S.Public(relative) and S.Public(edge) and Finite(x) and Finite(y)
        and point == "LEFT" and relative and relative == tab.Left and edge == "RIGHT") then return end
    local artHeight, tabHeight = relative:GetHeight(), tab:GetHeight()
    if not (Finite(artHeight) and Finite(tabHeight)) then return end
    local baseline = (tabHeight - artHeight) * .5 - 5
    if y ~= baseline then
        self.context:Anchor(label, point, relative, edge, x, baseline)
        visual.whisperBaseline = true
    end
end

function C.ApplyTabGeometry(self, visual, tab)
    local c, context = self.config, self.context
    if visual.tabFill then
        -- ChatTabArtTemplate is 32px tall and the native dock starts 3px
        -- above the message frame (upstream/live FloatingChatFrame.lua/xml).
        -- Paint only the Suite header row, leaving Blizzard's hit area alone.
        visual.tabFill:ClearAllPoints()
        visual.tabFill:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, -3)
        visual.tabFill:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, -3)
        visual.tabFill:SetHeight(c.tabHeight or 24)
    end
    if (c.tabHeight or 24) ~= 24 then
        context:Property(tab, "GetHeight", "SetHeight", c.tabHeight)
        visual.tabHeightOwned = true
    elseif visual.tabHeightOwned then
        context:RestoreProperty(tab, "SetHeight")
        visual.tabHeightOwned = nil
    end
    ApplyTabWidth(self, visual, tab)
end

-- Underline the native tab without copying its FontString. Its text and
-- clipping stay with Blizzard even when another addon repaints the title.
local function ApplyTabVisual(self, visual, tab, selected, chosenFont)
    if not visual.tabLine then
        visual.tabLabel = tab.Text
        visual.tabLine = Fill(tab, "ARTWORK")
    end
    local c, context = self.config, self.context
    if c.tabIndividualPanels and c.tabPanel and c.panelAlpha > 0 and not visual.tabFill then
        visual.tabFill = Fill(tab, "BACKGROUND")
        visual.tabEdges = {}
        for i = 1, 4 do visual.tabEdges[i] = Fill(tab, "BORDER") end
    end
    ApplyTabFont(self, visual.tabLabel, chosenFont)
    C.ApplyTabGeometry(self, visual, tab)
    ApplyWhisperBaseline(self, visual, tab)
    M.tabs[tab], visual.tab = visual, tab
    local line = visual.tabLine
    C.PlaceTabMarker(line, tab, c)
    Tint(line, c.accentColor, c.accentAlpha)
    ColorTab(self, visual, selected)
end

local function ApplyPanel(self, visual, frame, top)
    local c = self.config
    visual.panel:ClearAllPoints()
    -- The chat body's backdrop ends at the frame edge. Any texture extending
    -- into the dock row can cover native dynamic tabs in Retail.
    visual.panel:SetPoint("TOPLEFT", frame, "TOPLEFT", -c.padding, c.tabPanel and 0 or top)
    visual.panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", c.padding, -c.padding)
    Tint(visual.panel, c.panelColor, c.panelAlpha)
    if c.panelTexture and c.panelTexture ~= "" then
        visual.panel:SetTexture(S.ResolveTexture(c.panelTexture) or c.panelTexture)
        local r, g, b = RGB(c.panelColor)
        visual.panel:SetVertexColor(r, g, b, c.panelAlpha / 100)
    end
    visual.panel:SetShown(c.panelAlpha > 0)
    C.PaintGradient(visual, visual.panel, c)
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
        strip:SetPoint("TOPLEFT", frame, "TOPLEFT", -c.padding + (c.tabX or 0), top + (c.tabY or 0))
        strip:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", c.padding + (c.tabX or 0), c.tabY or 0)
        C.PaintDockGradient(strip, c)
        strip:SetShown(c.tabPanel and c.panelAlpha > 0)
    end
    visual.headerRule:ClearAllPoints()
    visual.headerRule:SetPoint("TOPLEFT", frame, "TOPLEFT", -c.padding, 0)
    visual.headerRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", c.padding, 0)
    visual.headerRule:SetHeight(2)
    Tint(visual.headerRule, c.accentColor, c.accentAlpha)
    visual.headerRule:SetShown(c.tabPanel and c.panelAlpha > 0
        and c.tabAccent and c.accentAlpha > 0 and not c.minimalChrome)
    for side = 1, 4 do
        local edge = visual.edges[side]
        ApplyEdge(edge, frame, side, c.borderSize, c.padding, top, c.borderColor, c.borderAlpha)
        if c.borderTexture and c.borderTexture ~= "" then
            edge:SetTexture(S.ResolveTexture(c.borderTexture) or c.borderTexture)
            local r, g, b = RGB(c.borderColor)
            edge:SetVertexColor(r, g, b, c.borderAlpha / 100)
        end
    end
end

local function InputWidth(c, frame)
    local width = c.inputWidth or 0
    if width > 0 then return width end
    width = frame:GetWidth()
    if Finite(width) and width > 0 then return width + 2 * c.padding end
end

local function ApplyInput(self, visual, frame, input)
    if NS.Safety.IsForbidden(input) then return end
    if not self.preview and C.LayoutLocked() then
        S.Queue("chat")
        return
    end
    local c, context = self.config, self.context
    local width = InputWidth(c, frame)
    if not width then return end
    if not self.preview then
        if c.lockWindowPosition or S.editMode then
            context:Property(input, "IsClampedToScreen", "SetClampedToScreen", true)
        else
            context:RestoreProperty(input, "SetClampedToScreen")
        end
    end
    -- Own one left anchor and a width so the text, hit area and panel move together.
    context:RestorePoints(input)
    local x, y = -c.padding + c.inputX, c.inputY
    if c.inputTop then
        context:Anchor(input, "BOTTOMLEFT", frame, "TOPLEFT", x, HeaderTop(c, frame, self.preview) + 2 + y)
    else
        context:Anchor(input, "TOPLEFT", frame, "BOTTOMLEFT", x, y - c.padding - 2)
    end
    context:Property(input, "GetWidth", "SetWidth", width)
    if c.inputHeight > 0 then
        context:Property(input, "GetHeight", "SetHeight", c.inputHeight)
    else
        context:RestoreProperty(input, "SetHeight")
    end
    if not visual.input then
        visual.input = Fill(input, "BACKGROUND")
        visual.input:SetAllPoints(input)
        visual.inputEdges = {}
        for i = 1, 4 do visual.inputEdges[i] = Fill(input, "BORDER") end
    end
    Tint(visual.input, c.inputColor, c.inputAlpha)
    visual.input:SetShown(c.inputPanel and c.inputAlpha > 0)
    for i = 1, 4 do
        local edge = visual.inputEdges[i]
        ApplyEdge(edge, visual.input, i, math.max(1, c.borderSize), 0, 0, c.borderColor, math.min(60, c.borderAlpha))
        edge:SetShown(c.inputPanel and c.inputAlpha > 0 and c.borderSize > 0)
    end
end

-- Suite.ChatState layout and window callbacks (a window's size follows
-- Blizzard's layout, a drag or Edit Mode): no OnSizeChanged hook on the
-- chat frame, whose resize Blizzard's own dock code dispatches.
function C.ResizeInput(frame)
    local visual = M.visuals[frame]
    if not M.active or not visual or not visual.input or (M.config.inputWidth or 0) ~= 0 then return end
    local current = frame:GetWidth()
    local width = InputWidth(M.config, frame)
    local applied = frame.editBox:GetWidth()
    if S.Finite(width) and S.Finite(applied) and math.abs(applied - width) < .01 then
        visual.inputFollowWidth = current
        return
    end
    if C.LayoutLocked() then
        S.Queue("chat")
        return
    end
    if width then M.context:Property(frame.editBox, "GetWidth", "SetWidth", width) end
    visual.inputFollowWidth = current
end

function C.ApplyInputLayout(self, visual, frame, input)
    ApplyInput(self, visual, frame, input)
    if not self.preview then visual.inputFollowWidth = frame:GetWidth() end
end

-- Inspect our actual applied anchor, including native screen clamping. A
-- native input reset can leave the window itself completely unchanged.
function C.InputGeometryChanged(frame)
    local m, input = M, frame.editBox
    local visual = m.visuals[frame]
    if not visual or not visual.input or not input or NS.Safety.IsForbidden(input) then return false end
    local width, current = InputWidth(m.config, frame), input:GetWidth()
    if not S.Finite(width) or not S.Finite(current) then return false end
    if math.abs(width - current) >= .01 then return true end
    local height = input:GetHeight()
    if m.config.inputHeight > 0 and S.Finite(height) and math.abs(height - m.config.inputHeight) >= .01 then return true end
    local record = m.context.points and m.context.points[input]
    if not record or not S.Finite(record.x) or not S.Finite(record.y) then return true end
    local point, relative, edge, x, y = input:GetPoint(1)
    local count = input:GetNumPoints()
    if not (S.Public(point) and S.Public(relative) and S.Public(edge)
        and S.Finite(x) and S.Finite(y) and S.Finite(count)) then return false end
    return count ~= 1 or point ~= record.point or relative ~= record.relative
        or edge ~= record.relativePoint or math.abs(x - record.x) >= .01 or math.abs(y - record.y) >= .01
end

-- An empty Suite choice follows MSUF; Blizzard's chat font remains an
-- explicit option and keeps its native ownership and size controls.
local function ApplyFont(self, frame, chosenFont)
    local c, context = self.config, self.context
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

-- lockWindowSize keeps the primary window at the chosen size.
local function ApplySizeLock(self, visual, frame, primary)
    local c, context = self.config, self.context
    if primary and c.lockWindowSize then
        context:Property(frame, "GetWidth", "SetWidth", c.windowWidth or 420)
        context:Property(frame, "GetHeight", "SetHeight", c.windowHeight or 180)
        context:Property(frame, "IsResizable", "SetResizable", false)
        visual.sizeLocked = true
    elseif visual.sizeLocked then
        context:RestoreProperty(frame, "SetWidth")
        context:RestoreProperty(frame, "SetHeight")
        context:RestoreProperty(frame, "SetResizable")
        visual.sizeLocked = nil
    end
end

-- Size and position settle before the input reads its followed width. The
-- same input painter is used by the live window and the options preview.
function C.ApplyWindowGeometry(self, visual, frame, keepPosition)
    local primary = frame == self.positionFrame
    if frame == _G.ChatFrame1 then primary = true end
    ApplySizeLock(self, visual, frame, primary)
    if not keepPosition then C.ApplyWindowPosition(self, visual, frame, primary) end
    if frame.editBox then C.ApplyInputLayout(self, visual, frame, frame.editBox) end
end

-- Every chat window is a ChatFrameN from Blizzard's floating chat frame
-- template: a ChatFrameNTab tab (created with it) and an editBox parent key.
function C.ApplyWindow(self, frame, keepPosition)
    if not frame or NS.Safety.IsForbidden(frame) then return end
    local c, primary = self.config, frame == _G.ChatFrame1
    local visual = M.visuals[frame] or CreateVisual(frame)
    local top = HeaderTop(c, frame)
    ApplyPanel(self, visual, frame, top)
    local tab, input = _G[frame:GetName() .. "Tab"], frame.editBox
    local tabFont, messageFont = ChosenFont(c.tabFont), ChosenFont(c.font)
    SetNativeChrome(self, frame, tab, input, c.panelAlpha > 0 or c.minimalChrome, c.hideTabArt)
    ApplyTabVisual(self, visual, tab, TabSelected(frame, _G.SELECTED_CHAT_FRAME, DockSelection()), tabFont)
    C.ApplyUnread(visual, tab)
    KeepTabVisible(self, frame)
    if primary then ApplySidebar(self, visual, frame) end
    ApplyCopyButton(self, visual, frame, top)
    C.ApplyClock(visual, frame, c, top)
    C.ApplyWindowGeometry(self, visual, frame, keepPosition)
    if c.animateInput or visual.inputAnimated then
        C.ApplyInputAnimation(self, input)
        visual.inputAnimated = c.animateInput
    end
    ApplyFont(self, frame, messageFont)
    local spacing = C.MessageSpacing(c)
    if spacing then
        self.context:Property(frame, "GetSpacing", "SetSpacing", spacing)
    elseif visual.customSpacing then
        self.context:RestoreProperty(frame, "SetSpacing")
    end
    visual.customSpacing = spacing
    C.ApplyCompleteMessages(self, frame)
    -- The scrollback limit comes first: the saved ring replays into its room.
    C.ApplyLineLimit(self, frame)
    C.ApplyInputHistory(self, frame)
    C.ApplyMessageFade(visual, c)
    C.ApplyInactivity(self, visual)
    C.UpdateMinimalChrome(visual)
end

local function HideVisual(visual)
    if visual.headerClock then visual.headerClock:Hide() end
    C.HideGradient(visual)
    C.ClearUnread(visual)
    C.ReleaseMessageFade(visual)
    visual.panel:Hide()
    if visual.frame == _G.ChatFrame1 and M.dockStrip then M.dockStrip:Hide() end
    visual.headerRule:Hide()
    for i = 1, 4 do visual.edges[i]:Hide() end
    if visual.tabLine then visual.tabLine:Hide() end
    if visual.tabFill then
        visual.tabFill:Hide()
        for _, edge in ipairs(visual.tabEdges) do edge:Hide() end
    end
    if visual.sidebar then visual.sidebar:Hide() end
    if visual.sidebarFrame then visual.sidebarFrame:Hide() end
    if visual.copyButton then visual.copyButton:Hide() end
    if visual.input then visual.input:Hide() end
    if visual.inputEdges then for i = 1, 4 do visual.inputEdges[i]:Hide() end end
end

-- Hides the suite layers of one window and hands its chrome back.
function C.ReleaseWindow(self, visual)
    C.ReleaseCompleteMessages(visual.frame)
    HideVisual(visual)
    local frame = visual.frame
    local tab = _G[frame:GetName() .. "Tab"]
    ReleaseNativeChrome(self, frame, tab)
    if visual.tabLabel then
        if visual.whisperBaseline then self.context:RestorePoints(visual.tabLabel) end
        visual.whisperBaseline = nil
        self.context:RestoreTuple(visual.tabLabel, "SetTextColor")
        self.context:RestoreTuple(visual.tabLabel, "SetFont")
    end
    if self.alignedDockLead == tab then
        self.context:RestorePoints(tab)
        self.alignedDockLead = nil
    end
    M.tabs[tab] = nil
    ReleaseTabAlpha(self.context, tab, visual)
end

-- tabGap > 0: docked tabs keep that much room between them. Blizzard's
-- FCFDock_UpdateTabs lays the dock out again; after it, each tab moves right
-- of the previous tab of its row (static tabs, then dynamic ones), and every
-- styled tab gets its padded width back (ApplyTabWidth). In combat the dock
-- waits: with padding or a gap on, the module applies again once combat ends.
local spacedTabs = setmetatable({}, { __mode = "k" })

local function DynamicDockLead(dock)
    local docked = dock.DOCKED_CHAT_FRAMES
    for i = 1, math.min(#docked, 64) do
        local frame = docked[i]
        if NS.Safety.IsForbidden(frame) then return end
        if not frame.isStaticDocked then return _G[frame:GetName() .. "Tab"] end
    end
end

-- Preserve the scroll child's horizontal origin. The native first dynamic
-- tab is center-anchored inside the scroll frame, so shortening the buttons
-- moves it above the bottom-anchored static row.
local function AlignDynamicDockLead(dock)
    local tab = M.config.tabPanel and DynamicDockLead(dock) or nil
    local previous = M.alignedDockLead
    if previous and previous ~= tab then
        M.context:RestorePoints(previous)
        M.alignedDockLead = nil
    end
    local scrollFrame = dock.scrollFrame
    local child = tab and M.tabs[tab] and scrollFrame and scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
    if not child or not NS.Safety.CanAnchor(tab) then return end
    if spacedTabs[tab] then
        M.context:RestorePoints(tab)
        spacedTabs[tab] = nil
    end
    local points = tab:GetNumPoints()
    if not Finite(points) or points ~= 1 then return end
    local point, relative, edge, x, y = tab:GetPoint(1)
    if not (S.Public(point) and S.Public(relative) and S.Public(edge) and Finite(x) and Finite(y)
        and relative == child) then return end
    local native = point == "LEFT" and edge == "LEFT"
    if not native and not (previous == tab and point == "BOTTOMLEFT" and edge == "BOTTOMLEFT") then return end
    local dockBottom, childBottom = dock:GetBottom(), child:GetBottom()
    local dockScale, childScale, tabScale = dock:GetEffectiveScale(), child:GetEffectiveScale(), tab:GetEffectiveScale()
    if not (Finite(dockBottom) and Finite(childBottom) and Finite(dockScale) and dockScale > 0
        and Finite(childScale) and childScale > 0 and Finite(tabScale) and tabScale > 0) then return end
    local offset = (dockBottom * dockScale - childBottom * childScale) / tabScale
    if native or math.abs(y - offset) > .01 then
        M.context:Anchor(tab, "BOTTOMLEFT", child, "BOTTOMLEFT", x, offset)
        M.alignedDockLead = tab
    end
end

function C.DockGeometry()
    if not M.active or M.toolbarLayingOut then return end
    local padded = M.config.tabPadding and M.config.tabPadding > 0
    if C.LayoutLocked() then
        S.Queue("chat")
        return
    end
    -- A width change asks Blizzard to lay out tabs again before we space them.
    C.LayoutToolbarDock()
    if M.config.tabPanel or M.alignedDockLead then AlignDynamicDockLead(GENERAL_CHAT_DOCK) end
    if padded then
        for tab, visual in pairs(M.tabs) do ApplyTabWidth(M, visual, tab) end
    end
    local context, gap = M.context, M.config.tabGap
    if gap <= 0 then
        for tab in pairs(spacedTabs) do
            context:RestorePoints(tab)
            spacedTabs[tab] = nil
        end
        C.PositionTabs(M)
        C.UpdateWhisperArrows(GENERAL_CHAT_DOCK)
        return
    end
    -- GENERAL_CHAT_DOCK exists from the start on both clients (FloatingChatFrame.xml).
    local docked = _G.GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
    for tab in pairs(spacedTabs) do
        local visual = M.tabs[tab]
        if visual and not visual.frame.isDocked then
            context:RestorePoints(tab)
            spacedTabs[tab] = nil
        end
    end
    local lastStatic, lastDynamic
    for i = 1, math.min(#docked, 64) do
        local frame = docked[i]
        if not NS.Safety.IsForbidden(frame) then
            local tab = _G[frame:GetName() .. "Tab"]
            if not NS.Safety.IsForbidden(tab) then
                local last = frame.isStaticDocked and lastStatic or lastDynamic
                if last then
                    context:Anchor(tab, "LEFT", last, "RIGHT", 1 + gap, 0)
                    spacedTabs[tab] = true
                end
                if frame.isStaticDocked then lastStatic = tab else lastDynamic = tab end
            end
        end
    end
    C.PositionTabs(M)
    C.UpdateWhisperArrows(GENERAL_CHAT_DOCK)
end

-- The menu paints owned sample regions with the runtime surface painters.
C.PreviewPanel, C.PreviewEdge = ApplyPanel, ApplyEdge
C.PreviewInput = ApplyInput
