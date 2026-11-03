local _, NS = ...

-- The map grip is our own button. Use the same material and hover/pressed
-- states as Suite controls instead of the old unframed chat grabber artwork.
local Chrome = {}
NS.WindowControlChrome = Chrome
local Safety = NS.Safety
local fills = setmetatable({}, { __mode = "k" })

function Chrome.Parent(state)
    -- WorldMap's root can be LOW while its border and quest log are HIGH.
    -- Inherit the visible border's strata without changing native frames.
    if state.name == "WorldMapFrame" then
        local border = Safety.Field(state.frame, "BorderFrame")
        if Safety.CanDecorate(border, not NS.IsCombatLocked()) and Safety.Read(border, "GetParent") == state.frame then return border end
    end
    return state.frame
end

function Chrome.Level(state)
    local parent = Chrome.Parent(state)
    local level = parent:GetFrameLevel()
    -- Native portrait chrome is raised independently on both clients.
    local borderLevel = Safety.Read(Safety.Field(parent, "NineSlice"), "GetFrameLevel")
    if type(borderLevel) == "number" then level = math.max(level, borderLevel) end
    return level
end

-- Footer actions and native resize handles retain their own hit rectangles.
local outsideGrips = {
    ProfessionsFrame = true, ModelPreviewFrame = true, EventTrace = true, OpacityFrame = true,
    ChatConfigFrame = true, HelpFrame = true, CooldownViewerSettings = true,
    ColorPickerFrame = true, ScriptErrorsFrame = true, ClickBindingFrame = true,
}

function Chrome.Footprint(state)
    if state.inventory and state.name ~= "BankFrame" then return 0, 0, 8 end
    local outside = outsideGrips[state.name] or state.inventory
    return (outside or state.name == "WorldMapFrame") and 21 or 0,
        outside and 21 or 0, state.inventory and state.name ~= "BankFrame" and 18 or 0
end

local function ExteriorGrip(grip, state)
    local frame = state.frame
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local right, bottom = Safety.Read(frame, "GetRight"), Safety.Read(frame, "GetBottom")
    local leftSide = right ~= nil and (right + 21) * ratio > UIParent:GetWidth()
    local topSide = bottom ~= nil and (bottom - 21) * ratio < 0
    local corner = (topSide and "TOP" or "BOTTOM") .. (leftSide and "LEFT" or "RIGHT")
    local point = (topSide and "BOTTOM" or "TOP") .. (leftSide and "RIGHT" or "LEFT")
    grip:SetPoint(point, frame, corner, leftSide and -1 or 1, topSide and 1 or -1)
end

local function BagHandleEdge(state)
    local ratio = state.frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local top = Safety.Read(state.frame, "GetTop")
    local below = top ~= nil and (top + 8) * ratio > UIParent:GetHeight()
    return below and "BOTTOM" or "TOP", below and -7 or 1
end

function Chrome.PlaceGrip(grip, state)
    grip:ClearAllPoints()
    if state.inventory and state.name ~= "BankFrame" then
        local edge, offset = BagHandleEdge(state)
        grip:SetSize(20, 6)
        grip:SetPoint("BOTTOMRIGHT", state.frame, edge .. "RIGHT", -8, offset)
    elseif state.name == "WorldMapFrame" then
        -- Clear quest scrolling and keep the grip above a maximized map's bottom edge.
        grip:SetPoint("BOTTOMLEFT", state.frame, "BOTTOMRIGHT", 1, 3)
        grip:SetClampedToScreen(true)
    elseif outsideGrips[state.name] or state.inventory then
        -- Flip the exterior corner at screen edges; never clamp onto native input.
        ExteriorGrip(grip, state)
    else
        grip:SetPoint("BOTTOMRIGHT", state.frame, "BOTTOMRIGHT", -3, 3)
    end
end

function Chrome.PlaceTitleDrag(strip, state)
    strip:ClearAllPoints()
    if state.inventory and state.name ~= "BankFrame" then
        -- Native bag titles route portrait-menu clicks over their entire area.
        local edge, offset = BagHandleEdge(state)
        strip:SetPoint("BOTTOMLEFT", state.frame, edge .. "LEFT", 50, offset)
        strip:SetPoint("BOTTOMRIGHT", state.frame, edge .. "RIGHT", -34, offset)
        strip:SetHeight(6)
        if not fills[strip] then Chrome.PaintControl(strip, "buttonFill") end
    elseif state.name == "OpacityFrame" then
        -- This native popup is only 80 wide; its slider starts 35 below the top.
        strip:SetPoint("TOPLEFT", state.frame, "TOPLEFT", 4, -3)
        strip:SetPoint("TOPRIGHT", state.frame, "TOPRIGHT", -4, -3)
        strip:SetHeight(20)
    else
        strip:SetPoint("TOPLEFT", state.frame, "TOPLEFT", 50, -1)
        strip:SetPoint("TOPRIGHT", state.frame, "TOPRIGHT", -110, -1)
        strip:SetHeight(24)
    end
end

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
