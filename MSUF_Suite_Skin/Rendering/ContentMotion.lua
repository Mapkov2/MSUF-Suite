local _, NS = ...

-- Finite alpha transforms leave the owner's alpha, anchors and input alone.
local Content = { records = setmetatable({}, { __mode = "k" }), active = {}, watchers = {} }
NS.ContentMotion = Content
local Safety, Motion = NS.Safety, NS.Motion
local revision = 0

local function Stop(record)
    if Content.active[record] then record.group:Stop() end
    record.token = nil
    Content.active[record] = nil
end


local function Descendant(frame, ancestor)
    for _ = 1, 16 do
        frame = Safety.Read(frame, "GetParent")
        if frame == nil then return false end
        if frame == ancestor then return true end
    end
    return false
end

-- Active records are keyed by their target. Read the candidate's current
-- parent chain once even when several independent fades are playing.
local function HasActiveAncestor(frame)
    for _ = 1, 16 do
        frame = Safety.Read(frame, "GetParent")
        if frame == nil then return false end
        if Content.active[Content.records[frame]] then return true end
    end
    return false
end

local function CompleteOpening(watch, coveringFrame)
    for target, resolve in pairs(watch.pending) do
        watch.pending[target] = nil
        Safety.Dispatch(resolve, target, coveringFrame and Descendant(target, coveringFrame))
    end
end

local function Hidden(frame)
    local watch = Content.watchers[frame]
    if watch then
        watch.shown = false
        CompleteOpening(watch, frame)
    end
    local record = Content.records[frame]
    if record then Stop(record) end
end

local function Finished(group) Content.active[group.record] = nil end

function Content.HasOpeningFade(frame)
    local watch = Content.watchers[frame]
    return watch ~= nil and next(watch.owners) ~= nil
end

-- The native list may lay out before its now-visible window's OnShow hook.
-- Resolve in that hook, before drawing, so the window and list do not both
-- start a fade. If the window cannot fade, the list still gets its own fade.
function Content.DeferToOpening(target, resolve)
    local frame = target
    for _ = 1, 16 do
        frame = Safety.Read(frame, "GetParent")
        if frame == nil then return end
        local watch = Content.watchers[frame]
        if watch and not watch.shown and next(watch.owners)
            and Safety.CanCreateRegions(frame) and Safety.Read(frame, "IsVisible") == true then
            watch.pending[target] = resolve
            return watch.pending
        end
    end
end

function Content.Play(frame, owner, token)
    local record = Content.records[frame]
    if not Motion.Enabled() or not Safety.CanCreateRegions(frame)
        or Safety.Read(frame, "IsVisible") ~= true then
        if record then Stop(record) end
        return false
    end
    if record and record.owner ~= nil and record.owner ~= owner then return false end
    local unchanged = record and record.token == token and record.revision == revision
    if unchanged and Content.active[record] then return true end
    local first = next(Content.active)
    if first and (first ~= record or next(Content.active, first)) then
        if HasActiveAncestor(frame) then return false end
        local stopped
        for active in pairs(Content.active) do
            if active ~= record and Descendant(active.target, frame) then
                Stop(active)
                stopped = true
            end
        end
        -- Stopping a native group may dispatch another animation callback.
        if stopped and HasActiveAncestor(frame) then return false end
    end
    if unchanged then return true end
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
        if not Content.watchers[frame] then frame:HookScript("OnHide", Hidden) end
    end
    local from = 0
    if Content.active[record] and record.group:IsPlaying() then
        local progress = Safety.Read(record.alpha, "GetSmoothProgress")
        if type(progress) == "number" then
            progress = math.max(0, math.min(1, progress))
            from = record.fromAlpha + (record.toAlpha - record.fromAlpha) * progress
        end
        record.group:Stop()
    end
    record.owner, record.token, record.revision = owner, token, revision
    -- Replays of the same fade reuse the native animation configuration.
    if record.fromAlpha ~= from then
        record.alpha:SetFromAlpha(from)
        record.fromAlpha = from
    end
    if record.toAlpha ~= alpha then
        record.alpha:SetToAlpha(alpha)
        record.toAlpha = alpha
    end
    Content.active[record] = true
    record.group:Play()
    return true
end

local function Release(record, owner)
    if not record or record.owner ~= owner then return false end
    Stop(record)
    record.owner = nil
    return true
end

function Content.StopOwner(owner, frame)
    if frame ~= nil then return Release(Content.records[frame], owner) end
    local found = false
    for _, record in pairs(Content.records) do
        if Release(record, owner) then found = true end
    end
    return found
end

local function Shown(frame)
    local watch = Content.watchers[frame]
    if not watch then return end
    watch.shown = true
    local owner = next(watch.owners)
    local covered = false
    if owner then
        watch.serial = watch.serial + 1
        covered = Content.Play(frame, owner, watch.serial)
    end
    CompleteOpening(watch, covered and frame)
end

function Content.Watch(frame, owner)
    if not Safety.CanCreateRegions(frame)
        or not Safety.HasMethod(frame, "CreateAnimationGroup") then return false end
    local watch = Content.watchers[frame]
    if not watch then
        watch = { owners = {}, serial = 0, pending = {}, shown = Safety.Read(frame, "IsVisible") == true }
        Content.watchers[frame] = watch
        frame:HookScript("OnShow", Shown)
        if not Content.records[frame] then frame:HookScript("OnHide", Hidden) end
    end
    watch.owners[owner] = true
    return true
end

local function RemoveOwner(watch, owner)
    if not watch or not watch.owners[owner] then return end
    watch.owners[owner] = nil
    if not next(watch.owners) then CompleteOpening(watch) end
end

function Content.Unwatch(owner, frame)
    Content.StopOwner(owner, frame)
    RemoveOwner(Content.watchers[frame], owner)
end

function Content.UnwatchOwner(owner)
    Content.StopOwner(owner)
    for _, watch in pairs(Content.watchers) do RemoveOwner(watch, owner) end
end

local function StopAll(_, event)
    local combat = event == "PLAYER_REGEN_DISABLED"
    if not combat then revision = revision + 1 end
    for record in pairs(Content.active) do
        if not combat or not Safety.CanCreateRegions(record.target)
            or Safety.Read(record.target, "IsVisible") ~= true then Stop(record) end
    end
end
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", StopAll)
NS.Registry.AddListener(Content, StopAll)
NS.PublicAPI.PlayContent = Content.Play
NS.PublicAPI.StopContent = Content.StopOwner
