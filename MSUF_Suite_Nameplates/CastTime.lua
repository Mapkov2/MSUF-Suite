local _, private = ...
local NS, S = private.NS, private.Suite
local LOOK_BLIZZARD, HIDE = private.Mode.LOOK_BLIZZARD, private.Mode.HIDE
local Key, Text = private.Key, private.Text
-- Nameplate casts can carry secret values. Never assign CastTimeText to the
-- native bar: its Lua formatter then reads secret StatusBar values in tainted
-- execution. DurationTextBinding formats the opaque duration in the engine.
local CastTime = {}
private.CastTime = CastTime
local M
local formatter
local elapsedComponents
local IN_COMBAT = { inCombat = true }
local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_STOP" }
local CAST_UPDATES = { "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }
-- Cast-dependent presentation needs the edges. Timing and readiness also need updates.
local CAST_GROUPS = { CAST_EVENTS, CAST_UPDATES }

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

-- DurationTextBinding and NumericRuleFormatter (upstream/ptr and forever)
-- format elapsed/total entirely in the engine, including secret contents.
local function ApplyFormat(state, choice)
    local elapsed = choice == 2
    if state.elapsed == elapsed then return end
    state.elapsed = elapsed
    if elapsed then
        if not elapsedComponents then
            local seconds = C_StringUtil.CreateNumericRuleFormatter()
            seconds:AddBreakpoint({ threshold = 0, format = "%.1fs" })
            elapsedComponents = {
                { property = Enum.DurationTextBindingProperty.ElapsedDuration, formatter = seconds },
                { property = Enum.DurationTextBindingProperty.TotalDuration, formatter = seconds },
            }
        end
        state.binding:SetTextFormat("{}/{}", elapsedComponents)
    else
        state.binding:SetFormatter(Formatter())
    end
end

function CastTime.Restore(cast)
    local state = cast and M.castTimes[cast]
    if not state or not state.unit then return end
    state.unit = nil
    if state.active == false then return end
    -- A forbidden label still needs to be hidden when the plate is reused.
    state.active = nil
    state.binding:Disable()
    if Safe(state.label) then
        state.label:Hide()
        state.active = false
    end
end

-- UnitCastingDuration, UnitChannelDuration and UnitEmpoweredChannelDuration
-- return an opaque duration object, or nothing without that kind of cast.
-- An empowered cast's time comes from the empowered channel's own duration
-- (UnitDocumentation, Retail and Forever), which includes the hold at its
-- top stage by default. The cast duration rule
-- (shared with QualityOfLife/EnemyCastStack.lua): the object may itself be
-- secret (UnitCastingDuration: SecretReturns, UnitDocumentation), and
-- DurationTextBinding:SetDuration takes secret arguments only from untainted
-- code (SecretArguments = "AllowedWhenUntainted"). A public object is bound
-- as it is; a secret one shows no time; a public nil means no such cast.
local PaintTimeFont
local function OnCastShown(cast)
    local state = M.castTimes[cast]
    if state and state.unit and state.active == true then PaintTimeFont(state, true) end
end

PaintTimeFont = function(state, shown)
    local style = state.timeStyle
    if not style or state.appliedTimeStyle == style then return end
    local cast = state.cast
    if not shown then
        if not Safe(cast) then return end
        local visible = cast:IsShown()
        if S.Public(visible) and visible == false then
            if not state.fontHook then
                cast:HookScript("OnShow", OnCastShown)
                state.fontHook = true
            end
            return
        end
    end
    if Text.Apply(state.label, style, style.size, true) then state.appliedTimeStyle = style end
end

local function ApplyDuration(state, unit, getter)
    local duration = getter(unit)
    if not S.Public(duration) or duration == nil then return false end
    PaintTimeFont(state)
    state.binding:SetDuration(duration)
    state.binding:Enable()
    state.active = true
    state.label:Show()
    return true
end

function CastTime.Refresh(state, unit, event)
    if state.active and (event == "UNIT_SPELLCAST_INTERRUPTIBLE"
        or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE") then return end
    if state.active ~= false then
        state.active = nil
        state.binding:Disable()
        state.label:Hide()
        state.active = false
    end
    if not unit then return end
    if event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        ApplyDuration(state, unit, UnitChannelDuration)
    elseif event == "UNIT_SPELLCAST_EMPOWER_START" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        ApplyDuration(state, unit, UnitEmpoweredChannelDuration)
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
        ApplyDuration(state, unit, UnitCastingDuration)
    elseif event == nil or event == "UNIT_SPELLCAST_INTERRUPTIBLE"
        or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        -- Blizzard can report interruptibility after cast start. Retry both
        -- duration kinds without reading the native bar's secret progress.
        -- A channel may be an empower already running when the plate appears:
        -- its own duration (nothing for other channels) adds the hold.
        if not ApplyDuration(state, unit, UnitCastingDuration)
            and ApplyDuration(state, unit, UnitChannelDuration) then
            ApplyDuration(state, unit, UnitEmpoweredChannelDuration)
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
    return { cast = cast, label = label, binding = binding, active = false }
end

local function WantsTime(config, prefix)
    return prefix and config.look ~= LOOK_BLIZZARD and config.enemyCastEnabled ~= HIDE
        and config[prefix] and config[Key[prefix].CastTimeEnabled] ~= false
end

-- uf: the plate of this castbar; a label combat holds back is made when the
-- end of combat applies that plate again (Skin.lua OnCombatEnded).
function CastTime.Paint(cast, prefix, unit, uf)
    if not cast then return end
    if not unit or not WantsTime(M.config, prefix) then
        CastTime.Restore(cast)
        return
    end
    if NS.Safety.IsForbidden(cast) then return end
    local state = M.castTimes[cast]
    if not state then
        if NS.IsCombatLocked() then
            M.pendingPlates[uf] = true
            return
        end
        state = Create(cast)
        M.castTimes[cast] = state
    end
    local format = M.config[Key[prefix].CastTimeFormat] or 1
    if format == 2 or state.elapsed then ApplyFormat(state, format) end
    local styles = Text and Text.styles
    state.timeStyle = styles and styles[Key[prefix].Cast].time
    if state.unit ~= unit then
        state.unit = unit
        CastTime.Refresh(state, unit)
    elseif state.active == true then
        PaintTimeFont(state)
    end
end

function CastTime.OnChanged(module, event, unit, ...)
    if not module.active or not S.Public(unit) or type(unit) ~= "string" then return end
    if module.castTimeEvents or module.kickEvents then
        local uf = module.activeUnits[unit]
        if not Safe(uf) then return end
        local cast = uf.CastBarsContainer and uf.CastBarsContainer.castBar
        if cast then
            local state = module.castTimeEvents and module.castTimes[cast]
            if state and state.unit == unit then CastTime.Refresh(state, unit, event) end
            if module.kickEvents then private.KickReady.OnCast(cast, unit, event) end
        end
    end
    if private.Extensions.usesCasts then private.Extensions.OnCast(module, event, unit, ...) end
end

function CastTime.SyncEvents(module)
    if not module.active then return end
    local c = module.config
    local kick = private.KickReady.castEvents and c.look ~= LOOK_BLIZZARD and c.enemy and c.enemyCastEnabled ~= HIDE
    local time = WantsTime(c, "enemy") or WantsTime(c, "friendly")
    module.kickEvents, module.castTimeEvents = kick, time
    local mode = (kick or time) and 2 or private.Extensions.usesCasts and 1 or 0
    local previous = module.castListening or 0
    if mode == previous then return end
    module.castListening = mode
    for i, events in ipairs(CAST_GROUPS) do
        local needed = mode >= i
        if needed ~= (previous >= i) then
            for _, event in ipairs(events) do
                if needed then
                    module.context:Event(event, CastTime.OnChanged, IN_COMBAT)
                else
                    module.context:RemoveEvent(event)
                end
            end
        end
    end
end

-- MSUF's interrupt-ready settings were applied: repaint the castbars of the
-- shown plates (KickReady.lua decides from MSUF's switch and look).
function CastTime.Repaint()
    for _, uf in pairs(M.activeUnits) do
        local health = Safe(uf) and uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
        local cast = health and uf.CastBarsContainer and uf.CastBarsContainer.castBar
        if cast and (not private.IsSkinSuppressed or not private.IsSkinSuppressed(uf)) then
            private.KickReady.Paint(cast, private.PlatePrefix(uf), M.units[health])
        end
    end
end
