local _, NS = ...

-- The map grip is our own button. Use the same material and hover/pressed
-- states as Suite controls instead of the old unframed chat grabber artwork.
local Chrome = {}
NS.WindowControlChrome = Chrome
local grips = setmetatable({}, { __mode = "k" })
local GRIP_SPEC = { role = "button", radius = 4, inset = 1, forceEdge = true }

function Chrome.RecolorGrip(grip)
    local lines = grips[grip]
    if not lines then return end
    local r, g, b, a = NS.Theme.GetColor("text")
    for index = 1, #lines do lines[index]:SetColorTexture(r, g, b, a * 0.8) end
end

-- The minimize button and the restore tab are our own frames too: painted
-- from the theme, and painted again after a look, colour or profile change.
local fills = setmetatable({}, { __mode = "k" })

function Chrome.RecolorControl(control)
    local fill = fills[control]
    if not fill then return end
    fill.background:SetColorTexture(NS.Theme.GetColor(fill.role))
    if fill.label then fill.label:SetTextColor(NS.Theme.GetColor("text")) end
end

function Chrome.PaintControl(control, role, label)
    local background = control:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    fills[control] = { background = background, role = role, label = label }
    Chrome.RecolorControl(control)
end

function Chrome.StyleGrip(grip)
    NS.Surface.SkinOwnedButton(grip, GRIP_SPEC)
    local lines = grips[grip]
    if not lines then
        lines = {}
        grips[grip] = lines
        for index = 1, 2 do
            local line = grip:CreateLine(nil, "OVERLAY", nil, 1)
            line:SetThickness(1)
            local span = index * 4
            line:SetStartPoint("BOTTOMRIGHT", grip, -5 - span, 5)
            line:SetEndPoint("BOTTOMRIGHT", grip, -5, 5 + span)
            lines[index] = line
        end
    end
    Chrome.RecolorGrip(grip)
end

-- The window's own (localized) title, else a name derived from its frame.
function Chrome.Title(state)
    local frame = state.frame
    local title = NS.Safety.Call(frame, "GetTitleText")
        or NS.Safety.Field(NS.Safety.Field(frame, "TitleContainer"), "TitleText")
    local text = NS.Safety.Read(title, "GetText")
    -- Forever's outer container has no title region; all three child panes
    -- use this same localized native caption.
    if state.name == "LFGParentFrame" then text = NS.Safety.Field(_G, "LFG_TITLE") end
    if type(text) == "string" and text ~= "" then return text end
    return (state.name:gsub("Frame$", ""):gsub("(%l)(%u)", "%1 %2"))
end

function Chrome.Control(button, glyph, offset)
    button:SetSize(22, 22)
    button:SetFrameLevel(button:GetParent():GetFrameLevel() + offset)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(glyph)
    NS.WindowControlChrome.PaintControl(button, "buttonFill", label)
end
