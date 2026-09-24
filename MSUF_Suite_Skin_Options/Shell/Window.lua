local _, Private = ...
local NS, O = Private.NS, Private.Options

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

    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(NS.Theme.GetColor("ink"))

    local thumb = bar:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(8, 48)
    thumb:SetTexture(NS.path .. "Media\\Shapes\\pill_h24_fill.png")
    if thumb.SetTextureSliceMargins then
        thumb:SetTextureSliceMargins(12, 0, 12, 0)
    end
    thumb:SetVertexColor(NS.Theme.GetColor("accent"))
    bar:SetThumbTexture(thumb)

    local syncing = false
    local function UpdateRange(_, _, verticalRange)
        local range = math.max(0, tonumber(verticalRange) or 0)
        bar:SetMinMaxValues(0, range)
        bar:SetShown(range > 0)
    end
    scroll:SetScript("OnScrollRangeChanged", UpdateRange)
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

local function CreateWindow()
    local layout = O.Layout
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
    window:SetScript("OnHide", function()
        if O.CloseDropdown then O.CloseDropdown() end
    end)
    window:Hide()

    local topAccent = window:CreateTexture(nil, "OVERLAY")
    topAccent:SetPoint("TOPLEFT", 12, -2)
    topAccent:SetPoint("TOPRIGHT", -12, -2)
    topAccent:SetHeight(2)
    topAccent:SetColorTexture(NS.Theme.GetColor("accent"))

    local headerTitle = O.CreateText(window, "MAPKOSKIN", 14, "title")
    headerTitle:SetPoint("TOPLEFT", 18, -18)
    local headerSubtitle = O.CreateText(window, "Independent UI skinning engine", 11, "muted")
    headerSubtitle:SetPoint("LEFT", headerTitle, "RIGHT", 12, 0)

    local status = O.CreateText(window, "OUT OF COMBAT ONLY", 9, "success", "RIGHT")
    status:SetPoint("TOPRIGHT", -242, -20)

    local close = O.CreateWindowActionButton(window, "close", 30, 28,
        function() window:Hide() end)
    close:SetPoint("TOPRIGHT", -14, -12)

    local expertMode = O.CreateButton(window, "Expert", 82, 28, function()
        O.SetMode("expert")
    end, "navigation")
    expertMode:SetPoint("TOPRIGHT", close, "TOPLEFT", -6, 0)

    local guidedMode = O.CreateButton(window, "Guided", 82, 28, function()
        O.SetMode("guided")
    end, "navigation")
    guidedMode:SetPoint("RIGHT", expertMode, "LEFT", -6, 0)

    local rail = O.CreatePanel(window, "navigation")
    rail:SetPoint("TOPLEFT", 10, -layout.header)
    rail:SetPoint("BOTTOMLEFT", 10, 10)
    rail:SetWidth(layout.rail)

    local brand = O.CreateText(rail, "M  MAPKO", 13, "accent")
    brand:SetPoint("TOPLEFT", 15, -16)
    local brandSub = O.CreateText(rail, "SKIN ENGINE", 9, "dim")
    brandSub:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 20, -4)

    local content = O.CreatePanel(window, "panel")
    content:SetPoint("TOPLEFT", rail, "TOPRIGHT", 10, 0)
    content:SetPoint("BOTTOMRIGHT", -10, 10)

    local pageTitle = O.CreateText(content, "", 12, "accent")
    pageTitle:SetPoint("TOPLEFT", 16, -10)
    local pageContext = O.CreateText(content, "", 9, "dim")
    pageContext:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -3)

    local SearchChanged
    local searchInput = O.CreateSearchBox(content, "Search every setting...", function(query)
        if SearchChanged then SearchChanged(query) end
    end, 310)
    searchInput:SetPoint("TOPRIGHT", -12, -9)

    local divider = content:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 12, -45)
    divider:SetPoint("TOPRIGHT", -12, -45)
    divider:SetHeight(1)
    divider:SetColorTexture(NS.Theme.GetColor("borderSoft"))

    local pageHost = CreateFrame("Frame", nil, content)
    pageHost:SetPoint("TOPLEFT", 16, -59)
    pageHost:SetPoint("BOTTOMRIGHT", -16, 16)
    if pageHost.SetClipsChildren then pageHost:SetClipsChildren(true) end

    local searchPopup = O.CreatePanel(content, "popup")
    searchPopup:SetPoint("TOPRIGHT", searchInput, "BOTTOMRIGHT", 0, -5)
    searchPopup:SetSize(420, 254)
    searchPopup:SetFrameLevel(100)
    searchPopup:Hide()

    local searchEmpty = O.CreateText(searchPopup, "No matching setting", 11, "muted", "CENTER")
    searchEmpty:SetPoint("TOPLEFT", 12, -16)
    searchEmpty:SetPoint("TOPRIGHT", -12, -16)
    searchEmpty:Hide()

    local searchRows = {}
    for index = 1, 8 do
        local row = O.CreateButton(searchPopup, "", 396, 26, nil, "navigation")
        row:SetPoint("TOPLEFT", 12, -12 - (index - 1) * 29)
        local widgetState = O.widgetStates[row]
        if widgetState and widgetState.label then widgetState.label:SetJustifyH("LEFT") end
        row:Hide()
        searchRows[index] = row
    end

    local state = {
        window = window,
        rail = rail,
        content = content,
        pageHost = pageHost,
        pageTitle = pageTitle,
        pageContext = pageContext,
        navButtons = {},
        navSections = {},
        pageFrames = {},
        activePage = nil,
    }

    local function ShowPage(key, focusLabel)
        local definition = pageDefinitions[key]
        if not definition then return end
        local meta = O.GetPageMeta(key)
        if meta.simple == false and O.GetMode() ~= "expert" then
            O.SetMode("expert")
        end
        if O.CloseDropdown then O.CloseDropdown() end
        searchPopup:Hide()
        if state.activePage and state.pageFrames[state.activePage] then
            state.pageFrames[state.activePage]:Hide()
            O.SetButtonActive(state.navButtons[state.activePage], false)
        end
        local page = state.pageFrames[key]
        if not page then
            page = CreateFrame("Frame", nil, pageHost)
            page:SetAllPoints()
            state.pageFrames[key] = page
            definition.builder(page)
        end
        page:Show()
        state.activePage = key
        O.ui.lastPage = key
        pageTitle:SetText(string.upper(definition.label))
        pageContext:SetText(focusLabel and ("FOUND: " .. string.upper(focusLabel)) or "")
        O.SetButtonActive(state.navButtons[key], true)
        O.RefreshAll()
    end
    state.showPage = ShowPage

    local groupLabels = {
        start = "START",
        design = "DESIGN",
        coverage = "BLIZZARD UI",
        manage = "MANAGE",
    }
    local groupOrder = { "start", "design", "coverage", "manage" }
    for index = 1, #groupOrder do
        local group = groupOrder[index]
        local heading = O.CreateText(rail, groupLabels[group], 9, "dim")
        heading:Hide()
        state.navSections[group] = heading
    end

    for index = 1, #pageOrder do
        local key = pageOrder[index]
        local definition = pageDefinitions[key]
        local nav = O.CreateButton(rail, definition.label, layout.rail - 20, 32, function()
            ShowPage(key)
        end, "navigation")
        local widgetState = O.widgetStates[nav]
        if widgetState and widgetState.label then
            widgetState.label:SetJustifyH("LEFT")
        end
        state.navButtons[key] = nav
    end

    local function RefreshNavigation()
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
            ShowPage("dashboard")
        end
    end
    state.refreshNavigation = RefreshNavigation
    O.TrackMode(RefreshNavigation)
    RefreshNavigation()

    SearchChanged = function(query)
        query = tostring(query or "")
        local results = O.SearchSettings(query, #searchRows)
        searchEmpty:SetShown(query ~= "" and #results == 0)
        for index = 1, #searchRows do
            local row = searchRows[index]
            local result = results[index]
            if result then
                row.searchResult = result
                local widgetState = O.widgetStates[row]
                if widgetState and widgetState.label then
                    widgetState.label:SetText(result.label .. "   |   " .. result.pageLabel
                        .. (result.expert and "   [Expert]" or ""))
                end
                row:SetScript("OnClick", function(button)
                    local selected = button.searchResult
                    if not selected then return end
                    if selected.expert then O.SetMode("expert") end
                    searchInput:SetText("")
                    searchInput:ClearFocus()
                    ShowPage(selected.page, selected.label)
                end)
                row:Show()
            else
                row.searchResult = nil
                row:Hide()
            end
        end
        searchPopup:SetShown(query:match("%S") ~= nil)
    end

    local footer = O.CreateText(rail, "v" .. NS.version .. "  |  API " .. tostring(NS.apiVersion), 9, "dim")
    footer:SetPoint("BOTTOMLEFT", 14, 12)

    local undo = O.CreateButton(rail, "Undo", 88, 26, function() O.Undo() end)
    undo:SetPoint("BOTTOMLEFT", 10, 34)
    local redo = O.CreateButton(rail, "Redo", 88, 26, function() O.Redo() end)
    redo:SetPoint("LEFT", undo, "RIGHT", 8, 0)

    local profileStatus = O.CreateText(rail, "", 9, "muted")
    profileStatus:SetPoint("BOTTOMLEFT", undo, "TOPLEFT", 4, 8)
    profileStatus:SetPoint("RIGHT", -12, 0)

    O.TrackRefresh(function()
        topAccent:SetColorTexture(NS.Theme.GetColor("accent"))
        divider:SetColorTexture(NS.Theme.GetColor("borderSoft"))
        O.SetTextColor(headerTitle, "title")
        O.SetTextColor(headerSubtitle, "muted")
        O.SetTextColor(status, "success")
        O.SetButtonActive(guidedMode, O.GetMode() == "guided")
        O.SetButtonActive(expertMode, O.GetMode() == "expert")
        local undoLabel, redoLabel = O.GetHistoryState()
        O.SetButtonEnabled(undo, undoLabel ~= nil)
        O.SetButtonEnabled(redo, redoLabel ~= nil)
        local lookKey = NS.DB and NS.DB.theme and NS.DB.theme.look or "custom"
        local look = NS.LookPresets[lookKey]
        local lookLabel = look and look.label or "Custom"
        profileStatus:SetText(("Profile: %s\nStyle: %s"):format(NS.Database.GetActiveProfileName(), lookLabel))
    end)

    if UISpecialFrames then
        UISpecialFrames[#UISpecialFrames + 1] = "MapkoSkinOptionsFrame"
    end
    O.windowState = state
    return state
end

function O.BuildWindow()
    return O.windowState or CreateWindow()
end

function O.ShowPage(key, focusLabel)
    if O.embeddedHost and O.embeddedHost:IsShown() then
        O.embeddedHost:ShowPage(key)
        return
    end
    local state = O.BuildWindow()
    state.showPage(key, focusLabel)
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
