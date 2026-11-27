local _, P = ...
local Tr = P.Tr
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
    if P.Suite.Client.isForever then
        buttons[#buttons + 1] = { "Cozy Sleeping Bag", function() P.S.Navigation.OpenSleepingBag() end }
    end
    for index, button in ipairs(buttons) do
        local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
        P.Button(ctx, parent, button[1], 16 + column * width / 2, y - row * 35, width / 2 - 6,
            button[2], Enabled, P.Meta(PAGE, ID, "action." .. index, "action", section))
    end
    return y - math.ceil(#buttons / 2) * 35 - 10
end

local function NavigationTabs(ctx, parent, sectionId, width, sections, y, selectTab)
    local picker = { ctx = ctx, header = parent, width = width, selected = 1, spec = { page = PAGE, module = ID } }
    local values = {}
    for index in ipairs(sections) do
        values[index] = { value = index, text = Tr(TAB_LABELS[index]),
            meta = P.Meta(PAGE, ID, "tab." .. index, "action", sectionId) }
    end
    local row, choose = P.MenuWorkspace.WrappingTabs(picker, values, function(index)
        picker.selected = index
        selectTab(index)
        return true
    end)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    for _, item in ipairs(row.items) do
        local index = item.id
        item.button:SetScript("OnClick", function()
            if P.Combat() then return end
            choose(index)
            P.Refresh()
        end)
    end
    P.M.TrackRefresh(ctx, function()
        local enabled = not P.Combat()
        for _, item in ipairs(row.items) do item.button:SetEnabled(enabled) end
    end)
    return row, choose
end

function P.BuildNavigationDetails(ctx, parent, group, sectionId, width, sections, allRules, keywords, register, resize)
    local panels, choose = {}, nil
    local function Select(index)
        if choose then
            choose(index)
        end
    end
    local function Show(index)
        for number, panel in ipairs(panels) do panel:SetShown(number == index) end
    end
    local y = P.BuildNavigationPreview(ctx, parent, width, function(key) Select(KEYS[key] or 1) end)
    y = Actions(ctx, parent, sectionId, y, width - 32)
    local tabs
    tabs, choose = NavigationTabs(ctx, parent, sectionId, width, sections, y, Show)
    local content = CreateFrame("Frame", nil, parent)
    content:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", -16, -8)
    content:SetSize(width, 1)
    local maxHeight = 0
    for index, section in ipairs(sections) do
        local panel = CreateFrame("Frame", nil, content)
        panel:SetPoint("TOPLEFT")
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
    local function Bottom() return y - tabs:GetHeight() - 8 - maxHeight end
    if resize then tabs:HookScript("OnSizeChanged", function() resize(Bottom()) end) end
    local shortcut = P.AttachRuleColors(parent, group.title, ID, allRules)
    if shortcut then
        P.M.RegisterControlMetadata(shortcut, P.Meta(PAGE, ID, "action.colors.enabled", "action", sectionId),
            Tr("%s Colors"):format(Tr(group.title)), "button")
    end
    local bottom = Bottom()
    return bottom, -bottom + 12, shortcut
end
