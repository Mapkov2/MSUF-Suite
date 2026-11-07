local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.Chat
local M = C.M
local records = setmetatable({}, { __mode = "k" })

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
        owner:HookScript("OnHide", Stop)
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

function C.ApplyInputAnimation(self, input)
    local record = Prepare(input, self.config)
    if not record then return end
    record.context = self.context
    if not record.hooked then
        input:HookScript("OnEditFocusGained", Activated)
        input:HookScript("OnEditFocusLost", Stop)
        record.hooked = true
    end
end

-- The sample uses exactly the same native animation group as the live input.
-- Animation transforms neither change anchors nor write the box's base alpha.
function S.ChatPreviewInputAnimation(owner, config)
    local record = Prepare(owner, config)
    if record then
        record.group:Stop()
        record.group:Play()
    end
end

function C.StopInputAnimations()
    for owner in pairs(records) do Stop(owner) end
end
