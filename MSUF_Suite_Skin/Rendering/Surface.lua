local _, NS = ...

local forever = (rawget(NS, "Client") or {}).isForever == true
local Surface = {}
NS.Surface = Surface
local OnPainted = function() end
function Surface.SetMotionProvider(callback) OnPainted = callback end
local OnPalettePainted = function() end
function Surface.SetPaletteMotionProvider(callback) OnPalettePainted = callback end

local BlizzardYellow = NS.BlizzardYellow

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

-- The shell material counts as glass below this combined alpha.
local GLASS_COMPOSITING_ALPHA_CUTOFF = 0.94
-- Parent levels searched for an enclosing filled surface.
local MAX_ANCESTOR_DEPTH = 12

local structuralRoles = {
    shell = true,
    panel = true,
    card = true,
    popup = true,
}

local ConfigureShape = NS.Geometry.ConfigureShape

-- Settings can change every material. Only glass panels that inherit an
-- enclosing fill also depend on other surfaces or a native reparent.
local paintGeneration = 0

local function NextPaintGeneration()
    paintGeneration = paintGeneration + 1
end

-- Owned regions are created on the target, so the target must accept them.
local function CanPaint(target, spec)
    return NS.Safety.CanCreateRegions(target, spec and spec.allowImplicitProtected)
end

local function CanRefreshState(state)
    return state ~= nil and CanPaint(state.target, state.spec)
end

local function AnchorTexture(texture, target, inset)
    texture:ClearAllPoints()
    inset = tonumber(inset) or 0
    texture:SetPoint("TOPLEFT", target, "TOPLEFT", inset, -inset)
    texture:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", -inset, inset)
end

local function SetVertexColor(texture, colorKey, alphaScale)
    local r, g, b, a = NS.Theme.GetColor(colorKey)
    texture:SetVertexColor(r, g, b, a * (alphaScale or 1))
end

local function ResolveFill(material, spec, alphaScale)
    if spec.resolveFill then
        local r, g, b, a, tr, tg, tb, ta, gradient, direction = spec.resolveFill(spec, alphaScale)
        if r ~= nil then return r, g, b, a, tr, tg, tb, ta, gradient, direction end
    end
    local themeProvider = NS.Theme
    local getColor = themeProvider.GetColorTable
    local from, to = getColor(material.from), getColor(material.to)
    local opacity = themeProvider.GetMaterialOpacity(material)
        * (tonumber(spec.fillAlphaScale) or 1) * (alphaScale or 1)
    local theme = NS.DB.theme
    local strength = theme.gradientStrength or 1
    local opaque = spec.opaqueFill == true
    local r, g, b, a = from[1], from[2], from[3], from[4]
    return r, g, b, opaque and 1 or a * opacity,
        r + (to[1] - r) * strength, g + (to[2] - g) * strength, b + (to[3] - b) * strength,
        opaque and 1 or (a + (to[4] - a) * strength) * opacity,
        theme.gradient == true, theme.gradientDirection or "VERTICAL"
end

function Surface.PrepareFill(material, spec)
    return { ResolveFill(material, spec) }
end

local function ApplyFill(texture, material, state, alphaScale, prepared)
    local r, g, b, fromA, toR, toG, toB, toA, shaded, direction
    if prepared then
        r, g, b, fromA, toR, toG, toB, toA, shaded, direction = unpack(prepared)
        material = nil
    else
        local spec = state.spec
        r, g, b, fromA, toR, toG, toB, toA, shaded, direction = ResolveFill(material, spec, alphaScale)
        if spec.resolveFill then material = nil end
    end
    texture:SetVertexColor(1, 1, 1, 1)
    if shaded or state.gradientFrom then
        -- Replace the previous per-corner colors even when the shade is turned off.
        local reuse = NS.Theme.ReuseColor
        state.gradientFrom = reuse(state.gradientFrom, r, g, b, fromA, material, 1)
        local finish = state.gradientFrom
        if shaded then
            state.gradientTo = reuse(state.gradientTo, toR, toG, toB, toA, material, 2)
            finish = state.gradientTo
        end
        texture:SetGradient(direction, state.gradientFrom, finish)
    else
        texture:SetVertexColor(r, g, b, fromA)
    end
end

Surface.PaintFill = ApplyFill

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
    if state.preparedShell then state.preparedDepth = nil end
    if amount <= 0 or state.spec.fillVisible == false or state.spec.depth == false or suppressFill
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
    if state.preparedShell then
        state.preparedDepth = state.visible ~= false
        state.depth:Hide()
    elseif state.visible == false then
        state.depth:Hide()
    else
        state.depth:Show()
    end
end

function Surface.UsesGlassCompositing()
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

local function FlattensNestedFill(state)
    return state.spec.keepGlassFill == false
        or (state.spec.keepGlassFill == nil and RoleForState(state) == "panel")
end

local function HasFilledStructuralSurfaceAncestor(state)
    local current = state.target
    for _ = 1, MAX_ANCESTOR_DEPTH do
        -- A secret parent is not a public registry key.
        current = NS.Safety.Read(current, "GetParent")
        if not current then return false end
        local ancestor = NS.Registry.GetSurface(current)
        -- A flattened ancestor already has another filled ancestor. Thus the
        -- first visible structural fill establishes the same composited base.
        if ancestor and not ancestor.preparedShell and ancestor.visible ~= false and ancestor.spec.fillVisible ~= false and SupportsDepth(ancestor) then
            return true
        end
    end
    return false
end

local function IsPaintCurrent(state)
    return state.paintGeneration == paintGeneration
        and (state.filledGlassAncestor == nil or state.filledGlassAncestor == HasFilledStructuralSurfaceAncestor(state))
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
    if not tokens then
        tokens = {}
        state.tokens = tokens
    end
    for index = #tokens, 1, -1 do tokens[index] = nil end
    AddMaterialTokens(tokens, state.spec.role or "panel")
    AddToken(tokens, state.spec.appearanceToken)
    if state.spec.activeRole then
        AddMaterialTokens(tokens, state.spec.activeRole)
    end
    if state.spec.selectionEdge then AddToken(tokens, "title") end
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

-- Hover asset and alpha scale for the configured hover style.
local function HoverStyle(geometry, scale)
    local theme = NS.DB and NS.DB.theme or NS.Defaults.theme
    local hoverStyle = theme.hoverStyle or NS.Defaults.theme.hoverStyle
    local asset = geometry.fill
    scale = scale * (tonumber(theme.hoverIntensity) or 1)
    if hoverStyle == "outline" then
        asset = geometry.hoverEdge
    elseif hoverStyle == "softFill" then
        scale = scale * 0.28
    elseif hoverStyle == "off" then
        scale = 0
    end
    return asset, scale
end
Surface.HoverStyle = HoverStyle

local function RefreshButtonState(state, geometry)
    if state.kind ~= "button" then
        return
    end
    local visibleScale = state.visible == false and 0
        or NS.Theme.GetMaterialOpacity(controlOpacityMaterial)
    local hoverAsset, hoverScale = HoverStyle(geometry, visibleScale)
    -- Blizzard can rewrite textures installed in native button slots.
    ConfigureShape(state.highlight, hoverAsset, geometry, true)
    ConfigureShape(state.pushed, geometry.fill, geometry, true)
    ConfigureShape(state.disabled, geometry.fill, geometry, true)
    SetVertexColor(state.highlight, "hover", hoverScale)
    SetVertexColor(state.pushed, "pressed", visibleScale)
    SetVertexColor(state.disabled, "disabled", 0.45 * visibleScale)
end

local function RefreshInteractiveHover(state, geometry)
    local overlay = state.hoverOverlay
    if not overlay then return end
    if state.kind == "button" then
        overlay:Hide()
        return
    end
    local asset, scale = HoverStyle(geometry, NS.Theme.GetMaterialOpacity(controlOpacityMaterial))
    ConfigureShape(overlay, asset, geometry)
    SetVertexColor(overlay, "hover", scale)
    state.hoverEnabled = scale > 0
    if state.visible and state.hovered and state.hoverEnabled then
        overlay:Show()
    else
        overlay:Hide()
    end
end
Surface.RefreshInteractiveHover = RefreshInteractiveHover

-- Shared by every interactive surface; the state comes from the Registry.
local function OnHoverEnter(button)
    local state = NS.Registry.GetSurface(button)
    if not state or not state.hoverOverlay then return end
    state.hovered = true
    if state.visible and state.hoverEnabled and state.kind ~= "button" then
        state.hoverOverlay:Show()
    end
end

local function OnHoverLeave(button)
    local state = NS.Registry.GetSurface(button)
    if not state or not state.hoverOverlay then return end
    state.hovered = false
    state.hoverOverlay:Hide()
end

-- HookScript cannot be undone, so each button is hooked at most once.
local hoverHooked = setmetatable({}, { __mode = "k" })

local function EnsureInteractiveHover(target, state)
    if state.spec.interactive == false then return end
    local role = state.spec.role
    local interactive = state.spec.interactive or state.spec.listItem
        or role == "button" or role == "navigation"
    if not interactive or state.hoverOverlay or state.kind == "button"
        or type(target.HookScript) ~= "function"
        or NS.Safety.Read(target, "GetObjectType") ~= "Button"
        or not CanPaint(target) then
        return
    end
    local overlay = target:CreateTexture(nil, BUTTON_HIGHLIGHT_LAYER, nil, BUTTON_HIGHLIGHT_SUBLEVEL)
    AnchorTexture(overlay, target, state.spec.inset)
    overlay:Hide()
    state.hoverOverlay = overlay
    if not hoverHooked[target] then
        hoverHooked[target] = true
        target:HookScript("OnEnter", OnHoverEnter)
        target:HookScript("OnLeave", OnHoverLeave)
    end
end

-- Tabs mirror Blizzard's own selection. A false IsSelected() result leaves
-- the requested state in place; only the isSelected field can clear it.
local function ReadNativeSelected(target)
    local selected = target.isSelected
    if selected == nil then
        selected = NS.Safety.Read(target, "IsSelected") or nil
    end
    return selected
end

-- A selected tab uses its own contrast even with decorative borders off.
function Surface.GetEdgePaint(state, material)
    if state.active and state.spec.selectionEdge then return "title", 0.86 end
    return material.border, NS.Theme.GetBorderOpacity()
end

local function RefreshState(state, checked)
    -- Only SetActive/SetVisible pass their immediately preceding guard.
    -- Between that read and this call they change owned scalar state only;
    -- Attach and explicit refreshes always obtain a fresh protection answer.
    if not checked and not CanRefreshState(state) then
        return false
    end
    if state.syncNativeSelected then
        local selected = ReadNativeSelected(state.target)
        if selected ~= nil then
            state.active = selected == true
        end
    end
    local geometry = NS.Geometry.Resolve(state.spec, state.geometry)
    state.geometry = geometry
    local material = NS.Theme.GetMaterial(RoleForState(state))
    local hideIdleListFill = state.spec.listItem == true and state.active ~= true
    local filledGlassAncestor
    if FlattensNestedFill(state) and state.spec.listItem ~= true and Surface.UsesGlassCompositing() then
        filledGlassAncestor = HasFilledStructuralSurfaceAncestor(state)
    end
    local suppressNestedGlassFill = filledGlassAncestor
    local tintLayer = suppressNestedGlassFill and forever
        and state.spec.keepGlassFill ~= false and not state.spec.opaqueFill
    if tintLayer then suppressNestedGlassFill = false end
    ConfigureShape(state.fill, geometry.fill, geometry)
    ApplyFill(state.fill, material, state, tintLayer and 0.32 or nil)

    local edgeAsset = geometry.edge
    if state.active and (state.spec.activeEdge or state.spec.selectionEdge) then
        edgeAsset = geometry.hoverEdge
    end
    if not edgeAsset and state.spec.forceEdge then
        edgeAsset = geometry.hoverEdge
    end
    if edgeAsset then
        ConfigureShape(state.edge, edgeAsset, geometry)
        local color, opacity = Surface.GetEdgePaint(state, material)
        SetVertexColor(state.edge, color, opacity)
        if state.preparedShell then state.edge:Hide() else state.edge:Show() end
    else
        state.edge:Hide()
    end

    RefreshDepth(state, geometry, material, suppressNestedGlassFill or tintLayer)
    RefreshButtonState(state, geometry)
    RefreshInteractiveHover(state, geometry)
    if state.preparedShell then
        state.preparedEdge = state.visible ~= false and edgeAsset or nil
        state.preparedFill = state.visible ~= false and state.spec.fillVisible ~= false and not hideIdleListFill and not suppressNestedGlassFill
        state.fill:Hide()
    elseif state.visible == false then
        state.fill:Hide()
        state.edge:Hide()
        if state.depth then state.depth:Hide() end
    elseif state.spec.fillVisible == false or hideIdleListFill or suppressNestedGlassFill then
        -- Dense Blizzard lists should read as one continuous panel, not a
        -- stack of boxed cards. Keep the normal row transparent; button
        -- highlight/pushed textures and an explicit active state still supply
        -- interaction and selection feedback.
        state.fill:Hide()
    else
        state.fill:Show()
    end
    -- nil marks an independent surface; false must notice a structural parent
    -- added later. Publish this alongside the other successful paint stamp.
    state.filledGlassAncestor = filledGlassAncestor
    state.paintGeneration = paintGeneration
    OnPainted(state)
    OnPalettePainted(state, material)
    return true
end

-- deferRefresh: the caller (SkinOwnedButton) registers and paints the
-- surface itself once it is a button, so neither happens here.
local function AttachNow(target, spec, deferRefresh, prepareShell)
    local state = NS.Registry.GetSurface(target)
    -- An ownedArt control has no Blizzard-gold text (PublicAPI.lua).
    if not (spec or state and state.spec or {}).ownedArt then BlizzardYellow.TrackFrame(target) end
    if state then
        if state.preparedShell then
            state.preparedShell, state.preparedFill, state.preparedEdge, state.preparedDepth = nil, nil, nil, nil
        end
        state.spec = spec or state.spec
        if state.pendingVisible then
            NS.CombatGate.Cancel(state.pendingVisible)
            state.pendingVisible = nil
        end
        state.visible = true
        EnsureInteractiveHover(target, state)
        if state.inset ~= state.spec.inset then
            state.inset = state.spec.inset
            AnchorTexture(state.fill, target, state.inset)
            AnchorTexture(state.edge, target, state.inset)
        end
        if state.hoverOverlay then AnchorTexture(state.hoverOverlay, target, state.spec.inset) end
        if not deferRefresh then
            NS.Registry.RegisterSurface(target, state, SurfaceTokens(state))
            state.refresh(state)
        end
        return state
    end

    local fill = target:CreateTexture(nil, "BACKGROUND", nil, -7)
    local edge = target:CreateTexture(nil, "BORDER", nil, 7)
    AnchorTexture(fill, target, spec and spec.inset)
    AnchorTexture(edge, target, spec and spec.inset)

    state = {
        target = target,
        spec = spec or {},
        inset = spec and spec.inset,
        preparedShell = prepareShell,
        fill = fill,
        edge = edge,
        visible = true,
        refresh = RefreshState,
    }
    EnsureInteractiveHover(target, state)
    if not deferRefresh then
        NS.Registry.RegisterSurface(target, state, SurfaceTokens(state))
        state.refresh(state)
    end
    return state
end

-- A spec is caller-owned and read-only here: Surface keeps a reference and
-- reads it again on every refresh (theme and token changes). Callers may
-- share one spec between surfaces and rewrite it in place only when they
-- attach every surface that uses it again right afterwards (WindowActionSkin
-- and ControlSkin do); Surface never writes to a spec.
function Surface.Attach(target, spec)
    if not target then
        return nil, "invalid target"
    end
    if not CanPaint(target, spec) then
        return nil, "protected target"
    end
    if type(target.CreateTexture) ~= "function" then return nil, "invalid target" end
    -- CanPaint rejects protected targets in combat. Unprotected cosmetics
    -- must also paint on a window's first combat opening.
    return AttachNow(target, spec)
end

-- Attach for hooks that run per row initialization or per native update
-- (scrolling lists, stat and slot updates): a surface that shows this exact
-- spec, visible and painted for the current generation, is left alone.
-- Callers that rewrite a spec table in place call Attach instead.
function Surface.Ensure(target, spec, prepareShell)
    local state = target and NS.Registry.GetSurface(target)
    if prepareShell then
        -- Never hide an already-adopted surface. Only this root's first cold
        -- material is prepared, and a refresh cannot show its layers yet.
        if state then return state.preparedShell and state.spec == spec and state or nil end
        if not target or NS.IsCombatLocked() or not CanPaint(target, spec) or type(target.CreateTexture) ~= "function" then return end
        return AttachNow(target, spec, false, true)
    end
    if state and state.spec == spec and state.visible ~= false and not state.syncNativeSelected
        and IsPaintCurrent(state) and (not NS.IsCombatLocked() or CanRefreshState(state)) then
        if state.preparedShell then
            if not CanPaint(target, spec) then return end
            state.preparedShell = nil
            if state.preparedFill then state.fill:Show() end
            if state.preparedEdge then state.edge:Show() end
            if state.preparedDepth then state.depth:Show() end
            state.preparedFill, state.preparedEdge, state.preparedDepth = nil, nil, nil
        end
        return state
    end
    return Surface.Attach(target, spec)
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
    return type(button.CreateTexture) == "function"
        and type(button.SetHighlightTexture) == "function"
        and type(button.SetPushedTexture) == "function"
end

local function RepairLayer(texture, layer, sublevel)
    if not texture then return end
    local current, order = NS.Safety.Call(texture, "GetDrawLayer")
    if NS.Safety.Public(current) and NS.Safety.Public(order) and current == layer and order == sublevel then return end
    texture:SetDrawLayer(layer, sublevel)
end

-- Rebinding on a native tab can change the layer of just one owned texture.
function Surface.RepairOwnedTabLayers(state)
    RepairLayer(state.highlight, BUTTON_HIGHLIGHT_LAYER, BUTTON_HIGHLIGHT_SUBLEVEL)
    RepairLayer(state.pushed, BUTTON_PUSHED_LAYER, BUTTON_PUSHED_SUBLEVEL)
    RepairLayer(state.disabled, BUTTON_DISABLED_LAYER, BUTTON_DISABLED_SUBLEVEL)
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
    if active ~= nil then
        if state.pendingActive then
            NS.CombatGate.Cancel(state.pendingActive)
            state.pendingActive = nil
        end
        state.active = active == true
    end
    if syncNativeSelected ~= nil then state.syncNativeSelected = syncNativeSelected == true end
end

function Surface.SkinOwnedButton(button, spec, active, syncNativeSelected, nativeSelection)
    if not button then return nil, "invalid button" end
    if not CanPaint(button, spec) then return nil, "protected button" end
    if not SupportsButtonStateTextures(button) then return nil, "invalid button" end
    spec = spec or {}
    local state = NS.Registry.GetSurface(button)
    if state and state.kind == "button" then
        if not spec.ownedArt then BlizzardYellow.TrackFrame(button) end
        -- TabSystemMixin broadcasts selection to every sibling. Only the marked
        -- PlayerSpells tabs reuse material here; ControlSkin still repairs live art.
        if nativeSelection and state.spec == spec and state.active == active and state.visible
            and IsPaintCurrent(state) and state.syncNativeSelected == syncNativeSelected
            and not state.pendingVisible and not state.pendingActive then
            local selected = button.isSelected
            if NS.Safety.Public(selected) and selected == active then return state end
        end
        state.spec = spec
        if state.pendingVisible then
            NS.CombatGate.Cancel(state.pendingVisible)
            state.pendingVisible = nil
        end
        state.visible = true
    else
        state = AttachNow(button, spec, true)
        AddButtonStateTextures(button, state)
    end
    SetButtonPresentation(state, active, syncNativeSelected)
    NS.Registry.RegisterSurface(button, state, SurfaceTokens(state))
    state.refresh(state)
    return state
end

-- repaint: paint even a surface that already shows this state (a public
-- selection change repaints once, as its full reconcile did).
function Surface.SetActive(target, active, repaint)
    local state = NS.Registry.GetSurface(target)
    if not state then
        return false
    end
    if not CanPaint(state.target, state.spec) then
        if not NS.IsCombatLocked() then return false, "protected" end
        local key = "surface-active:" .. tostring(target)
        state.pendingActive = key
        local _, reason = NS.CombatGate.RunOrDefer(key, function()
            state.pendingActive = nil
            Surface.SetActive(target, active, repaint)
        end)
        return false, reason
    end
    if state.pendingActive then
        NS.CombatGate.Cancel(state.pendingActive)
        state.pendingActive = nil
    end
    active = active == true
    -- Selection hooks run per row initialization and per native refresh: a
    -- surface that shows this state, painted for the current generation,
    -- is left alone (Surface.Ensure's rule).
    if not repaint and state.active == active and IsPaintCurrent(state)
        and state.visible ~= false and not state.syncNativeSelected then
        return true
    end
    state.active = active
    state.refresh(state, true)
    return true
end

function Surface.SetVisible(target, visible)
    local state = NS.Registry.GetSurface(target)
    if not state then
        return false
    end
    if not CanPaint(state.target, state.spec) then
        if not NS.IsCombatLocked() then return false, "protected" end
        local key = "surface-visible:" .. tostring(target)
        state.pendingVisible = key
        local _, reason = NS.CombatGate.RunOrDefer(key, function()
            state.pendingVisible = nil
            Surface.SetVisible(target, visible)
        end)
        return false, reason
    end
    if state.pendingVisible then
        NS.CombatGate.Cancel(state.pendingVisible)
        state.pendingVisible = nil
    end
    -- Repeated public reconciliation often requests the visibility that the
    -- preceding paint already established. Explicit Refresh/Attach still
    -- repair native resets and in-place spec changes.
    if state.visible == (visible == true) and IsPaintCurrent(state)
        and not state.syncNativeSelected then return true end
    state.visible = visible == true
    state.refresh(state, true)
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
    if state and (not NS.IsCombatLocked() or CanRefreshState(state)) then
        state.refresh(state)
        return true
    end
    return false
end

-- A caller's color for the edge of target's surface (the Suite colors a
-- tooltip border by item quality or class), in place of the theme's border
-- until the next repaint. Without a color the theme's border is back. False
-- when target has no visible edge. Only the owned edge texture changes, so
-- combat does not matter.
function Surface.TintEdge(target, r, g, b)
    local public = NS.Safety.Public
    if not (public(target) and public(r) and public(g) and public(b)) then return false end
    local state = NS.Registry.GetSurface(target)
    if not state then
        local tooltips = NS.SuiteCore().Tooltips
        return tooltips ~= nil and tooltips.TooltipChrome.TintEdge(target, r, g, b)
    end
    if not state.edge:IsShown() then return false end
    if r == nil then
        local material = NS.Theme.GetMaterial(RoleForState(state))
        SetVertexColor(state.edge, material.border, NS.Theme.GetBorderOpacity())
    else
        local _, _, _, alpha = state.edge:GetVertexColor()
        state.edge:SetVertexColor(r, g, b, alpha)
    end
    return true
end

-- Every settings notification can change how a surface paints.
NS.Registry.AddListener(Surface, NextPaintGeneration)
