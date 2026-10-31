local root = assert(arg[1], "repository root required")
-- MSUF's menu search finds the cooldown manager's new per-spell rules
-- (package cdm11-C): they lead to the spell list, where a spell's own
-- options open. Runs the client of suite_search_findability_contract.lua up
-- to its own checks, in English (the new strings are translated after the
-- merge).
--   lua suite_cdm_perspell_search_contract.lua <suiteRoot> [Mainline|Forever] [locale]
arg[2], arg[3] = arg[2] or "Mainline", arg[3] or "enUS"
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_search_findability_contract.lua", [=[
local wanted = { "Show only when usable", "Show only during a spell alert", "Glow while missing", "Border color while active",
    "Bar name (Enter)", "Sound when used", "Sound when a charge returns" }
local rows = {}
for _, row in ipairs(P.SearchRows()) do
    if row.pageKey == "suite_cooldownManager" and row.label then rows[row.label] = row end
end
for _, english in ipairs(wanted) do
    local row = rows[P.Tr(english)]
    Check(row ~= nil, flavor .. ": no search row for " .. english)
    Check(row == nil or row.prepareKind == "suiteCDMSpell", flavor .. ": " .. english .. " leads to the spell list")
end
for query, english in pairs({ ["only when usable"] = "Show only when usable", ["spell alert"] = "Show only during a spell alert",
    ["glow while missing"] = "Glow while missing", ["charge returns"] = "Sound when a charge returns",
    ["bar name"] = "Bar name (Enter)" }) do
    local label = P.Tr(english)
    local rank, results = Rank(query, function(rec) return rec.key == "suite_cooldownManager" and rec.label == label end)
    Check(rank ~= nil, string.format("%s: \"%s\" does not find %s (got %s)", flavor, query, english, Got(results)))
end
if #failures > 0 then error("suite_cdm_perspell_search_contract failed:\n  " .. table.concat(failures, "\n  ")) end
print("suite_cdm_perspell_search_contract: ok (" .. flavor .. ")")
]=], "------------------------------------------------------------------ every uniquely named Suite row")
