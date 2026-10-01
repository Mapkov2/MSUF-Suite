local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local F = { rows = {}, currencies = {}, currencyPool = {}, text = {}, lines = {}, linePool = {}, labels = {} }
P.BagFinance = F

-- The Bags gold history (RootDB.suiteBagGold): each character's last
-- recorded balance and its 30 days of income and spending. The Gold history
-- lists every character's balance from it. DataTexts keeps its own list
-- (RootDB.goldLedger, MSUF_Suite_DataTexts/GoldLedger.lua): the Bags only
-- read it, and only while that opt-in is on. One clear removes both
-- (NS.ClearCharacterGold).
local function Ledger()
    local root = NS.RootDB
    if type(root) ~= "table" then return nil end
    if type(root.suiteBagGold) ~= "table" or type(root.suiteBagGold.characters) ~= "table" then
        root.suiteBagGold = { characters = {} }
    end
    return root.suiteBagGold
end

local function AltGold()
    local data = S.Config("dataTexts")
    return data ~= nil and data.trackAltGold == true and type(NS.RootDB.goldLedger) == "table"
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
F.LocalDay = LocalDay

-- Days that left the 30-day window leave the history. A character keeps
-- its last recorded balance; one without a balance and without a day in the
-- window is removed.
local function Prune(ledger, today)
    for guid, record in pairs(ledger.characters) do
        local days = type(record) == "table" and type(record.days) == "table" and record.days or {}
        while days[1] and (type(days[1]) ~= "table" or not S.Finite(days[1].day) or days[1].day < today - 29) do
            table.remove(days, 1)
        end
        if type(record) ~= "table" or (#days == 0 and not (S.Finite(record.money) and type(record.name) == "string")) then
            ledger.characters[guid] = nil
        else
            record.days = days
        end
    end
end

function F.Record()
    if not M.active or not M.config.showGoldHistory then F.recording = false; return end
    local guid, money = UnitGUID("player"), GetMoney()
    if not S.Public(guid) or type(guid) ~= "string" or not S.Finite(money) or money < 0 then return end
    local ledger = Ledger()
    if not ledger then return end
    local name, realm = UnitFullName("player")
    if not S.Public(name) or type(name) ~= "string" then return end
    local now = GetServerTime()
    local day = LocalDay(now)
    if not F.pruned then
        Prune(ledger, day)
        F.pruned = true
    end
    local record = ledger.characters[guid]
    if not record then
        record = { days = {}, money = money }
        ledger.characters[guid] = record
    end
    record.name = name .. (S.Public(realm) and type(realm) == "string" and realm ~= "" and " - " .. realm or "")
    local current = record.days[#record.days]
    if not current or current.day ~= day then
        current = { day = day, earned = 0, spent = 0 }
        record.days[#record.days + 1] = current
    end
    -- Money changes while disabled or between sessions were not observed;
    -- establish a baseline instead of inventing income or spending for them.
    if not F.recording or F.guid ~= guid then record.money = money end
    F.recording, F.guid = true, guid
    local delta = money - record.money
    if delta > 0 then current.earned = current.earned + delta
    elseif delta < 0 then current.spent = current.spent - delta end
    while #record.days > 30 or record.days[1] and record.days[1].day < day - 29 do table.remove(record.days, 1) end
    record.money, record.updated = money, now
end

local function CurrencyInfo(id)
    if not S.Finite(id) or id <= 0 or id >= 2147483647 then return nil end
    local data = C_CurrencyInfo.GetCurrencyInfo(id)
    if S.Public(data) and type(data) == "table" and S.Public(data.name) and type(data.name) == "string"
        and S.Finite(data.quantity) then return data end
end

local function ReadCurrencies()
    for i = #F.currencies, 1, -1 do F.currencies[i] = nil end
    for value in (M.config.currencyIDs or ""):gmatch("%d+") do
        if #F.currencies == 8 then break end
        local id, seen = tonumber(value), false
        for i = 1, #F.currencies do if F.currencies[i].id == id then seen = true; break end end
        local data = not seen and CurrencyInfo(id)
        if data then
            local index = #F.currencies + 1
            local row = F.currencyPool[index] or {}
            row.id, row.name, row.quantity, row.icon = id, data.name, data.quantity, data.iconFileID
            F.currencies[index], F.currencyPool[index] = row, row
        end
    end
end

local function Line(left, right)
    local index = #F.lines + 1
    local row = F.linePool[index] or {}
    row.left, row.right = left, right or ""
    F.lines[index], F.linePool[index] = row, row
end

-- One row per character: its Bags record, else DataTexts' entry while that
-- opt-in is on. Returns the rows sorted by name and their total.
local listed = {}
local function Balances(ledger)
    for i = #F.rows, 1, -1 do F.rows[i] = nil end
    for guid in pairs(listed) do listed[guid] = nil end
    local total = 0
    local function Add(guid, record)
        if listed[guid] or type(record) ~= "table" or not S.Finite(record.money) or type(record.name) ~= "string" then
            return
        end
        listed[guid] = true
        F.rows[#F.rows + 1], total = record, total + record.money
    end
    for guid, record in pairs(ledger.characters) do Add(guid, record) end
    if AltGold() then
        for guid, record in pairs(NS.RootDB.goldLedger) do Add(guid, record) end
    end
    table.sort(F.rows, function(a, b) return a.name < b.name end)
    return F.rows, total
end

function F.BuildRows()
    for i = #F.lines, 1, -1 do F.lines[i] = nil end
    for i = 1, #F.currencies do
        local currency = F.currencies[i]
        Line(currency.name, tostring(currency.quantity))
    end
    local ledger = M.config.showGoldHistory and Ledger()
    if ledger then
        Line(" ")
        local rows, total = Balances(ledger)
        Line(S.Text("Recorded character gold"), S.MoneyText(total))
        for i = 1, #rows do Line(rows[i].name, S.MoneyText(rows[i].money)) end
        Line(S.Text("Other characters show their last recorded balance."))
        local guid = S.PublicText(UnitGUID("player"))
        local current = guid and ledger.characters[guid]
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
    return F.lines
end

local function Tooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(S.Text("Gold and currencies"))
    local rows = F.BuildRows()
    for i = 1, math.min(12, #rows) do GameTooltip:AddDoubleLine(rows[i].left, rows[i].right) end
    GameTooltip:AddLine(S.Text("Click to open the full gold history."), 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine(S.Text("Right-click to choose currencies."), 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

local function WindowRows()
    if not F.window or not F.window:IsShown() then return end
    local rows, font = F.BuildRows(), S.ResolveFont(M.config.font) or S.GlobalFontPath()
    for i = 1, #rows do
        local label = F.labels[i]
        if not label then
            label = { left = S.CreateFontString(F.content, nil, "OVERLAY"), right = S.CreateFontString(F.content, nil, "OVERLAY") }
            label.left:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
            label.right:SetPoint("TOPRIGHT", 0, -(i - 1) * 24)
            label.right:SetWidth(245)
            label.left:SetJustifyH("LEFT"); label.right:SetJustifyH("RIGHT")
            label.left:SetWordWrap(false); label.right:SetWordWrap(false)
            F.labels[i] = label
        end
        local width = rows[i].right == "" and 552 or 300
        if label.width ~= width then label.left:SetWidth(width); label.width = width end
        if label.font ~= font then
            S.SetFont(label.left, font, 12, "OUTLINE")
            S.SetFont(label.right, font, 12, "OUTLINE")
            label.font = font
        end
        label.left:SetText(rows[i].left); label.right:SetText(rows[i].right)
        label.left:Show(); label.right:Show()
    end
    for i = #rows + 1, #F.labels do F.labels[i].left:Hide(); F.labels[i].right:Hide() end
    F.content:SetHeight(math.max(24, #rows * 24))
end

function F.Show()
    ReadCurrencies()
    if not F.window then
        F.window = P.GridView.Window("MSUFSuiteBagGoldHistory", 610, 510, "Gold and currencies")
        local scroll = S.CreateFrame("ScrollFrame", nil, F.window, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -38)
        scroll:SetPoint("BOTTOMRIGHT", -35, 16)
        F.content = S.CreateFrame("Frame", nil, scroll)
        F.content:SetSize(552, 24)
        scroll:SetScrollChild(F.content)
    end
    F.window:Show()
    WindowRows()
end

-- The footer line stands above the Suite grid's footer. In the combat
-- layout it stands right above Blizzard's money row, in the room
-- InventoryView.lua leaves below the slots (F.LINE), so the currencies and
-- the Gold history stay at hand during a fight. Placed out of combat only.
F.LINE = 18
local function Place(combat)
    local offset = combat and 4 or 35
    if F.offset == offset or NS.IsCombatLocked() then return end
    F.offset = offset
    local money = M.frame.MoneyFrame
    F.button:ClearAllPoints()
    F.button:SetPoint("BOTTOMLEFT", money, "TOPLEFT", 4, offset)
    F.button:SetPoint("BOTTOMRIGHT", money, "TOPRIGHT", -4, offset)
end

-- Whether the line has anything to show (the combat layout asks first).
function F.HasLine()
    return M.active and (M.config.showGoldHistory or #F.currencies > 0) and true or false
end

function F.Refresh()
    if not M.active or not M.frame then return end
    if not M.frame:IsShown() and not (F.window and F.window:IsShown()) then return end
    ReadCurrencies()
    WindowRows()
    if not M.frame:IsShown() then return end
    if not F.button then
        -- Above the inventory view's footer, which stands on Blizzard's money
        -- row (it moves up for tracked currencies); see Place.
        F.button = S.CreateFrame("Button", nil, M.frame)
        F.button:SetHeight(14)
        F.button:SetFrameLevel(M.frame:GetFrameLevel() + 16)
        F.button:SetScript("OnEnter", Tooltip)
        F.button:SetScript("OnLeave", GameTooltip_Hide)
        F.button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        F.button:SetScript("OnClick", function(button, mouseButton)
            if mouseButton == "RightButton" then S.BagCurrencyMenu(button) else F.Show() end
        end)
        F.label = S.CreateFontString(F.button, nil, "OVERLAY")
        F.label:SetAllPoints(F.button)
        F.label:SetJustifyH("LEFT")
        F.label:SetWordWrap(false)
    end
    for i = #F.text, 1, -1 do F.text[i] = nil end
    for i = 1, #F.currencies do
        local row = F.currencies[i]
        local icon = S.Finite(row.icon) and ("|T" .. row.icon .. ":12|t ") or ""
        F.text[#F.text + 1] = icon .. row.name .. ": " .. tostring(row.quantity)
    end
    if M.config.showGoldHistory then F.text[#F.text + 1] = S.Text("Gold history") end
    local font = S.ResolveFont(M.config.font) or S.GlobalFontPath()
    if F.font ~= font then S.SetFont(F.label, font, 10, "OUTLINE"); F.font = font end
    F.label:SetText(table.concat(F.text, "   "))
    -- The Suite grid and the combat layout leave room for the line;
    -- Blizzard's own grid puts item rows there.
    local view = P.InventoryView
    local combat = view.CombatLine()
    local shown = #F.text > 0 and (view.SuiteLayout() or combat)
    if shown then Place(combat) end
    F.button:SetShown(shown)
end

local function Flush()
    F.queued = false
    F.Refresh()
end

function F.Event(_, event)
    if event == "PLAYER_MONEY" or event == "PLAYER_ENTERING_WORLD" then F.Record() end
    if F.queued or not M.active or not M.frame then return end
    if not M.frame:IsShown() and not (F.window and F.window:IsShown()) then return end
    F.queued = true
    C_Timer.After(0, Flush)
end

function F.Enable()
    if not M.active or not M.config.showGoldHistory then F.recording = false end
    if not F.events then
        F.events = S.CreateFrame("Frame")
        F.events:SetScript("OnEvent", F.Event)
    end
    F.events:UnregisterAllEvents()
    if M.active then
        if M.config.showGoldHistory then
            F.events:RegisterEvent("PLAYER_MONEY")
            F.events:RegisterEvent("PLAYER_ENTERING_WORLD")
            F.Record()
        end
        F.events:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
        if not F.hooked then M.frame:HookScript("OnShow", F.Refresh); F.hooked = true end
        F.Refresh()
    end
end

function F.Disable()
    F.recording = false
    if F.events then F.events:UnregisterAllEvents() end
    if F.button then F.button:Hide() end
    if F.window then F.window:Hide() end
end

hooksecurefunc(M, "Refresh", F.Enable)
hooksecurefunc(M, "Disable", F.Disable)
