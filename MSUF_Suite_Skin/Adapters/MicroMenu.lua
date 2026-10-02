local _, NS = ...

-- Skins the exact current MicroMenu root and button set outside combat.
-- Blizzard keeps the buttons, their scripts, state changes and semantic
-- regions (alerts, notifications, performance text). In the owned layout mode
-- OwnedMicroBar takes the whole MicroMenu into its own bar and places the
-- button grid; otherwise Blizzard keeps the layout and this adapter only
-- decorates. The reversible art states (tints, faded regions, plates) live
-- in MicroMenuStates.lua (loads before), the settings, their validation and
-- presets, and the icon colours they resolve to in MicroMenuSettings.lua
-- (loads next).
local MicroMenuSkin = {
    active = false,
}
NS.MicroMenuSkin = MicroMenuSkin

local Safety = NS.Safety
local Field = Safety.Field
local Call = Safety.Call
local Read = Safety.Read
local HasMethod = Safety.HasMethod
local Dispatch = Safety.Dispatch
local Kit = NS.AdapterKit
local States = NS.MicroMenuStates
local BorderValue, CanControl = States.BorderValue, States.CanControl
local ApplyTextureTint, FadeExact = States.ApplyTextureTint, States.FadeExact
local RestoreButtonTextures, RestoreButtonAlphas = States.RestoreButtonTextures, States.RestoreButtonAlphas
local ApplySurface, RestoreSurface = States.ApplySurface, States.RestoreSurface
local ShowsAppliedPlate = States.ShowsAppliedPlate

local BUTTON_NAMES = NS.Client.isForever and {
    "CharacterMicroButton",
    "ProfessionMicroButton",
    "SpellbookMicroButton",
    "TalentMicroButton",
    "LegacyMicroButton",
    "QuestLogMicroButton",
    "HousingMicroButton",
    "GuildMicroButton",
    "LFDMicroButton",
    "CollectionsMicroButton",
    "EJMicroButton",
    "HelpMicroButton",
    "StoreMicroButton",
    "MainMenuMicroButton",
} or {
    "CharacterMicroButton",
    "ProfessionMicroButton",
    "PlayerSpellsMicroButton",
    "AchievementMicroButton",
    "QuestLogMicroButton",
    "HousingMicroButton",
    "GuildMicroButton",
    "LFDMicroButton",
    "CollectionsMicroButton",
    "EJMicroButton",
    "HelpMicroButton",
    "StoreMicroButton",
    "MainMenuMicroButton",
}

local TEXTURE_STATES = {
    { getter = "GetNormalTexture", state = "normal" },
    { getter = "GetHighlightTexture", state = "hover" },
    { getter = "GetPushedTexture", state = "pressed" },
    { getter = "GetDisabledTexture", state = "disabled" },
}

-- These regions form Blizzard's baked ornamental button art. They are hidden
-- only while the clean MSKIN glyph layer is active and restored exactly when
-- the user selects Blizzard art or disables the adapter. Alert, notification,
-- quick-keybind and performance regions intentionally stay native and above
-- the owned visual layer because they carry live semantic state.
local CLEAN_HIDDEN_MEMBERS = {
    "Background",
    "PushedBackground",
    "Portrait",
    "Shadow",
    "PushedShadow",
    "Emblem",
    "HighlightEmblem",
}

-- Blizzard's MicroButton methods whose native state updates rewrite the
-- button art. They are copied onto every button when it is created, so each
-- live instance is hooked once; OnEnter/OnLeave use one script hook that also
-- drives the owned bar's mouseover reveal.
local BUTTON_STATE_METHODS = { "SetPushed", "SetNormal", "OnEnable", "OnDisable" }

local activeButtons = setmetatable({}, { __mode = "k" })
local hookedButtons = setmetatable({}, { __mode = "k" })
local listenerOwner = {}
local listenerRegistered = false
local containerHooked = false
local activeRoot
local activeOwner
local desiredActive = false
local desiredRoot
local desiredOwner
local DEFER_KEY = "micro-menu:state"
local visualSuspended = false
local transitionInProgress = false

local function Settings()
    local icons = NS.DB and NS.DB.icons
    local configured = icons and icons.microMenu
    if configured then return configured end
    return NS.Defaults.icons.microMenu
end

-- Root and buttons -----------------------------------------------------------------------

local function ResolveRoot(requested)
    if requested and requested ~= MicroMenu then return nil, "unexpected-root" end
    return MicroMenu
end

local function ResolveButton(name, root)
    local button = _G[name]
    if not button then return nil end
    if HasMethod(button, "GetObjectType") and Call(button, "GetObjectType") ~= "Button" then
        return nil
    end
    if not Kit.ParentIs(button, root) then return nil end
    return button
end

local function ResolveVisualState(button)
    if Read(button, "IsEnabled") == false then return "disabled" end
    if Read(button, "GetButtonState") == "PUSHED" then return "pressed" end
    if Read(button, "IsMouseOver") == true then return "hover" end
    return "normal"
end

-- stateOnly (a native state hook): the last full pass already undid what
-- another icon style or plate setting had changed, so only the art Blizzard
-- rewrites with each state is refreshed.
local function ApplyCleanButton(button, buttonName, settings, stateOnly)
    local success = true
    if not stateOnly then success = RestoreButtonTextures(button) end
    for index = 1, #CLEAN_HIDDEN_MEMBERS do
        local region = Field(button, CLEAN_HIDDEN_MEMBERS[index])
        if region then
            success = FadeExact(button, region) and success
        end
    end
    for index = 1, #TEXTURE_STATES do
        local region = Call(button, TEXTURE_STATES[index].getter)
        if region then success = FadeExact(button, region) and success end
    end
    if not stateOnly then success = RestoreSurface(button) and success end
    return NS.MicroMenuVisual.Apply(button, buttonName, settings, ResolveVisualState(button))
        and success
end

local function TintRequested(settings)
    return settings.tint ~= "native"
        or (tonumber(settings.normalOpacity) or 1) < 1
        or (tonumber(settings.hoverOpacity) or 1) < 1
        or (tonumber(settings.pressedOpacity) or 1) < 1
        or (tonumber(settings.disabledOpacity) or 1) < 1
end

local function ApplyNativeButton(button, settings, stateOnly)
    local success = true
    if not stateOnly then
        success = NS.MicroMenuVisual.Restore(button)
        success = RestoreButtonAlphas(button) and success
        success = RestoreButtonTextures(button) and success
    end

    -- Full Blizzard keeps the original button background. Blizzard icons keep
    -- the original icon and state textures, while the Suite bar supplies the
    -- surrounding frame.
    local extraPlate = settings.buttonBackground == true or BorderValue(settings.buttonBorder) > 0
    if extraPlate or settings.iconStyle == "blizzardIcons" then
        local background = Field(button, "Background")
        local pushedBackground = Field(button, "PushedBackground")
        if background then success = FadeExact(button, background) and success end
        if pushedBackground then success = FadeExact(button, pushedBackground) and success end
    end

    if TintRequested(settings) then
        for index = 1, #TEXTURE_STATES do
            local spec = TEXTURE_STATES[index]
            local region = Call(button, spec.getter)
            if region then
                success = ApplyTextureTint(button, region, spec.state, settings) and success
            end
        end
    end

    if extraPlate then
        if stateOnly and ShowsAppliedPlate(button) then return success end
        return ApplySurface(button, "microButton", settings.buttonBackground,
            settings.buttonBorder, settings, false, true) and success
    end
    if stateOnly then return success end
    return RestoreSurface(button) and success
end

local function ApplyButton(button, buttonName, settings, stateOnly)
    if not CanControl(button) then return false end
    -- Blizzard icons use the live native textures. Copying their atlas into a
    -- smaller overlay loses portrait, state and client-specific artwork.
    if settings.iconStyle ~= "blizzard" and settings.iconStyle ~= "blizzardIcons" then
        return ApplyCleanButton(button, buttonName, settings, stateOnly)
    end
    return ApplyNativeButton(button, settings, stateOnly)
end

local function RestoreButton(button)
    local success = RestoreButtonTextures(button)
    success = RestoreButtonAlphas(button) and success
    success = NS.MicroMenuVisual.Restore(button) and success
    return RestoreSurface(button) and success
end

-- Hooks ----------------------------------------------------------------------------------

local function HooksQuiet()
    return NS.IsCombatLocked() or visualSuspended or transitionInProgress
        or not MicroMenuSkin.active
end

-- Repaints the state-dependent art of one skinned button.
local function RefreshButtonState(button)
    local buttonName = activeButtons[button]
    local settings = buttonName and Settings()
    if settings then ApplyButton(button, buttonName, settings, true) end
end

-- The hooks run inside Blizzard's own calls (UpdateMicroButtons walks every
-- button; OnEnter/OnLeave run the button's own scripts first), so the
-- repaint and the bar's mouseover reveal are each their own error boundary.
local function OnButtonVisualLifecycle(button)
    if not HooksQuiet() then Dispatch(RefreshButtonState, button) end
end

local function OnButtonEnter(button)
    OnButtonVisualLifecycle(button)
    Dispatch(NS.OwnedMicroBar.HoverEnter)
end

local function OnButtonLeave(button)
    OnButtonVisualLifecycle(button)
    Dispatch(NS.OwnedMicroBar.HoverLeave)
end

-- Repaints the state art of every skinned button without a full skin pass,
-- for OwnedMicroBar when it only places the bar again. False when the hooks
-- are quiet (combat, a Blizzard override, a transition or no active skin).
function MicroMenuSkin.RefreshButtonStates()
    if HooksQuiet() then return false end
    for button in pairs(activeButtons) do
        Dispatch(RefreshButtonState, button)
    end
    return true
end

local layoutRefreshPending = false
-- Which BUTTON_NAMES entries were shown at the last layout, as a bit mask:
-- a number, so comparing sets allocates nothing.
local shownButtons = 0

local function ShownButtonMask()
    local mask, bit = 0, 1
    for index = 1, #BUTTON_NAMES do
        local button = _G[BUTTON_NAMES[index]]
        if button and activeButtons[button] and NS.Safety.Read(button, "IsShown") == true then
            mask = mask + bit
        end
        bit = bit * 2
    end
    return mask
end

local function FlushButtonLayout()
    layoutRefreshPending = false
    if NS.IsCombatLocked() or visualSuspended or transitionInProgress
        or not MicroMenuSkin.active then
        return
    end
    MicroMenuSkin.RefreshActive(true)
end

-- Every MicroButton's OnShow/OnHide calls MicroMenuContainer:Layout() (all
-- clients), so one hook on the container sees each visibility change. Repeated
-- signals within a frame collapse into one deferred check.
local function OnContainerLayout()
    if NS.IsCombatLocked() or visualSuspended or transitionInProgress
        or not MicroMenuSkin.active or layoutRefreshPending then
        return
    end
    layoutRefreshPending = true
    C_Timer.After(0, FlushButtonLayout)
end

local function EnsureContainerHook()
    local container = _G.MicroMenuContainer
    if containerHooked or not HasMethod(container, "Layout") then
        return containerHooked
    end
    hooksecurefunc(container, "Layout", OnContainerLayout)
    containerHooked = true
    return true
end

-- Returns false when a required native method is missing on this client.
local function EnsureButtonHooks(button, buttonName)
    if hookedButtons[button] then return true end
    for index = 1, #BUTTON_STATE_METHODS do
        if not HasMethod(button, BUTTON_STATE_METHODS[index]) then return false end
    end
    local tabard = buttonName == "GuildMicroButton"
    if not HasMethod(button, "HookScript")
        or (tabard and not HasMethod(button, "UpdateTabard")) then
        return false
    end
    for index = 1, #BUTTON_STATE_METHODS do
        hooksecurefunc(button, BUTTON_STATE_METHODS[index], OnButtonVisualLifecycle)
    end
    if tabard then hooksecurefunc(button, "UpdateTabard", OnButtonVisualLifecycle) end
    button:HookScript("OnEnter", OnButtonEnter)
    button:HookScript("OnLeave", OnButtonLeave)
    hookedButtons[button] = true
    return true
end

local function EnsureVisualHooks(buttons)
    local success = EnsureContainerHook()
    local found = false
    for button, buttonName in pairs(buttons) do
        found = true
        success = EnsureButtonHooks(button, buttonName) and success
    end
    return found and success
end

local function RestoreAbsentButtons(currentButtons)
    local success = true
    for button in pairs(activeButtons) do
        if not currentButtons[button] then
            success = RestoreButton(button) and success
        end
    end
    return success
end

local ApplyNow

local function ApplyActive()
    if MicroMenuSkin.active then ApplyNow(activeRoot, activeOwner) end
end

-- Settings writes arrive once per slider tick or colour-picker move: the
-- full pass they need runs once on the next frame (after combat when it
-- started in between).
local function OnThemeChanged(_, domain)
    if MicroMenuSkin.active and (domain == "color" or domain == "theme"
        or domain == "appearance" or domain == "geometry"
        or domain == "profile" or domain == "adapter") then
        NS.Registry.QueueJob(ApplyActive)
    end
end

local function EnsureListener()
    if listenerRegistered then return end
    NS.Registry.AddListener(listenerOwner, OnThemeChanged)
    listenerRegistered = true
end

local function RemoveListener()
    if listenerRegistered then
        NS.Registry.RemoveListener(listenerOwner)
    end
    listenerRegistered = false
end

-- Apply and disable ----------------------------------------------------------------------

-- Returns the surface target (owned bar or native root), whether the bar owns
-- it, whether Blizzard currently overrides the menu, and partial.
local function ApplyLayout(root, settings)
    local target, layoutReason = NS.OwnedMicroBar.Apply(root, settings)
    local ownedBar = NS.OwnedMicroBar.GetFrames()
    if layoutReason == "blizzard-override" then
        if ownedBar and ownedBar ~= root then RestoreSurface(ownedBar) end
        return root, false, true, false
    end
    if not target then
        if ownedBar and ownedBar ~= root then RestoreSurface(ownedBar) end
        return root, false, false, true
    end
    local owned = target ~= root
    local inactive = owned and root or ownedBar
    if inactive and inactive ~= target then RestoreSurface(inactive) end
    return target, owned, false, false
end

local function ApplyResolved(root, owner, settings)
    local partial = false
    local currentButtons = setmetatable({}, { __mode = "k" })
    for index = 1, #BUTTON_NAMES do
        local buttonName = BUTTON_NAMES[index]
        local button = ResolveButton(buttonName, root)
        if button then
            currentButtons[button] = buttonName
            if not NS.MicroMenuVisual.Prepare(button, buttonName, settings) then
                partial = true
            end
            -- Native artwork can still use MSKIN button surfaces later. Seed
            -- those regions before an owned layout reparents the button,
            -- independent of the currently selected icon artwork.
            if not ApplySurface(button, "microButton", true, settings.buttonBorder,
                settings, false, true) then
                partial = true
            end
        else
            partial = true
        end
    end
    -- Hooks must exist before OwnedMicroBar reparents the native buttons.
    -- Installing them for every icon style also keeps a later Blizzard ->
    -- clean-art switch from trying to hook implicitly protected buttons.
    if not EnsureVisualHooks(currentButtons) then
        partial = true
    end
    NS.OwnedMicroBar.TrackHoverButtons(currentButtons)

    local barTarget, ownedTarget, overridden, layoutPartial = ApplyLayout(root, settings)
    partial = partial or layoutPartial
    -- Camelot's MicroMenu root has its own wide action-bar art. Its border
    -- extends past our compact owned shell, producing a second frame.
    if NS.Client.isForever and ownedTarget and settings.iconStyle ~= "blizzard" then
        local borderArt = Field(root, "BorderArt")
        local backgroundArt = Field(root, "BackgroundArt")
        if borderArt then partial = not FadeExact(root, borderArt) or partial end
        if backgroundArt then partial = not FadeExact(root, backgroundArt) or partial end
    elseif not RestoreButtonAlphas(root) then
        partial = true
    end
    if overridden then
        if not RestoreSurface(root) then partial = true end
    elseif not ApplySurface(barTarget, "microBar", settings.barBackground,
        settings.barBorder, settings, true, ownedTarget) then
        partial = true
    end

    visualSuspended = overridden
    for button, buttonName in pairs(currentButtons) do
        local applied
        if overridden then
            applied = RestoreButton(button)
        else
            applied = ApplyButton(button, buttonName, settings)
        end
        if not applied then partial = true end
    end
    if not RestoreAbsentButtons(currentButtons) then partial = true end

    activeButtons = currentButtons
    activeRoot = root
    activeOwner = owner
    shownButtons = ShownButtonMask()
    MicroMenuSkin.active = true
    desiredActive = true
    desiredRoot = root
    desiredOwner = owner
    EnsureListener()
    return true, partial and "partial" or "applied"
end

-- transitionInProgress keeps the native hooks quiet while this adapter itself
-- rewrites the buttons. Each transition is its own error boundary, so the
-- flag is cleared even when it raises and the hooks do not stay silent.
local function RunTransition(transition, ...)
    transitionInProgress = true
    local finished, success, result = Kit.Isolate(transition, ...)
    transitionInProgress = false
    if not finished then return false, "error" end
    return success, result
end

ApplyNow = function(requestedRoot, owner)
    if NS.IsCombatLocked() then return false, "combat" end
    local root, reason = ResolveRoot(requestedRoot)
    if not root then return false, reason end
    local settings = Settings()
    if not settings then return false, "settings" end
    return RunTransition(ApplyResolved, root, owner, settings)
end

local function DisableResolved()
    local partial = not States.RestoreArt()
    for button in pairs(activeButtons) do
        if not NS.MicroMenuVisual.Restore(button) then partial = true end
    end
    if not States.RestoreSurfaces() then partial = true end
    if NS.OwnedMicroBar.Disable(activeRoot) == false then partial = true end

    activeButtons = setmetatable({}, { __mode = "k" })
    activeRoot, activeOwner = nil, nil
    MicroMenuSkin.active = false
    visualSuspended = false
    desiredActive, desiredRoot, desiredOwner = false, nil, nil
    RemoveListener()
    return true, partial and "partial" or "disabled"
end

local function DisableNow()
    if NS.IsCombatLocked() then return false, "combat" end
    return RunTransition(DisableResolved)
end

local function RunDesired()
    if desiredActive then
        return ApplyNow(desiredRoot, desiredOwner)
    end
    return DisableNow()
end

local function DeferDesired()
    NS.CombatGate.RunOrDefer(DEFER_KEY, RunDesired)
    return false, "combat"
end

function MicroMenuSkin.Apply(frame, owner)
    desiredActive, desiredRoot, desiredOwner = true, frame, owner
    if NS.IsCombatLocked() then return DeferDesired() end
    return ApplyNow(frame, owner)
end

function MicroMenuSkin.Disable()
    desiredActive, desiredRoot, desiredOwner = false, nil, nil
    if NS.IsCombatLocked() then return DeferDesired() end
    return DisableNow()
end

-- layoutOnly: a MicroButton was shown or hidden. Every button already
-- carries its skin (hidden ones included), so only a changed set of shown
-- buttons needs the owned grid placed again; nothing is re-skinned.
local function RefreshLayout()
    if NS.IsCombatLocked() then return false, "combat" end
    local mask = ShownButtonMask()
    if mask == shownButtons then return true, "unchanged" end
    shownButtons = mask
    return NS.OwnedMicroBar.Relayout(activeRoot), "layout"
end

function MicroMenuSkin.RefreshActive(layoutOnly)
    if not MicroMenuSkin.active then return false, "inactive" end
    if layoutOnly then return RefreshLayout() end
    desiredActive, desiredRoot, desiredOwner = true, activeRoot, activeOwner
    if NS.IsCombatLocked() then return DeferDesired() end
    return ApplyNow(activeRoot, activeOwner)
end

-- Applies a changed setting to the active skin (MicroMenuSettings.lua).
local function RefreshAfterSetting()
    if not MicroMenuSkin.active then return true, "stored" end
    return ApplyNow(activeRoot, activeOwner)
end

-- Private to MicroMenuSettings.lua, which loads next and takes it off NS
-- again.
NS.MicroMenuShared = {
    Settings = Settings,
    RefreshAfterSetting = RefreshAfterSetting,
    buttonCount = #BUTTON_NAMES,
}
