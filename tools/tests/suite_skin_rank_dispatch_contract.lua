-- Exercise the rank control with the shared adapter fixtures and a model of pooled rows.
local root = assert(arg[1], "Suite root required")
local path = os.getenv("SUITE_RANKS_FIXTURE") or root .. "/tools/tests/suite_skin_generic_windows_contract.lua"
local handle = assert(io.open(path, "rb"))
local source = handle:read("*a")
handle:close()
local catalogStart = assert(source:find("-- Catalog: classified once at load", 1, true))
local setupStart = assert(source:find("-- Blizzard's callback isolation", catalogStart, true))
local frameHelper = assert(source:find("local function Frame(name, children)", setupStart, true))
local setupEnd = assert(source:find('if fixtureMode == "flight-map-fixture" then', frameHelper, true))
local helpersStart = assert(source:find("local function Load(file, namespace)", setupEnd, true))
local helpersEnd = assert(source:find('Section("adapter kit colors"', helpersStart, true))
local ranksStart = assert(source:find('Section("forever spellbook ranks toggle"', 1, true))
local ranksEnd = assert(source:find('Section("prepared Forever spells window combat artwork"', ranksStart, true))
local support = [[
NS.ControlSkin.ApplyButton = NS.ControlSkin.ApplyButton or function() return {} end
NS.ControlSkin.ApplyTab = NS.ControlSkin.ApplyTab or function() return {} end
NS.ControlSkin.ApplySearchBox = NS.ControlSkin.ApplySearchBox or function() return {} end
]]
local finish = [[
if #failures > 0 then error(table.concat(failures, "\n")) end
print("Suite rank menu dispatch: " .. checks .. " checks passed")
]]
local setup = source:sub(1, catalogStart - 1) .. source:sub(setupStart, setupEnd - 1)
local helpers = source:sub(helpersStart, helpersEnd - 1)
local ranks = source:sub(ranksStart, ranksEnd - 1)
assert(loadstring(setup .. support .. helpers .. ranks .. finish, "@suite_rank_menu_fixture"))()
