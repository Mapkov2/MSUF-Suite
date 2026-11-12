local _, P = ...
local NS, S = P.NS, P.Suite
local ID = "bnetToast"
local POINTS = NS.AnchorPoints
local Finite = S.Finite
local M = {}

-- Blizzard's Battle.net toast: BNToastFrame (Blizzard_BNet/BNet.xml), a
-- SocialToastTemplate (Blizzard_SocialToast/SocialToast.xml: 250 x 50,
-- BackdropTemplate with BACKDROP_TOAST_12_12, strata LOW). BNToastMixin:
-- ShowToast sets 63 for a toast with a character line and 50 otherwise.
-- Verified on Gethe wow-ui-source live 297d7aaa and forever 4cd0ab75:
-- Blizzard_BNet/Mainline/BNet.lua and .xml, Blizzard_SharedXML/
-- AlertFrameIntrinsic.lua/.xml and Blizzard_ChatFrameBase/Shared/
-- ChatAlertFrameMixin.lua are identical there. Blizzard_FrameXML/Mainline/
-- AlertFrames.lua differs only in queued alert systems (Forever's
-- shouldIgnoreAlertsFunc); AlertFrameAutoAnchoredMixin and
-- AlertContainerMixin are the same. Blizzard_QuickJoin/QuickJoinToast.lua
-- on Forever also shows or hides the Friends button with the gamepad mode,
-- which NativeAnchor reads on each refresh.
--
-- Placement. The toast is an auto-anchored member of ChatAlertFrame. Each
-- layout pass of that container while the toast shows (run by the postcall
-- OnShow and OnHide of every chat alert: the toast itself, the Friends
-- button, voice and other alerts) calls AdjustAnchors: ClearAllPoints, then
-- SetPoint to the chat alert below the toast. The same chain places the
-- Friends button (QuickJoinToastButton), so moving ChatAlertFrame would move
-- that button too. A post-hook on the toast's SetPoint puts the toast back
-- on the Suite's anchor right after Blizzard placed it. hooksecurefunc
-- keeps Blizzard's caller secure; it is installed the first time the toast
-- is moved and does nothing while the toast keeps Blizzard's spot.
-- Accepted: the chat alerts after the toast in anchor priority (the Korean
-- time alert at 2, voice chat prompts and speaker notifications at 10 and
-- up) are anchored on top of the toast by AlertContainerMixin:UpdateAnchors,
-- so while a moved toast shows they stack on it there. Keeping them at the
-- chat would need a hook on every chat alert layout pass, voice chat in
-- combat included.
--
-- Cost. No event, ticker or OnUpdate. In combat nothing here runs unless
-- Blizzard shows or lays out the toast: then one hook call moves it, and the
-- hook call that move causes returns at its first test. Look, font, scale
-- and layer are set outside combat on the toast and its own regions, and
-- Blizzard never sets them again.
--
-- Taint. No field is written onto a Blizzard frame or table and Blizzard's
-- anchoring code is never called. Only widget methods of the toast and its
-- regions run (none is protected), on textures this file creates there.
local TOAST_WIDTH, TOAST_HEIGHT = 250, 63
local PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }
local LINES = { "TopLine", "MiddleLine", "BottomLine", "DoubleLine" }
local OUTLINES = { "", "OUTLINE", "THICKOUTLINE" }
-- AlertContainerMixin:GetPointsForJustification: the first alert sits on
-- the container's own bottom edge, the next ones on top of the one below.
local SIDES = { LEFT = "BOTTOMLEFT", CENTER = "BOTTOM", RIGHT = "BOTTOMRIGHT" }
local ABOVE = { BOTTOMLEFT = "TOPLEFT", BOTTOM = "TOP", BOTTOMRIGHT = "TOPRIGHT" }
-- BNet.xml anchors the toast here before Blizzard first places it.
local XML_POINT, XML_Y = "CENTER", 50

local function Toast()
    local toast = _G.BNToastFrame
    if toast and not NS.Safety.IsForbidden(toast) then return toast end
end

------------------------------------------------------------------ placement
-- The anchor the toast follows while it is moved (nil: Blizzard's spot) and
-- the point of both. busy covers the SetPoint the hook itself makes.
local placeHost, placePoint, busy = nil, "BOTTOMLEFT", false

local function Pin(toast)
    busy = true
    toast:ClearAllPoints()
    toast:SetPoint(placePoint, placeHost, placePoint, 0, 0)
    busy = false
end

local function Anchored(toast, _, relative)
    if busy or not placeHost or relative == placeHost then return end
    Pin(toast)
end

-- Blizzard's spot: on top of the Friends button while it shows, else on
-- ChatAlertFrame itself, on the side of its justification. The delves and
-- text-to-speech alerts (anchor priority 0, like the Friends button) that
-- can sit below the toast are rare and not followed. Returns point, relative
-- frame, relative point and y offset.
local function NativeAnchor()
    local container = _G.ChatAlertFrame
    if not container then return XML_POINT, UIParent, XML_POINT, XML_Y end
    local point = SIDES[container.justification] or SIDES.CENTER
    local below = _G.QuickJoinToastButton
    if below and below:IsShown() then return point, below, ABOVE[point], 0 end
    return point, container, point, 0
end

-- Hands a toast this module placed back to Blizzard's spot; Blizzard's next
-- layout pass places it there anyway.
local function HandBack(toast, host)
    if select(2, toast:GetPoint(1)) ~= host then return end
    local point, relative, relativePoint, y = NativeAnchor()
    busy = true
    toast:ClearAllPoints()
    toast:SetPoint(point, relative, relativePoint, 0, y)
    busy = false
end

local function Follow(self, toast)
    if self.active and self.config.moved then
        if not self.hooked then
            hooksecurefunc(toast, "SetPoint", Anchored)
            self.hooked = true
        end
        placeHost, placePoint = self.host, self.point
        Pin(toast)
        return
    end
    local host = placeHost
    placeHost = nil
    if host then HandBack(toast, host) end
end

-- The host stands where the toast goes: the saved point, or Blizzard's spot
-- while the toast was never moved, at the toast's scale.
local function PlaceHost(self)
    local c, host = self.config, self.host
    if c.moved then
        self.point = S.PlaceHost(host, c, "BOTTOMLEFT")
        return
    end
    local point, relative, relativePoint, y = NativeAnchor()
    host:ClearAllPoints()
    host:SetPoint(point, relative, relativePoint, 0, y)
    host:SetScale(c.scale / 100)
    self.point = point
end

-- The offsets of the host's own point from the same point of UIParent, in
-- the host's scale: where an MSUF Edit Mode drag starts while the toast
-- still keeps Blizzard's spot.
local function HostOffset(host, point)
    local left, bottom, width, height = host:GetRect()
    local factor = UIParent:GetEffectiveScale() / host:GetEffectiveScale()
    if not (Finite(left) and Finite(bottom) and Finite(width) and Finite(height) and Finite(factor)) then return end
    local parentWidth, parentHeight = UIParent:GetWidth() * factor, UIParent:GetHeight() * factor
    local x, y = left + (width - parentWidth) / 2, bottom + (height - parentHeight) / 2
    if point:find("LEFT", 1, true) then x = left elseif point:find("RIGHT", 1, true) then x = left + width - parentWidth end
    if point:find("BOTTOM", 1, true) then y = bottom elseif point:find("TOP", 1, true) then y = bottom + height - parentHeight end
    return math.floor(x * 10 + .5) / 10, math.floor(y * 10 + .5) / 10
end

------------------------------------------------------------------ look
-- The Suite panel: a fill, a one pixel frame and an accent stripe, below the
-- text (BNet.xml draws the toast's lines and icon in BORDER 0).
local function Panel(host)
    local panel = { fill = S.CreateTexture(host, nil, "BACKGROUND", nil, -8), edges = {},
        stripe = S.CreateTexture(host, nil, "BORDER", nil, -7) }
    panel.fill:SetAllPoints(host)
    for i = 1, 4 do panel.edges[i] = S.CreateTexture(host, nil, "BORDER", nil, -8) end
    panel.stripe:SetPoint("TOPLEFT", host, "TOPLEFT", 1, -1)
    panel.stripe:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 1, 1)
    panel.stripe:SetWidth(2)
    return panel
end

local function ShowPanel(panel, shown)
    panel.fill:SetShown(shown)
    for i = 1, 4 do panel.edges[i]:SetShown(shown) end
    panel.stripe:SetShown(shown)
end

local function FadeBackdrop(self, toast, faded)
    local alphas = self.pieceAlpha
    for _, key in ipairs(PIECES) do
        local piece = toast[key]
        if piece then
            if faded then
                if alphas[piece] == nil then alphas[piece] = piece:GetAlpha() end
                piece:SetAlpha(0)
            elseif alphas[piece] ~= nil then
                piece:SetAlpha(alphas[piece])
                alphas[piece] = nil
            end
        end
    end
end

-- Palette i + 1 of the shared QoL looks for toast style i; nil for Blizzard.
local function Palette(config)
    if config.look > 1 then return S.QoLPalette(config.look - 1) end
end

local function PaintPanel(panel, palette, config, owner)
    S.QoLColor(panel.fill, palette.background, config.opacity / 100)
    local r, g, b = S.RGB(palette.border)
    S.PlaceEdges(panel.edges, owner, 1, r, g, b, .95)
    S.QoLColor(panel.stripe, palette.accent, 1)
    panel.stripe:SetShown(config.accent == true)
end

local function ApplyLook(self, toast)
    local palette = self.active and Palette(self.config)
    if not palette then
        if self.panel then ShowPanel(self.panel, false) end
        FadeBackdrop(self, toast, false)
        return
    end
    local panel = self.panel or Panel(toast)
    self.panel = panel
    ShowPanel(panel, true)
    PaintPanel(panel, palette, self.config, toast)
    FadeBackdrop(self, toast, true)
end

------------------------------------------------------------------ text
-- The Suite font on Blizzard's four lines (S.SetFont only: the host's text
-- helpers would mark the font strings). Each line gets back the font and
-- shadow it had before.
local function StyleLine(line, config)
    local font = S.ResolveFont(config.font) or S.GlobalFontPath()
    S.SetFont(line, font, config.fontSize, S.FontFlags(OUTLINES[config.fontOutline] or "OUTLINE", config.fontRendering))
    local shadow = config.fontShadow == true and config.fontRendering ~= NS.FontRendering.SLUG
    line:SetShadowColor(0, 0, 0, shadow and config.fontShadowOpacity / 100 or 0)
    local distance = shadow and config.fontShadowDistance or 0
    line:SetShadowOffset(distance, -distance)
end

local function ApplyText(self, toast)
    local styled, saved = self.active and self.config.suiteFont == true, self.lineState
    for _, key in ipairs(LINES) do
        local line = toast[key]
        local state = line and saved[line]
        if line and styled then
            if not state then
                saved[line] = { font = { line:GetFont() }, offset = { line:GetShadowOffset() },
                    shadow = { line:GetShadowColor() } }
            end
            StyleLine(line, self.config)
        elseif state then
            line:SetFont(unpack(state.font))
            line:SetShadowOffset(unpack(state.offset))
            line:SetShadowColor(unpack(state.shadow))
            saved[line] = nil
        end
    end
end

-- Scale and layer: the toast's own, captured before the first change. A
-- strata change reaches the toast's children; its broadcast tooltip
-- (BNet.xml TooltipFrame, TOOLTIP without a fixed strata) gets its own back.
local function ApplyFrame(self, toast)
    local native, tooltip = self.native, toast.TooltipFrame
    if not native then
        native = { scale = toast:GetScale(), strata = toast:GetFrameStrata(),
            tooltip = tooltip and tooltip:GetFrameStrata() }
        self.native = native
    end
    local c = self.config
    toast:SetScale(self.active and c.scale / 100 or native.scale)
    local strata = self.active and c.raise and "HIGH" or native.strata
    if toast:GetFrameStrata() == strata then return end
    toast:SetFrameStrata(strata)
    if tooltip and native.tooltip then tooltip:SetFrameStrata(native.tooltip) end
end

------------------------------------------------------------------ edit mode
-- The sample's lines as BNet.xml places an online toast's (top, character
-- and status line, each 10 high with 4 between) in its colors.
local PREVIEW_LINES = {
    { y = -10, r = .510, g = .773, b = 1 },
    { y = -24, r = .510, g = .773, b = 1 },
    { y = -38, r = .486, g = .518, b = .541 },
}

local function NativeFont(line)
    line:SetFontObject(_G.FriendsFont_Normal or _G.GameFontHighlightSmall)
    line:SetShadowColor(0, 0, 0, 1)
    line:SetShadowOffset(1, -1)
end

-- A sample of an online toast with the toast's look and font, at the spot
-- the toast takes. Blizzard's backdrop stands in for the Blizzard look.
local function CreatePreview(self)
    local host = self.host
    local icon = S.CreateTexture(host, nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("LEFT", host, "LEFT", 4, 0)
    icon:SetTexture("Interface\\FriendsFrame\\UI-Toast-ToastIcons")
    icon:SetTexCoord(0, .25, .5, 1)
    local preview = { icon = icon, panel = Panel(host), lines = {} }
    local texts = { S.Text("Battle.net friend"), UnitName("player") or "", _G.BN_TOAST_ONLINE or "" }
    for index, spec in ipairs(PREVIEW_LINES) do
        local line = S.CreateFontString(host, nil, "OVERLAY")
        line:SetPoint("TOPLEFT", host, "TOPLEFT", 44, spec.y)
        line:SetPoint("RIGHT", host, "RIGHT", -20, 0)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        -- A font string needs its font before its text.
        NativeFont(line)
        line:SetText(texts[index])
        preview.lines[index] = line
    end
    self.preview = preview
    return preview
end

local function PaintPreview(self)
    local preview = self.preview or CreatePreview(self)
    local host, c = self.host, self.config
    local palette = Palette(c)
    ShowPanel(preview.panel, palette ~= nil)
    if palette then
        PaintPanel(preview.panel, palette, c, host)
        host:SetBackdrop(nil)
    elseif _G.BACKDROP_TOAST_12_12 then
        host:SetBackdrop(_G.BACKDROP_TOAST_12_12)
    end
    for index, line in ipairs(preview.lines) do
        if c.suiteFont then StyleLine(line, c) else NativeFont(line) end
        local spec = PREVIEW_LINES[index]
        line:SetTextColor(spec.r, spec.g, spec.b)
    end
end

local function Preview(self)
    if not (self.active and S.editMode) then
        self.host:Hide()
        return
    end
    PaintPreview(self)
    self.host:SetFrameStrata(self.config.raise and "HIGH" or "LOW")
    self.host:Show()
end

function M:HideEditPreview()
    if self.host then self.host:Hide() end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "toast", {
        label = "Battle.net toast", order = 658,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return POINTS[self.config.point] or "BOTTOMLEFT" end,
        capture = function(origin)
            if self.config.moved or not self.host then return end
            local x, y = HostOffset(self.host, POINTS[self.config.point] or "BOTTOMLEFT")
            if x then origin.x, origin.y = x, y end
        end,
        moveValues = { moved = true }, resetKeys = { "moved" },
        historyKeys = { "moved", "scale" }, sizeKeys = { "scale" },
    })
end

------------------------------------------------------------------ lifecycle
local function Apply(self)
    local toast = Toast()
    if not toast then return end
    ApplyFrame(self, toast)
    ApplyLook(self, toast)
    ApplyText(self, toast)
    Follow(self, toast)
end

-- Blizzard_BNet normally loads before the Suite; a later load is waited for.
local function AddonLoaded(self, _, name)
    if name ~= "Blizzard_BNet" then return end
    self.context:RemoveEvent("ADDON_LOADED")
    Apply(self)
end

local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    host:SetSize(TOAST_WIDTH, TOAST_HEIGHT)
    host:SetFrameStrata("LOW")
    host:EnableMouse(false)
    host:Hide()
    self.host = host
end

function M:Enable()
    self.pieceAlpha, self.lineState = self.pieceAlpha or {}, self.lineState or {}
    Create(self)
    PlaceHost(self)
    if not Toast() then self.context:Event("ADDON_LOADED", AddonLoaded) end
    Apply(self)
    Preview(self)
end

function M:Refresh()
    PlaceHost(self)
    Apply(self)
    Preview(self)
end

-- Off: Blizzard's spot, look, font, scale and layer come back. The hook
-- stays installed and does nothing.
function M:Disable()
    if self.host then self.host:Hide() end
    Apply(self)
end

S.Install(ID, M)
