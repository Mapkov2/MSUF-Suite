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

-- Styled health bars: health -> { border = alpha, dim = alpha, revision }.
local plates = setmetatable({}, { __mode = "k" })
local border, dim, dimAlpha, targetRGB, focusRGB = KEEP, KEEP, 1, nil, nil
local active = false
local revision, hooked = 0, false
local original

local function Safe(region)
    return region and not NS.Safety.IsForbidden(region)
end

-- Blizzard's own border color for the plate's state (Restore).
local function NativeColor(health)
    local target, focus = health.isTarget, health.isFocus
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

local function Paint(health, state, colorOnly)
    local frame, overlay = health.selectedBorder, health.deselectedOverlay
    if Safe(frame) then
        if not colorOnly then
            local alpha = border == HIDE and 0 or 1
            if state.border ~= alpha then
                frame:SetAlpha(alpha)
                state.border = alpha
            end
        end
        if border == CUSTOM then
            local rgb = CustomColor(health)
            frame:SetVertexColor(rgb[1], rgb[2], rgb[3])
            state.colored = true
        elseif state.colored then
            local color = NativeColor(health)
            if color then frame:SetVertexColor(color.r, color.g, color.b) end
            state.colored = nil
        end
    end
    if not colorOnly and Safe(overlay) then
        local alpha = dim == HIDE and 0 or dim == CUSTOM and dimAlpha or 1
        if state.dim ~= alpha then
            overlay:SetAlpha(alpha)
            state.dim = alpha
        end
    end
    state.revision = revision
end

-- Runs after Blizzard's own update on every target or focus change: only a
-- styled plate repaints, and only its border color (Blizzard just set it).
local function OnUpdateSelection(health)
    local state = plates[health]
    if state and border == CUSTOM then Paint(health, state, true) end
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
    if not active and next(plates) == nil then Selection.inUse = false end
    local frame, overlay = health.selectedBorder, health.deselectedOverlay
    if Safe(frame) then
        if state.border ~= 1 then frame:SetAlpha(1) end
        if state.colored then
            local color = NativeColor(health)
            if color then frame:SetVertexColor(color.r, color.g, color.b) end
        end
    end
    if Safe(overlay) and state.dim ~= 1 then overlay:SetAlpha(1) end
end

function Selection.Configure(config)
    local skin = config.look ~= LOOK_BLIZZARD
    border = skin and config.selectionBorder or KEEP
    dim = skin and config.selectionDim or KEEP
    dimAlpha = (config.selectionDimPercent or 50) / 100
    active = border ~= KEEP or dim ~= KEEP
    Selection.inUse = active or next(plates) ~= nil
    -- Profiles saved before these settings existed have no colors yet.
    targetRGB = { NS.RGB(config.selectionTargetColor or "ffffff") }
    focusRGB = { NS.RGB(config.selectionFocusColor or "ff66ff") }
    revision = revision + 1
end

-- A plate pass (Skin.lua Paint, only while inUse) on a health bar it already
-- checked: styled is false for a plate whose side the skin leaves alone.
function Selection.Apply(health, styled)
    local state = plates[health]
    if not styled or not active then
        if state then Restore(health, state) end
        return
    end
    if not state then
        state = {}
        plates[health] = state
        Hook(health)
    end
    if state.revision ~= revision then Paint(health, state) end
end

function Selection.Restore(health)
    local state = health and plates[health]
    if state then Restore(health, state) end
end

function Selection.RestoreAll()
    for health, state in pairs(plates) do
        if Safe(health) then Restore(health, state) else plates[health] = nil end
    end
end
