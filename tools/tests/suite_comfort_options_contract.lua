local root = assert(arg[1])
local F = dofile(root .. "/tools/tests/comfort_fixture.lua")
local e = F.New(root, true)
local settings = { fishingComfort = { rod = "", lure = "" }, dataTexts = { suppliesItems = "" }, groupFinderTools = { activities = "" } }
local state, menu, prompt, calls = {}, nil, nil, 0
local P = { Suite = e.NS, S = e.S, Tr = function(v) return v end, Combat = function() return e.NS.InCombat() end,
    Get = function(id, key) return settings[id][key] end,
    Set = function(id, key, value) settings[id][key] = value; return true end,
    ProfileGuard = function() local current = state; return function() return current == state end end,
    AskText = function(_, _, fn) prompt = fn end }
e.NS.Client.isForever = true
local function Menu()
    local m = { entries = {}, titles = {} }
    function m:CreateTitle(title) self.titles[#self.titles + 1] = title end
    function m:CreateButton(title, fn) local row = { click = fn }; self.entries[title] = row; return row end
    function m:CreateCheckbox(title, selected, fn)
        local row = self:CreateButton(title, fn); row.selected = selected
        function row:SetTooltip(fn) self.tooltip = fn end
        return row
    end
    return m
end
P.ContextMenu = function(_, build) menu = Menu(); build(nil, menu) end
Enum = { ItemClass = { Weapon = 2, Consumable = 0 }, ItemWeaponSubclass = { Fishingpole = 20 }, LFGListFilter = { PvE = 1 } }
NUM_BAG_SLOTS, GROUP_FINDER_CATEGORY_ID_DUNGEONS = 0, 2
C_Container = { GetContainerNumSlots = function() calls = calls + 1; return 3 end, GetContainerItemID = function(_, slot) return 40 + slot end }
e.S.Print = function() end
C_Item = { GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, id == 41 and 2 or 0, id == 41 and 20 or 0 end,
    GetItemInfo = function(id)
    assert(id > 0 and id < 2147483647, "invalid native item id")
    return "Item" .. id, nil, nil, nil, nil, nil, nil, nil, nil, 1, nil, id == 41 and 2 or 0, id == 41 and 20 or 0
end }
C_LFGList = { GetAvailableActivityGroups = function() return { 7, 8 } end, GetActivityGroupInfo = function(id) return "Dungeon" .. id end }
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/ComfortPickers.lua"))("options", P)
assert(calls == 0, "loading options picker cannot inspect bags")
P.ComfortItemMenu({}, "fishingComfort", "rod", "rod")
assert(menu.entries.Item41 and not menu.entries.Item42, "rod picker contains actual fishing poles only")
menu.entries.Item41.click(); assert(settings.fishingComfort.rod == "41")
P.ComfortItemMenu({}, "fishingComfort", "rod", "rod")
menu.entries["Advanced: enter item ID or link"].click(); prompt("42")
assert(settings.fishingComfort.rod == "41", "expert rod choice cannot silently select a potion")
P.ComfortItemMenu({}, "dataTexts", "suppliesItems", "supplies", true)
menu.entries.Item41.click(); menu.entries.Item42.click()
assert(settings.dataTexts.suppliesItems == "41,42", "same menu supports repeated selection")
assert(menu.entries.Item41.selected() and menu.entries.Item42.selected())
menu.entries.Item41.click(); assert(settings.dataTexts.suppliesItems == "42", "same menu supports deselection")
local before = settings.dataTexts.suppliesItems
state = {}; menu.entries.Item43.click(); assert(settings.dataTexts.suppliesItems == before, "stale profile menu cannot write")
P.ComfortItemMenu({}, "fishingComfort", "lure", "lure")
assert(menu.entries.Item42.tooltip and not menu.entries.Item41 and #menu.titles > 0, "lure picker explains generic consumables and supplies native item tooltips")
menu.entries["Advanced: enter item ID or link"].click(); prompt("|cff00ff00|Hitem:777:0|h[My lure]|h|r")
assert(settings.fishingComfort.lure == "777", "expert entry accepts a real item link")
P.ComfortItemMenu({}, "fishingComfort", "lure", "lure")
menu.entries["Advanced: enter item ID or link"].click(); state = {}; prompt("888")
assert(settings.fishingComfort.lure == "777", "late prompt cannot write to another profile")
P.ComfortDungeonMenu({}); menu.entries.Dungeon7.click(); menu.entries.Dungeon8.click()
assert(settings.groupFinderTools.activities == "7,8", "named dungeon choices persist together")
e:Combat(true); menu.entries.Dungeon7.click(); assert(settings.groupFinderTools.activities == "7,8", "combat menu cannot mutate selection")
print("comfort option pickers: cold zero reads, named choices, repeated selection, item tooltips, expert links and stale guards passed")
