local _, P = ...
-- Rows for MSUF's menu search. Every Suite page with its aliases and the words
-- players use for it, and every catalog setting and section, so a Suite
-- setting is found before its page was ever opened. MSUF calls the provider
-- on the first search (and again after a language change), never at load.
-- An MSUF build without the provider hook simply gets no rows.
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
    suite_qualityOfLife = "quality of life|qol|comfort|helpers",
    suite_hud = "hud|objective tracker|quest tracker|announcements|afk screen",
    suite_modules = "module list|optional modules|enable modules",
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
    { page = "suite_modules", label = "What is the MSUF Suite?",
        help = "The MSUF Suite adds optional interface modules to this menu, such as the minimap, action bars, nameplates, the cooldown manager, chat and bags. Turn each one on or off on the Suite Modules page.",
        words = "suite|msuf suite|modules|suite modules|optional modules|enable modules" },
}
local KIND_OF = { font = "dropdown", texture = "dropdown", choices = "dropdown" }

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
        if item.key == pageKey then groupId = item.group; break end
    end
    for _, item in ipairs(items) do
        if groupId and item.title and item.id == groupId then return Tr(item.title) end
    end
end

-- Installed modules per page, in catalog order.
local function ModulesByPage()
    local byPage = {}
    for _, id in ipairs(P.order) do
        local spec = P.catalog[id]
        if spec.page and Suite.Client.HasAddOn(spec.addon) then
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
    for _, alias in ipairs(page.aliases or {}) do keywords[#keywords + 1] = alias end
    AddWords(keywords, page.label)
    for _, spec in ipairs(modules) do AddWords(keywords, spec.title) end
    local group, label = GroupTitle(page.key), Tr(page.label or page.title or page.key)
    return {
        pageKey = page.key, kind = "page", keywords = keywords,
        help = #modules == 1 and Tr(modules[1].description) or nil,
        hint = Tr("MSUF Suite") .. " > " .. (group and (group .. " > ") or "") .. label,
    }
end

-- A rule repeated per bar, window or slot (bar1Size, w2Width, ess_desat) is
-- edited through one shared set of controls bound to whichever instance the
-- page selects, under the page's own section names. One row stands for all
-- instances: no instance setting key and no instance section; the row leads
-- to the page and its control label.
local function TemplateKey(rule)
    if rule.suffix then return "#" .. rule.suffix end
    if rule.slot or rule.bar or rule.window or rule.key:find("%d") then return (rule.key:gsub("%d+", "#")) end
end

local function RuleRow(page, spec, rule, template)
    local kind = RuleKind(rule)
    if not kind then return nil end
    local keywords = {}
    AddWords(keywords, spec.title)
    AddWords(keywords, rule.label)
    AddWords(keywords, rule.help)
    for i = 1, math.min(#(rule.choices or {}), 12) do AddWords(keywords, rule.choices[i]) end
    -- A rule without a section (the module switch) names its module when the
    -- page holds several.
    local section = not template and (rule.sectionTitle and Tr(rule.sectionTitle)
        or (spec.title ~= page.title and Tr(spec.title))) or nil
    -- Colors are edited from the section's color shortcut, not a control on
    -- the page, so a color row leads to its section.
    local exact = kind ~= "color" and not template
    return {
        pageKey = page.key, kind = kind, label = Tr(rule.label),
        section = section, keywords = keywords, help = rule.help and Tr(rule.help) or nil,
        settingKey = exact and ("msufsuite." .. spec.id .. "." .. rule.key) or nil,
        anchorText = kind == "color" and section or nil,
    }
end

local function SectionRow(page, spec, title)
    local keywords = {}
    AddWords(keywords, spec.title)
    AddWords(keywords, title)
    return { pageKey = page.key, kind = "section", label = Tr(title), keywords = keywords }
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
    for _, rule in ipairs(spec.controls) do
        local template = TemplateKey(rule)
        local sectionKey = rule.sectionTitle and ((template and "#" or "") .. rule.sectionTitle)
        if sectionKey and not seenSections[sectionKey] then
            seenSections[sectionKey] = true
            if template then instanceTitles[#instanceTitles + 1] = rule.sectionTitle end
        end
        if not rule.hidden and not rule.previewOnly and not seenRules[template or rule.key] then
            seenRules[template or rule.key] = true
            rows[#rows + 1] = RuleRow(page, spec, rule, template)
            if sectionKey and not template and not seenSections["row:" .. sectionKey] then
                seenSections["row:" .. sectionKey] = true
                rows[#rows + 1] = SectionRow(page, spec, rule.sectionTitle)
            end
        end
    end
end

function P.SearchRows()
    local rows, byPage, pagesByKey = {}, ModulesByPage(), {}
    for _, page in ipairs(P.pages) do
        local modules, instanceTitles = byPage[page.key] or {}, {}
        local pageRow = PageRow(page, modules)
        rows[#rows + 1] = pageRow
        for _, spec in ipairs(modules) do ModuleRows(rows, page, spec, instanceTitles) end
        for _, title in ipairs(instanceTitles) do AddWords(pageRow.keywords, title) end
        pagesByKey[page.key] = page
    end
    for _, entry in ipairs(FAQ) do
        if pagesByKey[entry.page] then rows[#rows + 1] = FaqRow(entry) end
    end
    return rows
end

P.searchRegistered = M.RegisterSearchProvider("MSUF_Suite", P.SearchRows) == true
