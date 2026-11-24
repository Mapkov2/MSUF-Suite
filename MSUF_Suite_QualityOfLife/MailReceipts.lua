local _, P = ...
local NS, S = P.NS, P.Suite
local Receipts = {}
local LIMIT, ATTACHMENTS = 30, 12
local EVENTS = { "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED" }

local function History(create)
    local guid = S.PublicText(UnitGUID("player"))
    local root = NS.RootDB
    if not guid or type(root) ~= "table" then return end
    if type(root.suiteSentMail) ~= "table" then
        if not create then return end
        root.suiteSentMail = {}
    end
    local receipts = root.suiteSentMail[guid]
    if type(receipts) ~= "table" and create then
        receipts = {}
        root.suiteSentMail[guid] = receipts
    end
    return type(receipts) == "table" and receipts or nil
end

local function Capture(recipient)
    Receipts.pending = nil
    if not Receipts.active or not Receipts.mailOpen or NS.InCombat() then return end
    recipient = S.PublicText(recipient)
    local now, gold, cod = GetServerTime(), GetSendMailMoney(), GetSendMailCOD()
    if not recipient or not S.Finite(now) or not S.Finite(gold) or not S.Finite(cod) then return end
    local items = {}
    for slot = 1, ATTACHMENTS do
        local name, _, _, count = GetSendMailItem(slot)
        if not S.Public(name) then return end
        if name ~= nil then
            if not S.PublicText(name) or not S.Finite(count) or count < 1 then return end
            items[#items + 1] = ("%d × %s"):format(count, name)
        end
    end
    Receipts.pending = { at = now, recipient = recipient, items = items, gold = gold, cod = cod }
end

local function Rows()
    local history, rows = History(false), {}
    if not history then return rows end
    for index = 1, math.min(#history, LIMIT) do
        local entry = history[index]
        if type(entry) == "table" and S.PublicText(entry.recipient) and S.Finite(entry.at) and type(entry.items) == "table" then
            local lines = { date("%x %X", entry.at) }
            for i = 1, math.min(#entry.items, ATTACHMENTS) do
                local item = S.PublicText(entry.items[i])
                if item then lines[#lines + 1] = item end
            end
            if S.Finite(entry.gold) and entry.gold > 0 then
                lines[#lines + 1] = S.Text("Gold sent: %s"):format(S.MoneyText(entry.gold))
            end
            if S.Finite(entry.cod) and entry.cod > 0 then
                lines[#lines + 1] = S.Text("Cash on delivery: %s"):format(S.MoneyText(entry.cod))
            end
            rows[#rows + 1] = { key = index, label = entry.recipient, detail = table.concat(lines, "\n") }
        end
    end
    return rows
end

function Receipts:Open()
    S.ToolListWindow.Open(self, { title = "Recently sent mail", rows = Rows,
        help = "Shows confirmed outgoing mail for this character.",
        empty = "No sent mail has been recorded.",
        actions = { { label = "Clear history", enabled = function() return #Rows() > 0 end,
            run = function()
                S.Confirm("clearSentMail", { text = S.Text("Clear this character's sent mail history?"),
                    callback = function()
                        local history = History(false)
                        if history then wipe(history) end
                        S.ToolListWindow.Refresh(self)
                    end })
            end } },
    })
end

local function Button(self)
    if not self.button then
        local button = S.CreateFrame("Button", nil, MailFrame, "UIPanelButtonTemplate")
        button:SetPoint("LEFT", MailFrame, "BOTTOMRIGHT", -110, -12)
        button:SetSize(106, 22)
        button:SetText(S.Text("Sent mail"))
        button:SetScript("OnClick", function() self:Open() end)
        self.button = button
    end
    self.button:Show()
end

local function MailEvent(self, event)
    if event == "MAIL_SHOW" then
        self.mailOpen = true
        Button(self)
    elseif event == "MAIL_SEND_SUCCESS" then
        local entry = self.pending
        self.pending = nil
        if not entry then return end
        local now = GetServerTime()
        if not S.Finite(now) or now < entry.at or now - entry.at > 30 then return end
        local history = History(true)
        if not history then return end
        table.insert(history, 1, entry)
        while #history > LIMIT do table.remove(history) end
        S.ToolListWindow.Refresh(self)
    else
        self.pending = nil
        if event == "MAIL_CLOSED" then self.mailOpen = false end
    end
end

function Receipts:Enable()
    if not self.hooked then
        hooksecurefunc("SendMail", Capture)
        self.hooked = true
    end
    for _, event in ipairs(EVENTS) do self.context:Event(event, MailEvent) end
    local mailbox = MailFrame
    if not S.Public(mailbox) or not mailbox or NS.Safety.IsForbidden(mailbox) then return end
    local shown = mailbox:IsShown()
    if S.Public(shown) and shown == true then MailEvent(self, "MAIL_SHOW") end
end

function Receipts:Disable()
    self.pending, self.mailOpen = nil, false
    if self.button then self.button:Hide() end
    S.ToolListWindow.Close(self)
end

S.Install("mailReceipts", Receipts)
