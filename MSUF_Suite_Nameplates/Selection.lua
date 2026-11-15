local _, private = ...
local NS = private.NS
local Style = NS.NameplateStyle
local Mode = private.Mode
local Roles = private.Roles
local KEEP, CUSTOM, HIDE, LOOK_BLIZZARD = Mode.KEEP, Mode.CUSTOMIZE, Mode.HIDE, Mode.LOOK_BLIZZARD
-- Blizzard's target / focus border (healthBar.selectedBorder) and the dimming
-- of every other plate (healthBar.deselectedOverlay).
-- NamePlateHealthBarMixin:UpdateSelectionBorder (Blizzard_NamePlateHealthBar.lua
-- :90-116 on live, ptr2 and forever) shows them on target and focus changes
-- and colors the border from NAMEPLATE_BORDER_*_COLOR. A post-hook repaints
-- only what the player chose; Blizzard keeps deciding what shows, and its
-- color globals are only read, never written.
-- inUse: a choice leaves Blizzard's look or a plate still carries one. The
-- plate pass (Skin.lua Paint) skips this module entirely otherwise.
local Selection = { inUse = false }
private.Selection = Selection

-- Styled regions and the native health backdrop opacity saved for restoration.
local plates = setmetatable({}, { __mode = "k" })
local badges = setmetatable({}, { __mode = "k" })
local hookedBadges = setmetatable({}, { __mode = "k" })
local border, dim, dimAlpha, targetRGB, focusRGB = KEEP, KEEP, 1, nil, nil
local active, hideAll, hideEnemyBackground, hideFriendlyBackground = false, false, false, false
local enemyOff, friendlyOff, nativeOff
local revision, hooked = 0, false
local original
local plan
local pending = setmetatable({}, { __mode = "k" })
local retryFrame
local owner

function Selection.Bind(module) owner = module end

local function RetryPlate(uf)
    if owner and uf and NS.IsCombatLocked() then owner.pendingPlates[uf] = true end
end

local function DeferRestore(health)
    pending[health] = true
    if not NS.IsCombatLocked() then return end
    if not retryFrame then
        retryFrame = CreateFrame("Frame")
        retryFrame:SetScript("OnEvent", function(frame)
            frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            for bar in pairs(pending) do Selection.Restore(bar) end
        end)
    end
    retryFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function Safe(region)
    return region and not NS.Safety.IsForbidden(region)
end

local function Writable(region)
    if not NS.Public(region) or not Safe(region) then return false end
    local allowed = region:CanBeAccessedInContext()
    return NS.Public(allowed) and allowed == true
end

-- Blizzard's own border color for the plate's state (Restore).
local function NativeColor(health, badge)
    local target, focus = health.isTarget, health.isFocus
    if badge then
        if NS.Public(target) and target == true then return NamePlateConstants.TARGET_BORDER_COLOR end
        if NS.Public(focus) and focus == true then return NamePlateConstants.FOCUS_TARGET_BORDER_COLOR end
        return
    end
    if NS.Public(target) and target == true then return NAMEPLATE_BORDER_TARGET_COLOR end
    if NS.Public(focus) and focus == true then return NAMEPLATE_BORDER_FOCUS_TARGET_COLOR end
end

-- isTarget / isFocus can be secret on restricted maps. Only a known focus
-- that is not known as the target takes the focus color.
local function CustomColor(health)
    local target, focus = health.isTarget, health.isFocus
    local isTarget = NS.Public(target) and target == true
    local isFocus = NS.Public(focus) and focus == true
    return (isFocus and not isTarget) and focusRGB or targetRGB
end

-- The textures stay anchored and Blizzard still owns their shown state.
local function HiddenAlpha(texture, originalAlpha, hide)
    if hide and originalAlpha == nil then
        local alpha = texture:GetAlpha()
        if NS.Finite(alpha) then
            texture:SetAlpha(0)
            return alpha
        end
        return nil, false
    elseif not hide and originalAlpha ~= nil then
        texture:SetAlpha(originalAlpha)
        return nil
    end
    return originalAlpha
end

local function PaintBorder(owner, state, colorOnly, badge)
    local frame = owner.selectedBorder
    if not NS.Public(frame) or frame and not Writable(frame) then return false end
    if not frame then return true end
    local applied
    if not colorOnly then
        state.border, applied = HiddenAlpha(frame, state.border, state.mode == HIDE or state.highlightSelection)
    end
    if state.mode == CUSTOM and not state.highlightSelection then
        local rgb = CustomColor(owner)
        frame:SetVertexColor(rgb[1], rgb[2], rgb[3])
        state.colored = true
    elseif state.colored then
        local color = NativeColor(owner, badge)
        if color then frame:SetVertexColor(color.r, color.g, color.b) end
        state.colored = nil
    end
    return applied ~= false
end

local function Paint(health, state, colorOnly)
    local painted = PaintBorder(health, state, colorOnly)
    if colorOnly then return end
    local mode = state.styled and dim or KEEP
    local overlay = health.deselectedOverlay
    if (mode ~= KEEP or state.dim) and overlay then
        if not Writable(overlay) then return false end
        local alpha = mode == HIDE and 0 or mode == CUSTOM and dimAlpha or 1
        if state.dim ~= alpha then
            overlay:SetAlpha(alpha)
            state.dim = alpha
        end
    end
    return painted
end

local function OnUpdateBadge(badge)
    local state = badges[badge]
    if state and state.mode == CUSTOM then PaintBorder(badge, state, true, true) end
end

local function RestoreBorder(owner, state, badge)
    if state.border == nil and not state.colored then return true end
    if not Safe(owner) then return false end
    local frame = owner.selectedBorder
    if not Writable(frame) then return false end
    state.border = HiddenAlpha(frame, state.border, false)
    if state.colored then
        local color = NativeColor(owner, badge)
        if color then frame:SetVertexColor(color.r, color.g, color.b) end
        state.colored = nil
    end
    return true
end

local function PaintBadge(state, badge)
    local mode = state.highlightSelection and HIDE or state.mode
    if mode == KEEP and not state.badge then return true end
    if state.badge and (state.badge ~= badge or mode == KEEP) then
        if not RestoreBorder(state.badge, badges[state.badge], true) then return false end
        badges[state.badge], state.badge = nil, nil
    end
    if mode == KEEP or not Safe(badge) or not Safe(badge.selectedBorder) then return true end
    local visual = badges[badge]
    if not visual then
        visual = {}
        badges[badge], state.badge = visual, badge
    end
    if mode == CUSTOM and not hookedBadges[badge] and badge.UpdateSelectionBorder then
        hooksecurefunc(badge, "UpdateSelectionBorder", OnUpdateBadge)
        hookedBadges[badge] = true
    end
    visual.mode = mode
    return PaintBorder(badge, visual, false, true)
end

-- Forever draws an oversized native backdrop on the bar; Classic uses the
-- Nameplate-Border texture there. Keep its anchors for the selection border.
local function PaintBackground(health, state, hide)
    local texture = health.bgTexture
    if not NS.Public(texture) then return false end
    if not texture then return true end
    if not Writable(texture) then return false end
    local alpha, applied = HiddenAlpha(texture, state.background, hide)
    state.background = alpha
    return applied ~= false
end

-- Asset restoration can reset the texture's alpha after the normal plate pass.
function Selection.RepaintBackground(health)
    local state = plates[health]
    if not state or not state.hideBackground or state.background == nil then return end
    local texture = health.bgTexture
    if Writable(texture) then texture:SetAlpha(0) end
end

local function PaintOutline(health, state)
    if not Safe(health) then return end
    local target, focus = health.isTarget, health.isFocus
    local publicTarget = NS.Public(target)
    local color, selected = Style.HighlightColor(plan, publicTarget and target == true,
        NS.Public(focus) and focus == true, state.aggro, state.mouseover)
    local visual = state.outline
    local size = color and plan.size or state.outlineSize
    local hex = color or state.outlineColor
    if visual.borderSize ~= size or size > 0 and visual.borderColor ~= hex then
        Style.PaintBorder(visual, health, size, hex)
    end
    local override = publicTarget and selected == true or nil
    if override ~= state.highlightSelection then
        state.highlightSelection = override
        local painted = PaintBorder(health, state, false)
        local badge = PaintBadge(state, state.levelBadge)
        if not painted or not badge then
            state.revision = nil
            RetryPlate(state.uf)
        end
    end
end

local function ReadAggro(unit)
    if not NS.Public(unit) or type(unit) ~= "string" then return false end
    local status = UnitThreatSituation("player", unit)
    if NS.Finite(status) then return status >= 2 end
    -- Solo fights can have a visible NPC target even without a threat result.
    if Roles.grouped then return false end
    local combat = UnitAffectingCombat(unit)
    if not NS.Public(combat) or combat ~= true then return false end
    local player = UnitIsPlayer(unit)
    if not NS.Public(player) or player ~= false then return false end
    local attacksPlayer = UnitIsUnit(unit .. "target", "player")
    return NS.Public(attacksPlayer) and attacksPlayer == true
end

function Selection.ThreatChanged(health, unit)
    if not Selection.aggroEnabled then return end
    local state = plates[health]
    if not state or not state.highlight or state.side ~= "enemy" then return end
    local aggro = ReadAggro(unit)
    if aggro == state.aggro then return end
    state.aggro = aggro
    PaintOutline(health, state)
end

function Selection.HighlightMouseover(uf, current)
    if not plan or not plan.mouseover or not Safe(uf) then return end
    local health = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if not NS.Public(health) then return end
    local state = health and plates[health]
    if not state or not state.highlight or state.mouseover == current or not Safe(health) then return end
    state.mouseover = current
    PaintOutline(health, state)
end

-- Runs after Blizzard updates the target or focus border. It also updates
-- the shared outline when the plate changes selection state.
local function OnUpdateSelection(health)
    local state = plates[health]
    if not state then return end
    if state.highlight and plan then PaintOutline(health, state) end
    if state.mode == CUSTOM and not state.highlightSelection then Paint(health, state, true) end
end

-- One hook per method and session (a secure hook cannot be removed), first
-- needed when a choice leaves Keep. Health bars made before it get their own.
local function Hook(health)
    if not hooked then
        original = NamePlateHealthBarMixin.UpdateSelectionBorder
        hooksecurefunc(NamePlateHealthBarMixin, "UpdateSelectionBorder", OnUpdateSelection)
        hooked = true
    end
    -- A hooked method is no longer the original: each frame is hooked once.
    if health.UpdateSelectionBorder == original then
        hooksecurefunc(health, "UpdateSelectionBorder", OnUpdateSelection)
    end
end

local function Restore(health, state)
    state.highlight, state.revision, state.hideBackground = nil, nil, false
    local restored = RestoreBorder(health, state)
    local overlay = health.deselectedOverlay
    if state.dim and state.dim ~= 1 then
        if Writable(overlay) then
            overlay:SetAlpha(1)
            state.dim = nil
        else
            restored = false
        end
    end
    if state.background ~= nil and not PaintBackground(health, state, false) then restored = false end
    local badge = state.badge
    if badge and RestoreBorder(badge, badges[badge], true) then
        badges[badge], state.badge = nil, nil
    elseif badge then
        restored = false
    end
    if not restored then
        DeferRestore(health)
        return
    end
    plates[health], pending[health] = nil, nil
    if not active and not hideAll and not enemyOff and not friendlyOff
        and not hideEnemyBackground and not hideFriendlyBackground and next(plates) == nil then
        Selection.inUse = false
    end
end

function Selection.Configure(config)
    local skin = config.look ~= LOOK_BLIZZARD
    border = skin and config.selectionBorder or KEEP
    dim = skin and config.selectionDim or KEEP
    dimAlpha = (config.selectionDimPercent or 50) / 100
    nativeOff = not skin and config.barsOverride == true
    enemyOff = (skin or nativeOff) and Style.OutlineOff(config, "enemy")
    friendlyOff = (skin or nativeOff) and Style.OutlineOff(config, "friendly")
    plan = skin and (not enemyOff or not friendlyOff) and Style.CompileHighlights(config) or nil
    Selection.highlights = plan ~= nil
    Selection.aggroEnabled = not enemyOff and config.enemy == true and plan and plan.aggro and true or false
    active = border ~= KEEP or dim ~= KEEP or plan ~= nil
    hideAll = config.hideHealthBarBorders == true
    hideEnemyBackground = skin and config.enemy and Style.HideNativeOutline(config, "enemy")
    hideFriendlyBackground = skin and config.friendly and Style.HideNativeOutline(config, "friendly")
    Selection.inUse = active or hideAll or enemyOff or friendlyOff or hideEnemyBackground or hideFriendlyBackground
        or next(plates) ~= nil
    -- Profiles saved before these settings existed have no colors yet.
    targetRGB = { NS.RGB(config.selectionTargetColor or "ffffff") }
    focusRGB = { NS.RGB(config.selectionFocusColor or "ff66ff") }
    revision = revision + 1
end

-- A plate pass (Skin.lua Paint, only while inUse) on a health bar it already
-- checked: styled is false for a plate whose side the skin leaves alone.
function Selection.Apply(health, styled, uf, prefix, outline, size, color)
    local state = plates[health]
    local sideBackground = prefix == "enemy" and hideEnemyBackground or prefix == "friendly" and hideFriendlyBackground
    local off = hideAll or (styled or nativeOff) and (prefix == "enemy" and enemyOff or prefix == "friendly" and friendlyOff)
    local textures = private.Textures
    local customBackground = textures and textures.healthBack
        and (not textures.HasHealthBackground or textures.HasHealthBackground(uf))
    local hideBackground = not customBackground and (off or styled and sideBackground)
    if not off and not (styled and (active or hideBackground)) then
        if state then Restore(health, state) end
        return
    end
    if not state then
        state = {}
        plates[health] = state
    end
    pending[health] = nil
    state.outline, state.outlineSize, state.outlineColor = outline, size, color
    -- A unit can change faction on an existing plate without a profile refresh.
    state.hideBackground = hideBackground
    if (hideBackground == true) ~= (state.background ~= nil) then
        if not PaintBackground(health, state, hideBackground) then RetryPlate(uf) end
    end
    if state.revision ~= revision or state.styled ~= styled or state.side ~= prefix then
        state.styled, state.side, state.uf = styled, prefix, uf
        state.mode = off and HIDE or border
        state.levelBadge = NS.Client.isForever and uf and uf.PlayerLevelDiffFrame
        state.highlight = not off and styled and outline ~= nil and plan ~= nil
        if state.mode == CUSTOM or state.highlight and (plan.target or plan.focus) then Hook(health) end
        if state.highlight then
            state.mouseover = plan.mouseover and uf and private.Mouseover.IsHovered(uf)
            state.aggro = Selection.aggroEnabled and prefix == "enemy" and uf and ReadAggro(uf.unit)
        else
            state.highlightSelection = nil
        end
        local painted = Paint(health, state)
        local badge = PaintBadge(state, state.levelBadge)
        state.revision = painted and badge and revision or nil
        if not state.revision then RetryPlate(uf) end
    end
    if state.highlight then
        PaintOutline(health, state)
    elseif off and outline and plan and outline.borderSize ~= 0 then
        Style.PaintBorder(outline, health, 0)
    end
end

function Selection.Restore(health)
    local state = health and plates[health]
    if state then
        if state.highlight then Style.PaintBorder(state.outline, nil, 0) end
        Restore(health, state)
    end
end

function Selection.RestoreAll()
    for health, state in pairs(plates) do
        if Safe(health) then
            Selection.Restore(health)
        else
            if state.badge then badges[state.badge] = nil end
            plates[health], pending[health] = nil, nil
        end
    end
end
