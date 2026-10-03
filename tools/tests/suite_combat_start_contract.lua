-- The combat start: the client sends PLAYER_REGEN_DISABLED while
-- InCombatLockdown() is still false and the player's combat flag is already
-- true. Every public refusal of the Suite counts that dispatch as combat
-- (Suite.InCombat, MSUF_Suite/Core/Platform.lua): the controller's setters,
-- page resets, presets and the global look (Suite.lua), and the legacy scale
-- path of the host bridge (HostBridge.lua). One narrow write stays open:
-- MSUF Edit Mode commits a drag the player still holds when Edit Mode closes
-- for combat, inside that dispatch (S.CommitEditPosition through
-- MSUF_Suite_Modules/EditMode.lua). The real core, the real Edit Mode
-- elements; every call runs inside a PLAYER_REGEN_DISABLED handler.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local Suite, lockdown, fighting = {}, false, false
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
InCombatLockdown = function() return lockdown end
UnitAffectingCombat = function(unit)
    assert(unit == "player", "the combat rules read the player's combat flag only")
    return fighting or lockdown
end
UnitGUID = function() return "Player-Test" end
Minimap = { SetMaskTexture = function() end }
local frames = {}
CreateFrame = function()
    local frame = { events = {} }
    function frame:SetScript(_, callback) self.callback = callback end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    frames[#frames + 1] = frame
    return frame
end
local INSTALLED, loaded = { MSUF_Suite_Minimap = "minimap" }, {}
C_AddOns = {
    IsAddOnLoaded = function(name) return loaded[name] == true end,
    DoesAddOnExist = function(name) return INSTALLED[name] ~= nil end,
    GetAddOnEnableState = function() return 2 end,
    LoadAddOn = function(name)
        loaded[name] = true
        local controller = Suite.Suite
        if name == "MSUF_Suite_Modules" then
            controller.NewContext = function()
                return { Release = function() end, RefreshOwnedSkins = function() end }
            end
            -- The shared runtime's Edit Mode elements (MSUF_Suite_Modules/EditMode.lua).
            controller.Finite, controller.Text = Suite.Finite, function(text) return text end
            controller.Dispatch = Suite.Dispatch
            assert(loadfile(root .. "/MSUF_Suite_Modules/EditMode.lua"))("MSUF_Suite_Modules",
                { NS = Suite, Suite = controller })
        elseif INSTALLED[name] then
            controller.instances[INSTALLED[name]] = {
                Enable = function() end, Refresh = function() end, Disable = function() end,
            }
        end
    end,
}
local records = {}
MSUF_EditModeAPI = {
    RegisterElement = function(owner, element) records[owner .. "/" .. element.id] = element; return true end,
    RegisterSessionListener = function() end, IsActive = function() return false end,
    UnregisterOwner = function() end, UnregisterSessionListener = function() end,
}
UIParent = {}
Support.Load(root, "MSUF_Suite", Suite, "Core/HostBridge.lua")
Suite.Suite.RGB = Suite.RGB
_G.MSUFSuite = Suite
assert(Suite.Database.Initialize(nil))
local S = Suite.Suite
for _, id in ipairs(Suite.SuiteOrder) do S.Config(id).enabled = false end
S.Start()
assert(S.Set("minimap", "enabled", true) and S.states.minimap.active, "the minimap did not start")

-- The client's PLAYER_REGEN_DISABLED dispatch: the flag is true, the
-- lockdown is not yet; handler runs as a frame's OnEvent handler of it.
local function CombatStart(handler)
    local watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", handler)
    watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    fighting = true
    for _, frame in ipairs(frames) do
        if frame.events.PLAYER_REGEN_DISABLED and frame.callback then
            frame.callback(frame, "PLAYER_REGEN_DISABLED")
        end
    end
    watcher:UnregisterAllEvents()
    lockdown = true
end
local function CombatEnd()
    lockdown, fighting = false, false
end

local function Snapshot()
    return Suite.CopyValue(Suite.DB.suite)
end
local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

-- The setters, the page reset, the presets and the global look refuse.
local before = Snapshot()
local results = {}
CombatStart(function(_, event)
    assert(event == "PLAYER_REGEN_DISABLED" and not InCombatLockdown())
    results.set = { S.Set("minimap", "size", 180) }
    results.setMany = { S.SetMany("minimap", { size = 181, x = 12 }) }
    results.resetKeys = { S.ResetKeys("minimap", { size = 140 }) }
    results.reset = S.Reset("minimap")
    results.preset = S.Preset("off")
    results.look = S.ApplyGlobalLook("midnight")
end)
CombatEnd()
assert(results.set[1] == false and results.set[2] == "Finish combat before editing the suite",
    "S.Set accepted a change at the combat start")
assert(results.setMany[1] == false and results.resetKeys[1] == false,
    "S.SetMany or S.ResetKeys accepted a change at the combat start")
assert(results.reset == false and results.preset == false and results.look == false,
    "a page reset, a preset or the global look ran at the combat start")
assert(Same(Snapshot(), before), "a refused combat-start change still wrote the profile")

-- Out of combat the same calls go through (the refusal is the combat start).
assert(S.Set("minimap", "size", 180) and S.Config("minimap").size == 180)

-- The held drag: Edit Mode closes for combat and commits the drag inside the
-- same dispatch; a refused commit gets its start state back. Both go through.
local element = assert(records["MSUFSuite.minimap/map"] or (function()
    assert(S.RegisterOwnedMover("minimap", "map", { label = "Minimap", xKey = "x", yKey = "y", point = "TOPRIGHT",
        getFrame = function()
            return { GetScale = function() return 1 end, ClearAllPoints = function() end, SetPoint = function() end }
        end }))
    return records["MSUFSuite.minimap/map"]
end)(), "the minimap mover did not register")
local start = element.captureState()
local startX = S.Config("minimap").x
local committed, restored, publicSet
CombatStart(function()
    committed = element.movePosition({ state = start, deltaX = 25, deltaY = 0, phase = "commit" })
    publicSet = S.SetMany("minimap", { x = startX + 99 })
    restored = { x = S.Config("minimap").x }
    restored.ok = element.restoreState(start)
end)
CombatEnd()
assert(committed == true and restored.x == startX + 25,
    "the held drag Edit Mode commits at the combat start was refused")
assert(publicSet == false, "the public setter took the held-drag path")
assert(restored.ok == true and S.Config("minimap").x == startX,
    "a refused commit's start state was not given back at the combat start")
-- Under lockdown the narrow path refuses too.
lockdown = true
assert(element.movePosition({ state = start, deltaX = 5, deltaY = 0, phase = "commit" }) == false
    and S.CommitEditPosition("minimap", { x = 1 }) == false and S.Config("minimap").x == startX,
    "the held-drag path wrote under lockdown")
lockdown = false

-- The legacy scale path (an MSUF host without host API v1) refuses at the
-- combat start, before it writes MSUF's settings or calls MSUF's appliers.
local applied = {}
MSUF_DB = { general = { msufUiScale = 0.9, UIScale = { Enabled = false, Scale = 0.6 } } }
MSUF_ApplyMsufScale = function(value) applied[#applied + 1] = "frame:" .. value end
MSUF_ResetGlobalUiScale = function() applied[#applied + 1] = "reset" end
MSUF_SetGlobalUiScale = function(value) applied[#applied + 1] = "global:" .. value end
local scaleBefore = Suite.CopyValue(MSUF_DB)
local spec = { msufScale = 1, global = { preset = "custom", scale = 0.71 } }
local scaleOk, scaleWhy
CombatStart(function() scaleOk, scaleWhy = Suite.HostBridge.ApplyScale(spec) end)
CombatEnd()
assert(not Suite.HostBridge.HasCoreAPI(), "this host has host API v1")
assert(scaleOk == false and scaleWhy == "Finish combat first." and #applied == 0 and Same(MSUF_DB, scaleBefore),
    "the legacy scale path applied at the combat start")
assert(Suite.HostBridge.ApplyScale(spec) and MSUF_DB.general.UIScale.Scale == 0.71,
    "the legacy scale path refused out of combat")
assert(#reported == 0, "a call raised: " .. tostring(reported[1]))
print("Suite combat start: setters, page reset, presets, global look and the legacy scale refuse; held drags commit")
