local _, P = ...
local ID, PAGE = "navigation", "suite_qualityOfLife"
local KEYS = { markerSize = 2, cardWidth = 2, navigatorX = 2, beamHeight = 2, fontSize = 2 }
local TAB_LABELS = { "Basics", "Appearance", "Destinations", "Sounds", "Guides" }

local function Enabled()
    return P.S.Status(ID) == "Active" and not P.Combat()
end

local function Import()
    P.AskText("navigation-import", P.Tr("Paste one /way command per line. Nothing is tracked until you choose a saved place."),
        function(text)
            local navigation = P.S.Navigation
            if not navigation or not Enabled() then return end
            local _, message = navigation.Import(text)
            if message then P.S.Print(message) end
        end, 6500)
end

local function Actions(ctx, parent, section, y, width)
    local buttons = {
        { "Saved places", function() P.S.Navigation.OpenPlaces() end },
        { "Save my position", function() P.S.Navigation.SaveHere() end },
        { "Import waypoints", Import },
        { "Stop navigation", function() P.S.Navigation.Clear() end },
        { "Plan current route", function() P.S.Navigation.PlanRoute() end },
        { "Next route step", function() P.S.Navigation.NextStep() end },
        { "Preview navigation sound", function() P.S.Navigation.Play(P.S.Config(ID), true) end },
    }
    for index, button in ipairs(buttons) do
        local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
        P.Button(ctx, parent, button[1], 16 + column * width / 2, y - row * 35, width / 2 - 6,
            button[2], Enabled, P.Meta(PAGE, ID, "action." .. index, "action", section))
    end
    return y - math.ceil(#buttons / 2) * 35 - 10
end

function P.BuildNavigationDetails(ctx, parent, group, sectionId, width, sections, allRules, keywords, register)
    local panels, tabs, active, ui = {}, {}, nil, nil
    local function Select(index)
        active = index
        for number, panel in ipairs(panels) do panel:SetShown(number == index) end
        for number, tab in ipairs(tabs) do tab:SetAlpha(number == index and 1 or .65) end
    end
    local y
    y, ui = P.BuildNavigationPreview(ctx, parent, width, function(key) Select(KEYS[key] or 1) end)
    y = Actions(ctx, parent, sectionId, y, width - 32)
    local columns = width < 580 and 3 or #sections
    local tabWidth = (width - 32) / columns
    for index, section in ipairs(sections) do
        local slot = index - 1
        tabs[index] = P.Button(ctx, parent, TAB_LABELS[index], 16 + slot % columns * tabWidth,
            y - math.floor(slot / columns) * 32, tabWidth - 5, function() Select(index) end, nil,
            P.Meta(PAGE, ID, "tab." .. index, "action", sectionId))
    end
    y = y - math.ceil(#sections / columns) * 32 - 8
    local maxHeight = 0
    for index, section in ipairs(sections) do
        local panel = CreateFrame("Frame", nil, parent)
        panel:SetPoint("TOPLEFT", 0, y)
        panel:SetSize(width, 32)
        panels[index] = panel
        local bottom, entries = P.RuleGrid(ctx, panel, PAGE, ID, section.rules, -4, width - 32, nil, sectionId, nil, nil, true)
        register(group, sectionId, entries, keywords)
        for _, entry in ipairs(entries or {}) do
            if entry.widget then
                P.HM.SetSearchTargetPrepare(entry.widget, function()
                    local revealed = group.reveal(true)
                    Select(index)
                    return revealed ~= nil
                end)
            end
        end
        panel:SetHeight(math.max(40, -bottom + 8))
        maxHeight = math.max(maxHeight, -bottom + 8)
    end
    Select(1)
    local shortcut = P.AttachRuleColors(parent, group.title, ID, allRules)
    if shortcut then
        P.M.RegisterControlMetadata(shortcut, P.Meta(PAGE, ID, "action.colors.enabled", "action", sectionId),
            P.Tr("%s Colors"):format(P.Tr(group.title)), "button")
    end
    return y - maxHeight, -y + maxHeight + 12, shortcut
end
