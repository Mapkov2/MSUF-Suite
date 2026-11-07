local _, private = ...
local NS = private.NS
local Mode = private.Mode
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
local revision, hooked = 0, false
local original

local function Safe(region)
    return region and not NS.Safety.IsForbidden(region)
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
    elseif not hide and originalAlpha ~= nil then
        texture:SetAlpha(originalAlpha)
        return nil
    end
    return originalAlpha
end

local function PaintBorder(owner, state, colorOnly, badge)
    local frame = owner.selectedBorder
    if Safe(frame) then
        if not colorOnly then
            state.border = HiddenAlpha(frame, state.border, state.mode == HIDE)
        end
        if state.mode == CUSTOM then
            local rgb = CustomColor(owner)
            frame:SetVertexColor(rgb[1], rgb[2], rgb[3])
            state.colored = true
        elseif state.colored then
            local color = NativeColor(owner, badge)
            if color then frame:SetVertexColor(color.r, color.g, color.b) end
            state.colored = nil
        end
    end
end

local function Paint(health, state, colorOnly)
    PaintBorder(health, state, colorOnly)
    if colorOnly then return end
    local mode = state.styled and dim or KEEP
    local overlay = health.deselectedOverlay
    if (mode ~= KEEP or state.dim) and Safe(overlay) then
        local alpha = mode == HIDE and 0 or mode == CUSTOM and dimAlpha or 1
        if state.dim ~= alpha then
            overlay:SetAlpha(alpha)
            state.dim = alpha
        end
    end
end

local function OnUpdateBadge(badge)
    local state = badges[badge]
    if state and state.mode == CUSTOM then PaintBorder(badge, state, true, true) end
end

local function RestoreBorder(owner, state, badge)
    if not Safe(owner) then return end
    local frame = owner.selectedBorder
    if not Safe(frame) then return end
    HiddenAlpha(frame, state.border, false)
    if state.colored then
        local color = NativeColor(owner, badge)
        if color then frame:SetVertexColor(color.r, color.g, color.b) end
    end
end

local function PaintBadge(state, badge)
    if state.badge and (state.badge ~= badge or state.mode == KEEP) then
        RestoreBorder(state.badge, badges[state.badge], true)
        badges[state.badge], state.badge = nil, nil
    end
    if state.mode == KEEP or not Safe(badge) or not Safe(badge.selectedBorder) then return end
    local visual = badges[badge]
    if not visual then
        visual = {}
        badges[badge], state.badge = visual, badge
    end
    if state.mode == CUSTOM and not hookedBadges[badge] and badge.UpdateSelectionBorder then
        hooksecurefunc(badge, "UpdateSelectionBorder", OnUpdateBadge)
        hookedBadges[badge] = true
    end
    visual.mode = state.mode
    PaintBorder(badge, visual, false, true)
end

-- Forever draws an oversized native backdrop on the bar; Classic uses the
-- Nameplate-Border texture there. Keep its anchors for the selection border.
local function PaintBackground(health, state, hide)
    local texture = health.bgTexture
    if not Safe(texture) then return end
    state.background = HiddenAlpha(texture, state.background, hide)
end

-- Runs after Blizzard's own update on every target or focus change: only a
-- styled plate repaints, and only its border color (Blizzard just set it).
local function OnUpdateSelection(health)
    local state = plates[health]
    if state and state.mode == CUSTOM then Paint(health, state, true) end
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
    plates[health] = nil
    if not active and not hideAll and not hideEnemyBackground and not hideFriendlyBackground and next(plates) == nil then
        Selection.inUse = false
    end
    RestoreBorder(health, state)
    local overlay = health.deselectedOverlay
    if Safe(overlay) and state.dim and state.dim ~= 1 then overlay:SetAlpha(1) end
    PaintBackground(health, state, false)
    local badge = state.badge
    if badge then
        RestoreBorder(badge, badges[badge], true)
        badges[badge] = nil
    end
end

function Selection.Configure(config)
    local skin = config.look ~= LOOK_BLIZZARD
    border = skin and config.selectionBorder or KEEP
    dim = skin and config.selectionDim or KEEP
    dimAlpha = (config.selectionDimPercent or 50) / 100
    active = border ~= KEEP or dim ~= KEEP
    hideAll = config.hideHealthBarBorders == true
    hideEnemyBackground = skin and NS.Client.isForever and config.enemy and config.enemyNativeBorderEnabled == false
    hideFriendlyBackground = skin and NS.Client.isForever and config.friendly and config.friendlyNativeBorderEnabled == false
    Selection.inUse = active or hideAll or hideEnemyBackground or hideFriendlyBackground or next(plates) ~= nil
    -- Profiles saved before these settings existed have no colors yet.
    targetRGB = { NS.RGB(config.selectionTargetColor or "ffffff") }
    focusRGB = { NS.RGB(config.selectionFocusColor or "ff66ff") }
    revision = revision + 1
end

-- A plate pass (Skin.lua Paint, only while inUse) on a health bar it already
-- checked: styled is false for a plate whose side the skin leaves alone.
function Selection.Apply(health, styled, uf, prefix)
    local state = plates[health]
    local sideBackground = prefix == "enemy" and hideEnemyBackground or prefix == "friendly" and hideFriendlyBackground
    local hideBackground = hideAll or styled and sideBackground
    if not hideAll and not (styled and (active or hideBackground)) then
        if state then Restore(health, state) end
        return
    end
    if not state then
        state = {}
        plates[health] = state
    end
    -- A unit can change faction on an existing plate without a profile refresh.
    if (hideBackground == true) ~= (state.background ~= nil) then
        PaintBackground(health, state, hideBackground)
    end
    if state.revision ~= revision or state.styled ~= styled then
        state.styled = styled
        state.mode = hideAll and HIDE or border
        if state.mode == CUSTOM then Hook(health) end
        Paint(health, state)
        PaintBadge(state, NS.Client.isForever and uf and uf.PlayerLevelDiffFrame)
        state.revision = revision
    end
end

function Selection.Restore(health)
    local state = health and plates[health]
    if state then Restore(health, state) end
end

function Selection.RestoreAll()
    for health, state in pairs(plates) do
        if Safe(health) then
            Restore(health, state)
        else
            if state.badge then badges[state.badge] = nil end
            plates[health] = nil
        end
    end
end
