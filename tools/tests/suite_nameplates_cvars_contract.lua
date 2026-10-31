-- Nameplates: the Distance and stacking section and the split unit visibility
-- choices (Catalog/Nameplates.lua, CVars.lua Space and CHOICES). Each setting
-- reaches its Blizzard CVar through the module context, Keep Blizzard setting
-- writes nothing, releasing the context (the module turned off, Runtime.lua)
-- hands every CVar back, the combined minion choices still apply, the target
-- scale and the dimming of other plates stay their own values, and a control
-- whose CVar the client lacks has no place on the page.
local root = assert(arg[1])

------------------------------------------------------------------ environment
local live, setCalls, combat = {}, 0, false
C_CVar = {
    GetCVar = function(key) return live[key] end,
    SetCVar = function(key, value) setCalls = setCalls + 1; live[key] = tostring(value) end,
}
local PRD_DISABLED, gameRules = 5, {}
Enum = { GameRule = { PersonalResourceDisplayDisabled = PRD_DISABLED } }
C_GameRules = { IsGameRuleActive = function(rule) return gameRules[rule] == true end }
UnitName = function() return "Tester" end
GetRealmName = function() return "Realm" end

local function Catalog()
    local NS = { Client = { isForever = false, isMainline = true }, Text = function(value) return value end }
    NS.Public = function(value) return value ~= "secret" end
    NS.Finite = function(value) return type(value) == "number" and value == value end
    NS.RGB = function(hex)
        return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    end
    NS.Safety = { IsForbidden = function(frame) return frame.forbidden == true end }
    NS.InCombat = function() return combat end
    for _, file in ipairs({ "SuiteCatalog", "NameplateStyle", "Catalog/Nameplates" }) do
        assert(loadfile(root .. "/MSUF_Suite/Core/" .. file .. ".lua"))("MSUF_Suite", NS)
    end
    return NS, NS.SuiteCatalog.nameplates
end
local NS, spec = Catalog()
local rules = spec.rules

-- The real runtime: its context records, applies and hands back CVars.
NS.Number, NS.PublicText, NS.ReadText, NS.Text = NS.Finite, tostring, tostring, function(value) return value end
NS.Dispatch = function(fn, ...) return fn(...) end
NS.Print, NS.CharacterData, NS.RootDB = function() end, {}, {}
NS.Skin = { Release = function() end }
local S = { catalog = NS.SuiteCatalog, instances = {} }
NS.Suite = S
MSUFSuite = NS
assert(loadfile(root .. "/MSUF_Suite_Modules/Runtime.lua"))("MSUF_Suite_Modules", {})
local private = { NS = NS, Suite = S }
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Modes.lua"))("MSUF_Suite_Nameplates", private)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/CVars.lua"))("MSUF_Suite_Nameplates", private)
local CVars = private.CVars
local context = S.NewContext("nameplates")
local module = { context = context }

local function Config(overrides)
    local config = {}
    for key, rule in pairs(rules) do config[key] = rule.default end
    for key, value in pairs(overrides or {}) do config[key] = value end
    return config
end
local function Apply(overrides)
    module.config = Config(overrides)
    CVars.Apply(module)
end

-- Blizzard's values of every CVar the new settings write.
local BLIZZARD = {
    nameplateMaxDistance = "60", nameplateOccludedAlphaMult = "0.4", nameplateMinAlpha = "0.6",
    nameplateMinScale = "0.8", nameplateOverlapV = "1.1", nameplateOverlapH = "0.8",
    nameplateOtherTopInset = "0.08", nameplateOtherBottomInset = "0.1", nameplateMotionSpeed = "0.025",
    clampTargetNameplateToScreen = "0", nameplateShowEnemies = "1", nameplateShowFriendlyPlayers = "1",
    nameplateShowSelf = "1", nameplateShowEnemyPets = "1", nameplateShowEnemyGuardians = "0",
    nameplateShowEnemyTotems = "0", nameplateShowFriendlyPlayerPets = "0", nameplateShowFriendlyPlayerGuardians = "0",
    nameplateShowFriendlyPlayerTotems = "0", nameplateShowEnemyMinions = "1", nameplateShowFriendlyPlayerMinions = "0",
    nameplateSelectedScale = "1.1",
}
local function Reset()
    for key in pairs(live) do live[key] = nil end
    for key, value in pairs(BLIZZARD) do live[key] = value end
    for key in pairs(NS.RootDB) do NS.RootDB[key] = nil end
    setCalls = 0
end
local function Same(expected, message)
    for key, value in pairs(expected) do assert(live[key] == value, message .. ": " .. key .. " is " .. tostring(live[key])) end
end

------------------------------------------------------------------ catalog
-- Every new setting starts on Blizzard's value (a number on Blizzard's own
-- value in its unit) and names the CVar it writes in the module's manifest.
local NEW = {
    plateEnemies = { 1, "nameplateShowEnemies" }, plateFriendlyPlayers = { 1, "nameplateShowFriendlyPlayers" },
    personalResource = { 1, "nameplateShowSelf" }, plateEnemyPets = { 1, "nameplateShowEnemyPets" },
    plateEnemyGuardians = { 1, "nameplateShowEnemyGuardians" }, plateEnemyTotems = { 1, "nameplateShowEnemyTotems" },
    plateFriendlyPets = { 1, "nameplateShowFriendlyPlayerPets" },
    plateFriendlyGuardians = { 1, "nameplateShowFriendlyPlayerGuardians" },
    plateFriendlyTotems = { 1, "nameplateShowFriendlyPlayerTotems" },
    plateMaxDistanceMode = { 1, "nameplateMaxDistance" }, plateMaxDistance = { 60, "nameplateMaxDistance" },
    plateOccludedMode = { 1, "nameplateOccludedAlphaMult" }, plateOccludedPercent = { 40, "nameplateOccludedAlphaMult" },
    plateFadeDistance = { 1, "nameplateMinAlpha" }, plateShrinkDistance = { 1, "nameplateMinScale" },
    plateSpacingMode = { 1, "nameplateOverlapV" }, plateOverlapV = { 110, "nameplateOverlapV" },
    plateOverlapH = { 80, "nameplateOverlapH" }, plateMotionSpeed = { 1, "nameplateMotionSpeed" },
    plateInsetMode = { 1, "nameplateOtherTopInset" }, plateTopInset = { 8, "nameplateOtherTopInset" },
    plateBottomInset = { 10, "nameplateOtherBottomInset" }, plateClampTarget = { 1, "clampTargetNameplateToScreen" },
}
local manifestSize = 0
for key, expected in pairs(NEW) do
    local rule = assert(rules[key], key .. " is missing from the catalog")
    assert(rule.default == expected[1], key .. " does not start on Blizzard's value")
    assert(rule.cvar == expected[2] and spec.cvars[expected[2]], key .. " does not declare its CVar (Runtime.lua OwnsCVar)")
    for index = 1, 3 do
        assert(not (spec.look.presets[index] and spec.look.presets[index][key]) and not spec.look.visualKeys[key],
            key .. " is a Blizzard option, not part of a look or Quick Setup")
    end
    assert(rule.section == "distance" or rule.section == "visibility", key .. " sits in no Distance or Visibility section")
    manifestSize = manifestSize + 1
end
assert(not spec.look.presets[4].plateEnemies and not spec.look.presets[4].plateMaxDistance,
    "Quick Setup applies a Blizzard option")
assert(rules.plateMaxDistance.requiresChoice.key == "plateMaxDistanceMode" and rules.plateMaxDistance.requiresChoice.values[2],
    "the distance number does not wait for Customize")
assert(rules.plateOverlapH.requiresChoice.key == "plateSpacingMode" and rules.plateBottomInset.requiresChoice.key == "plateInsetMode"
    and rules.plateOccludedPercent.requiresChoice.key == "plateOccludedMode", "a Customize number is not gated")
for _, key in ipairs({ "plateFadeDistance", "plateShrinkDistance" }) do
    assert(#rules[key].choices == 4 and rules[key].choices[1] == "Keep Blizzard setting", key .. " lost its presets")
end
assert(rules.plateEnemies.sectionTitle == "Visibility" and rules.plateMaxDistance.sectionTitle == "Distance and stacking")

-- The combined minion choices stay what they were.
assert(rules.plateEnemyMinions.label == "Enemy minions (pets, guardians, totems)" and rules.plateEnemyMinions.default == 1
    and #rules.plateEnemyMinions.choices == 3 and not rules.plateEnemyMinions.hidden, "the combined enemy minion choice changed")
assert(rules.plateFriendlyMinions.label == "Friendly player minions" and rules.plateFriendlyMinions.default == 1
    and #rules.plateFriendlyMinions.choices == 3 and not rules.plateFriendlyMinions.hidden, "the combined friendly minion choice changed")
assert(spec.cvars.nameplateShowEnemyMinions and spec.cvars.nameplateShowFriendlyPlayerMinions)

------------------------------------------------------------------ keep writes nothing
Reset()
Apply()
assert(setCalls == 0, "Keep Blizzard setting wrote a CVar")
Same(BLIZZARD, "Keep Blizzard setting changed")
assert(next(NS.RootDB) == nil, "Keep Blizzard setting left a recovery record")

------------------------------------------------------------------ values reach their CVars
local ALL = {
    plateMaxDistanceMode = 2, plateMaxDistance = 80, plateOccludedMode = 2, plateOccludedPercent = 25,
    plateFadeDistance = 4, plateShrinkDistance = 3, plateSpacingMode = 2, plateOverlapV = 150, plateOverlapH = 60,
    plateMotionSpeed = 3, plateInsetMode = 2, plateTopInset = 5, plateBottomInset = 12, plateClampTarget = 2,
    plateEnemies = 3, plateFriendlyPlayers = 2, personalResource = 3,
    plateEnemyPets = 3, plateEnemyGuardians = 2, plateEnemyTotems = 2,
    plateFriendlyPets = 2, plateFriendlyGuardians = 3, plateFriendlyTotems = 2,
}
local WRITTEN = {
    nameplateMaxDistance = "80", nameplateOccludedAlphaMult = "0.25", nameplateMinAlpha = "0.3", nameplateMinScale = "0.9",
    nameplateOverlapV = "1.5", nameplateOverlapH = "0.6", nameplateMotionSpeed = "0.1",
    nameplateOtherTopInset = "0.05", nameplateOtherBottomInset = "0.12", clampTargetNameplateToScreen = "1",
    nameplateShowEnemies = "0", nameplateShowFriendlyPlayers = "1", nameplateShowSelf = "0",
    nameplateShowEnemyPets = "0", nameplateShowEnemyGuardians = "1", nameplateShowEnemyTotems = "1",
    nameplateShowFriendlyPlayerPets = "1", nameplateShowFriendlyPlayerGuardians = "0", nameplateShowFriendlyPlayerTotems = "1",
}
Reset()
Apply(ALL)
Same(WRITTEN, "a setting did not reach its CVar")
-- Every CVar the new settings write is covered by the table above.
local covered = {}
for key in pairs(WRITTEN) do covered[key] = true end
for _, expected in pairs(NEW) do assert(covered[expected[2]], expected[2] .. " is written by no case of this test") end

-- Customize alone does nothing for a number that stays on Keep, and each
-- preset writes the far-end value of its own CVar.
Reset()
Apply({ plateMaxDistance = 90, plateOccludedPercent = 10, plateOverlapV = 200, plateTopInset = 30 })
assert(setCalls == 0, "a number wrote while its choice stayed on Keep Blizzard setting")
for choice, expected in pairs({ [2] = "1", [3] = "0.8", [4] = "0.3" }) do
    Apply({ plateFadeDistance = choice })
    assert(live.nameplateMinAlpha == expected, "fade preset " .. choice .. " wrote " .. tostring(live.nameplateMinAlpha))
end
for choice, expected in pairs({ [2] = "1", [3] = "0.9", [4] = "0.6" }) do
    Apply({ plateShrinkDistance = choice })
    assert(live.nameplateMinScale == expected, "shrink preset " .. choice .. " wrote " .. tostring(live.nameplateMinScale))
end
for choice, expected in pairs({ [2] = "0.01", [3] = "0.1", [4] = "1" }) do
    Apply({ plateMotionSpeed = choice })
    assert(live.nameplateMotionSpeed == expected, "motion preset " .. choice .. " wrote " .. tostring(live.nameplateMotionSpeed))
end
Apply({ plateClampTarget = 3 })
assert(live.clampTargetNameplateToScreen == "0" and live.nameplateMinAlpha == BLIZZARD.nameplateMinAlpha,
    "off wrote the wrong value, or a setting moved back to Keep kept its old CVar value")

-- A setting moved back to Keep hands its CVar back; the others stay.
Reset()
Apply(ALL)
local moved = {}
for key, value in pairs(ALL) do moved[key] = value end
moved.plateMaxDistanceMode, moved.plateEnemies = 1, 1
Apply(moved)
assert(live.nameplateMaxDistance == "60" and live.nameplateShowEnemies == "1", "Keep did not hand the CVar back")
assert(live.nameplateOccludedAlphaMult == "0.25" and live.nameplateShowSelf == "0", "Keep on one setting moved another")

------------------------------------------------------------------ turning the module off
-- Context:Release is what Disable ends with (and Suite.lua Stop repeats it).
Reset()
Apply(ALL)
assert(setCalls > 0)
context:Release()
Same(BLIZZARD, "turning the module off left a CVar changed")
assert(next(NS.RootDB.suiteRecovery or {}) == nil, "a recovery record survived the release")
-- A value the player changed meanwhile is theirs: not overwritten.
Reset()
Apply(ALL)
live.nameplateMaxDistance = "100"
context:Release()
assert(live.nameplateMaxDistance == "100" and live.nameplateMinAlpha == BLIZZARD.nameplateMinAlpha,
    "the release overwrote a CVar the player changed")

------------------------------------------------------------------ the combined minion choices
Reset()
Apply({ plateEnemyMinions = 3 })
assert(live.nameplateShowEnemyMinions == "0" and live.nameplateShowEnemyPets == "1"
    and live.nameplateShowEnemyGuardians == "0" and live.nameplateShowEnemyTotems == "0",
    "the combined enemy minion choice stopped applying, or wrote the separate CVars")
Apply({ plateFriendlyMinions = 2 })
assert(live.nameplateShowFriendlyPlayerMinions == "1" and live.nameplateShowEnemyMinions == "1"
    and live.nameplateShowFriendlyPlayerPets == "0", "the combined friendly minion choice stopped applying")
Apply({ plateEnemyMinions = 3, plateEnemyTotems = 2 })
assert(live.nameplateShowEnemyMinions == "0" and live.nameplateShowEnemyTotems == "1",
    "the combined and the separate choice must both apply")

------------------------------------------------------------------ target scale, dimming and combat
-- The target's own scale and the dimming of other plates are separate values:
-- shrink and fade never write the target scale or the far-end maximums.
Reset()
Apply({ targetScaleEnabled = true, targetScalePercent = 130, plateShrinkDistance = 4, plateFadeDistance = 4,
    selectionDim = 2, selectionDimPercent = 30 })
assert(live.nameplateSelectedScale == "1.3" and live.nameplateMinScale == "0.6" and live.nameplateMinAlpha == "0.3",
    "target scale and shrink fought over a value")
assert(not spec.cvars.nameplateMaxScale and not spec.cvars.nameplateMaxAlpha and not spec.cvars.nameplateSelectedAlpha,
    "the module owns a CVar of the target or the far-end maximum")
Apply({ plateShrinkDistance = 4, plateFadeDistance = 4 })
assert(live.nameplateSelectedScale == BLIZZARD.nameplateSelectedScale, "the target scale stayed after it was switched off")
local overlay = { alpha = 1 }
function overlay:SetAlpha(alpha) self.alpha = alpha end
NamePlateHealthBarMixin = { UpdateSelectionBorder = function() end }
hooksecurefunc = function() end
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Selection.lua"))("MSUF_Suite_Nameplates", private)
local calls = setCalls
private.Selection.Configure(Config({ selectionDim = 2, selectionDimPercent = 30, plateFadeDistance = 4, plateShrinkDistance = 4 }))
private.Selection.Apply({ selectedBorder = { SetAlpha = function() end, SetVertexColor = function() end },
    deselectedOverlay = overlay, UpdateSelectionBorder = function() end }, true)
assert(math.abs(overlay.alpha - 0.3) < 1e-9 and setCalls == calls, "dimming other plates changed or wrote a CVar")

Reset()
combat = true
Apply({ plateMaxDistanceMode = 2 })
assert(setCalls == 0 and module.cvarsPending, "a distance CVar was written in combat")
combat = false
CVars.Apply(module)
assert(live.nameplateMaxDistance == "60" and not module.cvarsPending, "the held-back distance write failed after combat")
Apply({ plateMaxDistanceMode = 2, plateMaxDistance = 70 })
assert(live.nameplateMaxDistance == "70")

------------------------------------------------------------------ a CVar the client lacks
Reset()
live.nameplateMotionSpeed, live.nameplateOverlapH, live.clampTargetNameplateToScreen = nil, nil, nil
Apply(ALL)
assert(live.nameplateMotionSpeed == nil and live.nameplateOverlapH == nil and live.clampTargetNameplateToScreen == nil
    and live.nameplateMaxDistance == "80", "a missing CVar was written, or it stopped the others")
local records = NS.RootDB.suiteRecovery["Realm/Tester"].nameplates
assert(records.nameplateMaxDistance and not records.nameplateMotionSpeed and not records.nameplateOverlapH,
    "a CVar the client lacks left a recovery record")
local _, lacking = Catalog()
local controls, kept = lacking.getControls(), {}
for _, rule in ipairs(controls) do kept[rule.key] = true end
assert(not kept.plateMotionSpeed and not kept.plateOverlapH and not kept.plateClampTarget,
    "a control for a CVar the client lacks stayed")
assert(kept.plateMaxDistance and kept.plateEnemies and kept.plateFadeDistance and kept.look and kept.enemyNameSize,
    "available controls were dropped")
assert(lacking.controlAvailable(lacking.rules.plateMotionSpeed) == false and lacking.controlAvailable(lacking.rules.look) == true)
-- Personal resource display: also gone where the game rule disables it.
assert(kept.personalResource, "the personal resource display was dropped with its CVar present")
gameRules[PRD_DISABLED] = true
local _, ruled = Catalog()
local ruledKept = {}
for _, rule in ipairs(ruled.getControls()) do ruledKept[rule.key] = true end
assert(not ruledKept.personalResource and ruledKept.plateEnemies, "the disabled personal resource display still has a control")
gameRules[PRD_DISABLED] = nil

------------------------------------------------------------------ the page
local P = { Gates = {}, SearchPreparers = {}, catalog = { nameplates = lacking }, Suite = { NameplateStyle = NS.NameplateStyle, HostBridge = {} } }
P.Tr = function(text) return text end
P.Help = function(summary, details) return { summary = summary, details = details } end
P.HM = { GetSectionEntry = function() return nil end, SetSectionEnsureVisible = function() end }
P.W, P.M, P.T = { PageBuilder = function() return {} end }, {}, {}
P.S = { Config = function() return {} end }
P.Suite.RGB = NS.RGB
P.Suite.Registry = { AddListener = function() end }
P.BuildNameplatesPreview, P.BuildNameplatesAuraColors = function() end, function() end
local built, page = {}, nil
P.RegisterPage = function(registered) page = registered end
assert(loadfile(root .. "/MSUF_Suite_Options/Menu/Controls.lua"))("MSUF_Suite_Options", P)
-- The page hands each accordion's rule list to P.RuleSection.
P.ModuleCard = function() end
P.RuleSection = function(_, _, _, _, sectionId, _, shown) built[sectionId] = shown; return {} end
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesWorkspace.lua"))("MSUF_Suite_Options", P)
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/Nameplates.lua"))("MSUF_Suite_Options", P)
page.build({})
local function Keys(sectionId)
    local keys = {}
    for _, rule in ipairs(built[sectionId] or {}) do keys[rule.key] = true end
    return keys
end
local distance, visibility, more = Keys("suite_nameplates_distance"), Keys("suite_nameplates_visibility"), Keys("suite_nameplates_more")
assert(distance.plateMaxDistance and distance.plateFadeDistance and distance.plateTopInset and not distance.plateMotionSpeed
    and not distance.plateOverlapH and not distance.plateClampTarget,
    "the Distance and stacking section lacks a control, or shows one the client lacks")
assert(visibility.plateEnemies and visibility.plateFriendlyPlayers and visibility.plateEnemyPets and visibility.plateFriendlyTotems
    and visibility.plateEnemyMinions and visibility.plateFriendlyMinions, "the Visibility section lacks a control")
for key in pairs(NEW) do assert(not more[key], key .. " fell into More settings") end
assert(next(more) == nil, "a setting is placed nowhere: " .. tostring(next(more)))
assert(P.NameplateSearchTarget(rules.plateFadeDistance) == "suite_nameplates_distance")

print("Suite nameplates: distance, fade, stacking and unit visibility CVars, Keep, release, combined minions and missing CVars passed")
