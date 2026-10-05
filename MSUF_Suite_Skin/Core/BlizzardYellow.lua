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
local SameColor, ColorMatches = Safety.SameColor, Safety.ColorMatches
local COLOR_OWN = Safety.COLOR_OWN

-- Native GameFontNormal-family gold.
local NATIVE_R, NATIVE_G, NATIVE_B = 1.000, 0.820, 0.000

-- The configured color, refreshed at every entry point. Reused so that
-- pooled rows can be tracked without allocating.
local desired = { 0, 0, 0, 1 }

local function RefreshDesiredColor()
    desired[1], desired[2], desired[3], desired[4] = NS.Theme.GetColor("blizzardYellow")
end

-- Classifies Blizzard's own gold; its alpha does not matter.
local function IsNativeYellow(r, g, b)
    return SameColor(r, g, b, nil, NATIVE_R, NATIVE_G, NATIVE_B, nil, Safety.COLOR_NATIVE)
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

-- A region's object type never changes. Surfaces rescan their regions on
-- every re-attach (pooled rows are re-initialized with native gold), so each
-- region is asked once.
local fontStringRegions = setmetatable({}, { __mode = "k" })

local function IsFontString(region)
    if type(region) ~= "table" then return false end
    local known = fontStringRegions[region]
    if known == nil then
        known = Safety.Read(region, "GetObjectType") == "FontString"
        fontStringRegions[region] = known
    end
    return known
end

-- Catalog fonts by name, verified once. A name whose font does not exist
-- yet (its load-on-demand addon has not loaded) is checked again on the
-- next apply; no apply enumerates every client font.
local fontObjects = {}

local function CatalogFont(name)
    local object = fontObjects[name]
    if object == nil then
        local candidate = _G[name]
        if type(candidate) == "table" and Safety.Read(candidate, "GetObjectType") == "Font" then
            object = candidate
            fontObjects[name] = object
        end
    end
    return object
end

local function RestoreObject(object, state)
    local r, g, b, a = ReadTextColor(object)
    if not r or not ColorMatches(state.applied, r, g, b, a, COLOR_OWN) then
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
        if not ColorMatches(state.applied, r, g, b, a, COLOR_OWN) and not IsNativeYellow(r, g, b) then
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
    if not IsNativeYellow(r, g, b) and not ColorMatches(desired, r, g, b, a, COLOR_OWN) then return false end

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

-- 12.1 can return secret regions (Hierarchy aspect); they are skipped before
-- any comparison or lookup. Every node of a window pass comes here with all
-- its regions, so Safety.Public and IsFontString's cache are inlined.
local function TrackRegions(...)
    local count = 0
    local isSecret, known = issecretvalue, fontStringRegions
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if (isSecret == nil or not isSecret(region)) and type(region) == "table" then
            local fontString = known[region]
            if fontString == nil then fontString = IsFontString(region) end
            if fontString and ApplyObject(region, BlizzardYellow.directStates) then
                count = count + 1
            end
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

-- TrackFrame over frames[1..count] (a pooled row's subtree): the enable and
-- combat gates and the configured color are read once for the whole list.
function BlizzardYellow.TrackFrames(frames, count)
    if not (NS.DB and NS.DB.enabled) or NS.IsCombatLocked() then return 0 end
    RefreshDesiredColor()
    local tracked = 0
    for index = 1, count do
        local frame = frames[index]
        if type(frame) == "table" and not Safety.IsForbidden(frame) and type(frame.GetRegions) == "function" then
            tracked = tracked + TrackRegions(frame:GetRegions())
        end
    end
    return tracked
end

-- Returns the number recolored and whether text was one of the regions.
local function TrackKnownRegions(text, ...)
    local count, textSeen = 0, false
    local Public = Safety.Public
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if Public(region) then
            if region == text then textSeen = true end
            if IsFontString(region) and ApplyKnownNativeObject(region) then
                count = count + 1
            end
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
    local names = NS.BlizzardFontNames
    local count = 0
    for index = 1, #names do
        local object = CatalogFont(names[index])
        if object and ApplyObject(object, BlizzardYellow.states) then
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

-- Settings writes arrive once per slider tick or colour-picker move; the
-- full font pass they need runs once on the next frame (Registry.QueueJob).
local function ApplyQueued() BlizzardYellow.Apply() end

function BlizzardYellow:OnThemeChanged(domain, key)
    if domain == "color" and key ~= "blizzardYellow" then return end
    if domain ~= "color" and domain ~= "theme" and domain ~= "profile" then return end
    NS.Registry.QueueJob(ApplyQueued)
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
