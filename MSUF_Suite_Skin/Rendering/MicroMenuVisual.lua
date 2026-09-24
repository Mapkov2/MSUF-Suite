local _, NS = ...

-- Clean-room visual layer for Blizzard's native Micro Buttons. The native
-- Button objects remain the click, tooltip and secure-state owners; MSKIN only
-- paints already-created textures above their suppressed ornamental atlases.
local MicroMenuVisual = {}
NS.MicroMenuVisual = MicroMenuVisual

local STRETCHED = Enum and Enum.UITextureSliceMode
    and Enum.UITextureSliceMode.Stretched or 0
local ICON_ATLASES = {
    line = "Interface\\AddOns\\MSUF_Suite_Skin\\Media\\MicroMenu\\MapkoSkinMicroGlyphsAtlas.png",
    bold = "Interface\\AddOns\\MSUF_Suite_Skin\\Media\\MicroMenu\\MapkoSkinMicroGlyphsBoldAtlas.png",
}
local FOREVER_PLATE = "Interface\\AddOns\\MSUF_Suite_Skin\\Media\\MicroMenu\\ForeverMicroPlate.tga"
local MIDNIGHT_PLATE = "Interface\\AddOns\\MSUF_Suite_Skin\\Media\\MicroMenu\\MidnightMicroPlate.tga"
local ICON_SLOTS = 16

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
-- button background separately. These names are only for the menu preview;
-- live buttons copy their current native atlas so guild variants stay current.
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

local NATIVE_STATE_TEXTURES = {
    { key = "normal", getter = "GetNormalTexture" },
    { key = "highlight", getter = "GetHighlightTexture" },
    { key = "pushed", getter = "GetPushedTexture" },
    { key = "disabled", getter = "GetDisabledTexture" },
}

local states = setmetatable({}, { __mode = "k" })

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

local function CanCreate(button)
    return NS.Safety and NS.Safety.CanCreateRegions(button, true) == true
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

local function ConfigureShape(texture, asset, geometry)
    if not texture or not asset then return false end
    if texture.ClearTextureSlice then texture:ClearTextureSlice() end
    texture:SetTexture(asset)
    if geometry.slice and texture.SetTextureSliceMargins then
        texture:SetTextureSliceMargins(
            geometry.margins[1], geometry.margins[2],
            geometry.margins[3], geometry.margins[4])
        if texture.SetTextureSliceMode then
            texture:SetTextureSliceMode(STRETCHED)
        end
    end
    return true
end

local function ReuseColor(color, r, g, b, a)
    if color and color.r == r and color.g == g and color.b == b and color.a == a then
        return color
    end
    return CreateColor(r, g, b, a)
end

local function ApplySolid(texture, colorKey, alphaScale, state, cacheKey)
    local r, g, b, a = NS.Theme.GetColor(colorKey)
    a = (tonumber(a) or 1) * (tonumber(alphaScale) or 1)
    if texture.SetGradient and type(CreateColor) == "function" then
        local color = ReuseColor(state[cacheKey], r, g, b, a)
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
        state.materialFrom = ReuseColor(state.materialFrom, from[1], from[2], from[3], from[4] * opacity)
        state.materialTo = ReuseColor(state.materialTo, toR, toG, toB, toA * opacity)
        texture:SetGradient(
            NS.DB.theme.gradientDirection or "VERTICAL",
            state.materialFrom,
            state.materialTo)
    else
        texture:SetVertexColor(from[1], from[2], from[3], from[4] * opacity)
    end
end

local function AnchorSquare(texture, button, size)
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", button, "CENTER", 0, 0)
    texture:SetSize(size, size)
end

local function CapturePoints(region)
    local points = {}
    local ok, count = CallMethod(region, "GetNumPoints")
    count = ok and tonumber(count) or nil
    if count == nil then return nil end
    for index = 1, math.floor(count) do
        local pointOk, point, relativeTo, relativePoint, x, y =
            CallMethod(region, "GetPoint", index)
        if not pointOk or type(point) ~= "string" then return nil end
        points[#points + 1] = {
            point, relativeTo, relativePoint,
            tonumber(x) or 0, tonumber(y) or 0,
        }
    end
    return points
end

local function RestorePoints(region, points)
    if not CallMethod(region, "ClearAllPoints") then return false end
    for index = 1, #(points or {}) do
        if not CallMethod(region, "SetPoint", unpack(points[index])) then
            return false
        end
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

local function CaptureTextureSource(region)
    local atlasOk, atlas = CallMethod(region, "GetAtlas")
    local textureOk, texture = CallMethod(region, "GetTexture")
    if not atlasOk and not textureOk then return nil end
    return {
        atlas = atlasOk and atlas or nil,
        texture = textureOk and texture or nil,
    }
end

local function SameTextureSource(first, second)
    return type(first) == "table" and type(second) == "table"
        and first.atlas == second.atlas and first.texture == second.texture
end

local function CaptureTexCoord(region)
    local ok, first, second, third, fourth, fifth, sixth, seventh, eighth =
        CallMethod(region, "GetTexCoord")
    if not ok or first == nil then return nil end
    if fifth ~= nil then
        return { first, second, third, fourth, fifth, sixth, seventh, eighth }
    end
    return { first, second, third, fourth }
end

local function CaptureLayer(region)
    local ok, layer, subLevel = CallMethod(region, "GetDrawLayer")
    if not ok or type(layer) ~= "string" then return nil end
    return { layer, tonumber(subLevel) or 0 }
end

local function CaptureSize(region)
    local widthOk, width = CallMethod(region, "GetWidth")
    local heightOk, height = CallMethod(region, "GetHeight")
    width, height = tonumber(width), tonumber(height)
    if not widthOk or not heightOk or width == nil or height == nil then
        return nil
    end
    return { width, height }
end

local function CapturePerformanceRegion(state, region)
    if state.buttonName ~= "MainMenuMicroButton" or not region then return false end
    local source = CaptureTextureSource(region)
    local texCoord = CaptureTexCoord(region)
    local layer = CaptureLayer(region)
    local points = CapturePoints(region)
    local size = CaptureSize(region)
    if not source or not texCoord or not layer or not points or not size then
        return false
    end
    state.performance = {
        region = region,
        original = {
            source = source,
            texCoord = texCoord,
            layer = layer,
            points = points,
            size = size,
        },
    }
    return true
end

local PERFORMANCE_PROPERTIES = {
    "source", "texCoord", "layer", "points", "size",
}

local function HasOwnedPerformanceProperty(applied)
    for index = 1, #PERFORMANCE_PROPERTIES do
        if applied.owned[PERFORMANCE_PROPERTIES[index]] then return true end
    end
    return false
end

local function RestorePerformanceSource(region, source)
    if source.atlas ~= nil then
        return CallMethod(region, "SetAtlas", source.atlas)
    end
    return CallMethod(region, "SetTexture", source.texture)
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

    if applied.owned.source then
        local current = CaptureTextureSource(region)
        if not current then
            success = false
        elseif SameTextureSource(current, applied.source) then
            if RestorePerformanceSource(region, original.source) then
                applied.owned.source = false
            else
                success = false
            end
        else
            applied.owned.source = false
        end
    end
    if applied.owned.texCoord then
        local current = CaptureTexCoord(region)
        if not current then
            success = false
        elseif SameArray(current, applied.texCoord) then
            if CallMethod(region, "SetTexCoord", unpack(original.texCoord)) then
                applied.owned.texCoord = false
            else
                success = false
            end
        else
            applied.owned.texCoord = false
        end
    end
    if applied.owned.layer then
        local current = CaptureLayer(region)
        if not current then
            success = false
        elseif SameArray(current, applied.layer) then
            if CallMethod(region, "SetDrawLayer", unpack(original.layer)) then
                applied.owned.layer = false
            else
                success = false
            end
        else
            applied.owned.layer = false
        end
    end
    if applied.owned.points then
        local current = CapturePoints(region)
        if not current then
            success = false
        elseif SamePoints(current, applied.points) then
            if RestorePoints(region, original.points) then
                applied.owned.points = false
            else
                success = false
            end
        else
            applied.owned.points = false
        end
    end
    if applied.owned.size then
        local current = CaptureSize(region)
        if not current then
            success = false
        elseif SameArray(current, applied.size) then
            if CallMethod(region, "SetSize", unpack(original.size)) then
                applied.owned.size = false
            else
                success = false
            end
        else
            applied.owned.size = false
        end
    end

    if not HasOwnedPerformanceProperty(applied) then
        state.performance = nil
    end
    return success
end

local function RefreshOwnedPerformanceRegion(performance, state, visualSize)
    local applied = performance.applied
    local region = performance.region
    local success = true

    if applied.owned.source then
        local current = CaptureTextureSource(region)
        if not current then return false end
        if not SameTextureSource(current, applied.source) then
            applied.owned.source = false
        end
    end
    if applied.owned.texCoord then
        local current = CaptureTexCoord(region)
        if not current then return false end
        if not SameArray(current, applied.texCoord) then
            applied.owned.texCoord = false
        end
    end
    if applied.owned.layer then
        local current = CaptureLayer(region)
        if not current then return false end
        if not SameArray(current, applied.layer) then
            applied.owned.layer = false
        end
    end

    local x = math.max(7, visualSize * 0.5 - 3)
    local desiredPoints = { { "CENTER", state.button, "CENTER", x, 0 } }
    if applied.owned.points then
        local current = CapturePoints(region)
        if not current then
            success = false
        elseif not SamePoints(current, applied.points) then
            applied.owned.points = false
        elseif not SamePoints(applied.points, desiredPoints) then
            local previous = applied.points
            if RestorePoints(region, desiredPoints) then
                applied.points = desiredPoints
            else
                if not RestorePoints(region, previous) then
                    applied.points = CapturePoints(region) or previous
                end
                success = false
            end
        end
    end

    local desiredSize = { 2, Clamp(visualSize - 14, 6, 12) }
    if applied.owned.size then
        local current = CaptureSize(region)
        if not current then
            success = false
        elseif not SameArray(current, applied.size) then
            applied.owned.size = false
        elseif not SameArray(applied.size, desiredSize) then
            local previous = applied.size
            if CallMethod(region, "SetSize", unpack(desiredSize)) then
                applied.size = desiredSize
            else
                if not CallMethod(region, "SetSize", unpack(previous)) then
                    applied.size = CaptureSize(region) or previous
                end
                success = false
            end
        end
    end
    return success
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
    if applied.owned.size then
        if CallMethod(region, "SetSize", unpack(original.size)) then
            applied.owned.size = false
        else
            success = false
        end
    end
    if applied.owned.points then
        if RestorePoints(region, original.points) then
            applied.owned.points = false
        else
            success = false
        end
    end
    if applied.owned.layer then
        if CallMethod(region, "SetDrawLayer", unpack(original.layer)) then
            applied.owned.layer = false
        else
            success = false
        end
    end
    if applied.owned.texCoord then
        if CallMethod(region, "SetTexCoord", unpack(original.texCoord)) then
            applied.owned.texCoord = false
        else
            success = false
        end
    end
    if applied.owned.source then
        if RestorePerformanceSource(region, original.source) then
            applied.owned.source = false
        else
            success = false
        end
    end

    if HasOwnedPerformanceProperty(applied) then
        applied.restoring = true
    else
        state.performance = nil
    end
    return success
end

local function ApplyNewPerformanceRegion(state, visualSize, region)
    if not CapturePerformanceRegion(state, region) then return false end
    local performance = state.performance
    local applied = { owned = {}, restoring = false }
    performance.applied = applied

    local colorOk, r, g, b, a = CallMethod(region, "GetVertexColor")
    if not colorOk or type(r) ~= "number" or type(g) ~= "number"
        or type(b) ~= "number" then
        state.performance = nil
        return false
    end

    local success = true
    if CallMethod(region, "SetColorTexture", 1, 1, 1, 1) then
        applied.source = { atlas = nil, texture = nil }
        applied.owned.source = true
        local captured = CaptureTextureSource(region)
        if captured then
            applied.source = captured
        else
            success = false
        end
        if not CallMethod(region, "SetVertexColor", r, g, b,
            type(a) == "number" and a or 1) then
            success = false
        end
    else
        success = false
    end
    if CallMethod(region, "SetTexCoord", 0, 1, 0, 1) then
        applied.texCoord = { 0, 1, 0, 1 }
        applied.owned.texCoord = true
        local captured = CaptureTexCoord(region)
        if captured then
            applied.texCoord = captured
        else
            success = false
        end
    else
        success = false
    end
    if CallMethod(region, "SetDrawLayer", "OVERLAY", -5) then
        applied.layer = { "OVERLAY", -5 }
        applied.owned.layer = true
        local captured = CaptureLayer(region)
        if captured then
            applied.layer = captured
        else
            success = false
        end
    else
        success = false
    end

    local x = math.max(7, visualSize * 0.5 - 3)
    local desiredPoints = { { "CENTER", state.button, "CENTER", x, 0 } }
    if RestorePoints(region, desiredPoints) then
        applied.points = desiredPoints
        applied.owned.points = true
        local captured = CapturePoints(region)
        if captured then
            applied.points = captured
        else
            success = false
        end
    else
        -- ClearAllPoints may have succeeded before SetPoint failed.
        applied.points = CapturePoints(region) or desiredPoints
        applied.owned.points = true
        success = false
    end

    local desiredSize = { 2, Clamp(visualSize - 14, 6, 12) }
    if CallMethod(region, "SetSize", unpack(desiredSize)) then
        applied.size = desiredSize
        applied.owned.size = true
        local captured = CaptureSize(region)
        if captured then
            applied.size = captured
        else
            success = false
        end
    else
        success = false
    end

    if not success then
        RollbackNewPerformanceRegion(state)
        return false
    end
    return true
end

local function ApplyPerformanceRegion(state, visualSize)
    if state.buttonName ~= "MainMenuMicroButton" then return true end
    local currentRegion = ReadMember(state.button, "MainMenuBarPerformanceBar")
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

local function ConfigureNativeStateMask(state, binding)
    local mask = binding and binding.mask
    if not mask then return false end
    local pointsOk = CallMethod(mask, "SetAllPoints", state.button)
    local textureOk = CallMethod(mask, "SetColorTexture", 0, 0, 0, 0)
    if not textureOk then
        textureOk = CallMethod(mask, "SetTexture", "Interface\\Buttons\\WHITE8X8")
            and CallMethod(mask, "SetVertexColor", 1, 1, 1, 0)
    end
    local hideOk = CallMethod(mask, "Hide")
    binding.shown = false
    binding.ready = pointsOk and textureOk and hideOk
    return binding.ready
end

local function EnsureNativeStateMasks(state)
    state.nativeMasks = state.nativeMasks or {}
    local createMask = ReadMember(state.button, "CreateMaskTexture")
    if type(createMask) ~= "function" then return false end
    local success = true
    for index = 1, #NATIVE_STATE_TEXTURES do
        local key = NATIVE_STATE_TEXTURES[index].key
        local binding = state.nativeMasks[key]
        if not binding then
            if not CanCreate(state.button) then
                success = false
            else
                local ok, mask = pcall(createMask, state.button, nil,
                    "OVERLAY", nil, -4)
                if ok and mask then
                    binding = {
                        mask = mask,
                        applied = false,
                        ready = false,
                        shown = false,
                    }
                    state.nativeMasks[key] = binding
                else
                    success = false
                end
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
    local ok, target = CallMethod(state.button, spec.getter)
    if not ok then return false end

    if binding.applied and binding.target ~= target then
        if not binding.target
            or not CallMethod(binding.target, "RemoveMaskTexture", binding.mask) then
            return false
        end
        binding.applied = false
        binding.target = nil
        if not CallMethod(binding.mask, "Hide") then return false end
        binding.shown = false
    end
    if not target then return true end
    if not binding.applied then
        if not CallMethod(target, "AddMaskTexture", binding.mask) then return false end
        binding.target = target
        binding.applied = true
    end
    if binding.shown then return true end
    if not CallMethod(binding.mask, "Show") then return false end
    binding.shown = true
    return true
end

local function ApplyNativeStateMasks(state)
    local success = EnsureNativeStateMasks(state)
    for index = 1, #NATIVE_STATE_TEXTURES do
        success = ApplyNativeStateMask(state,
            NATIVE_STATE_TEXTURES[index]) and success
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
                if binding.target and CallMethod(binding.target,
                    "RemoveMaskTexture", binding.mask) then
                    binding.applied = false
                    binding.target = nil
                else
                    success = false
                end
            end
            if not binding.applied and not CallMethod(binding.mask, "Hide") then
                success = false
            elseif not binding.applied then
                binding.shown = false
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

local function ApplyLiveBlizzardIcon(state)
    local source
    if state.buttonName == "CharacterMicroButton" then
        source = state.button.Portrait
    else
        source = state.button:GetNormalTexture()
    end
    local atlas = source and source.GetAtlas and source:GetAtlas()
    local texture = source and source.GetTexture and source:GetTexture()
    local kind = atlas and "atlas" or texture and "texture" or nil
    local value = atlas or texture
    if kind == state.nativeIconKind and value == state.nativeIconValue then return source end
    state.nativeIconKind, state.nativeIconValue = kind, value
    if kind == "atlas" then
        state.icon:SetAtlas(value)
    elseif kind == "texture" then
        state.icon:SetTexture(value)
        if state.buttonName == "CharacterMicroButton" and source.GetTexCoord then
            state.icon:SetTexCoord(source:GetTexCoord())
        else
            state.icon:SetTexCoord(0, 1, 0, 1)
        end
    else
        ApplyIconSource(state.icon, state.buttonName, "line")
    end
    return source
end

local function EnsureState(button, buttonName, iconStyle)
    local state = states[button]
    if state then
        if (buttonName and buttonName ~= state.buttonName)
            or (iconStyle and iconStyle ~= state.iconStyle) then
            state.buttonName = buttonName or state.buttonName
            state.iconStyle = iconStyle or state.iconStyle
            state.nativeIconKind, state.nativeIconValue = nil, nil
            ApplyIconSource(state.icon, state.buttonName, state.iconStyle)
        end
        state.masksReady = EnsureNativeStateMasks(state)
        return state
    end
    if not CanCreate(button) or type(ReadMember(button, "CreateTexture")) ~= "function" then
        return nil
    end

    state = {
        button = button,
        buttonName = buttonName,
        iconStyle = iconStyle,
        plate = button:CreateTexture(nil, "OVERLAY", nil, -8),
        fill = button:CreateTexture(nil, "OVERLAY", nil, -7),
        edge = button:CreateTexture(nil, "OVERLAY", nil, -6),
        icon = button:CreateTexture(nil, "OVERLAY", nil, -5),
        nativeMasks = {},
        visible = false,
    }
    for _, region in ipairs({ state.plate, state.fill, state.edge, state.icon }) do
        CallMethod(region, "SetIgnoreParentAlpha", true)
        CallMethod(region, "SetIgnoreParentScale", false)
        CallMethod(region, "Hide")
    end
    state.plate:SetTexture(FOREVER_PLATE)
    ApplyIconSource(state.icon, buttonName, iconStyle)
    states[button] = state
    state.masksReady = EnsureNativeStateMasks(state)
    return state
end

local function NormalizeState(stateName)
    if stateName == "highlight" then return "hover" end
    if stateName == "pushed" then return "pressed" end
    if stateName == "normal" or stateName == "hover"
        or stateName == "pressed" or stateName == "disabled" then
        return stateName
    end
    return "normal"
end

local function RefreshState(state, settings, stateName)
    stateName = NormalizeState(stateName)
    if stateName == "hover" and settings.hoverStyle == "off" then
        stateName = "normal"
    end
    local visualSize = Clamp(settings.buttonSize, 20, 32)
    local iconSize = Clamp(settings.iconSize, 10, visualSize - 4)
    if state.buttonName == "MainMenuMicroButton"
        and ReadMember(state.button, "MainMenuBarPerformanceBar") then
        iconSize = math.min(iconSize, math.max(10, visualSize - 10))
    end
    AnchorSquare(state.fill, state.button, visualSize)
    AnchorSquare(state.edge, state.button, visualSize)
    AnchorSquare(state.icon, state.button, iconSize)
    local nativeIconSource
    if settings.iconStyle == "blizzardIcons" then
        nativeIconSource = ApplyLiveBlizzardIcon(state)
        -- The native Micro Button atlas is 32x40; preserve that ratio inside
        -- our plate rather than stretching Blizzard's glyph into a square.
        if state.buttonName ~= "CharacterMicroButton" then
            state.icon:SetSize(iconSize * 0.8, iconSize)
        end
    end
    AnchorSquare(state.plate, state.button, visualSize + 2)

    state.geometrySpec = GeometrySpec(settings, state.geometrySpec)
    local geometry = NS.Geometry.Resolve(state.geometrySpec, state.geometry)
    state.geometry = geometry
    ConfigureShape(state.fill, geometry.fill, geometry)
    local edgeAsset = geometry.edge
    local showFill = settings.buttonBackground == true
    local showEdge = edgeAsset ~= nil
    local hoverStyle = settings.hoverStyle or "outline"
    local material = NS.Theme.GetMaterial("microButton")

    if stateName == "normal" then
        ApplyMaterial(state.fill, material, state)
        if edgeAsset then
            ConfigureShape(state.edge, edgeAsset, geometry)
            local r, g, b, a = NS.Theme.GetColor(material.border)
            state.edge:SetVertexColor(r, g, b,
                a * NS.Theme.GetBorderOpacity())
        end
    elseif stateName == "hover" then
        ApplyMaterial(state.fill, material, state)
        if hoverStyle == "softFill" or hoverStyle == "solidFill" then
            ApplySolid(state.fill, "hover", hoverStyle == "softFill" and 0.24 or 0.72, state, "fillSolid")
            showFill = true
        end
        if hoverStyle == "outline" or hoverStyle == "softFill"
            or hoverStyle == "solidFill" then
            edgeAsset = geometry.hoverEdge
            showEdge = edgeAsset ~= nil
            if edgeAsset then
                ConfigureShape(state.edge, edgeAsset, geometry)
                ApplySolid(state.edge, "hover", NS.Theme.GetBorderOpacity(), state, "edgeSolid")
            end
        elseif hoverStyle == "iconOnly" or hoverStyle == "off" then
            showEdge = geometry.edge ~= nil and settings.buttonBorder ~= 0
            if geometry.edge then
                ConfigureShape(state.edge, geometry.edge, geometry)
                local r, g, b, a = NS.Theme.GetColor(material.border)
                state.edge:SetVertexColor(r, g, b,
                    a * NS.Theme.GetBorderOpacity())
            end
        end
    elseif stateName == "pressed" then
        ApplySolid(state.fill, "pressed", 0.52, state, "fillSolid")
        showFill = true
        edgeAsset = geometry.hoverEdge
        showEdge = edgeAsset ~= nil
        if edgeAsset then
            ConfigureShape(state.edge, edgeAsset, geometry)
            ApplySolid(state.edge, "pressed", NS.Theme.GetBorderOpacity(), state, "edgeSolid")
        end
    else
        ApplySolid(state.fill, "disabled", 0.18, state, "fillSolid")
        showFill = settings.buttonBackground == true
        if edgeAsset then
            ConfigureShape(state.edge, edgeAsset, geometry)
            ApplySolid(state.edge, "disabled", NS.Theme.GetBorderOpacity() * 0.62, state, "edgeSolid")
        end
    end

    local originalColor
    if nativeIconSource and nativeIconSource.GetVertexColor then
        local r, g, b, a = nativeIconSource:GetVertexColor()
        originalColor = state.nativeIconColor or {}
        originalColor[1], originalColor[2], originalColor[3], originalColor[4] = r, g, b, a
        state.nativeIconColor = originalColor
    end
    local r, g, b, a = NS.MicroMenuSkin.GetIconColor(stateName, originalColor)
    if settings.iconStyle == "blizzardIcons"
        and state.buttonName == "CharacterMicroButton" then
        -- A player portrait is full-color imagery, not a tintable glyph.
        r, g, b = 1, 1, 1
    end
    state.icon:SetVertexColor(r, g, b, a)
    state.icon:SetDesaturated(false)
    state.fill:SetShown(showFill and state.visible)
    state.edge:SetShown(showEdge and state.visible)
    local decorated = (settings.iconStyle == "bold" or settings.iconStyle == "blizzardIcons")
        and (settings.barMaterial == "forever" or settings.barMaterial == "modern"
            or settings.barMaterial == "midnightDark")
    if decorated and state.plateMaterial ~= settings.barMaterial then
        state.plate:SetTexture(settings.barMaterial == "forever" and FOREVER_PLATE or MIDNIGHT_PLATE)
        state.plate:SetDesaturated(settings.barMaterial == "midnightDark")
        if settings.barMaterial == "midnightDark" then
            state.plate:SetVertexColor(0.84, 0.85, 0.82, 1)
        else
            state.plate:SetVertexColor(1, 1, 1, 1)
        end
        state.plateMaterial = settings.barMaterial
    end
    state.plate:SetShown(state.visible and decorated)
    state.icon:SetShown(state.visible)
    local performanceOk = ApplyPerformanceRegion(state, visualSize)
    local masksOk = ApplyNativeStateMasks(state)
    state.currentState = stateName
    return performanceOk and masksOk
end

function MicroMenuVisual.Prepare(button, buttonName, settings)
    if not button or not settings then return false end
    local nativeStyle = settings.iconStyle == "blizzard"
    local state = EnsureState(button, buttonName,
        nativeStyle and "line" or settings.iconStyle)
    if not state then return false end
    if nativeStyle then
        -- Preallocate only. Native art remains entirely visible in Blizzard
        -- mode, while a later clean-style switch needs no CreateTexture or
        -- CreateMaskTexture call below an already-owned MicroMenu root.
        state.visible = false
        CallMethod(state.fill, "Hide")
        CallMethod(state.edge, "Hide")
        CallMethod(state.plate, "Hide")
        CallMethod(state.icon, "Hide")
        state.masksReady = EnsureNativeStateMasks(state)
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
    if settings.iconStyle == "blizzard" then
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
    return RefreshState(state, settings, stateName), "refreshed"
end

function MicroMenuVisual.Restore(button)
    local state = states[button]
    if not state then return true end
    local success = RestoreNativeStateMasks(state)
    success = RestorePerformanceRegion(state) and success
    state.visible = false
    state.fill:Hide()
    state.edge:Hide()
    state.plate:Hide()
    state.icon:Hide()
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
