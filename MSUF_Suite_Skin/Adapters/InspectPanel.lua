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
-- Owner state, deferral and the shared primitives come from PaperDollChrome
-- (CharacterPanel.lua).
local Chrome = NS.PaperDollChrome
local Field = NS.Safety.Field
local Call = NS.Safety.Call
local Public = NS.Safety.Public
local Fade, Attach, Track = Chrome.Fade, Chrome.Attach, Chrome.Track

local DEFAULT_OWNER = "blizzardWindows"
local ROOT_SPEC = Chrome.Spec("shell", 8, 0)
local MODEL_SPEC = Chrome.Spec("card", 6, 0)

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

-- ControlSkin copies these specs. Tab selection may be unknown (nil).
local function ControlSpec(pillHeight, role, activeRole, active)
    return {
        role = role,
        activeRole = activeRole,
        active = active,
        useControlShape = true,
        pillHeight = pillHeight,
        radius = 5,
        inset = 1,
        allowImplicitProtected = true,
    }
end
local TAB_SPEC_ACTIVE = ControlSpec(24, "navigation", "navigationActive", true)
local TAB_SPEC_INACTIVE = ControlSpec(24, "navigation", "navigationActive", false)
local TAB_SPEC_UNKNOWN = ControlSpec(24, "navigation", "navigationActive", nil)
local ACTION_SPEC = ControlSpec(24, "button", "buttonPrimary", nil)

local function SkinModel(state)
    if not state.active or NS.IsCombatLocked() then return false end
    for index = 1, #modelArtNames do
        Fade(state, _G[modelArtNames[index]])
    end

    -- SetPaperDollBackground owns the race-specific alpha of this black
    -- brightness overlay. Release our previous snapshot first so a native
    -- update can become the new reversible baseline before it is hidden again.
    local overlay = _G.InspectModelFrameBackgroundOverlay
    if overlay and NS.Safety.CanDecorate(overlay, true) then
        NS.Cosmetics.RestoreOwner(state.modelOverlayOwner)
        NS.Cosmetics.Fade(overlay, state.modelOverlayOwner)
    end
    return Attach(state, _G.InspectModelFrame, MODEL_SPEC)
end

local function SelectedTab()
    if type(_G.PanelTemplates_GetSelectedTab) ~= "function" or not _G.InspectFrame then
        return nil
    end
    local selected = _G.PanelTemplates_GetSelectedTab(_G.InspectFrame)
    if not Public(selected) then return nil end
    return tonumber(selected)
end

local function SkinTabs(state)
    if not state.active or NS.IsCombatLocked() then return false end
    local selected = SelectedTab()
    local applied = false
    for index = 1, 3 do
        local tab = _G["InspectFrameTab" .. index]
        if tab and NS.Safety.CanControl(tab, true) then
            local spec = TAB_SPEC_UNKNOWN
            if selected ~= nil then
                spec = selected == index and TAB_SPEC_ACTIVE or TAB_SPEC_INACTIVE
            end
            if NS.ControlSkin.ApplyPanelTab(tab, state.owner, spec) then
                Track(state, tab)
                applied = true
            end
        end
    end
    return applied
end

local function SkinAction(state, button)
    if not button or NS.IsCombatLocked() or not NS.Safety.CanControl(button, true)
        or not NS.ControlSkin.ApplyButton(button, state.owner, ACTION_SPEC) then
        return false
    end
    Track(state, button)
    return true
end

local panel

local function ApplyNow(state)
    local root = _G.InspectFrame
    if not root or not state.active then return false, "missing" end
    if NS.IsCombatLocked() then return false, "combat" end

    Attach(state, root, ROOT_SPEC)
    Chrome.FadeNineSlice(state, root)
    Fade(state, Field(root, "Bg"))
    Chrome.FadePortraits(state, root, _G.InspectFramePortrait)

    Chrome.SkinInset(state, _G.InspectFrameInset or Field(root, "Inset"))
    SkinModel(state)
    panel:SkinAllSlots(state)
    SkinTabs(state)
    SkinAction(state, Field(_G.InspectPaperDollFrame, "ViewButton"))
    SkinAction(state, Field(_G.InspectPaperDollItemsFrame, "InspectTalents"))
    NS.CharacterDetails.Apply(root, "inspect", state.owner)
    panel.InstallHooks()
    return true, "applied"
end

panel = Chrome.New({
    prefix = "inspect-panel",
    addon = "Blizzard_InspectUI",
    rootName = "InspectFrame",
    slotNames = slotNames,
    applyNow = ApplyNow,
    applyOrWait = function(state)
        if _G.InspectFrame then ApplyNow(state) else panel:ScheduleLoad() end
    end,
    initState = function(state)
        state.modelOverlayOwner = tostring(state.owner) .. ":inspect-model-overlay"
    end,
    slotIcon = function(slot)
        local name = Call(slot, "GetName")
        return name and _G[name .. "IconTexture"]
    end,
})
panel.skinAllSlots = function(state) return panel:SkinAllSlots(state) end

local InspectPanel = {
    owners = panel.owners,
    exactSlots = panel.exactSlots,
    hooks = {},
}
NS.InspectPanel = InspectPanel

local function OnSlotUpdated(slot) panel:RefreshSlot(slot) end
local function OnTabsSwitched() panel:ForActiveOwners("tabs", SkinTabs) end

local function OnPaperDollBackground(model)
    if model == _G.InspectModelFrame then
        panel:ForActiveOwners("model", SkinModel)
    end
end

-- Blizzard calls these through their globals.
local globalHooks = {
    { "InspectPaperDollItemSlotButton_Update", OnSlotUpdated },
    { "InspectSwitchTabs", OnTabsSwitched },
    { "SetPaperDollBackground", OnPaperDollBackground },
}

function panel.InstallHooks()
    local hooks = InspectPanel.hooks
    for index = 1, #globalHooks do
        local name, callback = globalHooks[index][1], globalHooks[index][2]
        if not hooks[name] and type(_G[name]) == "function" then
            hooksecurefunc(name, callback)
            hooks[name] = true
        end
    end
end

function InspectPanel.Apply(owner)
    return panel:Activate(owner or DEFAULT_OWNER)
end

function InspectPanel.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local state = panel.owners[owner]
    if not state then return true end
    if NS.IsCombatLocked() then return false, "combat" end

    state.active = false
    NS.CharacterDetails.Disable(_G.InspectFrame, owner)
    panel:Release(state)
    NS.Cosmetics.RestoreOwner(state.modelOverlayOwner)
    -- The parent blizzardWindows adapter restores shared IconSkin,
    -- ControlSkin and Cosmetics ownership once through GenericWindows.
    return true
end

return InspectPanel
