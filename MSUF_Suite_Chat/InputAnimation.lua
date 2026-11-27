local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
local M = C.M
local records = setmetatable({}, { __mode = "k" })
local pushes, moving = {}, {}
local pushDriver

function C.MessageInputOffset(owner, frame)
    local push = pushes[frame]
    return push and push.owner == owner and push.offset or 0
end

function C.MessageInputMoving(frame)
    return moving[frame] and not moving[frame].hold
end

local function PushDistance(push)
    local input, frame = push.input, push.frame
    local height, room = input:GetHeight(), frame:GetHeight()
    if not S.Finite(height) or height <= 0 then height = 32 end
    if not push.owner.preview then
        local inputScale, frameScale = input:GetEffectiveScale(), frame:GetEffectiveScale()
        if S.Finite(inputScale) and S.Finite(frameScale) and inputScale > 0 and frameScale > 0 then
            local scale = inputScale / frameScale
            height = height * scale
            local inputTop, bottom = input:GetTop(), frame:GetBottom()
            if S.Finite(inputTop) and S.Finite(bottom) then
                local messageBottom = bottom + (push.owner.config.messageTextY or 0)
                -- A bottom input outside the chat still animates, just like the preview.
                height = math.max(height, inputTop * scale - messageBottom)
            end
        end
    end
    local distance = height + 2
    return S.Finite(room) and math.min(distance, room * .5) or distance
end

local function RepaintMessages(push, settled)
    if push.owner.preview then
        if settled then push.repaint() else C.PositionMessages(push.owner, push.frame) end
    elseif not NS.Safety.IsForbidden(push.frame) then
        C.PositionMessages(push.owner, push.frame)
        if settled and not NS.InCombat() then push.frame:MarkDisplayDirty() end
    end
end

local function UpdatePushes(driver, elapsed)
    for frame, push in pairs(moving) do
        local owner = push.owner
        if not owner.preview and (not owner.active or owner.context ~= push.context
            or NS.Safety.IsForbidden(frame) or NS.Safety.IsForbidden(push.input)) then
            moving[frame], pushes[frame] = nil, nil
        elseif push.hold then
            push.hold = push.hold - elapsed
            if push.hold <= 0 then
                push.hold, push.from, push.target, push.elapsed = nil, push.offset, 0, 0
                RepaintMessages(push, true)
            end
        else
            local inCombat = not owner.preview and NS.InCombat()
            if push.elapsed == 0 and not owner.preview and not inCombat then frame:MarkDisplayDirty() end
            if push.target == nil then push.target = PushDistance(push) end
            push.elapsed = push.elapsed + elapsed
            local done = push.elapsed >= push.duration or push.from == push.target or inCombat
            local progress = done and 1 or push.elapsed / push.duration
            local eased = progress * progress * (3 - 2 * progress)
            push.offset = push.from + (push.target - push.from) * eased
            if done then
                if push.demo and push.target > 0 then
                    push.hold = .65
                else
                    moving[frame] = nil
                    if push.target == 0 then pushes[frame] = nil end
                end
            end
            RepaintMessages(push, done)
        end
    end
    if not next(moving) then driver:SetScript("OnUpdate", nil) end
end

local function StartPush(owner, frame, input, opening, repaint)
    local push = pushes[frame]
    if not opening and (not push or not push.open) then return end
    if opening and (not push or push.context ~= owner.context) then
        push = { owner = owner, frame = frame, context = owner.context, offset = 0 }
        pushes[frame] = push
    end
    push.input, push.demo, push.repaint = input, owner.preview, repaint
    push.open, push.from, push.elapsed, push.hold = opening, push.offset, 0, nil
    push.target = 0
    if opening then push.target = nil end
    local bridge = NS.HostBridge
    local reduced = bridge and bridge.MenuReducedMotion and bridge.MenuReducedMotion()
    push.duration = reduced and 0 or (owner.config.inputAnimationDuration or .18)
    moving[frame] = push
    if not pushDriver then pushDriver = S.CreateFrame("Frame", nil, UIParent) end
    pushDriver:SetScript("OnUpdate", UpdatePushes)
end

function C.ResetInputMessagePush(frame)
    local push = pushes[frame]
    if not push then return end
    pushes[frame], moving[frame] = nil, nil
    if not next(moving) then pushDriver:SetScript("OnUpdate", nil) end
    RepaintMessages(push, true)
end

local function Stop(owner)
    local record = records[owner]
    if record then record.group:Stop() end
end

local function Prepare(owner, config)
    if not config.animateInput then
        Stop(owner)
        return
    end
    if NS.Safety.IsForbidden(owner) or owner:IsProtected() then return end
    local record = records[owner]
    if not record then
        local group = owner:CreateAnimationGroup()
        -- The focus callback runs before ActivateChat sets the box to 1;
        -- without this the group would end on the alpha it found at Play
        -- (the IM style's 0.35) and the box would stay dim while typing.
        group:SetToFinalAlpha(true)
        local alpha = group:CreateAnimation("Alpha")
        alpha:SetFromAlpha(0)
        alpha:SetToAlpha(1)
        alpha:SetSmoothing("OUT")
        alpha:SetOrder(2)
        -- An instant first translation establishes the starting position;
        -- the eased second one returns to zero without a final anchor snap.
        local start = group:CreateAnimation("Translation")
        start:SetDuration(0)
        start:SetOrder(1)
        local slide = group:CreateAnimation("Translation")
        slide:SetOrder(2)
        slide:SetSmoothing("OUT")
        record = { group = group, alpha = alpha, start = start, slide = slide }
        records[owner] = record
    end
    local duration = config.inputAnimationDuration or 0.18
    local height = owner:GetHeight()
    if not S.Finite(height) or height <= 0 then height = 32 end
    local distance = math.min(24, math.max(8, height * 0.75))
    if config.inputTop then distance = -distance end
    record.start:SetOffset(0, -distance)
    record.slide:SetOffset(0, distance)
    record.alpha:SetDuration(duration * 0.65)
    record.slide:SetDuration(duration)
    return record
end

local function Activated(owner)
    local record = records[owner]
    if not M.active or not record or record.context ~= M.context or not M.config.animateInput then return end
    record.group:Stop()
    record.group:Play()
end

-- The live input plays on focus and stops on release or hide. These arrive
-- from Suite.ChatState's EventRegistry callbacks for permanent windows only;
-- a script hook on Blizzard's edit box would run inside ActivateChat and
-- DeactivateChat ahead of their chatType writes. Each callback runs before
-- Blizzard's own handler: a box that keeps its text stays active when it
-- loses the focus (ShouldDeactivateChatOnEditFocusLost), so its fade ends
-- at 1; an empty box stops before Blizzard deactivates or hides it.
local function Released(input)
    local text = input:GetText()
    local readable = S.Public(text)
    if readable and text ~= "" then return false end
    Stop(input)
    return readable
end

function C.ApplyInputAnimation(self, input)
    if not P.NS.ChatState.IsPermanentBox(input) then return end
    local record = Prepare(input, self.config)
    if not record then return end
    record.context = self.context
end

function C.InputAnimationEvent(kind, input)
    local closing
    if kind == "focus" then
        Activated(input)
    elseif kind == "release" then
        closing = Released(input)
    elseif kind == "hide" then
        Stop(input)
        closing = true
    end
    local c = M.config
    if not c.inputPushMessages or c.inputTop or NS.Safety.IsForbidden(input) then return end
    if closing then
        for frame, push in pairs(pushes) do
            if push.owner == M and push.input == input then StartPush(M, frame, input, false) end
        end
        return
    end
    if kind ~= "focus" then return end
    local frame = input.chatFrame
    if not S.Public(frame) or not frame or not M.visuals[frame] or NS.Safety.IsForbidden(frame) then return end
    -- Classic chat style sends through the General edit box even when another tab is showing.
    if S.Public(frame.isDocked) and frame.isDocked then
        local selected = C.DockSelection()
        if S.Public(selected) and selected and M.visuals[selected] and not NS.Safety.IsForbidden(selected) then
            frame = selected
        end
    end
    StartPush(M, frame, input, true)
end

-- The sample uses exactly the same native animation group as the live input.
-- Animation transforms never change anchors; the group ends at alpha 1.
function S.ChatPreviewInputAnimation(owner, config, parts)
    local record = Prepare(owner, config)
    if record then
        record.group:Stop()
        record.group:Play()
    end
    if parts and parts.previewOwner then
        if config.inputPushMessages and not config.inputTop then
            StartPush(parts.previewOwner, parts.sample, owner, true, function()
                S.ChatPaintPreviewMessages(parts)
            end)
        else
            C.ResetInputMessagePush(parts.sample)
        end
    end
end

function C.StopInputAnimations()
    for owner in pairs(records) do Stop(owner) end
    for frame, push in pairs(pushes) do
        if push.owner == M then C.ResetInputMessagePush(frame) end
    end
end
