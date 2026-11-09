local _, P = ...
local NS, S = P.NS, P.Suite
local Data, M = S.InventoryData, { direction = "deposit", status = "" }
local DEPOSIT, WITHDRAW = "deposit", "withdraw"
local QUESTION = "MSUF_SUITE_MOVE_MATCHING_BANK_STACKS"
local BANK_EVENTS = { "BAG_UPDATE_DELAYED", "CURSOR_CHANGED", "PLAYER_REGEN_DISABLED" }
-- Forever's equipped bags end before the first bank bag. The keyring is
-- deliberately outside this transfer source, and Retail has a reagent bag.
local CARRIED = NS.Client.isForever and { 0, 1, 2, 3, 4 } or { 0, 1, 2, 3, 4, 5 }
local LAST_CARRIED = CARRIED[#CARRIED]

local function Ready()
    if not M.active or not M.bankOpen or NS.InCombat() or not BankFrame:IsShown()
        or StackSplitFrame:IsShown() or S.QoLItemUseWindow("BankFrame") or not Data.EmptyCursor() then return false end
    local targeting = SpellIsTargeting()
    return S.Public(targeting) and targeting == false
end

local function Stop(reason)
    local pending = M.pending
    M.pending = nil
    if M.context then M.context:Cancel(Stop) end
    if M.preview then
        M.preview = nil
        S.HideQuestion(QUESTION)
    end
    if pending and pending.entries then
        M.status = S.Text("Bank transfer updated %d of %d requested stacks. Review your bags and bank.")
            :format(pending.updated, pending.total)
        NS.Print(M.status)
    else
        M.status = S.Text(type(reason) == "string" and reason or "Transfer stopped. Review the bank before trying again.")
    end
    S.ToolListWindow.Refresh(M)
end

local function ActiveBankType()
    if not Ready() then return end
    local bankType = BankFrame:GetActiveBankType()
    if S.Finite(bankType) and (bankType == Enum.BankType.Character or bankType == Enum.BankType.Account) then
        return bankType
    end
end

local function BankType()
    local bankType = ActiveBankType()
    if not bankType then return end
    local bags = Data.BankBags(bankType)
    if bags then return bankType, bags end
end

function M:Rows()
    local bankType, banks = BankType()
    if not bankType then return {} end
    local items = Data.Scan(self.direction == WITHDRAW and banks or CARRIED)
    local rows = {}
    for i = 1, #items do
        local item = items[i]
        if not item.locked then
            local guid = S.QoLItemGUID(item.bag, item.slot)
            if guid then
                rows[#rows + 1] = { key = guid, guid = guid, itemID = item.itemID, item = item, bankType = bankType,
                    label = S.Text("%s × %d"):format(item.name, item.count), icon = item.icon, search = item.search,
                    detail = S.Text("One click moves this complete stack. The destination is the bank tab type currently selected in Blizzard's bank.") }
            end
        end
    end
    return rows
end

local function HasSpace(bags)
    for i = 1, #bags do
        local free = C_Container.GetContainerNumFreeSlots(bags[i])
        if S.Finite(free) and free > 0 then return true end
    end
    return false
end

local function DepositRefusal(item, bankType)
    local location = ItemLocation:CreateFromBagAndSlot(item.bag, item.slot)
    local allowed = C_Bank.IsItemAllowedInBankType(bankType, location)
    if not S.Public(allowed) or allowed ~= true then return "This item cannot enter the selected bank." end
    if bankType == Enum.BankType.Account then
        local refundable = C_Item.CanBeRefunded(location)
        if not S.Public(refundable) or refundable ~= false then
            return "Move refundable items through Blizzard's bank confirmation."
        end
    end
end

local function Use(item, direction, bankType)
    if direction == DEPOSIT then
        return S.QoLRestrictedCall(C_Container.UseContainerItem, item.bag, item.slot, nil, bankType, false)
    end
    return S.QoLRestrictedCall(C_Container.UseContainerItem, item.bag, item.slot)
end

function M:Move(row)
    if not row or self.pending or not Ready() then return end
    if self.preview then Stop() end
    local bankType, banks = BankType()
    if bankType ~= row.bankType then
        Stop("The bank selection changed. Review the preview again.")
        return
    end
    local item = Data.Item(row.item.bag, row.item.slot)
    if not item or item.locked or item.itemID ~= row.itemID or item.count ~= row.item.count
        or S.QoLItemGUID(item.bag, item.slot) ~= row.guid then
            Stop("The item changed. Review the preview again.")
            return
        end
    local destination = self.direction == WITHDRAW and CARRIED or banks
    if not HasSpace(destination) then
        Stop("No free destination slot is known. Free a slot or merge stacks manually.")
        return
    end
    local refusal = self.direction == DEPOSIT and DepositRefusal(item, bankType)
    if refusal then
        Stop(refusal)
        return
    end
    self.pending = { bag = item.bag, slot = item.slot, itemID = item.itemID, guid = row.guid, count = item.count, bankType = bankType }
    self.status = S.Text("Waiting for the bank to confirm the transfer.")
    self.context:After(5, Stop)
    if not Use(item, self.direction, bankType) then Stop() end
    S.ToolListWindow.Refresh(self)
end

-- Count known empty slots once per click. Reserve one per submitted stack;
-- clients may merge earlier, but never assume asynchronous moves did so.
local function BatchCapacity(bags)
    local capacity = 0
    for i = 1, #bags do
        local free = C_Container.GetContainerNumFreeSlots(bags[i])
        if S.Finite(free) and free > 0 then capacity = capacity + free end
    end
    return capacity
end

-- The visible model's rows are mutable. Snapshot only readable physical
-- slots, then match the same GUID, item and quantity again on acceptance.
local function MatchStack(expected)
    local info = C_Container.GetContainerItemInfo(expected.bag, expected.slot)
    if not S.Public(info) or type(info) ~= "table" or not S.Finite(info.itemID) or info.itemID ~= expected.itemID
        or not S.Finite(info.stackCount) or info.stackCount ~= expected.count
        or not S.Public(info.isLocked) or info.isLocked ~= false
        or not S.Public(info.isFiltered) or info.isFiltered == true
        or expected.link and S.PublicText(info.hyperlink) ~= expected.link then return end
    local guid = S.QoLItemGUID(expected.bag, expected.slot)
    if guid and (not expected.guid or expected.guid == guid) then return guid end
end

local function SourceBags(banks, direction)
    if direction == DEPOSIT then return end
    local source = {}
    for i = 1, #banks do source[banks[i]] = true end
    return source
end

local function InSource(item, source)
    return item and S.Finite(item.bag) and S.Finite(item.slot) and item.slot > 0
        and S.Finite(item.itemID) and S.Finite(item.count) and item.count > 0
        and (source and source[item.bag] or not source and item.bag >= 0 and item.bag <= LAST_CARRIED)
end

local function BatchEntries(items, direction, bankType, banks)
    local entries, seen = {}, {}
    local source = SourceBags(banks, direction)
    local capacity = BatchCapacity(source and CARRIED or banks)
    for i = 1, #items do
        if #entries >= capacity then break end
        local item = items[i]
        if InSource(item, source) then
            local guid = MatchStack(item)
            if guid and not seen[guid] and (source or not DepositRefusal(item, bankType)) then
                seen[guid] = true
                entries[#entries + 1] = { bag = item.bag, slot = item.slot, itemID = item.itemID,
                    count = item.count, link = item.link, guid = guid }
            end
        end
    end
    return entries
end

local function NoBatch()
    NS.Print(S.Text("No matching stacks can be moved with the current bank selection."))
end

local function Updated(item)
    local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
    if not S.Public(info) then return false end
    if info == nil then return true end
    if type(info) ~= "table" or not S.Finite(info.itemID) or not S.Finite(info.stackCount) then return false end
    local guid = S.QoLItemGUID(item.bag, item.slot)
    return guid and (guid ~= item.guid or info.itemID ~= item.itemID or info.stackCount < item.count)
end

local function CheckBatch(pending)
    if pending.issuing then
        pending.dirty = true
        return
    end
    local entries = pending.entries
    for i = #entries, 1, -1 do
        if Updated(entries[i]) then
            local last = #entries
            entries[i] = entries[last]
            entries[last] = nil
            pending.updated = pending.updated + 1
        end
    end
    if #entries == 0 then Stop() end
end

local function AcceptBatch(preview)
    if M.preview ~= preview then return end
    M.preview = nil
    local approved, profile = preview.entries, preview.profile
    preview.entries, preview.profile = nil, nil
    local bankType, banks = BankType()
    if NS.DB ~= profile or bankType ~= preview.bankType then
        NoBatch()
        return
    end
    local source = SourceBags(banks, preview.direction)
    local capacity = BatchCapacity(source and CARRIED or banks)
    if capacity == 0 then
        NoBatch()
        return
    end
    local entries = {}
    local pending = { entries = entries, bankType = bankType, total = #approved, updated = 0, issuing = true }
    M.pending = pending
    -- Like the single-stack action, every native call stays in the hardware
    -- callback. A refused call stops the batch. Events only observe results.
    for i = 1, #approved do
        if M.pending ~= pending or #entries >= capacity or ActiveBankType() ~= bankType then break end
        local item = approved[i]
        if InSource(item, source) and MatchStack(item) and (source or not DepositRefusal(item, bankType)) then
            if not Use(item, preview.direction, bankType) then break end
            entries[#entries + 1] = item
        end
    end
    if M.pending ~= pending then return end
    pending.issuing = false
    if #entries == 0 then
        M.pending = nil
        NoBatch()
        return
    end
    if pending.dirty then
        CheckBatch(pending)
        if M.pending ~= pending then return end
    end
    M.status = S.Text("Waiting for the bank to confirm the transfer.")
    M.context:After(5, Stop)
    S.ToolListWindow.Refresh(M)
end

function M:CanBatch()
    if self.pending then return false end
    local bankType = ActiveBankType()
    return bankType ~= nil, bankType
end

function M:Batch(items, direction)
    if self.pending or (direction ~= DEPOSIT and direction ~= WITHDRAW) then return end
    local bankType, banks = BankType()
    if not bankType then return end
    local entries = BatchEntries(items, direction, bankType, banks)
    if #entries == 0 then
        NoBatch()
        return
    end
    local preview = { entries = entries, direction = direction, bankType = bankType, profile = NS.DB }
    self.preview = preview
    S.Confirm(QUESTION, {
        text = direction == DEPOSIT and S.Text("Deposit up to %d matching stacks into the selected bank?")
            or S.Text("Withdraw up to %d matching stacks from the selected bank?"),
        text_arg1 = #entries,
        callback = function() AcceptBatch(preview) end,
        cancelCallback = function()
            if self.preview == preview then self.preview = nil end
            preview.entries, preview.profile = nil, nil
        end,
    })
end

local function Event(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        Stop()
        return
    end
    if not self.pending then
        S.ToolListWindow.Refresh(self)
        return
    end
    local pending = self.pending
    if ActiveBankType() ~= pending.bankType then
        Stop()
        return
    end
    if event ~= "BAG_UPDATE_DELAYED" then return end
    if pending.entries then
        CheckBatch(pending)
        return
    end
    if Updated(pending) then Stop("Transfer confirmed. Select the next stack when ready.") end
end

local function WatchBank(self)
    for i = 1, #BANK_EVENTS do
        local event = BANK_EVENTS[i]
        self.context:Event(event, Event, event == "PLAYER_REGEN_DISABLED")
    end
end

local function OpenBank(self)
    self.bankOpen = true
    WatchBank(self)
    if self.pending or self.preview then Stop() end
    self.status = ""
    S.ToolListWindow.Refresh(self)
end

local function CloseBank(self)
    self.bankOpen = false
    for i = 1, #BANK_EVENTS do self.context:RemoveEvent(BANK_EVENTS[i]) end
    Stop()
end

function M:Open()
    S.ToolListWindow.Open(self, { title = "Bank transfer preview", rows = M.Rows,
        help = "Open your bank and select its destination tab type. Search the preview, select a stack, then click Move stack.",
        empty = "Open a bank outside combat to preview available stacks. Empty the cursor and close other item windows.",
        status = function(self) return self.status end,
        filter = function(self, row, query)
            if query ~= self.query then self.query, self.rule = query, NS.InventoryRules.Compile(query) end
            if query:find("is:equipment", 1, true) then
                local equippable = C_Item.IsEquippableItem(row.itemID)
                row.item.equipLoc = S.Public(equippable) and equippable == true and "INVTYPE_EQUIPMENT" or ""
            end
            return NS.InventoryRules.Matches(self.rule, row.item)
        end,
        tabs = { { key = "deposit", label = "Deposit" }, { key = "withdraw", label = "Withdraw" } },
        currentTab = function(self) return self.direction end,
        selectTab = function(self, key) Stop() self.direction = key self.status = "" end,
        actions = {
            { label = "Move stack", run = M.Move, enabled = function(self, row) return row ~= nil and not self.pending and Ready() end },
            { label = "Refresh", run = function(self) S.ToolListWindow.Refresh(self) end },
            { label = "Filters", run = function(_, _, window)
                local presets = { { "All items", "" }, { "Junk", "quality=0" }, { "Rare equipment", "is:equipment quality=3" },
                    { "Epic equipment", "is:equipment quality=4" }, { "Unbound items", "!is:bound" }, { "Quest items", "is:quest" } }
                local profile = NS.DB
                S.ContextMenu(window, function(_, menu)
                    for i = 1, #presets do
                        local preset = presets[i]
                        menu:CreateButton(S.Text(preset[1]), function()
                            if M.active and not NS.InCombat() and NS.DB == profile and window.owner == M then window.search:SetText(preset[2]) end
                        end)
                    end
                end)
            end },
        } })
end
function M:Refresh() Stop() end
function M:Enable()
    self.bankOpen = BankFrame:IsShown()
    self.context:Event("BANKFRAME_OPENED", OpenBank)
    self.context:Event("BANKFRAME_CLOSED", CloseBank, true)
    if self.bankOpen then WatchBank(self) end
end
function M:Disable()
    CloseBank(self)
    S.ToolListWindow.Close(self)
end
S.Install("bankTransfer", M)
