local _, NS = ...
local Controls = {}
NS.CurrencyControls = Controls
local Text, String, Suite = NS.Text, NS.String, NS.Suite
local ID, TAB = "characterPanel", "currency"
local WIDTH, HEIGHT = 122, 22
Controls.Height = 30
local sorts = { "Category", "Name", "Quantity" }
local options = {
    { "currencyHideZero", "Hide zero balances" },
    { "currencyShowInactive", "Show inactive currencies" },
    { "currencyIcons", "Show currency icons" },
    { "currencyCaps", "Show currency caps" },
    { "currencySearch", "Search" },
}

function Controls.Current(state)
    local module = state.module
    local view = module.view
    return not NS.Host.InCombat() and module.tab == TAB and view and view.frame:IsShown() and not view:IsMinimized()
end

local Current = Controls.Current

local function Apply(entry)
    if Current(entry.state) then Suite.Set(ID, entry.key, entry.value) end
end

local function Selected(entry)
    return entry.state.module.config[entry.key] == entry.value
end

local function Checked(entry)
    return entry.state.module.config[entry.key] == true
end

local function Toggle(entry)
    if Current(entry.state) then Suite.Set(ID, entry.key, not Checked(entry)) end
end

local function Labels()
    local name = String(UnitName("player"))
    local character = name and String(CURRENCY_FILTER_TYPE_CHARACTER)
    return { Text("All"), String(CURRENCY_FILTER_TYPE_TRANSFERABLE) or Text("Warband"),
        character and character:format(name) or Text("Character") }
end

local function Modes(_, menu, state)
    for index, label in ipairs(Labels()) do
        menu:CreateRadio(label, Selected, Apply, { state = state, key = "currencyView", value = index })
    end
end

local function Settings(_, menu, state)
    menu:CreateTitle(Text("Sort by"))
    for index, name in ipairs(sorts) do
        menu:CreateRadio(Text(name), Selected, Apply, { state = state, key = "currencySort", value = index })
    end
    menu:CreateDivider()
    for _, option in ipairs(options) do
        menu:CreateCheckbox(Text(option[2]), Checked, Toggle, { state = state, key = option[1] })
    end
    menu:CreateDivider()
    menu:CreateButton(Text("Refresh"), function()
        if Current(state) then NS.Currency.Reload(state) end
    end)
end

local function Favorites(config, id)
    local keep, found = {}, false
    for value in (config.currencyFavorites or ""):gmatch("%d+") do
        if tonumber(value) == id then found = true else keep[#keep + 1] = value end
    end
    return keep, found
end

local function ToggleFavorite(entry)
    if not Current(entry.state) then return end
    local list, found = Favorites(entry.state.module.config, entry.id)
    if not found then list[#list + 1] = tostring(entry.id) end
    local encoded = table.concat(list, ",")
    if #encoded <= 512 then Suite.Set(ID, "currencyFavorites", encoded) end
end

local function RowChoices(_, menu, entry)
    local _, pinned = Favorites(entry.state.module.config, entry.id)
    menu:CreateButton(Text(pinned and "Remove from favorites" or "Add to favorites"), ToggleFavorite, entry)
end

function Controls.RowMenu(state, entry, button)
    if Current(state) then Suite.ContextMenu(button, RowChoices, { state = state, id = entry.id }) end
end

local function MenuButton(view, bar, style, label, menu)
    return style.Button(view, bar, label, function(button)
        if bar.state and Current(bar.state) then Suite.ContextMenu(button, menu, bar.state) end
    end)
end

local function Search(bar, view, mode, style)
    local edit = style.Input(view, bar)
    edit:SetPoint("LEFT", mode, "RIGHT", 4, 0)
    edit:SetPoint("RIGHT", -4, 0)
    edit:SetHeight(HEIGHT)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetTextInsets(6, 6, 0, 0)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(80)
    local hint = style.Font(view, edit, 11, style.muted)
    hint:SetPoint("LEFT", 6, 0)
    hint:SetText(Text("Search"))
    edit:SetScript("OnTextChanged", function(self, user)
        local value = String(self:GetText()) or ""
        hint:SetShown(value == "")
        if not user or not bar.state or not Current(bar.state) then return end
        local query = NS.Currency.Query(value)
        if bar.state.query == query then return end
        bar.state.query = query
        NS.Currency.Paint(bar.state.module, false, true)
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if not bar.state or not Current(bar.state) then return end
        bar.state.query = ""
        self:SetText("")
        NS.Currency.Paint(bar.state.module, false, true)
    end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    bar:SetScript("OnHide", function() edit:ClearFocus() end)
    return edit
end

local function Create(view, style)
    local bar = style.Panel(view, view.report.parent)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(Controls.Height - 4)
    local settings = MenuButton(view, bar, style, "...", Settings)
    settings:SetPoint("LEFT", 4, 0)
    settings:SetSize(26, HEIGHT)
    settings:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText(Text("Settings"))
        GameTooltip:Show()
    end)
    local function Hide(button) if GameTooltip:IsOwned(button) then GameTooltip:Hide() end end
    settings:SetScript("OnLeave", Hide)
    settings:SetScript("OnHide", Hide)
    local mode, label = MenuButton(view, bar, style, "", Modes)
    mode:SetPoint("LEFT", settings, "RIGHT", 4, 0)
    mode:SetSize(WIDTH, HEIGHT)
    bar.mode, bar.modeLabel, bar.search = mode, label, Search(bar, view, mode, style)
    view.currencyControls = bar
    return bar
end

function Controls.Show(view, state, style)
    local bar = view.currencyControls or Create(view, style)
    local config = state.module.config
    if bar.state ~= state or config.currencySearch == false then
        bar.state = state
        bar.search:SetText(state.query)
    end
    style.Visible(bar.search, config.currencySearch ~= false)
    style.Text(bar.modeLabel, Labels()[config.currencyView or 1] or Text("All"))
    local width = NS.Number(bar.modeLabel:GetUnboundedStringWidth()) or WIDTH
    bar.mode:SetWidth(math.min(view.bodyWidth * .55, math.max(WIDTH, width + 12)))
    style.Visible(bar, true)
end

function Controls.Hide(view)
    local bar = view.currencyControls
    if not bar then return end
    bar.state, bar.panelShown = nil, false
    bar:Hide()
end
