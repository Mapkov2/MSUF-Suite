local root = assert(arg[1])
SUITE_OPTIONS_FIXTURE = true
local fixture = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
SUITE_OPTIONS_FIXTURE = nil
local P, S, M = fixture.optionsNS, fixture.S, fixture.M
local selected, key, effective, toggled, opened
local nativeMap, nativeToggles = "0", 0
local getCVar = C_CVar.GetCVar
C_CVar.GetCVar = function(name)
    if name == "showBattlefieldMinimap" then return nativeMap end
    return getCVar(name)
end
ToggleBattlefieldMap = function()
    nativeMap = nativeMap == "1" and "0" or "1"
    nativeToggles = nativeToggles + 1
end
GetBindingKey = function(command) assert(command == "MSUFSUITE_TOGGLE_MAP_OVERLAY"); return key end
GetBindingAction = function(keyName, overrides)
    assert(keyName == "SHIFT-M" and overrides == true)
    return effective
end
GetBindingText = function(value) return value end
Settings = { KEYBINDINGS_CATEGORY_ID = 9, OpenToCategory = function(id, category) opened = { id, category } end }
fixture.Suite.ToggleMapOverlay = function() toggled = true end
S.HasOwnedMover = function(id, element) return id == "navigationHUD" and (element == "map" or element == "compass") end
P.MoveOnScreen = function(id, element, popup) selected = { id, element, popup } end
local status = "Disabled"
S.Status = function() return status end

local ctx = { key = "suite_qualityOfLife", width = 850, refreshers = {}, widgets = {}, sections = {},
    pageItems = {}, entry = { sections = {} } }
fixture.SetCurrent(ctx)
M.pages.suite_qualityOfLife.build(ctx)
local group = assert(P.QoLView.FindFeature("navigationHUD"))
local section = P.QoLView.FeatureSectionId(group)
assert(P.HM.GetMissingSectionResolver(ctx.entry)(section))
local config = S.Config("navigationHUD")
assert(not config.enabled and not config.showCompass, "opening the settings activated the HUD")

local function Action(suffix)
    return assert(fixture.registeredControls["menu2.suite_qualityOfLife.navigationHUD.action." .. suffix], suffix)
end
local mode, markerOptions = nil, {}
for _, widget in ipairs(ctx.widgets) do
    local key = widget.meta and widget.meta.settingKey
    if key == "msufsuite.navigationHUD.shortcutMode" then mode = widget end
    local setting = key and key:match("^msufsuite%.navigationHUD%.(.+)$")
    if setting then markerOptions[setting] = widget end
end
assert(mode and mode.rowKind == "dropdown" and mode.get() == 1)
assert(mode.row.values[1].text == "Shift+M (default)" and mode.row.values[2].text == "Custom key binding")
mode.set(2)
assert(mode.get() == 2 and not config.enabled)
assert(markerOptions.showMapMarkers.get() and markerOptions.showKnownGathering.get() and not markerOptions.showGatheringMinimap.get())
assert(not markerOptions.showQuestOffers.get() and not markerOptions.showMapServices.get() and not markerOptions.showNavigationMinimap.get())
markerOptions.showQuestOffers.set(true)
markerOptions.showMapServices.set(true)
markerOptions.showNavigationMinimap.set(true)
assert(config.showQuestOffers and config.showMapServices and config.showNavigationMinimap and not config.enabled)
assert(not markerOptions.showHandyNotes.get() and not markerOptions.showQuestie.get())
markerOptions.showHandyNotes.set(true)
assert(config.showHandyNotes and not config.showQuestie and not config.enabled, "HandyNotes turned on another feature")
markerOptions.showQuestie.set(true)
markerOptions.showHandyNotes.set(false)
assert(not config.showHandyNotes and config.showQuestie and not config.enabled, "the provider switches must operate independently")

markerOptions.showGatheringMinimap.set(true)
markerOptions.showKnownGathering.set(false)
assert(config.showGatheringMinimap and not config.showKnownGathering and not config.enabled,
    "the native minimap option must stay independent of the overlay")
assert(markerOptions.showMarkers.get())
markerOptions.showMarkers.set(false)
assert(not config.showMarkers and config.showGatheringMinimap and not config.showKnownGathering,
    "the master switch must preserve each marker preference")
markerOptions.showMarkers.set(true)

local zone = Action("zoneMap")
assert(zone:IsEnabled() and not zone:GetChecked() and nativeToggles == 0, "native zone map must be independent of the overlay")
zone.set(true)
zone.set(true)
assert(nativeMap == "1" and nativeToggles == 1)
zone.scripts.OnEvent(zone, "CVAR_UPDATE", "showBattlefieldMinimap")
assert(zone:GetChecked())
local combat = P.Combat
P.Combat = function() return true end
zone.set(false)
assert(nativeToggles == 1)
P.Combat = combat
DISALLOW_FRAME_TOGGLING = true
zone.set(false)
assert(nativeToggles == 1)
DISALLOW_FRAME_TOGGLING = nil
zone.set(false)
assert(nativeMap == "0" and nativeToggles == 2)
nativeMap = "1"
zone.scripts.OnEvent(zone, "CVAR_UPDATE", "SHOWBATTLEFIELDMINIMAP")
assert(zone:GetChecked(), "native shortcut or window close must update the options")
nativeMap = nil
zone.scripts.OnEvent(zone, "CVAR_UPDATE", "showBattlefieldMinimap")
assert(not zone:IsEnabled() and not zone:GetChecked())

local shortcut = Action("mapShortcut")
assert(shortcut.mapShortcutLabel:find("No shortcut assigned", 1, true))
key = "ALT-M"
shortcut.scripts.OnEvent()
assert(shortcut.mapShortcutLabel:find(key, 1, true))
shortcut.scripts.OnClick()
assert(opened[1] == 9 and opened[2] == "MSUF Suite", "shortcut button did not open native bindings")

mode.set(1)
status, config.enabled, config.showCompass = "Active", true, true
key, effective = nil, "MSUFSUITE_TOGGLE_MAP_OVERLAY"
for _, refresh in ipairs(ctx.refreshers) do refresh() end
assert(shortcut.mapShortcutLabel:find("SHIFT-M", 1, true), "effective default shortcut is missing from the options")
Action("toggleMap").scripts.OnClick()
assert(toggled, "settings did not reach the native shortcut's action")
Action("moveMap").scripts.OnClick()
assert(selected[1] == "navigationHUD" and selected[2] == "map" and selected[3])
Action("moveCompass").scripts.OnClick()
assert(selected[1] == "navigationHUD" and selected[2] == "compass" and selected[3])
print("PASS discoverable map and compass settings, shortcut modes, native zone map and both edit-mode routes")
