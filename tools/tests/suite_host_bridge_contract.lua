-- Suite-side stub matrix of the Suite's host bridge (MSUF_Suite/Core/
-- HostBridge.lua): this Suite against a stubbed MSUF host with host API v1
-- (MSUF_HostAPI and Menu2's page-reset providers) and a stubbed older host.
-- With v1 it calls the host and wraps or writes nothing of MSUF's; without
-- it, it runs the Suite's previous code; both give the same MSUF_DB and
-- refuse the same specs. Real HostBridge.lua; the v1 host is a stub that
-- writes the fields the host API v1 spec names (the Suite's previous code is
-- the oracle). The full old/new host x old/new Suite matrix with the real
-- hosts is W4-H's host-side contract.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = DeepCopy(item) end
    return copy
end
local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local calls = {}
local function Legacy()
    calls = {}
    _G.MSUF_ApplyMsufScale = function(value) calls[#calls + 1] = "frame:" .. value end
    _G.MSUF_ResetGlobalUiScale = function() calls[#calls + 1] = "reset" end
    _G.MSUF_SetGlobalUiScale = function(value) calls[#calls + 1] = "global:" .. value end
    _G.MSUF_EnsureCooldownWidthObservers = function() calls[#calls + 1] = "observers" end
    _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey = function(unit) calls[#calls + 1] = "embed:" .. unit end
    _G.MSUF_ClassPower_Apply = function() calls[#calls + 1] = "classpower" end
    _G.MSUF_UFCore_NotifyConfigChanged = function(unit) calls[#calls + 1] = "notify:" .. unit end
end
local function NoLegacy()
    for _, name in ipairs({ "MSUF_ApplyMsufScale", "MSUF_ResetGlobalUiScale", "MSUF_SetGlobalUiScale",
        "MSUF_EnsureCooldownWidthObservers", "MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", "MSUF_ClassPower_Apply",
        "MSUF_UFCore_NotifyConfigChanged" }) do _G[name] = nil end
end
local function FreshDB()
    return { general = { UIScale = { Enabled = false, Scale = 0.53 }, msufUiScale = 0.9, uiScale = 0.8 },
        bars = { classPowerOffsetY = 12 }, player = { powerBarDetached = false } }
end

-- A v1 host, written to the spec: the same fields and appliers, its own.
local hostCalls, hostLookups = {}, 0
local HostAPI = { version = 1 }
function HostAPI.ApplyUIScaleProfile(spec)
    hostCalls[#hostCalls + 1] = "scale"
    local general = MSUF_DB.general
    general.msufUiScale = spec.msufScale or 1
    general.uiScale = nil
    if spec.global then
        general.UIScale.Enabled, general.UIScale.Scale = true, spec.global.scale
        general.globalUiScalePreset, general.globalUiScaleValue = spec.global.preset, spec.global.scale
    end
    return true
end
function HostAPI.SetResourceStack(mode)
    hostCalls[#hostCalls + 1] = "stack:" .. mode
    local bars, player = MSUF_DB.bars, MSUF_DB.player
    bars.showClassPower, bars.classPowerAnchorToCooldown, bars.classPowerCooldownTopAnchor = true, true, true
    bars.classPowerWidthMode, bars.detachedPowerBarWidthMode = "cooldown", "cooldown"
    bars.classPowerOffsetX, bars.classPowerOffsetY = 0, 0
    player.showPowerBar, player.powerBarDetached = true, true
    player.detachedPowerBarAnchorToClassPower, player.detachedPowerBarSyncClassPower = true, true
    player.detachedPowerBarAnchorMode = "CENTER"
    player.detachedPowerBarOffsetX, player.detachedPowerBarOffsetY = 0, -4
    return true
end
function HostAPI.GetResourceStack() return MSUF_DB.bars.classPowerAnchorToCooldown and "cooldown" or nil end

local function Bridge(withHost)
    rawset(_G, "MSUF_HostAPI", nil)
    hostLookups = 0
    setmetatable(_G, { __index = function(_, key)
        if key == "MSUF_HostAPI" then
            hostLookups = hostLookups + 1
            return withHost and HostAPI or nil
        end
    end })
    local Suite = { Finite = function(value)
        return type(value) == "number" and value == value and value > -math.huge and value < math.huge
    end }
    assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", Suite)
    return Suite.HostBridge
end

local SPEC = { msufScale = 1, global = { preset = "custom", scale = 0.71 } }

-- Without v1: the Suite's previous writes and appliers, in MSUF's order.
Legacy()
MSUF_DB = FreshDB()
local bridge = Bridge(false)
Check(bridge.ScaleReady(SPEC) and bridge.ApplyScale(SPEC) and not bridge.HasCoreAPI(), "the legacy scale path refused")
Check(table.concat(calls, ",") == "frame:1,reset,global:0.71", "the legacy scale appliers ran out of order")
Check(bridge.SetResourceStack("cooldown") and not bridge.SetResourceStack("other"), "the legacy stack refused")
Check(table.concat(calls, ",") == "frame:1,reset,global:0.71,observers,embed:player,classpower,notify:player",
    "the legacy stack appliers ran out of order")
local legacyDB = DeepCopy(MSUF_DB)
_G.MSUF_ResetGlobalUiScale = nil
Check(not bridge.ScaleReady(SPEC) and not bridge.ApplyScale(SPEC), "the legacy scale path ran without MSUF's appliers")

-- With v1: the host writes; the Suite calls none of MSUF's appliers (they
-- stay tripwires here) and writes nothing itself; the result is the same
-- MSUF_DB.
Legacy()
MSUF_DB = FreshDB()
hostCalls = {}
bridge = Bridge(true)
Check(bridge.ScaleReady(SPEC) and bridge.ApplyScale(SPEC) and bridge.SetResourceStack("cooldown")
    and not bridge.SetResourceStack("other") and bridge.HasCoreAPI(), "the v1 host path refused")
Check(table.concat(hostCalls, ",") == "scale,stack:cooldown" and #calls == 0,
    "the v1 host was not called for the writes, or the Suite called MSUF's appliers itself")
Check(Same(MSUF_DB, legacyDB), "the v1 host and the legacy path gave different MSUF settings")

-- Both paths refuse the same specs before anything is written: an invalid
-- spec, and a missing MSUF scale owner (the v1 setter's "unavailable").
local INVALID = { msufScale = 1, global = { preset = "custom", scale = 0 / 0 } }
for _, withHost in ipairs({ true, false }) do
    Legacy()
    MSUF_DB = FreshDB()
    local before = DeepCopy(MSUF_DB)
    bridge = Bridge(withHost)
    local ready, why = bridge.ScaleReady(INVALID)
    local applied, applyWhy = bridge.ApplyScale(INVALID)
    Check(not ready and not applied and why == "MSUF refused this UI scale" and applyWhy == why
        and Same(MSUF_DB, before), (withHost and "v1" or "legacy") .. ": an invalid scale spec was not refused")
    _G.MSUF_ResetGlobalUiScale = nil
    ready, why = bridge.ScaleReady(SPEC)
    applied, applyWhy = bridge.ApplyScale(SPEC)
    Check(not ready and not applied and why == "MSUF scale controls unavailable" and applyWhy == why
        and Same(MSUF_DB, before), (withHost and "v1" or "legacy") .. ": a missing MSUF scale owner was not refused")
end
-- A refusal MSUF gives only when it applies (its own range check) reaches
-- the caller in the installer's words.
Legacy()
MSUF_DB = FreshDB()
bridge = Bridge(true)
local applyScale = HostAPI.ApplyUIScaleProfile
HostAPI.ApplyUIScaleProfile = function() return false, "invalid" end
local applied, applyWhy = bridge.ApplyScale(SPEC)
Check(not applied and applyWhy == "MSUF refused this UI scale", "a v1 refusal at apply was not passed on")
HostAPI.ApplyUIScaleProfile = function() return false, "combat" end
applied, applyWhy = bridge.ApplyScale(SPEC)
Check(not applied and applyWhy == "Finish combat first.", "a v1 combat refusal was not passed on")
HostAPI.ApplyUIScaleProfile = applyScale

-- The host API is looked up once, however often the bridge is used.
for _ = 1, 100 do bridge.ApplyScale(SPEC) end
Check(hostLookups == 1, ("the host API was looked up %d times for 101 uses"):format(hostLookups))
setmetatable(_G, nil)

------------------------------------------------------------------ page resets
local function Handlers(log)
    local pages = { suite_bags = true, suite_hud = true }
    local h = { pages = pages, combatLocked = false }
    h.withHistory = function(label, source, fn) log[#log + 1] = "history:" .. label .. ":" .. source; return fn() end
    h.confirm = function(key, text, onAccept) log[#log + 1] = "confirm:" .. key .. ":" .. text; h.accept = onAccept end
    h.combat = function() return h.combatLocked end
    h.canReset = function(key) return pages[key] == true end
    h.warning = function(key) return "Reset " .. key .. "?" end
    h.label = function(key) return "Reset " .. key end
    h.prepare = function() return true end
    h.run = function(key) log[#log + 1] = "run:" .. key; return true end
    h.finish = function(key) log[#log + 1] = "finish" end
    return h
end
local function Host(v1)
    local M = { log = {} }
    function M.PageHasReset(key) return key == "host_page" end
    function M.BuildPageResetWarning(key) return "host warning " .. key end
    function M.ResetPageToDefaults(key) M.log[#M.log + 1] = "host reset " .. key; return true end
    function M.ShowPageResetConfirm(key) M.log[#M.log + 1] = "host confirm " .. key; return true end
    function M.RefreshToolbarPageReset() M.refreshed = (M.refreshed or 0) + 1 end
    if v1 then
        M.HOST_API_VERSION = 1
        function M.RegisterPageResetProvider(id, provider) M.providers = M.providers or {}; M.providers[id] = provider end
    end
    return M
end

-- v1 Menu2: one provider; Menu2's own functions stay its own.
bridge = Bridge(false)
local M = Host(true)
local own = { M.PageHasReset, M.BuildPageResetWarning, M.ResetPageToDefaults, M.ShowPageResetConfirm }
local log = {}
local handlers = Handlers(log)
Check(bridge.RegisterPageResets(M, handlers) == "provider" and M.refreshed == 1, "the v1 menu got no provider")
Check(M.PageHasReset == own[1] and M.BuildPageResetWarning == own[2] and M.ResetPageToDefaults == own[3]
    and M.ShowPageResetConfirm == own[4] and not M._msufSuitePageResetsInstalled,
    "the Suite wrapped a v1 menu's page reset functions")
local provider = M.providers["msuf-suite"]
Check(provider and provider.pages.suite_bags and provider.canReset("suite_hud") and not provider.canReset("host_page")
    and provider.warning("suite_bags") == "Reset suite_bags?", "the provider does not describe the Suite pages")
Check(provider.reset("suite_bags") and table.concat(log, ",") == "run:suite_bags,finish",
    "the provider reset wrapped its own history or skipped the refresh")
handlers.combatLocked = true
Check(not provider.reset("suite_bags") and #log == 2, "the provider reset ran in combat")
handlers.combatLocked = false
-- (Register.lua's real canReset handler is measured for allocations in
-- suite_options_menu_contract.)

-- Older Menu2: the four functions are wrapped as before.
M = Host(false)
log = {}
handlers = Handlers(log)
Check(bridge.RegisterPageResets(M, handlers) == "legacy" and M._msufSuitePageResetsInstalled, "the old menu was not wrapped")
Check(M.PageHasReset("suite_bags") and M.PageHasReset("host_page") and not M.PageHasReset("other"),
    "the wrapped PageHasReset lost a page")
Check(M.BuildPageResetWarning("suite_hud") == "Reset suite_hud?" and M.BuildPageResetWarning("host_page") == "host warning host_page",
    "the wrapped warning lost a page")
Check(M.ShowPageResetConfirm("suite_bags") and log[1] == "confirm:page-reset:Reset suite_bags?", "the wrapped confirm did not ask")
handlers.accept()
Check(table.concat(log, ",") == "confirm:page-reset:Reset suite_bags?,history:Reset suite_bags:page:reset:suite_bags,run:suite_bags,finish",
    "the wrapped reset lost its history entry or refresh")
Check(M.ResetPageToDefaults("host_page") and M.ShowPageResetConfirm("host_page") and M.log[1] == "host reset host_page"
    and M.log[2] == "host confirm host_page", "the wrap did not pass the host's pages through")
handlers.combatLocked = true
Check(not M.ResetPageToDefaults("suite_bags") and not M.ShowPageResetConfirm("suite_bags"), "the wrapped reset ran in combat")

-- One owner: the installer, the profiles and the page registration reach
-- MSUF's settings only through the bridge.
local function Source(rel)
    local file = assert(io.open(root .. "/" .. rel, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end
for _, rel in ipairs({ "MSUF_Suite/Core/Installer.lua", "MSUF_Suite/Core/Profiles.lua", "MSUF_Suite_Options/Menu/Register.lua" }) do
    local text = Source(rel)
    for _, write in ipairs({ "general.msufUiScale =", "general.UIScale", "bars.classPowerAnchorToCooldown = true",
        "player.powerBarDetached = true", "function M.PageHasReset", "function M.ResetPageToDefaults" }) do
        Check(not text:find(write, 1, true), rel .. " still writes " .. write .. " itself")
    end
end
Check(Source("MSUF_Suite/Core/Installer.lua"):find("Suite.HostBridge.ApplyScale(", 1, true)
    and Source("MSUF_Suite/Core/Profiles.lua"):find('Suite.HostBridge.SetResourceStack("cooldown")', 1, true)
    and Source("MSUF_Suite_Options/Menu/Register.lua"):find("Suite.HostBridge.RegisterPageResets(M,", 1, true),
    "a caller does not go through the bridge")

print("Suite host bridge: " .. checks .. " checks passed")
