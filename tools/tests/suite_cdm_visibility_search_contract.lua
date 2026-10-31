local root = assert(arg[1], "repository root required")
-- MSUF's menu search finds the cooldown manager's bar visibility conditions
-- (hide while resting, not in a group, outside instances, flying, dead;
-- opacity while hidden, show on mouseover, fade time) by their names. Runs
-- the client of suite_search_findability_contract.lua up to its own checks,
-- in English unless a flavor and locale are given.
--   lua suite_cdm_visibility_search_contract.lua <suiteRoot> [Mainline|Forever] [locale]
arg[2], arg[3] = arg[2] or "Mainline", arg[3] or "enUS"
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_search_findability_contract.lua", [=[
local LABELS = { "Hide while resting", "Hide when not in a group", "Hide outside instances", "Hide while flying",
    "Hide while dead", "Opacity while hidden (percent)", "Show on mouseover", "Fade time (seconds)" }
for _, english in ipairs(LABELS) do
    local label = P.Tr(english)
    local row
    for _, candidate in ipairs(P.SearchRows()) do
        if candidate.pageKey == "suite_cooldownManager" and candidate.label == label then row = candidate end
    end
    if Check(row, flavor .. ": no search row for \"" .. english .. "\"") then
        Check(row.sectionId == "suite_cooldownManager_visibility",
            flavor .. ": \"" .. english .. "\" does not lead to the Visibility section (" .. tostring(row.sectionId) .. ")")
        local rank, results = Rank(label, function(rec) return rec.key == "suite_cooldownManager" and rec.label == label end)
        Check(rank and rank <= PALETTE, string.format("%s: \"%s\" ranks the cooldown manager's row at %s (got %s)",
            flavor, label, tostring(rank), Got(results)))
    end
end
if #failures > 0 then error("suite_cdm_visibility_search_contract failed:\n  " .. table.concat(failures, "\n  ")) end
print("suite_cdm_visibility_search_contract: ok (" .. flavor .. ")")
]=], "------------------------------------------------------------------ every uniquely named Suite row")
