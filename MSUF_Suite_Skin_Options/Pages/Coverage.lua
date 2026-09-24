local _, Private = ...
local NS, O = Private.NS, Private.Options

local labels = {
    character = "Character and equipment",
    inventory = "Bags and bank",
    npc = "Merchants and NPC interaction",
    quest = "Quests and gossip",
    social = "Social, mail and guild",
    group = "Group Finder and PvE",
    profession = "Professions and crafting",
    economy = "Auction and economy",
    journal = "Collections and journals",
    map = "Map interfaces",
    calendar = "Calendar",
    utility = "Utility windows and dialogs",
    ["item-service"] = "Item services and upgrades",
    expansion = "Expansion-specific interfaces",
    housing = "Housing interfaces",
    hud = "Blizzard HUD chrome and alerts",
    tutorial = "Tutorials and help overlays",
}

O.RegisterPage("coverage", NS.L.COVERAGE, function(page)
    O.CreateSectionTitle(page, "Window categories", "Choose broad UI families. Dedicated secure behavior and semantic artwork remain untouched.")

    local view,viewButton=O.CreateDropdown(page,NS.L.CHARACTER_VIEW,{"modern","list","classic"},function()
        return NS.CharacterDetails.GetView() or "modern"
    end,function(value) NS.CharacterDetails.SetView(value) end,750,function(value)
        return NS.L["CHARACTER_VIEW_"..string.upper(value)]
    end,nil,{history=false})
    view:SetPoint("TOPLEFT",4,-65)
    page._mskinCharacterViewSelector=viewButton
    local dossier=O.CreateToggle(page,NS.L.DOSSIER_OPTION,function()
        return NS.DB.characterDetails.enabled
    end,function(value) NS.CharacterDetails.SetOption("enabled",value) end,750)
    dossier:SetPoint("TOPLEFT",view,"BOTTOMLEFT",0,-6)
    local expanded=O.CreateToggle(page,NS.L.DOSSIER_OPEN_OPTION,function()
        return NS.DB.characterDetails.expanded
    end,function(value) NS.CharacterDetails.SetOption("expanded",value) end,750)
    expanded:SetPoint("TOPLEFT",dossier,"BOTTOMLEFT",0,-6)
    local stats=O.CreateToggle(page,NS.L.STATS_OPTION,function()
        return NS.DB.characterStats.enabled
    end,function(value) NS.CharacterStats.SetOption("enabled",value) end,750)
    stats:SetPoint("TOPLEFT",expanded,"BOTTOMLEFT",0,-6)
    local dr=O.CreateToggle(page,NS.L.STATS_DR_OPTION,function()
        return NS.DB.characterStats.diminishingReturns
    end,function(value) NS.CharacterStats.SetOption("diminishingReturns",value) end,750)
    dr:SetPoint("TOPLEFT",stats,"BOTTOMLEFT",0,-6)
    local eqol=O.CreateToggle(page,NS.L.EQOL_CHARACTER_OPTION,function()
        return NS.DB.characterDetails.styleEQoL ~= false
    end,function(value) NS.CharacterDetails.SetOption("styleEQoL",value) end,750)
    eqol:SetPoint("TOPLEFT",dr,"BOTTOMLEFT",0,-6)

    local scrollHost = CreateFrame("Frame", nil, page)
    scrollHost:SetPoint("TOPLEFT", 4, -380)
    scrollHost:SetPoint("BOTTOMRIGHT", -4, 4)
    local categories = NS.GenericWindows.GetCategories()
    local _, content = O.CreateScrollContainer(scrollHost, #categories * 48 + 12)

    local previous
    for index = 1, #categories do
        local item = categories[index]
        local label = (labels[item.id] or item.id) .. ("   %d groups / %d roots"):format(item.groups, item.frames)
        local toggle = O.CreateToggle(content, label, function()
            return NS.DB.skinCategories[item.id]
        end, function(value)
            NS.GenericWindows.SetCategoryEnabled(item.id, value)
        end, 750)
        if previous then
            toggle:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
        else
            toggle:SetPoint("TOPLEFT", 0, -2)
        end
        previous = toggle
    end
end)
