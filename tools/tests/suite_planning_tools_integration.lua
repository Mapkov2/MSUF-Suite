local root = assert(arg[1], "repository root required")
local file = assert(io.open(root .. "/tools/tests/suite_run_summary_contract.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local needle = 'Event("CHALLENGE_MODE_START")\nEvent("CHALLENGE_MODE_COMPLETED")'
local replacement = [[Event("CHALLENGE_MODE_START")
S.instances.objectives = { active = true, mplusActive = true,
    mplus = { mapID = 42, level = 15, completed = false, splits = { [3] = 200, [4] = secret, [5] = -1 } } }
Event("CHALLENGE_MODE_COMPLETED")
assert(state.history[1].splits[3] == 200, "completed run lost the objective owner's public split")
assert(state.history[1].splits[4] == nil and state.history[1].splits[5] == nil, "unreadable or invalid split was retained")
S.instances.objectives.mplus.mapID = 999
]]
local first, last = assert(source:find(needle, 1, true))
source = source:sub(1, first - 1) .. replacement .. source:sub(last + 1)
needle = 'Event("CHALLENGE_MODE_COMPLETED_REWARDS")\nassert(cards == serial'
replacement = [[Event("CHALLENGE_MODE_COMPLETED_REWARDS")
assert(state.history[1].splits[3] == 200, "reward update lost the previously captured split")
S.instances.objectives.active = false
assert(cards == serial]]
first, last = assert(source:find(needle, 1, true))
source = source:sub(1, first - 1) .. replacement .. source:sub(last + 1)
assert(loadstring(source, "planning integration over real run summary harness"))()
print("suite_planning_tools_integration: public splits captured and preserved across reward updates")
