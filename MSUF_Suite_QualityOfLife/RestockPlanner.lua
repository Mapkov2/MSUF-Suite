local _, P = ...
local NS, S = P.NS, P.Suite
local Data, Lists, M = S.InventoryData, NS.InventoryLists, {}

function M:Rows()
    local _, bags, complete = Data.Bags()
    local rows = Data.QuantityRows(Lists.Quantities(self.config.targets) or {}, bags)
    for i = 1, #rows do
        local row = rows[i]
        local missing = math.max(0, row.quantity - (bags[row.itemID] or 0))
        local bank, bankAt, account, accountAt = S.InventoryArchive:Supply(row.itemID)
        row.label = S.Text("%s — missing %d"):format(Data.Name(row.itemID), missing)
        local knownBank = bankAt and S.Text("%d, recorded %s"):format(bank, date("%Y-%m-%d %H:%M", bankAt)) or S.Text("Not recorded")
        local knownAccount = accountAt and S.Text("%d, recorded %s"):format(account, date("%Y-%m-%d %H:%M", accountAt)) or S.Text("Not recorded")
        row.detail = S.Text("Target: %d · In bags: %d · Missing: %d\nBank: %s\nWarband bank: %s")
            :format(row.quantity, bags[row.itemID] or 0, missing, knownBank, knownAccount)
        if not complete then
            row.label = S.Text("%s — bag quantity unavailable"):format(Data.Name(row.itemID))
            row.detail = S.Text("Some bag slots are unavailable. Refresh outside combat before using a missing amount.")
        end
    end
    return rows
end

function M:Edit()
    S.InventoryToolsUI.Quantities(self, "Stock targets", function() return Lists.Quantities(M.config.targets) or {} end,
        function(values)
            local text = Lists.EncodeQuantities(values)
            return text and S.Set(M.id, "targets", text) or false
        end, function() M:Open() end)
end

function M:Open()
    S.ToolListWindow.Open(self, { title = "Stock targets", rows = M.Rows,
        help = "Missing amounts use your current bags. Bank amounts show the last archive snapshot and may have changed.",
        empty = "No stock targets yet. Choose Edit targets to add your consumables or materials.",
        actions = { { label = "Edit targets", run = M.Edit }, { label = "Refresh", run = function() S.ToolListWindow.Refresh(M) end } } })
end
function M:Refresh() S.ToolListWindow.Refresh(self) end
function M:Enable() self.context:Event("BAG_UPDATE_DELAYED", M.Refresh) end
function M:Disable() S.ToolListWindow.Close(self) end
S.Install("restockPlanner", M)
