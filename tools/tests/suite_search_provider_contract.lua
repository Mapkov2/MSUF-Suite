-- Suite pages and settings in MSUF's menu search (MSUF_Suite_Options/Menu/Search.lua).
--
-- Boots the sibling Classic MSUF checkout's real core, Options and search layer
-- (its tools/tests/client_world.lua), optionally substituting Retail's search
-- provider hook, then loads MSUF_Suite and MSUF_Suite_Options into
-- the same client and runs real searches. Checks that the provider registers
-- through M.RegisterSearchProvider without collecting at load, that every Suite
-- page answers its own name and its aliases (Register.lua puts them only into
-- M.ALIASES), that a setting of a never-opened page is found with its exact
-- target, that hidden rules, per-instance duplicates and modules whose addon is
-- not installed stay out, and that "minimap" reads apart from MSUF's own icon.
-- A module that is off keeps its page, FAQ answers and enable switch; only its
-- details leave the index, on the Classic host and on the Main host (which
-- refreshes only when the provider registers again).
-- An MSUF build without the hook gets no rows and no error.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local classic = root .. "/../MidnightSimpleUnitFrames-Classic"
local searchHost = (arg[3] or classic):gsub("\\", "/"):gsub("/$", "")

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
local registerAt = toc:find("\nMenu\\Register.lua\n", 1, true)
local actionsAt = toc:find("\nMenu\\SearchActions.lua\n", 1, true)
local searchAt = toc:find("\nMenu\\Search.lua\n", 1, true)
Check(registerAt and actionsAt and searchAt and registerAt < actionsAt and actionsAt < searchAt,
    "Suite search must load after page registration and the action inventory")
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
local world = World.New(classic, flavor)
if searchHost ~= classic then
    -- The Retail checkout does not carry Classic's client-world manifest. Boot
    -- the established Classic harness, but load Retail's search provider hook
    -- at its ordered TOC position to verify the production integration.
    local searchFile = searchHost .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_IndexQuery.lua"
    Read(searchFile)
    local loadFile = world.LoadFile
    function world:LoadFile(path, addon, namespace)
        if addon == "MidnightSimpleUnitFrames_Options"
            and path:find("/MSUF_Menu2_Search_IndexQuery.lua", 1, true) then
            path = searchFile
        end
        return loadFile(self, path, addon, namespace)
    end
end
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "MSUF did not boot: " .. tostring(failure and failure.file) .. " "
    .. tostring(failure and failure.message))
local env = world.env
world.core.MSUF2.frame = { IsShown = function() return true end }
env.InCombatLockdown = function() return false end
env.UnitAffectingCombat = function() return false end
env.C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
local getCVar = env.C_CVar.GetCVar
env.C_CVar.GetCVar = function(name) if name == "combinedBags" then return "1" end return getCVar(name) end
local missing, disabled = {}, {}
local loaded = { MidnightSimpleUnitFrames = true, MidnightSimpleUnitFrames_Options = true }
env.C_AddOns = {
    GetAddOnMetadata = function() return nil end,
    IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
    DoesAddOnExist = function(name) return name:find("^MSUF_Suite") ~= nil and not missing[name] end,
    GetAddOnEnableState = function(name) return disabled[name] and 0 or 2 end,
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
local Suite = env.MSUFSuite
Check(Suite.Database.Initialize(nil), "Suite test profile did not initialize")
for _, id in ipairs(Suite.SuiteOrder) do Suite.Suite.Config(id).enabled = true end
Suite.Skin.enabled = true
local P = {}
local collectors,collectionCalls={},{}
local nativeRegister=world.core.MSUF2.RegisterSearchProvider
world.core.MSUF2.RegisterSearchProvider=function(name,collect,contextChanged)
    if name:match("^MSUF_Suite") then
        local source=collect
        collect=function()
            collectionCalls[name]=(collectionCalls[name] or 0)+1
            return source()
        end
        collectors[name]=collect
    end
    return nativeRegister(name,collect,contextChanged)
end
LoadAddOn("MSUF_Suite_Options", P)
for _, feature in ipairs(P.QualityOfLifeSearchFeatures or {}) do
    Suite.Suite.Config(feature.id)[feature.switch] = true
end

-- Disabling a module/feature hides its details, but its real setting key must
-- still identify the switch used to turn it back on (cold or visited page).
do
    local chat = Suite.Suite.Config("chat")
    chat.enabled = false
    Check(P.SearchRowAvailable("suite_chat", "msufsuite.chat.enabled", {
        kind = "toggle", suiteModuleId = "chat",
    }), "a disabled module's enable switch disappeared from cold search")
    Check(P.SearchRowAvailable("suite_chat", "msufsuite.chat.enabled", { kind = "toggle" }),
        "a disabled module's enable switch disappeared from visited-page search")
    Check(not P.SearchRowAvailable("suite_chat", "msufsuite.chat.fontSize", { kind = "slider" }),
        "a disabled module still exposed its detail settings")
    P.ForgetAvailability()
    local page, switch
    for _, row in ipairs(P.SearchRows()) do
        if row.pageKey == "suite_chat" then
            if row.kind == "page" then
                page = row
            elseif row.settingKey == "msufsuite.chat.enabled" then
                switch = row
            else
                Check(false, "disabled chat retained a cold detail, section or action: " .. tostring(row.label))
            end
        end
    end
    Check(page and switch, "disabled chat lost its cold page or enable switch")
    chat.enabled = true

    local protection = Suite.Suite.Config("releaseProtection")
    protection.enabled = false
    Check(P.SearchRowAvailable("suite_qualityOfLife", "msufsuite.releaseProtection.enabled", { kind = "toggle" })
        and not P.SearchRowAvailable("suite_qualityOfLife", "msufsuite.releaseProtection.modifier", { kind = "dropdown" }),
        "disabled release protection must remain searchable through its enable switch")
    protection.enabled = true

    local checkedFeature = false
    for _, feature in ipairs(P.QualityOfLifeSearchFeatures or {}) do
        if feature.switch ~= "enabled" then
            local config = Suite.Suite.Config(feature.id)
            config[feature.switch] = false
            Check(P.SearchRowAvailable("suite_qualityOfLife",
                "msufsuite." .. feature.id .. "." .. feature.switch, { kind = "toggle" }),
                "a disabled QoL feature's switch disappeared from visited-page search")
            config[feature.switch] = true
            checkedFeature = true
            break
        end
    end
    Check(checkedFeature, "the QoL fixture had no independent feature switch")

    -- Skinning switched off keeps its page and the switch that turns it on.
    Suite.Skin.enabled = false
    Check(P.SearchRowAvailable("suite_skin", "msufsuite.skin.enabled", { kind = "toggle" })
        and P.SearchRowAvailable("suite_skin", nil, { kind = "page" })
        and not P.SearchRowAvailable("suite_skin", "msufsuite.skin.font.path", { kind = "textinput" }),
        "Skinning that is off lost its page or switch, or kept its details")
    local skinSwitch
    for _, row in ipairs(P.SearchRows()) do
        if row.settingKey == "msufsuite.skin.enabled" then skinSwitch = row end
    end
    Check(skinSwitch, "Skinning that is off lost its cold enable switch")
    Suite.Skin.enabled = true

    -- A module this client cannot run (its AddOn is off in Blizzard's list)
    -- offers neither its page nor its switch.
    disabled.MSUF_Suite_Chat = true
    P.ForgetAvailability()
    Check(not P.SearchRowAvailable("suite_chat", "msufsuite.chat.enabled", { kind = "toggle" })
        and not P.SearchRowAvailable("suite_chat", nil, { kind = "page" }),
        "an unavailable module stayed searchable")
    disabled.MSUF_Suite_Chat = nil
    P.ForgetAvailability()
end

local M = world.core.MSUF2
local api = M.Search._CoreAPI
do
    local config = Suite.Suite.Config("dataTexts")
    local original = Suite.CopyValue(config)
    local spec = Suite.SuiteCatalog.dataTexts
    local controlCount = #spec.controls
    Check(not P.SearchRowAvailable("suite_dataTexts", "msufsuite.dataTexts.bar4Name", {kind="textinput"}),
        "an unconfigured bar retained a visited-page search setting")
    for key, value in pairs(Suite.DataTextBarCreationValues(config, 13)) do config[key] = value end
    Suite.Suite.Normalize(Suite.DB)
    config.bar13Name = "Raid Analysis"
    local found, stale, action
    local actionId = P.Meta("suite_dataTexts", "dataTexts", "bar13.remove", "action", "suite_dataTexts_bar13").controlId
    for _, row in ipairs(P.SearchRows()) do
        if row.controlId == actionId then action = row end
        Check(not (row.controlId and row.sectionId == "suite_dataTexts_bar4"), "cold actions indexed an unconfigured bar")
        if row.settingKey == "msufsuite.dataTexts.bar13Name" then found = row end
        if row.settingKey == "msufsuite.dataTexts.bar4Name" then stale = row end
    end
    Check(found and not stale, "cold search did not match the dynamically configured bar inventory")
    Check(action and action.sectionId == "suite_dataTexts_bar13", "cold search omitted the exact dynamic remove action")
    local named = false
    for _, keyword in ipairs(found.keywords) do if keyword == "Raid Analysis" then named = true end end
    Check(named, "configured bar name is missing from its setting search words")
    for key, value in pairs(Suite.DataTextBarRemovalValues(config, 13)) do config[key] = value end
    Check(not P.SearchRowAvailable("suite_dataTexts", found.settingKey, {providerRow=found}),
        "a removed bar remained available through an already cached search row")
    Check(not P.SearchRowAvailable("suite_dataTexts", nil, {providerRow=action}), "removed bar retained its cached action")
    Check(not P.SearchRowAvailable("suite_dataTexts", nil, {kind="button",sectionId="suite_dataTexts_bar13"}), "removed bar retained a visited action")
    Check(#spec.controls == controlCount, "dynamic bar search permanently grew the global control list")
    Suite.DB.suite.modules.dataTexts = original
end
Check(P.searchRegistered == true, "the Suite provider did not register")
Check(api.GetSearchProviderCache() == nil, "Suite rows were collected at load instead of on the first search")

local function Search(query) return api.SearchPages(query) end
Check(Suite.SuiteCatalog.partyEffects == nil, "retired Celebrations remains in the catalog")
for _, query in ipairs({ "Celebrations", "When you or your pet cast Bloodlust", "Bloodlust" }) do
    for _, record in ipairs(Search(query)) do
        local key = record.exactTarget and record.exactTarget.settingKey
        Check(not key or not key:find("msufsuite.partyEffects.", 1, true), "search exposed retired Celebrations")
    end
end
local function CheckReleaseSearch(stage)
    for _, query in ipairs({ "release", "release protection", "freilassen", "releasen schutz", "geist freilassen", "release-schutz" }) do
        local found
        for index, record in ipairs(Search(query)) do
            if index <= 6 and record.key == "suite_qualityOfLife" and record.exactTarget
                and record.exactTarget.settingKey == "msufsuite.releaseProtection.enabled" then
                found = record
                break
            end
        end
        Check(found and (not found.provided
            or found.exactTarget.sectionId == "suite_qualityOfLife_releaseProtection_release_protection"),
            stage .. " search did not find the exact release protection switch: " .. query)
    end
end
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
for _, query in ipairs({ "mythic plus", "mythic+", "m+", "m+ mythic plus" }) do
    local results = Search(query)
    local timer, summary
    for i = 1, math.min(6, #results) do
        local rec = results[i]
        if rec.key == "suite_hud" and rec.label == "Mythic+ settings" then timer = rec end
        if rec.key == "suite_hud" and rec.label == "Mythic+ run summaries" then summary = rec end
    end
    if flavor == "Mainline" then
        Check(timer and timer.route and timer.route.accordion["suite_hud:suite_hud_objectives_module"],
            "'" .. query .. "' did not put the timer section in the search palette")
        Check(summary and summary.route and summary.route.accordion["suite_hud:suite_hud_runSummary_module"],
            "'" .. query .. "' did not put run summaries in the search palette")
        Check(timer.hint:find("^MSUF Suite > ") and summary.hint:find("^MSUF Suite > "),
            "'" .. query .. "' did not identify the Suite in its result breadcrumbs")
    else
        Check(not timer and not summary, "'" .. query .. "' exposed Retail-only HUD options")
    end
end
Check(api.GetSearchProviderCache().skipped == 0, "the host skipped Suite rows as malformed")
CheckReleaseSearch("unopened page")

-- Every alias of every page is a search word of that page (Register.lua only
-- fills M.ALIASES). Quality of Life aliases name features of both clients;
-- its features' own switch rows carry their words instead.
local pageRecords = {}
for _, rec in ipairs(api.GetSearchRecords()) do
    if rec.kind == "page" then pageRecords[rec.key] = rec end
end
local normalize = M.Search.Text.NormalizeSearchText
for _, page in ipairs(P.pages) do
    local rec = Check(pageRecords[page.key], "no page record for " .. page.key)
    for _, alias in ipairs(page.key ~= "suite_qualityOfLife" and page.aliases or {}) do
        Check((" " .. rec.haystack .. " "):find(" " .. normalize(alias) .. " ", 1, true),
            "alias '" .. alias .. "' is not a search word of " .. page.key)
    end
end

-- A disabled module of a shared page stays findable through its own switch
-- (through the host cache, after a controller setter); its settings leave.
do
    for _, id in ipairs({"runSummary", "announcements", "afkScreen"}) do
        Check(Suite.Suite.Set(id, "enabled", false), "could not disable HUD sibling: " .. id)
    end
    for _, case in ipairs({ {"run summaries", "runSummary"}, {"announcements", "announcements"}, {"afk screen", "afkScreen"} }) do
        local switch
        for _, row in ipairs(Search(case[1])) do
            if row.key == "suite_hud" and row.exactTarget
                and row.exactTarget.settingKey == "msufsuite." .. case[2] .. ".enabled" then switch = row end
        end
        Check(switch, "a disabled HUD module lost its enable switch in search: " .. case[1])
    end
    local activeSibling
    for _, row in ipairs(api.GetSearchRecords()) do
        local key = row.exactTarget and row.exactTarget.settingKey
        if key == "msufsuite.objectives.width" then activeSibling = row end
        Check(key ~= "msufsuite.announcements.zone", "a disabled HUD module kept its settings in the index")
    end
    Check(activeSibling, "active HUD sibling disappeared")
    for _, id in ipairs({"runSummary", "announcements", "afkScreen"}) do
        Check(Suite.Suite.Set(id, "enabled", true), "could not reenable HUD sibling: " .. id)
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
-- The FAQ answers how to turn the module on, so it stays while the module is off.
Check(Suite.Suite.Set("minimap", "enabled", false), "could not switch the Suite minimap off")
suiteFaq = false
for _, rec in ipairs(Search("enable minimap")) do
    if rec.kind == "faq" and rec.key == "suite_minimap" then suiteFaq = true end
end
Check(suiteFaq, "'enable minimap' lost the Suite answer while the Suite minimap is off")
Check(Suite.Suite.Set("minimap", "enabled", true), "could not switch the Suite minimap on")
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
-- Classic MSUF routes a color row to its section; Main MSUF anchors on the
-- section title.
Check(border and border.key == "suite_minimap" and border.kind == "color" and (border.exactTarget
    and border.exactTarget.sectionId == "suite_minimap_" .. catalog.minimap.rules.borderColor.section
    or border.exactTarget == nil and border.anchorFallback == M.Tr(catalog.minimap.rules.borderColor.sectionTitle)),
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
do
    local specialization
    for _, row in ipairs(rows) do
        Check(row.suiteModuleId ~= "mapQuickSwitch", "search still exposes the retired QoL module")
        if row.settingKey == "msufsuite.minimap.specButton" then specialization = row end
    end
    if flavor == "Forever" then
        Check(not specialization, "Forever search exposed Retail specialization settings")
    else
        Check(specialization and specialization.pageKey == "suite_minimap"
            and specialization.sectionId == "suite_minimap_specialization",
            "specialization search must target the exact Minimap accordion")
    end
end
local expectedQolRows, expectedQolCount, expectedCategories = {}, 0, {}
for _, feature in ipairs(Check(P.QualityOfLifeSearchFeatures,
    "the Quality of Life page did not publish its feature search inventory")) do
    local sectionId = "suite_qualityOfLife_" .. feature.id .. "_" .. feature.sections[1]
    Check(not expectedQolRows[sectionId] and not (P.Available(feature.id) and expectedQolRows[sectionId] == false),
        "duplicate Quality of Life feature inventory: " .. sectionId)
    if P.Available(feature.id) then
        expectedQolRows[sectionId] = "msufsuite." .. feature.id .. "." .. feature.switch
        expectedQolCount = expectedQolCount + 1
        expectedCategories["suite_qualityOfLife_category_" .. feature.category] = true
    end
end
local directQolRows, directQolCount, categoryRows = {}, 0, {}
for _, row in ipairs(rows) do
    if row.pageKey == "suite_qualityOfLife" and row.qolFeatureId then
        directQolCount = directQolCount + 1
        Check(row.kind == "toggle" and row.sectionId and not directQolRows[row.sectionId]
            and row.settingKey == expectedQolRows[row.sectionId],
            "Quality of Life feature search has no unique exact toggle target: " .. tostring(row.sectionId))
        directQolRows[row.sectionId] = row
    elseif row.pageKey == "suite_qualityOfLife" and row.kind == "section"
        and type(row.sectionId) == "string"
        and row.sectionId:find("^suite_qualityOfLife_category_") then
        Check(not categoryRows[row.sectionId], "duplicate Quality of Life category search row")
        categoryRows[row.sectionId] = row
    end
end
Check(directQolCount == expectedQolCount, "search omitted Quality of Life feature switches: " .. directQolCount)
for sectionId in pairs(expectedQolRows) do
    Check(directQolRows[sectionId], "search omitted Quality of Life feature: " .. sectionId)
end
local categoryCount = 0
for _ in pairs(categoryRows) do categoryCount = categoryCount + 1 end
local expectedCategoryCount = 0
for sectionId in pairs(expectedCategories) do
    expectedCategoryCount = expectedCategoryCount + 1
    Check(categoryRows[sectionId], "search omitted an available Quality of Life category: " .. sectionId)
end
Check(categoryCount == expectedCategoryCount, "search kept a Quality of Life category without features: " .. categoryCount)
for _, feature in ipairs(P.QualityOfLifeSearchFeatures) do
    local sectionId = "suite_qualityOfLife_" .. feature.id .. "_" .. feature.sections[1]
    local expectedKey = expectedQolRows[sectionId]
    local exact
    for _, rec in ipairs(api.GetSearchRecords()) do
        if rec.provided and rec.key == "suite_qualityOfLife" and rec.exactTarget
            and rec.exactTarget.settingKey == expectedKey
            and rec.exactTarget.sectionId == sectionId then
            exact = rec
            break
        end
    end
    if expectedKey then
        Check(exact, "indexed Quality of Life search target lost its stable feature route: " .. sectionId)
    else
        Check(not exact, "unavailable Quality of Life feature entered the index: " .. sectionId)
    end
end
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

-- Exercise the actual host cache through controller setters, addon availability
-- and profile activation. Calling the predicate alone cannot catch stale rows.
-- No page has been visited yet, so both hosts index provider rows only.
local function FindSetting(key)
    for _, record in ipairs(api.GetSearchRecords()) do
        if record.settingKey == key or record.exactTarget and record.exactTarget.settingKey == key then
            return record
        end
    end
end
do
    local switches, byModule = {}, {}
    for _, feature in ipairs(P.QualityOfLifeSearchFeatures) do
        switches["msufsuite." .. feature.id .. "." .. feature.switch] = true
    end
    local function Identity(record)
        return table.concat({ record.key or "", record.kind or "", record.label or "",
            record.settingKey or record.exactTarget and record.exactTarget.settingKey or "",
            record.exactTarget and record.exactTarget.controlId or "", record.sectionId or "" }, "|")
    end
    for _, record in ipairs(api.GetSearchRecords()) do
        local row = record.providerRow or {}
        local key = record.settingKey or record.exactTarget and record.exactTarget.settingKey
        local id, field
        if key then id, field = key:match("^msufsuite%.([^.]+)%.(.+)$") end
        id = row.suiteModuleId or id
        if id and catalog[id] and record.kind ~= "page" and field ~= "enabled"
            and not row.suiteModuleSwitch and not switches[key] then
            byModule[id] = byModule[id] or {}
            byModule[id][#byModule[id] + 1] = Identity(record)
        end
    end
    local checked = 0
    for _, id in ipairs(Suite.SuiteOrder) do
        local details = byModule[id]
        if details then
            local hadMaster = FindSetting("msufsuite." .. id .. ".enabled")
            Check(Suite.Suite.Set(id, "enabled", false), "could not disable " .. id)
            local indexed = {}
            for _, record in ipairs(api.GetSearchRecords()) do indexed[Identity(record)] = true end
            for _, identity in ipairs(details) do
                Check(not indexed[identity], "disabled module retained a cold detail: " .. id .. " " .. identity)
            end
            if hadMaster then
                Check(FindSetting("msufsuite." .. id .. ".enabled"), "disabled module lost its switch: " .. id)
            else
                local featureSwitches = 0
                for _, feature in ipairs(P.QualityOfLifeSearchFeatures) do
                    if feature.id == id then
                        local record = FindSetting("msufsuite." .. id .. "." .. feature.switch)
                        Check(record and record.kind == "toggle"
                            and (record.providerRow == nil or record.providerRow.suiteModuleSwitch),
                            "disabled aggregate module lost its feature switch: " .. id)
                        featureSwitches = featureSwitches + 1
                    end
                end
                Check(featureSwitches > 0, "module has neither a master nor a real feature switch: " .. id)
            end
            Check(Suite.Suite.Set(id, "enabled", true), "could not reenable " .. id)
            indexed = {}
            for _, record in ipairs(api.GetSearchRecords()) do indexed[Identity(record)] = true end
            for _, identity in ipairs(details) do
                Check(indexed[identity], "reenabled module lost a cold detail: " .. id .. " " .. identity)
            end
            checked = checked + 1
        end
    end
    Check(checked >= 20, "module filtering fixture covered too few available modules: " .. checked)
    Check(FindSetting("msufsuite.chat.fontSize"), "chat fixture has no font setting")
    disabled.MSUF_Suite_Chat = true
    P.Refresh()
    Check(not FindSetting("msufsuite.chat.fontSize"), "disabled addon retained cached details")
    disabled.MSUF_Suite_Chat = nil
    P.Refresh()
    Check(FindSetting("msufsuite.chat.fontSize"), "available addon did not regain its details")

    local original = Suite.Database.GetActiveProfileName()
    Check(Suite.Database.Create("Search disabled module", true), "could not create test profile")
    Suite.Database.GetProfile("Search disabled module").suite.modules.chat.enabled = false
    Check(Suite.Database.Activate("Search disabled module"), "could not activate test profile")
    Check(not FindSetting("msufsuite.chat.fontSize"), "profile activation retained previous module details")
    Check(FindSetting("msufsuite.chat.enabled"), "profile activation hid the module switch")
    Check(Suite.Database.Activate(original), "could not restore test profile")
    Check(FindSetting("msufsuite.chat.fontSize"), "profile restoration did not rebuild search")
    local config = Suite.Suite.Config("dataTexts")
    local saved = Suite.CopyValue(config)
    local count = #catalog.dataTexts.controls
    local hadPage = M.cache and M.cache.suite_dataTexts
    for _,id in ipairs(Suite.DataTextBarIDs(config)) do
        Check(Suite.Suite.SetMany("dataTexts",Suite.DataTextBarRemovalValues(config,id)), "could not clear configured bar inventory")
    end
    local ids = {400000}
    for id=13,31 do ids[#ids+1]=id end
    for _, id in ipairs(ids) do
        Check(Suite.Suite.SetMany("dataTexts", Suite.DataTextBarCreationValues(config,id)), "could not configure dynamic search bar")
    end
    Check(Suite.Suite.Set("dataTexts", "bar400000Name", "Raid Analysis"), "could not name high-ID bar")
    Check(#Suite.DataTextBarIDs(config)==20,"dynamic fixture must have exactly twenty configured bars")
    local dynamicRows=P.SearchRows()
    local providerNames={}
    for name in pairs(collectors) do providerNames[#providerNames+1]=name end
    table.sort(providerNames)
    Check(#providerNames==17,"provider partition cardinality must remain fixed for 256 bars")
    local total,maxGroup,baseRows=0,0,0
    local perBar={}
    for _,row in ipairs(dynamicRows) do
        local bar=row.pageKey=="suite_dataTexts" and ((row.suiteRuleKey or ""):match("^bar(%d+)") or (row.sectionId or ""):match("^suite_dataTexts_bar(%d+)$"))
        if bar then perBar[bar]=(perBar[bar] or 0)+1 end
    end
    local maxPerBar=0
    for _,count in pairs(perBar) do maxPerBar=math.max(maxPerBar,count) end
    Check(Suite.DataTextBarLimit==256 and maxPerBar*16<=4000,"bounded sixteen-bar partition cannot fit maximum structural inventory")
    for _,name in ipairs(providerNames) do
        local part=collectors[name]()
        Check(#part<=4000,"provider partition exceeded the unchanged host limit: "..name)
        total=total+#part;maxGroup=math.max(maxGroup,#part)
        if name=="MSUF_Suite" then baseRows=#part end
    end
    Check(total==#dynamicRows,"provider partitions lost or duplicated Suite rows")
    print("suite search dynamic coverage: "..#dynamicRows.." rows / 20 configured bars; 17 fixed providers, base "..baseRows..", max part "..maxGroup..", max per bar "..maxPerBar)
    Search("data texts") -- Warm actual host context predicates after the profile/configuration changes.
    for name in pairs(collectors) do collectionCalls[name]=0 end
    P.InvalidateSearch()
    Check(FindSetting("msufsuite.dataTexts.bar400000Name"), "high-ID bar missing from host cache")
    for name in pairs(collectors) do Check(collectionCalls[name]==1,"host failed to collect the fresh complete provider partition: "..name) end
    Check(api.GetSearchProviderCache().skipped==0 and FindSetting("msufsuite.actionTracker.rows"), "dynamic inventory truncated later Suite modules")
    local named
    for _, record in ipairs(Search("Raid Analysis")) do
        if record.key=="suite_dataTexts" and record.route and record.route.accordion["suite_dataTexts:suite_dataTexts_bar400000"] then named=record end
    end
    Check(named, "named high-ID bar missing from actual query")
    Search("Raid");Search("Raid Analysis");Search("data text")
    for name in pairs(collectors) do Check(collectionCalls[name]==1,"query recollected rows without configuration invalidation: "..name) end
    Check((M.cache and M.cache.suite_dataTexts)==hadPage and #catalog.dataTexts.controls==count, "search built UI or grew global controls")
    Check(Suite.Suite.SetMany("dataTexts",Suite.DataTextBarRemovalValues(config,400000)), "could not remove high-ID bar")
    Check(not FindSetting("msufsuite.dataTexts.bar400000Name"), "removed high-ID bar retained host rows")
    Check(Suite.Database.Create("Search empty bars",true), "could not create dynamic test profile")
    local other=Suite.Database.GetProfile("Search empty bars").suite.modules.dataTexts
    other.barIds="0"
    for _,id in ipairs(Suite.DataTextBarIDs(other)) do other["bar"..id.."Enabled"]=false end
    Check(Suite.Database.Activate("Search empty bars"), "could not switch dynamic test profile")
    Check(not FindSetting("msufsuite.dataTexts.bar13Name"), "profile switch retained old configured bars")
    Check(Suite.Database.Activate(original) and FindSetting("msufsuite.dataTexts.bar13Name"), "profile switch failed to restore dynamic rows")
    Suite.DB.suite.modules.dataTexts=saved
    P.Refresh()
end

-- Search navigation must open a cold QoL page, select its category/tab, and
-- build the exact setting widget before resolving it. The client-world harness
-- omits a few native Widget methods and window chrome; supply only those API
-- surfaces for this route test.
do
    local createFrame = env.CreateFrame
    env.CreateFrame = function(kind, ...)
        local frame = createFrame(kind, ...)
        local createFontString = frame.CreateFontString
        if createFontString then
            frame.CreateFontString = function(self, ...)
                local text = createFontString(self, ...)
                text.GetUnboundedStringWidth = text.GetUnboundedStringWidth or function(region)
                    return region:GetStringWidth()
                end
                return text
            end
        end
        if kind == "Button" then
            frame.Click = frame.Click or function(self, button)
                local handler = self:GetScript("OnClick")
                if handler then return handler(self, button or "LeftButton") end
            end
        elseif kind == "CheckButton" then
            frame.SetChecked = function(self, value) self._checked = value end
            frame.GetChecked = function(self) return self._checked end
        elseif kind == "Slider" then
            frame.SetValueStep = frame.SetValueStep or function() end
            frame.SetMinMaxValues = function(self, lo, hi) self._min, self._max = lo, hi end
            frame.GetMinMaxValues = function(self) return self._min or 0, self._max or 1 end
            frame.SetValue = function(self, value) self._value = value end
            frame.GetValue = function(self) return self._value or 0 end
        elseif kind == "EditBox" then
            frame.SetAutoFocus = frame.SetAutoFocus or function() end
            frame.SetNumeric = frame.SetNumeric or function() end
            frame.SetMaxLetters = frame.SetMaxLetters or function(self, value) self._maxLetters=value end
            frame.HasFocus = frame.HasFocus or function() return false end
        end
        return frame
    end
    M.SetActivePageHeader = M.SetActivePageHeader or function() end
    M.RunStickyHeaderActivation = M.RunStickyHeaderActivation or function() end
    M.SetTitle, M.UpdateNav = function() end, function() end
    M.scrollChild = env.CreateFrame("Frame", nil, env.UIParent)
    M.frame = env.CreateFrame("Frame", nil, env.UIParent)
    M.frame:Show()

    if M.InvalidateSearchProvider then
        local config=Suite.Suite.Config("dataTexts")
        local saved=Suite.CopyValue(config)
        Check(Suite.Suite.SetMany("dataTexts",Suite.DataTextBarCreationValues(config,400000)), "could not configure action route bar")
        local wanted=P.Meta("suite_dataTexts","dataTexts","bar400000.remove","action","suite_dataTexts_bar400000").controlId
        local target
        for _, record in ipairs(api.GetSearchRecords()) do
            if record.exactTarget and record.exactTarget.controlId==wanted then target=record;break end
        end
        Check(target, "cold high-ID remove action has no exact host target")
        local selected,anchored,exact=api.OpenSearchTarget(target.key,target.label,target.anchorFallback or target.label,target.anchor,target.route,target.exactTarget)
        world.widgets:RunTimers(80)
        Check(selected and anchored and exact and M.activeKey=="suite_dataTexts", "dynamic action failed to focus its real control")
        Check(config.bar400000Enabled==true, "search executed the remove action")
        Suite.DB.suite.modules.dataTexts=saved;P.Refresh()
    end
    -- Navigation runs through the host's routing and rendering. The harness
    -- loads only Main's IndexQuery into the Classic menu, so opening targets is
    -- checked against the Classic host; the index checks below run on both.
    if searchHost == classic then
        if flavor == "Mainline" then
            for _, case in ipairs({
                { label = "Mythic+ settings", sectionId = "suite_hud_objectives_module", prefix = "objectives" },
                { label = "Mythic+ run summaries", sectionId = "suite_hud_runSummary_module", prefix = "summary" },
            }) do
                local target
                for i, record in ipairs(Search("mythic plus")) do
                    if i <= 6 and record.key == "suite_hud" and record.label == case.label then
                        target = record
                        break
                    end
                end
                Check(target, "Mythic+ HUD shortcut disappeared after its page was built")
                local selected, anchored = api.OpenSearchTarget(target.key, target.label,
                    target.anchorFallback or target.label, target.anchor, target.route, target.exactTarget)
                world.widgets:RunTimers(80)
                local entry = M.cache and M.cache.suite_hud
                local section = entry and entry.sections and entry.sections[case.sectionId]
                Check(selected and anchored and M.activeKey == "suite_hud"
                    and section and section._msuf2CollapsibleEntry.open == true,
                    "Mythic+ search did not open the HUD section: " .. case.sectionId)
                local tabs = assert(section._msufSuiteHUDTabs)
                tabs.select("suite_hud_" .. case.prefix .. "_type")
                Check(tabs.panels["suite_hud_" .. case.prefix .. "_type"]:IsShown(),
                    "HUD warm-routing setup did not select Appearance")
                api.OpenSearchTarget(target.key, target.label,
                    target.anchorFallback or target.label, target.anchor, target.route, target.exactTarget)
                world.widgets:RunTimers(80)
                Check(tabs.panels["suite_hud_" .. case.prefix .. "_content"]:IsShown(),
                    "Mythic+ shortcut kept the previously selected HUD tab")
            end
        end

        local function RouteExact(settingKey, expectedTab, expectedSection)
            local target
            for _, record in ipairs(api.GetSearchRecords()) do
                if record.key == "suite_qualityOfLife"
                    and record.exactTarget and record.exactTarget.settingKey == settingKey then
                    target = record
                    break
                end
            end
            Check(target, "no exact Quality of Life search record: " .. settingKey)
            local selected, anchored, exact = api.OpenSearchTarget(target.key, target.label,
                target.anchorFallback or target.label, target.anchor, target.route, target.exactTarget)
            world.widgets:RunTimers(80)
            local entry = M.cache and M.cache.suite_qualityOfLife
            local feature = entry and entry.qualityOfLifeFeatureRows[expectedSection or target.exactTarget.sectionId]
            local category = feature and entry.sections["suite_qualityOfLife_category_" .. feature.category]
            local _, widget = M.RuntimeControlCatalog.FindBySettingKey(
                settingKey, "suite_qualityOfLife", target.exactTarget)
            Check(selected and anchored and exact and widget,
                "Quality of Life search did not focus exact setting: " .. settingKey)
            Check(feature and feature.details and feature.tab == expectedTab
                and feature.row:GetParent():IsShown() and feature.details:IsShown(),
                "Quality of Life search did not reveal the correct feature tab: " .. settingKey)
            Check(category and category._msuf2CollapsibleEntry.open == true,
                "Quality of Life search left its category closed: " .. settingKey)
        end

        Check(M.cache.suite_qualityOfLife == nil, "Quality of Life page unexpectedly warm before exact search")
        RouteExact("msufsuite.releaseProtection.enabled", "main")
        RouteExact("msufsuite.releaseProtection.modifier", "main", "suite_qualityOfLife_releaseProtection_release_protection")
        RouteExact("msufsuite.actionTracker.rows", "main")
        RouteExact("msufsuite.qol.junkReport", "merchants")
        if flavor == "Mainline" then
            RouteExact("msufsuite.tooltipDetails.unitMount", "main", "suite_qualityOfLife_tooltipDetails_tooltip_details")
            RouteExact("msufsuite.tooltipDetails.unitMountOwned", "main", "suite_qualityOfLife_tooltipDetails_tooltip_details")
        end
        -- Edit Mode must scroll to the feature's settings card below the list,
        -- rather than the parent category header. Exercise the real host routing.
        do
            local entry = M.cache.suite_qualityOfLife
            local previousScroll, previousTop, previousHeight = M.scrollFrame, entry.wrapper.GetTop, M.scrollChild.GetHeight
            local offset
            M.scrollFrame = env.CreateFrame("ScrollFrame", nil, env.UIParent)
            M.scrollFrame:SetHeight(400)
            M.scrollFrame.SetVerticalScroll = function(_, value) offset = value end
            M.scrollChild.GetHeight = function() return 2400 end
            entry.wrapper.GetTop = function() return 1200 end
            for _, case in ipairs({
                { "combatStatsHUD", "secondary_stats", "character" },
                { "durabilityAlert", "durability_warning", "gear" },
                { "actionTracker", "action_tracker", "main" },
            }) do
                local sectionId = "suite_qualityOfLife_" .. case[1] .. "_" .. case[2]
                local details = entry._msuf2ResolveMissingSection(sectionId)
                local previousDetailTop = details.GetTop
                details.GetTop = function() return 700 end
                local category = details._msuf2CollapsibleEntry
                category.open = false
                category.body:Hide()
                offset = nil
                Check(Suite.Menu.FocusQualityOfLifeModule(case[1]), "Edit Mode detail route failed: " .. case[1])
                world.widgets:RunTimers(80)
                local feature = entry.qualityOfLifeFeatureRows[sectionId]
                Check(offset == 456 and category.open and details:IsShown()
                    and feature.tab == case[3] and feature.row:GetParent():IsShown(),
                    "Edit Mode did not scroll directly to its visible settings card: " .. case[1])
                details.GetTop = previousDetailTop
            end
            M.scrollFrame, entry.wrapper.GetTop, M.scrollChild.GetHeight = previousScroll, previousTop, previousHeight
        end
        CheckReleaseSearch("visited page")
        for _, settingKey in ipairs({ "msufsuite.actionTracker.rows", "msufsuite.qol.junkReport" }) do
            local matches = 0
            for _, record in ipairs(api.GetSearchRecords()) do
                if record.key == "suite_qualityOfLife" and record.exactTarget
                    and record.exactTarget.settingKey == settingKey then
                    matches = matches + 1
                end
            end
            Check(matches == 1, "opened Quality of Life setting has duplicate search rows: " .. settingKey)
        end
    end
    for _, case in ipairs({
        { "action tracker", "msufsuite.actionTracker.enabled" },
        { "keystone command", "msufsuite.mythicKeyShare.enabled" },
        { "loot history", "msufsuite.loot.manageHistory" },
    }) do
        local moduleId = case[2]:match("^msufsuite%.([^.]+)%.")
        if P.Available(moduleId) then
            local first = Search(case[1])[1]
            Check(first and first.key == "suite_qualityOfLife" and first.exactTarget
                and first.exactTarget.settingKey == case[2],
                "Quality of Life search did not put the feature first: " .. case[1])
        else
            Check(not FindSetting(case[2]), "unavailable client feature remained searchable: " .. case[1])
        end
    end
    if M.RegisterSearchAvailability then
        Check(Suite.Suite.Set("qol", "autoJunk", false), "could not disable visited QoL subfeature")
        Check(not FindSetting("msufsuite.qol.junkReport"), "disabled subfeature retained its live detail")
        Check(FindSetting("msufsuite.qol.autoJunk") and FindSetting("msufsuite.qol.guildRepair"),
            "disabling one subfeature hid its switch or another feature in the same module")
        Check(Suite.Suite.Set("qol", "autoJunk", true), "could not reenable visited QoL subfeature")
        Check(FindSetting("msufsuite.qol.junkReport"), "reenabled subfeature did not return")
        Check(Suite.Suite.Set("actionTracker", "enabled", false), "could not disable visited feature")
        Check(not FindSetting("msufsuite.actionTracker.rows"), "visited disabled feature retained a live setting")
        Check(FindSetting("msufsuite.actionTracker.enabled"), "visited disabled feature lost its switch")
        for _, record in ipairs(api.GetSearchRecords()) do
            Check(not (record.key == "suite_qualityOfLife" and record.kind ~= "toggle"
                and record.sectionId == "suite_qualityOfLife_actionTracker_main"),
                "visited disabled feature retained a live action or section")
        end
        Check(Suite.Suite.Set("actionTracker", "enabled", true), "could not reenable visited feature")
        Check(FindSetting("msufsuite.actionTracker.rows"), "visited reenabled feature did not return")

        -- The visited Repair/Sell junk rows own separate switches; there is
        -- no qol.enabled widget. Both survive when their backing module is off.
        Check(Suite.Suite.Set("qol", "enabled", false), "could not disable visited aggregate module")
        Check(not FindSetting("msufsuite.qol.junkReport"), "visited disabled aggregate retained a detail")
        local featureSwitches = 0
        for _, feature in ipairs(P.QualityOfLifeSearchFeatures) do
            if feature.id == "qol" then
                local settingKey = "msufsuite.qol." .. feature.switch
                local record = FindSetting(settingKey)
                Check(record, "visited disabled aggregate lost its feature switch: " .. feature.switch)
                local _, widget = M.RuntimeControlCatalog.FindBySettingKey(
                    settingKey, "suite_qualityOfLife", record.exactTarget)
                Check(widget, "aggregate search switch has no real visited widget: " .. feature.switch)
                featureSwitches = featureSwitches + 1
            end
        end
        Check(featureSwitches > 0, "visited aggregate fixture exercised no feature switches")
        Check(Suite.Suite.Set("qol", "enabled", true), "could not reenable visited aggregate module")
        Check(FindSetting("msufsuite.qol.junkReport"), "visited reenabled aggregate detail did not return")
    end
end

-- The Retail hook isolates a broken optional provider from the menu search.
if searchHost ~= classic then
    local calls = 0
    M.RegisterSearchProvider("broken-test", function()
        calls = calls + 1
        error("expected provider failure")
    end)
    Check(#api.GetSearchRecords() > 0 and calls == 1,
        "a failing search provider broke the index")
    Check(#api.GetSearchRecords() > 0 and calls == 1,
        "a failing search provider was repeatedly called")
    M.RegisterSearchProvider("broken-test", nil)
end

-- Use the shipped German translations while retaining every English term.
-- Only the translation delegate changes; provider, host cache and query engine are real.
do
    local german={}
    local localeEnv={MSUF_NS={LOCALE="deDE",RegisterLocale=function() return german end}}
    setmetatable(localeEnv,{__index=env});localeEnv._G=localeEnv
    local chunk=assert(loadfile(root.."/MSUF_Suite/Locales/deDE.lua"))
    setfenv(chunk,localeEnv);chunk()
    local nativeTr=M.Tr
    M.Tr=function(text) return german[text] or nativeTr(text) end
    P.InvalidateSearch()
    for _, case in ipairs({
        {"Datenleisten","suite_dataTexts"},{"data texts","suite_dataTexts"},
        {"Schadensmesser","suite_damageMeter"},{"damage meter","suite_damageMeter"},
        {"Questtracker","suite_hud"},{"quest tracker","suite_hud"},
        {"empfangene Buffs","suite_cooldownManager"},{"cooldown manager","suite_cooldownManager"},
    }) do
        local found
        for _, record in ipairs(Search(case[1])) do if record.key==case[2] then found=record;break end end
        Check(found,"bilingual page query missed its exact owner: "..case[1])
    end
    for _,case in ipairs({{"Dungeonportale","dungeonPortals"},{"Charakterfenster","characterExtras"}}) do
        local found
        for _,record in ipairs(Search(case[1])) do
            if record.exactTarget and record.exactTarget.settingKey=="msufsuite."..case[2]..".enabled" then found=record;break end
        end
        Check((found ~= nil) == (P.Available(case[2]) == true and Suite.Suite.Config(case[2]).enabled == true),
            "German feature alias did not follow client availability: "..case[1])
    end
    local seen={}
    for _,row in ipairs(P.SearchRows()) do
        if row.controlId then seen[row.controlId]=row end
        if row.settingKey=="msufsuite.tooltipDetails.unitMount" then
            Check(row.label==german["Currently ridden mount in unit tooltips (out of combat)"], "mount label did not use shipped translation")
            local english=false
            for _,word in ipairs(row.keywords) do if word=="Currently ridden mount in unit tooltips (out of combat)" then english=true end end
            Check(english,"translated mount row lost the English query words")
        end
    end
    for _,case in ipairs({
        {"chat","clearHistory","suite_chat_tools","Clear saved chat history"},
        {"dataTexts","chooseSeasonStages","suite_dataTexts_sources","Choose observed seasonal stages"},
    }) do
        local id=P.Meta(P.catalog[case[1]].page,case[1],case[2],"action",case[3]).controlId
        Check(seen[id] and seen[id].label==german[case[4]],"new action has no translated exact target: "..case[2])
    end
    -- The run history action exists only where the catalog offers Mythic+ results.
    local summary=P.catalog.runSummary
    local history=P.Meta(summary.page,"runSummary","action.history","action","suite_hud_runSummary_module").controlId
    if summary.rules.showMythicPlus then
        Check(german["Open run history"] and seen[history] and seen[history].label==german["Open run history"],
            "run history action has no translated exact target")
    else
        Check(not seen[history],"run history action indexed without Mythic+ results")
    end
    M.Tr=nativeTr
    P.InvalidateSearch()
    -- The German words come from the German pack, not from the English word
    -- lists: an English client does not match them.
    for _, case in ipairs({{"Schadensmesser","suite_damageMeter"},{"empfangene Buffs","suite_cooldownManager"},
        {"Datenleisten","suite_dataTexts"},{"Infoleiste","suite_dataTexts"}}) do
        for _, record in ipairs(Search(case[1])) do
            Check(record.key~=case[2],"an English client matched the German word "..case[1])
        end
    end
end

-- Every shipped locale exercises the combined Core/Suite query path, including
-- the actual optional-page examples, conversational input, and translated FAQ.
do
    local locales = { "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
    local questions = {
        enUS="where are my bags", enGB="where are my bags", deDE="wo sind meine taschen",
        esES="dónde están mis bolsas", esMX="dónde están mis bolsas", frFR="où sont mes sacs",
        itIT="dove sono le mie borse", ptBR="onde estão minhas bolsas", ruRU="где мои сумки",
        koKR="가방 설정은 어디에 있나요", zhCN="背包设置在哪里", zhTW="背包設定在哪裡",
    }
    local faq = {
        {"suite_minimap", "The Suite Minimap page styles the minimap itself: size, shape, border, zoom, buttons and info texts. MSUF's own minimap icon is under Miscellaneous."},
        {"suite_nameplates", "The Suite Nameplates page styles Blizzard's enemy and friendly nameplates. MSUF's aura filters only decide whether nameplate-only auras show on MSUF frames."},
        {"suite_cooldownManager", "The Suite Cooldown manager page (CDM) shows Blizzard's tracked cooldowns and buffs as bars you arrange and style freely."},
    }
    local pageModules = { suite_bags="bags", suite_cooldownManager="cooldownManager", suite_minimap="minimap", suite_nameplates="nameplates" }
    local originalTr, originalLocale = M.Tr, world.core.LOCALE
    local enabled = {}
    for _, id in ipairs({"bags", "cooldownManager", "minimap", "nameplates"}) do
        enabled[id] = Suite.Suite.Config(id).enabled
        Suite.Suite.Config(id).enabled = true
    end
    local function ContainsOwner(query, page)
        for _, row in ipairs(Search(query)) do if row.key == page then return true end end
        return false
    end
    for _, locale in ipairs(locales) do
        local translations = {}
        local localeEnv = { MSUF_NS = { LOCALE=locale, RegisterLocale=function() return translations end } }
        setmetatable(localeEnv, {__index=env}); localeEnv._G=localeEnv
        local chunk = assert(loadfile(classic .. "/MidnightSimpleUnitFrames/Locales/" .. locale .. ".lua"))
        setfenv(chunk,localeEnv); chunk()
        if locale ~= "enUS" and locale ~= "enGB" then
            chunk = assert(loadfile(root .. "/MSUF_Suite/Locales/" .. locale .. ".lua"))
            setfenv(chunk,localeEnv); chunk()
        end
        M.Tr=function(text) return translations[text] or text end
        world.core.LOCALE=locale
        P.InvalidateSearch()
        local examples = assert(M.SearchData.SEARCH_EXAMPLES[locale])
        for _, example in ipairs(examples) do
            local page = example[3]
            if page == "suite_bags" or page == "suite_cooldownManager" then
                Check(ContainsOwner(example[2], page) == P.Available(pageModules[page]),
                    locale .. ": Suite example disagrees with client availability for " .. page .. ": " .. example[2])
            end
        end
        -- Conversational parsing is the host's: the harness pairs Main's index
        -- with Classic's language data, so only the Classic host answers it.
        if searchHost == classic then
            Check(ContainsOwner(questions[locale], "suite_bags") == P.Available("bags"),
                locale .. ": natural Suite question disagrees with bags availability: " .. questions[locale])
        end
        local answers = {}
        for _, row in ipairs(api.GetSearchRecords()) do
            if row.kind == "faq" and row.answer then answers[row.key .. "\031" .. row.answer] = true end
        end
        for _, entry in ipairs(faq) do
            local translated = translations[entry[2]] or entry[2]
            Check((answers[entry[1] .. "\031" .. translated] == true) == P.Available(pageModules[entry[1]]),
                locale .. ": translated Suite FAQ disagrees with client availability: " .. entry[1])
            if locale ~= "enUS" and locale ~= "enGB" then
                Check(translated ~= entry[2], locale .. ": Suite FAQ fell back to English: " .. entry[1])
            end
        end
        Suite.Suite.Config("bags").enabled=false
        Suite.Suite.Config("cooldownManager").enabled=false
        P.InvalidateSearch()
        -- Off modules answer with their page and switch only, never details.
        for _, example in ipairs(examples) do
            local page = example[3]
            if page == "suite_bags" or page == "suite_cooldownManager" then
                for _, row in ipairs(Search(example[2])) do
                    local key = row.exactTarget and row.exactTarget.settingKey or ""
                    Check(row.key ~= page or row.kind == "page" or row.kind == "faq" or key:match("%.enabled$"),
                        locale .. ": a Suite module that is off kept a detail in an example query: " .. example[2])
                end
                -- MSUF folds Latin letters only, so the Cyrillic page title
                -- "Сумки" cannot answer "сумки" once no detail row matches.
                if page == "suite_bags" and locale ~= "ruRU" then
                    Check(ContainsOwner(example[2], page) == P.Available("bags"),
                        locale .. ": bags that are off lost their page for their own name: " .. example[2])
                end
            end
        end
        for _, row in ipairs(Search(questions[locale])) do
            local key = row.exactTarget and row.exactTarget.settingKey or ""
            Check(row.key ~= "suite_bags" or row.kind == "page" or row.kind == "faq" or key:match("%.enabled$"),
                locale .. ": bags that are off kept a detail in the natural question")
        end
        Suite.Suite.Config("bags").enabled=true
        Suite.Suite.Config("cooldownManager").enabled=true
        P.InvalidateSearch()
        print(locale .. ": combined Suite examples, natural query, 3 FAQ translations and disabled modules OK")
    end
    M.Tr, world.core.LOCALE = originalTr, originalLocale
    for id, value in pairs(enabled) do Suite.Suite.Config(id).enabled=value end
    P.InvalidateSearch()
end

-- With every Suite module off, search keeps only what turns them back on:
-- pages, FAQ answers, enable switches and Quality of Life categories, and the
-- Skinning page's two maintenance actions, which need no Skin addon. With
-- their AddOns off it keeps nothing of the Suite but those two. The Main host
-- cannot filter widgets of pages already visited (it has no availability
-- hook), so the visited-cache checks need that hook.
local MAINTENANCE_LABELS = { [M.Tr("Save setup as\226\128\166")] = true, [M.Tr("Restore chat colors")] = true }
local function MaintenanceRows(rows)
    local found = 0
    for _, row in ipairs(rows) do
        if row.suiteAlways then
            Check(row.pageKey == "suite_skin" and row.kind == "button" and MAINTENANCE_LABELS[row.label],
                "an always-found Suite row is not a Skinning maintenance action: " .. tostring(row.label))
            found = found + 1
        end
    end
    return found
end
do
    local savedEnabled, savedDisabled, skinEnabled = {}, {}, Suite.Skin.enabled
    for _, id in ipairs(Suite.SuiteOrder) do
        savedEnabled[id] = Suite.Suite.Config(id).enabled
        Suite.Suite.Config(id).enabled = false
    end
    for name, value in pairs(disabled) do savedDisabled[name] = value end
    disabled.MSUF_Suite_Skin = true
    Suite.Skin.enabled = false
    P.Refresh()
    local offRows = P.SearchRows()
    Check(#offRows > 0, "modules that are off lost their pages and switches")
    Check(MaintenanceRows(offRows) == 2, "Save setup as or Restore chat colors is not found without the Skin addon")
    for _, row in ipairs(offRows) do
        local key = row.settingKey or ""
        local switch = key:match("%.enabled$") or row.suiteModuleSwitch
            or (row.sectionId or ""):match("^suite_qualityOfLife_category_")
        Check(row.kind == "page" or row.kind == "faq" or switch or row.suiteAlways,
            "modules that are off kept a cold detail: " .. tostring(row.pageKey) .. " " .. tostring(row.label))
    end
    if M.RegisterSearchAvailability then
        for _, row in ipairs(api.GetSearchRecords()) do
            local key = row.exactTarget and row.exactTarget.settingKey or ""
            local provider = row.providerRow or {}
            Check(not row.key:match("^suite_") or row.kind == "page" or row.kind == "faq" or row.kind == "section"
                or key:match("%.enabled$") or provider.suiteModuleSwitch or provider.suiteAlways
                or key:match("^msufsuite%.qol%.") or key:match("^msufsuite%.loot%."),
                "Suite-off cache retained " .. row.kind .. " on " .. row.key)
        end
    end
    Check(#Search("target width") > 0, "Suite-off search lost Core settings")
    for id, value in pairs(savedEnabled) do Suite.Suite.Config(id).enabled = value end
    Suite.Skin.enabled = skinEnabled
    for name in pairs(disabled) do disabled[name] = nil end
    for name, value in pairs(savedDisabled) do disabled[name] = value end
    P.Refresh()
    Check(FindSetting("msufsuite.chat.fontSize"), "reenabled Suite failed to restore cached settings")

    -- Blizzard's current-character AddOn switch also gates loaded provider rows.
    for _, id in ipairs(Suite.SuiteOrder) do disabled[catalog[id].addon] = true end
    disabled.MSUF_Suite_Skin = true
    local addonOffRows = P.SearchRows()
    Check(#addonOffRows == 2 and MaintenanceRows(addonOffRows) == 2, "Suite AddOns that are off still provided rows")
    if M.RegisterSearchAvailability then
        Search("suite")
        local maintenance = 0
        for _, row in ipairs(api.GetSearchRecords()) do
            local always = row.providerRow and row.providerRow.suiteAlways
            if always then maintenance = maintenance + 1 end
            Check(not row.key:match("^suite_") or always, "AddOn-off cache retained " .. row.kind .. " on " .. row.key)
        end
        Check(maintenance == 2, "search does not find Save setup as and Restore chat colors without the Skin addon")
    end
    for name in pairs(disabled) do disabled[name] = nil end
    for name, value in pairs(savedDisabled) do disabled[name] = value end
    P.Refresh()
    Check(FindSetting("msufsuite.chat.fontSize"), "restored AddOn state did not restore Suite search")

    local before = 0
    for _, count in pairs(collectionCalls) do before = before + count end
    env.InCombatLockdown = function() return true end
    -- The hosts do no search work in combat; the Suite needs no gate of its own.
    Check(#Search("minimap") == 0 and (not M.RegisterSearchAvailability or #api.GetSearchRecords() == 0),
        "combat performed search work")
    local after = 0
    for _, count in pairs(collectionCalls) do after = after + count end
    Check(after == before, "combat invoked a Suite provider")
    env.InCombatLockdown = function() return false end
end

print("suite_search_provider_contract: ok (" .. #rows .. " rows; every page by name and alias)")
print(table.concat(shown, "\n"))
