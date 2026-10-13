local root=assert(arg[1],"repository root required")
local run=assert(loadfile(root.."/tools/tests/data_scheduler_cases.lua"))()
for _,scenario in ipairs({"cancel","replace","cancel_replace","same_callback","self_reschedule",
    "error_isolation","idle_cancel","warm_budget"}) do run(root,scenario) end
print("Shared data scheduler: eight independent lifecycle and budget cases passed")
