local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L
local WIDTH = 474
local statusLabels = {
    missing = L["Not installed"], disabled = L["Disabled"], waiting = L["Waiting for addon"],
    ready = L["Ready"], applied = L["Skinned"],
}

local function Toggle(parent, label, key, previous)
    local toggle = O.CreateToggle(parent, label, function()
        return NS.DB.addonSkins[key]
    end, function(value) NS.AddonSkins.SetOption(key, value) end, WIDTH)
    if previous then toggle:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
    else toggle:SetPoint("TOPLEFT", 0, -2) end
    return toggle
end

O.RegisterPage("addonSkins", L["Addon skins"], function(page)
    O.CreateSectionTitle(page, L["Addon skins"],
        L["Apply your current skin to supported addon windows. Enable the addons you want to skin."])
    local definitions = NS.AddonSkinDefinitions
    local _, content = O.CreateLeftColumn(page, 500, (#definitions + 2) * 46 + 10, WIDTH)
    local previous = Toggle(content, L["Skin other addons"], "enabled")
    previous = Toggle(content, L["AceGUI / AceConfig windows"], "aceGUI", previous)
    local card = O.CreatePanel(page, "card")
    card:SetPoint("TOPLEFT", 524, -70)
    card:SetPoint("BOTTOMRIGHT", -4, 4)
    local _, statusContent = O.CreateScrollContainer(card, #definitions * 24 + 52, 250)
    local title = O.CreateText(statusContent, L["Addon status"], 11, "accent")
    title:SetPoint("TOPLEFT", 16, -16)
    for index = 1, #definitions do
        local entry = definitions[index]
        previous = Toggle(content, entry.label, entry.id, previous)
        local line = O.CreateText(statusContent, "", 10, "muted")
        line:SetPoint("TOPLEFT", 16, -42 - (index - 1) * 24)
        line:SetPoint("RIGHT", -12, 0)
        line:SetWordWrap(false)
        line:SetMaxLines(1)
        O.TrackRefresh(function()
            local status = NS.AddonSkins.GetStatus(entry.id)
            line:SetText(string.format("%s: %s", entry.label, statusLabels[status] or statusLabels.ready))
            O.SetTextColor(line, status == "applied" and "success" or "muted")
        end)
    end
end)
