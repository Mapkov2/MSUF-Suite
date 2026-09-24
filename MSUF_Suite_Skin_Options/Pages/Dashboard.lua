local _, Private = ...
local NS, O = Private.NS, Private.Options

O.RegisterPage("dashboard", NS.L.DASHBOARD, function(page)
    O.CreateSectionTitle(page, "Make the Blizzard UI yours", "Choose a style, font and coverage in minutes. Every deeper control remains available in Expert mode.")

    local master = O.CreateToggle(page, NS.L.MASTER_ENABLE, function()
        return NS.DB.enabled
    end, function(value)
        NS.Adapters.SetMasterEnabled(value)
    end, 520)
    master:SetPoint("TOPLEFT", 4, -70)

    local hero = O.CreatePanel(page, "card")
    hero:SetPoint("TOPLEFT", 4, -122)
    hero:SetPoint("TOPRIGHT", -4, -122)
    hero:SetHeight(178)

    local heroTitle = O.CreateText(hero, "QUICK SETUP", 12, "accent")
    heroTitle:SetPoint("TOPLEFT", 16, -16)
    local heroText = O.CreateText(hero,
        "1. Pick a complete look.  2. Tune icons.  3. Choose a font.  4. Decide which Blizzard interfaces are skinned.",
        13, "text")
    heroText:SetPoint("TOPLEFT", heroTitle, "BOTTOMLEFT", 0, -10)
    heroText:SetPoint("RIGHT", -18, 0)
    heroText:SetJustifyV("TOP")

    local actions = {
        { "Choose a look", "looks", "buttonPrimary" },
        { "Customize icons", "icons", "button" },
        { "Choose a font", "typography", "button" },
        { "Choose coverage", "skins", "button" },
    }
    local previous
    for index = 1, #actions do
        local action = actions[index]
        local tag = O.CreateButton(hero, action[1], 176, 30, function()
            O.ShowPage(action[2])
        end, action[3])
        if previous then
            tag:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        else
            tag:SetPoint("BOTTOMLEFT", 16, 16)
        end
        previous = tag
    end

    local preview = O.CreatePanel(page, "navigation")
    preview:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -12)
    preview:SetPoint("BOTTOMRIGHT", -4, 4)

    local previewTitle = O.CreateText(preview, "CURRENT STYLE PREVIEW", 11, "muted")
    previewTitle:SetPoint("TOPLEFT", 16, -14)

    local card = O.CreatePanel(preview, "card")
    card:SetPoint("TOPLEFT", 16, -42)
    card:SetSize(320, 150)
    local title = O.CreateText(card, "Every color has a purpose", 16, "title")
    title:SetPoint("TOPLEFT", 16, -18)
    local body = O.CreateText(card,
        ("Guided mode shows the essentials. Expert mode exposes all %d RGBA tokens and exact hex entry."):format(#NS.ColorOrder),
        12, "muted")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -9)
    body:SetPoint("RIGHT", -16, 0)
    body:SetJustifyV("TOP")

    local primary = O.CreateButton(card, "Primary action", 134, 28, nil, "buttonPrimary")
    primary:SetPoint("BOTTOMLEFT", 16, 16)
    local secondary = O.CreateButton(card, "Secondary", 120, 28)
    secondary:SetPoint("LEFT", primary, "RIGHT", 8, 0)

    local shapeCard = O.CreatePanel(preview, "card")
    shapeCard:SetPoint("TOPLEFT", card, "TOPRIGHT", 12, 0)
    shapeCard:SetPoint("BOTTOMRIGHT", -16, 16)
    local shapeTitle = O.CreateText(shapeCard, "Safe to experiment", 16, "title")
    shapeTitle:SetPoint("TOPLEFT", 16, -18)
    local shapeBody = O.CreateText(shapeCard, "Undo and redo are always available in the sidebar. Profile import/export keeps every setting portable.", 12, "muted")
    shapeBody:SetPoint("TOPLEFT", shapeTitle, "BOTTOMLEFT", 0, -9)
    shapeBody:SetPoint("RIGHT", -16, 0)
    shapeBody:SetJustifyV("TOP")
end)
