local _, P = ...
local NS, S = P.NS, P.Suite
local Data, M = S.InventoryData, {}
local SCOPES = { "bags", "bank", "mail", "auctions" }
local LABELS = { bags = "Bags", bank = "Bank", mail = "Mail", auctions = "Auction House" }
local TABS = { { key = "all", label = "All items" }, { key = "bags", label = LABELS.bags },
    { key = "bank", label = LABELS.bank }, { key = "warband", label = "Warband" },
    { key = "mail", label = LABELS.mail }, { key = "auctions", label = "Auction House" },
    { key = "guild", label = "Guild bank" } }
local MAX_MAIL_ATTACHMENTS, MAX_GUILD_SLOTS = 16, 98
local MAX_MAIL_MESSAGES, MAX_AUCTIONS, MAX_GUILD_TABS = 200, 10000, 8
S.InventoryArchive = M

local function Store()
    if type(NS.RootDB) ~= "table" then return end
    if type(NS.RootDB.suiteInventoryArchive) ~= "table" then
        NS.RootDB.suiteInventoryArchive = { characters = {}, account = {} }
    end
    local store = NS.RootDB.suiteInventoryArchive
    if type(store.characters) ~= "table" then store.characters = {} end
    if type(store.account) ~= "table" then store.account = {} end
    if type(store.guild) ~= "table" then store.guild = {} end
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

local function Forget(store, guid)
    store.characters[guid], store.guild[guid] = nil, nil
end

local function Prune(store, current)
    local records = {}
    for guid, row in pairs(store.characters) do
        if type(row) == "table" and guid ~= current then records[#records + 1] = { guid = guid, at = row.at or 0 } end
    end
    table.sort(records, function(a, b) return a.at > b.at end)
    for i = M.config.characters, #records do Forget(store, records[i].guid) end
end

local function CharacterRecord(store, guid, address, region)
    local row = store.characters[guid]
    if type(row) ~= "table" then
        row = {}
        store.characters[guid] = row
    end
    row.address, row.region = address, region
    return row
end

local function Capture()
    if not M.active or NS.InCombat() then return end
    local guid, address, region = Data.CurrentCharacter()
    local store = Store()
    if not guid or not store then return end
    local row = CharacterRecord(store, guid, address, region)
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

-- These readers consume the native window's latest complete results. They
-- never request mailbox pages, owned auctions, or guild bank tabs themselves.
local function Whole(value, limit)
    return S.Finite(value) and value >= 0 and value <= limit and value % 1 == 0
end

local function Count(counts, id, amount)
    if not Whole(id, 2147483647) or id == 0 or not Whole(amount, 2147483647) or amount == 0 then return false end
    counts[id] = (counts[id] or 0) + amount
    return true
end

local function CountMail(counts, message, attachments)
    local seen = 0
    for slot = 1, MAX_MAIL_ATTACHMENTS do
        local _, id, _, quantity, _, _, currency = GetInboxItem(message, slot)
        if not S.Public(id) or not S.Public(currency) then return false end
        if currency then
            seen = seen + 1
        elseif id then
            if not Count(counts, id, quantity) then return false end
            seen = seen + 1
        end
        if seen == attachments then return true end
    end
    return false
end

local function MailCounts()
    local loaded, total = GetInboxNumItems()
    if not Whole(loaded, MAX_MAIL_MESSAGES) or not S.Finite(total) or loaded ~= total then return end
    local counts = {}
    for message = 1, loaded do
        local _, _, _, _, _, cod, days, attachments = GetInboxHeaderInfo(message)
        if not S.Finite(days) or not S.Public(attachments) or not S.Public(cod) then return end
        attachments = attachments or 0
        if not Whole(attachments, MAX_MAIL_ATTACHMENTS) then return end
        -- Unpaid cash-on-delivery attachments are still the sender's items.
        if attachments > 0 and (cod == nil or cod == 0) and not CountMail(counts, message, attachments) then return end
    end
    return counts
end

local function AuctionCounts()
    local full = C_AuctionHouse.HasFullOwnedAuctionResults()
    if not S.Public(full) or full ~= true then return end
    local length = C_AuctionHouse.GetNumOwnedAuctions()
    if not Whole(length, MAX_AUCTIONS) then return end
    local counts = {}
    for index = 1, length do
        local auction = C_AuctionHouse.GetOwnedAuctionInfo(index)
        if not S.Public(auction) or not auction or not S.Finite(auction.status) then return end
        if auction.status == Enum.AuctionStatus.Active then
            local key = auction.itemKey
            if not S.Public(key) or not key or not Count(counts, key.itemID, auction.quantity) then return end
        end
    end
    return counts
end

local function GuildID()
    local guild = C_Club and C_Club.GetGuildClubId()
    return S.Finite(guild) and guild or S.PublicText(guild)
end

local function GuildTab()
    if not GuildBankFrame or not GuildBankFrame:IsShown() then return end
    local tab = GetCurrentGuildBankTab()
    if Whole(tab, MAX_GUILD_TABS) and tab > 0 then return tab end
end

local function GuildCounts(tab)
    local name, _, canView = GetGuildBankTabInfo(tab)
    name = S.PublicText(name)
    if not S.Public(canView) then return end
    if canView == false then return false end
    if canView ~= true or not name then return end
    local counts = {}
    for slot = 1, MAX_GUILD_SLOTS do
        local texture, quantity = GetGuildBankItemInfo(tab, slot)
        if not S.Public(texture) then return end
        if texture then
            local link = S.PublicText(GetGuildBankItemLink(tab, slot))
            local id = link and tonumber(link:match("|Hitem:(%d+)"))
            if not Count(counts, id, quantity) then return end
        end
    end
    return counts, name
end

local function ForgetDeniedGuildTabs(store, guid, region)
    local record = store.guild[guid]
    if type(record) ~= "table" or record.region ~= region or type(record.tabs) ~= "table" then return end
    local id = GuildID()
    if not id or record.id ~= id then return end
    local changed
    for tab = 1, MAX_GUILD_TABS do
        if record.tabs[tab] then
            local _, _, canView = GetGuildBankTabInfo(tab)
            if S.Public(canView) and canView == false then
                record.tabs[tab], changed = nil, true
            end
        end
    end
    return changed
end

local function RecordGuild(store, guid, region, tab, now)
    local guildID = GuildID()
    if not guildID then return end
    local name = S.PublicText((GetGuildInfo("player")))
    if not name then return end
    local counts, tabName = GuildCounts(tab)
    if counts == nil then return end
    local record = store.guild[guid]
    -- Keep these observations separate from character holdings. An alt can
    -- only browse guild tabs it was itself allowed to see during capture.
    if type(record) ~= "table" or record.id ~= guildID or record.region ~= region or type(record.tabs) ~= "table" then
        if counts == false then return end
        record = { id = guildID, region = region, tabs = {} }
        store.guild[guid] = record
    end
    record.name = name
    record.tabs[tab] = counts and { counts = counts, at = now, name = tabName } or nil
    return true
end

local function MailShown() return MailFrame and MailFrame:IsShown() end
local function AuctionsShown() return AuctionHouseFrame and AuctionHouseFrame:IsShown() end

local function CaptureLocations(self)
    local mail, auctions, guild = self.mailPending, self.auctionsPending, self.guildPending
    local permissions = self.guildPermissionsPending
    self.mailPending, self.auctionsPending, self.guildPending, self.guildPermissionsPending = nil, nil, nil, nil
    if not self.active or NS.InCombat() then return end
    local guid, address, region = Data.CurrentCharacter()
    local store, now = Store(), GetServerTime()
    if not guid or not store or not S.Finite(now) then return end
    local mailCounts = mail and MailShown() and MailCounts()
    local auctionsCounts = auctions and AuctionsShown() and AuctionCounts()
    local guildUpdated = guild and guild == GuildTab() and RecordGuild(store, guid, region, guild, now)
    local permissionsUpdated = permissions and GuildTab() and ForgetDeniedGuildTabs(store, guid, region)
    if not mailCounts and not auctionsCounts and not guildUpdated and not permissionsUpdated then return end
    if mailCounts or auctionsCounts then
        local row = CharacterRecord(store, guid, address, region)
        if mailCounts then row.mail = { counts = mailCounts, at = now } end
        if auctionsCounts then row.auctions = { counts = auctionsCounts, at = now } end
        row.at = now
        Prune(store, guid)
    end
    S.ToolListWindow.Refresh(self)
end

local function LocationEvent(self, event)
    if NS.InCombat() then return end
    if event == "MAIL_INBOX_UPDATE" and MailShown() then
        self.mailPending = true
    elseif event == "OWNED_AUCTIONS_UPDATED" and AuctionsShown() then
        self.auctionsPending = true
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        self.guildPending = GuildTab()
    elseif event == "GUILDBANK_UPDATE_TABS" and GuildTab() then
        self.guildPermissionsPending = true
    end
    if self.mailPending or self.auctionsPending or self.guildPending or self.guildPermissionsPending then self.locations:Request() end
end

local function Stamp(snapshot)
    return S.Text("Recorded %s"):format(date("%Y-%m-%d %H:%M", snapshot.at))
end

local function Recorded(snapshot)
    return type(snapshot) == "table" and type(snapshot.counts) == "table" and S.Finite(snapshot.at)
end

local function AddRows(rows, owner, scope, snapshot, query, identity)
    if not Recorded(snapshot) then return end
    local title, label = S.Text(scope), S.Text("%s × %d — %s (%s)")
    local key = (identity or owner) .. ":" .. scope .. ":"
    local suffix = query and " " .. (owner .. " " .. title):lower()
    local stamp
    for id, count in pairs(snapshot.counts) do
        if #rows >= 10000 then return end
        if S.Finite(id) and S.Finite(count) and id > 0 and count > 0 then
            local name = Data.Name(id)
            if not query or (name:lower() .. " " .. id .. suffix):find(query, 1, true) then
                stamp = stamp or Stamp(snapshot)
                rows[#rows + 1] = { key = key .. id, itemID = id,
                    label = label:format(name, count, owner, title), detail = stamp }
            end
        end
    end
end

local function AddCharacterRows(rows, record, scope, query)
    if scope ~= "all" then
        AddRows(rows, record.address, LABELS[scope], record[scope], query)
        return
    end
    for _, key in ipairs(SCOPES) do AddRows(rows, record.address, LABELS[key], record[key], query) end
end

local function AddGuildRows(rows, guild, region, query)
    if type(guild) ~= "table" or guild.region ~= region or type(guild.name) ~= "string" or type(guild.tabs) ~= "table" then return end
    local id = GuildID()
    if not id or guild.id ~= id then return end
    for tab = 1, MAX_GUILD_TABS do
        local snapshot = guild.tabs[tab]
        if Recorded(snapshot) and type(snapshot.name) == "string" then
            local name = S.Text("%s (%s)"):format(guild.name, snapshot.name)
            AddRows(rows, name, "Guild bank", snapshot, query, "guild:" .. tab)
        end
    end
end

local function BrowseStatus(owner, snapshot)
    return Recorded(snapshot) and S.Text("%s (%s)"):format(owner, Stamp(snapshot)) or owner
end

function M:Rows(query)
    local rows, store = {}, Store()
    local guid, _, region = Data.CurrentCharacter()
    self.status = nil
    if not store or not region then return rows end
    if query == "" then query = nil end
    local scope = self.scope or "all"
    local selected = self.character and store.characters[self.character]
    if not Archived(selected, region) then self.character, selected = nil, nil end
    local account, warband = store.account[region], S.Text("Warband")
    if scope == "warband" then
        self.status = BrowseStatus(warband, account)
        AddRows(rows, warband, "Warband bank", account, query)
    elseif scope == "guild" then
        self.status = S.Text("Guild bank")
        AddGuildRows(rows, store.guild[guid], region, query)
    elseif selected then
        self.status = BrowseStatus(selected.address, selected[scope])
        AddCharacterRows(rows, selected, scope, query)
    else
        self.status = S.Text("All characters")
        for _, record in pairs(store.characters) do
            if Archived(record, region) then AddCharacterRows(rows, record, scope, query) end
        end
        if scope == "all" then
            AddRows(rows, warband, "Warband bank", account, query)
            AddGuildRows(rows, store.guild[guid], region, query)
        end
    end
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

-- A shopping render visits each snapshot once. Current bags belong to the live
-- bag reader, and the region's shared bank is only included once.
local function IndexMaterials(result, wanted, owner, location, snapshot)
    if not Recorded(snapshot) then return end
    local source
    for id, count in pairs(snapshot.counts) do
        if S.Finite(id) and wanted[id] and S.Finite(count) and count > 0 then
            source = source or { owner = owner, location = location, recorded = date("%Y-%m-%d %H:%M", snapshot.at) }
            local entries = result[id]
            if not entries then
                entries = {}
                result[id] = entries
            end
            entries[#entries + 1] = { source = source, count = count }
        end
    end
end

function M:MaterialSources(wanted)
    local result = {}
    if not self.active or not next(wanted) then return result end
    local store, guid, _, region = Store(), Data.CurrentCharacter()
    if not store or not guid then return result end
    local own = store.characters[guid]
    if Archived(own, region) then IndexMaterials(result, wanted, nil, LABELS.bank, own.bank) end
    IndexMaterials(result, wanted, nil, "Warband bank", store.account[region])
    local others = {}
    for id, record in pairs(store.characters) do
        if id ~= guid and Archived(record, region) then others[#others + 1] = record end
    end
    table.sort(others, function(a, b) return a.address < b.address end)
    for i = 1, #others do
        local record = others[i]
        IndexMaterials(result, wanted, record.address, LABELS.bags, record.bags)
        IndexMaterials(result, wanted, record.address, LABELS.bank, record.bank)
    end
    return result
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
                    S.TooltipLines.Line(tooltip, S.Text("%s (%s)"):format(record.address, S.Text(LABELS[scope])),
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

-- The characters recorded in this region, by address.
local function Characters(excludeCurrent)
    local guid, _, region = Data.CurrentCharacter()
    local store, list = Store(), {}
    if not guid or not store then return list end
    for id, record in pairs(store.characters) do
        if (not excludeCurrent or id ~= guid) and Archived(record, region) then
            list[#list + 1] = { guid = id, address = record.address }
        end
    end
    table.sort(list, function(a, b) return a.address < b.address end)
    return list
end

local function HasOther()
    local guid, _, region = Data.CurrentCharacter()
    local store = Store()
    if not guid or not store then return false end
    for id, record in pairs(store.characters) do
        if id ~= guid and Archived(record, region) then return true end
    end
    return false
end

local function ChooseCharacter(owner, _, window)
    local profile = NS.DB
    local function Select(guid)
        if NS.InCombat() or NS.DB ~= profile or window.owner ~= owner or not owner.active then return end
        owner.character = guid
        if owner.scope == "warband" or owner.scope == "guild" then owner.scope = "all" end
        window.offset, window.selected = 0, nil
        S.ToolListWindow.Refresh(owner)
    end
    S.ContextMenu(window, function(_, menu)
        menu:CreateTitle(S.Text("Choose a character"))
        menu:CreateButton(S.Text("All characters"), function() Select(nil) end)
        for _, character in ipairs(Characters()) do
            local guid = character.guid
            menu:CreateButton(character.address, function() Select(guid) end)
        end
    end)
end

-- Recording goes on while the archive is on, so the current character comes
-- back with the next bag change. Every character is treated alike: forgetting
-- removes what is stored, and turning the archive off stops recording.
local function ForgetCurrent()
    local guid, address = Data.CurrentCharacter()
    if not guid then return end
    ConfirmForget(S.Text("Forget everything recorded for %s? While Inventory archive is on, it is recorded again the next time your bags change."),
        address, function(store) Forget(store, guid) end)
end

local function ForgetOther(_, _, window)
    S.ContextMenu(window, function(_, menu)
        menu:CreateTitle(S.Text("Forget which character?"))
        for _, other in ipairs(Characters(true)) do
            menu:CreateButton(other.address, function()
                ConfirmForget(S.Text("Forget everything recorded for %s? Visit them again with Inventory archive on to record them anew."),
                    other.address, function(store) Forget(store, other.guid) end)
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
    { label = "Forget a character", run = ForgetOther, enabled = HasOther },
    { label = "Forget warband bank", run = ForgetWarband, enabled = HasWarband },
    { label = "Character", run = ChooseCharacter },
}

local SPEC = { title = "Inventory archive", rows = M.Rows, tabs = TABS, actions = ACTIONS,
    help = "These are dated snapshots. Visit each character and open their bank to refresh its recorded contents.",
    empty = "No recorded items match. Visit another character with Inventory archive enabled to add its bags.",
    currentTab = function(self) return self.scope end,
    selectTab = function(self, scope) self.scope = scope end,
    status = function(self) return self.status end,
    -- Rows already limits the list to matches before allocating display entries.
    filter = function() return true end,
}

function M:Browse(scope, query)
    if not self.active or NS.InCombat() then return end
    self.character, self.scope = nil, scope or "all"
    return S.ToolListWindow.Open(self, SPEC, query)
end

function M:Open()
    Capture()
    self:Browse()
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
    self.locations = self.context:Coalesce(.15, CaptureLocations)
    self.context:Event("MAIL_INBOX_UPDATE", LocationEvent)
    self.context:Event("OWNED_AUCTIONS_UPDATED", LocationEvent)
    self.context:Event("GUILDBANKBAGSLOTS_CHANGED", LocationEvent)
    self.context:Event("GUILDBANK_UPDATE_TABS", LocationEvent)
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
    if self.locations then self.locations:Cancel() end
    self.mailPending, self.auctionsPending, self.guildPending, self.guildPermissionsPending = nil, nil, nil, nil
    self.bankOpen = false
    S.ToolListWindow.Close(self)
end
S.Install("inventoryArchive", M)
