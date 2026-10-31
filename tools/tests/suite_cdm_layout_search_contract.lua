local root = assert(arg[1], "repository root required")
-- MSUF's menu search finds the cooldown manager's layout extras (package
-- cdm11-E): the frame name of "Other frame", its "Pick a frame" button, the
-- Masque switch and the layout copy button. Runs the client of
-- suite_search_findability_contract.lua up to its own checks, in English
-- (the new strings are translated after the merge).
--   lua suite_cdm_layout_search_contract.lua <suiteRoot> [Mainline|Forever] [locale]
arg[2], arg[3] = arg[2] or "Mainline", arg[3] or "enUS"
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_search_findability_contract.lua", [=[
local wanted = { "Frame name", "Pick a frame", "Skin icons with Masque", "Copy layout to other specializations" }
local rows = {}
for _, row in ipairs(P.SearchRows()) do
    if row.pageKey == "suite_cooldownManager" and row.label then rows[row.label] = true end
end
for _, english in ipairs(wanted) do
    Check(rows[P.Tr(english)], flavor .. ": no search row for " .. english)
end
for query, english in pairs({ ["frame name"] = "Frame name", ["pick a frame"] = "Pick a frame", ["masque"] = "Skin icons with Masque",
    ["copy layout"] = "Copy layout to other specializations" }) do
    local label = P.Tr(english)
    local rank, results = Rank(query, function(rec) return rec.key == "suite_cooldownManager" and rec.label == label end)
    Check(rank ~= nil, string.format("%s: \"%s\" does not find %s (got %s)", flavor, query, english, Got(results)))
end
if #failures > 0 then error("suite_cdm_layout_search_contract failed:\n  " .. table.concat(failures, "\n  ")) end
print("suite_cdm_layout_search_contract: ok (" .. flavor .. ")")
]=], "------------------------------------------------------------------ every uniquely named Suite row")
