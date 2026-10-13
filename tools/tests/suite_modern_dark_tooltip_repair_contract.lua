local root = assert(arg[1])
local H = assert(loadfile(root .. "/tools/tests/suite_installer_harness.lua"))()
local function Setup(forever)
    local Suite = H.Setup({ root = root, forever = forever })
    local profile = assert(Suite.Database.GetProfile(Suite.Database.GetActiveProfileName()))
    profile.suite.modules.tooltipDetails = { enabled = false, anchor = 1, growth = 1,
        fixedX = -24, fixedY = 24, inspectHovered = false, itemLevel = true }
    profile.suite.modules.damageMeter = { w1Y = 32, w1Height = 250, headerOutside = true }
    Suite.RootDB.installation = { status = "complete", profile = "modernDark",
        frameProfileName = Suite.Database.GetActiveProfileName() }
    local calls, before, after = 0, 0, 0
    Suite.ProfileVariants.BeforeMutation = function() before = before + 1; return true end
    Suite.ProfileVariants.AfterMutation = function() after = after + 1 end
    Suite.Suite.SetMany = function(id, values)
        assert(id == "tooltipDetails")
        calls = calls + 1
        for key, value in pairs(values) do profile.suite.modules[id][key] = value end
        return true
    end
    return Suite, profile.suite.modules, function() return calls, before, after end
end
local Suite, modules, Counts = Setup(false)
local config = modules.tooltipDetails
assert(Suite.SuiteProfiles.EnsureModernDarkTooltips())
assert(config.enabled and config.anchor == 3 and config.fixedX == -12 and config.fixedY == 340)
assert(config.fixedY >= modules.damageMeter.w1Y + modules.damageMeter.w1Height + 38 + 20,
    "tooltip overlaps the meter's outside header")
assert(config.inspectHovered == false and config.itemLevel == true)
local calls, before, after = Counts()
assert(calls == 1 and before == 1 and after == 1)
assert(not Suite.SuiteProfiles.EnsureModernDarkTooltips() and Counts() == 1, "repair repeated")
for _, choice in ipairs({ "other-preset", "other-profile", "custom-y", "custom-anchor", "off-custom", "meter", "combat", "variant", "forever", "refusal" }) do
    local S, m, GetCalls = Setup(choice == "forever")
    if choice == "other-preset" then S.RootDB.installation.profile = "classic" end
    if choice == "other-profile" then S.RootDB.installation.frameProfileName = "Someone else" end
    if choice == "custom-y" then m.tooltipDetails.fixedY = 150 end
    if choice == "custom-anchor" then m.tooltipDetails.anchor = 2 end
    if choice == "off-custom" then m.tooltipDetails.fixedX = -40 end
    if choice == "meter" then m.damageMeter.w1Height = 400 end
    if choice == "combat" then H.combat = true end
    if choice == "variant" then S.ProfileVariants.BeforeMutation = function() return false end end
    if choice == "refusal" then S.Suite.SetMany = function() return false end end
    assert(not S.SuiteProfiles.EnsureModernDarkTooltips(), choice .. " was modified")
    assert(GetCalls() == 0, choice .. " wrote tooltip settings")
    assert(m.tooltipDetails.enabled == false, choice .. " enabled a module")
    if choice == "refusal" then assert(not S.RootDB.installation.modernDarkTooltipRevision) end
end
local S, m, GetCalls = Setup(false)
S.ProfileVariants.BeforeMutation = function()
    m.tooltipDetails.enabled, m.tooltipDetails.anchor = true, 3
    m.tooltipDetails.fixedX, m.tooltipDetails.fixedY = -40, 150
    return true
end
assert(not S.SuiteProfiles.EnsureModernDarkTooltips() and GetCalls() == 0,
    "lifting a variant let the repair overwrite a personal base anchor")
assert(m.tooltipDetails.fixedX == -40 and m.tooltipDetails.fixedY == 150)
S, m, GetCalls = Setup(false)
local base = Suite.CopyValue(S.Database.GetProfile(S.Database.GetActiveProfileName()))
S.ProfileVariants.BaseProfile = function() return base end
m.tooltipDetails.fixedY = 100 -- an active overlay, while stored base is still the old factory
S.ProfileVariants.BeforeMutation = function() m.tooltipDetails.fixedY = 24; return true end
assert(S.SuiteProfiles.EnsureModernDarkTooltips() and GetCalls() == 1,
    "an overlay prevented the original stored factory from being repaired")
print("Modern Dark HUD tooltip repair, meter clearance, profile/variant ownership and personal anchors passed")
