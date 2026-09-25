local _, NS = ...

-- Dedicated, bounded Retail Micro Menu skinning. Blizzard keeps ownership of
-- layout, scripts, button state changes and semantic regions; this adapter
-- only decorates the exact current MicroMenu root/button set outside combat.
local MicroMenuSkin = {
    active = false,
}
NS.MicroMenuSkin = MicroMenuSkin

local BUTTON_NAMES = NS.Client and NS.Client.isForever and {
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

local OPTION_KEYS = {
    layoutMode = true,
    visibility = true,
    locked = true,
    orientation = true,
    growth = true,
    buttonsPerLine = true,
    spacing = true,
    scale = true,
    padding = true,
    layoutPoint = true,
    layoutRelativePoint = true,
    layoutX = true,
    layoutY = true,
    positionPreset = true,
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

local textureStates = setmetatable({}, { __mode = "k" })
local alphaStates = setmetatable({}, { __mode = "k" })
local surfaceRecords = setmetatable({}, { __mode = "k" })
local activeButtons = setmetatable({}, { __mode = "k" })
local listenerOwner = {}
local listenerRegistered = false
local activeRoot
local activeOwner
local desiredActive = false
local desiredRoot
local desiredOwner
local DEFER_KEY = "micro-menu:state"
local visualSuspended = false
local visualHooks = setmetatable({}, { __mode = "k" })
local transitionInProgress = false

local function Accessible(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then
        if type(canaccessvalue) ~= "function" or not canaccessvalue(value) then
            return nil
        end
    end
    return value
end

local function IsCombatLocked()
    return type(NS.IsCombatLocked) == "function" and NS.IsCombatLocked() == true
end

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

local function SameVertex(first, second)
    return first and second
        and Near(first[1], second[1])
        and Near(first[2], second[2])
        and Near(first[3], second[3])
        and Near(first[4], second[4])
end

-- Pass the operands through pcall; do not allocate a capturing closure per read.
local function IndexMember(object, key)
    return object[key]
end

local function ReadMember(target, key)
    if not target then return nil end
    local ok, value = pcall(IndexMember, target, key)
    return ok and value or nil
end

local function CallMethod(target, methodName, ...)
    local method = ReadMember(target, methodName)
    if type(method) ~= "function" then return false end
    return pcall(method, target, ...)
end

local function ReadGlobal(name)
    local ok, value = pcall(function() return _G[name] end)
    return ok and value or nil
end

local function ReadAlpha(region)
    local ok, value = CallMethod(region, "GetAlpha")
    if not ok then return nil end
    value = Accessible(value)
    return type(value) == "number" and value or nil
end

local function ReadVertex(region)
    local ok, r, g, b, a = CallMethod(region, "GetVertexColor")
    if not ok then return nil end
    r, g, b, a = Accessible(r), Accessible(g), Accessible(b), Accessible(a)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end
    return { r, g, b, type(a) == "number" and a or 1 }
end

local function ReadDesaturated(region)
    local ok, value = CallMethod(region, "IsDesaturated")
    if not ok then return nil end
    value = Accessible(value)
    return type(value) == "boolean" and value or nil
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
    return NS.Safety and NS.Safety.CanControl(target, true) == true
end

local function CanCreateRegions(target, allowImplicitProtected)
    return NS.Safety
        and NS.Safety.CanCreateRegions(target, allowImplicitProtected == true) == true
end

local function NormalizeState(stateName)
    if stateName == "highlight" then return "hover" end
    if stateName == "pushed" then return "pressed" end
    if STATE_TOKENS[stateName] then return stateName end
    return "normal"
end

local function ReadOriginalColor(original)
    if type(original) ~= "table" then return 1, 1, 1, 1 end
    local getRGBA = ReadMember(original, "GetRGBA")
    local r, g, b, a
    if type(getRGBA) == "function" then
        local ok
        ok, r, g, b, a = pcall(getRGBA, original)
        if not ok then r, g, b, a = nil, nil, nil, nil end
    end
    if type(r) ~= "number" then
        local ok
        ok, r, g, b, a = pcall(function()
            return original.r or original[1], original.g or original[2],
                original.b or original[3], original.a or original[4]
        end)
        if not ok then r, g, b, a = nil, nil, nil, nil end
    end
    r, g, b, a = Accessible(r), Accessible(g), Accessible(b), Accessible(a)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return 1, 1, 1, 1
    end
    return Clamp01(r), Clamp01(g), Clamp01(b), Clamp01(type(a) == "number" and a or 1)
end

local function ClassColor(stateName)
    local r, g, b, a = 1, 1, 1, 1
    if NS.Theme and type(NS.Theme.GetPlayerClassColor) == "function" then
        local ok, cr, cg, cb, ca = pcall(NS.Theme.GetPlayerClassColor, false)
        if ok and type(cr) == "number" and type(cg) == "number" and type(cb) == "number" then
            r, g, b, a = cr, cg, cb, type(ca) == "number" and ca or 1
        end
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
        if NS.Theme and type(NS.Theme.GetColor) == "function" then
            local ok, _, _, _, tokenAlpha = pcall(NS.Theme.GetColor, STATE_TOKENS[stateName])
            if ok and type(tokenAlpha) == "number" then a = a * tokenAlpha end
        end
    elseif tint == "monochrome" and NS.Theme
        and type(NS.Theme.GetColor) == "function" then
        local ok
        ok, r, g, b, a = pcall(NS.Theme.GetColor, STATE_TOKENS[stateName])
        if not ok then r, g, b, a = nil, nil, nil, nil end
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            local luminance = Clamp01(r * 0.2126 + g * 0.7152 + b * 0.0722)
            r, g, b = luminance, luminance, luminance
        end
    elseif NS.Theme and type(NS.Theme.GetColor) == "function" then
        local ok
        ok, r, g, b, a = pcall(NS.Theme.GetColor, STATE_TOKENS[stateName])
        if not ok then r, g, b, a = nil, nil, nil, nil end
    end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        r, g, b, a = originalR, originalG, originalB, 1
    end
    return Clamp01(r), Clamp01(g), Clamp01(b),
        originalA * Clamp01(type(a) == "number" and a or 1) * opacity
end

local function ApplyTextureTint(button, region, stateName)
    if not region or not CanControl(button) then return false end
    local current = ReadVertex(region)
    if not current then return false end
    local currentDesaturated = ReadDesaturated(region)
    local state = textureStates[region]
    if not state then
        state = {
            button = button,
            original = { current[1], current[2], current[3], current[4] },
            originalDesaturated = currentDesaturated,
        }
    else
        state.button = button
        if state.applied and not SameVertex(current, state.applied)
            and not SameVertex(current, state.original) then
            state.original = { current[1], current[2], current[3], current[4] }
        end
        if currentDesaturated ~= nil and state.appliedDesaturated ~= nil
            and currentDesaturated ~= state.appliedDesaturated
            and currentDesaturated ~= state.originalDesaturated then
            state.originalDesaturated = currentDesaturated
        end
    end

    local r, g, b, a = MicroMenuSkin.GetIconColor(stateName, state.original)
    local desired = { r, g, b, a }
    local tint = (Settings() or {}).tint or "native"
    local desiredDesaturated = state.originalDesaturated
    if tint == "monochrome" and desiredDesaturated ~= nil then
        desiredDesaturated = true
    end

    if not SameVertex(current, desired) then
        local ok = CallMethod(region, "SetVertexColor", r, g, b, a)
        if not ok then return false end
    end
    if desiredDesaturated ~= nil and currentDesaturated ~= desiredDesaturated then
        local ok = CallMethod(region, "SetDesaturated", desiredDesaturated)
        if not ok then return false end
    end

    state.applied = desired
    state.appliedDesaturated = desiredDesaturated
    if SameVertex(state.original, desired)
        and (state.originalDesaturated == nil
            or state.originalDesaturated == desiredDesaturated) then
        textureStates[region] = nil
    else
        textureStates[region] = state
    end
    return true
end

local function RestoreTexture(region, state)
    if not state or not CanControl(state.button) then return false end
    local current = ReadVertex(region)
    local success = true
    if current and state.applied and SameVertex(current, state.applied)
        and not SameVertex(current, state.original) then
        success = CallMethod(region, "SetVertexColor",
            state.original[1], state.original[2], state.original[3], state.original[4]) and success
    end
    local currentDesaturated = ReadDesaturated(region)
    if currentDesaturated ~= nil and state.appliedDesaturated ~= nil
        and currentDesaturated == state.appliedDesaturated
        and state.originalDesaturated ~= nil
        and currentDesaturated ~= state.originalDesaturated then
        success = CallMethod(region, "SetDesaturated", state.originalDesaturated) and success
    end
    textureStates[region] = nil
    return success
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
    if not Near(current, 0) and not CallMethod(region, "SetAlpha", 0) then
        return false
    end
    state.applied = 0
    if Near(state.original, 0) then
        alphaStates[region] = nil
    else
        alphaStates[region] = state
    end
    return true
end

local function RestoreAlpha(region, state)
    if not state or not CanControl(state.button) then return false end
    local current = ReadAlpha(region)
    local success = true
    if current ~= nil and Near(current, state.applied) and not Near(current, state.original) then
        success = CallMethod(region, "SetAlpha", state.original)
    end
    alphaStates[region] = nil
    return success
end

local function SurfaceSpec(role, settings, isBar)
    local shape = settings.shape
    if isBar then
        if settings.barMaterial == "forever" then
            role = "microBarForever"
        elseif settings.barMaterial == "modern" then
            role = "microBarModern"
        elseif settings.barMaterial == "midnightDark" then
            role = "microBarDark"
        end
    end
    local spec = {
        role = role,
        radius = tonumber(settings.radius) or 6,
        border = BorderValue(isBar and settings.barBorder or settings.buttonBorder),
        inset = isBar and -2 or 2,
        pillHeight = 32,
        slice = true,
    }
    if shape == "global" or shape == nil then
        spec.useControlShape = true
    else
        spec.shape = shape
    end
    return spec
end

local function RestoreSurface(target)
    local record = surfaceRecords[target]
    if not record then return true end
    local current = NS.Registry and NS.Registry.GetSurface(target)
    if not current or current.spec ~= record.appliedSpec then
        surfaceRecords[target] = nil
        return true
    end
    local success = true
    if record.previous then
        local restored = NS.Surface.Attach(target, record.previous.spec)
        success = restored ~= nil
        if restored then
            local visible = record.previous.visible ~= false
            local ok = NS.Surface.SetVisible(target, visible)
            success = ok ~= false and success
        end
    else
        local ok = NS.Surface.SetVisible(target, false)
        success = ok ~= false
    end
    if success then surfaceRecords[target] = nil end
    return success
end

local function ApplySurface(target, role, background, border, settings, isBar,
    allowImplicitProtected)
    border = BorderValue(border)
    if background ~= true and border == 0 then
        return RestoreSurface(target)
    end
    if not NS.Surface or not NS.Registry
        or not CanCreateRegions(target, allowImplicitProtected) then
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
    local surface = NS.Surface.Attach(target, spec)
    if not surface then return false end
    record.appliedSpec = spec
    surfaceRecords[target] = record

    return true
end

local function ResolveRoot(requested)
    local globalRoot = ReadGlobal("MicroMenu")
    if globalRoot then
        if requested and requested ~= globalRoot then return nil, "unexpected-root" end
        return globalRoot
    end
    if not requested then return nil, "missing" end
    local ok, name = CallMethod(requested, "GetName")
    if not ok or Accessible(name) ~= "MicroMenu" then return nil, "unexpected-root" end
    return requested
end

local function ResolveButton(name, root)
    local button = ReadGlobal(name)
    if not button then return nil end
    local objectType = ReadMember(button, "GetObjectType")
    if type(objectType) == "function" then
        local ok, value = pcall(objectType, button)
        if not ok or Accessible(value) ~= "Button" then return nil end
    end
    local ok, parent = CallMethod(button, "GetParent")
    if not ok or parent ~= root then return nil end
    return button
end

local function CollectKeys(map, button, inverseSet)
    local result = {}
    for key, state in pairs(map) do
        if (button and state.button == button)
            or (inverseSet and state.button and not inverseSet[state.button]) then
            result[#result + 1] = key
        end
    end
    return result
end

local function RestoreButtonTextures(button)
    local success = true
    local textures = CollectKeys(textureStates, button)
    for index = 1, #textures do
        local region = textures[index]
        success = RestoreTexture(region, textureStates[region]) and success
    end
    return success
end

local function RestoreButtonAlphas(button)
    local success = true
    local alphas = CollectKeys(alphaStates, button)
    for index = 1, #alphas do
        local region = alphas[index]
        success = RestoreAlpha(region, alphaStates[region]) and success
    end
    return success
end

local function ResolveVisualState(button)
    local ok, enabled = CallMethod(button, "IsEnabled")
    if ok then enabled = Accessible(enabled) else enabled = nil end
    if enabled == false then return "disabled" end

    local state
    ok, state = CallMethod(button, "GetButtonState")
    if ok then state = Accessible(state) else state = nil end
    if state == "PUSHED" then return "pressed" end

    local mouseOver
    ok, mouseOver = CallMethod(button, "IsMouseOver")
    if ok then mouseOver = Accessible(mouseOver) else mouseOver = nil end
    if mouseOver == true then return "hover" end
    return "normal"
end

local function ApplyButton(button, buttonName, settings)
    if not CanControl(button) then return false end
    local success = true
    -- Blizzard icons use the live native textures. Copying their atlas into a
    -- smaller overlay loses portrait, state and client-specific artwork.
    local clean = settings.iconStyle ~= "blizzard"
        and settings.iconStyle ~= "blizzardIcons"

    if clean then
        success = RestoreButtonTextures(button) and success
        for index = 1, #CLEAN_HIDDEN_MEMBERS do
            local member = CLEAN_HIDDEN_MEMBERS[index]
            local region = ReadMember(button, member)
            if region then
                success = FadeExact(button, region) and success
            end
        end
        for index = 1, #TEXTURE_STATES do
            local spec = TEXTURE_STATES[index]
            local ok, region = CallMethod(button, spec.getter)
            if ok and region then success = FadeExact(button, region) and success end
        end
        success = RestoreSurface(button) and success
        if not NS.MicroMenuVisual
            or not NS.MicroMenuVisual.Apply(button, buttonName, settings,
                ResolveVisualState(button)) then
            success = false
        end
        return success
    end

    if NS.MicroMenuVisual then
        success = NS.MicroMenuVisual.Restore(button) and success
    end
    success = RestoreButtonAlphas(button) and success
    success = RestoreButtonTextures(button) and success

    -- Full Blizzard keeps the original button background. Blizzard icons keep
    -- the original icon and state textures, while the Suite bar supplies the
    -- surrounding frame.
    local extraPlate = settings.buttonBackground == true
        or BorderValue(settings.buttonBorder) > 0
    if extraPlate or settings.iconStyle == "blizzardIcons" then
        local background = ReadMember(button, "Background")
        local pushedBackground = ReadMember(button, "PushedBackground")
        if background then success = FadeExact(button, background) and success end
        if pushedBackground then success = FadeExact(button, pushedBackground) and success end
    end

    local tintRequested = settings.tint ~= "native"
        or (tonumber(settings.normalOpacity) or 1) < 1
        or (tonumber(settings.hoverOpacity) or 1) < 1
        or (tonumber(settings.pressedOpacity) or 1) < 1
        or (tonumber(settings.disabledOpacity) or 1) < 1
    if tintRequested then
        for index = 1, #TEXTURE_STATES do
            local spec = TEXTURE_STATES[index]
            local ok, region = CallMethod(button, spec.getter)
            if ok and region then
                success = ApplyTextureTint(button, region, spec.state) and success
            end
        end
    end

    if extraPlate then
        success = ApplySurface(button, "microButton", settings.buttonBackground,
            settings.buttonBorder, settings, false, true) and success
    else
        success = RestoreSurface(button) and success
    end
    return success
end

local BUTTON_VISUAL_HOOK_METHODS = {
    "OnEnter", "OnLeave", "SetPushed", "SetNormal",
    "OnEnable", "OnDisable", "UpdateTabard",
}

local BUTTON_LAYOUT_HOOK_METHODS = { "OnShow", "OnHide" }

local function OnButtonVisualLifecycle(button)
    if IsCombatLocked() or visualSuspended or transitionInProgress
        or not MicroMenuSkin.active or not button then
        return
    end
    local buttonName = activeButtons[button]
    local settings = buttonName and Settings() or nil
    if settings then ApplyButton(button, buttonName, settings) end
end

local layoutRefreshPending = false
local function FlushButtonLayout()
    layoutRefreshPending = false
    if IsCombatLocked() or visualSuspended or transitionInProgress
        or not MicroMenuSkin.active then
        return
    end
    MicroMenuSkin.RefreshActive()
end
local function OnButtonLayoutLifecycle()
    if IsCombatLocked() or visualSuspended or transitionInProgress
        or not MicroMenuSkin.active or layoutRefreshPending then return end
    layoutRefreshPending = true
    local timer = _G.C_Timer
    if timer and type(timer.After) == "function" then
        timer.After(0, FlushButtonLayout)
    else
        FlushButtonLayout()
    end
end

local function EnsureButtonHooks(button, buttonName)
    if type(hooksecurefunc) ~= "function" then return false end
    local hooks = visualHooks[button]
    if not hooks then
        hooks = {}
        visualHooks[button] = hooks
    end
    local found = false
    for index = 1, #BUTTON_VISUAL_HOOK_METHODS do
        local methodName = BUTTON_VISUAL_HOOK_METHODS[index]
        local key = "visual:" .. methodName
        local methodExists = type(ReadMember(button, methodName)) == "function"
        if not methodExists and (methodName ~= "UpdateTabard"
            or buttonName == "GuildMicroButton") then
            return false
        end
        if methodExists then
            found = true
            if not hooks[key] then
                local ok = pcall(function()
                    hooksecurefunc(button, methodName, OnButtonVisualLifecycle)
                end)
                if not ok then return false end
                hooks[key] = true
            end
        end
    end
    for index = 1, #BUTTON_LAYOUT_HOOK_METHODS do
        local methodName = BUTTON_LAYOUT_HOOK_METHODS[index]
        local key = "layout:" .. methodName
        local methodExists = type(ReadMember(button, methodName)) == "function"
        if not methodExists then
            return false
        end
        if methodExists then
            found = true
            if not hooks[key] then
                local ok = pcall(function()
                    hooksecurefunc(button, methodName, OnButtonLayoutLifecycle)
                end)
                if not ok then return false end
                hooks[key] = true
            end
        end
    end
    return found
end

local function EnsureVisualHooks(buttons)
    local success = true
    local found = false
    for button, buttonName in pairs(buttons) do
        found = true
        success = EnsureButtonHooks(button, buttonName) and success
    end
    return found and success
end

local function RestoreButton(button)
    local success = true
    success = RestoreButtonTextures(button) and success
    success = RestoreButtonAlphas(button) and success
    if NS.MicroMenuVisual then
        success = NS.MicroMenuVisual.Restore(button) and success
    end
    success = RestoreSurface(button) and success
    return success
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

local function RemoveListener()
    if listenerRegistered and NS.Registry then
        NS.Registry.RemoveListener(listenerOwner)
    end
    listenerRegistered = false
end

local ApplyNow

local function EnsureListener()
    if listenerRegistered or not NS.Registry then return end
    NS.Registry.AddListener(listenerOwner, function(_, domain)
        if MicroMenuSkin.active and (domain == "color" or domain == "theme"
            or domain == "appearance" or domain == "geometry"
            or domain == "profile" or domain == "adapter") then
            ApplyNow(activeRoot, activeOwner)
        end
    end)
    listenerRegistered = true
end

local function ApplyResolved(root, owner, settings)
    local partial = false
    local currentButtons = setmetatable({}, { __mode = "k" })
    for index = 1, #BUTTON_NAMES do
        local buttonName = BUTTON_NAMES[index]
        local button = ResolveButton(buttonName, root)
        if button then
            currentButtons[button] = buttonName
            if NS.MicroMenuVisual
                and type(NS.MicroMenuVisual.Prepare) == "function"
                and not NS.MicroMenuVisual.Prepare(button, buttonName, settings) then
                partial = true
            end
            -- Native artwork can still use MSKIN button surfaces later. Seed
            -- those regions before an owned layout reparents the button,
            -- independent of the currently selected icon artwork.
            if not ApplySurface(button, "microButton",
                    true, settings.buttonBorder,
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
    if NS.OwnedMicroBar and NS.OwnedMicroBar.TrackHoverButtons then
        NS.OwnedMicroBar.TrackHoverButtons(currentButtons)
    end

    local barTarget, ownedTarget = root, false
    local skipBarSurface = false
    if NS.OwnedMicroBar and type(NS.OwnedMicroBar.Apply) == "function" then
        local target, layoutReason = NS.OwnedMicroBar.Apply(root, settings)
        if layoutReason == "blizzard-override" then
            skipBarSurface = true
        elseif target then
            barTarget = target
            ownedTarget = target ~= root
        else
            partial = true
        end
        local ownedBar = type(NS.OwnedMicroBar.GetFrames) == "function"
            and NS.OwnedMicroBar.GetFrames() or nil
        local inactiveTarget = ownedTarget and root or ownedBar
        if inactiveTarget and inactiveTarget ~= barTarget then
            RestoreSurface(inactiveTarget)
        end
    end
    -- Camelot's MicroMenu root has its own wide action-bar art. Its border
    -- extends past our compact owned shell, producing a second frame.
    if NS.Client and NS.Client.isForever and ownedTarget
        and settings.iconStyle ~= "blizzard" then
        local borderArt = ReadMember(root, "BorderArt")
        local backgroundArt = ReadMember(root, "BackgroundArt")
        if borderArt then partial = not FadeExact(root, borderArt) or partial end
        if backgroundArt then partial = not FadeExact(root, backgroundArt) or partial end
    elseif not RestoreButtonAlphas(root) then
        partial = true
    end
    if skipBarSurface then
        if not RestoreSurface(root) then partial = true end
    elseif not ApplySurface(barTarget, "microBar", settings.barBackground,
        settings.barBorder, settings, true, ownedTarget) then
        partial = true
    end

    visualSuspended = skipBarSurface
    for button, buttonName in pairs(currentButtons) do
        if skipBarSurface then
            if not RestoreButton(button) then partial = true end
        elseif not ApplyButton(button, buttonName, settings) then
            partial = true
        end
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

ApplyNow = function(requestedRoot, owner)
    if IsCombatLocked() then return false, "combat" end
    if transitionInProgress then return false, "busy" end
    local root, reason = ResolveRoot(requestedRoot)
    if not root then return false, reason end
    local settings = Settings()
    if not settings then return false, "settings" end

    transitionInProgress = true
    local ok, success, result = pcall(ApplyResolved, root, owner, settings)
    transitionInProgress = false
    if not ok then error(success, 0) end
    return success, result
end

local function DisableResolved()
    local partial = false

    local textures = {}
    for region in pairs(textureStates) do textures[#textures + 1] = region end
    for index = 1, #textures do
        local region = textures[index]
        if not RestoreTexture(region, textureStates[region]) then partial = true end
    end

    local alphas = {}
    for region in pairs(alphaStates) do alphas[#alphas + 1] = region end
    for index = 1, #alphas do
        local region = alphas[index]
        if not RestoreAlpha(region, alphaStates[region]) then partial = true end
    end

    if NS.MicroMenuVisual then
        for button in pairs(activeButtons) do
            if not NS.MicroMenuVisual.Restore(button) then partial = true end
        end
    end

    local surfaces = {}
    for target in pairs(surfaceRecords) do surfaces[#surfaces + 1] = target end
    for index = 1, #surfaces do
        if not RestoreSurface(surfaces[index]) then partial = true end
    end
    if NS.OwnedMicroBar and type(NS.OwnedMicroBar.Disable) == "function" then
        local restored = NS.OwnedMicroBar.Disable(activeRoot)
        if restored == false then partial = true end
    end

    activeButtons = setmetatable({}, { __mode = "k" })
    activeRoot, activeOwner = nil, nil
    MicroMenuSkin.active = false
    visualSuspended = false
    desiredActive, desiredRoot, desiredOwner = false, nil, nil
    RemoveListener()
    return true, partial and "partial" or "disabled"
end

local function DisableNow()
    if IsCombatLocked() then return false, "combat" end
    if transitionInProgress then return false, "busy" end
    transitionInProgress = true
    local ok, success, result = pcall(DisableResolved)
    transitionInProgress = false
    if not ok then error(success, 0) end
    return success, result
end

local function RunDesired()
    if desiredActive then
        return ApplyNow(desiredRoot, desiredOwner)
    end
    return DisableNow()
end

local function DeferDesired()
    if not NS.CombatGate or type(NS.CombatGate.RunOrDefer) ~= "function" then
        return false, "combat"
    end
    NS.CombatGate.RunOrDefer(DEFER_KEY, RunDesired)
    return false, "combat"
end

function MicroMenuSkin.Apply(frame, owner)
    desiredActive, desiredRoot, desiredOwner = true, frame, owner
    if IsCombatLocked() then return DeferDesired() end
    return ApplyNow(frame, owner)
end

function MicroMenuSkin.Disable()
    desiredActive, desiredRoot, desiredOwner = false, nil, nil
    if IsCombatLocked() then return DeferDesired() end
    return DisableNow()
end

function MicroMenuSkin.RefreshActive()
    if not MicroMenuSkin.active then return false, "inactive" end
    desiredActive, desiredRoot, desiredOwner = true, activeRoot, activeOwner
    if IsCombatLocked() then return DeferDesired() end
    return ApplyNow(activeRoot, activeOwner)
end

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

function MicroMenuSkin.ApplyPreset(presetName)
    if IsCombatLocked() then return false, "combat" end
    if presetName == "recommended" or presetName == "default" then
        presetName = (NS.Defaults and NS.Defaults.icons
            and NS.Defaults.icons.microMenu and NS.Defaults.icons.microMenu.preset) or "forever"
    end
    local preset = NS.MicroMenuPresetValues and NS.MicroMenuPresetValues[presetName]
    local settings = MutableSettings()
    if not preset or not settings then return false, "invalid preset" end
    for key in pairs(OPTION_KEYS) do
        if preset[key] ~= nil then settings[key] = preset[key] end
    end
    settings.preset = presetName
    return RefreshAfterSetting()
end

function MicroMenuSkin.SetOption(key, value)
    if IsCombatLocked() then return false, "combat" end
    if key == "preset" then return MicroMenuSkin.ApplyPreset(value) end
    if not OPTION_KEYS[key] then return false, "unknown option" end
    local settings = MutableSettings()
    if not settings then return false, "settings" end

    if key == "barBackground" or key == "buttonBackground" or key == "locked" then
        if type(value) ~= "boolean" then return false, "invalid value" end
    elseif key == "layoutMode" then
        if not IsListed(NS.MicroMenuLayoutModes, value) then
            return false, "invalid value"
        end
    elseif key == "visibility" then
        if not IsListed(NS.MicroMenuVisibilityModes, value) then
            return false, "invalid value"
        end
    elseif key == "orientation" then
        if not IsListed(NS.MicroMenuOrientations, value) then
            return false, "invalid value"
        end
    elseif key == "growth" then
        if not IsListed(NS.MicroMenuGrowthModes, value) then
            return false, "invalid value"
        end
    elseif key == "layoutPoint" or key == "layoutRelativePoint" then
        if not IsListed(NS.MicroMenuPoints, value) then
            return false, "invalid value"
        end
    elseif key == "positionPreset" then
        if value ~= "custom" and not (NS.MicroMenuPositionPresets
            and NS.MicroMenuPositionPresets[value]) then
            return false, "invalid value"
        end
    elseif key == "buttonsPerLine" then
        value = tonumber(value)
        if not value or value < 1 or value > #BUTTON_NAMES then
            return false, "invalid value"
        end
        value = math.floor(value + 0.5)
    elseif key == "spacing" then
        value = tonumber(value)
        if not value or value < -8 or value > 16 then
            return false, "invalid value"
        end
        value = math.floor(value + 0.5)
    elseif key == "scale" then
        value = tonumber(value)
        if not value or value < 0.5 or value > 1.5 then
            return false, "invalid value"
        end
    elseif key == "padding" then
        value = tonumber(value)
        if not value or value < 0 or value > 16 then
            return false, "invalid value"
        end
        value = math.floor(value + 0.5)
    elseif key == "layoutX" or key == "layoutY" then
        value = tonumber(value)
        if not value or value < -4096 or value > 4096 then
            return false, "invalid value"
        end
        value = math.floor(value + 0.5)
    elseif key == "barBorder" or key == "buttonBorder" then
        if type(value) == "boolean" then value = value and 1 or 0 end
        value = tonumber(value)
        if not value or value < 0 or value > 2 then return false, "invalid value" end
        value = math.floor(value + 0.5)
    elseif key == "shape" then
        if not IsListed(NS.MicroMenuShapes, value) then return false, "invalid value" end
    elseif key == "barMaterial" then
        if not IsListed(NS.MicroMenuBarMaterials, value) then return false, "invalid value" end
    elseif key == "radius" then
        value = tonumber(value)
        if not IsListed(NS.GeometryRadii, value) then return false, "invalid value" end
    elseif key == "iconStyle" then
        if not IsListed(NS.MicroMenuIconStyles, value) then
            return false, "invalid value"
        end
    elseif key == "hoverStyle" then
        if not IsListed(NS.MicroMenuHoverStyles, value) then
            return false, "invalid value"
        end
    elseif key == "buttonSize" then
        value = tonumber(value)
        if not value or value < 20 or value > 32 then
            return false, "invalid value"
        end
        value = math.floor(value + 0.5)
        if tonumber(settings.iconSize) and settings.iconSize > value - 4 then
            settings.iconSize = value - 4
        end
    elseif key == "iconSize" then
        value = tonumber(value)
        local maximum = math.min(28, (tonumber(settings.buttonSize) or 28) - 4)
        if not value or value < 10 or value > maximum then
            return false, "invalid value"
        end
        value = math.floor(value + 0.5)
    elseif key == "tint" then
        if not IsListed(NS.MicroMenuTintModes, value) then return false, "invalid value" end
    else
        value = tonumber(value)
        if not value then return false, "invalid value" end
        value = Clamp01(value)
    end

    settings[key] = value
    if VISUAL_OPTION_KEYS[key] then
        settings.preset = "custom"
    elseif key == "layoutMode" and settings.preset == "blizzard"
        and value ~= "blizzard" then
        settings.preset = "custom"
    elseif key == "layoutPoint" or key == "layoutRelativePoint"
        or key == "layoutX" or key == "layoutY" then
        settings.positionPreset = "custom"
    end
    return RefreshAfterSetting()
end

function MicroMenuSkin.ResetRecommended()
    if IsCombatLocked() then return false, "combat" end
    local defaults = NS.Defaults and NS.Defaults.icons
        and NS.Defaults.icons.microMenu
    local settings = MutableSettings()
    if not defaults or not settings then return false, "settings" end
    for key in pairs(OPTION_KEYS) do
        if defaults[key] ~= nil then settings[key] = defaults[key] end
    end
    settings.preset = defaults.preset
    return RefreshAfterSetting()
end

function MicroMenuSkin.SetPositionPreset(presetName)
    if IsCombatLocked() then return false, "combat" end
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
