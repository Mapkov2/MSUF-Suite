local _, P = ...
local D, S, NS = P.DamageMeter, P.Suite, P.NS
local M = D.M
local WIDTH, GAP, ROW, PAD, HEADING = 176, 6, 24, 8, 19

local function Favorites()
    local config = M.config.favoriteMeters
    if M.favoriteConfig == config then return M.favoriteTypes end
    local selected = {}
    for value in config:gmatch("%d+") do
        local kind = tonumber(value)
        if kind >= 0 and kind < #NS.DamageMeterTypeLabels then selected[kind] = true end
    end
    M.favoriteConfig, M.favoriteTypes = config, selected
    return selected
end

function D.ToggleFavorite(kind)
    if M.inCombat or NS.IsCombatLocked() then return false end
    local selected, values = Favorites(), {}
    for meter = 0, #NS.DamageMeterTypeLabels - 1 do
        local on = selected[meter]
        if meter == kind then on = not on end
        if on then values[#values + 1] = tostring(meter) end
    end
    return S.Set(M.id, "favoriteMeters", table.concat(values, ","))
end

local function Position(button, index, y)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT", PAD + ((index - 1) % 2) * (WIDTH + GAP),
        y - math.floor((index - 1) / 2) * (ROW + GAP))
end

local function Heading(panel)
    if panel.favoriteHeading then return panel.favoriteHeading end
    local heading = S.CreateFontString(panel, nil, "OVERLAY")
    D.FontStyle(heading, 11, "details")
    heading:SetText(S.Text("Favorites"))
    heading:SetJustifyH("LEFT")
    panel.favoriteHeading, panel.favoriteButtons = heading, {}
    local help = S.CreateFontString(panel, nil, "OVERLAY")
    D.FontStyle(help, 11, "details")
    help:SetText(S.Text("Right-click a meter to add or remove a favorite."))
    help:SetWordWrap(true)
    help:SetJustifyH("LEFT")
    help:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, 5)
    help:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, 5)
    help:SetHeight(30)
    panel.favoriteHelp = help
    return heading
end

-- Reflow only on opening the picker or changing a favorite. Both groups use
-- the same tile builder and click route; every meter remains in its category.
function D.LayoutFavorites(panel)
    local favorites, count = Favorites(), 0
    for _ in pairs(favorites) do count = count + 1 end
    local shift = count > 0 and HEADING + math.ceil(count / 2) * (ROW + GAP) + 5 or 0
    local heading = Heading(panel)
    D.FontStyle(heading, 11, "details")
    D.FontStyle(panel.favoriteHelp, 11, "details")
    panel.favoriteHelp:SetShown(not M.inCombat and not NS.IsCombatLocked())
    heading:SetTextColor(unpack(panel.palette.accent))
    panel.favoriteHelp:SetTextColor(unpack(panel.palette.text))
    heading:ClearAllPoints()
    heading:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD)
    heading:SetShown(count > 0)
    for _, button in pairs(panel.favoriteButtons) do button:Hide() end
    local index = 0
    for kind = 0, #NS.DamageMeterTypeLabels - 1 do
        if favorites[kind] then
            index = index + 1
            local button = panel.favoriteButtons[kind]
                or D.CreateTypeTile(panel, index, kind, -PAD - HEADING, panel.favoriteButtons)
            Position(button, index, -PAD - HEADING)
            D.FontStyle(button.label, 11, "details")
            D.FontStyle(button.arrow, 11, "details")
            D.StyleTypeTile(button, panel.palette, panel.win.meterType == kind, false)
            button.arrow:SetTextColor(unpack(panel.palette.accent))
            button:Show()
        end
    end
    for _, title in ipairs(panel.headings) do
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, title.baseY - shift)
    end
    for _, button in pairs(panel.buttons) do
        Position(button, button.groupIndex, button.baseY - shift)
        button.arrow:SetText(favorites[button.meterType] and "*" or ">")
    end
    panel:SetHeight(panel.baseHeight + shift + 36)
end
