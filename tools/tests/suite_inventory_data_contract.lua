local root = assert(arg[1], "repository root required")
local F = dofile(root .. "/tools/tests/suite_inventory_tools_fixture.lua")
local E = F.New(root)
local S, NS = E.S, E.NS
local Data, UI, Lists = S.InventoryData, S.InventoryToolsUI, NS.InventoryLists
local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function OpenList(owner)
    local window
    for _, frame in ipairs(E.frames) do if frame.owner == owner and frame.actions then window = frame end end
    return assert(window, "no list window is open for the owner")
end

-- Uncached item names: asked for once, repainted in the open list on arrival.
local cached, requested = {}, {}
C_Item.GetItemNameByID = function(id) return cached[id] end
C_Item.RequestLoadItemDataByID = function(id) requested[id] = (requested[id] or 0) + 1 end
local create = S.CreateFrame
S.CreateFrame = function(...)
    local frame = create(...)
    -- The fixture frame has no UnregisterEvent.
    function frame:UnregisterEvent(event) self.events[event] = nil end
    return frame
end
local due
S.Debounce = function(_, fn) return { Request = function() due = fn end } end
local restock = E:Start("restockPlanner", { targets = "555=2" })
restock:Open()
local list = OpenList(restock)
eq(list.items[1].label:find("Item 555", 1, true) ~= nil, true, "uncached item shows its number")
eq(requested[555], 1, "uncached item requested")
S.ToolListWindow.Refresh(restock); restock:Rows(); Data.Name(555); Data.QuantityRows({ [555] = 1 })
eq(requested[555], 1, "item data asked for again")
local listener
for _, frame in ipairs(E.frames) do if frame.events.GET_ITEM_INFO_RECEIVED then listener = frame end end
assert(listener, "nothing listened for the item data")
listener.scripts.OnEvent(listener, "GET_ITEM_INFO_RECEIVED", 999, true)
eq(due, nil, "an unrelated item arrived and repainted the list")
eq(listener.events.GET_ITEM_INFO_RECEIVED, true, "an unrelated item ended the wait")
cached[555] = "Moon Cloth"
listener.scripts.OnEvent(listener, "GET_ITEM_INFO_RECEIVED", 555, true)
eq(list.items[1].label:find("Moon Cloth", 1, true), nil, "the repaint ran inside the event")
eq(listener.events.GET_ITEM_INFO_RECEIVED, nil, "the event stayed registered with nothing outstanding")
due()
eq(list.items[1].label:find("Moon Cloth", 1, true) ~= nil, true, "the open list kept the placeholder")
eq(requested[555], 1, "arrived item asked for again")

-- A full list refuses a new item with its own message and stays open.
local lines = {}
for i = 1, 200 do lines[i] = i .. "=1" end
local store = table.concat(lines, "\n")
local owner = { active = true }
UI.Quantities(owner, "Targets", function() return Lists.Quantities(store) or {} end, function(values)
    local text = Lists.EncodeQuantities(values)
    if not text then return false end
    store = text
    return true
end, function() end)
list = OpenList(owner)
list.actions[1]:Click()
list.actions[2]:Click()
local save, editor
for _, frame in ipairs(E.frames) do
    if frame.text == "Save" then save = frame end
    if frame.input and frame.error then editor = frame end
end
editor.input:SetText("201"); save:Click()
editor.input:SetText("1"); save:Click()
eq(editor.error:GetText(), "This list is full.", "a full list gave no message")
eq(editor:IsShown(), true, "the editor closed instead of showing the message")
save:Click()
eq(editor:IsShown(), true, "the editor closed on the second attempt")
S.ToolListWindow.Refresh(owner)
eq(list:IsShown(), true, "a refused save closed the list")

-- A refusal that comes from the saver keeps the list open too.
local accept = false
UI.Quantities(owner, "Targets", function() return Lists.Quantities(store) or {} end, function() return accept end, function() end)
list = OpenList(owner)
list.buttons[1]:Click()
list.actions[3]:Click()
S.ToolListWindow.Refresh(owner)
eq(list:IsShown(), true, "a refusing saver closed the list")
print("inventory data: " .. checks .. " behavior checks")
