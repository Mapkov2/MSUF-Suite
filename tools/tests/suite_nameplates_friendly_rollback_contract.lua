-- The friendly nameplate switches confirm their native write inside the
-- controller's batch (MSUF_Suite/Core/Suite.lua, SetMany). A module that does
-- not run afterwards, a value Blizzard refuses or a raising confirmation
-- restores the whole batch before the menu repaints: settings, look record
-- and the module's CVar records. Real controller, runtime and nameplate CVars.
local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
if flavor == "Forever" then GameEvent = { RegisterCamelotEvents = function() end } end
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end
MSUF_NS = {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
InCombatLockdown = function() return false end
Minimap = { SetMaskTexture = function() end }
CreateFrame = function()
    local frame = {}
    function frame:SetScript() end
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    return frame
end
UnitName = function() return "Tester" end
GetRealmName = function() return "Realm" end
UnitGUID = function() return "Player-Test" end
Enum = Enum or {}
Enum.GameRule = Enum.GameRule or {}
C_GameRules = { IsGameRuleActive = function() return false end }

local Suite, S = {}, nil
-- Blizzard's values. refused[key] models a value the client keeps; a write
-- fires CVAR_UPDATE at once, as in the client.
local live, refused, writes = {}, {}, 0
C_CVar = {
    GetCVar = function(key) return live[key] end,
    SetCVar = function(key, value)
        if refused[key] then return false end
        writes = writes + 1
        live[key] = tostring(value)
        local module = S and S.instances.nameplates
        if module and module.active then Suite.SyncFriendlyNameplates(module, "CVAR_UPDATE", key) end
        return true
    end,
}

local startFails = false
local loaded = {}
local function Instance()
    local private = { NS = Suite, Suite = S }
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/Modes.lua"))("MSUF_Suite_Nameplates", private)
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/CVars.lua"))("MSUF_Suite_Nameplates", private)
    local module = { starts = 0 }
    function module:Enable()
        if startFails then error("deliberate nameplate start failure") end
        self.starts = self.starts + 1
        private.CVars.Apply(self)
    end
    function module:Refresh() private.CVars.Apply(self) end
    function module:Disable() end
    return module
end
C_AddOns = {
    IsAddOnLoaded = function(name) return loaded[name] == true end,
    DoesAddOnExist = function(name) return name == "MSUF_Suite_Nameplates" end,
    GetAddOnEnableState = function() return 2 end,
    LoadAddOn = function(name)
        loaded[name] = true
        if name == "MSUF_Suite_Modules" then
            assert(loadfile(root .. "/MSUF_Suite_Modules/Runtime.lua"))(name, {})
            S.RefreshEditMover, S.UnregisterEditElements = function() end, function() end
        elseif name == "MSUF_Suite_Nameplates" then
            S.instances.nameplates = Instance()
        end
    end,
}
-- Forever loads the Mainline TOC.
Support.Load(root, "MSUF_Suite", Suite, "Core/Suite.lua")
_G.MSUFSuite = Suite
-- The skin boundary loads right after the controller (no skin is installed).
assert(loadfile(root .. "/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite", Suite)
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", Suite)
S = Suite.Suite
assert(Suite.Database.Initialize(nil))
for _, id in ipairs(Suite.SuiteOrder) do S.Config(id).enabled = false end
S.Start()

local checks = 0
local function Check(condition, message)
    checks = checks + 1
    assert(condition, message)
end
local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not Same(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end
-- What the menu sees when the controller repaints it.
local painted = {}
Suite.Options = { RefreshAll = function()
    local config = S.Config("nameplates")
    painted[#painted + 1] = { enabled = config.enabled, friendly = config.friendlySkinEnabled,
        npcs = config.friendlyNPCs, native = live.nameplateShowFriendlyPlayers }
end }
local function Watch()
    painted, writes, reported = {}, 0, {}
end
live.nameplateShowFriendlyPlayers, live.nameplateShowFriendlyNpcs, live.UnitNameNPC = "0", "0", "0"
-- The header switch of a disabled module enables it with only that scope.
local HEADER = { enabled = true, friendlySkinEnabled = true, friendlyNpcSkinEnabled = false,
    enemySkinEnabled = false, neutralSkinEnabled = false }

-- A module that cannot start keeps nothing of the switch.
local before = Suite.CopyValue(S.Config("nameplates"))
startFails = true
Watch()
local ok, reason = Suite.SetFriendlyNameplates("friendly", true, HEADER)
Check(not ok and reason == "Stopped after an error", "a failed start was not refused with its status")
Check(Same(S.Config("nameplates"), before), "a failed start kept the enabled switch or the visibility")
Check(live.nameplateShowFriendlyPlayers == "0" and writes == 0, "a failed start changed native visibility")
Check(#painted == 1 and painted[1].enabled == false and painted[1].friendly == before.friendlySkinEnabled,
    "the menu repainted before the batch was restored")
Check(#reported == 1 and reported[1]:find("deliberate nameplate start failure", 1, true),
    "the start failure was not reported once")

-- A recoverable error: the switch starts the module and commits Blizzard's
-- value before the menu repaints.
startFails = false
Watch()
Check(Suite.SetFriendlyNameplates("friendly", true, HEADER), "the switch did not restart a recoverable module")
Check(S.Status("nameplates") == "Active" and S.Config("nameplates").enabled
    and S.Config("nameplates").friendlySkinEnabled and live.nameplateShowFriendlyPlayers == "1",
    "the restarted module did not apply the switch")
Check(#painted == 1 and painted[1].native == "1", "the menu repainted before the native value was confirmed")

-- Blizzard refuses the value while the module runs: the saved switch stays.
Check(Suite.SetFriendlyNameplates("friendly", false), "preparing Suite Off failed")
refused.nameplateShowFriendlyPlayers = true
Watch()
ok = Suite.SetFriendlyNameplates("friendly", true)
Check(not ok and S.Config("nameplates").friendlySkinEnabled == false, "a refused native On kept the profile wish")
Check(live.nameplateShowFriendlyPlayers == "0" and #painted == 1 and painted[1].friendly == false,
    "a refused native On reached the menu")
Check(S.Status("nameplates") == "Active", "a refused native On stopped the module")
refused.nameplateShowFriendlyPlayers = nil

-- NPC names-only hides Blizzard's NPC plates and shows world names. A
-- refused switch back to health bars keeps both overrides on their
-- Blizzard values, so turning the module off still restores them.
-- Blizzard's own NPC On (its settings or a binding) turns the NPC scope on.
C_CVar.SetCVar("nameplateShowFriendlyNpcs", "1")
Check(S.Config("nameplates").friendlyNpcSkinEnabled, "Blizzard On did not reach the NPC scope")
Check(S.SetMany("nameplates", { friendlyNPCs = 4 }), "preparing names-only failed")
Check(live.nameplateShowFriendlyNpcs == "0" and live.UnitNameNPC == "1", "names-only did not apply its overrides")
local records = S.CVarRecords("nameplates")
Check(records.nameplateShowFriendlyNpcs and records.nameplateShowFriendlyNpcs.before == "1",
    "names-only did not record Blizzard's NPC visibility")
refused.nameplateShowFriendlyNpcs = true
Watch()
ok = Suite.SetFriendlyNameplates("friendlyNpc", true, { friendlyNPCs = 2 })
Check(not ok and S.Config("nameplates").friendlyNPCs == 4 and #painted == 1 and painted[1].npcs == 4,
    "a refused NPC display change kept the profile wish")
Check(Same(S.CVarRecords("nameplates"), records), "a restored batch lost the Blizzard values under its overrides")
refused.nameplateShowFriendlyNpcs = nil
Check(S.SetMany("nameplates", { enabled = false }), "turning the module off failed")
Check(live.nameplateShowFriendlyNpcs == "1" and live.UnitNameNPC == "0",
    "turning the module off did not hand Blizzard's NPC values back")

-- Any confirmed batch: a raising confirmation restores it too, the look record
-- included; a batch without confirmation keeps today's behavior.
Check(Suite.SuiteLooks.Supports("cursorEffects"), "the look record is not exercised")
local db = Suite.DB.suite
-- A first enable adopts the global look: the module has no record yet.
db.moduleLooks.cursorEffects = nil
local looks, cursor = db.moduleLooks and Suite.CopyValue(db.moduleLooks), Suite.CopyValue(S.Config("cursorEffects"))
Watch()
ok = S.SetMany("cursorEffects", { enabled = true }, function() error("deliberate confirmation error") end)
Check(not ok and #reported == 1 and Same(S.Config("cursorEffects"), cursor) and Same(db.moduleLooks, looks),
    "a raising confirmation kept the batch or its look record")
Check(S.SetMany("cursorEffects", { enabled = true }) and S.Config("cursorEffects").enabled
    and not Same(db.moduleLooks, looks), "a batch without confirmation did not adopt the global look")

print("Suite friendly rollback " .. flavor .. ": " .. checks .. " causal checks passed")
