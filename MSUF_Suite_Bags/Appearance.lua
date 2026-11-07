local _, P = ...
local S = P.Suite
local Appearance = { buttons = setmetatable({}, { __mode = "k" }) }
P.BagAppearance = Appearance

-- Shared painters for the live bags, bank and menu sample. All regions passed
-- here belong to the Suite; Blizzard retains the item buttons and their actions.
function Appearance.Window(t, c)
    local panel = t.combined and P.BagPresentation.IsPanel(c) and not t.combat or false
    P.BagPanelAppearance.Geometry(t, panel, t.goldBoth)
    local r, g, b = S.RGB(c.backgroundColor)
    local ar, ag, ab = S.RGB(c.accentColor)
    local opacity = c.backgroundOpacity / 100
    t[1]:SetColorTexture(0, 0, 0, .5 * opacity)
    t[2]:SetColorTexture(r, g, b, opacity)
    t[3]:SetColorTexture(r + .025, g + .025, b + .025, opacity)
    t[4]:SetColorTexture(ar, ag, ab, .24)
    if t[5] then t[5]:SetColorTexture(r * .7, g * .7, b * .7, opacity) end
    t[6]:SetColorTexture(ar, ag, ab, .45)
    for i = 7, 9 do t[i]:SetColorTexture(.28, .31, .36, .55) end
    if t.goldLabel then
        local font = S.ResolveFont(c.font)
        S.SetFont(t.goldLabel, font, 11, "OUTLINE")
        if t.dailyGoldLabel then S.SetFont(t.dailyGoldLabel, font, 11, "OUTLINE") end
    end
    if panel then P.BagPanelAppearance.Paint(t, c) end
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
S.BagsPaintPreviewSection = Appearance.PaintSection
