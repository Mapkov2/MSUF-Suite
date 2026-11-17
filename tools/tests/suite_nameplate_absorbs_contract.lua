local root = assert(arg[1])
local secret = {}
local combat, calls = false, 0
local function Public(value) return value ~= secret end
local profile = { general = {
    barTexture = "SharedHealth", absorbBarTexture = "ShieldTexture", absorbBarColorR = .2,
    absorbBarColorG = .6, absorbBarOpacity = .55, healAbsorbBarOpacity = .8,
} }
local liveProfile = profile
local NS = {
    Public = Public,
    Finite = function(value) return Public(value) and type(value) == "number" end,
    InCombat = function() calls = calls + 1 return combat end,
    ResolveTexture = function(key, fallback) return key and "lsm:" .. key or fallback end,
    HostBridge = { CurrentFrameProfile = function() return profile end },
}
local private = { NS = NS }
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeBars.lua"))("Suite", NS)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Absorbs.lua"))("Nameplates", private)
local absorbs = assert(private.Absorbs)

local function Region(path, tiled)
    local region = { color = { .95, .8, .65, .9 }, path = path, tiled = tiled, frameAlpha = .4 }
    function region:GetVertexColor() calls = calls + 1 return unpack(self.color) end
    function region:SetVertexColor(...) calls = calls + 1 self.color = { ... } end
    function region:GetAtlas() calls = calls + 1 return self.atlas end
    function region:GetTexture() calls = calls + 1 return self.path end
    function region:GetHorizTile() calls = calls + 1 return self.tiled end
    function region:GetVertTile() calls = calls + 1 return self.tiled end
    function region:SetTexture(asset, horizontal, vertical)
        calls = calls + 1
        assert(horizontal == vertical)
        self.path, self.tiled, self.atlas = asset, horizontal, nil
    end
    function region:SetAtlas(atlas, size)
        calls = calls + 1
        assert(size == false)
        self.atlas, self.path = atlas, nil
    end
    return region
end

local function Writable(region)
    calls = calls + 1
    return Public(region) and region and not region.locked
end
local health = {
    totalAbsorb = Region("shield", false), totalAbsorbOverlay = Region("shield-overlay", true),
    overAbsorbGlow = Region("shield-glow", false), myHealAbsorb = Region("heal-absorb", true),
    myHealAbsorbLeftShadow = Region("left", false), myHealAbsorbRightShadow = Region("right", false),
    overHealAbsorbGlow = Region("heal-absorb-glow", false), myHealPrediction = Region("heal", false),
}
function health:IsProtected() return false end
local uf = { IsProtected = function(self) return self.protected or false end }
local function Apply(styled) return absorbs.Apply(uf, health, styled, Writable) end
local function Near(a, b) return math.abs(a - b) < .0001 end
local config = { look = 3, nameplateAbsorbMode = 1, nameplateHealAbsorbMode = 1 }
assert(not absorbs.Configure(config) and not absorbs.inUse and Apply(true) and calls == 0)
local pos, neg, glow = health.totalAbsorb, health.myHealAbsorb, health.overAbsorbGlow
local overlay, heals = health.totalAbsorbOverlay, health.myHealPrediction
local beforeHeal = heals.color
config.nameplateAbsorbMode, config.nameplateHealAbsorbMode = 2, 2
assert(absorbs.Configure(config) and absorbs.shared and Apply(true))
assert(pos.path == "lsm:ShieldTexture" and pos.color[1] == .2 and pos.color[2] == .6 and pos.color[4] == .55)
assert(neg.path == "lsm:SharedHealth" and not neg.tiled and neg.color[1] == .7 and neg.color[4] == .8)
assert(overlay.color[4] == 0 and Near(glow.color[4], .9 * .55), "retain the native full-health shield cue")
assert(pos.frameAlpha == .4 and neg.frameAlpha == .4 and heals.color == beforeHeal, "prediction fade and heals are independent")
for _ = 1, 20 do
    local before = calls
    pos.shown, pos.width = true, 19 -- Blizzard changes these independently of the appearance.
    assert(Apply(true) and calls == before and pos.shown and pos.width == 19)
end
assert(not absorbs.Configure(config))
profile.general.enableAbsorbBar = false
assert(absorbs.SharedChanged(config) and absorbs.Configure(config) and Apply(true))
assert(pos.color[4] == 0 and overlay.color[4] == 0 and glow.color[4] == 0)
assert(neg.color[4] == .8 and heals.color == beforeHeal)

config.nameplateAbsorbMode, config.nameplateHealAbsorbMode = 1, 3
assert(absorbs.Configure(config) and Apply(true))
assert(pos.path == "shield" and pos.color[4] == .9 and overlay.color[4] == .9 and glow.color[4] == .9)
assert(neg.path == "heal-absorb" and neg.tiled and neg.color[4] == 0)
assert(health.myHealAbsorbLeftShadow.color[4] == 0 and health.overHealAbsorbGlow.color[4] == 0)
combat, uf.protected = true, true
assert(not Apply(false) and neg.color[4] == 0, "restore must defer for a protected native plate")
combat, uf.protected = false, false
assert(Apply(false) and neg.color[4] == .9 and health.myHealAbsorbLeftShadow.color[4] == .9)

profile.general.enableAbsorbBar = true
config.nameplateAbsorbMode, config.nameplateHealAbsorbMode = 2, 1
assert(absorbs.Configure(config))
pos.locked = true
assert(not Apply(true) and overlay.color[4] ~= 0, "retain native shield art when its base is inaccessible")
pos.locked = false
assert(Apply(true) and overlay.color[4] == 0 and pos.path == "lsm:ShieldTexture")
config.look = 2
assert(absorbs.Configure(config) and not absorbs.inUse and Apply(true))
assert(pos.path == "shield" and overlay.color[4] == .9)
profile = nil
config.look = 3
assert(not absorbs.Configure(config) and not absorbs.inUse, "on a host with no shared settings use native art")

-- The existing texture lease handles absorb-only setups, shared Bars edits,
-- combat deferral and recycled plates without a new runtime listener.
profile = liveProfile
config.barsOverride = true
uf.HealthBarsContainer = { healthBar = health }
NS.NameplateStyle = { UsesNativeOutline = function() return false end }
NS.Safety = { IsForbidden = function() return false end }
NS.IsCombatLocked = function() return combat end
private.Layout = { Observe = function() end }
local host = { PublicGlobals = { MSUF_UpdateAllBarTextures_Immediate = function() end } }
host.Public = { Colors = { SetAbsorbOverlayColor = function(r) profile.general.absorbBarColorR = r end } }
NS.HostBridge.Namespace = function() return host end
NS.HostBridge.ObserveSharedCastbarStyle = nil
function hooksecurefunc(owner, key, callback)
    local original = assert(owner[key])
    owner[key] = function(...) original(...) callback(...) end
end
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Textures.lua"))("Nameplates", private)
local textures = private.Textures
local refreshed = 0
private.Suite = { Apply = function(id)
    assert(id == "nameplates")
    refreshed = refreshed + 1
    textures.Configure(config)
    textures.Apply(uf)
end }
textures.ObserveHostStyles({ active = true, config = config, context = { Coalesce = function(_, _, run)
    return { Request = function() run({ active = true, config = config }) end }
end } })
textures.Configure(config)
assert(textures.inUse)
textures.Apply(uf)
assert(pos.path == "lsm:ShieldTexture")
host.PublicGlobals.MSUF_UpdateAllBarTextures_Immediate()
assert(refreshed == 0, "an unchanged shared profile repainted plates")
profile.general.absorbBarOpacity = .3
host.PublicGlobals.MSUF_UpdateAllBarTextures_Immediate("player")
assert(refreshed == 0, "a nonshared Unit Frame change refreshed nameplates")
host.PublicGlobals.MSUF_UpdateAllBarTextures_Immediate()
assert(refreshed == 1 and pos.color[4] == .3, "the shared Absorb Display settings did not refresh the plate")
host.Public.Colors.SetAbsorbOverlayColor(.85)
assert(refreshed == 2 and pos.color[1] == .85, "the shared color picker did not refresh the plate")

local replay, registered
function CreateFrame()
    assert(not replay, "the texture owner created a second combat listener")
    return {
        SetScript = function(frame, event, callback)
            assert(event == "OnEvent")
            replay = function() callback(frame, "PLAYER_REGEN_ENABLED") end
        end,
        RegisterEvent = function(_, event) registered = event end,
        UnregisterEvent = function(_, event)
            assert(registered == event)
            registered = nil
        end,
    }
end
combat, uf.protected = true, true
textures.Restore(uf, true)
assert(registered == "PLAYER_REGEN_ENABLED" and pos.path == "lsm:ShieldTexture")
combat, uf.protected = false, false
replay()
assert(not registered and pos.path == "shield" and pos.color[4] == .9)
textures.Apply(uf)
assert(pos.path == "lsm:ShieldTexture" and pos.color[4] == .3)
textures.Restore(uf, true)
assert(pos.path == "shield" and pos.color[4] == .9)
print("Nameplate absorbs: native shield and heal-absorb art, shared style, no steady calls, independent opacity, combat restore and fallback passed")
