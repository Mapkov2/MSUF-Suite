local _, NS = ...

-- Small runtime companion for catalog windows whose roots or cosmetic regions
-- are created after the main adapter pass. Names and callbacks were verified
-- against Gethe/wow-ui-source upstream/live at
-- 8ea15b61e45c0ed4eba01439c90757f86eb78d34.
--
-- This module deliberately does not load Blizzard addons. Catalog.lua owns
-- LoD discovery; the callbacks below only refresh objects created by normal
-- Blizzard UI activity. No Blizzard scripts, mixins, methods, or frame fields
-- are replaced.

local CommonMenus = {
    activeOwnerCount = 0,
    callbackState = {},
}
NS.CommonMenus = CommonMenus

local Field = NS.Safety.Field
local Dispatch = NS.Safety.Dispatch
local Kit = NS.AdapterKit

local DEFAULT_OWNER = "blizzardWindows"
local BAG_OPEN_CALLBACK = "ContainerFrame.OpenBag"
local BAG_ITEM_LIMIT = 256

local BAG_MODE = {
    role = "shell",
    allowImplicitProtected = true,
}

local BAG_ITEM_SPEC = {
    role = "button",
    activeRole = "buttonPrimary",
    useControlShape = false,
    shape = "continuous",
    radius = 4,
    inset = 1,
    regions = { "NormalTexture", "ItemSlotBackground" },
    allowImplicitProtected = true,
}

local BAG_MONEY_SPEC = {
    role = "status",
    shape = "continuous",
    radius = 4,
    inset = 0,
    border = 1,
    allowImplicitProtected = true,
}

local BAG_SEARCH_SPEC = { role = "input", radius = 4, inset = 0, allowImplicitProtected = true }
local BAG_ACTION_SPEC = { role = "button", radius = 4, inset = 1, allowImplicitProtected = true }
local MONEY_BORDER_FIELDS = { "Left", "Middle", "Right" }

-- These named regions are textures rather than frames, so the bounded child
-- traversal cannot discover them reliably. Cosmetics.Fade records their
-- original alpha under the shared owner and GenericWindows.Disable restores it.
local cosmeticGlobals = {
    { category = "npc", names = { "BuybackBG", "MerchantFrameBottomLeftBorder" } },
    { category = "social", names = {
        "InboxFrameBg", "SendStationeryBackgroundLeft", "SendStationeryBackgroundRight",
        "OpenStationeryBackgroundLeft", "OpenStationeryBackgroundRight",
    } },
}

-- Deferral keys are commonMenus:<owner>:<suffix>.
local Owners = Kit.NewOwners({
    prefix = "commonMenus",
    default = DEFAULT_OWNER,
    surfaces = true,
    init = function(state)
        -- bag frame / pooled item button -> skin generation of its pass
        state.frames = Kit.WeakSet()
        state.items = Kit.WeakSet()
        -- pooled item button -> the ItemSlotBackground its pass faded (or false)
        state.slotBackgrounds = Kit.WeakSet()
    end,
})
CommonMenus.owners = Owners.owners

local function SkinBagItem(state, frame, button)
    if not button or not Kit.ParentIs(button, frame)
        or type((Field(button, "GetBagID"))) ~= "function"
        or type((Field(button, "GetID"))) ~= "function" then
        return false
    end
    local icon = Field(button, "icon")
    local qualityBorder = Field(button, "IconBorder")
    if not icon or not qualityBorder then return false end

    local control = NS.ControlSkin.ApplyButton(button, state.owner, BAG_ITEM_SPEC)
    local iconSkinned = Kit.SkinItemIcon(button, state.owner, icon, qualityBorder, true)
    return control ~= nil and iconSkinned
end

-- A pooled item button keeps its control skin while Blizzard reuses it, so
-- that takes one pass per skin generation, or again when Initialize gave the
-- button an ItemSlotBackground (combined bags) after that pass. Its quality
-- border follows its contents: the SetItemButtonQuality post-hook
-- (DeepWindows) repaints it when UpdateItems sets it. Only without that hook
-- is it repainted here on every opening; IconSkin reads the native
-- IconBorder while it skins, and on a button it owns that repaint creates no
-- regions and no tables.
local function RefreshBagItem(state, frame, button, generation)
    local slotBackground = Field(button, "ItemSlotBackground") or false
    if state.items[button] ~= generation or state.slotBackgrounds[button] ~= slotBackground then
        if not SkinBagItem(state, frame, button) then return false end
        state.items[button] = generation
        state.slotBackgrounds[button] = slotBackground
        return true
    end
    if CommonMenus.callbackState.qualityHook then return true end
    local icon, qualityBorder = Field(button, "icon"), Field(button, "IconBorder")
    return icon ~= nil and qualityBorder ~= nil and Kit.ParentIs(button, frame)
        and Kit.SkinItemIcon(button, state.owner, icon, qualityBorder, true)
end

-- ContainerFrame item buttons come from its itemButtonPool (Retail and
-- Forever: Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua).
local function RefreshBagItems(state, frame, generation)
    local pool = Field(frame, "itemButtonPool")
    if type((Field(pool, "EnumerateActive"))) ~= "function" then return 0 end
    local count, visited = 0, 0
    for button in pool:EnumerateActive() do
        if visited >= BAG_ITEM_LIMIT then break end
        visited = visited + 1
        if RefreshBagItem(state, frame, button, generation) then count = count + 1 end
    end
    return count
end

local function SkinMoneyFrame(state, frame)
    local money = Field(frame, "MoneyFrame")
    local border = Field(money, "Border")
    if not money or not border or not Kit.Attach(state, money, BAG_MONEY_SPEC) then
        return false
    end
    Kit.FadeFields(state, border, MONEY_BORDER_FIELDS)
    return true
end

-- Opening a bag reaches here twice: the OpenBag callback fires in
-- ContainerFrame_OnShow, before UpdateItems has filled the reused buttons,
-- and the post-hook runs once ContainerFrame_GenerateFrame has finished. The
-- bag window's static tree takes one full pass per skin generation; the item
-- buttons (refreshItems) are handled from the post-hook, once their contents
-- and quality borders are current. The shared search/sort controls follow
-- the bag that currently holds them.
local function ApplyBagFrame(state, frame, refreshItems)
    local owner = state.owner
    local generation = Kit.SkinGeneration()
    if state.frames[frame] ~= generation then
        if not NS.GenericWindows.ApplyFrame(frame, owner, BAG_MODE) then return false end
        state.frames[frame] = generation
        SkinMoneyFrame(state, frame)
        local close = Field(frame, "CloseButton")
        if close then NS.WindowActionSkin.Apply(close, owner, "close") end
    end
    if refreshItems then RefreshBagItems(state, frame, generation) end
    -- ContainerFrameMixin:UpdateSearchBox reparents these shared controls after
    -- the initial traversal. Revisit only their exact current bag owner.
    local search, sort = BagItemSearchBox, BagItemAutoSortButton
    if Kit.ParentIs(search, frame) then
        NS.ControlSkin.ApplySearchBox(search, owner, BAG_SEARCH_SPEC)
    end
    if Kit.ParentIs(sort, frame) and NS.Surface.Attach(sort, BAG_ACTION_SPEC) then
        -- Keep the native sort icon, scripts and highlight; just add its plate.
        state.surfaces[sort] = true
    end
    return true
end

local function FadeCosmeticGlobals(state)
    local faded = 0
    for index = 1, #cosmeticGlobals do
        local group = cosmeticGlobals[index]
        if NS.GenericWindows.IsCategoryEnabled(group.category) then
            for nameIndex = 1, #group.names do
                if Kit.Fade(state, _G[group.names[nameIndex]]) then
                    faded = faded + 1
                end
            end
        end
    end
    return faded
end

local function ApplyBagForOwners(frame, refreshItems)
    -- Bag windows are usable in combat. Cosmetic traversal is optional, so do
    -- absolutely no queueing or mutation there; the next out-of-combat open
    -- refreshes the rebuilt item pool. Only this one dynamic root is visited,
    -- never every catalog window.
    if not frame or NS.IsCombatLocked() or not NS.GenericWindows.IsCategoryEnabled("inventory") then
        return
    end
    -- Each owner's pass is its own error boundary: this runs from Blizzard's
    -- OpenBag callback and ContainerFrame_GenerateFrame post-hook.
    for _, state in pairs(CommonMenus.owners) do
        if state.active then Dispatch(ApplyBagFrame, state, frame, refreshItems) end
    end
end

-- The item buttons wait for the post-hook when it is installed.
function CommonMenus:OnBagOpened(frame)
    ApplyBagForOwners(frame, CommonMenus.callbackState.generateHook ~= true)
end

-- ContainerFrame_GenerateFrame finishes after search/sort controls, money,
-- optional add-slot controls and the item update have run. This exact
-- post-hook complements the earlier OpenBag callback without polling.
function CommonMenus:OnBagGenerated(frame)
    ApplyBagForOwners(frame, true)
end

local function OnContainerGenerated(frame)
    CommonMenus:OnBagGenerated(frame)
end

local function RegisterCallbacks()
    local registered = false
    local callbackState = CommonMenus.callbackState
    if not callbackState.bags then
        EventRegistry:RegisterCallback(BAG_OPEN_CALLBACK, CommonMenus.OnBagOpened, CommonMenus)
        callbackState.bags = true
        registered = true
    end
    if not callbackState.generateHook
        and NS.DeepWindows.InstallContainerGenerateHook(OnContainerGenerated) then
        callbackState.generateHook = true
        registered = true
    end
    if not callbackState.qualityHook and NS.DeepWindows.InstallItemQualityHook() then
        callbackState.qualityHook = true
        registered = true
    end
    return registered
end

local function UnregisterCallbacks()
    if CommonMenus.callbackState.bags then
        EventRegistry:UnregisterCallback(BAG_OPEN_CALLBACK, CommonMenus)
    end
    -- Secure hooks cannot be removed. Keep the installation markers while the
    -- inert callbacks wait for a later owner enable.
    CommonMenus.callbackState = {
        generateHook = CommonMenus.callbackState.generateHook == true,
        qualityHook = CommonMenus.callbackState.qualityHook == true,
    }
end

local function ApplyNow(state)
    if NS.GenericWindows.IsCategoryEnabled("inventory") then RegisterCallbacks() end
    FadeCosmeticGlobals(state)
end

function CommonMenus.Apply(owner)
    local state = Owners.State(owner)
    if not state.active then
        state.active = true
        CommonMenus.activeOwnerCount = CommonMenus.activeOwnerCount + 1
    end

    if NS.IsCombatLocked() then
        Owners.RunOrDefer(state, "apply", ApplyNow)
        return false, "combat"
    end

    ApplyNow(state)
    return true
end

function CommonMenus.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local state = CommonMenus.owners[owner]
    if not state then
        return true
    end

    Owners.Release(state)
    CommonMenus.activeOwnerCount = math.max(0, CommonMenus.activeOwnerCount - 1)

    if CommonMenus.activeOwnerCount == 0 then
        UnregisterCallbacks()
    end

    -- The shared blizzardWindows owner is restored exactly once by
    -- GenericWindows.Disable in the parent adapter. Calling it here would
    -- also disable catalog roots before that adapter has finished its teardown.
    return true
end

return CommonMenus
