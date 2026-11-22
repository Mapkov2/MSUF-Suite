local _, NS = ...
local Suite, S = NS.NS, NS.Suite
local Chrome, Card, Loot = NS.TooltipChrome, NS.ItemTooltipCard, NS.LootTooltipRows
local Reference, owner = NS.ItemReference, {}
local M = {}
local frames = {
    Blizzard_GameTooltip = {
        "GameTooltip", "EmbeddedItemTooltip", "GameNoHeaderTooltip",
        "GameSmallHeaderTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
        "BuffFrameTooltip",
    },
    Blizzard_UIPanels_Game = {
        "ItemRefTooltip",
        "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
    },
    Blizzard_FrameXML = {
        "BattlePetTooltip", "FloatingBattlePetTooltip", "FloatingPetBattleAbilityTooltip",
    },
    Blizzard_PetBattleUI = {
        "PetBattlePrimaryAbilityTooltip", "PetBattlePrimaryUnitTooltip",
    },
    Blizzard_GarrisonBase = {
        "FloatingGarrisonFollowerAbilityTooltip", "FloatingGarrisonFollowerTooltip", "FloatingGarrisonMissionTooltip",
        "FloatingGarrisonShipyardFollowerTooltip", "GarrisonFollowerAbilityTooltip", "GarrisonFollowerAbilityWithoutCountersTooltip",
        "GarrisonFollowerMissionAbilityWithoutCountersTooltip", "GarrisonFollowerTooltip", "GarrisonShipyardFollowerTooltip",
    },
    Blizzard_CatalogShop = {
        "CatalogShopTooltip",
    },
    Blizzard_CustomizationUI = {
        "CustomizationNoHeaderTooltip",
    },
    Blizzard_Settings_Shared = {
        "SettingsTooltip",
    },
    Blizzard_Collections = {
        "PetJournalPrimaryAbilityTooltip", "PetJournalSecondaryAbilityTooltip",
    },
    Blizzard_HelpFrame = {
        "BrowserSettingsTooltip",
    },
    Blizzard_HelpPlate = { "HelpPlateTooltip" },
    Blizzard_QuickKeybind = { "QuickKeybindTooltip" },
    Blizzard_Contribution = { "ContributionBuffTooltip" },
    Blizzard_EncounterJournal = { "EncounterJournalTooltip" },
    Blizzard_GarrisonTemplates = { "GarrisonMissionMechanicTooltip", "GarrisonMissionMechanicFollowerCounterTooltip" },
    Blizzard_GarrisonUI = { "GarrisonBonusAreaTooltip", "GarrisonMissionListTooltipThreatsFrame" },
    Blizzard_HousingHouseFinder = { "HouseFinderHighlightedPlotTooltip" },
    Blizzard_PVPUI = { "ConquestTooltip" },
    Blizzard_UnitFrame = { "PartyMemberBuffTooltip" },
    Blizzard_PerksProgram = { "PerksProgramTooltip" },
    Blizzard_RuneforgeUI = { "RuneforgeFrameResultTooltip" },
}
M.addons = frames
local seen = setmetatable({}, { __mode = "k" })

local function BindConfig()
    local config = S.Config("tooltipAppearance")
    if not config.configured then Suite.TooltipAppearance.ImportLegacy(Suite.Skin.LegacyTooltipLayout()) end
    if not NS.DB or NS.DB.theme ~= config then NS.DB = { theme = config } end
    NS.DB.enabled = M.active == true
end

function NS.MarkConfigured()
    NS.DB.theme.configured = true
end

local function BindFrames(list)
    for _, name in ipairs(list) do
        local frame = _G[name]
        if frame and not seen[frame] then
            local ok = Chrome.Apply(frame, owner)
            if ok then seen[frame] = true end
        end
    end
end

local function OnAddonLoaded(_, _, addon)
    local list = frames[addon]
    if not list then return end
    BindFrames(list)
    if addon == "Blizzard_UIPanels_Game" then
        if LootFrame then Loot.Apply(LootFrame, owner) end
        if ItemRefTooltip then Reference.Apply(ItemRefTooltip) end
    end
end

function NS.RefreshTheme()
    BindConfig()
    NS.RefreshPalette()
    NS.Registry.NotifyListeners("theme", "tooltipAppearance")
end

function M:Enable()
    BindConfig()
    NS.RefreshPalette()
    NS.Surface.RefreshMedia()
    for _, list in pairs(frames) do BindFrames(list) end
    if LootFrame then Loot.Apply(LootFrame, owner) end
    if ItemRefTooltip then Reference.Apply(ItemRefTooltip) end
    -- FrameXML can load individual tooltip families later in the session.
    self.context:Event("ADDON_LOADED", OnAddonLoaded)
    Card.Refresh()
    Suite.Skin.TooltipAppearanceChanged()
end

function M:Refresh()
    NS.RefreshTheme()
end

function M:Disable()
    BindConfig()
    Card.Refresh()
    Loot.Disable(owner)
    Reference.Disable()
    Chrome.DisableOwner(owner)
    for frame in pairs(seen) do seen[frame] = nil end
    Suite.Skin.TooltipAppearanceChanged()
end

local function RefreshMedia()
    NS.Registry.NotifyListeners("tooltipMedia")
end

local function MediaRegistered(_, kind, key)
    if kind == "statusbar" then
        local setting = Card.Setting
        if key == setting("backgroundTexture") or key == setting("headerTexture") then
            NS.CombatGate.RunOrDefer(RefreshMedia, RefreshMedia)
        end
        NS.TooltipVitals.MediaRegistered(key)
    elseif kind == "font" then
        NS.TooltipVitals.FontRegistered(key)
    end
end

BindConfig()
NS.RefreshPalette()
NS.Surface.RefreshMedia()
local media = Suite.SharedMedia()
if media then media.RegisterCallback(NS, "LibSharedMedia_Registered", MediaRegistered) end
Suite.Registry.AddListener(NS, function(_, domain)
    if (domain == "profile" and not M.active) or domain == "look" then NS.RefreshTheme() end
end)
S.Install("tooltipAppearance", M)
Suite.Tooltips = NS
