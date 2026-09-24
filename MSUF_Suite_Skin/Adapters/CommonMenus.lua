local _, NS = ...

-- Small runtime companion for catalog windows whose roots or cosmetic regions
-- are created after the main adapter pass.  Names and callbacks were verified
-- against Gethe/wow-ui-source upstream/live at
-- 8ea15b61e45c0ed4eba01439c90757f86eb78d34.
--
-- This module deliberately does not load Blizzard addons.  Catalog.lua owns
-- LoD discovery; the callbacks below only refresh objects created by normal
-- Blizzard UI activity.  No Blizzard scripts, mixins, methods, or frame fields
-- are replaced.

local CommonMenus = {
    owners = {},
    activeOwnerCount = 0,
    callbackState = {},
}
NS.CommonMenus = CommonMenus

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

-- These named regions are textures rather than frames, so the bounded child
-- traversal cannot discover them reliably.  Cosmetics.Fade records their
-- original alpha under the shared owner and GenericWindows.Disable restores it.
local cosmeticGlobals = {
    { category = "npc", names = { "BuybackBG", "MerchantFrameBottomLeftBorder" } },
    { category = "social", names = {
        "InboxFrameBg", "SendStationeryBackgroundLeft", "SendStationeryBackgroundRight",
        "OpenStationeryBackgroundLeft", "OpenStationeryBackgroundRight",
    } },
}

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function Report(label, message)
    if type(NS.ReportError) == "function" then
        NS.ReportError("common menus " .. label, message)
    end
end

local function OwnerKey(owner)
    return tostring(owner or DEFAULT_OWNER)
end

local function GetOwnerState(owner)
    owner = owner or DEFAULT_OWNER
    local state = CommonMenus.owners[owner]
    if not state then
        state = {
            active = false,
            frames = setmetatable({}, { __mode = "k" }),
            surfaces = setmetatable({}, { __mode = "k" }),
            deferred = {},
        }
        CommonMenus.owners[owner] = state
    end
    return state, owner
end

local function ApplyFrame(frame, owner, role)
    if not frame or not NS.GenericWindows
        or type(NS.GenericWindows.ApplyFrame) ~= "function" then
        return false, "missing"
    end

    local ok, applied, reason = pcall(NS.GenericWindows.ApplyFrame, frame, owner, {
        role = role or "shell",
        allowImplicitProtected = true,
    })
    if not ok then
        Report("frame " .. tostring(frame), applied)
        return false, "failed"
    end
    return applied == true, reason
end

local function ParentIs(frame, expectedParent)
    local getter = SafeField(frame, "GetParent")
    if type(getter) ~= "function" then return false end
    local ok, parent = pcall(getter, frame)
    return ok and parent == expectedParent
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

local function SkinBagItem(frame, button, owner)
    if not button or not ParentIs(button, frame)
        or type(SafeField(button, "GetBagID")) ~= "function"
        or type(SafeField(button, "GetID")) ~= "function" then
        return false
    end

    local icon = SafeField(button, "icon")
    local qualityBorder = SafeField(button, "IconBorder")
    if not icon or not qualityBorder or not NS.ControlSkin or not NS.IconSkin then
        return false
    end

    local okControl, control = pcall(NS.ControlSkin.ApplyButton,
        button, owner, BAG_ITEM_SPEC)
    local okIcon, iconState = pcall(NS.IconSkin.Apply, button, owner, {
        icon = icon,
        nativeBorder = qualityBorder,
        allowImplicitProtected = true,
    })
    if not okControl then Report("bag item control", control) end
    if not okIcon then Report("bag item icon", iconState) end
    return okControl and control ~= nil and okIcon and iconState ~= nil
end

local function SkinBagItems(frame, owner)
    local count = 0
    local visited = setmetatable({}, { __mode = "k" })
    local function Skin(button)
        if not visited[button] then
            visited[button] = true
            if SkinBagItem(frame, button, owner) then count = count + 1 end
        end
    end

    local enumerated = EnumerateActive(SafeField(frame, "itemButtonPool"),
        BAG_ITEM_LIMIT, Skin)
    if not enumerated then
        local items = SafeField(frame, "Items")
        if type(items) == "table" then
            for index = 1, math.min(#items, BAG_ITEM_LIMIT) do Skin(items[index]) end
        end
    end
    return count
end

local function SkinMoneyFrame(frame, owner, state)
    local money = SafeField(frame, "MoneyFrame")
    local border = SafeField(money, "Border")
    if not money or not border or not NS.Surface then return false end

    local ok, surface = pcall(NS.Surface.Attach, money, BAG_MONEY_SPEC)
    if not ok or not surface then
        if not ok then Report("bag money", surface) end
        return false
    end
    state.surfaces[money] = true
    if NS.Cosmetics and type(NS.Cosmetics.Fade) == "function" then
        for _, key in ipairs({ "Left", "Middle", "Right" }) do
            local region = SafeField(border, key)
            if region then pcall(NS.Cosmetics.Fade, region, owner) end
        end
    end
    return true
end

local function ApplyBagFrame(frame, owner, state)
    local success, reason = ApplyFrame(frame, owner, BAG_MODE.role)
    if not success then return false, reason end
    state.frames[frame] = true
    SkinBagItems(frame, owner)
    SkinMoneyFrame(frame, owner, state)
    -- ContainerFrameMixin:UpdateSearchBox reparents these shared controls after
    -- the initial traversal. Revisit only their exact current bag owner.
    local search, sort, close = _G.BagItemSearchBox, _G.BagItemAutoSortButton, SafeField(frame, "CloseButton")
    if search and ParentIs(search, frame) then
        NS.ControlSkin.ApplySearchBox(search, owner, BAG_SEARCH_SPEC)
    end
    if sort and ParentIs(sort, frame) then
        -- Keep the native sort icon, scripts and highlight; just add its plate.
        if NS.Surface.Attach(sort, BAG_ACTION_SPEC) then state.surfaces[sort] = true end
    end
    if close then NS.WindowActionSkin.Apply(close, owner, "close") end
    return true
end

local function FadeCosmeticGlobals(owner)
    if not NS.Cosmetics or type(NS.Cosmetics.Fade) ~= "function" then
        return 0
    end

    local faded = 0
    for index = 1, #cosmeticGlobals do
        local group = cosmeticGlobals[index]
        if NS.GenericWindows.IsCategoryEnabled(group.category) then
            for nameIndex = 1, #group.names do
                local name = group.names[nameIndex]
                local region = _G[name]
                if region then
                    local ok, result = pcall(NS.Cosmetics.Fade, region, owner)
                    if ok and result then
                        faded = faded + 1
                    elseif not ok then
                        Report("cosmetic " .. name, result)
                    end
                end
            end
        end
    end
    return faded
end

local function DeferredKey(owner, suffix)
    return "commonMenus:" .. OwnerKey(owner) .. ":" .. suffix
end

local function RunOrDefer(owner, suffix, callback)
    local state = CommonMenus.owners[owner]
    if not state or not state.active then
        return false, "disabled"
    end
    if not NS.IsCombatLocked() then
        callback(state)
        return true
    end

    local key = DeferredKey(owner, suffix)
    state.deferred[key] = true
    NS.CombatGate.RunOrDefer(key, function()
        local current = CommonMenus.owners[owner]
        if current then
            current.deferred[key] = nil
        end
        if current and current.active then
            callback(current)
        end
    end)
    return false, "combat"
end

local function RefreshOwner(owner, dynamicFrame)
    return RunOrDefer(owner, dynamicFrame and ("bag:" .. tostring(dynamicFrame)) or "refresh", function(state)
        -- ContainerFrame builds its item pool before firing OpenBag, so this
        -- one dynamic root can be rescanned without touching every catalog
        -- window. Static roots and their LoD lifecycle remain catalog-owned.
        if dynamicFrame then
            ApplyBagFrame(dynamicFrame, owner, state)
        else
            FadeCosmeticGlobals(owner)
        end
    end)
end


function CommonMenus:OnBagGenerated(frame)
    -- ContainerFrame_GenerateFrame finishes after search/sort controls, money,
    -- optional add-slot controls and the final item update have all run. This
    -- exact post-hook complements the earlier OpenBag callback without polling.
    self:OnBagOpened(frame)
end

local function InstallBagHooks()
    if CommonMenus.callbackState.generateHook then return false end
    local deep = NS.DeepWindows
    if not deep or type(deep.InstallContainerGenerateHook) ~= "function" then
        return false
    end
    local ok, installed = pcall(deep.InstallContainerGenerateHook, function(frame)
        CommonMenus:OnBagGenerated(frame)
    end)
    if not ok or installed ~= true then
        if not ok then Report("hook ContainerFrame_GenerateFrame", installed) end
        return false
    end
    CommonMenus.callbackState.generateHook = true
    return true
end

function CommonMenus:OnBagOpened(frame)
    -- Bag windows are usable in combat. Cosmetic traversal is optional, so do
    -- absolutely no queueing or mutation there; the next out-of-combat open
    -- refreshes the rebuilt item pool.
    if not frame or NS.IsCombatLocked() or not NS.GenericWindows.IsCategoryEnabled("inventory") then
        return
    end
    for owner, state in pairs(self.owners) do
        if state.active then
            RefreshOwner(owner, frame)
        end
    end
end

local function RegisterCallbacks()
    local registry = EventRegistry
    if not registry then
        return false
    end

    local registered = false
    if not CommonMenus.callbackState.bags
        and type(registry.RegisterCallback) == "function" then
        local ok, message = pcall(registry.RegisterCallback, registry,
            BAG_OPEN_CALLBACK, CommonMenus.OnBagOpened, CommonMenus)
        if ok then
            CommonMenus.callbackState.bags = true
            registered = true
        else
            Report("register " .. BAG_OPEN_CALLBACK, message)
        end
    end

    if InstallBagHooks() then registered = true end

    return registered
end

local function UnregisterCallbacks()
    local registry = EventRegistry
    if registry then
        if CommonMenus.callbackState.bags
            and type(registry.UnregisterCallback) == "function" then
            pcall(registry.UnregisterCallback, registry, BAG_OPEN_CALLBACK, CommonMenus)
        end
    end
    -- Secure hooks cannot be removed. Keep the installation marker while the
    -- inert callback waits for a later owner enable.
    local generateHook = CommonMenus.callbackState.generateHook == true
    CommonMenus.callbackState = { generateHook = generateHook }
end

function CommonMenus.Apply(owner)
    local state
    state, owner = GetOwnerState(owner)
    if not state.active then
        state.active = true
        CommonMenus.activeOwnerCount = CommonMenus.activeOwnerCount + 1
    end

    if NS.IsCombatLocked() then
        local key = DeferredKey(owner, "apply")
        state.deferred[key] = true
        NS.CombatGate.RunOrDefer(key, function()
            local current = CommonMenus.owners[owner]
            if current then
                current.deferred[key] = nil
            end
            if current and current.active then
                if NS.GenericWindows.IsCategoryEnabled("inventory") then RegisterCallbacks() end
                FadeCosmeticGlobals(owner)
            end
        end)
        return false, "combat"
    end

    if NS.GenericWindows.IsCategoryEnabled("inventory") then RegisterCallbacks() end
    FadeCosmeticGlobals(owner)
    return true
end

function CommonMenus.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local state = CommonMenus.owners[owner]
    if not state then
        return true
    end

    state.active = false
    for key in pairs(state.deferred) do
        NS.CombatGate.Cancel(key)
    end
    state.deferred = {}
    for surface in pairs(state.surfaces) do
        pcall(NS.Surface.SetVisible, surface, false)
    end
    state.surfaces = setmetatable({}, { __mode = "k" })
    CommonMenus.owners[owner] = nil
    CommonMenus.activeOwnerCount = math.max(0, CommonMenus.activeOwnerCount - 1)

    if CommonMenus.activeOwnerCount == 0 then
        UnregisterCallbacks()
    end

    -- The shared blizzardWindows owner is restored exactly once by
    -- GenericWindows.Disable in the parent adapter.  Calling it here would
    -- also disable catalog roots before that adapter has finished its teardown.
    return true
end

return CommonMenus
