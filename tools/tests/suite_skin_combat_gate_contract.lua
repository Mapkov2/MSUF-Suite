-- Deferred work after combat (Core/CombatGate.lua) runs in the order of the
-- latest request, so the last thing asked for a surface during combat is
-- what it shows afterwards; a window part that refuses to release in combat
-- is not counted as released and releases once combat ends; the Auction
-- House UI loaded during combat is skinned after it.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local locked = false
local frames = {}
CreateFrame = function()
    local frame = { events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(_, script) self.script = script end
    frames[#frames + 1] = frame
    return frame
end
local NS = {
    IsCombatLocked = function() return locked end,
    Safety = { Dispatch = function(callback, ...) return callback(...) end },
}
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/CombatGate.lua"))("MSUF_Suite_Skin", NS)
local Gate, gateFrame = NS.CombatGate, frames[#frames]
local function EndCombat()
    locked = false
    gateFrame.script(gateFrame, "PLAYER_REGEN_ENABLED")
end

-- The latest request for a surface wins: attach then hide leaves it hidden,
-- hide then attach leaves it shown, also when the attach was asked first.
local shown
local function Attach() shown = true end
local function Hide() shown = false end
locked = true
Gate.RunOrDefer("surface:row", Attach)
Gate.RunOrDefer("surface-visible:row", Hide)
EndCombat()
Check(shown == false, "a surface hidden during combat was shown again after it")
locked = true
Gate.RunOrDefer("surface-visible:row", Hide)
Gate.RunOrDefer("surface:row", Attach)
EndCombat()
Check(shown == true, "a surface attached after its hide during combat stayed hidden")
locked = true
Gate.RunOrDefer("surface:row", Attach)
Gate.RunOrDefer("surface-visible:row", Hide)
Gate.RunOrDefer("surface:row", Attach)
EndCombat()
Check(shown == true, "a repeated request did not move behind the requests made since")

-- Jobs run in request order, independent of how the keys hash.
local ran = {}
locked = true
for index = 1, 40 do
    local name = ("job%02d"):format(41 - index)
    Gate.RunOrDefer(name, function() ran[#ran + 1] = name end)
end
Check(Gate.GetPendingCount() == 40 and gateFrame.events.PLAYER_REGEN_ENABLED, "deferred jobs were not counted")
EndCombat()
local ordered = #ran == 40
for index = 1, #ran do
    if ran[index] ~= ("job%02d"):format(41 - index) then ordered = false end
end
Check(ordered, "deferred jobs ran out of request order: " .. table.concat(ran, " ", 1, math.min(#ran, 6)))
Check(Gate.GetPendingCount() == 0 and not gateFrame.events.PLAYER_REGEN_ENABLED,
    "the gate kept jobs or its event after the drain")

-- A key asked for on every update during a long fight keeps the list short;
-- a cancelled job does not run.
locked = true
local updates = 0
for _ = 1, 2000 do
    Gate.RunOrDefer("stats:refresh", function() updates = updates + 1 end)
    Gate.RunOrDefer("slots:refresh", function() end)
end
Check(#Gate.order <= Gate.GetPendingCount() * 2 + 17,
    ("re-requests grew the deferred list to %d entries"):format(#Gate.order))
Gate.RunOrDefer("cancelled", function() error("contract: a cancelled job ran") end)
Gate.Cancel("cancelled")
EndCombat()
Check(updates == 1, "a job asked for many times ran " .. updates .. " times")

------------------------------------------------------------------ window parts
-- A part's release refused in combat is retried after combat; the adapter
-- reports "combat", not a completed release.
local releases = {}
local PARTS = { "DeepWindows", "SemanticHUD", "SharedChrome", "UIPanelButtons", "CommonMenus",
    "Commerce", "CharacterPanel", "InspectPanel", "SocialUISkin", "MajorWindows", "LegacyWindows",
    "CommonArt", "ForeverGroupFinder" }
for _, name in ipairs(PARTS) do
    NS[name] = { Disable = function()
        releases[name] = (releases[name] or 0) + 1
        if name == "CharacterPanel" and locked then return false, "combat" end
        return true
    end }
end
NS.GenericWindows = { Disable = function() return true end, IsCategoryEnabled = function() return true end }
NS.WindowControls = { DisableOwner = function() end }
NS.Client = { isForever = false }
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/Blizzard.lua"))("MSUF_Suite_Skin", NS)
local definition = NS.Adapters.definitions.blizzardWindows
locked = true
local released, reason = definition.disable(nil, "blizzardWindows")
Check(released == false and reason == "combat", "a part that refused in combat was counted as released")
Check(releases.CharacterPanel == 1 and releases.DeepWindows == 1, "the other parts were not released")
EndCombat()
Check(releases.CharacterPanel == 2 and releases.DeepWindows == 1,
    "the part that refused in combat did not release after it")
released, reason = definition.disable(nil, "blizzardWindows")
Check(released == true, "an out-of-combat release did not complete: " .. tostring(reason))

------------------------------------------------------------- auction house
-- Blizzard_AuctionHouseUI loaded during combat is skinned once combat ends.
local loadContinuations = {}
EventUtil = { ContinueOnAddOnLoaded = function(_, callback) loadContinuations[#loadContinuations + 1] = callback end }
local skinnedControls = 0
local function Noop() end
NS.Safety.Field = function(target, key) return type(target) == "table" and target[key] or nil end
NS.Safety.CanDecorate = function() return true end
NS.Safety.Read = Noop
NS.AdapterKit = {
    Fade = Noop, FadeNineSlice = Noop, Attach = Noop, Ensure = Noop, HideSurfaces = Noop,
    SurfaceSpec = function(role) return { role = role } end,
    WeakSet = function() return setmetatable({}, { __mode = "k" }) end,
    PathOf = function() return nil end,
    SkinControl = function() skinnedControls = skinnedControls + 1 end,
}
NS.ControlSkin = { DisableOwner = Noop }
NS.Cosmetics = { RestoreOwner = Noop }
NS.DB = { skinCategories = { economy = true, social = false } }
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/Commerce.lua"))("MSUF_Suite_Skin", NS)
local Commerce = NS.Commerce
AuctionHouseFrame = nil
Commerce.Apply("combat-load")
Commerce.Apply("disabled-in-combat")
Check(#loadContinuations == 2 and Commerce.GetStatus("combat-load").auctionWaiting,
    "the skin did not wait for the Auction House UI")
locked = true
AuctionHouseFrame = {}
for _, continuation in ipairs(loadContinuations) do continuation() end
Check(skinnedControls == 0 and not Commerce.GetStatus("combat-load").auction,
    "the Auction House was skinned during combat")
Commerce.Disable("disabled-in-combat")
EndCombat()
Check(skinnedControls > 0 and Commerce.GetStatus("combat-load").auction,
    "the Auction House UI loaded during combat was never skinned")
Check(not Commerce.GetStatus("disabled-in-combat").auction and Gate.GetPendingCount() == 0,
    "a disabled owner's Auction House skin ran after combat")

print("Suite skin combat gate: " .. checks .. " checks passed")
