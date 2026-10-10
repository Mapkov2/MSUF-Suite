local root = assert(arg[1])
local queries, writes, expanded, toggles = 0, 0, false, {}
local config = { currencyIDs = "1,2,3,4,5,6,7" }
local module = { active = true, config = config }
local S = { Public = function(v) return v ~= "secret" end, Finite = function(v) return type(v) == "number" end,
    Text = function(v) return v end, Set = function(_, key, value) config[key], writes = value, writes + 1 end }
local menu
local function Entry(label, select, click)
    return { label = label, select = select, click = click,
        SetEnabled = function(self, value) self.enabled = value end,
        SetResponse = function(self, value) self.response = value end }
end
MenuResponse = { Open = 1 }
MenuUtil = { CreateContextMenu = function(anchor, generator)
    menu = { entries = {}, titles = {}, SetScrollMode = function() end, CreateDivider = function() end }
    function menu:CreateTitle(label) self.titles[#self.titles + 1] = label end
    function menu:CreateCheckbox(label, select, click) local e = Entry(label, select, click); self.entries[label] = e; return e end
    function menu:CreateButton(label, click) local e = Entry(label, nil, click); self.entries[label] = e; return e end
    generator(anchor, menu)
end }
-- Blizzard's list shows a collapsed header's currencies only once expanded,
-- and the expanded state is the player's saved Currency tab state.
C_CurrencyInfo = {
    GetCurrencyInfo = function(id) return { name = "Currency " .. id } end,
    GetCurrencyListSize = function() queries = queries + 1; return expanded and 11 or 1 end,
    GetCurrencyListInfo = function(i)
        if i == 1 then return { name = "Expansion", isHeader = true, isHeaderExpanded = expanded, currencyListDepth = 0 } end
        if expanded then return { name = "Currency " .. (i - 1), isHeader = false } end
    end,
    GetCurrencyListLink = function(i) return tostring(i - 1) end,
    GetCurrencyIDFromLink = tonumber,
    ExpandCurrencyList = function(index, value) assert(index == 1); expanded = value; toggles[#toggles + 1] = value end,
}
-- S.ContextMenu: Blizzard's context menu outside WoW Forever's Gamepad UI
-- (MSUF_Suite_Modules/Dialogs.lua).
assert(loadfile(root .. "/MSUF_Suite_Modules/Dialogs.lua"))("MSUF_Suite_Modules", { Suite = S })
assert(loadfile(root .. "/MSUF_Suite_Bags/CurrencyPicker.lua"))("Bags", { Suite = S, BagsModule = module })
assert(queries == 0, "currency chooser does not enumerate currencies in the background")
S.BagCurrencyMenu({})
local eight, nine = menu.entries["Currency 8"], menu.entries["Currency 9"]
assert(eight and nine and menu.entries["Currency 10"], "currencies of a collapsed header must be listed")
assert(not expanded and #toggles == 2 and toggles[1] == true and toggles[2] == false,
    "the picker must leave Blizzard's collapsed header collapsed")
assert(eight.enabled and nine.enabled)
eight.click()
assert(config.currencyIDs == "1,2,3,4,5,6,7,8" and eight.select() and not nine.enabled,
    "eighth selection updates check and disables only new selections")
menu.entries["Currency 2"].click()
assert(nine.enabled and not menu.entries["Currency 2"].select(), "unchecking re-enables additional currencies")
nine.click()
assert(config.currencyIDs == "1,3,4,5,6,7,8,9")
-- An expanded header stays expanded and is never toggled.
expanded, toggles = true, {}
S.BagCurrencyMenu({})
assert(expanded and #toggles == 0, "the picker toggled a header the player had expanded")
local before = queries
module.active = false
assert(not S.BagCurrencyMenu({}) and queries == before, "disabled bags never open or query the picker")

-- Two expansions each hold a "Dungeon and Raid" sub-header: same name, same
-- depth. A model of Blizzard's tree list: rows in order, a header's children
-- only while it is expanded (the player's Currency tab state).
local function Node(name, isExpanded, children) return { name = name, expanded = isExpanded, children = children } end
local function Tree(dfDungeons, wwDungeons, dfOpen, wwOpen)
    return {
        Node("Dragonflight", dfOpen, { Node("Dungeon and Raid", dfDungeons, { { name = "Currency 21", id = 21 } }),
            { name = "Currency 22", id = 22 } }),
        Node("The War Within", wwOpen, { Node("Dungeon and Raid", wwDungeons, { { name = "Currency 31", id = 31 } }),
            { name = "Currency 32", id = 32 } }),
    }
end
local tree
local function Rows()
    local rows = {}
    local function Walk(list, depth)
        for _, node in ipairs(list) do
            rows[#rows + 1] = { node = node, depth = depth }
            if node.children and node.expanded then Walk(node.children, depth + 1) end
        end
    end
    Walk(tree, 0)
    return rows
end
C_CurrencyInfo = {
    GetCurrencyInfo = function(id) return { name = "Currency " .. id } end,
    GetCurrencyListSize = function() return #Rows() end,
    GetCurrencyListInfo = function(i)
        local row = Rows()[i]
        if not row then return nil end
        local node = row.node
        return { name = node.name, isHeader = node.children ~= nil, isHeaderExpanded = node.expanded == true,
            currencyListDepth = row.depth }
    end,
    GetCurrencyListLink = function(i) local row = Rows()[i]; return row and row.node.id and tostring(row.node.id) end,
    GetCurrencyIDFromLink = tonumber,
    ExpandCurrencyList = function(i, value) Rows()[i].node.expanded = value end,
}
local function States()
    return { tree[1].expanded, tree[1].children[1].expanded, tree[2].expanded, tree[2].children[1].expanded }
end
module.active, config.currencyIDs = true, ""
tree = Tree(false, false, false, false)
S.BagCurrencyMenu({})
for _, id in ipairs({ 21, 22, 31, 32 }) do
    assert(menu.entries["Currency " .. id], "a same-named sub-header kept currency " .. id .. " out of the picker")
end
local state = States()
assert(not state[1] and not state[2] and not state[3] and not state[4],
    "the picker left a collapsed header expanded")
-- The player's own expanded sub-header stays expanded beside its namesake.
tree = Tree(true, false, true, true)
S.BagCurrencyMenu({})
assert(menu.entries["Currency 21"] and menu.entries["Currency 31"], "a sub-header's currencies were not listed")
state = States()
assert(state[1] and state[2] and state[3] and not state[4],
    "the picker collapsed a same-named header the player had expanded")
print("currency picker bounds, checked state, Blizzard's header state and no background enumeration passed")
