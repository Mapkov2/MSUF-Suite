local root = assert(arg[1])
local run = assert(loadfile(root .. "/tools/tests/applicant_view_cases.lua"))()
for _, scenario in ipairs({ "individual_status", "individual_score", "listing_change", "group_authority",
    "fresh_click_guard", "full_group", "pending_fills_group", "secret_leader", "secret_assistant",
    "secret_capacity", "missing_limit", "zero_limit", "fresh_listing_guard", "combat_return",
    "reopen", "reenable_reopen", "paging", "invite_decline" }) do
    run(root, scenario)
end
local ok, reason = pcall(run, root, "individual_status", "without_view_events")
assert(not ok and tostring(reason):find("individual native update", 1, true), "missing owned event regression escaped")
print("Applicant sorting: 18 owned-view/action cases and an event mutation rejected")
