local _, NS = ...

-- Clean-room visual layer for Blizzard's native Micro Buttons. The native
-- Button objects remain the click, tooltip and secure-state owners; MSKIN only
-- paints already-created textures above their suppressed ornamental atlases.
local MicroMenuVisual = {}
NS.MicroMenuVisual = MicroMenuVisual

local Safety = NS.Safety
local ConfigureShape = NS.Geometry.ConfigureShape

local MEDIA = NS.path .. "Media\\MicroMenu\\"
local ICON_ATLASES = {
    line = MEDIA .. "MapkoSkinMicroGlyphsAtlas.png",
    bold = MEDIA .. "MapkoSkinMicroGlyphsBoldAtlas.png",
}
local FOREVER_PLATE = MEDIA .. "ForeverMicroPlate.tga"
local MIDNIGHT_PLATE = MEDIA .. "MidnightMicroPlate.tga"
local ICON_SLOTS = 16

-- The bold glyph style sits on a plate made for the authored bar materials.
local PLATE_TEXTURES = {
    forever = FOREVER_PLATE,
    modern = MIDNIGHT_PLATE,
    midnightDark = MIDNIGHT_PLATE,
}

local ICON_CELLS = {
    CharacterMicroButton = 0,
    ProfessionMicroButton = 1,
    PlayerSpellsMicroButton = 2,
    SpellbookMicroButton = 2,
    TalentMicroButton = 9,
    LegacyMicroButton = 3,
    AchievementMicroButton = 3,
    QuestLogMicroButton = 4,
    HousingMicroButton = 5,
    GuildMicroButton = 6,
    LFDMicroButton = 7,
    CollectionsMicroButton = 8,
    EJMicroButton = 9,
    HelpMicroButton = 10,
    StoreMicroButton = 11,
    MainMenuMicroButton = 12,
}

-- Blizzard keeps the icon art in the button's Normal atlas and paints the
-- button background separately. These names are only for the menu preview.
local BLIZZARD_ICON_NAMES = {
    ProfessionMicroButton = "Professions",
    PlayerSpellsMicroButton = "SpecTalents",
    SpellbookMicroButton = "SpellbookAbilities",
    TalentMicroButton = "SpecTalents",
    LegacyMicroButton = "Legacy",
    AchievementMicroButton = "Achievements",
    QuestLogMicroButton = "Questlog",
    HousingMicroButton = "Housing",
    GuildMicroButton = "GuildCommunities",
    LFDMicroButton = "Groupfinder",
    CollectionsMicroButton = "Collections",
    EJMicroButton = "AdventureGuide",
    HelpMicroButton = "GameMenu",
    StoreMicroButton = "Shop",
    MainMenuMicroButton = "GameMenu",
}

-- These icon styles keep Blizzard's own artwork and need no overlay.
local NATIVE_ICON_STYLES = { blizzard = true, blizzardIcons = true }

local NATIVE_STATE_TEXTURES = {
    { key = "normal", getter = "GetNormalTexture" },
    { key = "highlight", getter = "GetHighlightTexture" },
    { key = "pushed", getter = "GetPushedTexture" },
    { key = "disabled", getter = "GetDisabledTexture" },
}

local VISUAL_STATES = {
    normal = "normal",
    hover = "hover",
    highlight = "hover",
    pressed = "pressed",
    pushed = "pressed",
    disabled = "disabled",
}

local HOVER_FILL_ALPHA = { softFill = 0.24, solidFill = 0.72 }

-- The game menu button carries Blizzard's latency/framerate bar.
local PERFORMANCE_BUTTON = "MainMenuMicroButton"
local PERFORMANCE_BAR = "MainMenuBarPerformanceBar"

local states = setmetatable({}, { __mode = "k" })

local function HasMethod(target, name)
    return type(Safety.Field(target, name)) == "function" and not Safety.IsForbidden(target)
end

local function AllPublic(...)
    for index = 1, select("#", ...) do
        if not Safety.Public((select(index, ...))) then return false end
    end
    return true
end

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function Near(first, second)
    return type(first) == "number" and type(second) == "number"
        and math.abs(first - second) <= 0.00001
end

local function SameValue(first, second)
    if type(first) == "number" or type(second) == "number" then
        return Near(first, second)
    end
    return first == second
end

local function SameArray(first, second)
    if type(first) ~= "table" or type(second) ~= "table"
        or #first ~= #second then
        return false
    end
    for index = 1, #first do
        if not SameValue(first[index], second[index]) then return false end
    end
    return true
end

local function SamePoints(first, second)
    if type(first) ~= "table" or type(second) ~= "table"
        or #first ~= #second then
        return false
    end
    for index = 1, #first do
        if not SameArray(first[index], second[index]) then return false end
    end
    return true
end

local function CanCreate(button)
    return Safety.CanCreateRegions(button, true)
end

local function GeometrySpec(settings, spec)
    spec = spec or {}
    spec.role = "microButton"
    spec.radius = tonumber(settings.radius) or 6
    spec.border = tonumber(settings.buttonBorder) or 0
    spec.pillHeight = Clamp(settings.buttonSize, 20, 32)
    spec.slice = true
    if settings.shape == "global" or settings.shape == nil then
        spec.useControlShape = true
        spec.shape = nil
    else
        spec.useControlShape = nil
        spec.shape = settings.shape
    end
    return spec
end

local function ApplySolid(texture, colorKey, alphaScale, state, cacheKey)
    local r, g, b, a = NS.Theme.GetColor(colorKey)
    a = (tonumber(a) or 1) * (tonumber(alphaScale) or 1)
    if texture.SetGradient and type(CreateColor) == "function" then
        local color = NS.Theme.ReuseColor(state[cacheKey], r, g, b, a)
        state[cacheKey] = color
        texture:SetGradient("VERTICAL", color, color)
    else
        texture:SetVertexColor(r, g, b, a)
    end
end

local function ApplyMaterial(texture, material, state)
    local from = NS.Theme.GetColorTable(material.from)
    local to = NS.Theme.GetColorTable(material.to)
    local opacity = NS.Theme.GetMaterialOpacity(material)
    local strength = NS.DB.theme.gradientStrength or 1
    local toR = from[1] + (to[1] - from[1]) * strength
    local toG = from[2] + (to[2] - from[2]) * strength
    local toB = from[3] + (to[3] - from[3]) * strength
    local toA = from[4] + (to[4] - from[4]) * strength
    if NS.DB.theme.gradient and texture.SetGradient
        and type(CreateColor) == "function" then
        state.materialFrom = NS.Theme.ReuseColor(state.materialFrom, from[1], from[2], from[3], from[4] * opacity)
        state.materialTo = NS.Theme.ReuseColor(state.materialTo, toR, toG, toB, toA * opacity)
        texture:SetGradient(NS.DB.theme.gradientDirection or "VERTICAL",
            state.materialFrom, state.materialTo)
    else
        texture:SetVertexColor(from[1], from[2], from[3], from[4] * opacity)
    end
end

local function AnchorSquare(texture, button, size)
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", button, "CENTER", 0, 0)
    texture:SetSize(size, size)
end

-- Blizzard's performance bar is borrowed while the clean style is active:
-- recolored flat, laid next to the glyph and returned exactly as found.
-- Each property is owned separately and only while it still shows the
-- value we wrote; a later Blizzard write takes the property back.
-- Readers return a new value, or nil when it is missing or secret.

local function CapturePoints(region)
    local count = tonumber(Safety.Read(region, "GetNumPoints"))
    if count == nil then return nil end
    local points = {}
    for index = 1, math.floor(count) do
        local point, relativeTo, relativePoint, x, y = Safety.Call(region, "GetPoint", index)
        if type(point) ~= "string" or not AllPublic(point, relativeTo, relativePoint, x, y) then
            return nil
        end
        points[#points + 1] = {
            point, relativeTo, relativePoint,
            tonumber(x) or 0, tonumber(y) or 0,
        }
    end
    return points
end

local function WritePoints(region, points)
    if not Safety.Invoke(region, "ClearAllPoints") then return false end
    for index = 1, #points do
        region:SetPoint(unpack(points[index]))
    end
    return true
end

local function CaptureTextureSource(region)
    if not HasMethod(region, "GetAtlas") and not HasMethod(region, "GetTexture") then
        return nil
    end
    return {
        atlas = Safety.Read(region, "GetAtlas"),
        texture = Safety.Read(region, "GetTexture"),
    }
end

local function SameTextureSource(first, second)
    return type(first) == "table" and type(second) == "table"
        and first.atlas == second.atlas and first.texture == second.texture
end

local function WriteTextureSource(region, source)
    if source.atlas ~= nil then
        return Safety.Invoke(region, "SetAtlas", source.atlas)
    end
    return Safety.Invoke(region, "SetTexture", source.texture)
end

local function CaptureTexCoord(region)
    local first, second, third, fourth, fifth, sixth, seventh, eighth =
        Safety.Call(region, "GetTexCoord")
    if first == nil or not AllPublic(first, second, third, fourth, fifth, sixth, seventh, eighth) then
        return nil
    end
    if fifth ~= nil then
        return { first, second, third, fourth, fifth, sixth, seventh, eighth }
    end
    return { first, second, third, fourth }
end

local function WriteTexCoord(region, coords)
    return Safety.Invoke(region, "SetTexCoord", unpack(coords))
end

local function CaptureLayer(region)
    local layer, subLevel = Safety.Call(region, "GetDrawLayer")
    if type(layer) ~= "string" or not AllPublic(layer, subLevel) then return nil end
    return { layer, tonumber(subLevel) or 0 }
end

local function WriteLayer(region, layer)
    return Safety.Invoke(region, "SetDrawLayer", unpack(layer))
end

local function CaptureSize(region)
    local width = tonumber(Safety.Read(region, "GetWidth"))
    local height = tonumber(Safety.Read(region, "GetHeight"))
    if width == nil or height == nil then return nil end
    return { width, height }
end

local function WriteSize(region, size)
    return Safety.Invoke(region, "SetSize", unpack(size))
end

-- Restored in this order; a rollback runs it backwards.
local PERFORMANCE_PROPERTIES = {
    { key = "source", capture = CaptureTextureSource, same = SameTextureSource, write = WriteTextureSource },
    { key = "texCoord", capture = CaptureTexCoord, same = SameArray, write = WriteTexCoord },
    { key = "layer", capture = CaptureLayer, same = SameArray, write = WriteLayer },
    { key = "points", capture = CapturePoints, same = SamePoints, write = WritePoints },
    { key = "size", capture = CaptureSize, same = SameArray, write = WriteSize },
}
-- The first three are set once; points and size follow the button size.
local SOURCE, TEX_COORD, LAYER, POINTS, SIZE = 1, 2, 3, 4, 5

local function HasOwnedPerformanceProperty(applied)
    for index = 1, #PERFORMANCE_PROPERTIES do
        if applied.owned[PERFORMANCE_PROPERTIES[index].key] then return true end
    end
    return false
end

-- Where the bar goes for this button size. Rebuilt only when the size
-- changes; applied values may keep a reference, so it is never mutated.
local function PerformanceLayout(state, visualSize)
    local layout = state.performanceLayout
    if not layout or layout.visualSize ~= visualSize then
        layout = {
            visualSize = visualSize,
            points = { { "CENTER", state.button, "CENTER", math.max(7, visualSize * 0.5 - 3), 0 } },
            size = { 2, Clamp(visualSize - 14, 6, 12) },
        }
        state.performanceLayout = layout
    end
    return layout
end

local function CapturePerformanceRegion(state, region)
    local original = {}
    for index = 1, #PERFORMANCE_PROPERTIES do
        local property = PERFORMANCE_PROPERTIES[index]
        local value = property.capture(region)
        if not value then return false end
        original[property.key] = value
    end
    state.performance = { region = region, original = original }
    return true
end

local function RestorePerformanceRegion(state)
    local performance = state and state.performance
    if not performance or not performance.region or not performance.applied then
        return true
    end
    local region = performance.region
    local original = performance.original
    local applied = performance.applied
    applied.restoring = true
    local success = true
    for index = 1, #PERFORMANCE_PROPERTIES do
        local property = PERFORMANCE_PROPERTIES[index]
        local key = property.key
        if applied.owned[key] then
            local current = property.capture(region)
            if not current then
                success = false
            elseif not property.same(current, applied[key]) then
                applied.owned[key] = false
            elseif property.write(region, original[key]) then
                applied.owned[key] = false
            else
                success = false
            end
        end
    end
    if not HasOwnedPerformanceProperty(applied) then
        state.performance = nil
    end
    return success
end

-- Moves an owned property to its desired value unless someone else has
-- taken it over. A failed write puts the previous value back.
local function FollowDesired(region, applied, property, desired)
    local key = property.key
    if not applied.owned[key] then return true end
    local current = property.capture(region)
    if not current then return false end
    if not property.same(current, applied[key]) then
        applied.owned[key] = false
        return true
    end
    if property.same(applied[key], desired) then return true end
    local previous = applied[key]
    if property.write(region, desired) then
        applied[key] = desired
        return true
    end
    if not property.write(region, previous) then
        applied[key] = property.capture(region) or previous
    end
    return false
end

local function RefreshOwnedPerformanceRegion(performance, state, visualSize)
    local applied = performance.applied
    local region = performance.region
    for index = SOURCE, LAYER do
        local property = PERFORMANCE_PROPERTIES[index]
        local key = property.key
        if applied.owned[key] then
            local current = property.capture(region)
            if not current then return false end
            if not property.same(current, applied[key]) then
                applied.owned[key] = false
            end
        end
    end
    local layout = PerformanceLayout(state, visualSize)
    local success = FollowDesired(region, applied, PERFORMANCE_PROPERTIES[POINTS], layout.points)
    return FollowDesired(region, applied, PERFORMANCE_PROPERTIES[SIZE], layout.size) and success
end

local function RollbackNewPerformanceRegion(state)
    local performance = state and state.performance
    local applied = performance and performance.applied
    if not performance or not applied then return true end
    local region = performance.region
    local original = performance.original
    local success = true

    -- This is the initial Apply call and Lua cannot yield between the mutation
    -- and this rollback. Restoring every property we successfully touched is
    -- therefore safe even when its post-write getter failed and there is no
    -- usable ownership comparison yet.
    for index = #PERFORMANCE_PROPERTIES, 1, -1 do
        local property = PERFORMANCE_PROPERTIES[index]
        if applied.owned[property.key] then
            if property.write(region, original[property.key]) then
                applied.owned[property.key] = false
            else
                success = false
            end
        end
    end

    if HasOwnedPerformanceProperty(applied) then
        applied.restoring = true
    else
        state.performance = nil
    end
    return success
end

-- Writes value, takes ownership, and records what the client reports back.
local function TakeProperty(region, applied, property, value)
    if not property.write(region, value) then return false end
    local key = property.key
    applied[key] = value
    applied.owned[key] = true
    local captured = property.capture(region)
    if not captured then return false end
    applied[key] = captured
    return true
end

local function ApplyNewPerformanceRegion(state, visualSize, region)
    if not CapturePerformanceRegion(state, region) then return false end
    local performance = state.performance
    local applied = { owned = {}, restoring = false }
    performance.applied = applied

    local r, g, b, a = Safety.ReadColor(region, "GetVertexColor")
    if not r then
        state.performance = nil
        return false
    end

    -- A flat white texture keeps the bar's own latency color as its tint.
    local success = false
    if Safety.Invoke(region, "SetColorTexture", 1, 1, 1, 1) then
        applied.owned.source = true
        local captured = CaptureTextureSource(region)
        applied.source = captured or {}
        success = captured ~= nil
        if not Safety.Invoke(region, "SetVertexColor", r, g, b, a) then success = false end
    end
    success = TakeProperty(region, applied, PERFORMANCE_PROPERTIES[TEX_COORD], { 0, 1, 0, 1 }) and success
    success = TakeProperty(region, applied, PERFORMANCE_PROPERTIES[LAYER], { "OVERLAY", -5 }) and success
    local layout = PerformanceLayout(state, visualSize)
    success = TakeProperty(region, applied, PERFORMANCE_PROPERTIES[POINTS], layout.points) and success
    success = TakeProperty(region, applied, PERFORMANCE_PROPERTIES[SIZE], layout.size) and success

    if not success then
        RollbackNewPerformanceRegion(state)
        return false
    end
    return true
end

local function ApplyPerformanceRegion(state, visualSize)
    if state.buttonName ~= PERFORMANCE_BUTTON then return true end
    local currentRegion = Safety.Field(state.button, PERFORMANCE_BAR)
    local performance = state.performance

    if performance and performance.region ~= currentRegion then
        if performance.applied and not RestorePerformanceRegion(state) then
            return false
        end
        state.performance = nil
        performance = nil
    end
    if performance and performance.applied and performance.applied.restoring then
        if not RestorePerformanceRegion(state) then return false end
        performance = state.performance
    end
    if not currentRegion then return true end
    if not performance then
        return ApplyNewPerformanceRegion(state, visualSize, currentRegion)
    end
    return RefreshOwnedPerformanceRegion(performance, state, visualSize)
end

-- Native state masks: a transparent mask per native state texture hides
-- Blizzard's art under the overlay without changing that texture itself.

local function ConfigureNativeStateMask(state, binding)
    local mask = binding.mask
    local pointsOk = Safety.Invoke(mask, "SetAllPoints", state.button)
    local textureOk = Safety.Invoke(mask, "SetColorTexture", 0, 0, 0, 0)
    if not textureOk then
        textureOk = Safety.Invoke(mask, "SetTexture", "Interface\\Buttons\\WHITE8X8")
            and Safety.Invoke(mask, "SetVertexColor", 1, 1, 1, 0)
    end
    local hideOk = Safety.Invoke(mask, "Hide")
    binding.shown = false
    binding.ready = pointsOk and textureOk and hideOk
    return binding.ready
end

local function EnsureNativeStateMasks(state)
    state.nativeMasks = state.nativeMasks or {}
    local button = state.button
    local success = true
    for index = 1, #NATIVE_STATE_TEXTURES do
        local key = NATIVE_STATE_TEXTURES[index].key
        local binding = state.nativeMasks[key]
        if not binding then
            -- CanCreate is checked first: indexing CreateMaskTexture on a
            -- compositor frame is itself reported.
            if CanCreate(button) and type(button.CreateMaskTexture) == "function" then
                binding = {
                    mask = button:CreateMaskTexture(nil, "OVERLAY", nil, -4),
                    applied = false,
                    ready = false,
                    shown = false,
                }
                state.nativeMasks[key] = binding
            else
                success = false
            end
        end
        if binding and not binding.ready
            and not ConfigureNativeStateMask(state, binding) then
            success = false
        end
    end
    return success
end

local function ApplyNativeStateMask(state, spec)
    local binding = state.nativeMasks and state.nativeMasks[spec.key]
    if not binding or not binding.ready then return false end
    if not HasMethod(state.button, spec.getter) then return false end
    local target = Safety.Call(state.button, spec.getter)

    if binding.applied and binding.target ~= target then
        if not binding.target
            or not Safety.Invoke(binding.target, "RemoveMaskTexture", binding.mask) then
            return false
        end
        binding.applied = false
        binding.target = nil
        if not Safety.Invoke(binding.mask, "Hide") then return false end
        binding.shown = false
    end
    if not target then return true end
    if not binding.applied then
        if not Safety.Invoke(target, "AddMaskTexture", binding.mask) then return false end
        binding.target = target
        binding.applied = true
    end
    if binding.shown then return true end
    if not Safety.Invoke(binding.mask, "Show") then return false end
    binding.shown = true
    return true
end

local function ApplyNativeStateMasks(state)
    local success = EnsureNativeStateMasks(state)
    for index = 1, #NATIVE_STATE_TEXTURES do
        success = ApplyNativeStateMask(state, NATIVE_STATE_TEXTURES[index]) and success
    end
    return success
end

local function RestoreNativeStateMasks(state)
    if not state or not state.nativeMasks then return true end
    local success = true
    for index = 1, #NATIVE_STATE_TEXTURES do
        local binding = state.nativeMasks[NATIVE_STATE_TEXTURES[index].key]
        if binding then
            if binding.applied then
                if binding.target
                    and Safety.Invoke(binding.target, "RemoveMaskTexture", binding.mask) then
                    binding.applied = false
                    binding.target = nil
                else
                    success = false
                end
            end
            if not binding.applied then
                if Safety.Invoke(binding.mask, "Hide") then
                    binding.shown = false
                else
                    success = false
                end
            end
        end
    end
    return success
end

local function ApplyIconSource(texture, buttonName, iconStyle)
    if iconStyle == "blizzardIcons" and BLIZZARD_ICON_NAMES[buttonName]
        and texture.SetAtlas then
        texture:SetAtlas("UI-HUD-MicroMenu-" .. BLIZZARD_ICON_NAMES[buttonName] .. "-Up")
        return
    end
    local cell = ICON_CELLS[buttonName] or ICON_CELLS.HelpMicroButton
    texture:SetTexture(ICON_ATLASES[iconStyle] or ICON_ATLASES.line)
    if texture.SetTexCoord then
        texture:SetTexCoord(cell / ICON_SLOTS, (cell + 1) / ICON_SLOTS, 0, 1)
    end
end

-- Our overlay keeps its own alpha while the native button fades.
local function PrepareOverlayRegion(region)
    Safety.Invoke(region, "SetIgnoreParentAlpha", true)
    Safety.Invoke(region, "SetIgnoreParentScale", false)
    region:Hide()
    return region
end

local function EnsureState(button, buttonName, iconStyle)
    local state = states[button]
    if state then
        if (buttonName and buttonName ~= state.buttonName)
            or (iconStyle and iconStyle ~= state.iconStyle) then
            state.buttonName = buttonName or state.buttonName
            state.iconStyle = iconStyle or state.iconStyle
            ApplyIconSource(state.icon, state.buttonName, state.iconStyle)
        end
        state.masksReady = EnsureNativeStateMasks(state)
        return state
    end
    if not CanCreate(button) or type(button.CreateTexture) ~= "function" then
        return nil
    end

    state = {
        button = button,
        buttonName = buttonName,
        iconStyle = iconStyle,
        plate = PrepareOverlayRegion(button:CreateTexture(nil, "OVERLAY", nil, -8)),
        fill = PrepareOverlayRegion(button:CreateTexture(nil, "OVERLAY", nil, -7)),
        edge = PrepareOverlayRegion(button:CreateTexture(nil, "OVERLAY", nil, -6)),
        icon = PrepareOverlayRegion(button:CreateTexture(nil, "OVERLAY", nil, -5)),
        nativeMasks = {},
        visible = false,
    }
    state.plate:SetTexture(FOREVER_PLATE)
    ApplyIconSource(state.icon, buttonName, iconStyle)
    states[button] = state
    state.masksReady = EnsureNativeStateMasks(state)
    return state
end

-- Sizes and anchors the overlay; returns the button size.
local function LayoutOverlay(state, settings)
    local visualSize = Clamp(settings.buttonSize, 20, 32)
    local iconSize = Clamp(settings.iconSize, 10, visualSize - 4)
    if state.buttonName == PERFORMANCE_BUTTON and Safety.Field(state.button, PERFORMANCE_BAR) then
        -- Leave room beside the glyph for the performance bar.
        iconSize = math.min(iconSize, math.max(10, visualSize - 10))
    end
    AnchorSquare(state.fill, state.button, visualSize)
    AnchorSquare(state.edge, state.button, visualSize)
    AnchorSquare(state.icon, state.button, iconSize)
    AnchorSquare(state.plate, state.button, visualSize + 2)
    return visualSize
end

local function PaintBorderEdge(state, geometry, asset, material)
    ConfigureShape(state.edge, asset, geometry)
    local r, g, b, a = NS.Theme.GetColor(material.border)
    state.edge:SetVertexColor(r, g, b, a * NS.Theme.GetBorderOpacity())
end

local function PaintSolidEdge(state, geometry, asset, colorKey, alphaScale)
    ConfigureShape(state.edge, asset, geometry)
    ApplySolid(state.edge, colorKey, alphaScale, state, "edgeSolid")
end

local function PaintHoverLayers(state, settings, geometry, material)
    local hoverStyle = settings.hoverStyle or "outline"
    local showFill = settings.buttonBackground == true
    local showEdge = geometry.edge ~= nil
    ApplyMaterial(state.fill, material, state)
    local fillAlpha = HOVER_FILL_ALPHA[hoverStyle]
    if fillAlpha then
        ApplySolid(state.fill, "hover", fillAlpha, state, "fillSolid")
        showFill = true
    end
    if hoverStyle == "outline" or fillAlpha then
        showEdge = geometry.hoverEdge ~= nil
        if showEdge then
            PaintSolidEdge(state, geometry, geometry.hoverEdge, "hover", NS.Theme.GetBorderOpacity())
        end
    elseif hoverStyle == "iconOnly" or hoverStyle == "off" then
        showEdge = geometry.edge ~= nil and settings.buttonBorder ~= 0
        if geometry.edge then PaintBorderEdge(state, geometry, geometry.edge, material) end
    end
    return showFill, showEdge
end

-- Paints fill and edge for one visual state; returns whether each shows.
local function PaintStateLayers(state, settings, geometry, stateName)
    local material = NS.Theme.GetMaterial("microButton")
    ConfigureShape(state.fill, geometry.fill, geometry)
    if stateName == "hover" then
        return PaintHoverLayers(state, settings, geometry, material)
    elseif stateName == "pressed" then
        ApplySolid(state.fill, "pressed", 0.52, state, "fillSolid")
        if geometry.hoverEdge then
            PaintSolidEdge(state, geometry, geometry.hoverEdge, "pressed", NS.Theme.GetBorderOpacity())
        end
        return true, geometry.hoverEdge ~= nil
    elseif stateName == "disabled" then
        ApplySolid(state.fill, "disabled", 0.18, state, "fillSolid")
        if geometry.edge then
            PaintSolidEdge(state, geometry, geometry.edge, "disabled", NS.Theme.GetBorderOpacity() * 0.62)
        end
        return settings.buttonBackground == true, geometry.edge ~= nil
    end
    ApplyMaterial(state.fill, material, state)
    if geometry.edge then PaintBorderEdge(state, geometry, geometry.edge, material) end
    return settings.buttonBackground == true, geometry.edge ~= nil
end

local function PaintPlate(state, settings)
    local material = settings.barMaterial
    local decorated = settings.iconStyle == "bold" and PLATE_TEXTURES[material] ~= nil
    if decorated and state.plateMaterial ~= material then
        state.plate:SetTexture(PLATE_TEXTURES[material])
        state.plate:SetDesaturated(material == "midnightDark")
        if material == "midnightDark" then
            state.plate:SetVertexColor(0.84, 0.85, 0.82, 1)
        else
            state.plate:SetVertexColor(1, 1, 1, 1)
        end
        state.plateMaterial = material
    end
    state.plate:SetShown(state.visible and decorated)
end

-- Paints the overlay for a clean (line or bold) icon style.
local function RefreshState(state, settings, stateName)
    stateName = VISUAL_STATES[stateName] or "normal"
    if stateName == "hover" and settings.hoverStyle == "off" then
        stateName = "normal"
    end
    local visualSize = LayoutOverlay(state, settings)
    state.geometrySpec = GeometrySpec(settings, state.geometrySpec)
    local geometry = NS.Geometry.Resolve(state.geometrySpec, state.geometry)
    state.geometry = geometry
    local showFill, showEdge = PaintStateLayers(state, settings, geometry, stateName)

    local r, g, b, a = NS.MicroMenuSkin.GetIconColor(stateName, nil)
    state.icon:SetVertexColor(r, g, b, a)
    state.icon:SetDesaturated(false)
    state.fill:SetShown(showFill and state.visible)
    state.edge:SetShown(showEdge and state.visible)
    PaintPlate(state, settings)
    state.icon:SetShown(state.visible)
    local performanceOk = ApplyPerformanceRegion(state, visualSize)
    local masksOk = ApplyNativeStateMasks(state)
    state.currentState = stateName
    return performanceOk and masksOk
end

local function HideOverlay(state)
    state.visible = false
    state.fill:Hide()
    state.edge:Hide()
    state.plate:Hide()
    state.icon:Hide()
end

function MicroMenuVisual.Prepare(button, buttonName, settings)
    if not button or not settings then return false end
    local nativeStyle = NATIVE_ICON_STYLES[settings.iconStyle] == true
    local state = EnsureState(button, buttonName,
        nativeStyle and "line" or settings.iconStyle)
    if not state then return false end
    if nativeStyle then
        -- Preallocate only. Native art remains entirely visible in Blizzard
        -- mode, while a later clean-style switch needs no CreateTexture or
        -- CreateMaskTexture call below an already-owned MicroMenu root.
        HideOverlay(state)
        return state.masksReady
    end
    -- Attach while Blizzard's native MicroMenu is still under its original
    -- parent. RefreshState only confirms these existing bindings after the
    -- OwnedMicroBar move makes the native hierarchy implicit-protected.
    state.masksReady = ApplyNativeStateMasks(state)
    return state.masksReady
end

function MicroMenuVisual.Apply(button, buttonName, settings, stateName)
    if not button or not settings then return false, "invalid" end
    if NATIVE_ICON_STYLES[settings.iconStyle] then
        MicroMenuVisual.Restore(button)
        return false, "native"
    end
    local state = EnsureState(button, buttonName, settings.iconStyle)
    if not state then return false, "unavailable" end
    state.visible = true
    return RefreshState(state, settings, stateName), "applied"
end

function MicroMenuVisual.Refresh(button, settings, stateName)
    local state = states[button]
    if not state or not state.visible then return false, "inactive" end
    if NATIVE_ICON_STYLES[settings.iconStyle] then
        MicroMenuVisual.Restore(button)
        return false, "native"
    end
    return RefreshState(state, settings, stateName), "refreshed"
end

function MicroMenuVisual.Restore(button)
    local state = states[button]
    if not state then return true end
    local success = RestoreNativeStateMasks(state)
    success = RestorePerformanceRegion(state) and success
    HideOverlay(state)
    state.currentState = nil
    return success
end

function MicroMenuVisual.GetState(button)
    return states[button]
end

function MicroMenuVisual.GetIconPath(buttonName)
    return ICON_CELLS[buttonName] ~= nil and ICON_ATLASES.line or nil
end

function MicroMenuVisual.ApplyIcon(texture, buttonName, iconStyle)
    if not texture or ICON_CELLS[buttonName] == nil then return false end
    ApplyIconSource(texture, buttonName, iconStyle)
    return true
end
