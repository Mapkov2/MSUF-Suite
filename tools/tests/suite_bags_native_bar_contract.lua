local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
securecallfunction = function(fn, ...) return fn(...) end
MSUF_NS = { Client = { Family = "Mainline", Flavor = "Mainline", IsRetail = true } }
SlashCmdList = {}
local combat = false
InCombatLockdown = function() return combat end
local frames = {}
CreateFrame = function()
    local frame = { scripts = {}, events = {} }
    function frame:SetScript(event, fn) self.scripts[event] = fn end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    frames[#frames + 1] = frame
    return frame
end
local NS = {}
Support.Load(root, "MSUF_Suite", NS, "Core/Suite.lua", nil, "Mainline")
assert(NS.Database.Initialize(nil))
local S = NS.Suite
local available = { bags = true, dataTexts = true }
S.Availability = function(id) return available[id] ~= false end
S.NewContext = function() return { Release = function() end } end
S.RefreshEditMover, S.UnregisterEditElements = function() end, function() end
NS.Skin = { SurfacesChanged = function() end }
BagsBar = { shown = true }
function BagsBar:IsShown() return self.shown end
function BagsBar:Hide() self.shown = false end
function BagsBar:Show() self.shown = true; if self.onShow then self.onShow() end end
function BagsBar:HookScript(_, fn) self.onShow = fn end
RegisterStateDriver = function(frame, _, value) frame.driver = value end
UnregisterStateDriver = function(frame) frame.driver = nil end
local dt = { config = S.Config("dataTexts") }
local P = { NS = NS, Suite = S, DataTexts = dt }
assert(loadfile(root .. "/MSUF_Suite_DataTexts/NativeBagBar.lua"))("DataTexts", P)
dt.Enable, dt.Refresh, dt.Disable = P.DataTextNativeBagBar.Sync, P.DataTextNativeBagBar.Sync, P.DataTextNativeBagBar.Sync
S.instances.dataTexts = dt
S.instances.bags = { Enable = function() end, Refresh = function() end, Disable = function() end }
S.Config("dataTexts").enabled, S.Config("dataTexts").hideBlizzardBagBar = true, true
S.Config("bags").inventoryView, S.Config("bags").enabled = 1, false
S.started = true
S.Apply("dataTexts")
assert(BagsBar.shown and not BagsBar.driver, "disabled Bags preserves native equipped slots")
S.Config("bags").enabled = true
S.Apply("bags")
assert(not BagsBar.shown and BagsBar.driver == "hide", "active replacement may hide native equipped slots")
assert(S.OwnsBlizzardSurface("bagBar"), "skin yields to the active replacement")
S.Config("bags").enabled = false
combat = true
S.Apply("bags")
assert(not BagsBar.shown, "combat queues native bag-bar restoration")
combat = false
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_REGEN_ENABLED then frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED") end
end
assert(BagsBar.shown and not BagsBar.driver, "Bags disable restores native slots while DataTexts stays active")
assert(dt.active and not S.OwnsBlizzardSurface("bagBar"), "DataTexts keeps running without claiming restored slots")
S.Config("bags").enabled = true
S.Config("bags").inventoryView = 4
S.Apply("bags")
assert(BagsBar.shown and not S.OwnsBlizzardSurface("bagBar"), "Blizzard grid keeps native equipped slots reachable")
S.Config("bags").inventoryView = 1
S.Apply("bags")
dt.paused = true
NS.startingBeforeLockdown = true
BagsBar:Show()
assert(BagsBar.shown, "reload hid equipped slots before the combined inventory was ready")
S.instances.bags.combinedBagConfigured = true
P.DataTextNativeBagBar.Sync()
assert(not BagsBar.shown and BagsBar.driver == "hide", "combat reload did not claim the native bags bar")
NS.startingBeforeLockdown, dt.paused = nil, nil
available.bags = false
S.Apply("bags")
assert(BagsBar.shown and not BagsBar.driver, "unavailable replacement returns native bags")
available.bags = true
S.Apply("bags")
available.dataTexts = false
S.Apply("dataTexts")
assert(BagsBar.shown and not S.OwnsBlizzardSurface("bagBar"), "unavailable DataTexts cannot claim native slots")
print("Bags native bar lifecycle contract passed")
