local _, NS = ...

-- Dedicated, bounded Retail Micro Menu skinning. Blizzard keeps ownership of
-- layout, scripts, button state changes and semantic regions; this adapter
-- only decorates the exact current MicroMenu root/button set outside combat.
local MicroMenuSkin = {
    active = false,
}
NS.MicroMenuSkin = MicroMenuSkin

local Field = NS.Safety.Field
local Call = NS.Safety.Call
local Public = NS.Safety.Public

-- Exactly one boolean, also for a missing target (Field returns no value then).
local function HasMethod(target, name)
    return type(target) == "table" and type(target[name]) == "function"
end

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

local STATE_TOKENS = {
    normal = "microIcon",
    hover = "microIconHover",
    pressed = "microIconPressed",
    disabled = "microIconDisabled",
}

local STATE_OPACITY = {
    normal = "normalOpacity",
    hover = "hoverOpacity",
    pressed = "pressedOpacity",
    disabled = "disabledOpacity",
}

-- Layout ownership and visual styling are intentionally independent. Moving,
-- scaling or unlocking the owned bar must not discard the selected icon look.
local VISUAL_OPTION_KEYS = {
    barBackground = true,
    barBorder = true,
    barMaterial = true,
    buttonBackground = true,
    buttonBorder = true,
    shape = true,
    radius = true,
    iconStyle = true,
    buttonSize = true,
    iconSize = true,
    hoverStyle = true,
    tint = true,
    normalOpacity = true,
    hoverOpacity = true,
    pressedOpacity = true,
    disabledOpacity = true,
}

local POSITION_KEYS = {
    layoutPoint = true,
    layoutRelativePoint = true,
    layoutX = true,
    layoutY = true,
}

-- Blizzard's MicroButton methods whose native state updates rewrite the
-- button art. They are copied onto every button when it is created, so each
-- live instance is hooked once; OnEnter/OnLeave use one script hook that also
-- drives the owned bar's mouseover reveal.
local BUTTON_STATE_METHODS = { "SetPushed", "SetNormal", "OnEnable", "OnDisable" }

local textureStates = setmetatable({}, { __mode = "k" })
local alphaStates = setmetatable({}, { __mode = "k" })
local surfaceRecords = setmetatable({}, { __mode = "k" })
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

local function Clamp01(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function Near(first, second)
    return type(first) == "number" and type(second) == "number"
        and math.abs(first - second) <= 0.00001
end

-- Compares a stored { r, g, b, a } with four values.
local function SameVertex(color, r, g, b, a)
    return color ~= nil and Near(color[1], r) and Near(color[2], g)
        and Near(color[3], b) and Near(color[4], a)
end

local function StoreVertex(color, r, g, b, a)
    color[1], color[2], color[3], color[4] = r, g, b, a
end

local function ReadAlpha(region)
    local value = Call(region, "GetAlpha")
    if type(value) == "number" and Public(value) then return value end
    return nil
end

local function ReadVertex(region)
    local r, g, b, a = Call(region, "GetVertexColor")
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number"
        or not Public(r) or not Public(g) or not Public(b) or not Public(a) then
        return nil
    end
    return r, g, b, type(a) == "number" and a or 1
end

local function ReadDesaturated(region)
    local value = Call(region, "IsDesaturated")
    if type(value) == "boolean" and Public(value) then return value end
    return nil
end

local function Settings()
    local icons = NS.DB and NS.DB.icons
    local configured = icons and icons.microMenu
    if configured then return configured end
    return NS.Defaults and NS.Defaults.icons and NS.Defaults.icons.microMenu
end

local function IsListed(values, value)
    for index = 1, #(values or {}) do
        if values[index] == value then return true end
    end
    return false
end

local function BorderValue(value)
    if value == true then return 1 end
    if value == false then return 0 end
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 2 then return 2 end
    return math.floor(value + 0.5)
end

local function CanControl(target)
    -- Once the exact native MicroMenu is parented below the owned bar, WoW may
    -- report its non-secure descendants as implicitly protected. Cosmetic
    -- repainting is still permitted outside combat; explicitly protected or
    -- forbidden objects continue to fail closed in Safety.CanControl.
    return NS.Safety.CanControl(target, true) == true
end

local function NormalizeState(stateName)
    if stateName == "highlight" then return "hover" end
    if stateName == "pushed" then return "pressed" end
    if STATE_TOKENS[stateName] then return stateName end
    return "normal"
end

-- Icon colors -------------------------------------------------------------------------

local function ReadOriginalColor(original)
    if type(original) ~= "table" then return 1, 1, 1, 1 end
    local r, g, b, a
    if type(original.GetRGBA) == "function" then
        r, g, b, a = original:GetRGBA()
    end
    if type(r) ~= "number" then
        r, g, b, a = original.r or original[1], original.g or original[2],
            original.b or original[3], original.a or original[4]
    end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number"
        or not Public(r) or not Public(g) or not Public(b) or not Public(a) then
        return 1, 1, 1, 1
    end
    return Clamp01(r), Clamp01(g), Clamp01(b), Clamp01(type(a) == "number" and a or 1)
end

local function ClassColor(stateName)
    local r, g, b, a = NS.Theme.GetPlayerClassColor(false)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        r, g, b, a = 1, 1, 1, 1
    elseif type(a) ~= "number" then
        a = 1
    end
    if stateName == "hover" then
        r, g, b = r + (1 - r) * 0.25, g + (1 - g) * 0.25, b + (1 - b) * 0.25
    elseif stateName == "pressed" then
        r, g, b = r * 0.82, g * 0.82, b * 0.82
    elseif stateName == "disabled" then
        local gray = r * 0.299 + g * 0.587 + b * 0.114
        r, g, b = (r + gray) * 0.5, (g + gray) * 0.5, (b + gray) * 0.5
    end
    return Clamp01(r), Clamp01(g), Clamp01(b), Clamp01(a)
end

function MicroMenuSkin.GetIconColor(stateName, original)
    stateName = NormalizeState(stateName)
    local originalR, originalG, originalB, originalA = ReadOriginalColor(original)
    local settings = Settings() or {}
    local opacity = Clamp01(settings[STATE_OPACITY[stateName]] == nil
        and 1 or settings[STATE_OPACITY[stateName]])
    local tint = settings.tint or "native"
    if tint == "native" then
        return originalR, originalG, originalB, originalA * opacity
    end

    local r, g, b, a
    if tint == "class" then
        r, g, b, a = ClassColor(stateName)
        local _, _, _, tokenAlpha = NS.Theme.GetColor(STATE_TOKENS[stateName])
        if type(tokenAlpha) == "number" then a = a * tokenAlpha end
    else
        r, g, b, a = NS.Theme.GetColor(STATE_TOKENS[stateName])
        if tint == "monochrome" and type(r) == "number" and type(g) == "number"
            and type(b) == "number" then
            local luminance = Clamp01(r * 0.2126 + g * 0.7152 + b * 0.0722)
            r, g, b = luminance, luminance, luminance
        end
    end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        r, g, b, a = originalR, originalG, originalB, 1
    end
    return Clamp01(r), Clamp01(g), Clamp01(b),
        originalA * Clamp01(type(a) == "number" and a or 1) * opacity
end

-- Reversible texture and alpha states ---------------------------------------------------

local function ApplyTextureTint(button, region, stateName)
    if not region or not CanControl(button) then return false end
    local currentR, currentG, currentB, currentA = ReadVertex(region)
    if not currentR then return false end
    local currentDesaturated = ReadDesaturated(region)
    local state = textureStates[region]
    if not state then
        state = {
            button = button,
            original = { currentR, currentG, currentB, currentA },
            originalDesaturated = currentDesaturated,
        }
    else
        state.button = button
        -- Blizzard changed the color since we tinted it: that is the new native value.
        if state.applied and not SameVertex(state.applied, currentR, currentG, currentB, currentA)
            and not SameVertex(state.original, currentR, currentG, currentB, currentA) then
            StoreVertex(state.original, currentR, currentG, currentB, currentA)
        end
        if currentDesaturated ~= nil and state.appliedDesaturated ~= nil
            and currentDesaturated ~= state.appliedDesaturated
            and currentDesaturated ~= state.originalDesaturated then
            state.originalDesaturated = currentDesaturated
        end
    end

    local r, g, b, a = MicroMenuSkin.GetIconColor(stateName, state.original)
    local desiredDesaturated = state.originalDesaturated
    if (Settings() or {}).tint == "monochrome" and desiredDesaturated ~= nil then
        desiredDesaturated = true
    end
    if not (Near(currentR, r) and Near(currentG, g) and Near(currentB, b) and Near(currentA, a)) then
        region:SetVertexColor(r, g, b, a)
    end
    if desiredDesaturated ~= nil and currentDesaturated ~= desiredDesaturated then
        region:SetDesaturated(desiredDesaturated)
    end

    state.applied = state.applied or {}
    StoreVertex(state.applied, r, g, b, a)
    state.appliedDesaturated = desiredDesaturated
    if SameVertex(state.original, r, g, b, a)
        and (state.originalDesaturated == nil
            or state.originalDesaturated == desiredDesaturated) then
        textureStates[region] = nil
    else
        textureStates[region] = state
    end
    return true
end

local function RestoreTexture(region, state)
    if not CanControl(state.button) then return false end
    local r, g, b, a = ReadVertex(region)
    local original = state.original
    if r and state.applied and SameVertex(state.applied, r, g, b, a)
        and not SameVertex(original, r, g, b, a) then
        region:SetVertexColor(original[1], original[2], original[3], original[4])
    end
    local currentDesaturated = ReadDesaturated(region)
    if currentDesaturated ~= nil and state.appliedDesaturated ~= nil
        and currentDesaturated == state.appliedDesaturated
        and state.originalDesaturated ~= nil
        and currentDesaturated ~= state.originalDesaturated then
        region:SetDesaturated(state.originalDesaturated)
    end
    textureStates[region] = nil
    return true
end

local function FadeExact(button, region)
    if not region or not CanControl(button) then return false end
    local current = ReadAlpha(region)
    if current == nil then return false end
    local state = alphaStates[region]
    if not state then
        state = { button = button, original = current }
    else
        state.button = button
        if not Near(current, state.applied) and not Near(current, state.original) then
            state.original = current
        end
    end
    if not Near(current, 0) then region:SetAlpha(0) end
    state.applied = 0
    if Near(state.original, 0) then
        alphaStates[region] = nil
    else
        alphaStates[region] = state
    end
    return true
end

local function RestoreAlpha(region, state)
    if not CanControl(state.button) then return false end
    local current = ReadAlpha(region)
    if current ~= nil and Near(current, state.applied) and not Near(current, state.original) then
        region:SetAlpha(state.original)
    end
    alphaStates[region] = nil
    return true
end

-- Clearing entries during pairs() is allowed; nothing is added meanwhile.
local function RestoreButtonTextures(button)
    local success = true
    for region, state in pairs(textureStates) do
        if state.button == button then
            success = RestoreTexture(region, state) and success
        end
    end
    return success
end

local function RestoreButtonAlphas(button)
    local success = true
    for region, state in pairs(alphaStates) do
        if state.button == button then
            success = RestoreAlpha(region, state) and success
        end
    end
    return success
end

-- Surfaces -------------------------------------------------------------------------------

local BAR_ROLES = {
    forever = "microBarForever",
    modern = "microBarModern",
    midnightDark = "microBarDark",
}

local function SurfaceSpec(role, settings, isBar)
    if isBar then
        role = BAR_ROLES[settings.barMaterial] or role
    end
    local spec = {
        role = role,
        radius = tonumber(settings.radius) or 6,
        border = BorderValue(isBar and settings.barBorder or settings.buttonBorder),
        inset = isBar and -2 or 2,
        pillHeight = 32,
        slice = true,
    }
    if settings.shape == "global" or settings.shape == nil then
        spec.useControlShape = true
    else
        spec.shape = settings.shape
    end
    return spec
end

local function RestoreSurface(target)
    local record = surfaceRecords[target]
    if not record then return true end
    local current = NS.Registry.GetSurface(target)
    if not current or current.spec ~= record.appliedSpec then
        surfaceRecords[target] = nil
        return true
    end
    local success
    if record.previous then
        success = NS.Surface.Attach(target, record.previous.spec) ~= nil
        if success then
            success = NS.Surface.SetVisible(target, record.previous.visible ~= false) ~= false
        end
    else
        success = NS.Surface.SetVisible(target, false) ~= false
    end
    if success then surfaceRecords[target] = nil end
    return success
end

local function ApplySurface(target, role, background, border, settings, isBar,
    allowImplicitProtected)
    if background ~= true and BorderValue(border) == 0 then
        return RestoreSurface(target)
    end
    if not NS.Safety.CanCreateRegions(target, allowImplicitProtected == true) then
        return false
    end

    local existing = NS.Registry.GetSurface(target)
    local record = surfaceRecords[target]
    if not record then
        record = {
            previous = existing and { spec = existing.spec, visible = existing.visible } or nil,
        }
    elseif existing and existing.spec ~= record.appliedSpec then
        record.previous = { spec = existing.spec, visible = existing.visible }
    end

    local spec = SurfaceSpec(role, settings, isBar)
    spec.fillVisible = background == true
    spec.allowImplicitProtected = allowImplicitProtected == true
    if not NS.Surface.Attach(target, spec) then return false end
    record.appliedSpec = spec
    surfaceRecords[target] = record
    return true
end

-- Root and buttons -----------------------------------------------------------------------

local function ResolveRoot(requested)
    local globalRoot = _G.MicroMenu
    if globalRoot then
        if requested and requested ~= globalRoot then return nil, "unexpected-root" end
        return globalRoot
    end
    if not requested then return nil, "missing" end
    if Call(requested, "GetName") ~= "MicroMenu" then return nil, "unexpected-root" end
    return requested
end

local function ResolveButton(name, root)
    local button = _G[name]
    if not button then return nil end
    if HasMethod(button, "GetObjectType") and Call(button, "GetObjectType") ~= "Button" then
        return nil
    end
    if Call(button, "GetParent") ~= root then return nil end
    return button
end

local function PublicCall(button, method)
    local value = Call(button, method)
    if Public(value) then return value end
end

local function ResolveVisualState(button)
    if PublicCall(button, "IsEnabled") == false then return "disabled" end
    if PublicCall(button, "GetButtonState") == "PUSHED" then return "pressed" end
    if PublicCall(button, "IsMouseOver") == true then return "hover" end
    return "normal"
end

local function ApplyCleanButton(button, buttonName, settings)
    local success = RestoreButtonTextures(button)
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
    success = RestoreSurface(button) and success
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

local function ApplyNativeButton(button, settings)
    local success = NS.MicroMenuVisual.Restore(button)
    success = RestoreButtonAlphas(button) and success
    success = RestoreButtonTextures(button) and success

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
                success = ApplyTextureTint(button, region, spec.state) and success
            end
        end
    end

    if extraPlate then
        return ApplySurface(button, "microButton", settings.buttonBackground,
            settings.buttonBorder, settings, false, true) and success
    end
    return RestoreSurface(button) and success
end

local function ApplyButton(button, buttonName, settings)
    if not CanControl(button) then return false end
    -- Blizzard icons use the live native textures. Copying their atlas into a
    -- smaller overlay loses portrait, state and client-specific artwork.
    if settings.iconStyle ~= "blizzard" and settings.iconStyle ~= "blizzardIcons" then
        return ApplyCleanButton(button, buttonName, settings)
    end
    return ApplyNativeButton(button, settings)
end

local function RestoreButton(button)
    local success = RestoreButtonTextures(button)
    success = RestoreButtonAlphas(button) and success
    success = NS.MicroMenuVisual.Restore(button) and success
    return RestoreSurface(button) and success
end

-- Hooks ----------------------------------------------------------------------------------

local function OnButtonVisualLifecycle(button)
    if NS.IsCombatLocked() or visualSuspended or transitionInProgress
        or not MicroMenuSkin.active then
        return
    end
    local buttonName = activeButtons[button]
    local settings = buttonName and Settings()
    if settings then ApplyButton(button, buttonName, settings) end
end

local function OnButtonEnter(button)
    OnButtonVisualLifecycle(button)
    NS.OwnedMicroBar.HoverEnter()
end

local function OnButtonLeave(button)
    OnButtonVisualLifecycle(button)
    NS.OwnedMicroBar.HoverLeave()
end

local layoutRefreshPending = false

local function FlushButtonLayout()
    layoutRefreshPending = false
    if NS.IsCombatLocked() or visualSuspended or transitionInProgress
        or not MicroMenuSkin.active then
        return
    end
    MicroMenuSkin.RefreshActive()
end

-- Every MicroButton's OnShow/OnHide calls MicroMenuContainer:Layout() (all
-- clients), so one hook on the container sees each visibility change. Repeated
-- signals within a frame collapse into one deferred refresh.
local function OnContainerLayout()
    if NS.IsCombatLocked() or visualSuspended or transitionInProgress
        or not MicroMenuSkin.active or layoutRefreshPending then
        return
    end
    layoutRefreshPending = true
    local timer = _G.C_Timer
    if timer and type(timer.After) == "function" then
        timer.After(0, FlushButtonLayout)
    else
        FlushButtonLayout()
    end
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

local function OnThemeChanged(_, domain)
    if MicroMenuSkin.active and (domain == "color" or domain == "theme"
        or domain == "appearance" or domain == "geometry"
        or domain == "profile" or domain == "adapter") then
        ApplyNow(activeRoot, activeOwner)
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
    MicroMenuSkin.active = true
    desiredActive = true
    desiredRoot = root
    desiredOwner = owner
    EnsureListener()
    return true, partial and "partial" or "applied"
end

-- transitionInProgress keeps the native hooks quiet while this adapter itself
-- rewrites the buttons; each transition clears it again when it finishes.
ApplyNow = function(requestedRoot, owner)
    if NS.IsCombatLocked() then return false, "combat" end
    local root, reason = ResolveRoot(requestedRoot)
    if not root then return false, reason end
    local settings = Settings()
    if not settings then return false, "settings" end

    transitionInProgress = true
    local success, result = ApplyResolved(root, owner, settings)
    transitionInProgress = false
    return success, result
end

local function DisableResolved()
    local partial = false
    for region, state in pairs(textureStates) do
        if not RestoreTexture(region, state) then partial = true end
    end
    for region, state in pairs(alphaStates) do
        if not RestoreAlpha(region, state) then partial = true end
    end
    for button in pairs(activeButtons) do
        if not NS.MicroMenuVisual.Restore(button) then partial = true end
    end
    for target in pairs(surfaceRecords) do
        if not RestoreSurface(target) then partial = true end
    end
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
    transitionInProgress = true
    local success, result = DisableResolved()
    transitionInProgress = false
    return success, result
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

function MicroMenuSkin.RefreshActive()
    if not MicroMenuSkin.active then return false, "inactive" end
    desiredActive, desiredRoot, desiredOwner = true, activeRoot, activeOwner
    if NS.IsCombatLocked() then return DeferDesired() end
    return ApplyNow(activeRoot, activeOwner)
end

-- Settings -------------------------------------------------------------------------------

local function MutableSettings()
    if not NS.DB then return nil end
    NS.DB.icons = NS.DB.icons or {}
    if not NS.DB.icons.microMenu then
        local defaults = NS.Defaults and NS.Defaults.icons and NS.Defaults.icons.microMenu
        if not defaults then return nil end
        NS.DB.icons.microMenu = {}
        for key, value in pairs(defaults) do NS.DB.icons.microMenu[key] = value end
    end
    return NS.DB.icons.microMenu
end

local function RefreshAfterSetting()
    if not MicroMenuSkin.active then return true, "stored" end
    return ApplyNow(activeRoot, activeOwner)
end

-- Option validators: (value, settings) -> accepted, normalized value.
local function BooleanOption(value)
    return type(value) == "boolean", value
end

local function ListedOption(listName)
    return function(value) return IsListed(NS[listName], value), value end
end

local function RangeOption(minimum, maximum, integer)
    return function(value)
        value = tonumber(value)
        if not value or value < minimum or value > maximum then return false end
        return true, integer and math.floor(value + 0.5) or value
    end
end

local BorderRange = RangeOption(0, 2, true)
local ButtonSizeRange = RangeOption(20, 32, true)

local function BorderOption(value)
    if type(value) == "boolean" then value = value and 1 or 0 end
    return BorderRange(value)
end

local function OpacityOption(value)
    value = tonumber(value)
    return value ~= nil, value and Clamp01(value)
end

local optionValidators = {
    layoutMode = ListedOption("MicroMenuLayoutModes"),
    visibility = ListedOption("MicroMenuVisibilityModes"),
    locked = BooleanOption,
    orientation = ListedOption("MicroMenuOrientations"),
    growth = ListedOption("MicroMenuGrowthModes"),
    buttonsPerLine = RangeOption(1, #BUTTON_NAMES, true),
    spacing = RangeOption(-8, 16, true),
    scale = RangeOption(0.5, 1.5, false),
    padding = RangeOption(0, 16, true),
    layoutPoint = ListedOption("MicroMenuPoints"),
    layoutRelativePoint = ListedOption("MicroMenuPoints"),
    layoutX = RangeOption(-4096, 4096, true),
    layoutY = RangeOption(-4096, 4096, true),
    positionPreset = function(value)
        return value == "custom" or (NS.MicroMenuPositionPresets
            and NS.MicroMenuPositionPresets[value]) ~= nil, value
    end,
    barBackground = BooleanOption,
    barBorder = BorderOption,
    barMaterial = ListedOption("MicroMenuBarMaterials"),
    buttonBackground = BooleanOption,
    buttonBorder = BorderOption,
    shape = ListedOption("MicroMenuShapes"),
    radius = function(value)
        value = tonumber(value)
        return IsListed(NS.GeometryRadii, value), value
    end,
    iconStyle = ListedOption("MicroMenuIconStyles"),
    buttonSize = function(value, settings)
        local accepted
        accepted, value = ButtonSizeRange(value)
        if accepted and tonumber(settings.iconSize) and settings.iconSize > value - 4 then
            settings.iconSize = value - 4
        end
        return accepted, value
    end,
    iconSize = function(value, settings)
        local maximum = math.min(28, (tonumber(settings.buttonSize) or 28) - 4)
        return RangeOption(10, maximum, true)(value)
    end,
    hoverStyle = ListedOption("MicroMenuHoverStyles"),
    tint = ListedOption("MicroMenuTintModes"),
    normalOpacity = OpacityOption,
    hoverOpacity = OpacityOption,
    pressedOpacity = OpacityOption,
    disabledOpacity = OpacityOption,
}
for _, condition in ipairs(NS.MicroMenuLoadConditions) do
    optionValidators[condition[1]] = BooleanOption
end

function MicroMenuSkin.ApplyPreset(presetName)
    if NS.IsCombatLocked() then return false, "combat" end
    if presetName == "recommended" or presetName == "default" then
        presetName = (NS.Defaults and NS.Defaults.icons
            and NS.Defaults.icons.microMenu and NS.Defaults.icons.microMenu.preset) or "forever"
    end
    local preset = NS.MicroMenuPresetValues and NS.MicroMenuPresetValues[presetName]
    local settings = MutableSettings()
    if not preset or not settings then return false, "invalid preset" end
    for key in pairs(optionValidators) do
        if preset[key] ~= nil then settings[key] = preset[key] end
    end
    settings.preset = presetName
    return RefreshAfterSetting()
end

function MicroMenuSkin.SetOption(key, value)
    if NS.IsCombatLocked() then return false, "combat" end
    if key == "preset" then return MicroMenuSkin.ApplyPreset(value) end
    local validate = optionValidators[key]
    if not validate then return false, "unknown option" end
    local settings = MutableSettings()
    if not settings then return false, "settings" end
    local accepted
    accepted, value = validate(value, settings)
    if not accepted then return false, "invalid value" end

    settings[key] = value
    if VISUAL_OPTION_KEYS[key] then
        settings.preset = "custom"
    elseif key == "layoutMode" and settings.preset == "blizzard" and value ~= "blizzard" then
        settings.preset = "custom"
    elseif POSITION_KEYS[key] then
        settings.positionPreset = "custom"
    end
    return RefreshAfterSetting()
end

function MicroMenuSkin.ResetRecommended()
    if NS.IsCombatLocked() then return false, "combat" end
    local defaults = NS.Defaults and NS.Defaults.icons
        and NS.Defaults.icons.microMenu
    local settings = MutableSettings()
    if not defaults or not settings then return false, "settings" end
    for key in pairs(optionValidators) do
        if defaults[key] ~= nil then settings[key] = defaults[key] end
    end
    settings.preset = defaults.preset
    return RefreshAfterSetting()
end

function MicroMenuSkin.SetPositionPreset(presetName)
    if NS.IsCombatLocked() then return false, "combat" end
    local preset = NS.MicroMenuPositionPresets
        and NS.MicroMenuPositionPresets[presetName]
    local settings = MutableSettings()
    if not preset or not settings then return false, "invalid preset" end
    settings.layoutPoint = preset.point
    settings.layoutRelativePoint = preset.relativePoint or preset.point
    settings.layoutX = preset.x or 0
    settings.layoutY = preset.y or 0
    settings.positionPreset = presetName
    return RefreshAfterSetting()
end
