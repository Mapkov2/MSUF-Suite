local _, NS = ...

-- Finite alpha transforms leave the owner's alpha, anchors and input alone.
local Content = { records = setmetatable({}, { __mode = "k" }), active = {}, watchers = {} }
NS.ContentMotion = Content
local Safety, Motion = NS.Safety, NS.Motion
local revision = 0
-- frame -> cover(frame): true when the owner hid the frame for its own opening.
local covers = setmetatable({}, { __mode = "k" })

-- A window whose owner presents the opening itself (the Character Glass view)
-- skips the alpha fade over its whole native subtree. Its children's deferred
-- fades resolve as covered, exactly as after a played opening.
function Content.SetOpeningCover(frame, cover)
    covers[frame] = cover
end

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
        watch.shown, watch.openedAt = false, nil
        CompleteOpening(watch, frame)
    end
    local record = Content.records[frame]
    if record then Stop(record) end
end

-- Forever Communities has a large native subtree. Open it at its authored
-- opacity. Only the opening is shared by its children; a later tab or list
-- change still owns its usual transition.
function Content.InstantOpening(frame, explicitChange)
    if not NS.Client.isForever then return end
    local root = CommunitiesFrame
    if not root then return end
    if frame == root and not explicitChange then return root end
    local watch = Content.watchers[root]
    if not watch or not next(watch.owners) then return end
    if watch.shown then
        if not watch.openedAt then return end
        if watch.openedAt ~= GetTime() then watch.openedAt = nil return end
    elseif Safety.Read(root, "IsVisible") ~= true then return end
    if frame == root or Descendant(frame, root) then return root end
end

local function Finished(group) Content.active[group.record] = nil end

local function IsWindowWatch(watch)
    if not watch then return end
    for _, kind in pairs(watch.owners) do
        if kind == "window" then return true end
    end
end

local function Enabled(window)
    if window then return Motion.WindowEnabled() end
    return Motion.Enabled()
end

local function OpensIndependently(source)
    return not IsWindowWatch(Content.watchers[source])
end

local function OpeningOwner(watch, preferred)
    local source = watch.owners[preferred]
    if source and OpensIndependently(source) then return preferred end
    for owner, root in pairs(watch.owners) do
        if OpensIndependently(root) then return owner end
    end
end

function Content.IsWindow(frame)
    return IsWindowWatch(Content.watchers[frame]) == true
end

function Content.HasOpeningFade(frame)
    local watch = Content.watchers[frame]
    return watch ~= nil and not Content.InstantOpening(frame) and OpeningOwner(watch) ~= nil and Enabled(IsWindowWatch(watch))
end

-- The native list may lay out before its now-visible window's OnShow hook.
-- Resolve in that hook, before drawing, so the window and list do not both
-- start a fade. An instant opening consumes the same-frame list transition.
-- The second return means its parent has already completed that opening.
function Content.DeferToOpening(target, resolve)
    local root = Content.InstantOpening(target)
    if root then
        local opening = Content.watchers[root]
        if opening and not opening.shown then
            opening.pending[target] = resolve
            return opening.pending
        end
        return nil, true
    end
    local frame = target
    for _ = 1, 16 do
        frame = Safety.Read(frame, "GetParent")
        if frame == nil then return end
        local watch = Content.watchers[frame]
        if watch and not watch.shown and Content.HasOpeningFade(frame)
            and Safety.CanCreateRegions(frame) and Safety.Read(frame, "IsVisible") == true then
            watch.pending[target] = resolve
            return watch.pending
        end
    end
end

function Content.Play(frame, owner, token, window)
    local record = Content.records[frame]
    if record and record.owner ~= nil and record.owner ~= owner then return false end
    if not Enabled(window) or not Safety.CanCreateRegions(frame)
        or Safety.Read(frame, "IsVisible") ~= true then
        if record and record.window == window then Stop(record) end
        return false
    end
    if Content.InstantOpening(frame, true) then
        if record and Content.active[record] then Stop(record) end
        return false
    end
    local unchanged = record and record.token == token and record.revision == revision and record.window == window
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
    record.owner, record.token, record.revision, record.window = owner, token, revision, window
    -- Replays of the same fade reuse the native animation configuration.
    local extended = window and NS.Theme.GetWindowAnimationMode() == "extended" or false
    if record.extended ~= extended then
        record.alpha:SetDuration(extended and 0.24 or 0.12)
        record.alpha:SetSmoothing(extended and "IN_OUT" or "OUT")
        record.extended = extended
    end
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
    if not next(watch.owners) then watch.shown = true return end
    local instant = Content.InstantOpening(frame)
    watch.shown = true
    if instant then
        if instant == frame then watch.openedAt = GetTime() end
        CompleteOpening(watch, frame)
        return
    end
    local cover = covers[frame]
    if cover and not NS.IsCombatLocked() and Safety.Dispatch(cover, frame) == true then
        CompleteOpening(watch, frame)
        return
    end
    local record = Content.records[frame]
    local owner = OpeningOwner(watch, record and record.owner)
    local covered = false
    if owner then
        watch.serial = watch.serial + 1
        covered = Content.Play(frame, owner, watch.serial, IsWindowWatch(watch))
    end
    CompleteOpening(watch, covered and frame)
end

local function SettleMailbox()
    local frame = Safety.Field(_G, "MailFrame")
    if Safety.Read(frame, "IsVisible") == true then Shown(frame) end
end

local function QueueMailboxOpening()
    NS.Registry.QueueJob(SettleMailbox)
end

function Content.Watch(frame, owner, window, bodyRoot)
    if not Safety.CanCreateRegions(frame)
        or not Safety.HasMethod(frame, "CreateAnimationGroup") then return false end
    local watch = Content.watchers[frame]
    if not watch then
        watch = { owners = {}, serial = 0, pending = {}, shown = Safety.Read(frame, "IsVisible") == true }
        Content.watchers[frame] = watch
        if NS.Client.isForever and frame == CommunitiesFrame and watch.shown then watch.openedAt = GetTime() end
        -- A previously skinned mailbox opens its bags and reads mail after OnShow.
        local onShow = NS.Client.isForever and frame == Safety.Field(_G, "MailFrame") and QueueMailboxOpening or Shown
        frame:HookScript("OnShow", onShow)
        if not Content.records[frame] then frame:HookScript("OnHide", Hidden) end
    end
    if window then
        watch.owners[owner] = "window"
    elseif watch.owners[owner] ~= "window" then
        -- A named body discovered under a Blizzard window inherits the
        -- window's opening. Explicit tab and result fades call Play directly.
        watch.owners[owner] = bodyRoot or true
    end
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

local function StopAll(_, event, key)
    if event == "motion" and key == "windowAnimations" then
        for record in pairs(Content.active) do
            if record.window then Stop(record) end
        end
        return
    end
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
function NS.PublicAPI.PlayContent(frame, owner, token)
    return Content.Play(frame, owner, token)
end
NS.PublicAPI.StopContent = Content.StopOwner
