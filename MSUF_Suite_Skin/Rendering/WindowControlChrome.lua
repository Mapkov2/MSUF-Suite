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
