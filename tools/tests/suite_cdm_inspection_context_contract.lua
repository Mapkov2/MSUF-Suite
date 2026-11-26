local root = assert(arg[1])
local source = arg[2] or root
local function NoGameRead() error("configuration inspection read live game state") end
UnitAura, C_Timer, GetTime = NoGameRead, nil, NoGameRead
local config = { enabled = true, c1_on = true, c2_on = false, c1_vis = 1, c2_vis = 4,
    c1_alpha = 100, c2_alpha = 0, c1_oocAlpha = 100, c2_oocAlpha = 100 }
local CDM = { SLOTS = { { key = "c1", title = "First" }, { key = "c2", title = "Second" } },
    KEYS = {}, VIS = { HIDDEN = 4, COMBAT = 2, COMBAT_OR_TARGET = 3 } }
for _, slot in ipairs(CDM.SLOTS) do
    local keys = {}
    for _, suffix in ipairs({ "on", "vis", "alpha", "oocAlpha", "hideMounted", "hideVehicle", "hideReady" }) do
        keys[suffix] = slot.key .. "_" .. suffix
    end
    CDM.KEYS[slot.key] = keys
end
local S = { Config = function() return config end, Availability = function() return true end, states = { cooldownManager = {} } }
assert(loadfile(source .. "/MSUF_Suite/Core/CDMInspection.lua"))("test", { Suite = S, CDM = CDM, Text = function(value) return value end })
local rows = S.CDMInspectionRows()
assert(rows[2].target and rows[2].target.prepareKind == "suiteCDMBar"
    and rows[2].target.prepareValue == "c2", "inspection lost exact CDM bar identity")
assert(rows[2].target.sectionId == "suite_cooldownManager_visibility"
    and rows[2].target.settingKey == "msufsuite.cooldownManager.c1_vis", "inspection does not target actual visibility control")
assert(S.CDMInspectionRow("missing") == nil, "unknown bars must not select a fallback")
assert(rows[1].reason:find("Blizzard", 1, true) and rows[2].reason:find("Hidden", 1, true), "per-bar causes mixed")
local combat = false
local Page = { PAGE = "suite_cooldownManager", ID = "cooldownManager", selected = "c1" }
local P = { CDMPage = Page, Suite = { CDM = CDM }, Combat = function() return combat end }
function Page.Select(slot) Page.selected = slot; return true end
assert(loadfile(source .. "/MSUF_Suite_Options/Pages/CooldownManagerInspection.lua"))("test", P)
local saved = rows[2].target
local page, exact = P.ResolveCDMInspectionTarget("suite_cooldownManager", saved)
assert(page == Page.PAGE and exact ~= saved and exact.prepareKind == nil and exact.prepareValue == nil and Page.selected == "c2", "saved target did not restore its bar")
assert(saved.prepareValue == "c2" and exact.settingKey == saved.settingKey, "saved target identity mutated")
config.c2_vis = 2
assert(S.CDMInspectionRow("c2").reason:find("only in combat", 1, true), "visibility edit kept stale causes")
combat = true
assert(P.ResolveCDMInspectionTarget(Page.PAGE, rows[1].target) == false and Page.selected == "c2", "combat changed target")
combat = false
assert(P.ResolveCDMInspectionTarget(Page.PAGE, { prepareKind = "suiteCDMBar", prepareValue = "missing" }) == false,
    "invalid saved slot did not fail closed")
assert(P.ResolveCDMInspectionTarget("suite_chat", saved) == nil, "unrelated navigation intercepted")
assert(config.c2_on == false and config.c2_alpha == 0, "inspection modified settings")
print("PASS CDM inspection: exact saved bar, current report, combat refusal, no game reads")
