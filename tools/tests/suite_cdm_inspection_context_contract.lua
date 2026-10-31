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
local combat, checks, refreshers, metadata = false, 0, {}, {}
local original = S.CDMInspectionRow
S.CDMInspectionRow = function(key) checks = checks + 1; return original(key) end
local Page = { PAGE = "suite_cooldownManager", ID = "cooldownManager", selected = "c1" }
local note = { GetStringHeight = function(self) return #(self.text or "") / 4 end }
Page.SetRaw = function(label, text) label.text = text end
local P = { CDMPage = Page, S = S, Suite = { CDM = CDM }, T = { colors = {} },
    M = { TrackRefresh = function(_, fn) refreshers[#refreshers + 1] = fn end,
        RegisterControlMetadata = function(_, meta) metadata[#metadata + 1] = meta end },
    HM = { SkipHistoryCheckpoint = function() end }, Combat = function() return combat end,
    Text = function() return note end, FinishBody = function(_, body, y) body.bottom = y end,
    Meta = function(page, id, key, kind, section) return { pageKey = page, key = key, sectionId = section } end }
function P.Refresh() for _, fn in ipairs(refreshers) do fn() end end
function Page.Select(slot) Page.selected = slot; P.Refresh(); return true end
local click
local initialMetadata
P.Button = function(_, _, _, _, _, _, fn, _, meta) click, initialMetadata = fn, meta; return {} end
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/CooldownManagerInspection.lua"))("test", P)
local body = {}
Page.BuildInspection({}, {}, body, -100, 400, "suite_cooldownManager_visibility")
assert(initialMetadata.prepareValue == "c1", "cold first-open target lost its bar before first refresh")
P.Refresh()
assert(checks == 0, "closed inspection performed a scan")
assert(metadata[#metadata].prepareValue == "c1", "new saved targets must capture selected bar")
click()
assert(checks == 1 and note.text:find("Blizzard", 1, true), "check did not show current configuration")
local height = body.bottom
for i = 1, 25 do P.Refresh() end
assert(checks == 1 and body.bottom == height, "unchanged menu refreshes repeated inspection")
config.cosmetic = true
P.Refresh()
assert(checks == 1, "unrelated options rebuilt visibility causes")
local saved = rows[2].target
local page, exact = P.ResolveCDMInspectionTarget("suite_cooldownManager", saved)
assert(page == Page.PAGE and exact ~= saved and exact.prepareKind == nil and exact.prepareValue == nil and Page.selected == "c2", "saved target did not restore its bar")
assert(checks == 2 and note.text:find("Hidden", 1, true), "bar switch kept stale causes")
assert(metadata[#metadata].prepareValue == "c2" and saved.prepareValue == "c2", "target identity mutated")
config.c2_vis = 2
P.Refresh()
assert(checks == 3 and note.text:find("only in combat", 1, true), "visibility edit kept stale causes")
combat = true
assert(P.ResolveCDMInspectionTarget(Page.PAGE, rows[1].target) == false and Page.selected == "c2", "combat changed target")
click(); P.Refresh()
assert(checks == 3, "combat performed an inspection")
combat = false
assert(P.ResolveCDMInspectionTarget(Page.PAGE, { prepareKind = "suiteCDMBar", prepareValue = "missing" }) == false,
    "invalid saved slot did not fail closed")
assert(P.ResolveCDMInspectionTarget("suite_chat", saved) == nil, "unrelated navigation intercepted")
assert(config.c2_on == false and config.c2_alpha == 0, "inspection modified settings")
print("PASS CDM inspection: exact saved bar, cold manual UI, changed-only refresh, combat refusal, no game reads")
