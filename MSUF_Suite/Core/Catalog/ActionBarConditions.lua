local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_ActionBars")
local E = NS.ActionBarEnum
local VIS, COND = E.VISIBILITY, E.CONDITION
local prefixes = {}
for i = 1, NS.ActionBarCount do prefixes[i] = "bar" .. i end
local labels = { "Always", "In combat", "Out of combat", "Mouseover", "Mouseover or combat", "Never", "Custom conditions" }
local extra = {
    { "CondFocus", "Focus condition", { "Ignore", "Has a focus", "No focus" } },
    { "CondFlying", "Flight condition", { "Ignore", "Flying", "Not flying" } },
    { "CondGroup", "Group condition", { "Ignore", "Grouped", "Solo", "In party", "In raid", "Not in party", "Not in raid" } },
    { "CondCasting", "Casting condition", { "Ignore", "Casting or channeling", "Not casting or channeling" } },
    { "CondSkyriding", "Skyriding condition", { "Ignore", "Skyriding", "Not skyriding" } },
    { "CondInstance", "Instance condition", { "Ignore", "In instance", "Outside instances", "In dungeon", "Outside dungeons",
        "In raid instance", "Outside raid instances", "In dungeon or raid", "Outside dungeons and raids" } },
    { "CondHousing", "Housing condition", { "Ignore", "In housing", "Outside housing", "Inside house", "On house plot",
        "In house editor", "In neighbourhood" } },
}
local shared = {
    B.Choice("globalVisibility", "Shared visibility mode", VIS.MOUSEOVER, labels),
    B.Choice("globalCondCombine", "Show when", E.COMBINE.ANY, { "Any condition is met", "All conditions are met" }),
    B.Choice("globalCondCombat", "Combat condition", COND.YES, { "Ignore", "In combat", "Out of combat" }),
    B.Choice("globalCondMounted", "Mount condition", COND.IGNORE, { "Ignore", "Mounted", "Not mounted" }),
    B.Choice("globalCondTarget", "Target condition", E.TARGET_CONDITION.IGNORE,
        { "Ignore", "Has a target", "No target", "Hostile target", "Friendly target" }),
    B.Bool("globalCondMouseover", "Reveal on mouseover", true),
}
B.Section("actionbars", "global_visibility", "Shared visibility rules", shared)
local rules = NS.SuiteCatalog.actionbars.rules
for i = 0, NS.ActionBarCount do
    local p = i == 0 and "global" or prefixes[i]
    local rows = {}
    if i > 0 then rows[1] = B.Bool(p .. "UseGlobalVisibility", "Use shared visibility rules", false) end
    for _, spec in ipairs(extra) do rows[#rows + 1] = B.Choice(p .. spec[1], spec[2], COND.IGNORE, spec[3]) end
    B.Section("actionbars", i == 0 and "global_visibility" or p,
        i == 0 and "Shared visibility rules" or NS.ActionBarTitles[i], rows, i > 0 and { bar = i } or nil)
    for _, suffix in ipairs({ "CondCombine", "CondCombat", "CondMounted", "CondTarget", "CondMouseover" }) do
        rules[p .. suffix].requiresChoice = { key = p .. "Visibility", values = { [VIS.CUSTOM] = true } }
        if i > 0 then rules[p .. suffix].disabledBy = p .. "UseGlobalVisibility" end
    end
    for _, spec in ipairs(extra) do
        local rule = rules[p .. spec[1]]
        if spec[1] == "CondCasting" or spec[1] == "CondInstance" or spec[1] == "CondSkyriding" then
            B.Tooltip(rule, [[These conditions fade the bar's visuals while its secure buttons keep their normal input.
Combine with mouseover to reveal it while pointing at the bar.]])
        end
        rule.requiresChoice = { key = p .. "Visibility", values = { [VIS.CUSTOM] = true } }
        if i > 0 then rule.disabledBy = p .. "UseGlobalVisibility" end
    end
    rules[p .. "CondSkyriding"].hidden = NS.Client.isForever or nil
    rules[p .. "CondHousing"].hidden = NS.Client.isForever or nil
    if i > 0 then rules[p .. "Visibility"].disabledBy = p .. "UseGlobalVisibility" end
    if i > 0 then B.Tooltip(rules[p .. "UseGlobalVisibility"],
        "Follows later changes to Shared visibility rules. Turning this bar off with its quick switch still keeps it hidden.") end
end

function NS.ActionBarVisibilityPrefix(config, index)
    local p = prefixes[index]
    return config[p .. "UseGlobalVisibility"] and config[p .. "Visibility"] ~= VIS.NEVER and "global" or p
end

function NS.ActionBarVisibilityMode(config, index)
    return config[NS.ActionBarVisibilityPrefix(config, index) .. "Visibility"]
end

local visibilitySuffixes = { "Visibility", "CondCombine", "CondCombat", "CondMounted", "CondTarget", "CondMouseover",
    "CondFocus", "CondFlying", "CondGroup", "CondCasting", "CondSkyriding", "CondInstance", "CondHousing" }
-- A direct mover edit detaches just this bar from shared rules, beginning
-- with the effective values. Other bars and the saved shared rule stay put.
function NS.ActionBarLocalVisibility(config, index)
    local p, values = prefixes[index], {}
    if config[p .. "UseGlobalVisibility"] then
        local from = NS.ActionBarVisibilityPrefix(config, index)
        for _, suffix in ipairs(visibilitySuffixes) do values[p .. suffix] = config[from .. suffix] end
        values[p .. "UseGlobalVisibility"] = false
    end
    return values
end

function NS.ActionBarHasContext(config, index)
    local p = NS.ActionBarVisibilityPrefix(config, index)
    return (config[p .. "CondCasting"] or 1) > 1 or (config[p .. "CondInstance"] or 1) > 1
        or (not NS.Client.isForever and (config[p .. "CondSkyriding"] or 1) > 1)
end

local macroTests = {
    CondCombat = { [2] = "combat", [3] = "nocombat" },
    CondMounted = { [2] = "mounted", [3] = "nomounted" },
    CondTarget = { [2] = "@target,exists", [3] = "@target,noexists", [4] = "@target,harm", [5] = "@target,help" },
    CondFocus = { [2] = "@focus,exists", [3] = "@focus,noexists" },
    CondFlying = { [2] = "flying", [3] = "noflying" },
    CondGroup = { [2] = "group", [3] = "nogroup", [4] = "group:party", [5] = "group:raid",
        [6] = "nogroup:party", [7] = "nogroup:raid" },
    CondHousing = { [2] = "house", [3] = "nohouse", [4] = "house:inside", [5] = "house:plot",
        [6] = "house:editor", [7] = "house:neighborhood" },
}
-- Target selectors must not share a bracket: @focus would redirect the
-- target condition. Separate brackets represent OR; ALL uses a secure
-- failure clause per test, followed by the positive result.
local order = { "CondTarget", "CondCombat", "CondMounted", "CondFocus", "CondFlying", "CondGroup", "CondHousing" }
local inverse = {
    ["@target,exists"] = "@target,noexists", ["@target,noexists"] = "@target,exists",
    ["@target,harm"] = "@target,noharm", ["@target,help"] = "@target,nohelp",
    ["@focus,exists"] = "@focus,noexists", ["@focus,noexists"] = "@focus,exists",
}
local function Negate(test)
    if inverse[test] then return inverse[test] end
    return test:sub(1, 2) == "no" and test:sub(3) or "no" .. test
end

function NS.ActionBarConditionBody(config, index)
    local p = NS.ActionBarVisibilityPrefix(config, index)
    local tests = {}
    for _, suffix in ipairs(order) do
        if suffix ~= "CondHousing" or not NS.Client.isForever then
            local test = macroTests[suffix][config[p .. suffix]]
            if test then tests[#tests + 1] = test end
        end
    end
    local hover = config[p .. "CondMouseover"] == true
    local context = NS.ActionBarHasContext(config, index)
    local shown = context and "context" or hover and "fade" or "show"
    if #tests == 0 then return shown end
    if config[p .. "CondCombine"] == E.COMBINE.ALL then
        -- Preserve the original compact body when there is only one unit.
        local focused = (config[p .. "CondFocus"] or 1) > 1
        if not focused then return "[" .. table.concat(tests, ",") .. "] " .. shown .. "; hide" end
        local body = {}
        for _, test in ipairs(tests) do body[#body + 1] = "[" .. Negate(test) .. "] hide" end
        body[#body + 1] = shown
        return table.concat(body, "; ")
    end
    local body = {}
    for _, test in ipairs(tests) do body[#body + 1] = "[" .. test .. "] show" end
    body[#body + 1] = context and "context" or hover and "fade" or "hide"
    return table.concat(body, "; ")
end

local instanceTests = {
    function(c) return c.inInstance end,
    function(c) return not c.inInstance end,
    function(c) return c.instanceType == "party" end,
    function(c) return c.instanceType ~= "party" end,
    function(c) return c.instanceType == "raid" end,
    function(c) return c.instanceType ~= "raid" end,
    function(c) return c.instanceType == "party" or c.instanceType == "raid" end,
    function(c) return c.instanceType ~= "party" and c.instanceType ~= "raid" end,
}
local contextOrder = { "CondCasting", "CondInstance", "CondSkyriding" }
function NS.ActionBarContextPasses(config, index, context)
    local p = NS.ActionBarVisibilityPrefix(config, index)
    local all = config[p .. "CondCombine"] == E.COMBINE.ALL
    local seen, result = false, all
    for _, suffix in ipairs(contextOrder) do
        local choice = config[p .. suffix] or 1
        if choice > 1 and (suffix ~= "CondSkyriding" or not NS.Client.isForever) then
            local value
            if suffix == "CondInstance" then value = instanceTests[choice - 1](context)
            else
                value = suffix == "CondCasting" and context.casting or suffix == "CondSkyriding" and context.skyriding
                value = choice == COND.YES and value == true or choice == COND.NO and value ~= true
            end
            result, seen = all and result and value or not all and (result or value), true
        end
    end
    return seen and result == true
end

function NS.ActionBarFades(config, index)
    local mode = NS.ActionBarVisibilityMode(config, index)
    if mode == VIS.MOUSEOVER or mode == VIS.MOUSEOVER_OR_COMBAT then return true end
    local p = NS.ActionBarVisibilityPrefix(config, index)
    return mode == VIS.CUSTOM and (config[p .. "CondMouseover"] == true or NS.ActionBarHasContext(config, index))
end
