local _, NS = ...

-- Recolors Blizzard's normal gold text without global frame enumeration. The
-- generated BlizzardFontNames whitelist covers existing FontObjects, while
-- bounded adapters recolor later FontStrings when Blizzard exposes them.
-- Global color constants are never read or written: BuffFrame and other 12.1
-- secret-data paths consume those tables directly, so addon ownership would
-- taint their execution.
local BlizzardYellow = {
    states = setmetatable({}, { __mode = "k" }),
    directStates = setmetatable({}, { __mode = "k" }),
    appliedCount = 0,
    directCount = 0,
}
NS.BlizzardYellow = BlizzardYellow

local Safety = NS.Safety

local EPSILON = 0.015
-- Native GameFontNormal-family gold.
local NATIVE_R, NATIVE_G, NATIVE_B = 1.000, 0.820, 0.000

-- The configured color, refreshed at every entry point. Reused so that
-- pooled rows can be tracked without allocating.
local desired = { 0, 0, 0, 1 }

local function RefreshDesiredColor()
    desired[1], desired[2], desired[3], desired[4] = NS.Theme.GetColor("blizzardYellow")
end

local function Close(left, right)
    return math.abs(left - right) <= EPSILON
end

local function MatchesColor(color, r, g, b, a)
    return Close(r, color[1]) and Close(g, color[2]) and Close(b, color[3]) and Close(a, color[4])
end

local function IsNativeYellow(r, g, b)
    return Close(r, NATIVE_R) and Close(g, NATIVE_G) and Close(b, NATIVE_B)
end

local function CopyColor(target, source)
    target[1], target[2], target[3], target[4] = source[1], source[2], source[3], source[4]
    return target
end

local function SetTextColor(object, color)
    object:SetTextColor(color[1], color[2], color[3], color[4])
end

-- Text color as plain numbers. Secret or missing colors read as nil and are
-- never compared or tracked.
local function ReadTextColor(object)
    if type(object) ~= "table" or type(object.SetTextColor) ~= "function" then return nil end
    return Safety.ReadColor(object, "GetTextColor")
end

local function IsFontString(region)
    return type(region) == "table" and Safety.Read(region, "GetObjectType") == "FontString"
end

local function LoadedFontSet()
    local loaded = {}
    local names = type(GetFonts) == "function" and GetFonts() or nil
    if type(names) ~= "table" then return loaded end
    for index = 1, #names do loaded[names[index]] = true end
    return loaded
end

local function RestoreObject(object, state)
    local r, g, b, a = ReadTextColor(object)
    if not r or not MatchesColor(state.applied, r, g, b, a) then
        return false
    end
    SetTextColor(object, state.original)
    return true
end

-- Recolors native gold, or text still showing our previous color.
local function ApplyObject(object, states)
    local r, g, b, a = ReadTextColor(object)
    if not r then return false end
    local state = states[object]
    if state then
        if not MatchesColor(state.applied, r, g, b, a) and not IsNativeYellow(r, g, b) then
            return false
        end
    elseif IsNativeYellow(r, g, b) then
        state = { original = { r, g, b, a }, applied = {} }
        states[object] = state
    else
        return false
    end
    SetTextColor(object, desired)
    CopyColor(state.applied, desired)
    return true
end

-- A verified selected dropdown label may already equal the configured source
-- color by the time its pooled FontString is exposed. Record its native origin
-- explicitly so disabling MapkoSkin remains reversible even for late rows.
local function ApplyKnownNativeObject(object)
    local r, g, b, a = ReadTextColor(object)
    if not r then return false end
    if BlizzardYellow.directStates[object] then
        return ApplyObject(object, BlizzardYellow.directStates)
    end
    if not IsNativeYellow(r, g, b) and not MatchesColor(desired, r, g, b, a) then return false end

    SetTextColor(object, desired)
    BlizzardYellow.directStates[object] = {
        original = { NATIVE_R, NATIVE_G, NATIVE_B, a },
        applied = CopyColor({}, desired),
    }
    return true
end

local function CountStates(states)
    local count = 0
    for _ in pairs(states) do count = count + 1 end
    return count
end

function BlizzardYellow.Restore()
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("blizzard-yellow:restore", BlizzardYellow.Restore)
        return false, "combat"
    end
    for object, state in pairs(BlizzardYellow.states) do
        RestoreObject(object, state)
        BlizzardYellow.states[object] = nil
    end
    for object, state in pairs(BlizzardYellow.directStates) do
        RestoreObject(object, state)
        BlizzardYellow.directStates[object] = nil
    end
    BlizzardYellow.appliedCount = 0
    BlizzardYellow.directCount = 0
    return true
end

local function CanTrack(frame)
    return NS.DB and NS.DB.enabled and not NS.IsCombatLocked()
        and type(frame) == "table" and not Safety.IsForbidden(frame)
end

local function TrackRegions(...)
    local count = 0
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if IsFontString(region) and ApplyObject(region, BlizzardYellow.directStates) then
            count = count + 1
        end
    end
    return count
end

-- Recolor only FontStrings already reached through a known Blizzard adapter.
-- This intentionally avoids global frame enumeration and never walks unrelated
-- addon globals. GenericWindows and Surface call this on bounded/exact targets,
-- including pooled ScrollBox rows when Blizzard initializes them.
function BlizzardYellow.TrackFrame(frame)
    if not CanTrack(frame) or type(frame.GetRegions) ~= "function" then return 0 end
    RefreshDesiredColor()
    return TrackRegions(frame:GetRegions())
end

-- Returns the number recolored and whether text was one of the regions.
local function TrackKnownRegions(text, ...)
    local count, textSeen = 0, false
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if region == text then textSeen = true end
        if IsFontString(region) and ApplyKnownNativeObject(region) then
            count = count + 1
        end
    end
    return count, textSeen
end

local function TrackKnownFrame(frame)
    if not CanTrack(frame) then return 0 end
    RefreshDesiredColor()
    -- Text is usually one of the regions, but a template may parent its
    -- label to a child frame. It is visited once either way.
    local text = frame.Text
    local count, textSeen = 0, false
    if type(frame.GetRegions) == "function" then
        count, textSeen = TrackKnownRegions(text, frame:GetRegions())
    end
    if not textSeen and IsFontString(text) and ApplyKnownNativeObject(text) then
        count = count + 1
    end
    return count
end

-- These two entry points are intentionally narrow: only a verified modern
-- DropdownButton selection label and a selected MenuTemplate row may opt into
-- the known-native path above.
function BlizzardYellow.TrackDropdown(button)
    if Safety.Read(button, "IsEnabled") == false then return 0 end
    return TrackKnownFrame(button)
end

function BlizzardYellow.TrackMenuSelection(row)
    local description = Safety.Call(row, "GetElementDescription")
    if type(description) ~= "table" or Safety.Read(description, "IsSelected") ~= true
        or Safety.Read(description, "IsEnabled") == false then
        return 0
    end
    return TrackKnownFrame(row)
end

function BlizzardYellow.Apply()
    if not NS.DB then return false, "uninitialized" end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("blizzard-yellow:apply", BlizzardYellow.Apply)
        return false, "combat"
    end
    if not NS.DB.enabled then return BlizzardYellow.Restore() end

    RefreshDesiredColor()
    local loaded = LoadedFontSet()
    local names = NS.BlizzardFontNames or {}
    local count = 0
    for index = 1, #names do
        local name = names[index]
        if loaded[name] and ApplyObject(_G[name], BlizzardYellow.states) then
            count = count + 1
        end
    end
    local directCount = 0
    for object in pairs(BlizzardYellow.directStates) do
        if ApplyObject(object, BlizzardYellow.directStates) then directCount = directCount + 1 end
    end
    BlizzardYellow.appliedCount = count
    BlizzardYellow.directCount = CountStates(BlizzardYellow.directStates)
    return true, count + directCount
end

function BlizzardYellow:OnThemeChanged(domain, key)
    if domain == "color" and key ~= "blizzardYellow" then return end
    if domain ~= "color" and domain ~= "theme" and domain ~= "profile" then return end
    BlizzardYellow.Apply()
end

function BlizzardYellow.GetStatus()
    -- This is diagnostic bookkeeping, not rendering work. Count only when
    -- requested, including keys collected since the last frame was styled.
    BlizzardYellow.directCount = CountStates(BlizzardYellow.directStates)
    return {
        applied = BlizzardYellow.appliedCount,
        direct = BlizzardYellow.directCount,
        source = false,
    }
end

NS.Registry.AddListener(BlizzardYellow, BlizzardYellow.OnThemeChanged)

return BlizzardYellow
