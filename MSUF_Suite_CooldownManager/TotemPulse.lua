local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Optional next-pulse hints for the player's own, publicly identified totems.

if not NS.Client.isForever then return end
local _, class = UnitClass("player")
if not S.Public(class) or class ~= "SHAMAN" then return end

local Pulse = {}
C.TotemPulse = Pulse

-- Forever spell tooltips: Healing Stream every 2 s, Mana Tide every 3 s.
-- Use a verified cast family, and treat placement as an estimated phase.
local intervals = { [5394] = 2, [16190] = 3 }
local floor = math.floor

local function Stop(clock)
    if not clock or not clock.cycle then return end
    clock.cycle, clock.interval = nil, nil
    clock:Hide()
    clock:Clear()
end

function Pulse.Release(icon)
    local clock = icon.totemPulseClock
    if not clock then return end
    clock.entry = nil
    Stop(clock)
end

local function Visible(icon, entry)
    local bar = C.bars[entry.slot]
    return not (bar and bar.hidden) and icon:IsVisible() and icon.coolAlpha ~= 0 and not icon.sim
end

local function Refresh(icon)
    local clock = icon.totemPulseClock
    local entry = clock and clock.entry
    if not entry or entry.icon ~= icon or not Visible(icon, entry) then return Stop(clock) end
    local have, _, start, length, _, _, spell = GetTotemInfo(entry.id)
    Pulse.Sync(icon, entry, have, start, length, spell)
end

local function OnHide(icon) Stop(icon.totemPulseClock) end
local function OnDone(clock) Refresh(clock.icon) end

local function Create(icon)
    local clock = S.CreateFrame("Cooldown", nil, icon.over, "CooldownFrameTemplate")
    clock:SetSize(12, 12)
    clock:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -1, -1)
    clock:SetDrawSwipe(true)
    clock:SetSwipeColor(.35, .8, .95, .9)
    clock:SetDrawEdge(false)
    clock:SetDrawBling(false)
    clock:SetHideCountdownNumbers(false)
    local text = clock:GetCountdownFontString()
    if text then
        S.SetFont(text, nil, 10, "OUTLINE")
        text:SetTextColor(.6, .95, 1)
        text:ClearAllPoints()
        text:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -2, -2)
    end
    clock:SetScript("OnCooldownDone", OnDone)
    clock:Hide()
    clock.icon = icon
    icon.totemPulseClock = clock
    icon:HookScript("OnShow", Refresh)
    icon:HookScript("OnHide", OnHide)
    return clock
end

function Pulse.Sync(icon, entry, have, start, length, spell)
    if not (entry.ov and entry.ov.totemPulse == true) then return Pulse.Release(icon) end
    local clock = icon.totemPulseClock
    if clock then clock.entry = entry end
    if not S.Public(have) or not S.Finite(start) or not S.Finite(length) or not S.Finite(spell) then
        return Stop(clock)
    end
    if have ~= true or length <= 0 then return Stop(clock) end
    local interval = intervals[C.Ranks.Canon(spell)]
    if not interval then return Stop(clock) end
    local now = GetTime()
    local elapsed = now - start
    if elapsed < 0 or elapsed >= length then return Stop(clock) end
    clock = clock or Create(icon)
    clock.entry = entry
    if not Visible(icon, entry) then return Stop(clock) end
    -- The native completion script can run just before a float boundary.
    local cycle = start + floor((elapsed + .02) / interval) * interval
    if cycle + interval > start + length then return Stop(clock) end
    if clock.cycle == cycle and clock.interval == interval then return end
    clock.cycle, clock.interval = cycle, interval
    clock:SetCooldown(cycle, interval)
    clock:Show()
end

-- Native visibility rules sometimes set alpha without hiding an owned bar.
-- Reuse their transitions and the existing, tiny index of active totem slots.
function Pulse.BarVisibility(slot, hidden)
    local list = C.Index.totems
    for i = 1, #list do
        local entry = list[i]
        local icon = entry.icon
        if entry.slot == slot and icon then
            if hidden then
                Stop(icon.totemPulseClock)
            elseif entry.ov and entry.ov.totemPulse == true then
                local have, _, start, length, _, _, spell = GetTotemInfo(entry.id)
                Pulse.Sync(icon, entry, have, start, length, spell)
            end
        end
    end
end
