local _, Suite = ...

-- The one place where the Suite reaches into MSUF for settings MSUF owns:
-- the UI scale, the class resource stack and Menu2's page resets. MSUF hosts
-- with host API v1 (MSUF_HostAPI and Menu2's RegisterPageResetProvider, the
-- "MSUF host API v1 for the Suite") own these writes; older hosts get the
-- Suite's previous code, kept here unchanged. Capabilities are resolved
-- once, at the first use (MSUF's core loads before the Suite, its options
-- before the Suite's), and cached.
local HostBridge = {}
Suite.HostBridge = HostBridge

local HOST_API_VERSION = 1
local coreResolved, coreAPI = false, nil

-- MSUF_HostAPI when it is v1 or newer, else nil.
local function CoreAPI()
    if not coreResolved then
        coreResolved = true
        local api = _G.MSUF_HostAPI
        if type(api) == "table" and type(api.version) == "number" and api.version >= HOST_API_VERSION
            and type(api.ApplyUIScaleProfile) == "function" and type(api.SetResourceStack) == "function" then
            coreAPI = api
        end
    end
    return coreAPI
end

function HostBridge.HasCoreAPI()
    return CoreAPI() ~= nil
end

------------------------------------------------------------------ UI scale
-- The legacy path: MSUF's own scale settings and appliers, written in the
-- order MSUF applies them.
local function LegacyScaleReady(spec)
    if type(_G.MSUF_DB) ~= "table" or type(_G.MSUF_DB.general) ~= "table" then
        return false, "MSUF scale settings unavailable"
    end
    if type(_G.MSUF_ResetGlobalUiScale) ~= "function"
        or type(_G.MSUF_ApplyMsufScale) ~= "function" then
        return false, "MSUF scale controls unavailable"
    end
    if spec.global and type(_G.MSUF_SetGlobalUiScale) ~= "function" then
        return false, "MSUF UI scale control unavailable"
    end
    return true
end

local function LegacyApplyScale(spec)
    local general = _G.MSUF_DB.general
    local msufScale = spec.msufScale or 1
    general.msufUiScale = msufScale
    general.uiScale = nil
    _G.MSUF_ApplyMsufScale(msufScale)
    _G.MSUF_ResetGlobalUiScale(true)
    local global = spec.global
    if not global then return true end
    general.UIScale = type(general.UIScale) == "table" and general.UIScale or {}
    general.UIScale.Enabled = true
    general.UIScale.Scale = global.scale
    general.globalUiScalePreset = global.preset
    general.globalUiScaleValue = global.scale
    _G.MSUF_SetGlobalUiScale(global.scale, true)
    return true
end

-- Whether a scale profile can be applied now (spec as for ApplyScale).
-- A v1 host answers for itself when it applies.
function HostBridge.ScaleReady(spec)
    if CoreAPI() then return true end
    return LegacyScaleReady(spec)
end

-- spec = { msufScale = number (default 1), global = nil | { preset = "pixel"|"custom", scale = number } }
-- Returns ok, reason.
function HostBridge.ApplyScale(spec)
    local api = CoreAPI()
    if api then return api.ApplyUIScaleProfile(spec) end
    local ready, why = LegacyScaleReady(spec)
    if not ready then return false, why end
    return LegacyApplyScale(spec)
end

------------------------------------------------------------------ resource stack
-- The legacy path: the class resource and the detached player power bar
-- stack on the cooldown manager, as MSUF's own settings, then MSUF's
-- appliers (each guarded: older MSUF builds lack some of them).
local function LegacyCooldownStack()
    local db = _G.MSUF_DB
    local bars, player = db.bars, db.player
    bars.showClassPower = true
    bars.classPowerAnchorToCooldown = true
    bars.classPowerCooldownTopAnchor = true
    bars.classPowerWidthMode = "cooldown"
    bars.detachedPowerBarWidthMode = "cooldown"
    bars.classPowerOffsetX, bars.classPowerOffsetY = 0, 0
    player.showPowerBar = true
    player.powerBarDetached = true
    player.detachedPowerBarAnchorToClassPower = true
    player.detachedPowerBarSyncClassPower = true
    player.detachedPowerBarAnchorMode = "CENTER"
    player.detachedPowerBarOffsetX, player.detachedPowerBarOffsetY = 0, -4
    if type(_G.MSUF_EnsureCooldownWidthObservers) == "function" then
        _G.MSUF_EnsureCooldownWidthObservers()
    end
    if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey) == "function" then
        _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey("player", true)
    end
    if type(_G.MSUF_ClassPower_Apply) == "function" then
        _G.MSUF_ClassPower_Apply({ playerHP = true })
    end
    if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
        _G.MSUF_UFCore_NotifyConfigChanged("player", false, true, "SuiteResourceStack")
    end
    return true
end

-- mode "cooldown": class resource and power bar on the cooldown manager.
-- Returns whether anything changed; unknown modes change nothing.
function HostBridge.SetResourceStack(mode)
    if mode ~= "cooldown" then return false end
    local api = CoreAPI()
    if api then return api.SetResourceStack(mode) == true end
    local db = _G.MSUF_DB
    if type(db) ~= "table" or type(db.bars) ~= "table" or type(db.player) ~= "table" then return false end
    return LegacyCooldownStack()
end

------------------------------------------------------------------ page resets
-- handlers (from MSUF_Suite_Options/Menu/Register.lua):
--   pages        { [pageKey] = true } of the Suite pages
--   canReset     fn(key) -> whether the page resets now (addon state)
--   warning      fn(key) -> the confirmation text
--   label        fn(key) -> the history label
--   prepare      fn(key) -> whether what the reset needs is there
--   run          fn(key) -> ok: the reset itself (no history, no refresh)
--   finish       fn(key): refresh and feedback after a reset
--   withHistory  fn(label, source, fn) -> ok;  confirm fn(key, text, onAccept)
--   combat       fn() -> whether combat refuses
-- A v1 Menu2 owns the confirmation, the combat refusal and the history
-- entry; older menus get the four wrapped functions as before.
local PROVIDER_ID = "msuf-suite"

local function RegisterProvider(M, handlers)
    local function Reset(key)
        if handlers.combat() or not handlers.canReset(key) or not handlers.prepare(key) then return false end
        local ok = handlers.run(key) == true
        if ok then handlers.finish(key) end
        return ok
    end
    M.RegisterPageResetProvider(PROVIDER_ID, {
        pages = handlers.pages,
        canReset = handlers.canReset,
        warning = handlers.warning,
        reset = Reset,
    })
end

local function WrapLegacy(M, handlers)
    if M._msufSuitePageResetsInstalled then return end
    M._msufSuitePageResetsInstalled = true
    local pages = handlers.pages
    local oldHas, oldWarning = M.PageHasReset, M.BuildPageResetWarning
    local oldReset, oldConfirm = M.ResetPageToDefaults, M.ShowPageResetConfirm
    function M.PageHasReset(key)
        if pages[key] then return handlers.canReset(key) end
        return (oldHas and oldHas(key)) or false
    end
    function M.BuildPageResetWarning(key)
        if not pages[key] then return oldWarning and oldWarning(key) end
        return handlers.warning(key)
    end
    function M.ResetPageToDefaults(key)
        if not pages[key] then return oldReset and oldReset(key) or false end
        if not handlers.canReset(key) or handlers.combat() or not handlers.prepare(key) then return false end
        local ok = handlers.withHistory(handlers.label(key), "page:reset:" .. tostring(key), function()
            return handlers.run(key) == true
        end)
        if ok then handlers.finish(key) end
        return ok
    end
    function M.ShowPageResetConfirm(key)
        if not pages[key] then return oldConfirm and oldConfirm(key) or false end
        if not handlers.canReset(key) or handlers.combat() then return false end
        handlers.confirm("page-reset", M.BuildPageResetWarning(key), function() M.ResetPageToDefaults(key) end)
        return true
    end
end

-- Returns "provider" or "legacy".
function HostBridge.RegisterPageResets(M, handlers)
    local mode
    if type(M.HOST_API_VERSION) == "number" and M.HOST_API_VERSION >= HOST_API_VERSION
        and type(M.RegisterPageResetProvider) == "function" then
        RegisterProvider(M, handlers)
        mode = "provider"
    else
        WrapLegacy(M, handlers)
        mode = "legacy"
    end
    if M.RefreshToolbarPageReset then M.RefreshToolbarPageReset() end
    return mode
end

return HostBridge
