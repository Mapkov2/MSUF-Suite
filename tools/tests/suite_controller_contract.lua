local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local Suite, loads, frames, combat = {}, 0, {}, false
MSUF_NS = { Client = { Family = "Classic", Flavor = "Vanilla" } }
SlashCmdList = {}
InCombatLockdown = function() return combat end
Minimap = { SetMaskTexture = function() end }
CreateFrame = function()
    local frame = { events = {} }
    function frame:SetScript(_, callback) self.callback = callback end
    function frame:RegisterEvent(event)
        self.events[event] = true
        self.registrations = (self.registrations or 0) + 1
    end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    frames[#frames + 1] = frame
    return frame
end
C_AddOns = {
    IsAddOnLoaded = function() return false end,
    DoesAddOnExist = function(name) return name == "MSUF_Suite_Minimap" end,
    LoadAddOn = function(name)
        assert(name == "MSUF_Suite_Modules" or name == "MSUF_Suite_Minimap")
        local controller = Suite.Suite
        if name == "MSUF_Suite_Modules" then
            loads = loads + 1
            controller.NewContext = function()
                return { Release = function(self) self.released = true end }
            end
        else
            controller.instances.minimap = {
                Enable = function(self) self.starts = (self.starts or 0) + 1 end,
                Refresh = function(self) self.refreshes = (self.refreshes or 0) + 1 end,
                Disable = function(self) self.stops = (self.stops or 0) + 1 end,
            }
        end
        -- Forever can register successfully without returning a loaded flag.
    end,
}
Support.Load(root, "MSUF_Suite", Suite, "Core/Suite.lua", nil, "Vanilla")
assert(Suite.Database.Initialize(nil))
Suite.Suite.Normalize(Suite.DB)
for _, id in ipairs(Suite.SuiteOrder) do
    assert(Suite.Suite.Config(id).enabled == true, id .. " factory module is off")
end
for _, id in ipairs(Suite.SuiteOrder) do Suite.Suite.Config(id).enabled = false end
Suite.Suite.Start()
assert(loads == 0 and #frames == 0, "disabled modules performed startup work")
assert(Suite.Suite.Set("minimap", "enabled", true))
local module = Suite.Suite.instances.minimap
assert(loads == 1 and module.starts == 1 and Suite.Suite.Status("minimap") == "Active")
combat = true
Suite.Suite.Apply("minimap")
Suite.Suite.Apply("minimap")
assert(#frames == 1 and frames[1].registrations == 1 and module.refreshes == nil,
    "combat refresh was not coalesced")
assert(not Suite.Suite.Set("minimap", "enabled", false))
combat = false
frames[1]:callback()
assert(module.refreshes == 1 and not next(frames[1].events))
assert(Suite.Database.Create("Fresh", false))
assert(Suite.Database.Activate("Fresh"))
assert(Suite.Suite.Config("minimap").enabled == true and module.active,
    "new profile did not start with its modules enabled")
assert(Suite.Suite.Set("minimap", "enabled", false))
assert(module.stops == 1 and module.context.released and not module.active)
module.Enable = function(self) error("deliberate partial activation") end
local ok = pcall(Suite.Suite.Set, "minimap", "enabled", true)
assert(not ok and module.active and not Suite.Suite.states.minimap.active)
assert(Suite.Suite.Set("minimap", "enabled", false))
assert(module.stops == 2 and not module.active, "partial activation leaked on disable")
assert(loads == 1 and type(SlashCmdList.MSUFSUITE) == "function")
-- Setup enables available core modules. Other factory-enabled modules keep
-- their saved switch, and unavailable modules still show their reason.
module.Enable = function(self) self.starts = self.starts + 1 end
local S = Suite.Suite
assert(S.Preset("core"))
assert(S.Config("minimap").enabled and module.active and S.Status("minimap") == "Active")
assert(not S.Config("actionbars").enabled and not S.Config("damageMeter").enabled)
assert(S.Status("actionbars") ~= "Off" and S.Status("actionbars") ~= "Active", "unavailable module lost its reason")
assert(S.Config("qol").enabled and S.Config("quests").enabled and S.Config("loot").enabled
    and S.Config("buffReminders").enabled)
assert(S.Set("qol", "enabled", true) and S.Preset("core") and S.Config("qol").enabled, "setup overrode an opt-in choice")
UnitGUID = function() return "Player-Test" end
local addonDisabled = true
C_AddOns.GetAddOnEnableState = function(name, guid)
    assert(guid == "Player-Test")
    return addonDisabled and name == "MSUF_Suite_Minimap" and 0 or 1
end
S.Apply("minimap")
assert(not module.active and S.Status("minimap"):find("Disabled in Blizzard", 1, true),
    "Blizzard's AddOn checkbox did not stop the loaded module")
addonDisabled = false
S.Apply("minimap")
assert(module.active and S.Status("minimap") == "Active",
    "re-enabled Blizzard AddOn did not restore the module")
assert(S.Preset("off") and not S.Config("minimap").enabled and not S.Config("qol").enabled and not module.active)
assert(not S.Preset("everything"))
print("Standalone suite controller: dormant startup, own loader, combat coalescing, profile switch, partial cleanup and setup presets passed")
