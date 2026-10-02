local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Finance = { rows = {}, currencies = {}, currencyPool = {}, text = {}, lines = {}, linePool = {}, labels = {} }
P.BagFinance = Finance

-- The Bags gold history: each character's last recorded balance and its 30
-- days of income and spending, in the one gold ledger the DataTexts account
-- total shares (MSUF_Suite/Core/Catalog/Bags.lua). The Gold history lists the
-- characters the Bags recorded, and the account total's characters only
-- while that DataTexts opt-in is on. One clear removes all
-- (NS.ClearCharacterGold).
local Gold = NS.GoldLedger

local function AltGold()
    local data = S.Config("dataTexts")
    return data ~= nil and data.trackAltGold == true
end

-- Days since 1970-01-01 of the player's local calendar date (the inverse of
-- the proleptic Gregorian civil calendar), so a day starts at local midnight.
-- Labels format the day number in UTC, which prints exactly that date.
local function LocalDay(now)
    local t = date("*t", now)
    local year, month = t.year, t.month
    if month <= 2 then year = year - 1 end
    local era = math.floor(year / 400)
    local yearOfEra = year - era * 400
    local dayOfYear = math.floor((153 * ((month + 9) % 12) + 2) / 5) + t.day - 1
    local dayOfEra = yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100) + dayOfYear
    return era * 146097 + dayOfEra - 719468
end
Finance.LocalDay = LocalDay

-- Days that left the 30-day window leave the history. A character keeps
-- its last recorded balance; one without a balance and without a day in the
-- window is removed.
local function Prune(characters, today)
    for guid, record in pairs(characters) do
        local days = type(record) == "table" and type(record.days) == "table" and record.days or {}
        while days[1] and (type(days[1]) ~= "table" or not S.Finite(days[1].day) or days[1].day < today - 29) do
            table.remove(days, 1)
        end
        if type(record) ~= "table" or (#days == 0 and not (S.Finite(record.money) and type(record.name) == "string")) then
            characters[guid] = nil
        else
            record.days = days
        end
    end
end

-- The first amount of a recording session, or of a new record (after a
-- clear), is its baseline: money changes while the history was off or
-- between sessions were not observed, so none is invented as income or
-- spending (Finance.observed: the last amount recorded).
function Finance.Record()
    if not M.active or not M.config.showGoldHistory then
        Finance.observed = nil
        return
    end
    local record, money, guid, created = Gold.Record("bags")
    if not record then return end
    if created then Finance.observed = nil end
    local day = LocalDay(record.updated)
    if not Finance.pruned then
        Prune(Gold.Characters(), day)
        Finance.pruned = true
    end
    local days = type(record.days) == "table" and record.days or {}
    record.days = days
    local current = days[#days]
    if not current or current.day ~= day then
        current = { day = day, earned = 0, spent = 0 }
        days[#days + 1] = current
    end
    local delta = Finance.observed and Finance.guid == guid and money - Finance.observed or 0
    Finance.observed, Finance.guid = money, guid
    if delta > 0 then current.earned = current.earned + delta
    elseif delta < 0 then current.spent = current.spent - delta end
    while #days > 30 or days[1] and days[1].day < day - 29 do table.remove(days, 1) end
end

local function CurrencyInfo(id)
    if not S.Finite(id) or id <= 0 or id >= 2147483647 then return nil end
    local data = C_CurrencyInfo.GetCurrencyInfo(id)
    if S.Public(data) and type(data) == "table" and S.Public(data.name) and type(data.name) == "string"
        and S.Finite(data.quantity) then return data end
end

local function ReadCurrencies()
    for i = #Finance.currencies, 1, -1 do Finance.currencies[i] = nil end
    for value in (M.config.currencyIDs or ""):gmatch("%d+") do
        if #Finance.currencies == 8 then break end
        local id, seen = tonumber(value), false
        for i = 1, #Finance.currencies do
            if Finance.currencies[i].id == id then
                seen = true
                break
            end
        end
        local data = not seen and CurrencyInfo(id)
        if data then
            local index = #Finance.currencies + 1
            local row = Finance.currencyPool[index] or {}
            row.id, row.name, row.quantity, row.icon = id, data.name, data.quantity, data.iconFileID
            Finance.currencies[index], Finance.currencyPool[index] = row, row
        end
    end
end

local function Line(left, right)
    local index = #Finance.lines + 1
    local row = Finance.linePool[index] or {}
    row.left, row.right = left, right or ""
    Finance.lines[index], Finance.linePool[index] = row, row
end

-- One row per character the Bags recorded, and per account total character
-- while that opt-in is on. Returns the rows sorted by name and their total.
local function Balances(characters)
    for i = #Finance.rows, 1, -1 do Finance.rows[i] = nil end
    local total, alts = 0, AltGold()
    for _, record in pairs(characters) do
        if Gold.Listed(record) and (record.bags == true or alts and record.account == true) then
            Finance.rows[#Finance.rows + 1], total = record, total + record.money
        end
    end
    table.sort(Finance.rows, function(a, b) return a.name < b.name end)
    return Finance.rows, total
end

function Finance.BuildRows()
    for i = #Finance.lines, 1, -1 do Finance.lines[i] = nil end
    for i = 1, #Finance.currencies do
        local currency = Finance.currencies[i]
        Line(currency.name, tostring(currency.quantity))
    end
    local characters = M.config.showGoldHistory and Gold.Characters()
    if characters then
        Line(" ")
        local rows, total = Balances(characters)
        Line(S.Text("Recorded character gold"), S.MoneyText(total))
        for i = 1, #rows do Line(rows[i].name, S.MoneyText(rows[i].money)) end
        Line(S.Text("Other characters show their last recorded balance."))
        local guid = S.PublicText(UnitGUID("player"))
        local current = guid and characters[guid]
        if type(current) == "table" and type(current.days) == "table" then
            local earned, spent = 0, 0
            for i = 1, #current.days do earned, spent = earned + current.days[i].earned, spent + current.days[i].spent end
            Line(" ")
            Line(S.Text("Income recorded in the last 30 days"), S.MoneyText(earned))
            Line(S.Text("Spending recorded in the last 30 days"), S.MoneyText(spent))
            for i = #current.days, 1, -1 do
                local row = current.days[i]
                Line(date("!%Y-%m-%d", row.day * 86400),
                    "+" .. S.MoneyText(row.earned) .. " / -" .. S.MoneyText(row.spent))
            end
        end
    end
    return Finance.lines
end

local function Tooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(S.Text("Gold and currencies"))
    local rows = Finance.BuildRows()
    for i = 1, math.min(12, #rows) do GameTooltip:AddDoubleLine(rows[i].left, rows[i].right) end
    GameTooltip:AddLine(S.Text("Click to open the full gold history."), 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine(S.Text("Right-click to choose currencies."), 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

local function WindowRows()
    if not Finance.window or not Finance.window:IsShown() then return end
    local rows, font = Finance.BuildRows(), S.ResolveFont(M.config.font) or S.GlobalFontPath()
    for i = 1, #rows do
        local label = Finance.labels[i]
        if not label then
            label = { left = S.CreateFontString(Finance.content, nil, "OVERLAY"), right = S.CreateFontString(Finance.content, nil, "OVERLAY") }
            label.left:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
            label.right:SetPoint("TOPRIGHT", 0, -(i - 1) * 24)
            label.right:SetWidth(245)
            label.left:SetJustifyH("LEFT")
            label.right:SetJustifyH("RIGHT")
            label.left:SetWordWrap(false)
            label.right:SetWordWrap(false)
            Finance.labels[i] = label
        end
        local width = rows[i].right == "" and 552 or 300
        if label.width ~= width then
            label.left:SetWidth(width)
            label.width = width
        end
        if label.font ~= font then
            S.SetFont(label.left, font, 12, "OUTLINE")
            S.SetFont(label.right, font, 12, "OUTLINE")
            label.font = font
        end
        label.left:SetText(rows[i].left)
        label.right:SetText(rows[i].right)
        label.left:Show()
        label.right:Show()
    end
    for i = #rows + 1, #Finance.labels do
        Finance.labels[i].left:Hide()
        Finance.labels[i].right:Hide()
    end
    Finance.content:SetHeight(math.max(24, #rows * 24))
end

function Finance.Show()
    ReadCurrencies()
    if not Finance.window then
        Finance.window = P.GridView.Window("MSUFSuiteBagGoldHistory", 610, 510, "Gold and currencies")
        local scroll = S.CreateFrame("ScrollFrame", nil, Finance.window, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -38)
        scroll:SetPoint("BOTTOMRIGHT", -35, 16)
        Finance.content = S.CreateFrame("Frame", nil, scroll)
        Finance.content:SetSize(552, 24)
        scroll:SetScrollChild(Finance.content)
    end
    Finance.window:Show()
    WindowRows()
end

-- The footer line stands above the Suite grid's footer. In the combat
-- layout it stands right above Blizzard's money row, in the room
-- InventoryView.lua leaves below the slots (Finance.LINE), so the currencies and
-- the Gold history stay at hand during a fight. Placed out of combat only.
Finance.LINE = 18
local function Place(combat)
    local offset = combat and 4 or 35
    if Finance.offset == offset or NS.IsCombatLocked() then return end
    Finance.offset = offset
    local money = M.frame.MoneyFrame
    Finance.button:ClearAllPoints()
    Finance.button:SetPoint("BOTTOMLEFT", money, "TOPLEFT", 4, offset)
    Finance.button:SetPoint("BOTTOMRIGHT", money, "TOPRIGHT", -4, offset)
end

-- Whether the line has anything to show (the combat layout asks first).
function Finance.HasLine()
    return M.active and (M.config.showGoldHistory or #Finance.currencies > 0) and true or false
end

function Finance.Refresh()
    if not M.active or not M.frame then return end
    if not M.frame:IsShown() and not (Finance.window and Finance.window:IsShown()) then return end
    ReadCurrencies()
    WindowRows()
    if not M.frame:IsShown() then return end
    if not Finance.button then
        -- Above the inventory view's footer, which stands on Blizzard's money
        -- row (it moves up for tracked currencies); see Place.
        Finance.button = S.CreateFrame("Button", nil, M.frame)
        Finance.button:SetHeight(14)
        Finance.button:SetFrameLevel(M.frame:GetFrameLevel() + 16)
        Finance.button:SetScript("OnEnter", Tooltip)
        Finance.button:SetScript("OnLeave", GameTooltip_Hide)
        Finance.button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        Finance.button:SetScript("OnClick", function(button, mouseButton)
            if mouseButton == "RightButton" then S.BagCurrencyMenu(button) else Finance.Show() end
        end)
        Finance.label = S.CreateFontString(Finance.button, nil, "OVERLAY")
        Finance.label:SetAllPoints(Finance.button)
        Finance.label:SetJustifyH("LEFT")
        Finance.label:SetWordWrap(false)
    end
    for i = #Finance.text, 1, -1 do Finance.text[i] = nil end
    for i = 1, #Finance.currencies do
        local row = Finance.currencies[i]
        local icon = S.Finite(row.icon) and ("|T" .. row.icon .. ":12|t ") or ""
        Finance.text[#Finance.text + 1] = icon .. row.name .. ": " .. tostring(row.quantity)
    end
    if M.config.showGoldHistory then Finance.text[#Finance.text + 1] = S.Text("Gold history") end
    local font = S.ResolveFont(M.config.font) or S.GlobalFontPath()
    if Finance.font ~= font then
        S.SetFont(Finance.label, font, 10, "OUTLINE")
        Finance.font = font
    end
    Finance.label:SetText(table.concat(Finance.text, "   "))
    -- The Suite grid and the combat layout leave room for the line;
    -- Blizzard's own grid puts item rows there.
    local view = P.InventoryView
    local combat = view.CombatLine()
    local shown = #Finance.text > 0 and (view.SuiteLayout() or combat)
    if shown then Place(combat) end
    Finance.button:SetShown(shown)
end

local function Flush()
    Finance.queued = false
    Finance.Refresh()
end

function Finance.Event(_, event)
    if event == "PLAYER_MONEY" or event == "PLAYER_ENTERING_WORLD" then Finance.Record() end
    if Finance.queued or not M.active or not M.frame then return end
    if not M.frame:IsShown() and not (Finance.window and Finance.window:IsShown()) then return end
    Finance.queued = true
    C_Timer.After(0, Flush)
end

function Finance.Enable()
    if not M.active or not M.config.showGoldHistory then Finance.observed = nil end
    if not Finance.events then
        Finance.events = S.CreateFrame("Frame")
        Finance.events:SetScript("OnEvent", Finance.Event)
    end
    Finance.events:UnregisterAllEvents()
    if M.active then
        if M.config.showGoldHistory then
            Finance.events:RegisterEvent("PLAYER_MONEY")
            Finance.events:RegisterEvent("PLAYER_ENTERING_WORLD")
            Finance.Record()
        end
        Finance.events:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
        if not Finance.hooked then
            M.frame:HookScript("OnShow", Finance.Refresh)
            Finance.hooked = true
        end
        Finance.Refresh()
    end
end

function Finance.Disable()
    Finance.observed = nil
    if Finance.events then Finance.events:UnregisterAllEvents() end
    if Finance.button then Finance.button:Hide() end
    if Finance.window then Finance.window:Hide() end
end
