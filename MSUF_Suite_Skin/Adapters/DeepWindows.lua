local _, NS = ...

-- Bounded late-lifecycle coverage for a small set of Retail windows whose
-- material art or pooled descendants are created/refreshed after the normal
-- catalog pass. Contracts were verified against Gethe/wow-ui-source
-- upstream/live 8ea15b61e45c0ed4eba01439c90757f86eb78d34:
--
--   Blizzard_UIPanels_Game/Mainline/QuestFrameTemplates.xml, GossipFrame.xml,
--     BankFrame.lua, BankFrame.xml, ContainerFrame.lua and ContainerFrame.xml
--   Blizzard_Professions/Blizzard_ProfessionsFrame.lua,
--     Blizzard_ProfessionsCrafting.lua, Blizzard_ProfessionsCrafterOrderPage.lua
--     and Blizzard_ProfessionsCrafterOrderView.lua
--   Blizzard_ProfessionsCustomerOrders/*.lua and *.xml
--   Blizzard_Collections/Mainline/Blizzard_WarbandSceneCollection.lua/.xml,
--     Blizzard_PagedContent/Blizzard_PagedContentFrame.lua and
--     Blizzard_SharedXML/Mainline/SharedCollectionTemplates.xml
--   Blizzard_GenericTraitUI/Blizzard_GenericTraitFrame.lua/.xml
--
-- Blizzard continues to own data, visibility, geometry, scripts, attributes,
-- semantic textures and selection state. All paint work is outside combat;
-- permanent secure hooks and callbacks are installed once and are inert when
-- no owner is active. No timer, polling loop or frame OnUpdate is installed.
--
-- This file owns the owner lifecycle and the quest, gossip, bank and warband
-- windows; DeepWindowsProfessions.lua adds the profession, customer-order
-- and generic-trait windows.
local DeepWindows = {
    owners = {},
    waiting = {},
    hooks = {},
    warbandCallbacks = setmetatable({}, { __mode = "k" }),
    warbandSurfaces = setmetatable({}, { __mode = "k" }),
}
NS.DeepWindows = DeepWindows

local Safety = NS.Safety
local Field = Safety.Field
local Dispatch = Safety.Dispatch
local Kit = NS.AdapterKit
local Path = Kit.Path
local Fade = Kit.Fade

local DEFAULT_OWNER = "blizzardWindows"
local BANK_TAB_LIMIT = 32
local BANK_ITEM_LIMIT = 128
local WARBAND_CARD_LIMIT = 64

local UI_PANELS_ADDON = "Blizzard_UIPanels_Game"
local COLLECTIONS_ADDON = "Blizzard_Collections"

local BANK_TAB_SPEC = {
    role = "navigation",
    activeRole = "navigationActive",
    radius = 4,
    inset = 0,
    regions = { "Border" },
    allowImplicitProtected = true,
}

local WARBAND_CARD_SPEC = {
    role = "card",
    activeRole = "navigationActive",
    radius = 6,
    inset = 1,
    listItem = true,
    allowImplicitProtected = true,
}

local QUEST_PANELS = {
    "QuestFrameRewardPanel",
    "QuestFrameProgressPanel",
    "QuestFrameDetailPanel",
    "QuestFrameGreetingPanel",
    "QuestLogPopupDetailFrame",
}

local MATERIAL_FIELDS = {
    "MaterialTopLeft",
    "MaterialTopRight",
    "MaterialBotLeft",
    "MaterialBotRight",
    "SealMaterialBG",
}

local GOSSIP_MATERIAL_GLOBALS = {
    "GossipFrameGreetingPanelMaterialTopRight",
    "GossipFrameGreetingPanelMaterialBotLeft",
    "GossipFrameGreetingPanelMaterialBotRight",
}


local WARBAND_CARD_FIELDS = {
    "Icon", "Name", "NameBackground", "Border", "SlotFavorite", "HighlightTexture",
}

local function CategoryEnabled(category)
    return NS.GenericWindows.IsCategoryEnabled(category)
end

local function CanCreateRegions(target)
    return Safety.CanCreateRegions(target, true)
end

local SkinWarbandCard

local function OwnerState(parentOwner)
    parentOwner = parentOwner or DEFAULT_OWNER
    local state = DeepWindows.owners[parentOwner]
    if not state then
        state = {
            parentOwner = parentOwner,
            owner = tostring(parentOwner) .. ":deep-windows",
            active = false,
            deferred = {},
            cardSurfaces = Kit.WeakSet(),
            cardsVisited = 0,
            cardsDecorated = 0,
        }
        -- Built once per owner, not per refresh. Returning true ends the
        -- page walk after WARBAND_CARD_LIMIT cards.
        state.visitCard = function(card)
            state.cardsVisited = state.cardsVisited + 1
            if SkinWarbandCard(state, card) then state.cardsDecorated = state.cardsDecorated + 1 end
            return state.cardsVisited >= WARBAND_CARD_LIMIT
        end
        DeepWindows.owners[parentOwner] = state
    end
    return state
end


local function FadeMaterialPanel(state, panel)
    if not panel then return 0 end
    local faded = 0
    for index = 1, #MATERIAL_FIELDS do
        if Fade(state, Field(panel, MATERIAL_FIELDS[index])) then
            faded = faded + 1
        end
    end
    return faded
end

local function SetQuestText(state, active)
    local questText = NS.QuestText
    local method = active and questText.Activate or questText.Deactivate
    method(_G.QuestFrame, state.owner)
    method(_G.GossipFrame, state.owner)
    method(_G.QuestLogPopupDetailFrame, state.owner)
end

local function ApplyQuestAndGossip(state)
    if not state or not state.active then return false, "disabled" end
    if not CategoryEnabled("quest") then
        SetQuestText(state, false)
        return true, "disabled"
    end
    if NS.IsCombatLocked() then return false, "combat" end

    local faded = 0
    for index = 1, #QUEST_PANELS do
        faded = faded + FadeMaterialPanel(state, _G[QUEST_PANELS[index]])
    end
    SetQuestText(state, true)

    if Fade(state, Path(_G.GossipFrame, "GreetingPanel", "MaterialTopLeft")) then
        faded = faded + 1
    end
    for index = 1, #GOSSIP_MATERIAL_GLOBALS do
        if Fade(state, _G[GOSSIP_MATERIAL_GLOBALS[index]]) then
            faded = faded + 1
        end
    end

    return faded > 0, faded > 0 and "applied" or "missing"
end


-- apply(state, a, b) for every active owner while the category is enabled.
-- These run from Blizzard's lifecycle hooks, so each owner's pass is its
-- own error boundary and a raising pass never reaches Blizzard's caller.
local function ForActiveOwners(category, apply, a, b)
    if NS.IsCombatLocked() or not CategoryEnabled(category) then return end
    for _, state in pairs(DeepWindows.owners) do
        if state.active then Dispatch(apply, state, a, b) end
    end
end


-- Pooled row templates only: Blizzard creates those rows later from the
-- (then hooked) mixin, so each new row carries the hook.
local function HookMixin(key, mixinName, methodName, callback)
    if DeepWindows.hooks[key] then return true end
    if not Kit.HookFunction(_G[mixinName], methodName, callback) then return false end
    DeepWindows.hooks[key] = true
    return true
end


-- A post-hook on Blizzard's function: the bag renderer is its own error
-- boundary so a raising pass never reaches ContainerFrame_GenerateFrame's caller.
local function DispatchContainerGenerate(frame)
    local callback = DeepWindows.containerGenerateCallback
    if callback then Dispatch(callback, frame) end
end

-- CommonMenus owns the exact bag renderer and active-owner gate. This audited
-- adapter owns the sole irreversible post-hook so every permanent lifecycle
-- hook remains centralized in the project's allowlisted files.
function DeepWindows.InstallContainerGenerateHook(callback)
    if type(callback) ~= "function" then return false end
    if DeepWindows.hooks.containerGenerate then return true end
    if not Kit.HookGlobal("ContainerFrame_GenerateFrame", DispatchContainerGenerate) then
        return false
    end
    DeepWindows.containerGenerateCallback = callback
    DeepWindows.hooks.containerGenerate = true
    return true
end

-- IconSkin reads the native quality border only while it skins. Repaint a
-- border IconSkin owns (bags, bank, catalog item buttons) from the one
-- Blizzard just set; on an owned button that creates no regions and no tables.
local function RepaintItemBorder(button)
    local iconState = NS.IconSkin.GetState(button)
    local owner = NS.IconSkin.GetOwner(button)
    if owner == nil or not iconState then return end
    Kit.SkinItemIcon(button, owner, iconState.icon, iconState.nativeBorder, true)
end

-- Buttons IconSkin does not own return at once. The repaint runs inside
-- Blizzard's item update loop, so it is its own error boundary. Combat
-- updates wait for the next out-of-combat one.
local function OnItemQualitySet(button)
    if NS.IsCombatLocked() or NS.IconSkin.GetOwner(button) == nil then return end
    Dispatch(RepaintItemBorder, button)
end

-- Every item button takes its quality border from the global
-- SetItemButtonQuality (Blizzard_ItemButton, Retail and Forever):
-- ContainerFrameMixin:UpdateItems (also after BAG_UPDATE and item data that
-- loads while the bag is open), BankPanelItemButtonMixin:Refresh and the
-- other item windows. The post-hook is permanent and inert without owners.
function DeepWindows.InstallItemQualityHook()
    if DeepWindows.hooks.itemQuality then return true end
    if not Kit.HookGlobal("SetItemButtonQuality", OnItemQualitySet) then return false end
    DeepWindows.hooks.itemQuality = true
    return true
end


local function SkinBankTab(state, tab, panel)
    if not state or not state.active or not tab or not panel
        or not Kit.ParentIs(tab, panel) or not Field(tab, "tabData")
        or NS.IsCombatLocked() or not CategoryEnabled("inventory") then
        return false
    end
    return NS.ControlSkin.ApplyTab(tab, state.owner, BANK_TAB_SPEC) ~= nil
end

local function SkinBankItem(state, button, panel)
    if not state or not state.active or not button or not panel
        or not Kit.ParentIs(button, panel) or NS.IsCombatLocked()
        or not CategoryEnabled("inventory") then
        return false
    end

    -- Current BankPanelItemButtonMixin uses the inherited lowercase item icon
    -- and the inherited IconBorder updated by SetItemButtonQuality. Cooldown,
    -- SearchOverlay, IconQuestTexture, Background and itemLocation stay native.
    local icon = Field(button, "icon")
    local qualityBorder = Field(button, "IconBorder")
    if not icon or not qualityBorder then return false end
    return Kit.SkinItemIcon(button, state.owner, icon, qualityBorder, true)
end

-- Skins at most limit active pool objects; returns how many were skinned.
local function SkinPool(state, pool, panel, limit, skin)
    if type((Field(pool, "EnumerateActive"))) ~= "function" then return 0 end
    local visited, decorated = 0, 0
    for object in pool:EnumerateActive() do
        if visited >= limit then break end
        visited = visited + 1
        if skin(state, object, panel) then decorated = decorated + 1 end
    end
    return decorated
end

local function ApplyBank(state)
    if not state or not state.active then return false, "disabled" end
    if not CategoryEnabled("inventory") then return true, "disabled" end
    if NS.IsCombatLocked() then return false, "combat" end
    local panel = Path(_G.BankFrame, "BankPanel")
    if not panel then return false, "missing" end

    local decorated = SkinBankTab(state, Field(panel, "PurchaseTab"), panel) and 1 or 0
    decorated = decorated + SkinPool(state, Field(panel, "bankTabPool"), panel,
        BANK_TAB_LIMIT, SkinBankTab)
    decorated = decorated + SkinPool(state, Field(panel, "itemButtonPool"), panel,
        BANK_ITEM_LIMIT, SkinBankItem)
    return true, decorated > 0 and "applied" or "waiting"
end

local function RefreshBankTab(tab)
    local panel = Path(_G.BankFrame, "BankPanel")
    if panel and Kit.ParentIs(tab, panel) then
        ForActiveOwners("inventory", SkinBankTab, tab, panel)
    end
end

local function RefreshBankItem(button)
    local panel = Path(_G.BankFrame, "BankPanel")
    if panel and Kit.ParentIs(button, panel) then
        ForActiveOwners("inventory", SkinBankItem, button, panel)
    end
end

local function InstallBankHooks()
    HookMixin("bank-tab-init", "BankPanelTabMixin", "Init", RefreshBankTab)
    HookMixin("bank-item-init", "BankPanelItemButtonMixin", "Init", RefreshBankItem)
    -- RefreshAllItemsForSelectedTab refreshes each button's border in place.
    DeepWindows.InstallItemQualityHook()
end

SkinWarbandCard = function(state, card)
    if not state or not state.active or not card or NS.IsCombatLocked()
        or not CategoryEnabled("journal") or not CanCreateRegions(card)
        or not Kit.HasFields(card, WARBAND_CARD_FIELDS) then
        return false
    end

    -- Only reuse a card surface this adapter installed with its own spec.
    local existing = NS.Registry.GetSurface(card)
    local record = DeepWindows.warbandSurfaces[card]
    if existing and (not record or record.surface ~= existing
        or existing.spec ~= WARBAND_CARD_SPEC
        or (record.owner and record.owner ~= state.owner)) then
        return false
    end

    local surface = NS.Surface.Attach(card, WARBAND_CARD_SPEC)
    if not surface then return false end

    record = record or {}
    record.surface = surface
    record.owner = state.owner
    DeepWindows.warbandSurfaces[card] = record
    state.cardSurfaces[card] = surface
    Fade(state, Field(card, "NameBackground"))
    Fade(state, Field(card, "Border"))
    return true
end

local function WarbandIcons()
    return Path(_G.WarbandSceneJournal, "IconsFrame", "Icons")
end

local function ApplyWarbandCards(state, icons)
    if not state or not state.active then return false, "disabled" end
    if not CategoryEnabled("journal") then return true, "disabled" end
    if NS.IsCombatLocked() then return false, "combat" end
    icons = icons or WarbandIcons()
    if not icons or icons ~= WarbandIcons() then return false, "missing" end

    state.cardsVisited, state.cardsDecorated = 0, 0
    if not Kit.ForEachRow(icons, state.visitCard) then return false, "missing" end
    return true, state.cardsDecorated > 0 and "applied" or "waiting"
end

function DeepWindows:OnWarbandSceneUpdate()
    local icons = WarbandIcons()
    if icons then ForActiveOwners("journal", ApplyWarbandCards, icons) end
end

local function RegisterWarbandCallback(icons)
    if DeepWindows.warbandCallbacks[icons] then return true end
    local event = Path(_G.PagedContentFrameBaseMixin, "Event", "OnUpdate")
    if type(event) ~= "string" or not NS.Safety.Invoke(icons, "RegisterCallback",
        event, DeepWindows.OnWarbandSceneUpdate, DeepWindows) then
        return false
    end
    DeepWindows.warbandCallbacks[icons] = event
    return true
end


local function ApplyCollections(state)
    if not CategoryEnabled("journal") then return true, "disabled" end
    local icons = WarbandIcons()
    if not icons then return false, "missing" end
    RegisterWarbandCallback(icons)
    return ApplyWarbandCards(state, icons)
end


-- Adds one sub-apply result to the running applied/waiting counts.
local function Tally(applied, waiting, ok, reason)
    if ok and reason == "waiting" then return applied, waiting + 1 end
    if ok then return applied + 1, waiting end
    return applied, waiting
end

local function ApplyUIPanels(state)
    local attempted, applied, waiting = 0, 0, 0
    if CategoryEnabled("quest") then
        attempted = attempted + 1
        applied, waiting = Tally(applied, waiting, ApplyQuestAndGossip(state))
    end
    if CategoryEnabled("inventory") then
        attempted = attempted + 1
        InstallBankHooks()
        applied, waiting = Tally(applied, waiting, ApplyBank(state))
    end
    if attempted == 0 then return true, "disabled" end
    if applied == attempted then return true, "applied" end
    if applied > 0 then return true, "partial" end
    if waiting > 0 then return true, "waiting" end
    return false, "missing"
end

-- The window families in apply order: quest and bank, professions, customer
-- orders, the warband collection, then generic traits. DeepWindowsProfessions.lua
-- (loads next) adds the specs of the profession, customer-order and
-- generic-trait windows into their places.
local FAMILY_ORDER = {
    UI_PANELS_ADDON,
    "Blizzard_Professions",
    "Blizzard_ProfessionsCustomerOrders",
    COLLECTIONS_ADDON,
    "Blizzard_GenericTraitUI",
}
local addonSpecs = {}
local addonSpecByName = {}

-- Adds a window family, { addon, relevant(), ready(), apply(state) }, at its
-- place in FAMILY_ORDER.
local function AddAddonSpec(spec)
    addonSpecByName[spec.addon] = spec
    local count = 0
    for index = 1, #FAMILY_ORDER do
        local listed = addonSpecByName[FAMILY_ORDER[index]]
        if listed then
            count = count + 1
            addonSpecs[count] = listed
        end
    end
end

AddAddonSpec({
    addon = UI_PANELS_ADDON,
    relevant = function()
        return CategoryEnabled("quest") or CategoryEnabled("inventory")
    end,
    -- Not load-on-demand (12.1.0, 12.1.5, Forever): loaded before this skin.
    ready = function() return true end,
    apply = ApplyUIPanels,
})
AddAddonSpec({
    addon = COLLECTIONS_ADDON,
    relevant = function() return CategoryEnabled("journal") end,
    ready = function() return _G.WarbandSceneJournal ~= nil end,
    apply = ApplyCollections,
})

local ApplyState

local function DeferredKey(state, suffix)
    return "deep-windows:" .. tostring(state.parentOwner) .. ":" .. tostring(suffix)
end

local function DeferApply(state, suffix)
    if not state or not state.active then return false, "combat" end
    local parentOwner = state.parentOwner
    local key = DeferredKey(state, suffix)
    state.deferred[key] = true
    local ran, reason = NS.CombatGate.RunOrDefer(key, function()
        local current = DeepWindows.owners[parentOwner]
        if current then current.deferred[key] = nil end
        if current and current.active then ApplyState(current) end
    end)
    if ran then state.deferred[key] = nil end
    return ran == true, reason
end

-- Each addon spec is its own error boundary per owner: a raising window is
-- reported and the other windows and owners still apply.
local function ApplyAddonForOwners(spec)
    for _, state in pairs(DeepWindows.owners) do
        if state.active and spec.relevant() then
            if NS.IsCombatLocked() then
                DeferApply(state, "load-" .. spec.addon)
            else
                Dispatch(spec.apply, state)
            end
        end
    end
end

local function ScheduleAddon(addon)
    if DeepWindows.waiting[addon] then return true end
    if NS.Client.IsAddOnLoaded(addon) then return false end
    DeepWindows.waiting[addon] = true
    EventUtil.ContinueOnAddOnLoaded(addon, function()
        DeepWindows.waiting[addon] = nil
        ApplyAddonForOwners(addonSpecByName[addon])
    end)
    return true
end

ApplyState = function(state)
    if not state or not state.active then return false, "disabled" end
    if NS.IsCombatLocked() then return DeferApply(state, "apply") end

    local applied, waiting, failed = 0, 0, 0
    for index = 1, #addonSpecs do
        local spec = addonSpecs[index]
        if spec.relevant() then
            if NS.Client.IsAddOnLoaded(spec.addon) or spec.ready() then
                local finished, result, reason = Kit.Isolate(spec.apply, state)
                if not finished then
                    failed = failed + 1
                elseif result and reason == "waiting" then
                    waiting = waiting + 1
                elseif result then
                    applied = applied + 1
                else
                    failed = failed + 1
                end
            elseif ScheduleAddon(spec.addon) then
                waiting = waiting + 1
            else
                failed = failed + 1
            end
        end
    end

    if applied == 0 and waiting > 0 and failed == 0 then return true, "waiting" end
    if applied == 0 and failed > 0 then return false, "missing" end
    if waiting > 0 or failed > 0 then return true, "partial" end
    return true, "applied"
end

-- Hides only warband card surfaces this owner installed and still owns.
local function HideWarbandCards(state)
    for card, surface in pairs(state.cardSurfaces) do
        local record = DeepWindows.warbandSurfaces[card]
        if NS.Registry.GetSurface(card) == surface and record and record.surface == surface
            and record.owner == state.owner and surface.spec == WARBAND_CARD_SPEC then
            NS.Surface.SetVisible(card, false)
            record.owner = nil
        end
    end
end

local function DisableNow(state)
    if not state then return true end
    state.active = false
    Kit.CancelDeferred(state)
    SetQuestText(state, false)
    NS.ControlSkin.DisableOwner(state.owner)
    NS.IconSkin.DisableOwner(state.owner)
    HideWarbandCards(state)
    NS.Cosmetics.RestoreOwner(state.owner)
    DeepWindows.owners[state.parentOwner] = nil
    return true
end

function DeepWindows.Apply(parentOwner)
    local state = OwnerState(parentOwner)
    Kit.CancelDeferred(state)
    state.active = true
    if NS.IsCombatLocked() then return DeferApply(state, "apply") end
    return ApplyState(state)
end

function DeepWindows.Disable(parentOwner)
    parentOwner = parentOwner or DEFAULT_OWNER
    local state = DeepWindows.owners[parentOwner]
    if not state then return true end

    Kit.CancelDeferred(state)
    if NS.IsCombatLocked() then
        state.active = false
        local key = DeferredKey(state, "disable")
        state.deferred[key] = true
        NS.CombatGate.RunOrDefer(key, function()
            local current = DeepWindows.owners[parentOwner]
            if current then
                current.deferred[key] = nil
                if not current.active then DisableNow(current) end
            end
        end)
        return false, "combat"
    end

    return DisableNow(state)
end

-- Private to DeepWindowsProfessions.lua, which loads next and takes it off
-- NS again, so no other addon can add a window family.
NS.DeepWindowsShared = {
    CategoryEnabled = CategoryEnabled,
    CanCreateRegions = CanCreateRegions,
    ForActiveOwners = ForActiveOwners,
    HookMixin = HookMixin,
    AddAddonSpec = AddAddonSpec,
}

return DeepWindows
