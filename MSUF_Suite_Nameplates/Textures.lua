local _, private = ...
local Selection, Absorbs = private.Selection, private.Absorbs
local NS, Slant = private.NS, private.SlantedHealth
local Style = NS.NameplateStyle
local Textures = {}
private.Textures = Textures

local healthFill, healthBack, castFill, castBack, focusFill, baseTextures, focusHealth, findFocus
local darkCastBackground, sharedCastStyle
local nativeEnemyOutline, nativeFriendlyOutline
local scopedHealth
local healthStates = setmetatable({}, { __mode = "k" })
local castStates = setmetatable({}, { __mode = "k" })
-- Release plates untextured and reuse their empty state by frame or castbar.
-- The replay previously allocated 320 B of state tables per added plate.
local spareHealth = setmetatable({}, { __mode = "k" })
local spareCast = setmetatable({}, { __mode = "k" })
local castHooks = setmetatable({}, { __mode = "k" })
local backgroundHooks = setmetatable({}, { __mode = "k" })
local painted = setmetatable({}, { __mode = "k" })
local deferred = setmetatable({}, { __mode = "k" })
local generation, restoreFrame = 0, nil
local Defer
local listening = false
local textureKeys = {}
local visuals
function Textures.Bind(plateVisuals) visuals = plateVisuals end
local function SettingsChanged(previous, current)
    if not previous or not current then return previous ~= current end
    for key, value in pairs(current) do
        if value ~= rawget(previous, key) then return true end
    end
    for key in pairs(previous) do
        if rawget(current, key) == nil then return true end
    end
    return false
end

function Textures.SharedCastbar(config, previous)
    local current = private.CastSettings.Read(config)
    if SettingsChanged(previous, current) then return current end
    return previous
end

local function RefreshNameplates()
    private.Suite.Apply("nameplates")
    if NS.Options then NS.Dispatch(NS.Options.RefreshAll) end
end

local function ApplySharedBars(module)
    local config = module.config
    if not module.active then return end
    local names = private.FriendlyNames
    if names and names.friendlyPaletteEnabled then names.RefreshFriendlyPalette(true) end
    if config.look == 2 then return end
    if Absorbs and Absorbs.SharedChanged(config) then return RefreshNameplates() end
    if config.barsOverride then return end
    local previous = module.barSettings or config
    local current = Style.BarSettings(config, Style.SharedBars())
    local changed
    if previous == config or current == config then
        changed = previous ~= current
    else
        changed = SettingsChanged(previous, current)
    end
    if changed or module:AggroHighlightSettingChanged() then RefreshNameplates() end
end
local function ApplySharedCastbar(module)
    if module.active and Textures.SharedCastbar(module.config, module.castbarStyle) ~= module.castbarStyle then
        RefreshNameplates()
    end
end

function Textures.ObserveHostStyles(module)
    local bridge = NS.HostBridge
    if not bridge then return end
    if bridge.ObserveSharedNameplateBars then
        module.barsJob = module.context:Coalesce(0, ApplySharedBars)
        bridge.ObserveSharedNameplateBars(function()
            if module.active and (private.FriendlyNames and private.FriendlyNames.friendlyPaletteEnabled
                or module.config.look ~= 2 and (not module.config.barsOverride or Absorbs and Absorbs.shared)) then
                module.barsJob:Request()
            end
        end)
    end
    if bridge.ObserveSharedCastbarStyle then
        module.castbarJob = module.context:Coalesce(0, ApplySharedCastbar)
        bridge.ObserveSharedCastbarStyle(function()
            if module.active and module.config.look ~= 2 then module.castbarJob:Request() end
        end)
    end
end
local function TintFocusVisual(health, path)
    local visual = visuals and private.Suite.Public(health) and visuals[health]
    if visual then visual.focusFill = path end
end

local CLASSIC_HEALTH = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
local CLASSIC_BACKGROUND = "Interface\\Tooltips\\Nameplate-Border"
local CAST_BACKGROUND = "ui-castingbar-background"
local CLASSIC_CAST_FILL = "Interface\\TargetingFrame\\UI-StatusBar"
local castColors = {
    standard = { 1, .84, .2 },
    uninterruptable = { .62, .62, .62 },
    interrupted = { 1, .25, .25 },
}
local castColorOverride, lockedColorOverride
local castColorRevision = 0
local castColorObject, lockedColorObject
-- Reuse the native regions. Only layout resets and cast fill changes need
-- a write during play. Progress events and OnUpdate stay with Blizzard.
local function Accessible(region)
    if not region.CanBeAccessedInContext then return true end
    local allowed = region:CanBeAccessedInContext()
    return NS.Public(allowed) and allowed == true
end

local function Writable(region)
    return NS.Public(region) and region and not NS.Safety.IsForbidden(region) and Accessible(region)
end

local function SetAsset(region, path, keepSlice)
    local ok = region:SetTexture(path)
    if not NS.Public(ok) or ok == false then return false end
    if not keepSlice then region:ClearTextureSlice() end
    return true
end

local function PaintHealthBackground(back, state, path, classic, reset)
    if not Writable(back) then return false end
    if path then
        if not SetAsset(back, path) then return false end
        back:SetTexCoord(0, 1, 0, 1)
        back:SetDrawLayer("BACKGROUND")
        back:SetVertexColor(.16, .16, .16)
    elseif classic then
        if not SetAsset(back, CLASSIC_BACKGROUND, true) then return false end
        back:SetTexCoord(0, 1, .5, 1)
        back:SetTextureSliceMargins(0, 0, 0, 0)
        back:SetDrawLayer("ARTWORK", 1)
        back:SetVertexColor(1, 1, 1)
    else
        back:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
        back:SetTexCoord(0, 1, 0, 1)
        back:SetDrawLayer("BACKGROUND")
        back:SetVertexColor(1, 1, 1)
    end
    local fit = path ~= nil and not classic
    if fit ~= (state.backFitted == true) or fit and reset then NS.NameplateStyle.FitModernHealthBackground(back, fit) end
    state.back, state.backFitted = path, fit
    return true
end

local function ApplyHealth(uf, health, reset, healthFill, healthBack)
    local state = healthStates[uf]
    if not state and not (healthFill or healthBack) then return true end
    if state and not reset and state.fill == healthFill and state.back == healthBack then return true end
    if not NS.Public(health) then return false end
    if not health then return true end
    if not Writable(health) then return false end
    local classic = NamePlateSetupOptions.useClassicHealthBar
    if not NS.Public(classic) then return false end
    if not state then
        state = spareHealth[uf]
        if state then spareHealth[uf] = nil else state = {} end
        healthStates[uf] = state
    end
    local complete = true
    local fill, back = health.barTexture, health.bgTexture
    if not NS.Public(fill) or not NS.Public(back) then return false end
    if fill and (state.fill ~= healthFill or reset and healthFill) then
        if not Writable(fill) then
            complete = false
        elseif healthFill then
            complete = SetAsset(fill, healthFill)
            if complete then state.fill = healthFill end
        elseif classic then
            complete = SetAsset(fill, CLASSIC_HEALTH, true)
            if complete then state.fill = nil end
        else
            fill:SetAtlas("UI-HUD-CoolDownManager-Bar")
            state.fill = nil
        end
    end
    if back and (state.back ~= healthBack or reset and healthBack) then
        if PaintHealthBackground(back, state, healthBack, classic, reset) then
            if not healthBack then Selection.RepaintBackground(health) end
        else
            complete = false
        end
    end
    if not (state.fill or state.back) then
        healthStates[uf] = nil
        state.backFitted = nil
        spareHealth[uf] = state
    end
    return complete
end

local function ApplyCastBarColor(cast, state)
    local kind = cast.barType
    local known = NS.Public(kind)
    local value, color = state.notInterruptible, nil
    if state.interrupted or known and kind == "interrupted" then
        color = castColors.interrupted
    elseif not state.full or NS.Public(value) and value == nil then
        local unit = cast.unit
        if known then
            value = kind == "uninterruptable"
        elseif not state.full and NS.Public(unit) and unit then
            local raw = select(8, UnitCastingInfo(unit))
            if NS.Public(raw) and raw == nil then raw = select(7, UnitChannelInfo(unit)) end
            if not NS.Public(raw) or raw ~= nil then value = raw end
        end
        state.notInterruptible = value
    end
    if not color and NS.Public(value) then
        color = value == true and castColors.uninterruptable or castColors.standard
    end
    -- Blizzard's progress and fade both draw the fill through the status bar.
    -- Set its color even when the new texture region cannot be accessed yet.
    if color then
        cast:SetStatusBarColor(color[1], color[2], color[3], 1)
    else
        local normal, locked = castColors.standard, castColors.uninterruptable
        local Evaluate = C_CurveUtil.EvaluateColorValueFromBoolean
        cast:SetStatusBarColor(Evaluate(value, locked[1], normal[1]), Evaluate(value, locked[2], normal[2]),
            Evaluate(value, locked[3], normal[3]), 1)
    end
    return color, value
end

local function RecolorCastFill(cast, state)
    local color, value = ApplyCastBarColor(cast, state)
    local fill = cast:GetStatusBarTexture()
    if not Writable(fill) then return false end
    if not state.colorRevision then fill:ClearTextureSlice() end
    if color then
        fill:SetVertexColor(color[1], color[2], color[3], 1)
    else
        local normal, locked = Textures.CastFillColorObjects()
        fill:SetVertexColorFromBoolean(value, locked, normal)
    end
    state.colorRevision = castColorRevision
    return true
end

local function RefreshCastShape(cast, state)
    return not state.slanted or not private.CastOutline or private.CastOutline.RefreshShape(cast)
end

local function PaintCastFill(cast, state)
    local kind = cast.barType
    if state.usesColorFill or NS.Public(kind) and kind == "empowered" then return RefreshCastShape(cast, state) end
    -- The public asset can be set on the bar without accessing its old texture.
    local ok = cast:SetStatusBarTexture(castFill)
    if not NS.Public(ok) or ok == false then
        ApplyCastBarColor(cast, state)
        state.colorOnly = true
        return false
    end
    state.fill = castFill
    state.colorOnly = nil
    state.colorRevision = nil
    return RecolorCastFill(cast, state) and RefreshCastShape(cast, state)
end

local function AfterCastFill(cast, full)
    local state = castStates[cast]
    if not state then return end
    state.fill, state.colorOnly = nil, nil
    state.full = not NS.Public(full) or full == true
    if not state.full then state.usesColorFill, state.notInterruptible, state.interrupted = nil, nil, nil end
    local uf = state.owner
    if not painted[uf] then return end
    if state.enabled and castFill then
        if not Writable(cast) or not PaintCastFill(cast, state) then Defer(uf, false) end
    elseif not RefreshCastShape(cast, state) then
        Defer(uf, false)
    end
end

local function AfterCastColorFill(cast)
    local state = castStates[cast]
    if not state then return end
    state.fill, state.colorOnly, state.usesColorFill = nil, nil, true
    if painted[state.owner] and not RefreshCastShape(cast, state) then Defer(state.owner, false) end
end

local function AfterCastEvent(cast, event)
    local state = castStates[cast]
    if not state or not state.enabled or not castFill or not painted[state.owner] then return end
    if not NS.Public(event) or (event ~= "UNIT_SPELLCAST_START" and event ~= "UNIT_SPELLCAST_CHANNEL_START") then return end
    -- Reassert the asset after Blizzard's event handler finishes the cast setup.
    if not Writable(cast) then return end
    local shown = cast:IsShown()
    if not NS.Public(shown) or not shown then return end
    if not PaintCastFill(cast, state) then Defer(state.owner, false) end
end

local function AfterInterrupt(cast)
    local state = castStates[cast]
    if not state or not state.enabled then return end
    state.interrupted = true
    if not (state.fill or state.colorOnly) then return end
    if not Writable(cast) then
        Defer(state.owner, false)
        return
    end
    if state.colorOnly then
        ApplyCastBarColor(cast, state)
    elseif not RecolorCastFill(cast, state) then
        Defer(state.owner, false)
    end
end

local function AfterFinish(cast)
    local state = castStates[cast]
    if not state or not state.enabled or not state.full or not castFill or not painted[state.owner] then return end
    -- Keep the selected texture and cast color after the native finish setup.
    if not Writable(cast) or not PaintCastFill(cast, state) then Defer(state.owner, false) end
end

local function RestoreCastFill(cast, state)
    local classic, kind = cast.classicStyleCastBar, cast.barType
    if not NS.Public(classic) then return false end
    if state.colorOnly and not state.fill and not classic then
        -- The native atlas never changed, and Modern uses white for every type.
        cast:SetStatusBarColor(1, 1, 1, 1)
        state.colorOnly = nil
        return true
    end
    -- The next native update restores restricted cast art using its original type.
    if not NS.Public(kind) then
        state.fill, state.colorOnly = nil, nil
        return true
    end
    local info = CastingBarTypeInfo[kind or "standard"]
    local asset = classic and CLASSIC_CAST_FILL or info and (state.full and info.full or info.filling)
    if not asset or asset == "" then
        state.fill, state.colorOnly = nil, nil
        return true
    end
    local fill
    if state.fill then
        if not Writable(cast:GetStatusBarTexture()) then return false end
        local ok = cast:SetStatusBarTexture(asset)
        if not NS.Public(ok) or ok == false then return false end
        fill = cast:GetStatusBarTexture()
        if not Writable(fill) then return false end
    end
    local color = classic and info and (state.full and info.classicFullColor or info.classicFillColor)
    local r, g, b = 1, 1, 1
    if color then r, g, b = color:GetRGB() end
    if color or not classic then
        cast:SetStatusBarColor(r, g, b, 1)
        if fill then fill:SetVertexColor(r, g, b, 1) end
    end
    state.fill, state.colorOnly = nil, nil
    return true
end

local function ApplyCastBackground(cast, state)
    local back = cast.Background
    if not NS.Public(back) then return false end
    if not back then
        state.backApplied, state.backPending = nil, nil
        return true
    end
    if not Writable(back) then return false end
    local path, jundies, style = state.back, state.darkBack, state.backStyle
    if path then
        if not SetAsset(back, path) then return false end
        back:SetTexCoord(0, 1, 0, 1)
        if style then
            back:SetVertexColor(style.backgroundR, style.backgroundG, style.backgroundB, style.backgroundA)
        elseif jundies then
            back:SetVertexColor(0, 0, 0, .5)
        else
            back:SetVertexColor(.16, .16, .16, 1)
        end
    elseif style then
        back:SetVertexColor(1, 1, 1, 1)
        back:SetColorTexture(style.backgroundR, style.backgroundG, style.backgroundB, style.backgroundA)
    else
        local classic = cast.classicStyleCastBar
        if not NS.Public(classic) then return false end
        back:SetVertexColor(1, 1, 1, 1)
        if classic then
            back:SetColorTexture(0, 0, 0, .5)
        else
            back:SetAtlas(CAST_BACKGROUND)
        end
    end
    state.backApplied, state.backPending = (path or style) and true or nil, nil
    return true
end

local function OnCastBackgroundShown(cast)
    local state = NS.Public(cast) and castStates[cast]
    local uf = state and state.owner
    if not uf or not state.backPending or not painted[uf] then return end
    if Writable(cast) then
        local visible = cast:IsVisible()
        if NS.Public(visible) and visible == false then return end
        if ApplyCastBackground(cast, state) then return end
    end
    if painted[uf] and state.owner == uf then
        painted[uf] = 0
        Defer(uf, false)
    end
end

local function UpdateCastBackground(cast, state, path, style, reset)
    local dark = path and darkCastBackground or nil
    local changed = state.back ~= path or state.darkBack ~= dark or state.backStyle ~= style
    state.back, state.darkBack, state.backStyle = path, dark, style
    if not (path or style) then
        state.backPending = nil
        return not state.backApplied or ApplyCastBackground(cast, state)
    end
    if not (changed or reset or state.backPending) then return true end
    state.backPending = true
    local visible = cast:IsVisible()
    if not NS.Public(visible) or visible then return ApplyCastBackground(cast, state) end
    local protected = cast:IsProtected()
    if not NS.Public(protected) or protected then return ApplyCastBackground(cast, state) end
    if not backgroundHooks[cast] then
        cast:HookScript("OnShow", OnCastBackgroundShown)
        backgroundHooks[cast] = true
    end
    return true
end

local function ApplyCastDetails(component, cast, style, reset, deferSpark)
    if not component then return true end
    if style then return component.Apply(cast, style, reset, deferSpark) end
    return component.Restore(cast)
end

local function ApplyCast(uf, cast, reset, useFill, castBack, style, deferSpark)
    if not NS.Public(cast) then return false end
    local state = castStates[cast]
    if not cast or not state and not (useFill or castBack or style) then return true end
    local slanted = style and style.slanted == true
    if state then state.enabled, state.slanted = useFill ~= nil, slanted end
    if not Writable(cast) then return false end
    if not state then
        state = spareCast[cast]
        if state then spareCast[cast] = nil else state = {} end
        castStates[cast] = state
    end
    state.enabled, state.slanted = useFill ~= nil, slanted
    if (useFill or slanted) and not castHooks[cast] then
        hooksecurefunc(cast, "UpdateBarFillTexture", AfterCastFill)
        hooksecurefunc(cast, "SetColorFill", AfterCastColorFill)
        hooksecurefunc(cast, "PlayInterruptAnims", AfterInterrupt)
        hooksecurefunc(cast, "PlayFinishAnim", AfterFinish)
        cast:HookScript("OnEvent", AfterCastEvent)
        castHooks[cast] = true
    end
    state.owner = uf
    local complete = true
    if castHooks[cast] then
        if useFill and (state.colorOnly or state.fill ~= useFill or state.colorRevision ~= castColorRevision) then
            local shown = cast:IsShown()
            if NS.Public(shown) and shown then
                if not state.colorOnly and state.fill == useFill then
                    complete = RecolorCastFill(cast, state)
                else
                    complete = PaintCastFill(cast, state)
                end
            end
        elseif not useFill and (state.fill or state.colorOnly) then
            complete = RestoreCastFill(cast, state)
        end
    end
    local backgroundStyle = style and style.backgroundR ~= nil and style or nil
    if not UpdateCastBackground(cast, state, castBack, backgroundStyle, reset) then complete = false end
    if style or state.style then
        if not ApplyCastDetails(private.CastAppearance, cast, style, reset, deferSpark and not state.style) then complete = false end
        if not ApplyCastDetails(private.CastTextStyle, cast, style, reset) then complete = false end
        if not ApplyCastDetails(private.CastGlowStyle, cast, style, reset) then complete = false end
        state.style = style or not complete and state.style or nil
    end
    if not (useFill or state.fill or state.colorOnly or state.back or state.backStyle or state.backApplied or state.style) then
        castStates[cast] = nil
        -- Nothing of the finished cycle (owner, cast kind, interrupt) may reach the next plate.
        for key in next, state do state[key] = nil end
        spareCast[cast] = state
    end
    return complete
end

local function Resolve(previousKey, previousPath, key)
    if not key or key == "" then return end
    if key == previousKey and previousPath then return previousPath end
    return NS.ResolveTexture(key)
end

local function SetCastRGB(color, r, g, b)
    if color[1] == r and color[2] == g and color[3] == b then return false end
    color[1], color[2], color[3] = r, g, b
    return true
end

local function ReadCastColors(style)
    local r, g, b, nr, ng, nb = NS.NameplateStyle.CastFillColors(castColorOverride, lockedColorOverride)
    local normal = SetCastRGB(castColors.standard, r, g, b)
    local locked = SetCastRGB(castColors.uninterruptable, nr, ng, nb)
    local interrupt = SetCastRGB(castColors.interrupted, style and style.interruptR or 1,
        style and style.interruptG or .25, style and style.interruptB or .25)
    if not normal and not locked and not interrupt then return false end
    castColorRevision = castColorRevision + 1
    castColorObject, lockedColorObject = nil, nil
    generation = generation + 1
    return true
end

function Textures.CastFillColorObjects()
    if not castColorObject then
        castColorObject = CreateColor(unpack(castColors.standard))
        lockedColorObject = CreateColor(unpack(castColors.uninterruptable))
    end
    return castColorObject, lockedColorObject
end

function Textures.RefreshCastColors()
    if not castFill or not ReadCastColors(sharedCastStyle) then return end
    for uf in pairs(painted) do Textures.Apply(uf) end
end

function Textures.Configure(config, style, scopedBars)
    local hadTextures, absorbChanged = Textures.inUse, Absorbs and Absorbs.Configure(config)
    local shapeChanged = Slant and Slant.Configure(config)
    local fill, back, cast, background = config.nativeHealthFillTexture, config.nativeHealthBackgroundTexture,
        config.nativeCastFillTexture, config.nativeCastBackgroundTexture
    local hpFill = Resolve(textureKeys[1], healthFill, fill)
    local hpBack = Resolve(textureKeys[2], healthBack, back)
    local spellFill = Resolve(textureKeys[3], castFill, cast)
    local spellBack = Resolve(textureKeys[4], castBack, background)
    if style then
        spellFill = spellFill or style.fill
        spellBack = spellBack or style.background
    end
    castColorOverride, lockedColorOverride = config.nativeCastFillColor, config.nativeCastLockedColor
    if spellFill then ReadCastColors(style) end
    local dark = config.look == 1 and background == "Solid" or nil
    local focusKey = config.nativeFocusHealthFillTexture
    local focus = Resolve(textureKeys[5], focusFill, focusKey)
    textureKeys[1], textureKeys[2], textureKeys[3], textureKeys[4] = fill, back, cast, background
    textureKeys[5] = focusKey
    local enemyOutline = NS.NameplateStyle.UsesNativeOutline(config, "enemy")
    local friendlyOutline = NS.NameplateStyle.UsesNativeOutline(config, "friendly")
    local scoped, scopedChanged
    for scope, bars in pairs(scopedBars or {}) do
        local side = (scope == "enemy" or scope == "neutral") and "enemy" or "friendly"
        local previous = scopedHealth and scopedHealth[scope]
        local fillKey, backKey = bars.nativeHealthFillTexture, bars.nativeHealthBackgroundTexture
        local fill = Resolve(previous and previous.fillKey, previous and previous.fill, fillKey)
        local back = not Style.UsesNativeOutline(bars, side)
            and Resolve(previous and previous.backKey, previous and previous.back, backKey) or nil
        local native = (side == "enemy" and enemyOutline) or (side == "friendly" and friendlyOutline)
        if fill ~= hpFill or back ~= (not native and hpBack or nil) then
            scoped = scoped or {}
            if previous and previous.fillKey == fillKey and previous.backKey == backKey
                and previous.fill == fill and previous.back == back then
                scoped[scope] = previous
            else
                scoped[scope] = { fillKey = fillKey, backKey = backKey, fill = fill, back = back }
                scopedChanged = true
            end
        end
    end
    for scope in pairs(scopedHealth or {}) do
        if not scoped or not scoped[scope] then scopedChanged = true break end
    end
    if hpFill ~= healthFill or hpBack ~= healthBack or spellFill ~= castFill or spellBack ~= castBack or focus ~= focusFill
        or enemyOutline ~= nativeEnemyOutline or friendlyOutline ~= nativeFriendlyOutline or dark ~= darkCastBackground
        or sharedCastStyle ~= style or scopedChanged or absorbChanged or shapeChanged then
        generation = generation + 1
    end
    nativeEnemyOutline, nativeFriendlyOutline, scopedHealth = enemyOutline, friendlyOutline, scoped
    Textures.scopedHealth = scoped
    healthFill, healthBack, castFill, castBack = hpFill, hpBack, spellFill, spellBack
    darkCastBackground, sharedCastStyle = dark, style
    focusFill = focus
    baseTextures = healthFill or healthBack or castFill or castBack or sharedCastStyle or scopedHealth
        or Absorbs and Absorbs.inUse or Slant and Slant.enabled
    Textures.inUse, Textures.focusFill = baseTextures or focusFill, focusFill
    Textures.healthFill, Textures.healthBack, Textures.castFill = healthFill, healthBack, castFill
    return hadTextures and not Textures.inUse
end
function Textures.HealthBackground(prefix, scope)
    local scoped = scopedHealth and scopedHealth[scope]
    if scoped then return scoped.back end
    if prefix == "enemy" and nativeEnemyOutline or prefix == "friendly" and nativeFriendlyOutline then return nil end
    return healthBack
end

function Textures.HasHealthBackground(uf)
    local state = uf and healthStates[uf]
    return state and state.back ~= nil
end

function Textures.HealthFill(uf)
    if uf == Textures.focusUF and focusFill then return focusFill end
    local scoped = scopedHealth and scopedHealth[private.AppearanceScope(uf)]
    if scoped then return scoped.fill end
    return healthFill
end

function Textures.SetFocus(uf)
    local previous = Textures.focusUF
    if previous == uf then
        TintFocusVisual(focusHealth, focusFill)
        return previous
    end
    TintFocusVisual(focusHealth, nil)
    Textures.focusUF = uf
    focusHealth = uf and uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    TintFocusVisual(focusHealth, focusFill)
    -- A focus change invalidates only these two plates. Keep their other
    -- texture state so applying the new fill cannot rewrite the castbar.
    if previous and painted[previous] then painted[previous] = -1 end
    if uf and painted[uf] then painted[uf] = -1 end
    return previous
end

local function FindFocus()
    local plate = C_NamePlate.GetNamePlateForUnit("focus")
    local current = plate and not NS.Safety.IsForbidden(plate) and plate.UnitFrame
    if current and NS.Safety.IsForbidden(current) then current = nil end
    Textures.SetFocus(current or nil)
    local exists = not current and UnitExists("focus")
    findFocus = NS.Public(exists) and exists == true
end

function Textures.PrepareFocus()
    if focusFill then FindFocus() else Textures.SetFocus(nil) end
end

local function RefreshFocus(module, uf, setRole, paint)
    if not uf or NS.Safety.IsForbidden(uf) then return end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local unit = health and module.units[health]
    if unit then
        setRole(uf, unit)
        paint(uf)
    elseif focusFill and (not private.SkinAllowed or private.SkinAllowed(uf)) then
        Textures.Apply(uf)
    end
end

function Textures.RefreshFocus(module, current, setRole, paint)
    local previous = module.focusUF
    local previousTexture = focusFill and Textures.SetFocus(current)
    local exists = focusFill and not current and UnitExists("focus")
    findFocus = NS.Public(exists) and exists == true
    RefreshFocus(module, previous, setRole, paint)
    if current ~= previous then RefreshFocus(module, current, setRole, paint) end
    if previousTexture and previousTexture ~= previous and previousTexture ~= current then
        RefreshFocus(module, previousTexture, setRole, paint)
    end
end

function Textures.Paint(uf, paint)
    local finishSpark = Textures.Apply(uf, nil, true)
    paint(uf)
    if finishSpark then Textures.OnLayout(uf, true) end
    if uf ~= Textures.focusUF then return end
    -- The initial presentation pass may have allocated the role texture.
    -- Update it once when the focus nameplate first gets a visual.
    local visual = NS.Public(focusHealth) and visuals[focusHealth]
    if visual and visual.focusFill ~= focusFill then
        visual.focusFill = focusFill
        if visual.fillColor then Textures.TintRole(visual, visual.fillColor, focusFill) end
    end
end

function Textures.PaintAdded(uf, paint)
    if findFocus then FindFocus() end
    Textures.Paint(uf, paint)
end

local function Apply(uf, reset, useTextures, background, deferSpark)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    local absorbDone = not Absorbs or Absorbs.Apply(uf, health, useTextures, Writable)
    local shapeDone = not Slant or Slant.Apply(uf, health, useTextures, Writable)
    if not useTextures then
        local healthDone = ApplyHealth(uf, health)
        local castDone = ApplyCast(uf, cast)
        return healthDone and castDone and absorbDone and shapeDone
    end
    local fill = Textures.HealthFill(uf)
    if fill then
        -- Both clients rebuild anchors when names-only mode changes. The
        -- fill is invisible there. Background ownership still feeds Selection.
        local namesOnly = private.HealthNameOnly(uf)
        if NS.Public(namesOnly) and namesOnly == true then fill = nil end
    end
    local healthDone = ApplyHealth(uf, health, reset, fill, background)
    local castDone = ApplyCast(uf, cast, reset, castFill, castBack, sharedCastStyle, deferSpark)
    return healthDone and castDone and absorbDone and shapeDone
end
local function FlushDeferred(frame)
    if NS.IsCombatLocked() then return end
    frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    listening = false
    for uf, restore in pairs(deferred) do
        if restore or not Textures.inUse then
            Textures.Restore(uf)
        else
            Textures.Apply(uf, painted[uf] ~= generation)
        end
    end
end

Defer = function(uf, restore)
    if not NS.IsCombatLocked() then return end
    deferred[uf] = restore
    if listening then return end
    if not restoreFrame then
        restoreFrame = CreateFrame("Frame")
        restoreFrame:SetScript("OnEvent", FlushDeferred)
    end
    restoreFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    listening = true
end

function Textures.Apply(uf, reset, paintedWithLayout)
    -- Plate entry points supply a public unit frame. A stable generation
    -- costs a table lookup on presentation events and touches no region.
    local version = painted[uf]
    local background = healthBack
    local scopedBackground = scopedHealth or background and (nativeEnemyOutline or nativeFriendlyOutline)
    local stable = version == generation and not reset
    if stable and not scopedBackground and deferred[uf] == nil then return end
    local useTextures = (not private.SkinAllowed or private.SkinAllowed(uf))
        and (baseTextures or focusFill and uf == Textures.focusUF)
    if not useTextures and not version then return end
    if not NS.Public(uf) or not uf or NS.Safety.IsForbidden(uf) then return end
    if scopedBackground then
        local prefix = private.PlatePrefix(uf)
        background = Textures.HealthBackground(prefix, scopedHealth and private.AppearanceScope(uf))
        local state = healthStates[uf]
        if stable and deferred[uf] == nil and (state and state.back or nil) == background
            and (not scopedHealth or (state and state.fill or nil) == Textures.HealthFill(uf)) then return end
    end
    if not Accessible(uf) then
        if version then painted[uf] = 0 end
        Defer(uf, false)
        return
    end
    if not version then private.Layout.Observe(uf) end
    painted[uf] = 0
    -- This paint answers the plate's own earlier deferral. One made while it
    -- runs (DeferCast: a cast height the client withheld in combat) is new,
    -- stays with this plate and survives a complete paint. A paint of another
    -- plate inside this one touches only that plate's key.
    local owed = deferred[uf]
    deferred[uf] = nil
    -- On a new lease Paint already owns the final layout boundary. Leave
    -- only Spark sizing until that synchronous pass has finished.
    local deferSpark = paintedWithLayout and not version and useTextures and sharedCastStyle ~= nil
    if Apply(uf, reset or version == 0, useTextures, background, deferSpark) then
        painted[uf] = useTextures and generation or nil
    else
        Defer(uf, false)
        -- Outside combat nothing new is kept: the earlier deferral stands.
        if deferred[uf] == nil then deferred[uf] = owed end
    end
    return deferSpark
end

-- FlushDeferred retries denied cast layouts or paints after combat.
-- Outside combat, the next layout or cast event retries instead.
function Textures.DeferCast(cast)
    if not NS.IsCombatLocked() then return end
    local state = castStates[cast]
    local uf = state and state.owner
    if not uf then return end
    Defer(uf, false)
end

-- The cold-layout handoff (Layout.lua Settle): the plate's geometry is final
-- after a layout pass of the Suite. The styled castbar samples its height once.
function Textures.OnLayout(uf, finishSpark)
    if not painted[uf] then return end
    if Slant then Slant.OnLayout(uf) end
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    local state = NS.Public(cast) and cast and castStates[cast]
    local appearance = private.CastAppearance
    if not state or not state.style or not appearance then return end
    if appearance.OnLayout(cast, finishSpark) == false and finishSpark and painted[uf] then
        painted[uf] = 0
        if deferred[uf] ~= true then Defer(uf, false) end
    end
end

function Textures.Restore(uf, recycled)
    if uf == Textures.focusUF then
        Textures.SetFocus(nil)
        findFocus = focusFill ~= nil
    end
    if not painted[uf] and deferred[uf] == nil then return end
    painted[uf], deferred[uf] = nil, nil
    if NS.Safety.IsForbidden(uf) then return end
    local state = recycled and healthStates[uf]
    if state then
        -- Both clients replace this asset in UpdateAnchors during acquire.
        -- The background still owes its tint, geometry and texture.
        state.fill = nil
        if not state.back then healthStates[uf], spareHealth[uf] = nil, state end
    end
    if not Accessible(uf) or not Apply(uf) then Defer(uf, true) end
end

function Textures.OnAnchors(uf)
    if painted[uf] then Textures.Apply(uf, true) end
end

function Textures.TintRole(visual, hex, path)
    local fill = visual.fill
    local r, g, b = private.Suite.RGB(hex)
    if path then
        fill:SetTexture(path)
        fill:SetVertexColor(r, g, b, 1)
    else
        fill:SetVertexColor(1, 1, 1, 1)
        fill:SetColorTexture(r, g, b, 1)
    end
    visual.fillColor, visual.fillPath = hex, path
end

function Textures.RestoreAll()
    for uf in pairs(painted) do Textures.Restore(uf) end
    for uf, restore in pairs(deferred) do
        if not restore then deferred[uf] = nil end
    end
    if listening and not next(deferred) then
        restoreFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        listening = false
    end
end
