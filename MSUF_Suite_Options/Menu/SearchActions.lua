local _, P = ...
local Tr = P.Tr

-- Actions are absent from the settings catalog. These are the stable controls
-- that open an editor, preview, picker or operation on the real feature page.
-- Searching them only navigates to the control; it never runs the action.
local MODULE_ACTIONS = {
    bags = { { "open", "Open bags" }, { "move", "Move bag windows" }, { "currencies", "Choose currencies" } },
    buffReminders = { { "edit", "Edit Mode" }, { "potionMap", "Add this map to the potion maps" } },
    damageMeter = { { "reset_data", "Reset combat data" }, { "move", "Move on screen" } },
    minimap = { { "rescan", "Collect addon buttons again" }, { "button_positions", "Arrange individual addon buttons" },
        { "reload", "Reload UI" } },
    actionbars = { { "bindings", "Key bindings" }, { "move", "Move on screen" }, { "reload", "Reload UI" } },
    cooldownManager = { { "move", "Move bars on screen" }, { "blizzard", "Open Blizzard's Cooldown Settings" } },
    objectives = { { "edit", "Move in Edit Mode" }, { "colors", "Tracker colors" } },
    -- Clear run history exists only with Mythic+ results (see the block below).
    runSummary = { { "edit", "Move in Edit Mode" }, { "preview_raid", "Preview raid result" },
        { "last", "Show last result" }, { "colors", "Summary colors" } },
    announcements = { { "edit", "Move in Edit Mode" }, { "colors", "Announcement colors" } },
}

-- module, section suffix, control key, visible label, optional classification/kind.
local EDITOR_ACTIONS = {
    { "actionbars", "editor", "editor.selected", "Selected bar", "ephemeral", "dropdown" },
    { "actionbars", "editor", "editor.copyTo", "Copy To", "ephemeral" },
    { "actionbars", "editor", "editor.preset.row", "One row" },
    { "actionbars", "editor", "editor.preset.double", "Two rows" },
    { "actionbars", "editor", "editor.preset.grid", "Three rows" },
    { "actionbars", "editor", "editor.preset.column", "One column" },
    { "actionbars", "editor", "editor.move", "Move selected bar" },
    { "actionbars", "editor", "editor.bindings", "Key bindings" },
    { "actionbars", "editor", "editor.extraAbility", "Move extra action button" },
    { "damageMeter", "windows", "window.selected", "Window", "ephemeral", "dropdown" },
    { "damageMeter", "windows", "window.move", "Move this window" },
    { "dataTexts", "gold", "action.clearGold", "Clear saved character gold" },
    { "dataTexts", "presets", "action.addBar", "Add bar" },
    { "dataTexts", "sources", "chooseSeasonStages", "Choose observed seasonal stages" },
    { "dataTexts", "sources", "chooseCrestCurrencies", "Choose crest currencies" },
    { "bags", "finance", "action.clearGold", "Clear saved character gold" },
    { "chat", "tools", "clearHistory", "Clear saved chat history" },
    { "chat", "tools", "timestamp", "Timestamps (Blizzard setting)", nil, "dropdown" },
    { "cooldownManager", "cooldownManager_module", "editor.selected", "Bar to edit", "ephemeral", "dropdown" },
    { "cooldownManager", "cooldownManager_module", "editor.add", "+ Add bar" },
    { "cooldownManager", "cooldownManager_module", "editor.actions", "Bar actions" },
    { "cooldownManager", "layout", "editor.move", "Move this bar on screen" },
    { "cooldownManager", "layout", "editor.reset", "Reset this bar's settings" },
    { "cooldownManager", "spells", "spells.add", "Add spells" },
    { "cooldownManager", "spells", "spells.restore", "Show removed spells" },
    { "cooldownManager", "spells", "spells.clear", "Reset to Blizzard's list" },
    { "cooldownManager", "spells", "spells.copy", "Copy to other specializations" },
    { "cooldownManager", "spells", "spells.importBlizzard", "Import Blizzard CDM" },
}
local BAR_ACTIONS = {
    { "addPlace", "Add data" }, { "move", "Move in Edit Mode" },
    { "manage", "Apply preset to this bar" }, { "duplicate", "Duplicate bar" },
    { "remove", "Remove bar" }, { "shared", "All bars" },
}
-- Each place of a bar has these in its own editor; they are found on the bar's
-- data entry, which opens that editor.
local PLACE_ACTION_WORDS = { "Remove data", "Move earlier", "Move later", "Choose data source" }
local QOL_ACTIONS = {
    xpBar = { { "resetSession", "Reset session" } },
    innervateCue = { { "target", "Use current player target" } },
    loadoutReminder = { { "saveCurrent", "Save current build and loot spec" }, { "clearSaved", "Clear saved selection" } },
}

-- The names of a Quality of Life feature's color rules besides its own switch,
-- in English and translated; nil when it has none. They are searched on the
-- feature's color entry: the feature row's own text is cut at the host's limit.
local function FeatureColorWords(feature)
    local words
    for _, section in ipairs(feature.sections) do
        for _, rule in ipairs(P.SectionRules(feature.id, section)) do
            if rule.color and not rule.hidden and rule.key ~= feature.switch then
                words = words or {}
                words[#words + 1], words[#words + 2] = rule.label, Tr(rule.label)
            end
        end
    end
    return words
end

local function DataTextTerms(id, key, keywords)
    if id ~= "dataTexts" then return end
    local bar = key:match("^bar(%d+)%.")
    local name = bar and P.S.Config(id)["bar" .. bar .. "Name"]
    if type(name) == "string" and name ~= "" then keywords[#keywords + 1] = name end
    if key:match("%.manage$") then
        keywords[#keywords + 1], keywords[#keywords + 2] = "Antique Footer preset", Tr("Antique Footer preset")
    end
end

-- A spell's own options (Pages/CooldownManagerPopover.lua, P.CDMPage.FIELDS) open
-- by clicking the spell in the Spells list, so their rows lead to that list.
-- Options that follow a bar setting are found by that bar setting already.
local SPELL_OPTION_KINDS = { bool = "toggle", choice = "dropdown", number = "slider", color = "color",
    sound = "dropdown", spell = "textinput", icon = "textinput" }
local SPELL_ACTIONS = { "Remove from bar", "Move to bar", "Reset this spell", "Copy to all specs" }
local function AddSpellOptionRows(rows, pagesByKey)
    local spec, page = P.catalog.cooldownManager, P.CDMPage
    if not (spec and page and page.FIELDS and pagesByKey[spec.page] and P.Suite.Client.HasAddOn(spec.addon)) then return end
    local shown = {}
    for _, row in ipairs(rows) do
        if row.pageKey == spec.page and row.label then shown[row.label] = true end
    end
    local function Row(label, kind, alternative)
        local text = Tr(label)
        if shown[text] then return end
        shown[text] = true
        local keywords = { label, text, spec.title, Tr(spec.title) }
        if alternative then keywords[#keywords + 1], keywords[#keywords + 2] = alternative, Tr(alternative) end
        rows[#rows + 1] = {
            pageKey = spec.page, kind = kind, label = text, sectionId = spec.page .. "_spells",
            suiteModuleId = "cooldownManager", section = Tr("Spell list"), keywords = keywords,
        }
    end
    for _, field in ipairs(page.FIELDS) do
        if not field.bar then Row(field.label, SPELL_OPTION_KINDS[field.kind] or "button", field.auraLabel) end
    end
    for _, label in ipairs(SPELL_ACTIONS) do Row(label, "button") end
end

-- Add(id, key, label, sectionId, classification, kind, feature, extra) below.
local function AddDataTextBarRows(Add)
    local dataTexts = P.S.Config("dataTexts")
    local placeWords = {}
    for _, word in ipairs(PLACE_ACTION_WORDS) do placeWords[#placeWords + 1], placeWords[#placeWords + 2] = word, Tr(word) end
    for _, bar in ipairs(P.Suite.DataTextBarIDs(dataTexts)) do
        -- Every bar has the same actions, so each shows its bar's name as the section.
        local name = dataTexts["bar" .. bar .. "Name"]
        local section = name ~= "" and name or nil
        for _, action in ipairs(BAR_ACTIONS) do
            Add("dataTexts", "bar" .. bar .. "." .. action[1], action[2], "suite_dataTexts_bar" .. bar, nil, nil, nil,
                { section = section, words = action[1] == "addPlace" and placeWords or nil })
        end
    end
end

local function AddQualityOfLifeRows(Add)
    for _, feature in ipairs(P.QualityOfLifeSearchFeatures) do
        local sectionId = "suite_qualityOfLife_" .. feature.id .. "_" .. feature.sections[1]
        -- The Quality of Life page owns which features have an Edit Mode button.
        if P.QualityOfLifeEditElements[feature.id] then
            Add(feature.id, "action.edit", "Move / resize in Edit Mode", sectionId, nil, nil, feature)
        end
        for _, action in ipairs(QOL_ACTIONS[feature.id] or {}) do
            Add(feature.id, "action." .. action[1], action[2], sectionId, nil, nil, feature)
        end
        local colorWords = FeatureColorWords(feature)
        if colorWords then
            local label = Tr("%s Colors"):format(Tr(feature.title))
            Add(feature.id, "action.colors." .. feature.switch, label, sectionId, nil, nil, feature, { words = colorWords })
        end
    end
end

function P.AppendSearchActionRows(rows, pagesByKey)
    -- extra: optional { words = { ... }, section = "shown section" }.
    local function Add(id, key, label, sectionId, classification, kind, feature, extra)
        local spec = P.catalog[id]
        local pageKey = spec and spec.page
        if not pageKey or not pagesByKey[pageKey] or not P.Suite.Client.HasAddOn(spec.addon) then return end
        local meta = P.Meta(pageKey, id, key, classification or "action", sectionId)
        local keywords = { label, Tr(label), spec.title, Tr(spec.title) }
        DataTextTerms(id, key, keywords)
        if feature then
            keywords[#keywords + 1] = feature.title
            keywords[#keywords + 1] = Tr(feature.title)
        end
        for _, word in ipairs(extra and extra.words or {}) do keywords[#keywords + 1] = word end
        if key == "action.edit" then
            -- These layout fields are edited only by the feature's real
            -- Edit Mode mover. Search their labels on that entry point.
            for _, positionKey in ipairs({ "point", "x", "y" }) do
                local rule = spec.rules[positionKey]
                if rule and rule.hidden then
                    keywords[#keywords + 1] = rule.label
                    keywords[#keywords + 1] = Tr(rule.label)
                end
            end
        end
        rows[#rows + 1] = {
            pageKey = pageKey, kind = kind or "button", label = Tr(label),
            sectionId = sectionId, controlId = meta.controlId,
            suiteModuleId = id, suiteFeatureSwitch = feature and feature.switch or nil,
            section = extra and extra.section or feature and Tr(feature.title) or Tr(spec.title), keywords = keywords,
        }
    end

    for _, id in ipairs(P.order) do
        local spec = P.catalog[id]
        for _, action in ipairs(MODULE_ACTIONS[id] or {}) do
            Add(id, "action." .. action[1], action[2], spec.page .. "_" .. id .. "_module")
        end
    end
    local summary = P.catalog.runSummary
    if summary and summary.rules.showMythicPlus then
        Add("runSummary", "action.preview_mythic", "Preview Mythic+ result", "suite_hud_runSummary_module")
        Add("runSummary", "action.history", "Open run history", "suite_hud_runSummary_module")
        Add("runSummary", "action.clear_history", "Clear run history", "suite_hud_runSummary_module")
    end
    for _, action in ipairs(EDITOR_ACTIONS) do
        local spec = P.catalog[action[1]]
        if spec then Add(action[1], action[3], action[4], spec.page .. "_" .. action[2], action[5], action[6]) end
    end
    -- The bar switches above the action bar editor ("Pet bar", "Action bar 3").
    for index, title in ipairs(P.Suite.ActionBarTitles) do
        Add("actionbars", "quick.bar" .. index, title, "suite_actionbars_actionbars_module", nil, "toggle")
    end
    AddDataTextBarRows(Add)
    for _, preset in ipairs(P.Suite.DataTextPresets) do
        Add("dataTexts", "preset." .. preset.id, preset.title, "suite_dataTexts_presets")
    end
    AddQualityOfLifeRows(Add)
    AddSpellOptionRows(rows, pagesByKey)
end
