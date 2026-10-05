-- Edges of the skin core, each with the real files:
--   * NS.Clamp turns NaN into the minimum, so an imported profile that carries
--     NaN for a range or a colour channel comes out of SanitizeProfile clamped.
--   * Registry.NotifyListeners calls every listener of its start exactly once,
--     also when a listener adds others meanwhile (WatchSettings does), and
--     skips one removed meanwhile.
--   * A texture an adapter bound to a colour role (Checkmarks.TrackTexture,
--     e.g. the QuickJoin social button) follows a look, colour or profile change.
-- Real Defaults, DefaultsLooks, Database, Safety, Registry, CombatGate, Theme,
-- Checkmarks and CheckmarksMenus.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, label)
    assert(value, label)
    checks = checks + 1
end

local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end
InCombatLockdown = function() return false end
local timers = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local function NextFrame()
    local queued = timers
    timers = {}
    for _, callback in ipairs(queued) do callback() end
end
CreateFrame = function()
    return { SetScript = function() end, RegisterEvent = function() end, UnregisterEvent = function() end }
end
EventRegistry = { RegisterCallback = function() end, UnregisterCallback = function() end }
UnitClass = function() return "Mage", "MAGE" end
C_ClassColor = { GetClassColor = function() return nil end }
RAID_CLASS_COLORS = {}
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local NS = {
    IsCombatLocked = function() return InCombatLockdown() end,
    Client = { isForever = false, isMainline = true },
    FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" },
    GenericWindows = { Disable = function() end, ApplyFrame = function() end },
    WindowActionSkin = { Restore = function() end, HasOwnedStates = function() return false end,
        DisableOwner = function() end },
}
for _, file in ipairs({ "Core/Defaults.lua", "Core/DefaultsLooks.lua", "Core/Database.lua", "Core/Safety.lua",
    "Core/Registry.lua", "Core/CombatGate.lua", "Core/Theme.lua", "Core/Checkmarks.lua",
    "Core/CheckmarksMenus.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end

------------------------------------------------------------------ Clamp and NaN
local nan = 0 / 0
Check(NS.Clamp(nan, 0, 1) == 0 and NS.Clamp(nan, 0.35, 1) == 0.35, "NS.Clamp passed NaN through")
Check(NS.Clamp(-1, 0, 1) == 0 and NS.Clamp(2, 0, 1) == 1 and NS.Clamp(0.5, 0, 1) == 0.5
    and NS.Clamp("x", 0, 1) == 0 and NS.Clamp(nil, 0.2, 1) == 0.2, "NS.Clamp changed for ordinary values")
-- An import payload (C_EncodingUtil.DeserializeCBOR keeps a NaN float).
local imported = NS.CopyValue(NS.Defaults)
imported.theme.gradientStrength = nan
imported.theme.shellOpacity = nan
imported.theme.colors.text = { nan, 0.5, 0.5, nan }
local profile = NS.Database.SanitizeProfile(imported)
local theme = profile and profile.theme
Check(theme and theme.gradientStrength == 0 and theme.shellOpacity == 0.35,
    "an imported NaN range survived SanitizeProfile")
Check(theme.colors.text[1] == 0 and theme.colors.text[2] == 0.5 and theme.colors.text[4] == 0,
    "an imported NaN colour channel survived SanitizeProfile")

Check(#reported == 0, "the skin core reported errors: " .. table.concat(reported, "; "))

print("Suite skin core edges: " .. checks .. " checks passed")
