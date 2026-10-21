local _, NS = ...

-- Finite alpha transforms leave the owner's alpha, anchors and input alone.
local Content = { records = setmetatable({}, { __mode = "k" }), active = {}, watchers = {} }
NS.ContentMotion = Content
local Safety, Motion = NS.Safety, NS.Motion

local function Stop(record)
    record.group:Stop()
    record.token = nil
    Content.active[record] = nil
end

local function Hidden(frame)
    local record = Content.records[frame]
    if record then Stop(record) end
end

local function Descendant(frame, ancestor)
    for _ = 1, 16 do
        frame = Safety.Read(frame, "GetParent")
        if frame == nil then return false end
        if frame == ancestor then return true end
    end
    return false
end

local function Finished(group) Content.active[group.record] = nil end

function Content.HasOpeningFade(frame)
    local watch = Content.watchers[frame]
    return watch ~= nil and next(watch.owners) ~= nil
end

function Content.Play(frame, owner, token)
    local record = Content.records[frame]
    if not Motion.Enabled() or not Safety.CanCreateRegions(frame) or Safety.GetProtection(frame)
        or Safety.Read(frame, "IsVisible") ~= true then
        if record then Stop(record) end
        return false
    end
    if record and record.owner ~= nil and record.owner ~= owner then return false end
    for active in pairs(Content.active) do
        if Descendant(frame, active.target) then return false end
        if Descendant(active.target, frame) then Stop(active) end
    end
    if record and record.token == token then return true end
    local alpha = Safety.Read(frame, "GetAlpha")
    if type(alpha) ~= "number" then return false end
    if not record then
        local group = frame:CreateAnimationGroup()
        local animation = group:CreateAnimation("Alpha")
        animation:SetDuration(0.12)
        animation:SetSmoothing("OUT")
        record = { target = frame, group = group, alpha = animation, owner = owner }
        group.record = record
        group:SetScript("OnFinished", Finished)
        Content.records[frame] = record
        frame:HookScript("OnHide", Hidden)
    end
    local from = 0
    if record.group:IsPlaying() then
        local progress = Safety.Read(record.alpha, "GetSmoothProgress")
        if type(progress) == "number" then
            progress = math.max(0, math.min(1, progress))
            from = record.fromAlpha + (record.toAlpha - record.fromAlpha) * progress
        end
    end
    record.group:Stop()
    record.owner, record.token = owner, token
    record.fromAlpha, record.toAlpha = from, alpha
    record.alpha:SetFromAlpha(from)
    record.alpha:SetToAlpha(alpha)
    Content.active[record] = true
    record.group:Play()
    return true
end

function Content.StopOwner(owner, frame)
    local found = false
    for target, record in pairs(Content.records) do
        if record.owner == owner and (frame == nil or frame == target) then
            Stop(record)
            record.owner, found = nil, true
        end
    end
    return found
end

local function Shown(frame)
    local watch = Content.watchers[frame]
    if watch and next(watch.owners) then
        watch.serial = watch.serial + 1
        Content.Play(frame, next(watch.owners), watch.serial)
    end
end

function Content.Watch(frame, owner)
    if not Safety.CanCreateRegions(frame) or Safety.GetProtection(frame)
        or not Safety.HasMethod(frame, "CreateAnimationGroup") then return false end
    local watch = Content.watchers[frame]
    if not watch then
        watch = { owners = {}, serial = 0 }
        Content.watchers[frame] = watch
        frame:HookScript("OnShow", Shown)
    end
    watch.owners[owner] = true
    return true
end

function Content.Unwatch(owner, frame)
    local watch = Content.watchers[frame]
    if watch then watch.owners[owner] = nil end
    Content.StopOwner(owner, frame)
end

function Content.UnwatchOwner(owner)
    for frame, watch in pairs(Content.watchers) do
        watch.owners[owner] = nil
    end
    Content.StopOwner(owner)
end

local function StopAll()
    for _, record in pairs(Content.records) do Stop(record) end
end
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", StopAll)
NS.Registry.AddListener(Content, StopAll)
NS.PublicAPI.PlayContent = Content.Play
NS.PublicAPI.StopContent = Content.StopOwner
