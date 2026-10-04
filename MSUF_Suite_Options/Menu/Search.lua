local _, P = ...
-- Rows for MSUF's menu search. Every Suite page with its aliases and the words
-- players use for it, and every catalog setting and section, so a Suite
-- setting is found before its page was ever opened. MSUF calls the provider
-- on the first search (and again after a language change), never at load.
-- An MSUF build without the provider hook simply gets no rows.
-- Classic MSUF asks the provider whether its context changed and can drop one
-- provider's cached rows; Main MSUF keeps the rows until the provider
-- registers again, so P.InvalidateSearch registers it again there.
local Suite, M, Tr = P.Suite, P.M, P.Tr
if type(M.RegisterSearchProvider) ~= "function" then return end

-- Words for a page that its title and aliases miss, matched as typed.
-- "minimap" alone also finds MSUF's own minimap icon; Suite pages carry the
-- word "suite" and a "MSUF Suite" breadcrumb so both results read apart.
local SUITE_WORDS = { "suite", "msuf suite", "suite module", "suite modules" }
local PAGE_WORDS = {
    suite_minimap = "minimap|mini map|map|minimap module|map border|map buttons",
    suite_nameplates = "nameplate|nameplates|name plate|name plates|plates|enemy nameplates|friendly nameplates",
    suite_cooldownManager = "cooldown manager|cooldowns|cdm|cooldown bars|cooldown icons|buff bars|tracked buffs",
    suite_buffReminders = "buff reminder|buff reminders|missing buffs|consumables|flask|food|augment rune",
    suite_chat = "chat|chat frame|chat window|chat tabs|chat font",
    suite_bags = "bags|bag|inventory|backpack|reagent bag|item level",
    suite_actionbars = "action bar|action bars|actionbar|actionbars|hotbar|hotbars|keybinds|stance bar|pet bar",
    suite_damageMeter = "damage meter|damage meters|meter|meters|dps meter|healing meter",
    suite_dataTexts = "data text|data texts|datatext|datatexts|info bar|info texts",
    suite_skin = "skin|skins|skinning|window skin|blizzard windows",
    suite_qualityOfLife = "quality of life|qualityoflife|quality_of_life|qol|comfort|helpers",
    suite_hud = "hud",
}
-- Words players use for a page in their own language: each English word is
-- searchable in English and, through the locale packs, as its translation.
local PAGE_TRANSLATED_WORDS = {
    suite_cooldownManager = { "received buffs" },
    suite_damageMeter = { "damage meter" },
    suite_dataTexts = { "data text", "data texts", "info bar", "info bars" },
}
local HUD_MODULE_WORDS = {
    objectives = "objective tracker|quest tracker|questtracker|objectives",
    runSummary = "mythic plus summary|raid boss kill summary|run summary|raid kill",
    announcements = "announcements|events",
    afkScreen = "afk screen|afk",
}
-- Questions MSUF's own help also answers ("minimap" is its icon too). Each
-- answer names the Suite page, so the two answers read apart.
local FAQ = {
    { page = "suite_minimap", label = "Where are the Suite minimap settings?",
        help = "The Suite Minimap page styles the minimap itself: size, shape, border, zoom, buttons and info texts. MSUF's own minimap icon is under Miscellaneous.",
        words = "minimap|minimap settings|enable minimap|turn on minimap|minimap shape|square minimap|minimap size|minimap buttons" },
    { page = "suite_nameplates", label = "Where are the nameplate settings?",
        help = "The Suite Nameplates page styles Blizzard's enemy and friendly nameplates. MSUF's aura filters only decide whether nameplate-only auras show on MSUF frames.",
        words = "nameplate|nameplates|enable nameplates|nameplate size|nameplate castbar|plates" },
    { page = "suite_cooldownManager", label = "Where is the cooldown manager?",
        help = "The Suite Cooldown manager page (CDM) shows Blizzard's tracked cooldowns and buffs as bars you arrange and style freely.",
        words = "cdm|cooldown manager|cooldowns|essential cooldowns|utility cooldowns|tracked buffs|enable cooldown manager" },
}
-- Feature words, searchable in English and as their translation.
local FEATURE_WORDS = {
    dungeonPortals = { "dungeonportal", "dungeon portal", "dungeon portals" },
    characterExtras = { "character window" },
    flightTimer = { "flight time" },
    popupAttention = { "dialog window", "loot notice" },
}
local KIND_OF = { font = "dropdown", texture = "dropdown", choices = "dropdown" }
local EMPTY_ROWS = {}

-- Search follows availability and the active configuration. A module or
-- Quality of Life feature that can run on this client keeps its page, its FAQ
-- answers and its own enable switch searchable while it is off, so players
-- find how to turn it on. Its settings, sections and actions follow its
-- enable switch (and a feature's own switch).
local function ModuleAvailable(id)
    return P.catalog[id] ~= nil and P.Available(id) == true
end

local function ModuleActive(id)
    return ModuleAvailable(id) and P.S.Config(id).enabled == true
end

local function FeatureActive(feature)
    return ModuleActive(feature.id) and P.S.Config(feature.id)[feature.switch] == true
end

local function SkinAvailable()
    return Suite.Client.AddOnEnabled("MSUF_Suite_Skin") == true
end

-- Page rows and FAQ answers: some module of the page can run here.
local function PageAvailable(pageKey)
    if pageKey == "suite_skin" then return SkinAvailable() end
    for _, id in ipairs(P.order) do
        if P.catalog[id].page == pageKey and ModuleAvailable(id) then return true end
    end
    return false
end

-- Page-level details: some module (or QoL feature) of the page is on.
local function PageActive(pageKey)
    if pageKey == "suite_skin" then return SkinAvailable() and P.SkinningEnabled() == true end
    if pageKey == "suite_qualityOfLife" then
        for _, feature in ipairs(P.QualityOfLifeSearchFeatures or EMPTY_ROWS) do
            if FeatureActive(feature) then return true end
        end
        return false
    end
    for _, id in ipairs(P.order) do
        if P.catalog[id].page == pageKey and ModuleActive(id) then return true end
    end
    return false
end

local function RuleKind(rule)
    if rule.color then return "color" end
    for field, kind in pairs(KIND_OF) do
        if rule[field] then return kind end
    end
    local value = type(rule.default)
    if value == "boolean" then return "toggle" end
    if value == "number" then return "slider" end
    if value == "string" then return "textinput" end
end

-- English words stay searchable next to the translated text.
local function AddWords(list, text)
    if type(text) ~= "string" or text == "" then return end
    list[#list + 1] = text
    local translated = Tr(text)
    if translated ~= text then list[#list + 1] = translated end
end

-- The navigation group title a page row sits under.
local function GroupTitle(pageKey)
    local items, groupId = M.navItems, nil
    if type(items) ~= "table" then return nil end
    for _, item in ipairs(items) do
        if item.key == pageKey then
            groupId = item.group
            break
        end
    end
    for _, item in ipairs(items) do
        if groupId and item.title and item.id == groupId then return Tr(item.title) end
    end
end

-- Modules that can run on this client, per page, in catalog order.
local function ModulesByPage()
    local byPage = {}
    for _, id in ipairs(P.order) do
        local spec = P.catalog[id]
        if spec.page and ModuleAvailable(id) then
            byPage[spec.page] = byPage[spec.page] or {}
            table.insert(byPage[spec.page], spec)
        end
    end
    return byPage
end

local function PageRow(page, modules)
    local keywords = {}
    for _, word in ipairs(SUITE_WORDS) do keywords[#keywords + 1] = word end
    for word in (PAGE_WORDS[page.key] or ""):gmatch("[^|]+") do keywords[#keywords + 1] = word end
    for _, word in ipairs(PAGE_TRANSLATED_WORDS[page.key] or EMPTY_ROWS) do AddWords(keywords, word) end
    -- Quality of Life aliases name features of both clients. Each feature
    -- this client offers carries its own words on its switch row instead.
    if page.key ~= "suite_qualityOfLife" then
        for _, alias in ipairs(page.aliases or {}) do keywords[#keywords + 1] = alias end
    end
    AddWords(keywords, page.label)
    if page.key ~= "suite_qualityOfLife" then
        for _, spec in ipairs(modules) do
            AddWords(keywords, spec.title)
            for word in (HUD_MODULE_WORDS[spec.id] or ""):gmatch("[^|]+") do AddWords(keywords, word) end
        end
    end
    local group, label = GroupTitle(page.key), Tr(page.label or page.title or page.key)
    return {
        pageKey = page.key, kind = "page", keywords = keywords,
        help = page.key ~= "suite_qualityOfLife" and #modules == 1 and Tr(modules[1].description) or nil,
        hint = Tr("MSUF Suite") .. " > " .. (group and (group .. " > ") or "") .. label,
    }
end

-- Only explicit template rules share a widget across instances. A digit in
-- an ordinary setting key does not make it a template (each configured
-- DataText bar has its own accordion and slot settings).
local function TemplateKey(rule)
    if rule.suffix then return "#" .. rule.suffix end
    if rule.slot or rule.bar or rule.window then return (rule.key:gsub("%d+", "#")) end
end

-- Shared editors use their first instance's stable widget identity. Other
-- numbered controls (DataTexts bars and slots) have their own real widgets.
local function RuleTarget(page, spec, rule)
    local section = rule.section
    if rule.key == "enabled" then return page.key .. "_" .. spec.id .. "_module" end
    if rule.previewOnly then return page.key .. "_preview", nil, false end
    if spec.id == "nameplates" then
        local target, title, exact = P.NameplateSearchTarget(rule)
        if target then return target, title, exact end
    end
    if spec.id == "cooldownManager" then
        if rule.suffix then
            for _, group in ipairs(P.CDMPage.SECTIONS) do
                for _, suffix in ipairs(group.suffixes) do
                    if suffix == rule.suffix then return page.key .. "_" .. group.id, group.title end
                end
            end
        end
        return page.key .. (section == "text" and "_text" or "_cooldownManager_module")
    end
    if rule.bar then
        local suffix = rule.key:match("^bar%d+(.+)$")
        for _, group in ipairs(P.ActionBarSearchGroups) do
            for _, candidate in ipairs(group.suffixes) do
                if suffix == candidate then return page.key .. "_bar_" .. group.id, group.title end
            end
        end
    end
    if rule.window then return page.key .. "_windows", "Window settings" end
    if spec.id == "dataTexts" and section then
        return P.DataTextSearchTarget(rule)
    elseif page.key == "suite_hud" then
        if rule.key == "enabled" or not section then return page.key .. "_" .. spec.id .. "_module" end
        local prefix = spec.id == "runSummary" and "summary" or spec.id
        if rule.color or section:find("Colors$") or section == "colors" then section = "type" end
        return page.key .. "_" .. prefix .. "_" .. section
    elseif spec.id == "nameplates" and section == "general" then
        return page.key .. "_nameplates_module"
    end
    return section and page.key .. "_" .. section or nil
end

local function RuleRow(page, spec, rule, template, feature, category, config)
    local kind = RuleKind(rule)
    if not kind then return nil end
    local keywords = {}
    AddWords(keywords, spec.title)
    AddWords(keywords, rule.label)
    AddWords(keywords, rule.help)
    local bar = spec.id == "dataTexts" and rule.key:match("^bar(%d+)")
    if bar and config then AddWords(keywords, config["bar" .. bar .. "Name"]) end
    if bar and rule.key == "bar" .. bar .. "Enabled" then
        keywords[#keywords + 1], keywords[#keywords + 2] = "Hide bar", Tr("Hide bar")
    end
    if feature then
        AddWords(keywords, feature.title)
        for _, word in ipairs(feature.keywords or {}) do keywords[#keywords + 1] = word end
    end
    if category then AddWords(keywords, category.title) end
    for _, choice in ipairs(rule.choices or {}) do AddWords(keywords, choice) end
    -- A rule without a section (the module switch) names its module when the
    -- page holds several.
    local sectionId, targetTitle, targetExact = RuleTarget(page, spec, rule)
    local section = feature and category and (Tr(category.title) .. " > " .. Tr(feature.title))
        or targetTitle and Tr(targetTitle)
        or not template and (rule.sectionTitle and Tr(rule.sectionTitle)
        or (spec.title ~= page.title and Tr(spec.title))) or nil
    -- Colors are edited from the section's color shortcut, not a control on
    -- the page, so a color row leads to its section.
    local exact = kind ~= "color" and targetExact ~= false
    return {
        pageKey = page.key, kind = kind, label = Tr(rule.label),
        suiteModuleId = spec.id, suiteFeatureSwitch = feature and feature.switch or nil, suiteRuleKey = rule.key,
        section = section, keywords = keywords, help = rule.help and Tr(rule.help) or nil,
        settingKey = exact and ("msufsuite." .. spec.id .. "." .. rule.key) or nil,
        sectionId = feature and (page.key .. "_" .. feature.id .. "_" .. feature.sections[1]) or sectionId,
        anchorText = kind == "color" and (feature and Tr(feature.title) or section) or nil,
    }
end

local function SectionRow(page, spec, title, sectionId, ruleKey)
    local keywords = {}
    AddWords(keywords, spec.title)
    AddWords(keywords, title)
    return { pageKey = page.key, kind = "section", label = Tr(title), keywords = keywords,
        suiteModuleId = spec.id, sectionId = sectionId, suiteRuleKey = ruleKey }
end

local function SearchableRule(spec, rule, config)
    if spec.controlAvailable and not spec.controlAvailable(rule, config) then return false end
    -- A rule this client cannot use has no control: its page skips the section
    -- (Buff Reminders' Mainline consumables on WoW Forever).
    if rule.requires and P.Requires[rule.requires] and not P.Requires[rule.requires]() then return false end
    if not rule.hidden then return true end
    -- These rules are hidden only from the generic settings grid. The page
    -- owns a switch, preview or direction pad for them instead.
    return spec.id == "dataTexts" and rule.key:match("^bar%d+Enabled$") ~= nil
        or spec.id == "dataTexts" and rule.key:match("^bar%d+StyleOverride$") ~= nil
        or spec.id == "damageMeter" and rule.key:match("^gradientDir") ~= nil
end

local function FaqRow(entry)
    local keywords = {}
    for word in entry.words:gmatch("[^|]+") do keywords[#keywords + 1] = word end
    AddWords(keywords, entry.label)
    return { pageKey = entry.page, kind = "faq", label = Tr(entry.label), help = Tr(entry.help), keywords = keywords }
end

-- Instance section names ("Pet bar", "Window 2", "Essential cooldowns") are
-- not page sections; they become words of the page row instead.
local function ModuleRows(rows, page, spec, instanceTitles)
    local seenRules, seenSections = {}, {}
    local config = Suite.Suite.Config(spec.id)
    local controls = spec.getControls and spec.getControls(config) or spec.controls
    for _, sourceRule in ipairs(controls) do
        local rule = sourceRule
        if TemplateKey(sourceRule) and sourceRule.sectionTitle and not seenSections["instance:" .. sourceRule.sectionTitle] then
            seenSections["instance:" .. sourceRule.sectionTitle] = true
            instanceTitles[#instanceTitles + 1] = sourceRule.sectionTitle
        end
        if rule.suffix then
            rule = spec.rules[Suite.CDM.KEYS.c1[rule.suffix]] or rule
        end
        local template = TemplateKey(rule)
        local sectionKey = rule.sectionTitle and ((template and "#" or "") .. rule.sectionTitle)
        if sectionKey and not seenSections[sectionKey] then
            seenSections[sectionKey] = true
        end
        if SearchableRule(spec, rule, config) and not seenRules[template or rule.key] then
            seenRules[template or rule.key] = true
            rows[#rows + 1] = RuleRow(page, spec, rule, template, nil, nil, config)
            if sectionKey and not template and not seenSections["row:" .. sectionKey] then
                seenSections["row:" .. sectionKey] = true
                local bar = spec.id == "dataTexts" and rule.key:match("^bar(%d+)")
                local title = bar and rule.section == "bar" .. bar and config["bar" .. bar .. "Name"] or rule.sectionTitle
                if type(title) ~= "string" or title == "" then title = rule.sectionTitle end
                rows[#rows + 1] = SectionRow(page, spec, title, RuleTarget(page, spec, rule), rule.key)
            end
        end
    end
end

-- Quality of Life has category accordions and feature tabs. Its old feature
-- section IDs remain the exact search targets; the page resolves them to the
-- category and tab before the setting widget is looked up. Keep the provider
-- inventory tied to the page's own taxonomy so new features need one owner.
local function QualityOfLifeRows(rows, page, modules, pageRow)
    local categories, features = P.QualityOfLifeCategories, P.QualityOfLifeSearchFeatures
    if type(categories) ~= "table" or type(features) ~= "table" then return false end
    local installed, byCategory = {}, {}
    for _, spec in ipairs(modules) do installed[spec.id] = spec end
    for _, category in ipairs(categories) do
        byCategory[category.id] = category
    end
    for _, feature in ipairs(features) do
        local spec, category = installed[feature.id], byCategory[feature.category]
        if spec and category then
            local sectionId = page.key .. "_" .. feature.id .. "_" .. feature.sections[1]
            local keywords = {}
            AddWords(keywords, feature.title)
            AddWords(keywords, category.title)
            AddWords(keywords, spec.title)
            for _, word in ipairs(feature.keywords or {}) do keywords[#keywords + 1] = word end
            for _, word in ipairs(FEATURE_WORDS[feature.id] or EMPTY_ROWS) do AddWords(keywords, word) end
            -- Color settings live in the feature's shortcut rather than as
            -- standalone widgets. Index their names on the exact feature row.
            local ruleRows, seen = {}, {}
            for _, sectionKey in ipairs(feature.sections) do
                for _, rule in ipairs(P.SectionRules(feature.id, sectionKey)) do
                    if rule.key ~= feature.switch and not rule.hidden and not seen[rule.key] then
                        seen[rule.key] = true
                        AddWords(keywords, rule.label)
                        if not rule.color and FeatureActive(feature) then
                            local row = RuleRow(page, spec, rule, nil, feature, category)
                            if row then ruleRows[#ruleRows + 1] = row end
                        end
                    end
                end
            end
            rows[#rows + 1] = {
                pageKey = page.key, kind = "toggle", label = Tr(feature.title),
                suiteModuleId = spec.id, suiteFeatureSwitch = feature.switch, suiteModuleSwitch = true,
                qolFeatureId = feature.id,
                section = Tr(category.title), keywords = keywords,
                settingKey = "msufsuite." .. feature.id .. "." .. feature.switch,
                sectionId = sectionId,
            }
            for _, row in ipairs(ruleRows) do rows[#rows + 1] = row end
        end
    end
    for _, category in ipairs(categories) do
        local enabled = false
        for _, feature in ipairs(features) do
            if feature.category == category.id and installed[feature.id] then
                enabled = true
                break
            end
        end
        if enabled then
            AddWords(pageRow.keywords, category.title)
            local keywords = {}
            AddWords(keywords, category.title)
            rows[#rows + 1] = {
                pageKey = page.key, kind = "section", label = Tr(category.title),
                keywords = keywords, sectionId = page.key .. "_category_" .. category.id,
            }
        end
    end
    return true
end

-- A module that is off keeps only its own enable switch.
local function SwitchRow(rows, page, spec)
    local config = Suite.Suite.Config(spec.id)
    local rule = spec.rules.enabled
    if SearchableRule(spec, rule, config) then rows[#rows + 1] = RuleRow(page, spec, rule, nil, nil, nil, config) end
end

function P.SearchRows()
    P.ForgetAvailability()
    local rows, byPage, pagesByKey = {}, ModulesByPage(), {}
    for _, page in ipairs(P.pages) do
        if PageAvailable(page.key) then
            local modules, instanceTitles = byPage[page.key] or {}, {}
            local pageRow = PageRow(page, modules)
            rows[#rows + 1] = pageRow
            if page.key == "suite_hud" then
                -- The timer and result card share this page with ordinary objectives.
                -- Give a plain Mythic+ search an explicit route to each real section.
                local objectives = P.catalog.objectives
                if objectives and objectives.rules.showMythicPlus then
                    rows[#rows + 1] = {
                        pageKey = page.key, kind = "section", label = Tr("Mythic+ settings"),
                        suiteModuleId = "objectives", suiteRuleKey = "showMythicPlus",
                        settingKey = "msufsuite.objectives.showMythicPlus",
                        hint = pageRow.hint .. " > " .. Tr("Mythic+ timer") .. " > " .. Tr("What to track"),
                        sectionId = "suite_hud_objectives_content", anchorText = Tr("What to track"),
                        keywords = { "mythic plus", "m+", "mythic plus timer", "mythic plus objective tracker" },
                    }
                end
                local summary = P.catalog.runSummary
                if summary and summary.rules.showMythicPlus then
                    rows[#rows + 1] = {
                        pageKey = page.key, kind = "section", label = Tr("Mythic+ run summaries"),
                        suiteModuleId = "runSummary", suiteRuleKey = "showMythicPlus",
                        settingKey = "msufsuite.runSummary.showMythicPlus",
                        hint = pageRow.hint .. " > " .. Tr("Mythic+ run summaries") .. " > " .. Tr("Results and details"),
                        sectionId = "suite_hud_summary_content", anchorText = Tr("Results and details"),
                        keywords = { "mythic plus", "m+", "mythic plus result", "mythic plus summary" },
                    }
                end
            end
            if page.key ~= "suite_qualityOfLife" or not QualityOfLifeRows(rows, page, modules, pageRow) then
                for _, spec in ipairs(modules) do
                    if ModuleActive(spec.id) then
                        ModuleRows(rows, page, spec, instanceTitles)
                    else
                        SwitchRow(rows, page, spec)
                    end
                end
            end
            for _, title in ipairs(instanceTitles) do AddWords(pageRow.keywords, title) end
            pagesByKey[page.key] = page
        end
    end
    for _, entry in ipairs(FAQ) do
        if pagesByKey[entry.page] then rows[#rows + 1] = FaqRow(entry) end
    end
    -- Skinning rows are gated per row below; its maintenance actions are
    -- found also while the Skin addon is off.
    for _, row in ipairs(P.SkinSearchRows()) do rows[#rows + 1] = row end
    P.AppendSearchActionRows(rows, pagesByKey)
    local visible = {}
    for _, row in ipairs(rows) do
        if P.SearchRowAvailable(row.pageKey, row.settingKey, row) then visible[#visible + 1] = row end
    end
    return visible
end

-- Each host caps a provider's rows. Keep ordinary modules separate from
-- dynamic bars, partitioned by configured ordinal rather than numeric ID.
-- The host collects sorted provider names once per invalidated rebuild, so
-- the base callback generates every row once and the fixed siblings reuse it.
local BARS_PER_GROUP = 16
local GROUP_COUNT = math.ceil(Suite.DataTextBarLimit / BARS_PER_GROUP)
local barGroups = {}
local function CollectBase()
    local ordinal = {}
    for index, bar in ipairs(Suite.DataTextBarIDs(P.S.Config("dataTexts"))) do
        ordinal[tostring(bar)] = math.ceil(index / BARS_PER_GROUP)
    end
    local base = {}
    barGroups = {}
    for _, row in ipairs(P.SearchRows()) do
        local bar = row.pageKey == "suite_dataTexts" and
            ((row.suiteRuleKey or ""):match("^bar(%d+)") or (row.sectionId or ""):match("^suite_dataTexts_bar(%d+)"))
        local group = bar and ordinal[bar]
        if group then
            local rows = barGroups[group]
            if not rows then
                rows = {}
                barGroups[group] = rows
            end
            rows[#rows + 1] = row
        elseif not bar then
            base[#base + 1] = row
        end
    end
    return base
end
-- Classic MSUF asks before each search whether the provider's context
-- changed. Blizzard's AddOn list can switch a Suite addon off while the menu
-- is open, so availability is read again; settings changes also invalidate
-- through P.Refresh.
local contextSignature
local function SearchContextChanged()
    P.ForgetAvailability()
    local parts = {}
    for _, id in ipairs(P.order) do
        parts[#parts + 1] = not ModuleAvailable(id) and "-" or P.S.Config(id).enabled == true and "1" or "0"
    end
    for _, feature in ipairs(P.QualityOfLifeSearchFeatures or EMPTY_ROWS) do
        parts[#parts + 1] = P.S.Config(feature.id)[feature.switch] == true and "1" or "0"
    end
    parts[#parts + 1] = not SkinAvailable() and "-" or P.SkinningEnabled() == true and "1" or "0"
    local signature = table.concat(parts)
    local changed = signature ~= contextSignature
    contextSignature = signature
    return changed
end
P.searchRegistered = M.RegisterSearchProvider("MSUF_Suite", CollectBase, SearchContextChanged) == true
for index = 1, GROUP_COUNT do
    local group = index
    M.RegisterSearchProvider("MSUF_Suite.DataTexts." .. string.format("%02d", group), function()
        return barGroups[group] or EMPTY_ROWS
    end)
end

-- Search records from visited pages and the cold provider share this gate.
-- Pages, FAQ answers and enable switches stay while their module can run
-- here; details leave as soon as their module or feature is switched off.
local function ModuleForRecord(pageKey, settingKey, record)
    local row = record.providerRow or record
    local id, key
    if type(settingKey) == "string" then id, key = settingKey:match("^msufsuite%.([^.]+)%.(.+)$") end
    id = row.suiteModuleId or id
    local sectionId = row.sectionId or record.sectionId
    if not id and type(sectionId) == "string" then
        for _, moduleId in ipairs(P.order) do
            if sectionId:sub(1, #pageKey + #moduleId + 2) == pageKey .. "_" .. moduleId .. "_" then
                id = moduleId
                break
            end
        end
        if pageKey == "suite_hud" and sectionId:find("^suite_hud_summary_") then id = "runSummary" end
    end
    if not id then
        for _, moduleId in ipairs(P.order) do
            if P.catalog[moduleId].page == pageKey then
                if id then return nil end -- aggregate pages have no one owner
                id = moduleId
            end
        end
    end
    return id, key, row
end

function P.SearchRowAvailable(pageKey, settingKey, record)
    if type(pageKey) ~= "string" then return true end
    local owner = type(settingKey) == "string" and settingKey:match("^msufsuite%.([^.]+)%.")
    if owner == "skin" then pageKey = "suite_skin"
    elseif owner and P.catalog[owner] then pageKey = P.catalog[owner].page or pageKey end
    if pageKey:sub(1, 6) ~= "suite_" then return true end
    record = record or {}
    local row = record.providerRow or record
    if record.kind == "page" or row.kind == "page" or record.kind == "faq" or row.kind == "faq" then
        return PageAvailable(pageKey)
    end
    -- Actions built in every state of their page (Pages/Appearance.lua).
    if row.suiteAlways or record.suiteAlways then return true end
    if pageKey == "suite_skin" then
        if not SkinAvailable() then return false end
        if settingKey == "msufsuite.skin.enabled" then return true end
        if P.SkinningEnabled() ~= true then return false end
        if (row.sectionId or record.sectionId) == "suite_skin_hud" and P.S.OwnsBlizzardSurface("damageMeter") then
            return false
        end
        return true
    end
    local id, key = ModuleForRecord(pageKey, settingKey, record)
    if not id then
        local categoryId = (row.sectionId or record.sectionId or ""):match("^suite_qualityOfLife_category_(.+)$")
        if categoryId then
            for _, feature in ipairs(P.QualityOfLifeSearchFeatures or EMPTY_ROWS) do
                if feature.category == categoryId and ModuleAvailable(feature.id) then return true end
            end
            return false
        end
        return PageActive(pageKey)
    end
    if not ModuleAvailable(id) then return false end
    if key == "enabled" or row.suiteModuleSwitch then return true end
    local featureSwitch = row.suiteFeatureSwitch
    if pageKey == "suite_qualityOfLife" then
        for _, feature in ipairs(P.QualityOfLifeSearchFeatures) do
            if feature.id == id then
                if key == feature.switch then return true end
                local sectionId = row.sectionId or record.sectionId
                for _, section in ipairs(feature.sections) do
                    if sectionId == pageKey .. "_" .. id .. "_" .. section then
                        featureSwitch = feature.switch
                        break
                    end
                end
                if featureSwitch then break end
            end
        end
    end
    local config = P.S.Config(id)
    local spec, controlKey = P.catalog[id], key or row.suiteRuleKey
    -- Live actions and section rows carry no setting key. Removed dynamic
    -- bars must leave the visited index as well as the cold provider.
    local bar = id == "dataTexts" and (row.sectionId or record.sectionId or ""):match("^suite_dataTexts_bar(%d+)")
    if bar then
        local barRule = spec.rules["bar" .. bar .. "Enabled"]
        if not barRule or not spec.controlAvailable(barRule, config) then return false end
    end
    if controlKey and spec.controlAvailable then
        local rule = spec.rules[controlKey]
        if not rule or not spec.controlAvailable(rule, config) then return false end
    end
    return config.enabled == true and (not featureSwitch or config[featureSwitch] == true)
end

if M.RegisterSearchAvailability then M.RegisterSearchAvailability("MSUF_Suite", P.SearchRowAvailable) end
if M.InvalidateSearchProvider then
    function P.InvalidateSearch() M.InvalidateSearchProvider("MSUF_Suite") end
else
    -- Registering again clears the host's cached rows of every provider; the
    -- DataText siblings read the partition the base collector refills first.
    function P.InvalidateSearch() M.RegisterSearchProvider("MSUF_Suite", CollectBase, SearchContextChanged) end
end
Suite.Registry.AddListener(P.SearchRows, function(_, domain)
    if domain == "profile" then
        P.ForgetAvailability()
        P.InvalidateSearch()
    end
end)
