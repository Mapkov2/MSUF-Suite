local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

local QUICK_ACTIONS = {
    { L["Choose a look"], "looks", "buttonPrimary" },
    { L["Customize icons"], "icons", "button" },
    { L["Choose a font"], "typography", "button" },
    { L["Choose coverage"], "skins", "button" },
}

local function BuildQuickSetup(page)
    local hero = O.CreatePanel(page, "card")
    hero:SetPoint("TOPLEFT", 4, -122)
    hero:SetPoint("TOPRIGHT", -4, -122)
    hero:SetHeight(178)

    local heroTitle = O.CreateText(hero, L["QUICK SETUP"], 12, "accent")
    heroTitle:SetPoint("TOPLEFT", 16, -16)
    local heroText = O.CreateText(hero,
        L["1. Pick a complete look.  2. Tune icons.  3. Choose a font.  4. Decide which Blizzard interfaces are skinned."],
        13, "text")
    heroText:SetPoint("TOPLEFT", heroTitle, "BOTTOMLEFT", 0, -10)
    heroText:SetPoint("RIGHT", -18, 0)
    heroText:SetJustifyV("TOP")

    local previous
    for index = 1, #QUICK_ACTIONS do
        local action = QUICK_ACTIONS[index]
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
    return hero
end

local function PreviewCard(parent, titleText, bodyText)
    local card = O.CreatePanel(parent, "card")
    local title = O.CreateText(card, titleText, 16, "title")
    title:SetPoint("TOPLEFT", 16, -18)
    local body = O.CreateText(card, bodyText, 12, "muted")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -9)
    body:SetPoint("RIGHT", -16, 0)
    body:SetJustifyV("TOP")
    return card
end

local function BuildStylePreview(page, hero)
    local preview = O.CreatePanel(page, "navigation")
    preview:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -12)
    preview:SetPoint("BOTTOMRIGHT", -4, 4)

    local previewTitle = O.CreateText(preview, L["CURRENT STYLE PREVIEW"], 11, "muted")
    previewTitle:SetPoint("TOPLEFT", 16, -14)

    local card = PreviewCard(preview, L["Every color has a purpose"],
        L["Guided mode shows the essentials. Expert mode exposes all %d RGBA tokens and exact hex entry."]
            :format(#NS.ColorOrder))
    card:SetPoint("TOPLEFT", 16, -42)
    card:SetSize(320, 150)
    local primary = O.CreateButton(card, L["Primary action"], 134, 28, nil, "buttonPrimary")
    primary:SetPoint("BOTTOMLEFT", 16, 16)
    local secondary = O.CreateButton(card, L["Secondary"], 120, 28)
    secondary:SetPoint("LEFT", primary, "RIGHT", 8, 0)

    local shapeCard = PreviewCard(preview, L["Safe to experiment"],
        L["Undo and redo are always available in the sidebar. Profile import/export keeps every setting portable."])
    shapeCard:SetPoint("TOPLEFT", card, "TOPRIGHT", 12, 0)
    shapeCard:SetPoint("BOTTOMRIGHT", -16, 16)
end

O.RegisterPage("dashboard", NS.L.DASHBOARD, function(page)
    O.CreateSectionTitle(page, L["Make the Blizzard UI yours"],
        L["Choose a style, font and coverage in minutes. Every deeper control remains available in Expert mode."])

    local master = O.CreateToggle(page, NS.L.MASTER_ENABLE, function()
        return NS.DB.enabled
    end, function(value)
        NS.Adapters.SetMasterEnabled(value)
    end, 520)
    master:SetPoint("TOPLEFT", 4, -70)

    BuildStylePreview(page, BuildQuickSetup(page))
end)
