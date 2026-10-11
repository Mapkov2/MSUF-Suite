-- Reuse the real meter's established native-client fixture and runtime
-- budgets; then check the new isolated menu renderer, including Forever.
local root = assert(arg[1])
local originalLoad, private = loadfile
loadfile = function(path)
    local chunk = assert(originalLoad(path))
    return function(addon, namespace)
        if path:find("MSUF_Suite_DamageMeter/Data.lua", 1, true) then private = namespace end
        return chunk(addon, namespace)
    end
end
local fixture = arg[2] == "Forever" and "suite_damage_meter_threat_contract.lua" or "suite_damage_meter_contract.lua"
assert(originalLoad(root .. "/tools/tests/" .. fixture))()
loadfile = originalLoad
local S, D = private.Suite, private.DamageMeter
local M = D.M
assert(originalLoad(root .. "/MSUF_Suite_DamageMeter/Preview.lua"))("MSUF_Suite_DamageMeter", private)
M:Disable()
M.active = false
local config, snapshot, windows = S.Config("damageMeter"), {}, {}
for key, value in pairs(config) do snapshot[key] = value end
for key, value in pairs(D.windows) do windows[key] = value end
config.w1Width, config.w1Height = 420, 240
config.w1Type, config.w1Session = D.TYPE.DamageDone + 1, D.SESSION.OVERALL
config.iconStyle = D.ICON.NONE
local stage = CreateFrame("Frame", nil, UIParent)
local preview = assert(S.DamageMeterDrawMenuPreview(stage, 1))
assert(preview.frame:GetWidth() == 420 and preview.frame:GetHeight() == 240, "menu did not draw the whole runtime window")
assert(preview.title.text:find("Overall", 1, true), "preview lost the Overall heading")
assert(not preview.rows[1].icon:IsShown(), "preview ignored Icons=None")
assert(preview.rows[1].valueText.text and preview.rows[1].nameText.text, "runtime row formatter did not paint samples")
local layouts, layout = 0, D.StyleWindowLayout
D.StyleWindowLayout = function(...) layouts = layouts + 1; return layout(...) end
local gen = M.styleGen
local sinks = { preview.frame, preview.header, preview.title, preview.timer, preview.rows[1], preview.rows[1].nameText, preview.rows[1].valueText }
local methods = { "SetSize", "SetPoint", "ClearAllPoints", "SetText", "SetFont", "SetShown" }
local savedSinks = {}
for i, region in ipairs(sinks) do
    savedSinks[i] = {}
    for _, key in ipairs(methods) do
        savedSinks[i][key] = rawget(region, key)
        region[key] = function() error("warm meter preview wrote a native sink") end
    end
end
local instructions = 0
debug.sethook(function() instructions = instructions + 1 end, "", 1)
for i = 1, 100 do assert(S.DamageMeterDrawMenuPreview(stage, 1) == preview) end
debug.sethook()
assert(instructions < 600000, "warm meter preview exceeded its bounded settings-scan budget")
for i, region in ipairs(sinks) do for _, key in ipairs(methods) do region[key] = savedSinks[i][key] end end
print("Warm meter source budget: " .. instructions .. " instructions / 100 draws, zero layout/text writes")
assert(layouts == 0 and M.styleGen == gen, "warm meter preview restyled or allocated a new window")
config.w1Width = 460
S.DamageMeterDrawMenuPreview(stage, 1)
assert(layouts == 1 and preview.frame:GetWidth() == 460, "settings did not reach the runtime preview")
if D.THREAT then
    config.w1Type = D.THREAT + 1
    S.DamageMeterDrawMenuPreview(stage, 1)
    assert(preview.rows[1].valueText.text:find("100%%"), "Threat sample did not use runtime threat formatting")
    assert(not preview.rows[1].icon:IsShown(), "Threat sample ignored Icons=None")
end
for key, value in pairs(windows) do assert(D.windows[key] == value and value ~= preview, "menu borrowed a live meter window") end
assert(not M.active and not M.preview, "menu enabled the meter or its live preview mode")
for key, value in pairs(config) do config[key] = snapshot[key] end
D.StyleWindowLayout = layout
print("Meter menu preview: whole runtime window, formatters, Threat, isolation and warm cache passed")
