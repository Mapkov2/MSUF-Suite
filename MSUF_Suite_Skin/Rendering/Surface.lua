local _, NS = ...

local Surface = {}
NS.Surface = Surface

local STRETCHED = Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0
-- Blizzard's special highlight must remain on HIGHLIGHT so it renders above
-- the normal button edge. Text safety comes from the outline asset's fully
-- transparent center, not from burying the highlight below other regions.
local BUTTON_HIGHLIGHT_LAYER = "HIGHLIGHT"
local BUTTON_HIGHLIGHT_SUBLEVEL = 0
-- Full-surface pressed/disabled fills must remain behind Blizzard's ARTWORK
-- labels, ratings and semantic icons. Native button atlases can live on
-- ARTWORK because their centers are transparent; our material fills cannot.
local BUTTON_PUSHED_LAYER = "BACKGROUND"
local BUTTON_PUSHED_SUBLEVEL = -5
local BUTTON_DISABLED_LAYER = "BACKGROUND"
local BUTTON_DISABLED_SUBLEVEL = -4

local structuralRoles = {
    shell = true,
    panel = true,
    card = true,
    popup = true,
}

local function CanDecorate(target, spec)
    return NS.Safety and NS.Safety.CanCreateRegions(target, spec and spec.allowImplicitProtected)
end

local function CanControl(target, spec)
    -- CanCreateRegions includes the same protection gate plus compositor safety.
    return NS.Safety and NS.Safety.CanCreateRegions(target, spec and spec.allowImplicitProtected)
end

local function CanRefreshState(state)
    if not state then
        return false
    end
    if state.kind == "button" then
        return CanControl(state.target, state.spec)
    end
    return CanDecorate(state.target, state.spec)
end

local function AnchorTexture(texture, target, inset)
    texture:ClearAllPoints()
    inset = tonumber(inset) or 0
    texture:SetPoint("TOPLEFT", target, "TOPLEFT", inset, -inset)
    texture:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", -inset, inset)
end

local function ConfigureShape(texture, asset, geometry)
    if not texture or not asset then
        return
    end
    if texture.ClearTextureSlice then
        texture:ClearTextureSlice()
    end
    texture:SetTexture(asset)
    if geometry.slice and texture.SetTextureSliceMargins then
        texture:SetTextureSliceMargins(
            geometry.margins[1],
            geometry.margins[2],
            geometry.margins[3],
            geometry.margins[4]
        )
        if texture.SetTextureSliceMode then
            texture:SetTextureSliceMode(STRETCHED)
        end
    end
end

local function SetVertexColor(texture, colorKey, alphaScale)
    local r, g, b, a = NS.Theme.GetColor(colorKey)
    texture:SetVertexColor(r, g, b, a * (alphaScale or 1))
end

local function ReuseColor(color, r, g, b, a)
    if color and color.r == r and color.g == g and color.b == b and color.a == a then
        return color
    end
    return CreateColor(r, g, b, a)
end

local function ApplyFill(texture, material, state)
    local from = NS.Theme.GetColorTable(material.from)
    local to = NS.Theme.GetColorTable(material.to)
    local opacity = NS.Theme.GetMaterialOpacity(material)
        * (tonumber(state.spec.fillAlphaScale) or 1)
    local strength = NS.DB.theme.gradientStrength or 1
    local toR = from[1] + (to[1] - from[1]) * strength
    local toG = from[2] + (to[2] - from[2]) * strength
    local toB = from[3] + (to[3] - from[3]) * strength
    local toA = from[4] + (to[4] - from[4]) * strength
    texture:SetVertexColor(1, 1, 1, 1)
    if NS.DB.theme.gradient and texture.SetGradient and type(CreateColor) == "function" then
        -- ColorUtil's RGBA objects are immutable inputs here. Reuse only exact
        -- values; still call SetGradient every time to repair native resets.
        state.gradientFrom = ReuseColor(state.gradientFrom, from[1], from[2], from[3], from[4] * opacity)
        state.gradientTo = ReuseColor(state.gradientTo, toR, toG, toB, toA * opacity)
        texture:SetGradient(
            NS.DB.theme.gradientDirection or "VERTICAL",
            state.gradientFrom,
            state.gradientTo
        )
    else
        texture:SetVertexColor(from[1], from[2], from[3], from[4] * opacity)
    end
end

local function MaterialForState(state)
    local role = state.spec.role or "panel"
    if state.active and state.spec.activeRole then
        role = state.spec.activeRole
    end
    return NS.Theme.GetMaterial(role)
end

local function RoleForState(state)
    if state.active and state.spec.activeRole then
        return state.spec.activeRole
    end
    return state.spec.role or "panel"
end

local function SupportsDepth(state)
    if state.kind == "button" or state.spec.listItem == true then
        return false
    end
    return structuralRoles[RoleForState(state)] == true
end

local function RefreshDepth(state, geometry, material, suppressFill)
    local amount = tonumber((NS.DB and NS.DB.theme and NS.DB.theme.materialDepth)
        or NS.Defaults.theme.materialDepth) or 0
    if amount <= 0 or state.spec.fillVisible == false or suppressFill
        or not SupportsDepth(state) or not geometry.hoverEdge then
        if state.depth then state.depth:Hide() end
        return
    end
    if not state.depth then
        state.depth = state.target:CreateTexture(nil, "BACKGROUND", nil, -6)
        AnchorTexture(state.depth, state.target, (tonumber(state.spec.inset) or 0) + 1)
    end
    ConfigureShape(state.depth, geometry.hoverEdge, geometry)
    SetVertexColor(state.depth, "background", amount * NS.Theme.GetMaterialOpacity(material))
    if state.visible == false then
        state.depth:Hide()
    else
        state.depth:Show()
    end
end

local GLASS_COMPOSITING_ALPHA_CUTOFF = 0.94

local function UsesGlassCompositing()
    -- Looks and color palettes are independently selectable. Resolve the
    -- actual shell material instead of coupling compositing to either name:
    -- a Glass look with another palette and an opaque look with a translucent
    -- palette must both retain the same single-base-fill behavior.
    local material = NS.Theme.GetMaterial("shell")
    if type(material) ~= "table" then return false end
    local from = NS.Theme.GetColorTable(material.from)
    local to = NS.Theme.GetColorTable(material.to)
    local fromAlpha = type(from) == "table" and tonumber(from[4]) or nil
    local toAlpha = type(to) == "table" and tonumber(to[4]) or nil
    local opacity = tonumber(NS.Theme.GetMaterialOpacity(material))
    if not fromAlpha or not toAlpha or not opacity then return false end
    return math.max(fromAlpha, toAlpha) * opacity < GLASS_COMPOSITING_ALPHA_CUTOFF
end

local function SafeParent(target)
    if not target then return nil end
    local getterOK, getParent = pcall(function() return target.GetParent end)
    if not getterOK or type(getParent) ~= "function" then return nil end
    local parentOK, parent = pcall(getParent, target)
    return parentOK and parent or nil
end

local function HasFilledStructuralSurfaceAncestor(state)
    local current = state and state.target
    local seen = {}
    local ancestors = {}
    for _ = 1, 12 do
        local parent = SafeParent(current)
        if not parent or seen[parent] then break end
        seen[parent] = true
        local ancestor = NS.Registry.GetSurface(parent)
        if ancestor and ancestor.visible ~= false and SupportsDepth(ancestor) then
            ancestors[#ancestors + 1] = ancestor
        end
        current = parent
    end

    -- Resolve from the outermost surface inward. Panels flatten by default;
    -- adapters can explicitly set keepGlassFill=false on another role when
    -- verified full-area chrome would otherwise stack another scrim.
    -- Explicit edge-only ancestors never make all descendants transparent.
    local hasFilledBase = false
    for index = #ancestors, 1, -1 do
        local ancestor = ancestors[index]
        local fills = ancestor.spec.fillVisible ~= false
            and not (ancestor.spec.listItem == true and ancestor.active ~= true)
        local flatten = ancestor.spec.keepGlassFill == false
            or (ancestor.spec.keepGlassFill == nil and RoleForState(ancestor) == "panel")
        if fills and flatten and hasFilledBase then
            fills = false
        end
        hasFilledBase = hasFilledBase or fills
    end
    return hasFilledBase
end

local function SuppressNestedGlassFill(state)
    local flatten = state.spec.keepGlassFill == false
        or (state.spec.keepGlassFill == nil and RoleForState(state) == "panel")
    return flatten
        and state.spec.listItem ~= true
        and UsesGlassCompositing()
        and HasFilledStructuralSurfaceAncestor(state)
end

local function AddToken(tokens, key)
    if not key then return end
    for index = 1, #tokens do
        if tokens[index] == key then return end
    end
    tokens[#tokens + 1] = key
end

local function AddMaterialTokens(tokens, role)
    local material = NS.Theme.GetMaterial(role)
    AddToken(tokens, material.from)
    AddToken(tokens, material.to)
    AddToken(tokens, material.border)
end

local function SurfaceTokens(state)
    local tokens = state.tokens
    if not tokens then tokens = {}; state.tokens = tokens end
    for index = #tokens, 1, -1 do tokens[index] = nil end
    AddMaterialTokens(tokens, state.spec.role or "panel")
    if state.spec.activeRole then
        AddMaterialTokens(tokens, state.spec.activeRole)
    end
    if state.kind == "button" then
        AddToken(tokens, "hover")
        AddToken(tokens, "pressed")
        AddToken(tokens, "disabled")
    elseif state.hoverOverlay then
        AddToken(tokens, "hover")
    end
    if SupportsDepth(state) then
        AddToken(tokens, "background")
    end
    return tokens
end

local controlOpacityMaterial = { opacity = "control" }

local function RefreshButtonState(state, geometry)
    if state.kind ~= "button" then
        return
    end
    local theme = NS.DB and NS.DB.theme or NS.Defaults.theme
    local visibleScale = state.visible == false and 0 or NS.Theme.GetMaterialOpacity(controlOpacityMaterial)
    local hoverStyle = theme.hoverStyle or NS.Defaults.theme.hoverStyle
    local hoverScale = visibleScale * (tonumber(theme.hoverIntensity) or 1)
    local hoverAsset = geometry.fill
    if hoverStyle == "outline" then
        hoverAsset = geometry.hoverEdge
    elseif hoverStyle == "softFill" then
        hoverScale = hoverScale * 0.28
    elseif hoverStyle == "off" then
        hoverScale = 0
    end
    ConfigureShape(state.highlight, hoverAsset, geometry)
    ConfigureShape(state.pushed, geometry.fill, geometry)
    ConfigureShape(state.disabled, geometry.fill, geometry)
    SetVertexColor(state.highlight, "hover", hoverScale)
    SetVertexColor(state.pushed, "pressed", visibleScale)
    SetVertexColor(state.disabled, "disabled", 0.45 * visibleScale)
end

local function RefreshInteractiveHover(state, geometry)
    local overlay = state.hoverOverlay
    if not overlay then return end
    if state.kind == "button" then overlay:Hide(); return end
    local theme = NS.DB and NS.DB.theme or NS.Defaults.theme
    local hoverStyle = theme.hoverStyle or NS.Defaults.theme.hoverStyle
    local asset = hoverStyle == "outline" and geometry.hoverEdge or geometry.fill
    local scale = NS.Theme.GetMaterialOpacity(controlOpacityMaterial)
        * (tonumber(theme.hoverIntensity) or 1)
    if hoverStyle == "softFill" then
        scale = scale * 0.28
    elseif hoverStyle == "off" then
        scale = 0
    end
    ConfigureShape(overlay, asset, geometry)
    SetVertexColor(overlay, "hover", scale)
    state.hoverEnabled = scale > 0
    if state.visible and state.hovered and state.hoverEnabled then overlay:Show()
    else overlay:Hide() end
end

local function EnsureInteractiveHover(target, state)
    local kind = type(target.GetObjectType) == "function" and target:GetObjectType()
    local role = state.spec.role
    local interactive = state.spec.interactive or state.spec.listItem
        or role == "button" or role == "navigation"
    if kind ~= "Button" or not interactive or state.hoverOverlay or state.kind == "button"
        or type(target.HookScript) ~= "function" or not CanControl(target) then return end
    local overlay = target:CreateTexture(nil, BUTTON_HIGHLIGHT_LAYER, nil, BUTTON_HIGHLIGHT_SUBLEVEL)
    AnchorTexture(overlay, target, state.spec.inset)
    overlay:Hide()
    state.hoverOverlay = overlay
    target:HookScript("OnEnter", function()
        state.hovered = true
        if state.visible and state.hoverEnabled and state.kind ~= "button" then overlay:Show() end
    end)
    target:HookScript("OnLeave", function()
        state.hovered = false
        overlay:Hide()
    end)
end

local function RefreshState(state)
    if not CanRefreshState(state) then
        return false
    end
    if state.syncNativeSelected and state.target then
        local selected = state.target.isSelected
        if selected == nil and type(state.target.IsSelected) == "function" then
            local ok, value = pcall(state.target.IsSelected, state.target)
            selected = ok and value or nil
        end
        if selected ~= nil then
            state.active = selected == true
        end
    end
    local geometry = NS.Geometry.Resolve(state.spec, state.geometry)
    state.geometry = geometry
    local material = MaterialForState(state)
    local hideIdleListFill = state.spec.listItem == true and state.active ~= true
    local suppressNestedGlassFill = SuppressNestedGlassFill(state)
    ConfigureShape(state.fill, geometry.fill, geometry)
    ApplyFill(state.fill, material, state)

    local edgeAsset = geometry.edge
    if state.active and state.spec.activeEdge then
        edgeAsset = geometry.hoverEdge
    end
    if not edgeAsset and state.spec.forceEdge then
        edgeAsset = geometry.hoverEdge
    end
    if edgeAsset then
        ConfigureShape(state.edge, edgeAsset, geometry)
        SetVertexColor(state.edge, material.border, NS.Theme.GetBorderOpacity())
        state.edge:Show()
    else
        state.edge:Hide()
    end

    RefreshDepth(state, geometry, material, suppressNestedGlassFill)

    RefreshButtonState(state, geometry)
    RefreshInteractiveHover(state, geometry)
    if state.visible == false then
        state.fill:Hide()
        state.edge:Hide()
        if state.depth then state.depth:Hide() end
    else
        -- Dense Blizzard lists should read as one continuous panel, not a
        -- stack of boxed cards. Keep the normal row transparent; button
        -- highlight/pushed textures and an explicit active state still supply
        -- interaction and selection feedback.
        if state.spec.fillVisible == false or hideIdleListFill or suppressNestedGlassFill then
            state.fill:Hide()
        else
            state.fill:Show()
        end
        if edgeAsset then
            state.edge:Show()
        end
    end
    return true
end

local function AttachNow(target, spec, deferRefresh)
    if NS.BlizzardYellow then NS.BlizzardYellow.TrackFrame(target) end
    local state = NS.Registry.GetSurface(target)
    if state then
        state.spec = spec or state.spec
        state.visible = true
        EnsureInteractiveHover(target, state)
        if state.hoverOverlay then AnchorTexture(state.hoverOverlay, target, state.spec.inset) end
        NS.Registry.RegisterSurface(target, state, SurfaceTokens(state))
        if not deferRefresh then state.refresh(state) end
        return state
    end

    local fill = target:CreateTexture(nil, "BACKGROUND", nil, -7)
    local edge = target:CreateTexture(nil, "BORDER", nil, 7)
    AnchorTexture(fill, target, spec and spec.inset)
    AnchorTexture(edge, target, spec and spec.inset)

    state = {
        target = target,
        spec = spec or {},
        fill = fill,
        edge = edge,
        visible = true,
        refresh = RefreshState,
    }
    EnsureInteractiveHover(target, state)
    NS.Registry.RegisterSurface(target, state, SurfaceTokens(state))
    if not deferRefresh then state.refresh(state) end
    return state
end

function Surface.Attach(target, spec)
    if not target then
        return nil, "invalid target"
    end
    if not CanDecorate(target, spec) then
        return nil, "protected target"
    end
    if type(target.CreateTexture) ~= "function" then return nil, "invalid target" end
    if NS.IsCombatLocked() then
        local _, reason = NS.CombatGate.RunOrDefer("surface:" .. tostring(target), function()
            Surface.Attach(target, spec)
        end)
        return nil, reason
    end
    local existing = NS.Registry.GetSurface(target)
    if existing then
        if NS.BlizzardYellow then NS.BlizzardYellow.TrackFrame(target) end
        existing.spec = spec or existing.spec
        existing.visible = true
        EnsureInteractiveHover(target, existing)
        if existing.hoverOverlay then AnchorTexture(existing.hoverOverlay, target, existing.spec.inset) end
        NS.Registry.RegisterSurface(target, existing, SurfaceTokens(existing))
        if not NS.IsCombatLocked() then
            existing.refresh(existing)
        end
        return existing
    end

    local state
    local ran, reason = NS.CombatGate.RunOrDefer("surface:" .. tostring(target), function()
        state = AttachNow(target, spec)
    end)
    return ran and state or nil, reason
end

local function AddButtonStateTextures(button, state)
    if state.kind == "button" then
        return
    end
    state.kind = "button"
    state.highlight = button:CreateTexture(nil, BUTTON_HIGHLIGHT_LAYER, nil, BUTTON_HIGHLIGHT_SUBLEVEL)
    state.pushed = button:CreateTexture(nil, BUTTON_PUSHED_LAYER, nil, BUTTON_PUSHED_SUBLEVEL)
    state.disabled = button:CreateTexture(nil, BUTTON_DISABLED_LAYER, nil, BUTTON_DISABLED_SUBLEVEL)
    AnchorTexture(state.highlight, button, state.spec.inset)
    AnchorTexture(state.pushed, button, state.spec.inset)
    AnchorTexture(state.disabled, button, state.spec.inset)
    button:SetHighlightTexture(state.highlight, "BLEND")
    state.highlight:SetDrawLayer(BUTTON_HIGHLIGHT_LAYER, BUTTON_HIGHLIGHT_SUBLEVEL)
    state.pushed:SetDrawLayer(BUTTON_PUSHED_LAYER, BUTTON_PUSHED_SUBLEVEL)
    state.disabled:SetDrawLayer(BUTTON_DISABLED_LAYER, BUTTON_DISABLED_SUBLEVEL)
    button:SetPushedTexture(state.pushed)
    if button.SetDisabledTexture then
        button:SetDisabledTexture(state.disabled)
    end
end

local function SupportsButtonStateTextures(button)
    return button and type(button.CreateTexture) == "function"
        and type(button.SetHighlightTexture) == "function"
        and type(button.SetPushedTexture) == "function"
end

function Surface.EnsureOwnedButtonHighlightLayer(button)
    local state = NS.Registry.GetSurface(button)
    if not state or state.kind ~= "button" or not state.highlight then
        return false
    end
    state.highlight:SetDrawLayer(BUTTON_HIGHLIGHT_LAYER, BUTTON_HIGHLIGHT_SUBLEVEL)
    if state.pushed then
        state.pushed:SetDrawLayer(BUTTON_PUSHED_LAYER, BUTTON_PUSHED_SUBLEVEL)
    end
    if state.disabled then
        state.disabled:SetDrawLayer(BUTTON_DISABLED_LAYER, BUTTON_DISABLED_SUBLEVEL)
    end
    return true
end

-- ControlSkin supplies the final selection state before painting, instead of
-- repainting once for attach, again for active, and again for visibility.
-- Existing two-argument callers retain their current selection/sync behavior.
local function SetButtonPresentation(state, active, syncNativeSelected)
    if active ~= nil then state.active = active == true end
    if syncNativeSelected ~= nil then state.syncNativeSelected = syncNativeSelected == true end
end

function Surface.SkinOwnedButton(button, spec, active, syncNativeSelected)
    if not button then return nil, "invalid button" end
    if not CanControl(button, spec) then return nil, "protected button" end
    if not SupportsButtonStateTextures(button) then return nil, "invalid button" end
    if NS.IsCombatLocked() then
        local _, reason = NS.CombatGate.RunOrDefer("button:" .. tostring(button), function()
            Surface.SkinOwnedButton(button, spec, active, syncNativeSelected)
        end)
        return nil, reason
    end
    spec = spec or {}
    local existing = NS.Registry.GetSurface(button)
    if existing and existing.kind == "button" then
        if NS.BlizzardYellow then NS.BlizzardYellow.TrackFrame(button) end
        existing.spec = spec
        existing.visible = true
        SetButtonPresentation(existing, active, syncNativeSelected)
        NS.Registry.RegisterSurface(button, existing, SurfaceTokens(existing))
        if not NS.IsCombatLocked() then
            existing.refresh(existing)
        end
        return existing
    end

    local state
    local ran, reason = NS.CombatGate.RunOrDefer("button:" .. tostring(button), function()
        state = AttachNow(button, spec, true)
        AddButtonStateTextures(button, state)
        SetButtonPresentation(state, active, syncNativeSelected)
        NS.Registry.RegisterSurface(button, state, SurfaceTokens(state))
        state.refresh(state)
    end)
    return ran and state or nil, reason
end

function Surface.SetActive(target, active)
    local state = NS.Registry.GetSurface(target)
    if not state then
        return false
    end
    if NS.IsCombatLocked() then
        local _, reason = NS.CombatGate.RunOrDefer("surface-active:" .. tostring(target), function()
            Surface.SetActive(target, active)
        end)
        return false, reason
    end
    if not CanRefreshState(state) then
        return false, "protected"
    end
    state.active = active == true
    state.refresh(state)
    return true
end

function Surface.SetVisible(target, visible)
    local state = NS.Registry.GetSurface(target)
    if not state then
        return false
    end
    if NS.IsCombatLocked() then
        local _, reason = NS.CombatGate.RunOrDefer("surface-visible:" .. tostring(target), function()
            Surface.SetVisible(target, visible)
        end)
        return false, reason
    end
    if not CanRefreshState(state) then
        return false, "protected"
    end
    state.visible = visible == true
    state.refresh(state)
    return true
end

function Surface.SetNativeStateSync(target, enabled)
    local state = NS.Registry.GetSurface(target)
    if not state then
        return false
    end
    state.syncNativeSelected = enabled == true
    return true
end

function Surface.Refresh(target)
    local state = NS.Registry.GetSurface(target)
    if state and not NS.IsCombatLocked() then
        state.refresh(state)
        return true
    end
    return false
end
