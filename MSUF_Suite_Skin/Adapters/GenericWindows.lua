local _, NS = ...

-- Catalog-driven, conservative coverage for Blizzard windows which do not
-- need a purpose-built adapter. The catalog supplies roots; this module only
-- walks their bounded child trees once when the root (or its LoD addon) is
-- available. It never scans the global frame list or polls. The shared
-- Surface layer attaches enter/leave hooks only to safe, skinned menu buttons.
--
-- Four files, in TOC order:
--   GenericWindows.lua         owner state, native chrome and its fading,
--                              the theme listener and disabling an owner
--   GenericWindowsNodes.lua    the skinning of single nodes
--   GenericWindowsFrames.lua   frame passes: named controls, the bounded
--                              child traversal and pooled ScrollBox rows
--   GenericWindowsCatalog.lua  catalog entries, load-on-demand and status
local GenericWindows = {
    maxDepth = 6,
    maxNodes = 480,
}
NS.GenericWindows = GenericWindows

local Safety = NS.Safety
local Field = Safety.Field
local Kit = NS.AdapterKit

local DEFAULT_OWNER = "blizzardWindows"

local frameStates = Kit.WeakSet()
local ownerStates = {}
local themeListenerRegistered = false

local backgroundFields = {
    "Bg", "BG", "Background", "background", "Backdrop",
    "bg", "ClassBackground", "BuybackBG", "TopBarBg", "TextBackground",
    "ModelBackground", "InboxFrameBg", "evergreenBg", "LoreBackground",
    "PageBackground", "PanelBackground", "ListBackground", "BlackBG",
    "BackgroundOverlay", "BackgroundTopLeft", "BackgroundTopRight",
    "BackgroundBotLeft", "BackgroundBotRight", "BgTop", "BgMiddle", "BgBottom",
    "ModelNameBackground", "ShadowOverlay",
    "InsetBorderBottomLeft", "InsetBorderBottomRight", "InsetBorderBottom",
    "InsetBorderLeft", "InsetBorderRight",
    "TopTileStreaks", "BottomTileStreaks", "BackgroundTile",
    "BackgroundTexture", "TitleBg", "TitleBG", "HeaderBg", "HeaderBG",
    "FooterBg", "FooterBG", "InsetBg", "InsetBG", "PortraitOverlay",
}

local nineSliceFields = {
    "NineSlice", "Border", "InsetBorder", "BackgroundNineSlice",
}

local nineSlicePieceFields = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}


local dialogHeaderFields = { "LeftBG", "CenterBG", "RightBG" }
local flatBackgroundFields = { "BottomLeft", "BottomRight", "BottomEdge", "TopSection" }
-- Retail TranslucentFrameTemplate predates NineSlicePanelTemplate. Its dialog
-- border is eight direct texture members on the frame instead of a NineSlice
-- child. Require the complete inherited contract (including Bg) so similarly
-- named semantic corners or item borders fail closed.
local translucentFrameBorderFields = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopBorder", "BottomBorder", "LeftBorder", "RightBorder",
}

-- Shared/Dialog/DialogTemplates.xml gives every non-secure DialogBorder*
-- variant the "Dialog" NineSlice layout. Require that key-value plus all
-- eight direct DiamondMetal pieces so arbitrary semantic NineSlices are never
-- consumed. SecureDialogBorder* writes similar pieces manually but has no
-- layoutType and therefore deliberately fails this contract.
local dialogBorderFields = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
}

-- Pooled ScrollBox rows share one mode per protection/menu variant.
local function RowMode(allowImplicitProtected, menuPopup)
    return {
        role = "card",
        radius = 4,
        inset = 0,
        listItem = true,
        maxDepth = 4,
        maxNodes = 120,
        allowImplicitProtected = allowImplicitProtected,
        menuPopup = menuPopup,
    }
end

local rowModes = {
    [true] = { [true] = RowMode(true, true), [false] = RowMode(true, false) },
    [false] = { [true] = RowMode(false, true), [false] = RowMode(false, false) },
}

local function CanSkin(frame, allowImplicitProtected)
    return Safety.CanCreateRegions(frame, allowImplicitProtected)
end

local function ObjectName(object)
    local name = Safety.Read(object, "GetName")
    return type(name) == "string" and name or ""
end

local function HasAnyField(object, fields)
    for index = 1, #fields do
        if Field(object, fields[index]) ~= nil then return true end
    end
    return false
end

local function OwnerState(owner)
    owner = owner or DEFAULT_OWNER
    local state = ownerStates[owner]
    if not state then
        state = {
            surfaces = Kit.WeakSet(),
            frames = Kit.WeakSet(),
            glyphs = Kit.WeakSet(),
            glyphRoles = Kit.WeakSet(),
            scrollBoxes = Kit.WeakSet(),
            -- row -> generation of its last full skin pass
            skinnedRows = Kit.WeakSet(),
            generation = 1,
            deferred = {},
            active = true,
        }
        ownerStates[owner] = state
    end
    return state, owner
end

local function OwnerKey(owner)
    return tostring(owner or DEFAULT_OWNER)
end

local function TrackSurface(owner, target)
    OwnerState(owner).surfaces[target] = true
end

local function CountControl(owner, control, metrics)
    TrackSurface(owner, control)
    if not metrics.controlTargets[control] then
        metrics.controlTargets[control] = true
        metrics.controls = metrics.controls + 1
    end
end

local function Attach(owner, target, spec, metrics)
    if not target or not CanSkin(target, spec.allowImplicitProtected) then
        return false
    end
    if not NS.Surface.Attach(target, spec) then
        metrics.errors = metrics.errors + 1
        return false
    end
    TrackSurface(owner, target)
    if not metrics.surfaceTargets[target] then
        metrics.surfaceTargets[target] = true
        metrics.surfaces = metrics.surfaces + 1
    end
    return true
end

-- targets collects regions faded on a root so a later preserveRootArt pass
-- can restore exactly those.
local function Fade(owner, region, targets)
    if type(region) == "table" and NS.Cosmetics.Fade(region, owner) and targets then
        targets[region] = true
    end
end

local function FadeFields(owner, object, fields, targets)
    for index = 1, #fields do
        Fade(owner, Field(object, fields[index]), targets)
    end
end

local function HasDirectTextureMember(frame, key)
    local region = Field(frame, key)
    return Kit.ObjectType(region) == "Texture" and Kit.ParentIs(region, frame)
end

local function HasTranslucentFrameChrome(frame)
    if not HasDirectTextureMember(frame, "Bg") then return false end
    for index = 1, #translucentFrameBorderFields do
        if not HasDirectTextureMember(frame, translucentFrameBorderFields[index]) then
            return false
        end
    end
    return true
end

local function HasDialogBorderChrome(frame)
    if Field(frame, "layoutType") ~= "Dialog" then return false end
    for index = 1, #dialogBorderFields do
        if not HasDirectTextureMember(frame, dialogBorderFields[index]) then
            return false
        end
    end
    return true
end

local function HasChrome(frame)
    return HasAnyField(frame, backgroundFields) or HasAnyField(frame, nineSliceFields)
        or HasTranslucentFrameChrome(frame) or HasDialogBorderChrome(frame)
end

local function FadeDialogBorderChrome(owner, frame, targets)
    FadeFields(owner, frame, dialogBorderFields, targets)
    Fade(owner, Field(frame, "Center"), targets)
    Fade(owner, Field(frame, "Bg"), targets)
end

local function FadeChrome(frame, owner, targets)
    FadeFields(owner, frame, backgroundFields, targets)
    if HasTranslucentFrameChrome(frame) then
        FadeFields(owner, frame, translucentFrameBorderFields, targets)
    end
    if HasDialogBorderChrome(frame) then
        FadeDialogBorderChrome(owner, frame, targets)
    end
    for index = 1, #nineSliceFields do
        local nineSlice = Field(frame, nineSliceFields[index])
        if nineSlice then
            FadeFields(owner, nineSlice, nineSlicePieceFields, targets)
            Fade(owner, Field(nineSlice, "Bg"), targets)
            Fade(owner, Field(nineSlice, "Background"), targets)
        end
    end
    FadeFields(owner, Field(frame, "Header"), dialogHeaderFields, targets)
    FadeFields(owner, Field(frame, "FlatBackground"), flatBackgroundFields, targets)
end

local function FadeAtlasRegion(region, owner, targets, atlases)
    local atlas = Safety.Read(region, "GetAtlas")
    if atlas ~= nil and atlases[atlas] then Fade(owner, region, targets) end
end

local function FadeAtlasRegions(frame, owner, targets, atlases)
    Kit.ForEachRegion(frame, FadeAtlasRegion, owner, targets, atlases)
end

local themeDomains = {
    theme = true, color = true, appearance = true, geometry = true, profile = true,
}

-- Repaints the glyphs. A theme change also makes every pooled row take one
-- full skin pass again on its next initialization.
local function OnThemeChanged(_, domain)
    local newGeneration = themeDomains[domain] == true
    for _, ownerState in pairs(ownerStates) do
        if newGeneration then ownerState.generation = ownerState.generation + 1 end
        for button, glyph in pairs(ownerState.glyphs) do
            glyph:SetTextColor(NS.Theme.GetColor(ownerState.glyphRoles[button] or "accentBright"))
        end
    end
end

local function EnsureThemeListener()
    if not themeListenerRegistered then
        NS.Registry.AddListener(GenericWindows, OnThemeChanged)
        themeListenerRegistered = true
    end
end

-- Shared ControlSkin, IconSkin, Checkmarks, ScrollBarSkin and Cosmetics
-- state of this owner, restored exactly once per disable.
local function RestoreOwnerSkins(owner)
    NS.IconSkin.DisableOwner(owner)
    NS.ControlSkin.DisableOwner(owner)
    NS.Checkmarks.UntrackOwner(owner)
    NS.ScrollBarSkin.DisableOwner(owner)
    NS.Cosmetics.RestoreOwner(owner)
end

local function DeactivateOwnerState(owner, ownerState)
    ownerState.active = false
    Kit.CancelDeferred(ownerState)
    for scrollBox, registration in pairs(ownerState.scrollBoxes) do
        Kit.UnregisterRowCallback(scrollBox, registration.event, registration)
    end
    ownerState.scrollBoxes = Kit.WeakSet()
    ownerState.skinnedRows = Kit.WeakSet()
    ownerState.generation = ownerState.generation + 1

    RestoreOwnerSkins(owner)
    for target in pairs(ownerState.surfaces) do
        NS.Surface.SetVisible(target, false)
    end
    for _, glyph in pairs(ownerState.glyphs) do
        glyph:Hide()
    end
    for frame in pairs(ownerState.frames) do
        local state = frameStates[frame]
        if state and state.owner == owner then
            state.active = false
        end
    end
end

-- Undoes every frame pass of this owner, exactly once per disable.
local function DeactivateOwner(owner)
    local ownerState = ownerStates[owner]
    if ownerState then
        DeactivateOwnerState(owner, ownerState)
    else
        RestoreOwnerSkins(owner)
    end
end

-- Private to the GenericWindows files that load next (TOC order); the last
-- of them, GenericWindowsCatalog.lua, takes it off NS again.
-- GenericWindowsNodes.lua adds the node skinners and the specs they share.
NS.GenericWindowsShared = {
    DEFAULT_OWNER = DEFAULT_OWNER,
    frameStates = frameStates,
    rowModes = rowModes,
    OwnerState = OwnerState,
    OwnerKey = OwnerKey,
    CanSkin = CanSkin,
    ObjectName = ObjectName,
    CountControl = CountControl,
    Attach = Attach,
    Fade = Fade,
    FadeFields = FadeFields,
    HasTranslucentFrameChrome = HasTranslucentFrameChrome,
    HasDialogBorderChrome = HasDialogBorderChrome,
    HasChrome = HasChrome,
    FadeDialogBorderChrome = FadeDialogBorderChrome,
    FadeChrome = FadeChrome,
    FadeAtlasRegions = FadeAtlasRegions,
    EnsureThemeListener = EnsureThemeListener,
    DeactivateOwner = DeactivateOwner,
}

return GenericWindows
