local _, Suite = ...
-- The first-run picker separates primary modules from optional QoL helpers.
-- This view only stages choices; Installer owns the profile transaction.
local List = {}
Suite.InstallerModules = List
local Text = Suite.Text

local function ModuleRow(parent, id, panel, label, toggle)
    local card = panel(parent, 0, 0, 250, 22, true)
    card.id = id
    card.label = label(card, "GameFontHighlightSmall", 10, -4, 188, 16)
    card.label:SetText(Text((Suite.SuiteCatalog[id] and Suite.SuiteCatalog[id].title) or id))
    card.state = label(card, "GameFontNormalSmall", 198, -4, 42, 16)
    card.state:SetJustifyH("RIGHT")
    card:SetScript("OnClick", function() toggle(id) end)
    card:SetScript("OnEnter", function(self)
        local spec = Suite.SuiteCatalog[id]
        if not spec then return end
        local tooltip = GameTooltip
        tooltip:SetOwner(self, "ANCHOR_RIGHT")
        tooltip:SetText(Text(spec.title or id))
        if type(spec.description) == "string" and spec.description ~= "" then
            tooltip:AddLine(Text(spec.description), 0.78, 0.84, 0.89, true)
        end
        local available, reason = Suite.Suite.Availability(id)
        if not available and reason then
            tooltip:AddLine(Suite.StatusText(tostring(reason), Text), 1, 0.45, 0.4, true)
        end
        tooltip:Show()
    end)
    card:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return card
end

function List.Show(window, shown)
    local scroll = window.moduleScroll
    scroll:SetShown(shown)
    for key, tab in pairs(window.moduleTabs) do
        tab:SetShown(shown)
        window.moduleTabStyle(tab, key == window.moduleTab)
    end
    local group = window.moduleGroups[window.moduleTab]
    local perColumn = math.ceil(#group / 2)
    local content = scroll:GetScrollChild()
    content:SetSize(508, math.max(172, perColumn * 25))
    for _, row in ipairs(window.moduleRows) do row:Hide() end
    for index, row in ipairs(group) do
        local column = index > perColumn and 1 or 0
        local line = column == 0 and index - 1 or index - perColumn - 1
        row:ClearAllPoints()
        row:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", column * 258, content:GetHeight() - 22 - line * 25)
        row:SetShown(shown)
    end
end

function List.Build(window, panel, label, navButton, style, toggle)
    -- ScrollFrameTemplate supplies native wheel input and a draggable bar on
    -- Retail and Forever. Content never extends into the footer/navigation.
    local scroll = CreateFrame("ScrollFrame", nil, window, "ScrollFrameTemplate")
    scroll:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 36, 82)
    scroll:SetSize(508, 172)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(508, 172)
    scroll:SetScrollChild(content)
    window.moduleScroll, window.moduleRows = scroll, {}
    window.moduleTab, window.moduleTabStyle = "modules", style
    window.moduleGroups, window.moduleTabs = { modules = {}, qol = {} }, {}
    for index, id in ipairs(Suite.SuiteOrder) do
        local row = ModuleRow(content, id, panel, label, toggle)
        window.moduleRows[index] = row
        local spec = Suite.SuiteCatalog[id]
        local group = window.moduleGroups[spec and spec.addon == "MSUF_Suite_QualityOfLife" and "qol" or "modules"]
        group[#group + 1] = row
    end
    for index, key in ipairs({ "modules", "qol" }) do
        local tab = navButton(window, 36 + (index - 1) * 258, 266, 250,
            Text(key == "modules" and "Modules" or "Quality of Life"), function()
                window.moduleTab = key
                List.Show(window, true)
                scroll:SetVerticalScroll(0)
            end)
        tab:SetScript("OnLeave", function(self) style(self, key == window.moduleTab) end)
        window.moduleTabs[key] = tab
    end
end
