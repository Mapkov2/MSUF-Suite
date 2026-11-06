local _, P = ...
local S, Presentation = P.Suite, P.BagPresentation
local Panel = {}
P.BagPanelAppearance = Panel

local function Texture(parent, layer)
    return S.CreateTexture(parent, nil, layer or "BACKGROUND")
end

local function Extras(t)
    if t.feather then return end
    local shell = t.shell
    t.feather = Texture(shell)
    t.feather:SetPoint("TOPLEFT")
    t.feather:SetPoint("BOTTOMLEFT")
    t.feather:SetWidth(Presentation.RAIL)
    t.ribbon = Texture(shell, "ARTWORK")
    t.ribbon:SetPoint("TOPLEFT", 20, -47)
    t.ribbon:SetSize(Presentation.RAIL + 148, 1)
    t.glow = Texture(shell, "BORDER")
    t.glow:SetPoint("TOPLEFT", 20, -45)
    t.glow:SetSize(Presentation.RAIL + 148, 5)
    t.heading = S.CreateFontString(shell, nil, "OVERLAY")
    t.heading:SetPoint("TOPLEFT", Presentation.RAIL + 16, -16)
    t.heading:SetPoint("TOPRIGHT", -176, -16)
    t.heading:SetJustifyH("LEFT")
    t.heading:SetWordWrap(false)
end

local function Inset(texture, left, right, height)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", left, 0)
    texture:SetPoint("TOPRIGHT", right, 0)
    if height then texture:SetHeight(height) else texture:SetPoint("BOTTOMRIGHT", right, 0) end
end

function Panel.Geometry(t, panel)
    if t.panel == panel then return end
    t.panel = panel
    if panel then Extras(t) end
    local rail = panel and Presentation.RAIL or 0
    Inset(t[2], rail, 0)
    Inset(t[3], rail, 0, panel and 50 or (t.combined and 62 or 40))
    t[1]:SetShown(not panel)
    for i = 6, 8 do t[i]:SetShown(not panel) end
    if t[5] then
        t[5]:ClearAllPoints()
        t[5]:SetPoint("BOTTOMLEFT", rail, 0)
        t[5]:SetPoint("BOTTOMRIGHT")
    end
    if t.feather then
        t.feather:SetShown(panel)
        t.ribbon:SetShown(panel)
        t.glow:SetShown(panel)
        t.heading:SetShown(panel)
    end
    if t.goldLabel and t.moneyAnchor then
        t.goldLabel:ClearAllPoints()
        if panel then
            t.goldLabel:SetPoint("BOTTOMLEFT", t.shell, "BOTTOMLEFT", 8, 50)
        else
            t.goldLabel:SetPoint("LEFT", t.moneyAnchor, "LEFT", 4, 0)
        end
        t.goldLabel:SetSize(panel and 96 or 210, panel and 32 or 0)
        t.goldLabel:SetWordWrap(panel)
    end
end

-- Static gradients; opening motion animates the Suite shell only. There is
-- no particle driver, native item animation or per-frame decoration work.
function Panel.Paint(t, c)
    local r, g, b = S.RGB(c.backgroundColor)
    local ar, ag, ab = S.RGB(c.accentColor)
    local opacity = c.backgroundOpacity / 100
    t.feather:SetColorTexture(1, 1, 1)
    t.feather:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, opacity))
    t.ribbon:SetColorTexture(1, 1, 1)
    t.ribbon:SetGradient("HORIZONTAL", CreateColor(ar, ag, ab, 0), CreateColor(ar, ag, ab, .8))
    t.glow:SetColorTexture(1, 1, 1)
    t.glow:SetGradient("HORIZONTAL", CreateColor(ar, ag, ab, 0), CreateColor(ar, ag, ab, .08))
    t[3]:SetColorTexture(r, g, b, 0)
    t[4]:SetColorTexture(ar, ag, ab, .12)
    t[5]:SetColorTexture(r, g, b, 0)
    t[9]:SetColorTexture(ar, ag, ab, .16)
    t.heading:SetTextColor(.94, .95, .98)
    S.SetFont(t.heading, S.ResolveFont(c.font) or S.GlobalFontPath(), 22, "")
    t.heading:SetText(S.Text("Backpack"))
end
