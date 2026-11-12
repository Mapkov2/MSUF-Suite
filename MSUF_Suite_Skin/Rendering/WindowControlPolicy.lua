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

-- Fixed-layout exchange windows keep their size: their caption is the X
-- (and a minimize where one is offered) without a maximize cell.
local fixedPanels = { TradeFrame = true }
function Policy.CanFit(state) return not fixedPanels[state.name] end

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

function Policy.HasManagedVisibility(state)
    if state.panel or UIPanelWindows[state.name] then return true end
    local area = Safety.Call(state.frame, "GetAttribute", "UIPanelLayout-area")
    return not Safety.Public(area) or area ~= nil
end

function Policy.CanChangeVisibility(state)
    local managed = Policy.HasManagedVisibility(state)
    return (not managed or not NS.IsCombatLocked()) and Policy.CanChangeGeometry(state.frame), managed
end

-- The profession window casts its open profession again as it shows, which
-- only Blizzard's own path may do. Minimizing notes the open profession; the
-- restore tab reopens it through the trade skill API, so Blizzard shows the
-- window from its own event. The book page simply shows again.
function Policy.NoteProfession(state)
    local info = state.name == "ProfessionsFrame" and C_TradeSkillUI.GetBaseProfessionInfo()
    local crafting = Safety.Read(Safety.Field(state.frame, "CraftingPage"), "IsShown") == true
    state.profession = crafting and info and Safety.Public(info.professionID) and info.professionID or nil
end

function Policy.ReopenProfession(state)
    return C_TradeSkillUI.OpenTradeSkill(state.profession) == true
end

-- Only persistent, player-opened windows get a restore tab (closing an NPC panel ends it).
local minimizable = {
    CharacterFrame = true, FriendsFrame = true, PVEFrame = true, PVPUIFrame = true, ProfessionsBookFrame = true,
    ProfessionsFrame = true, CollectionsJournal = true, EncounterJournal = true, SettingsPanel = true, AddonList = true,
    CommunitiesFrame = true, LFGParentFrame = true, LegacySystemFrame = true, PlayerSpellsFrame = true,
    WorldMapFrame = true, AchievementFrame = true, QuestLogFrame = true, MacroFrame = true, CalendarFrame = true,
    InspectFrame = true, DressUpFrame = true, HelpFrame = true,
}
function Policy.IsMinimizable(name) return minimizable[name] == true end

-- Blizzard buttons whose own OnClick opens the window as the player's click or
-- key binding does (live and forever): MinimapZoneTextButtonMixin:OnClick runs
-- ToggleWorldMap (Blizzard_Minimap/Mainline/Minimap.lua), the micro buttons
-- (Blizzard_MicroMenu/Mainline/MainMenuBarMicroButtons.lua) ToggleCharacter
-- ("PaperDollFrame"), ToggleProfessionsBook, ToggleAchievementFrame,
-- ToggleCollectionsJournal, ToggleEncounterJournal and, on WoW Forever,
-- ToggleLegacySystemUI. The restore tab clicks one of them from secure code
-- (WindowControlDelegate.lua). A hidden micro button still takes the click.
local openers = {
    WorldMapFrame = { "MinimapCluster", "ZoneTextButton" }, CharacterFrame = { "CharacterMicroButton" },
    ProfessionsBookFrame = { "ProfessionMicroButton" }, AchievementFrame = { "AchievementMicroButton" },
    CollectionsJournal = { "CollectionsMicroButton" }, EncounterJournal = { "EJMicroButton" },
    LegacySystemFrame = { "LegacyMicroButton" },
}
function Policy.Opener(state)
    local path = not state.profession and openers[state.name]
    if not path then return nil end
    local button = Safety.Field(_G, path[1])
    for index = 2, #path do button = Safety.Field(button, path[index]) end
    if not Safety.Public(button) or not button or Safety.IsForbidden(button)
        or Safety.Read(button, "GetObjectType") ~= "Button" or Safety.Read(button, "IsEnabled") ~= true then
        return nil
    end
    return button
end

-- The world map's own show and hide refresh its pins, and WoW Forever's pins
-- call the protected SetPassThroughButtons (MapCanvasMixin:AcquirePin): only
-- Blizzard's buttons may show or hide it, never the skin's own code.
function Policy.SecureOnly(state) return state.name == "WorldMapFrame" end

-- Blizzard's panel manager places the windows of its slots
-- (FramePositionDelegate:UpdateUIPanelPositions, Blizzard_UIParentPanelManager/
-- Shared/UIParentPanelManager.lua, live and forever). The skin only reads that
-- layout: a pass run from its code runs, and writes, under its taint.
local SLOTS = { "left", "doublewide", "center", "right", "fullscreen" }
local FOLLOWERS = { left = { "center", "right" }, doublewide = { "right" }, center = { "right" } }

local function SlotOf(frame)
    for _, slot in ipairs(SLOTS) do
        if GetUIPanel(slot) == frame then return slot end
    end
end

-- Where Blizzard's pass anchored a window, written into layout with the scale
-- it divided by (TOPLEFT both offsets, a centred TOP window only y): read
-- right after the pass, before the skin rescales the window.
local function PanelLayout(frame, layout)
    if Safety.Read(frame, "GetNumPoints") ~= 1 then return nil end
    local point, relative, relativePoint, x, y = frame:GetPoint(1)
    local scale = Safety.Read(frame, "GetScale")
    if not Safety.Public(point) or not Safety.Public(relative) or not Safety.Public(relativePoint)
        or type(x) ~= "number" or type(y) ~= "number" or type(scale) ~= "number" or scale <= 0 then
        return nil
    end
    layout[1], layout[2], layout[3], layout[4], layout[5] = point, relative, relativePoint, x, y
    layout.scale, layout.scaled = scale, point == "TOPLEFT"
    return layout
end

-- After Blizzard's pass (the UpdateUIPanelPositions post-hook): where it put
-- each controlled window that holds a slot.
function Policy.CapturePanels(states)
    for _, slot in ipairs(SLOTS) do
        local frame = GetUIPanel(slot)
        local state = frame and states[frame]
        if state then state.panelLayout = PanelLayout(frame, state.panelLayout or {}) end
    end
end

-- Puts a window that still holds its slot back where Blizzard's last pass put it.
function Policy.RestorePanel(state)
    local layout, frame = state.panelLayout, state.frame
    if not layout or not SlotOf(frame) then return false end
    local ratio = layout.scale / frame:GetScale()
    frame:ClearAllPoints()
    frame:SetPoint(layout[1], layout[2], layout[3], layout.scaled and layout[4] * ratio or layout[4], layout[5] * ratio)
    return true
end

-- A window that changed width moves the windows Blizzard laid out after it by
-- that width (UIParent units), as the pass would. A centred "center" window
-- (TOP) and windows the skin placed itself stay; protected ones wait for
-- Blizzard's next pass.
local scratch = {}
function Policy.ShiftFollowers(root, delta)
    local followers = delta ~= 0 and FOLLOWERS[SlotOf(root) or ""]
    if not followers then return end
    for _, slot in ipairs(followers) do
        local frame = GetUIPanel(slot)
        local controls = frame and NS.WindowControls.states[frame]
        local layout = frame and frame ~= root and not (controls and controls.customPosition)
            and Policy.CanChangeGeometry(frame) and PanelLayout(frame, scratch)
        if layout and layout[1] == "TOPLEFT" and layout[2] == UIParent and layout[3] == "TOPLEFT" then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", layout[4] + delta / layout.scale, layout[5])
        end
    end
end

-- Forever rebuilds native map overlays and pins when the player opens the
-- map during an encounter. Leave that layout to Blizzard until combat ends.
function Policy.DeferMapLayout(state)
    if state.name == "WorldMapFrame" and NS.Client.isForever and NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow)
        return true
    end
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
    if not (entry or standalone) then return nil end
    -- A catalogued, named top-level window can own its own visibility instead
    -- of registering with UIPanelWindows. Require a native caption on that path.
    if not (panel or standalone) then
        local close = Safety.Field(frame, "ClosePanelButton") or Safety.Field(frame, "CloseButton")
        if frame ~= Safety.Field(_G, name) or Safety.Read(close, "GetObjectType") ~= "Button" then return nil end
    end
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
