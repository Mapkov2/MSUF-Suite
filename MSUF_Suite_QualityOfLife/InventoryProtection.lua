local _, P = ...
local NS, S = P.NS, P.Suite
local Lists, Data = NS.InventoryLists, S.InventoryData
local M = { items = {}, locations = {} }
local POOR = 0 -- Enum.ItemQuality.Poor: the quality native junk selling takes
S.InventoryProtection = M

function M:Prepare()
    if not self.active then return end
    self.locations, self.unknownSets, self.protectGear = {}, false, false
    if not self.config.sets then return end
    local sets = C_EquipmentSet.GetEquipmentSetIDs()
    if not S.Public(sets) or type(sets) ~= "table" or #sets > 100 then
        self.unknownSets = true
        return
    end
    -- Exact membership has no loaded native callsite on either supported client.
    -- Keep every equippable item safe whenever the player has a saved set.
    self.protectGear = #sets > 0

end

function M:IsProtected(id, bag, slot)
    if not self.active then return false end
    if self.unknownSets or self.items[id] ~= nil then return true end
    if not self.protectGear then return false end
    local equippable = C_Item.IsEquippableItem(id)
    return not S.Public(equippable) or equippable ~= false
end

-- Blizzard's native "sell all junk" cannot skip single items. It may sell a
-- protected item when the sets or a bag slot are unreadable, or when a
-- protected item is junk: Poor quality, or a quality that cannot be read.
function M:HasProtectedJunk()
    if not self.active then return false end
    self:Prepare()
    if self.unknownSets then return true end
    local items, _, complete = Data.Bags()
    if not complete then return true end
    for i = 1, #items do
        local row = items[i]
        if (row.quality == nil or row.quality == POOR) and self:IsProtected(row.itemID, row.bag, row.slot) then return true end
    end
    return false
end

function M:Open()
    S.ToolListWindow.Open(self, { title = "Never sell items",
        help = "Protect selected items and equipment sets from all Suite sale actions.",
        empty = "Your list is empty. Choose Add item to begin.", rows = function()
            local rows = Data.QuantityRows(M.items)
            for i = 1, #rows do rows[i].label = Data.Name(rows[i].itemID) end
            return rows
        end, actions = {
            { label = "Add item", run = function(owner)
                S.InventoryToolsUI.PickItem(owner, function(_, id)
                    local items = Lists.Quantities(M.config.items) or {}
                    items[id] = 1
                    local text = Lists.EncodeQuantities(items)
                    if text then S.Set(M.id, "items", text) M:Open() end
                end, function() M:Open() end)
            end },
            { label = "Remove", enabled = function(_, row) return row ~= nil end, run = function(_, row)
                local items = Lists.Quantities(M.config.items) or {}
                items[row.itemID] = nil
                S.Set(M.id, "items", Lists.EncodeQuantities(items))
            end },
        } })
end

function M:Refresh()
    self.items = Lists.Quantities(self.config.items) or {}
    self:Prepare()
    S.ToolListWindow.Refresh(self)
end
function M:Enable()
    self.context:Event("EQUIPMENT_SETS_CHANGED", M.Prepare)
    self.context:Event("BAG_UPDATE_DELAYED", M.Prepare)
    self:Refresh()
end
function M:Disable()
    self.items, self.locations, self.unknownSets = {}, {}, false
    S.ToolListWindow.Close(self)
end
S.Install("inventoryProtection", M)
