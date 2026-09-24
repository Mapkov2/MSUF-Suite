local root = assert(arg[1], "repository root required")
local locked, Suite, checks = false, {}, 0
Suite.IsCombatLocked = function() return locked end
assert(loadfile(root .. "/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite", Suite)
local Skin = Suite.Skin
local function Check(value, message) assert(value, message);checks = checks + 1 end

MapkoSkin = nil
Check(Skin.SetEnabled(true) and Skin.Acquire("chat") == nil, "suite skin adapter tolerates an absent optional skin addon")
local acquired, released = 0, 0
local skinDB = { suite = "legacy-data" }
MapkoSkin = {
    DB = skinDB,
    GetAPI = function(major, minor)
        Check(major == 2 and minor == 0, "adapter requests the documented skin API")
        return { RegisterAddon = function(_, id)
            acquired = acquired + 1
            return { id = id, ReleaseAll = function() released = released + 1 end }
        end }
    end,
}
local client = Skin.Acquire("chat")
Check(client.id == "MSUF_Suite_chat" and Skin.Acquire("chat") == client and acquired == 1, "a module reuses its own skin client")
Check(Suite.DB == nil and MapkoSkin.DB == skinDB, "skin access never assigns module database ownership")
Check(Skin.Acquire("chat;foreign") == nil, "client identifiers cannot escape their suite prefix")
locked = true
Check(not Skin.SetEnabled(false) and released == 0, "skin release waits outside combat")
locked = false
Check(Skin.SetEnabled(false) and released == 1 and Skin.Acquire("chat") == nil, "skin can be disabled independently of suite modules")
Skin.Release("chat")
Check(released == 1, "repeated release is inert")
Skin.SetEnabled(true)
Check(Skin.Acquire("chat") ~= client and acquired == 2, "reenabling obtains a fresh skin surface client")
local mounted = false
MapkoSkin.MountOptions = function(parent, width, height) mounted = parent == Suite and width == 600 and height == 800;return mounted end
Check(Skin.OpenEditor(Suite, 600, 800) and mounted, "editor integration uses only the published embed function")
Skin.SetEnabled(false)
MapkoSkin = nil
MapkoSkinDB = nil
Suite.RootDB = {}
Suite.Client = { HasAddOn = function(name) return name == "MapkoSkin" end }
local stages = {}
C_AddOns = { LoadAddOn = function(name)
    stages[#stages + 1] = name
    if name == "MapkoSkin" then
        Check(MSUFSuiteSkinMigrating == true, "legacy database loads in migration-only mode")
        MapkoSkinDB = { profiles = { Default = { theme = {} } } }
        MapkoSkin = { addonName = "MapkoSkin", migrationOnly = true, GetAPI = function() end }
    elseif name == "MSUF_Suite_Skin" then
        MapkoSkin = { addonName = "MSUF_Suite_Skin", GetAPI = function() end }
    end
    return true
end }
Check(Skin.EnsureEngine() and stages[1] == "MapkoSkin" and stages[2] == "MSUF_Suite_Skin"
    and Suite.RootDB.skinMigrationDone and MSUFSuiteSkinMigrating == nil,
    "legacy profiles transfer before the embedded engine starts")
print("Standalone suite skin boundary: " .. checks .. " checks passed")
