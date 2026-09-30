local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local Suite, loads, frames, combat = {}, 0, {}, false
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
-- Main MSUF (Retail-only) publishes no client model.
MSUF_NS = {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
InCombatLockdown = function() return combat end
Minimap = { SetMaskTexture = function() end }
CreateFrame = function()
    local frame = { events = {} }
    function frame:SetScript(_, callback) self.callback = callback end
    function frame:RegisterEvent(event)
        self.events[event] = true
        self.registrations = (self.registrations or 0) + 1
    end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    frames[#frames + 1] = frame
    return frame
end
local function Instance()
    return {
        Enable = function(self) self.starts = (self.starts or 0) + 1 end,
        Refresh = function(self) self.refreshes = (self.refreshes or 0) + 1 end,
        Disable = function(self) self.stops = (self.stops or 0) + 1 end,
    }
end
local INSTALLED, loaded = { MSUF_Suite_Minimap = "minimap", MSUF_Suite_DataTexts = "dataTexts" }, {}
UnitGUID = function() return "Player-Test" end
C_AddOns = {
    IsAddOnLoaded = function(name) return loaded[name] == true end,
    DoesAddOnExist = function(name) return INSTALLED[name] ~= nil end,
    GetAddOnEnableState = function() return 2 end,
    LoadAddOn = function(name)
        assert(name == "MSUF_Suite_Modules" or INSTALLED[name], name)
        loaded[name] = true
        local controller = Suite.Suite
        if name == "MSUF_Suite_Modules" then
            -- The shared runtime: contexts (Runtime.lua) and movers (EditMode.lua).
            loads = loads + 1
            controller.NewContext = function()
                return { Release = function(self) self.released = true end, RefreshOwnedSkins = function() end }
            end
            controller.RefreshEditMover = function() end
            controller.UnregisterEditElements = function() end
        else
            controller.instances[INSTALLED[name]] = Instance()
        end
        -- Forever can register successfully without returning a loaded flag.
    end,
}
Support.Load(root, "MSUF_Suite", Suite, "Core/Suite.lua")
for _, id in ipairs({ "cursorEffects", "mapLandingShortcuts",
    "combatStatsHUD", "combatPetStatus", "combatMovementCue", "burningRushCue",
    "loadoutReminder", "lootToastFilter", "groupBloodlust", "innervateCue",
    "durabilityAlert", "battleRes" }) do
    local rule = assert(Suite.SuiteCatalog[id].rules.look, id .. " has no style choice")
    assert(rule.choices[1] == "Midnight Blue" and rule.choices[4] == "Clean Modern",
        id .. " has no complete Suite style selection")
    local config = Suite.CopyValue(Suite.Defaults.suite.modules[id])
    assert(Suite.SuiteLooks.ApplyToConfig(id, config, "cleanModern") and config.look == 4,
        id .. " did not follow the Clean Modern factory look")
end
local stats = Suite.CopyValue(Suite.Defaults.suite.modules.combatStatsHUD)
Suite.SuiteLooks.ApplyToConfig("combatStatsHUD", stats, "cleanModern")
assert(stats.backgroundColor == "101010" and stats.accentColor == "e6ecf2",
    "Clean Modern stats strip retained its previous gold palette")
local cursor = Suite.CopyValue(Suite.Defaults.suite.modules.cursorEffects)
Suite.SuiteLooks.ApplyToConfig("cursorEffects", cursor, "foreverGlass")
assert(cursor.look == 3 and cursor.color == "d8b66a",
    "cursor ring did not receive the selected Forever palette")
Suite.Suite.RGB = Suite.RGB
_G.MSUFSuite = Suite
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/Bootstrap.lua"))(
    "MSUF_Suite_QualityOfLife", {})
local paint = {}
function paint:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
Suite.Suite.QoLColor(paint, Suite.Suite.QoLStyle({ look = 4 }).background, .94)
assert(math.abs(paint.color[1] - 16 / 255) < .001 and paint.color[4] == .94,
    "Clean Modern QoL surface did not resolve to neutral graphite")
-- The skin boundary loads right after the controller (no skin is installed).
assert(loadfile(root .. "/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite", Suite)
assert(Suite.Database.Initialize(nil))
local oldHud = { suite = { schema = 1, modules = { objectives = {
    colorStyle = 1, backgroundOpacity = 82,
}, announcements = {
    enabled = true, zone = true, quests = false, achievements = false,
    level = false, scenario = false, duration = 4, scale = 100, x = 0, y = -170,
} } } }
Suite.Suite.Normalize(oldHud)
assert(oldHud.suite.modules.announcements.eventToasts == true
    and oldHud.suite.modules.announcements.quests == true
    and oldHud.suite.modules.announcements.achievements == true
    and oldHud.suite.modules.announcements.anchor == 2
    and oldHud.suite.modules.announcements.y == -170,
    "previous announcements factory profile did not adopt the Blizzard replacement")
assert(oldHud.suite.modules.objectives.backgroundOpacity == 0
    and Suite.Defaults.suite.modules.objectives.backgroundOpacity == 0,
    "tracker factory background must migrate to transparent")
assert(oldHud.suite.modules.objectives.titleSize == 18
    and oldHud.suite.modules.objectives.sectionSize == 14
    and oldHud.suite.modules.objectives.entrySize == 15
    and oldHud.suite.modules.objectives.objectiveSize == 13
    and oldHud.suite.modules.announcements.subtitleSize == 16,
    "previous HUD text sizes did not receive the readable defaults")
local customHud = { suite = { schema = 1, modules = { objectives = {
    colorStyle = 2, backgroundOpacity = 82, titleSize = 20, entrySize = 17,
}, xpBar = { point = 8, x = 30, y = 200 } } } }
Suite.Suite.Normalize(customHud)
assert(customHud.suite.modules.objectives.backgroundOpacity == 82,
    "explicit custom tracker opacity must survive the factory migration")
assert(customHud.suite.modules.objectives.titleSize == 20
    and customHud.suite.modules.objectives.entrySize == 17
    and customHud.suite.modules.xpBar.point == 8
    and customHud.suite.modules.xpBar.y == 200,
    "custom HUD typography or XP placement was overwritten")
for _, oldY in ipairs({ 148, 1040 }) do
    local oldXP = { suite = { schema = 1, modules = { xpBar = {
        point = 8, x = oldY == 1040 and 12 or 0, y = oldY,
    } } } }
    Suite.Suite.Normalize(oldXP)
    assert(oldXP.suite.modules.xpBar.point == 2
        and oldXP.suite.modules.xpBar.x == 0
        and oldXP.suite.modules.xpBar.y == -24,
        "old Suite or Forever XP placement remained at the bottom")
end
assert(Suite.Defaults.suite.modules.announcements.anchor == 1
    and Suite.Defaults.suite.modules.announcements.y == -90
    and Suite.Defaults.suite.modules.objectives.x == -35
    and Suite.Defaults.suite.modules.objectives.y == -290,
    "HUD factory positions must start top center and below the default minimap")
Suite.DB.suite.modules.skyriding = { enabled = false, look = 3 }
Suite.Suite.Normalize(Suite.DB)
assert(Suite.Suite.Config("skyriding").look == 3
    and Suite.Suite.Config("skyriding").panelColor == "14181b"
    and Suite.Suite.Config("skyriding").accentColor == "d8b66a",
    "older Skyriding profiles lost their selected colors")
for _, id in ipairs(Suite.SuiteOrder) do
    assert(Suite.Suite.Config(id).enabled == (id ~= "skyriding" and id ~= "actionTracker"
        and id ~= "durabilityAlert" and id ~= "battleRes" and id ~= "innervateCue"
        and id ~= "merchantLevel" and id ~= "vaultSpec" and id ~= "tooltipIDs"
        and id ~= "itemCounts" and id ~= "loadoutReminder" and id ~= "quietPopups"
        and id ~= "waypoints" and id ~= "dailyComfort" and id ~= "groupDeathAlert" and id ~= "releaseProtection"
        and id ~= "tooltipVisibility" and id ~= "uiErrorFilter"
        and id ~= "groupFinderDoubleClick" and id ~= "groupFinderApplicantSort" and id ~= "mythicKeyShare"
        and id ~= "groupBloodlust" and id ~= "lootContainers"
        and id ~= "cursorEffects"
        and id ~= "combatStatsHUD" and id ~= "delveSolePower"
        and id ~= "mythicResetReminder" and id ~= "combatPetStatus"
        and id ~= "lootVendorRules" and id ~= "mapLandingShortcuts"
        and id ~= "socketGemSuggestions" and id ~= "tooltipSpellCopy"
        and id ~= "macroBuilder" and id ~= "chatProfileLinks"
        and id ~= "tooltipMPlusScore" and id ~= "tooltipClassColors"
        and id ~= "collectionNewMarkers"
        and id ~= "guildChatPrivacy" and id ~= "groupFinderExitReminder"
        and id ~= "groupRaidShortcuts" and id ~= "trainerLearnAll"
        and id ~= "characterUpgradeWindow" and id ~= "lootToastFilter"
        and id ~= "combatMovementCue" and id ~= "professionAppearance"
        and id ~= "trustedPartyInvites" and id ~= "burningRushCue"),
        id .. " factory enable state is wrong")
end
for _, id in ipairs(Suite.SuiteOrder) do Suite.Suite.Config(id).enabled = false end
Suite.Suite.Start()
assert(loads == 0 and #frames == 0, "disabled modules performed startup work")
assert(Suite.Suite.Set("minimap", "enabled", true))
local module = Suite.Suite.instances.minimap
assert(loads == 1 and module.starts == 1 and Suite.Suite.Status("minimap") == "Active")
combat = true
Suite.Suite.Apply("minimap")
Suite.Suite.Apply("minimap")
assert(#frames == 1 and frames[1].registrations == 1 and module.refreshes == nil,
    "combat refresh was not coalesced")
assert(not Suite.Suite.Set("minimap", "enabled", false))
combat = false
frames[1]:callback()
assert(module.refreshes == 1 and not next(frames[1].events))
assert(Suite.Database.Create("Fresh", false))
assert(Suite.Database.Activate("Fresh"))
assert(Suite.Suite.Config("minimap").enabled == true and module.active,
    "new profile did not start with its modules enabled")
assert(Suite.Suite.Config("skyriding").enabled == false,
    "new profile enabled the Retail flight HUD without a user choice")
assert(Suite.Suite.Set("minimap", "enabled", false))
assert(module.stops == 1 and module.context.released and not module.active)
-- A module whose Enable raises is reported, releases what it took at once and
-- shows the failure until one of its settings changes.
module.Enable = function(self) error("deliberate partial activation") end
module.context.released = nil
assert(Suite.Suite.Set("minimap", "enabled", true), "a failing module raised out of the setter")
assert(#reported == 1 and reported[1]:find("deliberate partial activation", 1, true)
    and module.stops == 2 and module.context.released and not module.active
    and not Suite.Suite.states.minimap.active
    and Suite.Suite.Status("minimap") == "Stopped after an error",
    "partial activation was not released or its failure was not recorded")
assert(Suite.Suite.Set("minimap", "enabled", false))
assert(module.stops == 2 and not module.active and Suite.Suite.Status("minimap") == "Off",
    "a failed module was stopped twice or kept its failure after a change")
assert(loads == 1 and type(SlashCmdList.MSUFSUITE) == "function")
-- Setup enables available core modules. Other factory-enabled modules keep
-- their saved switch, and unavailable modules still show their reason.
module.Enable = function(self) self.starts = self.starts + 1 end
local S = Suite.Suite
assert(S.Preset("core"))
assert(S.Config("minimap").enabled and module.active and S.Status("minimap") == "Active")
assert(not S.Config("actionbars").enabled and not S.Config("damageMeter").enabled)
assert(S.Status("actionbars") ~= "Off" and S.Status("actionbars") ~= "Active", "unavailable module lost its reason")
assert(S.Config("qol").enabled and S.Config("quests").enabled and S.Config("loot").enabled
    and S.Config("buffReminders").enabled)
assert(S.Set("qol", "enabled", true) and S.Preset("core") and S.Config("qol").enabled, "setup overrode an opt-in choice")
UnitGUID = function() return "Player-Test" end
local addonDisabled = true
C_AddOns.GetAddOnEnableState = function(name, guid)
    assert(guid == "Player-Test")
    return addonDisabled and name == "MSUF_Suite_Minimap" and 0 or 1
end
S.Apply("minimap")
assert(not module.active and S.Status("minimap"):find("Disabled in Blizzard", 1, true),
    "Blizzard's AddOn checkbox did not stop the loaded module")
addonDisabled = false
S.Apply("minimap")
assert(module.active and S.Status("minimap") == "Active",
    "re-enabled Blizzard AddOn did not restore the module")
assert(S.Preset("off") and not S.Config("minimap").enabled and not S.Config("qol").enabled and not module.active)
assert(not S.Preset("everything"))

-- One failing module neither stops the modules after it nor the skin's
-- surface hand-back, and a combat queue drains completely.
local phases = {}
local surfacesChanged = Suite.Skin.SurfacesChanged
Suite.Skin.SurfacesChanged = function(phase) phases[#phases + 1] = phase end
reported = {}
S.Config("minimap").enabled, S.Config("dataTexts").enabled = true, true
module.Enable = function() error("minimap failed") end
local texts = assert(S.instances.dataTexts)
local textStarts = texts.starts
S.ApplyAll()
assert(#reported == 1 and texts.starts == textStarts + 1 and S.states.dataTexts.active and not module.active
    and S.Status("minimap") == "Stopped after an error",
    "a failing module stopped the modules after it")
module.Enable = function(self) self.starts = self.starts + 1 end
assert(S.Set("minimap", "enabled", true) and module.active)
phases = {}
texts.Refresh = function() error("dataTexts failed") end
S.Apply("dataTexts")
assert(#reported == 2 and phases[1] == "before" and phases[2] == "after" and not texts.active,
    "the skin did not take its surface back after the module failed")
assert(S.Set("dataTexts", "enabled", true) and texts.active)
texts.Refresh = function(self) self.refreshes = (self.refreshes or 0) + 1 end
local queue = frames[1]
combat = true
module.Refresh = function() error("minimap refresh failed") end
S.Apply("minimap")
S.Apply("dataTexts")
assert(queue.events.PLAYER_REGEN_ENABLED and S.Status("dataTexts") == "Waiting for combat to end")
combat = false
local refreshes = texts.refreshes or 0
queue:callback()
assert(#reported == 3 and texts.refreshes == refreshes + 1 and not queue.events.PLAYER_REGEN_ENABLED
    and S.Status("dataTexts") == "Active" and S.Status("minimap") == "Stopped after an error",
    "a failing queued module left the rest of the combat queue behind")
Suite.Skin.SurfacesChanged = surfacesChanged
-- A menu repaint that raises is reported; the applied change still succeeds.
Suite.Options = { RefreshAll = function() error("menu failed") end }
assert(S.Set("dataTexts", "enabled", false) and #reported == 4 and not texts.active,
    "a menu error failed a setting that was already applied")
Suite.Options = nil

-- Stopping a module runs every step isolated: a release that raises is
-- reported, the module stops cleanly and its CVars are still handed back.
local restoredCVars = {}
S.RestoreSaved = function(id) restoredCVars[id] = (restoredCVars[id] or 0) + 1 end
module.Refresh = function(self) self.refreshes = (self.refreshes or 0) + 1 end
assert(S.Set("minimap", "enabled", true) and module.active)
local release = module.context.Release
module.context.Release = function() error("release failed") end
local errors = #reported
assert(S.Set("minimap", "enabled", false))
module.context.Release = release
assert(#reported == errors + 1 and restoredCVars.minimap == 1 and not module.active
    and S.Status("minimap") == "Off", "a raising release kept the module's CVars applied")
S.RestoreSaved = nil

-- Statuses stay English source text like every other status; the menu
-- translates them once, when it shows them (suite_options_menu_contract).
Suite.L["Stopped after an error"] = "Nach einem Fehler gestoppt"
module.Enable = function() error("minimap failed again") end
assert(S.Set("minimap", "enabled", true))
assert(S.Status("minimap") == "Stopped after an error" and not module.active,
    "the failure status was translated before the menu translates it")
Suite.L["Stopped after an error"] = nil
-- A profile switch starts afresh: the failed module is tried again.
module.Enable = function(self) self.starts = self.starts + 1 end
assert(Suite.Database.Create("Retry", true) and Suite.Database.Activate("Retry"))
assert(module.active and S.Status("minimap") == "Active", "a profile switch kept a failed module stopped")

-- Modules queued in combat apply in catalog order, like S.ApplyAll.
local apply, appliedOrder = S.Apply, {}
for i = #S.order, 1, -1 do S.Queue(S.order[i]) end
S.Apply = function(id)
    appliedOrder[#appliedOrder + 1] = id
    return apply(id)
end
queue:callback()
S.Apply = apply
assert(#appliedOrder == #S.order and not queue.events.PLAYER_REGEN_ENABLED, "the combat queue did not drain")
for i, id in ipairs(S.order) do
    assert(appliedOrder[i] == id, "the combat queue applied modules out of catalog order")
end

-- The Bags catalog reads combinedBags through C_CVar like every other file;
-- the global GetCVar/SetCVar are not needed (and not stubbed here).
ContainerFrameCombinedBags = { EnumerateValidItems = function() end, UpdateItems = function() end }
hooksecurefunc = function() end
C_Container = { GetContainerItemInfo = function() end }
C_Item = { GetDetailedItemLevelInfo = function() end, IsEquippableItem = function() end }
local bagMode = "1"
C_CVar = { GetCVar = function(key) assert(key == "combinedBags"); return bagMode end }
GetCVar, SetCVar = nil, nil
local bagsAvailable, bagsReason = S.catalog.bags.available()
assert(bagsAvailable == true, "the Bags catalog needs the global GetCVar: " .. tostring(bagsReason))
bagMode = nil
assert(select(2, S.catalog.bags.available()) == "This client has no combined bag setting")
ContainerFrameCombinedBags, hooksecurefunc, C_Container, C_Item, C_CVar = nil, nil, nil, nil, nil
-- The controller calls only helpers that exist.
for _, file in ipairs({ "MSUF_Suite/Core/Suite.lua", "MSUF_Suite/Integrations/MapkoSkin.lua" }) do
    local source = assert(io.open(root .. "/" .. file, "rb")):read("*a")
    assert(not source:find("CloseMovers", 1, true) and not source:find("RefreshCopySkin", 1, true),
        file .. " still guards a helper nothing defines")
end
print("Standalone suite controller: dormant startup, own loader, combat coalescing, profile switch, error isolation and setup presets passed")
