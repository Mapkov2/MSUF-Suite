local _, NS = ...

-- Catalog-driven, conservative coverage for Blizzard windows which do not
-- need a purpose-built adapter. The catalog supplies roots; this module only
-- walks their bounded child trees once when the root (or its LoD addon) is
-- available. It never scans the global frame list or polls. The shared
-- Surface layer attaches enter/leave hooks only to safe, skinned menu buttons.
local GenericWindows = {
    maxDepth = 6,
    maxNodes = 480,
}
NS.GenericWindows = GenericWindows

local Safety = NS.Safety
local Field = Safety.Field
local Call = Safety.Call
local Kit = NS.AdapterKit

local DEFAULT_OWNER = "blizzardWindows"

local frameStates = Kit.WeakSet()
local ownerStates = {}
local entryStatus = {}
local entryOwners = {}
local staticPopupButtons = Kit.WeakSet()
local legacyPanelButtons = Kit.WeakSet()
local themeListenerRegistered = false

-- LoD handling uses one dormant dispatcher. It is registered only while at
-- least one catalog addon is outstanding, then unregistered immediately.
local pendingAddons = {}
local pendingAddonCount = 0
local loadFrame = CreateFrame("Frame")

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

local separatorFields = {
    "Divider", "Divider1", "Divider2", "HorizontalDivider", "VerticalDivider",
    "Separator", "Separator1", "Separator2", "DividingLine", "TitleDivider",
    "TopDivider", "BottomDivider", "LeftDivider", "RightDivider",
    "TextToSpeechFrameSeparator",
}

local dialogHeaderFields = { "LeftBG", "CenterBG", "RightBG" }
local flatBackgroundFields = { "BottomLeft", "BottomRight", "BottomEdge", "TopSection" }

-- Blizzard_SettingsPanel.xml: anonymous overlay anchored at TOPLEFT behind
-- the Game/AddOns tabs and category column.
local anonymousChromeAtlases = {
    ["Options_InnerFrame"] = true,
}

local menuBackgroundAtlases = {
    ["common-dropdown-bg"] = true,
    ["common-dropdown-c-bg"] = true,
}

local panelNameTokens = {
    "Inset", "Panel", "Container", "Content", "Header", "Footer",
    "Dialog", "Popup", "Pane", "Page", "List", "Body", "Section",
}

local itemIconNameTokens = {
    "Item", "Reward", "Loot", "Attachment", "Merchant",
}

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

local staticPopupButtonArt = {
    GetNormalTexture = "interface\\buttons\\ui-dialogbox-button-up",
    GetPushedTexture = "interface\\buttons\\ui-dialogbox-button-down",
    GetDisabledTexture = "interface\\buttons\\ui-dialogbox-button-disabled",
    GetHighlightTexture = "interface\\buttons\\ui-dialogbox-button-highlight",
}

local legacyPanelButtonArt = {
    GetNormalTexture = "interface\\buttons\\ui-panel-button-up",
    GetPushedTexture = "interface\\buttons\\ui-panel-button-down",
    GetDisabledTexture = "interface\\buttons\\ui-panel-button-disabled",
    GetHighlightTexture = "interface\\buttons\\ui-panel-button-highlight",
}

local texturePathGetters = { "GetTextureFilePath", "GetTexture" }

-- Surface keeps a reference to its spec and ControlSkin copies it, so every
-- spec here is shared and never changed. Index with allowImplicitProtected.
local function SpecPair(spec)
    local implicit, strict = {}, {}
    for key, value in pairs(spec) do
        implicit[key] = value
        strict[key] = value
    end
    implicit.allowImplicitProtected = true
    strict.allowImplicitProtected = false
    return { [true] = implicit, [false] = strict }
end

local childPanelSpecs = {
    popup = SpecPair({ role = "popup", radius = 6, inset = 0 }),
    navigation = SpecPair({ role = "navigation", radius = 6, inset = 0 }),
    panel = SpecPair({ role = "panel", radius = 6, inset = 0 }),
    card = SpecPair({ role = "card", radius = 6, inset = 0 }),
}
local dialogParentSpecs = SpecPair({ role = "popup", radius = 8, inset = 0 })
local menuRowSpecs = SpecPair({
    role = "card", radius = 4, inset = 0, listItem = true, interactive = true,
})
local textButtonSpecs = SpecPair({
    role = "button", border = 0, fillVisible = false, interactive = true,
})
local iconButtonSpecs = SpecPair({
    role = "button", shape = "round", radius = 4, inset = 1, interactive = true,
})
local iconCheckSpecs = SpecPair({
    role = "button", shape = "round", radius = 4, inset = 1, interactive = false,
})
local glyphButtonSpecs = SpecPair({
    role = "button", useControlShape = true, pillHeight = 24, inset = 1,
})
local inputSpecs = SpecPair({
    role = "input", useControlShape = true, pillHeight = 28, inset = 1,
    nineSlices = { "NineSlice" },
})

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

local function ContainsNameToken(name, tokens)
    if name == "" then return false end
    for index = 1, #tokens do
        if name:find(tokens[index], 1, true) then return true end
    end
    return false
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
    return Kit.ObjectType(region) == "Texture" and Call(region, "GetParent") == frame
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

local function IsTab(button, name)
    return name:find("Tab", 1, true) ~= nil
        or Field(button, "LeftActive") ~= nil
        or Field(button, "MiddleActive") ~= nil
        or Field(button, "RightActive") ~= nil
end

local function IsMinimalTab(button)
    -- MinimalTabTemplate instances declared with parentKey are anonymous, so
    -- their GetName() cannot identify them. These exact atlas key-values plus
    -- SelectableButtonMixin:IsSelected form the stable native contract.
    return type((Field(button, "IsSelected"))) == "function"
        and type((Field(button, "selectedLeftTexture"))) == "string"
        and type((Field(button, "selectedMiddleTexture"))) == "string"
        and type((Field(button, "selectedRightTexture"))) == "string"
        and Field(button, "Left") ~= nil
        and Field(button, "Middle") ~= nil
        and Field(button, "Right") ~= nil
end

local function HasThreeSlice(button)
    return Field(button, "Left") ~= nil
        and Field(button, "Center") ~= nil
        and Field(button, "Right") ~= nil
end

local function HasPanelButtonSlices(button)
    return Field(button, "Left") ~= nil
        and Field(button, "Middle") ~= nil
        and Field(button, "Right") ~= nil
end

local function TexturePath(texture)
    for index = 1, #texturePathGetters do
        local value = Safety.Read(texture, texturePathGetters[index])
        if type(value) == "string" then
            return value:gsub("/", "\\"):lower():gsub("%.blp$", ""):gsub("%.tga$", "")
        end
    end
    return nil
end

local function MatchesStateButtonArt(button, art)
    for getterName, expected in pairs(art) do
        local texture = Call(button, getterName)
        -- A few exact Blizzard dialog templates omit a disabled state.
        if not (getterName == "GetDisabledTexture" and not texture)
            and TexturePath(texture) ~= expected then
            return false
        end
    end
    return true
end

local function IsNativeArtButton(button, cache, art)
    if cache[button] then return true end
    if not MatchesStateButtonArt(button, art) then return false end
    cache[button] = true
    return true
end

local function IsDropdown(button)
    return NS.Checkmarks ~= nil and NS.Checkmarks.IsDropdown(button) == true
end

local function IsDropdownStepperButton(button)
    local normalAtlas = Field(button, "normalAtlas")
    if normalAtlas ~= "common-dropdown-icon-next"
        and normalAtlas ~= "common-dropdown-icon-back" then
        return false
    end
    local parent = Call(button, "GetParent")
    return parent ~= nil and (Field(parent, "IncrementButton") == button
        or Field(parent, "DecrementButton") == button)
end

-- Button families in detection order. The first family that matches owns the
-- button; ControlSkin[apply] then replaces its interactive state textures.
local buttonFamilies = {
    {
        -- Verified close/minimize/... window actions.
        matches = function(button)
            return NS.Checkmarks ~= nil and NS.Checkmarks.GetWindowAction(button) ~= nil
        end,
        apply = "ApplyButton",
        specs = glyphButtonSpecs,
    },
    {
        -- StaticPopup/Dialog and a few legacy panel templates do not inherit
        -- UIPanelButtonTemplate and use one full native normal texture.
        -- Replace their states reversibly, then suppress only verified art.
        matches = function(button)
            return IsNativeArtButton(button, staticPopupButtons, staticPopupButtonArt)
                or IsNativeArtButton(button, legacyPanelButtons, legacyPanelButtonArt)
        end,
        apply = "ApplyButton",
        specs = SpecPair({
            role = "button", activeRole = "buttonPrimary",
            useControlShape = true, pillHeight = 20, inset = 1,
        }),
        fadeNativeNormal = true,
    },
    {
        matches = IsDropdown,
        apply = "ApplyButton",
        specs = SpecPair({
            role = "button", activeRole = "buttonPrimary",
            useControlShape = true, pillHeight = 28, inset = 1,
            regions = { "Background" },
        }),
    },
    {
        -- DropdownWithSteppersTemplate uses two anonymous icon buttons. Their
        -- native Background is cosmetic, while Icon carries the semantic
        -- previous/next arrow and must remain under Blizzard's state mixin.
        matches = IsDropdownStepperButton,
        apply = "ApplyButton",
        specs = SpecPair({
            role = "button", activeRole = "buttonPrimary",
            useControlShape = false, shape = "continuous", radius = 4, inset = 1,
            regions = { "Background" },
        }),
    },
    {
        matches = IsMinimalTab,
        apply = "ApplyMinimalTab",
        specs = SpecPair({
            role = "navigation", activeRole = "navigationActive",
            useControlShape = true, pillHeight = 28, inset = 1,
        }),
    },
    {
        matches = function(button, name)
            return IsTab(button, name)
                and (HasPanelButtonSlices(button) or Field(button, "LeftActive") ~= nil)
        end,
        apply = "ApplyTab",
        specs = SpecPair({
            role = "navigation", activeRole = "navigationActive",
            useControlShape = true, pillHeight = 28, inset = 1,
        }),
    },
    {
        matches = HasThreeSlice,
        apply = "ApplyThreeSliceButton",
        specs = SpecPair({
            role = "button", activeRole = "buttonPrimary",
            useControlShape = true, pillHeight = 32, inset = 2,
        }),
    },
    {
        matches = function(button)
            return HasPanelButtonSlices(button) or Field(button, "NineSlice") ~= nil
        end,
        apply = "ApplyButton",
        specs = SpecPair({
            role = "button", activeRole = "buttonPrimary",
            useControlShape = true, pillHeight = 28, inset = 1,
            nineSlices = { "NineSlice" },
        }),
    },
}

local function SkinButton(button, owner, metrics)
    local allowImplicitProtected = metrics.allowImplicitProtected
    if not CanSkin(button, allowImplicitProtected) then return false end
    local name = ObjectName(button)
    for index = 1, #buttonFamilies do
        local family = buttonFamilies[index]
        if family.matches(button, name) then
            local nativeNormal = family.fadeNativeNormal and Call(button, "GetNormalTexture") or nil
            if not NS.ControlSkin[family.apply](button, owner, family.specs[allowImplicitProtected]) then
                return false
            end
            if nativeNormal then
                Fade(owner, nativeNormal)
                local flash = Field(button, "Flash")
                if type(flash) == "table" then NS.Cosmetics.SuppressVertexAlpha(flash, owner) end
            end
            CountControl(owner, button, metrics)
            return true
        end
    end
    return false
end

local function LooksLikeInput(editBox, name)
    return HasPanelButtonSlices(editBox)
        or Field(editBox, "NineSlice") ~= nil
        or name:find("Search", 1, true) ~= nil
        or name:find("Filter", 1, true) ~= nil
        or name:find("Input", 1, true) ~= nil
        or name:find("EditBox", 1, true) ~= nil
end

local function SkinInput(editBox, owner, metrics)
    if not LooksLikeInput(editBox, ObjectName(editBox))
        or not NS.ControlSkin.ApplySearchBox(editBox, owner, inputSpecs[metrics.allowImplicitProtected]) then
        return false
    end
    CountControl(owner, editBox, metrics)
    return true
end

local function LooksLikeScrollBar(frame, objectType, name)
    if name:find("ScrollBar", 1, true) ~= nil
        or Field(frame, "ScrollUpButton") ~= nil
        or Field(frame, "ScrollDownButton") ~= nil
        or (Field(frame, "Back") ~= nil and Field(frame, "Forward") ~= nil) then
        return true
    end
    return objectType == "Slider" and Safety.Read(frame, "GetOrientation") == "VERTICAL"
end

local function LooksLikeScrollBox(frame, name)
    return (name:find("ScrollBox", 1, true) ~= nil
            or type((Field(frame, "GetView"))) == "function")
        and type((Field(frame, "RegisterCallback"))) == "function"
        and type((Field(frame, "ForEachFrame"))) == "function"
end

local function GlyphForButton(button, hint)
    local name = hint or ObjectName(button)
    if name:find("Close", 1, true) then return "X" end
    if name:find("Minimize", 1, true) then return "-" end
    if name:find("Maximize", 1, true) then return "+" end
    if name:find("Previous", 1, true) or name:find("Prev", 1, true)
        or name:find("Back", 1, true) or name:find("Left", 1, true) then
        return "<"
    end
    if name:find("Next", 1, true) or name:find("Forward", 1, true)
        or name:find("Right", 1, true) then
        return ">"
    end
    return nil
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

local function ShowGlyph(button, owner, glyphText)
    local ownerState = OwnerState(owner)
    local glyph = ownerState.glyphs[button]
    if not glyph then
        glyph = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        glyph:SetPoint("CENTER", button, "CENTER")
        ownerState.glyphs[button] = glyph
    end
    local glyphRole = glyphText == "X" and "blizzardClose" or "accentBright"
    ownerState.glyphRoles[button] = glyphRole
    glyph:SetText(glyphText)
    glyph:SetTextColor(NS.Theme.GetColor(glyphRole))
    glyph:Show()
    EnsureThemeListener()
end

local function SkinGlyphButton(button, owner, metrics, glyphText)
    local allowImplicitProtected = metrics.allowImplicitProtected
    local verifiedAction = NS.Checkmarks and NS.Checkmarks.GetWindowAction(button) or nil
    if not NS.ControlSkin.ApplyButton(button, owner, glyphButtonSpecs[allowImplicitProtected]) then
        return false
    end
    local ownerState = OwnerState(owner)
    if verifiedAction then
        local glyph = ownerState.glyphs[button]
        if glyph then glyph:Hide() end
        ownerState.glyphRoles[button] = nil
    else
        Fade(owner, Call(button, "GetNormalTexture"))
        ShowGlyph(button, owner, glyphText)
    end
    CountControl(owner, button, metrics)
    return true
end

local function SkinIconButtonBase(button, owner, metrics, hint)
    local objectType = Kit.ObjectType(button)
    local allowImplicitProtected = metrics.allowImplicitProtected
    if not button or not CanSkin(button, allowImplicitProtected)
        or (objectType ~= "Button" and objectType ~= "CheckButton") then
        return false
    end

    local glyphText = objectType == "Button" and GlyphForButton(button, hint) or nil
    if glyphText then
        return SkinGlyphButton(button, owner, metrics, glyphText)
    end

    -- Keep semantic textures for checkboxes and icon-only controls whose
    -- meaning cannot be reconstructed from a verified name.
    local specs = objectType == "Button" and iconButtonSpecs or iconCheckSpecs
    local attached = Attach(owner, button, specs[allowImplicitProtected], metrics)
    if attached and objectType == "CheckButton" then
        Fade(owner, Call(button, "GetNormalTexture"))
    end
    return attached
end

local function SkinScrollBar(scrollBar, owner, metrics)
    if not scrollBar or not CanSkin(scrollBar, metrics.allowImplicitProtected)
        or not NS.ScrollBarSkin then
        return false
    end
    -- Only the exact current Blizzard scrollbar contracts opt in. The
    -- dedicated renderer preserves size, range, value, visibility, scripts,
    -- controllers and every native state atlas.
    if not NS.ScrollBarSkin.Apply(scrollBar, owner) then return false end
    if not metrics.scrollTargets[scrollBar] then
        metrics.scrollTargets[scrollBar] = true
        metrics.scrollBars = metrics.scrollBars + 1
    end
    return true
end

local function SkinItemIconButton(button, owner, metrics, name)
    if not NS.IconSkin then return false end
    local icon = Field(button, "Icon") or Field(button, "icon") or Field(button, "IconTexture")
    local iconBorder = Field(button, "IconBorder") or Field(button, "iconBorder")
    if not icon or not iconBorder then return false end
    local hasQualityContract = type((Field(button, "SetItemButtonQuality"))) == "function"
        or ContainsNameToken(name, itemIconNameTokens)
    if not hasQualityContract then return false end
    return Kit.SkinItemIcon(button, owner, icon, iconBorder, metrics.allowImplicitProtected)
end

local function ChildPanelRole(name)
    if name:find("Popup", 1, true) or name:find("Dialog", 1, true)
        or name:find("Tutorial", 1, true) then
        return "popup"
    end
    if name:find("Header", 1, true) or name:find("Footer", 1, true) then
        return "navigation"
    end
    if name:find("Inset", 1, true) or name:find("Content", 1, true) then
        return "panel"
    end
    return "card"
end

local function AttachChildSurface(owner, target, specs, metrics)
    if metrics.childSurfaces
        and Attach(owner, target, specs[metrics.allowImplicitProtected], metrics) then
        metrics.childSurfaceTargets[target] = true
    end
end

-- This frame is the visual border, not the dialog's behavior owner. Fade
-- only its native chrome and put the replacement surface on its parent,
-- preserving Blizzard's scripts, visibility and frame levels.
local function SkinDialogBorder(frame, owner, metrics)
    FadeDialogBorderChrome(owner, frame)
    local parent = Call(frame, "GetParent")
    if parent and not metrics.surfaceTargets[parent]
        and CanSkin(parent, metrics.allowImplicitProtected) then
        AttachChildSurface(owner, parent, dialogParentSpecs, metrics)
    end
end

local function SkinPanel(frame, owner, metrics)
    if HasDialogBorderChrome(frame) then
        SkinDialogBorder(frame, owner, metrics)
        return true
    end
    local name = ObjectName(frame)
    local translucentFrame = HasTranslucentFrameChrome(frame)
    if not HasChrome(frame)
        or (not translucentFrame and not ContainsNameToken(name, panelNameTokens)) then
        return false
    end

    local role = translucentFrame and "popup" or ChildPanelRole(name)
    AttachChildSurface(owner, frame, childPanelSpecs[role], metrics)
    FadeChrome(frame, owner)

    -- ProfessionsGuildListingTemplate is the one anonymous concrete child of
    -- this family in Retail. Its TooltipBackdrop Container has no global name,
    -- so handle that exact inherited member while the family contract is known.
    local container = translucentFrame and Field(frame, "Container") or nil
    if container and CanSkin(container, metrics.allowImplicitProtected)
        and HasChrome(container) then
        AttachChildSurface(owner, container, childPanelSpecs.panel, metrics)
        FadeChrome(container, owner)
    end
    return true
end

local function ModeValue(mode, key, fallback)
    if type(mode) == "table" and mode[key] ~= nil then
        return mode[key]
    end
    return fallback
end

local function PublicNumber(target, method)
    local value = Safety.Read(target, method)
    return type(value) == "number" and value or nil
end

-- A full-screen UIParent child must never receive a generic opaque root
-- surface. Several Blizzard managers (notably MotionSicknessFrame) are
-- permanently shown and use setAllPoints even when their own artwork is
-- currently empty. Size detection is an additional runtime fail-safe on top
-- of catalog modes, so one bad source classification cannot black out WoW.
local function IsFullscreenRoot(frame)
    local uiParent = _G.UIParent
    if not uiParent or frame == uiParent or Call(frame, "GetParent") ~= uiParent then
        return false
    end
    local width, height = PublicNumber(frame, "GetWidth"), PublicNumber(frame, "GetHeight")
    local uiWidth, uiHeight = PublicNumber(uiParent, "GetWidth"), PublicNumber(uiParent, "GetHeight")
    if not width or not height or not uiWidth or not uiHeight
        or uiWidth <= 0 or uiHeight <= 0 then
        return false
    end
    return width >= uiWidth * 0.9 and height >= uiHeight * 0.9
end

local function RootRole(mode)
    if type(mode) == "table" and type(mode.role) == "string" then
        return mode.role
    end
    if mode == "popup" or mode == "dialog" or mode == "tooltip" then
        return "popup"
    end
    if mode == "panel" then
        return "panel"
    end
    return "shell"
end

-- Catalog modes are static, so each converted mode is built once.
local catalogModes = Kit.WeakSet()
local NO_MODE = {}

local function CatalogMode(mode)
    local key = mode == nil and NO_MODE or mode
    local result = catalogModes[key]
    if result then return result end
    result = { allowImplicitProtected = true }
    if type(mode) == "table" then
        for modeKey, value in pairs(mode) do
            result[modeKey] = value
        end
    elseif type(mode) == "string" then
        result.role = RootRole(mode)
    end
    catalogModes[key] = result
    return result
end

local function SkinUnknownButton(frame, owner, metrics, name, objectType)
    local iconName = name:find("Close", 1, true) or name:find("Minimize", 1, true)
        or name:find("Maximize", 1, true) or name:find("Next", 1, true)
        or name:find("Prev", 1, true)
    if iconName then
        SkinIconButtonBase(frame, owner, metrics)
    elseif metrics.menuPopup then
        Attach(owner, frame, menuRowSpecs[metrics.allowImplicitProtected], metrics)
    elseif objectType == "Button" and Call(frame, "GetFontString") then
        -- Unknown text buttons keep their native art; add only the theme
        -- hover outline so menus remain consistently readable.
        Attach(owner, frame, textButtonSpecs[metrics.allowImplicitProtected], metrics)
    end
end

local function TrackNode(frame, owner, metrics)
    if NS.BlizzardYellow then
        NS.BlizzardYellow.TrackFrame(frame)
        if metrics.menuPopup then NS.BlizzardYellow.TrackMenuSelection(frame) end
    end
    if NS.Checkmarks then
        NS.Checkmarks.TrackFrame(frame, owner)
        NS.Checkmarks.TrackDropdown(frame, owner)
    end
end

local function SkinRootChrome(frame, owner, metrics)
    if metrics.preserveRootArt then return end
    local targets = metrics.rootChromeTargets
    FadeFields(owner, frame, separatorFields, targets)
    FadeChrome(frame, owner, targets)
    FadeAtlasRegions(frame, owner, targets, anonymousChromeAtlases)
    if metrics.menuPopup then
        FadeAtlasRegions(frame, owner, targets, menuBackgroundAtlases)
    end
end

local function SkinNode(frame, owner, metrics, isRoot)
    local objectType = Kit.ObjectType(frame)
    local name = ObjectName(frame)
    TrackNode(frame, owner, metrics)
    if LooksLikeScrollBox(frame, name) then
        metrics.dynamicScrollBoxes[frame] = true
    end

    -- HUD systems frequently own secure descendants or semantic artwork whose
    -- geometry and textures must stay native. Accent-only catalog entries
    -- deliberately stop after recoloring already-existing text and verified
    -- Blizzard glyph textures. They create no regions, fade no artwork, and
    -- never alter scripts, anchors, attributes, visibility, or actions.
    if metrics.accentOnly then return end

    if isRoot then
        SkinRootChrome(frame, owner, metrics)
        return
    end

    FadeFields(owner, frame, separatorFields)
    if objectType == "Button" or IsDropdown(frame) then
        if not SkinButton(frame, owner, metrics) then
            SkinUnknownButton(frame, owner, metrics, name, objectType)
        end
        if objectType == "Button" then
            SkinItemIconButton(frame, owner, metrics, name)
        end
    elseif objectType == "EditBox" then
        SkinInput(frame, owner, metrics)
    elseif objectType == "CheckButton" then
        SkinIconButtonBase(frame, owner, metrics)
    elseif LooksLikeScrollBar(frame, objectType, name) then
        SkinScrollBar(frame, owner, metrics)
    elseif objectType == "Frame" or objectType == "ScrollFrame" or objectType == "ScrollBox" then
        SkinPanel(frame, owner, metrics)
    end
end

-- Several Blizzard windows expose important controls as named regions or
-- mixin members which are not descendants (or whose internal child tree is
-- intentionally opaque). Probe only this fixed field vocabulary; this gives
-- Settings, AddOnList, ColorPicker and similar dialogs useful full coverage
-- without a global scan or semantic-art guessing.
local explicitButtonFields = {
    "OkayButton", "OKButton", "CancelButton", "ApplyButton", "CloseButton",
    "DoneButton", "AcceptButton", "DeclineButton", "ResetButton",
    "EnableAllButton", "DisableAllButton", "RefreshButton", "SearchButton",
    "BackButton", "NextButton", "PreviousButton",
    "MinimizeButton", "MaximizeButton", "CollapseButton", "ExpandButton",
    "PlusButton", "MinusButton",
}

local explicitTabFields = {
    "GameTab", "AddOnsTab", "GeneralTab", "AdvancedTab",
}

local explicitInputFields = {
    "SearchBox", "SearchEditBox", "FilterBox", "NameEditBox", "EditBox",
    "HexBox", "HexEditBox",
}

local explicitScrollFields = {
    "ScrollBar", "Scrollbar", "ScrollBoxScrollBar", "CategoryListScrollBar",
}

local explicitPanelFields = {
    "Inset", "Content", "Container", "Footer", "Header", "CategoryList",
    "SearchPreviewContainer", "LeftInset", "RightInset", "MainPanel",
    "GameTimeTutorial",
}

-- Named parentKey chains are not globals and are therefore invisible to the
-- catalog. Keep this list exact and source-reviewed instead of searching
-- arbitrary descendants for dialog-like names.
local explicitPanelPaths = {
    { "WoWTokenResults", "GameTimeTutorial" },
}

local LEGACY_DROPDOWN_BUTTON_LIMIT = 64

local function SkinExplicitPanel(panel, fieldName, owner, metrics)
    if not panel or not CanSkin(panel, metrics.allowImplicitProtected) or not HasChrome(panel) then
        return false
    end
    AttachChildSurface(owner, panel, childPanelSpecs[ChildPanelRole(fieldName)], metrics)
    FadeChrome(panel, owner)
    return true
end

-- Legacy Retail dropdown lists (currently retained by a small PvP path)
-- expose their native backdrops as Border/MenuBackdrop and their rows as
-- Button1..N rather than children of the opening dropdown control.
local function SkinLegacyDropdownList(frame, owner, metrics)
    local border = Field(frame, "Border")
    local backdrop = Field(frame, "MenuBackdrop")
    if border then FadeChrome(border, owner) end
    if backdrop then FadeChrome(backdrop, owner) end
    local count = math.max(tonumber((Field(frame, "numButtons"))) or 0, 1)
    count = math.min(count, LEGACY_DROPDOWN_BUTTON_LIMIT)
    local frameName = ObjectName(frame)
    for index = 1, count do
        local button = Field(frame, "Button" .. index)
            or (frameName ~= "" and _G[frameName .. "Button" .. index])
        if button and CanSkin(button, metrics.allowImplicitProtected) then
            if NS.Checkmarks then NS.Checkmarks.TrackFrame(button, owner) end
            Attach(owner, button, menuRowSpecs[metrics.allowImplicitProtected], metrics)
        end
    end
end

local function ExplicitControl(frame, key, allowImplicitProtected)
    local control = Field(frame, key)
    if control and CanSkin(control, allowImplicitProtected) then return control end
    return nil
end

local function SkinExplicitFields(frame, owner, metrics)
    local allowImplicitProtected = metrics.allowImplicitProtected
    if metrics.legacyDropdown then
        SkinLegacyDropdownList(frame, owner, metrics)
    end

    for index = 1, #explicitButtonFields do
        local control = ExplicitControl(frame, explicitButtonFields[index], allowImplicitProtected)
        if control and Kit.ObjectType(control) == "Button"
            and not SkinButton(control, owner, metrics) then
            SkinIconButtonBase(control, owner, metrics, explicitButtonFields[index])
        end
    end

    for index = 1, #explicitTabFields do
        local tab = ExplicitControl(frame, explicitTabFields[index], allowImplicitProtected)
        if tab and Kit.ObjectType(tab) == "Button" then
            SkinButton(tab, owner, metrics)
        end
    end

    for index = 1, #explicitInputFields do
        local input = ExplicitControl(frame, explicitInputFields[index], allowImplicitProtected)
        if input then SkinInput(input, owner, metrics) end
    end

    for index = 1, #explicitScrollFields do
        local scrollBar = ExplicitControl(frame, explicitScrollFields[index], allowImplicitProtected)
        if scrollBar then SkinScrollBar(scrollBar, owner, metrics) end
    end

    for index = 1, #explicitPanelFields do
        local fieldName = explicitPanelFields[index]
        SkinExplicitPanel(Field(frame, fieldName), fieldName, owner, metrics)
    end

    for index = 1, #explicitPanelPaths do
        local path = explicitPanelPaths[index]
        SkinExplicitPanel(Kit.PathOf(frame, path), path[#path], owner, metrics)
    end
end

-- Appends the given children for the next traversal depth. True when the
-- node limit cut the list short.
local function AppendChildren(queue, depths, depth, limit, ...)
    for index = 1, select("#", ...) do
        if #queue >= limit then return true end
        queue[#queue + 1] = (select(index, ...))
        depths[#depths + 1] = depth
    end
    return false
end

local function IsOwnedEquipmentHost(frame)
    -- Owned equipment UI has its own styling and lifecycle. Do not rescan its
    -- subtree as if it were Blizzard-authored chrome.
    return (NS.CharacterDetails and NS.CharacterDetails.IsHost(frame))
        or (NS.CharacterStats and NS.CharacterStats.IsHost(frame))
        or (NS.EQoLCharacter and NS.EQoLCharacter.IsHost(frame))
end

local function TraverseTree(root, owner, metrics, maxDepth, maxNodes)
    local queue, depths = { root }, { 0 }
    local head = 1
    while head <= #queue and metrics.nodes < maxNodes do
        local current, depth = queue[head], depths[head]
        head = head + 1
        if IsOwnedEquipmentHost(current) then
            -- Skipped deliberately; see IsOwnedEquipmentHost.
        elseif not CanSkin(current, metrics.allowImplicitProtected) then
            metrics.protected = metrics.protected + 1
        else
            metrics.nodes = metrics.nodes + 1
            SkinNode(current, owner, metrics, current == root)
            if depth < maxDepth then
                if AppendChildren(queue, depths, depth + 1, maxNodes, Call(current, "GetChildren")) then
                    metrics.truncated = true
                end
            elseif (Safety.Read(current, "GetNumChildren") or 0) > 0 then
                metrics.truncated = true
            end
        end
    end
    if head <= #queue or #queue >= maxNodes then
        metrics.truncated = true
    end
end

local function TraversalLimits(mode)
    local maxDepth = tonumber(ModeValue(mode, "maxDepth", nil)) or GenericWindows.maxDepth
    local maxNodes = tonumber(ModeValue(mode, "maxNodes", nil)) or GenericWindows.maxNodes
    return math.max(0, math.min(12, math.floor(maxDepth))),
        math.max(1, math.min(1200, math.floor(maxNodes)))
end

local function NewMetrics(mode, allowImplicitProtected)
    return {
        nodes = 0,
        surfaces = 0,
        controls = 0,
        scrollBars = 0,
        protected = 0,
        errors = 0,
        truncated = false,
        -- Working sets for this pass only; StoreFrameState removes them.
        surfaceTargets = {},
        controlTargets = {},
        scrollTargets = {},
        dynamicScrollBoxes = {},
        childSurfaceTargets = Kit.WeakSet(),
        rootChromeTargets = Kit.WeakSet(),
        allowImplicitProtected = allowImplicitProtected,
        menuPopup = ModeValue(mode, "menuPopup", false) == true,
        legacyDropdown = ModeValue(mode, "legacyDropdown", false) == true,
        preserveRootArt = ModeValue(mode, "preserveRootArt", false) == true,
        accentOnly = ModeValue(mode, "accentOnly", false) == true,
        childSurfaces = ModeValue(mode, "childSurfaces", true) ~= false,
    }
end

local metricWorkingSets = {
    "surfaceTargets", "childSurfaceTargets", "controlTargets", "scrollTargets",
    "dynamicScrollBoxes", "allowImplicitProtected", "menuPopup", "legacyDropdown",
    "preserveRootArt", "accentOnly", "childSurfaces", "rootChromeTargets",
}

local function StoreFrameState(frame, owner, mode, metrics, previousState, rootSurfaceAttached)
    local state = previousState or {}
    state.owner = owner
    state.mode = mode
    state.rootSurfaceAttached = rootSurfaceAttached
    state.childSurfaceTargets = metrics.childSurfaceTargets
    state.rootChromeTargets = metrics.rootChromeTargets
    state.active = true
    for index = 1, #metricWorkingSets do
        metrics[metricWorkingSets[index]] = nil
    end
    state.metrics = metrics
    frameStates[frame] = state
end

-- Fullscreen roots and preserveRootArt modes keep Blizzard's own backdrop,
-- including any art an earlier pass of this owner faded.
local function ResolveRootArt(frame, owner, metrics, wantsRootSurface, previous)
    metrics.fullscreenGuarded = wantsRootSurface and not metrics.accentOnly
        and IsFullscreenRoot(frame) or false
    if metrics.fullscreenGuarded then
        metrics.preserveRootArt = true
    end
    if metrics.preserveRootArt and previous and previous.rootChromeTargets then
        for region in pairs(previous.rootChromeTargets) do
            NS.Cosmetics.Restore(region, owner)
        end
    end
end

-- Modes are shared, unchanged tables or strings, so each root spec is built
-- once per mode and shared by every frame (and pooled row) using it.
local rootSpecs = Kit.WeakSet()

local function RootSpec(mode, allowImplicitProtected)
    local key = mode == nil and NO_MODE or mode
    local spec = rootSpecs[key]
    if not spec then
        spec = {
            role = RootRole(mode),
            radius = ModeValue(mode, "radius", 8),
            inset = ModeValue(mode, "inset", 0),
            border = ModeValue(mode, "border", nil),
            fillVisible = ModeValue(mode, "fillVisible", true) ~= false,
            listItem = ModeValue(mode, "listItem", false) == true,
            allowImplicitProtected = allowImplicitProtected,
        }
        rootSpecs[key] = spec
    end
    return spec
end

local RegisterDynamicScrollBox

-- While the Bags module paints the combined and reagent bag shell, the skin
-- keeps only the window's contents: no root surface and Blizzard's root art
-- left to the module. One derived mode per incoming mode.
local bagShellModes = Kit.WeakSet()

local function BagShellMode(mode)
    local key = mode == nil and NO_MODE or mode
    local result = bagShellModes[key]
    if result then return result end
    result = {}
    if type(mode) == "table" then
        for modeKey, value in pairs(mode) do result[modeKey] = value end
    elseif type(mode) == "string" then
        result.role = RootRole(mode)
    end
    result.rootSurface = false
    result.preserveRootArt = true
    bagShellModes[key] = result
    return result
end

local function OwnedMode(frame, mode)
    local ownership = NS.SuiteOwnership
    if ownership and ownership.IsBagShell(frame) and ownership.Owns("bagWindows") then
        return BagShellMode(mode)
    end
    return mode
end

local function ApplyFrameNow(frame, owner, mode)
    if not frame then return false, "invalid", nil end
    mode = OwnedMode(frame, mode)
    local allowImplicitProtected = ModeValue(mode, "allowImplicitProtected", false) == true
    if not CanSkin(frame, allowImplicitProtected) then
        return false, Safety.IsCompositorManaged(frame) and "compositor" or "protected", nil
    end
    if type((Field(frame, "CreateTexture"))) ~= "function" then return false, "invalid", nil end

    local previousState = frameStates[frame]
    local previous = previousState and previousState.owner == owner and previousState or nil
    local metrics = NewMetrics(mode, allowImplicitProtected)
    local wantsRootSurface = ModeValue(mode, "rootSurface", true) ~= false
    ResolveRootArt(frame, owner, metrics, wantsRootSurface, previous)

    local rootSurfaceAttached = false
    if wantsRootSurface and not metrics.fullscreenGuarded then
        if not Attach(owner, frame, RootSpec(mode, allowImplicitProtected), metrics) then
            return false, "surface", metrics
        end
        rootSurfaceAttached = true
    elseif previous and previous.rootSurfaceAttached == true then
        NS.Surface.SetVisible(frame, false)
    end

    if not metrics.accentOnly then
        SkinExplicitFields(frame, owner, metrics)
    end
    TraverseTree(frame, owner, metrics, TraversalLimits(mode))

    local ownerState = OwnerState(owner)
    ownerState.active = true
    if ModeValue(mode, "registerDynamicRows", true) ~= false then
        for scrollBox in pairs(metrics.dynamicScrollBoxes) do
            RegisterDynamicScrollBox(scrollBox, owner, allowImplicitProtected, metrics.menuPopup)
        end
    end
    if not metrics.childSurfaces and previous and previous.childSurfaceTargets then
        for target in pairs(previous.childSurfaceTargets) do
            NS.Surface.SetVisible(target, false)
        end
    end

    StoreFrameState(frame, owner, mode, metrics, previousState, rootSurfaceAttached)
    ownerState.frames[frame] = true
    if NS.WindowControls then NS.WindowControls.Attach(frame, owner) end
    return true, "applied", metrics
end

-- Blizzard initializes pooled ScrollBox rows on every scroll and data
-- refresh. A recycled row keeps every surface and faded region from its
-- first pass, so only element-dependent state is refreshed: Blizzard's
-- yellow text, the selected menu entry and the native check/expand glyphs.
local function RefreshRecycledRow(row, registration)
    local yellow = NS.BlizzardYellow
    if yellow then
        yellow.TrackFrame(row)
        if registration.mode.menuPopup then yellow.TrackMenuSelection(row) end
    end
    if NS.Checkmarks then NS.Checkmarks.TrackFrame(row, registration.owner) end
end

-- Registered once per ScrollBox as callback(registration, row).
local function OnRowInitialized(registration, row)
    local ownerState = registration.ownerState
    -- Optional pooled-row cosmetics never justify combat work or a
    -- post-combat backlog. A later OOC initialization handles the row.
    if not ownerState.active or not row or NS.IsCombatLocked() then return end
    if ownerState.skinnedRows[row] == ownerState.generation then
        RefreshRecycledRow(row, registration)
    elseif ApplyFrameNow(row, registration.owner, registration.mode) then
        ownerState.skinnedRows[row] = ownerState.generation
    end
end

RegisterDynamicScrollBox = function(scrollBox, owner, allowImplicitProtected, menuPopup)
    local ownerState = OwnerState(owner)
    if ownerState.scrollBoxes[scrollBox] then return false end
    local registration = {
        ownerState = ownerState,
        owner = owner,
        mode = rowModes[allowImplicitProtected == true][menuPopup == true],
    }
    registration.event = Kit.RegisterRowCallback(scrollBox, OnRowInitialized, registration)
    if not registration.event then return false end
    ownerState.scrollBoxes[scrollBox] = registration
    EnsureThemeListener()
    Kit.ForEachRow(scrollBox, function(row)
        OnRowInitialized(registration, row)
    end)
    return true
end

function GenericWindows.ApplyFrame(frame, owner, mode)
    owner = owner or DEFAULT_OWNER
    if NS.IsCombatLocked() then
        local ownerState = OwnerState(owner)
        local key = "generic-frame:" .. OwnerKey(owner) .. ":" .. tostring(frame)
        ownerState.deferred[key] = true
        NS.CombatGate.RunOrDefer(key, function()
            ownerState.deferred[key] = nil
            ApplyFrameNow(frame, owner, mode)
        end)
        return false, "combat"
    end
    return ApplyFrameNow(frame, owner, mode)
end

local function IsAddonLoaded(addon)
    return type(addon) ~= "string" or addon == "" or NS.Client.IsAddOnLoaded(addon)
end

local function ById(left, right)
    return left.id < right.id
end

-- The catalog is static after load, so its glass-ready generic entries are
-- collected and sorted once.
local catalogEntries
local noEntries = {}

local function CatalogEntries()
    if catalogEntries then return catalogEntries end
    local catalog = NS.BlizzardCatalog
    if not catalog then return noEntries end
    local entries = {}
    if catalog.IsGlassContractValid() then
        for _, entry in ipairs(catalog.entries) do
            if type(entry.id) == "string" and entry.skipGeneric ~= true
                and catalog.IsEntryGlassReady(entry) then
                entries[#entries + 1] = entry
            end
        end
        table.sort(entries, ById)
    end
    catalogEntries = entries
    return entries
end

local function ResolveFrame(value)
    if type(value) == "string" then
        return _G[value]
    end
    if type(value) == "table" or type(value) == "userdata" then
        return value
    end
    return nil
end

local function AddPending(entry, owner)
    local addon = entry.addon
    if type(addon) ~= "string" or addon == "" or IsAddonLoaded(addon)
        or NS.Client.HasAddOn(addon) == false then
        return false
    end
    local bucket = pendingAddons[addon]
    if not bucket then
        bucket = {}
        pendingAddons[addon] = bucket
        pendingAddonCount = pendingAddonCount + 1
    end
    bucket[entry.id .. ":" .. OwnerKey(owner)] = { entry = entry, owner = owner }
    loadFrame:RegisterEvent("ADDON_LOADED")
    return true
end

local function Enabled()
    if not NS.DB then
        return true
    end
    return NS.DB.enabled ~= false
        and (not NS.DB.skins or NS.DB.skins.blizzardWindows ~= false)
end

local categoryOrder = {
    "character", "inventory", "npc", "quest", "social", "group",
    "profession", "economy", "journal", "map", "calendar", "utility",
    "item-service", "expansion", "housing", "hud", "tutorial",
}

local metricTotalKeys = { "nodes", "surfaces", "controls", "scrollBars", "protected", "errors" }
local countedMetricKeys = { "surfaces", "controls", "scrollBars", "nodes", "fullscreenGuarded", "errors" }

function GenericWindows.IsCategoryEnabled(category)
    local categories = NS.DB and NS.DB.skinCategories
    return type(category) ~= "string" or not categories or categories[category] ~= false
end

local function SetEntryStatus(entry, owner, state)
    entryStatus[entry.id] = { state = state, frames = 0, owner = owner }
end

-- A Suite module that replaces this entry's surface keeps it while it runs
-- (Core/SuiteOwnership.lua).
local function SuiteOwnsEntry(entry)
    local ownership = NS.SuiteOwnership
    local surface = ownership and ownership.EntrySurface(entry.id)
    return surface ~= nil and ownership.Owns(surface)
end

-- Why an entry cannot be applied now, or nil when it can.
local function EntryBlocker(entry, owner)
    if not Enabled() then
        SetEntryStatus(entry, owner, "disabled")
        return "disabled"
    end
    if not GenericWindows.IsCategoryEnabled(entry.category) or SuiteOwnsEntry(entry) then
        SetEntryStatus(entry, owner, "disabled")
        entryOwners[entry.id] = owner
        return "disabled"
    end
    if entry.addon and NS.Client.HasAddOn(entry.addon) == false then
        SetEntryStatus(entry, owner, "unavailable")
        return "unavailable"
    end
    if NS.IsCombatLocked() then
        local ownerState = OwnerState(owner)
        local key = "generic-entry:" .. entry.id .. ":" .. OwnerKey(owner)
        ownerState.deferred[key] = true
        SetEntryStatus(entry, owner, "queued")
        NS.CombatGate.RunOrDefer(key, function()
            ownerState.deferred[key] = nil
            GenericWindows.ApplyEntry(entry, owner)
        end)
        return "combat"
    end
    if entry.addon and not IsAddonLoaded(entry.addon) then
        AddPending(entry, owner)
        SetEntryStatus(entry, owner, "waiting")
        entryOwners[entry.id] = owner
        return "waiting"
    end
    return nil
end

local function AddMetrics(totals, metrics)
    for index = 1, #metricTotalKeys do
        local key = metricTotalKeys[index]
        totals[key] = totals[key] + (metrics[key] or 0)
    end
    if metrics.fullscreenGuarded == true then
        totals.fullscreenGuarded = totals.fullscreenGuarded + 1
    end
    totals.truncated = totals.truncated or metrics.truncated == true
end

local function ApplyEntryFrames(entry, owner)
    local applied, failed, protected = 0, 0, 0
    local totals = {
        nodes = 0, surfaces = 0, controls = 0, scrollBars = 0,
        protected = 0, errors = 0, fullscreenGuarded = 0,
        truncated = false,
    }
    local frames = type(entry.frames) == "table" and entry.frames or noEntries
    for index = 1, #frames do
        local frameValue = frames[index]
        local frame = ResolveFrame(frameValue)
        if frame then
            local frameMode = type(entry.frameModes) == "table"
                and type(frameValue) == "string" and entry.frameModes[frameValue]
                or nil
            local ok, reason, metrics = ApplyFrameNow(frame, owner, CatalogMode(frameMode or entry.mode))
            if ok then
                applied = applied + 1
            else
                failed = failed + 1
                if reason == "protected" then protected = protected + 1 end
            end
            if metrics then AddMetrics(totals, metrics) end
            -- The Macro adapter also starts independently of the catalog.
            -- Reapply after a late generic pass so pooled slot surfaces keep
            -- their specific artwork and selection style in either event order.
            if entry.id == "macros" and NS.MacroWindow then
                NS.MacroWindow.Apply(frame, owner)
            end
        else
            failed = failed + 1
        end
    end
    return applied, failed, protected, totals
end

function GenericWindows.ApplyEntry(entry, owner)
    owner = owner or DEFAULT_OWNER
    if type(entry) ~= "table" or type(entry.id) ~= "string" then
        return false, "invalid"
    end
    local blocker = EntryBlocker(entry, owner)
    if blocker then return false, blocker end

    local applied, failed, protected, totals = ApplyEntryFrames(entry, owner)
    local state
    if applied > 0 and failed == 0 and totals.fullscreenGuarded == 0 then
        state = "applied"
    elseif applied > 0 then
        state = "partial"
    elseif protected > 0 then
        state = "protected"
    else
        state = "missing"
    end

    entryStatus[entry.id] = {
        state = state,
        frames = applied,
        failed = failed,
        owner = owner,
        metrics = totals,
    }
    entryOwners[entry.id] = owner
    return applied > 0, state
end

function GenericWindows.ScheduleLoadOnDemand(owner)
    owner = owner or DEFAULT_OWNER
    if not Enabled() then
        return 0
    end

    local scheduled = 0
    local entries = CatalogEntries()
    for index = 1, #entries do
        local entry = entries[index]
        if GenericWindows.IsCategoryEnabled(entry.category)
            and entry.addon and not IsAddonLoaded(entry.addon) and AddPending(entry, owner) then
            SetEntryStatus(entry, owner, "waiting")
            entryOwners[entry.id] = owner
            scheduled = scheduled + 1
        end
    end
    return scheduled
end

function GenericWindows.GetCategories()
    local counts = {}
    for index = 1, #categoryOrder do
        counts[categoryOrder[index]] = { id = categoryOrder[index], groups = 0, frames = 0 }
    end
    local entries = CatalogEntries()
    for index = 1, #entries do
        local entry = entries[index]
        local item = counts[entry.category]
        if item then
            item.groups = item.groups + 1
            item.frames = item.frames + #(entry.frames or noEntries)
        end
    end
    local result = {}
    for index = 1, #categoryOrder do
        result[#result + 1] = counts[categoryOrder[index]]
    end
    return result
end

function GenericWindows.SetCategoryEnabled(category, enabled)
    if NS.IsCombatLocked() or not NS.Defaults.skinCategories[category] then
        return false
    end
    NS.DB.skinCategories[category] = enabled == true
    local refreshed = NS.Adapters and NS.Adapters.Refresh
        and NS.Adapters.Refresh("blizzardWindows")
    NS.Registry.NotifyListeners("category", category)
    return refreshed ~= nil
end

function GenericWindows.ApplyAll(owner)
    owner = owner or DEFAULT_OWNER
    if not Enabled() then
        GenericWindows.Disable(owner)
        return false, "disabled"
    end
    if NS.IsCombatLocked() then
        local ownerState = OwnerState(owner)
        local key = "generic-owner:" .. OwnerKey(owner)
        ownerState.deferred[key] = true
        NS.CombatGate.RunOrDefer(key, function()
            ownerState.deferred[key] = nil
            GenericWindows.ApplyAll(owner)
        end)
        return false, "combat"
    end

    local entries = CatalogEntries()
    for index = 1, #entries do
        GenericWindows.ApplyEntry(entries[index], owner)
    end
    GenericWindows.ScheduleLoadOnDemand(owner)
    local counts = GenericWindows.GetCounts()
    local partial = counts.partial > 0 or counts.waiting > 0 or counts.queued > 0
        or counts.missing > 0 or counts.protected > 0 or counts.errors > 0
    return true, partial and "partial" or "applied", counts
end

local function RemovePendingForOwner(owner)
    for addon, bucket in pairs(pendingAddons) do
        for key, request in pairs(bucket) do
            if request.owner == owner then
                bucket[key] = nil
            end
        end
        if next(bucket) == nil then
            pendingAddons[addon] = nil
            pendingAddonCount = math.max(0, pendingAddonCount - 1)
        end
    end
    if pendingAddonCount == 0 then
        loadFrame:UnregisterEvent("ADDON_LOADED")
    end
end

-- Shared ControlSkin, IconSkin, Checkmarks, ScrollBarSkin and Cosmetics
-- state of this owner, restored exactly once per disable.
local function RestoreOwnerSkins(owner)
    NS.IconSkin.DisableOwner(owner)
    NS.ControlSkin.DisableOwner(owner)
    if NS.Checkmarks then NS.Checkmarks.UntrackOwner(owner) end
    if NS.ScrollBarSkin then NS.ScrollBarSkin.DisableOwner(owner) end
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

local function DisableNow(owner)
    if NS.MacroWindow then NS.MacroWindow.Disable(owner) end
    if NS.WindowControls then NS.WindowControls.DisableOwner(owner) end
    local ownerState = ownerStates[owner]
    if ownerState then
        DeactivateOwnerState(owner, ownerState)
    else
        RestoreOwnerSkins(owner)
    end

    RemovePendingForOwner(owner)
    for id, appliedOwner in pairs(entryOwners) do
        if appliedOwner == owner then
            entryStatus[id] = { state = "disabled", frames = 0, owner = owner }
        end
    end
    return true
end

function GenericWindows.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local ownerState = OwnerState(owner)
    Kit.CancelDeferred(ownerState)

    if NS.IsCombatLocked() then
        local key = "generic-owner:" .. OwnerKey(owner)
        ownerState.deferred[key] = true
        NS.CombatGate.RunOrDefer(key, function()
            ownerState.deferred[key] = nil
            DisableNow(owner)
        end)
        return false, "combat"
    end
    return DisableNow(owner)
end

function GenericWindows.GetStatus(id)
    local status = entryStatus[id]
    return status and status.state or "pending", status
end

function GenericWindows.GetStatusTable()
    local copy = {}
    for id, status in pairs(entryStatus) do
        local item = {}
        for key, value in pairs(status) do
            item[key] = value
        end
        copy[id] = item
    end
    return copy
end

function GenericWindows.GetCounts()
    local counts = {
        total = 0,
        applied = 0,
        partial = 0,
        waiting = 0,
        queued = 0,
        missing = 0,
        protected = 0,
        disabled = 0,
        pending = 0,
        frames = 0,
        surfaces = 0,
        controls = 0,
        scrollBars = 0,
        nodes = 0,
        fullscreenGuarded = 0,
        errors = 0,
        pendingAddons = pendingAddonCount,
    }

    local entries = CatalogEntries()
    counts.total = #entries
    for index = 1, #entries do
        local status = entryStatus[entries[index].id]
        local state = status and status.state or "pending"
        counts[state] = (counts[state] or 0) + 1
        if status then
            counts.frames = counts.frames + (status.frames or 0)
            local metrics = status.metrics
            if metrics then
                for keyIndex = 1, #countedMetricKeys do
                    local key = countedMetricKeys[keyIndex]
                    counts[key] = counts[key] + (metrics[key] or 0)
                end
            end
        end
    end
    return counts
end

function GenericWindows.GetAppliedCount()
    local counts = GenericWindows.GetCounts()
    return counts.applied + counts.partial
end

function GenericWindows.GetCatalogCount()
    return #CatalogEntries()
end

function GenericWindows.GetPendingAddonCount()
    return pendingAddonCount
end

function GenericWindows.GetTraversalLimits()
    return GenericWindows.maxDepth, GenericWindows.maxNodes
end

loadFrame:SetScript("OnEvent", function(self, event, addon)
    local bucket = event == "ADDON_LOADED" and pendingAddons[addon]
    if not bucket then
        return
    end

    pendingAddons[addon] = nil
    pendingAddonCount = math.max(0, pendingAddonCount - 1)
    for _, request in pairs(bucket) do
        GenericWindows.ApplyEntry(request.entry, request.owner)
    end
    if pendingAddonCount == 0 then
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

return GenericWindows
