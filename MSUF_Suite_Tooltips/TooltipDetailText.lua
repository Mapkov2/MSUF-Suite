local _, P = ...
local NS, S = P.NS, P.Suite
local Lines, Safety = S.TooltipLines, P.Safety
local Text = {}
P.TooltipDetailText = Text

local regions, used, parent = {}, 0
local valueSpace = string.rep("\194\160", 30)
local badgeSpace = string.rep("\194\160", 18)
local iconSpace = string.rep("\194\160", 7)

local function Region(tip, anchor, point, width, r, g, b)
    if not S.Public(anchor) or not anchor or Safety.IsForbidden(anchor) then return end
    used = used + 1
    local region = regions[used]
    if not region then
        parent = parent or Safety.CreateChildFrame("Frame", tip)
        region = parent:CreateFontString(nil, "OVERLAY", "GameTooltipText")
        region:SetWordWrap(false)
        regions[used] = region
    end
    region:ClearAllPoints()
    region:SetPoint(point, anchor, point)
    region:SetJustifyH("RIGHT")
    region:SetWidth(width)
    region:SetTextColor(r, g, b)
    return region
end

function Text.Clear()
    for i = 1, used do
        local region = regions[i]
        region:Hide()
        region:SetText("")
        region:SetAlpha(1)
        region:ClearAllPoints()
    end
    used = 0
end

-- Keep opaque text out of the native tooltip's line data and width
-- calculation. A public spacer holds its place in the native layout.
function Text.Line(tip, label, value, format, own, badgeIcon)
    local secretValue = NS.IsSecret(value)
    if not secretValue and value == nil then return end
    local secretOwn = NS.IsSecret(own)
    if not secretValue and not secretOwn then
        local display = format and format:format(value) or tostring(value)
        if own then display = "<" .. S.Text("You") .. "> " .. display end
        return Lines.Line(tip, label, display, own and 1 or .9, own and .8 or .9, own and .2 or .9)
    end
    if not tip.GetLeftLine or not tip.GetRightLine or not Safety.CanCreateRegions(tip) then return end
    local showBadge = secretOwn or own == true
    local left = S.Text(label)
    if showBadge then left = left .. (badgeIcon and iconSpace or badgeSpace) end
    local right = secretValue and valueSpace or tostring(value)
    tip:AddDoubleLine(left, right, .65, .81, .87, .9, .9, .9)
    local index = tip:NumLines()
    if not S.Finite(index) then return end
    if secretValue then
        local region = Region(tip, tip:GetRightLine(index), "RIGHT", 105, .9, .9, .9)
        if region then
            if format then region:SetFormattedText(format, value) else region:SetText(value) end
            region:Show()
        end
    end
    if showBadge then
        local badge = Region(tip, tip:GetLeftLine(index), "RIGHT", badgeIcon and 20 or 55, 1, .8, .2)
        if badge then
            badge:SetText(badgeIcon or "<" .. S.Text("You") .. ">")
            if secretOwn then badge:SetAlphaFromBoolean(own) end
            badge:Show()
        end
    end
end
