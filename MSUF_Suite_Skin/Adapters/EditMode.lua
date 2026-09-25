local _, NS = ...

-- Clean-room Blizzard Edit Mode skin based on wow-ui-source upstream/live
-- 710f59e. The manager, dialogs and setting controls remain entirely owned by
-- Blizzard. MapkoSkin only adds cosmetic textures and suppresses verified
-- decorative regions outside combat.
local EditModeSkin = {
    owners = {},
    checkControllers = setmetatable({}, { __mode = "k" }),
    sliderContainers = setmetatable({}, { __mode = "k" }),
}
NS.EditModeSkin = EditModeSkin

local Field = NS.Safety.Field
local Call = NS.Safety.Call

-- Exactly one boolean, also for a missing target (Field returns no value then).
local function HasMethod(target, name)
    return type(target) == "table" and type(target[name]) == "function"
end

local dialogRoots = {
    "EditModeLayoutDialog",
    "EditModeImportLayoutDialog",
    "EditModeImportLayoutLinkDialog",
    "EditModeUnsavedChangesDialog",
    "EditModeSystemSettingsDialog",
}

local settingTemplates = {
    "EditModeSettingDropdownTemplate",
    "EditModeSettingSliderTemplate",
    "EditModeSettingCheckboxTemplate",
}
local EXTRA_BUTTON_TEMPLATE = "EditModeSystemSettingsDialogExtraButtonTemplate"
local managerCheckButtons = {
    "ShowGridCheckButton",
    "EnableSnapCheckButton",
    "EnableAdvancedOptionsCheckButton",
}

-- EditModeManagerFrame's AccountSettings tree is static and known; seven
-- levels cover it without walking UIParent-sized grid/preview containers.
-- Dynamic dialog controls are handled by their pools.
local MANAGER_MODE = {
    role = "shell", radius = 8, inset = 0, maxDepth = 7, maxNodes = 420,
    registerDynamicRows = false, allowImplicitProtected = true,
}
local DIALOG_MODE = {
    role = "popup", radius = 8, inset = 0, maxDepth = 6, maxNodes = 220,
    registerDynamicRows = false, allowImplicitProtected = true,
}
local SLIDER_SPEC = {
    role = "input", shape = "continuous", radius = 4, inset = 2, allowImplicitProtected = true,
}
local SETTING_SPEC = {
    role = "panel", radius = 4, inset = 0, listItem = true, allowImplicitProtected = true,
}
local ACCOUNT_SPEC = { role = "panel", radius = 6, inset = 0, allowImplicitProtected = true }
local DROPDOWN_SPEC = {
    role = "input", activeRole = "navigationActive", useControlShape = true,
    pillHeight = 28, inset = 0, regions = { "Background" }, allowImplicitProtected = true,
}
local CHECK_SPEC = {
    role = "input", activeRole = "navigationActive", shape = "continuous",
    radius = 4, inset = 3, allowImplicitProtected = true,
}

-- ControlSkin copies each spec, so one table per role/height pair is shared.
local buttonSpecs = {}
local function ButtonSpec(role, height)
    local byHeight = buttonSpecs[role]
    if not byHeight then
        byHeight = {}
        buttonSpecs[role] = byHeight
    end
    local spec = byHeight[height]
    if not spec then
        spec = {
            role = role, activeRole = "buttonPrimary", useControlShape = true,
            pillHeight = height, inset = 1, allowImplicitProtected = true,
        }
        byHeight[height] = spec
    end
    return spec
end

-- Blizzard copies mixin methods onto each frame when it is created
-- (EditModeManager.xml, EditModeTemplates.xml, MinimalSlider.xml), so a hook
-- on the mixin table never reaches frames that already existed when this
-- load-on-demand addon loaded. Hook the exact instances this skin tracks.
local instanceHooks = {}
local function HookInstance(frame, method, callback)
    local hooked = instanceHooks[method]
    if not hooked then
        hooked = setmetatable({}, { __mode = "k" })
        instanceHooks[method] = hooked
    end
    if hooked[frame] or not HasMethod(frame, method) then return end
    hooksecurefunc(frame, method, callback)
    hooked[frame] = true
end

local function OwnerState(owner)
    local state = EditModeSkin.owners[owner]
    if not state then
        state = {
            owner = owner,
            active = false,
            primed = false,
            callbackRegistered = false,
            surfaces = setmetatable({}, { __mode = "k" }),
        }
        EditModeSkin.owners[owner] = state
    end
    return state
end

local function Attach(state, target, spec)
    if not target or not NS.Safety.CanDecorate(target, true)
        or not NS.Surface.Attach(target, spec) then
        return false
    end
    state.surfaces[target] = true
    return true
end

local function Fade(region, owner)
    if region then NS.Cosmetics.Fade(region, owner) end
end

local function FadeNineSlice(frame, owner)
    if frame then NS.Cosmetics.FadeNineSlice(frame, owner) end
end

local function SkinButton(state, button, role, height)
    if not button or not NS.Safety.CanControl(button, true)
        or not NS.ControlSkin.ApplyButton(button, state.owner, ButtonSpec(role, height)) then
        return false
    end
    state.surfaces[button] = true
    return true
end

local function RefreshOrSkinButton(state, button, role)
    if button and NS.ControlSkin.IsApplied(button) and NS.ControlSkin.Refresh(button) then
        return true
    end
    return SkinButton(state, button, role, 28)
end

local function SkinActionButtons(state, frame)
    RefreshOrSkinButton(state, Field(frame, "SaveChangesButton"), "buttonPrimary")
    RefreshOrSkinButton(state, Field(frame, "RevertAllChangesButton"), "button")
end

local function OnHasActiveChanges(frame)
    if NS.IsCombatLocked() then return end
    for _, state in pairs(EditModeSkin.owners) do
        if state.active and state.frame == frame then
            -- SetHasActiveChanges updates Blizzard's enabled state and may
            -- restore native button-state textures. Reassign only our already
            -- allocated cosmetic states after Blizzard has finished.
            SkinActionButtons(state, frame)
        end
    end
end

local SkinCheckButton

local function RefreshCheckController(controller)
    if NS.IsCombatLocked() then return end
    local state = EditModeSkin.checkControllers[controller]
    if state and state.active then
        SkinCheckButton(state, Field(controller, "Button"), controller)
    end
end

SkinCheckButton = function(state, button, controller)
    if not button or not NS.Safety.CanControl(button, true)
        or not NS.ControlSkin.ApplyButton(button, state.owner, CHECK_SPEC) then
        return false
    end

    -- ControlSkin supplies hover/pushed/disabled feedback. Preserve checked and
    -- disabled-checked textures because those communicate the saved setting,
    -- but force the configurable checkmark token: texture file IDs returned by
    -- current clients cannot be classified reliably from their source path.
    Fade(Call(button, "GetNormalTexture"), state.owner)
    NS.Checkmarks.TrackTexture(Call(button, "GetCheckedTexture")
        or Field(button, "CheckedTexture"), state.owner, "checkmark")
    NS.Checkmarks.TrackTexture(Call(button, "GetDisabledCheckedTexture")
        or Field(button, "DisabledCheckedTexture"), state.owner, "checkmark")
    if controller then
        EditModeSkin.checkControllers[controller] = state
        HookInstance(controller, "EditModeCheckButton_OnShow", RefreshCheckController)
        HookInstance(controller, "SetControlChecked", RefreshCheckController)
    end
    state.surfaces[button] = true
    return true
end

-- MinimalSliderWithSteppersTemplate stores the previous/next arrows as
-- anonymous texture regions on Back/Forward rather than button states. They
-- are fixed template regions, so they are collected once per slider.
local sliderGlyphs = setmetatable({}, { __mode = "k" })

local function CollectTextures(glyphs, ...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if Call(region, "GetObjectType") == "Texture" then
            glyphs[#glyphs + 1] = region
        end
    end
end

local function SliderGlyphs(container)
    local glyphs = sliderGlyphs[container]
    if not glyphs then
        glyphs = {}
        CollectTextures(glyphs, Call(Field(container, "Back"), "GetRegions"))
        CollectTextures(glyphs, Call(Field(container, "Forward"), "GetRegions"))
        glyphs.thumb = Field(Field(container, "Slider"), "Thumb")
        sliderGlyphs[container] = glyphs
    end
    return glyphs
end

local function TrackSliderGlyphs(state, container)
    local glyphs = SliderGlyphs(container)
    for index = 1, #glyphs do
        NS.Checkmarks.TrackTexture(glyphs[index], state.owner, "blizzardArrow")
    end
    NS.Checkmarks.TrackTexture(glyphs.thumb, state.owner, "active")
end

local function RefreshSliderContainer(container)
    if NS.IsCombatLocked() then return end
    local state = EditModeSkin.sliderContainers[container]
    if state and state.active then
        -- MinimalSliderWithSteppersMixin resets desaturation/alpha after value
        -- and enabled-state changes. Reassert only this slider's known glyphs.
        TrackSliderGlyphs(state, container)
    end
end

local function SkinSlider(state, wrapper)
    local nested = Field(wrapper, "Slider")
    local container = nested and Field(nested, "Slider") and nested or wrapper
    local slider = Field(container, "Slider") or nested or wrapper
    if not slider or not Attach(state, slider, SLIDER_SPEC) then
        return false
    end
    Fade(Field(slider, "Left"), state.owner)
    Fade(Field(slider, "Middle"), state.owner)
    Fade(Field(slider, "Right"), state.owner)
    -- Recolor the stepper glyphs and the thumb while retaining Blizzard's
    -- enabled alpha, click handlers, value semantics and narration.
    EditModeSkin.sliderContainers[container] = state
    HookInstance(container, "UpdateStepperStates", RefreshSliderContainer)
    HookInstance(container, "SetEnabled", RefreshSliderContainer)
    TrackSliderGlyphs(state, container)
    return true
end

local function SkinDropdown(state, dropdown)
    if not dropdown or not NS.Safety.CanControl(dropdown, true)
        or not NS.ControlSkin.ApplyButton(dropdown, state.owner, DROPDOWN_SPEC) then
        return false
    end
    -- Arrow and selection text remain Blizzard-owned semantic content.
    state.surfaces[dropdown] = true
    return true
end

local function SkinAccountCheckButtons(state, account)
    local checkButtons = Field(account, "settingsCheckButtons")
    if type(checkButtons) ~= "table" then return end
    local visited = 0
    for _, wrapper in pairs(checkButtons) do
        if visited >= 64 then break end
        visited = visited + 1
        SkinCheckButton(state, Field(wrapper, "Button"), wrapper)
    end
end

local function SkinSettingFrame(state, settingFrame)
    if not settingFrame then return end
    Attach(state, settingFrame, SETTING_SPEC)
    SkinDropdown(state, Field(settingFrame, "Dropdown"))
    SkinSlider(state, Field(settingFrame, "Slider"))
    SkinCheckButton(state, Field(settingFrame, "Button"), settingFrame)
end

local function SkinExtraButton(state, button)
    SkinButton(state, button, "button", 28)
end

local function SettingReserveCounts()
    local counts = {}
    for index = 1, #settingTemplates do counts[settingTemplates[index]] = 4 end

    local manager = _G.EditModeSettingDisplayInfoManager
    local display = Field(manager, "systemSettingDisplayInfo")
    local enum = _G.Enum
    local editTypes = enum and enum.EditModeSettingDisplayType
    local characterTypes = enum and enum.ChrCustomizationOptionType
    if type(display) ~= "table" or not editTypes then
        counts.EditModeSettingDropdownTemplate = 10
        counts.EditModeSettingSliderTemplate = 12
        counts.EditModeSettingCheckboxTemplate = 12
        return counts
    end

    for _, systemInfo in pairs(display) do
        local dropdowns, sliders, checkboxes = 0, 0, 0
        if type(systemInfo) == "table" then
            for _, setting in ipairs(systemInfo) do
                if setting.type == editTypes.Dropdown then
                    dropdowns = dropdowns + 1
                elseif setting.type == editTypes.Slider then
                    sliders = sliders + 1
                elseif characterTypes and setting.type == characterTypes.Checkbox then
                    checkboxes = checkboxes + 1
                end
            end
        end
        counts.EditModeSettingDropdownTemplate = math.max(counts.EditModeSettingDropdownTemplate, dropdowns + 1)
        counts.EditModeSettingSliderTemplate = math.max(counts.EditModeSettingSliderTemplate, sliders + 1)
        counts.EditModeSettingCheckboxTemplate = math.max(counts.EditModeSettingCheckboxTemplate, checkboxes + 1)
    end

    for template, count in pairs(counts) do
        counts[template] = math.max(1, math.min(32, count))
    end
    return counts
end

-- Skin enough pooled frames up front that the dialog never has to create
-- regions while it is being shown.
local function PrimePool(state, pools, template, count, skin)
    local pool = Call(pools, "GetPool", template)
    if not pool or not HasMethod(pool, "Acquire")
        or not HasMethod(pool, "Release") then
        return
    end
    local active = Call(pool, "GetNumActive")
    active = type(active) == "number" and active or 0
    local acquired = {}
    for _ = 1, count - math.max(0, active) do
        local frame = pool:Acquire()
        if not frame then break end
        acquired[#acquired + 1] = frame
        skin(state, frame)
    end
    for index = #acquired, 1, -1 do
        pool:Release(acquired[index])
    end
end

local function SkinActiveSettings(state, dialog)
    local pools = Field(dialog, "pools")
    if not HasMethod(pools, "EnumerateActiveByTemplate") then return end
    for index = 1, #settingTemplates do
        for settingFrame in pools:EnumerateActiveByTemplate(settingTemplates[index]) do
            SkinSettingFrame(state, settingFrame)
        end
    end
    for button in pools:EnumerateActiveByTemplate(EXTRA_BUTTON_TEMPLATE) do
        SkinExtraButton(state, button)
    end
end

local function PrimeSettings(state, dialog)
    if not state.primed then
        local pools = Field(dialog, "pools")
        if not pools then return end
        local reserve = SettingReserveCounts()
        for index = 1, #settingTemplates do
            local template = settingTemplates[index]
            PrimePool(state, pools, template, reserve[template] or 4, SkinSettingFrame)
        end
        PrimePool(state, pools, EXTRA_BUTTON_TEMPLATE, 8, SkinExtraButton)
        state.primed = true
    end
    SkinActiveSettings(state, dialog)
end

local function SkinManagerExplicit(state, frame)
    local owner = state.owner
    FadeNineSlice(Field(frame, "Border"), owner)
    SkinDropdown(state, Field(frame, "LayoutDropdown"))
    SkinActionButtons(state, frame)
    for index = 1, #managerCheckButtons do
        local controller = Field(frame, managerCheckButtons[index])
        SkinCheckButton(state, Field(controller, "Button"), controller)
    end
    SkinSlider(state, Field(Field(frame, "GridSpacingSlider"), "Slider"))

    local account = Field(frame, "AccountSettings")
    local settingsContainer = Field(account, "SettingsContainer")
    FadeNineSlice(Field(settingsContainer, "BorderArt"), owner)
    Fade(Field(Field(account, "Expander"), "Divider"), owner)
    Attach(state, settingsContainer, ACCOUNT_SPEC)
    SkinAccountCheckButtons(state, account)
end

local function SkinDialogExplicit(state, dialog)
    FadeNineSlice(Field(dialog, "Border"), state.owner)
    SkinButton(state, Field(dialog, "AcceptButton"), "buttonPrimary", 24)
    SkinButton(state, Field(dialog, "CancelButton"), "button", 24)
    SkinButton(state, Field(dialog, "SaveAndProceedButton"), "buttonPrimary", 24)
    SkinButton(state, Field(dialog, "ProceedButton"), "button", 24)
    SkinButton(state, Field(dialog, "CloseButton"), "button", 24)
    local buttons = Field(dialog, "Buttons")
    SkinButton(state, Field(buttons, "RevertChangesButton"), "button", 28)
    Fade(Field(buttons, "Divider"), state.owner)
end

local function ApplyRoots(state, frame)
    if not state.active or NS.IsCombatLocked() then return false, "combat" end
    frame = frame or _G.EditModeManagerFrame
    if not frame then return false, "missing-frame" end

    local applied, reason = NS.GenericWindows.ApplyFrame(frame, state.owner, MANAGER_MODE)
    if not applied then return false, reason end
    state.surfaces[frame] = true
    SkinManagerExplicit(state, frame)

    for index = 1, #dialogRoots do
        local dialog = _G[dialogRoots[index]]
        if dialog then
            NS.GenericWindows.ApplyFrame(dialog, state.owner, DIALOG_MODE)
            state.surfaces[dialog] = true
            SkinDialogExplicit(state, dialog)
        end
    end

    PrimeSettings(state, _G.EditModeSystemSettingsDialog)
    return true
end

local function OnEditModeEnter(state)
    if state.active and not NS.IsCombatLocked() then
        ApplyRoots(state, _G.EditModeManagerFrame)
    end
end

local function RegisterCallback(state)
    if state.callbackRegistered or not EventRegistry
        or type(EventRegistry.RegisterCallback) ~= "function" then
        return
    end
    EventRegistry:RegisterCallback("EditMode.Enter", OnEditModeEnter, state)
    state.callbackRegistered = true
end

function EditModeSkin.Apply(frame, owner)
    owner = owner or "editMode"
    if NS.IsCombatLocked() then return false, "combat" end
    frame = frame or _G.EditModeManagerFrame
    if not frame then return false, "missing-frame" end
    if not NS.Safety.CanDecorate(frame, true) then
        return false, "protected-frame"
    end

    local state = OwnerState(owner)
    state.active = true
    state.frame = frame
    HookInstance(frame, "SetHasActiveChanges", OnHasActiveChanges)
    RegisterCallback(state)
    return ApplyRoots(state, frame)
end

function EditModeSkin.Disable(_, owner)
    owner = owner or "editMode"
    if NS.IsCombatLocked() then return false, "combat" end
    local state = EditModeSkin.owners[owner]
    if not state then return true end
    state.active = false
    state.frame = nil
    state.primed = false
    if state.callbackRegistered then
        EventRegistry:UnregisterCallback("EditMode.Enter", state)
        state.callbackRegistered = false
    end

    NS.GenericWindows.Disable(owner)
    NS.ControlSkin.DisableOwner(owner)
    NS.Cosmetics.RestoreOwner(owner)
    for target in pairs(state.surfaces) do
        NS.Surface.SetVisible(target, false)
    end
    return true
end

return EditModeSkin
