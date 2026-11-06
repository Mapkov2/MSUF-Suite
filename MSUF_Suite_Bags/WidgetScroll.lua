local _, P = ...
local NS, S = P.NS, P.Suite
local Scroll = {}
P.BagWidgetScroll = Scroll
local min, max = math.min, math.max

function Scroll.CanChange(frame)
    if not NS.InCombat() then return true end
    local bar = frame.bagScrollBar
    return P.BagLayout.Frame(frame) and (not bar or P.BagLayout.Frame(bar))
end

local function Range(frame)
    return max(0, frame:GetScrollChild():GetHeight() - frame:GetHeight())
end

function Scroll.Cancel(frame)
    if frame.bagScrollTarget == nil then return end
    frame.bagScrollTarget, frame.bagScrollFrom, frame.bagScrollElapsed, frame.bagScrollDuration = nil, nil, nil, nil
    frame:SetScript("OnUpdate", nil)
    frame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    NS.Registry.RemoveListener(frame)
end

local function SetOffset(frame, value)
    frame.bagScrollWriting = true
    frame:SetVerticalScroll(value)
    frame.bagScrollWriting = nil
end

local function Finish(frame)
    local target = frame.bagScrollTarget
    Scroll.Cancel(frame)
    if target and frame:IsVisible() and Scroll.CanChange(frame) then
        SetOffset(frame, min(Range(frame), target))
    end
end

function Scroll.Clamp(frame, range, value)
    local target = frame.bagScrollTarget
    if target == nil then return end
    local bounded = min(range, max(0, target))
    if bounded == value then
        Scroll.Cancel(frame)
    elseif bounded ~= target or frame.bagScrollFrom > range then
        frame.bagScrollTarget, frame.bagScrollFrom, frame.bagScrollElapsed = bounded, value, 0
    end
end

local function Tick(frame, elapsed)
    if not frame:IsVisible() or not Scroll.CanChange(frame) then
        Scroll.Cancel(frame)
        return
    end
    local mode = P.BagMotion.Mode(S.Config("bags"))
    if mode == NS.BagsAnimation.OFF then
        Finish(frame)
        return
    end
    local duration = frame.bagScrollDuration
    frame.bagScrollElapsed = min(duration, frame.bagScrollElapsed + elapsed)
    local t = frame.bagScrollElapsed / duration
    local eased = 1 - (1 - t) * (1 - t) * (1 - t)
    if t == 1 then
        Finish(frame)
    else
        SetOffset(frame, frame.bagScrollFrom + (frame.bagScrollTarget - frame.bagScrollFrom) * eased)
    end
end

local function Changed(frame, domain)
    if domain == "profile" then Scroll.Cancel(frame) end
end

function Scroll.Wheel(frame, delta)
    if not frame:IsVisible() or not Scroll.CanChange(frame) then
        Scroll.Cancel(frame)
        return
    end
    local current = frame:GetVerticalScroll()
    local target = min(Range(frame), max(0, (frame.bagScrollTarget or current) - delta * 66))
    local mode = P.BagMotion.Mode(S.Config("bags"))
    if mode == NS.BagsAnimation.OFF or current == target then
        Scroll.Cancel(frame)
        if current ~= target then SetOffset(frame, target) end
        return
    end
    frame.bagScrollTarget, frame.bagScrollFrom, frame.bagScrollElapsed = target, current, 0
    frame.bagScrollDuration = mode == NS.BagsAnimation.FULL and .16 or .12
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    NS.Registry.AddListener(frame, Changed)
    frame:SetScript("OnUpdate", Tick)
end

function Scroll.Attach(frame)
    frame:HookScript("OnHide", Scroll.Cancel)
    frame:SetScript("OnEvent", Finish)
end
