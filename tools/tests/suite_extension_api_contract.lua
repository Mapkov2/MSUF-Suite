local root = assert(arg[1])
local ready, combat, notices
local imported
local function Profile() return { suite = {} } end
local Suite = {
    API = {}, DB = Profile(),
    Suite = { DataTextExtraSources = { ExtensionChanged = function() notices = (notices or 0) + 1 end } },
    PublicText = function(value) return type(value) == "string" and value or nil end,
    Public = function(value) return value ~= "SECRET" end,
    Finite = function(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end,
    InCombat = function() return combat end,
    Finish = function(fn, ...) return true, fn(...) end,
    Dispatch = function(fn, ...)
        local ok, first, second, third = pcall(fn, ...)
        if ok then return first, second, third end
    end,
    SuiteProfiles = { maxBytes = 100, Import = function(name, value) imported = { name, value } return true end },
}
assert(loadfile(root .. "/MSUF_Suite/Core/Extensions.lua"))("Suite", Suite)
local API, Extensions = Suite.API.Extensions, Suite.Extensions
local firstProfile = Suite.DB
local plugin = assert(API.Register("Example", function(kind, id)
    if kind == "Item" and id == 77 then return "Owned", "Yes" end
end))
assert(not API.Register("Example") and not API.Register("Invalid ID"))
assert(plugin.SetSetting("favorite", false))
assert(plugin.GetSetting("favorite") == false)
assert(not plugin.SetSetting("favorite", "SECRET"))
Suite.DB = Profile()
assert(plugin.GetSetting("favorite") == nil)
assert(plugin.SetSetting("favorite", 99))
Suite.DB = firstProfile
assert(plugin.GetSetting("favorite") == false, "plugin state leaked between profiles")
for i = 1, 31 do assert(plugin.SetSetting("k" .. i, i)) end
assert(not plugin.SetSetting("overflow", 1))
assert(plugin.SetSetting("k31", nil) and plugin.SetSetting("overflow", 1))

assert(plugin.PublishDataText("Count", "12", 99) and notices == 1)
assert(plugin.PublishDataText("Count", "12", 99) and notices == 1)
local broker, reserved = Extensions.Broker("MSUF.Example")
assert(reserved and broker.text == "12" and broker.label == "Count")
assert(plugin.RegisterProfile("Starter", 1, "MSUFS3:suite"))
assert(not plugin.RegisterProfile("Duplicate", 1, "MSUFS3:bad"))
assert(Extensions.ProfilePacks()[1].label == "Starter")
assert(not Extensions.ImportProfile("Example", 2, "Demo"))
assert(Extensions.ImportProfile("Example", 1, "Demo") and imported[1] == "Demo")
local failing = assert(API.Register("Failing", function()
    ready = (ready or 0) + 1
    error("callback error")
end))
local rows = 0
local function Add(_, label, value)
    assert(label == "Owned" and value == "Yes")
    rows = rows + 1
end
Extensions.TooltipLines("Item", 77, {}, Add)
Extensions.TooltipLines("Item", 77, {}, Add)
assert(rows == 2 and ready == 1, "provider errors did not isolate the failing callback")
combat = true
Extensions.TooltipLines("Item", 77, {}, Add)
assert(rows == 2 and not plugin.SetSetting("favorite", true))
combat = false
assert(failing.Unregister() and plugin.Unregister())
assert(not plugin.PublishDataText("Count", "99") and #Extensions.ProfilePacks() == 0)
assert(not Extensions.Broker("MSUF.Example"))
print("Suite extension lifecycle validated")
