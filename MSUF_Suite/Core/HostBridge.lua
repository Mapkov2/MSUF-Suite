local _, Suite = ...

-- The one place where the Suite reaches into MSUF for settings MSUF owns:
-- the UI scale, the class resource stack and Menu2's page resets, plus
-- MSUF's interrupt-ready engine for the nameplates. MSUF hosts
-- with host API v1 (MSUF_HostAPI and Menu2's RegisterPageResetProvider, the
-- "MSUF host API v1 for the Suite") own these writes; older hosts get the
-- Suite's previous code, kept here unchanged. Capabilities are resolved
-- once, at the first use (MSUF's core loads before the Suite, its options
-- before the Suite's), and cached.
local HostBridge = {}
Suite.HostBridge = HostBridge

local HOST_API_VERSION = 1
local coreResolved, coreAPI = false, nil

-- Catalog and factory preview share the live host namespace; do not cache
-- a missing or late-published older host export.
local function HostNamespace()
    return _G.MSUF_NS
end

-- The table MSUF publishes as MSUF_HostAPI (any version), else nil.
local function HostTable()
    local api = _G.MSUF_HostAPI
    if type(api) == "table" then return api end
    return nil
end

-- MSUF_HostAPI when it is v1 or newer, else nil.
local function CoreAPI()
    if not coreResolved then
        coreResolved = true
        local api = HostTable()
        if api and type(api.version) == "number" and api.version >= HOST_API_VERSION
            and type(api.ApplyUIScaleProfile) == "function" and type(api.SetResourceStack) == "function" then
            coreAPI = api
        end
    end
    return coreAPI
end

function HostBridge.HasCoreAPI()
    return CoreAPI() ~= nil
end

-- Read-only profile assignments. A character without a spec binding still
-- appears, but its unknown class/spec is never guessed from the current player.
function HostBridge.ProfileCharacters(profile)
    local db, rows = _G.MSUF_GlobalDB, {}
    local chars = type(db) == "table" and db.char
    if type(chars) ~= "table" then return rows end
    for name, entry in pairs(chars) do
        if type(name) == "string" and #name <= 160 and type(entry) == "table" then
            local any = false
            if type(entry.specProfileMap) == "table" then
                for spec, assigned in pairs(entry.specProfileMap) do
                    if assigned == profile and type(spec) == "number" and spec > 0 and spec < 100000 then
                        rows[#rows + 1] = { name = name, spec = spec }
                        any = true
                    end
                end
            end
            if not any and entry.activeProfile == profile then rows[#rows + 1] = { name = name } end
        end
    end
    table.sort(rows, function(a, b)
        if a.name == b.name then return (a.spec or 0) < (b.spec or 0) end
        return a.name < b.name
    end)
    return rows
end

------------------------------------------------------------------ interrupt readiness
-- MSUF's interrupt-ready engine for the nameplate castbars: MSUF.KickReady
-- (Classic MSUF's Castbars/MSUF_InterruptReady.lua), which hosts from
-- 2026-10-07 hand out through MSUF_HostAPI.GetKickReady() without a version
-- change. nil on older hosts and on Main MSUF: the nameplates then show no
-- readiness. Resolved at the first use, like the core API.
local KICK_READY_VERSION = 1
local kickResolved, kickReady = false, nil

function HostBridge.KickReady()
    if not kickResolved then
        kickResolved = true
        local api = HostTable()
        local get = api and api.GetKickReady
        local engine = get and get() or nil
        if type(engine) == "table" and type(engine.version) == "number" and engine.version >= KICK_READY_VERSION then
            kickReady = engine
        end
    end
    return kickReady
end

------------------------------------------------------------------ icon skins
-- MSUF's icon skins for the cooldown manager and action bars: the interface
-- MSUF 7.0 hands out through MSUF_HostAPI.GetIconSkins() (its own version 1,
-- Auras3/MSUF_Auras3_IconSkins_Host.lua; HOST_API_SPEC.md, icon skin addendum
-- of 2026-10-17). nil on older hosts: every icon keeps the Suite's own border,
-- as before. Resolved at the first use, like the core API.
-- A choice is "DEFAULT" (the Icon Skins page's default skin), "CUSTOM" (no
-- skin) or a skin id. Looks are compiled once per choice and kept until MSUF
-- reports that its default changed; MSUF reports that only out of combat (a
-- default edited in combat waits for the combat end there, as for its auras),
-- and the Suite's own choices change only out of combat, so every icon made
-- in a fight, also after a reload in combat, gets the look the others show.
local ICON_SKINS_VERSION = 1
local SQUARE = "RECTANGLE"
local skinsResolved, iconSkins = false, nil
local skinLooks = { [SQUARE] = {} } -- icon shape -> choice -> look, or false for no skin
local strengthLooks = setmetatable({}, { __mode = "k" }) -- compiled look -> strength variants
local skinWatchers = {}   -- module id -> true while it draws skins
local skinHooks = {}      -- key -> fn, run before the watchers refresh
local refreshed = {}      -- module id -> true when a hook refreshed it already

local function IconSkinsChanged(reason)
    for _, looks in pairs(skinLooks) do
        for choice in pairs(looks) do looks[choice] = nil end
    end
    -- Settings that wait for MSUF's new default (Register.lua: shapes the
    -- Icon Skins page set for it) are written first, so each module
    -- refreshes once, with the new look and its shape; a hook names the
    -- modules its writes refreshed in `refreshed`.
    for look in pairs(strengthLooks) do strengthLooks[look] = nil end
    for id in pairs(refreshed) do refreshed[id] = nil end
    for _, fn in pairs(skinHooks) do fn(refreshed, reason) end
    -- Suite.Suite: the module controller (Core/Suite.lua); out of combat here.
    for id in pairs(skinWatchers) do
        if not refreshed[id] then Suite.Suite.Apply(id) end
    end
end

function HostBridge.IconSkins()
    if not skinsResolved then
        skinsResolved = true
        local api = HostTable()
        local get = api and api.GetIconSkins
        local skins = get and get() or nil
        if type(skins) == "table" and type(skins.version) == "number" and skins.version >= ICON_SKINS_VERSION then
            iconSkins = skins
            skins.Subscribe("MSUF_Suite", IconSkinsChanged)
        end
    end
    return iconSkins
end

-- The look of a choice for icons of `shape` (square when nil; "CIRCLE" for
-- round action buttons), or nil when no skin draws: an older host, CUSTOM,
-- an unknown id or a skin made for another shape. Equal looks are the same
-- table until MSUF reports a change.
local function StrengthLook(skins, look, strength)
    if not look or not skins.WithGlossStrength then return nil end
    local variants = strengthLooks[look]
    if not variants then variants = {} strengthLooks[look] = variants end
    local adjusted = variants[strength]
    if adjusted == nil then
        adjusted = skins.WithGlossStrength(look, strength) or false
        variants[strength] = adjusted
    end
    return adjusted or nil
end

-- Optional current-host artwork; older hosts keep their existing appearance.
function HostBridge.GlossTexture()
    local skins = HostBridge.IconSkins()
    return skins and skins.GlossTexture and skins.GlossTexture() or nil
end

function HostBridge.IconSkinLook(choice, shape, strength)
    local skins = HostBridge.IconSkins()
    if not skins then return nil end
    if choice == nil then choice = skins.DEFAULT end
    shape = shape or SQUARE
    local looks = skinLooks[shape]
    if not looks then
        looks = {}
        skinLooks[shape] = looks
    end
    local look = looks[choice]
    if look == nil then
        look = skins.Compile(choice, shape) or false
        looks[choice] = look
    end
    if strength ~= nil then return StrengthLook(skins, look, strength) end
    return look or nil
end

-- Draws `look` on `owner` around `anchor` (see the interface); a nil look
-- hides an earlier one. clip: only the parts over the anchor draw (a look
-- over an icon that already shows it there). Returns whether a skin draws
-- the icon's look.
function HostBridge.PaintIconSkin(owner, look, width, height, anchor, clip)
    local skins = HostBridge.IconSkins()
    if not skins then return false end
    return skins.Paint(owner, look, width, height, anchor, clip) == true
end

-- How far a look's frame reaches past an icon of that size on each side
-- (x, y); 0, 0 for no look or a host without it.
function HostBridge.IconSkinOutset(look, width, height)
    local skins = look and HostBridge.IconSkins()
    if not (skins and skins.Outset) then return 0, 0 end
    return skins.Outset(look, width, height)
end

-- The icon shape a picked skin is made for, as MSUF's Icon Skins page
-- matches it, and the skin id it resolved (DEFAULT: the default skin); nil
-- for no skin, or on a host without icon skins.
function HostBridge.IconSkinShape(choice)
    local skins = HostBridge.IconSkins()
    if not (skins and skins.ShapeOf) then return nil end
    return skins.ShapeOf(choice)
end

-- MSUF's icon shapes (the same interface): `shape` is MSUF's id
-- (NS.IconShapeIds). Masks the textures in `...` and the regions of each
-- cooldown in `cooldowns` over `anchor`, and gives the cooldowns the shape's
-- swipe; returns the shape drawn ("RECTANGLE" on a host without shapes).
function HostBridge.ApplyIconShape(owner, shape, anchor, cooldowns, ...)
    local skins = HostBridge.IconSkins()
    if not (skins and skins.ApplyShape) then return SQUARE end
    return skins.ApplyShape(owner, shape, anchor, cooldowns, ...)
end

-- Ring and silhouette textures of a shape for the Suite's own shaped art,
-- and whether the ring only works behind the icon; nil without shapes.
function HostBridge.IconShapeArt(shape)
    local skins = HostBridge.IconSkins()
    if not (skins and skins.ShapeArt) then return nil end
    return skins.ShapeArt(shape)
end

-- A module that draws skins refreshes when MSUF's default skin changed.
function HostBridge.WatchIconSkins(id, on)
    skinWatchers[id] = on == true or nil
end

-- fn(refreshed, reason) runs when MSUF reports a new default skin (reason:
-- "apply", "combat" or "profile"), before the modules refresh (out of
-- combat: MSUF reports only then); it sets refreshed[id] for each module
-- its own writes refreshed. One per key.
function HostBridge.OnIconSkinsChanged(key, fn)
    skinHooks[key] = fn
end

------------------------------------------------------------------ target DoT suggestions
-- Read the host's curated aura IDs without sharing its mutable data or
-- changing the unit-frame DoT selection. Older hosts can omit this catalog.
function HostBridge.TargetDotCatalog(class)
    local host = HostNamespace()
    local auras = type(host) == "table" and host.MSUF_Auras3
    local data = type(auras) == "table" and auras.TargetDotData
    local source = type(data) == "table" and data[class]
    local out = {}
    if type(source) ~= "table" then return out end
    for i = 1, math.min(#source, 64) do
        local row = source[i]
        local id = type(row) == "table" and row[1]
        if Suite.Public(id) and type(id) == "number" and id > 0 and id < 2147483648 and id == math.floor(id) then
            out[#out + 1] = { id = id, curated = true }
        end
    end
    return out
end

------------------------------------------------------------------ UI scale
-- The legacy path: MSUF's own scale settings and appliers, written in the
-- order MSUF applies them.
local function LegacyScaleReady(spec)
    local db = HostBridge.CurrentFramePreview()
    if not db or type(db.general) ~= "table" then
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

-- MSUF's scale settings before a legacy apply. Should one of MSUF's
-- appliers raise partway, the settings go back together with the scale they
-- describe, so a refused install leaves MSUF as it was (the Modern install
-- keeps MSUF's own profile, nothing deletes these writes there). These are
-- the fields host API v1 saves for the same rollback (HOST_API_SPEC F): the
-- Suite's own writes plus disableScaling, which MSUF's scale owner writes
-- itself, and the UIScale table, which keeps its identity (MSUF may hold
-- it) and gets its saved contents back.
local SCALE_KEYS = { "msufUiScale", "uiScale", "globalUiScalePreset", "globalUiScaleValue", "disableScaling" }

local function SaveScale(general)
    local saved = { fields = {}, uiScale = general.UIScale }
    for index = 1, #SCALE_KEYS do saved.fields[SCALE_KEYS[index]] = general[SCALE_KEYS[index]] end
    if type(saved.uiScale) == "table" then
        local contents = {}
        for key, value in pairs(saved.uiScale) do contents[key] = value end
        saved.contents = contents
    end
    return saved
end

local function PutScaleBack(general, saved)
    for index = 1, #SCALE_KEYS do general[SCALE_KEYS[index]] = saved.fields[SCALE_KEYS[index]] end
    local ui = saved.uiScale
    general.UIScale = ui
    if type(ui) ~= "table" then return end
    local contents = saved.contents
    for key in pairs(ui) do
        if contents[key] == nil then ui[key] = nil end
    end
    for key, value in pairs(contents) do ui[key] = value end
end

local function ReapplyFrameScale(saved)
    _G.MSUF_ApplyMsufScale(tonumber(saved.fields.msufUiScale) or tonumber(saved.fields.uiScale) or 1)
end

local function ReapplyGlobalScale(saved)
    local ui = saved.contents
    if type(_G.MSUF_ApplyCurrentProfileGlobalUiScale) == "function" then
        _G.MSUF_ApplyCurrentProfileGlobalUiScale()
    elseif ui and ui.Enabled == true and Suite.Finite(ui.Scale) and type(_G.MSUF_SetGlobalUiScale) == "function" then
        _G.MSUF_SetGlobalUiScale(ui.Scale, true)
    else
        _G.MSUF_ResetGlobalUiScale(true)
    end
end

-- The saved settings, the scale they describe through MSUF's appliers (its
-- profile re-applier where MSUF has it), then the settings once more, as an
-- applier writes them itself. Each step runs on its own: one that raises is
-- reported and the next still runs, so the settings always end as saved.
local function RestoreLegacyScale(general, saved)
    Suite.Dispatch(PutScaleBack, general, saved)
    Suite.Dispatch(ReapplyFrameScale, saved)
    Suite.Dispatch(ReapplyGlobalScale, saved)
    Suite.Dispatch(PutScaleBack, general, saved)
end

local function LegacyApplyAtomic(spec)
    local general = _G.MSUF_DB.general
    local saved = SaveScale(general)
    if Suite.Dispatch(Suite.Finish, LegacyApplyScale, spec) then return true end
    RestoreLegacyScale(general, saved)
    return false
end

-- The scale ranges MSUF accepts, both bounds inclusive: host API v1
-- ApplyUIScaleProfile refuses anything outside them as "invalid" (the clamps
-- of MSUF's ApplyMsufScale and SetGlobalUiScale). Checked here for both
-- paths, so a refusal comes before the installer commits anything.
local MSUF_SCALE_MIN, MSUF_SCALE_MAX = 0.25, 2.0
local GLOBAL_SCALE_MIN, GLOBAL_SCALE_MAX = 0.3, 1.5

local function InRange(value, minimum, maximum)
    return Suite.Finite(value) and value >= minimum and value <= maximum
end

-- A spec both paths can apply: scales MSUF accepts, a known preset.
local function ValidSpec(spec)
    if type(spec) ~= "table" then return false end
    local msufScale = spec.msufScale
    if msufScale ~= nil and not InRange(msufScale, MSUF_SCALE_MIN, MSUF_SCALE_MAX) then return false end
    local global = spec.global
    if global == nil then return true end
    return type(global) == "table" and (global.preset == "pixel" or global.preset == "custom")
        and InRange(global.scale, GLOBAL_SCALE_MIN, GLOBAL_SCALE_MAX)
end

-- The v1 host's refusals in the installer's words (host API v1: "combat",
-- "unavailable", "invalid"; a refusal writes nothing).
local HOST_REFUSALS = {
    combat = "Finish combat first.",
    unavailable = "MSUF scale controls unavailable",
    invalid = "MSUF refused this UI scale",
}

-- Whether a scale profile can be applied now (spec as for ApplyScale), the
-- same answer on both paths, so a caller can check before it commits
-- anything. The v1 setter answers only by applying, and it refuses as
-- "unavailable" exactly when MSUF's scale settings or appliers are missing,
-- which is the legacy check, and "invalid" outside MSUF's ranges (above).
function HostBridge.ScaleReady(spec)
    if not ValidSpec(spec) then return false, HOST_REFUSALS.invalid end
    return LegacyScaleReady(spec)
end

-- spec = { msufScale = number (default 1), global = nil | { preset = "pixel"|"custom", scale = number } }
-- Returns ok, reason (the installer's English status text). The legacy
-- path puts MSUF's settings back when an applier raises; with v1 the host's
-- setter owns its writes and their rollback.
function HostBridge.ApplyScale(spec)
    -- Combat refuses from PLAYER_REGEN_DISABLED on, before InCombatLockdown()
    -- turns true: the v1 host's own answer, kept for the legacy path too.
    if Suite.InCombat() then return false, HOST_REFUSALS.combat end
    local ready, why = HostBridge.ScaleReady(spec)
    if not ready then return false, why end
    local api = CoreAPI()
    if not api then
        if LegacyApplyAtomic(spec) then return true end
        return false, HOST_REFUSALS.invalid
    end
    local ok, reason = api.ApplyUIScaleProfile(spec)
    if ok then return true end
    return false, HOST_REFUSALS[reason] or HOST_REFUSALS.invalid
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
-- Returns whether MSUF's appliers ran: on v1 the host's applied (it writes
-- an incomplete stack, and with force == true also re-applies a complete
-- one); the legacy path always writes and applies, as before. Unknown modes
-- change nothing.
function HostBridge.SetResourceStack(mode, force)
    if mode ~= "cooldown" then return false end
    local api = CoreAPI()
    if api then
        local _, applied = api.SetResourceStack(mode, force)
        return applied == true
    end
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
-- A v1 Menu2 owns the confirmation, the combat refusal, the canReset check
-- and the history entry, and runs the provider's steps in the spec's order:
-- prepare before its undo snapshot (so Undo also restores state prepare
-- loaded, the dormant Skinning engine), reset inside the one history entry
-- named by historyLabel (already translated), finish after the entry is
-- committed. Older menus get the four wrapped functions as before.
local PROVIDER_ID = "msuf-suite"

local function RegisterProvider(M, handlers)
    local run = handlers.run
    M.RegisterPageResetProvider(PROVIDER_ID, {
        pages = handlers.pages,
        canReset = handlers.canReset,
        warning = handlers.warning,
        prepare = handlers.prepare,
        reset = function(key) return run(key) == true end,
        finish = handlers.finish,
        historyLabel = handlers.label,
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
        -- An open menu history session retakes its snapshot, so its Undo
        -- also restores what prepare loaded (the dormant Skinning engine);
        -- a host with that history has the function (HOST_API_SPEC E).
        if M.SyncExternalHistoryState then M.SyncExternalHistoryState() end
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


-- Read the same factory the installer applies, using the host's public codec.
-- Cache successful decodes only: a late-loaded older host may publish it later.
local framePreviews = {}
function HostBridge.CurrentFramePreview()
    local frames = _G.MSUF_DB
    return type(frames) == "table" and frames or nil
end

function HostBridge.ModernDarkFrameCompact()
    local host = HostNamespace()
    return host and host.MSUF_MODERN_DARK_PROFILE_COMPACT or Suite.ModernDarkFramesCompact
end

local function FrameEnvelope(compact)
    local decode = _G.MSUF_TryDecodeCompactString
    if type(decode) ~= "function" then return nil end
    local envelope = Suite.Dispatch(decode, compact)
    local host = HostNamespace()
    local policy = host and host.ProfilePolicy
    if policy and type(policy.SelectSupportedDecodedProfile) == "function" then
        return Suite.Dispatch(policy.SelectSupportedDecodedProfile, envelope)
    end
    -- Older hosts also prefer the full snapshot carried by Wago exports.
    local full = type(envelope) == "table" and envelope.msuf6
    if type(full) == "table" and type(full.payload) == "table" then
        return { addon = envelope.addon, fmt = envelope.fmt, schema = full.schema,
            kind = full.kind or envelope.kind, profile = full.profile or envelope.profile, payload = full.payload }
    end
    return envelope
end

function HostBridge.StyleFrameFactory(compact, modes)
    if not modes then return compact end
    local envelope = FrameEnvelope(compact)
    local encode = _G.MSUF_EncodeCompactTable
    if type(envelope) ~= "table" or envelope.kind ~= "all" or type(encode) ~= "function" then return nil end
    local frames = Suite.InstallerFrameColors.Apply(envelope.payload, modes)
    if not frames then return nil end
    local copy = Suite.CopyValue(envelope)
    copy.payload = frames
    local encoded = Suite.Dispatch(encode, copy, "MSUF3")
    return type(encoded) == "string" and encoded:match("^MSUF3:") and encoded or nil
end

function HostBridge.FactoryFramePreview(layout)
    local host = HostNamespace()
    local compact
    if layout == "modernDark" then
        compact = HostBridge.ModernDarkFrameCompact()
    elseif layout == "forever" then
        compact = Suite.Client.isForever and host and host.MSUF_FOREVER_FACTORY_DEFAULT_PROFILE_COMPACT
            or Suite.ForeverFactoryFramesCompact
    else
        compact = not Suite.Client.isForever and host and host.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT
            or Suite.ClassicFactoryFramesCompact
    end
    if type(compact) ~= "string" then return nil end
    if framePreviews[compact] then return framePreviews[compact] end
    local envelope = FrameEnvelope(compact)
    local frames = type(envelope) == "table" and envelope.payload
    if type(frames) ~= "table" then return nil end
    framePreviews[compact] = frames
    return frames
end

-- MSUF's own Blizzard adapter can register the same Blizzard surface a suite
-- module now owns (Minimap, Blizzard's damage meter). While a suite owner
-- claims its key, that record reports disabled. Records are looked up at call
-- time by MSUF, so wrapping isEnabled needs no MSUF change; re-created records
-- are wrapped again at the next session start.
local suppressed, wrapped, EMPTY = {}, setmetatable({}, { __mode = "k" }), {}
function HostBridge.RefreshSuppressedEditElements()
    local em = _G.MSUF_EM2
    local external = em and em.ExternalElements
    if type(external) ~= "table" or type(external.GetRecord) ~= "function" then return end
    for key in pairs(suppressed) do
        local record = external.GetRecord(key)
        if type(record) == "table" and not wrapped[record] then
            local original = record.isEnabled
            wrapped[record] = true
            record.isEnabled = function(...)
                if next(suppressed[key] or EMPTY) then return false end
                if type(original) == "function" then return original(...) end
                return true
            end
        end
    end
end

function HostBridge.SuppressEditElement(owner, key, claim)
    suppressed[key] = suppressed[key] or {}
    suppressed[key][owner] = claim and true or nil
    if claim then HostBridge.RefreshSuppressedEditElements() end
end

-- Profile references are read-only outside the host's variant adapter. Host
-- profile operations remain the host's own entry points on every generation.
local function FrameProfiles()
    local root = _G.MSUF_GlobalDB
    return type(root) == "table" and type(root.profiles) == "table" and root.profiles or nil
end

function HostBridge.FrameProfile(name)
    local profiles = FrameProfiles()
    return profiles and profiles[name]
end

function HostBridge.HasFrameProfiles()
    return FrameProfiles() ~= nil
end

function HostBridge.FrameProfileNames()
    local names = {}
    for name in pairs(FrameProfiles() or {}) do names[#names + 1] = name end
    return names
end

function HostBridge.CurrentFrameProfile()
    return _G.MSUF_DB
end

function HostBridge.ImportFrameProfile(name, frames)
    local native = _G.MSUF_Profiles_ImportIntoNewProfile
    if type(native) == "function" then return native(name, frames) end
    local profiles = FrameProfiles()
    local ok, why = _G.MSUF_Profiles_ImportExternal(frames, name)
    if ok ~= true or type(profiles[name]) ~= "table" then
        if profiles[name] ~= nil then _G.MSUF_DeleteProfile(name) end
        return false, why or "Frame profile import failed"
    end
    if _G.MSUF_SwitchProfile(name) == true and _G.MSUF_ActiveProfile == name then return true end
    if _G.MSUF_ActiveProfile ~= name then _G.MSUF_DeleteProfile(name) end
    return false, "Frame profile could not be activated"
end

function HostBridge.ProfileVariantServices()
    local host = HostNamespace()
    return host.ProfileFields, host.ProfileVariants, host.ProfileSync, host.ProfileRuntime
end

function HostBridge.GroupFrames()
    return HostNamespace().GF
end

function HostBridge.FirstRunPending()
    local firstLoad = HostNamespace().FirstLoad6
    return type(firstLoad) == "table" and type(firstLoad.IsFirstRunPending) == "function"
        and firstLoad:IsFirstRunPending() == true
end

function HostBridge.FactoryFrameCompact(forever)
    local host = HostNamespace()
    if forever then
        return Suite.Client.isForever and host.MSUF_FOREVER_FACTORY_DEFAULT_PROFILE_COMPACT
            or Suite.ForeverFactoryFramesCompact
    end
    return not Suite.Client.isForever and host.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT
        or Suite.ClassicFactoryFramesCompact
end

function HostBridge.ResourceStackNeedsRepair(profile, force)
    local db = _G.MSUF_DB
    if type(db) ~= "table" or type(db.bars) ~= "table" or type(db.player) ~= "table" then return nil end
    local bars, player = db.bars, db.player
    return force or (bars.classPowerAnchorToCooldown ~= true
        and (player.powerBarDetached == true and player.detachedPowerBarAnchorToClassPower == true
            or profile == "forever" and bars.classPowerOffsetY == -41))
end

function HostBridge.CooldownAnchor()
    local db = _G.MSUF_DB
    local general = type(db) == "table" and db.general or nil
    local wants = type(general) == "table" and general.anchorToCooldown == true
    return wants, wants and type(_G.MSUF_GetSuiteCooldownAnchor) == "function"
end

-- Late-resolved legacy profile operations. These hosts publish no versioned
-- profile-operation API yet; keep their exact entry points behind this finite
-- adapter, including capability checks and late provider replacement.
local PROFILE_METHODS = {
    DeleteProfile = "MSUF_DeleteProfile",
    GetDefaultProfileForNewCharacters = "MSUF_GetDefaultProfileForNewCharacters",
    GetPixelPerfectScale = "MSUF_GetPixelPerfectScale",
    Profiles_ExportSelectionToString = "MSUF_Profiles_ExportSelectionToString",
    Profiles_ImportExternal = "MSUF_Profiles_ImportExternal",
    Profiles_ImportIntoNewProfile = "MSUF_Profiles_ImportIntoNewProfile",
    SetCurrentProfileScreenReferenceHeight = "MSUF_SetCurrentProfileScreenReferenceHeight",
    SetDefaultProfileForNewCharacters = "MSUF_SetDefaultProfileForNewCharacters",
    SwitchProfile = "MSUF_SwitchProfile",
}
HostBridge.Profiles = setmetatable({}, { __index = function(_, operation)
    local name = PROFILE_METHODS[operation]
    return name and _G[name] or nil
end })

function HostBridge.ActiveFrameProfileName()
    return _G.MSUF_ActiveProfile
end

function HostBridge.ProfileWasUnboundAtLogin()
    return _G.MSUF_ProfileWasUnboundAtLogin == true
end

function HostBridge.BossTargetIndicator()
    return _G.MSUF_NS.BossTargetIndicator
end

return HostBridge
