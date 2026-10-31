local _, P = ...
local NS, S = P.NS, P.Suite
local Data, M = S.InventoryData, {}
local SCOPES = { "bags", "bank" }
S.InventoryArchive = M

local function Store()
    if type(NS.RootDB) ~= "table" then return end
    if type(NS.RootDB.suiteInventoryArchive) ~= "table" then
        NS.RootDB.suiteInventoryArchive = { characters = {}, account = {} }
    end
    local store = NS.RootDB.suiteInventoryArchive
    if type(store.characters) ~= "table" then store.characters = {} end
    if type(store.account) ~= "table" then store.account = {} end
    return store
end

-- A character recorded in this region: what the window lists, the tooltips
-- count and the mail templates offer as a recipient.
local function Archived(record, region)
    return type(record) == "table" and record.region == region and type(record.address) == "string"
end

local function Snapshot(bags)
    local _, counts, complete = Data.Scan(bags)
    local now = GetServerTime()
    if not complete or not S.Finite(now) then return nil end
    return { counts = counts, at = now }
end

local function Prune(store, current)
    local records = {}
    for guid, row in pairs(store.characters) do
        if type(row) == "table" and guid ~= current then records[#records + 1] = { guid = guid, at = row.at or 0 } end
    end
    table.sort(records, function(a, b) return a.at > b.at end)
    for i = M.config.characters, #records do store.characters[records[i].guid] = nil end
end

local function Capture()
    if not M.active or NS.InCombat() then return end
    local guid, address, region = Data.CurrentCharacter()
    local store = Store()
    if not guid or not store then return end
    local row = store.characters[guid]
    if type(row) ~= "table" then row = {} store.characters[guid] = row end
    row.address, row.region = address, region
    local bags = Snapshot({ 0, 1, 2, 3, 4, 5 })
    if bags then row.bags, row.at = bags, bags.at end
    if M.bankOpen then
        local characterBags = Data.BankBags(Enum.BankType.Character)
        local accountBags = Data.BankBags(Enum.BankType.Account)
        if characterBags then row.bank = Snapshot(characterBags) or row.bank end
        if accountBags then store.account[region] = Snapshot(accountBags) or store.account[region] end
    end
    Prune(store, guid)
    S.ToolListWindow.Refresh(M)
end

local function Stamp(snapshot)
    return S.Text("Recorded %s"):format(date("%Y-%m-%d %H:%M", snapshot.at))
end

local function AddRows(rows, owner, scope, snapshot, query)
    if type(snapshot) ~= "table" or type(snapshot.counts) ~= "table" or not S.Finite(snapshot.at) then return end
    for id, count in pairs(snapshot.counts) do
        if #rows >= 10000 then return end
        if S.Finite(id) and S.Finite(count) and id > 0 and count > 0 then
            local name = Data.Name(id)
            local search = name .. " " .. id .. " " .. owner .. " " .. S.Text(scope)
            if not query or query == "" or search:lower():find(query, 1, true) then
                rows[#rows + 1] = { key = owner .. ":" .. scope .. ":" .. id, itemID = id,
                    label = S.Text("%s × %d — %s (%s)"):format(name, count, owner, S.Text(scope)),
                    detail = Stamp(snapshot), search = search }
            end
        end
    end
end

function M:Rows(query)
    local rows, store = {}, Store()
    local _, _, region = Data.CurrentCharacter()
    if not store or not region then return rows end
    for _, record in pairs(store.characters) do
        if Archived(record, region) then
            AddRows(rows, record.address, "Bags", record.bags, query)
            AddRows(rows, record.address, "Bank", record.bank, query)
        end
    end
    AddRows(rows, S.Text("Warband"), "Warband bank", store.account[region], query)
    table.sort(rows, function(a, b) return a.label < b.label end)
    return rows
end

function M:Supply(id)
    local store, guid, _, region = Store(), Data.CurrentCharacter()
    if not store or not guid then return 0, nil, 0, nil end
    local own = store.characters[guid]
    local bank = type(own) == "table" and own.bank
    local account = store.account[region]
    local bankCount = type(bank) == "table" and type(bank.counts) == "table" and bank.counts[id] or 0
    local accountCount = type(account) == "table" and type(account.counts) == "table" and account.counts[id] or 0
    return S.Finite(bankCount) and bankCount or 0, bank and S.Finite(bank.at) and bank.at or nil,
        S.Finite(accountCount) and accountCount or 0, account and S.Finite(account.at) and account.at or nil
end

function M:Recipients()
    local records, result = Store(), {}
    local guid, _, region = Data.CurrentCharacter()
    if not records or not guid then return result end
    local seen = {}
    for id, record in pairs(records.characters) do
        if id ~= guid and Archived(record, region) then
            seen[record.address] = true
        end
    end
    for id, record in pairs(NS.RootDB.suiteMailRecipients or {}) do
        if id ~= guid and type(record) == "table" and record.region == region
            and type(record.name) == "string" and type(record.realm) == "string" then seen[record.name .. "-" .. record.realm] = true end
    end
    for address in pairs(seen) do result[#result + 1] = address end
    table.sort(result)
    return result
end

local function Tooltip(tooltip, data)
    if not M.active or not M.config.tooltips or not S.Public(data) or type(data) ~= "table" or not S.Finite(data.id) then return end
    local store, _, _, region = Store(), Data.CurrentCharacter()
    if not store or not region then return end
    local shown = 0
    for _, record in pairs(store.characters) do
        if shown >= 10 then break end
        if Archived(record, region) then
            for _, scope in ipairs(SCOPES) do
                local snapshot = record[scope]
                local count = type(snapshot) == "table" and type(snapshot.counts) == "table" and snapshot.counts[data.id]
                if shown < 10 and S.Finite(count) and count > 0 and S.Finite(snapshot.at) then
                    S.TooltipLines.Line(tooltip, S.Text("%s (%s)"):format(record.address, S.Text(scope == "bags" and "Bags" or "Bank")),
                        S.Text("%d — %s"):format(count, Stamp(snapshot)))
                    shown = shown + 1
                end
            end
        end
    end
    local account = store.account[region]
    local count = type(account) == "table" and type(account.counts) == "table" and account.counts[data.id]
    if S.Finite(count) and count > 0 and S.Finite(account.at) then
        S.TooltipLines.Line(tooltip, "Warband bank", S.Text("%d — %s"):format(count, Stamp(account)))
    end
end

-- Asks first, then removes: remove(store) runs only if the archive is still
-- on, out of combat and on the same profile when the player answers.
local function ConfirmForget(text, address, remove)
    local profile = NS.DB
    S.Confirm("suite-archive-forget", { text = text, text_arg1 = address, callback = function()
        local store = Store()
        if not M.active or NS.InCombat() or NS.DB ~= profile or not store then return end
        remove(store)
        S.ToolListWindow.Refresh(M)
    end })
end

-- The other characters recorded in this region, by address.
local function Others()
    local guid, _, region = Data.CurrentCharacter()
    local store, list = Store(), {}
    if not guid or not store then return list end
    for id, record in pairs(store.characters) do
        if id ~= guid and Archived(record, region) then list[#list + 1] = { guid = id, address = record.address } end
    end
    table.sort(list, function(a, b) return a.address < b.address end)
    return list
end

-- Recording goes on while the archive is on, so the current character comes
-- back with the next bag change. Every character is treated alike: forgetting
-- removes what is stored, and turning the archive off stops recording.
local function ForgetCurrent()
    local guid, address = Data.CurrentCharacter()
    if not guid then return end
    ConfirmForget(S.Text("Forget everything recorded for %s? While Inventory archive is on, it is recorded again the next time your bags change."),
        address, function(store) store.characters[guid] = nil end)
end

local function ForgetOther(_, _, window)
    S.ContextMenu(window, function(_, menu)
        menu:CreateTitle(S.Text("Forget which character?"))
        for _, other in ipairs(Others()) do
            menu:CreateButton(other.address, function()
                ConfirmForget(S.Text("Forget everything recorded for %s? Visit them again with Inventory archive on to record them anew."),
                    other.address, function(store) store.characters[other.guid] = nil end)
            end)
        end
    end)
end

local function HasWarband()
    local store = Store()
    local _, _, region = Data.CurrentCharacter()
    return store ~= nil and region ~= nil and store.account[region] ~= nil
end

local function ForgetWarband()
    local _, _, region = Data.CurrentCharacter()
    if not region then return end
    ConfirmForget(S.Text("Forget the recorded warband bank? Opening your bank with Inventory archive on records it again."),
        nil, function(store) store.account[region] = nil end)
end

local ACTIONS = {
    { label = "Refresh current", run = Capture },
    { label = "Forget current", run = ForgetCurrent },
    { label = "Forget a character", run = ForgetOther, enabled = function() return #Others() > 0 end },
    { label = "Forget warband bank", run = ForgetWarband, enabled = HasWarband },
}

function M:Open()
    Capture()
    S.ToolListWindow.Open(self, { title = "Inventory archive", rows = M.Rows,
        help = "These are dated snapshots. Visit each character and open their bank to refresh its recorded contents.",
        empty = "No recorded items match. Visit another character with Inventory archive enabled to add its bags.",
        actions = ACTIONS })
end

local function Event(self, event)
    if event == "BANKFRAME_CLOSED" then
        self.bankOpen = false
        return
    end
    if event == "BANKFRAME_OPENED" then self.bankOpen = true end
    self.job:Request()
end

function M:Enable()
    self.bankOpen = BankFrame:IsShown()
    self.job = self.context:Coalesce(.15, Capture)
    self.context:Event("BAG_UPDATE_DELAYED", Event)
    self.context:Event("BANKFRAME_OPENED", Event)
    self.context:Event("BANKFRAME_CLOSED", Event)
    self.context:Event("PLAYER_REGEN_ENABLED", Event)
    if not self.tooltip then S.TooltipLines.Add(self, "Item", Tooltip) self.tooltip = true end
    self.job:Request()
end
function M:Refresh() if self.job then self.job:Request() end end
function M:Disable()
    if self.job then self.job:Cancel() end
    self.bankOpen = false
    S.ToolListWindow.Close(self)
end
S.Install("inventoryArchive", M)
