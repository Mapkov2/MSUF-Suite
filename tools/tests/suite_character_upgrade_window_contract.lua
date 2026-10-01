local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local module
local combat, reported = false, {}

local function Frame()
    local frame = { shown = false, hooks = {} }
    function frame:IsShown() return self.shown end
    function frame:IsProtected() return true end
    function frame:HookScript(event, callback)
        assert(not self.hooks[event], "duplicate hook")
        self.hooks[event] = callback
    end
    function frame:Show()
        if self.shown then return end
        self.shown = true
        if self.hooks.OnShow then self.hooks.OnShow() end
    end
    function frame:Hide()
        if not self.shown then return end
        self.shown = false
        if self.hooks.OnHide then self.hooks.OnHide() end
    end
    return frame
end

-- Blizzard_UIPanels_Game creates CharacterFrame before any addon loads;
-- Blizzard_ItemUpgradeUI loads on demand.
CharacterFrame = Frame()
local panels = Support.UIPanels(function() return combat end)
local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return combat end,
    Finish = function(callback, ...) return true, callback(...) end,
}
local watcher
local S = {
    Dispatch = Support.Dispatcher(reported),
    CreateFrame = function()
        watcher = { events = {} }
        function watcher:SetScript(_, callback) self.callback = callback end
        function watcher:RegisterEvent(event) self.events[event] = true end
        function watcher:UnregisterEvent(event) self.events[event] = nil end
        return watcher
    end,
    Install = function(id, instance)
        assert(id == "characterUpgradeWindow")
        module = instance
    end,
}
local context = { events = {} }
function context:Event(name, callback) self.events[name] = callback end
function context:RemoveEvent(name) self.events[name] = nil end

assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/CharacterPanel.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/CharacterUpgradeWindow.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
module.context, module.active = context, true
module:Enable()
assert(context.events.ADDON_LOADED, "LOD upgrade UI was not awaited")
ItemUpgradeFrame = Frame()
context.events.ADDON_LOADED(module, "ADDON_LOADED", "Blizzard_ItemUpgradeUI")
assert(module.hooked and not context.events.ADDON_LOADED, "native frame was not hooked once")

ItemUpgradeFrame:Show()
assert(CharacterFrame:IsShown() and S.HoldsCharacter(module) and panels.shown == 1 and #reported == 0,
    "the character window did not open through the panel manager at the upgrade vendor")
ItemUpgradeFrame:Hide()
assert(not CharacterFrame:IsShown() and panels.hidden == 1 and not S.HoldsCharacter(module),
    "owned character window did not close with vendor")

CharacterFrame:Show() -- Player-owned windows are left alone.
ItemUpgradeFrame:Show()
assert(panels.shown == 1 and CharacterFrame:IsShown() and not S.HoldsCharacter(module),
    "module claimed a character window that was already open")
ItemUpgradeFrame:Hide()
assert(CharacterFrame:IsShown(), "module closed a pre-existing character window")
CharacterFrame:Hide()

combat = true
ItemUpgradeFrame:Show()
assert(not CharacterFrame:IsShown() and context.events.PLAYER_REGEN_ENABLED and panels.blocked == 0,
    "character window opened during combat or was not deferred")
combat = false
context.events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(CharacterFrame:IsShown() and panels.shown == 2, "post-combat open failed")
ItemUpgradeFrame:Hide()
ItemUpgradeFrame:Show()
assert(CharacterFrame:IsShown() and panels.shown == 3, "second vendor open failed")
combat = true
ItemUpgradeFrame:Hide()
assert(CharacterFrame:IsShown() and watcher.events.PLAYER_REGEN_ENABLED and panels.blocked == 0,
    "the close in combat was not deferred")
combat = false
watcher.callback(watcher, "PLAYER_REGEN_ENABLED")
assert(not CharacterFrame:IsShown() and not watcher.events.PLAYER_REGEN_ENABLED,
    "deferred close failed")

ItemUpgradeFrame:Show()
assert(CharacterFrame:IsShown())
module:Disable()
module.active = false
assert(not CharacterFrame:IsShown() and not context.events.ADDON_LOADED,
    "disable left owned UI open")
ItemUpgradeFrame:Hide()
ItemUpgradeFrame:Show()
assert(not CharacterFrame:IsShown(), "permanent hook acted while disabled")
module.active = true
module:Enable()
assert(CharacterFrame:IsShown() and S.HoldsCharacter(module), "re-enable did not handle an already-open vendor")
ItemUpgradeFrame:Hide()
assert(not CharacterFrame:IsShown() and panels.blocked == 0 and #reported == 0,
    "the panel manager refused a call or a call raised")
print("suite_character_upgrade_window_contract: ok")
