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
-- MSUF anchors its button to the same 200x36 bounds as Blizzard's buttons.
-- Its visible border must use those bounds too, rather than losing two pixels
-- on each side to the generic Game Menu button inset.
local MSUF_BUTTON_SPEC = {
    role = "button",
    activeRole = "buttonPrimary",
    useControlShape = true,
    pillHeight = 32,
    inset = 0,
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

-- Addon buttons can be direct GameMenuFrame children instead of pool members.
-- MSUF's own button may use the panel-button fallback template on some clients.
local function SkinDirectButtons(frame, owner, ...)
    local msufButton = Field(frame, "MSUF")
    local pool = frame.buttonPool
    for index = 1, math.min(select("#", ...), GameMenuSkin.directChildLimit) do
        local button = select(index, ...)
        -- MainMenuFrameTemplates parents pooled buttons to this same frame;
        -- the pool pass already handles them once per native rebuild.
        if Kit.ObjectType(button) == "Button" and not pool:IsActive(button) then
            if Field(button, "Left") and Field(button, "Center") and Field(button, "Right") then
                if button == msufButton then
                    if Safety.CanControl(button, false) then
                        NS.ControlSkin.ApplyThreeSliceButton(button, owner, MSUF_BUTTON_SPEC)
                    end
                else
                    SkinButton(button, owner)
                end
            elseif button == msufButton and Safety.CanControl(button, false) then
                NS.ControlSkin.ApplyButton(button, owner, MSUF_BUTTON_SPEC)
            end
        end
    end
end

local function SkinDirectChildren(frame, owner)
    Safety.Dispatch(SkinDirectButtons, frame, owner, Safety.Call(frame, "GetChildren"))
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
    NS.Registry.AddListener(GameMenuSkin, function() NS.Registry.QueueJob(RefreshActiveFrames) end)
end

-- Buttons appear when Blizzard shows the menu, which can happen in combat.
-- Their cosmetic skin waits for the next out-of-combat opening then; the
-- pooled buttons keep it for every later one.
local function OnButtonsInitialized(frame)
    local frameState = frameStates[frame]
    if not frameState or not activeFrames[frame] or NS.IsCombatLocked() then return end
    Safety.Dispatch(SkinActiveButtons, frame.buttonPool, frameState.owner)
    SkinDirectChildren(frame, frameState.owner)
    -- Other addons can create their button in an OnShow hook after InitButtons.
    -- Store/trial events may rebuild the pool again before that next frame.
    if not frameState.directRefreshQueued then
        frameState.directRefreshQueued = true
        C_Timer.After(0, frameState.refreshDirectChildren)
    end
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
        frameState.refreshDirectChildren = function()
            frameState.directRefreshQueued = nil
            if activeFrames[frame] and not NS.IsCombatLocked()
                and Safety.Read(frame, "IsShown") == true then
                SkinDirectChildren(frame, frameState.owner)
            end
        end
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
    SkinDirectChildren(frame, owner)

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
