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
local DeepWindows = {
    owners = {},
    waiting = {},
    hooks = {},
    warbandCallbacks = setmetatable({}, { __mode = "k" }),
    warbandSurfaces = setmetatable({}, { __mode = "k" }),
}
NS.DeepWindows = DeepWindows

local Field = NS.Safety.Field
local Kit = NS.AdapterKit
local Path = Kit.Path
local Fade = Kit.Fade

local DEFAULT_OWNER = "blizzardWindows"
local DESCENDANT_DEPTH = 12
local BANK_TAB_LIMIT = 32
local BANK_ITEM_LIMIT = 128
local WARBAND_CARD_LIMIT = 64

local UI_PANELS_ADDON = "Blizzard_UIPanels_Game"
local PROFESSIONS_ADDON = "Blizzard_Professions"
local CUSTOMER_ORDERS_ADDON = "Blizzard_ProfessionsCustomerOrders"
local COLLECTIONS_ADDON = "Blizzard_Collections"
local GENERIC_TRAITS_ADDON = "Blizzard_GenericTraitUI"

local PROFESSION_MODE = {
    role = "shell",
    maxDepth = 10,
    maxNodes = 1200,
    allowImplicitProtected = true,
}

local CUSTOMER_ORDERS_MODE = {
    role = "shell",
    maxDepth = 10,
    maxNodes = 1200,
    allowImplicitProtected = true,
    -- Customer-order rows have exact mixin contracts below. Keeping their
    -- lifecycle here avoids the generic ScrollBox callback overwriting the
    -- category selection role after Blizzard initializes a recycled row.
    registerDynamicRows = false,
}

local GENERIC_TRAITS_MODE = {
    role = "shell",
    maxDepth = 4,
    maxNodes = 480,
    allowImplicitProtected = true,
    -- Trait buttons, edges, FX and currency are semantic Blizzard content.
    -- Only the exact shell fields below need a late lifecycle repaint.
    childSurfaces = false,
    registerDynamicRows = false,
}

local FOREVER_BOOK_MODE = {
    role = "panel", maxDepth = 0, maxNodes = 1,
    fillVisible = false, childSurfaces = false, registerDynamicRows = false,
    allowImplicitProtected = true,
}

local FOREVER_CARD_MODE = {
    role = "card", maxDepth = 0, maxNodes = 1,
    childSurfaces = false, registerDynamicRows = false,
    allowImplicitProtected = true,
}

local CUSTOMER_CATEGORY_SPEC = {
    role = "navigation",
    activeRole = "navigationActive",
    radius = 4,
    inset = 0,
    listItem = true,
    regions = { "NormalTexture", "HighlightTexture", "SelectedTexture" },
    allowImplicitProtected = true,
}

local CUSTOMER_ROW_SPEC = {
    role = "card",
    radius = 4,
    inset = 0,
    listItem = true,
    regions = { "HighlightTexture" },
    allowImplicitProtected = true,
}

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

local PROFESSION_DETAIL_FIELDS = {
    "BackgroundTop", "BackgroundMiddle", "BackgroundBottom", "BackgroundMinimized",
}

local FOREVER_PROFESSION_CARDS = {
    "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1",
    "SecondaryProfession2", "SecondaryProfession3",
}

local CUSTOMER_CATEGORY_FIELDS = {
    "Text", "NormalTexture", "HighlightTexture", "SelectedTexture", "Lines", "SpacerLine",
}

local WARBAND_CARD_FIELDS = {
    "Icon", "Name", "NameBackground", "Border", "SlotFavorite", "HighlightTexture",
}

local function CategoryEnabled(category)
    return NS.GenericWindows.IsCategoryEnabled(category)
end

local function CanCreateRegions(target)
    return NS.Safety.CanCreateRegions(target, true)
end

local SkinCustomerCategory
local SkinCustomerRow

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
        }
        -- Row visitors are built once per owner, not per refresh.
        state.visitCategory = function(button) SkinCustomerCategory(state, button) end
        state.visitRow = function(button) SkinCustomerRow(state, button) end
        DeepWindows.owners[parentOwner] = state
    end
    return state
end

local function FadeRegion(region, state)
    Fade(state, region)
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
    if not questText then return end
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

local function ApplyDeepRoot(state, root, mode)
    if not state or not state.active or not root then return false, "missing" end
    if NS.IsCombatLocked() then return false, "combat" end
    -- Use the parent catalog owner deliberately. GenericWindows already owns
    -- these roots and therefore remains the sole restorer for its surfaces,
    -- controls, dynamic ScrollBox callbacks and cosmetic state.
    local applied, reason = NS.GenericWindows.ApplyFrame(root, state.parentOwner, mode or PROFESSION_MODE)
    return applied == true, reason
end

local function FadePanelChrome(state, panel)
    if not panel then return end
    Fade(state, Field(panel, "Bg"))
    Fade(state, Field(panel, "Background"))
    Kit.FadeNineSlice(state, Field(panel, "NineSlice"))
end

local function FadeProfessionRecipeList(state, recipeList)
    if not recipeList then return end
    Fade(state, Field(recipeList, "Background"))
    Kit.FadeNineSlice(state, Field(recipeList, "BackgroundNineSlice"))
end

local function FadeProfessionSchematic(state, schematic, hasOwnNineSlice)
    if not schematic then return end
    Fade(state, Field(schematic, "Background"))
    Fade(state, Field(schematic, "MinimalBackground"))
    if hasOwnNineSlice then
        Kit.FadeNineSlice(state, Field(schematic, "NineSlice"))
    end
    Kit.FadeFields(state, Field(schematic, "Details"), PROFESSION_DETAIL_FIELDS)
end

-- Camelot puts its professions book inside ProfessionsFrame instead of
-- loading the standalone ProfessionsBookFrame. The anonymous atlas on
-- CraftingPage and the five book cards are exact decorative regions; spell
-- buttons, rank bars, recipes, and profession icons stay native.
local function FadeForeverProfessionBook(state, root, crafting)
    Kit.FadeAtlas(state, crafting, "Profession-Background-Template2")
    local content = Path(root, "BookPage", "ProfessionsContentFrame")
    if not content then return end
    NS.GenericWindows.ApplyFrame(content, state.parentOwner, FOREVER_BOOK_MODE)
    for index = 1, #FOREVER_PROFESSION_CARDS do
        local card = Field(content, FOREVER_PROFESSION_CARDS[index])
        if card then
            NS.GenericWindows.ApplyFrame(card, state.parentOwner, FOREVER_CARD_MODE)
            Fade(state, Field(card, "Background"))
        end
    end
end

local function FadeProfessionChrome(state, root)
    -- These exact parentKey-only frames are anonymous in Blizzard's XML, so
    -- the generic name-token traversal cannot identify their decorative art.
    -- Keep recipe, reagent, quality, reward and order-state content native.
    local crafting = Field(root, "CraftingPage")
    FadeProfessionRecipeList(state, Field(crafting, "RecipeList"))
    FadeProfessionSchematic(state, Field(crafting, "SchematicForm"), true)

    if NS.Client.isForever then
        FadeForeverProfessionBook(state, root, crafting)
    end

    Fade(state, Path(root, "SpecPage", "TreeView", "Background"))
    Fade(state, Path(root, "SpecPage", "DetailedView", "Background"))
    Fade(state, Path(root, "SpecPage", "TreePreview", "Background"))

    local orders = Field(root, "OrdersPage")
    local browse = Field(orders, "BrowseFrame")
    FadeProfessionRecipeList(state, Field(browse, "RecipeList"))
    local orderList = Field(browse, "OrderList")
    Fade(state, Field(orderList, "Background"))
    Kit.FadeNineSlice(state, Field(orderList, "NineSlice"))

    local orderView = Field(orders, "OrderView")
    local orderInfo = Field(orderView, "OrderInfo")
    Fade(state, Field(orderInfo, "Background"))
    Kit.FadeNineSlice(state, Field(orderInfo, "NineSlice"))
    local orderDetails = Field(orderView, "OrderDetails")
    Fade(state, Field(orderDetails, "Background"))
    Kit.FadeNineSlice(state, Field(orderDetails, "NineSlice"))
    -- This concrete order SchematicForm has no own NineSlice in Retail.
    FadeProfessionSchematic(state, Field(orderDetails, "SchematicForm"), false)
end

SkinCustomerCategory = function(state, button)
    if not state or not state.active or not button or Field(button, "isSpacer") == true
        or NS.IsCombatLocked() or not CanCreateRegions(button)
        or not Kit.HasFields(button, CUSTOMER_CATEGORY_FIELDS) then
        return false
    end
    -- ControlSkin copies the spec synchronously, so the shared table can
    -- carry this row's selection for exactly one call.
    CUSTOMER_CATEGORY_SPEC.active = Kit.IsShown(Field(button, "SelectedTexture"))
    local applied = NS.ControlSkin.ApplyButton(button, state.owner, CUSTOMER_CATEGORY_SPEC)
    CUSTOMER_CATEGORY_SPEC.active = nil
    return applied ~= nil
end

SkinCustomerRow = function(state, button)
    if not state or not state.active or not button or NS.IsCombatLocked()
        or not CanCreateRegions(button) or not Field(button, "HighlightTexture") then
        return false
    end
    return NS.ControlSkin.ApplyButton(button, state.owner, CUSTOMER_ROW_SPEC) ~= nil
end

local function SkinVisibleCustomerRows(state, root)
    local browse = Field(root, "BrowseOrders")
    Kit.ForEachRow(Path(browse, "CategoryList", "ScrollBox"), state.visitCategory)
    Kit.ForEachRow(Path(browse, "RecipeList", "ScrollBox"), state.visitRow)
    Kit.ForEachRow(Path(root, "MyOrdersPage", "OrderList", "ScrollBox"), state.visitRow)
    Kit.ForEachRow(Path(root, "Form", "CurrentListings", "OrderList", "ScrollBox"), state.visitRow)
end

local function FadeCustomerOrdersChrome(state, root)
    -- Standalone customer orders copies Auction House chrome into anonymous
    -- parentKey frames. Fade only those source-confirmed decorative members;
    -- recipe icons, favorites, text, money and order state remain native.
    FadePanelChrome(state, Field(root, "MoneyFrameInset"))
    Kit.ForEachRegion(Field(root, "MoneyFrameBorder"), FadeRegion, state)

    local browse = Field(root, "BrowseOrders")
    FadePanelChrome(state, Field(browse, "CategoryList"))
    FadePanelChrome(state, Field(browse, "RecipeList"))

    FadePanelChrome(state, Path(root, "MyOrdersPage", "OrderList"))

    local form = Field(root, "Form")
    Fade(state, Field(form, "RecipeHeader"))
    FadePanelChrome(state, Field(form, "LeftPanelBackground"))
    FadePanelChrome(state, Field(form, "RightPanelBackground"))
    Fade(state, Path(form, "PaymentContainer", "NoteEditBox", "Border"))
    local listings = Field(form, "CurrentListings")
    FadePanelChrome(state, listings)
    FadePanelChrome(state, Field(listings, "OrderList"))

    SkinVisibleCustomerRows(state, root)
end

local function ApplyProfessionRoot(state, root)
    local applied, reason = ApplyDeepRoot(state, root)
    if applied and root == _G.ProfessionsFrame then
        FadeProfessionChrome(state, root)
    end
    return applied, reason
end

local function ApplyCustomerOrdersRoot(state, root)
    local applied, reason = ApplyDeepRoot(state, root, CUSTOMER_ORDERS_MODE)
    if applied then FadeCustomerOrdersChrome(state, root) end
    return applied, reason
end

local function FadeGenericTraitChrome(state, root)
    -- GenericTraitFrameMixin:ApplyLayout assigns these atlases after the
    -- catalog pass. They are exact decorative shell members; ButtonsParent,
    -- talent nodes, edges, FX, currency text/icon and scripts stay native.
    Fade(state, Field(root, "Background"))
    Fade(state, Field(root, "BorderOverlay"))
    Kit.FadeNineSlice(state, Field(root, "NineSlice"))
    Fade(state, Path(root, "NineSlice", "DetailTop"))
    Fade(state, Path(root, "Header", "TitleDivider"))
    Fade(state, Path(root, "Inset", "Bg"))
    Kit.FadeNineSlice(state, Path(root, "Inset", "NineSlice"))
    Fade(state, Path(root, "Currency", "CurrencyBackground"))
end

local function ApplyGenericTraitRoot(state, root)
    local applied, reason = ApplyDeepRoot(state, root, GENERIC_TRAITS_MODE)
    if applied then FadeGenericTraitChrome(state, root) end
    return applied, reason
end

-- True when frame is nil (a whole-window refresh) or lies inside root.
local function Covers(root, frame)
    return root ~= nil and (frame == nil or frame == root
        or Kit.IsDescendantOf(frame, root, DESCENDANT_DEPTH))
end

-- apply(state, a, b) for every active owner while the category is enabled.
local function ForActiveOwners(category, apply, a, b)
    if NS.IsCombatLocked() or not CategoryEnabled(category) then return end
    for _, state in pairs(DeepWindows.owners) do
        if state.active then apply(state, a, b) end
    end
end

local function RefreshProfessions(frame)
    local root = _G.ProfessionsFrame
    if Covers(root, frame) then
        ForActiveOwners("profession", ApplyProfessionRoot, root)
    end
end

local function RefreshCustomerOrders(frame)
    local root = _G.ProfessionsCustomerOrdersFrame
    if Covers(root, frame) then
        ForActiveOwners("profession", ApplyCustomerOrdersRoot, root)
    end
end

local function RefreshGenericTraits(frame)
    local root = _G.GenericTraitFrame
    if Covers(root, frame) then
        ForActiveOwners("character", ApplyGenericTraitRoot, root)
    end
end

local function RefreshCustomerCategory(button)
    local root = _G.ProfessionsCustomerOrdersFrame
    if root and Kit.IsDescendantOf(button, root, DESCENDANT_DEPTH) then
        ForActiveOwners("profession", SkinCustomerCategory, button)
    end
end

local function RefreshCustomerRow(button)
    local root = _G.ProfessionsCustomerOrdersFrame
    if root and Kit.IsDescendantOf(button, root, DESCENDANT_DEPTH) then
        ForActiveOwners("profession", SkinCustomerRow, button)
    end
end

function DeepWindows:OnProfessionsTabSet(frame)
    if frame == _G.ProfessionsFrame then RefreshProfessions(frame) end
end

local function HookMixin(key, mixinName, methodName, callback)
    if DeepWindows.hooks[key] then return true end
    if not Kit.HookFunction(_G[mixinName], methodName, callback) then return false end
    DeepWindows.hooks[key] = true
    return true
end

local function DispatchContainerGenerate(frame)
    local callback = DeepWindows.containerGenerateCallback
    if callback then callback(frame) end
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

local function InstallProfessionsHooks()
    if not DeepWindows.hooks.professionsTabSet
        and Kit.RegisterEventCallback("ProfessionsFrame.TabSet",
            DeepWindows.OnProfessionsTabSet, DeepWindows) then
        DeepWindows.hooks.professionsTabSet = true
    end

    HookMixin("professions-show", "ProfessionsMixin", "OnShow", RefreshProfessions)
    HookMixin("professions-refresh", "ProfessionsMixin", "Refresh", RefreshProfessions)
    HookMixin("crafting-init", "ProfessionsCraftingPageMixin", "Init", RefreshProfessions)
    HookMixin("crafting-refresh", "ProfessionsCraftingPageMixin", "Refresh", RefreshProfessions)
    HookMixin("crafting-schematic", "ProfessionsCraftingPageMixin",
        "SchematicPostInit", RefreshProfessions)
    HookMixin("orders-init", "ProfessionsCraftingOrderPageMixin", "Init", RefreshProfessions)
    HookMixin("orders-refresh", "ProfessionsCraftingOrderPageMixin", "Refresh", RefreshProfessions)
    HookMixin("order-view-schematic", "ProfessionsCrafterOrderViewMixin",
        "SchematicPostInit", RefreshProfessions)
end

local function InstallCustomerOrderHooks()
    HookMixin("customer-show", "ProfessionsCustomerOrdersMixin",
        "OnShow", RefreshCustomerOrders)
    HookMixin("customer-browse-init", "ProfessionsCustomerOrdersBrowsePageMixin",
        "Init", RefreshCustomerOrders)
    HookMixin("customer-orders-refresh", "ProfessionsCustomerOrdersMyOrdersMixin",
        "RefreshOrders", RefreshCustomerOrders)
    HookMixin("customer-form-init", "ProfessionsCustomerOrderFormMixin",
        "Init", RefreshCustomerOrders)
    HookMixin("customer-category-init", "ProfessionsCustomerOrdersCategoryButtonMixin",
        "Init", RefreshCustomerCategory)
    HookMixin("customer-category-selected", "ProfessionsCustomerOrdersCategoryButtonMixin",
        "UpdateSelected", RefreshCustomerCategory)
    HookMixin("customer-recipe-row-init", "ProfessionsCustomerOrdersRecipeListElementMixin",
        "Init", RefreshCustomerRow)
    HookMixin("customer-order-row-init", "ProfessionsCustomerOrderListElementMixin",
        "Init", RefreshCustomerRow)
    HookMixin("customer-listing-row-init", "ProfessionsCustomerListingsElementMixin",
        "Init", RefreshCustomerRow)
end

local function InstallGenericTraitHooks()
    HookMixin("generic-trait-layout", "GenericTraitFrameMixin",
        "ApplyLayout", RefreshGenericTraits)
    HookMixin("generic-trait-show", "GenericTraitFrameMixin",
        "OnShow", RefreshGenericTraits)
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
end

local function SkinWarbandCard(state, card)
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

    local count, decorated = 0, 0
    local visited = Kit.ForEachRow(icons, function(card)
        count = count + 1
        if SkinWarbandCard(state, card) then decorated = decorated + 1 end
        return count >= WARBAND_CARD_LIMIT
    end)
    if not visited then return false, "missing" end
    return true, decorated > 0 and "applied" or "waiting"
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

local function ApplyProfessions(state)
    if not CategoryEnabled("profession") then return true, "disabled" end
    InstallProfessionsHooks()
    return ApplyProfessionRoot(state, _G.ProfessionsFrame)
end

local function ApplyCustomerOrders(state)
    if not CategoryEnabled("profession") then return true, "disabled" end
    InstallCustomerOrderHooks()
    return ApplyCustomerOrdersRoot(state, _G.ProfessionsCustomerOrdersFrame)
end

local function ApplyCollections(state)
    if not CategoryEnabled("journal") then return true, "disabled" end
    local icons = WarbandIcons()
    if not icons then return false, "missing" end
    RegisterWarbandCallback(icons)
    return ApplyWarbandCards(state, icons)
end

local function ApplyGenericTraits(state)
    if not CategoryEnabled("character") then return true, "disabled" end
    InstallGenericTraitHooks()
    return ApplyGenericTraitRoot(state, _G.GenericTraitFrame)
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

local addonSpecs = {
    {
        addon = UI_PANELS_ADDON,
        relevant = function()
            return CategoryEnabled("quest") or CategoryEnabled("inventory")
        end,
        ready = function() return _G.QuestFrame ~= nil or _G.BankFrame ~= nil end,
        apply = ApplyUIPanels,
    },
    {
        addon = PROFESSIONS_ADDON,
        relevant = function() return CategoryEnabled("profession") end,
        ready = function() return _G.ProfessionsFrame ~= nil end,
        apply = ApplyProfessions,
    },
    {
        addon = CUSTOMER_ORDERS_ADDON,
        relevant = function() return CategoryEnabled("profession") end,
        ready = function() return _G.ProfessionsCustomerOrdersFrame ~= nil end,
        apply = ApplyCustomerOrders,
    },
    {
        addon = COLLECTIONS_ADDON,
        relevant = function() return CategoryEnabled("journal") end,
        ready = function() return _G.WarbandSceneJournal ~= nil end,
        apply = ApplyCollections,
    },
    {
        addon = GENERIC_TRAITS_ADDON,
        relevant = function() return CategoryEnabled("character") end,
        ready = function() return _G.GenericTraitFrame ~= nil end,
        apply = ApplyGenericTraits,
    },
}

local addonSpecByName = {}
for index = 1, #addonSpecs do
    addonSpecByName[addonSpecs[index].addon] = addonSpecs[index]
end

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

local function ApplyAddonForOwners(spec)
    for _, state in pairs(DeepWindows.owners) do
        if state.active and spec.relevant() then
            if NS.IsCombatLocked() then
                DeferApply(state, "load-" .. spec.addon)
            else
                spec.apply(state)
            end
        end
    end
end

local function ScheduleAddon(addon)
    if DeepWindows.waiting[addon] then return true end
    if NS.Client.IsAddOnLoaded(addon) then return false end
    DeepWindows.waiting[addon] = true
    local scheduled = Kit.ContinueOnAddOnLoaded(addon, function()
        DeepWindows.waiting[addon] = nil
        ApplyAddonForOwners(addonSpecByName[addon])
    end)
    if not scheduled then DeepWindows.waiting[addon] = nil end
    return scheduled
end

ApplyState = function(state)
    if not state or not state.active then return false, "disabled" end
    if NS.IsCombatLocked() then return DeferApply(state, "apply") end

    local applied, waiting, failed = 0, 0, 0
    for index = 1, #addonSpecs do
        local spec = addonSpecs[index]
        if spec.relevant() then
            if NS.Client.IsAddOnLoaded(spec.addon) or spec.ready() then
                local result, reason = spec.apply(state)
                if result and reason == "waiting" then
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

return DeepWindows
