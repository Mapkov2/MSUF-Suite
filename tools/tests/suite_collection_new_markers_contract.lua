local root = assert(arg[1], "repository root required")
local module, timers = nil, {}
local handlers, cleared = {}, { mounts = {}, pets = {}, toys = {} }
local combat = false
local suite = {
    Install = function(_, value) module = value end,
    PublicText = function(value) return type(value) == "string" and value ~= "secret" and value ~= "" and value or nil end,
    Finite = function(value) return type(value) == "number" and value == value and value ~= math.huge end,
}
local context = {
    Event = function(_, event, callback) handlers[event] = callback end,
    RemoveEvent = function(_, event) handlers[event] = nil end,
}
local function Emit(event, id)
    local callback = handlers[event]
    if callback then callback(module, event, id) end
end
local function RunTimers()
    local batch = timers
    timers = {}
    for _, callback in ipairs(batch) do callback() end
end
C_Timer = { After = function(delay, callback)
    assert(delay == 0)
    timers[#timers + 1] = callback
end }
C_MountJournal = { ClearFanfare = function(id) cleared.mounts[#cleared.mounts + 1] = id end }
C_PetJournal = { ClearFanfare = function(id) cleared.pets[#cleared.pets + 1] = id end }
C_ToyBoxInfo = { ClearFanfare = function(id) cleared.toys[#cleared.toys + 1] = id end }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/CollectionNewMarkers.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = { IsCombatLocked = function() return combat end }, Suite = suite })
module.active = true
module.context = context
module.config = { mounts = true, pets = true, toys = true }
module:Enable()
Emit("NEW_MOUNT_ADDED", 123)
Emit("NEW_MOUNT_ADDED", 123)
Emit("NEW_PET_ADDED", "BattlePet-0-abc")
Emit("NEW_TOY_ADDED", 456)
assert(#timers == 1 and #cleared.mounts == 0, "collection updates did not coalesce")
RunTimers()
assert(#cleared.mounts == 1 and cleared.mounts[1] == 123
    and cleared.pets[1] == "BattlePet-0-abc" and cleared.toys[1] == 456,
    "new collection fanfares were not cleared once")
module.config.toys = false
module:Refresh()
Emit("NEW_TOY_ADDED", 789)
assert(#timers == 0, "disabled collection type kept doing work")
combat = true
Emit("NEW_MOUNT_ADDED", 321)
RunTimers()
assert(handlers.PLAYER_REGEN_ENABLED and #cleared.mounts == 1,
    "collection clearing did not defer out of combat")
combat = false
Emit("PLAYER_REGEN_ENABLED")
assert(cleared.mounts[2] == 321 and not handlers.PLAYER_REGEN_ENABLED,
    "deferred fanfare did not clear on combat exit")
Emit("NEW_MOUNT_ADDED", 654)
module.active = false
module:Disable()
RunTimers()
assert(#cleared.mounts == 2 and not handlers.NEW_MOUNT_ADDED,
    "disabled module processed an old timer or kept events")
print("Suite opt-in collection new markers passed")
