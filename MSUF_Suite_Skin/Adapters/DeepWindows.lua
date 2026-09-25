local _, NS = ...

-- Bounded late-lifecycle coverage for a small set of Retail windows whose
-- material art or pooled descendants are created/refreshed after the normal
-- catalog pass.  Contracts were verified against Gethe/wow-ui-source
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

local DEFAULT_OWNER = "blizzardWindows"

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

local function WeakMap()
    return setmetatable({}, { __mode = "k" })
end

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function Path(object, ...)
    for index = 1, select("#", ...) do
        object = SafeField(object, select(index, ...))
        if not object then return nil end
    end
    return object
end

local function Report(label, message)
    if type(NS.ReportError) == "function" then
        NS.ReportError("deep windows " .. tostring(label), message)
    end
end

local function IsCombatLocked()
    return type(NS.IsCombatLocked) == "function" and NS.IsCombatLocked() == true
end

local function CategoryEnabled(category)
    local generic = NS.GenericWindows
    if generic and type(generic.IsCategoryEnabled) == "function" then
        local ok, enabled = pcall(generic.IsCategoryEnabled, category)
        return ok and enabled ~= false
    end
    return true
end

local function IsLoaded(addon)
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loadedOrLoading, loaded = pcall(C_AddOns.IsAddOnLoaded, addon)
        return ok and (loaded == true or (loaded == nil and loadedOrLoading == true))
    end
    if type(IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(IsAddOnLoaded, addon)
        return ok and loaded == true
    end
    return false
end

local function OwnerState(parentOwner)
    parentOwner = parentOwner or DEFAULT_OWNER
    local state = DeepWindows.owners[parentOwner]
    if not state then
        state = {
            parentOwner = parentOwner,
            skinOwner = tostring(parentOwner) .. ":deep-windows",
            active = false,
            deferred = {},
            cardSurfaces = WeakMap(),
        }
        DeepWindows.owners[parentOwner] = state
    end
    return state, parentOwner
end

local function CanDecorate(target)
    return target and NS.Safety
        and type(NS.Safety.CanDecorate) == "function"
        and NS.Safety.CanDecorate(target, true)
end

local function CanCreateRegions(target)
    return target and NS.Safety
        and type(NS.Safety.CanCreateRegions) == "function"
        and NS.Safety.CanCreateRegions(target, true)
end

local function Fade(state, region)
    if not state or not state.active or not region or IsCombatLocked()
        or not CanDecorate(region) or not NS.Cosmetics
        or type(NS.Cosmetics.Fade) ~= "function" then
        return false
    end
    local ok, applied = pcall(NS.Cosmetics.Fade, region, state.skinOwner)
    if not ok then Report("fade", applied) end
    return ok and applied == true
end

local nineSlicePieces = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

local function FadeNineSlice(state, nineSlice)
    if not nineSlice then return end
    for index = 1, #nineSlicePieces do
        Fade(state, SafeField(nineSlice, nineSlicePieces[index]))
    end
end

local function ParentIs(frame, expectedParent)
    local getter = SafeField(frame, "GetParent")
    if type(getter) ~= "function" then return false end
    local ok, parent = pcall(getter, frame)
    return ok and parent == expectedParent
end

local function IsDescendantOf(frame, ancestor, maxDepth)
    if not frame or not ancestor then return false end
    local current = frame
    for _ = 1, maxDepth or 12 do
        if current == ancestor then return true end
        local getter = SafeField(current, "GetParent")
        if type(getter) ~= "function" then return false end
        local ok, parent = pcall(getter, current)
        if not ok or not parent or parent == current then return false end
        current = parent
    end
    return current == ancestor
end

local function FadeMaterialPanel(state, panel)
    if not panel then return 0 end
    local faded = 0
    for index = 1, #MATERIAL_FIELDS do
        if Fade(state, SafeField(panel, MATERIAL_FIELDS[index])) then
            faded = faded + 1
        end
    end
    return faded
end

local function ApplyQuestAndGossip(state)
    if not state or not state.active then return false, "disabled" end
    if not CategoryEnabled("quest") then
        if NS.QuestText then
            NS.QuestText.Deactivate(_G.QuestFrame, state.skinOwner)
            NS.QuestText.Deactivate(_G.QuestLogPopupDetailFrame, state.skinOwner)
        end
        return true, "disabled"
    end
    if IsCombatLocked() then return false, "combat" end

    local faded = 0
    for index = 1, #QUEST_PANELS do
        faded = faded + FadeMaterialPanel(state, _G[QUEST_PANELS[index]])
    end
    if NS.QuestText then
        NS.QuestText.Activate(_G.QuestFrame, state.skinOwner)
        NS.QuestText.Activate(_G.QuestLogPopupDetailFrame, state.skinOwner)
    end

    local gossipPanel = Path(_G.GossipFrame, "GreetingPanel")
    if Fade(state, SafeField(gossipPanel, "MaterialTopLeft")) then
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
    if IsCombatLocked() then return false, "combat" end
    local generic = NS.GenericWindows
    if not generic or type(generic.ApplyFrame) ~= "function" then
        return false, "missing"
    end

    -- Use the parent catalog owner deliberately. GenericWindows already owns
    -- these roots and therefore remains the sole restorer for its surfaces,
    -- controls, dynamic ScrollBox callbacks and cosmetic state.
    local ok, applied, reason = pcall(generic.ApplyFrame,
        root, state.parentOwner, mode or PROFESSION_MODE)
    if not ok then
        Report("root reapply", applied)
        return false, "failed"
    end
    return applied == true, reason
end

local function FadeExactPanel(state, panel)
    if not panel then return end
    Fade(state, SafeField(panel, "Bg"))
    Fade(state, SafeField(panel, "Background"))
    FadeNineSlice(state, SafeField(panel, "NineSlice"))
end

local function FadeExactRegions(state, frame)
    local getter = SafeField(frame, "GetRegions")
    if type(getter) ~= "function" then return end
    pcall(function()
        local function Visit(...)
            for index = 1, select("#", ...) do
                Fade(state, select(index, ...))
            end
        end
        Visit(getter(frame))
    end)
end

local function FadeProfessionRecipeList(state, recipeList)
    if not recipeList then return end
    Fade(state, SafeField(recipeList, "Background"))
    FadeNineSlice(state, SafeField(recipeList, "BackgroundNineSlice"))
end

local function FadeProfessionDetails(state, details)
    if not details then return end
    for _, key in ipairs({
        "BackgroundTop", "BackgroundMiddle", "BackgroundBottom", "BackgroundMinimized",
    }) do
        Fade(state, SafeField(details, key))
    end
end

local function FadeProfessionSchematic(state, schematic, hasOwnNineSlice)
    if not schematic then return end
    Fade(state, SafeField(schematic, "Background"))
    Fade(state, SafeField(schematic, "MinimalBackground"))
    if hasOwnNineSlice then
        FadeNineSlice(state, SafeField(schematic, "NineSlice"))
    end
    FadeProfessionDetails(state, SafeField(schematic, "Details"))
end

local function FadeProfessionChrome(state, root)
    -- These exact parentKey-only frames are anonymous in Blizzard's XML, so
    -- the generic name-token traversal cannot identify their decorative art.
    -- Keep recipe, reagent, quality, reward and order-state content native.
    local crafting = SafeField(root, "CraftingPage")
    FadeProfessionRecipeList(state, SafeField(crafting, "RecipeList"))
    FadeProfessionSchematic(state, SafeField(crafting, "SchematicForm"), true)

    if NS.Client and NS.Client.isForever then
        -- Camelot puts its professions book inside ProfessionsFrame instead of
        -- loading the standalone ProfessionsBookFrame. The anonymous atlas on
        -- CraftingPage and the five book cards are exact decorative regions;
        -- spell buttons, rank bars, recipes, and profession icons stay native.
        if crafting and type(crafting.GetRegions) == "function" then
            local regions = { crafting:GetRegions() }
            for index = 1, #regions do
                local region = regions[index]
                if type(region.GetAtlas) == "function"
                    and region:GetAtlas() == "Profession-Background-Template2" then
                    Fade(state, region)
                end
            end
        end
        local content = Path(root, "BookPage", "ProfessionsContentFrame")
        if content then
            NS.GenericWindows.ApplyFrame(content, state.parentOwner, {
                role = "panel", maxDepth = 0, maxNodes = 1,
                fillVisible = false, childSurfaces = false, registerDynamicRows = false,
                allowImplicitProtected = true,
            })
            for _, key in ipairs({
                "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1",
                "SecondaryProfession2", "SecondaryProfession3",
            }) do
                local card = SafeField(content, key)
                if card then
                    NS.GenericWindows.ApplyFrame(card, state.parentOwner, {
                        role = "card", maxDepth = 0, maxNodes = 1,
                        childSurfaces = false, registerDynamicRows = false,
                        allowImplicitProtected = true,
                    })
                    Fade(state, SafeField(card, "Background"))
                end
            end
        end
    end

    Fade(state, Path(root, "SpecPage", "TreeView", "Background"))
    Fade(state, Path(root, "SpecPage", "DetailedView", "Background"))
    Fade(state, Path(root, "SpecPage", "TreePreview", "Background"))

    local orders = SafeField(root, "OrdersPage")
    local browse = SafeField(orders, "BrowseFrame")
    FadeProfessionRecipeList(state, SafeField(browse, "RecipeList"))
    local orderList = SafeField(browse, "OrderList")
    Fade(state, SafeField(orderList, "Background"))
    FadeNineSlice(state, SafeField(orderList, "NineSlice"))

    local orderView = SafeField(orders, "OrderView")
    local orderInfo = SafeField(orderView, "OrderInfo")
    Fade(state, SafeField(orderInfo, "Background"))
    FadeNineSlice(state, SafeField(orderInfo, "NineSlice"))
    local orderDetails = SafeField(orderView, "OrderDetails")
    Fade(state, SafeField(orderDetails, "Background"))
    FadeNineSlice(state, SafeField(orderDetails, "NineSlice"))
    -- This concrete order SchematicForm has no own NineSlice in Retail.
    FadeProfessionSchematic(state, SafeField(orderDetails, "SchematicForm"), false)
end

local function RegionIsShown(region)
    local getter = SafeField(region, "IsShown")
    if type(getter) ~= "function" then return false end
    local ok, shown = pcall(getter, region)
    return ok and shown == true
end

local function SkinCustomerCategory(state, button)
    if not state or not state.active or not button or SafeField(button, "isSpacer") == true
        or IsCombatLocked() or not CanCreateRegions(button)
        or not SafeField(button, "Text") or not SafeField(button, "NormalTexture")
        or not SafeField(button, "HighlightTexture") or not SafeField(button, "SelectedTexture")
        or not SafeField(button, "Lines") or not SafeField(button, "SpacerLine")
        or not NS.ControlSkin or type(NS.ControlSkin.ApplyButton) ~= "function" then
        return false
    end
    CUSTOMER_CATEGORY_SPEC.active = RegionIsShown(SafeField(button, "SelectedTexture"))
    local ok, applied = pcall(NS.ControlSkin.ApplyButton,
        button, state.skinOwner, CUSTOMER_CATEGORY_SPEC)
    CUSTOMER_CATEGORY_SPEC.active = nil
    if not ok then Report("customer category", applied) end
    return ok and applied ~= nil
end

local function SkinCustomerRow(state, button)
    if not state or not state.active or not button or IsCombatLocked()
        or not CanCreateRegions(button) or not SafeField(button, "HighlightTexture")
        or not NS.ControlSkin or type(NS.ControlSkin.ApplyButton) ~= "function" then
        return false
    end
    local ok, applied = pcall(NS.ControlSkin.ApplyButton,
        button, state.skinOwner, CUSTOMER_ROW_SPEC)
    if not ok then Report("customer row", applied) end
    return ok and applied ~= nil
end

local function ForEachVisibleRow(scrollBox, callback)
    local forEach = SafeField(scrollBox, "ForEachFrame")
    if type(forEach) ~= "function" or type(callback) ~= "function" then return end
    pcall(forEach, scrollBox, callback)
end

local function SkinVisibleCustomerRows(state, root)
    local browse = SafeField(root, "BrowseOrders")
    ForEachVisibleRow(Path(browse, "CategoryList", "ScrollBox"), function(button)
        SkinCustomerCategory(state, button)
    end)
    ForEachVisibleRow(Path(browse, "RecipeList", "ScrollBox"), function(button)
        SkinCustomerRow(state, button)
    end)
    ForEachVisibleRow(Path(root, "MyOrdersPage", "OrderList", "ScrollBox"), function(button)
        SkinCustomerRow(state, button)
    end)
    ForEachVisibleRow(Path(root, "Form", "CurrentListings", "OrderList", "ScrollBox"), function(button)
        SkinCustomerRow(state, button)
    end)
end

local function FadeCustomerOrdersChrome(state, root)
    -- Standalone customer orders copies Auction House chrome into anonymous
    -- parentKey frames. Fade only those source-confirmed decorative members;
    -- recipe icons, favorites, text, money and order state remain native.
    FadeExactPanel(state, SafeField(root, "MoneyFrameInset"))
    FadeExactRegions(state, SafeField(root, "MoneyFrameBorder"))

    local browse = SafeField(root, "BrowseOrders")
    FadeExactPanel(state, SafeField(browse, "CategoryList"))
    FadeExactPanel(state, SafeField(browse, "RecipeList"))

    FadeExactPanel(state, Path(root, "MyOrdersPage", "OrderList"))

    local form = SafeField(root, "Form")
    Fade(state, SafeField(form, "RecipeHeader"))
    FadeExactPanel(state, SafeField(form, "LeftPanelBackground"))
    FadeExactPanel(state, SafeField(form, "RightPanelBackground"))
    Fade(state, Path(form, "PaymentContainer", "NoteEditBox", "Border"))
    local listings = SafeField(form, "CurrentListings")
    FadeExactPanel(state, listings)
    FadeExactPanel(state, SafeField(listings, "OrderList"))

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
    Fade(state, SafeField(root, "Background"))
    Fade(state, SafeField(root, "BorderOverlay"))
    FadeNineSlice(state, SafeField(root, "NineSlice"))
    Fade(state, Path(root, "NineSlice", "DetailTop"))
    Fade(state, Path(root, "Header", "TitleDivider"))
    Fade(state, Path(root, "Inset", "Bg"))
    FadeNineSlice(state, Path(root, "Inset", "NineSlice"))
    Fade(state, Path(root, "Currency", "CurrencyBackground"))
end

local function ApplyGenericTraitRoot(state, root)
    local applied, reason = ApplyDeepRoot(state, root, GENERIC_TRAITS_MODE)
    if applied then FadeGenericTraitChrome(state, root) end
    return applied, reason
end

local function ApplyProfessionRootForOwners(root, descendant)
    if IsCombatLocked() or not root then return end
    if descendant and not IsDescendantOf(descendant, root, 12) then return end
    for _, state in pairs(DeepWindows.owners) do
        if state.active and CategoryEnabled("profession") then
            ApplyProfessionRoot(state, root)
        end
    end
end

local function RefreshProfessions(frame)
    local root = _G.ProfessionsFrame
    if root and (frame == nil or frame == root or IsDescendantOf(frame, root, 12)) then
        ApplyProfessionRootForOwners(root, frame)
    end
end

local function RefreshCustomerOrders(frame)
    local root = _G.ProfessionsCustomerOrdersFrame
    if root and (frame == nil or frame == root or IsDescendantOf(frame, root, 12)) then
        for _, state in pairs(DeepWindows.owners) do
            if state.active and CategoryEnabled("profession") then
                ApplyCustomerOrdersRoot(state, root)
            end
        end
    end
end

local function RefreshGenericTraits(frame)
    local root = _G.GenericTraitFrame
    if not root or (frame ~= nil and frame ~= root
        and not IsDescendantOf(frame, root, 12)) then
        return
    end
    for _, state in pairs(DeepWindows.owners) do
        if state.active and CategoryEnabled("character") then
            ApplyGenericTraitRoot(state, root)
        end
    end
end


local function RefreshCustomerCategory(button)
    local root = _G.ProfessionsCustomerOrdersFrame
    if not root or not IsDescendantOf(button, root, 12) or IsCombatLocked() then return end
    for _, state in pairs(DeepWindows.owners) do
        if state.active and CategoryEnabled("profession") then
            SkinCustomerCategory(state, button)
        end
    end
end

local function RefreshCustomerRow(button)
    local root = _G.ProfessionsCustomerOrdersFrame
    if not root or not IsDescendantOf(button, root, 12) or IsCombatLocked() then return end
    for _, state in pairs(DeepWindows.owners) do
        if state.active and CategoryEnabled("profession") then
            SkinCustomerRow(state, button)
        end
    end
end

function DeepWindows:OnProfessionsTabSet(frame)
    if frame == _G.ProfessionsFrame then RefreshProfessions(frame) end
end

local function HookMixin(key, mixinName, methodName, callback)
    if DeepWindows.hooks[key] then return true end
    local mixin = _G[mixinName]
    if type(mixin) ~= "table" or type(SafeField(mixin, methodName)) ~= "function"
        or type(hooksecurefunc) ~= "function" then
        return false
    end
    local ok, message = pcall(hooksecurefunc, mixin, methodName, callback)
    if not ok then
        Report("hook " .. key, message)
        return false
    end
    DeepWindows.hooks[key] = true
    return true
end

-- CommonMenus owns the exact bag renderer and active-owner gate. This audited
-- adapter owns the sole irreversible post-hook so every permanent lifecycle
-- hook remains centralized in the project's allowlisted files.
function DeepWindows.InstallContainerGenerateHook(callback)
    if type(callback) ~= "function" then return false end
    if DeepWindows.hooks.containerGenerate then return true end
    if type(hooksecurefunc) ~= "function"
        or type(_G.ContainerFrame_GenerateFrame) ~= "function" then
        return false
    end

    DeepWindows.containerGenerateCallback = callback
    local ok, message = pcall(hooksecurefunc, "ContainerFrame_GenerateFrame", function(frame)
        local current = DeepWindows.containerGenerateCallback
        if type(current) == "function" then current(frame) end
    end)
    if not ok then
        DeepWindows.containerGenerateCallback = nil
        Report("hook container-generate", message)
        return false
    end
    DeepWindows.hooks.containerGenerate = true
    return true
end

local function InstallProfessionsHooks()
    if not DeepWindows.hooks.professionsTabSet and EventRegistry
        and type(EventRegistry.RegisterCallback) == "function" then
        local ok, message = pcall(EventRegistry.RegisterCallback, EventRegistry,
            "ProfessionsFrame.TabSet", DeepWindows.OnProfessionsTabSet, DeepWindows)
        if ok then
            DeepWindows.hooks.professionsTabSet = true
        else
            Report("ProfessionsFrame.TabSet", message)
        end
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
        or not ParentIs(tab, panel) or not SafeField(tab, "tabData")
        or IsCombatLocked() or not CategoryEnabled("inventory")
        or not NS.ControlSkin or type(NS.ControlSkin.ApplyTab) ~= "function" then
        return false
    end
    local ok, applied = pcall(NS.ControlSkin.ApplyTab,
        tab, state.skinOwner, BANK_TAB_SPEC)
    if not ok then Report("bank tab", applied) end
    return ok and applied ~= nil
end

local function SkinBankItem(state, button, panel)
    if not state or not state.active or not button or not panel
        or not ParentIs(button, panel) or IsCombatLocked()
        or not CategoryEnabled("inventory") or not NS.IconSkin
        or type(NS.IconSkin.Apply) ~= "function" then
        return false
    end

    -- Current BankPanelItemButtonMixin uses the inherited lowercase item icon
    -- and the inherited IconBorder updated by SetItemButtonQuality. Cooldown,
    -- SearchOverlay, IconQuestTexture, Background and itemLocation stay native.
    local icon = SafeField(button, "icon")
    local qualityBorder = SafeField(button, "IconBorder")
    if not icon or not qualityBorder then return false end
    local ok, applied = pcall(NS.IconSkin.Apply, button, state.skinOwner, {
        icon = icon,
        nativeBorder = qualityBorder,
        allowImplicitProtected = true,
    })
    if not ok then Report("bank item", applied) end
    return ok and applied ~= nil
end

local function EnumerateActive(pool, limit, callback)
    local enumerate = SafeField(pool, "EnumerateActive")
    if type(enumerate) ~= "function" or type(callback) ~= "function" then
        return false
    end
    local ok, iterator, invariant, control = pcall(enumerate, pool)
    if not ok or type(iterator) ~= "function" then return false end
    for _ = 1, limit do
        local iterOk, value = pcall(iterator, invariant, control)
        if not iterOk or value == nil then break end
        control = value
        callback(value)
    end
    return true
end

local function ApplyBank(state)
    if not state or not state.active then return false, "disabled" end
    if not CategoryEnabled("inventory") then return true, "disabled" end
    if IsCombatLocked() then return false, "combat" end
    local panel = Path(_G.BankFrame, "BankPanel")
    if not panel then return false, "missing" end

    local decorated = 0
    if SkinBankTab(state, SafeField(panel, "PurchaseTab"), panel) then
        decorated = decorated + 1
    end
    EnumerateActive(SafeField(panel, "bankTabPool"), 32, function(tab)
        if SkinBankTab(state, tab, panel) then decorated = decorated + 1 end
    end)
    EnumerateActive(SafeField(panel, "itemButtonPool"), 128, function(button)
        if SkinBankItem(state, button, panel) then decorated = decorated + 1 end
    end)
    return true, decorated > 0 and "applied" or "waiting"
end

local function RefreshBankTab(tab)
    if IsCombatLocked() then return end
    local panel = Path(_G.BankFrame, "BankPanel")
    if not panel or not ParentIs(tab, panel) then return end
    for _, state in pairs(DeepWindows.owners) do
        if state.active and CategoryEnabled("inventory") then
            SkinBankTab(state, tab, panel)
        end
    end
end

local function RefreshBankItem(button)
    if IsCombatLocked() then return end
    local panel = Path(_G.BankFrame, "BankPanel")
    if not panel or not ParentIs(button, panel) then return end
    for _, state in pairs(DeepWindows.owners) do
        if state.active and CategoryEnabled("inventory") then
            SkinBankItem(state, button, panel)
        end
    end
end

local function InstallBankHooks()
    HookMixin("bank-tab-init", "BankPanelTabMixin", "Init", RefreshBankTab)
    HookMixin("bank-item-init", "BankPanelItemButtonMixin", "Init", RefreshBankItem)
end

local function SkinWarbandCard(state, card)
    if not state or not state.active or not card or IsCombatLocked()
        or not CategoryEnabled("journal") or not CanCreateRegions(card)
        or not SafeField(card, "Icon") or not SafeField(card, "Name")
        or not SafeField(card, "NameBackground") or not SafeField(card, "Border")
        or not SafeField(card, "SlotFavorite") or not SafeField(card, "HighlightTexture")
        or not NS.Surface or type(NS.Surface.Attach) ~= "function"
        or not NS.Registry or type(NS.Registry.GetSurface) ~= "function" then
        return false
    end

    local existing = NS.Registry.GetSurface(card)
    local record = DeepWindows.warbandSurfaces[card]
    if existing then
        if not record or record.surface ~= existing
            or SafeField(existing, "spec") ~= WARBAND_CARD_SPEC
            or (record.owner and record.owner ~= state.skinOwner) then
            return false
        end
    end

    local ok, surface = pcall(NS.Surface.Attach, card, WARBAND_CARD_SPEC)
    if not ok then
        Report("warband card", surface)
        return false
    end
    if not surface then return false end

    record = record or {}
    record.surface = surface
    record.owner = state.skinOwner
    DeepWindows.warbandSurfaces[card] = record
    state.cardSurfaces[card] = surface
    Fade(state, SafeField(card, "NameBackground"))
    Fade(state, SafeField(card, "Border"))
    return true
end

local function ApplyWarbandCards(state, icons)
    if not state or not state.active then return false, "disabled" end
    if not CategoryEnabled("journal") then return true, "disabled" end
    if IsCombatLocked() then return false, "combat" end
    icons = icons or Path(_G.WarbandSceneJournal, "IconsFrame", "Icons")
    if not icons or icons ~= Path(_G.WarbandSceneJournal, "IconsFrame", "Icons") then
        return false, "missing"
    end
    local forEach = SafeField(icons, "ForEachFrame")
    if type(forEach) ~= "function" then return false, "missing" end

    local count = 0
    local decorated = 0
    local ok, message = pcall(forEach, icons, function(card)
        count = count + 1
        if SkinWarbandCard(state, card) then decorated = decorated + 1 end
        return count >= 64
    end)
    if not ok then
        Report("warband enumeration", message)
        return false, "failed"
    end
    return true, decorated > 0 and "applied" or "waiting"
end

local function RefreshWarbandOwners(icons)
    if IsCombatLocked() or icons ~= Path(_G.WarbandSceneJournal, "IconsFrame", "Icons") then
        return
    end
    for _, state in pairs(DeepWindows.owners) do
        if state.active and CategoryEnabled("journal") then
            ApplyWarbandCards(state, icons)
        end
    end
end

function DeepWindows:OnWarbandSceneUpdate()
    RefreshWarbandOwners(Path(_G.WarbandSceneJournal, "IconsFrame", "Icons"))
end

local function RegisterWarbandCallback(icons)
    if not icons or DeepWindows.warbandCallbacks[icons] then return icons ~= nil end
    local event = Path(_G.PagedContentFrameBaseMixin, "Event", "OnUpdate")
    local register = SafeField(icons, "RegisterCallback")
    if not event or type(register) ~= "function" then return false end
    local ok, message = pcall(register, icons, event,
        DeepWindows.OnWarbandSceneUpdate, DeepWindows)
    if not ok then
        Report("warband callback", message)
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
    local icons = Path(_G.WarbandSceneJournal, "IconsFrame", "Icons")
    if not icons then return false, "missing" end
    RegisterWarbandCallback(icons)
    return ApplyWarbandCards(state, icons)
end

local function ApplyGenericTraits(state)
    if not CategoryEnabled("character") then return true, "disabled" end
    InstallGenericTraitHooks()
    return ApplyGenericTraitRoot(state, _G.GenericTraitFrame)
end

local function ApplyUIPanels(state)
    local attempted, applied, waiting = 0, 0, 0
    if CategoryEnabled("quest") then
        attempted = attempted + 1
        local ok, reason = ApplyQuestAndGossip(state)
        if ok and reason == "waiting" then
            waiting = waiting + 1
        elseif ok then
            applied = applied + 1
        end
    end
    if CategoryEnabled("inventory") then
        attempted = attempted + 1
        InstallBankHooks()
        local ok, reason = ApplyBank(state)
        if ok and reason == "waiting" then
            waiting = waiting + 1
        elseif ok then
            applied = applied + 1
        end
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

local function CancelDeferred(state)
    if not state then return end
    for key in pairs(state.deferred) do
        if NS.CombatGate and type(NS.CombatGate.Cancel) == "function" then
            NS.CombatGate.Cancel(key)
        end
        state.deferred[key] = nil
    end
end

local function DeferApply(state, suffix)
    if not state or not state.active or not NS.CombatGate
        or type(NS.CombatGate.RunOrDefer) ~= "function" then
        return false, "combat"
    end
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
    if not spec then return end
    if IsCombatLocked() then
        for _, state in pairs(DeepWindows.owners) do
            if state.active and spec.relevant() then
                DeferApply(state, "load-" .. spec.addon)
            end
        end
        return
    end
    for _, state in pairs(DeepWindows.owners) do
        if state.active and spec.relevant() then
            local ok, applied = pcall(spec.apply, state)
            if not ok then Report("load " .. spec.addon, applied) end
        end
    end
end

local function ScheduleAddon(addon)
    if DeepWindows.waiting[addon] then return true end
    if IsLoaded(addon) or not EventUtil
        or type(EventUtil.ContinueOnAddOnLoaded) ~= "function" then
        return false
    end
    DeepWindows.waiting[addon] = true
    local ok, message = pcall(EventUtil.ContinueOnAddOnLoaded, addon, function()
        DeepWindows.waiting[addon] = nil
        ApplyAddonForOwners(addonSpecByName[addon])
    end)
    if not ok then
        DeepWindows.waiting[addon] = nil
        Report("load " .. addon, message)
        return false
    end
    return true
end

ApplyState = function(state)
    if not state or not state.active then return false, "disabled" end
    if IsCombatLocked() then return DeferApply(state, "apply") end

    local applied, waiting, failed = 0, 0, 0
    for index = 1, #addonSpecs do
        local spec = addonSpecs[index]
        if spec.relevant() then
            if IsLoaded(spec.addon) or spec.ready() then
                local ok, result, reason = pcall(spec.apply, state)
                if ok and result and reason == "waiting" then
                    waiting = waiting + 1
                elseif ok and result then
                    applied = applied + 1
                else
                    failed = failed + 1
                    if not ok then Report(spec.addon, result) end
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

local function DisableNow(state)
    if not state then return true end
    state.active = false
    CancelDeferred(state)
    if NS.QuestText then
        NS.QuestText.Deactivate(_G.QuestFrame, state.skinOwner)
        NS.QuestText.Deactivate(_G.QuestLogPopupDetailFrame, state.skinOwner)
    end

    if NS.ControlSkin and type(NS.ControlSkin.DisableOwner) == "function" then
        pcall(NS.ControlSkin.DisableOwner, state.skinOwner)
    end
    if NS.IconSkin and type(NS.IconSkin.DisableOwner) == "function" then
        pcall(NS.IconSkin.DisableOwner, state.skinOwner)
    end
    if NS.Surface and type(NS.Surface.SetVisible) == "function"
        and NS.Registry and type(NS.Registry.GetSurface) == "function" then
        for card, surface in pairs(state.cardSurfaces) do
            local current = NS.Registry.GetSurface(card)
            local record = DeepWindows.warbandSurfaces[card]
            if current == surface and record and record.surface == surface
                and record.owner == state.skinOwner
                and SafeField(current, "spec") == WARBAND_CARD_SPEC then
                pcall(NS.Surface.SetVisible, card, false)
                record.owner = nil
            end
        end
    end
    if NS.Cosmetics and type(NS.Cosmetics.RestoreOwner) == "function" then
        pcall(NS.Cosmetics.RestoreOwner, state.skinOwner)
    end

    DeepWindows.owners[state.parentOwner] = nil
    return true
end

function DeepWindows.Apply(parentOwner)
    local state
    state, parentOwner = OwnerState(parentOwner)
    CancelDeferred(state)
    state.active = true
    if IsCombatLocked() then return DeferApply(state, "apply") end
    return ApplyState(state)
end

function DeepWindows.Disable(parentOwner)
    parentOwner = parentOwner or DEFAULT_OWNER
    local state = DeepWindows.owners[parentOwner]
    if not state then return true end

    CancelDeferred(state)
    if IsCombatLocked() then
        state.active = false
        if NS.CombatGate and type(NS.CombatGate.RunOrDefer) == "function" then
            local key = DeferredKey(state, "disable")
            state.deferred[key] = true
            NS.CombatGate.RunOrDefer(key, function()
                local current = DeepWindows.owners[parentOwner]
                if current then
                    current.deferred[key] = nil
                    if not current.active then DisableNow(current) end
                end
            end)
        end
        return false, "combat"
    end

    return DisableNow(state)
end

return DeepWindows
