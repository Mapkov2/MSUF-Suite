local _, NS = ...

-- The current mainline Game Menu rebuilds its buttons from buttonPool whenever
-- it is shown.  Styling a fixed set of globals therefore cannot cover it.  We
-- prime a bounded set of pooled frames once, outside combat, and release only
-- the objects acquired here.  Blizzard's scripts, callbacks and layout data
-- are never replaced.

local GameMenuSkin = {
    reserveCount = 24,
    directChildLimit = 64,
}
NS.GameMenuSkin = GameMenuSkin

local frameStates = setmetatable({}, { __mode = "k" })
local activeFrames = setmetatable({}, { __mode = "k" })
local listenerRegistered = false

local function SafeGetter(object, methodName)
    local method = object and object[methodName]
    if type(method) ~= "function" then
        return nil
    end
    local ok, value = pcall(method, object)
    if ok then
        return value
    end
    return nil
end

local function SkinButton(button, owner)
    if not NS.Safety or not NS.Safety.CanControl(button, false) then
        return false
    end

    local state = NS.ControlSkin.ApplyThreeSliceButton(button, owner, {
        role = "button",
        activeRole = "buttonPrimary",
        useControlShape = true,
        pillHeight = 32,
        inset = 2,
    })
    if not state then
        return false
    end
    return true
end

local function SkinActiveButtons(pool, owner)
    local ok, message = pcall(function()
        for button in pool:EnumerateActive() do
            SkinButton(button, owner)
        end
    end)
    if not ok then
        NS.ReportError("game menu active buttons", message)
    end
end

local function ObjectType(object)
    local value = SafeGetter(object, "GetObjectType")
    return type(value) == "string" and value or ""
end

local function SkinDirectThreeSliceButtons(frame, owner)
    if not frame or type(frame.GetChildren) ~= "function" then
        return
    end

    local ok, children = pcall(function() return { frame:GetChildren() } end)
    if not ok then
        NS.ReportError("game menu direct buttons", children)
        return
    end

    local limit = math.min(#children, GameMenuSkin.directChildLimit)
    for index = 1, limit do
        local button = children[index]
        if ObjectType(button) == "Button" and button.Left and button.Center and button.Right then
            SkinButton(button, owner)
        end
    end
end

local function ActiveCount(pool)
    local count = SafeGetter(pool, "GetNumActive")
    local ok, numeric = pcall(tonumber, count)
    count = ok and numeric or nil
    return count and math.max(0, count) or 0
end

local function PrimeButtonPool(pool, owner)
    local acquireCount = math.max(0, GameMenuSkin.reserveCount - ActiveCount(pool))
    local acquired = {}

    for index = 1, acquireCount do
        local ok, button = pcall(pool.Acquire, pool)
        if not ok or not button then
            if not ok then
                NS.ReportError("game menu button acquire", button)
            end
            break
        end
        acquired[#acquired + 1] = button
        SkinButton(button, owner)
    end

    -- Release exactly the frames acquired above; active menu buttons are never
    -- disturbed when a theme is reapplied while the menu is open.
    for index = #acquired, 1, -1 do
        local ok, message = pcall(pool.Release, pool, acquired[index])
        if not ok then
            NS.ReportError("game menu button release", message)
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

local function CaptureFrameState(frame, state)
    local text = frame.Header and frame.Header.Text
    if text and type(text.GetTextColor) == "function" then
        local ok, r, g, b, a = pcall(text.GetTextColor, text)
        if ok then
            state.headerColor = { r, g, b, a }
        end
    end
end

local function RefreshFrameText(frame)
    local text = frame.Header and frame.Header.Text
    if text and type(text.SetTextColor) == "function" then
        text:SetTextColor(NS.Theme.GetColor("title"))
    end
end

local function RegisterThemeListener()
    if listenerRegistered then
        return
    end
    listenerRegistered = true
    NS.Registry.AddListener(GameMenuSkin, function()
        for frame in pairs(activeFrames) do
            RefreshFrameText(frame)
        end
    end)
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
    if not NS.Safety or not NS.Safety.CanDecorate(frame, false) then
        return false, "protected-frame"
    end

    local pool = frame.buttonPool
    if not pool or type(pool.Acquire) ~= "function" or type(pool.Release) ~= "function" then
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

    local shell = NS.Surface.Attach(frame, { role = "shell", inset = 0 })
    if not shell then
        return false, "shell-failed"
    end

    if frame.Header then
        NS.Surface.Attach(frame.Header, {
            role = "navigationActive",
            shape = "continuous",
            radius = 6,
            inset = 4,
        })
    end

    FadeShell(frame, owner)
    RefreshFrameText(frame)
    SkinActiveButtons(pool, owner)
    PrimeButtonPool(pool, owner)
    -- Correctly integrated addon buttons can be direct GameMenuFrame children
    -- instead of members of Blizzard's pool. Cover only bounded, structurally
    -- verified three-slice buttons; no addon name or foreign field is assumed.
    SkinDirectThreeSliceButtons(frame, owner)

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
    local text = frame.Header and frame.Header.Text
    if frameState and frameState.headerColor and text and type(text.SetTextColor) == "function" then
        text:SetTextColor(unpack(frameState.headerColor))
    end
    if frameState then
        frameState.applied = false
    end
    activeFrames[frame] = nil
    return true
end
