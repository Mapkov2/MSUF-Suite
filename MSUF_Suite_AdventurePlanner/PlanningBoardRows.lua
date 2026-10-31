local _, P = ...
local S, Plan = P.Suite, P.PlanningTools
local B = Plan.Board
local Bridge = P.NS.HostBridge
B.LIST_WIDTH = 440

-- Rows use Menu2's nav-item painter: no fill at rest, its hover and its
-- selected pill. Without Menu2 a stripe and fill mark them the same way.
local function StyleRow(button, row)
    local window = button.window
    local selected = row.key == window.selected
    if button.plannerNativeButton then
        button:SetActive(selected)
        button:SetAlpha(row.disabled and .5 or 1)
        return
    end
    if selected then
        B.Tint(button.fill, "pillActive", .9)
    elseif button.hover then
        B.Tint(button.fill, "pillHover", 1)
    else
        B.Tint(button.fill, "pillHover", 0)
    end
    button.stripe:SetShown(selected)
    B.TintLabel(button.text, row.disabled and "disabled" or selected and "title" or "text")
end

local function Hover(button, hover)
    button.hover = hover
    local window = button.window
    local row = window.spec and window.filtered[window.offset + button.index]
    if row then StyleRow(button, row) end
end

local function FallbackRow(window, width)
    local row = S.CreateFrame("Button", nil, window.listSlider)
    row:SetSize(width, B.ROW_HEIGHT - 4)
    row.fill = B.Fill(row, "pillHover", 0, "pillBase")
    row.stripe = B.Texture(row, "ARTWORK", "accent", 1)
    row.stripe:SetPoint("TOPLEFT", 0, -6)
    row.stripe:SetPoint("BOTTOMLEFT", 0, 6)
    row.stripe:SetWidth(3)
    row.text = B.Label(row, "", 13)
    row:SetScript("OnEnter", function(self) Hover(self, true) end)
    row:SetScript("OnLeave", function(self) Hover(self, false) end)
    return row
end

function B.CreateRows(window)
    window.buttons = {}
    local width = B.LIST_WIDTH - 32
    for i = 1, B.PAGE_ROWS + 1 do
        local row = Bridge.MenuNavButton(window.listSlider, width, B.ROW_HEIGHT - 4)
        if row then
            row.plannerNativeButton = true
            row.text = B.TrackFont(Bridge.MenuButtonLabel(row), 13, false)
        else
            row = FallbackRow(window, width)
        end
        row:SetPoint("TOPLEFT", 0, -(i - 1) * B.ROW_HEIGHT)
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", 14, -6)
        row.text:SetSize(width - 28, 34)
        row.text:SetJustifyH("LEFT")
        row.text:SetJustifyV("MIDDLE")
        row.text:SetWordWrap(true)
        row.index, row.window = i, window
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", B.RowClicked)
        window.buttons[i] = row
    end
end

function B.DrawRows(window)
    for i, button in ipairs(window.buttons) do
        local row = window.filtered[window.offset + i]
        button:SetShown(row ~= nil)
        if row then
            button.text:SetText(row.label or "")
            StyleRow(button, row)
        end
    end
    local count = #window.filtered
    window.counter:SetText(S.Text("%d–%d of %d"):format(count == 0 and 0 or window.offset + 1,
        math.min(count, window.offset + B.PAGE_ROWS), count))
end

-- offset is in pixels: a new first row repaints, a fraction only slides.
function B.PlaceList(window, offset, force)
    local first = math.floor(offset / B.ROW_HEIGHT)
    local fraction = offset - first * B.ROW_HEIGHT
    window.listSlider:ClearAllPoints()
    window.listSlider:SetPoint("TOPLEFT", 0, fraction)
    if force or first ~= window.offset then
        window.offset = first
        B.DrawRows(window)
    end
    local last = window.buttons[#window.buttons]
    last:SetShown(window.filtered[first + #window.buttons] ~= nil and fraction > 0)
end

function B.ListScrolled(window, offset)
    if B.Valid(window) then B.PlaceList(window, offset) end
end

-- Footer pills sized to their labels, left to right as Menu2 lays out its own.
local function DrawActions(window, selected)
    local x = 14
    for i, button in ipairs(window.actions) do
        local action = window.spec.actions[i]
        button:SetShown(action ~= nil)
        if action then
            button.text:SetText(S.Text(action.label))
            if not Bridge.MenuFitButton(button, 96, 220) then button:SetWidth(148) end
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", x, -620)
            x = x + button:GetWidth() + 8
            button:SetEnabled(not action.enabled or action.enabled(window.owner, selected))
            B.StyleButton(button, false)
        end
    end
end

local function DrawDetails(window, tab, selected)
    window.detailTitle:SetText(selected and selected.label or S.Text("Details"))
    window.details:SetText(selected and selected.detail or Plan.Overview.Hint(tab))
    local view = window.detailScrollFrame:GetHeight()
    local height = math.max(view, window.details:GetStringHeight() + 16)
    window.details:SetHeight(height)
    window.detailsChild:SetHeight(height)
    window.detailScroll:SetRange(height, view)
    window.detailScroll:Apply(window.detailScroll.offset)
end

local function DrawList(window, tab, query)
    local count = #window.filtered
    window.listScroll:SetRange(count * B.ROW_HEIGHT, B.PAGE_ROWS * B.ROW_HEIGHT)
    B.PlaceList(window, window.listScroll.offset, true)
    window.empty:SetShown(count == 0)
    window.empty:SetText(query ~= "" and #window.items > 0 and S.Text("No results")
        or S.Text("No saved entries") .. "\n\n" .. Plan.Overview.Hint(tab))
    DrawDetails(window, tab, window:Selected())
end

function B.Draw(window, query)
    local tab = window.spec.currentTab(window.owner)
    local overview = tab == "characters"
    window.matrix:SetShown(overview)
    window.list:SetShown(not overview)
    window.detailsPanel:SetShown(not overview)
    window.counter:SetShown(not overview)
    if overview then
        Plan.Matrix.Draw(window, query)
    else
        DrawList(window, tab, query)
    end
    DrawActions(window, window:Selected())
end

-- The header counts every saved character on every page; other pages reuse
-- one count until the saved data or the weekly reset changes.
local function Summary(window, tab)
    local reset = Plan.Weekly.Reset()
    if tab ~= "characters" and (not window.statsRows or window.statsGeneration ~= Plan.generation
        or window.statsReset ~= reset) then
        window.statsRows = Plan.Weekly.Rows(false)
        window.statsGeneration, window.statsReset = Plan.generation, reset
    end
    local characters, _, rewards, gold = Plan.Overview.Stats(tab == "characters" and window.items or window.statsRows)
    if P.NS.Client.isForever then
        window.summary:SetText(S.Text("Characters: %d • Gold: %s"):format(characters, Plan.Matrix.GoldText(gold)))
    else
        window.summary:SetText(S.Text("Characters: %d • Gold: %s • Vault rewards waiting: %d")
            :format(characters, Plan.Matrix.GoldText(gold), rewards))
    end
end

local function Stats(window)
    local tab = window.spec.currentTab(window.owner)
    Summary(window, tab)
    for _, entry in ipairs(window.spec.tabs) do
        if entry.key == tab then window.pageTitle:SetText(S.Text(entry.label)) end
    end
    window.pageHint:SetText(Plan.Overview.Hint(tab))
    B.DrawNav(window)
end

function B.Update(window)
    if not window:IsShown() then return end
    if not B.Valid(window) then
        window:Hide()
        return
    end
    if window.foldActive then B.FinishAccordion(window, false) B.LayoutNav(window) end
    B.EnsureFonts()
    window.now = Plan.Now() or 0
    local query = window.search:GetText():lower()
    local overview = window.spec.currentTab(window.owner) == "characters"
    window.items = window.spec.rows(window.owner, query) or {}
    local count = 0
    for _, row in ipairs(window.items) do
        if overview or query == "" or (row.search or row.label or ""):lower():find(query, 1, true) then
            count = count + 1
            window.filtered[count] = row
        end
    end
    for i = #window.filtered, count + 1, -1 do window.filtered[i] = nil end
    if not window.selected and window.filtered[1] then window.selected = window.filtered[1].key end
    window.status:SetText(window.spec.status and window.spec.status(window.owner) or "")
    Stats(window)
    B.Draw(window, query)
end
