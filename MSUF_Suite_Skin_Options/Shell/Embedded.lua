local _, P = ...
local NS, O = P.NS, P.Options
local L = NS.L

-- The MSUF left navigation has one Skinning entry. This second rail exposes
-- every MapkoSkin editor page inside that entry without opening another UI.
local PAGE_KEYS = { "dashboard", "looks", "icons", "colors", "typography", "geometry",
    "skins", "coverage", "hud", "profiles", "advanced" }
local RAIL_WIDTH = 174
local SEARCH_ROWS = 6

local function ShowEmbeddedPage(host, key)
    local definition = O.GetPageDefinition(key)
    if not definition then return false end
    if O.GetPageMeta(key).simple == false and O.GetMode() ~= "expert" then O.SetMode("expert") end
    if host.key and host.pages[host.key] then host.pages[host.key]:Hide() end
    local page = host.pages[key]
    if not page then
        page = CreateFrame("Frame", nil, host.content)
        page:SetAllPoints(host.content)
        host.pages[key] = page
        O.BuildPage(page, host, definition.builder)
    end
    host.key = key
    O.ui.lastPage = key
    page:Show()
    for name, button in pairs(host.buttons) do O.SetButtonActive(button, name == key) end
    O.RefreshAll()
    return true
end

-- Mode switch plus one navigation button per page.
local function BuildRail(host)
    local rail = O.CreatePanel(host, "navigation")
    rail:SetPoint("TOPLEFT", 0, 0)
    rail:SetPoint("BOTTOMLEFT", 0, 0)
    rail:SetWidth(RAIL_WIDTH)
    host.rail = rail
    local title = O.CreateText(rail, L["SKINNING"], 12, "accent")
    title:SetPoint("TOPLEFT", 12, -12)

    local guided = O.CreateButton(rail, L["Guided"], 70, 24, function() O.SetMode("guided") end)
    guided:SetPoint("TOPLEFT", 12, -38)
    local expert = O.CreateButton(rail, L["Expert"], 70, 24, function() O.SetMode("expert") end)
    expert:SetPoint("LEFT", guided, "RIGHT", 8, 0)
    O.TrackRefresh(function()
        O.SetButtonActive(guided, O.GetMode() == "guided")
        O.SetButtonActive(expert, O.GetMode() == "expert")
    end)

    for index, key in ipairs(PAGE_KEYS) do
        local definition = O.GetPageDefinition(key)
        if definition then
            local button = O.CreateButton(rail, definition.label, 150, 27,
                function() host:ShowPage(key) end, "navigation")
            button:SetPoint("TOPLEFT", 12, -73 - (index - 1) * 31)
            O.AlignButtonLabel(button)
            host.buttons[key] = button
        end
    end
end

local function SearchRowClick(row)
    local host = O.embeddedHost
    local match = row.searchResult
    if not (host and match) then return end
    if match.expert then O.SetMode("expert") end
    host:ShowPage(match.page)
    host.search:SetText("")
    host.search:ClearFocus()
    host.searchPopup:Hide()
end

local function SearchChanged(host, query)
    query = tostring(query or "")
    local matches = O.SearchSettings(query, SEARCH_ROWS)
    for index, row in ipairs(host.searchRows) do
        local match = matches[index]
        row.searchResult = match
        row:SetShown(match ~= nil)
        if match then
            row.caption:SetText(match.label .. "  |  " .. match.pageLabel)
        end
    end
    host.searchPopup:SetShown(query:match("%S") ~= nil and #matches > 0)
end

local function BuildSearch(host)
    local search = O.CreateSearchBox(host, L["Search skinning settings..."], function(query)
        SearchChanged(host, query)
    end, 310)
    search:SetPoint("TOPLEFT", host.rail, "TOPRIGHT", 10, -8)
    host.search = search

    local popup = O.CreatePanel(host, "popup")
    popup:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -4)
    popup:SetSize(420, 196)
    popup:SetFrameLevel((host.GetFrameLevel and host:GetFrameLevel() or 0) + 25)
    popup:Hide()
    host.searchPopup = popup

    host.searchRows = {}
    for index = 1, SEARCH_ROWS do
        local row = O.CreateButton(popup, "", 396, 27, SearchRowClick, "navigation")
        row:SetPoint("TOPLEFT", 12, -8 - (index - 1) * 30)
        row.caption = O.AlignButtonLabel(row)
        row:Hide()
        host.searchRows[index] = row
    end
end

local function CreateHost(parent)
    local host = CreateFrame("Frame", nil, parent)
    host.pages, host.buttons = {}, {}
    host.ShowPage = ShowEmbeddedPage
    O.embeddedHost = host
    BuildRail(host)
    BuildSearch(host)
    host.content = CreateFrame("Frame", nil, host)
    host.content:SetPoint("TOPLEFT", host.rail, "TOPRIGHT", 10, -46)
    if host.content.SetClipsChildren then host.content:SetClipsChildren(true) end
    host:SetScript("OnHide", function(self)
        self.searchPopup:Hide()
        O.CloseDropdown()
    end)
    return host
end

function O.Mount(parent, width, height)
    if NS.IsCombatLocked() then return nil end
    local host = O.embeddedHost or CreateHost(parent)
    host:SetParent(parent)
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", 0, 0)
    host:SetSize(width, height)
    -- Pages are laid out for 820 px; narrower hosts scale the content down.
    local contentWidth = width - RAIL_WIDTH - 10
    local scale = math.min(1, math.max(0.55, contentWidth / 820))
    host.content:SetScale(scale)
    host.content:SetSize(contentWidth / scale, (height - 54) / scale)
    host:ShowPage(host.key or O.ui.lastPage or "dashboard")
    host:Show()
    return host
end
