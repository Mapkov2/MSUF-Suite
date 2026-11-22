local _, private = ...
local NS, Style = private.NS, private.NS.NameplateStyle
local Features = {}
private.EasyFeatures = Features
local owner, config, generation = nil, nil, 0
local StyleScopes = NS.NameplateExtensions
local patterns, patternEvents, colors, order = {}, {}, {}, {}
local sharedPatterns
local states = setmetatable({}, { __mode = "k" })
local casts = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local selected = {}
local castLayers = { "castTint", "icon", "seam" }
local restores = setmetatable({}, { __mode = "k" })
local threatRoles = { ThreatLost = true, ThreatWarning = true, ThreatTransition = true, TankMode = true, OtherTank = true }

local function Publish()
    Features.enabled = Features.inUse or private.TargetResource.enabled or next(restores) ~= nil
    owner.extras = Features.enabled
end

local function Writable(region)
    if not NS.Public(region) or not region or NS.Safety.IsForbidden(region) then return false end
    if region.CanBeAccessedInContext then
        local access = region:CanBeAccessedInContext()
        if not NS.Public(access) or access ~= true then return false end
    end
    return true
end

local function Mutable(state)
    if not Writable(state.uf) or not Writable(state.health) then return false end
    if NS.InCombat() then
        local protected = state.uf:IsProtected()
        if not NS.Public(protected) or protected ~= false then
            owner.pendingPlates[state.uf] = true
            return false
        end
    end
    return true
end

local function RestoreName(state)
    if state.nameColor then
        if not Writable(state.uf.name) then return false end
        state.uf.name:SetTextColor(unpack(state.nameColor))
        state.nameColor, state.nameTint = nil, nil
    end
    return true
end

local function CaptureName(state)
    local r, g, b, a = state.uf.name:GetTextColor()
    if not NS.Finite(r) or not NS.Finite(g) or not NS.Finite(b) or not NS.Finite(a) then return false end
    local saved = state.nameOriginal or {}
    saved[1], saved[2], saved[3], saved[4] = r, g, b, a
    state.nameOriginal, state.nameColor = saved, saved
    return true
end

local function Pattern(state)
    local plan = state.patternPlan
    local chosen
    if plan then
        for _, kind in ipairs(order) do
            local active = kind == "mouseover" and private.Mouseover.IsHovered(state.uf) or selected[kind] == state.uf
            local key = kind == "mouseover" and "hover" or kind
            if active and plan[key] then chosen = plan[key] break end
        end
    end
    if not chosen then
        if state.pattern then state.pattern:Hide() end
        state.patternKind = nil
        return
    end
    if not state.pattern then state.pattern = state.health:CreateTexture(nil, "ARTWORK", nil, 5) end
    local texture, fill = state.pattern, state.health:GetStatusBarTexture()
    if not Writable(fill) then
        texture:Hide()
        return
    end
    if state.patternFill ~= fill then texture:SetAllPoints(fill) state.patternFill = fill end
    if state.patternKind ~= chosen or state.patternGeneration ~= generation then
        texture:SetTexture(chosen.texture)
        texture:SetVertexColor(1, 1, 1, 1)
        texture:SetAlpha(chosen.alpha * (state.opacity or 1))
        state.patternKind, state.patternGeneration = chosen, generation
    end
    texture:Show()
end

local function PaintName(state, hex)
    if config.threatNameColor and hex and Writable(state.uf.name) then
        if not state.nameColor then
            CaptureName(state)
        end
        if state.nameColor and state.nameTint ~= hex then state.uf.name:SetTextColor(NS.RGB(hex)) state.nameTint = hex end
    else
        RestoreName(state)
    end
end

local function Threat(state, role)
    local key = threatRoles[role] and private.RoleKey[role]
    local hex = state.prefix == "enemy" and key and config[key.enabled] ~= false and config[key.color]
    state.threatHex, state.role = hex, role
    PaintName(state, hex)
    if config.threatFrameColor and hex then
        if not state.threat then state.threat = Style.CreateBorder(state.health) end
        Style.PaintBorder(state.threat, state.health, owner.barSettings.highlightBorderSize or 2, hex)
    elseif state.threat then
        Style.PaintBorder(state.threat, state.health, 0)
    end
end

local function CastTint(state, locked)
    if not config.castHealthColors or state.prefix ~= "enemy" or not state.active then
        if state.castTint then state.castTint:Hide() end
        return
    end
    if not state.castTint then
        state.castTint = state.health:CreateTexture(nil, "ARTWORK", nil, 3)
        state.castTint:SetColorTexture(1, 1, 1, 1)
    end
    local fill = state.health:GetStatusBarTexture()
    if not Writable(fill) then
        state.castTint:Hide()
        return
    end
    if state.tintFill ~= fill then state.castTint:SetAllPoints(fill) state.tintFill = fill end
    if NS.Public(locked) and locked == nil then
        if not NS.Public(state.unit) or type(state.unit) ~= "string" then return end
        local _, _, _, _, _, _, _, value = UnitCastingInfo(state.unit)
        locked = value
        if NS.Public(locked) and locked == nil then
            local _, _, _, _, _, _, channel = UnitChannelInfo(state.unit)
            locked = channel
        end
    end
    if NS.Public(locked) and locked == nil then
        state.active = false
        state.castTint:Hide()
        return
    end
    state.castTint:SetVertexColorFromBoolean(locked, colors.locked, colors.interruptible)
    state.castTint:SetAlpha(state.opacity or 1)
    state.castTint:Show()
end

local function Icon(state)
    local cast = state.cast
    local native = cast and cast.Icon
    local visible = Writable(native) and native:IsShown()
    local enabled = config.castIconCombinedHeight and NS.Public(visible) and visible == true
    if not enabled then
        if state.icon then state.icon:Hide() end
        if state.iconAlpha and Writable(native) then native:SetAlpha(state.iconAlpha) state.iconAlpha = nil end
        return
    end
    if not state.icon then
        state.icon = cast:CreateTexture(nil, "ARTWORK", nil, 4)
        state.icon:SetPoint("TOPRIGHT", state.health, "TOPLEFT", -2, 0)
        state.icon:SetPoint("BOTTOMRIGHT", cast, "BOTTOMLEFT", -2, 0)
        state.icon:SetTexCoord(.07, .93, .07, .93)
    end
    local healthHeight, castHeight = state.health:GetHeight(), cast:GetHeight()
    if not NS.Finite(healthHeight) or not NS.Finite(castHeight) then
        state.icon:Hide()
        if state.iconAlpha then native:SetAlpha(state.iconAlpha) state.iconAlpha = nil end
        return
    end
    local gap = NamePlateSetupOptions.castBarToHealthBarSpacing
    local size = healthHeight + castHeight + (NS.Finite(gap) and gap or 2)
    if state.iconWidth ~= size then state.icon:SetWidth(size) state.iconWidth = size end
    state.icon:SetTexture(native:GetTexture())
    if state.iconAlpha == nil then
        local alpha = native:GetAlpha()
        if not NS.Finite(alpha) then
        state.icon:Hide()
        return
    end
        state.iconAlpha = alpha
    end
    native:SetAlpha(0)
    state.icon:Show()
end

local function OnCast(cast)
    if not Features.inUse or not config.castHealthColors then return end
    local state = casts[cast]
    if not state or not state.enabled or not Mutable(state) then return end
    local shown = cast:IsShown()
    state.active = NS.Public(shown) and shown == true
    CastTint(state)
end

local function OnInterruptibility(cast, locked)
    if not Features.inUse or not config.castHealthColors then return end
    local state = casts[cast]
    if state and state.enabled and Mutable(state) then CastTint(state, locked) end
end

local function OnIcon(cast)
    if not Features.inUse then return end
    local state = casts[cast]
    if state and state.enabled and (config.castIconCombinedHeight or state.iconAlpha) and Mutable(state) then Icon(state) end
end

local function OnCastEnd(cast)
    local state = casts[cast]
    if not state or not state.enabled then return end
    state.active = false
    if state.castTint and Writable(state.castTint) then state.castTint:Hide() end
end

local function RestoreCast(state)
    state.active = false
    for _, key in ipairs(castLayers) do
        if state[key] then state[key]:Hide() end
    end
    local native = state.cast and state.cast.Icon
    if state.iconAlpha and Writable(native) then native:SetAlpha(state.iconAlpha) state.iconAlpha = nil end
    return state.iconAlpha == nil
end

local function SamePatterns(first, second)
    if first == second then return true end
    if not first or not second then return false end
    for _, entry in ipairs(StyleScopes.Patterns) do
        local a, b = first[entry.kind], second[entry.kind]
        if (a == nil) ~= (b == nil) or a and b and (a.texture ~= b.texture or a.alpha ~= b.alpha) then return false end
    end
    return true
end

local function CompilePatterns(config)
    patterns, patternEvents = {}, {}
    for _, scope in ipairs(StyleScopes.OpacityScopes) do
        local plan = {}
        for _, entry in ipairs(StyleScopes.Patterns) do
            local key, alpha = StyleScopes.PatternSettings(config, scope, entry)
            local texture = NS.ResolveTexture(key)
            if texture then
                plan[entry.kind] = { texture = texture, alpha = alpha / 100 }
                patternEvents[entry.kind] = true
            end
        end
        if next(plan) then patterns[scope] = plan end
    end
    Features.splitEnemyPatterns = not SamePatterns(patterns.enemy, patterns.neutral)
    sharedPatterns = not Features.splitEnemyPatterns
        and SamePatterns(patterns.enemy, patterns.friendly) and SamePatterns(patterns.enemy, patterns.friendlyNpc)
    Features.hoverPatterns = patternEvents.hover
end

local function PatternPlan(uf, unit, prefix)
    if sharedPatterns then return patterns.enemy end
    local scope = StyleScopes.OpacityScope(StyleScopes.PlateKind(uf, unit))
    return patterns[scope or prefix]
end

function Features.UpdatePatternScope(uf, unit)
    local state = states[uf]
    if not state or not state.enabled then return end
    local plan = PatternPlan(uf, unit, state.prefix)
    if plan == state.patternPlan or not Mutable(state) then return end
    state.patternPlan = plan
    Pattern(state)
end

function Features.Configure(module)
    owner, config, generation = module, module.config, generation + 1
    for _, state in pairs(states) do if Mutable(state) then RestoreName(state) end end
    CompilePatterns(config)
    order = Style.HighlightOrder(config.highlightPriority and config.highlightOrder or nil)
    if config.castHealthColors then
        colors.interruptible = CreateColor(NS.RGB(config.castHealthInterruptible or "4fb3ff"))
        colors.locked = CreateColor(NS.RGB(config.castHealthLocked or "f39200"))
    end
    Features.inUse = module.active and config.look ~= 2 and (next(patternEvents) or config.castHealthColors
        or config.threatNameColor or config.threatFrameColor or config.castIconCombinedHeight or config.castSeamLine)
    private.TargetResource.Configure(module)
    if not Features.inUse then
        Features.splitEnemyPatterns, Features.hoverPatterns = false, false
        for uf, state in pairs(states) do if state.enabled then Features.Restore(uf) end end
    end
    Publish()
    Features.Selection("target")
    Features.Selection("focus")
end

function Features.Paint(uf, health, cast, prefix, unit, styled, role)
    local state = states[uf]
    if not Features.inUse or not styled then
        if state then Features.Restore(uf) end
    else
        if not state then state = { uf = uf, health = health } states[uf] = state end
        if Mutable(state) then
            if state.cast ~= cast and state.castDirty then
                RestoreCast(state)
                state.icon, state.iconWidth, state.castDirty = nil, nil, nil
            end
            state.prefix, state.unit, state.enabled, state.cast = prefix, unit, true, cast
            state.nameTint = nil
            state.patternPlan = PatternPlan(uf, unit, prefix)
            Pattern(state)
            Threat(state, role)
            if Writable(cast) and (config.castHealthColors or config.castIconCombinedHeight or config.castSeamLine) then
                state.castDirty = true
                casts[cast] = state
                if not hooked[cast] then
                    hooked[cast] = true
                    cast:HookScript("OnHide", OnCastEnd)
                    hooksecurefunc(cast, "HandleCastStart", OnCast)
                    hooksecurefunc(cast, "UpdateInterruptibleState", OnInterruptibility)
                    hooksecurefunc(cast, "PlayInterruptAnims", OnCastEnd)
                    hooksecurefunc(cast, "PlayFinishAnim", OnCastEnd)
                    hooksecurefunc(cast, "UpdateIconShown", OnIcon)
                end
                OnCast(cast)
                if config.castIconCombinedHeight or state.iconAlpha then Icon(state) end
                if config.castSeamLine and not state.seam then
                    state.seam = cast:CreateTexture(nil, "OVERLAY")
                    state.seam:SetPoint("TOPLEFT", cast, "TOPLEFT")
                    state.seam:SetPoint("TOPRIGHT", cast, "TOPRIGHT")
                    state.seam:SetHeight(1)
                    state.seam:SetColorTexture(0, 0, 0, 1)
                end
                if state.seam then state.seam:SetShown(config.castSeamLine == true) end
            else
                if state.castDirty then RestoreCast(state) state.castDirty = nil end
            end
        end
    end
    private.TargetResource.Attach(uf, health, styled)
end

function Features.Selection(kind)
    local old = selected[kind]
    local plate = Features.inUse and C_NamePlate.GetNamePlateForUnit(kind)
    local uf = Writable(plate) and plate.UnitFrame
    if not Writable(uf) then uf = nil end
    selected[kind] = uf
    if states[old] and states[old].enabled and Mutable(states[old]) then Pattern(states[old]) end
    if uf ~= old and states[uf] and states[uf].enabled and Mutable(states[uf]) then Pattern(states[uf]) end
    if kind == "target" and private.TargetResource.enabled then private.TargetResource.Selection() end
end

function Features.Added()
    if patternEvents.target then Features.Selection("target") end
    if patternEvents.focus then Features.Selection("focus") end
    if not patternEvents.target and private.TargetResource.enabled then private.TargetResource.Selection() end
end

function Features.Hover(uf)
    local state = states[uf]
    if state and state.enabled and Mutable(state) then Pattern(state) end
end

function Features.Role(uf, role)
    local state = states[uf]
    if state and state.enabled and Mutable(state) then Threat(state, role) end
end

function Features.NativeName(uf)
    if not Features.inUse then return end
    local state = states[uf]
    if not state or not state.enabled or not config.threatNameColor or not state.threatHex
        or uf.UpdateNameOverride or not Mutable(state) or not Writable(uf.name) then return end
    local shown = uf.name:IsShown()
    if not NS.Public(shown) or shown ~= true then return end
    if not CaptureName(state) then return end
    state.nameTint = nil
    PaintName(state, state.threatHex)
end

function Features.Restore(uf, removed)
    local state = states[uf]
    private.TargetResource.Restore(uf, removed)
    if not state then return end
    if removed and selected.target == uf then selected.target = nil end
    if removed and selected.focus == uf then selected.focus = nil end
    if not state.enabled and not restores[uf] then return end
    state.enabled = false
    if not Mutable(state) then
        restores[uf] = true
        Publish()
        return
    end
    if state.pattern then state.pattern:Hide() end
    local castRestored, nameRestored = RestoreCast(state), RestoreName(state)
    if state.threat then Style.PaintBorder(state.threat, state.health, 0) end
    if not castRestored or not nameRestored then
        restores[uf], owner.pendingPlates[uf] = true, true
        Publish()
        return
    end
    restores[uf], state.castDirty = nil, nil
    Publish()
end

function Features.SetOpacity(uf, alpha)
    local state = states[uf]
    if not state then return end
    state.opacity = alpha
    if state.pattern and state.patternKind then state.pattern:SetAlpha(state.patternKind.alpha * alpha) end
    if state.castTint then state.castTint:SetAlpha(alpha) end
end
