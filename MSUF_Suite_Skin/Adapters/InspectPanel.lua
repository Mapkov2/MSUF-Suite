local _, NS = ...

-- Native-preserving Inspect coverage verified against Gethe/wow-ui-source
-- upstream/live at 027d26c3406d3de2cbd2b1f67d468fe033a1bcd4:
--
--   Blizzard_InspectUI/Mainline/Blizzard_InspectUI.xml
--   Blizzard_InspectUI/Mainline/Blizzard_InspectUI.lua
--   Blizzard_InspectUI/Mainline/InspectPaperDollFrame.xml
--   Blizzard_InspectUI/Mainline/InspectPaperDollFrame.lua
--
-- Blizzard keeps ownership of inspected-unit data, the model/faction fallback,
-- item icons, quality state, sockets, tabs, scripts and geometry. This adapter
-- only replaces explicitly named decorative chrome with reversible surfaces.
local InspectPanel = {
    owners = {},
    waiting = false,
    hookedSlots = false,
    hookedTabs = false,
    hookedModelBackground = false,
    exactSlots = setmetatable({}, { __mode = "k" }),
}
NS.InspectPanel = InspectPanel

local DEFAULT_OWNER = "blizzardWindows"
local INSPECT_ADDON = "Blizzard_InspectUI"

local modelArtNames = {
    "InspectModelFrameBackgroundTopLeft",
    "InspectModelFrameBackgroundTopRight",
    "InspectModelFrameBackgroundBotLeft",
    "InspectModelFrameBackgroundBotRight",
    "InspectModelFrameBorderTopLeft",
    "InspectModelFrameBorderTopRight",
    "InspectModelFrameBorderBottomLeft",
    "InspectModelFrameBorderBottomRight",
    "InspectModelFrameBorderLeft",
    "InspectModelFrameBorderRight",
    "InspectModelFrameBorderTop",
    "InspectModelFrameBorderBottom",
    "InspectModelFrameBorderBottom2",
}

local slotNames = {
    "InspectHeadSlot",
    "InspectNeckSlot",
    "InspectShoulderSlot",
    "InspectBackSlot",
    "InspectChestSlot",
    "InspectShirtSlot",
    "InspectTabardSlot",
    "InspectWristSlot",
    "InspectHandsSlot",
    "InspectWaistSlot",
    "InspectLegsSlot",
    "InspectFeetSlot",
    "InspectFinger0Slot",
    "InspectFinger1Slot",
    "InspectTrinket0Slot",
    "InspectTrinket1Slot",
    "InspectMainHandSlot",
    "InspectSecondaryHandSlot",
}

local function WeakSet()
    return setmetatable({}, { __mode = "k" })
end

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function AccessibleNumber(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then
        if type(canaccessvalue) ~= "function" or not canaccessvalue(value) then
            return nil
        end
    end
    return tonumber(value)
end

local function OwnerState(owner)
    owner = owner or DEFAULT_OWNER
    local state = InspectPanel.owners[owner]
    if not state then
        state = {
            owner = owner,
            modelOverlayOwner = tostring(owner) .. ":inspect-model-overlay",
            active = false,
            surfaces = WeakSet(),
            deferred = {},
        }
        InspectPanel.owners[owner] = state
    end
    return state, owner
end

local function Report(label, message)
    if type(NS.ReportError) == "function" then
        NS.ReportError("inspect panel " .. tostring(label), message)
    end
end

local function CategoryEnabled()
    return not NS.GenericWindows
        or type(NS.GenericWindows.IsCategoryEnabled) ~= "function"
        or NS.GenericWindows.IsCategoryEnabled("character")
end

local function IsAddonLoaded()
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loadedOrLoading, loaded = pcall(C_AddOns.IsAddOnLoaded, INSPECT_ADDON)
        return ok and (loaded == true or (loaded == nil and loadedOrLoading == true))
    end
    if type(IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(IsAddOnLoaded, INSPECT_ADDON)
        return ok and loaded == true
    end
    return _G.InspectFrame ~= nil
end

local function TrackSurface(state, target)
    if state and target then state.surfaces[target] = true end
end

local function Fade(state, region)
    if not state or not region or NS.IsCombatLocked() or not NS.Cosmetics
        or type(NS.Cosmetics.Fade) ~= "function" or not NS.Safety
        or not NS.Safety.CanDecorate(region, true) then
        return false
    end
    local ok, result = pcall(NS.Cosmetics.Fade, region, state.owner)
    if not ok then Report("fade", result) end
    return ok and result == true
end

local function FadeNineSlice(state, target)
    local nineSlice = SafeField(target, "NineSlice")
    if not nineSlice or NS.IsCombatLocked() or not NS.Cosmetics
        or type(NS.Cosmetics.FadeNineSlice) ~= "function" or not NS.Safety
        or not NS.Safety.CanDecorate(nineSlice, true) then
        return false
    end
    local ok, message = pcall(NS.Cosmetics.FadeNineSlice, nineSlice, state.owner)
    if not ok then Report("nine slice", message) end
    return ok == true
end

local function Attach(state, target, role, radius, inset, listItem)
    if not state or not target or NS.IsCombatLocked() or not NS.Surface
        or type(NS.Surface.Attach) ~= "function" or not NS.Safety
        or not NS.Safety.CanCreateRegions(target, true) then
        return false
    end
    local ok, surface = pcall(NS.Surface.Attach, target, {
        role = role or "card",
        radius = radius or 4,
        inset = inset or 0,
        listItem = listItem == true,
        allowImplicitProtected = true,
    })
    if ok and surface then
        TrackSurface(state, target)
        return true
    end
    if not ok then Report("surface", surface) end
    return false
end

local function SkinInset(state)
    local inset = _G.InspectFrameInset or SafeField(_G.InspectFrame, "Inset")
    if not inset then return false end
    FadeNineSlice(state, inset)
    Fade(state, SafeField(inset, "Bg"))
    Fade(state, SafeField(inset, "Background"))
    return Attach(state, inset, "panel", 5, 0)
end

local function SkinModel(state)
    if not state or not state.active or NS.IsCombatLocked() then return false end
    for index = 1, #modelArtNames do
        Fade(state, _G[modelArtNames[index]])
    end

    -- SetPaperDollBackground owns the race-specific alpha of this black
    -- brightness overlay. Release our previous snapshot first so a native
    -- update can become the new reversible baseline before it is hidden again.
    local overlay = _G.InspectModelFrameBackgroundOverlay
    if overlay and NS.Cosmetics and type(NS.Cosmetics.RestoreOwner) == "function"
        and type(NS.Cosmetics.Fade) == "function" and NS.Safety
        and NS.Safety.CanDecorate(overlay, true) then
        local ok, message = pcall(NS.Cosmetics.RestoreOwner, state.modelOverlayOwner)
        if not ok then Report("model overlay restore", message) end
        ok, message = pcall(NS.Cosmetics.Fade, overlay, state.modelOverlayOwner)
        if not ok then Report("model overlay fade", message) end
    end
    return Attach(state, _G.InspectModelFrame, "card", 6, 0)
end

local function SkinSlot(state, slot)
    if not state or not state.active or not slot or not InspectPanel.exactSlots[slot]
        or NS.IsCombatLocked() then
        return false
    end

    Attach(state, slot, "button", 4, 0, true)
    if NS.IconSkin and type(NS.IconSkin.Apply) == "function" then
        local name = type(slot.GetName) == "function" and slot:GetName() or nil
        local icon = SafeField(slot, "Icon") or SafeField(slot, "icon")
            or (name and _G[name .. "IconTexture"])
        local border = SafeField(slot, "IconBorder") or SafeField(slot, "iconBorder")
        if icon and border then
            local ok, iconState = pcall(NS.IconSkin.Apply, slot, state.owner, {
                icon = icon,
                nativeBorder = border,
                allowImplicitProtected = true,
            })
            if not ok then Report("slot icon", iconState) end
        end
    end
    return true
end

local function SkinAllSlots(state)
    if not state or not state.active or NS.IsCombatLocked() then return false end
    local applied = false
    for index = 1, #slotNames do
        local name = slotNames[index]
        local slot = _G[name]
        if slot then
            InspectPanel.exactSlots[slot] = true
            Fade(state, _G[name .. "Frame"])
            applied = SkinSlot(state, slot) or applied
        end
    end
    return applied
end

local function SelectedTab()
    if type(_G.PanelTemplates_GetSelectedTab) ~= "function" or not _G.InspectFrame then
        return nil
    end
    local ok, selected = pcall(_G.PanelTemplates_GetSelectedTab, _G.InspectFrame)
    return ok and AccessibleNumber(selected) or nil
end

local function SkinTabs(state)
    if not state or not state.active or NS.IsCombatLocked() then return false end
    local selected = SelectedTab()
    local applied = false
    for index = 1, 3 do
        local tab = _G["InspectFrameTab" .. tostring(index)]
        if tab and NS.ControlSkin and type(NS.ControlSkin.ApplyPanelTab) == "function"
            and NS.Safety and NS.Safety.CanControl(tab, true) then
            local active
            if selected ~= nil then
                active = selected == index
            end
            local ok, controlState = pcall(NS.ControlSkin.ApplyPanelTab, tab, state.owner, {
                role = "navigation",
                activeRole = "navigationActive",
                active = active,
                useControlShape = true,
                pillHeight = 24,
                radius = 5,
                inset = 1,
                allowImplicitProtected = true,
            })
            if ok and controlState then
                TrackSurface(state, tab)
                applied = true
            elseif not ok then
                Report("tab", controlState)
            end
        end
    end
    return applied
end

local function SkinAction(state, button)
    if not state or not button or NS.IsCombatLocked() or not NS.ControlSkin
        or type(NS.ControlSkin.ApplyButton) ~= "function" or not NS.Safety
        or not NS.Safety.CanControl(button, true) then
        return false
    end
    local ok, controlState = pcall(NS.ControlSkin.ApplyButton, button, state.owner, {
        role = "button",
        activeRole = "buttonPrimary",
        useControlShape = true,
        pillHeight = 24,
        radius = 5,
        inset = 1,
        allowImplicitProtected = true,
    })
    if ok and controlState then
        TrackSurface(state, button)
        return true
    end
    if not ok then Report("action", controlState) end
    return false
end

local function SkinActions(state)
    local paperDoll = _G.InspectPaperDollFrame
    local items = _G.InspectPaperDollItemsFrame
    SkinAction(state, SafeField(paperDoll, "ViewButton"))
    SkinAction(state, SafeField(items, "InspectTalents"))
end

local function DeferredKey(state, suffix)
    return "inspect-panel:" .. tostring(suffix) .. ":" .. tostring(state.owner)
end

local function RunOrDefer(state, suffix, callback)
    if not state or not state.active or type(callback) ~= "function" then return false end
    local key = DeferredKey(state, suffix)
    state.deferred[key] = true
    local ran, reason = NS.CombatGate.RunOrDefer(key, function()
        local current = InspectPanel.owners[state.owner]
        if current then current.deferred[key] = nil end
        if current and current.active then callback(current) end
    end)
    if ran then state.deferred[key] = nil end
    return ran == true, reason
end

local function RefreshSlotForOwners(slot)
    if not InspectPanel.exactSlots[slot] then return end
    for _, state in pairs(InspectPanel.owners) do
        if state.active then
            if NS.IsCombatLocked() then
                RunOrDefer(state, "slots", SkinAllSlots)
            else
                SkinSlot(state, slot)
            end
        end
    end
end

local function RefreshTabsForOwners()
    for _, state in pairs(InspectPanel.owners) do
        if state.active then RunOrDefer(state, "tabs", SkinTabs) end
    end
end

local function RefreshModelForOwners(model)
    if model ~= _G.InspectModelFrame then return end
    for _, state in pairs(InspectPanel.owners) do
        if state.active then RunOrDefer(state, "model", SkinModel) end
    end
end

local function InstallHooks()
    if type(hooksecurefunc) ~= "function" then return false end

    if not InspectPanel.hookedSlots
        and type(_G.InspectPaperDollItemSlotButton_Update) == "function" then
        local ok = pcall(function()
            hooksecurefunc("InspectPaperDollItemSlotButton_Update", RefreshSlotForOwners)
        end)
        InspectPanel.hookedSlots = ok == true
    end

    if not InspectPanel.hookedTabs and type(_G.InspectSwitchTabs) == "function" then
        local ok = pcall(function()
            hooksecurefunc("InspectSwitchTabs", RefreshTabsForOwners)
        end)
        InspectPanel.hookedTabs = ok == true
    end

    if not InspectPanel.hookedModelBackground and type(_G.SetPaperDollBackground) == "function" then
        local ok = pcall(function()
            hooksecurefunc("SetPaperDollBackground", RefreshModelForOwners)
        end)
        InspectPanel.hookedModelBackground = ok == true
    end

    return InspectPanel.hookedSlots and InspectPanel.hookedTabs
        and InspectPanel.hookedModelBackground
end

local function ApplyNow(state)
    local root = _G.InspectFrame
    if not root or not state or not state.active then return false, "missing" end
    if NS.IsCombatLocked() then return false, "combat" end

    Attach(state, root, "shell", 8, 0)
    FadeNineSlice(state, root)
    Fade(state, SafeField(root, "Bg"))
    Fade(state, SafeField(root, "Portrait"))
    Fade(state, SafeField(root, "portrait"))
    Fade(state, _G.InspectFramePortrait)
    local portraitContainer = SafeField(root, "PortraitContainer")
    Fade(state, SafeField(portraitContainer, "Portrait"))
    Fade(state, SafeField(portraitContainer, "portrait"))

    SkinInset(state)
    SkinModel(state)
    SkinAllSlots(state)
    SkinTabs(state)
    SkinActions(state)
    NS.CharacterDetails.Apply(root,"inspect",state.owner)
    InstallHooks()
    return true, "applied"
end

local function ApplyForActiveOwners()
    if NS.IsCombatLocked() then
        for _, state in pairs(InspectPanel.owners) do
            if state.active then RunOrDefer(state, "apply", ApplyNow) end
        end
        return
    end
    for _, state in pairs(InspectPanel.owners) do
        if state.active then
            local ok, message = pcall(ApplyNow, state)
            if not ok then Report("load", message) end
        end
    end
end

local function ScheduleLoad()
    if InspectPanel.waiting then return true end
    if IsAddonLoaded() or not EventUtil
        or type(EventUtil.ContinueOnAddOnLoaded) ~= "function" then
        return false
    end
    InspectPanel.waiting = true
    local ok, message = pcall(EventUtil.ContinueOnAddOnLoaded, INSPECT_ADDON, function()
        InspectPanel.waiting = false
        ApplyForActiveOwners()
    end)
    if not ok then
        InspectPanel.waiting = false
        Report("addon load", message)
        return false
    end
    return true
end

function InspectPanel.Apply(owner)
    if not CategoryEnabled() then return true, "disabled" end
    local state
    state, owner = OwnerState(owner)
    state.active = true

    if NS.IsCombatLocked() then
        RunOrDefer(state, "apply", function(current)
            if _G.InspectFrame then ApplyNow(current) else ScheduleLoad() end
        end)
        return false, "combat"
    end
    if not _G.InspectFrame then
        if ScheduleLoad() then return true, "waiting" end
        return false, "missing"
    end
    return ApplyNow(state)
end

function InspectPanel.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local state = InspectPanel.owners[owner]
    if not state then return true end
    if NS.IsCombatLocked() then return false, "combat" end

    state.active = false
    NS.CharacterDetails.Disable(_G.InspectFrame,owner)
    for key in pairs(state.deferred) do
        NS.CombatGate.Cancel(key)
        state.deferred[key] = nil
    end
    for target in pairs(state.surfaces) do
        pcall(NS.Surface.SetVisible, target, false)
    end
    if NS.Cosmetics and type(NS.Cosmetics.RestoreOwner) == "function" then
        local ok, message = pcall(NS.Cosmetics.RestoreOwner, state.modelOverlayOwner)
        if not ok then Report("model overlay disable", message) end
    end
    InspectPanel.owners[owner] = nil

    -- The parent blizzardWindows adapter restores shared IconSkin,
    -- ControlSkin and Cosmetics ownership once through GenericWindows.
    return true
end

return InspectPanel
