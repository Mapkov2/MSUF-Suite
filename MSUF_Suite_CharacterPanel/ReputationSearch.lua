local _, NS = ...
local Search = {}
NS.ReputationSearch = Search
local WIDTH, HEIGHT, INSET = 240, 24, 6
local function Clamp(value) return math.max(0, math.min(1, value)) end

local function Limits(view)
    local w, h = NS.Number(view.frame:GetWidth()), NS.Number(view.frame:GetHeight())
    if w and h then return math.max(1, w - WIDTH - 2 * INSET), math.max(1, h - HEIGHT - 2 * INSET) end
end

local function PositionPrefs(control, save)
    local profile = NS.Suite.ModuleState("characterPanel")
    local tab = control.bound and control.bound.tab
    if not profile or not tab then return profile end
    local positions = profile.tabSearchPositions
    if type(positions) ~= "table" then
        if not save then return end
        positions = {}
        profile.tabSearchPositions = positions
    end
    if save and type(positions[tab]) ~= "table" then
        local config = NS.Suite.Config("characterPanel")
        for id in pairs(positions) do
            if type(id) == "string" and id:match("^custom") and not NS.Host.CharacterTabs.Find(config, id) then positions[id] = nil end
        end
        positions[tab] = {}
    end
    if type(positions[tab]) == "table" then return positions[tab] end
end

local function Place(control)
    local view, prefs = control.view, PositionPrefs(control)
    local w, h = Limits(view)
    if not w then return end
    local x = prefs and NS.Number(prefs.reputationSearchX)
    local y = prefs and NS.Number(prefs.reputationSearchY)
    control:ClearAllPoints()
    control:SetPoint("BOTTOMLEFT", view.frame, "BOTTOMLEFT", INSET + (x and Clamp(x) * w or math.max(0, w - 24)),
        INSET + (y and Clamp(y) * h or 0))
end

local function Drop(control, save)
    if not control.dragging then return end
    control.dragging = nil
    control:StopMovingOrSizing()
    local view = control.view
    local w, h = Limits(view)
    if save and w and not NS.Host.InCombat() then
        local x, y = NS.Number(control:GetLeft()), NS.Number(control:GetBottom())
        local left, bottom = NS.Number(view.frame:GetLeft()), NS.Number(view.frame:GetBottom())
        local scale, parentScale = NS.Number(control:GetEffectiveScale()), NS.Number(view.frame:GetEffectiveScale())
        local prefs = PositionPrefs(control, true)
        if prefs and x and y and left and bottom and scale and parentScale and parentScale > 0 then
            prefs.reputationSearchX = Clamp((x * scale / parentScale - left - INSET) / w)
            prefs.reputationSearchY = Clamp((y * scale / parentScale - bottom - INSET) / h)
        end
    end
    Place(control)
end

local function Repaint(control, reset)
    local state = control.state
    if not state or NS.Host.InCombat() then return end
    if state.rail then control.view:ShowRailGroups(state.groups, reset, false)
    else control.view:ShowGroups(state.groups, false, state, reset) end
end

local function Grip(view, control, style)
    local grip = NS.Window.CreateChild(view, "Button", control)
    grip:SetSize(20, HEIGHT)
    grip:SetPoint("LEFT")
    for i = 0, 5 do
        local dot = style.Texture(grip, nil, "ARTWORK")
        dot:SetSize(2, 2)
        dot:SetPoint("TOPLEFT", 7 + i % 2 * 4, -6 - math.floor(i / 2) * 4)
        style.Tint(view, dot, style.muted)
    end
    grip:RegisterForDrag("LeftButton")
    grip:RegisterForClicks("RightButtonUp")
    grip:SetScript("OnDragStart", function()
        if control.state and not NS.Host.InCombat() then
            control.dragging = true
            control:StartMoving()
        end
    end)
    grip:SetScript("OnDragStop", function() Drop(control, true) end)
    grip:SetScript("OnClick", function()
        if NS.Host.InCombat() then return end
        local prefs = PositionPrefs(control)
        if prefs then prefs.reputationSearchX, prefs.reputationSearchY = nil, nil end
        Place(control)
    end)
    grip:SetScript("OnEnter", function()
        GameTooltip:SetOwner(grip, "ANCHOR_TOP")
        GameTooltip:SetText(NS.Text("Drag to move"))
        GameTooltip:AddLine(GetBindingText("BUTTON2") .. " - " .. NS.Text("Reset position"))
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() if GameTooltip:IsOwned(grip) then GameTooltip:Hide() end end)
end

local function Create(view, style)
    local control = style.Panel(view, view.footer)
    control.view = view
    control:SetSize(WIDTH, HEIGHT)
    control:SetMovable(true)
    control:SetClampedToScreen(true)
    control:SetFrameLevel(view.report.scroll:GetFrameLevel() + (view.embedded and 32 or 12))
    Grip(view, control, style)
    local edit = NS.Window.CreateChild(view, "EditBox", control)
    edit:SetPoint("TOPLEFT", 22, -1)
    edit:SetPoint("BOTTOMRIGHT", -83, 1)
    edit:SetAutoFocus(false)
    if view.embedded then edit:EnableMouse(false) end
    edit:SetMaxLetters(80)
    edit:SetFontObject("GameFontHighlightSmall")
    local hint = style.Font(view, edit, 12, style.muted)
    hint:SetPoint("LEFT")
    hint:SetText(NS.Text("Search"))
    local count = style.Font(view, control, 11, style.muted, "RIGHT")
    count:SetPoint("RIGHT", -24, 0)
    local clear = style.Button(view, control, "×", function()
        if not control.state or NS.Host.InCombat() then return end
        edit:SetText("")
        edit:SetFocus()
    end)
    clear:SetSize(22, HEIGHT - 2)
    clear:SetPoint("RIGHT", -1, 0)
    clear:SetScript("OnEnter", function()
        GameTooltip:SetOwner(clear, "ANCHOR_TOP")
        GameTooltip:SetText(NS.Text("Clear search"))
        GameTooltip:Show()
    end)
    clear:SetScript("OnLeave", function() if GameTooltip:IsOwned(clear) then GameTooltip:Hide() end end)
    clear:Hide()
    control.edit, control.hint, control.clear, control.count = edit, hint, clear, count
    edit:SetScript("OnTextChanged", function()
        if not control.state or NS.Host.InCombat() then return end
        local value = edit:GetText()
        if not NS.Public(value) or type(value) ~= "string" then return end
        hint:SetShown(value == "")
        clear:SetShown(value ~= "")
        local query = NS.ReputationList.Query(value)
        if query == control.state.query then return end
        control.state.query = query
        Repaint(control, true)
    end)
    edit:SetScript("OnEscapePressed", function()
        edit:SetText("")
        edit:ClearFocus()
    end)
    edit:SetScript("OnEnterPressed", function() edit:ClearFocus() end)
    control:SetScript("OnHide", function()
        edit:ClearFocus()
        Drop(control, false)
    end)
    return control
end

function Search.Hide(view)
    local control = view and view.reputationSearch
    if control then
        control.state = nil
        control:Hide()
    end
end

-- Custom rows can carry secret values (even outside lockdown). Search only
-- readable text or numbers, and keep each matching row's original action and layout.
local function Contains(value, query)
    if not NS.Public(value) then return false end
    if type(value) == "number" then value = tostring(value) end
    return type(value) == "string" and (strlower or string.lower)(value):find(query, 1, true) ~= nil
end

local function ProjectReport(state)
    local query, groups = state.query, state.groups
    local filtered = query ~= "" and {} or groups
    local matches, total = 0, 0
    for _, group in ipairs(groups) do
        total = total + #group.rows
        if query ~= "" then
            if Contains(group.title, query) then
                filtered[#filtered + 1] = group
                matches = matches + #group.rows
            else
                local rows = {}
                for _, row in ipairs(group.rows) do
                    if Contains(row.label, query) or Contains(row.value, query) then rows[#rows + 1] = row end
                end
                if #rows > 0 then
                    filtered[#filtered + 1] = { title = group.title, rows = rows, action = group.action,
                        layout = group.layout, depth = group.depth, collapsed = group.collapsed }
                    matches = matches + #rows
                end
            end
        end
    end
    if query ~= "" and #filtered == 0 then filtered[1] = { title = NS.Text("No results"), rows = {} } end
    return filtered, matches, total
end

function Search.Show(view, state, style)
    state.query = state.query or ""
    local control = view.reputationSearch
    if not control then
        control = Create(view, style)
        view.reputationSearch = control
    end
    if control.state ~= state then
        if control.bound ~= state or state.query == "" then
            control.state = nil
            control.edit:SetText(state.query or "")
            control.hint:SetShown(not state.query or state.query == "")
            control.clear:SetShown(state.query ~= nil and state.query ~= "")
            control.bound = state
        end
        control.state = state
        Place(control)
    end
    control:Show()
    local project = state.tab and ProjectReport or NS.ReputationList.Project
    local groups, matches, total = project(state, state.groups)
    control.count:SetText(state.query ~= "" and (matches .. " / " .. total) or tostring(total))
    return groups
end
