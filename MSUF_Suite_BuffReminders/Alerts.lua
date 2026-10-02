local _, P = ...
local S = P.Suite
local R = P.BuffReminders
local CHANNELS = { "Master", "SFX", "Dialog" }
local SOUNDS = { false, "RAID_WARNING", "READY_CHECK", "IG_QUEST_LOG_OPEN" }

-- The border effect of an entry's category, and its color.
local function BorderStyle(self, entry)
    local c = self.config
    local style = c.reminderGlow or 1
    local category = entry and entry.category or "personal"
    local own = c[category .. "_glow"] or 1
    if own > 1 then style = own - 1 end
    local color = style > 1 and c.reminderGlowColor or c.borderColor
    if own > 1 and style > 1 then color = c[category .. "_glowColor"] end
    return style, color or "e8b855"
end

local function Pulse(button)
    local group = button.alertPulse
    if group then return group end
    group = button.border:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(.25)
    alpha:SetToAlpha(1)
    alpha:SetDuration(.65)
    button.alertPulse = group
    return group
end

-- Runs for every button on each mask change. Only a newly visible reminder
-- plays sound: the identity (kind, ID, slot or poison rank) survives
-- recompiles and layout changes, and one sound covers a batch. The border
-- and its pulse change only when their style or color changes, so a running
-- pulse is never restarted.
function R.AlertTransition(self, button, entry, visible)
    local kind, id, slot
    if visible and entry then kind, id, slot = entry.kind, entry.id, entry.slot or entry.poisonRank or 0 end
    if kind and (button.alertKind ~= kind or button.alertID ~= id or button.alertSlot ~= slot) then
        self.view.newAlert = true
    end
    button.alertKind, button.alertID, button.alertSlot = kind, id, slot
    local style, color = BorderStyle(self, entry)
    if button.alertColor ~= color then
        button.border:SetColorTexture(S.RGB(color))
        button.alertColor = color
    end
    local pulsing = visible and style == 3
    if button.alertPulsing == pulsing then return end
    button.alertPulsing = pulsing
    if pulsing then
        Pulse(button):Play()
    else
        if button.alertPulse then button.alertPulse:Stop() end
        button.border:SetAlpha(1)
    end
end

function R.PlayReminderAlert(self)
    local view = self.view
    if not view.newAlert then return end
    view.newAlert = nil
    local name = SOUNDS[self.config.reminderSound or 1]
    if name and not S.editMode then
        PlaySound(SOUNDKIT[name], CHANNELS[self.config.reminderSoundChannel or 1] or "Master")
    end
end

-- Forgets every identity and border state, so a later reminder starts fresh.
function R.StopReminderAlerts(self)
    local view = self.view
    for _, button in ipairs(view.buttons or {}) do
        button.alertKind, button.alertID, button.alertSlot = nil, nil, nil
        button.alertColor, button.alertPulsing = nil, nil
        if button.alertPulse then button.alertPulse:Stop() end
    end
    view.newAlert = nil
end
