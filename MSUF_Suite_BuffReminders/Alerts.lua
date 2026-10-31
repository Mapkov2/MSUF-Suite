local _, P = ...
local NS, S = P.NS, P.Suite
local R = P.BuffReminders
local CHANNELS = { "Master", "SFX", "Dialog" }
-- The catalog's reminderSound choice is an index into this list: new sounds
-- go at the end.
local SOUNDS = { false, "RAID_WARNING", "READY_CHECK", "IG_QUEST_LOG_OPEN", "ALARM_CLOCK_WARNING_3", "MAP_PING",
    "TELL_MESSAGE" }

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
    group = (button.reminderAlertBorder or button.border):CreateAnimationGroup()
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
    local border = button.reminderAlertBorder or button.border
    if button.alertColor ~= color then
        if button.reminderBorderArt then border:SetVertexColor(S.RGB(color))
        else
            border:SetColorTexture(S.RGB(color))
        end
        button.alertColor = color
    end
    if button.reminderSkinned or button.reminderBorderShown == false then
        local shown = not button.reminderSkinned or style > 1
        if button.reminderBorderShown ~= shown then
            button.reminderBorderShown = shown
            border:SetShown(shown)
        end
    end
    local pulsing = visible and style == 3
    if button.alertPulsing == pulsing then return end
    button.alertPulsing = pulsing
    if pulsing then
        Pulse(button):Play()
    else
        if button.alertPulse then button.alertPulse:Stop() end
        border:SetAlpha(1)
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

-- A dismissed reminder stays hidden until the next reload. It is remembered by
-- the identity AlertTransition uses, so it survives recompiles and layout
-- changes.
local function DismissKey(entry)
    return entry.kind .. ":" .. entry.id .. ":" .. (entry.slot or entry.poisonRank or 0)
end

-- PostClick of a reminder button: a right or middle click dismisses it. The
-- button's secure attributes are not touched: its left click still casts or
-- uses. Refused in combat and in Edit Mode, where every reminder shows.
function R.DismissClick(self, button, mouseButton)
    local entry = button.entry
    if mouseButton ~= "RightButton" and mouseButton ~= "MiddleButton" then return end
    if not entry or NS.IsCombatLocked() or S.editMode then return end
    local view = self.view
    view.dismissed = view.dismissed or {}
    view.dismissed[DismissKey(entry)] = true
    entry.dismissed = true
    -- The reminder keeps its bit in the mask; repainting hides it (ShowMask).
    view.mask = nil
    self:Update("visual")
end

-- A new reminder list marks the entries the player dismissed before.
function R.RestoreDismissed(self, entries)
    local dismissed = self.view.dismissed
    if not dismissed then return end
    for _, entry in ipairs(entries) do entry.dismissed = dismissed[DismissKey(entry)] end
end
