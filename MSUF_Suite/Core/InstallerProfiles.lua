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

local LAYOUTS = {
    { "classic", "Modern MSUF Suite", "Modern Suite layout with DataTexts, damage meters and optional Skin." },
    { "forever", "MSUF Suite Forever", "Forever Suite layout with Antique Map and optional parchment Skin." },
    { "modernDark", "Modern Dark", "Dark unit frames, class colors and square cooldown icons." },
    { "blizzard", "MSUF Blizzard", "Gold portraits, centered cooldowns and a familiar Blizzard layout." },
    { "darkRaid", "Dark Raid", "Compact dark frames, a corner raid grid and centered cooldowns." },
    { "wayfarer", "Wayfarer", "Brass frames, three action rows and a quest tracker below the map." },
    { "preMidnight", "Pre-Midnight", "Dark Rogue HUD, compact side panels and narrow action bars." },
}

function Picker.LayoutName(layout)
    for _, entry in ipairs(LAYOUTS) do
        if entry[1] == layout then return entry[2] end
    end
    return LAYOUTS[1][2]
end

function Picker.HasPaletteChoice(layout)
    return layout ~= "blizzard" and layout ~= "wayfarer" and layout ~= "preMidnight"
end

function Picker.IsFullLayout(layout)
    return layout == "modernDark" or layout == "blizzard" or layout == "darkRaid"
        or layout == "wayfarer" or layout == "preMidnight"
end

local function ExistingRows(window, button, choose)
    local names = Suite.SuiteProfiles.Names()
    local height = math.max(177, #names * 36)
    window.existingProfileContent:SetHeight(height)
    for index, name in ipairs(names) do
        local row = window.existingProfileRows[index]
        if not row then
            row = button(window.existingProfileContent, 0, 0, 484, "", function(self)
                if window:IsShown() and window.existingProfilesOpen then choose(self.profileName) end
            end)
            window.existingProfileRows[index] = row
        end
        row.profileName = name
        row.caption:SetText(Text("Use profile: %s"):format(name))
        row:ClearAllPoints()
        row:SetPoint("BOTTOMLEFT", window.existingProfileContent, "BOTTOMLEFT", 0, height - index * 36 + 6)
        row:Show()
    end
    for index = #names + 1, #window.existingProfileRows do window.existingProfileRows[index]:Hide() end
    window.existingProfiles:SetVerticalScroll(0)
    return #names > 0
end

function Picker.BuildExisting(window, button, choose)
    window.existingProfileRows = {}
    local scroll = CreateFrame("ScrollFrame", nil, window, "ScrollFrameTemplate")
    scroll:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 36, 110)
    scroll:SetSize(484, 177)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(484, 177)
    scroll:SetScrollChild(content)
    scroll:Hide()
    window.existingProfiles, window.existingProfileContent = scroll, content
    window.existingProfileButton = button(window, 36, 300, 508, Text("Use an existing profile"), function()
        window.existingProfilesOpen = not window.existingProfilesOpen and ExistingRows(window, button, choose) or false
        Suite.Installer.Refresh()
        Suite.Client.ResumeControllerWindow(window)
    end)
end

function Picker.ShowExisting(window, shown)
    if not shown then window.existingProfilesOpen = false end
    window.existingProfileButton:SetShown(shown and #Suite.SuiteProfiles.Names() > 0)
    window.existingProfileButton.caption:SetText(window.existingProfilesOpen and Text("Back") or Text("Use an existing profile"))
    window.existingProfiles:SetShown(shown and window.existingProfilesOpen)
end

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
    frame:SetSize(104, 10)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 388, -12)
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
    frame.fill:SetSize(64, 8)
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
    local selectedProfile
    for _, card in ipairs(window.layoutCards) do
        local profile = window.previewProfile(card.layout)
        local palette = Picker.HasPaletteChoice(card.layout) and look or "authored"
        PaintSample(card.preview, Colors(profile, palette))
        if card.layout == layout then selectedProfile = profile end
    end
    if not Picker.HasPaletteChoice(layout) then return end
    local keys = { "bgColor", "borderColor", "barColor", "leftColor" }
    for _, control in ipairs(window.colors) do
        local colors = Colors(selectedProfile, control.look)
        for index, texture in ipairs(control.swatches) do
            texture:SetShown(colors ~= nil)
            if colors then Tint(texture, colors[keys[index]]) end
        end
    end
end

function Picker.Build(window, label, card, button, style, chooseLayout, chooseLook, previewProfile)
    local cards = {}
    for index, entry in ipairs(LAYOUTS) do
        local layout, name, description = entry[1], entry[2], entry[3]
        local control = card(window, 36, 0, function() chooseLayout(layout) end)
        control.layout = layout
        control.title:SetText(Text(name))
        control.detail:SetText(Text(description))
        control:SetHeight(23)
        control.mark:SetPoint("TOPLEFT", control, "TOPLEFT", 388, -1)
        control.mark:SetHeight(11)
        control.title:SetFontObject("GameFontNormalSmall")
        control.title:SetPoint("TOPLEFT", control, "TOPLEFT", 16, -1)
        control.title:SetHeight(11)
        control.detail:SetPoint("TOPLEFT", control, "TOPLEFT", 16, -12)
        control.detail:SetHeight(11)
        control.preview = Sample(control)
        cards[index], window[layout] = control, control
    end
    window.layoutCards, window.previewProfile = cards, previewProfile
    window.colorLabel = label(window, "GameFontNormalSmall", 36, -337, 508, 16)
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
    for index, card in ipairs(window.layoutCards) do
        local selected = card.layout == layout
        local slot = Suite.Client.isForever and index <= 2 and 3 - index or index
        card:ClearAllPoints()
        card:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 36, 309 - (slot - 1) * 24)
        card:SetShown(shown)
        window.colorStyle(card, selected)
        card.mark:SetText(Text(selected and "SELECTED" or "CHOOSE"))
    end
    if shown then PaintPreviews(window, layout, look) end
    local palettes = shown and Picker.HasPaletteChoice(layout)
    window.colorLabel:SetShown(palettes)
    for _, control in ipairs(window.colors) do
        control:SetShown(palettes)
        window.colorStyle(control, control.look == look)
    end
end
