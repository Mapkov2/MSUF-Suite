local _, NS = ...

-- Late-lifecycle coverage for the profession, customer-order and generic
-- trait windows. DeepWindows.lua (loaded before this file) owns the owner
-- lifecycle and the shared contract in its header; this file adds these
-- three windows as addon specs. Their chrome, pooled rows and page passes
-- follow Blizzard's lifecycle signals, one pass per frame at most.
local DeepWindows = NS.DeepWindows
-- DeepWindows.lua's private helpers: taken off NS again, so nothing
-- internal stays reachable through _G.MapkoSkin.
local Shared = NS.DeepWindowsShared
NS.DeepWindowsShared = nil

local Safety = NS.Safety
local Field = Safety.Field
local Kit = NS.AdapterKit
local Path = Kit.Path
local Fade = Kit.Fade

local CategoryEnabled = Shared.CategoryEnabled
local CanCreateRegions = Shared.CanCreateRegions
local ForActiveOwners = Shared.ForActiveOwners
local HookMixin = Shared.HookMixin

local DESCENDANT_DEPTH = 12

local PROFESSIONS_ADDON = "Blizzard_Professions"
local CUSTOMER_ORDERS_ADDON = "Blizzard_ProfessionsCustomerOrders"
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

local SkinCustomerCategory
local SkinCustomerRow

local function FadeRegion(region, state)
    Fade(state, region)
end

-- root -> skin generation of its last full pass
local rootGenerations = Kit.WeakSet()

local function ApplyDeepRoot(state, root, mode, allowCombat)
    if not state or not state.active or not root then return false, "missing" end
    if not allowCombat and NS.IsCombatLocked() then return false, "combat" end
    -- Use the parent catalog owner deliberately. GenericWindows already owns
    -- these roots and therefore remains the sole restorer for its surfaces,
    -- controls, dynamic ScrollBox callbacks and cosmetic state.
    local applied, reason = NS.GenericWindows.ApplyFrame(root, state.parentOwner, mode, allowCombat)
    if applied == true then rootGenerations[root] = Kit.SkinGeneration() end
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
local function SkinForeverProfessionBook(state, book, reuse)
    local content = Field(book, "ProfessionsContentFrame")
    if not content then return end
    local getSurface = NS.Registry.GetSurface
    if not reuse or not getSurface(content) then
        NS.GenericWindows.ApplyFrame(content, state.parentOwner, FOREVER_BOOK_MODE, true)
    end
    for index = 1, #FOREVER_PROFESSION_CARDS do
        local card = Field(content, FOREVER_PROFESSION_CARDS[index])
        if card then
            local surface = reuse and getSurface(card)
            local prepared = surface and surface.visible ~= false and surface.spec and surface.spec.role == "card"
            if prepared or NS.GenericWindows.ApplyFrame(card, state.parentOwner, FOREVER_CARD_MODE, true) then
                local background = Field(card, "Background")
                local alpha = prepared and Safety.Read(background, "GetAlpha")
                if (not prepared or type(alpha) == "number" and alpha > 0)
                    and Safety.CanDecorate(background, not NS.IsCombatLocked()) then
                    -- The generic card pass owns its artwork and restores it with the card.
                    NS.Cosmetics.Fade(background, state.parentOwner)
                end
            end
        end
    end
end

local function FadeProfessionChrome(state, root, changed)
    -- These exact parentKey-only frames are anonymous in Blizzard's XML, so
    -- the generic name-token traversal cannot identify their decorative art.
    -- Keep recipe, reagent, quality, reward and order-state content native.
    local crafting = Field(root, "CraftingPage")
    local schematic = Field(crafting, "SchematicForm")
    if not changed or changed == crafting then
        FadeProfessionRecipeList(state, Field(crafting, "RecipeList"))
        if NS.Client.isForever then Kit.FadeAtlas(state, crafting, "Profession-Background-Template2") end
    end
    if not changed or changed == crafting or changed == schematic then
        FadeProfessionSchematic(state, schematic, true)
    end

    local spec = Field(root, "SpecPage")
    if not changed or changed == spec then
        Fade(state, Path(spec, "TreeView", "Background"))
        Fade(state, Path(spec, "DetailedView", "Background"))
        Fade(state, Path(spec, "TreePreview", "Background"))
    end

    local orders = Field(root, "OrdersPage")
    if not changed or changed == orders then
        local browse = Field(orders, "BrowseFrame")
        FadeProfessionRecipeList(state, Field(browse, "RecipeList"))
        local orderList = Field(browse, "OrderList")
        Fade(state, Field(orderList, "Background"))
        Kit.FadeNineSlice(state, Field(orderList, "NineSlice"))
    end

    local orderView = Field(orders, "OrderView")
    if changed and changed ~= orders and changed ~= orderView then return end
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
    -- Row visitors are built once per owner, not per refresh.
    if not state.visitCategory then
        state.visitCategory = function(button) SkinCustomerCategory(state, button) end
        state.visitRow = function(button) SkinCustomerRow(state, button) end
    end
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

local PROFESSION_PAGES = { "CraftingPage", "SpecPage", "OrdersPage" }

local function WatchProfessionMotion(state, root)
    local watch, owner = NS.ContentMotion.Watch, state.parentOwner
    for index = 1, #PROFESSION_PAGES do
        watch(Field(root, PROFESSION_PAGES[index]), owner)
    end
    local book = NS.Client.isForever and Field(root, "BookPage")
    if not book or watch(book, owner) then return end
    -- Secure profession spell buttons protect their parent cards. Their rank
    -- displays are independent visual frames and can use the normal fade.
    local content = Field(book, "ProfessionsContentFrame")
    for index = 1, #FOREVER_PROFESSION_CARDS do
        watch(Path(content, FOREVER_PROFESSION_CARDS[index], "StatusBar"), owner)
    end
end

local function ApplyProfessionRoot(state, root)
    if not root or not CategoryEnabled("profession") or root ~= Field(_G, "ProfessionsFrame") then return false, "disabled" end
    local combat = NS.IsCombatLocked()
    if combat then Shared.RunOrDefer(state, "profession", ApplyProfessionRoot, root) end
    local applied, reason = ApplyDeepRoot(state, root, PROFESSION_MODE, true)
    if applied then
        FadeProfessionChrome(state, root)
        WatchProfessionMotion(state, root)
    end
    if NS.Client.isForever then
        local book = Field(root, "BookPage")
        if book and (combat and not Kit.IsHidden(book) or not combat and applied) then
            SkinForeverProfessionBook(state, book, combat)
        end
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

-- Blizzard's lifecycle signals arrive in bursts: one ProfessionsFrame:Refresh
-- refreshes every page (their SchematicPostInit, Init and Refresh run inner
-- first), and a recipe click runs the crafting page's SchematicPostInit.
-- Every pass runs at once inside the post-hook, so frames Blizzard's pools
-- create for the first time never show native art, and a frame takes at most
-- one pass per frame:
--   * a window-level signal (a tab switch, ApplyLayout) takes the root's full
--     pass;
--   * a page signal takes the node pass of that page's subtree only, unless
--     the root had its full pass this frame or has none in this skin
--     generation (then the root takes it);
--   * opening a window, or ProfessionsFrame:Refresh (every trade skill list
--     update, so every craft), takes none while the root was applied in this
--     skin generation: the page signals that rebuild its content (Refresh of
--     every page runs inside it) ask for their own.
local rootPasses = {
    {
        rootName = "ProfessionsFrame", category = "profession", mode = PROFESSION_MODE,
        apply = ApplyProfessionRoot, chrome = FadeProfessionChrome,
    },
    {
        rootName = "ProfessionsCustomerOrdersFrame", category = "profession", mode = CUSTOMER_ORDERS_MODE,
        apply = ApplyCustomerOrdersRoot, chrome = FadeCustomerOrdersChrome,
    },
    {
        rootName = "GenericTraitFrame", category = "character", mode = GENERIC_TRAITS_MODE,
        apply = ApplyGenericTraitRoot,
    },
}
local PROFESSIONS_PASS, CUSTOMER_ORDERS_PASS, GENERIC_TRAITS_PASS = rootPasses[1], rootPasses[2], rootPasses[3]

-- frame -> true while it had its pass in the current frame
local passedThisFrame = Kit.WeakSet()
local frameResetScheduled = false

local function ForgetFramePasses()
    frameResetScheduled = false
    for frame in pairs(passedThisFrame) do passedThisFrame[frame] = nil end
end

local function RememberPass(frame)
    passedThisFrame[frame] = true
    if not frameResetScheduled then
        frameResetScheduled = true
        C_Timer.After(0, ForgetFramePasses)
    end
end

-- Levels between root and frame, or nil when frame is not below root.
local function DepthBelow(root, frame)
    local current, depth = frame, 0
    while depth <= DESCENDANT_DEPTH do
        if current == root then return depth end
        current = Safety.Read(current, "GetParent")
        if current == nil then return nil end
        depth = depth + 1
    end
    return nil
end

-- The root pass's mode for a subtree depth levels below the root, so the
-- subtree keeps the depth limit the root's traversal gives it. Built once.
local subtreeModes = {}

local function SubtreeMode(rootMode, depth)
    local byDepth = subtreeModes[rootMode]
    if not byDepth then
        byDepth = {}
        subtreeModes[rootMode] = byDepth
    end
    local mode = byDepth[depth]
    if not mode then
        mode = {}
        for key, value in pairs(rootMode) do mode[key] = value end
        mode.maxDepth = math.max(0, rootMode.maxDepth - depth)
        byDepth[depth] = mode
    end
    return mode
end

local function ApplySubtree(state, pass, subtree)
    local root = _G[pass.rootName]
    local depth = DepthBelow(root, subtree)
    if not depth then return end
    local applied = NS.GenericWindows.ApplyDescendant(subtree, state.parentOwner, SubtreeMode(pass.mode, depth))
    -- The window's exact decorative fields, which Init can assign again.
    if pass == PROFESSIONS_PASS and NS.IsCombatLocked() then
        Shared.RunOrDefer(state, "profession", ApplyProfessionRoot, root)
    end
    if applied and pass.chrome then pass.chrome(state, root, subtree) end
end

local function RequestRootPass(pass, frame, opening)
    local root = _G[pass.rootName]
    if not Covers(root, frame) or passedThisFrame[root] then return end
    if opening and rootGenerations[root] == Kit.SkinGeneration() then return end
    RememberPass(root)
    ForActiveOwners(pass.category, pass.apply, root, nil, pass == PROFESSIONS_PASS)
end

local function RequestSubtreePass(pass, subtree)
    local root = _G[pass.rootName]
    if not root or not subtree or passedThisFrame[subtree] or not Covers(root, subtree) then return end
    local blockedRoot = pass == PROFESSIONS_PASS and NS.IsCombatLocked() and not Safety.CanCreateRegions(root)
    if passedThisFrame[root] and not blockedRoot then return end
    if not blockedRoot and rootGenerations[root] ~= Kit.SkinGeneration() then
        RememberPass(root)
        ForActiveOwners(pass.category, pass.apply, root, nil, pass == PROFESSIONS_PASS)
        return
    end
    RememberPass(subtree)
    ForActiveOwners(pass.category, ApplySubtree, pass, subtree, pass == PROFESSIONS_PASS)
end

local function RefreshProfessions(frame)
    RequestRootPass(PROFESSIONS_PASS, frame, true)
end

local function ProfessionsTabSet(frame)
    RequestRootPass(PROFESSIONS_PASS, frame, false)
end

local function ProfessionsOpened(frame)
    RequestRootPass(PROFESSIONS_PASS, frame, true)
end

local selectedProfession = Kit.WeakSet()

local function PlayProfessionSelection(state, frame, skill)
    NS.ContentMotion.Play(Field(frame, "CraftingPage"), state.parentOwner, skill)
end

local function ProfessionSelected(frame, tab)
    local skill = Field(tab, "skillLine")
    if not Safety.Public(skill) or skill ~= nil and type(skill) ~= "number" then return end
    local previous = selectedProfession[frame]
    if previous == skill then return end
    selectedProfession[frame] = skill
    if previous and skill then ForActiveOwners("profession", PlayProfessionSelection, frame, skill, true) end
end

local function RefreshProfessionPage(page)
    RequestSubtreePass(PROFESSIONS_PASS, page)
end

local function RefreshProfessionBook(book)
    if not Kit.IsHidden(book) then
        ForActiveOwners("profession", SkinForeverProfessionBook, book, true, true)
    end
end

-- SchematicPostInit ends SchematicForm:Init; only the schematic changed.
local function RefreshProfessionSchematic(page)
    RequestSubtreePass(PROFESSIONS_PASS, Field(page, "SchematicForm") or page)
end

local function RefreshCustomerOrdersPage(page)
    RequestSubtreePass(CUSTOMER_ORDERS_PASS, page)
end

local function CustomerOrdersOpened(frame)
    RequestRootPass(CUSTOMER_ORDERS_PASS, frame, true)
end

local function RefreshGenericTraits(frame)
    RequestRootPass(GENERIC_TRAITS_PASS, frame, false)
end

local function GenericTraitsOpened(frame)
    RequestRootPass(GENERIC_TRAITS_PASS, frame, true)
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
    if frame == _G.ProfessionsFrame then ProfessionsTabSet(frame) end
end

-- XML frames receive a copy of their mixin when Blizzard creates them, and
-- those frames exist before this adapter installs anything, so a hook on the
-- mixin table would never run for them. Their lifecycle methods are hooked
-- on the frame instance (once each); OnShow is observed as a script, which
-- works however the XML bound it.
local instanceHooks = setmetatable({}, { __mode = "k" })

local function HookInstance(frame, method, callback)
    if not frame then return false end
    local hooked = instanceHooks[frame]
    if not hooked then
        hooked = {}
        instanceHooks[frame] = hooked
    end
    if hooked[method] then return true end
    local installed
    if method == "OnShow" then
        installed = Safety.HasMethod(frame, "HookScript")
        if installed then frame:HookScript("OnShow", callback) end
    else
        installed = Kit.HookFunction(frame, method, callback)
    end
    hooked[method] = installed or nil
    return installed
end

local function InstallProfessionsHooks()
    if not DeepWindows.hooks.professionsTabSet then
        EventRegistry:RegisterCallback("ProfessionsFrame.TabSet", DeepWindows.OnProfessionsTabSet, DeepWindows)
        DeepWindows.hooks.professionsTabSet = true
    end

    -- Blizzard_ProfessionsFrame.xml, Blizzard_ProfessionsCrafting.xml and
    -- Blizzard_ProfessionsCrafterOrderPage/View.xml: the pages are parentKey
    -- children of ProfessionsFrame.
    local root = _G.ProfessionsFrame
    local crafting = Field(root, "CraftingPage")
    local orders = Field(root, "OrdersPage")
    HookInstance(root, "OnShow", ProfessionsOpened)
    HookInstance(root, "Refresh", RefreshProfessions)
    if NS.Client.isForever then
        HookInstance(Field(root, "BookPage"), "Update", RefreshProfessionBook)
        HookInstance(root, "RightTabSelected", ProfessionSelected)
    end
    HookInstance(crafting, "Init", RefreshProfessionPage)
    HookInstance(crafting, "Refresh", RefreshProfessionPage)
    -- A profession switch rebuilds the specialization tabs and tree here.
    HookInstance(Field(root, "SpecPage"), "Refresh", RefreshProfessionPage)
    HookInstance(crafting, "SchematicPostInit", RefreshProfessionSchematic)
    HookInstance(orders, "Init", RefreshProfessionPage)
    HookInstance(orders, "Refresh", RefreshProfessionPage)
    HookInstance(Field(orders, "OrderView"), "SchematicPostInit", RefreshProfessionPage)
end

local function InstallCustomerOrderHooks()
    -- Blizzard_ProfessionsCustomerOrders.xml: the pages are parentKey children.
    local root = _G.ProfessionsCustomerOrdersFrame
    HookInstance(root, "OnShow", CustomerOrdersOpened)
    HookInstance(Field(root, "BrowseOrders"), "Init", RefreshCustomerOrdersPage)
    HookInstance(Field(root, "MyOrdersPage"), "RefreshOrders", RefreshCustomerOrdersPage)
    HookInstance(Field(root, "Form"), "Init", RefreshCustomerOrdersPage)
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
    local root = _G.GenericTraitFrame
    HookInstance(root, "ApplyLayout", RefreshGenericTraits)
    HookInstance(root, "OnShow", GenericTraitsOpened)
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

local function ApplyGenericTraits(state)
    if not CategoryEnabled("character") then return true, "disabled" end
    InstallGenericTraitHooks()
    return ApplyGenericTraitRoot(state, _G.GenericTraitFrame)
end

-- DeepWindows.lua places each family in its apply order (FAMILY_ORDER).
Shared.AddAddonSpec({
    addon = PROFESSIONS_ADDON,
    relevant = function() return CategoryEnabled("profession") end,
    ready = function() return _G.ProfessionsFrame ~= nil end,
    apply = ApplyProfessions,
    allowCombat = true,
})
Shared.AddAddonSpec({
    addon = CUSTOMER_ORDERS_ADDON,
    relevant = function() return CategoryEnabled("profession") end,
    ready = function() return _G.ProfessionsCustomerOrdersFrame ~= nil end,
    apply = ApplyCustomerOrders,
})
Shared.AddAddonSpec({
    addon = GENERIC_TRAITS_ADDON,
    relevant = function() return CategoryEnabled("character") end,
    ready = function() return _G.GenericTraitFrame ~= nil end,
    apply = ApplyGenericTraits,
})
