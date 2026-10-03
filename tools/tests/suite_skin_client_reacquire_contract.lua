-- A Suite module that stops gets its skin client back when it starts again in
-- the same session (S2-1). Suite.Skin.Release lets go of the module's targets
-- (client:ReleaseAll); the skin keeps the client's name registered, so a
-- fresh RegisterAddon of that name is refused ("already-registered") and the
-- Suite must reuse the client it already holds. Without that, the Objectives
-- tracker, Announcements and Run summary paint fallback colours after being
-- turned off and on, after Suite skinning off/on, or after a failed module
-- restarts, until /reload.
-- Loads the real MSUF_Suite_Skin/Core/Safety.lua, PublicAPI.lua,
-- PublicAPIMethods.lua and Finalize.lua, MSUF_Suite/Integrations/MapkoSkin.lua
-- and MSUF_Suite_Modules/Runtime.lua (Context:Skin and Context:Release).
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

securecallfunction = function(callback, ...) return callback(...) end
hooksecurefunc = function(target, method, post)
    local original = target[method]
    target[method] = function(...)
        local results = { original(...) }
        post(...)
        return unpack(results)
    end
end
local locked = false
InCombatLockdown = function() return locked end
UnitName = function() return "Player" end
GetRealmName = function() return "Realm" end

-- The real CombatGate.lua drains its jobs on PLAYER_REGEN_ENABLED.
local gateFrame
CreateFrame = function()
    local frame = { RegisterEvent = Noop, UnregisterEvent = Noop }
    function frame:SetScript(_, handler) self.handler = handler end
    gateFrame = gateFrame or frame
    return frame
end
local function EndCombat()
    locked = false
    gateFrame.handler(gateFrame, "PLAYER_REGEN_ENABLED")
end

-- The skin engine's namespace: the fields Bootstrap.lua and the rendering
-- modules provide that the public API reads.
local cosmeticOwners = setmetatable({}, { __mode = "k" })
local NS = {
    addonName = "MSUF_Suite_Skin", apiVersion = 1, publicAPIMajor = 2, publicAPIMinor = 1,
    IsCombatLocked = function() return locked end,
    ControlSkin = { DisableOwner = Noop, GetOwner = Noop },
    WindowActionSkin = { DisableOwner = Noop, GetOwner = Noop },
    IconSkin = { DisableOwner = Noop, GetOwner = Noop },
    Cosmetics = {
        GetOwner = function(target) return cosmeticOwners[target] end,
        Fade = function(target, owner)
            cosmeticOwners[target] = owner
            target.faded = true
            return true
        end,
        RestoreOwner = function(owner)
            for target, holder in pairs(cosmeticOwners) do
                if holder == owner then
                    cosmeticOwners[target] = nil
                    target.faded = false
                end
            end
        end,
    },
    Registry = { AddListener = Noop, NotifyListeners = Noop, QueueJob = Noop, GetSurface = Noop },
    Clamp = function(value, low, high)
        value = tonumber(value) or low
        if value < low then return low end
        if value > high then return high end
        return value
    end,
    Theme = { GetColor = function() return 0.1, 0.2, 0.3, 1 end },
    DB = { enabled = true, theme = { look = "midnightDark" } },
}

for _, file in ipairs({ "Safety", "CombatGate", "PublicAPI", "PublicAPIMethods", "Finalize" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/" .. file .. ".lua"))("MSUF_Suite_Skin", NS)
end
NS.EnsureDatabaseReady = Noop
MapkoSkin = NS
C_AddOns = { LoadAddOn = function() return true end }

-- The Suite core's fields the skin boundary and the module runtime read.
local Suite = {
    Client = { HasAddOn = function() return false end, AddOnEnabled = function() return true end },
    IsCombatLocked = function() return locked end,
    Suite = { started = false, states = {}, instances = {}, catalog = {} },
    RootDB = { skinMigrationDone = true },
    Dispatch = securecallfunction,
    Public = function() return true end,
}
MSUFSuite = Suite
assert(loadfile(root .. "/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite", Suite)
assert(loadfile(root .. "/MSUF_Suite_Modules/Runtime.lua"))("MSUF_Suite_Modules", {})
local Skin = Suite.Skin
NS.PublicAPI.OnPlayerLogin()
Check(Skin.SetEnabled(true), "Suite skinning turns on")
local api = NS.GetAPI(2, 0)

local function Region()
    return { SetAlpha = Noop, GetAlpha = function() return 1 end }
end

-- The three HUD modules that paint with skin colours: stop, start again.
for _, id in ipairs({ "objectives", "announcements", "runSummary" }) do
    local context = Suite.Suite.NewContext(id)
    local first = context:Skin()
    Check(first and first:GetColor("surface") == 0.1, id .. " gets a skin client")
    local region = Region()
    Check(first:Fade(region) and region.faded, id .. " skins a target")
    context:Release()
    Check(not region.faded, id .. " gives its target back when it stops")
    local _, reason = api:RegisterAddon("MSUF_Suite_" .. id)
    Check(reason == "already-registered", "the skin keeps the stopped module's name registered")
    local second = context:Skin()
    Check(second == first, id .. " gets its skin client back when it starts again")
    Check(second:GetColor("text") == 0.1 and second:GetLook() == "midnightDark",
        id .. " paints with the skin's colours after a restart")
    Check(second:Fade(region) and region.faded, id .. " skins its target again after a restart")
    -- A second release (Suite skinning off after the module stopped) is harmless.
    context:Release()
    context:Release()
    Check(not region.faded and context:Skin() == first, id .. " survives a repeated release")
end

-- Suite skinning off and on (the master switch releases every client).
local held = {}
for _, id in ipairs({ "objectives", "announcements", "runSummary" }) do held[id] = Skin.Acquire(id) end
Check(Skin.SetEnabled(false), "Suite skinning turns off")
for _, id in ipairs({ "objectives", "announcements", "runSummary" }) do
    Check(Skin.Acquire(id) == nil, id .. " gets no skin client while Suite skinning is off")
end
Check(Skin.SetEnabled(true), "Suite skinning turns on again")
for _, id in ipairs({ "objectives", "announcements", "runSummary" }) do
    local client = Skin.Acquire(id)
    Check(client ~= nil and client == held[id], id .. " gets its skin client back after skinning off/on")
end

-- A module that fails in combat releases there (the skin defers it); it starts
-- again after combat and keeps the target it skins before the release ran.
local context = Suite.Suite.NewContext("objectives")
local client = context:Skin()
local kept = Region()
Check(client:Fade(kept) and kept.faded, "the module skins a target before combat")
locked = true
context:Release()
Check(kept.faded, "the release waits for the end of combat")
Check(context:Skin() == client, "the module keeps its skin client during combat")
EndCombat()
Check(not kept.faded, "the deferred release gives the target back")
Check(context:Skin() == client and client:Fade(kept) and kept.faded,
    "the restarted module skins its target again after combat")
locked = true
context:Release()
local again = context:Skin()
Check(again == client and again:Fade(kept), "a restart in combat queues the module's target")
EndCombat()
Check(kept.faded, "the target the restarted module claimed survives the deferred release")

print("Suite skin client reacquire: " .. checks .. " checks passed")
