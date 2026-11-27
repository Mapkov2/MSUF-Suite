local _, P = ...
local S = P.Suite
local Appearance = { buttons = setmetatable({}, { __mode = "k" }) }
P.BagAppearance = Appearance
-- The optional global button skin can reuse its material on these Suite-created
-- actions. The Bags owner already keeps their exact identities for font refresh.
S.BagActionButtons = Appearance.buttons

local FOREVER_LOOK = 3
local GLASS_SOFT_ALPHA, GLASS_DARK_ALPHA = .88, .94
local DEFAULT_BORDER = { .063, .063, .063, 1 }

function Appearance.DefaultBorder(c)
    if c.backpackBorderStyle == P.NS.BagsBorderStyle.CUSTOM then return nil end
    local skin = P.NS.Skin
    local border = skin and skin.GetTooltipBorder and skin.GetTooltipBorder()
    return border and border[4] > 0 and border or DEFAULT_BORDER
end

local function SizeBorder(t, width)
    if t.borderWidth == width then return end
    t.borderWidth = width
    t[6]:SetHeight(width)
    t[7]:SetHeight(width)
    t[8]:SetWidth(width)
    t[9]:SetWidth(width)
    for i = 8, 9 do
        local top, bottom = i == 8 and "TOPLEFT" or "TOPRIGHT", i == 8 and "BOTTOMLEFT" or "BOTTOMRIGHT"
        t[i]:ClearAllPoints()
        t[i]:SetPoint(top, t.shell, top, 0, -width)
        t[i]:SetPoint(bottom, t.shell, bottom, 0, width)
    end
end

function Appearance.WindowShape()
    local skin = P.NS.Skin
    return skin and skin.GetRoundedWindowGeometry and skin.GetRoundedWindowGeometry()
end

local function PaintShadow(t, geometry, opacity)
    local shadow = t[1]
    if geometry then
        P.NS.Skin.PaintRoundedWindowShadow(shadow, geometry, opacity, not t.rounded)
    else
        if t.rounded then
            shadow:ClearTextureSlice()
            shadow:SetVertexColor(1, 1, 1, 1)
        end
        shadow:SetColorTexture(0, 0, 0, opacity)
    end
end

local function RoundChrome(t, shadowOpacity)
    local geometry = Appearance.WindowShape()
    if geometry or t.roundedMask then
        t.roundedMask = P.NS.Skin.MaskOwnedWindow(t.shell, t.roundedMask, geometry,
            t[2], t[3], t[4], t[5], t.feather, t.closeFill, not t.combined and t[6] or nil)
    end
    local rounded = t.roundedMask and t.roundedMask.active == true or nil
    PaintShadow(t, rounded and geometry, shadowOpacity)
    if t.rounded ~= rounded then
        t.rounded = rounded
        for i = 6, 9 do t[i]:SetShown(not rounded or i == 6 and not t.combined) end
        if not rounded and t.roundedBorder then t.roundedBorder:Hide() end
    end
    return geometry and not rounded and P.NS.InCombat()
end

local function PaintRoundBorder(t, width, r, g, b, a)
    local art = P.NS.Skin.PaintRoundedWindowOutline
    t.roundedBorder = art(t.shell, t.roundedBorder, width, r, g, b, a, nil, nil, true, true)
end

local function PaintBorder(t, c, ar, ag, ab)
    if not t.combined then
        t[6]:SetColorTexture(ar, ag, ab, .45)
        if t.rounded then
            PaintRoundBorder(t, 1, .28, .31, .36, .55)
        else
            if t.borderWidth then SizeBorder(t, 1) end
            for i = 7, 9 do t[i]:SetColorTexture(.28, .31, .36, .55) end
        end
        return
    end
    local default = Appearance.DefaultBorder(c)
    local width = default and 1 or c.backpackBorderWidth
    local r, g, b, a
    if default then
        r, g, b, a = unpack(default)
    else
        r, g, b = S.RGB(c.backpackBorderColor)
        a = width > 0 and c.backpackBorderOpacity / 100 or 0
    end
    if t.rounded then
        PaintRoundBorder(t, width, r, g, b, a)
    else
        SizeBorder(t, width)
        for i = 6, 9 do t[i]:SetColorTexture(r, g, b, a) end
    end
end

local function PaintBody(t, glass, panel, r, g, b, opacity)
    local body = t[2]
    if glass then
        t.bodyGradient = true
        body:SetColorTexture(1, 1, 1, 1)
        local soft = CreateColor(r, g, b, opacity * GLASS_SOFT_ALPHA)
        local dark = CreateColor(r * .85, g * .85, b * .85, opacity * GLASS_DARK_ALPHA)
        body:SetGradient(panel and "HORIZONTAL" or "VERTICAL", soft, dark)
    elseif t.bodyGradient then
        body:SetColorTexture(1, 1, 1, 1)
        local flat = CreateColor(r, g, b, opacity)
        body:SetGradient("HORIZONTAL", flat, flat)
    else
        body:SetColorTexture(r, g, b, opacity)
    end
end

-- Shared painters for the live bags, bank and menu sample. All regions passed
-- here belong to the Suite; Blizzard retains the item buttons and their actions.
function Appearance.Window(t, c)
    local panel = t.combined and P.BagPresentation.IsPanel(c) and not t.combat or false
    P.BagPanelAppearance.Geometry(t, panel, t.goldBoth, panel and P.BagPresentation.Rail(c) or 0)
    local r, g, b = S.RGB(c.backgroundColor)
    local ar, ag, ab = S.RGB(c.accentColor)
    local opacity = c.backgroundOpacity / 100
    local glass = t.combined and c.look == FOREVER_LOOK
    local shadowOpacity = (glass and .10 or .5) * opacity
    PaintBody(t, glass, panel, r, g, b, opacity)
    t[3]:SetColorTexture(r + .025, g + .025, b + .025, (glass or panel) and .28 * opacity or opacity)
    t[4]:SetColorTexture(ar, ag, ab, panel and .12 or .24)
    if t[5] then t[5]:SetColorTexture(r * .7, g * .7, b * .7, (glass or panel) and .46 * opacity or opacity) end
    local deferred = RoundChrome(t, shadowOpacity)
    PaintBorder(t, c, ar, ag, ab)
    if t.goldLabel then
        local font = S.ResolveFont(c.font)
        S.SetFont(t.goldLabel, font, 11, "OUTLINE")
        if t.dailyGoldLabel then S.SetFont(t.dailyGoldLabel, font, 11, "OUTLINE") end
    end
    if panel then P.BagPanelAppearance.Paint(t, c, opacity) end
    return deferred
end

function Appearance.Button(button, selected)
    local c = P.BagsModule.active and P.BagsModule.config or S.Config("bags")
    local rail = button.bagRail == true
    if button.bagAccent == c.accentColor and button.bagSelected == selected and button.paintedRail == rail then return end
    if button.paintedRail ~= rail then
        button.rule:ClearAllPoints()
        button.rule:SetPoint(rail and "TOPLEFT" or "BOTTOMLEFT")
        button.rule:SetPoint(rail and "BOTTOMLEFT" or "BOTTOMRIGHT")
        button.rule:SetWidth(rail and 2 or 1)
        button.rule:SetHeight(1)
        button.paintedRail = rail
    end
    button.bagAccent, button.bagSelected = c.accentColor, selected
    local ar, ag, ab = S.RGB(c.accentColor)
    -- The three view tabs share one moving selection surface.
    local filled = selected and not button.bagNavigation
    button.surface:SetColorTexture(ar, ag, ab, filled and .22 or .065)
    button.rule:SetColorTexture(ar, ag, ab, filled and .9 or .13)
end

function Appearance.Tool(button, label, texture, atlas, panel)
    if panel and not button.bagIcon then
        button.bagIcon = S.CreateTexture(button, nil, "ARTWORK")
        button.bagIcon:SetPoint("TOPLEFT", 3, -3)
        button.bagIcon:SetPoint("BOTTOMRIGHT", -3, 3)
        if atlas then button.bagIcon:SetAtlas(atlas) else button.bagIcon:SetTexture(texture) end
    end
    if button.bagIcon then button.bagIcon:SetShown(panel) end
    button.bagTool = panel and label or nil
    button:SetText(panel and "" or S.Text(label))
end

local function Enter(button)
    if button:IsEnabled() then
        if button.bagNavigation then P.BagMotion.Hover(button.surface, P.BagsModule.active and P.BagsModule.config or S.Config("bags"), true)
        else
            button.surface:SetAlpha(1)
        end
    end
    if button.bagTool then
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        GameTooltip:SetText(S.Text(button.bagTool))
        GameTooltip:Show()
    end
end

local function Leave(button)
    if button.bagNavigation then P.BagMotion.Hover(button.surface, P.BagsModule.active and P.BagsModule.config or S.Config("bags"), false)
    else
        button.surface:SetAlpha(.7)
    end
    if button.bagTool then GameTooltip:Hide() end
end

local function MuteTexture(texture)
    if texture then texture:SetAlpha(0) end
end

function Appearance.MakeButton(button)
    button.Left:SetAlpha(0)
    button.Middle:SetAlpha(0)
    button.Right:SetAlpha(0)
    button:SetNormalFontObject("GameFontHighlightSmall")
    button:SetHighlightFontObject("GameFontHighlightSmall")
    button:SetDisabledFontObject("GameFontDisableSmall")
    MuteTexture(button:GetNormalTexture())
    MuteTexture(button:GetPushedTexture())
    MuteTexture(button:GetDisabledTexture())
    MuteTexture(button:GetHighlightTexture())
    local surface = S.CreateTexture(button, nil, "BACKGROUND")
    surface:SetAllPoints(button)
    surface:SetAlpha(.7)
    local rule = S.CreateTexture(button, nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    button.surface, button.rule = surface, rule
    button:HookScript("OnEnter", Enter)
    button:HookScript("OnLeave", Leave)
    Appearance.Button(button, false)
    Appearance.buttons[button] = true
end

function Appearance.Refresh()
    for button in pairs(Appearance.buttons) do Appearance.Button(button, button.bagSelected) end
end

function Appearance.Section(label, parent)
    local plate = label.plate
    if plate then return plate end
    plate = P.ChildFrame("Frame", parent)
    plate:EnableMouse(false)
    plate:SetFrameLevel(parent:GetFrameLevel())
    local fill = S.CreateTexture(plate, nil, "BACKGROUND")
    fill:SetAllPoints(plate)
    local edge = S.CreateTexture(plate, nil, "BORDER")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("TOPRIGHT")
    edge:SetHeight(1)
    plate.fill, plate.edge = fill, edge
    label.plate = plate
    return plate
end

function Appearance.PaintSection(plate, anchor, x, y, width, height, config, label)
    if plate.x ~= x or plate.y ~= y or plate.width ~= width or plate.height ~= height then
        plate:ClearAllPoints()
        plate:SetPoint("TOPLEFT", anchor, "TOPLEFT", x - 3, y + 4)
        plate:SetSize(width + 1, height)
        plate.x, plate.y, plate.width, plate.height = x, y, width, height
    end
    local c = config or P.BagsModule.config
    local panel = P.BagPresentation.IsPanel(c)
    if plate.panel ~= panel then
        plate.panel, plate.color = panel, nil
        plate.fill:SetShown(not panel)
        plate.edge:ClearAllPoints()
        plate.edge:SetPoint(panel and "BOTTOMLEFT" or "TOPLEFT")
        plate.edge:SetPoint(panel and "BOTTOMRIGHT" or "TOPRIGHT")
        if panel then
            plate.edge:ClearAllPoints()
            plate.edge:SetPoint("TOPLEFT", 0, -30)
            plate.edge:SetPoint("TOPRIGHT", 0, -30)
        end
    end
    local color = c.accentColor
    if plate.color ~= color then
        local r, g, b = S.RGB(color)
        plate.fill:SetColorTexture(r, g, b, .045)
        plate.edge:SetColorTexture(r, g, b, panel and .2 or .18)
        plate.color = color
    end
    if panel and label then
        local text, path = label:GetText(), label:GetFont()
        if plate.heading ~= text or plate.font ~= path or plate.ruleWidth ~= width then
            plate.edge:ClearAllPoints()
            plate.edge:SetPoint("TOPLEFT", math.min(width - 12, label:GetStringWidth() + 12), -20)
            plate.edge:SetPoint("TOPRIGHT", 0, -20)
            plate.heading, plate.font, plate.ruleWidth = text, path, width
        end
    end
    plate:Show()
end

S.BagsPaintPreviewTool = Appearance.Tool
S.BagsPaintPreviewWindow = Appearance.Window
S.BagsDefaultBorder = Appearance.DefaultBorder
S.BagsPaintPreviewSection = Appearance.PaintSection
