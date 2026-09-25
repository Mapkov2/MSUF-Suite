-- Blizzard surfaces a running Suite module replaces (Blizzard's damage meter,
-- the bag window shell, the cooldown viewers, the bag bar) are left to that
-- module by the skin, and styled again once the module is off. The skin lets
-- go before the module starts and takes the surface back after it stopped.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

------------------------------------------------------------------ controller
local Suite, events = {}, {}
MSUF_NS = { Client = { Family = "Mainline", Flavor = "Mainline", IsRetail = true } }
SlashCmdList = {}
InCombatLockdown = function() return false end
CreateFrame = function()
    local frame = {}
    function frame:SetScript() end
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:UnregisterAllEvents() end
    return frame
end
Support.Load(root, "MSUF_Suite", Suite, "Core/Suite.lua", nil, "Mainline")
assert(Suite.Database.Initialize(nil))
local S = Suite.Suite
local available = true
S.Availability = function() return available end

Check(S.OwnsBlizzardSurface("damageMeter") == (S.Config("damageMeter").enabled == true),
    "Blizzard's damage meter ownership does not follow the Suite meter setting")
S.Config("damageMeter").enabled = true
Check(S.OwnsBlizzardSurface("damageMeter"), "an enabled Suite meter does not own Blizzard's meter")
available = false
Check(not S.OwnsBlizzardSurface("damageMeter"), "an unavailable Suite meter owns Blizzard's meter")
available = true
S.states.damageMeter.error = "failed"
Check(not S.OwnsBlizzardSurface("damageMeter"), "a failed Suite meter owns Blizzard's meter")
S.states.damageMeter.error = nil
S.Config("damageMeter").enabled = false
Check(not S.OwnsBlizzardSurface("damageMeter"), "a disabled Suite meter owns Blizzard's meter")

S.Config("dataTexts").enabled = true
S.Config("dataTexts").hideBlizzardBagBar = false
Check(not S.OwnsBlizzardSurface("bagBar"), "DataTexts owns a bag bar it keeps visible")
S.Config("dataTexts").hideBlizzardBagBar = true
Check(S.OwnsBlizzardSurface("bagBar"), "DataTexts does not own the bag bar it hides")
Check(not S.OwnsBlizzardSurface("chatFrames") and not S.OwnsBlizzardSurface("minimap"),
    "a surface no module replaces is owned")

-- Start and stop order around a surface module; other modules never notify.
Suite.Skin = { SurfacesChanged = function(phase) events[#events + 1] = "skin:" .. phase end }
S.started = true
S.NewContext = function() return { Release = function() end } end
S.instances.bags = {
    Enable = function() events[#events + 1] = "enable" end,
    Refresh = function() events[#events + 1] = "refresh" end,
    Disable = function() events[#events + 1] = "disable" end,
}
S.Config("bags").enabled = true
S.Apply("bags")
Check(table.concat(events, ",") == "skin:before,enable,skin:after",
    "the skin did not let go before the Bags module started: " .. table.concat(events, ","))
events = {}
S.Config("bags").enabled = false
S.Apply("bags")
Check(table.concat(events, ",") == "skin:before,disable,skin:after",
    "the skin did not take the bag shell back after the Bags module stopped: " .. table.concat(events, ","))
events = {}
S.instances.chat = { Enable = function() end, Refresh = function() end, Disable = function() end }
S.Apply("chat")
Check(#events == 0, "a module without a Blizzard surface notified the skin")

------------------------------------------------------------------ skin side
local owned = {}
MSUFSuite = { Suite = { OwnsBlizzardSurface = function(surface) return owned[surface] == true end } }

local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end
local function Frame()
    return {
        IsForbidden = function() return false end,
        IsProtected = function() return false, false end,
    }
end
local NS = {
    DB = { enabled = true, skins = {} },
    Client = { HasAddOn = function() return false end },
    IsCombatLocked = function() return false end,
    CombatGate = { RunOrDefer = function() error("no combat in this contract") end },
    WindowControls = { DisableOwner = function() end, Attach = function() end },
    Cosmetics = { RestoreOwner = function() end },
    Surface = { Attach = function(frame) return frame end, SetVisible = function() end },
    Checkmarks = { TrackControlTree = function() end },
}
for _, file in ipairs({ "Core/Safety.lua", "Core/Registry.lua", "Core/SuiteOwnership.lua", "Adapters/Blizzard.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
local Ownership, Adapters = NS.SuiteOwnership, NS.Adapters
Check(Adapters.definitions.damageMeter.suiteSurface == "damageMeter",
    "Blizzard's damage meter adapter does not yield to the Suite meter")

-- The adapter gate: an owned surface is disabled, a free one applied.
local applied, disabled = 0, 0
assert(Adapters.Register({
    id = "contractMeter", suiteSurface = "damageMeter",
    resolve = function() return Frame() end,
    apply = function() applied = applied + 1; return true end,
    disable = function() disabled = disabled + 1; return true end,
}))
owned.damageMeter = true
Check(Adapters.Apply("contractMeter") == false and applied == 0 and disabled == 1
    and Adapters.GetStatus("contractMeter") == "disabled",
    "the skin styled a surface the Suite owns")
owned.damageMeter = false
Check(Adapters.Apply("contractMeter") == true and applied == 1,
    "the skin did not style a surface the Suite left to Blizzard")

-- Refresh phases rebuild only surfaces that changed hands, once per adapter.
local rebuilt = {}
Adapters.Refresh = function(id) rebuilt[#rebuilt + 1] = id; return true end
Ownership.answers = {}
Ownership.Refresh("before")
Check(#rebuilt == 0, "a surface the skin never asked about was rebuilt")
owned = { damageMeter = false, bagWindows = false, bagBar = false }
Check(not Ownership.Owns("damageMeter") and not Ownership.Owns("bagWindows")
    and not Ownership.Owns("bagBar"), "free surfaces answered as owned")
owned.bagWindows, owned.bagBar = true, true
Ownership.Refresh("after")
Check(#rebuilt == 0, "the skin let go only after the module had started")
Ownership.Refresh("before")
Check(#rebuilt == 1 and rebuilt[1] == "blizzardWindows",
    "the bag shell and bag bar were not handed over in one rebuild")
Check(Ownership.Owned("bagWindows") and Ownership.Owned("bagBar"), "the handed over answer was not kept")
rebuilt = {}
Ownership.Refresh("before")
Check(#rebuilt == 0, "an unchanged surface was rebuilt")
owned.bagWindows = false
Ownership.Refresh("before")
Check(#rebuilt == 0, "the skin took a surface back before its module stopped")
Ownership.Refresh("after")
Check(#rebuilt == 1 and rebuilt[1] == "blizzardWindows" and not Ownership.Owned("bagWindows"),
    "the skin did not take the bag shell back after the module stopped")
rebuilt = {}
owned.damageMeter = true
Ownership.Refresh("before")
Check(#rebuilt == 1 and rebuilt[1] == "damageMeter", "Blizzard's meter was not handed to the Suite meter")

ContainerFrameCombinedBags, ContainerFrame6 = {}, {}
Check(Ownership.IsBagShell(ContainerFrameCombinedBags) and Ownership.IsBagShell(ContainerFrame6)
    and not Ownership.IsBagShell({}) and not Ownership.IsBagShell(nil),
    "the bag shell frames are misidentified")
Check(Ownership.EntrySurface("hud-cooldown-viewers") == "cooldownViewers"
    and Ownership.EntrySurface("hud-bag-bar") == "bagBar"
    and Ownership.EntrySurface("hud-minimap") == nil
    and Ownership.EntrySurface("hud-action-bars") == nil,
    "catalog entries map to the wrong owned surfaces")
Check(#reported == 0, "the ownership contract raised errors: " .. table.concat(reported, "; "))

print("Suite skin ownership: " .. checks .. " checks passed")
