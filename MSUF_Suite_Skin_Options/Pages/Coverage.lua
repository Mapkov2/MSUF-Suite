local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

local WIDTH = 750

local CATEGORY_LABELS = {
    character = L["Character and equipment"],
    inventory = L["Bags and bank"],
    npc = L["Merchants and NPC interaction"],
    quest = L["Quests and gossip"],
    social = L["Social, mail and guild"],
    group = L["Group Finder and PvE"],
    profession = L["Professions and crafting"],
    economy = L["Auction and economy"],
    journal = L["Collections and journals"],
    map = L["Map interfaces"],
    calendar = L["Calendar"],
    utility = L["Utility windows and dialogs"],
    ["item-service"] = L["Item services and upgrades"],
    expansion = L["Expansion-specific interfaces"],
    housing = L["Housing interfaces"],
    hud = L["Blizzard HUD chrome and alerts"],
    tutorial = L["Tutorials and help overlays"],
}

local CHARACTER_VIEWS = { "modern", "list", "classic" }

local function CharacterViewLabel(value)
    return NS.L["CHARACTER_VIEW_" .. string.upper(value)]
end

-- { label, settings table, key, module }: character panel switches.
local CHARACTER_TOGGLES = {
    { NS.L.DOSSIER_OPTION, "characterDetails", "enabled", "CharacterDetails" },
    { NS.L.DOSSIER_OPEN_OPTION, "characterDetails", "expanded", "CharacterDetails" },
    { NS.L.STATS_OPTION, "characterStats", "enabled", "CharacterStats" },
    { NS.L.STATS_DR_OPTION, "characterStats", "diminishingReturns", "CharacterStats" },
}

local function BuildCharacterControls(page)
    local view, viewButton = O.CreateDropdown(page, NS.L.CHARACTER_VIEW, CHARACTER_VIEWS, function()
        return NS.CharacterDetails.GetView() or "modern"
    end, function(value)
        NS.CharacterDetails.SetView(value)
    end, WIDTH, CharacterViewLabel, nil, { history = false })
    view:SetPoint("TOPLEFT", 4, -65)
    page._mskinCharacterViewSelector = viewButton

    local previous = view
    for index = 1, #CHARACTER_TOGGLES do
        local spec = CHARACTER_TOGGLES[index]
        local group, key, module = spec[2], spec[3], spec[4]
        local toggle = O.CreateToggle(page, spec[1], function()
            return NS.DB[group][key]
        end, function(value)
            NS[module].SetOption(key, value)
        end, WIDTH)
        toggle:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
        previous = toggle
    end
    -- EnhanceQoL styling is on unless it was switched off.
    local eqol = O.CreateToggle(page, NS.L.EQOL_CHARACTER_OPTION, function()
        return NS.DB.characterDetails.styleEQoL ~= false
    end, function(value)
        NS.CharacterDetails.SetOption("styleEQoL", value)
    end, WIDTH)
    eqol:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
end

local function BuildCategories(page)
    local scrollHost = CreateFrame("Frame", nil, page)
    scrollHost:SetPoint("TOPLEFT", 4, -380)
    scrollHost:SetPoint("BOTTOMRIGHT", -4, 4)
    local categories = NS.GenericWindows.GetCategories()
    local _, content = O.CreateScrollContainer(scrollHost, #categories * 48 + 12)

    local previous
    for index = 1, #categories do
        local item = categories[index]
        local label = (CATEGORY_LABELS[item.id] or item.id)
            .. "   " .. L["%d groups / %d roots"]:format(item.groups, item.frames)
        local toggle = O.CreateToggle(content, label, function()
            return NS.DB.skinCategories[item.id]
        end, function(value)
            NS.GenericWindows.SetCategoryEnabled(item.id, value)
        end, WIDTH)
        if previous then
            toggle:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
        else
            toggle:SetPoint("TOPLEFT", 0, -2)
        end
        previous = toggle
    end
end

O.RegisterPage("coverage", NS.L.COVERAGE, function(page)
    O.CreateSectionTitle(page, L["Window categories"],
        L["Choose broad UI families. Dedicated secure behavior and semantic artwork remain untouched."])
    BuildCharacterControls(page)
    BuildCategories(page)
end)
