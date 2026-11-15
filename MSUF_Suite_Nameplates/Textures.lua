local _, private = ...
local Selection = private.Selection
local NS = private.NS
local Textures = {}
private.Textures = Textures

local healthFill, healthBack, castFill, castBack, focusFill, baseTextures, focusHealth, findFocus
local darkCastBackground
local nativeEnemyOutline, nativeFriendlyOutline
local healthStates = setmetatable({}, { __mode = "k" })
local castStates = setmetatable({}, { __mode = "k" })
local castHooks = setmetatable({}, { __mode = "k" })
local painted = setmetatable({}, { __mode = "k" })
local deferred = setmetatable({}, { __mode = "k" })
local generation, restoreFrame = 0, nil
local Defer
local listening = false
local textureKeys = {}
local visuals
function Textures.Bind(plateVisuals) visuals = plateVisuals end

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

local function PaintHealthBackground(back, state, path, classic)
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
    if fit or state.backFitted then NS.NameplateStyle.FitModernHealthBackground(back, fit) end
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
    state = state or {}
    healthStates[uf] = state
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
        if PaintHealthBackground(back, state, healthBack, classic) then
            if not healthBack then Selection.RepaintBackground(health) end
        else
            complete = false
        end
    end
    if not (state.fill or state.back) then healthStates[uf] = nil end
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

local function PaintCastFill(cast, state)
    local kind = cast.barType
    if state.usesColorFill or NS.Public(kind) and kind == "empowered" then return true end
    local fill = cast:GetStatusBarTexture()
    if not NS.Public(fill) then return false end
    if not fill then return true end
    if not Writable(fill) then return false end
    -- The selected texture is public, even when Blizzard's cast type is secret.
    -- Set it through the status bar so progress uses the custom asset's coordinates.
    local ok = cast:SetStatusBarTexture(castFill)
    if not NS.Public(ok) or ok == false then return false end
    state.fill = castFill
    state.colorRevision = nil
    return RecolorCastFill(cast, state)
end

local function AfterCastFill(cast, full)
    local state = castStates[cast]
    if not state then return end
    state.fill = nil
    state.full = not NS.Public(full) or full == true
    if not state.full then state.usesColorFill, state.notInterruptible, state.interrupted = nil, nil, nil end
    local uf = state.owner
    if not state.enabled or not painted[uf] then return end
    if not castFill then return end
    if not Writable(cast) or not PaintCastFill(cast, state) then Defer(uf, false) end
end

local function AfterCastColorFill(cast)
    local state = castStates[cast]
    if state then state.fill, state.usesColorFill = nil, true end
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
    if state.fill and (not Writable(cast) or not RecolorCastFill(cast, state)) then Defer(state.owner, false) end
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
    -- The next native update restores restricted cast art using its original type.
    if not NS.Public(kind) then
        state.fill = nil
        return true
    end
    local info = CastingBarTypeInfo[kind or "standard"]
    local asset = classic and CLASSIC_CAST_FILL or info and (state.full and info.full or info.filling)
    if not asset or asset == "" then
        state.fill = nil
        return true
    end
    local fill = cast:GetStatusBarTexture()
    if not Writable(fill) then return false end
    local ok = cast:SetStatusBarTexture(asset)
    if not NS.Public(ok) or ok == false then return false end
    fill = cast:GetStatusBarTexture()
    if not Writable(fill) then return false end
    if classic and info and info.classicFillColor then
        local color = state.full and info.classicFullColor or info.classicFillColor
        local r, g, b = color:GetRGB()
        cast:SetStatusBarColor(r, g, b, 1)
        fill:SetVertexColor(r, g, b, 1)
    elseif not classic then
        cast:SetStatusBarColor(1, 1, 1, 1)
        fill:SetVertexColor(1, 1, 1, 1)
    end
    state.fill = nil
    return true
end

local function ApplyCastBackground(cast, state, path, jundies)
    local back = cast.Background
    if not NS.Public(back) then return false end
    if not back then return true end
    if not Writable(back) then return false end
    if path then
        if not SetAsset(back, path) then return false end
        back:SetTexCoord(0, 1, 0, 1)
        if jundies then back:SetVertexColor(0, 0, 0, .5)
        else
            back:SetVertexColor(.16, .16, .16, 1)
        end
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
    state.back, state.darkBack = path, jundies
    return true
end

local function ApplyCast(uf, cast, reset, useFill, castBack)
    if not NS.Public(cast) then return false end
    local state = castStates[cast]
    if not cast or not state and not (useFill or castBack) then return true end
    if state then state.enabled = useFill ~= nil end
    if not Writable(cast) then return false end
    if not state then
        state = {}
        castStates[cast] = state
    end
    state.enabled = useFill ~= nil
    if useFill and not castHooks[cast] then
        hooksecurefunc(cast, "UpdateBarFillTexture", AfterCastFill)
        hooksecurefunc(cast, "SetColorFill", AfterCastColorFill)
        hooksecurefunc(cast, "PlayInterruptAnims", AfterInterrupt)
        hooksecurefunc(cast, "PlayFinishAnim", AfterFinish)
        cast:HookScript("OnEvent", AfterCastEvent)
        castHooks[cast] = true
    end
    state.owner = uf
    local complete = true
    if castHooks[cast] and (state.fill ~= useFill or useFill and state.colorRevision ~= castColorRevision) then
        if useFill then
            local shown = cast:IsShown()
            if NS.Public(shown) and shown then
                if state.fill == useFill then
                    complete = RecolorCastFill(cast, state)
                else
                    complete = PaintCastFill(cast, state)
                end
            end
        elseif state.fill then
            complete = RestoreCastFill(cast, state)
        end
    end
    local dark = castBack and darkCastBackground or nil
    if state.back ~= castBack or state.darkBack ~= dark or reset and castBack then
        if not ApplyCastBackground(cast, state, castBack, dark) then complete = false end
    end
    if not (useFill or state.fill or state.back) then castStates[cast] = nil end
    return complete
end

local function Resolve(previousKey, previousPath, key)
    if key == previousKey and previousPath then return previousPath end
    if key and key ~= "" then return NS.ResolveTexture(key) end
end

local function SetCastRGB(color, r, g, b)
    if color[1] == r and color[2] == g and color[3] == b then return false end
    color[1], color[2], color[3] = r, g, b
    return true
end

local function ReadCastColors()
    local r, g, b, nr, ng, nb = NS.NameplateStyle.CastFillColors(castColorOverride, lockedColorOverride)
    local normal = SetCastRGB(castColors.standard, r, g, b)
    local locked = SetCastRGB(castColors.uninterruptable, nr, ng, nb)
    if not normal and not locked then return false end
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
    if not castFill or not ReadCastColors() then return end
    for uf in pairs(painted) do Textures.Apply(uf) end
end

function Textures.Configure(config)
    local hadTextures = Textures.inUse
    local fill, back, cast, background = config.nativeHealthFillTexture, config.nativeHealthBackgroundTexture,
        config.nativeCastFillTexture, config.nativeCastBackgroundTexture
    local hpFill = Resolve(textureKeys[1], healthFill, fill)
    local hpBack = Resolve(textureKeys[2], healthBack, back)
    local spellFill = Resolve(textureKeys[3], castFill, cast)
    local spellBack = Resolve(textureKeys[4], castBack, background)
    castColorOverride, lockedColorOverride = config.nativeCastFillColor, config.nativeCastLockedColor
    if spellFill then ReadCastColors() end
    local dark = config.look == 1 and background == "Solid" or nil
    local focusKey = config.nativeFocusHealthFillTexture
    local focus = Resolve(textureKeys[5], focusFill, focusKey)
    textureKeys[1], textureKeys[2], textureKeys[3], textureKeys[4] = fill, back, cast, background
    textureKeys[5] = focusKey
    local enemyOutline = NS.NameplateStyle.UsesNativeOutline(config, "enemy")
    local friendlyOutline = NS.NameplateStyle.UsesNativeOutline(config, "friendly")
    if hpFill ~= healthFill or hpBack ~= healthBack or spellFill ~= castFill or spellBack ~= castBack or focus ~= focusFill
        or enemyOutline ~= nativeEnemyOutline or friendlyOutline ~= nativeFriendlyOutline or dark ~= darkCastBackground then
        generation = generation + 1
    end
    nativeEnemyOutline, nativeFriendlyOutline = enemyOutline, friendlyOutline
    healthFill, healthBack, castFill, castBack = hpFill, hpBack, spellFill, spellBack
    darkCastBackground = dark
    focusFill = focus
    baseTextures = healthFill or healthBack or castFill or castBack
    Textures.inUse, Textures.focusFill = baseTextures or focusFill, focusFill
    Textures.healthFill, Textures.healthBack, Textures.castFill = healthFill, healthBack, castFill
    return hadTextures and not Textures.inUse
end

function Textures.HealthBackground(prefix)
    if prefix == "enemy" and nativeEnemyOutline or prefix == "friendly" and nativeFriendlyOutline then return nil end
    return healthBack
end

function Textures.HasHealthBackground(uf)
    local state = uf and healthStates[uf]
    return state and state.back ~= nil
end

function Textures.HealthFill(uf)
    if uf == Textures.focusUF then return focusFill or healthFill end
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
    Textures.Apply(uf)
    paint(uf)
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

local function Apply(uf, reset, useTextures, background)
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
    if not useTextures then
        local healthDone = ApplyHealth(uf, health)
        local castDone = ApplyCast(uf, cast)
        return healthDone and castDone
    end
    local healthDone = ApplyHealth(uf, health, reset, Textures.HealthFill(uf), background)
    local castDone = ApplyCast(uf, cast, reset, castFill, castBack)
    return healthDone and castDone
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

function Textures.Apply(uf, reset)
    -- Plate entry points supply a public unit frame. A stable generation
    -- costs a table lookup on presentation events and touches no region.
    local version = painted[uf]
    local background = healthBack
    local scopedBackground = background and (nativeEnemyOutline or nativeFriendlyOutline)
    local stable = version == generation and not reset
    if stable and not scopedBackground and deferred[uf] == nil then return end
    local useTextures = (not private.SkinAllowed or private.SkinAllowed(uf))
        and (baseTextures or focusFill and uf == Textures.focusUF)
    if not useTextures and not version then return end
    if not NS.Public(uf) or not uf or NS.Safety.IsForbidden(uf) then return end
    if scopedBackground then
        background = Textures.HealthBackground(private.PlatePrefix(uf))
        local state = healthStates[uf]
        if stable and deferred[uf] == nil and (state and state.back or nil) == background then return end
    end
    if not Accessible(uf) then
        if version then painted[uf] = 0 end
        Defer(uf, false)
        return
    end
    if not version then private.Layout.Observe(uf) end
    painted[uf] = 0
    if Apply(uf, reset or version == 0, useTextures, background) then
        painted[uf], deferred[uf] = useTextures and generation or nil, nil
    else
        Defer(uf, false)
    end
end

function Textures.Restore(uf)
    if uf == Textures.focusUF then
        Textures.SetFocus(nil)
        findFocus = focusFill ~= nil
    end
    if not painted[uf] and deferred[uf] == nil then return end
    painted[uf], deferred[uf] = nil, nil
    if NS.Safety.IsForbidden(uf) then return end
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
