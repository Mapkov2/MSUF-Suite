-- Exercises the real Copy To selection/write functions without constructing Menu2.
local root = assert(arg[1], "repository root required")
local file = assert(io.open(root .. "/MSUF_Suite_Options/Pages/ActionBars.lua", "rb"))
local source = file:read("*a"); file:close()
local prefix = assert(source:find("local function Preset", 1, true))
local first = assert(source:find("local TARGET_WIDTHS", 1, true))
local last = assert(source:find("local function AttachCopyTo", first, true))
local config, rules, history, writes, confirmed, combat = {}, {}, 0, 0, 0, false
-- The page reads the Suite namespace's client facts (Core/Platform.lua) at load.
-- The catalog's choice values (Core/Catalog/ActionBars.lua), as the client's namespace has them.
local _, catalog = dofile(root .. "/tools/tests/suite_test_support.lua").CatalogDefaults(root, "actionbars", "ActionBars")
local P = { Suite = { ActionBarCount = 4, ActionBarTitles = {"Action bar 1", "Action bar 2", "Action bar 3", "Action bar 4"},
        Client = { isForever = false }, ActionBarEnum = catalog.ActionBarEnum },
    S = {}, M = {}, W = {}, T = {}, Tr = function(x) return x end, catalog = { actionbars = { rules = {} } } }
P.catalog.actionbars.rules = setmetatable(rules, { __index = function() return {} end })
P.Help = function(a) return a end
P.Get = function(_, key) return config[key] end
P.Combat = function() return combat end
P.WithHistory = function(_, _, callback) history = history + 1; return callback() end
P.SetMany = function(_, values) writes = writes + 1; for k,v in pairs(values) do config[k] = v end; return true end
P.Refresh = function() end
-- Copy to All asks first through the pages' confirmation (Menu/Bridge.lua).
P.Confirm = function(_, _, onAccept) confirmed = confirmed + 1; onAccept() end
local code = source:sub(1, prefix-1) .. source:sub(first, last-1) ..
    "return { targets=CopyDestination, click=SelectCopyDestination, run=RunCopyTo, scopes=copyScopes }"
local api = assert(loadstring(code))("Options", P)
for i=1,4 do config["bar"..i.."Size"]=30+i;config["bar"..i.."X"]=i*10 end
for k in pairs(api.scopes) do api.scopes[k] = k=="layout" end
local choices=api.targets(1)
assert(choices[2] and not choices[3])
api.click(2);api.click(3);api.click(4)
local hidden=0
local popup={Hide=function() hidden=hidden+1 end}
api.run(popup)
assert(config.bar2Size==32 and config.bar3Size==31 and config.bar4Size==31, "copy touched unselected target or missed subset")
assert(config.bar3X==30 and config.bar4X==40 and history==1 and writes==1 and confirmed==0, "subset lost positions or one-step undo")
api.click(3);api.click(4);api.run(popup)
assert(history==1 and hidden==1, "empty selection copied")
api.click("all");api.run(popup)
assert(config.bar2Size==31 and confirmed==1 and history==2, "All lost confirmation or target")
combat=true;api.run(popup);assert(history==2, "copy ran in combat")
print("Action bar copy: arbitrary subset, groups, positions, single history write, empty target, all confirmation and combat gate passed")
