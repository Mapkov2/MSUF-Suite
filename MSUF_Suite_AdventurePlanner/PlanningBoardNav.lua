local _, P = ...
local NS, S, B = P.NS, P.Suite, P.PlanningTools.Board
local Bridge = NS.HostBridge
-- The rail as Menu2 builds its own: group titles that fold their pages, and
-- 24 px navigation pills on a 28 px step with an icon from MSUF's HD atlas.
-- Without Menu2 the same layout paints from the theme colors.
B.NAV_GROUPS = { { key = "week", label = "This week" }, { key = "history", label = "History" },
    { key = "tools", label = "Tools" } }
local ICONS = { characters = { 1, 2 }, preparation = { 6, 1 }, goals = { 3, 0 }, runs = { 1, 1 }, raid = { 6, 2 },
    loadouts = { 4, 2 }, lfg = { 5, 3 }, notes = { 1, 4 } }
local ITEM_WIDTH, ITEM_HEIGHT, ITEM_STEP, TITLE_HEIGHT = 184, 24, 28, 18
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

function B.StyleNav(button)
    local window = button.window
    local entry = window.spec and window.spec.tabs[button.index]
    local active = entry ~= nil and entry.key == window.spec.currentTab(window.owner)
    if button.plannerNativeButton then return button:SetActive(active) end
    B.Tint(button.fill, active and "pillActive" or "pillHover", (active or button.hover) and 1 or 0)
    button.stripe:SetShown(active)
    B.TintLabel(button.text, active and "title" or button.hover and "text" or "muted")
end

local function Hover(button, hover)
    button.hover = hover
    if button.window.spec then B.StyleNav(button) end
end

local function FallbackButton(window)
    local button = S.CreateFrame("Button", nil, window.rail)
    button:SetSize(ITEM_WIDTH, ITEM_HEIGHT)
    button.fill = B.Fill(button, "pillHover", 0, "pillBase")
    button.stripe = B.Texture(button, "ARTWORK", "accent", 1)
    button.stripe:SetPoint("TOPLEFT", 0, -4)
    button.stripe:SetPoint("BOTTOMLEFT", 0, 4)
    button.stripe:SetWidth(3)
    button.text = B.Label(button, "", 13, "muted")
    button.text:SetPoint("LEFT", 12, 0)
    button.text:SetPoint("RIGHT", -8, 0)
    button:SetScript("OnEnter", function(self) Hover(self, true) end)
    button:SetScript("OnLeave", function(self) Hover(self, false) end)
    return button
end

local function NavButton(window, index)
    local button = Bridge.MenuNavButton(window.rail, ITEM_WIDTH, ITEM_HEIGHT)
    if button then
        button.plannerNativeButton = true
        button.text = B.TrackFont(Bridge.MenuButtonLabel(button), 13, false)
    else
        button = FallbackButton(window)
    end
    button.text:SetHeight(ITEM_HEIGHT - 4)
    button.text:SetJustifyV("MIDDLE")
    button.text:SetWordWrap(false)
    button.index, button.window = index, window
    button:SetScript("OnClick", B.TabClicked)
    return button
end

local function PaintTitle(row)
    local open = not row.window.navCollapsed[row.group]
    if not Bridge.MenuArrow(row.arrow, open, "nav") then
        row.arrow:SetTexture(ARROW)
        row.arrow:SetRotation(open and math.pi * .5 or 0)
        local c = B.Color("muted", "text")
        row.arrow:SetVertexColor(c[1], c[2], c[3], .8)
    end
    B.TintLabel(row.text, row.hover and "navHeaderHover" or Bridge.MenuColor("navHeaderText") and "navHeaderText" or "muted")
end

local function GatherNav(window, key)
    local caption = nil
    local count = 0
    for _, row in ipairs(window.captions) do if row.group == key then caption = row end end
    for _, tab in ipairs(window.spec.tabs) do if tab.group == key then count = count + 1 end end
    if not caption then return end
    local top = caption.plannerNavY - TITLE_HEIGHT - 6
    for _, row in ipairs(window.captions) do
        if row:IsShown() and row.plannerNavY < top then B.AddFoldRegion(window, row, count * ITEM_STEP, false) end
    end
    for i, button in ipairs(window.tabs) do
        local entry = window.spec.tabs[i]
        if entry and button:IsShown() and button.plannerNavY <= top then
            local child = entry.group == key
            B.AddFoldRegion(window, button, child and top - button.plannerNavY or count * ITEM_STEP, child)
        end
    end
end

local function TitleClicked(row)
    local window = row.window
    if not B.Valid(window) then return end
    B.FinishAccordion(window, true)
    window.navCollapsed[row.group] = not window.navCollapsed[row.group] or nil
    B.PlayAccordion(window, not window.navCollapsed[row.group], B.LayoutNav, GatherNav, row.group)
end

local function TitleRow(window, group)
    local row = S.CreateFrame("Button", nil, window.rail)
    row:SetSize(ITEM_WIDTH - 2, TITLE_HEIGHT)
    row.text = B.Label(row, "", 12, "muted")
    row.text:SetPoint("LEFT", 0, 0)
    row.text:SetSize(ITEM_WIDTH - 22, TITLE_HEIGHT)
    row.text:SetJustifyV("MIDDLE")
    row.text:SetWordWrap(false)
    row.text:SetText(S.Text(group.label):upper())
    row.arrow = S.CreateTexture(row, nil, "OVERLAY")
    row.arrow:SetSize(10, 10)
    row.arrow:SetPoint("RIGHT", -6, 0)
    row.group, row.window = group.key, window
    row:SetScript("OnClick", TitleClicked)
    row:SetScript("OnEnter", function(self) self.hover = true PaintTitle(self) end)
    row:SetScript("OnLeave", function(self) self.hover = nil PaintTitle(self) end)
    return row
end

function B.CreateNav(window)
    window.rail = B.Panel(window, 16, -44, B.RAIL_WIDTH, B.HOST_HEIGHT, "rail")
    window.tabs, window.captions, window.navCollapsed = {}, {}, {}
    for i = 1, 8 do window.tabs[i] = NavButton(window, i) end
    for i, group in ipairs(B.NAV_GROUPS) do window.captions[i] = TitleRow(window, group) end
end

local function Caption(window, key)
    for _, caption in ipairs(window.captions) do if caption.group == key then return caption end end
end

local function Place(region, y)
    region.plannerNavY = y
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", 8, y)
    region:Show()
end

-- Titles precede the first page of their group; a folded group keeps its
-- title and hides its pages. The spec keeps group order.
function B.LayoutNav(window)
    for _, caption in ipairs(window.captions) do caption:Hide() end
    local y, group = -14
    for i, button in ipairs(window.tabs) do
        local entry = window.spec.tabs[i]
        button:Hide()
        if entry then
            local caption = entry.group ~= group and Caption(window, entry.group)
            if caption then
                if group then y = y - 10 end
                Place(caption, y)
                PaintTitle(caption)
                y = y - TITLE_HEIGHT - 6
            end
            group = entry.group
            button.text:SetText(S.Text(entry.nav or entry.label))
            if ICONS[entry.key] and button.plannerNativeButton then
                Bridge.MenuNavIcon(button, "suite_planner_" .. entry.key, ICONS[entry.key])
            end
            if not window.navCollapsed[entry.group] then
                Place(button, y)
                y = y - ITEM_STEP
            end
        end
    end
end

function B.DrawNav(window)
    for i, button in ipairs(window.tabs) do
        if window.spec.tabs[i] then B.StyleNav(button) end
    end
end
