-- Apex's existing native-frame signals must survive Suite taking over CDM.
-- The optional second argument mutation-checks the original Native.lua.
local root = arg[1] or "."
local locked, applies, queued, writes, hooks = false, 0, 0, 0, 0
local cvar, saved = "0", nil
local M = { active = true, config = { blizzard = 1 } }
local S = {}
function S.Public(value) return type(value) ~= "table" or value.secret ~= true end
function S.Text(value) return value end
function S.Dispatch(fn, ...) return fn(...) end
function S.Number(value) return type(value) == "number" end
function S.Queue() queued = queued + 1 end
function S.RestoreCVar()
    if saved ~= nil then cvar, saved = saved, nil; writes = writes + 1 end
end
local ctx = { callbacks = {} }
M.context = ctx
function ctx:CVar(_, value)
    if saved == nil then saved = cvar end
    cvar = value
    writes = writes + 1
end
function ctx:Alpha(viewer, value) viewer:SetAlpha(value) end
function ctx:RestoreProperty(viewer) viewer:SetAlpha(1) end
function ctx:Event(event, callback) self.callbacks[event] = callback end
function ctx:RemoveEvent(event) self.callbacks[event] = nil end
function hooksecurefunc(target, method, callback)
    hooks = hooks + 1
    local original = target[method]
    target[method] = function(...)
        original(...)
        callback(...)
    end
end
local viewers = {}
for _, name in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do
    local viewer = { alpha = 1 }
    function viewer:SetAlpha(value) self.alpha = value; writes = writes + 1 end
    function viewer:OnAcquireItemFrame() end
    function viewer:GetChildren() end
    _G[name] = viewer
    viewers[#viewers + 1] = viewer
end
local C = { M = M, Const = { BLIZZARD = { OFF = 1, INVISIBLE = 2 } },
    Layout = { MSUFAnchor = function() return false, false end } }
local P = { CDM = C, Suite = S, NS = {
    CDM = { KEYS = {} }, Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return locked end,
} }
assert(loadfile(arg[2] or root .. "/MSUF_Suite_CooldownManager/Native.lua"))("MSUF_Suite_CooldownManager", P)
local N = C.Native
function S.Apply()
    applies = applies + 1
    N.Apply()
end
local function Invisible()
    for _, viewer in ipairs(viewers) do assert(viewer.alpha == 0, "a native viewer became visible") end
end
local function Settings()
    RogueApexNow:ApplySettings()
end

RogueApexNow = { db = { enabled = true, shadowTechniquesGlow = false }, ApplySettings = function() end }
assert(N.Mode() == 2, "active Apex was stopped by Suite's default native mode")
assert(select(2, N.Mode()):find("Rogue Apex Now", 1, true), "status must explain Apex compatibility")
N.WatchApex(ctx)
N.Apply()
assert(cvar == "1" and saved == "0", "Apex must enable even an originally disabled viewer reversibly")
assert(M.config.blizzard == 1, "compatibility must not rewrite the saved native mode")
Invisible()
local beforeWrites, beforeApplies, beforeHooks = writes, applies, hooks
Settings()
N.Apply()
N.WatchApex(ctx)
assert(writes == beforeWrites and applies == beforeApplies and hooks == beforeHooks, "unchanged settings must be inert")

RogueApexNow.db.enabled = false
Settings()
assert(applies == beforeApplies + 1 and N.Mode() == 1 and cvar == "0", "turning Apex off must release its native requirement")
RogueApexNow.db.shadowTechniquesGlow = true
Settings()
assert(N.Mode() == 2 and cvar == "1", "Apex's independent stack glow still needs native sources")
Invisible()

locked = true
beforeWrites = writes
RogueApexNow.db.shadowTechniquesGlow = false
Settings()
assert(queued == 1 and writes == beforeWrites and cvar == "1", "combat must defer native writes")
locked = false
N.Apply()
assert(cvar == "0" and N.Applied() == 1, "deferred native mode must apply after combat")

-- A late addon load is discovered without any polling or double hooks.
RogueApexNow = nil
N.WatchApex(ctx)
RogueApexNow = { db = { enabled = true }, ApplySettings = function() end }
local loaded = assert(ctx.callbacks.ADDON_LOADED)
beforeApplies = applies
loaded(M, "ADDON_LOADED", "UnrelatedAddon")
assert(applies == beforeApplies, "an unrelated addon triggered a refresh")
loaded(M, "ADDON_LOADED", "RogueApexNow")
assert(applies == beforeApplies + 1 and cvar == "1", "late Apex load did not enable its sources")
beforeHooks = hooks
loaded(M, "ADDON_LOADED", "RogueApexNow")
assert(hooks == beforeHooks, "late load installed duplicate hooks")

-- Explicit invisible mode also owns and restores an originally-off CVar.
M.config.blizzard = 2
RogueApexNow.db.enabled = false
Settings()
assert(N.Mode() == 2 and cvar == "0", "explicit invisible mode must restore the original CVar after Apex stops")
RogueApexNow.db.enabled = true
Settings()
assert(N.Mode() == 2 and cvar == "1", "Apex must enable its sources even without a mode transition")
Invisible()
M.active = false
N.Release()
assert(cvar == "0" and saved == nil and ctx.callbacks.ADDON_LOADED == nil, "Suite disable must restore and unregister")
for _, viewer in ipairs(viewers) do assert(viewer.alpha == 1, "Suite disable must restore native alpha") end
beforeApplies = applies
RogueApexNow.db.enabled = false
Settings()
assert(applies == beforeApplies, "a disabled Suite reacted to Apex's settings")

M.active, M.config.blizzard = true, 1
RogueApexNow = { db = { enabled = { secret = true }, shadowTechniquesGlow = { secret = true } } }
assert(N.Mode() == 1, "unreadable foreign flags must fail closed")
RogueApexNow = { db = "broken" }
assert(N.Mode() == 1, "malformed foreign settings must fail closed")
RogueApexNow = nil
N.WatchApex(ctx)
N.Apply()
N.Release()
assert(cvar == "0", "an absent Apex changed the original native behavior")
print("suite_apex_now_compat_contract: OK")
