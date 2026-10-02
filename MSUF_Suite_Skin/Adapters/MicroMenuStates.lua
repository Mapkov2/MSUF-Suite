local _, NS = ...

-- The reversible art states of the Micro Menu (MicroMenu.lua, which loads
-- after this file): icon tints, faded native regions and the plates
-- (surfaces) on the buttons and the bar. Each records the native value it
-- replaced and restores exactly that, unless Blizzard changed it since.
local States = {}
NS.MicroMenuStates = States

local Safety = NS.Safety
local Read = Safety.Read
local ColorMatches = Safety.ColorMatches
-- The client keeps vertex colors at 8-bit precision: a color we set reads
-- back within COLOR_OWN of the stored { r, g, b, a }.
local COLOR_OWN = Safety.COLOR_OWN

local textureStates = setmetatable({}, { __mode = "k" })
local alphaStates = setmetatable({}, { __mode = "k" })
local surfaceRecords = setmetatable({}, { __mode = "k" })

local function Near(first, second)
    return type(first) == "number" and type(second) == "number"
        and math.abs(first - second) <= 0.00001
end

local function StoreVertex(color, r, g, b, a)
    color[1], color[2], color[3], color[4] = r, g, b, a
end

local function ReadDesaturated(region)
    local value = Read(region, "IsDesaturated")
    if type(value) == "boolean" then return value end
    return nil
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

-- Reversible texture and alpha states ---------------------------------------------------

-- settings: the Micro Menu settings of this pass (monochrome desaturates).
local function ApplyTextureTint(button, region, stateName, settings)
    if not region or not CanControl(button) then return false end
    local currentR, currentG, currentB, currentA = Safety.ReadColor(region, "GetVertexColor")
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
        if state.applied
            and not ColorMatches(state.applied, currentR, currentG, currentB, currentA, COLOR_OWN)
            and not ColorMatches(state.original, currentR, currentG, currentB, currentA, COLOR_OWN) then
            StoreVertex(state.original, currentR, currentG, currentB, currentA)
        end
        if currentDesaturated ~= nil and state.appliedDesaturated ~= nil
            and currentDesaturated ~= state.appliedDesaturated
            and currentDesaturated ~= state.originalDesaturated then
            state.originalDesaturated = currentDesaturated
        end
    end

    local r, g, b, a = NS.MicroMenuSkin.GetIconColor(stateName, state.original)
    local desiredDesaturated = state.originalDesaturated
    if settings.tint == "monochrome" and desiredDesaturated ~= nil then
        desiredDesaturated = true
    end
    if not Safety.SameColor(currentR, currentG, currentB, currentA, r, g, b, a, COLOR_OWN) then
        region:SetVertexColor(r, g, b, a)
    end
    if desiredDesaturated ~= nil and currentDesaturated ~= desiredDesaturated then
        region:SetDesaturated(desiredDesaturated)
    end

    state.applied = state.applied or {}
    StoreVertex(state.applied, r, g, b, a)
    state.appliedDesaturated = desiredDesaturated
    if ColorMatches(state.original, r, g, b, a, COLOR_OWN)
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
    local r, g, b, a = Safety.ReadColor(region, "GetVertexColor")
    local original = state.original
    if r and ColorMatches(state.applied, r, g, b, a, COLOR_OWN)
        and not ColorMatches(original, r, g, b, a, COLOR_OWN) then
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
    local current = Read(region, "GetAlpha")
    if type(current) ~= "number" then return false end
    local state = alphaStates[region]
    if not state then
        -- Native alpha 0 leaves nothing to restore; keep no record for it
        -- instead of building one on every state hook.
        if Near(current, 0) then return true end
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
    local current = Read(region, "GetAlpha")
    if Near(current, state.applied) and not Near(current, state.original) then
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

-- True while target still shows the plate our last full pass attached. The
-- plate does not depend on the button state, so a state hook keeps it.
local function ShowsAppliedPlate(target)
    local record = surfaceRecords[target]
    local current = NS.Registry.GetSurface(target)
    return record ~= nil and current ~= nil and current.spec == record.appliedSpec
        and current.visible ~= false
end

-- Restores every tinted and faded region (Disable).
function States.RestoreArt()
    local success = true
    for region, state in pairs(textureStates) do
        if not RestoreTexture(region, state) then success = false end
    end
    for region, state in pairs(alphaStates) do
        if not RestoreAlpha(region, state) then success = false end
    end
    return success
end

-- Restores every plate this adapter attached (Disable).
function States.RestoreSurfaces()
    local success = true
    for target in pairs(surfaceRecords) do
        if not RestoreSurface(target) then success = false end
    end
    return success
end

States.BorderValue, States.CanControl = BorderValue, CanControl
States.ApplyTextureTint, States.FadeExact = ApplyTextureTint, FadeExact
States.RestoreButtonTextures, States.RestoreButtonAlphas = RestoreButtonTextures, RestoreButtonAlphas
States.ApplySurface, States.RestoreSurface = ApplySurface, RestoreSurface
States.ShowsAppliedPlate = ShowsAppliedPlate
