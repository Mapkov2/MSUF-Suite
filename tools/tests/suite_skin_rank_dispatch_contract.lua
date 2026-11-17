-- Isolate the rank-control ownership regression from other adapter sections.
-- This exercises the real adapter and a menu protocol fixture, not WoW taint.
local root = assert(arg[1], "Suite root required")
local path = os.getenv("SUITE_RANKS_FIXTURE") or root .. "/tools/tests/suite_skin_generic_windows_contract.lua"
local handle = assert(io.open(path, "rb"))
local source = handle:read("*a")
handle:close()
local headerEnd = assert(source:find('Section("adapter kit colors"', 1, true))
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
assert(loadstring(source:sub(1, headerEnd - 1) .. support .. source:sub(ranksStart, ranksEnd - 1) .. finish,
    "@suite_rank_menu_fixture"))()
