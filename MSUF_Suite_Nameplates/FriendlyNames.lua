local _, private = ...
local NS, S = private.NS, private.Suite
local GROUP_NAMES_ONLY = private.Mode.GROUP_NAMES_ONLY
-- "Names only: party / raid" (Friendly player display): the names of friendly
-- players outside the group fade out. The module's friendlyNames table holds
-- each faded name's alpha from before; group and role changes filter again
-- (Skin.lua RefreshActive).
local Names = { repairKinds = {} }
private.FriendlyNames = Names
local M
local X = NS.NameplateExtensions
local onlyNames = setmetatable({}, { __mode = "k" })
local labelOwners = setmetatable({}, { __mode = "k" })
local barOwners = setmetatable({}, { __mode = "k" })
local targetBars = setmetatable({}, { __mode = "k" })
local barNameKinds = {}
local npcHealthBars = private.ForcedNPCHealth or setmetatable({}, { __mode = "k" })
Names.npcHealthBars = npcHealthBars
local nameHooked, colorRevision = nil, 0
local friendlyR, friendlyG, friendlyB, friendlyOverride
local visualFields = { "HealthBarsContainer", "CastBarsContainer", "AurasFrame", "RaidTargetFrame", "ClassificationFrame",
    "PlayerLevelDiffFrame", "WidgetContainer" }

function Names.Bind(module) M = module end

local function Safe(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

local function Writable(uf, region)
    if not Safe(region) then return false end
    if region.CanBeAccessedInContext then
        local accessible = region:CanBeAccessedInContext()
        if not S.Public(accessible) or accessible ~= true then
            if NS.InCombat() then M.pendingPlates[uf] = true end
            return false
        end
    end
    if NS.InCombat() then
        local protected = region:IsProtected()
        if not S.Public(protected) or protected ~= false then
            M.pendingPlates[uf] = true
            return false
        end
    end
    return true
end

function Names.Restore(name, uf)
    local alpha = name and M.friendlyNames[name]
    if alpha == nil then return true end
    if not Writable(uf, name) then
        if uf then M.pendingPlates[uf] = true end
        return false
    end
    if uf and private.Extensions and private.Extensions.inUse then private.Extensions.BeforeNameFilter(uf) end
    name:SetAlpha(alpha)
    M.friendlyNames[name] = nil
    return true
end

function Names.Filter(uf, prefix)
    local name = uf.name
    if prefix ~= "friendly" or M.config.friendlyNamesOnly ~= GROUP_NAMES_ONLY then
        if M.friendlyNames[name] ~= nil then Names.Restore(name, uf) end
        return
    end
    if not S.Public(uf.isPlayer) or uf.isPlayer ~= true or private.UnitKinds and private.UnitKinds[uf] ~= "friendlyPlayer" then
        Names.Restore(name, uf)
        return
    end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local unit = health and M.units[health]
    if not unit then
        Names.Restore(name, uf)
        return
    end
    local party, raid = UnitInParty(unit), UnitInRaid(unit)
    if not S.Public(party) or not S.Public(raid) then
        Names.Restore(name, uf)
        return
    end
    if party or raid then
        if M.friendlyNames[name] ~= nil and Names.Restore(name, uf) then
            local hover, extensions = private.Mouseover, private.Extensions
            if hover.textInUse then hover.Apply(uf, health, prefix, M.config.look ~= private.Mode.LOOK_BLIZZARD and M.config[prefix]) end
            if extensions and extensions.inUse then extensions.ResumeName(uf) end
        end
        return
    end
    if M.friendlyNames[name] == nil then
        if not Writable(uf, name) then return end
        if private.Extensions and private.Extensions.inUse then private.Extensions.BeforeNameFilter(uf) end
        local hover = private.Mouseover
        if hover.textInUse and not hover.ReleaseName(uf, name) then return end
        local alpha = name:GetAlpha()
        if not NS.Finite(alpha) then return end
        M.friendlyNames[name] = alpha
        -- Alpha survives Blizzard's ordinary name Show()/Hide() refreshes.
        name:SetAlpha(0)
    end
end

-- A simplified plate processes PLAYER_TARGET_CHANGED before Blizzard updates
-- its cached isTarget. Its bar setter runs after that change, on just the old
-- and new target. A plate may also be assigned before its name arrives.
local simplifiedBars = setmetatable({}, { __mode = "k" })
local ApplyNameColor

local function SimplifiedTargetChanged(bar)
    local uf = simplifiedBars[bar]
    if M.active and Safe(uf) and S.Public(uf.isSimplified) and uf.isSimplified == true then
        Names.RepairMissing(uf, uf.unit, true)
    end
end

function Names.RepairMissing(uf, unit, targetChanged)
    if not M.active or not Names.managedNames or not S.Public(unit) or type(unit) ~= "string"
        or M.activeUnits[unit] ~= uf or not Writable(uf, uf) or not S.Public(uf.unit) or uf.unit ~= unit then return end
    local state = onlyNames[uf]
    local kind = private.UnitKinds[uf]
    local nameOnly = state and state.scope or Names.friendlyPlayerNames and kind == "friendlyPlayer"
    if not nameOnly and not barNameKinds[kind] then return end
    if private.SkinScopes.suppressed[uf] or uf.UpdateNameOverride or not uf.optionTable or not uf.ShouldShowName then return end
    local name = uf.name
    if not Writable(uf, name) then return end
    local missing
    if not nameOnly then
        -- A populated full bar already belongs to Blizzard. It needs no
        -- visibility, target or unit-name queries, including for opaque text.
        local text = name:GetText()
        if not S.Public(text) or text ~= nil and text ~= "" then return end
        missing = true
    end
    if nameOnly and S.Public(uf.isSimplified) and uf.isSimplified == true then
        local bar = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
        if bar and not simplifiedBars[bar] and Writable(uf, bar) then
            simplifiedBars[bar] = uf
            hooksecurefunc(bar, "SetIsTarget", SimplifiedTargetChanged)
        end
    end
    local shown = name:IsShown()
    if not S.Public(shown) then return end
    if shown and nameOnly then
        local text = name:GetText()
        missing = S.Public(text) and (text == nil or text == "")
        if not missing and not targetChanged then return end
    elseif not shown and not nameOnly then
        -- A full bar keeps Blizzard's visibility. The cache can resolve
        -- its shown but empty name either before or after frame assignment.
        return
    end
    -- Only ask the native renderer to repair a missing name or a stale
    -- selection. It also applies realm, class, spectator and visibility rules.
    if not S.Public(uf.widgetsOnlyMode) or uf.widgetsOnlyMode == true then return end
    -- An accessible region can still belong to a secret unit. Blizzard's
    -- Lua updater branches on identity, target and mouseover comparisons.
    -- In restricted contexts leave visibility to the driver and only forward
    -- a name to a text sink that the driver has already chosen to show.
    local value = UnitName(unit)
    if not S.Public(value) or not S.Public(uf.isTarget) or not S.Public(uf.isSimplified)
        or not S.Public(uf.forceShowUnitName) or not S.Public(uf.colorNameWithClassColor) or not S.Public(uf.hideRealmName)
        or NS.GroupActionsRestricted and NS.GroupActionsRestricted()
        or not S.Public(UnitIsUnit(unit, "target")) or not S.Public(UnitIsUnit(unit, "mouseover")) then
        if missing and (not S.Public(value) or value and value ~= "") then
            name:SetText(value)
        end
        return
    end
    local expected = uf:ShouldShowName()
    if S.Public(expected) and type(expected) == "boolean" and (expected ~= shown or expected and missing) then
        securecallfunction(CompactUnitFrame_UpdateName, uf)
    end
end

-- On Forever the vertex tint can change while the visible glyphs stay white.
-- Capture and restore the font color, including its optional alpha.
local function PublicColor(r, g, b, a)
    if not (S.Finite(r) and S.Finite(g) and S.Finite(b)) then return end
    if not S.Public(a) or a ~= nil and not S.Finite(a) then return end
    return r, g, b, a
end

-- WoW includes UnitTreatAsPlayerForDisplay in its friendly-player CVar.
-- Correct only the native health component on an explicitly managed NPC.
-- Its own visibility rules still handle widgets-only units and game objects.
function Names.SyncNPCHealth(uf, kind, onlyName)
    local native = uf.showOnlyName
    if not S.Public(native) then return end
    local wanted = native == true and not onlyName and (kind == "neutralNpc"
        or kind == "friendlyNpc" and M.config.friendlyNPCs == private.Mode.SHOW)
    local bar = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local owned = npcHealthBars[uf]
    if not wanted and not owned then return end
    -- SetShowOnlyName also updates native Show/Hide and component state.
    if NS.InCombat() then
        M.pendingPlates[uf] = true
        return
    end
    if owned and (owned ~= bar or not wanted) then
        if not Writable(uf, owned) then return end
        if owned == bar and native == true then owned:SetShowOnlyName(true) end
        npcHealthBars[uf] = nil
    end
    if not wanted or not Writable(uf, bar) then return end
    local hidden = bar:IsShowOnlyName()
    if S.Public(hidden) and hidden == true then
        bar:SetShowOnlyName(false)
        npcHealthBars[uf] = bar
    end
end

-- Native font colors can be rounded to 8 bits. Compare the visible RGB to
-- the palette, never to an immediate readback that may still be native white.
local function SameRGB(r, g, b, red, green, blue)
    return r == red and g == green and b == blue
        or math.abs(r - red) < 1 / 255 and math.abs(g - green) < 1 / 255 and math.abs(b - blue) < 1 / 255
end

local function RestoreNameColor(uf, state)
    local label = state.label
    if not label then return true end
    if not Writable(uf, label) then return false end
    local r, g, b, a = PublicColor(label:GetTextColor())
    local vr, vg, vb, va
    if state.vertexR then vr, vg, vb, va = PublicColor(label:GetVertexColor()) end
    -- Some clients expose RGB only. A public alpha received directly by a
    -- setter still belongs to that same channel, including an omitted alpha.
    if a == nil then a = state.fontAlpha end
    if va == nil then va = state.vertexAlpha end
    state.writingColor = true
    if vr and SameRGB(vr, vg, vb, 1, 1, 1) and not SameRGB(state.vertexR, state.vertexG, state.vertexB, 1, 1, 1) then
        label:SetVertexColor(state.vertexR, state.vertexG, state.vertexB, va)
    end
    if r and SameRGB(r, g, b, state.appliedR, state.appliedG, state.appliedB)
        and not SameRGB(r, g, b, state.beforeR, state.beforeG, state.beforeB) then
        label:SetTextColor(state.beforeR, state.beforeG, state.beforeB, a)
    end
    state.label, state.deferredLabel, state.writingColor = nil, nil, nil
    state.vertexR, state.vertexG, state.vertexB = nil, nil, nil
    state.fontAlpha, state.vertexAlpha = nil, nil
    return true
end

function Names.RestoreNameOnly(uf)
    local state = onlyNames[uf]
    if not state then return end
    if state.scope and private.Layout and private.Layout.InvalidateName then private.Layout.InvalidateName(uf) end
    local hadColor = state.colorR ~= nil
    state.scope, state.questText, state.colorR, state.retryColor, state.revision = nil, nil, nil, nil, nil
    state.nativeTintDirty = nil
    local restored = RestoreNameColor(uf, state)
    if not restored then state.deferredLabel = state.label end
    if hadColor and private.NameText then private.NameText.ColorOwnerChanged(uf, false) end
    for region, alpha in pairs(state.alphas) do
        if Writable(uf, region) then
            local current = region:GetAlpha()
            if S.Finite(current) and current == 0 then region:SetAlpha(alpha) end
            state.alphas[region] = nil
        else
            restored = false
        end
    end
    if restored then onlyNames[uf] = nil end
end

local function HideRegion(uf, state, region)
    if not Writable(uf, region) then return end
    local alpha = region:GetAlpha()
    if S.Finite(alpha) and alpha ~= 0 then
        state.alphas[region] = alpha
        region:SetAlpha(0)
    end
end

local function ResolveDisplay(kind, unit)
    local scope = X.OpacityScope(kind)
    if scope == "neutral" and Names.neutralSplit then
        local exists = UnitExists(unit)
        if not S.Public(exists) or exists ~= true then return end
        local attackable = UnitCanAttack("player", unit)
        if not S.Public(attackable) or not X.CustomNameOnly(M.config, scope, attackable) then return end
        if attackable == false then return scope, true end
        local fighting = UnitAffectingCombat(unit)
        if S.Public(fighting) and fighting == false then return scope end
        return
    end
    if scope and X.CustomNameOnly(M.config, scope) then return scope end
end

local OnBarColor
local function NativeBarRGB(state, r, g, b)
    -- A pooled bar starts white, and Blizzard can also give a priest trainer
    -- the white player-class bar. An explicit Friendly NPC swatch (including
    -- white) is resolved before the native bar is consulted.
    if r == 1 and g == 1 and b == 1 and state.scope == "friendlyNpc" and Names.friendlyPaletteEnabled then
        return friendlyR, friendlyG, friendlyB
    end
    return r, g, b
end

local function NameOnlyRGB(uf, state)
    local config = M.config
    local player, scope, unit = state.player, state.scope, state.unit
    if player == true and scope == "enemy" and config.enemyPlateNameClassColor then
        local _, class = UnitClass(unit)
        local color = S.Public(class) and type(class) == "string" and RAID_CLASS_COLORS[class]
        if color then return color.r, color.g, color.b end
        return nil, nil, nil, true
    end
    if player then return end
    local typeColor = config[scope .. "PlateNameTypeColor"]
    if typeColor and scope == "friendlyNpc" and (friendlyOverride or S.Public(uf.isPlayer) and uf.isPlayer == true) then
        return friendlyR, friendlyG, friendlyB
    end
    if state.barHex then return NS.RGB(state.barHex) end
    if typeColor and scope == "neutral" and config.enemyNeutralEnabled ~= false and config.enemyNeutralColor then
        return NS.RGB(config.enemyNeutralColor)
    end
    if typeColor and scope == "enemy" and state.role and config["enemy" .. state.role .. "Enabled"] ~= false then
        local r, g, b = X.NameOnlyNPCColor(config, scope, state.role)
        if r then return r, g, b end
    end
    -- A hidden StatusBar retains its native color. The role overlay, when
    -- present, was resolved by the same function used to draw the visible fill.
    local bar = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar or uf.healthBar
    if Safe(bar) and bar.GetStatusBarColor then
        state.bar = bar
        if Writable(uf, bar) then
            if bar.SetStatusBarColor and barOwners[bar] ~= uf then
                if not barOwners[bar] then hooksecurefunc(bar, "SetStatusBarColor", OnBarColor) end
                barOwners[bar] = uf
            end
            local r, g, b = bar:GetStatusBarColor()
            if S.Finite(r) and S.Finite(g) and S.Finite(b) then
                r, g, b = NativeBarRGB(state, r, g, b)
                return r, g, b, nil, true
            end
        else
            state.retryBar = true
        end
    end
    if not typeColor then return nil, nil, nil, nil, true end
    if scope == "friendlyNpc" then return friendlyR, friendlyG, friendlyB, nil, true end
    local r, g, b = X.NameOnlyNPCColor(config, scope, state.role)
    if not r then r, g, b = UnitSelectionColor(unit) end
    if S.Finite(r) and S.Finite(g) and S.Finite(b) then return r, g, b, nil, true end
    return nil, nil, nil, nil, true
end

local function ResolveNameColor(uf, state)
    local hadColor = state.colorR ~= nil
    state.bar, state.retryBar = nil, nil
    state.colorR, state.colorG, state.colorB, state.retryColor, state.followsBar = NameOnlyRGB(uf, state)
    if hadColor ~= (state.colorR ~= nil) and private.NameText then
        private.NameText.ColorOwnerChanged(uf, state.colorR ~= nil)
    end
end

local function NPCColorOwner(label)
    local uf = labelOwners[label]
    local state = uf and onlyNames[uf]
    if not M.active or not state or state.writingColor or state.player ~= false or not state.scope or not state.colorR
        or not Safe(uf) or uf.name ~= label then return end
    return uf, state
end

-- CompactUnitFrame_UpdateName writes the vertex RGB after setting the name.
-- A vertex write can replace the visible tint while GetTextColor still
-- reports our previous value. The setter arguments identify that change.
local function OnNativeTint(label, r, g, b, a)
    local uf, state = NPCColorOwner(label)
    if not state then return end
    if not PublicColor(r, g, b, a) then return end
    if state.label == label then state.beforeR, state.beforeG, state.beforeB, state.fontAlpha = r, g, b, a end
    ApplyNameColor(uf, state, false, "font", r, g, b, a)
end

local function OnVertexColor(label, r, g, b, a)
    local uf, state = NPCColorOwner(label)
    if not state or not PublicColor(r, g, b, a) then return end
    if state.label == label then state.vertexR, state.vertexG, state.vertexB, state.vertexAlpha = r, g, b, a end
    -- The native setter can change the visible glyph even when the font
    -- getter still reports our swatch. Keep its opacity in the vertex channel.
    ApplyNameColor(uf, state, not SameRGB(r, g, b, state.colorR, state.colorG, state.colorB), "vertex", r, g, b, a)
end

local function OnFontObject(label)
    local uf, state = NPCColorOwner(label)
    if state then ApplyNameColor(uf, state, true, "fontObject") end
end

function ApplyNameColor(uf, state, nativeChange, channel, r, g, b, a)
    local label = uf.name
    if nativeChange then state.nativeTintDirty = true end
    if state.label and (state.label ~= label or state.deferredLabel) and not RestoreNameColor(uf, state) then return end
    if not Writable(uf, label) then return end
    -- Install before the first font read. A new plate can withhold that
    -- read until another owner sets its initial (often white) font color.
    if state.player == false and labelOwners[label] ~= uf then
        if not labelOwners[label] then
            hooksecurefunc(label, "SetVertexColor", OnVertexColor)
            hooksecurefunc(label, "SetTextColor", OnNativeTint)
            hooksecurefunc(label, "SetFontObject", OnFontObject)
        end
        labelOwners[label] = uf
    end
    local vr, vg, vb, va
    if channel == "vertex" then
        vr, vg, vb, va = r, g, b, a
    elseif state.player == false then
        vr, vg, vb, va = PublicColor(label:GetVertexColor())
        if not vr then return end
    end
    if channel ~= "font" then
        r, g, b, a = PublicColor(label:GetTextColor())
    end
    if not r then return end
    if state.label == label then
        if a == nil and channel ~= "font" then a = state.fontAlpha end
        if va == nil and channel ~= "vertex" then va = state.vertexAlpha end
    end
    state.fontAlpha, state.vertexAlpha = a, va
    -- Native selection may already have run before this pooled label was
    -- claimed. Establish its visible color once, even on a matching readback.
    local neutralize = vr and not SameRGB(vr, vg, vb, 1, 1, 1)
    local force = state.nativeTintDirty or neutralize or state.player == false and label ~= state.label
    if channel == "fontObject" or label ~= state.label or not SameRGB(r, g, b, state.appliedR, state.appliedG, state.appliedB) then
        -- Keep the native baseline across a palette change on the same label.
        -- An external color becomes the new baseline when we paint over it.
        state.beforeR, state.beforeG, state.beforeB = r, g, b
    end
    state.label = label
    state.appliedR, state.appliedG, state.appliedB = state.colorR, state.colorG, state.colorB
    if force or not SameRGB(r, g, b, state.colorR, state.colorG, state.colorB) then
        state.writingColor = true
        if neutralize then
            state.vertexR, state.vertexG, state.vertexB = vr, vg, vb
            label:SetVertexColor(1, 1, 1, va)
        end
        label:SetTextColor(state.colorR, state.colorG, state.colorB, a)
        state.writingColor, state.nativeTintDirty = nil, nil
    end
end

-- UpdateIsTarget calls this component only for the old and new target.
-- Run after native target presentation regardless of event listener order.
local function OnBarTarget(bar)
    local uf = targetBars[bar]
    local state = uf and onlyNames[uf]
    if M.active and state and state.targetBar == bar and state.scope and state.player == false and Safe(uf)
        and uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar == bar then
        Names.PaintNameOnly(uf, true)
    end
end

function Names.ApplyNameOnly(uf, unit, role, barHex, kind)
    local scope, questText, player
    if Names.nameOnlyEnabled and S.Public(unit) and type(unit) == "string" then
        kind = kind or X.UnitKind(uf, unit)
        player = kind == "friendlyPlayer" or kind == "enemyPlayer"
        scope, questText = ResolveDisplay(kind, unit)
    end
    if not scope then
        Names.RestoreNameOnly(uf)
        return false
    end
    local state = onlyNames[uf]
    if not state then
        state = { alphas = {} }
        onlyNames[uf] = state
    end
    if state.label and (state.unit ~= unit or state.player ~= player) and not RestoreNameColor(uf, state) then
        state.deferredLabel = state.label
    end
    if state.scope ~= scope and private.Layout and private.Layout.InvalidateName then private.Layout.InvalidateName(uf) end
    if state.scope ~= scope or state.unit ~= unit or state.player ~= player or state.role ~= role or state.barHex ~= barHex
        or state.revision ~= colorRevision or state.retryColor or state.retryBar
        or state.followsBar and state.bar ~= (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar or uf.healthBar) then
        state.scope, state.unit, state.player, state.role, state.revision = scope, unit, player, role, colorRevision
        state.barHex = barHex
        ResolveNameColor(uf, state)
    end
    state.questText = questText
    if player == false and state.colorR then ApplyNameColor(uf, state) end
    local bar = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if player == false and bar and bar ~= state.targetBar and Safe(bar) and bar.SetIsTarget then
        local access = true
        if bar.CanBeAccessedInContext then access = bar:CanBeAccessedInContext() end
        if S.Public(access) and access == true then
            if not targetBars[bar] then hooksecurefunc(bar, "SetIsTarget", OnBarTarget) end
            targetBars[bar], state.targetBar = uf, bar
        elseif NS.InCombat() then
            M.pendingPlates[uf] = true
        end
    end
    for _, field in ipairs(visualFields) do HideRegion(uf, state, uf[field]) end
    if not state.colorR then RestoreNameColor(uf, state) end
    return true, player
end

function Names.NameOnlyScope(uf)
    local state = onlyNames[uf]
    return state and state.scope
end

function Names.IsNameOnly(uf) return Names.NameOnlyScope(uf) ~= nil end

function Names.KeepsQuestText(uf)
    local state = onlyNames[uf]
    return state and state.questText
end

function Names.NeutralDisplayChanged(uf, unit, kind)
    kind = kind or X.UnitKind(uf, unit)
    local player = kind == "friendlyPlayer" or kind == "enemyPlayer"
    local scope, questText = ResolveDisplay(kind, unit)
    local state = onlyNames[uf]
    return scope ~= (state and state.scope) or questText ~= (state and state.questText)
        or scope ~= nil and state.player ~= player
end

function Names.OwnsColor(uf)
    local state = onlyNames[uf]
    return state and state.colorR ~= nil
end

function Names.PaintNameOnly(uf, selectionChanged)
    local state = onlyNames[uf]
    if not state then return end
    if selectionChanged and state.followsBar then ResolveNameColor(uf, state) end
    if state.colorR then ApplyNameColor(uf, state, selectionChanged and state.player == false) end
end

function Names.RefreshRole(uf, role, barHex)
    local state = onlyNames[uf]
    if not state or not state.scope then return false end
    if state.player == false and (state.role ~= role or state.barHex ~= barHex) then
        state.role, state.barHex = role, barHex
        ResolveNameColor(uf, state)
        if state.colorR then ApplyNameColor(uf, state) else RestoreNameColor(uf, state) end
    end
    return true
end

-- Blizzard calls the bar setter only when its RGB changes. Health value
-- updates, unchanged colors and other unit frames never enter this callback.
function OnBarColor(bar, r, g, b)
    local uf = barOwners[bar]
    local state = onlyNames[uf]
    if not state or state.bar ~= bar or not state.scope or not state.followsBar or not M.active or not Safe(uf) then return end
    if not (S.Finite(r) and S.Finite(g) and S.Finite(b)) then return end
    r, g, b = NativeBarRGB(state, r, g, b)
    if state.label and state.colorR == r and state.colorG == g and state.colorB == b then return end
    local acquired = state.colorR == nil
    state.colorR, state.colorG, state.colorB = r, g, b
    if acquired and private.NameText then private.NameText.ColorOwnerChanged(uf, true) end
    ApplyNameColor(uf, state)
end

function Names.RefreshFriendlyPalette(repaint)
    local config = M.config
    Names.friendlyPaletteEnabled = X.CustomNameOnly(config, "friendlyNpc") and config.friendlyNpcPlateNameTypeColor
    if not Names.friendlyPaletteEnabled then return end
    local r, g, b, override = X.NameOnlyNPCColor(config, "friendlyNpc")
    if r == friendlyR and g == friendlyG and b == friendlyB and override == friendlyOverride then return end
    friendlyR, friendlyG, friendlyB, friendlyOverride = r, g, b, override
    if repaint then
        for uf, state in pairs(onlyNames) do
            if state.scope == "friendlyNpc" then
                ResolveNameColor(uf, state)
                if state.colorR then ApplyNameColor(uf, state) end
            end
        end
    end
end

function Names.ConfigureNameOnly()
    local config = M.config
    colorRevision = colorRevision + 1
    Names.neutralNameOnly = config.neutralPlateNameOnly == true
    Names.neutralSplit = X.NeutralNameSplit(config)
    Names.nameOnlyEnabled = config.enemyPlateNameOnly or Names.neutralNameOnly or X.CustomNameOnly(config, "friendlyNpc")
    Names.friendlyPlayerNames = config.friendlyNamesOnly == private.Mode.ALL_NAMES_ONLY or config.friendlyNamesOnly == GROUP_NAMES_ONLY
    local styled = config.look ~= private.Mode.LOOK_BLIZZARD
    local enemy = styled and config.enemy and config.enemyNameVisible ~= false
    local friendly = styled and config.friendly and config.friendlyNameVisible ~= false
    barNameKinds.enemyNpc = enemy and config.enemySkinEnabled ~= false
    barNameKinds.enemyPlayer = barNameKinds.enemyNpc
    barNameKinds.neutralNpc = enemy and config.neutralSkinEnabled ~= false
    barNameKinds.friendlyPlayer = friendly and config.friendlySkinEnabled ~= false
    barNameKinds.friendlyNpc = friendly and config.friendlyNpcSkinEnabled ~= false
        and config.friendlyNPCs ~= private.Mode.NPC_NAMES_ONLY and config.friendlyNPCs ~= private.Mode.HIDE
    local repair = Names.repairKinds
    repair.enemyNpc = config.enemyPlateNameOnly or barNameKinds.enemyNpc
    repair.enemyPlayer = repair.enemyNpc
    repair.friendlyNpc = X.CustomNameOnly(config, "friendlyNpc") or barNameKinds.friendlyNpc
    repair.neutralNpc = Names.neutralNameOnly or barNameKinds.neutralNpc
    repair.friendlyPlayer = Names.friendlyPlayerNames or barNameKinds.friendlyPlayer
    Names.managedNames = repair.enemyNpc or repair.neutralNpc or repair.friendlyPlayer or repair.friendlyNpc
    Names.typeColorInUse = config.enemyPlateNameOnly and config.enemyPlateNameTypeColor
    Names.RefreshFriendlyPalette()
    if not Names.nameOnlyEnabled then
        for uf in pairs(onlyNames) do Names.RestoreNameOnly(uf) end
    elseif not nameHooked then
        hooksecurefunc("CompactUnitFrame_UpdateName", function(uf)
            local state = onlyNames[uf]
            if not M.active or not state then return end
            if state.retryColor then ResolveNameColor(uf, state) end
            if state.colorR then ApplyNameColor(uf, state) end
        end)
        nameHooked = true
    end
end
