local root = assert(arg[1])
local combat, calls, writes, queued, pending = false, 0, 0, 0, 0
local function Write() assert(not combat, "native special styling in combat"); writes = writes + 1 end
local function Region(font)
    local r = { alpha = 1, font = font or "original", size = 11, flags = "OUTLINE" }
    function r:GetAlpha() calls = calls + 1; return self.alpha end
    function r:SetAlpha(value) Write(); self.alpha = value end
    function r:GetFont() return self.font, self.size, self.flags end
    function r:SetFont(path, size, flags) Write(); self.font, self.size, self.flags = path, size, flags end
    function r:GetTextColor() return 1, 1, 1, 1 end
    function r:SetTextColor() Write() end
    function r:GetShadowOffset() return 1, -1 end
    function r:SetShadowOffset() Write() end
    function r:GetShadowColor() return 0, 0, 0, 1 end
    function r:SetShadowColor() Write() end
    return r
end
local hooks = {}
local function Hook(frame, event, fn) hooks[frame] = hooks[frame] or {}; hooks[frame][event] = fn end
local extra = { style = Region(), HotKey = Region(), HookScript = Hook, GetFrameLevel = function() return 5 end }
local time = Region()
extra.cooldown = { HookScript = Hook, GetCountdownFontString = function() return time end }
local zoneTime = Region()
local zoneButton = { Cooldown = { HookScript = Hook, GetCountdownFontString = function() return zoneTime end },
    HookScript = Hook, GetFrameLevel = extra.GetFrameLevel }
local zone = { Style = Region(), UpdateDisplayedZoneAbilities = function() end,
    SpellButtonContainer = { EnumerateActive = function()
        local first = true
        return function() if first then first = false; return zoneButton end end
    end } }
ExtraActionButton1, ZoneAbilityFrame = extra, zone
local zoneCallback
hooksecurefunc = function(object, method, callback)
    assert(object == zone and method == "UpdateDisplayedZoneAbilities", "unexpected native hook")
    zoneCallback = callback
end
local NS = { InCombat = function() return combat end }
local config = { styleSpecialButtons = false, hideSpecialArtwork = false, specialKeybind = true,
    specialKeybindSize = 13, specialCooldownSize = 17, borderSize = 0 }
local S = { Finite = function(value) return type(value) == "number" end,
    Queue = function() queued = queued + 1 end,
    SetStyledFont = function(region, font, size, flags) region:SetFont(font, size, flags) end }
local cancelled = 0
local AB = { M = { active = true, config = config, context = {
    Coalesce = function(_, _, fn) return { Request = function() pending = pending + 1 end,
        Cancel = function() cancelled = cancelled + 1 end } end } },
    style = { texts = { keybind = { font = "keys", flags = "" }, cooldown = { font = "time", flags = "OUTLINE" } },
        kr = 1, kg = 1, kb = 1, dr = 1, dg = 1, db = 1 } }
assert(loadfile(root .. "/MSUF_Suite_ActionBars/ExtraButtons.lua"))("MSUF_Suite_ActionBars", { NS = NS, Suite = S, ActionBars = AB })
AB.SyncSpecialButtons()
assert(calls == 0 and writes == 0 and next(hooks) == nil and not zoneCallback, "default path touched native UI")
config.styleSpecialButtons, config.hideSpecialArtwork, config.specialKeybind = true, true, false
AB.SyncSpecialButtons()
assert(extra.style.alpha == 0 and zone.Style.alpha == 0, "artwork stayed visible")
assert(extra.HotKey.alpha == 0 and extra.HotKey.font == "keys" and extra.HotKey.size == 13, "extra hotkey style")
assert(time.font == "time" and time.size == 17 and zoneCallback, "zone/extra cooldown style or update lifecycle")
local prior = writes
combat, config.hideSpecialArtwork = true, false
AB.SyncSpecialButtons()
assert(writes == prior and queued == 1 and AB.specialPending, "combat change was not deferred")
combat = false
AB.SyncSpecialButtons()
assert(extra.style.alpha == 1 and zone.Style.alpha == 1, "artwork did not restore")
AB.M.active = false
AB.StopSpecialButtons()
assert(extra.HotKey.alpha == 1 and extra.HotKey.font == "original" and time.font == "original", "font/alpha restoration")
local count = calls
prior = writes
zoneCallback()
AB.SyncSpecialButtons()
assert(calls == count and writes == prior and pending == 0 and cancelled == 1, "disabled special adapter kept working")
assert(extra._msuf == nil and extra.border == nil, "addon state leaked onto native button")

-- Execute the real selector, then exercise it with the persisted runtime.
local f = assert(io.open(root .. "/MSUF_Suite_ActionBars/Controller.lua", "rb"))
local source = f:read("*a"); f:close()
local a = assert(source:find("local function ApplyAutoAdd(config)", 1, true))
local b = assert(source:find("local function Collect(config)", a, true))
local actions = {}
local api = { RestoreCVar = function(id, key) actions[#actions + 1] = { "restore", id, key } end }
local module = { context = { CVar = function(_, key, value) actions[#actions + 1] = { "apply", key, value } end } }
local chunk = assert(loadstring("local S, M = ...\n" .. source:sub(a, b - 1) .. "\nreturn ApplyAutoAdd"))
local apply = chunk(api, module)
apply({ autoAddSpells = 2 })
assert(actions[1][1] == "apply" and actions[1][2] == "AutoPushSpellToActionBar" and actions[1][3] == "1", "persisted enable")
apply({ autoAddSpells = 3 })
assert(actions[2][3] == "0", "persisted disable")
apply({ autoAddSpells = 1 })
assert(actions[3][1] == "restore" and actions[3][2] == "actionbars", "native recovery owner not used")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local _, catalog = Support.CatalogDefaults(root, "actionbars", "ActionBars")
assert(catalog.SuiteCatalog.actionbars.cvars.AutoPushSpellToActionBar, "disabled addon cannot recover its CVar")

-- A queued native style change must run after combat even when no setting
-- changed; this is the actual controller refresh with unrelated work parked.
local start = assert(source:find("function M:Refresh()", 1, true))
local finish = assert(source:find("-- Blizzard's bars cannot be rebuilt", start, true))
local syncs = 0
local owner = { config = { imported = true } }
local bars = { specialPending = true, BAR_COUNT = 0, bars = {},
    ReparentLeaveButton = function() end, Masque = { Active = function() return false end },
    SyncAssistedDecoration = function() end, UpdateClickAttributes = function() end,
    SyncSpecialButtons = function() syncs = syncs + 1 end }
local env = { M = owner, AB = bars, NS = { IsCombatLocked = function() return false end },
    work = {}, rebuild = false, EventRegistry = { TriggerEvent = function() end } }
for _, name in ipairs({ "SyncCapture", "ApplyPickupModifier", "ApplyAutoAdd", "Collect", "ApplyLayout", "ApplyStyle",
    "ApplyVisibilityWork", "ApplyPaint", "ClearWork" }) do env[name] = function() end end
env.AnyBarWork = function() return false end
local refresh = assert(loadstring(source:sub(start, finish - 1)))
setfenv(refresh, setmetatable(env, { __index = _G })); refresh()
owner:Refresh()
assert(syncs == 1, "queued special styling was lost on an unchanged refresh")

-- Reload discards Lua-local state, keeping only the saved recovery table and
-- native CVar. The actual runtime must retain the first pre-override value.
do
    local values, reads = { AutoPushSpellToActionBar = "0" }, 0
    local runtimeNS = { RootDB = {}, Public = function() return true end,
        Dispatch = function(fn, ...) return fn(...) end, Skin = { Release = function() end } }
    local runtimeEnv = setmetatable({ MSUFSuite = runtimeNS,
        C_CVar = {
            GetCVar = function(key) reads = reads + 1; return values[key] end,
            SetCVar = function(key, value) values[key] = value end,
        }, UnitName = function() return "Tester" end, GetRealmName = function() return "Realm" end }, { __index = _G })
    runtimeEnv._G = runtimeEnv
    local function Boot()
        runtimeNS.Suite = { catalog = catalog.SuiteCatalog, instances = {} }
        local code = assert(loadfile(root .. "/MSUF_Suite_Modules/Runtime.lua"))
        setfenv(code, runtimeEnv); code("MSUF_Suite_Modules", {})
        local runtime = runtimeNS.Suite
        return runtime, chunk(runtime, { context = runtime.NewContext("actionbars") })
    end
    local runtime, choose = Boot()
    choose({ autoAddSpells = 1 })
    assert(reads == 0, "default automatic placement queried a native CVar")
    choose({ autoAddSpells = 2 })
    assert(values.AutoPushSpellToActionBar == "1", "native placement was not enabled")
    runtime, choose = Boot()
    choose({ autoAddSpells = 2 })
    choose({ autoAddSpells = 1 })
    assert(values.AutoPushSpellToActionBar == "0", "reload lost the original automatic-placement setting")
    values.AutoPushSpellToActionBar = "1"
    choose({ autoAddSpells = 3 })
    runtime, choose = Boot()
    runtime.RestoreSaved("actionbars")
    assert(values.AutoPushSpellToActionBar == "1", "disabled action bar addon could not recover its declared CVar")
    choose({ autoAddSpells = 3 })
    values.AutoPushSpellToActionBar = "1" -- a later player choice wins.
    choose({ autoAddSpells = 1 })
    assert(values.AutoPushSpellToActionBar == "1", "restore overwrote a later player choice")
end
print("Action bars: special styles, deferred refresh and persisted CVar routing passed")
