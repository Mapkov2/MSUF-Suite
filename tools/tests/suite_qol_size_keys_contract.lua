local root = assert(arg[1], "repository root required")
-- MSUF Edit Mode builds a mover's size controls from its sizeKeys and the
-- catalog rules (MSUF_Suite_Modules/EditMode.lua, PopupControls); a key
-- without a ranged rule silently loses its control. Every sizeKeys list in
-- the Quality of Life addon must name ranged rules of its own module.
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
MSUF_NS = {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
InCombatLockdown = function() return false end
Minimap = { SetMaskTexture = function() end }
UnitGUID = function() return "Player-Test" end
CreateFrame = function()
    local frame = {}
    for _, key in ipairs({ "SetScript", "RegisterEvent", "UnregisterEvent", "UnregisterAllEvents" }) do
        frame[key] = function() end
    end
    return frame
end
C_AddOns = { IsAddOnLoaded = function() return false end, DoesAddOnExist = function() return false end,
    GetAddOnEnableState = function() return 0 end, LoadAddOn = function() end }
local Suite = Support.Load(root, "MSUF_Suite", {}, "Core/Suite.lua")
local catalog = assert(Suite.SuiteCatalog, "the Suite catalog did not load")

local checked = 0
for _, file in ipairs(Support.TocFiles(root, "MSUF_Suite_QualityOfLife")) do
    if file:match("%.lua$") then
        local handle = assert(io.open(root .. "/MSUF_Suite_QualityOfLife/" .. file, "rb"))
        local source = handle:read("*a"):gsub("\r\n", "\n")
        handle:close()
        local fileID = source:match('\nlocal ID%s*=%s*"([%w_]+)"') or source:match('\nlocal ID%s*,[^=\n]*=%s*"([%w_]+)"')
        for call in source:gmatch("S%.RegisterOwnedMover%((.-)%}%)") do
            local keys = call:match("sizeKeys%s*=%s*(%b{})")
            if keys then
                local first = call:match("^%s*([^,]+),")
                local id = first and (first:match('^"([%w_]+)"$') or first == "ID" and fileID)
                assert(id and catalog[id], file .. ": a mover with sizeKeys names no catalog module")
                for key in keys:gmatch('"([%w_]+)"') do
                    local rule = catalog[id].rules[key]
                    assert(rule and type(rule.min) == "number" and type(rule.max) == "number",
                        file .. ": size key " .. key .. " has no ranged rule in " .. id)
                    checked = checked + 1
                end
            end
        end
        assert(not source:find("extraControls%s*=%s*{%s*\n%s*{ id = \"width\""),
            file .. " builds width controls by hand; use sizeKeys")
    end
end
assert(checked >= 30, "the scan found only " .. checked .. " size keys")
print("QoL size keys: " .. checked .. " keys name ranged catalog rules")
