local _, NS = ...

-- Reviewed native top-level windows. This is geometry policy, not a frame scan;
-- catalog membership alone never turns HUD, tooltips or nested panes into windows.
local Policy = {}
NS.WindowControlPolicy = Policy
local Safety = NS.Safety
local inventoryRoots = {
    BankFrame = true, ContainerFrameCombinedBags = true,
    ContainerFrame1 = true, ContainerFrame2 = true, ContainerFrame3 = true,
    ContainerFrame4 = true, ContainerFrame5 = true, ContainerFrame6 = true,
}

function Policy.IsInventory(frame)
    local name = Safety.Read(frame, "GetName")
    return inventoryRoots[name] == true and frame == Safety.Field(_G, name)
end

local specialPanels = {
    SettingsPanel = true, AddonList = true, PlayerSpellsFrame = true,
    GameMenuFrame = true, ProfessionsFrame = true,
    SocialUIFrame = true, FriendsFrame = true, FriendsFriendsFrame = true,
    DeathRecapFrame = true, ClickBindingFrame = true, GuideFrame = true,
    SubscriptionInterstitialFrame = true, CurrencyTransferMenu = true,
    ChatConfigFrame = true, HelpFrame = true, CooldownViewerSettings = true,
    ColorPickerFrame = true, OpacityFrame = true, ScriptErrorsFrame = true,
    ModelPreviewFrame = true, EventTrace = true, TimeManagerFrame = true,
    -- Forever's dedicated skin applies this outer container; its three
    -- PortraitFrame panes follow it and are not generic catalog roots.
    LFGParentFrame = true,
}
local compactWidths = { OpacityFrame = 80, TimeManagerFrame = 220 }
local nativeParentRoots = { FriendsFrame = true, SocialUIFrame = true, ModelPreviewFrame = true }
local excludedCategories = {
    hud = true, inventory = true, tutorial = true, utility = true,
}

local function IsBag(name)
    return name:find("^ContainerFrame") or name:find("^BankFrame")
        or name:find("^Bag") or name:find("^Bags")
end

function Policy.CanChangeGeometry(frame)
    if Safety.IsForbidden(frame) then return false end
    local name = Safety.Read(frame, "GetName")
    local inventory = inventoryRoots[name]
    if inventory and not Policy.IsInventory(frame) then return false end
    local protected, explicit = Safety.GetProtection(frame)
    if explicit then return false end
    -- Secure spell buttons make these plain native book containers implicit.
    -- Forever embeds the profession book in its main profession window.
    local nativeBook = name == "PlayerSpellsFrame" or name == "ProfessionsBookFrame"
        or name == "ProfessionsFrame" and NS.Client.isForever
    return not protected or (not NS.IsCombatLocked() and (inventory or nativeBook and frame == Safety.Field(_G, name)))
end

-- Geometry release may run just after another Suite module claims the root.
-- Ordinary controls and callbacks additionally respect that current owner.
function Policy.CanControl(frame)
    if Policy.IsInventory(frame) and NS.SuiteOwnership.OwnsWindowGeometry(frame) then return false end
    return Policy.CanChangeGeometry(frame)
end

local focusCompanions = {
    OpenMailFrame = true, WorldMapFrame = true,
    BattleNetInviteFrame = true, AddFriendFrame = true, AuctionHouseMultisellProgressFrame = true,
    CatalogShopFrame = true, CatalogShopRefundFrame = true, CatalogShopTopUpFrame = true,
    CreateChannelPopup = true, CommunitiesAvatarPickerDialog = true, CommunitiesSettingsDialog = true,
    CommunitiesTicketManagerDialog = true, CovenantPreviewFrame = true,
    ExpansionTrialThanksForPlayingDialog = true, ExpansionTrialCheckPointDialog = true, GuildInviteFrame = true,
    GroupLootHistoryFrame = true, RolePollPopup = true, WardrobeCustomSetEditFrame = true,
    LFDRoleCheckPopup = true, LFGDungeonReadyPopup = true, LFGInvitePopup = true, LFGListApplicationDialog = true,
    LFGListInviteDialog = true, PVPFramePopup = true, PlunderstormFramePopup = true, PVPRoleCheckPopup = true,
    PVPReadyDialog = true, PVPReadyPopup = true, LFGReadyCheckPopup = true, ReportCheatingDialog = true,
    IslandsQueueFrame = true, PhotoSharingFrame = true, PhotoSharingBrowserFrame = true,
    PhotoSharingBrowserPopup = true, QuickJoinRoleSelectionFrame = true, RecruitAFriendRewardsFrame = true,
    RecruitAFriendRecruitmentFrame = true, ReportFrame = true, SecureTransferDialog = true, SplashFrame = true,
    PetBattleQueueReadyFrame = true, BankCleanUpConfirmationPopup = true, SideDressUpFrame = true,
    MasterLooterFrame = true, WowTokenRedemptionFrame = true, WowTokenDialog = true,
    NeighborhoodChangeNameDialog = true, HousingCharterRequestSignatureDialog = true,
    BuyHouseConfirmationDialog = true, MoveHouseConfirmationDialog = true, ImportHouseConfirmationDialog = true,
    AbandonHouseConfirmationDialog = true,
}
local focusParents = {
    CalendarViewHolidayFrame = "CalendarFrame", CalendarViewRaidFrame = "CalendarFrame",
    CalendarViewEventFrame = "CalendarFrame", CalendarCreateEventFrame = "CalendarFrame",
    CalendarMassInviteFrame = "CalendarFrame", CalendarEventPickerFrame = "CalendarFrame",
    CalendarTexturePickerFrame = "CalendarFrame", CurrencyTransferLog = "TokenFrame",
    SideDressUpFrame = "RecruitAFriendRewardsFrame",
}

local function IdentifyWindow(frame, focus)
    if not frame or Safety.IsForbidden(frame) then return nil end
    local name = Safety.Read(frame, "GetName")
    if type(name) ~= "string" or name == "" then return nil end
    local companion = focus and (focusCompanions[name] or focusParents[name])
    if companion and frame ~= Safety.Field(_G, name) then return nil end
    if IsBag(name) and not inventoryRoots[name] and not companion then return nil end
    if inventoryRoots[name] and not Policy.IsInventory(frame) then return nil end
    if name == "LFGParentFrame" and not NS.Client.isForever then return nil end
    local entry = NS.BlizzardCatalog.FindByFrame(name)
    local standalone = specialPanels[name] or inventoryRoots[name] or companion
    local panel = UIPanelWindows[name]
    if not (entry or standalone) or not (panel or standalone) then return nil end
    if panel and panel.area == "full" and not (focus and name == "WorldMapFrame") then return nil end
    if entry and excludedCategories[entry.category] and not standalone then return nil end
    local parent = Safety.Read(frame, "GetParent")
    if parent ~= UIParent and not inventoryRoots[name] and not (standalone and parent == nil)
        and not (nativeParentRoots[name] and parent == Safety.Read(_G, "GetAppropriateTopLevelParent"))
        and not (focus and focusParents[name] and parent == Safety.Field(_G, focusParents[name])) then return nil end
    if focus then return name, entry, panel end
    local width, height = Safety.Read(frame, "GetWidth"), Safety.Read(frame, "GetHeight")
    -- Professions starts at width one; its native SetTab sizes the root after
    -- showing it. Our anchors follow that layout without another skin pass.
    local initialProfession = name == "ProfessionsFrame" and width == 1 and frame == Safety.Field(_G, name)
    -- The Game Menu similarly starts at height one before laying out buttons.
    if type(width) ~= "number" or type(height) ~= "number"
        or width < (compactWidths[name] or (inventoryRoots[name] and 120) or 240) and not initialProfession
        or height < 170 and not standalone then return nil end
    return name, entry, panel
end

function Policy.IdentifyWindow(frame)
    return IdentifyWindow(frame, false)
end

-- Native windows can start at width one before their first layout. Observation
-- does not need the size/protection permission required by move/scale controls.
function Policy.IdentifyFocusWindow(frame)
    return IdentifyWindow(frame, true)
end

function Policy.Eligible(frame)
    if not Policy.CanControl(frame) then return nil end
    return Policy.IdentifyWindow(frame)
end
