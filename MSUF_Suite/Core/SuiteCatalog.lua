local _, NS = ...
-- Settings schema shared by the controller, profile IO and the menu. Feature
-- files under Core/Catalog declare their modules with these builders; Finalize
-- derives the defaults once every catalog file has loaded.
local catalog, order = {}, {}
NS.SuiteCatalog, NS.SuiteOrder = catalog, order
local Build = {}
NS.CatalogBuild = Build

-- The builder of one catalog file: every module it declares runs in that
-- load-on-demand addon (spec.addon). Related Quality of Life helpers share
-- one runtime addon; their settings and event subscriptions remain
-- independent after it loads.
function Build.ForAddon(addon)
    return setmetatable({
        Module = function(id, spec)
            spec.addon = addon
            return Build.Module(id, spec)
        end,
    }, { __index = Build })
end

-- Class colors are character identity, so resolve them only on cold settings
-- paths. Renderers read these stable preset tables just like authored looks.
local classPresets, classReady = {}, false
local classPalette = { accent = "e6ecf2", border = "737679", label = "e6ecf2" }
local Looks = { classRevision = 0 }
NS.SuiteLooks = Looks
local function Hex(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + .5),
        math.floor(g * 255 + .5), math.floor(b * 255 + .5))
end
function Looks.RefreshClassColor()
    if classReady then return end
    -- Blizzard UnitUtil.lua uses UnitClass("player") with C_ClassColor.
    local _, class = UnitClass("player")
    if type(class) ~= "string" then return end
    local color = C_ClassColor.GetClassColor(class)
    if type(color) ~= "table" then return end
    local r, g, b = color.r, color.g, color.b
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number"
        or r ~= r or g ~= g or b ~= b then return end
    r, g, b = math.max(0, math.min(1, r)), math.max(0, math.min(1, g)), math.max(0, math.min(1, b))
    classReady = true
    classPalette.accent = Hex(r, g, b)
    classPalette.border = Hex(r * .5, g * .5, b * .5)
    classPalette.label = Hex(.6 + r * .4, .6 + g * .4, .6 + b * .4)
    for i = 1, #classPresets do
        local entry = classPresets[i]
        for key, role in pairs(entry.fields) do entry.preset[key] = classPalette[role] end
    end
    Looks.classRevision = Looks.classRevision + 1
end
function Build.ClassPreset(base, fields)
    local preset = {}
    for key, value in pairs(base) do preset[key] = value end
    for key, role in pairs(fields) do preset[key] = classPalette[role] end
    classPresets[#classPresets + 1] = { preset = preset, fields = fields }
    return preset
end

-- The nine anchor points of every "Screen anchor" and position choice, with
-- their choice labels. Saved profiles store the choice index, so this order
-- never changes.
NS.AnchorPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
NS.AnchorLabels = { "Top left", "Top", "Top right", "Left", "Center", "Right", "Bottom left", "Bottom", "Bottom right" }

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
-- Empty font keys inherit the MSUF font. Chat offers an explicit Blizzard
-- choice; empty texture keys keep the module default.
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
-- defaultEnabled, optIn (never enabled by presets), automation (the module acts for
-- the player as a whole, see Build.Automation), page (menu page key), available() -> ok, reason.
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
    assert(type(spec.addon) == "string", "missing Suite addon for " .. tostring(id))
    spec.id = id
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

-- Only Smooth and Sharp rendering draw a text shadow; its opacity and
-- distance also follow the shadow switch.
function Build.LinkFontShadow(rules)
    local rendering = { key = "fontRendering", values = { [1] = true, [2] = true } }
    rules.fontShadow.requiresChoice = rendering
    for _, key in ipairs({ "fontShadowOpacity", "fontShadowDistance" }) do
        rules[key].enableKey = "fontShadow"
        rules[key].requiresChoice = rendering
    end
end

-- The "Text" section of the action bars and the cooldown manager: font,
-- outline, rendering and shadow, followed by the module's own `extra` rules.
function Build.TextSection(id, extra)
    local rules = {
        Build.Font("font", "Font"),
        Build.Choice("fontOutline", "Text outline", 1, { "Outline", "Thick outline", "None" }),
        Build.Choice("fontRendering", "Font rendering", 3, { "Smooth", "Sharp / pixel", "Slug" }),
        Build.Bool("fontShadow", "Text shadow"),
        Build.Number("fontShadowOpacity", "Shadow opacity (percent)", 100, 20, 100, 5),
        Build.Choice("fontShadowDistance", "Shadow distance", 1, { "1 px", "2 px" }),
    }
    for i = 1, #extra do rules[#rules + 1] = extra[i] end
    Build.Section(id, "text", "Text", rules)
    Build.LinkFontShadow(catalog[id].rules)
end

-- Automation: settings that make the Suite act on the player's behalf without
-- a confirmation each time. It spends or sells, opens or uses items, accepts,
-- chooses or submits for the player, messages other players, sends inspect
-- requests, starts the combat log, or cancels auras and cinematics.
-- Shared imports switch these off (NS.SanitizeAutomation) and profile
-- variants never hold them (ProfileVariants.lua). A module whose spec says
-- automation = true is automation as a whole: its enable switch is flagged,
-- and variants leave all of its rules alone. Build.Automation flags one
-- switch of a module that also does other things.
function Build.Automation(rule)
    assert(type(rule.default) == "boolean", "automation switch " .. tostring(rule.key) .. " is not a switch")
    rule.automation = true
    return rule
end
-- [module id] = { automation rule keys }, filled by FinalizeCatalog.
local automationRules = {}

local function CollectAutomation(id)
    local spec = catalog[id]
    if spec.automation then spec.rules.enabled.automation = true end
    for _, rule in ipairs(spec.controls) do
        if rule.automation then
            local keys = automationRules[id] or {}
            automationRules[id] = keys
            keys[#keys + 1] = rule.key
        end
    end
end

function NS.FinalizeCatalog()
    NS.Defaults.suite = { schema=1, modules={} }
    for i = 1, #order do
        local id = order[i]
        local look = catalog[id].look
        if look and look.extra and not look.global then
            -- Modules without a preset selector still retain whether their
            -- colors follow Class Style through profile export/import.
            Build.Add(id, Build.Bool("classStyle", "Class Style", false), nil, nil, { hidden = true })
        end
        local defaults = {}
        for key, rule in pairs(catalog[id].rules) do defaults[key] = rule.default end
        NS.Defaults.suite.modules[id] = defaults
    end
    for i = 1, #order do CollectAutomation(order[i]) end
end

-- Sharing a setup never authorizes spending or automation: every automation
-- switch of a shared profile arrives switched off.
function NS.SanitizeAutomation(profile)
    local modules = type(profile) == "table" and type(profile.suite) == "table" and profile.suite.modules
    if type(modules) ~= "table" then return end
    for id, keys in pairs(automationRules) do
        local config = modules[id]
        if type(config) == "table" then
            for _, key in ipairs(keys) do config[key] = false end
        end
    end
end

-- Resolve the shared look to a module's ordinary catalog settings. This is
-- pure, so factory profiles can be styled before activation.
local lookIndexes = { midnight = 1, midnightDark = 2, foreverGlass = 3, cleanModern = 5, classColor = 6 }
local function LookValues(id, lookIndex, config)
    local look = catalog[id].look
    if not look or not (look.global or look.extra) then return nil end
    local values = {}
    if look.global then
        local choice = look.global == true and lookIndex or look.global[lookIndex]
        values[look.key] = choice
        local preset = look.presets and look.presets[choice]
        if preset then
            for key, value in pairs(preset) do values[key] = value end
        end
    end
    if look.extra then look.extra(values, lookIndex, config) end
    if not look.global then values.classStyle = lookIndex == 6 end
    return values
end

Looks.indexes = lookIndexes
function NS.SuiteLooks.ApplyToConfig(id, config, lookName)
    if lookName == "classColor" then Looks.RefreshClassColor() end
    local index = lookIndexes[lookName]
    local values = index and LookValues(id, index, config)
    if not values then return false end
    local rules = catalog[id].rules
    local changed = false
    for key, value in pairs(values) do
        local rule = rules[key]
        if rule and type(value) == type(rule.default) and config[key] ~= value then
            config[key] = value
            changed = true
        end
    end
    return changed
end

-- Refresh only modules that still select Class Style. Custom module palettes
-- and DataText per-bar overrides survive login and profile activation.
function Looks.RefreshConfig(id, config)
    local look = catalog[id].look
    if not look then return end
    if look.global then
        local choice = look.global == true and 6 or look.global[6]
        if not choice or config[look.key] ~= choice then return end
        local preset = look.presets and look.presets[choice]
        if preset then
            for key, value in pairs(preset) do
                if catalog[id].rules[key] then config[key] = value end
            end
        end
    elseif look.extra and config.classStyle then
        Looks.ApplyToConfig(id, config, "classColor")
    end
end

-- Factory/setup profiles are staged without touching live frames. Layout,
-- module enable switches and native resource/status colors stay intact.
function Looks.StyleProfile(profile, lookName)
    local db = type(profile) == "table" and profile.suite
    if not db or type(db.modules) ~= "table" or not lookIndexes[lookName] then return false end
    db.globalLook = lookName
    for i = 1, #order do
        local id = order[i]
        local config = db.modules[id]
        if type(config) == "table" then Looks.ApplyToConfig(id, config, lookName) end
    end
    return true
end
