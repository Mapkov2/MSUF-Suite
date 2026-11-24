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

-- Blizzard's UpdateShowOnlyName: a friendly unit displayed like a player (UnitTreatAsPlayerForDisplay)
-- gets a name-only plate while the friendly-player names-only CVar is on. The driver can set
-- uf.showOnlyName after our paint (handler order varies), so an unset field is read from the unit.
local function NativeNameOnly(uf, unit)
    local native = uf.showOnlyName
    if npcHealthBars[uf] or not S.Public(native) then return false end
    if native ~= nil then return native == true end
    local display = UnitTreatAsPlayerForDisplay and UnitTreatAsPlayerForDisplay(unit)
    if not S.Public(display) or display ~= true then return false end
    local friend = UnitIsFriend("player", unit)
    return S.Public(friend) and friend == true and C_CVar.GetCVarBool("nameplateShowOnlyNameForFriendlyPlayerUnits") == true
end

-- WoW includes UnitTreatAsPlayerForDisplay in its friendly-player CVar.
-- Correct only the native health component on an explicitly managed NPC.
-- Its own visibility rules still handle widgets-only units and game objects.
local function SyncHealth(uf, kind, onlyName)
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

local nativeHooked
-- After Blizzard's UpdateShowOnlyName (unit setup, faction, CVar): a color-only NPC that lost its
-- name-only plate gives its name color back, whatever kind the Suite has recorded for it.
local function OnNativeNames(uf)
    local state = onlyNames[uf]
    if state and state.colorOnly and state.scope and not NativeNameOnly(uf, state.unit) then Names.RestoreNameOnly(uf) end
end

-- Skin.Paint and Blizzard's UpdateShowOnlyName (Skin.lua hook) both call this for a Friendly NPC on
-- a name-only plate, in whichever order the driver and the Suite set the plate up. Without a Name
-- only display (nameOnlyEnabled) this is its only entry: no other plate pays for it.
function Names.SyncNPCHealth(uf, kind, onlyName)
    SyncHealth(uf, kind, onlyName)
    local unit = uf.unit
    if kind == "friendlyNpc" and Names.nativeNpcNames and M.active and S.Public(unit) and type(unit) == "string" then
        Names.ApplyNameOnly(uf, unit, nil, nil, kind)
    end
end

-- Native font colors can be rounded to 8 bits. Compare the visible RGB to
-- the palette, never to an immediate readback that may still be native white.
local function SameRGB(r, g, b, red, green, blue)
    return r == red and g == green and b == blue
        or math.abs(r - red) < 1 / 255 and math.abs(g - green) < 1 / 255 and math.abs(b - blue) < 1 / 255
end

-- On a FontString both color setters also reach its alpha aspect. A name color is written the way
-- CompactUnitFrame_UpdateName writes one: RGB only, never an alpha (a read-back one can be a fade's 0).

local function RestoreNameColor(uf, state)
    local label = state.label
    if not label then return true end
    if not Writable(uf, label) then return false end
    local r, g, b, a = PublicColor(label:GetTextColor())
    local npc = state.tintsVertex
    local vr, vg, vb
    if npc then vr, vg, vb = PublicColor(label:GetVertexColor()) end
    local ar, ag, ab = state.appliedR, state.appliedG, state.appliedB
    state.writingColor = true
    -- A channel still showing our color (or withheld) returns to its native value: Blizzard's
    -- last vertex write, else its plain white. A later native write is left alone.
    if npc and (not vr or ar and SameRGB(vr, vg, vb, ar, ag, ab)) then
        label:SetVertexColor(state.vertexR or 1, state.vertexG or 1, state.vertexB or 1)
    end
    local br, bg, bb = state.beforeR or 1, state.beforeG or 1, state.beforeB or 1
    if npc and not r or r and ar and SameRGB(r, g, b, ar, ag, ab) and not SameRGB(r, g, b, br, bg, bb) then
        label:SetTextColor(br, bg, bb)
    end
    state.label, state.deferredLabel, state.writingColor, state.tintsVertex = nil, nil, nil, nil
    state.vertexR, state.vertexG, state.vertexB = nil, nil, nil
    state.beforeR, state.beforeG, state.beforeB = nil, nil, nil
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

local function ResolveDisplay(kind, unit, uf)
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
    -- Blizzard's friendly-player rules show such an NPC by name only, in a player class color. Unless
    -- Show forces its bar, that native plate stays as it is and takes just its NPC color.
    if kind == "friendlyNpc" and Names.nativeNpcNames and uf and NativeNameOnly(uf, unit) then
        return scope, nil, true
    end
end

local OnBarColor
local function NativeBarRGB(state, r, g, b)
    -- A pooled bar starts white, and Blizzard can also give a priest trainer
    -- the white player-class bar. An explicit Friendly NPC swatch (including
    -- white) is resolved before the native bar is consulted.
    if r == 1 and g == 1 and b == 1 and state.fallbackR then
        return state.fallbackR, state.fallbackG, state.fallbackB
    end
    return r, g, b
end

-- Friendly and neutral NPC names never take the hidden bar's RGB: Blizzard paints NPCs it shows
-- like players in their class color (a white priest, a pink paladin), and a pooled or Suite-painted
-- bar can still hold white. The name takes the NPC's own colors instead: grey when dead or tapped
-- (CompactUnitFrame_UpdateName), the Friendly NPC palette with color by type, else its reaction.
local function ReactionRGB(scope, unit, typeColor)
    local dead, denied = UnitIsDead(unit), UnitIsTapDenied(unit)
    if not (S.Public(dead) and S.Public(denied)) then return nil, nil, nil, true end
    if dead or denied then return .5, .5, .5 end
    if typeColor and scope == "friendlyNpc" and Names.friendlyPaletteEnabled then return friendlyR, friendlyG, friendlyB end
    local reaction = UnitReaction(unit, "player")
    if not S.Finite(reaction) then return nil, nil, nil, true end
    if reaction >= 5 then return 0, 1, 0 end
    if reaction == 4 then return 1, 1, 0 end
    return 1, 0, 0
end

local function StateReactionRGB(state)
    return ReactionRGB(state.scope, state.unit, M.config[state.scope .. "PlateNameTypeColor"] and not state.colorOnly)
end

-- Blizzard writes the bar only when its color changes (death, tapping, reaction, threat).
local function WatchBar(uf, state)
    local bar = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar or uf.healthBar
    if not (Safe(bar) and bar.GetStatusBarColor) then return end
    state.bar = bar
    if not Writable(uf, bar) then
        state.retryBar = true
        return
    end
    if bar.SetStatusBarColor and barOwners[bar] ~= uf then
        if not barOwners[bar] then hooksecurefunc(bar, "SetStatusBarColor", OnBarColor) end
        barOwners[bar] = uf
    end
    return bar
end

local function NameOnlyRGB(uf, state)
    local config = M.config
    local player, scope, unit = state.player, state.scope, state.unit
    local names = private.NameText
    local custom, explicit
    if names and names.CustomNameColor then custom, explicit = names.CustomNameColor(scope) end
    if explicit then return custom.r, custom.g, custom.b end
    if player == true and scope == "enemy" and config.enemyPlateNameClassColor then
        local _, class = UnitClass(unit)
        local color = S.Public(class) and type(class) == "string" and RAID_CLASS_COLORS[class]
        if color then return color.r, color.g, color.b end
        return nil, nil, nil, true
    end
    if player then return end
    local typeColor = config[scope .. "PlateNameTypeColor"] and not state.colorOnly
    if not typeColor and custom then return custom.r, custom.g, custom.b end
    if typeColor and scope == "friendlyNpc" and (friendlyOverride or S.Public(uf.isPlayer) and uf.isPlayer == true) then
        return friendlyR, friendlyG, friendlyB
    end
    if state.barHex then return NS.RGB(state.barHex) end
    if typeColor and scope == "neutral" and config.enemyNeutralEnabled ~= false and config.enemyNeutralColor then
        return NS.RGB(config.enemyNeutralColor)
    end
    if scope ~= "enemy" then
        WatchBar(uf, state)
        state.reaction = true
        local r, g, b, retry = ReactionRGB(scope, unit, typeColor)
        return r, g, b, retry, true
    end
    if typeColor and state.role and config["enemy" .. state.role .. "Enabled"] ~= false then
        local r, g, b = X.NameOnlyNPCColor(config, scope, state.role)
        if r then return r, g, b end
    end
    if typeColor then
        local r, g, b = UnitSelectionColor(unit)
        if S.Finite(r) and S.Finite(g) and S.Finite(b) then
            state.fallbackR, state.fallbackG, state.fallbackB = r, g, b
        end
    end
    -- A hidden enemy StatusBar retains its native color, including threat. The role overlay,
    -- when present, was resolved by the same function used to draw the visible fill.
    local bar = WatchBar(uf, state)
    if bar then
        local r, g, b = bar:GetStatusBarColor()
        if S.Finite(r) and S.Finite(g) and S.Finite(b) then
            r, g, b = NativeBarRGB(state, r, g, b)
            return r, g, b, nil, true
        end
    end
    if typeColor then
        local r, g, b = X.NameOnlyNPCColor(config, scope, state.role)
        if S.Finite(r) and S.Finite(g) and S.Finite(b) then return r, g, b, nil, true end
    end
    return state.fallbackR, state.fallbackG, state.fallbackB, nil, true
end

local function ResolveNameColor(uf, state)
    local hadColor = state.colorR ~= nil
    state.bar, state.retryBar = nil, nil
    state.fallbackR, state.fallbackG, state.fallbackB, state.reaction = nil, nil, nil, nil
    state.colorR, state.colorG, state.colorB, state.retryColor, state.followsBar = NameOnlyRGB(uf, state)
    if hadColor ~= (state.colorR ~= nil) and private.NameText then
        private.NameText.ColorOwnerChanged(uf, state.colorR ~= nil)
    end
end

-- Death, tapping and faction can change while the bar stays hidden. Each native repaint of the
-- name re-reads them, so a reaction color never goes stale and a withheld one resolves.
local function FollowReaction(uf, state)
    if state.retryColor then return ResolveNameColor(uf, state) end
    if not state.reaction then return end
    local r, g, b = StateReactionRGB(state)
    if r then state.colorR, state.colorG, state.colorB = r, g, b end
end

local function NPCColorOwner(label)
    local uf = labelOwners[label]
    local state = uf and onlyNames[uf]
    if not M.active or not state or state.writingColor or state.player ~= false or not state.scope
        or not Safe(uf) or uf.name ~= label then return end
    FollowReaction(uf, state)
    if state.colorR then return uf, state end
end

-- CompactUnitFrame_UpdateName writes the vertex RGB after setting the name.
-- A vertex write can replace the visible tint while GetTextColor still
-- reports our previous value. The setter arguments identify that change.
local function OnNativeTint(label, r, g, b, a)
    local uf, state = NPCColorOwner(label)
    if not state then return end
    if not PublicColor(r, g, b, a) then return end
    if state.label == label then state.beforeR, state.beforeG, state.beforeB = r, g, b end
    ApplyNameColor(uf, state, false, "font", r, g, b, a)
end

local function OnVertexColor(label, r, g, b, a)
    local uf, state = NPCColorOwner(label)
    if not state or not PublicColor(r, g, b, a) then return end
    if state.label == label then state.vertexR, state.vertexG, state.vertexB = r, g, b end
    -- The native setter can change the visible glyph even when the font
    -- getter still reports our swatch.
    ApplyNameColor(uf, state, not SameRGB(r, g, b, state.colorR, state.colorG, state.colorB), "vertex", r, g, b, a)
end

local function OnFontObject(label)
    local uf, state = NPCColorOwner(label)
    if state then ApplyNameColor(uf, state, true, "fontObject") end
end

-- Install before the first font read. A new plate can withhold that read until another owner sets
-- its initial (often white) font color. A color-only plate has no global name hook: these follow it.
local function ClaimLabel(uf, label)
    if labelOwners[label] == uf then return end
    if not labelOwners[label] then
        hooksecurefunc(label, "SetVertexColor", OnVertexColor)
        hooksecurefunc(label, "SetTextColor", OnNativeTint)
        hooksecurefunc(label, "SetFontObject", OnFontObject)
    end
    labelOwners[label] = uf
end

-- Clients differ in how a FontString's vertex and text colors combine, and its color getters can be
-- withheld. Blizzard colors names through the vertex and never through the text color, so an NPC name
-- takes its color in both channels. It is written on a new label even when the getters are withheld,
-- and again after every native write; a withheld readback alone keeps our last write.
function ApplyNameColor(uf, state, nativeChange, channel, r, g, b, a)
    local label = uf.name
    if nativeChange then state.nativeTintDirty = true end
    if state.label and (state.label ~= label or state.deferredLabel) and not RestoreNameColor(uf, state) then return end
    if not Writable(uf, label) then return end
    local npc = state.player == false
    if npc then ClaimLabel(uf, label) end
    local vr, vg, vb
    if channel == "vertex" then
        vr, vg, vb = r, g, b
    elseif npc then
        vr, vg, vb = PublicColor(label:GetVertexColor())
    end
    if channel ~= "font" then
        r, g, b, a = PublicColor(label:GetTextColor())
    end
    if not r and not npc then return end
    local fresh = label ~= state.label
    local cr, cg, cb = state.colorR, state.colorG, state.colorB
    local ar, ag, ab = state.appliedR, state.appliedG, state.appliedB
    -- Keep the native baselines across a palette change on the same label.
    -- An external color becomes the new baseline when we paint over it.
    if r and (channel == "fontObject" or fresh or not SameRGB(r, g, b, ar, ag, ab)) then
        state.beforeR, state.beforeG, state.beforeB = r, g, b
    end
    if npc and vr and (fresh or not SameRGB(vr, vg, vb, ar, ag, ab)) then
        state.vertexR, state.vertexG, state.vertexB = vr, vg, vb
    end
    state.label, state.tintsVertex = label, npc or nil
    state.appliedR, state.appliedG, state.appliedB = cr, cg, cb
    if state.nativeTintDirty or npc and (fresh or vr and not SameRGB(vr, vg, vb, cr, cg, cb))
        or r and not SameRGB(r, g, b, cr, cg, cb) then
        state.writingColor = true
        if npc then label:SetVertexColor(cr, cg, cb) end
        label:SetTextColor(cr, cg, cb)
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
    local scope, questText, player, colorOnly
    if (Names.nameOnlyEnabled or Names.nativeNpcNames) and S.Public(unit) and type(unit) == "string" then
        kind = kind or X.UnitKind(uf, unit)
        player = kind == "friendlyPlayer" or kind == "enemyPlayer"
        scope, questText, colorOnly = ResolveDisplay(kind, unit, uf)
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
        or state.revision ~= colorRevision or state.retryColor or state.retryBar or state.colorOnly ~= colorOnly
        or state.followsBar and state.bar ~= (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar or uf.healthBar) then
        state.scope, state.unit, state.player, state.role, state.revision = scope, unit, player, role, colorRevision
        state.barHex, state.colorOnly = barHex, colorOnly
        ResolveNameColor(uf, state)
    end
    state.questText = questText
    if player == false and state.colorR then
        ApplyNameColor(uf, state)
    elseif player == false and state.retryColor and Writable(uf, uf.name) then
        ClaimLabel(uf, uf.name) -- an unreadable reaction resolves at the next native repaint
    end
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
    if not colorOnly then
        for _, field in ipairs(visualFields) do HideRegion(uf, state, uf[field]) end
    end
    if not state.colorR then RestoreNameColor(uf, state) end
    return not colorOnly, player
end

-- A color-only NPC keeps Blizzard's own name-only plate: no layout, region or role change.
function Names.NameOnlyScope(uf)
    local state = onlyNames[uf]
    if state and not state.colorOnly then return state.scope end
end

function Names.IsNameOnly(uf) return Names.NameOnlyScope(uf) ~= nil end

function Names.KeepsQuestText(uf)
    local state = onlyNames[uf]
    return state and state.questText
end

function Names.NeutralDisplayChanged(uf, unit, kind)
    kind = kind or X.UnitKind(uf, unit)
    local player = kind == "friendlyPlayer" or kind == "enemyPlayer"
    local scope, questText, colorOnly = ResolveDisplay(kind, unit, uf)
    local state = onlyNames[uf]
    return scope ~= (state and state.scope) or questText ~= (state and state.questText)
        or scope ~= nil and (state.player ~= player or state.colorOnly ~= colorOnly)
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
    return not state.colorOnly
end

-- Blizzard calls the bar setter only when its RGB changes. Health value
-- updates, unchanged colors and other unit frames never enter this callback.
function OnBarColor(bar, r, g, b)
    local uf = barOwners[bar]
    local state = onlyNames[uf]
    if not state or state.bar ~= bar or not state.scope or not state.followsBar or not M.active or not Safe(uf) then return end
    if state.reaction then
        r, g, b = StateReactionRGB(state)
        if not r then return end
    elseif not (S.Finite(r) and S.Finite(g) and S.Finite(b)) then
        return
    else
        r, g, b = NativeBarRGB(state, r, g, b)
    end
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
    -- Show forces the bar of an NPC shown like a player (SyncHealth); Keep, Hide and world names leave
    -- it on Blizzard's name-only plate, which then takes the NPC color (SyncNPCHealth, label hooks).
    local friendlyNames = X.CustomNameOnly(config, "friendlyNpc")
    Names.nativeNpcNames = config.friendlyNpcSkinEnabled ~= false and config.friendlyNPCs ~= private.Mode.SHOW
        and not friendlyNames
    Names.nameOnlyEnabled = config.enemyPlateNameOnly or Names.neutralNameOnly or friendlyNames
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
    for uf, state in pairs(onlyNames) do
        if not (state.colorOnly and Names.nativeNpcNames or not state.colorOnly and Names.nameOnlyEnabled) then
            Names.RestoreNameOnly(uf)
        end
    end
    if Names.nativeNpcNames and not nativeHooked and private.HookPlates and NamePlateUnitFrameMixin
        and NamePlateUnitFrameMixin.UpdateShowOnlyName then
        private.HookPlates("UpdateShowOnlyName", OnNativeNames)
        nativeHooked = true
    end
    if Names.nameOnlyEnabled and not nameHooked then
        hooksecurefunc("CompactUnitFrame_UpdateName", function(uf)
            local state = onlyNames[uf]
            if not M.active or not state then return end
            if state.retryColor then ResolveNameColor(uf, state) end
            if state.colorR then ApplyNameColor(uf, state) end
        end)
        nameHooked = true
    end
end
