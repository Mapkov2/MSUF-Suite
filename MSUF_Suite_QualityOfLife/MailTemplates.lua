local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end
local Lists, Data, UI = NS.InventoryLists, S.InventoryData, S.InventoryToolsUI
local M = { status = "" }

local function Entries() return Lists.Templates(M.config.templates) end
local function Save(entries)
    local text = Lists.EncodeTemplates(entries)
    return text and S.Set(M.id, "templates", text) or false
end
local function Selected()
    local entries = Entries()
    return entries[M.selected], entries
end
local function OwnRecipient(address)
    local recipients = S.InventoryArchive:Recipients()
    for i = 1, #recipients do if recipients[i] == address then return true end end
    return false
end
local function Ready()
    return M.active and M.mailOpen and not NS.InCombat() and MailFrame:IsShown()
        and SendMailFrame:IsShown() and not S.QoLItemUseWindow("MailFrame") and Data.EmptyCursor()
end

local function Attachments()
    local counts, slots, complete = {}, 0, true
    for i = 1, 12 do
        local name, id, _, count = GetSendMailItem(i)
        if not S.Public(name) or not S.Public(id) or not S.Public(count) then complete = false
        elseif name then
            if not S.Finite(id) or not S.Finite(count) or count < 1 then complete = false
            else
                counts[id], slots = (counts[id] or 0) + count, slots + 1
            end
        end
    end
    return counts, slots, complete
end

function M:Rows()
    local rows = {}
    if not self.preview then
        local entries = Entries()
        for i = 1, #entries do
            local entry = entries[i]
            rows[i] = { key = i, index = i, label = entry.name, search = entry.name .. " " .. entry.recipient,
                detail = S.Text("Recipient: %s\nSubject: %s"):format(entry.recipient, entry.subject) }
        end
        return rows
    end
    local entry = Selected()
    if not entry then return rows end
    local _, bags, complete = Data.Bags()
    local attached = Ready() and Attachments() or {}
    for id, quantity in pairs(Lists.Quantities(entry.items) or {}) do
        rows[#rows + 1] = { key = id, itemID = id, quantity = quantity, search = Data.Name(id) .. " " .. id,
            label = S.Text("%s — wanted %d, attached %d, in bags %d"):format(Data.Name(id), quantity, attached[id] or 0, bags[id] or 0),
            detail = S.Text("Attach selected adds at most one stack and never exceeds the template quantity. Review attachments and send manually.") }
        if not complete then
            rows[#rows].label = S.Text("%s — need %d, bag quantity unavailable"):format(Data.Name(id), quantity)
            rows[#rows].detail = S.Text("Some bag slots are unavailable. Refresh outside combat before using a missing amount.")
        end
    end
    table.sort(rows, function(a, b) return a.label < b.label end)
    return rows
end

local function EditField(field, title, limit)
    local entry = Selected()
    if not entry then return end
    local before, index = M.config.templates, M.selected
    UI.Text(M, title, entry[field], limit, function(_, text)
        local entries = Entries()
        entries[index][field] = text
        return Save(entries)
    end, function() return M.config.templates == before end)
end

local function Recipient(self, _, window)
    local before, index = M.config.templates, M.selected
    local profile = NS.DB
    if not index then return end
    S.ContextMenu(window, function(_, menu)
        menu:CreateTitle(S.Text("Choose your character"))
        local recipients = S.InventoryArchive:Recipients()
        if #recipients == 0 then menu:CreateTitle(S.Text("Visit an alt with Inventory archive or Mail recipients enabled first.")) end
        for i = 1, #recipients do
            local address = recipients[i]
            menu:CreateButton(address, function()
                if not self.active or NS.InCombat() or NS.DB ~= profile or self.config.templates ~= before then return end
                local entries = Entries()
                entries[index].recipient = address
                Save(entries)
            end)
        end
    end)
end

local function EditItems()
    if not Selected() then return end
    local index = M.selected
    local before = M.config.templates
    UI.Quantities(M, "Mail materials", function()
        local entries = Entries()
        return entries[index] and Lists.Quantities(entries[index].items) or {}
    end, function(values)
        if M.config.templates ~= before then return false end
        local entries, text = Entries(), Lists.EncodeQuantities(values)
        if not entries[index] or not text then return false end
        entries[index].items = text
        before = Lists.EncodeTemplates(entries)
        return before and Save(entries) or false
    end, function() M:Open() end, function() return M.config.templates == before end)
end

local function Status(text)
    M.status = S.Text(text)
    S.ToolListWindow.Refresh(M)
end

function M:Fill()
    local entry = Selected()
    if not Ready() or not entry or not OwnRecipient(entry.recipient) then
        Status("Open Send Mail and choose one of your recorded characters.")
        return
    end
    local _, slots, complete = Attachments()
    if not complete or slots > 0 then
        Status("Start with an empty mail before applying a template address.")
        return
    end
    local address, subject = SendMailNameEditBox:GetText(), SendMailSubjectEditBox:GetText()
    if not S.Public(address) or not S.Public(subject) or type(address) ~= "string" or type(subject) ~= "string"
        or address ~= "" and address ~= entry.recipient or subject ~= "" and subject ~= entry.subject then
        Status("Clear the existing recipient and subject before applying this template.")
        return
    end
    SendMailNameEditBox:SetText(entry.recipient)
    SendMailSubjectEditBox:SetText(entry.subject)
    Status("Address and subject filled. Select materials to attach; sending remains manual.")
end

function M:Attach(row)
    local entry = Selected()
    if not row or not Ready() or not entry or not OwnRecipient(entry.recipient) then return end
    local address = S.PublicText(SendMailNameEditBox:GetText())
    if address ~= entry.recipient then
        Status("Apply the template address first. Check the recipient before attaching items.")
        return
    end
    local counts, slots, complete = Attachments()
    if not complete or slots >= 12 then
        Status("Mail attachment slots are full or unavailable.")
        return
    end
    local need = (Lists.Quantities(entry.items) or {})[row.itemID]
    if not need then return end
    need = need - (counts[row.itemID] or 0)
    if need <= 0 then
        Status("The requested quantity is already attached.")
        return
    end
    local items = Data.Bags()
    for i = 1, #items do
        local item = items[i]
        if item.itemID == row.itemID and not item.locked and not item.bound and not item.quest and not item.hasLoot then
            local amount = math.min(item.count, need)
            local ok
            if amount < item.count then ok = S.QoLRestrictedCall(C_Container.SplitContainerItem, item.bag, item.slot, amount)
            else
                ok = S.QoLRestrictedCall(C_Container.PickupContainerItem, item.bag, item.slot)
            end
            if not ok then
                Status("Attachment preparation stopped. Check your cursor.")
                return
            end
            local kind, id = GetCursorInfo()
            if not S.Public(kind) or kind ~= "item" or not S.Finite(id) or id ~= item.itemID then
                Status("Attachment preparation stopped. Check your cursor.")
                return
            end
            if S.QoLRestrictedCall(ClickSendMailItemButton) then Status("Attachment requested. Review the mail before sending.")
            else
                Status("Attachment preparation stopped. Check your cursor.")
            end
            return
        end
    end
    Status("No unlocked, unbound, non-quest stack is available in your bags.")
end

local function NewTemplate(self)
    UI.Text(self, "New mail template", "", 64, function(_, text)
        local entries = Entries()
        if #entries >= 24 then return false, S.Text("This list is full.") end
        entries[#entries + 1] = { name = text, subject = text, recipient = "", items = "" }
        self.selected = #entries
        return Save(entries)
    end)
end

local function Actions(self)
    if self.preview then
        return {
            { label = "Fill address", run = M.Fill },
            { label = "Attach selected", run = M.Attach, enabled = function(_, row) return row ~= nil and Ready() end },
            { label = "Back", run = function() self.preview = false self:Open() end },
        }
    end
    return {
        { label = "New template", run = NewTemplate },
        { label = "Recipient", run = Recipient, enabled = function() return Selected() ~= nil end },
        { label = "Subject", run = function() EditField("subject", "Mail subject", 120) end, enabled = function() return Selected() ~= nil end },
        { label = "Materials", run = EditItems, enabled = function() return Selected() ~= nil end },
        { label = "Preview", run = function() self.preview = true self:Open() end, enabled = function() return Selected() ~= nil end },
        { label = "Delete", run = function()
            local _, entries = Selected()
            if self.selected then table.remove(entries, self.selected) self.selected = nil Save(entries) end
        end, enabled = function() return Selected() ~= nil end },
    }
end

function M:Open()
    S.ToolListWindow.Open(self, { title = self.preview and "Mail preview" or "Mail templates", rows = M.Rows,
        help = "Choose your alt, subject and material quantities. Apply and attach from the Send Mail tab, then review and send manually.",
        empty = "Create a template, choose a recorded alt and add materials. Visit your alts first if the recipient list is empty.",
        status = function() return M.status end,
        menu = function(self, row)
            if not self.preview then self.selected = row.index EditField("name", "Name", 64) end
        end,
        onSelect = function(self, row) if not self.preview then self.selected = row.index end end,
        actions = Actions(self) })
end
function M:Refresh() S.ToolListWindow.Refresh(self) end
local function Event(self, event)
    if event == "MAIL_SHOW" then self.mailOpen = true end
    if event == "MAIL_CLOSED" then self.mailOpen = false self.status = "" end
    S.ToolListWindow.Refresh(self)
end
function M:Enable()
    self.mailOpen = MailFrame:IsShown()
    self.context:Event("MAIL_SHOW", Event)
    self.context:Event("MAIL_CLOSED", Event)
    self.context:Event("MAIL_SEND_INFO_UPDATE", Event)
    self.context:Event("BAG_UPDATE_DELAYED", Event)
end
function M:Disable() self.mailOpen = false S.ToolListWindow.Close(self) end
S.Install("mailTemplates", M)
