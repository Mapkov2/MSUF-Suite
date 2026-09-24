local _, P = ...
local NS, O = P.NS, P.Options

local keys = { "dashboard", "looks", "icons", "colors", "typography", "geometry",
    "skins", "coverage", "hud", "profiles", "advanced" }
local originalShowPage = O.ShowPage

-- The MSUF left navigation has one Skinning entry. This second rail exposes
-- every MapkoSkin editor page inside that entry without opening another UI.
function O.Mount(parent, width, height)
    if NS.IsCombatLocked() then return nil end
    local host = O.embeddedHost
    if not host then
        host = CreateFrame("Frame", nil, parent)
        host.pages, host.buttons = {}, {}
        local rail = O.CreatePanel(host, "navigation")
        rail:SetPoint("TOPLEFT", 0, 0)
        rail:SetPoint("BOTTOMLEFT", 0, 0)
        rail:SetWidth(174)
        local title = O.CreateText(rail, "SKINNING", 12, "accent")
        title:SetPoint("TOPLEFT", 12, -12)

        local guided = O.CreateButton(rail, "Guided", 70, 24, function() O.SetMode("guided") end)
        guided:SetPoint("TOPLEFT", 12, -38)
        local expert = O.CreateButton(rail, "Expert", 70, 24, function() O.SetMode("expert") end)
        expert:SetPoint("LEFT", guided, "RIGHT", 8, 0)

        for index, key in ipairs(keys) do
            local def = O.GetPageDefinition(key)
            if def then
                local button = O.CreateButton(rail, def.label, 150, 27,
                    function() host:ShowPage(key) end, "navigation")
                button:SetPoint("TOPLEFT", 12, -73 - (index - 1) * 31)
                local state = O.widgetStates and O.widgetStates[button]
                if state and state.label then state.label:SetJustifyH("LEFT") end
                host.buttons[key] = button
            end
        end

        local searchResults
        local search = O.CreateSearchBox(host, "Search skinning settings...", function(query)
            if searchResults then searchResults(query) end
        end, 310)
        search:SetPoint("TOPLEFT", rail, "TOPRIGHT", 10, -8)
        local popup = O.CreatePanel(host, "popup")
        popup:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -4)
        popup:SetSize(420, 196)
        popup:SetFrameLevel((host.GetFrameLevel and host:GetFrameLevel() or 0) + 25)
        popup:Hide()
        local results = {}
        for index = 1, 6 do
            local row = O.CreateButton(popup, "", 396, 27, nil, "navigation")
            row:SetPoint("TOPLEFT", 12, -8 - (index - 1) * 30)
            local state = O.widgetStates and O.widgetStates[row]
            if state and state.label then state.label:SetJustifyH("LEFT") end
            row:Hide()
            results[index] = row
        end
        host.content = CreateFrame("Frame", nil, host)
        host.content:SetPoint("TOPLEFT", rail, "TOPRIGHT", 10, -46)
        if host.content.SetClipsChildren then host.content:SetClipsChildren(true) end
        function host:ShowPage(key)
            local def = O.GetPageDefinition(key)
            if not def then return false end
            local meta = O.GetPageMeta and O.GetPageMeta(key)
            if meta and meta.simple == false and O.GetMode() ~= "expert" then O.SetMode("expert") end
            if self.key and self.pages[self.key] then self.pages[self.key]:Hide() end
            local page = self.pages[key]
            if not page then
                page = CreateFrame("Frame", nil, self.content)
                page:SetAllPoints(self.content)
                def.builder(page)
                self.pages[key] = page
            end
            self.key = key
            O.ui.lastPage = key
            page:Show()
            for name, button in pairs(self.buttons) do O.SetButtonActive(button, name == key) end
            O.RefreshAll()
            return true
        end
        searchResults = function(query)
            query = tostring(query or "")
            local matches = O.SearchSettings(query, #results)
            for index, row in ipairs(results) do
                local match = matches[index]
                row:SetShown(match ~= nil)
                if match then
                    local state = O.widgetStates and O.widgetStates[row]
                    if state and state.label then
                        state.label:SetText(match.label .. "  |  " .. match.pageLabel)
                    end
                    row:SetScript("OnClick", function()
                        if match.expert then O.SetMode("expert") end
                        host:ShowPage(match.page)
                        search:SetText("")
                        if search.ClearFocus then search:ClearFocus() end
                        popup:Hide()
                    end)
                end
            end
            popup:SetShown(query:match("%S") ~= nil and #matches > 0)
        end
        O.TrackRefresh(function()
            O.SetButtonActive(guided, O.GetMode() == "guided")
            O.SetButtonActive(expert, O.GetMode() == "expert")
        end)
        host:SetScript("OnHide", function()
            popup:Hide()
            if O.CloseDropdown then O.CloseDropdown() end
        end)
        O.embeddedHost = host
    end
    host:SetParent(parent)
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", 0, 0)
    host:SetSize(width, height)
    local scale = math.min(1, math.max(0.55, (width - 184) / 820))
    host.content:SetScale(scale)
    host.content:SetSize((width - 184) / scale, (height - 54) / scale)
    host:ShowPage(host.key or O.ui.lastPage or "dashboard")
    host:Show()
    return host
end

O.ShowPage = function(key, ...)
    local host = O.embeddedHost
    if host and host:IsShown() then return host:ShowPage(key) end
    if originalShowPage then return originalShowPage(key, ...) end
end
