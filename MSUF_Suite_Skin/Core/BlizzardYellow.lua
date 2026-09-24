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

local EPSILON = 0.015
local nativeYellow = {
    { 1.000, 0.820, 0.000 }, -- native GameFontNormal-family gold
}

local function Close(left, right)
    return type(left) == "number" and math.abs(left - right) <= EPSILON
end

local function ReadColor(object)
    if not object or type(object.GetTextColor) ~= "function" then return nil end
    local ok, r, g, b, a = pcall(object.GetTextColor, object)
    if not ok or type(r) ~= "number" then return nil end
    return { r, g, b, tonumber(a) or 1 }
end

local function SameColor(left, right)
    return left and right and Close(left[1], right[1]) and Close(left[2], right[2])
        and Close(left[3], right[3]) and Close(left[4], right[4])
end

local function IsNativeYellow(color)
    if not color then return false end
    for index = 1, #nativeYellow do
        local candidate = nativeYellow[index]
        if Close(color[1], candidate[1]) and Close(color[2], candidate[2])
            and Close(color[3], candidate[3]) then
            return true
        end
    end
    return false
end

local function LoadedFontSet()
    local loaded = {}
    if type(GetFonts) ~= "function" then return loaded end
    local ok, names = pcall(GetFonts)
    if not ok or type(names) ~= "table" then return loaded end
    for index = 1, #names do loaded[names[index]] = true end
    return loaded
end

local function RestoreObject(object, state)
    local current = ReadColor(object)
    if not SameColor(current, state.applied) or type(object.SetTextColor) ~= "function" then
        return false
    end
    local original = state.original
    local ok = pcall(object.SetTextColor, object, original[1], original[2], original[3], original[4])
    return ok
end

local function ApplyObject(object, states, desired)
    local current = ReadColor(object)
    local state = states[object]
    if state and (SameColor(current, state.applied) or IsNativeYellow(current)) then
        local ok = pcall(object.SetTextColor, object, desired[1], desired[2], desired[3], desired[4])
        if ok then
            state.applied = { desired[1], desired[2], desired[3], desired[4] }
            return true
        end
    elseif not state and IsNativeYellow(current) and type(object.SetTextColor) == "function" then
        local applied = { desired[1], desired[2], desired[3], desired[4] }
        local ok = pcall(object.SetTextColor, object, applied[1], applied[2], applied[3], applied[4])
        if ok then
            states[object] = { original = current, applied = applied }
            return true
        end
    end
    return false
end

-- A verified selected dropdown label may already equal the configured source
-- color by the time its pooled FontString is exposed. Record its native origin
-- explicitly so disabling MapkoSkin remains reversible even for late rows.
local function ApplyKnownNativeObject(object, desired)
    local current = ReadColor(object)
    if not current or type(object.SetTextColor) ~= "function" then return false end
    local state = BlizzardYellow.directStates[object]
    if state then return ApplyObject(object, BlizzardYellow.directStates, desired) end
    if not IsNativeYellow(current) and not SameColor(current, desired) then return false end

    local original = { nativeYellow[1][1], nativeYellow[1][2], nativeYellow[1][3], current[4] }
    local applied = { desired[1], desired[2], desired[3], desired[4] }
    local ok = pcall(object.SetTextColor, object, unpack(applied))
    if not ok then return false end
    BlizzardYellow.directStates[object] = { original = original, applied = applied }
    return true
end

local function DesiredColor()
    local r, g, b, a = NS.Theme.GetColor("blizzardYellow")
    return { r, g, b, a }
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

-- Recolor only FontStrings already reached through a known Blizzard adapter.
-- This intentionally avoids global frame enumeration and never walks unrelated
-- addon globals. GenericWindows and Surface call this on bounded/exact targets,
-- including pooled ScrollBox rows when Blizzard initializes them.
function BlizzardYellow.TrackFrame(frame)
    if not NS.DB or not NS.DB.enabled or NS.IsCombatLocked() or not frame then return 0 end
    local getter = frame.GetRegions
    if type(getter) ~= "function" then return 0 end
    local desired = DesiredColor()
    local count = 0
    local ok = pcall(function()
        local function Visit(...)
            for index = 1, select("#", ...) do
                local region = select(index, ...)
                local objectType
                if region and type(region.GetObjectType) == "function" then
                    local got, value = pcall(region.GetObjectType, region)
                    if got then objectType = value end
                end
                if objectType == "FontString"
                    and ApplyObject(region, BlizzardYellow.directStates, desired) then
                    count = count + 1
                end
            end
        end
        Visit(getter(frame))
    end)
    if not ok then return 0 end
    return count
end

local function TrackKnownFrame(frame)
    if not NS.DB or not NS.DB.enabled or NS.IsCombatLocked() or not frame then return 0 end
    local desired = DesiredColor()
    local count = 0
    local seen = setmetatable({}, { __mode = "k" })
    local function Visit(region)
        if not region or seen[region] then return end
        seen[region] = true
        local objectType
        if type(region.GetObjectType) == "function" then
            local ok, value = pcall(region.GetObjectType, region)
            if ok then objectType = value end
        end
        if objectType == "FontString" and ApplyKnownNativeObject(region, desired) then
            count = count + 1
        end
    end
    if type(frame.GetRegions) == "function" then
        pcall(function()
            local function VisitAll(...)
                for index = 1, select("#", ...) do Visit(select(index, ...)) end
            end
            VisitAll(frame:GetRegions())
        end)
    end
    local ok, text = pcall(function() return frame.Text end)
    if ok then Visit(text) end
    return count
end

-- These two entry points are intentionally narrow: only a verified modern
-- DropdownButton selection label and a selected MenuTemplate row may opt into
-- the known-native path above.
function BlizzardYellow.TrackDropdown(button)
    if not button then return 0 end
    if type(button.IsEnabled) == "function" then
        local ok, enabled = pcall(button.IsEnabled, button)
        if ok and enabled == false then return 0 end
    end
    return TrackKnownFrame(button)
end

function BlizzardYellow.TrackMenuSelection(row)
    if not row or type(row.GetElementDescription) ~= "function" then return 0 end
    local ok, description = pcall(row.GetElementDescription, row)
    if not ok or not description or type(description.IsSelected) ~= "function" then return 0 end
    local selectedOk, selected = pcall(description.IsSelected, description)
    if not selectedOk or selected ~= true then return 0 end
    if type(description.IsEnabled) == "function" then
        local enabledOk, enabled = pcall(description.IsEnabled, description)
        if enabledOk and enabled == false then return 0 end
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

    local loaded = LoadedFontSet()
    local desired = DesiredColor()
    local count = 0
    for index = 1, #(NS.BlizzardFontNames or {}) do
        local name = NS.BlizzardFontNames[index]
        if loaded[name] then
            local object = _G[name]
            if ApplyObject(object, BlizzardYellow.states, desired) then count = count + 1 end
        end
    end
    local directCount = 0
    for object in pairs(BlizzardYellow.directStates) do
        if ApplyObject(object, BlizzardYellow.directStates, desired) then directCount = directCount + 1 end
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
