local _, NS = ...
-- Settings schema shared by the controller, profile IO and the menu. Feature
-- files under Core/Catalog declare their modules with these builders; Finalize
-- derives the defaults once every catalog file has loaded.
local catalog, order = {}, {}
NS.SuiteCatalog, NS.SuiteOrder = catalog, order
-- Related Quality of Life helpers share one optional runtime addon. Their
-- settings and event subscriptions remain independent after it loads.
local moduleAddons = {
    actionbars = "MSUF_Suite_ActionBars",
    minimap = "MSUF_Suite_Minimap",
    damageMeter = "MSUF_Suite_DamageMeter",
    bags = "MSUF_Suite_Bags",
    qol = "MSUF_Suite_QualityOfLife",
    quests = "MSUF_Suite_QualityOfLife",
    loot = "MSUF_Suite_QualityOfLife",
    combatLog = "MSUF_Suite_QualityOfLife",
    xpBar = "MSUF_Suite_QualityOfLife",
    skyriding = "MSUF_Suite_QualityOfLife",
    dataTexts = "MSUF_Suite_DataTexts",
    buffReminders = "MSUF_Suite_BuffReminders",
    chat = "MSUF_Suite_Chat",
    cooldownManager = "MSUF_Suite_CooldownManager",
    objectives = "MSUF_Suite_Modules",
    announcements = "MSUF_Suite_Modules",
    afkScreen = "MSUF_Suite_Modules",
}
local Build = {}
NS.CatalogBuild = Build

function Build.Number(key, label, value, min, max, step)
    return { key=key, label=label, default=value, min=min, max=max, step=step or 1 }
end
function Build.Bool(key, label, value)
    return { key=key, label=label, default=value == true }
end
function Build.Choice(key, label, value, labels)
    local rule = Build.Number(key, label, value, 1, #labels)
    rule.choices = labels
    return rule
end
function Build.String(key, label, value, maxLength)
    return { key=key, label=label, default=value, maxLength=maxLength }
end
function Build.Color(key, label, value)
    local rule = Build.String(key, label, value, 6)
    rule.color = true
    return rule
end
-- Empty font/texture keys mean "use the native or module default".
function Build.Font(key, label)
    local rule = Build.String(key, label, "", 260)
    rule.font = true
    return rule
end
function Build.Texture(key, label)
    local rule = Build.String(key, label, "", 260)
    rule.texture = true
    return rule
end

-- spec fields: title, description, conflicts, core (enabled by the core preset),
-- defaultEnabled, optIn (never enabled by presets), page (menu page key), available() -> ok, reason.
-- cvars: { [name] = true } CVars the runtime may set through its context; the
-- controller hands them back even while the module addon is disabled.
-- look (optional), shared by the controller and the menu:
--   key         choice rule that selects a preset
--   presets     [choice] = visual settings written together with that choice
--   visualKeys  settings whose edit switches the choice to `custom`
--   custom      the Custom choice, if the module has one
--   global      part of the suite-wide Skinning look: true when the choice
--               equals the look index (1 Midnight Blue, 2 Midnight Dark,
--               3 MSUF Forever), or { choice per look index }
--   extra(values, lookIndex, config) adds settings derived from a global look
function Build.Module(id, spec)
    assert(not catalog[id], "duplicate suite module " .. tostring(id))
    assert(moduleAddons[id], "missing Suite addon for " .. tostring(id))
    spec.id = id
    spec.addon = moduleAddons[id]
    spec.controls = {}
    spec.rules = {}
    spec.conflicts = spec.conflicts or {}
    catalog[id], order[#order + 1] = spec, id
    Build.Add(id, Build.Bool("enabled", "Enable module", spec.defaultEnabled ~= false))
    return spec
end

-- Adds a rule to a module. section/sectionTitle drive menu grouping; opts may
-- carry enableKey, requires, category, help and any presentation hints.
function Build.Add(id, rule, section, sectionTitle, opts)
    local spec = assert(catalog[id], "unknown suite module " .. tostring(id))
    assert(not spec.rules[rule.key], id .. "." .. rule.key .. " declared twice")
    rule.section, rule.sectionTitle = section, sectionTitle
    if opts then
        for field, value in pairs(opts) do rule[field] = value end
    end
    spec.controls[#spec.controls + 1] = rule
    spec.rules[rule.key] = rule
    return rule
end

function Build.Section(id, section, sectionTitle, rules, opts)
    for i = 1, #rules do Build.Add(id, rules[i], section, sectionTitle, opts) end
end

function NS.FinalizeCatalog()
    NS.Defaults.suite = { schema=1, modules={} }
    for i = 1, #order do
        local id = order[i]
        local defaults = {}
        for key, rule in pairs(catalog[id].rules) do defaults[key] = rule.default end
        NS.Defaults.suite.modules[id] = defaults
    end
end
