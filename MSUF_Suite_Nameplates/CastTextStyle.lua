local _, private = ...
local NS = private.NS
local Accessible = private.CastAppearance.Accessible
local CastTextStyle = {}
private.CastTextStyle = CastTextStyle

local states = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })

local function Utf8Prefix(name, count)
    for index in name:gmatch("()[^\128-\191]") do
        if count == 0 then return name:sub(1, index - 1) .. "..." end
        count = count - 1
    end
    return name
end

local function FitName(cast, label, name, settings, suffix)
    local maximum = settings.nameMax or 30
    local shortened = Utf8Prefix(name, maximum)
    local reserve = settings.nameReserve or 0
    if reserve <= 0 or not label.GetUnboundedStringWidthForText then return shortened end

    -- Measure only public text. The actual anchors still belong to Blizzard
    -- and the Suite's layout, including the cast target attached to the name.
    local right, left = cast:GetRight(), label:GetLeft()
    if not NS.Finite(right) or not NS.Finite(left) or right <= left then return shortened end
    local budget = right - left - reserve
    local width = label:GetUnboundedStringWidthForText(shortened .. suffix)
    if not NS.Finite(width) or width <= budget then return shortened end

    local best = Utf8Prefix(name, 0)
    local lo, hi = 1, maximum - 1
    while lo <= hi do
        local middle = math.floor((lo + hi) / 2)
        local candidate = Utf8Prefix(name, middle)
        width = label:GetUnboundedStringWidthForText(candidate .. suffix)
        if not NS.Finite(width) then return shortened end
        if width <= budget then
            best, lo = candidate, middle + 1
        else
            hi = middle - 1
        end
    end
    return best
end

local function ReadActiveCast(cast)
    local unit = cast.unit
    if not NS.Public(unit) or type(unit) ~= "string" then return end
    local casting, channel, empower = cast.casting, cast.channeling, cast.reverseChanneling
    if not NS.Public(casting) or not NS.Public(channel) or not NS.Public(empower) then return end
    if channel == true or empower == true then
        local _, name = UnitChannelInfo(unit)
        return name
    elseif casting == true then
        local _, name, _, _, _, _, _, _, _, _, delay = UnitCastingInfo(unit)
        return name, delay
    end
end

local function Paint(cast, state)
    if not Accessible(cast) then return false end
    local shown = cast:IsShown()
    if not NS.Public(shown) or not shown then return true end
    local label = cast.Text
    if not Accessible(label) then return false end
    local name, delay = ReadActiveCast(cast)
    local settings = state.settings
    local public = NS.Public(name)
    if public and (type(name) ~= "string" or name == "") then return true end
    local seconds = settings and settings.showPushback and NS.Finite(delay) and delay > 0 and delay / 1000
    if public then
        local suffix = seconds and (" +%.1f"):format(seconds) or ""
        local text = settings and settings.shortenName and FitName(cast, label, name, settings, suffix) or name
        text = text .. suffix
        if text ~= name or state.changed then label:SetText(text) end
        state.changed = text ~= name
    elseif seconds then
        -- Never measure, format in Lua or cache a restricted spell name.
        label:SetFormattedText("%s +%.1f", name, seconds)
        state.changed = true
    elseif state.changed then
        label:SetText(name)
        state.changed = false
    end
    return true
end

local function OnCastStart(cast)
    local state = states[cast]
    if not state then return end
    -- Blizzard has just assigned the new native spell label. A paint from
    -- the plate's previous cast must never be restored over that label.
    state.changed = false
    if state.settings then state.pending = not Paint(cast, state) end
end

local function OnCastDelayed(cast)
    local state = states[cast]
    if state and state.settings and state.settings.showPushback then
        state.pending = not Paint(cast, state)
    end
end

function CastTextStyle.Restore(cast)
    if not NS.Public(cast) then return false end
    local state = states[cast]
    if not state then return true end
    state.settings = nil
    if state.changed and not Paint(cast, state) then return false end
    states[cast] = nil
    return true
end

function CastTextStyle.Apply(cast, settings, reset)
    if not NS.Public(cast) then return false end
    if not cast or not settings or not (settings.shortenName or settings.showPushback) then
        return CastTextStyle.Restore(cast)
    end
    if not Accessible(cast) then return false end
    local state = states[cast]
    if not state then
        state = {}
        states[cast] = state
    elseif state.settings == settings and not state.pending and not reset then
        return true
    end
    if not hooked[cast] then
        -- The native mixin calls these methods even when a plate is acquired
        -- during an existing cast and no CastBar OnEvent script fires.
        hooksecurefunc(cast, "HandleCastStart", OnCastStart)
        hooksecurefunc(cast, "HandleCastDelayed", OnCastDelayed)
        hooked[cast] = true
    end
    state.settings = settings
    state.pending = not Paint(cast, state)
    return not state.pending
end
