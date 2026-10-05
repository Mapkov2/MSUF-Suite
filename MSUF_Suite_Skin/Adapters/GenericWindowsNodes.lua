local _, NS = ...

-- GenericWindows node skinning (see GenericWindows.lua): the surface specs,
-- the button families, inputs, glyph and icon buttons, scrollbars, panels and
-- SkinNode, which a frame pass of GenericWindowsFrames.lua calls per node.
local Shared = NS.GenericWindowsShared

local Safety = NS.Safety
local Field = Safety.Field
local Call = Safety.Call
local Kit = NS.AdapterKit

local OwnerState = Shared.OwnerState
local CanSkin = Shared.CanSkin
local ObjectName = Shared.ObjectName
local CountControl = Shared.CountControl
local Attach = Shared.Attach
local Fade = Shared.Fade
local FadeFields = Shared.FadeFields
local HasTranslucentFrameChrome = Shared.HasTranslucentFrameChrome
local HasDialogBorderChrome = Shared.HasDialogBorderChrome
local HasChrome = Shared.HasChrome
local FadeDialogBorderChrome = Shared.FadeDialogBorderChrome
local FadeChrome = Shared.FadeChrome
local FadeAtlasRegions = Shared.FadeAtlasRegions
local EnsureThemeListener = Shared.EnsureThemeListener

local staticPopupButtons = Kit.WeakSet()
local legacyPanelButtons = Kit.WeakSet()

local separatorFields = {
    "Divider", "Divider1", "Divider2", "HorizontalDivider", "VerticalDivider",
    "Separator", "Separator1", "Separator2", "DividingLine", "TitleDivider",
    "TopDivider", "BottomDivider", "LeftDivider", "RightDivider",
    "TextToSpeechFrameSeparator",
}

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

local function ContainsNameToken(name, tokens)
    if name == "" then return false end
    for index = 1, #tokens do
        if name:find(tokens[index], 1, true) then return true end
    end
    return false
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

-- Every button node compares its state textures against two art sets, and
-- pooled buttons share a few files: each distinct path is normalized once.
-- The cache is dropped when it reaches NORMALIZED_PATH_LIMIT paths.
local NORMALIZED_PATH_LIMIT = 512
local normalizedPaths, normalizedCount = {}, 0

local function NormalizedPath(value)
    local path = normalizedPaths[value]
    if path then return path end
    if normalizedCount >= NORMALIZED_PATH_LIMIT then
        normalizedPaths, normalizedCount = {}, 0
    end
    path = value:gsub("/", "\\"):lower():gsub("%.blp$", ""):gsub("%.tga$", "")
    normalizedPaths[value] = path
    normalizedCount = normalizedCount + 1
    return path
end

local function TexturePath(texture)
    for index = 1, #texturePathGetters do
        local value = Safety.Read(texture, texturePathGetters[index])
        if type(value) == "string" then return NormalizedPath(value) end
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
    return NS.Checkmarks.IsDropdown(button) == true
end

local function IsDropdownStepperButton(button)
    local normalAtlas = Field(button, "normalAtlas")
    if normalAtlas ~= "common-dropdown-icon-next"
        and normalAtlas ~= "common-dropdown-icon-back" then
        return false
    end
    local parent = Safety.Read(button, "GetParent")
    return parent ~= nil and (Field(parent, "IncrementButton") == button
        or Field(parent, "DecrementButton") == button)
end

-- Button families in detection order. The first family that matches owns the
-- button; ControlSkin[apply] then replaces its interactive state textures.
local buttonFamilies = {
    {
        -- Verified close/minimize/... window actions.
        matches = function(button)
            return NS.Checkmarks.GetWindowAction(button) ~= nil
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
    local verifiedAction = NS.Checkmarks.GetWindowAction(button)
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
    if not scrollBar or not CanSkin(scrollBar, metrics.allowImplicitProtected) then
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
    local parent = Safety.Read(frame, "GetParent")
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

local function TrackNode(frame, owner, metrics, buttonTracked)
    NS.BlizzardYellow.TrackFrame(frame)
    if metrics.menuPopup then NS.BlizzardYellow.TrackMenuSelection(frame) end
    NS.Checkmarks.TrackFrame(frame, owner, buttonTracked)
    NS.Checkmarks.TrackDropdown(frame, owner)
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

-- buttonTracked: the node is a child of a node this pass visited, whose
-- Checkmarks child pass (TrackNode) already tracked its button textures.
local function SkinNode(frame, owner, metrics, isRoot, buttonTracked)
    local objectType = Kit.ObjectType(frame)
    local name = ObjectName(frame)
    TrackNode(frame, owner, metrics, buttonTracked)
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


Shared.childPanelSpecs = childPanelSpecs
Shared.menuRowSpecs = menuRowSpecs
Shared.ChildPanelRole = ChildPanelRole
Shared.AttachChildSurface = AttachChildSurface
Shared.SkinButton = SkinButton
Shared.SkinIconButtonBase = SkinIconButtonBase
Shared.SkinInput = SkinInput
Shared.SkinScrollBar = SkinScrollBar
Shared.SkinNode = SkinNode
