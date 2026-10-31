local root = assert(arg[1], "repository root required")
-- MSUF's menu search finds the cooldown manager's new looks (package
-- cdm11-B): Pixel and Autocast's lines, the swipe colors, the countdown's
-- tenths and urgent stage, and the timer bar spark. Runs the client of
-- suite_search_findability_contract.lua up to its own checks, in English
-- (the new strings are translated after the merge).
--   lua suite_cdm_look_search_contract.lua <suiteRoot> [Mainline|Forever] [locale]
arg[2], arg[3] = arg[2] or "Mainline", arg[3] or "enUS"
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_search_findability_contract.lua", [=[
local wanted = { "Glow lines", "Glow thickness", "Glow speed (percent)", "Class-colored swipe", "Show a spark",
    "Show tenths below (seconds, 0 = off)", "Urgent warning below (seconds, 0 = off)" }
local rows = {}
for _, row in ipairs(P.SearchRows()) do
    if row.pageKey == "suite_cooldownManager" and row.label then rows[row.label] = true end
end
for _, english in ipairs(wanted) do
    Check(rows[P.Tr(english)], flavor .. ": no search row for " .. english)
end
for query, english in pairs({ ["glow lines"] = "Glow lines", ["spark"] = "Show a spark", ["tenths"] = "Show tenths below (seconds, 0 = off)",
    ["urgent warning"] = "Urgent warning below (seconds, 0 = off)", ["colored swipe"] = "Class-colored swipe" }) do
    local label = P.Tr(english)
    local rank, results = Rank(query, function(rec) return rec.key == "suite_cooldownManager" and rec.label == label end)
    Check(rank ~= nil, string.format("%s: \"%s\" does not find %s (got %s)", flavor, query, english, Got(results)))
end
if #failures > 0 then error("suite_cdm_look_search_contract failed:\n  " .. table.concat(failures, "\n  ")) end
print("suite_cdm_look_search_contract: ok (" .. flavor .. ")")
]=], "------------------------------------------------------------------ every uniquely named Suite row")
