local _, P = ...
local S = P.Suite
local C = P.Chat

-- Allocate bounded native animation groups on the settings/window path.
-- There is no Lua animation tick and no work while the group is stopped.
function C.PrepareFadeAnimations(visual, seconds)
    visual.fadeDuration = seconds or 0
    if visual.fadeDuration <= 0 then return end
    visual.fadeAnimations = visual.fadeAnimations or {}
    for index, part in pairs(visual.fadeParts) do
        local record = visual.fadeAnimations[index]
        if not record or record.part ~= part then
            if record then record.group:Stop() end
            record = { part = part, group = part:CreateAnimationGroup() }
            record.alpha = record.group:CreateAnimation("Alpha")
            record.alpha:SetSmoothing("IN_OUT")
            record.group:SetScript("OnFinished", function()
                -- Without set-to-final-alpha, commit only while the getter
                -- still matches our value. Foreign writes take precedence.
                local current = part:GetAlpha()
                if S.Finite(current) and current == visual.fadeApplied[index] then
                    part:SetAlpha(record.target)
                    visual.fadeApplied[index] = record.target
                end
            end)
            visual.fadeAnimations[index] = record
        end
    end
end

function C.StopFadeAnimation(visual, index)
    local record = visual.fadeAnimations and visual.fadeAnimations[index]
    if record then record.group:Stop() end
end

function C.FadePart(visual, index, target)
    local part = visual.fadeParts[index]
    local record = visual.fadeAnimations and visual.fadeAnimations[index]
    local current = part:GetAlpha()
    if not S.Finite(current) then return end
    if record and visual.fadeDuration > 0 and current ~= target then
        record.group:Stop()
        record.target = target
        record.alpha:SetFromAlpha(current)
        record.alpha:SetToAlpha(target)
        record.alpha:SetDuration(visual.fadeDuration)
        visual.fadeApplied[index] = current
        record.group:Play()
    else
        part:SetAlpha(target)
        visual.fadeApplied[index] = target
    end
end
