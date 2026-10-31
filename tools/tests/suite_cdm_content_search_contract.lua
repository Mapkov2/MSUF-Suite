local root = assert(arg[1], "repository root required")
-- MSUF's menu search finds the cooldown manager's ready pulse rules (the
-- bar's switch among the cooldown effects, the four General settings in
-- Basics) by their names. Runs the client of suite_search_findability_contract.lua
-- up to its own checks, in English unless a flavor and locale are given.
--   lua suite_cdm_content_search_contract.lua <suiteRoot> [Mainline|Forever] [locale]
arg[2], arg[3] = arg[2] or "Mainline", arg[3] or "enUS"
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_search_findability_contract.lua", [=[
local LABELS = {
    { "Pulse ready cooldowns in the screen center", "suite_cooldownManager_effects" },
    { "Pulse only in combat", "suite_cooldownManager_cooldownManager_module" },
    { "Ready pulse size", "suite_cooldownManager_cooldownManager_module" },
    { "Ready pulse vertical position", "suite_cooldownManager_cooldownManager_module" },
    { "Ready pulse hold time (seconds)", "suite_cooldownManager_cooldownManager_module" },
}
for _, spec in ipairs(LABELS) do
    local english, section = spec[1], spec[2]
    local label = P.Tr(english)
    local row
    for _, candidate in ipairs(P.SearchRows()) do
        if candidate.pageKey == "suite_cooldownManager" and candidate.label == label then row = candidate end
    end
    if Check(row, flavor .. ": no search row for \"" .. english .. "\"") then
        Check(row.sectionId == section,
            flavor .. ": \"" .. english .. "\" leads to " .. tostring(row.sectionId) .. ", not " .. section)
        local rank, results = Rank(label, function(rec) return rec.key == "suite_cooldownManager" and rec.label == label end)
        Check(rank and rank <= PALETTE, string.format("%s: \"%s\" ranks the cooldown manager's row at %s (got %s)",
            flavor, label, tostring(rank), Got(results)))
    end
end
if #failures > 0 then error("suite_cdm_content_search_contract failed:\n  " .. table.concat(failures, "\n  ")) end
print("suite_cdm_content_search_contract: ok (" .. flavor .. ")")
]=], "------------------------------------------------------------------ every uniquely named Suite row")
