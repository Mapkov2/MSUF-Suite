local _, NS = ...

-- Independent, reversible artwork for exact Blizzard window/action buttons.
-- The native Button remains the sole owner of clicks, scripts, narration,
-- visibility, enabled state, geometry and tooltips. We only replace its four
-- texture slots with project-owned glyph textures outside combat.
local WindowActionSkin = {
    states = setmetatable({}, { __mode = "k" }),
    owners = {},
}
NS.WindowActionSkin = WindowActionSkin

-- A combat-delayed visual request must not outlive an owner-wide disable. The
-- generation invalidates older requests; the blocked state rejects later
-- combat requests, and a distinct owner-disable barrier guarantees cleanup
-- regardless of drain order.
local ownerGenerations = setmetatable({}, { __mode = "k" })
local blockedOwners = setmetatable({}, { __mode = "k" })

local FINE_ATLAS = NS.path .. "Media\\WindowActions\\MapkoSkinWindowActionsFine.png"
local BOLD_ATLAS = NS.path .. "Media\\WindowActions\\MapkoSkinWindowActionsBold.png"
local ATLAS_SLOTS = 8

local validKinds = {
    close = true,
    maximize = true,
    minimize = true,
    add = true,
    remove = true,
    expand = true,
    collapse = true,
}

local glyphCells = {
    close = 0,
    plus = 1,
    minus = 2,
    up = 3,
    down = 4,
}

local specialTextures = {
    { key = "normal", getter = "GetNormalTexture", setter = "SetNormalTexture" },
    { key = "pushed", getter = "GetPushedTexture", setter = "SetPushedTexture" },
    { key = "disabled", getter = "GetDisabledTexture", setter = "SetDisabledTexture" },
    { key = "highlight", getter = "GetHighlightTexture", setter = "SetHighlightTexture" },
}

local buttonArtKitSuffixes = {
    normal = "",
    pushed = "-Pressed",
    disabled = "-Disabled",
    highlight = "-Highlight",
}

local Safety = NS.Safety

local function Field(object, key)
    return Safety.Field(object, key) or nil
end

-- The first result of a getter, or nil.
local function Getter(object, method)
    return Safety.Call(object, method) or nil
end

local function AccessibleAlpha(region)
    return tonumber(Safety.Read(region, "GetAlpha"))
end

local function Wipe(target)
    for key in pairs(target) do target[key] = nil end
    return target
end

local function IsListed(list, value)
    for index = 1, #list do
        if list[index] == value then return true end
    end
    return false
end

local function Settings()
    return NS.DB and NS.DB.icons and NS.DB.icons.windowActions
        or NS.Defaults.icons.windowActions
end

local function CanApply(button)
    return button and Safety.CanCreateRegions(button, true)
        and type(Field(button, "CreateTexture")) == "function"
end

local function OwnerSet(owner)
    if owner == nil then return nil end
    local set = WindowActionSkin.owners[owner]
    if not set then
        set = setmetatable({}, { __mode = "k" })
        WindowActionSkin.owners[owner] = set
    end
    return set
end

local function OwnerGeneration(owner)
    return owner ~= nil and (ownerGenerations[owner] or 0) or 0
end

local function InvalidateOwnerRequests(owner)
    if owner == nil then return end
    ownerGenerations[owner] = OwnerGeneration(owner) + 1
    blockedOwners[owner] = true
end

local function BeginOwnerRequest(owner)
    if owner ~= nil and not NS.IsCombatLocked() then blockedOwners[owner] = nil end
end

local function DeferOwnerRequest(key, owner, callback)
    local generation = OwnerGeneration(owner)
    return NS.CombatGate.RunOrDefer(key, function()
        if owner ~= nil and (blockedOwners[owner]
            or OwnerGeneration(owner) ~= generation) then return end
        callback()
    end)
end

local function BindOwner(button, state, owner)
    if state.owner ~= nil and state.owner ~= owner then return false end
    state.owner = owner
    local set = OwnerSet(owner)
    if set then set[button] = true end
    return true
end

-- The state-texture setters reject nil. A slot that had no native texture
-- keeps our glyph, which is hidden on restore.
local function SetSpecialTexture(button, setter, texture, blendMode)
    if texture == nil then return false end
    if blendMode then
        return Safety.Invoke(button, setter, texture, blendMode)
    end
    return Safety.Invoke(button, setter, texture)
end

local function ReadBlendMode(texture)
    local value = Safety.Read(texture, "GetBlendMode")
    return type(value) == "string" and value or nil
end

local function SnapshotNative(button, state)
    local native = Wipe(state.native)
    for index = 1, #specialTextures do
        local definition = specialTextures[index]
        native[definition.key] = Getter(button, definition.getter)
    end
    native.highlightBlendMode = ReadBlendMode(native.highlight)
    state.nativeCaptured = true
end

local function HideGlyphs(state)
    if not state.glyphs then return end
    for _, glyph in pairs(state.glyphs) do
        glyph:Hide()
    end
end

local function RestoreExtraRegions(state)
    for region, snapshot in pairs(state.extraRegions) do
        if AccessibleAlpha(region) == 0 then
            region:SetAlpha(snapshot.alpha)
        end
        state.extraRegions[region] = nil
    end
end

local function RestoreNative(button, state)
    if not state.nativeCaptured then return end
    for index = 1, #specialTextures do
        local definition = specialTextures[index]
        local glyph = state.glyphs and state.glyphs[definition.key]
        if glyph and Getter(button, definition.getter) == glyph then
            local blendMode = definition.key == "highlight"
                and state.native.highlightBlendMode or nil
            SetSpecialTexture(button, definition.setter,
                state.native[definition.key], blendMode)
        end
    end
    HideGlyphs(state)
    RestoreExtraRegions(state)
    Wipe(state.native)
    state.nativeCaptured = false
end

local function RebaseNative(state)
    -- Blizzard or another owner replaced our state slots after Apply. Those
    -- newer slots win; discard the old snapshot instead of overwriting them.
    HideGlyphs(state)
    RestoreExtraRegions(state)
    Wipe(state.native)
    state.nativeCaptured = false
end

local function SyncNativeAtlases(button, state)
    if not state.nativeCaptured or not state.glyphs then return true end
    -- Normal and Pushed only: the first two state slots.
    for index = 1, 2 do
        local definition = specialTextures[index]
        local glyph = state.glyphs[definition.key]
        if Getter(button, definition.getter) ~= glyph then
            return false
        end
        local atlas = Safety.Read(glyph, "GetAtlas")
        if type(atlas) == "string" then
            -- Dynamic Blizzard controls rewrite the active Normal/Pushed
            -- texture objects in place. Mirror that state into the hidden
            -- native textures before repainting our glyphs so Native/Disable
            -- always restores the current semantic action, not a stale one.
            Safety.Invoke(state.native[definition.key], "SetAtlas", atlas, true)
        end
    end
    return true
end

local function MatchesButtonArtKit(button, artKit)
    if type(artKit) ~= "string" or artKit == "" then return false end
    for index = 1, #specialTextures do
        local definition = specialTextures[index]
        local atlas = Safety.Read(Getter(button, definition.getter), "GetAtlas")
        local expected = artKit .. buttonArtKitSuffixes[definition.key]
        if type(atlas) ~= "string" or atlas:lower() ~= expected:lower() then
            return false
        end
    end
    return true
end

local function SyncNativeButtonArtKit(button, state, artKit)
    if not state.nativeCaptured or not state.glyphs then return true end
    if not MatchesButtonArtKit(button, artKit) then return false end

    -- UIButtonMixin:SetButtonArtKit rewrites all four active texture objects
    -- in place. When those objects are our glyphs, mirror the complete kit to
    -- the hidden native textures before repainting or restoring them.
    for index = 1, #specialTextures do
        local definition = specialTextures[index]
        if Getter(button, definition.getter) ~= state.glyphs[definition.key] then
            return false
        end
        local native = state.native[definition.key]
        if type(Field(native, "SetAtlas")) ~= "function" then return false end
    end
    for index = 1, #specialTextures do
        local definition = specialTextures[index]
        local expected = artKit .. buttonArtKitSuffixes[definition.key]
        if not Safety.Invoke(state.native[definition.key], "SetAtlas", expected, true) then
            return false
        end
    end
    return true
end

local function CreateGlyph(button, layer, subLevel)
    local texture = button:CreateTexture(nil, layer, nil, subLevel)
    texture:SetPoint("CENTER", button, "CENTER", 0, 0)
    if type(texture.SetSnapToPixelGrid) == "function" then
        texture:SetSnapToPixelGrid(false)
    end
    if type(texture.SetTexelSnappingBias) == "function" then
        texture:SetTexelSnappingBias(0)
    end
    return texture
end

-- Callers have verified that the button accepts owned regions.
local function EnsureGlyphs(button, state)
    if state.glyphs then return end
    state.glyphs = {
        normal = CreateGlyph(button, "ARTWORK", 6),
        pushed = CreateGlyph(button, "ARTWORK", 6),
        disabled = CreateGlyph(button, "ARTWORK", 6),
        highlight = CreateGlyph(button, "HIGHLIGHT", 6),
    }
end

local function GlyphKey(kind, glyphMode)
    if kind == "close" then return "close" end
    if kind == "add" then return "plus" end
    if kind == "remove" then return "minus" end
    if glyphMode == "chevrons" then
        if kind == "maximize" or kind == "expand" then return "up" end
        return "down"
    end
    if kind == "maximize" or kind == "expand" then return "plus" end
    return "minus"
end

local function ColorRole(kind, stateName)
    if kind == "close" then
        if stateName == "pushed" then return "blizzardClosePressed" end
        if stateName == "highlight" then return "blizzardCloseHover" end
        if stateName == "disabled" then return "blizzardCloseDisabled" end
        return "blizzardClose"
    end
    if stateName == "pushed" then return "blizzardExpandPressed" end
    if stateName == "highlight" then return "blizzardExpandHover" end
    if stateName == "disabled" then return "disabled" end
    return "blizzardExpand"
end

local function ConfigureGlyph(glyph, atlas, cell, size, role, alphaScale)
    glyph:SetTexture(atlas)
    glyph:SetTexCoord(cell / ATLAS_SLOTS, (cell + 1) / ATLAS_SLOTS, 0, 1)
    glyph:SetSize(size, size)
    local r, g, b, a = NS.Theme.GetColor(role)
    glyph:SetVertexColor(r, g, b, (tonumber(a) or 1) * alphaScale)
    glyph:Show()
end

local function AnchorGlyphs(button, state, settings)
    local x = math.floor((tonumber(settings.glyphOffsetX) or 0) + 0.5)
    local y = math.floor((tonumber(settings.glyphOffsetY) or 0) + 0.5)
    for _, glyph in pairs(state.glyphs) do
        glyph:ClearAllPoints()
        glyph:SetPoint("CENTER", button, "CENTER", x, y)
    end
end

local function ConfigureGlyphs(button, state, settings)
    local glyphKey = GlyphKey(state.kind, settings.glyphMode)
    local cell = glyphCells[glyphKey]
    local atlas = settings.weight == "bold" and BOLD_ATLAS or FINE_ATLAS
    local configuredSize = state.kind == "close"
        and settings.closeGlyphSize or settings.glyphSize
    local size = math.floor((tonumber(configuredSize) or 12) + 0.5)
    local idle = tonumber(settings.opacity) or 0.78
    AnchorGlyphs(button, state, settings)
    ConfigureGlyph(state.glyphs.normal, atlas, cell, size,
        ColorRole(state.kind, "normal"), idle)
    ConfigureGlyph(state.glyphs.pushed, atlas, cell, size,
        ColorRole(state.kind, "pushed"), 1)
    ConfigureGlyph(state.glyphs.disabled, atlas, cell, size,
        ColorRole(state.kind, "disabled"), math.min(idle, 0.55))
    ConfigureGlyph(state.glyphs.highlight, atlas, cell, size,
        ColorRole(state.kind, "highlight"), math.max(0.35, 1 - idle + 0.35))
end

local function AssignGlyphStates(button, state)
    return SetSpecialTexture(button, "SetNormalTexture", state.glyphs.normal)
        and SetSpecialTexture(button, "SetPushedTexture", state.glyphs.pushed)
        and SetSpecialTexture(button, "SetDisabledTexture", state.glyphs.disabled)
        and SetSpecialTexture(button, "SetHighlightTexture", state.glyphs.highlight, "BLEND")
end

local function FadeExtraRegion(state, region)
    if type(Field(region, "SetAlpha")) ~= "function" then return end
    local current = AccessibleAlpha(region)
    if current == nil then return end
    local snapshot = state.extraRegions[region]
    if not snapshot then
        snapshot = { alpha = current }
        state.extraRegions[region] = snapshot
    end
    if current == snapshot.alpha or current == 0 then
        region:SetAlpha(0)
    end
end

local function RefreshExtraRegions(button, state)
    if state.kind == "close" or state.kind == "minimize" then
        FadeExtraRegion(state, Field(button, "Border"))
    end
    if state.kind == "expand" or state.kind == "collapse" then
        FadeExtraRegion(state, Field(button, "Icon"))
    end
end

-- One spec serves every action surface: all of them follow the same
-- settings, and every refresh rewrites it before the surface reads it.
local surfaceSpec = {
    role = "button",
    pillHeight = 24,
    allowImplicitProtected = true,
}

local function SurfaceSpec(settings)
    local shape = settings.surfaceShape
    surfaceSpec.useControlShape = shape == "global"
    surfaceSpec.shape = shape ~= "global" and shape or nil
    surfaceSpec.radius = tonumber(settings.surfaceRadius) or 4
    surfaceSpec.inset = tonumber(settings.surfaceInset) or 2
    surfaceSpec.border = settings.style == "outline" and 1 or 0
    surfaceSpec.fillVisible = settings.style == "soft"
    return surfaceSpec
end

local function RefreshSurface(button, settings)
    if settings.style ~= "soft" and settings.style ~= "outline" then
        if NS.Registry.GetSurface(button) then NS.Surface.SetVisible(button, false) end
        return true
    end
    local surface = NS.Surface.Attach(button, SurfaceSpec(settings))
    if not surface then return false end
    NS.Surface.SetVisible(button, true)
    return true
end

function WindowActionSkin.HasOwnedStates(button)
    local state = WindowActionSkin.states[button]
    if not state or not state.glyphs or not state.nativeCaptured then return false end
    for index = 1, #specialTextures do
        local definition = specialTextures[index]
        if Getter(button, definition.getter) ~= state.glyphs[definition.key] then
            return false
        end
    end
    return true
end

local function ApplyNow(button, owner, kind)
    if not CanApply(button) then return nil, "protected control" end
    if not validKinds[kind] then return nil, "unknown action" end

    local state = WindowActionSkin.states[button]
    if state and not BindOwner(button, state, owner) then
        return nil, "owned by another adapter"
    end
    if not state then
        state = {
            owner = owner,
            kind = kind,
            native = {},
            extraRegions = setmetatable({}, { __mode = "k" }),
            visible = false,
        }
        WindowActionSkin.states[button] = state
        BindOwner(button, state, owner)
    elseif state.nativeCaptured and not WindowActionSkin.HasOwnedStates(button) then
        local detected = NS.Checkmarks and NS.Checkmarks.DetectWindowAction
            and NS.Checkmarks.DetectWindowAction(button) or nil
        if detected then
            RebaseNative(state)
            kind = detected
        else
            return nil, "state texture ownership changed"
        end
    end
    state.kind = kind

    local settings = Settings()
    state.style = settings.style
    state.glyphMode = settings.glyphMode
    state.weight = settings.weight

    if settings.style == "native" then
        local restoredModern = state.nativeCaptured == true
        RestoreNative(button, state)
        RefreshSurface(button, settings)
        state.visible = true
        if restoredModern and NS.Checkmarks and not state.repaintingNative then
            state.repaintingNative = true
            NS.Checkmarks.TrackButton(button, owner)
            state.repaintingNative = false
        end
        return state
    end

    if not state.nativeCaptured then SnapshotNative(button, state) end
    EnsureGlyphs(button, state)
    ConfigureGlyphs(button, state, settings)
    if not RefreshSurface(button, settings) or not AssignGlyphStates(button, state) then
        RestoreNative(button, state)
        return nil, "state textures unavailable"
    end
    RefreshExtraRegions(button, state)
    state.visible = true
    return state
end

function WindowActionSkin.Apply(button, owner, kind)
    if not button then return nil, "invalid control" end
    BeginOwnerRequest(owner)
    if NS.IsCombatLocked() then
        local _, reason = DeferOwnerRequest("window-action:" .. tostring(button), owner, function()
            ApplyNow(button, owner, kind)
        end)
        return nil, reason or "combat"
    end
    return ApplyNow(button, owner, kind)
end

function WindowActionSkin.Track(button, owner, kind)
    if kind == nil and NS.Checkmarks then
        kind = NS.Checkmarks.DetectWindowAction(button)
            or (WindowActionSkin.HasOwnedStates(button)
                and WindowActionSkin.GetKind(button) or nil)
    end
    return WindowActionSkin.Apply(button, owner, kind)
end

local function SyncNativeVisualNow(button, owner, kind)
    local state = WindowActionSkin.states[button]
    if state and state.visible and state.owner ~= owner then
        return nil, "owned by another adapter"
    end
    if state and not SyncNativeAtlases(button, state) then
        return nil, "state texture ownership changed"
    end
    return ApplyNow(button, owner, kind)
end

function WindowActionSkin.SyncNativeVisual(button, owner, kind)
    if not button then return nil, "invalid control" end
    BeginOwnerRequest(owner)
    if NS.IsCombatLocked() then
        local _, reason = DeferOwnerRequest("window-action:" .. tostring(button), owner, function()
            SyncNativeVisualNow(button, owner, kind)
        end)
        return nil, reason or "combat"
    end
    return SyncNativeVisualNow(button, owner, kind)
end

-- Exact lifecycle adapters use this only after Blizzard has intentionally
-- replaced the active state slots. Unknown changes still go through the normal
-- compare-and-swap path and fail closed.
local function AdoptNativeVisualNow(button, owner, kind)
    local state = WindowActionSkin.states[button]
    if state and state.visible and state.owner ~= owner then
        return nil, "owned by another adapter"
    end
    if state and state.visible and state.nativeCaptured then
        if WindowActionSkin.HasOwnedStates(button) then
            if not SyncNativeAtlases(button, state) then
                return nil, "state texture ownership changed"
            end
        else
            -- The trusted lifecycle may replace only Normal/Pushed. Restore
            -- any untouched slots that still reference our glyphs, retain the
            -- newly supplied slots, then capture that complete native set.
            RestoreNative(button, state)
        end
    end
    return ApplyNow(button, owner, kind)
end

function WindowActionSkin.AdoptNativeVisual(button, owner, kind)
    if not button then return nil, "invalid control" end
    BeginOwnerRequest(owner)
    if NS.IsCombatLocked() then
        local _, reason = DeferOwnerRequest("window-action:" .. tostring(button), owner, function()
            AdoptNativeVisualNow(button, owner, kind)
        end)
        return nil, reason or "combat"
    end
    return AdoptNativeVisualNow(button, owner, kind)
end

function WindowActionSkin.Refresh(button)
    local state = WindowActionSkin.states[button]
    if not state or not state.visible then return false, "unknown action" end
    if state.owner ~= nil and blockedOwners[state.owner] then
        return false, "owner disabled"
    end
    local refreshed, reason = WindowActionSkin.Apply(button, state.owner, state.kind)
    return refreshed ~= nil, reason
end

local function DisableNow(button, state)
    RestoreNative(button, state)
    if NS.Registry.GetSurface(button) then NS.Surface.SetVisible(button, false) end
    state.visible = false
    local set = state.owner ~= nil and WindowActionSkin.owners[state.owner] or nil
    if set then set[button] = nil end
    -- Keep the four hidden child textures as a button-local reusable resource.
    -- WoW cannot delete regions; dropping this weak state would allocate four
    -- more textures on every disable/enable or profile cycle.
    state.owner = nil
    return true
end

local function SyncButtonArtKitNow(button, owner, artKit, kind)
    if not MatchesButtonArtKit(button, artKit) then
        return nil, "button art kit changed"
    end
    local state = WindowActionSkin.states[button]
    if state and state.visible and state.owner ~= owner then
        return nil, "owned by another adapter"
    end
    if state and state.visible and state.nativeCaptured then
        if WindowActionSkin.HasOwnedStates(button) then
            if not SyncNativeButtonArtKit(button, state, artKit) then
                return nil, "state texture ownership changed"
            end
        else
            -- Also tolerate the equivalent slot-replacement implementation in
            -- older templates: CAS restore keeps every newly supplied slot.
            RestoreNative(button, state)
        end
    end
    if kind ~= nil then return ApplyNow(button, owner, kind) end
    if state and state.visible then return DisableNow(button, state) end
    return true
end

-- Dedicated trusted lifecycle for UIButtonMixin:SetButtonArtKit. Unlike the
-- generic dynamic-action path, this method synchronizes Normal, Pushed,
-- Disabled and Highlight because Blizzard rewrites the complete art kit.
function WindowActionSkin.SyncButtonArtKit(button, owner, artKit, kind)
    if not button then return nil, "invalid control" end
    if type(artKit) ~= "string" or artKit == "" then
        return nil, "invalid art kit"
    end
    if kind ~= nil and not validKinds[kind] then return nil, "unknown action" end
    BeginOwnerRequest(owner)
    if NS.IsCombatLocked() then
        local _, reason = DeferOwnerRequest("window-action:" .. tostring(button), owner,
            function()
                SyncButtonArtKitNow(button, owner, artKit, kind)
            end)
        return nil, reason or "combat"
    end
    return SyncButtonArtKitNow(button, owner, artKit, kind)
end

function WindowActionSkin.Disable(button, owner)
    local state = WindowActionSkin.states[button]
    if not state or not state.visible then return true end
    if owner ~= nil and state.owner ~= owner then return false, "owner mismatch" end
    if NS.IsCombatLocked() then
        local _, reason = NS.CombatGate.RunOrDefer("window-action:" .. tostring(button), function()
            WindowActionSkin.Disable(button, owner)
        end)
        return false, reason or "combat"
    end
    return DisableNow(button, state)
end

function WindowActionSkin.RefreshOwner(owner)
    local set = WindowActionSkin.owners[owner]
    if not set then return true end
    if owner ~= nil and blockedOwners[owner] then return false, "owner disabled" end
    if NS.IsCombatLocked() then
        local _, reason = NS.CombatGate.RunOrDefer("window-action-owner:" .. tostring(owner), function()
            WindowActionSkin.RefreshOwner(owner)
        end)
        return false, reason or "combat"
    end
    for button in pairs(set) do
        local state = WindowActionSkin.states[button]
        if state and state.visible then ApplyNow(button, owner, state.kind) end
    end
    return true
end

function WindowActionSkin.DisableOwner(owner)
    InvalidateOwnerRequests(owner)
    if NS.IsCombatLocked() then
        local _, reason = NS.CombatGate.RunOrDefer(
            "window-action-owner-disable:" .. tostring(owner), function()
            WindowActionSkin.DisableOwner(owner)
        end)
        return false, reason or "combat"
    end
    local set = WindowActionSkin.owners[owner]
    if not set then return true end
    local buttons = {}
    for button in pairs(set) do buttons[#buttons + 1] = button end
    for index = 1, #buttons do
        local button = buttons[index]
        local state = WindowActionSkin.states[button]
        if state and state.visible and state.owner == owner then DisableNow(button, state) end
    end
    WindowActionSkin.owners[owner] = nil
    return true
end

WindowActionSkin.UntrackOwner = WindowActionSkin.DisableOwner

function WindowActionSkin.Restore()
    if NS.IsCombatLocked() then
        local _, reason = NS.CombatGate.RunOrDefer("window-action:restore", WindowActionSkin.Restore)
        return false, reason or "combat"
    end
    local buttons = {}
    for button in pairs(WindowActionSkin.states) do buttons[#buttons + 1] = button end
    for index = 1, #buttons do
        local state = WindowActionSkin.states[buttons[index]]
        if state and state.visible then DisableNow(buttons[index], state) end
    end
    WindowActionSkin.owners = {}
    return true
end

function WindowActionSkin.RefreshAll()
    if NS.IsCombatLocked() then
        local _, reason = NS.CombatGate.RunOrDefer("window-action:refresh-all", WindowActionSkin.RefreshAll)
        return false, reason or "combat"
    end
    local buttons = {}
    for button in pairs(WindowActionSkin.states) do buttons[#buttons + 1] = button end
    for index = 1, #buttons do
        local state = WindowActionSkin.states[buttons[index]]
        if state and state.visible then WindowActionSkin.Refresh(buttons[index]) end
    end
    return true
end

function WindowActionSkin.OnNativeChanged(button)
    local state = WindowActionSkin.states[button]
    if not state or not state.visible then return false, "unknown action" end
    if NS.IsCombatLocked() then
        local _, reason = NS.CombatGate.RunOrDefer("window-action:" .. tostring(button), function()
            WindowActionSkin.OnNativeChanged(button)
        end)
        return false, reason or "combat"
    end
    local kind = NS.Checkmarks and NS.Checkmarks.DetectWindowAction
        and NS.Checkmarks.DetectWindowAction(button) or nil
    if not kind then return WindowActionSkin.Disable(button, state.owner) end
    return WindowActionSkin.Apply(button, state.owner, kind) ~= nil
end

function WindowActionSkin.SetOption(key, value)
    if NS.IsCombatLocked() then return false, "combat" end
    local settings = Settings()
    if key == "style" then
        if not IsListed(NS.WindowActionStyles, value) then return false, "invalid value" end
    elseif key == "glyphMode" then
        if not IsListed(NS.WindowActionGlyphModes, value) then return false, "invalid value" end
    elseif key == "weight" then
        if not IsListed(NS.WindowActionWeights, value) then return false, "invalid value" end
    elseif key == "glyphSize" then
        value = tonumber(value)
        if not value or value < 8 or value > 18 then return false, "invalid value" end
        value = math.floor(value + 0.5)
    elseif key == "closeGlyphSize" then
        value = tonumber(value)
        if not value or value < 6 or value > 18 then return false, "invalid value" end
        value = math.floor(value + 0.5)
    elseif key == "glyphOffsetX" or key == "glyphOffsetY" then
        value = tonumber(value)
        if not value or value < -4 or value > 4 then return false, "invalid value" end
        value = math.floor(value + 0.5)
    elseif key == "surfaceInset" then
        value = tonumber(value)
        if not value or value < 0 or value > 6 then return false, "invalid value" end
        value = math.floor(value + 0.5)
    elseif key == "surfaceShape" then
        if not IsListed(NS.WindowActionShapes, value) then return false, "invalid value" end
    elseif key == "surfaceRadius" then
        value = tonumber(value)
        if not IsListed(NS.GeometryRadii, value) then return false, "invalid value" end
    elseif key == "opacity" then
        value = tonumber(value)
        if not value or value < 0.35 or value > 1 then return false, "invalid value" end
    else
        return false, "unknown option"
    end
    settings[key] = value
    WindowActionSkin.RefreshAll()
    if NS.Registry then NS.Registry.NotifyListeners("windowAction", key) end
    return true
end

function WindowActionSkin.ResetRecommended()
    if NS.IsCombatLocked() then return false, "combat" end
    local defaults = NS.Defaults.icons.windowActions
    local settings = Settings()
    for key, value in pairs(defaults) do settings[key] = value end
    local refreshed, reason = WindowActionSkin.RefreshAll()
    if NS.Registry then NS.Registry.NotifyListeners("windowAction", "reset") end
    return refreshed, reason
end

function WindowActionSkin.GetState(button)
    local state = WindowActionSkin.states[button]
    return state and state.visible and state or nil
end
function WindowActionSkin.GetKind(button)
    local state = WindowActionSkin.states[button]
    return state and state.visible and state.kind or nil
end
function WindowActionSkin.GetOwner(button)
    local state = WindowActionSkin.states[button]
    return state and state.visible and state.owner or nil
end
function WindowActionSkin.IsApplied(button)
    local state = WindowActionSkin.states[button]
    return state ~= nil and state.visible == true
end
function WindowActionSkin.GetStatus()
    local count = 0
    for _, state in pairs(WindowActionSkin.states) do
        if state.visible then count = count + 1 end
    end
    return { applied = count, style = Settings().style }
end

function WindowActionSkin:OnThemeChanged(domain)
    if domain == "windowAction" then return end
    if domain == "color" or domain == "theme" or domain == "appearance"
        or domain == "geometry" or domain == "profile" then
        WindowActionSkin.RefreshAll()
    end
end

NS.Registry.AddListener(WindowActionSkin, WindowActionSkin.OnThemeChanged)

return WindowActionSkin
