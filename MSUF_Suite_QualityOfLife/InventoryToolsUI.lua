local _, P = ...
local NS, S = P.NS, P.Suite
local UI = {}
S.InventoryToolsUI = UI

function UI.Number(owner, title, value, save, valid)
    S.ToolListWindow.Edit(owner, { title = title, label = "Enter a whole quantity from 1 to 99,999.", text = tostring(value or 1),
        maxBytes = 5, valid = valid, onSave = function(self, text)
            local count = tonumber(text)
            if not count or count % 1 ~= 0 or count < 1 or count > 99999 then return false, S.Text("Enter a whole quantity from 1 to 99,999.") end
            return save(self, count)
        end })
end

function UI.Text(owner, title, value, limit, save, valid)
    S.ToolListWindow.Edit(owner, { title = title, text = value or "", maxBytes = limit or 64, valid = valid,
        onSave = function(self, text)
            text = text:gsub("[\r\n]", " ")
            if not text:find("%S") then return false, S.Text("Enter a name.") end
            return save(self, text)
        end })
end

function UI.PickItem(owner, pick, back, valid)
    local items = S.InventoryData.Bags()
    local rows, seen = {}, {}
    for i = 1, #items do
        local item = items[i]
        if not seen[item.itemID] then
            seen[item.itemID] = true
            rows[#rows + 1] = { key = item.itemID, itemID = item.itemID, label = item.name, icon = item.icon,
                search = item.name .. " " .. item.itemID, detail = S.Text("Choose this item to add it to your list.") }
        end
    end
    table.sort(rows, function(a, b) return a.label < b.label end)
    S.ToolListWindow.Open(owner, { title = "Choose an item", help = "Search your bags by name. You can also enter an item link or ID.",
        empty = "No items found in your bags. Enter an item link or ID to add an item.", rows = function() return rows end, valid = valid,
        actions = {
            { label = "Choose item", enabled = function(_, row) return row ~= nil end,
                run = function(self, row) pick(self, row.itemID) end },
            { label = "Item link or ID", run = function(self)
                S.ToolListWindow.Edit(self, { title = "Item link or ID", label = "Paste an item link or enter its item ID.", maxBytes = 1024, valid = valid,
                    onSave = function(module, text)
                        local id = tonumber(text:match("item:(%d+)")) or tonumber(text)
                        if not id or id % 1 ~= 0 or id < 1 or id > 9999999 then return false, S.Text("Enter a valid item link or ID.") end
                        pick(module, id)
                    end })
            end },
            { label = "Back", run = back },
        } })
end

function UI.Quantities(owner, title, get, set, back, valid)
    local baseline = NS.InventoryLists.EncodeQuantities(get())
    local function Valid()
        return (not valid or valid()) and NS.InventoryLists.EncodeQuantities(get()) == baseline
    end
    -- set(values) may refresh this window before it returns, so the new
    -- baseline has to be in place by then; a refusal gives the old one back.
    local function Store(values)
        if not Valid() then return false end
        local encoded = NS.InventoryLists.EncodeQuantities(values)
        if not encoded then return false end
        local previous = baseline
        baseline = encoded
        local saved = set(values) or false
        if not saved then baseline = previous end
        return saved
    end
    local function Open()
        S.ToolListWindow.Open(owner, { title = title, valid = Valid,
            help = "Add items from your bags, then choose the quantity for each item.",
            empty = "Your list is empty. Choose Add item to begin.",
            rows = function() local _, counts = S.InventoryData.Bags() return S.InventoryData.QuantityRows(get(), counts) end,
            actions = {
                { label = "Add item", run = function(self)
                    UI.PickItem(self, function(module, id)
                        UI.Number(module, "Item quantity", get()[id] or 1, function(_, count)
                            local values = get()
                            values[id] = count
                            if Store(values) == false then return false, S.Text("This list is full.") end
                            Open()
                        end, Valid)
                    end, Open, Valid)
                end },
                { label = "Quantity", enabled = function(_, row) return row ~= nil end, run = function(self, row)
                    local id = row.itemID
                    UI.Number(self, "Item quantity", row.quantity, function(_, count)
                        local values = get()
                        values[id] = count
                        return Store(values)
                    end, Valid)
                end },
                { label = "Remove", enabled = function(_, row) return row ~= nil end, run = function(_, row)
                    local values = get()
                    values[row.itemID] = nil
                    Store(values)
                end },
                { label = "Back", run = back or function() S.ToolListWindow.Close(owner) end },
            } })
    end
    Open()
end
