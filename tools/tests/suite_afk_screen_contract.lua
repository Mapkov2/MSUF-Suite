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
function actor:HookScript(event, callback)
    assert(event == "OnModelLoaded")
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
UnitName = function() return "Tester" end
GetZoneText = function() return "Test zone" end
UnitClass = function() return "Mage" end
UnitLevel = function() return 80 end
GetInventoryItemTexture = function(unit, slot)
    assert(unit == "player")
    return 1000 + slot
end
GetInventoryItemLink = function(unit, slot)
    assert(unit == "player")
    if slot == 1 then return "|cff0070dd|Hitem:1|h[Test Helm]|h|r" end
end
ModelSceneUtil = { SetUpCharacterSheetScene = function(scene)
    assert(scene.kind == "ModelScene")
    sceneSetups = sceneSetups + 1
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
    assert(delay == 0 and deferred == nil)
    deferred = callback
end }

local events = {}
local suite = {
    Public = function(value) return value ~= secret end,
    CreateFrame = function(kind, name, parent)
        local frame = Frame(kind)
        frame.parent = parent
        return frame
    end,
    CreateTexture = function(_, ...) return Frame("Texture") end,
    CreateFontString = function(_, ...) return Frame("FontString") end,
    SetFont = function() return true end,
    Install = function(id, module) assert(id == "afkScreen"); installed = module end,
}
local private = { NS = {}, Suite = suite }
assert(loadfile(root .. "/MSUF_Suite_Modules/AFKScreen.lua"))("MSUF_Suite_Modules", private)
local module = assert(installed)
module.active = true
local eventUnits = {}
module.context = { Event = function(_, event, callback, allowCombat, unit)
    assert(allowCombat == true)
    events[event] = callback
    eventUnits[event] = unit
end, RemoveEvent = function(_, event) events[event] = nil end }

module:Enable()
assert(events.PLAYER_FLAGS_CHANGED and events.UNIT_FLAGS
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
assert(module.host.parent == WorldFrame and UIParent.alpha == 0,
    "AFK presentation should remain visible while regular UI fades out")
assert(not Minimap:IsShown(), "native minimap markers should hide while AFK")
assert(math.abs(module.panel.scale - (1200 / 2120) * .8) < .0001,
    "WorldFrame presentation must retain the UIParent visual scale: "
        .. tostring(module.panel.scale))
assert(#module.icons == 18 and module.icons[1].texture == 1001
    and module.icons[17].texture == 1016 and module.icons[18].texture == 1017
    and module.itemNames[1].text == "Test Helm"
    and module.itemNames[2].text == "Neck",
    "equipped items and names should flank the character")
assert(sceneSetups == 1 and cameraStarts == 1 and cameraStops == 0,
    "AFK should set up the model scene and start one camera orbit")
actor.fileID = 12345
actor.onModelLoaded()
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
recheck = deferred
deferred = nil
recheck()
assert(module.host:IsShown() and deferred == nil,
    "deferred check should show AFK when chat lockdown ends")
assert(cameraStarts == 2, "returning to AFK should restart the orbit")
assert(UIParent.alpha == 0, "returning to AFK should fade the UI again")

afk = false
events.UNIT_FLAGS(module, "UNIT_FLAGS", "player")

portraitFails = true
actor.fileID = 0
afk = true
events.PLAYER_ENTERING_WORLD(module, "PLAYER_ENTERING_WORLD")
assert(module.host:IsShown()
    and module.fallback.texture == "Interface\\Icons\\INV_Misc_QuestionMark"
    and module.fallback:IsShown(),
    "portrait failure should keep a visible fallback")
events.PLAYER_LEAVING_WORLD(module, "PLAYER_LEAVING_WORLD")
assert(not module.host:IsShown() and cameraStops == 3,
    "world exit should dismiss the screen and stop camera movement")
assert(UIParent.alpha == .85, "world exit should restore the UI")
afk = true
events.PLAYER_ENTERING_WORLD(module, "PLAYER_ENTERING_WORLD")
module:Disable()
assert(not module.host:IsShown() and cameraStops == 4,
    "disabling should dismiss the screen and stop the camera")
assert(UIParent.alpha == .85, "disabling should restore the UI")
ModelSceneUtil = nil
portraitFails = false
installed = nil
assert(loadfile(root .. "/MSUF_Suite_Modules/AFKScreen.lua"))("MSUF_Suite_Modules", private)
local classic = assert(installed)
classic.active = true
classic.context = module.context
afk = true
classic:Enable()
assert(classic.host:IsShown() and classic.model == nil
    and classic.fallback.portraitUnit == "player"
    and classic.fallback:IsShown(),
    "clients without the ModelScene utility should retain a portrait fallback")
classic:Disable()
assert(UIParent.alpha == .85, "fallback mode should also restore the UI")

ModelSceneUtil = { SetUpCharacterSheetScene = function(scene)
    assert(scene.kind == "ModelScene")
    sceneSetups = sceneSetups + 1
end }
installed = nil
assert(loadfile(root .. "/MSUF_Suite_Modules/AFKScreen.lua"))("MSUF_Suite_Modules", private)
local combatModule = assert(installed)
local combatEvents = {}
combatModule.active = true
combatModule.context = {
    Event = function(_, event, callback, allowCombat)
        assert(allowCombat == true)
        combatEvents[event] = callback
    end,
    RemoveEvent = function(_, event) combatEvents[event] = nil end,
}
combat, afk = true, true
local beforeChecks, beforeScenes, beforeStarts = checks, sceneSetups, cameraStarts
combatModule:Enable()
combatModule:Refresh()
assert(not combatModule.host and checks == beforeChecks
    and sceneSetups == beforeScenes and cameraStarts == beforeStarts,
    "combat during enable and refresh must not query AFK or create a scene")
assert(not combatEvents.PLAYER_FLAGS_CHANGED and not combatEvents.UNIT_FLAGS,
    "AFK status events should not be registered during combat")

combat = false
combatEvents.PLAYER_REGEN_ENABLED(combatModule, "PLAYER_REGEN_ENABLED")
assert(combatModule.host:IsShown() and combatModule.model:IsShown()
    and sceneSetups == beforeScenes + 1 and cameraStarts == beforeStarts + 1,
    "AFK can appear after combat ends")
assert(combatEvents.PLAYER_FLAGS_CHANGED and combatEvents.UNIT_FLAGS,
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
assert(not combatEvents.PLAYER_FLAGS_CHANGED and not combatEvents.UNIT_FLAGS,
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
combat = secret
beforeChecks = checks
combatEvents.UNIT_FLAGS(combatModule, "UNIT_FLAGS", "player")
assert(checks == beforeChecks and not combatModule.host:IsShown()
    and UIParent.alpha == .85,
    "an unreadable combat state must fail closed without querying AFK")
combat = false
combatEvents.PLAYER_REGEN_ENABLED(combatModule, "PLAYER_REGEN_ENABLED")
combatModule:Disable()
assert(UIParent.alpha == .85, "combat lifecycle must leave the UI restored")

installed = nil
assert(loadfile(root .. "/MSUF_Suite_Modules/AFKScreen.lua"))("MSUF_Suite_Modules", private)
local ownerModule = assert(installed)
local ownerEvents = {}
ownerModule.active = true
ownerModule.context = {
    Event = function(_, event, callback) ownerEvents[event] = callback end,
    RemoveEvent = function(_, event) ownerEvents[event] = nil end,
}
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
paired.context = module.context
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
formOnly.context = module.context
formOnly:Enable()
assert(formActor.nativeCalls == 1 and not formOnly.fallback:IsShown(),
    "a form-tagged active actor should be reused for the native model")
formOnly:Disable()
assert(UIParent.alpha == .85, "form previews should restore the UI")

print("Suite AFK screen: native/form models, equipment, camera, secrets, fallback and combat quiescence passed")
