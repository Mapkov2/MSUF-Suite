local _, NS = ...

-- Catalog-driven, conservative coverage for Blizzard windows which do not
-- need a purpose-built adapter.  The catalog supplies roots; this module only
-- walks their bounded child trees once when the root (or its LoD addon) is
-- available. It never scans the global frame list or polls. The shared
-- Surface layer attaches enter/leave hooks only to safe, skinned menu buttons.
local GenericWindows = {
    maxDepth = 6,
    maxNodes = 480,
}
NS.GenericWindows = GenericWindows

local DEFAULT_OWNER = "blizzardWindows"

local frameStates = setmetatable({}, { __mode = "k" })
local ownerStates = {}
local entryStatus = {}
local entryOwners = {}
local themeListenerRegistered = false
local OwnerKey
local staticPopupButtons = setmetatable({}, { __mode = "k" })
local legacyPanelButtons = setmetatable({}, { __mode = "k" })

-- LoD handling uses one dormant dispatcher.  It is registered only while at
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

local separatorFields = {
    "Divider", "Divider1", "Divider2", "HorizontalDivider", "VerticalDivider",
    "Separator", "Separator1", "Separator2", "DividingLine", "TitleDivider",
    "TopDivider", "BottomDivider", "LeftDivider", "RightDivider",
    "TextToSpeechFrameSeparator",
}

local anonymousChromeAtlases = {
    -- Blizzard_SettingsPanel.xml: anonymous overlay anchored at TOPLEFT
    -- behind the Game/AddOns tabs and category column.
    ["Options_InnerFrame"] = true,
}

local panelNameTokens = {
    "Inset", "Panel", "Container", "Content", "Header", "Footer",
    "Dialog", "Popup", "Pane", "Page", "List", "Body", "Section",
}

-- Pass the operands through pcall; do not allocate a capturing closure per read.
local function IndexMember(object, key)
    return object[key]
end

local function SafeField(object, key)
    if not object then
        return nil
    end
    local ok, value = pcall(IndexMember, object, key)
    if ok then
        return value
    end
    return nil
end

local function AccessibleBoolean(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then
        if type(canaccessvalue) ~= "function" or not canaccessvalue(value) then
            return nil
        end
    end
    return value == true
end

local function IsUnsafe(frame, allowImplicitProtected)
    return not NS.Safety or not NS.Safety.CanCreateRegions(frame, allowImplicitProtected)
end

local function IsUnsafeControl(frame, allowImplicitProtected)
    return not NS.Safety or not NS.Safety.CanCreateRegions(frame, allowImplicitProtected)
end

local function ObjectType(object)
    local getter = SafeField(object, "GetObjectType")
    if type(getter) ~= "function" then
        return nil
    end
    local ok, value = pcall(getter, object)
    if not ok or type(value) ~= "string" then
        return nil
    end
    return value
end

local function ObjectName(object)
    local getter = SafeField(object, "GetName")
    if type(getter) ~= "function" then
        return ""
    end
    local ok, value = pcall(getter, object)
    if not ok or type(value) ~= "string" then
        return ""
    end
    return value
end

local function ContainsNameToken(name, tokens)
    if name == "" then
        return false
    end
    for index = 1, #tokens do
        if name:find(tokens[index], 1, true) then
            return true
        end
    end
    return false
end

local function OwnerState(owner)
    owner = owner or DEFAULT_OWNER
    local state = ownerStates[owner]
    if not state then
        state = {
            surfaces = setmetatable({}, { __mode = "k" }),
            frames = setmetatable({}, { __mode = "k" }),
            glyphs = setmetatable({}, { __mode = "k" }),
            glyphRoles = setmetatable({}, { __mode = "k" }),
            scrollBoxes = setmetatable({}, { __mode = "k" }),
            deferred = {},
            active = true,
        }
        ownerStates[owner] = state
    end
    return state, owner
end

local function TrackSurface(owner, target)
    local state = OwnerState(owner)
    state.surfaces[target] = true
end

local function Attach(owner, target, spec, metrics)
    spec = spec or {}
    if spec.allowImplicitProtected == nil and metrics then
        spec.allowImplicitProtected = metrics.allowImplicitProtected == true
    end
    if not target or IsUnsafe(target, spec.allowImplicitProtected) then
        return false
    end
    local ok, surface = pcall(NS.Surface.Attach, target, spec)
    if ok and surface then
        TrackSurface(owner, target)
        if not metrics.surfaceTargets[target] then
            metrics.surfaceTargets[target] = true
            metrics.surfaces = metrics.surfaces + 1
        end
        return true
    end
    metrics.errors = metrics.errors + 1
    return false
end

local function Fade(owner, region, targets)
    if region then
        local ok, faded = pcall(NS.Cosmetics.Fade, region, owner)
        if ok and faded and targets then targets[region] = true end
    end
end

local nineSlicePieceFields = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
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

local function HasDirectTextureMember(frame, key)
    local region = SafeField(frame, key)
    if ObjectType(region) ~= "Texture" then return false end
    local getParent = SafeField(region, "GetParent")
    if type(getParent) ~= "function" then return false end
    local ok, parent = pcall(getParent, region)
    return ok and parent == frame
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
    if SafeField(frame, "layoutType") ~= "Dialog" then return false end
    for index = 1, #dialogBorderFields do
        if not HasDirectTextureMember(frame, dialogBorderFields[index]) then
            return false
        end
    end
    return true
end

local function FadeTranslucentFrameChrome(owner, frame, targets)
    if not HasTranslucentFrameChrome(frame) then return false end
    for index = 1, #translucentFrameBorderFields do
        Fade(owner, SafeField(frame, translucentFrameBorderFields[index]), targets)
    end
    return true
end

local function FadeDialogBorderChrome(owner, frame, targets)
    if not HasDialogBorderChrome(frame) then return false end
    for index = 1, #dialogBorderFields do
        Fade(owner, SafeField(frame, dialogBorderFields[index]), targets)
    end
    Fade(owner, SafeField(frame, "Center"), targets)
    Fade(owner, SafeField(frame, "Bg"), targets)
    return true
end

local function FadeNineSlice(owner, nineSlice, targets)
    if nineSlice then
        if targets then
            for index = 1, #nineSlicePieceFields do
                Fade(owner, SafeField(nineSlice, nineSlicePieceFields[index]), targets)
            end
        else
            pcall(NS.Cosmetics.FadeNineSlice, nineSlice, owner)
        end
    end
end

local function FadeChrome(frame, owner, targets)
    for index = 1, #backgroundFields do
        Fade(owner, SafeField(frame, backgroundFields[index]), targets)
    end

    FadeTranslucentFrameChrome(owner, frame, targets)
    FadeDialogBorderChrome(owner, frame, targets)

    for index = 1, #nineSliceFields do
        local nineSlice = SafeField(frame, nineSliceFields[index])
        if nineSlice then
            FadeNineSlice(owner, nineSlice, targets)
            Fade(owner, SafeField(nineSlice, "Bg"), targets)
            Fade(owner, SafeField(nineSlice, "Background"), targets)
        end
    end

    local header = SafeField(frame, "Header")
    if header then
        if targets then
            Fade(owner, SafeField(header, "LeftBG"), targets)
            Fade(owner, SafeField(header, "CenterBG"), targets)
            Fade(owner, SafeField(header, "RightBG"), targets)
        else
            pcall(NS.Cosmetics.FadeDialogHeader, header, owner)
        end
    end

    local flatBackground = SafeField(frame, "FlatBackground")
    if flatBackground then
        if targets then
            for _, field in ipairs({ "BottomLeft", "BottomRight", "BottomEdge", "TopSection" }) do
                Fade(owner, SafeField(flatBackground, field), targets)
            end
        else
            pcall(NS.Cosmetics.FadeFlatBackground, flatBackground, owner)
        end
    end
end

local function FadeAnonymousChrome(frame, owner, targets)
    local getter = SafeField(frame, "GetRegions")
    if type(getter) ~= "function" then return end
    pcall(function()
        local function Visit(...)
            for index = 1, select("#", ...) do
                local region = select(index, ...)
                local getAtlas = SafeField(region, "GetAtlas")
                if type(getAtlas) == "function" then
                    local ok, atlas = pcall(getAtlas, region)
                    if ok and anonymousChromeAtlases[atlas] then Fade(owner, region, targets) end
                end
            end
        end
        Visit(getter(frame))
    end)
end

local function FadeSeparators(frame, owner, targets)
    for index = 1, #separatorFields do
        Fade(owner, SafeField(frame, separatorFields[index]), targets)
    end
end

local function HasAnyField(object, fields)
    for index = 1, #fields do
        if SafeField(object, fields[index]) ~= nil then
            return true
        end
    end
    return false
end

local function IsTab(button, name)
    if name:find("Tab", 1, true) then
        return true
    end
    return SafeField(button, "LeftActive") ~= nil
        or SafeField(button, "MiddleActive") ~= nil
        or SafeField(button, "RightActive") ~= nil
end

local function IsMinimalTab(button)
    -- MinimalTabTemplate instances declared with parentKey are anonymous, so
    -- their GetName() cannot identify them. These exact atlas key-values plus
    -- SelectableButtonMixin:IsSelected form the stable native contract.
    return type(SafeField(button, "IsSelected")) == "function"
        and type(SafeField(button, "selectedLeftTexture")) == "string"
        and type(SafeField(button, "selectedMiddleTexture")) == "string"
        and type(SafeField(button, "selectedRightTexture")) == "string"
        and SafeField(button, "Left") ~= nil
        and SafeField(button, "Middle") ~= nil
        and SafeField(button, "Right") ~= nil
end

local function HasThreeSlice(button)
    return SafeField(button, "Left") ~= nil
        and SafeField(button, "Center") ~= nil
        and SafeField(button, "Right") ~= nil
end

local function HasPanelButtonSlices(button)
    return SafeField(button, "Left") ~= nil
        and SafeField(button, "Middle") ~= nil
        and SafeField(button, "Right") ~= nil
end

local function ButtonStateTexture(button, getterName)
    local getter = SafeField(button, getterName)
    if type(getter) ~= "function" then return nil end
    local ok, texture = pcall(getter, button)
    return ok and texture or nil
end

local function TexturePath(texture)
    for _, getterName in ipairs({ "GetTextureFilePath", "GetTexture" }) do
        local getter = SafeField(texture, getterName)
        if type(getter) == "function" then
            local ok, value = pcall(getter, texture)
            if ok and type(value) == "string" then
                return value:gsub("/", "\\"):lower():gsub("%.blp$", ""):gsub("%.tga$", "")
            end
        end
    end
    return nil
end

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

local function MatchesStateButtonArt(button, art)
    for getterName, expected in pairs(art) do
        local texture = ButtonStateTexture(button, getterName)
        if getterName == "GetDisabledTexture" and not texture then
            -- A few exact Blizzard dialog templates omit a disabled state.
        elseif TexturePath(texture) ~= expected then
            return false
        end
    end
    return true
end

local function IsStaticPopupButton(button)
    if staticPopupButtons[button] then return true end
    if not MatchesStateButtonArt(button, staticPopupButtonArt) then return false end
    staticPopupButtons[button] = true
    return true
end


local function IsLegacyPanelStateButton(button)
    if legacyPanelButtons[button] then return true end
    if not MatchesStateButtonArt(button, legacyPanelButtonArt) then return false end
    legacyPanelButtons[button] = true
    return true
end

local function IsDropdown(button)
    return NS.Checkmarks and NS.Checkmarks.IsDropdown(button) == true
end

local function IsDropdownStepperButton(button)
    local normalAtlas = SafeField(button, "normalAtlas")
    if normalAtlas ~= "common-dropdown-icon-next"
        and normalAtlas ~= "common-dropdown-icon-back" then
        return false
    end
    local getter = SafeField(button, "GetParent")
    if type(getter) ~= "function" then
        return false
    end
    local ok, parent = pcall(getter, button)
    if not ok or not parent then
        return false
    end
    return SafeField(parent, "IncrementButton") == button
        or SafeField(parent, "DecrementButton") == button
end

local function SkinButton(button, owner, metrics)
    local name = ObjectName(button)
    local result
    local allowImplicitProtected = metrics.allowImplicitProtected == true

    if IsUnsafeControl(button, allowImplicitProtected) then
        return false
    end

    local actionKind = NS.Checkmarks and NS.Checkmarks.GetWindowAction(button) or nil
    if actionKind then
        local ok, value = pcall(NS.ControlSkin.ApplyButton, button, owner, {
            role = "button",
            useControlShape = true,
            pillHeight = 24,
            inset = 1,
            allowImplicitProtected = allowImplicitProtected,
        })
        result = ok and value
    elseif IsStaticPopupButton(button) or IsLegacyPanelStateButton(button) then
        -- StaticPopup/Dialog and a few legacy panel templates do not inherit
        -- UIPanelButtonTemplate and use one full native normal texture.
        -- Replace their states reversibly, then suppress only verified art.
        local nativeNormal = ButtonStateTexture(button, "GetNormalTexture")
        local ok, value = pcall(NS.ControlSkin.ApplyButton, button, owner, {
            role = "button",
            activeRole = "buttonPrimary",
            useControlShape = true,
            pillHeight = 20,
            inset = 1,
            allowImplicitProtected = allowImplicitProtected,
        })
        result = ok and value
        if result then
            Fade(owner, nativeNormal)
            local flash = SafeField(button, "Flash")
            if flash then pcall(NS.Cosmetics.SuppressVertexAlpha, flash, owner) end
        end
    elseif IsDropdown(button) then
        local ok, value = pcall(NS.ControlSkin.ApplyButton, button, owner, {
            role = "button",
            activeRole = "buttonPrimary",
            useControlShape = true,
            pillHeight = 28,
            inset = 1,
            regions = { "Background" },
            allowImplicitProtected = allowImplicitProtected,
        })
        result = ok and value
    elseif IsDropdownStepperButton(button) then
        -- DropdownWithSteppersTemplate uses two anonymous icon buttons. Their
        -- native Background is cosmetic, while Icon carries the semantic
        -- previous/next arrow and must remain under Blizzard's state mixin.
        local ok, value = pcall(NS.ControlSkin.ApplyButton, button, owner, {
            role = "button",
            activeRole = "buttonPrimary",
            useControlShape = false,
            shape = "continuous",
            radius = 4,
            inset = 1,
            regions = { "Background" },
            allowImplicitProtected = allowImplicitProtected,
        })
        result = ok and value
    elseif IsMinimalTab(button) then
        local ok, value = pcall(NS.ControlSkin.ApplyMinimalTab, button, owner, {
            role = "navigation",
            activeRole = "navigationActive",
            useControlShape = true,
            pillHeight = 28,
            inset = 1,
            allowImplicitProtected = allowImplicitProtected,
        })
        result = ok and value
    elseif IsTab(button, name) and (HasPanelButtonSlices(button) or SafeField(button, "LeftActive")) then
        local ok, value = pcall(NS.ControlSkin.ApplyTab, button, owner, {
            role = "navigation",
            activeRole = "navigationActive",
            useControlShape = true,
            pillHeight = 28,
            inset = 1,
            allowImplicitProtected = allowImplicitProtected,
        })
        result = ok and value
    elseif HasThreeSlice(button) then
        local ok, value = pcall(NS.ControlSkin.ApplyThreeSliceButton, button, owner, {
            role = "button",
            activeRole = "buttonPrimary",
            useControlShape = true,
            pillHeight = 32,
            inset = 2,
            allowImplicitProtected = allowImplicitProtected,
        })
        result = ok and value
    elseif HasPanelButtonSlices(button) or SafeField(button, "NineSlice") then
        local ok, value = pcall(NS.ControlSkin.ApplyButton, button, owner, {
            role = "button",
            activeRole = "buttonPrimary",
            useControlShape = true,
            pillHeight = 28,
            inset = 1,
            nineSlices = { "NineSlice" },
            allowImplicitProtected = allowImplicitProtected,
        })
        result = ok and value
    end

    if result then
        TrackSurface(owner, button)
        if not metrics.controlTargets[button] then
            metrics.controlTargets[button] = true
            metrics.controls = metrics.controls + 1
        end
        return true
    end
    return false
end


local menuBackgroundAtlases = {
    ["common-dropdown-bg"] = true,
    ["common-dropdown-c-bg"] = true,
}

local function FadeMenuPopupArt(frame, owner, targets)
    local getter = SafeField(frame, "GetRegions")
    if type(getter) ~= "function" then return end
    pcall(function()
        local function Visit(...)
            for index = 1, select("#", ...) do
                local region = select(index, ...)
                local atlasGetter = SafeField(region, "GetAtlas")
                if type(atlasGetter) == "function" then
                    local ok, atlas = pcall(atlasGetter, region)
                    if ok and menuBackgroundAtlases[atlas] then Fade(owner, region, targets) end
                end
            end
        end
        Visit(getter(frame))
    end)
end

local function LooksLikeInput(editBox, name)
    return HasPanelButtonSlices(editBox)
        or SafeField(editBox, "NineSlice") ~= nil
        or name:find("Search", 1, true) ~= nil
        or name:find("Filter", 1, true) ~= nil
        or name:find("Input", 1, true) ~= nil
        or name:find("EditBox", 1, true) ~= nil
end

local function SkinInput(editBox, owner, metrics)
    local name = ObjectName(editBox)
    if not LooksLikeInput(editBox, name) then
        return false
    end
    local ok, result = pcall(NS.ControlSkin.ApplySearchBox, editBox, owner, {
        role = "input",
        useControlShape = true,
        pillHeight = 28,
        inset = 1,
        nineSlices = { "NineSlice" },
        allowImplicitProtected = metrics.allowImplicitProtected == true,
    })
    if ok and result then
        TrackSurface(owner, editBox)
        if not metrics.controlTargets[editBox] then
            metrics.controlTargets[editBox] = true
            metrics.controls = metrics.controls + 1
        end
        return true
    end
    return false
end

local function LooksLikeScrollBar(frame, objectType, name)
    if name:find("ScrollBar", 1, true) ~= nil
        or SafeField(frame, "ScrollUpButton") ~= nil
        or SafeField(frame, "ScrollDownButton") ~= nil
        or (SafeField(frame, "Back") ~= nil and SafeField(frame, "Forward") ~= nil) then
        return true
    end
    if objectType == "Slider" then
        local getter = SafeField(frame, "GetOrientation")
        if type(getter) == "function" then
            local ok, orientation = pcall(getter, frame)
            return ok and orientation == "VERTICAL"
        end
    end
    return false
end

local function LooksLikeScrollBox(frame, name)
    return (name:find("ScrollBox", 1, true) ~= nil
            or type(SafeField(frame, "GetView")) == "function")
        and type(SafeField(frame, "RegisterCallback")) == "function"
        and type(SafeField(frame, "ForEachFrame")) == "function"
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

local function RefreshGlyphs()
    for _, ownerState in pairs(ownerStates) do
        for button, glyph in pairs(ownerState.glyphs) do
            if glyph and type(glyph.SetTextColor) == "function" then
                glyph:SetTextColor(NS.Theme.GetColor(ownerState.glyphRoles[button] or "accentBright"))
            end
        end
    end
end

local function EnsureThemeListener()
    if not themeListenerRegistered then
        NS.Registry.AddListener(GenericWindows, RefreshGlyphs)
        themeListenerRegistered = true
    end
end

local function SkinIconButtonBase(button, owner, metrics, hint)
    local objectType = ObjectType(button)
    local allowImplicitProtected = metrics.allowImplicitProtected == true
    if not button or IsUnsafeControl(button, allowImplicitProtected)
        or (objectType ~= "Button" and objectType ~= "CheckButton") then
        return false
    end

    local glyphText = objectType == "Button" and GlyphForButton(button, hint) or nil
    if glyphText then
        local verifiedAction = NS.Checkmarks
            and NS.Checkmarks.GetWindowAction(button) or nil
        local ok, result = pcall(NS.ControlSkin.ApplyButton, button, owner, {
            role = "button",
            useControlShape = true,
            pillHeight = 24,
            inset = 1,
            allowImplicitProtected = allowImplicitProtected,
        })
        if not ok or not result then
            return false
        end
        local ownerState = OwnerState(owner)
        local glyph = ownerState.glyphs[button]
        if verifiedAction then
            if glyph then glyph:Hide() end
            ownerState.glyphRoles[button] = nil
        else
            local getter = SafeField(button, "GetNormalTexture")
            if type(getter) == "function" then
                local got, texture = pcall(getter, button)
                if got then Fade(owner, texture) end
            end
            if not glyph then
                local okGlyph, created = pcall(button.CreateFontString, button, nil, "OVERLAY", "GameFontNormalLarge")
                if okGlyph then
                    glyph = created
                    ownerState.glyphs[button] = glyph
                    glyph:SetPoint("CENTER", button, "CENTER")
                end
            end
            if glyph then
                local glyphRole = glyphText == "X" and "blizzardClose" or "accentBright"
                ownerState.glyphRoles[button] = glyphRole
                glyph:SetText(glyphText)
                glyph:SetTextColor(NS.Theme.GetColor(glyphRole))
                glyph:Show()
                EnsureThemeListener()
            end
        end
        TrackSurface(owner, button)
        if not metrics.controlTargets[button] then
            metrics.controlTargets[button] = true
            metrics.controls = metrics.controls + 1
        end
        return true
    end

    -- Keep semantic textures for checkboxes and icon-only controls whose
    -- meaning cannot be reconstructed from a verified name.
    local attached = Attach(owner, button, {
        role = "button",
        shape = "round",
        radius = 4,
        inset = 1,
        interactive = objectType == "Button",
    }, metrics)
    if attached and objectType == "CheckButton" then
        local getter = SafeField(button, "GetNormalTexture")
        if type(getter) == "function" then
            local got, texture = pcall(getter, button)
            if got then Fade(owner, texture) end
        end
    end
    return attached
end

local function SkinScrollBar(scrollBar, owner, metrics)
    local allowImplicitProtected = metrics.allowImplicitProtected == true
    if not scrollBar or IsUnsafeControl(scrollBar, allowImplicitProtected) then
        return false
    end

    -- Only the exact current Blizzard scrollbar contracts opt in. The
    -- dedicated renderer preserves size, range, value, visibility, scripts,
    -- controllers and every native state atlas.
    if NS.ScrollBarSkin and type(NS.ScrollBarSkin.Apply) == "function" then
        local ok, state = pcall(NS.ScrollBarSkin.Apply, scrollBar, owner)
        if not ok then
            if type(NS.ReportError) == "function" then
                NS.ReportError("generic scrollbar", state)
            end
            return false
        end
        if not state then return false end
    else
        return false
    end
    if not metrics.scrollTargets[scrollBar] then
        metrics.scrollTargets[scrollBar] = true
        metrics.scrollBars = metrics.scrollBars + 1
    end
    return true
end

local itemIconNameTokens = {
    "Item", "Reward", "Loot", "Attachment", "Merchant",
}

local function SkinItemIconButton(button, owner, metrics, name)
    if not NS.IconSkin then return false end
    local icon = SafeField(button, "Icon") or SafeField(button, "icon")
        or SafeField(button, "IconTexture")
    local iconBorder = SafeField(button, "IconBorder") or SafeField(button, "iconBorder")
    if not icon or not iconBorder then return false end
    local hasQualityContract = type(SafeField(button, "SetItemButtonQuality")) == "function"
        or ContainsNameToken(name or ObjectName(button), itemIconNameTokens)
    if not hasQualityContract then return false end
    local ok, state = pcall(NS.IconSkin.Apply, button, owner, {
        icon = icon,
        nativeBorder = iconBorder,
        allowImplicitProtected = metrics.allowImplicitProtected == true,
    })
    return ok and state ~= nil
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

local function HasChrome(frame)
    return HasAnyField(frame, backgroundFields) or HasAnyField(frame, nineSliceFields)
        or HasTranslucentFrameChrome(frame) or HasDialogBorderChrome(frame)
end

local function SkinPanel(frame, owner, metrics)
    local name = ObjectName(frame)
    local translucentFrame = HasTranslucentFrameChrome(frame)
    if HasDialogBorderChrome(frame) then
        -- This frame is the visual border, not the dialog's behavior owner.
        -- Fade only its native chrome and put the replacement surface on its
        -- parent, preserving Blizzard's scripts, visibility and frame levels.
        FadeDialogBorderChrome(owner, frame)
        local getParent = SafeField(frame, "GetParent")
        local ok, parent = false, nil
        if type(getParent) == "function" then
            ok, parent = pcall(getParent, frame)
        end
        if ok and parent and metrics.childSurfaces
            and not metrics.surfaceTargets[parent]
            and not IsUnsafe(parent, metrics.allowImplicitProtected) then
            if Attach(owner, parent, {
                role = "popup",
                radius = 8,
                inset = 0,
            }, metrics) then
                metrics.childSurfaceTargets[parent] = true
            end
        end
        return true
    end
    if not HasChrome(frame)
        or (not translucentFrame and not ContainsNameToken(name, panelNameTokens)) then
        return false
    end

    if metrics.childSurfaces then
        if Attach(owner, frame, {
            role = translucentFrame and "popup" or ChildPanelRole(name),
            radius = 6,
            inset = 0,
        }, metrics) then
            metrics.childSurfaceTargets[frame] = true
        end
    end
    FadeChrome(frame, owner)

    -- ProfessionsGuildListingTemplate is the one anonymous concrete child of
    -- this family in Retail. Its TooltipBackdrop Container has no global name,
    -- so handle that exact inherited member while the family contract is known.
    local container = translucentFrame and SafeField(frame, "Container") or nil
    if container and not IsUnsafe(container, metrics.allowImplicitProtected)
        and HasChrome(container) then
        if metrics.childSurfaces then
            if Attach(owner, container, {
                role = "panel",
                radius = 6,
                inset = 0,
            }, metrics) then
                metrics.childSurfaceTargets[container] = true
            end
        end
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

local function NumericMethod(target, key)
    local method = SafeField(target, key)
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, target)
    if not ok or type(value) ~= "number" then return nil end
    return value
end

-- A full-screen UIParent child must never receive a generic opaque root
-- surface.  Several Blizzard managers (notably MotionSicknessFrame) are
-- permanently shown and use setAllPoints even when their own artwork is
-- currently empty.  Size detection is an additional runtime fail-safe on top
-- of catalog modes, so one bad source classification cannot black out WoW.
local function IsFullscreenRoot(frame)
    local uiParent = _G.UIParent
    if not uiParent or frame == uiParent then return false end
    local getParent = SafeField(frame, "GetParent")
    if type(getParent) ~= "function" then return false end
    local ok, parent = pcall(getParent, frame)
    if not ok or parent ~= uiParent then return false end

    local width, height = NumericMethod(frame, "GetWidth"), NumericMethod(frame, "GetHeight")
    local uiWidth, uiHeight = NumericMethod(uiParent, "GetWidth"), NumericMethod(uiParent, "GetHeight")
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

local function CatalogMode(mode)
    local result = { allowImplicitProtected = true }
    if type(mode) == "table" then
        for key, value in pairs(mode) do
            result[key] = value
        end
    elseif type(mode) == "string" then
        result.role = RootRole(mode)
    end
    return result
end

local function SkinNode(frame, owner, metrics, isRoot)
    local objectType = ObjectType(frame)
    local name = ObjectName(frame)

    if NS.BlizzardYellow then NS.BlizzardYellow.TrackFrame(frame) end
    if metrics.menuPopup and NS.BlizzardYellow then
        NS.BlizzardYellow.TrackMenuSelection(frame)
    end
    if NS.Checkmarks then
        NS.Checkmarks.TrackFrame(frame, owner)
        NS.Checkmarks.TrackDropdown(frame, owner)
    end

    -- HUD systems frequently own secure descendants or semantic artwork whose
    -- geometry and textures must stay native.  Accent-only catalog entries
    -- deliberately stop after recoloring already-existing text and verified
    -- Blizzard glyph textures.  They create no regions, fade no artwork, and
    -- never alter scripts, anchors, attributes, visibility, or actions.
    if metrics.accentOnly then
        if LooksLikeScrollBox(frame, name) then
            metrics.dynamicScrollBoxes[frame] = true
        end
        return
    end

    if not (isRoot and metrics.preserveRootArt) then
        FadeSeparators(frame, owner, isRoot and metrics.rootChromeTargets or nil)
    end

    if LooksLikeScrollBox(frame, name) then
        metrics.dynamicScrollBoxes[frame] = true
    end

    if isRoot then
        if not metrics.preserveRootArt then
            FadeChrome(frame, owner, metrics.rootChromeTargets)
            FadeAnonymousChrome(frame, owner, metrics.rootChromeTargets)
            if metrics.menuPopup then FadeMenuPopupArt(frame, owner, metrics.rootChromeTargets) end
        end
    elseif objectType == "Button" or IsDropdown(frame) then
        if not SkinButton(frame, owner, metrics) then
            local iconName = name:find("Close", 1, true) or name:find("Minimize", 1, true)
                or name:find("Maximize", 1, true) or name:find("Next", 1, true)
                or name:find("Prev", 1, true)
            if iconName then
                SkinIconButtonBase(frame, owner, metrics)
            elseif metrics.menuPopup then
                Attach(owner, frame, {
                    role = "card",
                    radius = 4,
                    inset = 0,
                    listItem = true,
                    interactive = true,
                    allowImplicitProtected = metrics.allowImplicitProtected,
                }, metrics)
            elseif objectType == "Button" and type(frame.GetFontString) == "function"
                and frame:GetFontString() then
                -- Unknown text buttons keep their native art; add only the
                -- theme hover outline so menus remain consistently readable.
                Attach(owner, frame, {
                    role = "button", border = 0, fillVisible = false,
                    interactive = true,
                    allowImplicitProtected = metrics.allowImplicitProtected,
                }, metrics)
            end
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
-- intentionally opaque).  Probe only this fixed field vocabulary; this gives
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

local function ResolveFieldPath(frame, path)
    local target = frame
    for index = 1, #path do
        target = SafeField(target, path[index])
        if not target then return nil end
    end
    return target
end

local function SkinExplicitPanel(panel, fieldName, owner, metrics)
    if not panel or IsUnsafe(panel, metrics.allowImplicitProtected) or not HasChrome(panel) then
        return false
    end
    if metrics.childSurfaces then
        if Attach(owner, panel, {
            role = ChildPanelRole(fieldName),
            radius = 6,
            inset = 0,
        }, metrics) then
            metrics.childSurfaceTargets[panel] = true
        end
    end
    FadeChrome(panel, owner)
    return true
end

local function SkinExplicitFields(frame, owner, metrics)
    -- Legacy Retail dropdown lists (currently retained by a small PvP path)
    -- expose their native backdrops as Border/MenuBackdrop and their rows as
    -- Button1..N rather than children of the opening dropdown control.
    if metrics.legacyDropdown == true then
        local border = SafeField(frame, "Border")
        local backdrop = SafeField(frame, "MenuBackdrop")
        if border then FadeChrome(border, owner) end
        if backdrop then FadeChrome(backdrop, owner) end
        local count = math.max(tonumber(SafeField(frame, "numButtons")) or 0, 1)
        count = math.min(count, 64)
        local frameName = ObjectName(frame)
        for index = 1, count do
            local button = SafeField(frame, "Button" .. index)
                or (frameName ~= "" and _G[frameName .. "Button" .. index])
            if button and not IsUnsafe(button, metrics.allowImplicitProtected) then
                if NS.Checkmarks then NS.Checkmarks.TrackFrame(button, owner) end
                Attach(owner, button, {
                    role = "card", radius = 4, inset = 0, listItem = true,
                    interactive = true,
                    allowImplicitProtected = metrics.allowImplicitProtected,
                }, metrics)
            end
        end
    end

    for index = 1, #explicitButtonFields do
        local control = SafeField(frame, explicitButtonFields[index])
        if control and not IsUnsafeControl(control, metrics.allowImplicitProtected)
            and ObjectType(control) == "Button" then
            if not SkinButton(control, owner, metrics) then
                SkinIconButtonBase(control, owner, metrics, explicitButtonFields[index])
            end
        end
    end

    for index = 1, #explicitTabFields do
        local tab = SafeField(frame, explicitTabFields[index])
        if tab and not IsUnsafeControl(tab, metrics.allowImplicitProtected)
            and ObjectType(tab) == "Button" then
            SkinButton(tab, owner, metrics)
        end
    end

    for index = 1, #explicitInputFields do
        local input = SafeField(frame, explicitInputFields[index])
        if input and not IsUnsafeControl(input, metrics.allowImplicitProtected) then
            SkinInput(input, owner, metrics)
        end
    end

    for index = 1, #explicitScrollFields do
        local scrollBar = SafeField(frame, explicitScrollFields[index])
        if scrollBar and not IsUnsafe(scrollBar, metrics.allowImplicitProtected) then
            SkinScrollBar(scrollBar, owner, metrics)
        end
    end

    for index = 1, #explicitPanelFields do
        local panel = SafeField(frame, explicitPanelFields[index])
        SkinExplicitPanel(panel, explicitPanelFields[index], owner, metrics)
    end

    for index = 1, #explicitPanelPaths do
        local path = explicitPanelPaths[index]
        SkinExplicitPanel(ResolveFieldPath(frame, path), path[#path], owner, metrics)
    end
end

local function ReadChildren(frame)
    local getter = SafeField(frame, "GetChildren")
    if type(getter) ~= "function" then
        return nil
    end

    local children = {}
    local ok = pcall(function()
        local function Pack(...)
            local count = select("#", ...)
            for index = 1, count do
                children[#children + 1] = select(index, ...)
            end
        end
        Pack(getter(frame))
    end)
    if not ok then
        return nil
    end

    return children
end

local function AppendChildren(frame, queue, depths, depth, limit)
    local children = ReadChildren(frame)
    if not children then return 0, 0 end

    local appended = 0
    for index = 1, #children do
        if #queue >= limit then
            break
        end
        queue[#queue + 1] = children[index]
        depths[#depths + 1] = depth
        appended = appended + 1
    end
    return #children, appended
end

local ApplyFrameNow

local function ScrollBoxInitializedEvent()
    return ScrollBoxListMixin and ScrollBoxListMixin.Event
        and ScrollBoxListMixin.Event.OnInitializedFrame
end

local function RegisterDynamicScrollBox(scrollBox, owner, allowImplicitProtected, menuPopup)
    local event = ScrollBoxInitializedEvent()
    local ownerState = OwnerState(owner)
    if not event or ownerState.scrollBoxes[scrollBox]
        or type(SafeField(scrollBox, "RegisterCallback")) ~= "function" then
        return false
    end

    -- The callback can fire repeatedly while rows recycle in combat. Keep
    -- its immutable mode beside the registration instead of allocating it
    -- for every row, including rows we intentionally skip while locked.
    local mode = {
        role = "card",
        radius = 4,
        inset = 0,
        listItem = true,
        maxDepth = 4,
        maxNodes = 120,
        allowImplicitProtected = allowImplicitProtected == true,
        menuPopup = menuPopup == true,
    }
    local function SkinRow(_, row)
        if not ownerState.active or not row then
            return
        end
        if NS.IsCombatLocked() then
            -- Optional pooled-row cosmetics never justify combat work or a
            -- post-combat backlog. A later OOC initialization/refresh handles
            -- the row naturally.
            return
        end
        ApplyFrameNow(row, owner, mode)
    end

    local ok = pcall(scrollBox.RegisterCallback, scrollBox, event, SkinRow, ownerState)
    if not ok then
        return false
    end
    ownerState.scrollBoxes[scrollBox] = true
    pcall(scrollBox.ForEachFrame, scrollBox, function(row)
        SkinRow(ownerState, row)
    end)
    return true
end

ApplyFrameNow = function(frame, owner, mode)
    if not frame then return false, "invalid", nil end
    local allowImplicitProtected = ModeValue(mode, "allowImplicitProtected", false) == true
    if IsUnsafe(frame, allowImplicitProtected) then
        local reason = NS.Safety and NS.Safety.IsCompositorManaged(frame)
            and "compositor" or "protected"
        return false, reason, nil
    end
    if type(SafeField(frame, "CreateTexture")) ~= "function" then return false, "invalid", nil end

    local previousState = frameStates[frame]
    local metrics = {
        nodes = 0,
        surfaces = 0,
        controls = 0,
        scrollBars = 0,
        protected = 0,
        errors = 0,
        truncated = false,
        surfaceTargets = setmetatable({}, { __mode = "k" }),
        childSurfaceTargets = setmetatable({}, { __mode = "k" }),
        controlTargets = setmetatable({}, { __mode = "k" }),
        scrollTargets = setmetatable({}, { __mode = "k" }),
        dynamicScrollBoxes = setmetatable({}, { __mode = "k" }),
        allowImplicitProtected = allowImplicitProtected,
        menuPopup = ModeValue(mode, "menuPopup", false) == true,
        legacyDropdown = ModeValue(mode, "legacyDropdown", false) == true,
        preserveRootArt = ModeValue(mode, "preserveRootArt", false) == true,
        accentOnly = ModeValue(mode, "accentOnly", false) == true,
        childSurfaces = ModeValue(mode, "childSurfaces", true) ~= false,
        rootChromeTargets = setmetatable({}, { __mode = "k" }),
    }

    local wantsRootSurface = ModeValue(mode, "rootSurface", true) ~= false
    metrics.fullscreenGuarded = wantsRootSurface and not metrics.accentOnly
        and IsFullscreenRoot(frame) or false
    if metrics.fullscreenGuarded then
        metrics.preserveRootArt = true
    end

    if metrics.preserveRootArt and previousState and previousState.owner == owner then
        for region in pairs(previousState.rootChromeTargets or {}) do
            pcall(NS.Cosmetics.Restore, region, owner)
        end
    end

    local maxDepth = tonumber(ModeValue(mode, "maxDepth", GenericWindows.maxDepth)) or GenericWindows.maxDepth
    local maxNodes = tonumber(ModeValue(mode, "maxNodes", GenericWindows.maxNodes)) or GenericWindows.maxNodes
    maxDepth = math.max(0, math.min(12, math.floor(maxDepth)))
    maxNodes = math.max(1, math.min(1200, math.floor(maxNodes)))

    local rootSurfaceAttached = false
    if wantsRootSurface and not metrics.fullscreenGuarded then
        if not Attach(owner, frame, {
            role = RootRole(mode),
            radius = ModeValue(mode, "radius", 8),
            inset = ModeValue(mode, "inset", 0),
            border = ModeValue(mode, "border", nil),
            fillVisible = ModeValue(mode, "fillVisible", true) ~= false,
            listItem = ModeValue(mode, "listItem", false) == true,
            allowImplicitProtected = allowImplicitProtected,
        }, metrics) then
            return false, "surface", metrics
        end
        rootSurfaceAttached = true
    elseif previousState and previousState.owner == owner
        and previousState.rootSurfaceAttached == true then
        pcall(NS.Surface.SetVisible, frame, false)
    end

    if not metrics.accentOnly then
        SkinExplicitFields(frame, owner, metrics)
    end

    local queue, depths = { frame }, { 0 }
    local head = 1
    while head <= #queue and metrics.nodes < maxNodes do
        local current = queue[head]
        local depth = depths[head]
        head = head + 1

        if (NS.CharacterDetails and NS.CharacterDetails.IsHost(current))
            or (NS.CharacterStats and NS.CharacterStats.IsHost(current))
            or (NS.EQoLCharacter and NS.EQoLCharacter.IsHost(current)) then
            -- Owned equipment UI has its own styling and lifecycle. Do not
            -- rescan its subtree as if it were Blizzard-authored chrome.
        elseif IsUnsafe(current, allowImplicitProtected) then
            metrics.protected = metrics.protected + 1
        else
            metrics.nodes = metrics.nodes + 1
            local ok = pcall(SkinNode, current, owner, metrics, current == frame)
            if not ok then
                metrics.errors = metrics.errors + 1
            end
            if depth < maxDepth then
                local childCount, appended = AppendChildren(current, queue, depths, depth + 1, maxNodes)
                if appended < childCount then metrics.truncated = true end
            else
                local children = ReadChildren(current)
                if children and #children > 0 then metrics.truncated = true end
            end
        end
    end
    metrics.truncated = metrics.truncated or head <= #queue or #queue >= maxNodes
    local ownerState = OwnerState(owner)
    ownerState.active = true
    if ModeValue(mode, "registerDynamicRows", true) ~= false then
        for scrollBox in pairs(metrics.dynamicScrollBoxes) do
            RegisterDynamicScrollBox(scrollBox, owner, allowImplicitProtected, metrics.menuPopup)
        end
    end
    local childSurfaceTargets = metrics.childSurfaceTargets
    local rootChromeTargets = metrics.rootChromeTargets
    if not metrics.childSurfaces and previousState and previousState.owner == owner then
        for target in pairs(previousState.childSurfaceTargets or {}) do
            pcall(NS.Surface.SetVisible, target, false)
        end
    end
    metrics.surfaceTargets = nil
    metrics.childSurfaceTargets = nil
    metrics.controlTargets = nil
    metrics.scrollTargets = nil
    metrics.dynamicScrollBoxes = nil
    metrics.allowImplicitProtected = nil
    metrics.menuPopup = nil
    metrics.legacyDropdown = nil
    metrics.preserveRootArt = nil
    metrics.accentOnly = nil
    metrics.childSurfaces = nil
    metrics.rootChromeTargets = nil

    local state = previousState or {}
    state.owner = owner
    state.mode = mode
    state.metrics = metrics
    state.rootSurfaceAttached = rootSurfaceAttached
    state.childSurfaceTargets = childSurfaceTargets
    state.rootChromeTargets = rootChromeTargets
    state.active = true
    frameStates[frame] = state

    ownerState.frames[frame] = true
    if NS.WindowControls then NS.WindowControls.Attach(frame, owner) end
    return true, "applied", metrics
end

OwnerKey = function(owner)
    return tostring(owner or DEFAULT_OWNER)
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
    if type(addon) ~= "string" or addon == "" then
        return true
    end
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loadedOrLoading, loaded = pcall(C_AddOns.IsAddOnLoaded, addon)
        if not ok then
            return false
        end
        if loaded ~= nil then
            return AccessibleBoolean(loaded) == true
        end
        return AccessibleBoolean(loadedOrLoading) == true
    end
    if type(IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(IsAddOnLoaded, addon)
        return ok and AccessibleBoolean(loaded) == true
    end
    return false
end

local function CatalogEntries()
    local catalog = NS.BlizzardCatalog
    local source = catalog and catalog.entries
    local entries = {}
    if type(source) ~= "table"
        or type(catalog.IsGlassContractValid) ~= "function"
        or type(catalog.IsEntryGlassReady) ~= "function"
        or catalog.IsGlassContractValid() ~= true then
        return entries
    end
    for _, entry in pairs(source) do
        if type(entry) == "table" and type(entry.id) == "string"
            and entry.skipGeneric ~= true
            and catalog.IsEntryGlassReady(entry) == true then
            entries[#entries + 1] = entry
        end
    end
    table.sort(entries, function(left, right) return left.id < right.id end)
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
    if type(addon) ~= "string" or addon == "" or IsAddonLoaded(addon) then
        return false
    end
    if NS.Client and NS.Client.HasAddOn(addon)==false then return false end

    local bucket = pendingAddons[addon]
    if not bucket then
        bucket = {}
        pendingAddons[addon] = bucket
        pendingAddonCount = pendingAddonCount + 1
    end
    local key = entry.id .. ":" .. OwnerKey(owner)
    bucket[key] = { entry = entry, owner = owner }
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

function GenericWindows.IsCategoryEnabled(category)
    local categories = NS.DB and NS.DB.skinCategories
    return type(category) ~= "string" or not categories or categories[category] ~= false
end

function GenericWindows.ApplyEntry(entry, owner)
    owner = owner or DEFAULT_OWNER
    if type(entry) ~= "table" or type(entry.id) ~= "string" then
        return false, "invalid"
    end
    if not Enabled() then
        entryStatus[entry.id] = { state = "disabled", frames = 0, owner = owner }
        return false, "disabled"
    end
    if not GenericWindows.IsCategoryEnabled(entry.category) then
        entryStatus[entry.id] = { state = "disabled", frames = 0, owner = owner }
        entryOwners[entry.id] = owner
        return false, "disabled"
    end
    if entry.addon and NS.Client and NS.Client.HasAddOn(entry.addon)==false then
        entryStatus[entry.id] = { state = "unavailable", frames = 0, owner = owner }
        return false, "unavailable"
    end

    if NS.IsCombatLocked() then
        local ownerState = OwnerState(owner)
        local key = "generic-entry:" .. entry.id .. ":" .. OwnerKey(owner)
        ownerState.deferred[key] = true
        entryStatus[entry.id] = { state = "queued", frames = 0, owner = owner }
        NS.CombatGate.RunOrDefer(key, function()
            ownerState.deferred[key] = nil
            GenericWindows.ApplyEntry(entry, owner)
        end)
        return false, "combat"
    end

    if entry.addon and not IsAddonLoaded(entry.addon) then
        AddPending(entry, owner)
        entryStatus[entry.id] = { state = "waiting", frames = 0, owner = owner }
        entryOwners[entry.id] = owner
        return false, "waiting"
    end

    local applied, failed, protected = 0, 0, 0
    local totals = {
        nodes = 0, surfaces = 0, controls = 0, scrollBars = 0,
        protected = 0, errors = 0, fullscreenGuarded = 0,
        truncated = false,
    }

    for index = 1, #((type(entry.frames) == "table" and entry.frames) or {}) do
        local frameValue = entry.frames[index]
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
                if reason == "protected" then
                    protected = protected + 1
                end
            end
            if metrics then
                for _, key in ipairs({ "nodes", "surfaces", "controls", "scrollBars", "protected", "errors" }) do
                    totals[key] = totals[key] + (metrics[key] or 0)
                end
                if metrics.fullscreenGuarded == true then
                    totals.fullscreenGuarded = totals.fullscreenGuarded + 1
                end
                totals.truncated = totals.truncated or metrics.truncated == true
            end
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
            entryStatus[entry.id] = { state = "waiting", frames = 0, owner = owner }
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
            item.frames = item.frames + #(entry.frames or {})
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

local function DisableNow(owner)
    if NS.MacroWindow then NS.MacroWindow.Disable(owner) end
    if NS.WindowControls then NS.WindowControls.DisableOwner(owner) end
    local ownerState = ownerStates[owner]
    if ownerState then
        ownerState.active = false
        for key in pairs(ownerState.deferred) do
            NS.CombatGate.Cancel(key)
        end
        ownerState.deferred = {}

        local event = ScrollBoxInitializedEvent()
        if event then
            for scrollBox in pairs(ownerState.scrollBoxes) do
                local unregister = SafeField(scrollBox, "UnregisterCallback")
                if type(unregister) == "function" then
                    pcall(unregister, scrollBox, event, ownerState)
                end
            end
        end
        ownerState.scrollBoxes = setmetatable({}, { __mode = "k" })

        pcall(NS.IconSkin.DisableOwner, owner)
        pcall(NS.ControlSkin.DisableOwner, owner)
        if NS.Checkmarks and type(NS.Checkmarks.UntrackOwner) == "function" then
            pcall(NS.Checkmarks.UntrackOwner, owner)
        end
        if NS.ScrollBarSkin and type(NS.ScrollBarSkin.DisableOwner) == "function" then
            pcall(NS.ScrollBarSkin.DisableOwner, owner)
        end
        pcall(NS.Cosmetics.RestoreOwner, owner)
        for target in pairs(ownerState.surfaces) do
            pcall(NS.Surface.SetVisible, target, false)
        end
        for _, glyph in pairs(ownerState.glyphs) do
            if glyph and type(glyph.Hide) == "function" then
                glyph:Hide()
            end
        end
        for frame in pairs(ownerState.frames) do
            local state = frameStates[frame]
            if state and state.owner == owner then
                state.active = false
            end
        end
    else
        pcall(NS.IconSkin.DisableOwner, owner)
        pcall(NS.ControlSkin.DisableOwner, owner)
        if NS.Checkmarks and type(NS.Checkmarks.UntrackOwner) == "function" then
            pcall(NS.Checkmarks.UntrackOwner, owner)
        end
        if NS.ScrollBarSkin and type(NS.ScrollBarSkin.DisableOwner) == "function" then
            pcall(NS.ScrollBarSkin.DisableOwner, owner)
        end
        pcall(NS.Cosmetics.RestoreOwner, owner)
    end

    RemovePendingForOwner(owner)
    for id, appliedOwner in pairs(entryOwners) do
        if appliedOwner == owner then
            entryStatus[id] = {
                state = "disabled",
                frames = 0,
                owner = owner,
            }
        end
    end
    return true
end

function GenericWindows.Disable(owner)
    owner = owner or DEFAULT_OWNER
    local ownerState = OwnerState(owner)
    for key in pairs(ownerState.deferred) do
        NS.CombatGate.Cancel(key)
        ownerState.deferred[key] = nil
    end

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
                for _, key in ipairs({
                    "surfaces", "controls", "scrollBars", "nodes",
                    "fullscreenGuarded", "errors",
                }) do
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
    if event ~= "ADDON_LOADED" then
        return
    end
    local bucket = pendingAddons[addon]
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
