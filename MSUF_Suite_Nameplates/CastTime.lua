local _, private = ...
local NS, S = private.NS, private.Suite
-- Nameplate casts can carry secret values. Never assign CastTimeText to the
-- native bar: its Lua formatter then reads secret StatusBar values in tainted
-- execution. DurationTextBinding formats the opaque duration in the engine.
local CastTime = {}
private.CastTime = CastTime
local M
local formatter

function CastTime.Bind(module) M = module end

local function Safe(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

-- One seconds formatter (C_StringUtil, Retail and Forever) for every plate.
local function Formatter()
    if formatter then return formatter end
    formatter = C_StringUtil.CreateSecondsFormatter()
    formatter:SetMaxInterval(Enum.SecondsFormatterInterval.Seconds)
    formatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
    formatter:SetMillisecondsThreshold(60)
    return formatter
end

function CastTime.Restore(cast)
    local state = cast and M.castTimes[cast]
    if not state or not state.unit then return end
    state.unit = nil
    state.active = false
    state.binding:Disable()
    if Safe(state.label) then state.label:Hide() end
end

-- UnitCastingDuration and UnitChannelDuration return an opaque duration
-- object, or nothing without that kind of cast. The cast duration rule
-- (shared with QualityOfLife/EnemyCastStack.lua): the object may itself be
-- secret (UnitCastingDuration: SecretReturns, UnitDocumentation), and
-- DurationTextBinding:SetDuration takes secret arguments only from untainted
-- code (SecretArguments = "AllowedWhenUntainted"). A public object is bound
-- as it is; a secret one shows no time; a public nil means no such cast.
local function ApplyDuration(state, unit, getter)
    local duration = getter(unit)
    if not S.Public(duration) or duration == nil then return false end
    state.binding:SetDuration(duration)
    state.binding:Enable()
    state.active = true
    state.label:Show()
    return true
end

function CastTime.Refresh(state, unit, event)
    if state.active and (event == "UNIT_SPELLCAST_INTERRUPTIBLE"
        or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE") then return end
    state.active = false
    state.binding:Disable()
    state.label:Hide()
    if not unit then return end
    if event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
        or event == "UNIT_SPELLCAST_EMPOWER_START" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        ApplyDuration(state, unit, UnitChannelDuration)
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
        ApplyDuration(state, unit, UnitCastingDuration)
    elseif event == nil or event == "UNIT_SPELLCAST_INTERRUPTIBLE"
        or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        -- Blizzard can report interruptibility after cast start. Retry both
        -- duration kinds without reading the native bar's secret progress.
        if not ApplyDuration(state, unit, UnitCastingDuration) then
            ApplyDuration(state, unit, UnitChannelDuration)
        end
    end
end

local function Create(cast)
    local binding = C_DurationUtil.CreateDurationTextBinding()
    local label = cast:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlateCastBar")
    label:SetPoint("LEFT", cast, "RIGHT", 4, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(1, 1, 1)
    label:Hide()
    binding:SetFontString(label)
    binding:SetFormatter(Formatter())
    binding:SetUpdateInterval(0.1)
    binding:SetZeroDurationText("")
    binding:SetExpiredText("")
    binding:Disable()
    return { label = label, binding = binding }
end

function CastTime.Paint(cast, prefix, unit)
    if not Safe(cast) then return end
    if not prefix or M.config.look == 2 or M.config.enemyCastEnabled == 3 or not M.config[prefix]
        or M.config[prefix .. "CastTimeEnabled"] == false or not unit then
        CastTime.Restore(cast)
        return
    end
    local state = M.castTimes[cast]
    if not state then
        if NS.IsCombatLocked() then M.needsRefresh = true; return end
        state = Create(cast)
        M.castTimes[cast] = state
    end
    if state.unit ~= unit then
        state.unit = unit
        CastTime.Refresh(state, unit)
    end
end
