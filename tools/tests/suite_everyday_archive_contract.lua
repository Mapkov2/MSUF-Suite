local root = assert(arg[1])
local F = assert(loadfile(root .. "/tools/tests/comfort_fixture.lua"))()
local E = F.New(root, false)
local S, NS = E.S, E.NS
date = os.date
local chat = { M = { config = { historyLines = 20 } } }
E.P.Chat = chat
E:Load("MSUF_Suite_Chat/History.lua")
local ring = chat.HistoryRing("1:General")
for i = 1, 25 do chat.HistoryStore(ring, "|cffffffffMessage " .. i .. "|r", 1, 1, 1) end
local rows = chat.HistorySnapshot()
assert(#rows == 20 and rows[1].text == "Message 25" and rows[20].text == "Message 6", "search snapshot is newest first and bounded")
chat.HistoryStore(ring, "|Hitem:1|h[Item]|h", 1, 1, 1)
rows = chat.HistorySnapshot()
assert(rows[1].text == "[Item]" and rows[1].search:find("General", 1, true), "plain searchable text keeps tab identity")
chat.HistoryStore(ring, "|HBNplayer:|Ksecret|k|h[Person]|h", 1, 1, 1)
assert(not chat.HistorySnapshot()[1].text:find("|K", 1, true), "cross-session names sanitized")
chat.M:ClearHistory(); assert(#chat.HistorySnapshot() == 0, "cleared history disappears")
chat.M.config = nil
S.Config = function() return { historyLines = 20 } end
chat.HistoryStore(chat.HistoryRing("2:Disabled"), "Saved while previously enabled", 1, 1, 1)
assert(#chat.HistorySnapshot() == 1, "saved archive opens when chat module was never enabled this session")

-- The browser keeps its snapshot only while its window is open (up to 16 tabs of 1000 lines otherwise stay in memory), and
-- turning Chat off closes it. The stand-in window hides first when it is already shown, as the shared window does.
local shown, held = nil, setmetatable({}, { __mode = "v" })
S.ToolListWindow = {
    Open = function(owner, spec)
        if shown then shown.spec.onHide(shown.owner) end
        shown = { owner = owner, spec = spec }
        held.rows = spec.rows(owner)
        return {}
    end,
    Refresh = function(owner) if shown and shown.owner == owner then held.rows = shown.spec.rows(owner) end end,
    Close = function(owner)
        if not (shown and shown.owner == owner) then return end
        local window = shown
        shown = nil
        window.spec.onHide(owner)
    end,
}
E:Load("MSUF_Suite_Chat/HistoryBrowser.lua")
chat.M:OpenHistory()
assert(#held.rows == 1, "the browser lists the saved message")
chat.M:OpenHistory()
assert(#held.rows == 1, "opening the browser again lost its rows")
chat.HistoryStore(chat.HistoryRing("3:Trade"), "Another saved message", 1, 1, 1)
shown.spec.actions[2].run(shown.owner)
assert(#held.rows == 2, "Refresh saved messages did not take a new snapshot")
S.ToolListWindow.Close(shown.owner)
collectgarbage()
assert(held.rows == nil, "the snapshot outlived its window")
chat.M:OpenHistory()
assert(#held.rows == 2, "the browser did not open again after its snapshot was released")
assert(chat.HistoryDisable, "Chat has no way to close the history browser")
chat.HistoryDisable()
assert(shown == nil, "turning Chat off left the history browser open")
collectgarbage()
assert(held.rows == nil, "turning Chat off kept the snapshot")

local reads = 0
local bar1 = { index = 1, key = { Visibility = "bar1Visibility" } }
local action = { M = { active = true, config = {} }, ENUM = { VISIBILITY = { NEVER = 6 } }, BUTTONS = 12, owned = {
    { command = "ACTIONBUTTON1", bar = bar1, index = 1, button = { GetAttribute = function() return 1 end } },
    { command = "ACTIONBUTTON2", bar = bar1, index = 2, button = { GetAttribute = function() return E.secret end } },
} }
E.P.ActionBars = action
NS.ActionBarTitles = { "Action bar 1" }
GetActionInfo = function(slot) reads = reads + 1; assert(slot == 1); return "spell", 7 end
GetBindingKey = function() return nil end
C_Spell = { GetSpellInfo = function() return { name = "Heal" } end }
E:Load("MSUF_Suite_ActionBars/KeyAudit.lua")
rows = S.ActionKeyAuditRows(true)
assert(#rows == 1 and reads == 1 and rows[1].label:find("Heal"), "only public actual action slots inspected")
E:Combat(true); assert(#S.ActionKeyAuditRows(false) == 0 and reads == 1, "no action scan in combat")
E:Combat(false)
GetBindingKey = function() return "1" end
assert(#S.ActionKeyAuditRows(true) == 0, "bound action disappears from issues-only list")
assert(#S.ActionKeyAuditRows(false) == 1, "full review retains bound action")

NS.CDM = { SLOTS = { { key = "ess", title = "Essential" } }, KEYS = { ess = { on = "on", vis = "vis",
    alpha = "alpha", oocAlpha = "ooc", hideMounted = "mounted", hideVehicle = "vehicle", hideReady = "ready" } },
    VIS = { HIDDEN = 4, COMBAT = 2, COMBAT_OR_TARGET = 3 } }
local config = { enabled = true, on = true, vis = 1, alpha = 100, ooc = 100 }
S.Config = function() return config end
S.Availability = function() return true end
S.states = { cooldownManager = {} }
assert(loadfile(root .. "/MSUF_Suite/Core/CDMInspection.lua"))("test", NS)
rows = S.CDMInspectionRows(); assert(#rows == 1 and rows[1].reason:find("Blizzard"), "config inspection does not promise spell visibility")
config.on, config.vis, config.ooc, config.mounted = false, 4, 0, true
rows = S.CDMInspectionRows()
assert(rows[1].reason:find("switched off", 1, true) and rows[1].reason:find("Hidden", 1, true)
    and rows[1].reason:find("opacity", 1, true), "all applicable configured causes explained")
E:Load("MSUF_Suite_Modules/PreparationStatus.lua")
assert(S.PlanningReadiness()[1].status == "unknown", "disabled reminder is not ready")
S.instances.buffReminders = { active = true, list = { entries = { { present = true }, { present = false } } }, listen = {} }
assert(S.PlanningReadiness()[1].status == "missing", "existing missing result reused")
S.instances.buffReminders.list.needsFullRefresh = true
assert(S.PlanningReadiness()[1].status == "unknown", "stale owner cache is not ready")
print("PASS everyday archives: saved chat search, key review, visibility causes and cached preparation")
