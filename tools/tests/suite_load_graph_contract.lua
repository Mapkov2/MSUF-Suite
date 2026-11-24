local root, flavor = assert(arg[1]), assert(arg[2])
-- Blizzard builds its shared font objects at startup on every client.
GameFontHighlightSmall = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
-- The client's securecallfunction reports an error and returns nothing;
-- this stand-in lets errors raise, so a failing callback fails the test.
securecallfunction = function(callback, ...) return callback(...) end
assert(flavor == "Mainline" or flavor == "Forever", "the Suite supports Retail and WoW Forever only")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
-- Shared native spellbook enums exist on both clients; ActionBarSet is Forever-only.
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 },
    ItemQuality = { Poor = 0, Common = 1, Uncommon = 2 }, BagIndex = { Backpack = 0 } }
Constants = { InventoryConstants = { NumBagSlots = 4 } }
C_SpellBook = {}
EventRegistry = { RegisterCallback = function() end }
local frames, loads, featureLoads, optionLoads, loaded = {}, 0, 0, 0, {}
local tooltipLoads, tooltipEnabled = 0, false
Enum.TooltipDataType = { Item = 1, Spell = 2, Unit = 3, UnitAura = 4, PetAction = 5, Totem = 6, Flyout = 7, Macro = 8 }
Enum.TooltipDataLineType = { UnitName = 1 }

SlashCmdList = {}
MSUFSuiteDB, MapkoSkinDB, MapkoSkin = nil, nil, nil
-- Both clients load the Mainline TOCs. Retail boots under the Main MSUF build
-- (no client model); Forever under the Classic build, which publishes
-- MSUF_NS.Client.
if flavor == "Mainline" then
    MSUF_NS = {}
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
else
    MSUF_NS = { Client = {
        Family = "Mainline", Flavor = "Mainline", IsRetail = true, IsForever = true,
        SupportsEvent = function() return true end,
    } }
    MSUF_PixelLayoutRegion = function(frame) return frame end
end
CreateFrame = function()
    local frame = { events = {} }
    function frame:SetScript(_, callback) self.callback = callback end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    frames[#frames + 1] = frame
    return frame
end
IsLoggedIn = function() return false end
canaccesstable = function() return true end
local deferred = {}
C_Timer = { After = function(delay, callback)
    assert(delay == 0)
    deferred[#deferred + 1] = callback
end }
InCombatLockdown = function() return false end
C_EventUtils = { IsEventValid = function() return true end }
-- C_CVar exists on both clients; this world has no native nameplate settings.
C_CVar = { GetCVar = function() return nil end }
UnitGUID = function() return "Player-Test" end
UnitName = function() return "Tester" end
UnitClass = function() return "Druid", "DRUID" end
GetRealmName = function() return "Realm" end
GetMoney = function() return 0 end
GetLocale = function() return "enUS" end
LoggingCombat = function(value) if value ~= nil then return value end; return false end
C_ChatInfo = { IsLoggingCombat = function() return false end }
GetInstanceInfo = function() return "outside", "none", 0 end
C_AddOns = {
    DoesAddOnExist = function(name)
        return name == "MSUF_Suite_QualityOfLife" or name == "MSUF_Suite_Tooltips"
            or flavor == "Forever" and name == "MSUF_Suite_ActionBars"
    end,
    IsAddOnLoaded = function(name) return loaded[name] == true end,
    GetAddOnEnableState = function(name)
        if name == "MSUF_Suite_Tooltips" and not tooltipEnabled then return 0 end
        return 2
    end,
    LoadAddOn = function(name)
        if name == "MSUF_Suite_Modules" then
            loads = loads + 1
            Support.Load(root, name, {})
            loaded[name] = true
            -- Forever can return a diagnostic even though the addon ran.
            return nil, "FOREVER_DIAGNOSTIC"
        end
        if name == "MSUF_Suite_QualityOfLife" then
            featureLoads = featureLoads + 1
            Support.Load(root, name, {})
            loaded[name] = true
            return true
        end
        if name == "MSUF_Suite_Tooltips" then
            assert(tooltipEnabled, "attempted to load Tooltips while disabled in the AddOn list")
            tooltipLoads = tooltipLoads + 1
            Support.Load(root, name, {})
            loaded[name] = true
            return nil, "FOREVER_DIAGNOSTIC"
        end
        -- Like the client, report addons this fixture does not install.
        if name == "MSUF_Suite_Skin" then return false, "MISSING" end
        -- The options addon's registration is covered by suite_options_menu_contract.
        assert(name == "MSUF_Suite_Options", name)
        optionLoads = optionLoads + 1
        loaded[name] = true
        MSUFSuite.Menu.attached = true
        return true
    end,
}
Support.Load(root, "MSUF_Suite", {})
assert(#frames == 2 and frames[2].events.PLAYER_ENTERING_WORLD and loads == 0)
-- The key binding labels load with the core, right after the bar titles.
local coreFiles, bindingsAt, barsAt = Support.TocFiles(root, "MSUF_Suite"), nil, nil
for index, file in ipairs(coreFiles) do
    if file == "Core/Bindings.lua" then bindingsAt = index end
    if file == "Core/Catalog/ActionBars.lua" then barsAt = index end
end
assert(barsAt and bindingsAt == barsAt + 1, "Core/Bindings.lua must follow Core/Catalog/ActionBars.lua")
assert(BINDING_HEADER_MSUFSUITE == "MSUF Suite" and BINDING_HEADER_MSUFSUITE_BAR9 == "Action bar 9"
    and BINDING_NAME_MSUFSUITE_BAR10_BUTTON12 == "Action bar 10 button 12",
    "the key binding panel would show raw command names")
frames[1]:callback("ADDON_LOADED", "MSUF_Suite")
-- MSUF's options addon is not loaded yet, so one watcher waits for it.
assert(#frames == 3 and frames[3].events.ADDON_LOADED and optionLoads == 0)
local owner = assert(MSUFSuite)
assert((owner.Suite.catalog.objectives.rules.showMythicPlus ~= nil) == (flavor == "Mainline"),
    "Mythic+ HUD setting must be available only on Retail")
assert((owner.Suite.catalog.runSummary.rules.showMythicPlus ~= nil) == (flavor == "Mainline"),
    "Mythic+ result card must be available only on Retail")
assert(owner.Suite.Availability("innervateCue") == (flavor == "Mainline"),
    "Innervate cue must be restricted to Retail Druids")
assert(owner.Suite.Availability("releaseProtection") and not owner.Suite.Config("releaseProtection").enabled
    and owner.Suite.Config("releaseProtection").modifier == 1,
    "release protection must be opt-in with Shift on Retail and Forever")
do
    assert(owner.Suite.Config("objectives").enabled
        and owner.Suite.Config("runSummary").enabled
        and owner.Suite.Config("announcements").enabled
        and owner.Suite.catalog.objectives.available == nil
        and owner.Suite.catalog.announcements.available == nil,
        "Suite-owned HUD must be enabled by default and have no client gate on Retail and Forever")
    if flavor == "Forever" then
        assert(owner.Suite.Config("actionbars").enabled
            and owner.Suite.catalog.actionbars.core
            and owner.Suite.catalog.actionbars.rules.enabled.default,
            "Forever ActionBars must be enabled by default")
        local oldBars = { suite = { schema = 1, actionBarsDefaultRevision = 1,
            modules = { actionbars = { enabled = false } } } }
        owner.Suite.Normalize(oldBars)
        assert(oldBars.suite.modules.actionbars.enabled
            and oldBars.suite.revision == owner.Suite.MigrationRevision,
            "older Forever profile did not activate ActionBars")
        oldBars.suite.modules.actionbars.enabled = false
        owner.Suite.Normalize(oldBars)
        assert(not oldBars.suite.modules.actionbars.enabled,
            "later player ActionBars choice was overwritten")
        local profile = { suite = { schema = 1, modules = {
            objectives = { enabled = false },
            announcements = { enabled = false },
        } } }
        owner.Suite.Normalize(profile)
        assert(profile.suite.modules.objectives.enabled
            and profile.suite.modules.announcements.enabled,
            "older Forever profile did not activate the Suite-owned HUD")
        profile.suite.modules.objectives.enabled = false
        owner.Suite.Normalize(profile)
        assert(not profile.suite.modules.objectives.enabled,
            "later user HUD choice was overwritten")
    end
    -- This lightweight boot fixture has no WoW frame methods; the dedicated
    -- HUD contract exercises both live module implementations.
    owner.Suite.Normalize(owner.DB)
    owner.Suite.Config("objectives").enabled = false
    owner.Suite.Config("runSummary").enabled = false
    owner.Suite.Config("announcements").enabled = false
    assert(owner.Suite.Availability("floatingCombatText") and owner.Suite.Config("floatingCombatText").enabled,
        "Floating combat text must be available and enabled by default on both clients")
    -- The combat text contract supplies FontStrings and native animations.
    owner.Suite.Config("floatingCombatText").enabled = false
    -- Secure ActionBars and the XP bar have their own contract fixtures.
    if flavor == "Forever" then
        assert(owner.Suite.Config("glimmer").enabled, "Forever Glimmer must start enabled")
        owner.Suite.Config("glimmer").enabled = false -- rendering has its own native-surface fixture
        owner.Suite.Config("actionbars").enabled = false
        assert(owner.Suite.Config("foreverPartyMap").enabled, "Forever party map must start enabled")
        -- The party map contract exercises its separate Blizzard_WorldMap listener.
        owner.Suite.Config("foreverPartyMap").enabled = false
    end
    owner.Suite.Config("xpBar").enabled = false
    -- Aura skins wait for Blizzard's aura addon in this lightweight fixture.
    -- Their listener ownership is exercised by the native aura contract.
    owner.Suite.Config("playerAuraSkins").enabled = false
end
frames[1]:callback("PLAYER_LOGIN")
frames[2]:callback("PLAYER_ENTERING_WORLD", true, false)
assert(#deferred == 2, "startup and installer each defer one callback")
for _, callback in ipairs(deferred) do callback() end
assert(owner.Suite.started and owner.RootDB == MSUFSuiteDB and owner.Skin.enabled)
assert(owner.Suite.Config("combatLog").enabled == true
    and owner.Suite.Config("combatLog").dungeonMythicPlus == true
    and owner.Suite.Config("combatLog").raidNormal == true,
    "combat logging did not keep safe, useful defaults")
assert(owner.Host.build == (flavor == "Mainline" and "Main" or "Classic"))
assert(owner.Client.flavor == flavor, "client detected as " .. tostring(owner.Client.flavor))
assert(not owner.Suite.Availability("tooltipDetails") and tooltipLoads == 0 and not owner.Tooltips,
    "Tooltips ran with the AddOn disabled")
tooltipEnabled = true
assert(owner.Suite.Availability("tooltipDetails"), "the shared tooltip anchor is unavailable on " .. flavor)
assert(owner.Suite.catalog.tooltipDetails.rules.inspectHovered.hidden ~= true,
    "the shared tooltip anchor exposed Retail inspect controls on Forever")
assert(type(owner.ForeverFactoryFramesCompact) == "string"
    and owner.ForeverFactoryFramesCompact:match("^MSUF3:")
    and type(owner.ForeverFactoryModuleCompact) == "string",
    "Forever installer choice is unavailable on a Mainline client")
assert(type(owner.ClassicFactoryFramesCompact) == "string"
    and owner.ClassicFactoryFramesCompact:match("^MSUF3:"),
    "Classic MSUF frame factory is unavailable to the installer")
assert(owner.Suite.Config("chat").enabled == true
    and owner.Suite.Config("chat").look == 5,
    "chat must start enabled with the client look")
assert(frames[5].events.PLAYER_LOGOUT and not frames[5].events.PLAYER_REGEN_ENABLED,
    "successful startup must retain only its profile save event")
assert(#frames == 5 and loads == 1 and featureLoads == 1
    and not next(frames[1].events) and not next(frames[2].events))
assert((owner.Suite.MythicPlus ~= nil) == (flavor == "Mainline"),
    "Mythic+ runtime must be available only on Retail")
frames[3]:callback("ADDON_LOADED", "SomeOtherAddon")
assert(optionLoads == 0 and frames[3].events.ADDON_LOADED)
loaded.MidnightSimpleUnitFrames_Options = true
frames[3]:callback("ADDON_LOADED", "MidnightSimpleUnitFrames_Options")
assert(optionLoads == 1 and owner.Menu.attached and not next(frames[3].events))
-- The first enabled module loads the runtime once; disabling releases its events.
assert(owner.Suite.Set("qol", "enabled", true))
assert(loads == 1 and featureLoads == 1 and owner.Suite.states.qol.active)
assert(owner.Suite.Set("quests", "enabled", true))
assert(owner.Suite.Set("loot", "enabled", true))
assert(owner.Suite.Set("combatLog", "enabled", true))
assert(featureLoads == 1 and owner.Suite.states.quests.active and owner.Suite.states.loot.active
    and owner.Suite.states.combatLog.active,
    "Quality of Life package was loaded more than once")
assert(owner.Suite.Set("qol", "enabled", false))
assert(owner.Suite.Set("quests", "enabled", false))
assert(owner.Suite.Set("loot", "enabled", false))
assert(owner.Suite.Set("combatLog", "enabled", false))
assert(not owner.Suite.states.qol.active and not owner.Suite.states.quests.active
    and not owner.Suite.states.loot.active and not owner.Suite.states.combatLog.active
    and loads == 1 and featureLoads == 1)
for index, frame in ipairs(frames) do
    if index ~= 5 then assert(not next(frame.events), "disabled runtime retained an event") end
end
assert(MapkoSkin == nil and MapkoSkinDB == nil)
local legacy = { itemTooltipStyle = "card", tooltipLayout = { x = 17, unitHealth = "show", bogus = true } }
local name = owner.Database.GetActiveProfileName()
assert(not owner.TooltipAppearance.ImportLegacy(legacy, name .. " other"))
assert(owner.TooltipAppearance.ImportLegacy(legacy, name))
local config = owner.Suite.Config("tooltipAppearance")
assert(config.tooltipLayout.x == 17 and config.tooltipLayout.unitHealth == "show" and not config.tooltipLayout.bogus)
local exported = assert(owner.ProfileIO.PrepareTable(owner.DB, false)).suite.modules.tooltipAppearance
assert(exported.tooltipLayout ~= config.tooltipLayout and exported.tooltipLayout.x == 17
    and exported.itemTooltipStyle == "card", "standalone tooltip layout did not round-trip through profiles")
assert(not owner.TooltipAppearance.ImportLegacy({ tooltipLayout = { x = 4 } }, name), "migration overwrote a saved layout")
assert(owner.Suite.Set("tooltipAppearance", "enabled", false))
assert(tooltipLoads == 0, "an off module loaded its addon before the page requested it")
local tooltips = assert(owner.TooltipAppearance.Engine(), "configuration did not load without Skinning")
local card = tooltips.ItemTooltipCard
assert(not tooltips.DB.enabled and card.Setting("x") == 17 and tooltipLoads == 1)
assert(card.SetPreset("forever") and card.Setting("height") == 40, "standalone Forever preset was unavailable")
assert(card.SetPreset("retail") and card.Setting("height") == 48, "standalone Retail preset was unavailable")
assert(owner.Suite.Set("tooltipAppearance", "enabled", true))
assert(owner.Suite.states.tooltipAppearance.active and tooltips.DB.enabled and tooltipLoads == 1)
assert(owner.Suite.Set("tooltipAppearance", "enabled", false))
assert(not owner.Suite.states.tooltipAppearance.active and not tooltips.DB.enabled and not MapkoSkin)

print("Standalone TOC boot, menu attach, on-demand activation and disable passed: " .. flavor)
