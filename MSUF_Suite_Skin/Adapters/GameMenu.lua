local _, NS = ...

-- The current mainline Game Menu rebuilds its buttons from buttonPool whenever
-- it is shown. Styling a fixed set of globals therefore cannot cover it. We
-- prime a bounded set of pooled frames once, outside combat, and release only
-- the objects acquired here. Blizzard's scripts, callbacks and layout data
-- are never replaced.

local GameMenuSkin = {
    reserveCount = 24,
    directChildLimit = 64,
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

local function ActiveCount(pool)
    local count = Safety.Read(pool, "GetNumActive")
    return type(count) == "number" and math.max(0, count) or 0
end

local function PrimeButtonPool(pool, owner)
    local acquired = {}
    for _ = 1, math.max(0, GameMenuSkin.reserveCount - ActiveCount(pool)) do
        local button = pool:Acquire()
        if not button then break end
        acquired[#acquired + 1] = button
        SkinButton(button, owner)
    end

    -- Release exactly the frames acquired above; active menu buttons are never
    -- disturbed when a theme is reapplied while the menu is open.
    for index = #acquired, 1, -1 do
        pool:Release(acquired[index])
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

local function CaptureFrameState(frame, state)
    local r, g, b, a = Safety.ReadColor(HeaderText(frame), "GetTextColor")
    if r then
        state.headerColor = { r, g, b, a }
    end
end

local function RefreshFrameText(frame)
    local text = HeaderText(frame)
    if text and type(text.SetTextColor) == "function" then
        text:SetTextColor(NS.Theme.GetColor("title"))
    end
end

local function RefreshActiveFrames()
    for frame in pairs(activeFrames) do
        RefreshFrameText(frame)
    end
end

local function RegisterThemeListener()
    if listenerRegistered then
        return
    end
    listenerRegistered = true
    NS.Registry.AddListener(GameMenuSkin, RefreshActiveFrames)
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
    if not pool or type(pool.Acquire) ~= "function" or type(pool.Release) ~= "function"
        or type(pool.EnumerateActive) ~= "function" then
        return false, "missing-pool"
    end

    local frameState = frameStates[frame]
    if not frameState then
        frameState = {}
        frameStates[frame] = frameState
    end
    if not frameState.applied then
        CaptureFrameState(frame, frameState)
    end

    if not NS.Surface.Attach(frame, SHELL_SPEC) then
        return false, "shell-failed"
    end
    if frame.Header then
        NS.Surface.Attach(frame.Header, HEADER_SPEC)
    end

    FadeShell(frame, owner)
    RefreshFrameText(frame)
    SkinActiveButtons(pool, owner)
    PrimeButtonPool(pool, owner)
    SkinDirectThreeSliceButtons(owner, Safety.Call(frame, "GetChildren"))

    frameState.applied = true
    frameState.owner = owner
    activeFrames[frame] = true
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
    local text = HeaderText(frame)
    if frameState and frameState.headerColor and text and type(text.SetTextColor) == "function" then
        text:SetTextColor(unpack(frameState.headerColor))
    end
    if frameState then
        frameState.applied = false
    end
    activeFrames[frame] = nil
    return true
end
