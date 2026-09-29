local root = assert(arg[1], "repository root required")
local module
local combat, toggles, hides = false, 0, 0

local function Frame()
    local frame = { shown = false, hooks = {} }
    function frame:IsShown() return self.shown end
    function frame:IsProtected() return true end
    function frame:HookScript(event, callback)
        assert(not self.hooks[event], "duplicate hook")
        self.hooks[event] = callback
    end
    function frame:Show()
        self.shown = true
        if self.hooks.OnShow then self.hooks.OnShow() end
    end
    function frame:Hide()
        self.shown = false
        if self.hooks.OnHide then self.hooks.OnHide() end
    end
    return frame
end

CharacterFrame = Frame()
ToggleCharacter = function(tab, onlyShow)
    assert(tab == "PaperDollFrame" and onlyShow == true)
    toggles = toggles + 1
    CharacterFrame:Show()
end
HideUIPanel = function(frame)
    hides = hides + 1
    frame:Hide()
end
local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return combat end,
}
local S = { Install = function(id, instance)
    assert(id == "characterUpgradeWindow")
    module = instance
end }
local context = { events = {} }
function context:Event(name, callback) self.events[name] = callback end
function context:RemoveEvent(name) self.events[name] = nil end

assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/CharacterUpgradeWindow.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
module.context, module.active = context, true
module:Enable()
assert(context.events.ADDON_LOADED, "LOD upgrade UI was not awaited")
ItemUpgradeFrame = Frame()
context.events.ADDON_LOADED(module, "ADDON_LOADED", "Blizzard_ItemUpgradeUI")
assert(module.hooked and not context.events.ADDON_LOADED, "native frame was not hooked once")

ItemUpgradeFrame:Show()
assert(CharacterFrame:IsShown() and module.openedCharacter and toggles == 1,
    "equipment window did not open at the upgrade vendor")
ItemUpgradeFrame:Hide()
assert(not CharacterFrame:IsShown() and hides == 1 and not module.openedCharacter,
    "owned equipment window did not close with vendor")

CharacterFrame:Show() -- Player-owned windows are left alone.
ItemUpgradeFrame:Show()
assert(toggles == 1 and CharacterFrame:IsShown() and not module.openedCharacter,
    "module claimed a character window that was already open")
ItemUpgradeFrame:Hide()
assert(CharacterFrame:IsShown(), "module closed a pre-existing character window")
CharacterFrame:Hide()

combat = true
ItemUpgradeFrame:Show()
assert(not CharacterFrame:IsShown() and context.events.PLAYER_REGEN_ENABLED,
    "character window opened during combat or was not deferred")
combat = false
context.events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(CharacterFrame:IsShown() and toggles == 2,
    "post-combat open failed")
ItemUpgradeFrame:Hide()
ItemUpgradeFrame:Show()
assert(CharacterFrame:IsShown() and toggles == 3, "second vendor open failed")
combat = true
ItemUpgradeFrame:Hide()
assert(CharacterFrame:IsShown() and context.events.PLAYER_REGEN_ENABLED,
    "protected close was not deferred")
combat = false
context.events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(not CharacterFrame:IsShown() and not context.events.PLAYER_REGEN_ENABLED,
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
assert(CharacterFrame:IsShown(), "re-enable did not handle an already-open vendor")
local nativeHide = HideUIPanel
HideUIPanel = function() error("client refused panel close") end
ItemUpgradeFrame:Hide()
assert(CharacterFrame:IsShown() and not module.openedCharacter,
    "restricted panel close raised an error or retained ownership")
HideUIPanel = nativeHide
CharacterFrame:Hide()
local nativeToggle = ToggleCharacter
ToggleCharacter = function() error("client refused panel open") end
ItemUpgradeFrame:Show()
assert(not CharacterFrame:IsShown() and not module.openedCharacter,
    "restricted panel open raised an error or claimed ownership")
ToggleCharacter = nativeToggle
print("suite_character_upgrade_window_contract: ok")
