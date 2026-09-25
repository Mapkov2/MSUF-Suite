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
    owners = {},
    activeOwnerCount = 0,
    callbackState = {},
}
NS.CommonMenus = CommonMenus

local Field = NS.Safety.Field
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

local function OwnerState(owner)
    owner = owner or DEFAULT_OWNER
    local state = CommonMenus.owners[owner]
    if not state then
        state = {
            owner = owner,
            active = false,
            frames = Kit.WeakSet(),
            surfaces = Kit.WeakSet(),
            deferred = {},
        }
        CommonMenus.owners[owner] = state
    end
    return state
end

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

-- ContainerFrame item buttons come from its itemButtonPool; older layouts
-- keep them in the Items array instead.
local function SkinBagItems(state, frame)
    local pool = Field(frame, "itemButtonPool")
    local count = 0
    if type((Field(pool, "EnumerateActive"))) == "function" then
        local visited = 0
        for button in pool:EnumerateActive() do
            if visited >= BAG_ITEM_LIMIT then break end
            visited = visited + 1
            if SkinBagItem(state, frame, button) then count = count + 1 end
        end
        return count
    end
    local items = Field(frame, "Items")
    if type(items) == "table" then
        for index = 1, math.min(#items, BAG_ITEM_LIMIT) do
            if SkinBagItem(state, frame, items[index]) then count = count + 1 end
        end
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

local function ApplyBagFrame(state, frame)
    local owner = state.owner
    if not NS.GenericWindows.ApplyFrame(frame, owner, BAG_MODE) then return false end
    state.frames[frame] = true
    SkinBagItems(state, frame)
    SkinMoneyFrame(state, frame)
    -- ContainerFrameMixin:UpdateSearchBox reparents these shared controls after
    -- the initial traversal. Revisit only their exact current bag owner.
    local search, sort = _G.BagItemSearchBox, _G.BagItemAutoSortButton
    if search and Kit.ParentIs(search, frame) then
        NS.ControlSkin.ApplySearchBox(search, owner, BAG_SEARCH_SPEC)
    end
    if sort and Kit.ParentIs(sort, frame) and NS.Surface.Attach(sort, BAG_ACTION_SPEC) then
        -- Keep the native sort icon, scripts and highlight; just add its plate.
        state.surfaces[sort] = true
    end
    local close = Field(frame, "CloseButton")
    if close then NS.WindowActionSkin.Apply(close, owner, "close") end
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

function CommonMenus:OnBagOpened(frame)
    -- Bag windows are usable in combat. Cosmetic traversal is optional, so do
    -- absolutely no queueing or mutation there; the next out-of-combat open
    -- refreshes the rebuilt item pool. ContainerFrame builds its item pool
    -- before firing OpenBag, so this one dynamic root is rescanned without
    -- touching every catalog window.
    if not frame or NS.IsCombatLocked() or not NS.GenericWindows.IsCategoryEnabled("inventory") then
        return
    end
    for _, state in pairs(self.owners) do
        if state.active then ApplyBagFrame(state, frame) end
    end
end

-- ContainerFrame_GenerateFrame finishes after search/sort controls, money,
-- optional add-slot controls and the final item update have all run. This
-- exact post-hook complements the earlier OpenBag callback without polling.
function CommonMenus:OnBagGenerated(frame)
    self:OnBagOpened(frame)
end

local function OnContainerGenerated(frame)
    CommonMenus:OnBagGenerated(frame)
end

local function RegisterCallbacks()
    local registered = false
    if not CommonMenus.callbackState.bags
        and Kit.RegisterEventCallback(BAG_OPEN_CALLBACK, CommonMenus.OnBagOpened, CommonMenus) then
        CommonMenus.callbackState.bags = true
        registered = true
    end
    if not CommonMenus.callbackState.generateHook
        and NS.DeepWindows.InstallContainerGenerateHook(OnContainerGenerated) then
        CommonMenus.callbackState.generateHook = true
        registered = true
    end
    return registered
end

local function UnregisterCallbacks()
    if CommonMenus.callbackState.bags then
        Kit.UnregisterEventCallback(BAG_OPEN_CALLBACK, CommonMenus)
    end
    -- Secure hooks cannot be removed. Keep the installation marker while the
    -- inert callback waits for a later owner enable.
    local generateHook = CommonMenus.callbackState.generateHook == true
    CommonMenus.callbackState = { generateHook = generateHook }
end

local function ApplyNow(state)
    if NS.GenericWindows.IsCategoryEnabled("inventory") then RegisterCallbacks() end
    FadeCosmeticGlobals(state)
end

function CommonMenus.Apply(owner)
    local state = OwnerState(owner)
    owner = state.owner
    if not state.active then
        state.active = true
        CommonMenus.activeOwnerCount = CommonMenus.activeOwnerCount + 1
    end

    if NS.IsCombatLocked() then
        local key = "commonMenus:" .. tostring(owner) .. ":apply"
        state.deferred[key] = true
        NS.CombatGate.RunOrDefer(key, function()
            local current = CommonMenus.owners[owner]
            if current then current.deferred[key] = nil end
            if current and current.active then ApplyNow(current) end
        end)
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

    state.active = false
    Kit.CancelDeferred(state)
    Kit.HideSurfaces(state)
    state.surfaces = Kit.WeakSet()
    CommonMenus.owners[owner] = nil
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
