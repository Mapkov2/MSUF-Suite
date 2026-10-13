local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_installer_harness.lua")
local function Setup(forever)
    local S = H.Setup({ root = root, forever = forever })
    local name = S.Database.GetActiveProfileName()
    local profile = S.Database.GetProfile(name)
    local c = profile.suite.modules.minimap
    local old = { size = 256, point = 3, x = -8, y = -8, borderSize = 2,
        borderColor = "000000", borderAlpha = 100, borderClassColor = false, shadowSize = 0,
        outerBorderSize = 2, outerBorderGap = 4, outerBorderColor = "000000",
        styleBackdrop = false, styleTexture = 1, styleBackdropColor = "090c14",
        styleBackdropAlpha = 85, styleBackdropPadding = 4, infoLocationSource = 1,
        infoLocationZone = true, infoLocationSubzone = false, dungeonButton = true,
        dungeonStyle = 1, dungeonWidth = 52, dungeonHeight = 26, dungeonAnchor = 1,
        dungeonX = 0, dungeonY = -12, infoClockY = 14, infoCalendarDay = true }
    for key, value in pairs(old) do c[key] = value end
    S.RootDB.installation = { status = "complete", profile = "modernDark", frameProfileName = name }
    local calls, before, after = 0, 0, 0
    S.ProfileVariants.BeforeMutation = function() before = before + 1; return true end
    S.ProfileVariants.AfterMutation = function() after = after + 1 end
    S.Suite.SetMany = function(id, values)
        assert(id == "minimap")
        calls = calls + 1
        for key, value in pairs(values) do c[key] = value end
        return true
    end
    return S, c, function() return calls, before, after end
end
for _, forever in ipairs({ false, true }) do
    local S, c, Counts = Setup(forever)
    c.borderAlpha = 95 -- historic Modern Dark factory
    c.styleBackdropColor, c.styleBackdropAlpha = "101010", 82 -- dormant original dark plate
    assert(S.SuiteProfiles.EnsureModernDarkMinimap())
    assert(c.size == 240 and c.x == -16 and c.y == -16 and c.borderAlpha == 100)
    assert(c.styleBackdrop and c.styleBackdropColor == "16191b" and c.styleBackdropPadding == 6)
    assert(c.infoLocationSource == 4 and c.dungeonStyle == 2 and c.dungeonWidth == 48)
    assert(c.dungeonX == 8 and c.dungeonY == -16 and c.infoClockY == 14 and c.infoCalendarDay)
    local calls, before, after = Counts()
    assert(calls == 1 and before == 1 and after == 1)
    assert(not S.SuiteProfiles.EnsureModernDarkMinimap() and Counts() == 1, "repair repeated")
end
for _, pair in ipairs({ { "101010", 85 }, { "090c14", 82 } }) do
    local S, c = Setup(false)
    c.styleBackdropColor, c.styleBackdropAlpha = pair[1], pair[2]
    assert(S.SuiteProfiles.EnsureModernDarkMinimap())
    assert(not c.styleBackdrop and c.styleBackdropColor == pair[1] and c.styleBackdropAlpha == pair[2],
        "mixed personal plate pair was replaced")
end
for _, choice in ipairs({ "preset", "profile", "incomplete", "combat", "variant", "refusal", "missing-base" }) do
    local S, c, Counts = Setup(false)
    if choice == "preset" then S.RootDB.installation.profile = "classic" end
    if choice == "profile" then S.RootDB.installation.frameProfileName = "Someone else" end
    if choice == "incomplete" then S.RootDB.installation.status = "pending" end
    if choice == "combat" then H.combat = true end
    if choice == "variant" then S.ProfileVariants.BeforeMutation = function() return false end end
    if choice == "missing-base" then S.ProfileVariants.BaseProfile = function() end end
    if choice == "refusal" then S.Suite.SetMany = function() return false end end
    assert(not S.SuiteProfiles.EnsureModernDarkMinimap(), choice .. " was modified")
    assert(Counts() == 0 and c.size == 256 and c.infoLocationSource == 1)
    assert(not S.RootDB.installation.modernDarkMinimapRevision, choice .. " prevented a later retry")
end
for key, value in pairs({ size = 300, borderAlpha = 50, borderClassColor = true, shadowSize = 8,
    styleBackdropColor = "123456", styleBackdropAlpha = 30, styleBackdropPadding = 12,
    infoLocationSource = 3, dungeonY = -30 }) do
    local S, c = Setup(false)
    c[key] = value
    assert(S.SuiteProfiles.EnsureModernDarkMinimap(), "independent original groups were not repaired")
    assert(c[key] == value, "personal setting overwritten: " .. key)
end
local S, c, Counts = Setup(false)
local base = S.CopyValue(S.Database.GetProfile(S.Database.GetActiveProfileName()))
S.ProfileVariants.BaseProfile = function() return base end
c.size = 310 -- active overlay, base is still original
S.ProfileVariants.BeforeMutation = function() c.size = 256; return true end
assert(S.SuiteProfiles.EnsureModernDarkMinimap() and c.size == 240, "overlay blocked base repair")
S, c, Counts = Setup(false)
S.ProfileVariants.BeforeMutation = function() c.size = 310; c.dungeonY = -30; return true end
assert(S.SuiteProfiles.EnsureModernDarkMinimap())
assert(c.size == 310 and c.dungeonY == -30 and c.infoLocationSource == 4,
    "repair did not recheck the base after lifting a variant")
S, c, Counts = Setup(false)
c.infoLocationSource, c.dungeonStyle = nil, nil -- profiles written before these options existed
assert(S.SuiteProfiles.EnsureModernDarkMinimap() and c.infoLocationSource == 4 and c.dungeonStyle == 2)
print("Modern Dark minimap migration: both clients, personal edits, retries and variant ownership passed")
