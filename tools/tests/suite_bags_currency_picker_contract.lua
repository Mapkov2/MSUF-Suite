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
print("currency picker bounds, checked state, Blizzard's header state and no background enumeration passed")
