local _, private = ...
-- Choice values of the Nameplates settings (MSUF_Suite/Core/Catalog/
-- Nameplates.lua). The Blizzard rules list "Automatic" first,
-- then Show (or On, Customize, Custom) and Hide (or Off).
private.Mode = {
    KEEP = 1, SHOW = 2, CUSTOMIZE = 2, HIDE = 3,
    -- look: Jundies, Blizzard, Custom, Mapko.
    LOOK_BLIZZARD = 2,
    -- barGeometry: Client default, Same on Retail and Forever.
    SAME_GEOMETRY = 2,
    -- levelAppearance (Forever only): Level number, Blizzard badge.
    LEVEL_BADGE = 2,
    -- friendlyNamesOnly: Keep, Names only (all friendly players), Names only
    -- (party / raid), Health bars.
    ALL_NAMES_ONLY = 2, GROUP_NAMES_ONLY = 3,
    -- friendlyNPCs: Keep, Show, Hide, Names only (world names).
    NPC_NAMES_ONLY = 4,
}

-- Setting keys that are a prefix or a color role plus a suffix. A key is built
-- once; a paint then reads Key[prefix].BackdropColor ("enemyBackdropColor"),
-- two table reads instead of a concatenation of two strings per read.
local function Memo(make)
    return setmetatable({}, { __index = function(made, name)
        local value = make(name)
        made[name] = value
        return value
    end })
end
private.Key = Memo(function(prefix)
    return Memo(function(suffix) return prefix .. suffix end)
end)
-- The enemy color roles' keys ("enemyTankEnabled", "enemyTankColor").
private.RoleKey = Memo(function(role)
    return { enabled = "enemy" .. role .. "Enabled", color = "enemy" .. role .. "Color" }
end)

-- The settings side of a plate's unit frame: "friendly", "enemy", or nil
-- while Blizzard's isFriend is restricted or unset.
function private.PlatePrefix(uf)
    local value = uf.isFriend
    if not private.Suite.Public(value) or type(value) ~= "boolean" then return nil end
    return value and "friendly" or "enemy"
end

-- Per-type enable switches share the regular paint path when all are on.
local NS, S = private.NS, private.Suite
local X = NS.NameplateExtensions
local scopes = { suppressed = setmetatable({}, { __mode = "k" }) }
private.SkinScopes = scopes
local module, restorePlate, active
local suppressed = scopes.suppressed
local hidden = setmetatable({}, { __mode = "k" })

local function Safe(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

function scopes.Allowed(uf, unit)
    if not active or not Safe(uf) then return true end
    if not unit then
        unit = uf.unit
        if not S.Public(unit) or type(unit) ~= "string" then unit = nil end
    end
    local scope = X.OpacityScope(X.PlateKind(uf, unit))
    return not scope or X.SkinEnabled(module.config, scope)
end
private.SkinAllowed = scopes.Allowed

local function HideHostile(uf, state)
    local L = private.ExtensionLayout
    if uf.CanBeAccessedInContext then
        local accessible = uf:CanBeAccessedInContext()
        if not S.Public(accessible) or not accessible then
            module.pendingPlates[uf] = true
            return
        end
    end
    if L.HitTest(state, true) then L.Alpha(state, 0) end
end

function scopes.OnHitTest(uf)
    local state = hidden[uf]
    if not state then return false end
    private.ExtensionLayout.NativeHitTest(state)
    if active and suppressed[uf] then
        HideHostile(uf, state)
    else
        scopes.RestoreVisibility(uf)
    end
    return true
end

function scopes.RestoreVisibility(uf)
    local state = hidden[uf]
    if not state then return end
    local L = private.ExtensionLayout
    if Safe(uf) then
        if not L.HitTest(state, false) then return end
        L.Alpha(state, 1)
    end
    hidden[uf] = nil
end

local function Suppress(uf)
    if suppressed[uf] and not module.pendingPlates[uf] then return end
    suppressed[uf] = true
    restorePlate(uf, true)
    private.Auras.RestorePlate(uf)
    -- Blizzard has one native visibility switch for hostile and neutral
    -- plates. Keep it on when either scope is enabled; hide only the other.
    if private.PlatePrefix(uf) == "enemy" then
        local state = hidden[uf]
        if not state then
            local unit = uf.unit
            if not S.Public(unit) or type(unit) ~= "string" then return end
            state = { uf = uf, owner = module, plate = C_NamePlate.GetNamePlateForUnit(unit) }
            hidden[uf] = state
        end
        HideHostile(uf, state)
    else
        scopes.RestoreVisibility(uf)
    end
end

function scopes.Bind(owner, restore)
    module, restorePlate = owner, restore
    return Suppress
end

function scopes.Wrap(paint)
    return function(uf)
        if not Safe(uf) then return end
        if not scopes.Allowed(uf) then return Suppress(uf) end
        scopes.RestoreVisibility(uf)
        if suppressed[uf] then
            suppressed[uf] = nil
            private.Auras.Apply(uf)
        end
        return paint(uf)
    end
end

local function IsSuppressed(uf) return suppressed[uf] == true end
local function ApplyAuras(uf)
    if not suppressed[uf] then private.Auras.Apply(uf) end
end

function scopes.Configure()
    local wasActive = active
    local c = module.config
    active = c.enemySkinEnabled == false or c.neutralSkinEnabled == false
        or c.friendlySkinEnabled == false or c.friendlyNpcSkinEnabled == false
    private.IsSkinSuppressed = active and IsSuppressed or nil
    if wasActive and not active then
        for uf in pairs(suppressed) do
            suppressed[uf] = nil
            scopes.RestoreVisibility(uf)
        end
    end
    return active, active and ApplyAuras or private.Auras.Apply
end

function scopes.Disable()
    active, private.IsSkinSuppressed = false, nil
end
