local _, NS = ...

-- Mainline 12.1 Blizzard window catalog.
--
-- The addon and global names below are intentionally explicit. They were
-- verified against Gethe/wow-ui-source upstream/live at
-- 78282522143e25c3540583734fd192c3d69be910. This file is data only: it does
-- not load addons, scan UIParent, hook scripts, or register events.
--
-- Secure action, unit-frame, nameplate and aura behavior stays outside this
-- catalog.  User-facing HUD systems are represented by accent-only entries:
-- those paths recolor existing text and verified Blizzard glyphs but create no
-- regions and never touch scripts, anchors, attributes, or visibility.
-- GameMenu, PlayerSpells, ColorPicker, Settings, and AddonList are registered
-- outside the generic catalog and remain visible in standaloneGlass below.
-- Catalog roots with dedicated adapters (for example EncounterJournal) stay
-- listed here and carry an explicit dedicated owner contract.

-- Fullscreen and semantic-content roots keep their native background and do
-- not opt into implicit protection. Semantic-chrome roots add an edge-only
-- shell around native map art. Their safe child panels and controls are still
-- covered by the same bounded, out-of-combat traversal.
local semanticOverlayMode = {
    role = "panel",
    rootSurface = false,
    preserveRootArt = true,
    allowImplicitProtected = false,
}

-- Map canvases are semantic content, but their ordinary window chrome should
-- still read as Glass.  Keep Blizzard's map artwork and add only the edge
-- treatment; this avoids laying a translucent wash over the map itself.
local semanticChromeMode = {
    role = "shell",
    rootSurface = true,
    fillVisible = false,
    preserveRootArt = true,
    allowImplicitProtected = false,
}

local safePanelMode = { role = "shell", allowImplicitProtected = false }
local safeDialogMode = { role = "popup", allowImplicitProtected = false }
local hudAccentMode = {
    role = "panel",
    rootSurface = false,
    preserveRootArt = true,
    accentOnly = true,
    allowImplicitProtected = false,
    registerDynamicRows = false,
}

local entries = {
    -- Core character, inventory, NPC, and quest windows.
    {
        id = "character",
        category = "character",
        addon = "Blizzard_UIPanels_Game",
        frames = { "CharacterFrame", "GearManagerPopupFrame" },
        frameModes = { GearManagerPopupFrame = "dialog" },
    },
    {
        id = "inventory",
        category = "inventory",
        addon = "Blizzard_UIPanels_Game",
        frames = {
            "BankFrame", "ContainerFrameCombinedBags",
            "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
            "ContainerFrame4", "ContainerFrame5", "ContainerFrame6",
        },
    },
    {
        id = "inventory-dialogs",
        category = "inventory",
        addon = "Blizzard_UIPanels_Game",
        frames = { "BankCleanUpConfirmationPopup" },
        mode = "dialog",
    },
    {
        id = "merchant",
        category = "npc",
        addon = "Blizzard_UIPanels_Game",
        frames = { "MerchantFrame" },
    },
    {
        id = "quest-and-gossip",
        category = "quest",
        addon = "Blizzard_UIPanels_Game",
        frames = { "QuestFrame", "GossipFrame", "QuestLogPopupDetailFrame" },
        frameModes = { QuestLogPopupDetailFrame = "dialog" },
    },
    {
        id = "player-interaction",
        category = "npc",
        addon = "Blizzard_UIPanels_Game",
        frames = {
            "TradeFrame",
            "TaxiFrame",
            "ItemTextFrame",
            "PetitionFrame",
            "TabardFrame",
            "GuildRegistrarFrame",
            "MasterLooterFrame",
        },
        frameModes = { MasterLooterFrame = "dialog" },
    },
    {
        id = "dressing-room",
        category = "character",
        addon = "Blizzard_UIPanels_Game",
        frames = { "DressUpFrame", "SideDressUpFrame", "TransmogAndMountDressupFrame" },
    },
    {
        id = "model-preview",
        category = "utility",
        addon = "Blizzard_SharedXML",
        frames = { "ModelPreviewFrame" },
        mode = safePanelMode,
    },
    {
        id = "equipment-flyout",
        category = "inventory",
        addon = "Blizzard_FrameXML",
        frames = { "EquipmentFlyoutFrame" },
        mode = safePanelMode,
    },
    {
        id = "core-dialogs",
        category = "utility",
        addon = "Blizzard_FrameXML",
        frames = { "GuildInviteFrame", "CoinPickupFrame", "StackSplitFrame" },
        mode = "dialog",
    },
    {
        id = "static-popups",
        category = "utility",
        addon = "Blizzard_StaticPopup_Game",
        frames = { "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4" },
        mode = "dialog",
    },
    {
        id = "pet-battle-ready-dialog",
        category = "utility",
        addon = "Blizzard_StaticPopup_Game",
        frames = { "PetBattleQueueReadyFrame" },
        mode = safeDialogMode,
    },
    {
        id = "basic-message-dialog",
        category = "utility",
        addon = "Blizzard_SharedXML",
        frames = { "BasicMessageDialog" },
        mode = safeDialogMode,
    },
    {
        id = "talking-head",
        category = "hud",
        addon = "Blizzard_FrameXML",
        frames = { "TalkingHeadFrame" },
        skipGeneric = true,
    },
    {
        id = "core-tooltips",
        category = "utility",
        addon = "Blizzard_GameTooltip",
        frames = {
            "GameTooltip", "EmbeddedItemTooltip",
            "GameNoHeaderTooltip", "GameSmallHeaderTooltip",
            "ShoppingTooltip1", "ShoppingTooltip2",
        },
        mode = "tooltip",
    },
    {
        id = "item-reference-tooltips",
        category = "utility",
        addon = "Blizzard_UIPanels_Game",
        frames = { "ItemRefTooltip", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" },
        mode = "tooltip",
    },
    {
        id = "battle-pet-tooltips",
        category = "utility",
        addon = "Blizzard_FrameXML",
        frames = { "BattlePetTooltip", "FloatingBattlePetTooltip", "FloatingPetBattleAbilityTooltip" },
        mode = "tooltip",
    },
    {
        id = "pet-battle-ui-tooltips",
        category = "utility",
        addon = "Blizzard_PetBattleUI",
        frames = { "PetBattlePrimaryAbilityTooltip", "PetBattlePrimaryUnitTooltip" },
        mode = "tooltip",
    },
    {
        id = "garrison-tooltips",
        category = "utility",
        addon = "Blizzard_GarrisonBase",
        frames = {
            "FloatingGarrisonFollowerAbilityTooltip",
            "FloatingGarrisonFollowerTooltip",
            "FloatingGarrisonMissionTooltip",
            "FloatingGarrisonShipyardFollowerTooltip",
            "GarrisonFollowerAbilityTooltip",
            "GarrisonFollowerAbilityWithoutCountersTooltip",
            "GarrisonFollowerMissionAbilityWithoutCountersTooltip",
            "GarrisonFollowerTooltip",
            "GarrisonShipyardFollowerTooltip",
        },
        mode = "tooltip",
    },
    {
        id = "catalog-shop-tooltip",
        category = "utility",
        addon = "Blizzard_CatalogShop",
        frames = { "CatalogShopTooltip" },
        mode = "tooltip",
    },
    {
        id = "customization-tooltip",
        category = "utility",
        addon = "Blizzard_CustomizationUI",
        frames = { "CustomizationNoHeaderTooltip" },
        mode = "tooltip",
    },
    {
        id = "settings-tooltip",
        category = "utility",
        addon = "Blizzard_Settings_Shared",
        frames = { "SettingsTooltip" },
        mode = "tooltip",
    },
    {
        id = "collection-tooltips",
        category = "utility",
        addon = "Blizzard_Collections",
        frames = { "PetJournalPrimaryAbilityTooltip", "PetJournalSecondaryAbilityTooltip" },
        mode = "tooltip",
    },
    {
        id = "help-tooltips",
        category = "utility",
        addon = "Blizzard_HelpFrame",
        frames = { "BrowserSettingsTooltip" },
        mode = "tooltip",
    },
    {
        id = "help-plate-tooltip",
        category = "utility",
        addon = "Blizzard_HelpPlate",
        frames = { "HelpPlateTooltip" },
        mode = "tooltip",
    },
    {
        id = "quick-keybind-tooltip",
        category = "utility",
        addon = "Blizzard_QuickKeybind",
        frames = { "QuickKeybindTooltip" },
        mode = "tooltip",
    },
    {
        id = "contribution-tooltip",
        category = "utility",
        addon = "Blizzard_Contribution",
        frames = { "ContributionBuffTooltip" },
        mode = "tooltip",
    },
    {
        id = "encounter-journal-tooltip",
        category = "utility",
        addon = "Blizzard_EncounterJournal",
        frames = { "EncounterJournalTooltip" },
        mode = "tooltip",
    },
    {
        id = "garrison-extra-tooltips",
        category = "utility",
        addon = "Blizzard_GarrisonTemplates",
        frames = {
            "GarrisonMissionMechanicTooltip", "GarrisonMissionMechanicFollowerCounterTooltip",
        },
        mode = "tooltip",
    },
    {
        id = "garrison-ui-extra-tooltips",
        category = "utility",
        addon = "Blizzard_GarrisonUI",
        frames = {
            "GarrisonBonusAreaTooltip", "GarrisonMissionListTooltipThreatsFrame",
        },
        mode = "tooltip",
    },
    {
        id = "housing-finder-tooltip",
        category = "utility",
        addon = "Blizzard_HousingHouseFinder",
        frames = { "HouseFinderHighlightedPlotTooltip" },
        mode = "tooltip",
    },
    {
        id = "pvp-tooltips",
        category = "utility",
        addon = "Blizzard_PVPUI",
        frames = { "ConquestTooltip" },
        mode = "tooltip",
    },
    {
        id = "party-member-tooltip",
        category = "utility",
        addon = "Blizzard_UnitFrame",
        frames = { "PartyMemberBuffTooltip" },
        mode = "tooltip",
    },
    {
        id = "perks-program-tooltip",
        category = "utility",
        addon = "Blizzard_PerksProgram",
        frames = { "PerksProgramTooltip" },
        mode = "tooltip",
    },
    {
        id = "runeforge-result-tooltip",
        category = "utility",
        addon = "Blizzard_RuneforgeUI",
        frames = { "RuneforgeFrameResultTooltip" },
        mode = "tooltip",
    },

    -- Mail and social windows.
    {
        id = "mail",
        category = "social",
        addon = "Blizzard_MailFrame",
        frames = { "MailFrame", "OpenMailFrame" },
    },
    {
        id = "friends",
        category = "social",
        addon = "Blizzard_FriendsFrame",
        frames = { "FriendsFrame", "FriendsFriendsFrame", "FriendsTooltip" },
        frameModes = { FriendsTooltip = "tooltip" },
    },
    {
        id = "guild-rename",
        category = "social",
        addon = "Blizzard_GuildRename",
        frames = { "GuildRenameFrame" },
    },
    {
        id = "channels",
        category = "social",
        addon = "Blizzard_Channels",
        frames = { "ChannelFrame" },
    },
    {
        id = "channel-dialogs",
        category = "social",
        addon = "Blizzard_Channels",
        frames = { "CreateChannelPopup" },
        mode = "dialog",
    },
    {
        id = "add-friend-dialogs",
        category = "social",
        addon = "Blizzard_AddFriend",
        frames = { "AddFriendFrame", "BattleNetInviteFrame" },
        mode = "dialog",
    },
    {
        id = "quick-join-dialog",
        category = "social",
        addon = "Blizzard_QuickJoin",
        frames = { "QuickJoinFrame", "QuickJoinRoleSelectionFrame" },
        mode = "dialog",
        frameModes = { QuickJoinFrame = "panel" },
    },
    {
        id = "communities",
        category = "social",
        addon = "Blizzard_Communities",
        frames = { "CommunitiesFrame" },
        skipGeneric = true,
    },
    {
        id = "community-dialogs",
        category = "social",
        addon = "Blizzard_Communities",
        frames = {
            "CommunitiesAvatarPickerDialog",
            "CommunitiesSettingsDialog",
            "CommunitiesTicketManagerDialog",
            "CommunitiesGuildTextEditFrame",
            "CommunitiesGuildLogFrame",
            "CommunitiesGuildNewsFiltersFrame",
        },
        mode = "dialog",
    },
    {
        id = "guild-control",
        category = "social",
        addon = "Blizzard_GuildControlUI",
        frames = { "GuildControlUI" },
        mode = "dialog",
    },
    {
        id = "social-ui",
        category = "social",
        addon = "Blizzard_SocialUI",
        frames = { "SocialUIFrame" },
        skipGeneric = true,
    },
    {
        id = "battle-net-toasts",
        category = "social",
        addon = "Blizzard_BNet",
        frames = { "BNToastFrame", "TimeAlertFrame" },
        skipGeneric = true,
    },
    {
        id = "combat-log-navigation",
        category = "utility",
        addon = "Blizzard_CombatLog",
        frames = { "CombatLogQuickButtonFrame_Custom" },
        skipGeneric = true,
    },
    {
        id = "recruit-a-friend",
        category = "social",
        addon = "Blizzard_RecruitAFriend",
        frames = { "RecruitAFriendFrame" },
    },
    {
        id = "recruit-a-friend-dialogs",
        category = "social",
        addon = "Blizzard_RecruitAFriend",
        frames = { "RecruitAFriendRecruitmentFrame", "RecruitAFriendRewardsFrame" },
        mode = "dialog",
    },
    {
        id = "behavioral-messaging",
        category = "social",
        addon = "Blizzard_BehavioralMessaging",
        frames = { "BehavioralMessagingDetails" },
        mode = "dialog",
    },
    {
        id = "photo-sharing",
        category = "social",
        addon = "Blizzard_PhotoSharing",
        frames = { "PhotoSharingFrame", "PhotoSharingBrowserFrame", "PhotoSharingBrowserPopup" },
        frameModes = { PhotoSharingBrowserPopup = "dialog" },
    },

    -- Group content and journals.
    {
        id = "group-finder",
        category = "group",
        addon = "Blizzard_GroupFinder",
        frames = { "PVEFrame" },
        mode = {
            role = "shell", maxDepth = 10, maxNodes = 1200,
            registerDynamicRows = true,
        },
    },
    {
        id = "group-finder-dialogs",
        category = "group",
        addon = "Blizzard_GroupFinder",
        frames = {
            "LFDRoleCheckPopup",
            "LFGDungeonReadyPopup",
            "LFGInvitePopup",
            "LFGListApplicationDialog",
            "LFGListInviteDialog",
            "LFGReadyCheckPopup",
            "PVPFramePopup",
            "PVPRoleCheckPopup",
            "PVPReadyDialog",
            "PVPReadyPopup",
            "PlunderstormFramePopup",
            "PlunderstormQueueTutorialFrame",
        },
        mode = "dialog",
    },
    {
        id = "group-finder-status",
        category = "group",
        addon = "Blizzard_GroupFinder",
        frames = { "PVPHelperFrame", "PVPTimerFrame" },
        mode = hudAccentMode,
    },
    {
        id = "loot-windows",
        category = "group",
        addon = "Blizzard_UIPanels_Game",
        frames = {
            "LootFrame", "BonusRollFrame",
            "GroupLootFrame1", "GroupLootFrame2", "GroupLootFrame3", "GroupLootFrame4",
        },
        mode = safePanelMode,
    },
    {
        id = "group-system-dialogs",
        category = "group",
        addon = "Blizzard_FrameXML",
        frames = {
            "GroupLootHistoryFrame", "ReadyCheckListenerFrame", "RolePollPopup",
            "InstanceAbandonFrame", "InstanceAbandonPopup",
        },
        mode = safeDialogMode,
        frameModes = { GroupLootHistoryFrame = safePanelMode },
    },
    {
        id = "raid-window",
        category = "group",
        addon = "Blizzard_RaidFrame",
        frames = { "RaidParentFrame" },
    },
    {
        id = "collections",
        category = "journal",
        addon = "Blizzard_Collections",
        frames = { "CollectionsJournal" },
    },
    {
        id = "encounter-journal",
        category = "journal",
        addon = "Blizzard_EncounterJournal",
        frames = { "EncounterJournal" },
        skipGeneric = true,
    },
    {
        id = "mythic-plus",
        category = "group",
        addon = "Blizzard_ChallengesUI",
        frames = { "ChallengesFrame", "ChallengesKeystoneFrame" },
        mode = "panel",
        frameModes = { ChallengesKeystoneFrame = "dialog" },
    },
    {
        id = "pvp",
        category = "group",
        addon = "Blizzard_PVPUI",
        frames = { "PVPUIFrame" },
        mode = "panel",
        skipGeneric = true,
    },
    {
        id = "pvp-match",
        category = "group",
        addon = "Blizzard_PVPMatch",
        frames = { "PVPMatchResults", "PVPMatchScoreboard" },
        mode = "panel",
    },
    {
        id = "islands-queue",
        category = "group",
        addon = "Blizzard_IslandsQueueUI",
        frames = { "IslandsQueueFrame" },
    },
    {
        id = "torghast-level-picker",
        category = "group",
        addon = "Blizzard_TorghastLevelPicker",
        frames = { "TorghastLevelPickerFrame" },
        mode = "dialog",
    },
    {
        id = "end-of-match",
        category = "group",
        addon = "Blizzard_EndOfMatchUI",
        frames = { "EndOfMatchFrame" },
        mode = semanticOverlayMode,
    },
    {
        id = "player-choice",
        category = "quest",
        addon = "Blizzard_PlayerChoice",
        frames = {
            "PlayerChoiceFrame", "PlayerChoiceTimeRemaining",
            "CypherPlayerChoiceToggleButton", "GenericPlayerChoiceToggleButton",
            "TorghastPlayerChoiceToggleButton",
        },
        mode = {
            role = "shell", maxDepth = 10, maxNodes = 1000,
            allowImplicitProtected = true,
        },
        frameModes = {
            PlayerChoiceTimeRemaining = hudAccentMode,
            CypherPlayerChoiceToggleButton = hudAccentMode,
            GenericPlayerChoiceToggleButton = hudAccentMode,
            TorghastPlayerChoiceToggleButton = hudAccentMode,
        },
    },
    {
        id = "plunderstorm-basics",
        category = "group",
        addon = "Blizzard_PlunderstormBasics",
        frames = { "PlunderstormBasicsContainerFrame" },
        mode = semanticOverlayMode,
    },
    {
        id = "pet-battle",
        category = "group",
        addon = "Blizzard_PetBattleUI",
        frames = { "PetBattleFrame" },
        mode = semanticOverlayMode,
    },
    {
        id = "islands-party-pose",
        category = "group",
        addon = "Blizzard_IslandsPartyPoseUI",
        frames = { "IslandsPartyPoseFrame" },
        mode = semanticOverlayMode,
    },
    {
        id = "match-celebration-party-pose",
        category = "group",
        addon = "Blizzard_MatchCelebrationPartyPoseUI",
        frames = { "MatchCelebrationPartyPoseFrame" },
        mode = semanticOverlayMode,
    },
    {
        id = "warfronts-party-pose",
        category = "group",
        addon = "Blizzard_WarfrontsPartyPoseUI",
        frames = { "WarfrontsPartyPoseFrame" },
        mode = semanticOverlayMode,
    },
    {
        id = "spectate",
        category = "group",
        addon = "Blizzard_SpectateFrame",
        frames = { "SpectateFrame" },
        mode = semanticOverlayMode,
    },
    {
        id = "achievements",
        category = "journal",
        addon = "Blizzard_AchievementUI",
        frames = { "AchievementFrame" },
    },
    {
        id = "generic-traits",
        category = "character",
        addon = "Blizzard_GenericTraitUI",
        frames = { "GenericTraitFrame" },
    },
    {
        id = "order-hall-talents",
        category = "expansion",
        addon = "Blizzard_OrderHallUI",
        frames = { "OrderHallTalentFrame" },
    },

    -- Trading, professions, and item-service windows.
    {
        id = "auction-house",
        category = "economy",
        addon = "Blizzard_AuctionHouseUI",
        frames = { "AuctionHouseFrame", "AuctionHouseMultisellProgressFrame" },
    },
    {
        id = "professions",
        category = "profession",
        addon = "Blizzard_Professions",
        frames = { "ProfessionsFrame", "InspectRecipeFrame" },
    },
    {
        id = "profession-book",
        category = "profession",
        addon = "Blizzard_ProfessionsBook",
        frames = { "ProfessionsBookFrame" },
        skipGeneric = true,
    },
    {
        id = "crafting-orders",
        category = "profession",
        addon = "Blizzard_ProfessionsCustomerOrders",
        frames = { "ProfessionsCustomerOrdersFrame" },
    },
    {
        id = "guild-bank",
        category = "economy",
        addon = "Blizzard_GuildBankUI",
        frames = { "GuildBankFrame" },
    },
    {
        id = "inspect",
        category = "character",
        addon = "Blizzard_InspectUI",
        frames = { "InspectFrame" },
        skipGeneric = true,
    },
    {
        id = "macros",
        category = "character",
        addon = "Blizzard_MacroUI",
        frames = { "MacroFrame" },
        mode = { role = "popup" },
    },
    {
        id = "macro-dialogs",
        category = "character",
        addon = "Blizzard_MacroUI",
        frames = { "MacroPopupFrame" },
        mode = "dialog",
    },
    {
        id = "trainer",
        category = "npc",
        addon = "Blizzard_TrainerUI",
        frames = { "ClassTrainerFrame" },
    },
    {
        id = "transmog",
        category = "character",
        addon = "Blizzard_Transmog",
        frames = { "TransmogFrame" },
    },
    {
        id = "stable",
        category = "character",
        addon = "Blizzard_StableUI",
        frames = { "StableFrame" },
    },
    {
        id = "item-interaction",
        category = "item-service",
        addon = "Blizzard_ItemInteractionUI",
        frames = { "ItemInteractionFrame" },
        skipGeneric = true,
    },
    {
        id = "item-socketing",
        category = "item-service",
        addon = "Blizzard_ItemSocketingUI",
        frames = { "ItemSocketingFrame" },
        skipGeneric = true,
    },
    {
        id = "item-upgrade",
        category = "item-service",
        addon = "Blizzard_ItemUpgradeUI",
        frames = { "ItemUpgradeFrame" },
        skipGeneric = true,
    },
    {
        id = "runeforge",
        category = "item-service",
        addon = "Blizzard_RuneforgeUI",
        frames = { "RuneforgeFrame" },
    },
    {
        id = "scrapping-machine",
        category = "item-service",
        addon = "Blizzard_ScrappingMachineUI",
        frames = { "ScrappingMachineFrame" },
    },
    {
        id = "black-market",
        category = "economy",
        addon = "Blizzard_BlackMarketUI",
        frames = { "BlackMarketFrame" },
    },
    {
        id = "obliterum-forge",
        category = "item-service",
        addon = "Blizzard_ObliterumUI",
        frames = { "ObliterumForgeFrame" },
    },
    {
        id = "perks-program",
        category = "economy",
        addon = "Blizzard_PerksProgram",
        frames = { "PerksProgramFrame" },
        mode = semanticOverlayMode,
    },
    {
        id = "account-store",
        category = "economy",
        addon = "Blizzard_AccountStore",
        frames = { "AccountStoreFrame" },
        mode = safePanelMode,
    },
    {
        id = "catalog-shop",
        category = "economy",
        addon = "Blizzard_CatalogShop",
        frames = { "CatalogShopFrame" },
        mode = semanticOverlayMode,
    },
    {
        id = "catalog-shop-refund",
        category = "economy",
        addon = "Blizzard_CatalogShopRefundFlow",
        frames = { "CatalogShopRefundFrame" },
        mode = "dialog",
    },
    {
        id = "catalog-shop-top-up",
        category = "economy",
        addon = "Blizzard_CatalogShopTopUpFlow",
        frames = { "CatalogShopTopUpFrame" },
        mode = "dialog",
    },
    -- Calendar and maps.
    {
        id = "calendar",
        category = "calendar",
        addon = "Blizzard_Calendar",
        frames = {
            "CalendarFrame",
            "CalendarViewHolidayFrame",
            "CalendarViewRaidFrame",
            "CalendarViewEventFrame",
            "CalendarCreateEventFrame",
        },
    },
    {
        id = "calendar-dialogs",
        category = "calendar",
        addon = "Blizzard_Calendar",
        frames = { "CalendarMassInviteFrame", "CalendarEventPickerFrame", "CalendarTexturePickerFrame" },
        mode = "dialog",
    },
    {
        id = "world-map",
        category = "map",
        addon = "Blizzard_WorldMap",
        frames = { "WorldMapFrame" },
        mode = "map",
        skipGeneric = true,
    },
    {
        id = "flight-map",
        category = "map",
        addon = "Blizzard_FlightMap",
        frames = { "FlightMapFrame" },
        mode = "map",
    },
    {
        id = "adventure-map-dialog",
        category = "map",
        addon = "Blizzard_AdventureMap",
        frames = { "AdventureMapQuestChoiceDialog" },
        mode = "dialog",
    },
    {
        id = "battlefield-map",
        category = "map",
        addon = "Blizzard_BattlefieldMap",
        frames = { "BattlefieldMapFrame" },
        mode = semanticChromeMode,
    },

    -- Expansion and account-era feature windows.
    {
        id = "barbershop",
        category = "character",
        addon = "Blizzard_BarbershopUI",
        frames = { "BarberShopFrame" },
    },
    {
        id = "character-customization",
        category = "character",
        addon = "Blizzard_CharacterCustomize",
        frames = { "CharCustomizeFrame" },
        mode = {
            role = "panel", rootSurface = false, preserveRootArt = true,
            maxDepth = 10, maxNodes = 1200, allowImplicitProtected = false,
        },
    },
    {
        id = "allied-races",
        category = "character",
        addon = "Blizzard_AlliedRacesUI",
        frames = { "AlliedRacesFrame" },
    },
    {
        id = "archaeology",
        category = "profession",
        addon = "Blizzard_ArchaeologyUI",
        frames = { "ArchaeologyFrame" },
    },
    {
        id = "artifact",
        category = "expansion",
        addon = "Blizzard_ArtifactUI",
        frames = { "ArtifactFrame" },
    },
    {
        id = "azerite-item",
        category = "expansion",
        addon = "Blizzard_AzeriteUI",
        frames = { "AzeriteEmpoweredItemUI" },
    },
    {
        id = "azerite-essences",
        category = "expansion",
        addon = "Blizzard_AzeriteEssenceUI",
        frames = { "AzeriteEssenceUI" },
    },
    {
        id = "azerite-respec",
        category = "expansion",
        addon = "Blizzard_AzeriteRespecUI",
        frames = { "AzeriteRespecFrame" },
    },
    {
        id = "chromie-time",
        category = "expansion",
        addon = "Blizzard_ChromieTimeUI",
        frames = { "ChromieTimeFrame" },
    },
    {
        id = "covenant-preview",
        category = "expansion",
        addon = "Blizzard_CovenantPreviewUI",
        frames = { "CovenantPreviewFrame" },
    },
    {
        id = "covenant-renown",
        category = "expansion",
        addon = "Blizzard_CovenantRenown",
        frames = { "CovenantRenownFrame" },
    },
    {
        id = "covenant-sanctum",
        category = "expansion",
        addon = "Blizzard_CovenantSanctum",
        frames = { "CovenantSanctumFrame" },
    },
    {
        id = "soulbinds",
        category = "expansion",
        addon = "Blizzard_Soulbinds",
        frames = { "SoulbindViewer" },
    },
    {
        id = "delves-companion",
        category = "expansion",
        addon = "Blizzard_DelvesCompanionConfiguration",
        frames = { "DelvesCompanionAbilityListFrame", "DelvesCompanionConfigurationFrame" },
    },
    {
        id = "delves-difficulty",
        category = "expansion",
        addon = "Blizzard_DelvesDifficultyPicker",
        frames = { "DelvesDifficultyPickerFrame" },
        mode = "dialog",
    },
    {
        id = "expansion-landing-page",
        category = "expansion",
        addon = "Blizzard_ExpansionLandingPage",
        frames = { "ExpansionLandingPage" },
    },
    {
        id = "weekly-rewards",
        category = "expansion",
        addon = "Blizzard_WeeklyRewards",
        frames = { "WeeklyRewardsFrame" },
        mode = {
            role = "shell", maxDepth = 10, maxNodes = 1200,
            allowImplicitProtected = false,
        },
    },
    {
        id = "weekly-rewards-dialog",
        category = "expansion",
        addon = "Blizzard_WeeklyRewards",
        frames = { "WeeklyRewardExpirationWarningDialog" },
        mode = safeDialogMode,
    },
    {
        id = "anima-diversion",
        category = "expansion",
        addon = "Blizzard_AnimaDiversionUI",
        frames = { "AnimaDiversionFrame" },
        mode = semanticChromeMode,
    },
    {
        id = "contribution",
        category = "expansion",
        addon = "Blizzard_Contribution",
        frames = { "ContributionCollectionFrame" },
    },
    {
        id = "remix-artifact",
        category = "expansion",
        addon = "Blizzard_RemixArtifactUI",
        frames = { "RemixArtifactFrame" },
    },
    {
        id = "garrison",
        category = "expansion",
        addon = "Blizzard_GarrisonUI",
        frames = {
            "BFAMissionFrame",
            "CovenantMissionFrame",
            "GarrisonBuildingFrame",
            "GarrisonCapacitiveDisplayFrame",
            "GarrisonLandingPage",
            "GarrisonMissionFrame",
            "GarrisonMonumentFrame",
            "GarrisonRecruiterFrame",
            "GarrisonRecruitSelectFrame",
            "GarrisonShipyardFrame",
            "OrderHallMissionFrame",
        },
    },
    {
        id = "help",
        category = "utility",
        addon = "Blizzard_HelpFrame",
        frames = { "HelpFrame", "ReportCheatingDialog" },
        frameModes = { ReportCheatingDialog = "dialog" },
    },
    {
        id = "report-dialog",
        category = "utility",
        addon = "Blizzard_ReportFrame",
        frames = { "ReportFrame" },
        mode = "dialog",
    },
    {
        id = "chat-configuration",
        category = "utility",
        addon = "Blizzard_ChatFrame",
        frames = { "ChatConfigFrame" },
    },
    {
        id = "currency-transfer",
        category = "utility",
        addon = "Blizzard_TokenUI",
        frames = { "CurrencyTransferMenu", "CurrencyTransferLog", "TokenFramePopup" },
        frameModes = { TokenFramePopup = "dialog" },
    },
    {
        id = "click-bindings",
        category = "utility",
        addon = "Blizzard_ClickBindingUI",
        frames = { "ClickBindingFrame" },
    },
    {
        id = "cooldown-viewer-settings",
        category = "utility",
        addon = "Blizzard_CooldownViewer",
        frames = { "CooldownViewerSettings" },
        mode = safePanelMode,
    },
    {
        id = "cooldown-viewer-dialogs",
        category = "utility",
        addon = "Blizzard_CooldownViewer",
        frames = {
            "CooldownViewerImportLayoutDialog", "CooldownViewerLayoutDialog",
            "CooldownViewerSettingsEditAlert", "GroupBuffFilterEditVisualAlert",
        },
        mode = safeDialogMode,
    },
    {
        id = "time-manager",
        category = "utility",
        addon = "Blizzard_TimeManager",
        frames = { "TimeManagerFrame", "StopwatchFrame" },
    },
    {
        id = "death-recap",
        category = "utility",
        addon = "Blizzard_DeathRecap",
        frames = { "DeathRecapFrame" },
        mode = "dialog",
    },
    {
        id = "wow-token-dialogs",
        category = "utility",
        addon = "Blizzard_WowTokenUI",
        frames = { "WowTokenDialog", "WowTokenRedemptionFrame" },
        mode = "dialog",
    },
    {
        id = "subscription-interstitial",
        category = "utility",
        addon = "Blizzard_SubscriptionInterstitialUI",
        frames = { "SubscriptionInterstitialFrame" },
        mode = "dialog",
    },
    {
        id = "expansion-trial-dialog",
        category = "utility",
        addon = "Blizzard_ExpansionTrial",
        frames = { "ExpansionTrialCheckPointDialog" },
        mode = "dialog",
    },
    {
        id = "class-trial-dialogs",
        category = "utility",
        addon = "Blizzard_ClassTrial",
        frames = { "ClassTrialThanksForPlayingDialog", "ExpansionTrialThanksForPlayingDialog" },
        mode = semanticOverlayMode,
        frameModes = { ExpansionTrialThanksForPlayingDialog = safeDialogMode },
    },
    {
        id = "splash-frame",
        category = "utility",
        addon = "Blizzard_SplashFrame",
        frames = { "SplashFrame" },
        mode = semanticOverlayMode,
    },
    {
        id = "quick-keybind",
        category = "utility",
        addon = "Blizzard_QuickKeybind",
        frames = { "QuickKeybindFrame" },
        mode = semanticOverlayMode,
        skipGeneric = true,
    },
    {
        id = "secure-transfer-dialog",
        category = "utility",
        addon = "Blizzard_SecureTransferUI",
        frames = { "SecureTransferDialog" },
        mode = safeDialogMode,
    },
    {
        id = "script-errors",
        category = "utility",
        addon = "Blizzard_ScriptErrorsFrame",
        frames = { "ScriptErrorsFrame" },
        mode = safeDialogMode,
    },
    {
        id = "wow-survey",
        category = "utility",
        addon = "Blizzard_WowSurveyUI",
        frames = { "WowSurveyStatusFrame" },
        mode = semanticOverlayMode,
    },
    {
        id = "developer-console",
        category = "utility",
        addon = "Blizzard_Console",
        frames = { "DeveloperConsole" },
        mode = safePanelMode,
    },
    {
        id = "debug-tools",
        category = "utility",
        addon = "Blizzard_DebugTools",
        frames = { "FrameStackTooltip", "TableAttributeDisplay" },
        frameModes = { FrameStackTooltip = "tooltip" },
    },
    {
        id = "event-trace",
        category = "utility",
        addon = "Blizzard_EventTrace",
        frames = { "EventTrace", "EventTraceTooltip" },
        mode = safePanelMode,
        frameModes = { EventTraceTooltip = "tooltip" },
    },
    {
        id = "customization-debug",
        category = "utility",
        addon = "Blizzard_FrameXML",
        frames = { "CustomizationDebugFrame" },
        mode = safePanelMode,
    },
    {
        id = "legacy-dropdown-menus",
        category = "utility",
        addon = "Blizzard_SharedXML",
        frames = { "DropDownList1", "DropDownList2", "DropDownList3" },
        mode = {
            role = "popup", allowImplicitProtected = false,
            menuPopup = true, legacyDropdown = true,
        },
    },
    {
        id = "new-player-guide",
        category = "utility",
        addon = "Blizzard_NewPlayerExperienceGuide",
        frames = { "GuideFrame" },
        mode = safePanelMode,
    },
    {
        id = "ime-candidates",
        category = "utility",
        addon = "Blizzard_IME",
        frames = { "IMECandidatesFrame" },
        mode = "tooltip",
    },

    -- Transient Blizzard HUD chrome.  These entries use the accent-only mode:
    -- text and verified glyph textures are recolored, while semantic artwork,
    -- secure descendants, geometry, visibility and scripts remain native.
    {
        id = "hud-core-alerts",
        category = "hud",
        addon = "Blizzard_FrameXML",
        frames = {
            "AlertFrame", "BossBanner", "EventToastManagerFrame",
            "EventToastManagerSideDisplay", "HonorLevelUpBanner",
            "PrestigeLevelUpBanner", "LossOfControlFrame",
        },
        mode = hudAccentMode,
    },
    {
        id = "hud-core-fullscreen",
        category = "hud",
        addon = "Blizzard_FrameXML",
        frames = {
            "CinematicFrame", "DestinyFrame", "LowHealthFrame", "GhostFrame",
            "SpellActivationOverlayFrame",
        },
        mode = hudAccentMode,
    },
    {
        id = "hud-core-transient",
        category = "hud",
        addon = "Blizzard_FrameXML",
        frames = {
            "ArtifactLevelUpToast", "AutoFollowStatus", "AzeriteIslandsToast",
            "AzeriteLevelUpToast", "IconIntroTracker", "QuestSessionManager",
            "RatingMenuFrame", "RoleChangedFrame", "StreamingIcon",
            "SubZoneTextFrame", "TimerTracker", "ZoneTextFrame",
        },
        mode = hudAccentMode,
    },
    {
        id = "hud-report-screenshot",
        category = "hud",
        addon = "Blizzard_ReportFrameShared",
        frames = { "ReportScreenshotModeFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-visual-alerts",
        category = "hud",
        addon = "Blizzard_VisualAlerts",
        frames = { "VisualAlertsManager" },
        mode = hudAccentMode,
    },
    {
        id = "hud-azerite-animation",
        category = "hud",
        addon = "Blizzard_AzeriteEssenceUI",
        frames = { "AzeriteEssenceLearnAnimFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-commentator",
        category = "hud",
        addon = "Blizzard_Commentator",
        frames = { "CommentatorVictoryFanfareFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-action-status",
        category = "hud",
        addon = "Blizzard_ActionStatus",
        frames = { "ActionStatus" },
        mode = hudAccentMode,
    },
    {
        id = "hud-covenant-toasts",
        category = "hud",
        addon = "Blizzard_CovenantToasts",
        frames = { "CovenantChoiceToast", "CovenantRenownToast" },
        mode = hudAccentMode,
    },
    {
        id = "hud-major-faction-toasts",
        category = "hud",
        addon = "Blizzard_MajorFactions",
        frames = { "MajorFactionsRenownToast", "MajorFactionUnlockToast" },
        mode = hudAccentMode,
    },
    {
        id = "hud-cooldown-viewers",
        category = "hud",
        addon = "Blizzard_CooldownViewer",
        frames = {
            "BuffBarCooldownViewer", "BuffIconCooldownViewer",
            "EssentialCooldownViewer", "UtilityCooldownViewer",
        },
        mode = hudAccentMode,
    },
    {
        id = "hud-encounter-timeline",
        category = "hud",
        addon = "Blizzard_EncounterTimeline",
        frames = { "EncounterTimeline" },
        mode = hudAccentMode,
    },
    {
        id = "hud-encounter-warnings",
        category = "hud",
        addon = "Blizzard_EncounterWarnings",
        frames = { "CriticalEncounterWarnings", "MediumEncounterWarnings", "MinorEncounterWarnings" },
        mode = hudAccentMode,
    },
    {
        id = "hud-mirror-timers",
        category = "hud",
        addon = "Blizzard_MirrorTimer",
        frames = { "MirrorTimerContainer" },
        mode = hudAccentMode,
    },
    {
        id = "hud-quest-timer",
        category = "hud",
        addon = "Blizzard_QuestTimer",
        frames = { "QuestTimerFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-objective-status",
        category = "hud",
        addon = "Blizzard_ObjectiveTracker",
        frames = {
            "ScenarioRewardsFrame", "ScenarioTimerFrame",
            "ObjectiveTrackerTopBannerFrame", "ObjectiveTrackerUIWidgetContainer",
        },
        mode = hudAccentMode,
    },
    {
        id = "hud-pvp-status",
        category = "hud",
        addon = "Blizzard_PVPUI",
        frames = { "PvPObjectiveBannerFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-plunderstorm-prematch",
        category = "hud",
        addon = "Blizzard_PlunderstormPrematchUI",
        frames = { "PrematchHeaderFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-class-trial",
        category = "hud",
        addon = "Blizzard_ClassTrial",
        frames = { "ClassTrialTimerDisplay" },
        mode = hudAccentMode,
    },
    {
        id = "hud-subtitles",
        category = "hud",
        addon = "Blizzard_Subtitles",
        frames = { "SubtitlesFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-help-status",
        category = "hud",
        addon = "Blizzard_HelpFrame",
        frames = { "TicketStatusFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-gm-status",
        category = "hud",
        addon = "Blizzard_GMChatUI",
        frames = { "GMChatStatusFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-housing",
        category = "hud",
        addon = "Blizzard_HousingInspectModeUI",
        frames = { "HousingInspectModeManagerFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-housing-banner",
        category = "hud",
        addon = "Blizzard_HousingTemplates",
        frames = { "HousingTopBannerFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-fullscreen-browser",
        category = "hud",
        addon = "Blizzard_FullscreenBrowser",
        frames = { "FullscreenBrowserSpinnerFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-chat-overlays",
        category = "hud",
        addon = "Blizzard_ChatFrame",
        frames = { "ChatAlertFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-chat-autocomplete",
        category = "hud",
        addon = "Blizzard_AutoComplete",
        frames = { "AutoCompleteBox" },
        mode = safePanelMode,
    },
    {
        id = "hud-behavioral-message",
        category = "hud",
        addon = "Blizzard_BehavioralMessaging",
        frames = { "BehavioralMessagingTray" },
        mode = hudAccentMode,
    },
    {
        id = "hud-arrow-callouts",
        category = "hud",
        addon = "Blizzard_ArrowCalloutFrame",
        frames = { "ArrowCalloutFrameManager" },
        mode = hudAccentMode,
    },
    {
        id = "hud-world-loot-list",
        category = "hud",
        addon = "Blizzard_WorldLootObjectList",
        frames = { "WorldLootObjectList" },
        mode = hudAccentMode,
    },
    {
        id = "hud-item-belt",
        category = "hud",
        addon = "Blizzard_ItemBeltFrame",
        frames = { "ItemBeltFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-super-tracked",
        category = "hud",
        addon = "Blizzard_QuestNavigation",
        frames = { "SuperTrackedFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-raid-warnings",
        category = "hud",
        addon = "Blizzard_RaidWarning",
        frames = { "PrivateRaidBossEmoteFrameAnchor", "RaidWarningFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-widget-center-display",
        category = "hud",
        addon = "Blizzard_SharedWidgetFrames",
        frames = { "UIWidgetCenterDisplayFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-widget-containers",
        category = "hud",
        addon = "Blizzard_UIWidgets",
        frames = {
            "UIWidgetBelowMinimapContainerFrame", "UIWidgetCenterScreenContainerFrame",
            "UIWidgetSubZoneTextContainerFrame", "UIWidgetTopCenterContainerFrame",
        },
        mode = hudAccentMode,
    },
    {
        id = "hud-spell-pickup",
        category = "hud",
        addon = "Blizzard_SpellPickUpIndicator",
        frames = { "SpellPickupDisplay" },
        mode = hudAccentMode,
    },
    {
        id = "hud-motion-sickness",
        category = "hud",
        addon = "Blizzard_FrameXML",
        frames = { "MotionSicknessFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-move-pad",
        category = "hud",
        addon = "Blizzard_MovePad",
        frames = { "MovePadFrame" },
        mode = safePanelMode,
    },
    {
        id = "hud-extra-abilities",
        category = "hud",
        addon = "Blizzard_UIPanels_Game",
        frames = { "ExtraAbilityContainer" },
        mode = hudAccentMode,
    },
    {
        id = "hud-zone-ability",
        category = "hud",
        addon = "Blizzard_ZoneAbility",
        frames = { "ZoneAbilityFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-buffs",
        category = "hud",
        addon = "Blizzard_BuffFrame",
        frames = { "BuffFrame", "DebuffFrame", "DeadlyDebuffFrame", "ExternalDefensivesFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-action-bars",
        category = "hud",
        addon = "Blizzard_ActionBar",
        frames = {
            "MainActionBar", "MultiBar5", "MultiBar6", "MultiBar7",
            "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
            "PetActionBar", "PossessActionBar", "SpellFlyout", "StanceBar",
            "StatusTrackingBarManager", "ExtraActionBarFrame",
        },
        mode = hudAccentMode,
    },
    {
        id = "hud-action-reminders",
        category = "hud",
        addon = "Blizzard_ActionBar",
        frames = {
            "InteractLeftLootKeybindReminder", "InteractRightLootKeybindReminder",
            "PingKeybindReminder",
        },
        mode = hudAccentMode,
    },
    {
        id = "hud-override-action-bar",
        category = "hud",
        addon = "Blizzard_OverrideActionBar",
        frames = { "OverrideActionBar" },
        mode = hudAccentMode,
    },
    {
        id = "hud-unit-frames",
        category = "hud",
        addon = "Blizzard_UnitFrame",
        frames = {
            "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame", "PartyFrame",
            "BossTargetFrameContainer", "EncounterBar", "ComboFrame",
            "PlayerBuffTimerManager",
        },
        mode = hudAccentMode,
    },
    {
        id = "hud-class-resources",
        category = "hud",
        addon = "Blizzard_UnitFrame",
        frames = {
            "DevourerFuryBarFrame", "DruidComboPointBarFrame", "EssencePlayerFrame",
            "InsanityBarFrame", "MageArcaneChargesFrame", "MonkHarmonyBarFrame",
            "PaladinPowerBarFrame", "RogueComboPointBarFrame", "WarlockPowerFrame",
            "PlayerBottomManagedFrameContainer",
        },
        mode = hudAccentMode,
    },
    {
        id = "hud-nameplate-resources",
        category = "hud",
        addon = "Blizzard_NamePlates",
        frames = {
            "ClassNameplateBarDracthyrFrame", "ClassNameplateBarFeralDruidFrame",
            "ClassNameplateBarMageFrame", "ClassNameplateBarPaladinFrame",
            "ClassNameplateBarRogueFrame", "ClassNameplateBarWarlockFrame",
            "ClassNameplateBarWindwalkerMonkFrame",
        },
        mode = hudAccentMode,
    },
    {
        id = "hud-personal-resource",
        category = "hud",
        addon = "Blizzard_PersonalResourceDisplay",
        frames = { "PersonalResourceDisplayFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-bag-bar",
        category = "hud",
        addon = "Blizzard_MainMenuBarBagButtons",
        frames = { "BagsBar" },
        mode = hudAccentMode,
    },
    {
        id = "hud-minimap",
        category = "hud",
        addon = "Blizzard_Minimap",
        frames = { "MinimapCluster" },
        mode = hudAccentMode,
    },
    {
        id = "hud-addon-compartment",
        category = "hud",
        addon = "Blizzard_Minimap",
        frames = { "AddonCompartmentFrame" },
        skipGeneric = true,
    },
    {
        id = "hud-durability",
        category = "hud",
        addon = "Blizzard_DurabilityFrame",
        frames = { "DurabilityFrame" },
        mode = hudAccentMode,
    },
    {
        id = "hud-queue-status",
        category = "hud",
        addon = "Blizzard_QueueStatusFrame",
        frames = { "QueueStatusFrame" },
        mode = {
            role = "popup", maxDepth = 8, maxNodes = 400,
            allowImplicitProtected = false,
        },
    },
    {
        id = "hud-vehicle-seat",
        category = "hud",
        addon = "Blizzard_UIPanels_Game",
        frames = { "VehicleSeatIndicator" },
        mode = hudAccentMode,
    },
    {
        id = "hud-pet-battle-splash",
        category = "hud",
        addon = "Blizzard_PetBattleUI",
        frames = { "StartSplash" },
        mode = hudAccentMode,
    },
    {
        id = "hud-compact-raid",
        category = "hud",
        addon = "Blizzard_CompactRaidFrames",
        frames = { "CompactRaidFrameContainer", "CompactRaidFrameManager" },
        mode = hudAccentMode,
    },
    {
        id = "hud-account-store-container",
        category = "hud",
        addon = "Blizzard_AccountStore",
        frames = { "FullscreenAccountStoreContainer" },
        mode = hudAccentMode,
    },
    {
        id = "hud-kiosk",
        category = "hud",
        addon = "Blizzard_Kiosk",
        frames = {
            "KioskFrame", "KioskModeSplash", "KioskModeSplashEnd",
            "GameKioskSessionFinishedDialog", "GameKioskSessionStartedDialog",
        },
        mode = semanticOverlayMode,
        frameModes = {
            GameKioskSessionFinishedDialog = safeDialogMode,
            GameKioskSessionStartedDialog = safeDialogMode,
        },
    },

    -- Tutorial windows and instructional overlays are separate from HUD so a
    -- profile can keep Blizzard's onboarding presentation untouched.
    {
        id = "tutorial-boost",
        category = "tutorial",
        addon = "Blizzard_BoostTutorial",
        frames = {
            "NPE_TutorialMainFrame_Frame", "NPE_TutorialKeyboardMouseFrame_Frame",
            "NPE_TutorialInterfaceHelp",
        },
        mode = safeDialogMode,
        frameModes = { NPE_TutorialInterfaceHelp = hudAccentMode },
    },
    {
        id = "tutorial-manager",
        category = "tutorial",
        addon = "Blizzard_TutorialManager",
        frames = {
            "TutorialMainFrame_Frame", "TutorialSingleKey_Frame", "TutorialDoubleKey_Frame",
            "TutorialDragAnimationFrame", "TutorialDragOriginFrame", "TutorialDragTargetFrame",
        },
        mode = safeDialogMode,
        frameModes = {
            TutorialDragAnimationFrame = hudAccentMode,
            TutorialDragOriginFrame = hudAccentMode,
            TutorialDragTargetFrame = hudAccentMode,
        },
    },
    {
        id = "tutorial-new-player",
        category = "tutorial",
        addon = "Blizzard_NewPlayerExperience",
        frames = { "TutorialKeyboardMouseFrame_Frame", "TutorialWalk_Frame" },
        mode = safeDialogMode,
    },
    {
        id = "tutorial-managed",
        category = "tutorial",
        addon = "Blizzard_Tutorials",
        frames = { "RPETutorialInterrupt_Frame" },
        mode = safeDialogMode,
    },
    {
        id = "tutorial-help-plate",
        category = "tutorial",
        addon = "Blizzard_HelpPlate",
        frames = { "HelpPlateCanvas" },
        mode = hudAccentMode,
    },
    {
        id = "tutorial-nameplates",
        category = "tutorial",
        addon = "Blizzard_SettingsDefinitions_Frame",
        frames = { "NamePlatesTutorial" },
        mode = safeDialogMode,
    },
    {
        id = "tutorial-ping-system",
        category = "tutorial",
        addon = "Blizzard_SettingsDefinitions_Frame",
        frames = { "PingSystemTutorial" },
        mode = safeDialogMode,
    },
    {
        id = "tutorial-wardrobe-shortcuts",
        category = "tutorial",
        addon = "Blizzard_Collections",
        frames = { "TrackingInterfaceShortcutsFrame" },
        mode = safeDialogMode,
    },
    {
        id = "tutorial-remix-artifact",
        category = "tutorial",
        addon = "Blizzard_RemixArtifactTutorialUI",
        frames = { "RemixArtifactTutorialControllerFrame" },
        mode = hudAccentMode,
    },
    {
        id = "tutorial-garrison",
        category = "tutorial",
        addon = "Blizzard_GarrisonUI",
        frames = { "GarrisonMissionTutorialFrame", "OrderHallMissionTutorialFrame" },
        mode = safeDialogMode,
    },
    {
        id = "expansion-garrison-placers",
        category = "expansion",
        addon = "Blizzard_GarrisonUI",
        frames = {
            "CovenantFollowerPlacer", "GarrisonBuildingPlacer",
            "GarrisonBuildingPlacerFrame", "GarrisonFollowerPlacer",
            "GarrisonShipFollowerPlacer", "GarrisonShipyardMapMissionTooltip",
        },
        mode = hudAccentMode,
        frameModes = { GarrisonShipyardMapMissionTooltip = "tooltip" },
    },
    {
        id = "expansion-garrison-template-placer",
        category = "expansion",
        addon = "Blizzard_GarrisonTemplates",
        frames = { "GarrisonFollowerPlacerFrame" },
        mode = hudAccentMode,
    },
    {
        id = "expansion-artifact-underlay",
        category = "expansion",
        addon = "Blizzard_ArtifactUI",
        frames = { "ArtifactFrameUnderlay" },
        mode = hudAccentMode,
    },
    {
        id = "wardrobe-custom-set-dialog",
        category = "character",
        addon = "Blizzard_FrameXML",
        frames = { "WardrobeCustomSetEditFrame" },
        mode = safeDialogMode,
    },
    {
        id = "garrison-system-dialogs",
        category = "expansion",
        addon = "Blizzard_GarrisonTemplates",
        frames = {
            "GarrisonConfirmFollowerAbilityUpgradeFrame", "GarrisonThreatCountersFrame",
            "GarrisonTruncationFrame",
        },
        mode = safeDialogMode,
    },

    -- Midnight housing windows. Editor/inspection HUD and banners are covered
    -- above through accent-only roots; this section owns full windows/dialogs.
    {
        id = "house-list",
        category = "housing",
        addon = "Blizzard_HouseList",
        frames = { "HouseListFrame" },
    },
    {
        id = "house-editor",
        category = "housing",
        addon = "Blizzard_HouseEditor",
        frames = { "HouseEditorFrame", "DyeSelectionPopout" },
        mode = semanticOverlayMode,
        frameModes = { DyeSelectionPopout = safeDialogMode },
    },
    {
        id = "housing-controls",
        category = "housing",
        addon = "Blizzard_HousingControls",
        frames = { "HousingControlsFrame" },
        mode = semanticOverlayMode,
    },
    {
        id = "housing-blueprints",
        category = "housing",
        addon = "Blizzard_HousingBlueprint",
        frames = {
            "HousingBlueprintContentListFrame",
            "HousingBlueprintExportFrame",
            "HousingBlueprintImportFrame",
            "HousingBlueprintRenameFrame",
            "HousingBlueprintImportLoadingFrame",
        },
        frameModes = { HousingBlueprintImportLoadingFrame = hudAccentMode },
    },
    {
        id = "housing-bulletin-board",
        category = "housing",
        addon = "Blizzard_HousingBulletinBoard",
        frames = { "HousingBulletinBoardFrame", "HousingInviteResidentFrame" },
    },
    {
        id = "housing-bulletin-dialogs",
        category = "housing",
        addon = "Blizzard_HousingBulletinBoard",
        frames = { "NeighborhoodChangeNameDialog" },
        mode = "dialog",
    },
    {
        id = "housing-charter",
        category = "housing",
        addon = "Blizzard_HousingCharter",
        frames = { "HousingCharterFrame" },
    },
    {
        id = "housing-charter-dialogs",
        category = "housing",
        addon = "Blizzard_HousingCharter",
        frames = { "HousingCharterRequestSignatureDialog" },
        mode = "dialog",
    },
    {
        id = "housing-cornerstone",
        category = "housing",
        addon = "Blizzard_HousingCornerstone",
        frames = {
            "HousingCornerstoneFrame",
            "HousingCornerstonePurchaseFrame",
            "HousingCornerstoneVisitorFrame",
            "HousingCornerstoneHouseInfoFrame",
        },
    },
    {
        id = "housing-cornerstone-dialogs",
        category = "housing",
        addon = "Blizzard_HousingCornerstone",
        frames = {
            "BuyHouseConfirmationDialog",
            "MoveHouseConfirmationDialog",
            "ImportHouseConfirmationDialog",
        },
        mode = "dialog",
    },
    {
        id = "housing-create-neighborhood",
        category = "housing",
        addon = "Blizzard_HousingCreateNeighborhood",
        frames = { "HousingCreateGuildNeighborhoodFrame", "HousingCreateNeighborhoodCharterFrame" },
    },
    {
        id = "housing-create-neighborhood-dialogs",
        category = "housing",
        addon = "Blizzard_HousingCreateNeighborhood",
        frames = { "HousingCreateCharterNeighborhoodConfirmationFrame" },
        mode = "dialog",
    },
    {
        id = "housing-dashboard",
        category = "housing",
        addon = "Blizzard_HousingDashboard",
        frames = { "HousingDashboardFrame" },
        skipGeneric = true,
    },
    {
        id = "housing-house-finder",
        category = "housing",
        addon = "Blizzard_HousingHouseFinder",
        frames = { "HouseFinderFrame" },
        mode = "map",
    },
    {
        id = "housing-house-settings",
        category = "housing",
        addon = "Blizzard_HousingHouseSettings",
        frames = { "HousingHouseSettingsFrame" },
    },
    {
        id = "housing-house-settings-dialogs",
        category = "housing",
        addon = "Blizzard_HousingHouseSettings",
        frames = { "AbandonHouseConfirmationDialog" },
        mode = "dialog",
    },
    {
        id = "housing-model-preview",
        category = "housing",
        addon = "Blizzard_HousingModelPreview",
        frames = { "HousingModelPreviewFrame" },
    },
}

-- Glass coverage is a reviewed, fail-closed contract for the exact Retail
-- source snapshot named at the top of this file. The fingerprint covers entry
-- order, ids, categories, addon owners, skip flags, and ordered root names.
-- Any new, renamed, reordered, or re-owned root invalidates the whole catalog
-- until this review and its classification are updated deliberately.
local REVIEWED_CATALOG_FINGERPRINT = "7b0481aa-4dd0a23d"
local REVIEWED_CATALOG_ENTRIES = 242
local REVIEWED_CATALOG_ROOTS = 468

local dedicatedGlassOwners = {
    ["talking-head"] = "SharedChrome",
    ["communities"] = "CommunitiesSkin",
    ["social-ui"] = "SocialUISkin",
    ["battle-net-toasts"] = "SharedChrome",
    ["combat-log-navigation"] = "SharedChrome",
    ["encounter-journal"] = "EncounterJournalSkin",
    ["pvp"] = "MajorWindows",
    ["profession-book"] = "MajorWindows",
    ["inspect"] = "InspectPanel",
    ["item-interaction"] = "MajorWindows",
    ["item-socketing"] = "MajorWindows",
    ["item-upgrade"] = "MajorWindows",
    ["world-map"] = "WorldMapSkin",
    ["quick-keybind"] = "SharedChrome",
    ["hud-addon-compartment"] = "SharedChrome",
    ["housing-dashboard"] = "MajorWindows",
}

local partialDedicatedGlass = {
    ["talking-head"] = true,
    ["combat-log-navigation"] = true,
    ["quick-keybind"] = true,
    ["hud-addon-compartment"] = true,
}

local homogeneousGlassKinds = {}
local function MarkGlassKind(kind, ids)
    for index = 1, #ids do
        homogeneousGlassKinds[ids[index]] = kind
    end
end

MarkGlassKind("dedicated", {
    "talking-head", "communities", "social-ui", "battle-net-toasts",
    "combat-log-navigation", "encounter-journal", "pvp", "profession-book",
    "inspect", "item-interaction", "item-socketing", "item-upgrade",
    "world-map", "quick-keybind", "hud-addon-compartment", "housing-dashboard",
})

MarkGlassKind("semantic-content", {
    "end-of-match", "plunderstorm-basics", "pet-battle",
    "islands-party-pose", "match-celebration-party-pose",
    "warfronts-party-pose", "spectate", "perks-program", "catalog-shop",
    "character-customization", "splash-frame",
    "wow-survey", "housing-controls",
})

MarkGlassKind("semantic-chrome", {
    "battlefield-map", "anima-diversion",
})

MarkGlassKind("semantic-hud", {
    "group-finder-status", "hud-core-alerts", "hud-core-fullscreen",
    "hud-core-transient", "hud-report-screenshot", "hud-visual-alerts",
    "hud-azerite-animation", "hud-commentator", "hud-action-status",
    "hud-covenant-toasts", "hud-major-faction-toasts", "hud-cooldown-viewers",
    "hud-encounter-timeline", "hud-encounter-warnings", "hud-mirror-timers",
    "hud-quest-timer", "hud-objective-status", "hud-pvp-status",
    "hud-plunderstorm-prematch", "hud-class-trial", "hud-subtitles",
    "hud-help-status", "hud-gm-status", "hud-housing", "hud-housing-banner",
    "hud-fullscreen-browser", "hud-chat-overlays", "hud-behavioral-message",
    "hud-arrow-callouts", "hud-world-loot-list", "hud-item-belt",
    "hud-super-tracked", "hud-raid-warnings", "hud-widget-center-display",
    "hud-widget-containers", "hud-spell-pickup", "hud-motion-sickness",
    "hud-extra-abilities", "hud-zone-ability", "hud-buffs", "hud-action-bars",
    "hud-action-reminders", "hud-override-action-bar", "hud-unit-frames",
    "hud-class-resources", "hud-nameplate-resources", "hud-personal-resource",
    "hud-bag-bar", "hud-minimap", "hud-durability", "hud-vehicle-seat",
    "hud-pet-battle-splash", "hud-compact-raid", "hud-account-store-container",
    "tutorial-help-plate", "tutorial-remix-artifact",
    "expansion-garrison-template-placer", "expansion-artifact-underlay",
})

local mixedGlassKinds = {
    ["player-choice"] = {
        PlayerChoiceFrame = "generic-shell",
        PlayerChoiceTimeRemaining = "semantic-hud",
        CypherPlayerChoiceToggleButton = "semantic-hud",
        GenericPlayerChoiceToggleButton = "semantic-hud",
        TorghastPlayerChoiceToggleButton = "semantic-hud",
    },
    ["class-trial-dialogs"] = {
        ClassTrialThanksForPlayingDialog = "semantic-content",
        ExpansionTrialThanksForPlayingDialog = "generic-shell",
    },
    ["hud-kiosk"] = {
        KioskFrame = "semantic-content",
        KioskModeSplash = "semantic-content",
        KioskModeSplashEnd = "semantic-content",
        GameKioskSessionFinishedDialog = "generic-shell",
        GameKioskSessionStartedDialog = "generic-shell",
    },
    ["tutorial-boost"] = {
        NPE_TutorialMainFrame_Frame = "generic-shell",
        NPE_TutorialKeyboardMouseFrame_Frame = "generic-shell",
        NPE_TutorialInterfaceHelp = "semantic-hud",
    },
    ["tutorial-manager"] = {
        TutorialMainFrame_Frame = "generic-shell",
        TutorialSingleKey_Frame = "generic-shell",
        TutorialDoubleKey_Frame = "generic-shell",
        TutorialDragAnimationFrame = "semantic-hud",
        TutorialDragOriginFrame = "semantic-hud",
        TutorialDragTargetFrame = "semantic-hud",
    },
    ["expansion-garrison-placers"] = {
        CovenantFollowerPlacer = "semantic-hud",
        GarrisonBuildingPlacer = "semantic-hud",
        GarrisonBuildingPlacerFrame = "semantic-hud",
        GarrisonFollowerPlacer = "semantic-hud",
        GarrisonShipFollowerPlacer = "semantic-hud",
        GarrisonShipyardMapMissionTooltip = "generic-shell",
    },
    ["house-editor"] = {
        HouseEditorFrame = "semantic-content",
        DyeSelectionPopout = "generic-shell",
    },
    ["housing-blueprints"] = {
        HousingBlueprintContentListFrame = "generic-shell",
        HousingBlueprintExportFrame = "generic-shell",
        HousingBlueprintImportFrame = "generic-shell",
        HousingBlueprintRenameFrame = "generic-shell",
        HousingBlueprintImportLoadingFrame = "semantic-hud",
    },
}

-- These window owners are intentionally registered outside the generic
-- Blizzard catalog. Keep them in the same Glass audit so the headline root
-- inventory cannot hide standalone adapters or dynamic frame families.
local standaloneGlass = {
    { id = "colorPicker", addon = "Blizzard_ColorPickerFrame",
        roots = { "ColorPickerFrame", "OpacityFrame" }, owner = "GenericWindows", support = "full" },
    { id = "settings", addon = "Blizzard_Settings_Shared",
        roots = { "SettingsPanel" }, owner = "GenericWindows", support = "full" },
    { id = "addonList", addon = "Blizzard_AddOnList",
        roots = { "AddonList" }, owner = "GenericWindows", support = "full" },
    { id = "gameMenu", addon = "Blizzard_GameMenu",
        roots = { "GameMenuFrame" }, owner = "GameMenuSkin", support = "full" },
    { id = "playerSpells", addon = "Blizzard_PlayerSpells",
        roots = { "PlayerSpellsFrame" }, owner = "PlayerSpellsSkin", support = "full" },
    { id = "objectiveTracker", addon = "Blizzard_ObjectiveTracker",
        roots = { "ObjectiveTrackerFrame" }, owner = "ObjectiveTrackerSkin", support = "partial" },
    { id = "chatFrames", addon = "Blizzard_ChatFrameBase",
        roots = { "ChatFrame1" }, family = "ChatFrame%d", owner = "ChatFramesSkin", support = "partial" },
    { id = "damageMeter", addon = "Blizzard_DamageMeter",
        roots = { "DamageMeter" }, family = "DamageMeterSessionWindow%d",
        owner = "DamageMeterSkin", support = "full" },
    { id = "editMode", addon = "Blizzard_EditMode",
        roots = { "EditModeManagerFrame" }, owner = "EditModeSkin", support = "partial" },
    { id = "microMenu", addon = "Blizzard_MicroMenu",
        roots = { "MicroMenu" }, owner = "MicroMenuSkin", support = "partial" },
}

local nestedGlass = {
    { id = "auction-house-game-time-tutorial", addon = "Blizzard_AuctionHouseUI",
        parent = "AuctionHouseFrame", path = { "WoWTokenResults", "GameTimeTutorial" },
        owner = "GenericWindows", support = "full" },
}

-- Source-reviewed non-window candidates. Their explicit disposition prevents
-- a broad candidate scan from turning secure/HUD/glue objects into fake Glass
-- windows while still documenting why they are not skinned as shells.
local sourceExclusions = {
    { frame = "FramerateFrame", disposition = "hud-telemetry" },
    { frame = "UIThemeContainerFrame", disposition = "intrinsic-template" },
    { frame = "ReadyCheckFrame", disposition = "controller-wrapper" },
    { frame = "AuraButtonTooltip", disposition = "forbidden-scoped" },
    { frame = "PrivateAurasTooltip", disposition = "forbidden-scoped" },
    { frame = "SimpleCheckout", disposition = "forbidden-scoped" },
    { frame = "StoreFrame", disposition = "forbidden-scoped" },
    { frame = "StoreTooltip", disposition = "forbidden-scoped" },
    { frame = "ServicesLogoutPopup", disposition = "forbidden-scoped" },
    { frame = "StoreDialog", disposition = "forbidden-scoped" },
    { frame = "StoreConfirmationFrame", disposition = "forbidden-scoped" },
    { frame = "StoreVASValidationFrame", disposition = "forbidden-scoped" },
    { frame = "CommunitiesAddDialog", disposition = "forbidden-scoped" },
    { frame = "CommunitiesCreateDialog", disposition = "forbidden-scoped" },
    { frame = "AddonDialog", disposition = "glue-only" },
    { frame = "AccountSaveFrame", disposition = "glue-only" },
}

local function EntryRootSignature(entry)
    return type(entry) == "table" and type(entry.frames) == "table"
        and table.concat(entry.frames, "\31") or ""
end

local function CatalogFingerprint(catalogEntries)
    local parts = { tostring(#catalogEntries) }
    for index = 1, #catalogEntries do
        local entry = catalogEntries[index]
        parts[#parts + 1] = table.concat({
            type(entry.id) == "string" and entry.id or "",
            type(entry.category) == "string" and entry.category or "",
            type(entry.addon) == "string" and entry.addon or "",
            entry.skipGeneric == true and "1" or "0",
            EntryRootSignature(entry),
        }, "\30")
    end
    local text = table.concat(parts, "\29")
    local function Hash(seed, multiplier, modulus)
        local value = seed
        for index = 1, #text do
            value = (value * multiplier + text:byte(index)) % modulus
        end
        return value
    end
    return ("%08x-%08x"):format(
        Hash(216613626, 131, 2147483647),
        Hash(16777619, 137, 2147483629))
end

local reviewedFingerprint = CatalogFingerprint(entries)
local catalogSnapshotValid = reviewedFingerprint == REVIEWED_CATALOG_FINGERPRINT
    and #entries == REVIEWED_CATALOG_ENTRIES

local catalogEntrySet = {}
local reviewedEntrySignatures = {}
for entryIndex = 1, #entries do
    local entry = entries[entryIndex]
    catalogEntrySet[entry] = true
    reviewedEntrySignatures[entry] = EntryRootSignature(entry)
end

local glassByFrame = {}
local glassCounts = {
    total = 0,
    genericShell = 0,
    dedicated = 0,
    semanticContent = 0,
    semanticChrome = 0,
    semanticHUD = 0,
    full = 0,
    partial = 0,
    none = 0,
}
local glassErrors = {}
local glassReadyByEntry = {}

local function AddGlassError(entry, frameName, reason)
    glassErrors[#glassErrors + 1] = {
        id = entry and entry.id,
        frame = frameName,
        reason = reason,
    }
end

local function ModeForFrame(entry, frameName)
    local mode = type(entry.frameModes) == "table" and entry.frameModes[frameName]
        or entry.mode
    return mode
end

local function ResolveReviewedKind(entry, frameName)
    local mixed = mixedGlassKinds[entry.id]
    if mixed then return mixed[frameName] end
    return homogeneousGlassKinds[entry.id] or "generic-shell"
end

local function ModeMatchesKind(entry, frameName, kind)
    local mode = ModeForFrame(entry, frameName)
    if kind == "dedicated" then
        return entry.skipGeneric == true and dedicatedGlassOwners[entry.id] ~= nil
    end
    if entry.skipGeneric == true then return false end
    if kind == "semantic-hud" then
        return type(mode) == "table" and mode.rootSurface == false
            and mode.accentOnly == true
    end
    if kind == "semantic-content" then
        return type(mode) == "table" and mode.rootSurface == false
            and mode.accentOnly ~= true
    end
    if kind == "semantic-chrome" then
        return type(mode) == "table" and mode.rootSurface ~= false
            and mode.preserveRootArt == true and mode.fillVisible == false
            and mode.accentOnly ~= true
    end
    if kind == "generic-shell" then
        return type(mode) ~= "table" or (mode.rootSurface ~= false
            and mode.accentOnly ~= true
            and not (mode.preserveRootArt == true and mode.fillVisible == false))
    end
    return false
end

local function ResolveGlassContract(entry, frameName)
    local kind = ResolveReviewedKind(entry, frameName)
    if not kind then return nil, "root-classification-missing" end
    if not ModeMatchesKind(entry, frameName, kind) then
        return nil, "root-mode-contract-mismatch"
    end
    local owner = kind == "dedicated" and dedicatedGlassOwners[entry.id]
        or "GenericWindows"
    if not owner then return nil, "dedicated-owner-missing" end
    local support = "full"
    if kind == "semantic-hud" then
        support = "none"
    elseif kind == "semantic-content" or kind == "semantic-chrome"
        or (kind == "dedicated" and partialDedicatedGlass[entry.id]) then
        support = "partial"
    end
    return {
        kind = kind,
        owner = owner,
        support = support,
        reason = kind == "generic-shell" and "reviewed-catalog-glass-shell"
            or kind == "dedicated" and "dedicated-clean-room-adapter"
            or kind == "semantic-chrome" and "semantic-art-edge-only"
            or kind == "semantic-content" and "native-semantic-content"
            or "native-secure-or-semantic-hud",
    }
end

if not catalogSnapshotValid then
    AddGlassError(nil, nil, "catalog-snapshot-unreviewed:" .. reviewedFingerprint)
end

for entryIndex = 1, #entries do
    local entry = entries[entryIndex]
    local ready = catalogSnapshotValid and type(entry.id) == "string"
        and type(entry.frames) == "table"
    if not ready then
        AddGlassError(entry, nil, "entry-invalid")
    else
        for frameIndex = 1, #entry.frames do
            local frameName = entry.frames[frameIndex]
            if type(frameName) ~= "string" or frameName == "" then
                ready = false
                AddGlassError(entry, frameName, "frame-invalid")
            elseif glassByFrame[frameName] then
                ready = false
                AddGlassError(entry, frameName, "frame-duplicate")
            else
                local contract, reason = ResolveGlassContract(entry, frameName)
                if not contract then
                    ready = false
                    AddGlassError(entry, frameName, reason or "contract-missing")
                else
                    contract.id = entry.id
                    contract.frame = frameName
                    glassByFrame[frameName] = contract
                    glassCounts.total = glassCounts.total + 1
                    if contract.kind == "generic-shell" then
                        glassCounts.genericShell = glassCounts.genericShell + 1
                    elseif contract.kind == "dedicated" then
                        glassCounts.dedicated = glassCounts.dedicated + 1
                    elseif contract.kind == "semantic-content" then
                        glassCounts.semanticContent = glassCounts.semanticContent + 1
                    elseif contract.kind == "semantic-chrome" then
                        glassCounts.semanticChrome = glassCounts.semanticChrome + 1
                    elseif contract.kind == "semantic-hud" then
                        glassCounts.semanticHUD = glassCounts.semanticHUD + 1
                    end
                    glassCounts[contract.support] = glassCounts[contract.support] + 1
                end
            end
        end
    end
    glassReadyByEntry[entry] = ready
end

local flattened = {}
local byFrame = {}

for entryIndex = 1, #entries do
    local entry = entries[entryIndex]
    for frameIndex = 1, #entry.frames do
        local frameName = entry.frames[frameIndex]
        if not byFrame[frameName] then
            flattened[#flattened + 1] = frameName
            byFrame[frameName] = entry
        end
    end
end

local standaloneRootCount = 0
local standaloneSeen = {}
for index = 1, #standaloneGlass do
    local item = standaloneGlass[index]
    local valid = type(item.id) == "string" and type(item.addon) == "string"
        and type(item.owner) == "string" and type(item.roots) == "table"
        and (item.support == "full" or item.support == "partial")
    for rootIndex = 1, #(item.roots or {}) do
        local root = item.roots[rootIndex]
        standaloneRootCount = standaloneRootCount + 1
        if type(root) ~= "string" or root == "" or byFrame[root] or standaloneSeen[root] then
            valid = false
        end
        standaloneSeen[root] = true
    end
    if not valid then AddGlassError(item, nil, "standalone-contract-invalid") end
end

for index = 1, #nestedGlass do
    local item = nestedGlass[index]
    if type(item.id) ~= "string" or type(item.parent) ~= "string"
        or type(item.path) ~= "table" or #item.path == 0
        or type(item.owner) ~= "string" or not byFrame[item.parent] then
        AddGlassError(item, nil, "nested-contract-invalid")
    end
end

local exclusionSeen = {}
for index = 1, #sourceExclusions do
    local item = sourceExclusions[index]
    if type(item.frame) ~= "string" or item.frame == "" or byFrame[item.frame]
        or standaloneSeen[item.frame] or exclusionSeen[item.frame]
        or type(item.disposition) ~= "string" or item.disposition == "" then
        AddGlassError(item, item.frame, "source-exclusion-invalid")
    end
    exclusionSeen[item.frame] = true
end

local Catalog = {
    entries = entries,
    frames = flattened,
    byFrame = byFrame,
    glass = {
        valid = #glassErrors == 0,
        byFrame = glassByFrame,
        counts = glassCounts,
        errors = glassErrors,
        reviewedFingerprint = REVIEWED_CATALOG_FINGERPRINT,
        sourceRevision = "8ea15b61e45c0ed4eba01439c90757f86eb78d34",
        standalone = standaloneGlass,
        standaloneRootCount = standaloneRootCount,
        nested = nestedGlass,
        sourceExclusions = sourceExclusions,
    },
}
NS.BlizzardCatalog = Catalog

function Catalog.GetEntries()
    return entries
end

function Catalog.GetFrames()
    return flattened
end

function Catalog.FindByFrame(frameName)
    return byFrame[frameName]
end

function Catalog.GetGlassContract(frameName)
    return glassByFrame[frameName]
end

function Catalog.GetGlassCounts()
    return {
        total = glassCounts.total,
        genericShell = glassCounts.genericShell,
        dedicated = glassCounts.dedicated,
        semanticContent = glassCounts.semanticContent,
        semanticChrome = glassCounts.semanticChrome,
        semanticHUD = glassCounts.semanticHUD,
        full = glassCounts.full,
        partial = glassCounts.partial,
        none = glassCounts.none,
        standalone = standaloneRootCount,
        nested = #nestedGlass,
    }
end

function Catalog.GetGlassErrors()
    local result = {}
    for index = 1, #glassErrors do
        result[index] = glassErrors[index]
    end
    return result
end

function Catalog.IsGlassContractValid()
    return #glassErrors == 0
        and CatalogFingerprint(entries) == REVIEWED_CATALOG_FINGERPRINT
        and #entries == REVIEWED_CATALOG_ENTRIES
        and #flattened == REVIEWED_CATALOG_ROOTS
        and glassCounts.total == #flattened
end

function Catalog.ValidateGlassEntry(entry)
    return Catalog.IsGlassContractValid()
        and catalogEntrySet[entry] == true
        and reviewedEntrySignatures[entry] == EntryRootSignature(entry)
        and glassReadyByEntry[entry] == true
end

function Catalog.IsEntryGlassReady(entry)
    return type(entry) == "table" and catalogEntrySet[entry] == true
        and reviewedEntrySignatures[entry] == EntryRootSignature(entry)
        and glassReadyByEntry[entry] == true
end
