local _, Suite = ...
-- Layout profiles and palette choices are independent. Default palettes keep
-- each author's settings; changing colors only restyles the staged copy.
local Picker = {}
Suite.InstallerProfiles = Picker
local Text = Suite.Text
local COLORS = {
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
    return Text("Clean Modern")
end

function Picker.Build(window, label, card, button, style, chooseLayout, chooseLook)
    window.classic = card(window, 36, 241, function() chooseLayout("classic") end)
    window.classic.title:SetText(Text("Modern MSUF Suite · Retail profile"))
    window.classic.detail:SetText(Text("Original Retail unitframes with the Modern Suite layout."))
    window.forever = card(window, 36, 169, function() chooseLayout("forever") end)
    window.forever.title:SetText(Text("MSUF Forever  ·  Complete profile"))
    window.forever.detail:SetText(Text("Installs the Forever factory for MSUF frames, Suite and optional Skin."))
    window.colorLabel = label(window, "GameFontNormalSmall", 36, -306, 508, 16)
    window.colorLabel:SetText(Text("Colors"))
    window.colors, window.colorStyle = {}, style
    for index, choice in ipairs(COLORS) do
        local key = choice[1]
        local control = button(window, 36 + (index - 1) * 103, 108, 96, Text(choice[2]),
            function() chooseLook(key) end)
        control.look = key
        control.caption:SetSize(90, 28)
        control.caption:SetFontObject("GameFontHighlightSmall")
        control.caption:SetJustifyH("CENTER")
        control:SetScript("OnLeave", function(self) style(self, window.colorChoice == key) end)
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
    window.colorLabel:SetShown(shown)
    for _, control in ipairs(window.colors) do
        control:SetShown(shown)
        window.colorStyle(control, control.look == look)
    end
end
