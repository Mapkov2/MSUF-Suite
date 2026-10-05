local root = assert(arg[1], "repository root required")
local secret = {}
local afk, portraitFails, checks = false, false, 0
local combat = false
InCombatLockdown = function() return combat end
local cameraStarts, cameraStops, sceneSetups = 0, 0, 0
local actor = { fileID = 0 }
function actor:GetModelFileID() return self.fileID end
function actor:SetModelByUnit(unit, sheathe, dress, hideWeapons, native)
    assert(unit == "player" and sheathe and dress and hideWeapons == false and native)
    self.nativeCalls = (self.nativeCalls or 0) + 1
end
function actor:UseUnitSheatheCategory(value) assert(value == true) end
function actor:SetOnModelLoadedCallback(callback)
    self.onModelLoaded = callback
end
local deferred
local installed
local formMode
local formActor = { fileID = 0 }
for key, value in pairs(actor) do
    if type(value) == "function" then formActor[key] = value end
end
function formActor:ClearModel() self.cleared = (self.cleared or 0) + 1 end
ANIMAL_FORMS = { [1] = { actorTag = "flight" } }
GetShapeshiftFormID = function() return formMode and 1 or nil end

local function Frame(kind)
    local frame = { kind = kind, shown = true, effectiveScale = 1 }
    if kind == "ModelScene" then
        function frame:GetPlayerActor(tag)
            if tag == "flight" then return formMode and formActor or nil end
            if formMode == "only" then return nil end
            return actor
        end
        function frame:EnumerateActiveActors()
            return next, { [formActor] = true }, nil
        end
    end
    function frame:CreateTexture() return Frame("Texture") end
    function frame:CreateFontString() return Frame("FontString") end
    function frame:Hide() self.shown = false end
    function frame:Show() self.shown = true end
    function frame:IsShown() return self.shown end
    function frame:SetShown(value) self.shown = value == true end
    function frame:SetTexture(path) self.texture = path end
    function frame:SetText(value) self.text = value end
    function frame:SetTextColor(r, g, b) self.color = { r, g, b } end
    function frame:GetEffectiveScale() return self.effectiveScale or 1 end
    function frame:SetScale(value) self.scale = value end
    return setmetatable(frame, { __index = function() return function() end end })
end

UIParent = Frame("UIParent")
UIParent.GetWidth = function() return 1200 end
UIParent.GetHeight = function() return 750 end
UIParent.effectiveScale = .8
UIParent.alpha = .85
UIParent.GetAlpha = function(self) return self.alpha end
UIParent.SetAlpha = function(self, value) self.alpha = value end
WorldFrame = Frame("WorldFrame")
Minimap = Frame("Minimap")
local firstName, surname = "Tester", nil
UnitName = function() return firstName, surname end
GetZoneText = function() return "Test zone" end
UnitClass = function() return "Mage" end
UnitLevel = function() return 80 end
GetInventoryItemTexture = function(unit, slot)
    assert(unit == "player")
    return 1000 + slot
end
-- 12.x item links carry the named quality token |cnIQ<quality>: (live and
-- forever ColorManager.lua), never |cffRRGGBB.
GetInventoryItemLink = function(unit, slot)
    assert(unit == "player")
    if slot == 1 then return "|cnIQ3:|Hitem:1::::::::80:::::|h[Test Helm]|h|r" end
end
GetInventoryItemQuality = function(unit, slot)
    assert(unit == "player")
    if slot == 1 then return 3 end
end
-- Blizzard_Colors fills it from the quality colors, overrides included.
ITEM_QUALITY_COLORS = { [3] = { r = 0, g = 0.44, b = 0.87 } }
ModelSceneUtil = { SetUpCharacterSheetScene = function(scene)
    assert(scene.kind == "ModelScene")
    sceneSetups = sceneSetups + 1
    -- Blizzard releases scene actors and clears their load callbacks here.
    actor.onModelLoaded = nil
    formActor.onModelLoaded = nil
end }
MoveViewLeftStart = function(speed)
    assert(speed > 0 and speed < .1)
    cameraStarts = cameraStarts + 1
end
MoveViewLeftStop = function() cameraStops = cameraStops + 1 end
SetPortraitTexture = function(texture, unit)
    assert(unit == "player")
    -- A missing portrait leaves the texture unchanged (the API has no result).
    if portraitFails then return end
    texture.portraitUnit = unit
end
UnitIsAFK = function(unit)
    assert(unit == "player")
    checks = checks + 1
    return afk
end
C_Timer = { After = function(delay, callback)
    assert(delay == .1 and deferred == nil)
    deferred = callback
end }

local events = {}
-- A distinct media path proves the screen reads MSUF's shared font constant.
local SUITE_FONT = "Interface\\AddOns\\Test\\SuiteFont.ttf"
local suite = {
    GlobalFontPath = function() return SUITE_FONT end,
    Public = function(value) return value ~= secret end,
    CreateFrame = function(kind, name, parent)
        local frame = Frame(kind)
        frame.parent = parent
        return frame
    end,
    CreateTexture = function(_, ...) return Frame("Texture") end,
    CreateFontString = function(_, ...) return Frame("FontString") end,
    SetFont = function(label, path) label.fontPath = path or SUITE_FONT; return true end,
    Install = function(id, module) assert(id == "afkScreen"); installed = module end,
    -- The translation lookup (Platform.lua) and Blizzard's global strings
    -- with that fallback (Surfaces.lua).
    Text = function(text) return text end,
    BlizzardText = function(global, english)
        local value = global and _G[global]
        if type(value) == "string" and value ~= "" then return value end
        return english
    end,
}
-- A client-localized slot name from GlobalStrings.
SHOULDERSLOT = "Schulter"
-- Shared readers as defined by MSUF_Suite/Core/Platform.lua (aliased by Runtime.lua).
function suite.PublicText(value)
    return suite.Public(value) and type(value) == "string" and value ~= "" and value or nil
end
function suite.Number(value)
    return suite.Public(value) and type(value) == "number" and value == value
end
local NS = { MSUFMedia = { font = SUITE_FONT }, Client = { isForever = false },
    Dispatch = function(callback, ...) return callback(...) end }
function NS.IsCombatLocked() return InCombatLockdown() == true end
-- The shipped context timers on each module's stub context.
local TimerContext = dofile(root .. "/tools/tests/suite_test_support.lua").ModuleTimers(root, suite, NS)
local InCombatOption = dofile(root .. "/tools/tests/suite_test_support.lua").InCombatOption
local private = { NS = NS, Suite = suite }
assert(loadfile(root .. "/MSUF_Suite_Modules/AFKScreen.lua"))("MSUF_Suite_Modules", private)
local module = assert(installed)
module.active = true
local eventUnits = {}
module.context = TimerContext("afkScreen", module, { Event = function(_, event, callback, allowCombat, unit)
    assert(InCombatOption(allowCombat))
    events[event] = callback
    eventUnits[event] = unit
end, RemoveEvent = function(_, event) events[event] = nil end })

module:Enable()
assert(events.PLAYER_FLAGS_CHANGED and events.UNIT_FLAGS and events.PLAYER_STARTED_MOVING
    and events.PLAYER_ENTERING_WORLD and events.PLAYER_LEAVING_WORLD
    and events.PLAYER_REGEN_DISABLED and events.PLAYER_REGEN_ENABLED)
assert(not module.host and checks == 1, "inactive players should allocate no screen")
assert(eventUnits.UNIT_FLAGS == "player" and eventUnits.PLAYER_FLAGS_CHANGED == nil,
    "UNIT_FLAGS must be registered for the player only")

afk = true
events.PLAYER_FLAGS_CHANGED(module, "PLAYER_FLAGS_CHANGED", "party1")
assert(checks == 1, "another unit should not trigger the screen")
events.PLAYER_FLAGS_CHANGED(module, "PLAYER_FLAGS_CHANGED", "player")
assert(module.host:IsShown() and module.model and module.fallback.portraitUnit == "player"
    and module.name.text == "Tester" and module.class.text == "LEVEL 80  /  Mage",
    "AFK should show the character sheet and player details: "
        .. tostring(module.model and module.model.kind) .. ", "
        .. tostring(module.fallback.portraitUnit) .. ", "
        .. tostring(module.name.text) .. ", " .. tostring(module.class.text))
assert(module.name.fontPath == SUITE_FONT, "AFK text must use MSUF's shared font")
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
NS.Client.isForever, firstName, surname = true, "Torven", "Steinweg"
events.UNIT_FLAGS(module, "UNIT_FLAGS", "player")
assert(module.name.text == "Tester", "the active AFK screen should not be rebuilt on status events")
assert(module.host.parent == WorldFrame and UIParent.alpha == 0,
    "AFK presentation should remain visible while regular UI fades out")
assert(not Minimap:IsShown(), "native minimap markers should hide while AFK")
assert(math.abs(module.panel.scale - (1200 / 2120) * .8) < .0001,
    "WorldFrame presentation must retain the UIParent visual scale: "
        .. tostring(module.panel.scale))
assert(#module.icons == 18 and module.icons[1].texture == 1001
    and module.icons[17].texture == 1016 and module.icons[18].texture == 1017
    and module.itemNames[1].text == "Test Helm" and module.captions[1].text == "Head"
    and module.itemNames[2].text == "Neck" and module.itemNames[3].text == "Schulter",
    "equipped items and names should flank the character, with Blizzard's slot names")
local helmColor = module.itemNames[1].color
assert(helmColor[1] == 0 and helmColor[2] == 0.44 and helmColor[3] == 0.87,
    "an equipped item's name lost its quality color: " .. table.concat(helmColor, " "))
assert(sceneSetups == 1 and cameraStarts == 1 and cameraStops == 0,
    "AFK should set up the model scene and start one camera orbit")
actor.fileID = 12345
assert(type(actor.onModelLoaded) == "function", "actor load callback must use the ModelSceneActor API")
actor.onModelLoaded(actor)
assert(not module.fallback:IsShown() and not module.fallbackNote:IsShown(),
    "loaded 3D actor should replace the portrait fallback")
assert(actor.nativeCalls == 1, "the AFK scene should request the equipped native model")
events.UNIT_FLAGS(module, "UNIT_FLAGS", "player")
assert(cameraStarts == 1, "repeated status events must not restart the camera")

afk = secret
events.UNIT_FLAGS(module, "UNIT_FLAGS", "player")
assert(module.host:IsShown(), "secret AFK state must preserve the last known state")
assert(deferred, "secret state should receive one check after the chat event")
local before = checks
events.PLAYER_FLAGS_CHANGED(module, "PLAYER_FLAGS_CHANGED", secret)
assert(checks == before + 1 and deferred,
    "secret event unit should trigger a safe player recheck")

afk = false
local recheck = deferred
deferred = nil
recheck()
assert(not module.host:IsShown(), "deferred check should dismiss a cleared AFK state")
assert(cameraStops == 1, "leaving AFK should stop the camera")
assert(UIParent.alpha == .85, "leaving AFK should restore the previous UI alpha")
assert(Minimap:IsShown(), "leaving AFK should restore the minimap")
events.UNIT_FLAGS(module, "UNIT_FLAGS", "player")
assert(not module.host:IsShown(), "returning from AFK should dismiss the screen")

afk = secret
events.PLAYER_FLAGS_CHANGED(module, "PLAYER_FLAGS_CHANGED", "player")
assert(deferred, "a slash-command event with a secret value needs one deferred check")
afk = true
actor.fileID = 0
recheck = deferred
deferred = nil
recheck()
assert(module.host:IsShown() and deferred == nil,
    "deferred check should show AFK when chat lockdown ends")
assert(module.name.text == "Torven Steinweg", "Forever AFK should show both name parts")
assert(cameraStarts == 2, "returning to AFK should restart the orbit")
assert(UIParent.alpha == 0, "returning to AFK should fade the UI again")
assert(module.fallback:IsShown() and type(actor.onModelLoaded) == "function",
    "a released and reacquired actor must receive a new load callback")
actor.fileID = 12345
actor.onModelLoaded(actor)
assert(not module.fallback:IsShown(), "a reloaded actor should replace the portrait fallback")

afk = false
events.UNIT_FLAGS(module, "UNIT_FLAGS", "player")

portraitFails = true
actor.fileID = 0
surname = secret
afk = true
events.PLAYER_ENTERING_WORLD(module, "PLAYER_ENTERING_WORLD")
assert(module.name.text == "Torven", "secret surname should leave the public first name readable")
assert(module.host:IsShown()
    and module.fallback.texture == "Interface\\Icons\\INV_Misc_QuestionMark"
    and module.fallback:IsShown(),
    "portrait failure should keep a visible fallback")
events.PLAYER_LEAVING_WORLD(module, "PLAYER_LEAVING_WORLD")
assert(not module.host:IsShown() and cameraStops == 3,
    "world exit should dismiss the screen and stop camera movement")
assert(UIParent.alpha == .85, "world exit should restore the UI")
afk = true
firstName, surname = "Torven Steinweg", "Steinweg"
events.PLAYER_ENTERING_WORLD(module, "PLAYER_ENTERING_WORLD")
assert(module.name.text == "Torven Steinweg", "merged Forever name should not repeat the surname")
module:Disable()
assert(not module.host:IsShown() and cameraStops == 4,
    "disabling should dismiss the screen and stop the camera")
assert(UIParent.alpha == .85, "disabling should restore the UI")
portraitFails = false
installed = nil
assert(loadfile(root .. "/MSUF_Suite_Modules/AFKScreen.lua"))("MSUF_Suite_Modules", private)
local combatModule = assert(installed)
local combatEvents = {}
combatModule.active = true
combatModule.context = TimerContext("afkScreen", combatModule, {
    Event = function(_, event, callback, allowCombat)
        assert(InCombatOption(allowCombat))
        combatEvents[event] = callback
    end,
    RemoveEvent = function(_, event) combatEvents[event] = nil end,
})
combat, afk = true, true
local beforeChecks, beforeScenes, beforeStarts = checks, sceneSetups, cameraStarts
combatModule:Enable()
combatModule:Refresh()
assert(not combatModule.host and checks == beforeChecks
    and sceneSetups == beforeScenes and cameraStarts == beforeStarts,
    "combat during enable and refresh must not query AFK or create a scene")
assert(not combatEvents.PLAYER_FLAGS_CHANGED and not combatEvents.UNIT_FLAGS
    and not combatEvents.PLAYER_STARTED_MOVING,
    "AFK status events should not be registered during combat")

combat = false
combatEvents.PLAYER_REGEN_ENABLED(combatModule, "PLAYER_REGEN_ENABLED")
assert(combatModule.host:IsShown() and combatModule.model:IsShown()
    and sceneSetups == beforeScenes + 1 and cameraStarts == beforeStarts + 1,
    "AFK can appear after combat ends")
assert(combatEvents.PLAYER_FLAGS_CHANGED and combatEvents.UNIT_FLAGS
    and combatEvents.PLAYER_STARTED_MOVING,
    "AFK status events should resume after combat")

afk = secret
combatEvents.UNIT_FLAGS(combatModule, "UNIT_FLAGS", "player")
assert(deferred, "secret status should have one pending recheck")
combat = true
combatEvents.PLAYER_REGEN_DISABLED(combatModule, "PLAYER_REGEN_DISABLED")
assert(not combatModule.host:IsShown() and not combatModule.model:IsShown()
    and UIParent.alpha == .85 and Minimap:IsShown()
    and not combatModule.cameraSpinning,
    "combat start must hide the model, stop the camera and restore the UI/minimap")
assert(not combatEvents.PLAYER_FLAGS_CHANGED and not combatEvents.UNIT_FLAGS
    and not combatEvents.PLAYER_STARTED_MOVING,
    "combat should unregister frequent AFK status events")
beforeChecks = checks
local pending = deferred
deferred = nil
pending()
combatModule:Refresh()
assert(checks == beforeChecks and sceneSetups == beforeScenes + 1,
    "pending rechecks and refresh must do no AFK or scene work in combat")

combat, afk = false, false
combatEvents.PLAYER_REGEN_ENABLED(combatModule, "PLAYER_REGEN_ENABLED")
assert(not combatModule.host:IsShown() and combatEvents.PLAYER_FLAGS_CHANGED,
    "post-combat state should resume without showing a non-AFK player")
afk = true
combatEvents.PLAYER_FLAGS_CHANGED(combatModule, "PLAYER_FLAGS_CHANGED", "player")
assert(combatModule.host:IsShown(), "AFK should work again after combat")
-- Combat that starts before PLAYER_REGEN_DISABLED arrives closes the scene
-- on the next status event without querying AFK (InCombatLockdown is never
-- secret: Blizzard's secure code tests it directly).
combat = true
beforeChecks = checks
combatEvents.UNIT_FLAGS(combatModule, "UNIT_FLAGS", "player")
assert(checks == beforeChecks and not combatModule.host:IsShown()
    and UIParent.alpha == .85,
    "combat must close the scene without querying AFK")
combat = false
combatEvents.PLAYER_REGEN_ENABLED(combatModule, "PLAYER_REGEN_ENABLED")
combatModule:Disable()
assert(UIParent.alpha == .85, "combat lifecycle must leave the UI restored")

installed = nil
assert(loadfile(root .. "/MSUF_Suite_Modules/AFKScreen.lua"))("MSUF_Suite_Modules", private)
local ownerModule = assert(installed)
local ownerEvents = {}
ownerModule.active = true
ownerModule.context = TimerContext("afkScreen", ownerModule, {
    Event = function(_, event, callback) ownerEvents[event] = callback end,
    RemoveEvent = function(_, event) ownerEvents[event] = nil end,
})
afk = true
ownerModule:Enable()
assert(UIParent.alpha == 0, "AFK should fade the UI")
UIParent.alpha = .35
Minimap:Show()
afk = false
ownerEvents.PLAYER_FLAGS_CHANGED(ownerModule, "PLAYER_FLAGS_CHANGED", "player")
assert(UIParent.alpha == .35 and Minimap:IsShown(),
    "AFK exit must preserve newer UI or minimap visibility set by another addon")
ownerModule:Disable()
UIParent.alpha = .85

formMode, afk, actor.fileID, formActor.fileID = "paired", true, 12345, 0
installed = nil
assert(loadfile(root .. "/MSUF_Suite_Modules/AFKScreen.lua"))("MSUF_Suite_Modules", private)
local paired = assert(installed)
paired.active = true
paired.context = TimerContext("afkScreen", paired,
    { Event = module.context.Event, RemoveEvent = module.context.RemoveEvent })
paired:Enable()
assert(formActor.cleared == 1 and actor.nativeCalls >= 2
    and not paired.fallback:IsShown(),
    "a separate animal-form actor should be cleared while the equipped model is shown")
paired:Disable()

formMode, formActor.fileID = "only", 23456
installed = nil
assert(loadfile(root .. "/MSUF_Suite_Modules/AFKScreen.lua"))("MSUF_Suite_Modules", private)
local formOnly = assert(installed)
formOnly.active = true
formOnly.context = TimerContext("afkScreen", formOnly,
    { Event = module.context.Event, RemoveEvent = module.context.RemoveEvent })
formOnly:Enable()
assert(formActor.nativeCalls == 1 and not formOnly.fallback:IsShown(),
    "a form-tagged active actor should be reused for the native model")
formOnly:Disable()
assert(UIParent.alpha == .85, "form previews should restore the UI")

installed = nil
assert(loadfile(root .. "/MSUF_Suite_Modules/AFKScreen.lua"))("MSUF_Suite_Modules", private)
local exitModule = assert(installed)
local exitEvents = {}
exitModule.active = true
exitModule.context = TimerContext("afkScreen", exitModule, {
    Event = function(_, event, callback) exitEvents[event] = callback end,
    RemoveEvent = function(_, event) exitEvents[event] = nil end,
})
afk = true
exitModule:Enable()
assert(exitModule.host:IsShown(), "AFK exit scenario should start with a visible screen")
afk = secret
exitEvents.UNIT_FLAGS(exitModule, "UNIT_FLAGS", "player")
assert(deferred and exitModule.host:IsShown(), "a secret AFK read should get one grace recheck")
local unknownRecheck = deferred
deferred = nil
unknownRecheck()
assert(not exitModule.host:IsShown() and UIParent.alpha == .85 and Minimap:IsShown()
    and not exitModule.cameraSpinning,
    "an unreadable AFK state after the grace check must restore the UI")

afk = true
exitEvents.PLAYER_FLAGS_CHANGED(exitModule, "PLAYER_FLAGS_CHANGED", "player")
assert(exitModule.host:IsShown(), "a later public AFK event may reopen the screen")
afk = secret
exitEvents.UNIT_FLAGS(exitModule, "UNIT_FLAGS", "player")
local staleRecheck = assert(deferred)
deferred = nil
local checksBeforeMove = checks
exitEvents.PLAYER_STARTED_MOVING(exitModule, "PLAYER_STARTED_MOVING")
assert(not exitModule.host:IsShown() and UIParent.alpha == .85 and Minimap:IsShown()
    and not exitModule.cameraSpinning and not exitModule.recheckJob.pending,
    "movement must dismiss the screen immediately, even while AFK is secret")
staleRecheck()
assert(checks == checksBeforeMove and not exitModule.host:IsShown(),
    "a cancelled secret-state callback must not reopen the screen")
afk = false
exitEvents.PLAYER_FLAGS_CHANGED(exitModule, "PLAYER_FLAGS_CHANGED", "player")
afk = secret
exitEvents.UNIT_FLAGS(exitModule, "UNIT_FLAGS", "player")
local hiddenRecheck = assert(deferred)
deferred = nil
exitEvents.PLAYER_STARTED_MOVING(exitModule, "PLAYER_STARTED_MOVING")
afk = true
checksBeforeMove = checks
hiddenRecheck()
assert(checks == checksBeforeMove and not exitModule.host:IsShown(),
    "movement must also cancel an unknown-state check before the screen appears")
afk = false
exitEvents.PLAYER_FLAGS_CHANGED(exitModule, "PLAYER_FLAGS_CHANGED", "player")
-- A dungeon queue popup or a ready check needs the UI: the AFK screen closes
-- and stays closed until the player is back from AFK.
assert(exitEvents.LFG_PROPOSAL_SHOW and exitEvents.READY_CHECK, "the AFK screen ignores queue popups and ready checks")
for _, event in ipairs({ "LFG_PROPOSAL_SHOW", "READY_CHECK" }) do
    afk = true
    exitEvents.UNIT_FLAGS(exitModule, "UNIT_FLAGS", "player")
    assert(exitModule.host:IsShown(), "the AFK screen did not show before " .. event)
    exitEvents[event](exitModule, event)
    assert(not exitModule.host:IsShown() and UIParent.alpha == .85 and Minimap:IsShown(),
        event .. " left the UI faded behind the AFK screen")
    exitEvents.PLAYER_FLAGS_CHANGED(exitModule, "PLAYER_FLAGS_CHANGED", "player")
    assert(not exitModule.host:IsShown(), "a status event reopened the AFK screen over " .. event)
    afk = false
    exitEvents.PLAYER_FLAGS_CHANGED(exitModule, "PLAYER_FLAGS_CHANGED", "player")
end
afk = true
exitEvents.PLAYER_FLAGS_CHANGED(exitModule, "PLAYER_FLAGS_CHANGED", "player")
assert(exitModule.host:IsShown(), "a new AFK period did not show the screen again")
afk = false
exitEvents.PLAYER_FLAGS_CHANGED(exitModule, "PLAYER_FLAGS_CHANGED", "player")
exitModule:Disable()

print("Suite AFK screen: native/form models, equipment, camera, secrets, fallback and combat quiescence passed")
