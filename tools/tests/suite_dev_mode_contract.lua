local root = assert(arg[1], "Suite root required")
local forcedCombat = "addonCombatRestrictionsForced"
local secret = newproxy()
local values, writes, reads, prints, opened = {}, {}, 0, {}, {}
local fighting, refused, locked, indicator = false, nil, nil, nil
local function Unused() error("Dev Mode started background work") end
local function Noop() end

CreateFrame, hooksecurefunc = Unused, Unused
C_Timer = setmetatable({}, { __index = Unused })
SlashCmdList = {}
C_CVar = {
    GetCVar = function(key) reads = reads + 1; return values[key] end,
    GetCVarInfo = function(key) return values[key], "0", false, false, false, key == locked, false end,
    SetCVar = function(key, value)
        writes[#writes + 1] = { key, value }
        if key ~= refused then values[key] = value end
    end,
}
UnitAffectingCombat = function(unit) assert(unit == "player"); return fighting end
local function Identity(value) return value end
local Suite = {
    IsSecret = function(value) return rawequal(value, secret) end,
    Public = function(value) return not rawequal(value, secret) end,
    IsCombatLocked = function() return fighting or values[forcedCombat] == "1" end,
    InCombat = function(event) return event ~= "PLAYER_REGEN_ENABLED" and (fighting or values[forcedCombat] == "1") end,
    Dispatch = function(fn, ...) return fn(...) end,
    Text = Identity,
    Print = function(message) prints[#prints + 1] = message end,
    Menu = { Open = function(page) opened[#opened + 1] = page; return true end },
    Client = { isForever = true },
    RootDB = {},
}
assert(loadfile(root .. "/MSUF_Suite/Core/DevBarAnimationText.lua"))("MSUF_Suite", Suite)
assert(loadfile(root .. "/MSUF_Suite/Core/DevBarAnimation.lua"))("MSUF_Suite", Suite)
assert(loadfile(root .. "/MSUF_Suite/Core/DevMode.lua"))("MSUF_Suite", Suite)
local Dev, Run = Suite.DevMode, assert(SlashCmdList.MSUFSUITEDEVMODE)
local report, reportShown, reportStopped
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", Suite)

local spec, switches, actions, dropdown
local P = {
    Suite = Suite, Tr = Identity, Meta = function() end, FinishBody = function() end,
    W = { PageBuilder = function()
        return { Section = function() return {} end, width = 720 }
    end },
    HM = { GetSectionWidth = function() end },
    M = {
        BindDropdownAt = function(_, _, label, _, _, _, _, get, set)
            if label == "Taint logging" then dropdown = { get, set } end
        end,
        BindSwitchAt = function(_, _, label, _, _, _, get, set) switches[label] = { get, set } end,
    },
    RegisterPage = function(page) spec = page end,
    Description = function() return { GetStringHeight = function() return 14 end } end,
    Button = function(_, _, label, _, _, _, click)
        actions[label] = click
        return { GetHeight = function() return 26 end }
    end,
}
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/DevMode.lua"))("MSUF_Suite_Options", P)
spec.build({ searchRows = {} })
if Dev.RestoreLogging then Dev.RestoreLogging() end
if Dev.RestoreRestrictions then Dev.RestoreRestrictions() end
assert(reads == 0 and #writes == 0, "load or indexing queried or wrote a CVar")
assert(SLASH_MSUFSUITEDEVMODE1 == "/msufdev" and spec.key == "suite_devMode" and spec.reset == false)
Run("")
assert(opened[1] == spec.key and reads == 0, "slash did not open the diagnostic page")


UIParent = {}
CreateFrame = function(kind, name, parent)
    assert(kind == "Frame" and name == nil and parent == UIParent)
    local label = {
        SetPoint = Noop, GetStringWidth = function() return 48 end,
        SetText = function(_, value) assert(value == "Dev Mode on") end,
    }
    local texture = { SetAllPoints = Noop, SetColorTexture = Noop, SetSize = Noop, SetPoint = Noop, SetTexture = Noop }
    indicator = {
        SetPoint = function(_, point, relative, relativePoint, x, y)
            assert(point == "TOPLEFT" and relative == UIParent and relativePoint == "TOPLEFT" and x > 0 and y < 0)
        end,
        SetFrameStrata = Noop,
        EnableMouse = function(_, enabled) assert(not enabled) end,
        CreateTexture = function() return texture end,
        CreateFontString = function() return label end,
        SetSize = function(_, width, height) assert(width < 150 and height <= 24) end,
        RegisterEvent = function(self, event) assert(event == "CVAR_UPDATE"); self.watching = true end,
        UnregisterEvent = function(self, event) assert(event == "CVAR_UPDATE"); self.watching = false end,
        SetScript = function(self, event, handler) assert(event == "OnEvent"); self.callback = handler end,
        SetShown = function(self, shown) self.shown = shown end,
    }
    return indicator
end

for _, entry in ipairs(Dev.restrictions) do values[entry.key] = "0" end
values.taintLog = "0"
switches, actions = {}, {}
spec.build({})
assert(#writes == 0 and dropdown[1]() == "0", "viewing settings changed a CVar")
assert(not actions["Taint Report"], "legacy Core advertised an unavailable report")
MSUF_HostAPI = { GetTaintReport = function() return report end }
report = {
    version = 1,
    Show = function() reportShown = true end,
    Stop = function() reportStopped = true end,
}
spec.build({})
assert(actions["Taint Report"], "Dev Mode did not expose the Core report")()
assert(reportShown, "Dev Mode did not open the Core report")
report = nil
local textSwitch = assert(switches["Animate bar text"])
assert(not textSwitch[1]())
textSwitch[2](true)
assert(textSwitch[1]() and not Suite.DevBarAnimation.IsRunning(), "text toggle started the test")
textSwitch[2](false)
for _, entry in ipairs(Dev.restrictions) do assert(switches[entry.label] and not switches[entry.label][1]()) end
dropdown[2]("2")
assert(values.taintLog == "2" and dropdown[1]() == "2")
assert(Suite.RootDB.devModeCVars and Suite.RootDB.devModeCVars.taintLog == "2", "logging level was not saved")
assert(indicator and indicator.shown and indicator.watching, "missing diagnostic indicator")
values.taintLog = "1"
indicator:callback("CVAR_UPDATE", "TAINTLOG")
assert(indicator.shown and Suite.RootDB.devModeCVars.taintLog == "1", "console logging level was not saved")
values.taintLog = "0"
indicator:callback("CVAR_UPDATE", "taintLog")
assert(not indicator.shown and not indicator.watching and Suite.RootDB.devModeCVars == nil,
    "disabling through the console left logging queued for reload")
local logStart = #writes
Run("log")
assert(#writes == logStart + 1 and values.taintLog == "2" and Suite.RootDB.devModeCVars.taintLog == "2"
    and values[forcedCombat] == "0" and indicator.shown, "log command did not enable and save only verbose logging")
dropdown[2]("0")
local chat = Dev.restrictions[1]
local beforeSwitch = #writes
switches[chat.label][2](true)
assert(switches[chat.label][1]() and Suite.RootDB.devModeCVars[chat.key] == "1" and values[forcedCombat] == "0")
assert(writes[beforeSwitch + 1][1] == "taintLog" and writes[beforeSwitch + 1][2] == "2"
    and writes[beforeSwitch + 2][1] == chat.key, "enabling a Dev Mode switch did not start verbose logging first")
dropdown[2]("1")
local beforeBatch = #writes
actions["Force all addon restrictions"]()
assert(writes[beforeBatch + 1][1] == "taintLog" and writes[beforeBatch + 1][2] == "2",
    "enabling all Dev Mode restrictions did not start verbose logging first")
assert(writes[#writes][1] == forcedCombat and values.taintLog == "2", "batch order or logging isolation")
for _, entry in ipairs(Dev.restrictions) do assert(values[entry.key] == "1") end

-- A new Lua session starts with the saved root and factory CVars.
local previousIndicator = indicator
for key in pairs(values) do values[key] = "0" end
assert(loadfile(root .. "/MSUF_Suite/Core/DevMode.lua"))("MSUF_Suite", Suite)
Dev, Run = Suite.DevMode, SlashCmdList.MSUFSUITEDEVMODE
fighting = true
Dev.RestoreLogging()
assert(values.taintLog == "2" and values[forcedCombat] == "0", "combat reload did not restore only logging early")
assert(indicator ~= previousIndicator and indicator.shown, "reloaded diagnostics did not show the indicator")
fighting = false
Dev.RestoreRestrictions()
assert(writes[#writes][1] == forcedCombat)
for _, entry in ipairs(Dev.restrictions) do assert(values[entry.key] == "1") end

-- The client can also retain native CVars. The simulated combat flag must
-- come down for startup while its saved value survives for replay.
assert(loadfile(root .. "/MSUF_Suite/Core/DevMode.lua"))("MSUF_Suite", Suite)
Dev, Run = Suite.DevMode, SlashCmdList.MSUFSUITEDEVMODE
Dev.RestoreLogging()
assert(values[forcedCombat] == "0" and Suite.RootDB.devModeCVars[forcedCombat] == "1")
fighting = true
Dev.RestoreRestrictions("PLAYER_REGEN_ENABLED")
assert(values[forcedCombat] == "1", "stale player combat flag blocked the post-combat startup restore")

-- Before logging was coupled to Dev Mode, saved profiles could contain only
-- forced restrictions. Logging must be active on the very first reload.
Suite.RootDB.devModeCVars.taintLog, values.taintLog = nil, "0"
Dev.RestoreLogging()
assert(values.taintLog == "2" and Suite.RootDB.devModeCVars.taintLog == "2" and values[forcedCombat] == "1",
    "a legacy saved Dev Mode did not restore verbose logging in combat")

local before = #writes
Run("off")
assert(#writes == before and values[forcedCombat] == "1" and prints[#prints]:find("combat", 1, true))
fighting = false
Run("off")
assert(writes[before + 1][1] == forcedCombat, "simulated combat was not cleared first")
assert(values.taintLog == "0")
for _, entry in ipairs(Dev.restrictions) do assert(values[entry.key] == "0") end
assert(not indicator.shown and not indicator.watching and Suite.RootDB.devModeCVars == nil,
    "turning diagnostics off left an indicator, watcher or reload preference")
before = reads
Dev.RestoreLogging()
Dev.RestoreRestrictions()
assert(reads == before, "disabled diagnostics queried CVars on startup")

assert(Dev.Set(chat.key, "1") and Dev.Read(chat.key) == "1" and values[forcedCombat] == "0")
values[chat.key] = nil
values[Dev.restrictions[2].key] = secret
local ok, reason = Dev.SetAll(true)
assert(not ok and reason == "rejected" and values[forcedCombat] == "1",
    "a secret CVar hid a partial failure or prevented supported writes")
assert(values[chat.key] == nil and rawequal(values[Dev.restrictions[2].key], secret))
values[Dev.restrictions[2].key] = nil
refused = forcedCombat
Run("off")
assert(prints[#prints] == "/console addonCombatRestrictionsForced 0", "missing forced-combat recovery")
refused = nil
report = { version = 1, Stop = function() reportStopped = true end }
assert(Dev.SetAll(false))
assert(reportStopped, "turning off diagnostics left the Core report recording")
refused = "taintLog"
ok, reason = Dev.Set("taintLog", "2")
assert(not ok and reason == "rejected" and values.taintLog == "0")
ok, reason = Dev.SetAll(true)
assert(not ok and reason == "rejected" and values[forcedCombat] == "0", "all restrictions started without logging")
before = #writes
locked = chat.key
values[chat.key] = "0"
assert(not Dev.Set(chat.key, "1") and #writes == before, "secure CVar attempted a write")
Run("on extra")
Run("taint 99")
Run(secret)
assert(not Dev.Set("scriptErrors", "1") and #writes == before, "unlisted diagnostic action wrote a CVar")
assert(Suite.RootDB.devModeCVars == nil, "rejected changes persisted")
print("Suite Dev Mode cold load, reload, indicator, CVar validation and combat recovery passed")
