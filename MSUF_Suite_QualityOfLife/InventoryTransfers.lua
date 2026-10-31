local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end
local Data, M = S.InventoryData, { direction = "deposit", status = "" }

local function Ready()
    return M.active and M.bankOpen and not NS.InCombat() and BankFrame:IsShown()
        and not S.QoLItemUseWindow("BankFrame") and Data.EmptyCursor()
end

local function Stop(reason)
    M.pending = nil
    if M.context then M.context:Cancel(Stop) end
    M.status = S.Text(type(reason) == "string" and reason or "Transfer stopped. Review the bank before trying again.")
    S.ToolListWindow.Refresh(M)
end

local function BankType()
    if not Ready() then return end
    local bankType = BankFrame:GetActiveBankType()
    if not S.Finite(bankType) then return end
    local bags = Data.BankBags(bankType)
    if bags then return bankType, bags end
end

function M:Rows()
    local bankType, banks = BankType()
    if not bankType then return {} end
    local items = self.direction == "withdraw" and Data.Scan(banks) or Data.Bags()
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

function M:Move(row)
    if not row or self.pending or not Ready() then return end
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
    local destination = self.direction == "withdraw" and { 0, 1, 2, 3, 4, 5 } or banks
    if not HasSpace(destination) then
        Stop("No free destination slot is known. Free a slot or merge stacks manually.")
        return
    end
    if self.direction == "deposit" then
        local location = ItemLocation:CreateFromBagAndSlot(item.bag, item.slot)
        local allowed = C_Bank.IsItemAllowedInBankType(bankType, location)
        if not S.Public(allowed) or allowed ~= true then
            Stop("This item cannot enter the selected bank.")
            return
        end
        if bankType == Enum.BankType.Account then
            local refundable = C_Item.CanBeRefunded(location)
            if not S.Public(refundable) or refundable ~= false then
                Stop("Move refundable items through Blizzard's bank confirmation.")
                return
            end
        end
    end
    self.pending = { bag = item.bag, slot = item.slot, guid = row.guid, count = item.count, bankType = bankType }
    self.status = S.Text("Waiting for the bank to confirm the transfer.")
    self.context:After(5, Stop)
    local ok
    if self.direction == "deposit" then ok = S.QoLRestrictedCall(C_Container.UseContainerItem, item.bag, item.slot, nil, bankType, false)
    else
        ok = S.QoLRestrictedCall(C_Container.UseContainerItem, item.bag, item.slot)
    end
    if not ok then Stop() end
    S.ToolListWindow.Refresh(self)
end

local function Event(self, event)
    if event == "BANKFRAME_OPENED" then
        self.bankOpen = true self.status = ""
        return
    end
    if event == "BANKFRAME_CLOSED" or event == "PLAYER_REGEN_DISABLED" then
        if event == "BANKFRAME_CLOSED" then self.bankOpen = false end
        Stop()
        return
    end
    if not self.pending then
        S.ToolListWindow.Refresh(self)
        return
    end
    if not Ready() then
        Stop()
        return
    end
    local pending = self.pending
    local bankType = BankType()
    if bankType ~= pending.bankType then
        Stop()
        return
    end
    if event == "BAG_UPDATE_DELAYED" then
        local item = Data.Item(pending.bag, pending.slot)
        if not item or S.QoLItemGUID(pending.bag, pending.slot) ~= pending.guid or item.count < pending.count then
            Stop("Transfer confirmed. Select the next stack when ready.")
        end
    end
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
    self.context:Event("BANKFRAME_OPENED", Event)
    self.context:Event("BANKFRAME_CLOSED", Event)
    self.context:Event("BAG_UPDATE_DELAYED", Event)
    self.context:Event("CURSOR_CHANGED", Event)
    self.context:Event("PLAYER_REGEN_DISABLED", Event, { inCombat = true })
end
function M:Disable() Stop() self.bankOpen = false S.ToolListWindow.Close(self) end
S.Install("bankTransfer", M)
