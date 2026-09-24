local _, NS = ...

-- Clean-room Blizzard Edit Mode skin based on wow-ui-source upstream/live
-- 710f59e. The manager, dialogs and setting controls remain entirely owned by
-- Blizzard. MapkoSkin only adds cosmetic textures and suppresses verified
-- decorative regions outside combat.
local EditModeSkin = {
    owners = {},
    actionHooked = false,
    checkShowHooked = false,
    checkStateHooked = false,
    sliderStateHooked = false,
    sliderEnableHooked = false,
    checkControllers = setmetatable({}, { __mode = "k" }),
    sliderContainers = setmetatable({}, { __mode = "k" }),
}
NS.EditModeSkin = EditModeSkin

local dialogRoots = {
    { "EditModeLayoutDialog", "dialog" },
    { "EditModeImportLayoutDialog", "dialog" },
    { "EditModeImportLayoutLinkDialog", "dialog" },
    { "EditModeUnsavedChangesDialog", "dialog" },
    { "EditModeSystemSettingsDialog", "dialog" },
}

local settingTemplates = {
    "EditModeSettingDropdownTemplate",
    "EditModeSettingSliderTemplate",
    "EditModeSettingCheckboxTemplate",
}

local function SafeField(object, key)
    if not object then return nil end
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
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

local function Track(state, target)
    if state and target then state.surfaces[target] = true end
end

local function Attach(state, target, spec)
    if not target or not NS.Safety or not NS.Safety.CanDecorate(target, true) then
        return false
    end
    spec = spec or {}
    spec.allowImplicitProtected = true
    local surface = NS.Surface.Attach(target, spec)
    if surface then
        Track(state, target)
        return true
    end
    return false
end

local function Fade(region, owner)
    if region then pcall(NS.Cosmetics.Fade, region, owner) end
end

local function FadeNineSlice(frame, owner)
    if frame then pcall(NS.Cosmetics.FadeNineSlice, frame, owner) end
end

local function GetterRegion(control, method)
    local getter = SafeField(control, method)
    if type(getter) ~= "function" then return nil end
    local ok, region = pcall(getter, control)
    return ok and region or nil
end

local function FieldOrGetter(control, field, getter)
    return GetterRegion(control, getter) or SafeField(control, field)
end

local function SkinButton(state, button, role, activeRole, height)
    if not button or not NS.Safety or not NS.Safety.CanControl(button, true) then
        return false
    end
    local ok, result = pcall(NS.ControlSkin.ApplyButton, button, state.owner, {
        role = role or "button",
        activeRole = activeRole or "buttonPrimary",
        useControlShape = true,
        pillHeight = height or 28,
        inset = 1,
        allowImplicitProtected = true,
    })
    if ok and result then
        Track(state, button)
        return true
    end
    return false
end

local function SkinActionButtons(state, frame)
    local function RefreshOrSkin(button, role)
        if button and NS.ControlSkin and type(NS.ControlSkin.IsApplied) == "function"
            and NS.ControlSkin.IsApplied(button)
            and type(NS.ControlSkin.Refresh) == "function" then
            local ok, refreshed = pcall(NS.ControlSkin.Refresh, button)
            if ok and refreshed then return true end
        end
        return SkinButton(state, button, role, "buttonPrimary", 28)
    end
    local saveApplied = RefreshOrSkin(SafeField(frame, "SaveChangesButton"), "buttonPrimary")
    local revertApplied = RefreshOrSkin(SafeField(frame, "RevertAllChangesButton"), "button")
    return saveApplied, revertApplied
end

local SkinCheckButton
local TrackSliderGlyphs

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

local function RegisterActionHook()
    local mixin = _G.EditModeManagerFrameMixin
    if EditModeSkin.actionHooked or type(hooksecurefunc) ~= "function"
        or type(mixin) ~= "table"
        or type(SafeField(mixin, "SetHasActiveChanges")) ~= "function" then
        return EditModeSkin.actionHooked
    end
    local ok = pcall(function()
        hooksecurefunc(mixin, "SetHasActiveChanges", OnHasActiveChanges)
    end)
    EditModeSkin.actionHooked = ok == true
    return EditModeSkin.actionHooked
end

local function RefreshCheckController(controller)
    if NS.IsCombatLocked() then return end
    local state = EditModeSkin.checkControllers[controller]
    if not state or not state.active then return end
    SkinCheckButton(state, SafeField(controller, "Button"), controller)
end

local function RefreshSliderContainer(container)
    if NS.IsCombatLocked() then return end
    local state = EditModeSkin.sliderContainers[container]
    if not state or not state.active then return end
    -- MinimalSliderWithSteppersMixin resets desaturation/alpha after value and
    -- enabled-state changes. Reassert only the already tracked exact glyphs;
    -- no traversal, allocation, timer, or work for unrelated sliders.
    TrackSliderGlyphs(state, container)
end

local function RegisterControlHooks()
    if type(hooksecurefunc) ~= "function" then return false end

    local editCheckMixin = _G.EditModeCheckButtonMixin
    if not EditModeSkin.checkShowHooked and type(editCheckMixin) == "table"
        and type(SafeField(editCheckMixin, "EditModeCheckButton_OnShow")) == "function" then
        local ok = pcall(function()
            hooksecurefunc(editCheckMixin, "EditModeCheckButton_OnShow", RefreshCheckController)
        end)
        EditModeSkin.checkShowHooked = ok == true
    end

    local resizeCheckMixin = _G.ResizeCheckButtonMixin
    if not EditModeSkin.checkStateHooked and type(resizeCheckMixin) == "table"
        and type(SafeField(resizeCheckMixin, "SetControlChecked")) == "function" then
        local ok = pcall(function()
            hooksecurefunc(resizeCheckMixin, "SetControlChecked", RefreshCheckController)
        end)
        EditModeSkin.checkStateHooked = ok == true
    end

    local sliderMixin = _G.MinimalSliderWithSteppersMixin
    if not EditModeSkin.sliderStateHooked and type(sliderMixin) == "table"
        and type(SafeField(sliderMixin, "UpdateStepperStates")) == "function" then
        local ok = pcall(function()
            hooksecurefunc(sliderMixin, "UpdateStepperStates", RefreshSliderContainer)
        end)
        EditModeSkin.sliderStateHooked = ok == true
    end
    if not EditModeSkin.sliderEnableHooked and type(sliderMixin) == "table"
        and type(SafeField(sliderMixin, "SetEnabled")) == "function" then
        local ok = pcall(function()
            hooksecurefunc(sliderMixin, "SetEnabled", RefreshSliderContainer)
        end)
        EditModeSkin.sliderEnableHooked = ok == true
    end

    return EditModeSkin.checkShowHooked or EditModeSkin.checkStateHooked
        or EditModeSkin.sliderStateHooked or EditModeSkin.sliderEnableHooked
end

local function SkinDropdown(state, dropdown)
    if not dropdown or not NS.Safety or not NS.Safety.CanControl(dropdown, true) then
        return false
    end
    local ok, result = pcall(NS.ControlSkin.ApplyButton, dropdown, state.owner, {
        role = "input",
        activeRole = "navigationActive",
        useControlShape = true,
        pillHeight = 28,
        inset = 0,
        regions = { "Background" },
        allowImplicitProtected = true,
    })
    if ok and result then
        -- Arrow and selection text remain Blizzard-owned semantic content.
        Track(state, dropdown)
        return true
    end
    return false
end

SkinCheckButton = function(state, button, controller)
    if not button or not NS.Safety or not NS.Safety.CanControl(button, true) then
        return false
    end
    local ok, result = pcall(NS.ControlSkin.ApplyButton, button, state.owner, {
        role = "input",
        activeRole = "navigationActive",
        shape = "continuous",
        radius = 4,
        inset = 3,
        allowImplicitProtected = true,
    })
    if not ok or not result then return false end

    -- ControlSkin supplies hover/pushed/disabled feedback. Preserve checked and
    -- disabled-checked textures because those communicate the saved setting,
    -- but force the configurable checkmark token: texture file IDs returned by
    -- current clients cannot be classified reliably from their source path.
    Fade(GetterRegion(button, "GetNormalTexture"), state.owner)
    if NS.Checkmarks then
        NS.Checkmarks.TrackTexture(
            FieldOrGetter(button, "CheckedTexture", "GetCheckedTexture"),
            state.owner,
            "checkmark"
        )
        NS.Checkmarks.TrackTexture(
            FieldOrGetter(button, "DisabledCheckedTexture", "GetDisabledCheckedTexture"),
            state.owner,
            "checkmark"
        )
    end
    if controller then EditModeSkin.checkControllers[controller] = state end
    Track(state, button)
    return true
end

TrackSliderGlyphs = function(state, container)
    if not state or not container or not NS.Checkmarks then return false end
    local changed = false
    local function TrackRegions(control, role)
        local getRegions = SafeField(control, "GetRegions")
        if type(getRegions) ~= "function" then return end
        pcall(function()
            local regions = { getRegions(control) }
            for index = 1, #regions do
                local region = regions[index]
                local objectType = SafeField(region, "GetObjectType")
                if type(objectType) == "function" then
                    local ok, value = pcall(objectType, region)
                    if ok and value == "Texture" then
                        changed = NS.Checkmarks.TrackTexture(region, state.owner, role) or changed
                    end
                end
            end
        end)
    end
    TrackRegions(SafeField(container, "Back"), "blizzardArrow")
    TrackRegions(SafeField(container, "Forward"), "blizzardArrow")
    local slider = SafeField(container, "Slider")
    changed = NS.Checkmarks.TrackTexture(SafeField(slider, "Thumb"), state.owner, "active")
        or changed
    return changed
end

local function SkinSlider(state, wrapper)
    local nested = SafeField(wrapper, "Slider")
    local container = nested and SafeField(nested, "Slider") and nested or wrapper
    local slider = SafeField(container, "Slider") or nested or wrapper
    if not slider or not NS.Safety or not NS.Safety.CanDecorate(slider, true) then
        return false
    end
    local applied = Attach(state, slider, {
        role = "input",
        shape = "continuous",
        radius = 4,
        inset = 2,
    })
    if not applied then return false end
    Fade(SafeField(slider, "Left"), state.owner)
    Fade(SafeField(slider, "Middle"), state.owner)
    Fade(SafeField(slider, "Right"), state.owner)
    -- MinimalSliderWithSteppersTemplate stores the previous/next arrows as
    -- anonymous texture regions on Back/Forward rather than button states.
    -- Recolor those exact regions and the thumb while retaining Blizzard's
    -- enabled alpha, click handlers, value semantics and narration.
    EditModeSkin.sliderContainers[container] = state
    TrackSliderGlyphs(state, container)
    return true
end

local function SkinAccountCheckButtons(state, account)
    local checkButtons = SafeField(account, "settingsCheckButtons")
    if type(checkButtons) ~= "table" then return end
    local visited = 0
    for _, wrapper in pairs(checkButtons) do
        if visited >= 64 then break end
        visited = visited + 1
        SkinCheckButton(state, SafeField(wrapper, "Button"), wrapper)
    end
end

local function SkinSettingFrame(state, settingFrame)
    if not settingFrame then return false end
    Attach(state, settingFrame, {
        role = "panel",
        radius = 4,
        inset = 0,
        listItem = true,
    })
    SkinDropdown(state, SafeField(settingFrame, "Dropdown"))
    SkinSlider(state, SafeField(settingFrame, "Slider"))
    SkinCheckButton(state, SafeField(settingFrame, "Button"), settingFrame)
    return true
end

local function SettingReserveCounts()
    local counts = {}
    for index = 1, #settingTemplates do counts[settingTemplates[index]] = 4 end

    local manager = _G.EditModeSettingDisplayInfoManager
    local display = manager and SafeField(manager, "systemSettingDisplayInfo")
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
        local current = { dropdown = 0, slider = 0, checkbox = 0 }
        if type(systemInfo) == "table" then
            for _, setting in ipairs(systemInfo) do
                if setting.type == editTypes.Dropdown then
                    current.dropdown = current.dropdown + 1
                elseif setting.type == editTypes.Slider then
                    current.slider = current.slider + 1
                elseif characterTypes and setting.type == characterTypes.Checkbox then
                    current.checkbox = current.checkbox + 1
                end
            end
        end
        counts.EditModeSettingDropdownTemplate = math.max(counts.EditModeSettingDropdownTemplate, current.dropdown + 1)
        counts.EditModeSettingSliderTemplate = math.max(counts.EditModeSettingSliderTemplate, current.slider + 1)
        counts.EditModeSettingCheckboxTemplate = math.max(counts.EditModeSettingCheckboxTemplate, current.checkbox + 1)
    end

    for template, count in pairs(counts) do
        counts[template] = math.max(1, math.min(32, count))
    end
    return counts
end

local function PrimePool(state, collection, template, count, skin)
    local getter = SafeField(collection, "GetPool")
    if type(getter) ~= "function" then return false end
    local okPool, pool = pcall(getter, collection, template)
    if not okPool or not pool then return false end
    local acquire = SafeField(pool, "Acquire")
    local release = SafeField(pool, "Release")
    if type(acquire) ~= "function" or type(release) ~= "function" then return false end

    local activeCount = 0
    local countActive = SafeField(pool, "GetNumActive")
    if type(countActive) == "function" then
        local ok, value = pcall(countActive, pool)
        local converted = ok and tonumber(value) or nil
        activeCount = converted and math.max(0, converted) or 0
    end

    local acquired = {}
    for index = 1, math.max(0, count - activeCount) do
        local ok, frame = pcall(acquire, pool)
        if not ok or not frame then break end
        acquired[#acquired + 1] = frame
        skin(state, frame)
    end
    for index = #acquired, 1, -1 do
        pcall(release, pool, acquired[index])
    end
    return true
end

local function SkinActiveSettings(state, dialog)
    local pools = dialog and SafeField(dialog, "pools")
    local enumerate = pools and SafeField(pools, "EnumerateActiveByTemplate")
    if type(enumerate) ~= "function" then return end
    for index = 1, #settingTemplates do
        local template = settingTemplates[index]
        pcall(function()
            for settingFrame in enumerate(pools, template) do
                SkinSettingFrame(state, settingFrame)
            end
        end)
    end
    pcall(function()
        for button in enumerate(pools, "EditModeSystemSettingsDialogExtraButtonTemplate") do
            SkinButton(state, button, "button", "buttonPrimary", 28)
        end
    end)
end

local function PrimeSettings(state, dialog)
    if state.primed then
        SkinActiveSettings(state, dialog)
        return true
    end
    local pools = dialog and SafeField(dialog, "pools")
    if not pools then return false end
    local reserve = SettingReserveCounts()
    for index = 1, #settingTemplates do
        local template = settingTemplates[index]
        PrimePool(state, pools, template, reserve[template] or 4, SkinSettingFrame)
    end
    PrimePool(state, pools, "EditModeSystemSettingsDialogExtraButtonTemplate", 8,
        function(ownerState, button)
            SkinButton(ownerState, button, "button", "buttonPrimary", 28)
        end)
    state.primed = true
    SkinActiveSettings(state, dialog)
    return true
end

local function SkinManagerExplicit(state, frame)
    FadeNineSlice(SafeField(frame, "Border"), state.owner)
    SkinDropdown(state, SafeField(frame, "LayoutDropdown"))
    SkinActionButtons(state, frame)
    local showGrid = SafeField(frame, "ShowGridCheckButton")
    local snap = SafeField(frame, "EnableSnapCheckButton")
    local advanced = SafeField(frame, "EnableAdvancedOptionsCheckButton")
    SkinCheckButton(state, SafeField(showGrid, "Button"), showGrid)
    SkinCheckButton(state, SafeField(snap, "Button"), snap)
    SkinCheckButton(state, SafeField(advanced, "Button"), advanced)
    SkinSlider(state, SafeField(SafeField(frame, "GridSpacingSlider"), "Slider"))

    local account = SafeField(frame, "AccountSettings")
    local settingsContainer = SafeField(account, "SettingsContainer")
    FadeNineSlice(SafeField(settingsContainer, "BorderArt"), state.owner)
    Fade(SafeField(SafeField(account, "Expander"), "Divider"), state.owner)
    Attach(state, settingsContainer, { role = "panel", radius = 6, inset = 0 })
    SkinAccountCheckButtons(state, account)
end

local function SkinDialogExplicit(state, dialog)
    if not dialog then return end
    FadeNineSlice(SafeField(dialog, "Border"), state.owner)
    SkinButton(state, SafeField(dialog, "AcceptButton"), "buttonPrimary", "buttonPrimary", 24)
    SkinButton(state, SafeField(dialog, "CancelButton"), "button", "buttonPrimary", 24)
    SkinButton(state, SafeField(dialog, "SaveAndProceedButton"), "buttonPrimary", "buttonPrimary", 24)
    SkinButton(state, SafeField(dialog, "ProceedButton"), "button", "buttonPrimary", 24)
    SkinButton(state, SafeField(dialog, "CloseButton"), "button", "buttonPrimary", 24)
    local buttons = SafeField(dialog, "Buttons")
    SkinButton(state, SafeField(buttons, "RevertChangesButton"), "button", "buttonPrimary", 28)
    Fade(SafeField(buttons, "Divider"), state.owner)
end

local function ApplyRoots(state, frame)
    if not state.active or NS.IsCombatLocked() then return false, "combat" end
    frame = frame or _G.EditModeManagerFrame
    if not frame then return false, "missing-frame" end

    local applied, reason = NS.GenericWindows.ApplyFrame(frame, state.owner, {
        role = "shell",
        radius = 8,
        inset = 0,
        -- EditModeManagerFrame's AccountSettings tree is static and known;
        -- seven levels cover it without walking UIParent-sized grid/preview
        -- containers. Dynamic dialog controls are handled by their pools.
        maxDepth = 7,
        maxNodes = 420,
        registerDynamicRows = false,
        allowImplicitProtected = true,
    })
    if not applied then return false, reason end
    Track(state, frame)
    SkinManagerExplicit(state, frame)

    for index = 1, #dialogRoots do
        local definition = dialogRoots[index]
        local dialog = _G[definition[1]]
        if dialog then
            NS.GenericWindows.ApplyFrame(dialog, state.owner, {
                role = "popup",
                radius = 8,
                inset = 0,
                maxDepth = 6,
                maxNodes = 220,
                registerDynamicRows = false,
                allowImplicitProtected = true,
            })
            Track(state, dialog)
            SkinDialogExplicit(state, dialog)
        end
    end

    PrimeSettings(state, _G.EditModeSystemSettingsDialog)
    return true
end

local function OnEditModeEnter(state)
    if state and state.active and not NS.IsCombatLocked() then
        ApplyRoots(state, _G.EditModeManagerFrame)
    end
end

local function RegisterCallback(state)
    if state.callbackRegistered or not EventRegistry
        or type(EventRegistry.RegisterCallback) ~= "function" then
        return
    end
    local ok = pcall(EventRegistry.RegisterCallback, EventRegistry,
        "EditMode.Enter", OnEditModeEnter, state)
    state.callbackRegistered = ok == true
end

function EditModeSkin.Apply(frame, owner)
    owner = owner or "editMode"
    if NS.IsCombatLocked() then return false, "combat" end
    frame = frame or _G.EditModeManagerFrame
    if not frame then return false, "missing-frame" end
    if not NS.Safety or not NS.Safety.CanDecorate(frame, true) then
        return false, "protected-frame"
    end

    local state = OwnerState(owner)
    state.active = true
    state.frame = frame
    RegisterActionHook()
    RegisterControlHooks()
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
    if state.callbackRegistered and EventRegistry
        and type(EventRegistry.UnregisterCallback) == "function" then
        pcall(EventRegistry.UnregisterCallback, EventRegistry, "EditMode.Enter", state)
    end
    state.callbackRegistered = false

    NS.GenericWindows.Disable(owner)
    pcall(NS.ControlSkin.DisableOwner, owner)
    pcall(NS.Cosmetics.RestoreOwner, owner)
    for target in pairs(state.surfaces) do
        pcall(NS.Surface.SetVisible, target, false)
    end
    return true
end

return EditModeSkin
