local _, Suite = ...
-- Layout profiles and palette choices are independent. Default palettes keep
-- each author's settings; changing colors only restyles the staged copy.
local Picker = {}
Suite.InstallerProfiles = Picker
local Text = Suite.Text
local COLORS = {
    { "authored", "Profile colors" },
    { "midnight", "Midnight Blue" },
    { "midnightDark", "Midnight Dark" },
    { "foreverGlass", "MSUF Forever" },
    { "cleanModern", "Clean Modern" },
    { "classColor", "Class Style" },
}

function Picker.LookLabel(look)
    for _, choice in ipairs(COLORS) do
        if choice[1] == look then return Text(choice[2]) end
    end
    return Text("Profile colors")
end

-- Only a temporary module-sized palette is restyled. Previewing never
-- activates profiles, loads the meter runtime or writes the saved settings.
local function Colors(profile, look)
    local config = profile and profile.suite.modules.damageMeter
    if not config then return nil end
    local colors = { bgColor = config.bgColor, barColor = config.barColor,
        borderColor = config.borderColor, leftColor = config.leftColor, bgAlpha = config.bgAlpha }
    if look ~= "authored" then Suite.SuiteLooks.ApplyToConfig("damageMeter", colors, look) end
    return colors
end

local function Tint(region, hex, alpha)
    local r, g, b = Suite.RGB(hex)
    region:SetVertexColor(r, g, b, alpha or 1)
end

local function Sample(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(104, 22)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 388, -32)
    frame.edge = frame:CreateTexture(nil, "BACKGROUND")
    frame.edge:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.edge:SetAllPoints(frame)
    frame.background = frame:CreateTexture(nil, "ARTWORK")
    frame.background:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.background:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.fill = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    frame.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.fill:SetSize(64, 20)
    frame.caption = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.caption:SetAllPoints(frame)
    frame.caption:SetText(Text("Preview"))
    return frame
end

local function PaintSample(frame, colors)
    frame:SetShown(colors ~= nil)
    if not colors then return end
    Tint(frame.edge, colors.borderColor)
    Tint(frame.background, colors.bgColor, colors.bgAlpha / 100)
    Tint(frame.fill, colors.barColor)
    frame.caption:SetTextColor(Suite.RGB(colors.leftColor))
end

local function Swatches(control)
    control.swatches = {}
    control:SetSize(80, 38)
    control.caption:ClearAllPoints()
    control.caption:SetPoint("CENTER", control, "CENTER", 0, 5)
    control.caption:SetSize(74, 24)
    for index = 1, 4 do
        local texture = control:CreateTexture(nil, "ARTWORK")
        texture:SetTexture("Interface\\Buttons\\WHITE8X8")
        texture:SetSize(15, 5)
        texture:SetPoint("BOTTOMLEFT", control, "BOTTOMLEFT", 8 + (index - 1) * 16, 4)
        control.swatches[index] = texture
    end
end

local function PaintPreviews(window, layout, look)
    local classic, forever = window.previewProfile("classic"), window.previewProfile("forever")
    PaintSample(window.classic.preview, Colors(classic, look))
    PaintSample(window.forever.preview, Colors(forever, look))
    local profile = layout == "forever" and forever or classic
    local keys = { "bgColor", "borderColor", "barColor", "leftColor" }
    for _, control in ipairs(window.colors) do
        local colors = Colors(profile, control.look)
        for index, texture in ipairs(control.swatches) do
            texture:SetShown(colors ~= nil)
            if colors then Tint(texture, colors[keys[index]]) end
        end
    end
end

function Picker.Build(window, label, card, button, style, chooseLayout, chooseLook, previewProfile)
    window.classic = card(window, 36, 241, function() chooseLayout("classic") end)
    window.classic.title:SetText(Text("Modern MSUF Suite"))
    window.classic.detail:SetText(Text("Modern Suite layout with DataTexts, damage meters and optional Skin."))
    window.forever = card(window, 36, 169, function() chooseLayout("forever") end)
    window.forever.title:SetText(Text("MSUF Suite Forever"))
    window.forever.detail:SetText(Text("Forever Suite layout with Antique Map and optional parchment Skin."))
    window.previewProfile = previewProfile
    window.classic.preview, window.forever.preview = Sample(window.classic), Sample(window.forever)
    window.colorLabel = label(window, "GameFontNormalSmall", 36, -306, 508, 16)
    window.colorLabel:SetText(Text("Colors"))
    window.colors, window.colorStyle = {}, style
    for index, choice in ipairs(COLORS) do
        local key = choice[1]
        local control = button(window, 36 + (index - 1) * 85, 108, 80, Text(choice[2]),
            function() chooseLook(key ~= "authored" and key or nil) end)
        control.look = key
        control.caption:SetSize(74, 28)
        control.caption:SetFontObject("GameFontHighlightSmall")
        control.caption:SetJustifyH("CENTER")
        control:SetScript("OnLeave", function(self) style(self, window.colorChoice == key) end)
        Swatches(control)
        window.colors[index] = control
    end
end

function Picker.Show(window, shown, layout, look)
    window.colorChoice = look
    local cards = Suite.Client.isForever and { window.forever, window.classic }
        or { window.classic, window.forever }
    for index, card in ipairs(cards) do
        card:ClearAllPoints()
        card:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 36, 241 - (index - 1) * 72)
        card:SetShown(shown)
    end
    window.colorStyle(window.classic, layout == "classic")
    window.colorStyle(window.forever, layout == "forever")
    window.classic.mark:SetText(layout == "classic" and Text("SELECTED") or Text("CHOOSE"))
    window.forever.mark:SetText(layout == "forever" and Text("SELECTED") or Text("CHOOSE"))
    if shown then PaintPreviews(window, layout, look) end
    window.colorLabel:SetShown(shown)
    for _, control in ipairs(window.colors) do
        control:SetShown(shown)
        window.colorStyle(control, control.look == look)
    end
end
