local root = assert(arg[1], "repository root required")
local reason, available = "Update MSUF to use the cooldown manager", false
local config = { enabled = true, c1_on = false, c1_vis = 4, c1_alpha = 0 }
local state = {}
local S = { Config = function() return config end, states = { cooldownManager = state },
    Availability = function() return available, reason end }
local keys = {}
for _, key in ipairs({ "on", "vis", "alpha", "oocAlpha", "hideMounted", "hideVehicle", "hideReady" }) do keys[key] = "c1_" .. key end
local NS = { Suite = S, Text = function(value) return value end, CDM = {
    SLOTS = { { key = "c1", title = "Custom bar" } }, KEYS = { c1 = keys },
    VIS = { HIDDEN = 4, COMBAT = 2, COMBAT_OR_TARGET = 3 },
} }
assert(loadfile(root .. "/MSUF_Suite/Core/CDMInspection.lua"))("test", NS)
assert(S.CDMInspectionRow("c1").reason == reason, "unavailable module must take precedence over bar settings")
available, reason, state.error = true, nil, "Stopped after an error"
assert(S.CDMInspectionRow("c1").reason == state.error, "module load/runtime failure must be first")
state.error, config.enabled = nil, false
assert(S.CDMInspectionRow("c1").reason == "Cooldown manager is switched off.", "disabled module must be first")
print("suite_cdm_usability_inspection_contract: availability, failure and disabled precedence passed")
