-- Suite pages and settings in MSUF's menu search (MSUF_Suite_Options/Menu/Search.lua).
--
-- Boots the sibling Classic MSUF checkout's real core, Options and search layer
-- (its tools/tests/client_world.lua), loads MSUF_Suite and MSUF_Suite_Options into
-- the same client and runs real searches. Checks that the provider registers
-- through M.RegisterSearchProvider without collecting at load, that every Suite
-- page answers its own name and its aliases (Register.lua puts them only into
-- M.ALIASES), that a setting of a never-opened page is found with its exact
-- target, that hidden rules, per-instance duplicates and modules whose addon is
-- not installed stay out, and that "minimap" reads apart from MSUF's own icon.
-- An MSUF build without the hook gets no rows and no error.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local classic = root .. "/../MidnightSimpleUnitFrames-Classic"

local function Check(condition, message)
    if not condition then error("suite_search_provider_contract: " .. message, 2) end
    return condition
end

local function Read(path)
    local file = assert(io.open(path, "rb"), "cannot open " .. path)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

------------------------------------------------------------------ source contract
local toc = Read(root .. "/MSUF_Suite_Options/MSUF_Suite_Options_Mainline.toc")
Check(toc:find("\nMenu\\Register.lua\nMenu\\Search.lua\n", 1, true),
    "Menu\\Search.lua must load right after Menu\\Register.lua")
local source = Read(root .. "/MSUF_Suite_Options/Menu/Search.lua")
Check(source:find('if type(M.RegisterSearchProvider) ~= "function" then return end', 1, true),
    "the provider must register only where the MSUF menu has the hook")
Check(not source:find("pcall", 1, true), "no pcall in addon code")

------------------------------------------------------------------ host without the hook
do
    local P = { Suite = {}, M = {}, Tr = function(text) return text end }
    assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Search.lua"))("MSUF_Suite_Options", P)
    Check(P.SearchRows == nil and P.searchRegistered == nil, "a menu without the hook got a provider")
end

------------------------------------------------------------------ one client, both addons
local World = assert(loadfile(classic .. "/tools/tests/client_world.lua"),
    "the Classic MSUF checkout is required next to the Suite (" .. classic .. ")")()
-- arg 2 (optional): "Forever" boots the WoW Forever client instead of Retail.
local flavor = arg[2] or "Mainline"
assert(flavor == "Mainline" or flavor == "Forever", "the Suite supports Retail and WoW Forever only")
local world = World.New(classic, flavor):Boot()
local failure = world:FirstFailure()
Check(failure == nil, "MSUF did not boot: " .. tostring(failure and failure.file) .. " "
    .. tostring(failure and failure.message))
local env = world.env
env.InCombatLockdown = function() return false end
env.UnitAffectingCombat = function() return false end
local missing = {}
local loaded = { MidnightSimpleUnitFrames = true, MidnightSimpleUnitFrames_Options = true }
env.C_AddOns = {
    GetAddOnMetadata = function() return nil end,
    IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
    DoesAddOnExist = function(name) return name:find("^MSUF_Suite") ~= nil and not missing[name] end,
    GetAddOnEnableState = function() return 2 end,
    LoadAddOn = function() return false, "MISSING" end,
    GetNumAddOns = function() return 0 end,
}
local function LoadAddOn(addon, namespace)
    for line in Read(root .. "/" .. addon .. "/" .. addon .. "_Mainline.toc"):gmatch("[^\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local ok, message = world:LoadFile(root .. "/" .. addon .. "/" .. line:gsub("\\", "/"), addon, namespace)
            Check(ok, addon .. "/" .. line .. ": " .. tostring(message))
        end
    end
    loaded[addon] = true
end
LoadAddOn("MSUF_Suite", {})
local P = {}
LoadAddOn("MSUF_Suite_Options", P)

local M = world.core.MSUF2
local api = M.Search._CoreAPI
Check(P.searchRegistered == true, "the Suite provider did not register")
Check(api.GetSearchProviderCache() == nil, "Suite rows were collected at load instead of on the first search")

local function Search(query) return api.SearchPages(query) end
local function Line(rec)
    return string.format("%s [%s] %s", tostring(rec.label), tostring(rec.kind), tostring(rec.hint))
end
local shown = {}
local function Show(query, count)
    local results = Search(query)
    local lines = {}
    for i = 1, math.min(count or 3, #results) do lines[#lines + 1] = "    " .. i .. ". " .. Line(results[i]) end
    shown[#shown + 1] = "  '" .. query .. "':\n" .. table.concat(lines, "\n")
    return results
end

------------------------------------------------------------------ pages by name and alias
local catalog = world.env.MSUFSuite.SuiteCatalog
local PAGE_QUERIES = {
    { "minimap", "suite_minimap" }, { "nameplate", "suite_nameplates" }, { "nameplates", "suite_nameplates" },
    { "cooldown manager", "suite_cooldownManager" }, { "cdm", "suite_cooldownManager" },
    { "buff reminders", "suite_buffReminders" }, { "buff reminder", "suite_buffReminders" },
    { "chat", "suite_chat" }, { "bags", "suite_bags" }, { "action bars", "suite_actionbars" },
    { "action bar", "suite_actionbars" }, { "damage meter", "suite_damageMeter" }, { "meter", "suite_damageMeter" },
    { "data text", "suite_dataTexts" }, { "data texts", "suite_dataTexts" }, { "skinning", "suite_skin" },
    { "skin", "suite_skin" }, { "quality of life", "suite_qualityOfLife" }, { "qol", "suite_qualityOfLife" },
    -- Words only the provider knows (no title or alias holds them).
    { "hotbar", "suite_actionbars" }, { "name plates", "suite_nameplates" }, { "dps meter", "suite_damageMeter" },
}
for _, case in ipairs(PAGE_QUERIES) do
    local first = Show(case[1])[1]
    Check(first and first.key == case[2], "'" .. case[1] .. "' opens " .. tostring(first and first.key)
        .. " first, not " .. case[2])
end
Check(api.GetSearchProviderCache().skipped == 0, "the host skipped Suite rows as malformed")

-- Every alias of every page is a search word of that page (Register.lua only
-- fills M.ALIASES). Whether it ranks first depends on what else MSUF offers for
-- the word ("dps" is also a group role); the words above must rank first.
local pageRecords = {}
for _, rec in ipairs(api.GetSearchRecords()) do
    if rec.kind == "page" then pageRecords[rec.key] = rec end
end
local normalize = M.Search.Text.NormalizeSearchText
for _, page in ipairs(P.pages) do
    local rec = Check(pageRecords[page.key], "no page record for " .. page.key)
    for _, alias in ipairs(page.aliases or {}) do
        Check((" " .. rec.haystack .. " "):find(" " .. normalize(alias) .. " ", 1, true),
            "alias '" .. alias .. "' is not a search word of " .. page.key)
    end
end

-- "minimap": the Suite page first, its breadcrumb names the Suite, and MSUF's own
-- minimap icon help stays in the list.
local minimap = Search("minimap")
Check(minimap[1].kind == "page" and minimap[1].hint:find("^MSUF Suite > "),
    "the Suite Minimap page result does not say it is the Suite's: " .. Line(minimap[1]))
local msufIcon = false
for _, rec in ipairs(minimap) do
    if rec.key ~= "suite_minimap" and (rec.label:lower():find("minimap icon") or rec.key == "opt_misc") then msufIcon = true end
end
Check(msufIcon, "'minimap' lost MSUF's own minimap icon result")
Check(Show("enable minimap", 4)[1] ~= nil, "'enable minimap' found nothing")
local suiteFaq = false
for _, rec in ipairs(Search("enable minimap")) do
    if rec.kind == "faq" and rec.key == "suite_minimap" then suiteFaq = true end
end
Check(suiteFaq, "'enable minimap' answers only with MSUF's minimap icon help")
Show("suite", 3)
Show("modules", 5)

------------------------------------------------------------------ settings of unopened pages
local size = Show("minimap size")[1]
Check(size and size.key == "suite_minimap" and size.kind == "slider" and size.provided
    and size.exactTarget and size.exactTarget.settingKey == "msufsuite.minimap.size",
    "'minimap size' does not lead to the Suite control: " .. tostring(size and Line(size)))
Check(size.hint:find("> Minimap > " .. M.Tr(catalog.minimap.rules.size.sectionTitle), 1, true),
    "the setting breadcrumb lost its page or section: " .. size.hint)
local border = Show("minimap border color")[1]
Check(border and border.key == "suite_minimap" and border.kind == "color" and border.exactTarget == nil
    and border.anchorFallback == M.Tr(catalog.minimap.rules.borderColor.sectionTitle),
    "a Suite color must lead to its section's color shortcut")

-- Hidden rules stay out.
for _, rec in ipairs(Search("blizzard layout imported")) do
    Check(not (rec.provided and rec.label == "Blizzard layout imported"), "a hidden rule became a search row")
end

-- A per-bar rule is one row, not one per bar.
local buttonSize = 0
for _, rec in ipairs(Search("button size")) do
    if rec.provided and rec.key == "suite_actionbars" and rec.label == "Button size" then buttonSize = buttonSize + 1 end
end
Check(buttonSize == 1, "the action bars' per-bar Button size gave " .. buttonSize .. " rows")

------------------------------------------------------------------ installed modules only
local rows = P.SearchRows()
local chatRows = 0
for _, row in ipairs(rows) do
    if row.pageKey == "suite_chat" and row.kind ~= "page" and row.kind ~= "faq" then chatRows = chatRows + 1 end
end
Check(chatRows > 0, "the chat page has no rows")
missing.MSUF_Suite_Chat = true
for _, row in ipairs(P.SearchRows()) do
    Check(not (row.pageKey == "suite_chat" and row.kind ~= "page"), "rows of a module that is not installed")
end
missing.MSUF_Suite_Chat = nil

print("suite_search_provider_contract: ok (" .. #rows .. " rows; every page by name and alias)")
print(table.concat(shown, "\n"))
