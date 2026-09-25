local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

local pageDefinitions = {}
local pageOrder = {}

function O.RegisterPage(key, label, builder)
    if pageDefinitions[key] or type(builder) ~= "function" then
        return false
    end
    pageDefinitions[key] = { key = key, label = label, builder = builder }
    pageOrder[#pageOrder + 1] = key
    return true
end

function O.GetPageDefinition(key)
    return pageDefinitions[key]
end

------------------------------------------------------------------ scroll container
function O.CreateScrollContainer(parent, contentHeight, contentWidth)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -16, 0)
    scroll:EnableMouseWheel(true)
    if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(contentWidth or 790)
    child:SetHeight(contentHeight or 800)
    scroll:SetScrollChild(child)

    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetPoint("TOPRIGHT", -2, -4)
    bar:SetPoint("BOTTOMRIGHT", -2, 4)
    bar:SetWidth(8)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local track, thumb = O.CreateScrollThumb(bar, 48)

    local syncing = false
    scroll:SetScript("OnScrollRangeChanged", function(_, _, verticalRange)
        local range = math.max(0, tonumber(verticalRange) or 0)
        bar:SetMinMaxValues(0, range)
        bar:SetShown(range > 0)
    end)
    scroll:SetScript("OnVerticalScroll", function(_, offset)
        if syncing then return end
        syncing = true
        bar:SetValue(offset)
        syncing = false
    end)
    bar:SetScript("OnValueChanged", function(_, value)
        if syncing then return end
        syncing = true
        scroll:SetVerticalScroll(value)
        syncing = false
    end)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local nextValue = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 42))
        self:SetVerticalScroll(nextValue)
    end)

    O.TrackRefresh(function()
        track:SetColorTexture(NS.Theme.GetColor("ink"))
        thumb:SetVertexColor(NS.Theme.GetColor("accent"))
    end)
    return scroll, child
end

------------------------------------------------------------------ standalone window
local GROUP_ORDER = { "start", "design", "coverage", "manage" }
local GROUP_LABELS = {
    start = L["START"],
    design = L["DESIGN"],
    coverage = L["BLIZZARD UI"],
    manage = L["MANAGE"],
}

local function BuildFrame(layout)
    local window = CreateFrame("Frame", "MapkoSkinOptionsFrame", UIParent)
    window:SetSize(layout.width, layout.height)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    NS.Surface.Attach(window, { role = "shell", radius = 12 })

    window:SetScript("OnDragStart", function(self)
        if not NS.IsCombatLocked() then self:StartMoving() end
    end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    window:SetScript("OnShow", function() O.RefreshAll() end)
    window:SetScript("OnHide", function() O.CloseDropdown() end)
    window:Hide()
    return window
end

-- Accent line, brand title, combat notice, close and mode buttons.
local function BuildHeader(state)
    local window = state.window
    local topAccent = window:CreateTexture(nil, "OVERLAY")
    topAccent:SetPoint("TOPLEFT", 12, -2)
    topAccent:SetPoint("TOPRIGHT", -12, -2)
    topAccent:SetHeight(2)
    topAccent:SetColorTexture(NS.Theme.GetColor("accent"))
    state.topAccent = topAccent

    state.headerTitle = O.CreateText(window, "MAPKOSKIN", 14, "title")
    state.headerTitle:SetPoint("TOPLEFT", 18, -18)
    state.headerSubtitle = O.CreateText(window, L["Independent UI skinning engine"], 11, "muted")
    state.headerSubtitle:SetPoint("LEFT", state.headerTitle, "RIGHT", 12, 0)
    state.status = O.CreateText(window, L["OUT OF COMBAT ONLY"], 9, "success", "RIGHT")
    state.status:SetPoint("TOPRIGHT", -242, -20)

    local close = O.CreateWindowActionButton(window, "close", 30, 28, function() window:Hide() end)
    close:SetPoint("TOPRIGHT", -14, -12)
    state.expertMode = O.CreateButton(window, L["Expert"], 82, 28, function()
        O.SetMode("expert")
    end, "navigation")
    state.expertMode:SetPoint("TOPRIGHT", close, "TOPLEFT", -6, 0)
    state.guidedMode = O.CreateButton(window, L["Guided"], 82, 28, function()
        O.SetMode("guided")
    end, "navigation")
    state.guidedMode:SetPoint("RIGHT", state.expertMode, "LEFT", -6, 0)
end

-- Left rail: brand, grouped page navigation, profile status, undo and redo.
local function BuildRail(state, layout)
    local rail = O.CreatePanel(state.window, "navigation")
    rail:SetPoint("TOPLEFT", 10, -layout.header)
    rail:SetPoint("BOTTOMLEFT", 10, 10)
    rail:SetWidth(layout.rail)
    state.rail = rail

    local brand = O.CreateText(rail, "M  MAPKO", 13, "accent")
    brand:SetPoint("TOPLEFT", 15, -16)
    local brandSub = O.CreateText(rail, L["SKIN ENGINE"], 9, "dim")
    brandSub:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 20, -4)

    for index = 1, #GROUP_ORDER do
        local group = GROUP_ORDER[index]
        local heading = O.CreateText(rail, GROUP_LABELS[group], 9, "dim")
        heading:Hide()
        state.navSections[group] = heading
    end
    for index = 1, #pageOrder do
        local key = pageOrder[index]
        local nav = O.CreateButton(rail, pageDefinitions[key].label, layout.rail - 20, 32, function()
            state.showPage(key)
        end, "navigation")
        O.AlignButtonLabel(nav)
        state.navButtons[key] = nav
    end

    local footer = O.CreateText(rail, ("v%s  |  API %s"):format(NS.version, tostring(NS.apiVersion)), 9, "dim")
    footer:SetPoint("BOTTOMLEFT", 14, 12)
    state.undo = O.CreateButton(rail, L["Undo"], 88, 26, function() O.Undo() end)
    state.undo:SetPoint("BOTTOMLEFT", 10, 34)
    state.redo = O.CreateButton(rail, L["Redo"], 88, 26, function() O.Redo() end)
    state.redo:SetPoint("LEFT", state.undo, "RIGHT", 8, 0)
    state.profileStatus = O.CreateText(rail, "", 9, "muted")
    state.profileStatus:SetPoint("BOTTOMLEFT", state.undo, "TOPLEFT", 4, 8)
    state.profileStatus:SetPoint("RIGHT", -12, 0)
end

-- Content panel: page title and context line, divider and the page host.
local function BuildContent(state)
    local content = O.CreatePanel(state.window, "panel")
    content:SetPoint("TOPLEFT", state.rail, "TOPRIGHT", 10, 0)
    content:SetPoint("BOTTOMRIGHT", -10, 10)
    state.content = content

    state.pageTitle = O.CreateText(content, "", 12, "accent")
    state.pageTitle:SetPoint("TOPLEFT", 16, -10)
    state.pageContext = O.CreateText(content, "", 9, "dim")
    state.pageContext:SetPoint("TOPLEFT", state.pageTitle, "BOTTOMLEFT", 0, -3)

    local divider = content:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 12, -45)
    divider:SetPoint("TOPRIGHT", -12, -45)
    divider:SetHeight(1)
    divider:SetColorTexture(NS.Theme.GetColor("borderSoft"))
    state.divider = divider

    local pageHost = CreateFrame("Frame", nil, content)
    pageHost:SetPoint("TOPLEFT", 16, -59)
    pageHost:SetPoint("BOTTOMRIGHT", -16, 16)
    if pageHost.SetClipsChildren then pageHost:SetClipsChildren(true) end
    state.pageHost = pageHost
end

local SEARCH_ROWS = 8

local function SearchRowClick(row)
    local state = O.windowState
    local selected = row.searchResult
    if not (state and selected) then return end
    if selected.expert then O.SetMode("expert") end
    state.searchInput:SetText("")
    state.searchInput:ClearFocus()
    state.showPage(selected.page, selected.label)
end

local function SearchChanged(state, query)
    query = tostring(query or "")
    local results = O.SearchSettings(query, SEARCH_ROWS)
    state.searchEmpty:SetShown(query ~= "" and #results == 0)
    for index = 1, SEARCH_ROWS do
        local row = state.searchRows[index]
        local result = results[index]
        row.searchResult = result
        if result then
            row.caption:SetText(result.label .. "   |   " .. result.pageLabel
                .. (result.expert and ("   [" .. L["Expert"] .. "]") or ""))
            row:Show()
        else
            row:Hide()
        end
    end
    state.searchPopup:SetShown(query:match("%S") ~= nil)
end

-- Search box and its result popup with pooled result rows.
local function BuildSearch(state)
    local content = state.content
    state.searchInput = O.CreateSearchBox(content, L["Search every setting..."], function(query)
        SearchChanged(state, query)
    end, 310)
    state.searchInput:SetPoint("TOPRIGHT", -12, -9)

    local popup = O.CreatePanel(content, "popup")
    popup:SetPoint("TOPRIGHT", state.searchInput, "BOTTOMRIGHT", 0, -5)
    popup:SetSize(420, 254)
    popup:SetFrameLevel(100)
    popup:Hide()
    state.searchPopup = popup

    state.searchEmpty = O.CreateText(popup, L["No matching setting"], 11, "muted", "CENTER")
    state.searchEmpty:SetPoint("TOPLEFT", 12, -16)
    state.searchEmpty:SetPoint("TOPRIGHT", -12, -16)
    state.searchEmpty:Hide()

    state.searchRows = {}
    for index = 1, SEARCH_ROWS do
        local row = O.CreateButton(popup, "", 396, 26, SearchRowClick, "navigation")
        row:SetPoint("TOPLEFT", 12, -12 - (index - 1) * 29)
        row.caption = O.AlignButtonLabel(row)
        row:Hide()
        state.searchRows[index] = row
    end
end

local function ShowWindowPage(state, key, focusLabel)
    local definition = pageDefinitions[key]
    if not definition then return end
    if O.GetPageMeta(key).simple == false and O.GetMode() ~= "expert" then
        O.SetMode("expert")
    end
    O.CloseDropdown()
    state.searchPopup:Hide()
    local previous = state.activePage
    if previous and state.pageFrames[previous] then
        state.pageFrames[previous]:Hide()
        O.SetButtonActive(state.navButtons[previous], false)
    end
    local page = state.pageFrames[key]
    if not page then
        page = CreateFrame("Frame", nil, state.pageHost)
        page:SetAllPoints()
        state.pageFrames[key] = page
        O.BuildPage(page, state.window, definition.builder)
    end
    page:Show()
    state.activePage = key
    O.ui.lastPage = key
    state.pageTitle:SetText(string.upper(definition.label))
    state.pageContext:SetText(focusLabel and L["FOUND: %s"]:format(string.upper(focusLabel)) or "")
    O.SetButtonActive(state.navButtons[key], true)
    O.RefreshAll()
end

-- Guided mode hides the expert-only pages; group headings follow the pages.
local function RefreshNavigation(state)
    for _, heading in pairs(state.navSections) do heading:Hide() end
    for _, button in pairs(state.navButtons) do button:Hide() end

    local mode = O.GetMode()
    local y = -68
    local activeGroup
    for index = 1, #pageOrder do
        local key = pageOrder[index]
        local meta = O.GetPageMeta(key)
        if mode == "expert" or meta.simple ~= false then
            if activeGroup ~= meta.group then
                activeGroup = meta.group
                local heading = state.navSections[activeGroup]
                heading:ClearAllPoints()
                heading:SetPoint("TOPLEFT", 14, y)
                heading:Show()
                y = y - 18
            end
            local nav = state.navButtons[key]
            nav:ClearAllPoints()
            nav:SetPoint("TOPLEFT", 10, y)
            nav:Show()
            y = y - 36
        end
    end

    local activeMeta = state.activePage and O.GetPageMeta(state.activePage)
    if mode == "guided" and activeMeta and activeMeta.simple == false then
        state.showPage("dashboard")
    end
end

local function RefreshChrome(state)
    state.topAccent:SetColorTexture(NS.Theme.GetColor("accent"))
    state.divider:SetColorTexture(NS.Theme.GetColor("borderSoft"))
    O.SetTextColor(state.headerTitle, "title")
    O.SetTextColor(state.headerSubtitle, "muted")
    O.SetTextColor(state.status, "success")
    O.SetButtonActive(state.guidedMode, O.GetMode() == "guided")
    O.SetButtonActive(state.expertMode, O.GetMode() == "expert")
    local undoLabel, redoLabel = O.GetHistoryState()
    O.SetButtonEnabled(state.undo, undoLabel ~= nil)
    O.SetButtonEnabled(state.redo, redoLabel ~= nil)
    local lookKey = NS.DB and NS.DB.theme and NS.DB.theme.look or "custom"
    local look = NS.LookPresets[lookKey]
    local lookLabel = look and look.label or L["Custom"]
    state.profileStatus:SetText(L["Profile: %s\nStyle: %s"]:format(NS.Database.GetActiveProfileName(), lookLabel))
end

local function CreateWindow()
    local layout = O.Layout
    local state = {
        window = BuildFrame(layout),
        navButtons = {},
        navSections = {},
        pageFrames = {},
        activePage = nil,
    }
    state.showPage = function(key, focusLabel) ShowWindowPage(state, key, focusLabel) end
    O.windowState = state

    BuildHeader(state)
    BuildRail(state, layout)
    BuildContent(state)
    BuildSearch(state)

    local function RefreshMode() RefreshNavigation(state) end
    O.TrackMode(RefreshMode)
    RefreshMode()
    O.TrackRefresh(function() RefreshChrome(state) end)

    if UISpecialFrames then
        UISpecialFrames[#UISpecialFrames + 1] = "MapkoSkinOptionsFrame"
    end
    return state
end

function O.BuildWindow()
    return O.windowState or CreateWindow()
end

function O.ShowPage(key, focusLabel)
    local host = O.embeddedHost
    if host and host:IsShown() then
        return host:ShowPage(key)
    end
    O.BuildWindow().showPage(key, focusLabel)
end

function O.Open()
    if NS.IsCombatLocked() then
        NS.Print(NS.L.OPEN_BLOCKED_COMBAT)
        return false
    end
    local state = O.BuildWindow()
    state.window:Show()
    state.showPage(state.activePage or O.ui.lastPage or pageOrder[1])
    return true
end
