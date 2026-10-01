-- The catalog specs carry the module metadata the rest of the Suite derives
-- its lists from (no hand-kept copies): the module addon (Build.ForAddon),
-- automation (spec.automation, Build.Automation), the Edit Mode element
-- (spec.editElement) and the collapsed-section summary (spec.summary).
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Read(path)
    local file = io.open(root .. "/" .. path, "rb")
    if not file then return nil end
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end
MSUF_NS = {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
InCombatLockdown = function() return false end
local Suite = Support.Load(root, "MSUF_Suite", {}, "Core/Suite.lua")
local catalog, order = Suite.SuiteCatalog, Suite.SuiteOrder

-- The Lua sources of an addon, in TOC order.
local sources = {}
local function AddonSources(addon)
    if sources[addon] then return sources[addon] end
    local list = {}
    for _, file in ipairs(Support.TocFiles(root, addon)) do
        if file:match("%.lua$") then list[#list + 1] = assert(Read(addon .. "/" .. file), addon .. "/" .. file) end
    end
    sources[addon] = list
    return list
end

local source = Read("MSUF_Suite/Core/SuiteCatalog.lua")
Check(not source:find("moduleAddons", 1, true) and not source:find("automationModules", 1, true)
    and not source:find("automationSwitches", 1, true), "the catalog keeps a hand list of module metadata")

for _, id in ipairs(order) do
    local spec = catalog[id]
    -- Every module runs in an addon of this repository.
    Check(type(spec.addon) == "string" and Read(spec.addon .. "/" .. spec.addon .. "_Mainline.toc"),
        id .. " names no Suite addon: " .. tostring(spec.addon))
    -- An automation module flags its switch; every automation rule is a switch.
    Check(not spec.automation or spec.rules.enabled.automation == true, id .. " is automation but its switch is not")
    for _, rule in ipairs(spec.controls) do
        Check(not rule.automation or type(rule.default) == "boolean", id .. "." .. rule.key .. " is no switch")
    end
    -- Every summary key names a setting; numbered bars and windows share one.
    if spec.summary then
        for key in spec.summary:gmatch("%S+") do
            local found = spec.rules[key] ~= nil
            for ruleKey in pairs(spec.rules) do
                if ruleKey:gsub("^bar%d+", "bar"):gsub("^w%d+", "w") == key then found = true end
            end
            Check(found, id .. " summarizes a setting it does not have: " .. key)
        end
    end
    -- An Edit Mode element is one the module's runtime registers.
    if spec.editElement then
        local registered = false
        for _, text in ipairs(AddonSources(spec.addon)) do
            if text:find('"' .. id .. '"', 1, true) and text:find("RegisterOwnedMover(", 1, true)
                and text:find('"' .. spec.editElement .. '"', 1, true) then registered = true end
        end
        Check(registered, id .. " names an Edit Mode element its runtime never registers: " .. spec.editElement)
    end
end

-- Shared imports switch off exactly the flagged rules.
local profile = { suite = { schema = 1, modules = {} } }
for _, id in ipairs(order) do
    local config = {}
    for key, rule in pairs(catalog[id].rules) do
        if type(rule.default) == "boolean" then config[key] = true end
    end
    profile.suite.modules[id] = config
end
Suite.SanitizeAutomation(profile)
local flagged = 0
for _, id in ipairs(order) do
    for key, value in pairs(profile.suite.modules[id]) do
        local rule = catalog[id].rules[key]
        Check((value == false) == (rule.automation == true), "a shared import kept or cleared the wrong switch: " .. id .. "." .. key)
        if rule.automation then flagged = flagged + 1 end
    end
end
Check(flagged > 0, "no automation switch is flagged")
print("Suite catalog metadata: " .. checks .. " checks passed")
