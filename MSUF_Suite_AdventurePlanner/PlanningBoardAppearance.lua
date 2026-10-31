local _, P = ...
local NS, S, B = P.NS, P.Suite, P.PlanningTools.Board
local Bridge = NS.HostBridge
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 } }
local NEUTRAL, TEXT = { .08, .08, .08, .98 }, { 1, 1, 1, 1 }
local labels, fills, panels = {}, {}, {}
local EDGES = { { "TOPLEFT", "TOPRIGHT", "SetHeight" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight" },
    { "TOPLEFT", "BOTTOMLEFT", "SetWidth" }, { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth" } }

function B.Color(token, alternate)
    return Bridge.MenuColor(token, alternate)
        or ((token == "text" or token == "title" or token == "muted") and TEXT or NEUTRAL)
end

-- token false: the host paints this label (Menu2's own controls).
function B.TintLabel(label, token)
    label.plannerFontToken = token
    if token == false then return end
    if label.plannerClassFile then
        local r, g, b = S.ClassRGB(label.plannerClassFile)
        if r then
            label:SetTextColor(r, g, b, 1)
            return
        end
    end
    local c = B.Color(token, "text")
    label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

function B.TrackFont(label, size, token)
    if not label.plannerFontSize then labels[#labels + 1] = label end
    label.plannerFontSize = size
    S.SetFont(label, nil, size, "")
    B.TintLabel(label, token == nil and "text" or token)
    return label
end

-- alternate names the token of older hosts whose theme lacks the first one.
function B.Tint(texture, token, alpha, alternate)
    texture.plannerToken, texture.plannerAlpha = token, alpha
    texture.plannerAlternate = alternate or texture.plannerAlternate
    local c = B.Color(token, texture.plannerAlternate or "panel2")
    texture:SetColorTexture(c[1], c[2], c[3], (c[4] or 1) * (alpha or 1))
end

function B.Texture(parent, layer, token, alpha, alternate)
    local texture = S.CreateTexture(parent, nil, layer or "BACKGROUND")
    fills[#fills + 1] = texture
    B.Tint(texture, token, alpha, alternate)
    return texture
end

function B.Fill(parent, token, alpha, alternate)
    local texture = B.Texture(parent, "BACKGROUND", token, alpha, alternate)
    texture:SetAllPoints()
    return texture
end

-- A one pixel rule, as MSUF separates its window header and sections.
function B.Rule(parent, x, y, width)
    local rule = B.Texture(parent, "ARTWORK", "borderSoft", 1, "border")
    rule:SetPoint("TOPLEFT", x, y)
    rule:SetSize(width, 1)
    return rule
end

-- Four one pixel edges; the focus colour of an input repaints them.
function B.Edges(frame, token)
    frame.plannerEdges = {}
    for i, spec in ipairs(EDGES) do
        local edge = B.Texture(frame, "BORDER", token, 1, "border")
        edge:SetPoint(spec[1])
        edge:SetPoint(spec[2])
        edge[spec[3]](edge, 1)
        frame.plannerEdges[i] = edge
    end
end

function B.TintEdges(frame, token)
    for _, edge in ipairs(frame.plannerEdges) do B.Tint(edge, token, 1) end
end

local function PaintPanel(panel)
    if Bridge.MenuMaterial(panel, panel.plannerMaterial) then return end
    local c, edge = B.Color(panel.plannerToken, "panel2"), B.Color("borderSoft", "border")
    panel:SetBackdrop(BACKDROP)
    panel:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    panel:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
end

function B.Material(panel, material, token)
    if not panel.plannerMaterial then panels[#panels + 1] = panel end
    panel.plannerMaterial, panel.plannerToken = material, token
    PaintPanel(panel)
end

-- Menu2's pills paint their own selected, hover and disabled states.
function B.StyleButton(button, selected)
    if button.plannerNativeButton then return button:SetActive(selected == true) end
    B.Tint(button.fill, selected and "pillActive" or "pillBase")
    B.TintLabel(button.text, button:IsEnabled() and (selected and "title" or "text") or "disabled")
end

function B.ApplyFonts()
    for _, label in ipairs(labels) do
        S.SetFont(label, nil, label.plannerFontSize, "")
        B.TintLabel(label, label.plannerFontToken)
    end
    B.fontPath, B.fontRevision = S.GlobalFontPath(), S.FontRevision
end

function B.EnsureFonts()
    if B.fontPath ~= S.GlobalFontPath() or B.fontRevision ~= S.FontRevision then B.ApplyFonts() end
end

function B.Restyle(owner)
    local window = B.window
    local bar = window and window.restoreBar
    if bar and bar:IsShown() and bar.owner == owner then
        if bar.profile ~= NS.DB or not P.PlanningTools.CanEdit() then B.ClearRestore(window)
        else B.ApplyFonts() B.StyleButton(bar, false) end
    end
    if not window or window.owner ~= owner or not window:IsShown() or not B.Valid(window) then return end
    for _, panel in ipairs(panels) do PaintPanel(panel) end
    for _, fill in ipairs(fills) do B.Tint(fill, fill.plannerToken, fill.plannerAlpha) end
    B.ApplyFonts()
end

local function AppearanceChanged()
    if B.window then B.Restyle(B.window.owner or B.window.restoreBar.owner) end
end

function B.WatchAppearance()
    Bridge.WatchMenuAppearance(B, AppearanceChanged)
end
