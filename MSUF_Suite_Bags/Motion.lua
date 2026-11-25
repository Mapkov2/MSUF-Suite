local _, P = ...
local NS = P.NS
local Motion = { records = setmetatable({}, { __mode = "k" }) }
P.BagMotion = Motion
local MODE = NS.BagsAnimation
local StopSelection = function() end
local nextButton, nativeNextEnabled, widthOnly
function Motion.SetSelectionStop(callback) StopSelection = callback end

local function New(frame)
    local group = frame:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(.14)
    fade:SetSmoothing("OUT")
    local record = { group = group, fade = fade }
    Motion.records[frame] = record
    return record
end

local function Mode(config)
    if NS.InCombat() or NS.HostBridge.MenuReducedMotion() then return MODE.OFF end
    return config.animationMode
end
Motion.Mode = Mode

local function NextPulse(button)
    local group = button.bagNextPulse
    if group then return group end
    group = button:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(.7)
    fade:SetDuration(.75)
    fade:SetSmoothing("IN_OUT")
    button.bagNextPulse = group
    return group
end

local function SetNextEnabled(button, enabled)
    nativeNextEnabled(button, enabled)
    local pulse = enabled and not P.BagWindowMotion.active
        and not (widthOnly and P.InventoryRendering.Listed())
    local group = pulse and NextPulse(button) or button.bagNextPulse
    if not group or group:IsPlaying() == pulse then return end
    if pulse then group:Play() else group:Stop() end
end

function Motion.StopNextHint()
    if not nextButton then return end
    nextButton.SetEnabled = nativeNextEnabled
    if nextButton.bagNextPulse then nextButton.bagNextPulse:Stop() end
    nextButton, nativeNextEnabled, widthOnly = nil, nil, nil
end

-- Only the Suite-owned button is wrapped. Restoring its method at the combat
-- edge leaves the normal paging render path with no animation call or check.
function Motion.UpdateNextHint(button, config, limitedRows, limitedColumns)
    if not (limitedRows or limitedColumns) or Mode(config) == MODE.OFF then
        Motion.StopNextHint()
        return
    end
    widthOnly = not limitedRows
    if nextButton == button then return end
    nextButton, nativeNextEnabled = button, button.SetEnabled
    button.SetEnabled = SetNextEnabled
end

-- Native animation objects run only during a transition; no Lua OnUpdate,
-- timers. Hit regions and native items never animate.
function Motion.Play(frame, config, order)
    local mode = Mode(config)
    local record = Motion.records[frame]
    if record then record.group:Stop() end
    if mode == MODE.OFF then return end
    record = record or New(frame)
    local delay = mode == MODE.FULL and math.min(order or 0, 5) * .018 or 0
    record.fade:SetStartDelay(delay)
    record.fade:SetDuration(mode == MODE.FULL and .18 or .12)
    record.group:Play()
end

function Motion.Stop(frame)
    local record = Motion.records[frame]
    if record then
        record.group:Stop()
        if record.hover then frame:SetAlpha(record.goal) end
    end
end

function Motion.StopAll()
    StopSelection()
    for frame, record in pairs(Motion.records) do
        record.group:Stop()
        if record.hover then frame:SetAlpha(record.goal) end
    end
end

-- Match the short MSUF background hover; the FontString never transforms.
function Motion.Hover(surface, config, entered)
    local goal = entered and 1 or .7
    local record = Motion.records[surface]
    local from = surface:GetAlpha()
    if record and record.group:IsPlaying() then
        from = record.from + (record.goal - record.from) * record.fade:GetSmoothProgress()
    end
    if record then record.group:Stop() end
    if Mode(config) == MODE.OFF then
        if record then record.goal = goal end
        surface:SetAlpha(goal)
        return
    end
    record = record or New(surface)
    if not record.hover then
        record.hover = true
        record.group:SetToFinalAlpha(true)
    end
    record.from, record.goal = from, goal
    surface:SetAlpha(from)
    record.fade:SetFromAlpha(from)
    record.fade:SetToAlpha(goal)
    record.fade:SetStartDelay(0)
    record.fade:SetDuration(.12)
    record.group:Play()
end

-- Only the owned tab fill travels; labels and item contents stay steady.
function Motion.Switch(view, config)
    P.BagTabSelection.Switch(view, config)
end
