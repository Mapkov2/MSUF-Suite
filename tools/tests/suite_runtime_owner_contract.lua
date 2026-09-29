local root = assert(arg[1], "repository root required")
local Suite, frames, skinReleases = {}, {}, 0
-- The client's securecallfunction reports an error to the error handler and
-- returns nothing; this harness models exactly that.
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end
-- Classic MSUF (the multi-client build) hosts the Suite on WoW Forever.
MSUF_NS = { Client = {
    Family = "Mainline", Flavor = "Mainline", IsForever = true, IsRetail = true,
    SupportsEvent = function() return true end,
} }
MSUFSuite = Suite
MapkoSkin = setmetatable({}, { __index = function() error("runtime touched the skin provider") end })
SlashCmdList = {}
local pixelVisits = 0
MSUF_PixelLayoutRegion = function(region) pixelVisits = pixelVisits + 1;return region end
CreateFrame = function()
    local frame = { events = {}, registrations = 0, unregistrations = 0 }
    function frame:SetScript(_, callback) self.callback = callback end
    function frame:RegisterEvent(event) self.events[event] = true; self.registrations = self.registrations + 1 end
    function frame:RegisterUnitEvent(event, ...)
        self.events[event] = select("#", ...) > 1 and { ... } or ...
        self.registrations = self.registrations + 1
    end
    function frame:UnregisterEvent(event) self.events[event] = nil; self.unregistrations = self.unregistrations + 1 end
    function frame:UnregisterAllEvents() self.events = {} end
    frames[#frames + 1] = frame
    return frame
end
local cvarValues = { rotateMinimap = "0", combinedBags = "0", autoLootDefault = "0" }
C_CVar = {
    GetCVar = function(key) return cvarValues[key] end,
    SetCVar = function(key, value) cvarValues[key] = tostring(value) end,
}
UnitName = function() return "Tester" end
GetRealmName = function() return "Realm" end
InCombatLockdown = function() return false end
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
Support.Load(root, "MSUF_Suite", Suite, "Core/Suite.lua")
assert(loadfile(root .. "/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite", Suite)
assert(Suite.Database.Initialize(nil))
local private = {}
-- Blizzard builds its shared font objects at startup on every client.
GameFontHighlightSmall = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
Support.Load(root, "MSUF_Suite_Modules", private)
assert(private.NS == Suite and #frames == 0 and pixelVisits == 0)
local shared = 0
for id in pairs(Suite.Suite.instances) do
    assert(id == "afkScreen" or id == "objectives" or id == "runSummary" or id == "announcements",
        "shared runtime registered a module it does not own: " .. id)
    shared = shared + 1
end
assert(shared == 4 and Suite.Suite.MythicPlus == nil, "Forever loaded the Mythic+ view or lost a HUD module")
Support.Load(root, "MSUF_Suite_QualityOfLife", {})
local count = 0
for id in pairs(Suite.Suite.instances) do
    assert(Suite.Suite.catalog[id], "unknown module registration")
    count = count + 1
end
assert(count == 55 and Suite.Suite.instances.actionTracker and Suite.Suite.instances.durabilityAlert and Suite.Suite.instances.battleRes
    and Suite.Suite.instances.innervateCue and Suite.Suite.instances.merchantLevel
    and Suite.Suite.instances.vaultSpec and Suite.Suite.instances.tooltipIDs
    and Suite.Suite.instances.itemCounts and Suite.Suite.instances.loadoutReminder
    and Suite.Suite.instances.quietPopups and Suite.Suite.instances.waypoints
    and Suite.Suite.instances.dailyComfort and Suite.Suite.instances.groupDeathAlert
    and Suite.Suite.instances.tooltipVisibility and Suite.Suite.instances.uiErrorFilter
    and Suite.Suite.instances.groupFinderDoubleClick and Suite.Suite.instances.groupFinderApplicantSort
    and Suite.Suite.instances.mythicKeyShare
    and Suite.Suite.instances.groupBloodlust and Suite.Suite.instances.lootContainers
    and Suite.Suite.instances.lootVendorRules and Suite.Suite.instances.cursorEffects
    and Suite.Suite.instances.mapQuickSwitch and Suite.Suite.instances.combatStatsHUD
    and Suite.Suite.instances.combatPetStatus and Suite.Suite.instances.delveSolePower
    and Suite.Suite.instances.mythicResetReminder and Suite.Suite.instances.mapLandingShortcuts
    and Suite.Suite.instances.socketGemSuggestions and Suite.Suite.instances.tooltipSpellCopy
    and Suite.Suite.instances.macroBuilder and Suite.Suite.instances.chatProfileLinks
    and Suite.Suite.instances.tooltipMPlusScore and Suite.Suite.instances.tooltipClassColors
    and Suite.Suite.instances.collectionNewMarkers
    and Suite.Suite.instances.guildChatPrivacy and Suite.Suite.instances.groupFinderExitReminder
    and Suite.Suite.instances.groupRaidShortcuts and Suite.Suite.instances.trainerLearnAll
    and Suite.Suite.instances.characterUpgradeWindow and Suite.Suite.instances.lootToastFilter
    and Suite.Suite.instances.combatMovementCue and Suite.Suite.instances.professionAppearance
    and Suite.Suite.instances.trustedPartyInvites and Suite.Suite.instances.burningRushCue,
    "shared HUD modules and Quality of Life helpers did not register together")
local context = Suite.Suite.NewContext("qol")
assert(context:Skin() == nil, "disabled skin should require no provider")
local module, events = Suite.Suite.instances.qol, 0
module.active = true
context:Event("TEST_EVENT", function(self, event, value)
    assert(self == module and event == "TEST_EVENT" and value == 42)
    events = events + 1
end)
context.frame:callback("TEST_EVENT", 42)
assert(events == 1 and pixelVisits == 1)
context:Event("TEST_EVENT", function(self, event, value)
    assert(self == module and event == "TEST_EVENT" and value == 42)
    events = events + 1
end, true)
context.frame:callback("TEST_EVENT", 42)
assert(events == 2 and context.frame.registrations == 1 and context.combatEvents.TEST_EVENT,
    "refresh re-registered an unchanged event or lost its updated callback")
context:RemoveEvent("TEST_EVENT")
context:RemoveEvent("TEST_EVENT")
context:Event("UNIT_FLAGS", function() end, true, "player")
assert(context.frame.events.UNIT_FLAGS == "player", "a unit event was registered for every unit")
context:RemoveEvent("UNIT_FLAGS")
assert(context.frame.unregistrations == 2, "removing an absent event repeated a native call")
local native = { scale = 1 }
function native:GetScale() return self.scale end
function native:SetScale(value) self.scale = value end
context:Scale(native, 1.3)
assert(native.scale == 1.3 and pixelVisits == 1, "native parent was claimed by suite layout")
context:Release()
assert(native.scale == 1 and not next(context.frame.events) and not next(context.callbacks))
context:Scale(native, 1.2)
native.scale = 1.5
context:Release()
assert(native.scale == 1.5, "release overwrote a later external change")
-- One RegisterUnitEvent filters at most four units: a longer list (the five
-- boss tokens) is split over routing frames that reach the same callback.
local bossHits = {}
context:Event("UNIT_HEALTH", function(self, event, unit)
    assert(self == module and event == "UNIT_HEALTH")
    bossHits[#bossHits + 1] = unit
end, true, { "boss1", "boss2", "boss3", "boss4", "boss5" })
local overflow = context.unitFrames and context.unitFrames[1]
local firstUnits = context.frame.events.UNIT_HEALTH
assert(type(firstUnits) == "table" and #firstUnits == 4 and firstUnits[1] == "boss1" and firstUnits[4] == "boss4"
    and overflow and overflow.events.UNIT_HEALTH == "boss5",
    "a boss unit list was not split into four-unit registrations")
overflow:callback("UNIT_HEALTH", "boss5")
context.frame:callback("UNIT_HEALTH", "boss2")
assert(bossHits[1] == "boss5" and bossHits[2] == "boss2", "a routing frame did not reach the event callback")
context:RemoveEvent("UNIT_HEALTH")
assert(not context.frame.events.UNIT_HEALTH and not overflow.events.UNIT_HEALTH,
    "removing a unit list left a routing frame registered")
context:Event("UNIT_HEALTH", function() end, true, { "boss1", "boss2", "boss3", "boss4", "boss5" })
assert(context.unitFrames[1] == overflow, "a routing frame was created again instead of reused")
context:Release()
assert(not next(overflow.events), "release left a routing frame registered")
local paints, released = 0, 0
local owned = {}
context:OwnSkin("SkinFrame", owned, { role = "popup" })
assert(paints == 0)
MapkoSkin = { GetAPI = function()
    return { RegisterAddon = function()
        return { SkinFrame = function(_, target) assert(target == owned);paints = paints + 1 end,
            ReleaseAll = function() released = released + 1 end }
    end }
end }
Suite.Skin.SetEnabled(true)
context:RefreshOwnedSkins()
assert(paints == 1)
Suite.Skin.SetEnabled(false)
assert(released == 1)
Suite.Skin.SetEnabled(true)
context:RefreshOwnedSkins()
assert(paints == 2, "previously created popup lost its skin after toggling")
context:Release()
context:RefreshOwnedSkins()
assert(paints == 3 and released == 2, "module reactivation lost owned popup styling")
-- MapkoSkin is another addon: each owned-skin call is isolated, so its error
-- is reported, the other owned frames are still painted and the module's
-- Enable or Refresh (which calls these) is never failed by it.
local skinErrors, broken = #reported, {}
local skinning = Suite.Suite.NewContext("qol")
skinning:OwnSkin("SkinFrame", owned, { role = "popup" })
local ownedSkinCompleted = pcall(skinning.OwnSkin, skinning, "SkinBroken", broken, {})
local refreshCompleted = pcall(skinning.RefreshOwnedSkins, skinning)
assert(ownedSkinCompleted and refreshCompleted and #reported == skinErrors + 2 and paints == 5,
    "a MapkoSkin error escaped into the module or skipped another owned frame")

-- CVar ownership: a context sets only CVars its module declares, and a saved
-- record is dropped only once it is resolved.
local S = Suite.Suite
local function Saved(id, key)
    local recovery = Suite.RootDB.suiteRecovery and Suite.RootDB.suiteRecovery["Realm/Tester"]
    return recovery and recovery[id] and recovery[id][key]
end
local minimap = S.NewContext("minimap")
assert(S.instances.minimap == nil and not minimap:CVar("autoLootDefault", 1)
    and cvarValues.autoLootDefault == "0" and not Saved("minimap", "autoLootDefault"),
    "a context set a CVar its module never declared")
assert(minimap:CVar("rotateMinimap", 1) and cvarValues.rotateMinimap == "1" and Saved("minimap", "rotateMinimap"))
-- The module addon is not loaded: its catalog entry still hands the CVar back.
S.RestoreSaved("minimap")
assert(cvarValues.rotateMinimap == "0" and not Saved("minimap", "rotateMinimap"),
    "a saved CVar was dropped without being restored while its addon was not loaded")
-- An unreadable value keeps the record for a later attempt.
assert(minimap:CVar("rotateMinimap", 1))
cvarValues.rotateMinimap = nil
S.RestoreCVar("minimap", "rotateMinimap")
assert(Saved("minimap", "rotateMinimap"), "an unrestored CVar record was dropped")
cvarValues.rotateMinimap = "1"
S.RestoreCVar("minimap", "rotateMinimap")
assert(cvarValues.rotateMinimap == "0" and not Saved("minimap", "rotateMinimap"))
-- A later change by the player resolves the record without overwriting it.
assert(minimap:CVar("rotateMinimap", 1))
cvarValues.rotateMinimap = "0"
minimap:Release()
assert(cvarValues.rotateMinimap == "0" and not Saved("minimap", "rotateMinimap"))
-- Records of CVars no loaded code declares are kept for their owner.
Suite.RootDB.suiteRecovery = { ["Realm/Tester"] = { bags = {
    combinedBags = { before = "0", applied = "1" }, unknownCVar = { before = "0", applied = "1" },
} } }
cvarValues.combinedBags = "1"
S.RestoreSaved("bags")
assert(cvarValues.combinedBags == "0" and not Saved("bags", "combinedBags") and Saved("bags", "unknownCVar"),
    "the Bags catalog did not own combinedBags or an unknown record was dropped")
local bagsModule = { cvars = { unknownCVar = true } }
S.instances.bags = bagsModule
cvarValues.unknownCVar = "1"
S.RestoreSaved("bags")
S.instances.bags = nil
assert(cvarValues.unknownCVar == "0" and Suite.RootDB.suiteRecovery["Realm/Tester"] == nil,
    "a module-level cvars declaration did not restore its record")
-- An error in the skin engine during release is reported; the CVars are
-- still handed back.
local skinRelease, errors = Suite.Skin.Release, #reported
Suite.Skin.Release = function() error("skin release failed") end
assert(minimap:CVar("rotateMinimap", 1) and cvarValues.rotateMinimap == "1")
minimap:Release()
Suite.Skin.Release = skinRelease
assert(#reported == errors + 1 and cvarValues.rotateMinimap == "0" and not Saved("minimap", "rotateMinimap"),
    "a skin error during release kept a module CVar applied")

-- Every frame is released on its own: a module field refresh or a native
-- setter that raises is reported, the other frames are still restored and
-- the CVars are handed back. A restore that raised stays for the next release.
local function ScaleFrame(failRestore)
    local frame = { scale = 1 }
    function frame:GetScale() return self.scale end
    function frame:SetScale(value)
        if failRestore and value == 1 then error("setter failed") end
        self.scale = value
    end
    return frame
end
local release = S.NewContext("minimap")
local flagged = { flag = false }
release:Field(flagged, "flag", true, function() error("field refresh failed") end)
local stuck, scaled = ScaleFrame(true), ScaleFrame(false)
release:Scale(stuck, 2)
release:Scale(scaled, 1.5)
assert(release:CVar("rotateMinimap", 1) and flagged.flag == true and scaled.scale == 1.5)
errors = #reported
-- The controller releases through Dispatch (MSUF_Suite/Core/Suite.lua Stop).
Suite.Dispatch(release.Release, release)
assert(#reported == errors + 2 and flagged.flag == false and scaled.scale == 1 and stuck.scale == 2
    and cvarValues.rotateMinimap == "0" and not Saved("minimap", "rotateMinimap")
    and release.properties[stuck] and not release.properties[scaled] and not release.fields[flagged],
    "one raising restore skipped the other frames or kept a CVar applied")
-- Isolation is per record: whichever setter of one frame raises first, the
-- frame's other setters are still restored, and only the raising record
-- stays for the next release.
local twice = { scale = 1, alpha = 1, failures = 1 }
local function Fail(self)
    if self.failures > 0 then
        self.failures = self.failures - 1
        error("first restore failed")
    end
end
function twice:GetScale() return self.scale end
function twice:SetScale(value) if value == 1 then Fail(self) end self.scale = value end
function twice:GetAlpha() return self.alpha end
function twice:SetAlpha(value) if value == 1 then Fail(self) end self.alpha = value end
local perRecord = S.NewContext("minimap")
perRecord:Scale(twice, 2)
perRecord:Alpha(twice, 0.5)
errors = #reported
Suite.Dispatch(perRecord.Release, perRecord)
local kept = perRecord.properties[twice]
local restored = (twice.scale == 1 and 1 or 0) + (twice.alpha == 1 and 1 or 0)
local keptCount = 0
for _ in pairs(kept or {}) do keptCount = keptCount + 1 end
assert(#reported == errors + 1 and restored == 1 and keptCount == 1,
    "one raising setter skipped the frame's other setters or dropped its own record")
perRecord:Release()
assert(twice.scale == 1 and twice.alpha == 1 and not perRecord.properties[twice],
    "the record kept after a raising restore was not restored by the next release")

-- Blizzard may change a value we own (the chat menu resizes a font we set).
-- UpdateTupleBefore adopts that change as the value to restore, so modules
-- never reach into the context's private tuple records.
local label = { font = { "Base.ttf", 12, "" } }
function label:GetFont() return unpack(self.font) end
function label:SetFont(path, size, flags) self.font = { path, size, flags } end
local fonts = S.NewContext("chat")
assert(fonts:UpdateTupleBefore(label, "SetFont", 2, 12) == false, "an unowned tuple reported an original")
fonts:Tuple(label, "GetFont", "SetFont", "Suite.ttf", 14, "OUTLINE")
label.font[2] = 16
local owned, path, size, flags = fonts:UpdateTupleBefore(label, "SetFont", 2, 16)
assert(owned and path == "Base.ttf" and size == 16 and flags == "", "Blizzard's new size was not adopted")
owned, path, size = fonts:UpdateTupleBefore(label, "SetFont", 2, 14)
assert(owned and size == 16, "our own applied size replaced the original")
fonts:Tuple(label, "GetFont", "SetFont", "Suite.ttf", 14, "OUTLINE")
fonts:Release()
assert(label.font[1] == "Base.ttf" and label.font[2] == 16, "release did not return to Blizzard's adopted size")

-- Data ticks share one timer. A tick that raises is reported; the other ticks
-- of that round still run and the timer is armed again.
local timers, now, ran = {}, 100, {}
GetTime = function() return now end
C_Timer = { NewTimer = function(delay, callback)
    local timer = { delay = delay, callback = callback }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end }
S.ScheduleDataTick("failing", 1, function() error("tick failed") end)
S.ScheduleDataTick("working", 1, function() ran[#ran + 1] = "working" end)
local round = assert(timers[#timers])
now = 101
errors = #reported
round.callback()
assert(#reported == errors + 1 and ran[1] == "working", "a failing data tick stopped the other ticks")
S.ScheduleDataTick("later", 1, function() ran[#ran + 1] = "later" end)
local rearmed = timers[#timers]
assert(rearmed ~= round and not rearmed.cancelled, "a failing data tick left the shared timer disarmed")
now = 102
rearmed.callback()
assert(ran[2] == "later", "data ticks stayed frozen after a failing tick")
-- Blizzard's localized global string wins; the English text is the fallback.
SUITE_TEST_LABEL = "Minikarte"
assert(S.BlizzardText("SUITE_TEST_LABEL", "Minimap") == "Minikarte"
    and S.BlizzardText("SUITE_MISSING_LABEL", "Minimap") == "Minimap"
    and S.RGB == Suite.RGB and S.ResolveFont == Suite.ResolveFont,
    "the runtime lost a shared text, color or media helper")
SUITE_TEST_LABEL = nil
print("Standalone runtime: shared HUD modules and " .. (count - 3)
    .. " Quality of Life helpers register without skin or frames; event and property cleanup passed")
