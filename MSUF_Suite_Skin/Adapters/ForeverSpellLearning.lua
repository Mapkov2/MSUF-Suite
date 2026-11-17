local _, NS = ...
local Learning = {}
NS.SpellLearning = Learning
if not NS.Client.isForever then return end

local Safety = NS.Safety
local Public, Read = Safety.Public, Safety.Read
local ROWS, WIDTH, HEIGHT, ROW_HEIGHT = 10, 390, 420, 27
local OWNER = "spellLearning"
local SHELL = { role = "shell", inset = 0 }
local BUTTON = { role = "button", ownedArt = true }
local PRIMARY = { role = "buttonPrimary", pillHeight = 28, ownedArt = true }
local SEARCH = { role = "input", pillHeight = 25 }

local function Label(parent, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    return label
end

local function Button(parent, text, minWidth, callback, primary)
    local button = Safety.CreateChildFrame("Button", parent)
    local label = Label(button, primary and "GameFontHighlight" or nil)
    label:SetPoint("CENTER")
    label:SetJustifyH("CENTER")
    label:SetText(text)
    label:SetShadowColor(0, 0, 0, .9)
    label:SetShadowOffset(0, -1)
    local width = Read(label, "GetStringWidth") or 0
    button:SetSize(math.max(minWidth, math.ceil(width) + (primary and 32 or 18)), primary and 28 or 24)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", callback)
    button.label = label
    NS.ControlSkin.ApplyButton(button, OWNER, primary and PRIMARY or BUTTON)
    return button
end

local function Rule(parent, point, y, inset)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint(point .. "LEFT", parent, point .. "LEFT", inset, y)
    line:SetPoint(point .. "RIGHT", parent, point .. "RIGHT", -inset, y)
    line:SetHeight(1)
    return line
end

local function AllowedRace(race, low, high)
    if low == "" and high == "" then return true end
    if not Public(race) or type(race) ~= "number" or race < 1 or race > 64 then return false end
    return bit.band(tonumber(race < 33 and low or high) or 0, bit.lshift(1, (race - 1) % 32)) ~= 0
end

local function ReadIndex()
    local _, _, class = UnitClass("player")
    local _, _, race = UnitRace("player")
    local data = Public(class) and NS.ForeverSpellLearningData[class]
    local entries = {}
    if not data then return entries end
    for id, level, rank, source, low, high in data:gmatch("(%d+):(%d+):(%d+):(%d+):?(%d*):?(%d*) ") do
        if AllowedRace(race, low, high) then
            entries[#entries + 1] = { id = tonumber(id), level = tonumber(level), rank = tonumber(rank), source = tonumber(source) }
        end
    end
    return entries
end

local function ToolTip(row)
    if not row.spellID or NS.IsCombatLocked() or Safety.IsForbidden(GameTooltip) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(row.spellID)
    local source = row.source
    if source == 1 then
        GameTooltip:AddLine(NS.L["Class trainer"], NS.Theme.GetColor("accentBright"))
    elseif source == 2 then
        GameTooltip:AddLine(NS.L["Class quest"], NS.Theme.GetColor("accentBright"))
    elseif source == 4 then
        GameTooltip:AddLine(NS.L["Requires a talent"], NS.Theme.GetColor("accentBright"))
    end
    GameTooltip:Show()
end

local function HideTooltip(row)
    if not Safety.IsForbidden(GameTooltip) and Read(GameTooltip, "IsOwned", row) == true then GameTooltip:Hide() end
end

local function MakeRow(panel, index)
    local row = CreateFrame("Frame", nil, panel)
    local y = -99 - (index - 1) * ROW_HEIGHT
    row:SetPoint("TOPLEFT", 16, y)
    row:SetPoint("TOPRIGHT", -16, y)
    row:SetHeight(ROW_HEIGHT)
    if index < ROWS then row.divider = Rule(row, "BOTTOM", 0, 0) end
    row:EnableMouse(true)
    row:SetScript("OnEnter", ToolTip)
    row:SetScript("OnLeave", HideTooltip)
    row:SetScript("OnHide", HideTooltip)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(19, 19)
    row.icon:SetPoint("LEFT", 2, 0)
    row.name = Label(row)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.level = Label(row)
    row.level:SetPoint("RIGHT", -2, 0)
    row.level:SetWidth(86)
    row.level:SetJustifyH("RIGHT")
    row.rank = Label(row)
    row.rank:SetPoint("RIGHT", row.level, "LEFT", -12, 0)
    row.rank:SetWidth(64)
    row.rank:SetJustifyH("RIGHT")
    row.name:SetPoint("RIGHT", row.rank, "LEFT", -10, 0)
    return row
end

local function Paint(panel)
    local shown = panel.filtered
    local maxPage = math.max(1, math.ceil(#shown / ROWS))
    panel.page = math.min(maxPage, math.max(1, panel.page))
    local level = UnitLevel("player")
    local levelReadable = Public(level) and type(level) == "number"
    for index = 1, ROWS do
        local row = panel.rows[index]
        local entry = shown[(panel.page - 1) * ROWS + index]
        if entry then
            local tone = levelReadable and level >= entry.level and "accentBright" or "muted"
            row.spellID, row.source = entry.id, entry.source
            row.icon:SetTexture(entry.icon)
            row.name:SetText(entry.name)
            row.name:SetTextColor(NS.Theme.GetColor("text"))
            row.rank:SetText(entry.rank > 0 and NS.L["Rank %d"]:format(entry.rank) or "")
            row.rank:SetTextColor(NS.Theme.GetColor("muted"))
            row.level:SetText(NS.L["Level %d"]:format(entry.level))
            row.level:SetTextColor(NS.Theme.GetColor(tone))
            row:Show()
            if row:IsMouseOver() and Read(GameTooltip, "IsOwned", row) == true then ToolTip(row) end
        else
            row:Hide()
            row.spellID = nil
        end
    end
    panel.status:SetText(#shown > 0 and ("%d / %d"):format(panel.page, maxPage) or NS.L["No spells to show"])
    local canGoBack, canGoForward = panel.page > 1, panel.page < maxPage
    panel.previous:SetEnabled(canGoBack)
    panel.next:SetEnabled(canGoForward)
    panel.previous.label:SetTextColor(NS.Theme.GetColor(canGoBack and "text" or "dim"))
    panel.next.label:SetTextColor(NS.Theme.GetColor(canGoForward and "text" or "dim"))
end

local function Filter(panel)
    local query = panel.search:GetText()
    query = Public(query) and type(query) == "string" and query:lower() or ""
    local matches = panel.filtered
    local count = 0
    for _, entry in ipairs(panel.available) do
        if query == "" or entry.searchName:find(query, 1, true) then
            count = count + 1
            matches[count] = entry
        end
    end
    for index = #matches, count + 1, -1 do matches[index] = nil end
    Paint(panel)
end

local function Refresh(panel)
    if not panel:IsShown() or NS.IsCombatLocked() then return end
    panel.entries = panel.entries or ReadIndex()
    local count = 0
    for _, entry in ipairs(panel.entries) do
        local known = C_SpellBook.IsSpellKnown(entry.id)
        if Public(known) and known == false then
            local name = entry.name or C_Spell.GetSpellName(entry.id)
            if Public(name) and type(name) == "string" and name ~= "" then
                if not entry.name then
                    local icon = C_Spell.GetSpellTexture(entry.id)
                    entry.name, entry.searchName = name, name:lower()
                    entry.icon = Public(icon) and icon or nil
                end
                count = count + 1
                panel.available[count] = entry
            end
        end
    end
    for index = #panel.available, count + 1, -1 do panel.available[index] = nil end
    Filter(panel)
end

local function Advance(panel, delta)
    panel.page = panel.page + delta
    Paint(panel)
end

local function Position(panel)
    local book = panel.book
    local edge, left = Read(book, "GetRight"), Read(book, "GetLeft")
    local scale = Read(book, "GetEffectiveScale")
    panel:ClearAllPoints()
    if type(edge) == "number" and type(scale) == "number"
        and edge * scale / UIParent:GetEffectiveScale() + WIDTH + 8 <= UIParent:GetWidth() then
        panel:SetPoint("TOPLEFT", book, "TOPRIGHT", 8, 0)
    elseif type(left) == "number" and type(scale) == "number" and left * scale / UIParent:GetEffectiveScale() >= WIDTH + 8 then
        panel:SetPoint("TOPRIGHT", book, "TOPLEFT", -8, 0)
    else
        panel:SetPoint("TOP", book, "TOP", 0, -49)
    end
end

local function OnPanelEvent(panel, event)
    if event == "PLAYER_REGEN_DISABLED" then
        panel:Hide()
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        if not NS.IsCombatLocked() then Position(panel) end
    else
        NS.Registry.QueueJob(panel.refresh)
    end
end

local function PaintPanelTheme(panel)
    NS.Surface.Ensure(panel, SHELL)
    panel.title:SetTextColor(NS.Theme.GetColor("title"))
    panel.caption:SetTextColor(NS.Theme.GetColor("muted"))
    panel.status:SetTextColor(NS.Theme.GetColor("muted"))
    panel.close.label:SetTextColor(NS.Theme.GetColor("text"))
    panel.search:SetTextColor(NS.Theme.GetColor("text"))
    local hint = Safety.Field(panel.search, "Instructions")
    if type(hint) == "table" then hint:SetTextColor(NS.Theme.GetColor("muted")) end
    panel.headerRule:SetColorTexture(NS.Theme.GetColor("border"))
    panel.footerRule:SetColorTexture(NS.Theme.GetColor("border"))
    for index = 1, ROWS - 1 do
        panel.rows[index].divider:SetColorTexture(NS.Theme.GetColor("borderSoft"))
    end
end

local function OnPanelShow(panel)
    panel:RegisterEvent("SPELLS_CHANGED")
    panel:RegisterEvent("PLAYER_LEVEL_UP")
    panel:RegisterEvent("PLAYER_REGEN_DISABLED")
    panel:RegisterEvent("UI_SCALE_CHANGED")
    panel:RegisterEvent("DISPLAY_SIZE_CHANGED")
    Position(panel)
    PaintPanelTheme(panel)
    Refresh(panel)
end

local function OnPanelHide(panel)
    panel:UnregisterAllEvents()
    panel.search:ClearFocus()
end

local function CreatePanel(book)
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:Hide()
    panel.book, panel.page, panel.rows, panel.available, panel.filtered = book, 1, {}, {}, {}
    panel.refresh = function() Refresh(panel) end
    panel.close = Button(panel, CLOSE, 74, function() panel:Hide() end)
    panel.close:SetPoint("TOPRIGHT", -12, -10)
    panel.title = Label(panel, "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 16, -14)
    panel.title:SetPoint("RIGHT", panel.close, "LEFT", -10, 0)
    panel.title:SetText(NS.L["Spells to Learn"])
    panel.caption = Label(panel)
    panel.caption:SetPoint("TOPLEFT", 16, -40)
    panel.caption:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    panel.caption:SetText(NS.L["Unlearned spells and ranks by required level"])
    panel.search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
    panel.search:SetHeight(25)
    panel.search:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -61)
    panel.search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -61)
    panel.search:SetAutoFocus(false)
    NS.ControlSkin.ApplySearchBox(panel.search, OWNER, SEARCH)
    panel.headerRule = Rule(panel, "TOP", -93, 16)
    panel.footerRule = Rule(panel, "BOTTOM", 44, 16)
    panel.search:HookScript("OnTextChanged", function()
        panel.page = 1
        if panel:IsShown() then Filter(panel) end
    end)
    panel.search:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    for index = 1, ROWS do panel.rows[index] = MakeRow(panel, index) end
    panel.previous = Button(panel, "<", 29, function() Advance(panel, -1) end)
    panel.previous:SetPoint("BOTTOMLEFT", 16, 10)
    panel.next = Button(panel, ">", 29, function() Advance(panel, 1) end)
    panel.next:SetPoint("BOTTOMRIGHT", -16, 10)
    panel.status = Label(panel)
    panel.status:SetPoint("BOTTOM", 0, 16)
    panel:SetScript("OnMouseWheel", function(_, delta) Advance(panel, delta < 0 and 1 or -1) end)
    panel:SetScript("OnEvent", OnPanelEvent)
    panel:SetScript("OnShow", OnPanelShow)
    panel:SetScript("OnHide", OnPanelHide)
    return panel
end

function Learning.Hide(state)
    if state.learningButton then state.learningButton:Hide() end
    if state.learningPanel then state.learningPanel:Hide() end
end

local function Enabled()
    return NS.DB.enabled ~= false and NS.DB.skins.playerSpells ~= false and NS.DB.foreverSpellLearning ~= false
        and not NS.Client.IsGamepadUI()
end

local function CreateLearningButton(book, paged, onClick)
    -- A sibling of the rank toggle follows the book's own stacking and focus.
    local button = Button(book, NS.L["Spells to Learn"], 170, onClick, true)
    button:SetFrameLevel((Read(paged, "GetFrameLevel") or 1) + 10)
    button:SetPoint("TOPRIGHT", paged, "TOPRIGHT", -24, -10)
    return button
end

function Learning.Attach(state, book, paged)
    if not Enabled() or NS.IsCombatLocked() or Safety.IsForbidden(book) or Safety.IsForbidden(paged) then return end
    if not state.learningButton then
        local function Toggle()
            if NS.IsCombatLocked() or not Enabled() or Read(book, "IsVisible") ~= true then return end
            local panel = state.learningPanel
            if not panel then
                panel = CreatePanel(book)
                state.learningPanel = panel
            end
            panel:SetShown(not panel:IsShown())
        end
        local button = CreateLearningButton(book, paged, Toggle)
        state.learningButton = button
        book:HookScript("OnShow", Safety.Isolated(function()
            if state.active and Enabled() then button:Show() end
        end))
        book:HookScript("OnHide", Safety.Isolated(function() Learning.Hide(state) end))
    end
    local button = state.learningButton
    local red, green, blue = NS.Theme.GetColor("accentBright")
    button.label:SetTextColor(red, green, blue, 1)
    button:SetShown(Read(book, "IsVisible") == true)
end

function Learning.RefreshSetting()
    local state = NS.PlayerSpellsSkin.activeState
    if not state then return end
    if not Enabled() then return Learning.Hide(state) end
    local book = Safety.Field(state.frame, "SpellBookFrame")
    local paged = Safety.Field(book, "PagedSpellsFrame")
    if book and paged and not NS.IsCombatLocked() then Learning.Attach(state, book, paged) end
    if state.learningPanel and state.learningPanel:IsShown() then
        PaintPanelTheme(state.learningPanel)
        Paint(state.learningPanel)
    end
end

function Learning.SetEnabled(value)
    NS.DB.foreverSpellLearning = value == true
    Learning.RefreshSetting()
    return true
end
