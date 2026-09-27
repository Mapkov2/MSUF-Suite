local _, NS = ...

-- The current mainline Game Menu rebuilds its buttons from buttonPool whenever
-- it is shown (GameMenuFrameMixin:InitButtons, Blizzard_GameMenu/Shared/
-- GameMenuFrame.lua). Styling a fixed set of globals therefore cannot cover it.
-- A post-hook on the menu's own InitButtons skins the buttons Blizzard just
-- acquired. The pool is never driven from here: frames that addon code
-- acquires are created in addon (tainted) execution. Blizzard's scripts,
-- callbacks and layout data are never replaced.

local GameMenuSkin = {
    directChildLimit = 64,
    hookedFrames = setmetatable({}, { __mode = "k" }),
}
NS.GameMenuSkin = GameMenuSkin

local Safety = NS.Safety
local Field = Safety.Field
local Kit = NS.AdapterKit

local frameStates = setmetatable({}, { __mode = "k" })
local activeFrames = setmetatable({}, { __mode = "k" })
local listenerRegistered = false

local BUTTON_SPEC = {
    role = "button",
    activeRole = "buttonPrimary",
    useControlShape = true,
    pillHeight = 32,
    inset = 2,
}
local SHELL_SPEC = { role = "shell", inset = 0 }
local HEADER_SPEC = {
    role = "navigationActive",
    shape = "continuous",
    radius = 6,
    inset = 4,
}

local function SkinButton(button, owner)
    return Safety.CanControl(button, false)
        and NS.ControlSkin.ApplyThreeSliceButton(button, owner, BUTTON_SPEC) ~= nil
end

local function SkinActiveButtons(pool, owner)
    if type(Field(pool, "EnumerateActive")) ~= "function" then return end
    for button in pool:EnumerateActive() do
        SkinButton(button, owner)
    end
end

-- Correctly integrated addon buttons can be direct GameMenuFrame children
-- instead of members of Blizzard's pool. Cover only bounded, structurally
-- verified three-slice buttons; no addon name or foreign field is assumed.
local function SkinDirectThreeSliceButtons(owner, ...)
    for index = 1, math.min(select("#", ...), GameMenuSkin.directChildLimit) do
        local button = select(index, ...)
        if Kit.ObjectType(button) == "Button" and Field(button, "Left")
            and Field(button, "Center") and Field(button, "Right") then
            SkinButton(button, owner)
        end
    end
end

local function FadeShell(frame, owner)
    local border = frame.Border
    if border then
        NS.Cosmetics.Fade(border.Bg, owner)
        NS.Cosmetics.FadeNineSlice(border, owner)
    end
    NS.Cosmetics.FadeDialogHeader(frame.Header, owner)
end

local function HeaderText(frame)
    return frame.Header and frame.Header.Text
end

-- The header title takes the theme's title color. Its native color comes
-- back on disable only while ours is still shown (AdapterKit text colors).
local function RefreshActiveFrames()
    for frame in pairs(activeFrames) do
        local frameState = frameStates[frame]
        if frameState then Kit.RefreshTextColors(frameState.textColors) end
    end
end

local function RegisterThemeListener()
    if listenerRegistered then
        return
    end
    listenerRegistered = true
    NS.Registry.AddListener(GameMenuSkin, RefreshActiveFrames)
end

-- Buttons appear when Blizzard shows the menu, which can happen in combat.
-- Their cosmetic skin waits for the next out-of-combat opening then; the
-- pooled buttons keep it for every later one.
local function OnButtonsInitialized(frame)
    local frameState = frameStates[frame]
    if not frameState or not activeFrames[frame] or NS.IsCombatLocked() then return end
    Safety.Dispatch(SkinActiveButtons, frame.buttonPool, frameState.owner)
end

local function HookInitButtons(frame)
    if GameMenuSkin.hookedFrames[frame] then return end
    GameMenuSkin.hookedFrames[frame] = Kit.HookFunction(frame, "InitButtons", OnButtonsInitialized)
end

function GameMenuSkin.Apply(frame, owner)
    frame = frame or _G.GameMenuFrame
    owner = owner or "gameMenu"
    if not frame then
        return false, "missing-frame"
    end
    if NS.IsCombatLocked() then
        return false, "combat"
    end
    if not Safety.CanDecorate(frame, false) then
        return false, "protected-frame"
    end

    local pool = frame.buttonPool
    if type(Field(pool, "EnumerateActive")) ~= "function" then
        return false, "missing-pool"
    end

    local frameState = frameStates[frame]
    if not frameState then
        frameState = { textColors = Kit.NewTextColors() }
        frameStates[frame] = frameState
    end

    if not NS.Surface.Attach(frame, SHELL_SPEC) then
        return false, "shell-failed"
    end
    if frame.Header then
        NS.Surface.Attach(frame.Header, HEADER_SPEC)
    end

    FadeShell(frame, owner)
    Kit.SetTextColor(frameState.textColors, HeaderText(frame), "title")
    SkinActiveButtons(pool, owner)
    SkinDirectThreeSliceButtons(owner, Safety.Call(frame, "GetChildren"))

    frameState.owner = owner
    activeFrames[frame] = true
    HookInitButtons(frame)
    RegisterThemeListener()
    return true
end

function GameMenuSkin.Disable(frame, owner)
    frame = frame or _G.GameMenuFrame
    owner = owner or "gameMenu"
    if not frame then
        return false, "missing-frame"
    end
    if NS.IsCombatLocked() then
        return false, "combat"
    end

    NS.Surface.SetVisible(frame, false)
    if frame.Header then
        NS.Surface.SetVisible(frame.Header, false)
    end
    NS.ControlSkin.DisableOwner(owner)
    NS.Cosmetics.RestoreOwner(owner)

    local frameState = frameStates[frame]
    if frameState then
        Kit.RestoreTextColors(frameState.textColors)
    end
    activeFrames[frame] = nil
    return true
end
