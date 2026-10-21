local root = assert(arg[1], "repository root required")
-- MSUF's menu search finds the cooldown manager's pandemic window switch by
-- the word players use (owner request 2026-10-20: its old name, "refresh
-- window", was not findable). Runs the client of
-- suite_search_findability_contract.lua up to its own checks, in German
-- unless a flavor and locale are given.
--   lua suite_cdm_pandemic_search_contract.lua <suiteRoot> [Mainline|Forever] [locale]
-- The bare word finds it too. The host's query aliases also send "pandemic"
-- to its aura colors and cooldown text (MSUF_Menu2_Search_QueryAliases.lua),
-- but the host ranks the rows that contain a typed word before those only an
-- alias reaches (SearchClauseScore in MSUF_Menu2_Search_IndexQuery.lua). Only
-- host rows may rank above it. The rows of its look (style, color,
-- thickness) lead to the same section and count as the pandemic window too.
arg[2], arg[3] = arg[2] or "Mainline", arg[3] or "deDE"
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_search_findability_contract.lua", [=[
local label = P.Tr("Highlight the pandemic window")
Check(locale == "enUS" or label ~= "Highlight the pandemic window", flavor .. ": the pandemic window label is untranslated")
local found = false
for _, row in ipairs(P.SearchRows()) do
    if row.pageKey == "suite_cooldownManager" and row.label == label then found = true end
end
Check(found, flavor .. ": no search row for the pandemic window")
local LOOK = {}
for _, english in ipairs({ "Highlight the pandemic window", "Pandemic window style", "Pandemic window color",
    "Pandemic window thickness" }) do LOOK[P.Tr(english)] = true end
local function Mine(rec) return rec.key == "suite_cooldownManager" and LOOK[rec.label] == true end
local named = locale == "deDE" and "Pandemiefenster" or "pandemic window"
local rank, results = Rank(named, Mine)
Check(rank and rank <= PALETTE, string.format("%s: \"%s\" ranks the pandemic window at %s (got %s)",
    flavor, named, tostring(rank), Got(results)))
local bare = locale == "deDE" and "Pandemie" or "pandemic"
rank, results = Rank(bare, Mine)
Check(rank and rank <= PALETTE, string.format("%s: \"%s\" ranks the pandemic window at %s (got %s)",
    flavor, bare, tostring(rank), Got(results)))
for i = 1, (rank or 1) - 1 do
    Check(not tostring(results[i].key):find("^suite_"), flavor .. ": a Suite row ranks above the pandemic window: "
        .. tostring(results[i].key) .. " " .. tostring(results[i].label))
end
if #failures > 0 then error("suite_cdm_pandemic_search_contract failed:\n  " .. table.concat(failures, "\n  ")) end
print("suite_cdm_pandemic_search_contract: ok (" .. flavor .. ")")
]=], "------------------------------------------------------------------ every uniquely named Suite row")
