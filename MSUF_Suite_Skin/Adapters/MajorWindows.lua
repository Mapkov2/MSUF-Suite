local _, NS = ...

-- Purpose-built clean-room skins for visually unique Blizzard windows
-- which cannot be completed by the conservative catalog traversal alone.
-- Exact fields were verified against Gethe/wow-ui-source upstream/ptr at
-- a1f5e990cb945b0586a26789fa56bdc6c5331e89:
--
--   Blizzard_ProfessionsBook/Blizzard_ProfessionsBook.xml
--   Blizzard_HousingDashboard/*.xml and *.lua
--   Blizzard_PVPUI/Mainline/Blizzard_PVPUI.xml and *.lua
--   Blizzard_GroupFinder/Mainline/{PVEFrame,LFDFrame,LFGList}.xml
--   Blizzard_WeeklyRewards/{Blizzard_WeeklyRewards.xml,.lua}
--   Blizzard_ItemSocketingUI/Blizzard_ItemSocketingUI.xml
--   Blizzard_ItemInteractionUI/Blizzard_ItemInteractionUI.xml
--   Blizzard_ItemUpgradeUI/Mainline/Blizzard_ItemUpgradeUI.xml
--
-- The item-service fields are unchanged between upstream/live
-- 027d26c3406d3de2cbd2b1f67d468fe033a1bcd4 and upstream/ptr
-- e9e8bf68cb7b4177566532f8da9373590759587d.
--
-- Only explicitly named cosmetic regions and addon-owned surfaces are
-- changed. Blizzard scripts, anchors, data providers, secure profession
-- buttons, semantic icons, rewards and progress fills stay untouched.
local MajorWindows = {
    owners = {},
    waiting = {},
    indicators = setmetatable({}, { __mode = "k" }),
    activeOwnerCount = 0,
    housingCallbacksRegistered = false,
    -- HouseUpgradeFrame instances whose SetRewards is post-hooked
    rewardHooks = setmetatable({}, { __mode = "k" }),
}
NS.MajorWindows = MajorWindows

local Field = NS.Safety.Field
local Dispatch = NS.Safety.Dispatch
local Kit = NS.AdapterKit
local Path = Kit.Path
local Fade = Kit.Fade
local FadeFields = Kit.FadeFields
local Attach = Kit.Attach
local SkinControl = Kit.SkinControl
local SurfaceSpec = Kit.SurfaceSpec

local DEFAULT_OWNER = "blizzardWindows"
local HOUSING_SHOWN_CALLBACK = "HousingUpgradeFrame.Shown"

local groups = {
    {
        id = "profession-book",
        category = "profession",
        addon = "Blizzard_ProfessionsBook",
        root = "ProfessionsBookFrame",
    },
    {
        id = "housing-dashboard",
        category = "housing",
        addon = "Blizzard_HousingDashboard",
        root = "HousingDashboardFrame",
    },
    {
        id = "pvp",
        category = "group",
        addon = "Blizzard_PVPUI",
        root = "PVPUIFrame",
    },
    {
        id = "group-finder",
        category = "group",
        addon = "Blizzard_GroupFinder",
        root = "PVEFrame",
    },
    {
        id = "great-vault",
        category = "expansion",
        addon = "Blizzard_WeeklyRewards",
        root = "WeeklyRewardsFrame",
    },
    {
        id = "item-socketing",
        category = "item-service",
        addon = "Blizzard_ItemSocketingUI",
        root = "ItemSocketingFrame",
    },
    {
        id = "item-interaction",
        category = "item-service",
        addon = "Blizzard_ItemInteractionUI",
        root = "ItemInteractionFrame",
    },
    {
        id = "item-upgrade",
        category = "item-service",
        addon = "Blizzard_ItemUpgradeUI",
        root = "ItemUpgradeFrame",
    },
}

local SHELL = SurfaceSpec("shell", 8, 0)
local PANEL = SurfaceSpec("panel", 6, 0)
-- ProfessionsContentFrame exactly covers the book shell. A second material
-- fill there makes Glass nearly opaque, so it keeps only its edge.
local PANEL_EDGE = SurfaceSpec("panel", 6, 0, false, false, false)
local CARD = SurfaceSpec("card", 6, 0)
local CARD_INSET = SurfaceSpec("card", 6, 1)
local CARD_ROW = SurfaceSpec("card", 6, 1, true)
local SMALL_CARD = SurfaceSpec("card", 5, 0)
local SOCKET = SurfaceSpec("card", 5, 0, true)
local SLOT = SurfaceSpec("card", 5, 1, true)
local POPUP = SurfaceSpec("popup", 8, 0)
local PREVIEW_POPUP = SurfaceSpec("popup", 6, 0)
local STATUS = SurfaceSpec("status", 4, 1)
local FOOTER = SurfaceSpec("navigation", 5, 0)

local PRIMARY_BUTTON = {
    role = "button", activeRole = "buttonPrimary",
    radius = 5, inset = 1, pillHeight = 24,
}
local PVP_CATEGORY_BUTTON = {
    role = "navigation", radius = 8, inset = 2, pillHeight = 60,
    regions = { "Background", "Ring" },
}
local PVP_ACTIVITY = {
    role = "card", activeRole = "navigationActive", radius = 6,
    inset = 1, pillHeight = 54, listItem = true,
    regions = { "NormalTexture", "Bg" },
}
local GROUP_FINDER_NAVIGATION = {
    role = "navigation", activeRole = "navigationActive",
    radius = 6, inset = 2, pillHeight = 64,
    regions = { "bg", "ring" },
}
local VAULT_SELECT_BUTTON = {
    role = "button", activeRole = "buttonPrimary",
    radius = 5, inset = 1, pillHeight = 24,
    regions = { "Left", "Middle", "Right", "Background" },
}
local UPGRADE_DROPDOWN = {
    role = "button", radius = 5, inset = 1, pillHeight = 24,
    regions = { "Background" },
}

local PROFESSION_BOOK_MODE = {
    role = "shell", maxDepth = 6, maxNodes = 260,
    childSurfaces = false,
    allowImplicitProtected = true,
}
local HOUSING_MODE = {
    role = "shell", maxDepth = 9, maxNodes = 1000,
    allowImplicitProtected = true,
}
local PVP_MODE = {
    role = "panel", maxDepth = 9, maxNodes = 1000,
    allowImplicitProtected = true,
}
local GROUP_FINDER_MODE = {
    role = "shell", maxDepth = 10, maxNodes = 1200,
    registerDynamicRows = true, allowImplicitProtected = true,
}
local GREAT_VAULT_MODE = {
    role = "shell", maxDepth = 10, maxNodes = 1200,
    allowImplicitProtected = true,
}

local PROFESSION_CARDS = {
    "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1",
    "SecondaryProfession2", "SecondaryProfession3",
}
local PROFESSION_SPELL_BUTTONS = { "SpellButton1", "SpellButton2" }
local PVP_POPUP_FIELDS = {
    "Background", "BottomLeftCorner", "BottomRightCorner",
    "TopLeftCorner", "TopRightCorner", "BottomBorder", "TopBorder",
    "LeftBorder", "RightBorder", "LeftHide", "LeftHide2",
    "RightHide", "RightHide2", "BottomHide", "BottomHide2",
    "TopLeftFiligree", "TopRightFiligree",
}
local PVP_BONUS_BUTTONS = {
    "RandomBGButton", "RandomEpicBGButton", "Arena1Button",
    "BrawlButton", "BrawlButton2",
}
local PVP_RATED_BUTTONS = {
    "RatedSoloShuffle", "RatedBGBlitz", "Arena2v2", "Arena3v3", "RatedBG",
}
local GROUP_FINDER_CHROME = {
    "PVEFrameBlueBg", "PVEFrameTLCorner", "PVEFrameTRCorner",
    "PVEFrameBRCorner", "PVEFrameBLCorner", "PVEFrameLLVert",
    "PVEFrameRLVert", "PVEFrameBottomLine", "PVEFrameTopLine",
    "PVEFrameTopFiligree", "PVEFrameBottomFiligree",
}
local GROUP_FINDER_PANELS = { "LFDParentFrame", "RaidFinderFrame", "LFGListFrame", "ChallengesFrame" }
local LFG_LIST_PANELS = { "CategorySelection", "SearchPanel", "ApplicationViewer", "EntryCreation" }
local GROUP_FINDER_PANEL_ART = {
    "Background", "Bg", "TopTileStreaks", "RoleBackground",
    "InfoBackground", "CustomBG",
}
local INSET_ART = { "Background", "Bg" }
-- PVPQueueFrame's CategoryButton1..5 select these panels, in this order.
local PVP_CATEGORY_COUNT = 5
local GREAT_VAULT_ART = { "Background", "BorderShadow", "Divider1", "Divider2" }
local GREAT_VAULT_BORDER_ART = { "Border", "TopDecor" }
local GREAT_VAULT_HEADER_ART = { "HeaderDivider" }
local VAULT_WARNING_ART = { "ExtraBG" }
local SOCKET_FILIGREE = { "LeftFiligree", "RightFiligree" }
local ITEM_INTERACTION_FOOTER_ART = { "BlackBorder", "ButtonBorder", "ButtonBottomBorder" }
local INITIATIVE_TASKS_ART = { "BG", "BorderTop", "BorderRight", "TitleCornerTR" }
local INITIATIVE_ACTIVITY_ART = { "BG", "BGTexture", "BorderTop", "TitleCornerTR" }
local HOUSING_CATALOG_CARDS = { "Filters", "Categories", "OptionsContainer", "PreviewFrame" }
local HOUSING_COLLECTION_CARDS = { "Categories", "BlueprintCollection", "BlueprintDetails" }
local VAULT_TYPE_FRAMES = { "RaidFrame", "MythicFrame", "PVPFrame", "WorldFrame" }
local BACKGROUND_AND_BORDER = { "Background", "Border" }
local ITEM_SERVICE_SHELL_ART = { "Bg", "TopTileStreaks", "Portrait", "portrait" }
local ITEM_SOCKETING_ART = {
    "ParchmentFrame-Top", "ParchmentFrame-Bottom",
    "ParchmentFrame-Left", "ParchmentFrame-Right",
    "SocketFrame-Left", "SocketFrame-Right",
    "ButtonFrame-Left", "ButtonFrame-Right", "ButtonBorder-Mid",
    "GoldBorder-BottomRight", "GoldBorder-BottomLeft",
    "GoldBorder-TopRight", "GoldBorder-TopLeft",
    "GoldBorder-Left", "GoldBorder-Right",
    "GoldBorder-Top", "GoldBorder-Bottom",
    "BackgroundColor", "BackgroundHighlight",
    "BorderShadow-TopLeftCorner", "BorderShadow-TopRightCorner",
    "BorderShadow-BottomLeftCorner", "BorderShadow-BottomRightCorner",
    "BorderShadow-Top", "BorderShadow-Left",
    "BorderShadow-Bottom", "BorderShadow-Right",
    "BottomLeftNub", "BottomRightNub",
    "MiddleLeftNub", "MiddleRightNub",
    "TopLeftNub", "TopRightNub",
}
local ITEM_UPGRADE_ART = {
    "BottomBG", "BottomBGShadow", "TopBG", "IdleGlow", "MicaFleckSheen",
}
local ITEM_UPGRADE_PREVIEWS = {
    "LeftItemPreviewFrame", "RightItemPreviewFrame", "ItemHoverPreviewFrame",
}

local function CategoryEnabled(category)
    return NS.GenericWindows.IsCategoryEnabled(category)
end

local function OwnerState(owner)
    owner = owner or DEFAULT_OWNER
    local state = MajorWindows.owners[owner]
    if not state then
        state = {
            owner = owner,
            active = false,
            surfaces = Kit.WeakSet(),
            textColors = Kit.NewTextColors(),
        }
        MajorWindows.owners[owner] = state
    end
    return state
end

local function FadeNineSlice(state, target)
    Kit.FadeNineSlice(state, Field(target, "NineSlice"))
end

local function ApplyGeneric(root, owner, mode)
    return NS.GenericWindows.ApplyFrame(root, owner, mode)
end

-- The profession name plates are unnamed $parentNameFrame globals whose
-- parent must be the exact spell button.
local function FadeSpellNameFrame(state, button)
    local name = NS.Safety.Read(button, "GetName")
    if type(name) ~= "string" or name == "" then return end
    local nameFrame = _G[name .. "NameFrame"]
    if Kit.ParentIs(nameFrame, button) then Fade(state, nameFrame) end
end

local function SkinProfessionCard(state, card)
    if not card then return end
    Attach(state, card, CARD_INSET)
    for index = 1, #PROFESSION_SPELL_BUTTONS do
        FadeSpellNameFrame(state, Field(card, PROFESSION_SPELL_BUTTONS[index]))
    end
    local colors = state.textColors
    Kit.SetTextColor(colors, Field(card, "professionName"), "title")
    Kit.SetTextColor(colors, Field(card, "specialization"), "accentAlt")
    Kit.SetTextColor(colors, Field(card, "missingHeader"), "title")
    Kit.SetTextColor(colors, Field(card, "missingText"), "text")
    Kit.SetTextColor(colors, Field(card, "rank"), "muted")
end

local function SkinProfessionBook(root, state)
    local applied, reason = ApplyGeneric(root, state.owner, PROFESSION_BOOK_MODE)
    if not applied then return false, reason end

    Fade(state, _G.ProfessionsBookPage1)
    Fade(state, _G.ProfessionsBookPage2)
    Attach(state, _G.ProfessionsContentFrame, PANEL_EDGE)
    for index = 1, #PROFESSION_CARDS do
        SkinProfessionCard(state, _G[PROFESSION_CARDS[index]])
    end
    return true, "applied"
end

local function SkinHousingReward(state, reward)
    if not reward then return end
    Attach(state, reward, CARD_ROW)
    Fade(state, Field(reward, "Background"))
    Fade(state, Field(reward, "Divider"))
end

local function GetHousingUpgrade(root)
    return Path(root, "HouseInfoContent", "ContentFrame", "HouseUpgradeFrame")
end

local function SkinHousingPool(state, pool)
    if type((Field(pool, "EnumerateActive"))) ~= "function" then return end
    for reward in pool:EnumerateActive() do
        SkinHousingReward(state, reward)
    end
end

-- The reward cards Blizzard itself acquired for the selected level. The
-- pools are never driven from here: frames that addon code acquires are
-- created in addon (tainted) execution.
local function SkinHousingPools(state, upgrade)
    SkinHousingPool(state, Field(upgrade, "rewardPoolLarge"))
    SkinHousingPool(state, Field(upgrade, "rewardPoolSmall"))
end

local RefreshHousingRewards

-- HousingUpgradeFrameMixin:SetRewards (Blizzard_HousingDashboardHouseUpgrade.lua)
-- releases both pools and acquires, fills and shows the cards of the selected
-- level; its post-hook skins them before they are drawn. Each owner's pass is
-- its own error boundary.
local function OnHousingRewardsSet(upgrade)
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("major-windows:housing-rewards", RefreshHousingRewards)
        return
    end
    if not CategoryEnabled("housing") then return end
    for _, state in pairs(MajorWindows.owners) do
        if state.active then Dispatch(SkinHousingPools, state, upgrade) end
    end
end

-- The HouseUpgradeFrame carries its own copy of HousingUpgradeFrameMixin and
-- self:SetRewards() resolves on it, so the instance is hooked, once.
local function HookHousingRewards(upgrade)
    if not upgrade or MajorWindows.rewardHooks[upgrade] then return end
    MajorWindows.rewardHooks[upgrade] = Kit.HookFunction(upgrade, "SetRewards", OnHousingRewardsSet)
end

-- GetLayoutChildren returns one list table; GetChildren returns frames.
local function SkinHousingRewardList(state, first, ...)
    if select("#", ...) == 0 and type(first) == "table"
        and type((Field(first, "GetObjectType"))) ~= "function" then
        for index = 1, #first do
            SkinHousingReward(state, first[index])
        end
        return
    end
    SkinHousingReward(state, first)
    for index = 1, select("#", ...) do
        SkinHousingReward(state, (select(index, ...)))
    end
end

local function SkinHousingRewards(root, state)
    local rewards = Path(root, "HouseInfoContent", "ContentFrame", "HouseUpgradeFrame", "RewardsFrame")
    if not rewards then return end
    Attach(state, rewards, PANEL)

    local method = type((Field(rewards, "GetLayoutChildren"))) == "function" and "GetLayoutChildren"
        or "GetChildren"
    SkinHousingRewardList(state, NS.Safety.Call(rewards, method))
    local upgrade = GetHousingUpgrade(root)
    SkinHousingPools(state, upgrade)
    HookHousingRewards(upgrade)
end

local function SkinHousingInitiatives(root, state)
    local initiatives = Path(root, "HouseInfoContent", "ContentFrame", "InitiativesFrame")
    if not initiatives then return end
    Attach(state, initiatives, PANEL)

    local art = Field(initiatives, "InitiativesArt")
    Fade(state, Field(art, "InitiativesBG"))
    Kit.FadeNativeTextures(state, Field(art, "BorderArt"))

    local setFrame = Field(initiatives, "InitiativeSetFrame")
    local tasks = Field(setFrame, "InitiativeTasks")
    local activity = Field(setFrame, "InitiativeActivity")
    Attach(state, tasks, CARD)
    Attach(state, activity, CARD)
    FadeFields(state, tasks, INITIATIVE_TASKS_ART)
    FadeFields(state, activity, INITIATIVE_ACTIVITY_ART)
end

local function SkinHousingCollection(state, collection, cardKeys)
    Attach(state, collection, PANEL)
    Fade(state, Field(collection, "Background"))
    for index = 1, #cardKeys do
        Attach(state, Field(collection, cardKeys[index]), CARD)
    end
    Fade(state, Field(collection, "Divider"))
end

local function SkinHousingContent(root, state)
    local houseInfo = Field(root, "HouseInfoContent")
    local noHouse = Field(houseInfo, "DashboardNoHousesFrame")
    local content = Field(houseInfo, "ContentFrame")
    local upgrade = Field(content, "HouseUpgradeFrame")

    Attach(state, houseInfo, PANEL)
    Attach(state, noHouse, PANEL)
    Fade(state, Field(noHouse, "Background"))
    Attach(state, content, PANEL)
    Attach(state, upgrade, PANEL)
    -- Every direct texture on HousingUpgradeFrame is verified decorative:
    -- the full Elwynn background, four filigree corners and header divider.
    -- The level medallion, progress fill and reward icons are child frames.
    Kit.FadeNativeTextures(state, upgrade)
    Attach(state, Field(upgrade, "TrackFrame"), CARD)
    Fade(state, Path(upgrade, "TrackFrame", "Background"))

    SkinHousingCollection(state, Field(root, "CatalogContent"), HOUSING_CATALOG_CARDS)
    local collection = Field(root, "CollectionContent")
    SkinHousingCollection(state, collection, HOUSING_COLLECTION_CARDS)
    Fade(state, Path(collection, "BlueprintDetails", "PreviewBackground"))

    SkinHousingInitiatives(root, state)
    SkinHousingRewards(root, state)
end

local function SkinHousingDashboard(root, state)
    local applied, reason = ApplyGeneric(root, state.owner, HOUSING_MODE)
    if not applied then return false, reason end
    SkinHousingContent(root, state)
    return true, "applied"
end

local function SkinPVPStatus(state, statusBar)
    if not statusBar then return end
    Attach(state, statusBar, STATUS)
    FadeFields(state, statusBar, BACKGROUND_AND_BORDER)
end

local function SkinPVPActivity(state, button)
    SkinControl(state, button, PVP_ACTIVITY)
end

local function SkinPVPPopup(state, popup)
    if not popup then return end
    Attach(state, popup, POPUP)
    FadeFields(state, popup, PVP_POPUP_FIELDS)
end

local function SkinInsetCard(state, inset)
    Attach(state, inset, CARD)
    FadeNineSlice(state, inset)
    Fade(state, Field(inset, "Bg"))
end

-- The five panels in category order; reused, and a missing panel stays a
-- nil slot instead of shortening the list (the length of a table with nil
-- holes is undefined in Lua).
local pvpPanels = {}

local function SkinPVPCategories(state, queue)
    for index = 1, PVP_CATEGORY_COUNT do
        local button = Field(queue, "CategoryButton" .. index)
        SkinControl(state, button, PVP_CATEGORY_BUTTON)
        Kit.SelectionIndicator(state, MajorWindows.indicators, button, pvpPanels[index])
        pvpPanels[index] = nil
    end
end

local function SkinPVPQueuePanel(state, panel)
    SkinInsetCard(state, Field(panel, "Inset"))
    SkinPVPStatus(state, Field(panel, "ConquestBar"))
end

local function SkinPVPContent(root, state)
    local queue = _G.PVPQueueFrame or Field(root, "PVPQueueFrame")
    if not queue then return end

    local honor = _G.HonorFrame or Field(queue, "HonorFrame")
    local conquest = _G.ConquestFrame or Field(queue, "ConquestFrame")
    local training = _G.TrainingGroundsFrame or Field(queue, "TrainingGroundsFrame")
    local plunder = _G.PlunderstormFrame or Field(queue, "PlunderstormFrame")
    pvpPanels[1], pvpPanels[2], pvpPanels[3], pvpPanels[4], pvpPanels[5] = honor, conquest,
        _G.LFGListPVPStub or Field(queue, "LFGListPVPStub"), training, plunder
    SkinPVPCategories(state, queue)

    -- The category panels are visibility/controller frames, not visual
    -- panels. In Blizzard's PvP layout their content uses the same frame
    -- level as the controller, so a late full-frame surface can composite
    -- above and hide the Rated queue rows. Skin the concrete Insets/cards.
    SkinPVPQueuePanel(state, honor)
    SkinPVPQueuePanel(state, conquest)
    SkinPVPQueuePanel(state, training)

    local bonus = Field(honor, "BonusFrame")
    Attach(state, bonus, PANEL)
    Fade(state, Field(bonus, "WorldBattlesTexture"))
    for index = 1, #PVP_BONUS_BUTTONS do
        SkinPVPActivity(state, Field(bonus, PVP_BONUS_BUTTONS[index]))
    end

    Fade(state, Field(conquest, "RatedBGTexture"))
    for index = 1, #PVP_RATED_BUTTONS do
        SkinPVPActivity(state, Field(conquest, PVP_RATED_BUTTONS[index]))
    end

    local trainingBonus = Field(training, "BonusTrainingGroundList")
    Attach(state, trainingBonus, PANEL)
    Fade(state, Field(trainingBonus, "WorldBattlesTexture"))
    SkinPVPActivity(state, Field(trainingBonus, "RandomTrainingGroundButton"))
    SkinPVPActivity(state, Field(trainingBonus, "RandomTrainingGroundArenaButton"))

    Fade(state, Field(plunder, "Background"))
    SkinInsetCard(state, Field(plunder, "Inset"))

    local honorInset = Field(queue, "HonorInset")
    SkinInsetCard(state, honorInset)
    Fade(state, Field(honorInset, "Background"))

    SkinPVPPopup(state, Field(queue, "NewSeasonPopup"))
    local prestige = Field(queue, "PrestigeLevelDialog")
    if prestige then
        Attach(state, prestige, POPUP)
        FadeNineSlice(state, prestige)
    end
end

local function SkinPVP(root, state)
    local applied, reason = ApplyGeneric(root, state.owner, PVP_MODE)
    if not applied then return false, reason end
    SkinPVPContent(root, state)
    return true, "applied"
end

local function SkinGroupFinderPanel(state, panel)
    if not panel then return end
    Attach(state, panel, PANEL)
    FadeFields(state, panel, GROUP_FINDER_PANEL_ART)
    local inset = Field(panel, "Inset")
    if inset then
        Attach(state, inset, CARD)
        FadeNineSlice(state, inset)
        FadeFields(state, inset, INSET_ART)
    end
end

local function SkinGroupFinder(root, state)
    local applied, reason = ApplyGeneric(root, state.owner, GROUP_FINDER_MODE)
    if not applied then return false, reason end

    -- PVEFrame.xml keeps the blue rail and most gold dividers as named global
    -- textures rather than parentKey fields. They are exact window chrome;
    -- the category icons and labels remain untouched.
    for index = 1, #GROUP_FINDER_CHROME do
        Fade(state, _G[GROUP_FINDER_CHROME[index]])
    end

    -- Blizzard raises this exact chrome-only frame above the navigation rail.
    -- Fading its parent removes the anonymous gold divider regardless of rect
    -- state or region order; PVEFrame_ShowLeftInset only toggles Show/Hide.
    Fade(state, Field(root, "shadows"))

    -- PVEFrame.xml defines GroupFinderFrame with the root, so it exists
    -- whenever this runs (Forever has neither: Blizzard_GroupFinder
    -- excludes the camelot game type, and the root is never resolved there).
    local navigation = GroupFinderFrame
    for index = 1, 4 do
        local button = Field(navigation, "groupButton" .. index)
            or _G["GroupFinderFrameGroupButton" .. index]
        SkinControl(state, button, GROUP_FINDER_NAVIGATION)
    end

    for index = 1, #GROUP_FINDER_PANELS do
        SkinGroupFinderPanel(state, _G[GROUP_FINDER_PANELS[index]])
    end
    local list = _G.LFGListFrame
    for index = 1, #LFG_LIST_PANELS do
        SkinGroupFinderPanel(state, Field(list, LFG_LIST_PANELS[index]))
    end
    return true, "applied"
end

local function SkinGreatVault(root, state)
    local applied, reason = ApplyGeneric(root, state.owner, GREAT_VAULT_MODE)
    if not applied then return false, reason end

    FadeFields(state, root, GREAT_VAULT_ART)
    FadeFields(state, Field(root, "BorderContainer"), GREAT_VAULT_BORDER_ART)
    FadeFields(state, Field(root, "HeaderFrame"), GREAT_VAULT_HEADER_ART)

    for index = 1, #VAULT_TYPE_FRAMES do
        local typeFrame = Field(root, VAULT_TYPE_FRAMES[index])
        if typeFrame then
            Attach(state, typeFrame, PANEL)
            FadeFields(state, typeFrame, BACKGROUND_AND_BORDER)
        end
    end

    -- WeeklyRewardsMixin creates every selectable activity during OnLoad and
    -- exposes the stable list as Activities. Preserve completion icons,
    -- reward effects and item icons; replace only each card's base chrome.
    local activities = Field(root, "Activities")
    if type(activities) == "table" then
        for index = 1, #activities do
            local activity = activities[index]
            if activity then
                Attach(state, activity, CARD_ROW)
                FadeFields(state, activity, BACKGROUND_AND_BORDER)
            end
        end
    end

    SkinControl(state, Field(root, "SelectRewardButton"), VAULT_SELECT_BUTTON)

    local warning = _G.WeeklyRewardExpirationWarningDialog
    if warning then
        Attach(state, warning, POPUP)
        FadeNineSlice(state, warning)
        FadeFields(state, warning, VAULT_WARNING_ART)
    end
    return true, "applied"
end

local function SkinExactItemServiceShell(root, state)
    Attach(state, root, SHELL)
    FadeNineSlice(state, root)
    FadeFields(state, root, ITEM_SERVICE_SHELL_ART)
    Fade(state, Path(root, "PortraitContainer", "portrait"))
    Fade(state, Path(root, "PortraitContainer", "Portrait"))
end

local function SkinItemSocketing(root, state)
    SkinExactItemServiceShell(root, state)

    -- These exact fields are the parchment, gold frame, shadow and rivet
    -- layers around Blizzard's socket data. The socket Background, Icon,
    -- brackets, Shine and interaction textures remain native and visible.
    FadeFields(state, root, ITEM_SOCKETING_ART)

    local description = _G.ItemSocketingDescription
    Attach(state, description, PANEL)
    FadeNineSlice(state, description)

    local container = Field(root, "SocketingContainer")
    local sockets = Field(container, "SocketFrames")
    if type(sockets) == "table" then
        for index = 1, #sockets do
            local socket = sockets[index]
            if socket then
                Attach(state, socket, SOCKET)
                FadeFields(state, socket, SOCKET_FILIGREE)
            end
        end
    end
    SkinControl(state, Field(container, "ApplySocketsButton"), PRIMARY_BUTTON)
    return true, "applied"
end

local function SkinItemInteraction(root, state)
    SkinExactItemServiceShell(root, state)

    -- Background is the Blizzard-selected interaction texture kit. Keep it,
    -- along with conversion borders and celebration layers, as native state.
    local footer = Field(root, "ButtonFrame")
    Attach(state, footer, FOOTER)
    FadeFields(state, footer, ITEM_INTERACTION_FOOTER_ART)
    Kit.FadeNativeTextures(state, Field(footer, "MoneyFrameEdge"))
    SkinControl(state, Field(footer, "ActionButton"), PRIMARY_BUTTON)

    -- The slot surface is cosmetic only. Icon/GlowOverlay and all conversion
    -- input/output borders, arrows, flashes and texture-kit states stay native.
    Attach(state, Field(root, "ItemSlot"), SLOT)
    return true, "applied"
end

local function SkinItemUpgrade(root, state)
    SkinExactItemServiceShell(root, state)

    -- Suppress only the static panel ornament. BottomPanel_Flash, Ring,
    -- tooltip glow pieces, arrows and button glow remain Blizzard-owned so the
    -- complete upgrade-success and interaction feedback is preserved.
    FadeFields(state, root, ITEM_UPGRADE_ART)

    local itemButton = Field(root, "UpgradeItemButton")
    Attach(state, itemButton, SLOT)
    -- ButtonFrame is static slot ornament. IconBorder remains native because
    -- SetItemButtonQuality updates it whenever the selected item/target quality
    -- changes; no addon lifecycle hook is needed to preserve that state.
    Fade(state, Field(itemButton, "ButtonFrame"))

    for index = 1, #ITEM_UPGRADE_PREVIEWS do
        local key = ITEM_UPGRADE_PREVIEWS[index]
        local preview = Field(root, key)
        Attach(state, preview, key == "ItemHoverPreviewFrame" and PREVIEW_POPUP or CARD)
        -- ItemUpgradePreviewTemplate also owns GlowNineSlice; fading only the
        -- inherited NineSlice keeps that success effect intact.
        FadeNineSlice(state, preview)
    end

    local cost = Field(root, "UpgradeCostFrame")
    Attach(state, cost, SMALL_CARD)
    Fade(state, Field(cost, "BGTex"))
    Kit.FadeNativeTextures(state, Field(root, "PlayerCurrenciesBorder"))
    SkinControl(state, Field(root, "UpgradeButton"), PRIMARY_BUTTON)
    SkinControl(state, Path(root, "ItemInfo", "Dropdown"), UPGRADE_DROPDOWN)
    return true, "applied"
end

local groupSkinners = {
    ["profession-book"] = SkinProfessionBook,
    ["housing-dashboard"] = SkinHousingDashboard,
    pvp = SkinPVP,
    ["group-finder"] = SkinGroupFinder,
    ["great-vault"] = SkinGreatVault,
    ["item-socketing"] = SkinItemSocketing,
    ["item-interaction"] = SkinItemInteraction,
    ["item-upgrade"] = SkinItemUpgrade,
}

local function ApplyGroup(spec, state)
    if not state or not state.active then return false, "disabled" end
    if NS.IsCombatLocked() then return false, "combat" end
    if not CategoryEnabled(spec.category) then return true, "disabled" end
    local root = _G[spec.root]
    if not root then return false, NS.Client.IsAddOnLoaded(spec.addon) and "missing" or "waiting" end
    -- Each group is its own error boundary: a raising group is reported and
    -- the other groups (and owners) still apply.
    local finished, applied, reason = Kit.Isolate(groupSkinners[spec.id], root, state)
    if not finished then return false, "error" end
    return applied, reason
end

local function ApplyGroupForOwners(spec)
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("major-windows:load:" .. spec.id, function()
            ApplyGroupForOwners(spec)
        end)
        return
    end
    for _, state in pairs(MajorWindows.owners) do
        if state.active then ApplyGroup(spec, state) end
    end
end

RefreshHousingRewards = function()
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("major-windows:housing-rewards", RefreshHousingRewards)
        return
    end
    local root = _G.HousingDashboardFrame
    if not root or not CategoryEnabled("housing") then return end
    for _, state in pairs(MajorWindows.owners) do
        if state.active then SkinHousingRewards(root, state) end
    end
end

local function Schedule(spec)
    if MajorWindows.waiting[spec.id] then return true end
    if NS.Client.IsAddOnLoaded(spec.addon) then return false end
    MajorWindows.waiting[spec.id] = true
    EventUtil.ContinueOnAddOnLoaded(spec.addon, function()
        MajorWindows.waiting[spec.id] = nil
        ApplyGroupForOwners(spec)
        if spec.id == "housing-dashboard" then MajorWindows.RegisterHousingCallbacks() end
    end)
    return true
end

-- Reward cards that arrive later (their data loads asynchronously) come
-- through the SetRewards post-hook.
local function OnHousingUpgradeShown()
    RefreshHousingRewards()
end

function MajorWindows.RegisterHousingCallbacks()
    if MajorWindows.housingCallbacksRegistered or not _G.HousingDashboardFrame then
        return false
    end
    EventRegistry:RegisterCallback(HOUSING_SHOWN_CALLBACK, OnHousingUpgradeShown, MajorWindows)
    MajorWindows.housingCallbacksRegistered = true
    return true
end

local function UnregisterHousingCallbacks()
    if not MajorWindows.housingCallbacksRegistered then return end
    EventRegistry:UnregisterCallback(HOUSING_SHOWN_CALLBACK, MajorWindows)
    MajorWindows.housingCallbacksRegistered = false
end

function MajorWindows.OnThemeChanged(_, domain)
    if domain ~= "theme" and domain ~= "profile" and domain ~= "color" then return end
    if NS.IsCombatLocked() then return end
    for _, state in pairs(MajorWindows.owners) do
        if state.active then Kit.RefreshTextColors(state.textColors) end
    end
end

function MajorWindows.Apply(owner)
    local state = OwnerState(owner)
    if not state.active then
        state.active = true
        MajorWindows.activeOwnerCount = MajorWindows.activeOwnerCount + 1
    end
    if NS.IsCombatLocked() then return false, "combat" end

    local applied, waiting, failed = 0, 0, 0
    for index = 1, #groups do
        local spec = groups[index]
        if CategoryEnabled(spec.category) then
            local ok, reason = ApplyGroup(spec, state)
            if ok then
                applied = applied + 1
            elseif reason == "waiting" and Schedule(spec) then
                waiting = waiting + 1
            else
                failed = failed + 1
            end
        end
    end
    MajorWindows.RegisterHousingCallbacks()
    NS.Registry.AddListener(MajorWindows, MajorWindows.OnThemeChanged)

    if failed > 0 and applied == 0 and waiting == 0 then return false, "missing" end
    if failed > 0 then return true, "partial" end
    if waiting > 0 and applied == 0 then return true, "waiting" end
    return true, waiting > 0 and "partial" or "applied"
end

function MajorWindows.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local state = MajorWindows.owners[owner]
    if not state then return true end
    if NS.IsCombatLocked() then return false, "combat" end
    state.active = false
    Kit.HideSurfaces(state)
    Kit.HideIndicators(MajorWindows.indicators)
    Kit.RestoreTextColors(state.textColors)
    MajorWindows.owners[owner] = nil
    MajorWindows.activeOwnerCount = math.max(0, MajorWindows.activeOwnerCount - 1)
    if MajorWindows.activeOwnerCount == 0 then
        UnregisterHousingCallbacks()
        NS.Registry.RemoveListener(MajorWindows)
        NS.CombatGate.Cancel("major-windows:housing-rewards")
        for index = 1, #groups do
            NS.CombatGate.Cancel("major-windows:load:" .. groups[index].id)
        end
    end
    -- GenericWindows owns shared ControlSkin/Cosmetics restoration and runs
    -- after this module in the blizzardWindows adapter teardown.
    return true
end

function MajorWindows.GetIndicator(button)
    return MajorWindows.indicators[button]
end

function MajorWindows.GetWaitingCount()
    local count = 0
    for _ in pairs(MajorWindows.waiting) do count = count + 1 end
    return count
end

return MajorWindows
