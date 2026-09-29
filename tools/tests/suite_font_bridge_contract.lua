local root = assert(arg[1], "repository root required")
local path, epoch = "First.ttf", 1
MSUF_FontApplyEpoch = epoch
local applied = {}
local blizzardApplies = 0
MapkoSkin = { addonName = "MSUF_Suite_Skin", DB = { enabled = true, typography = {
    enabled = true, followMSUF = true,
} }, Typography = { ApplyConfigured = function() blizzardApplies = blizzardApplies + 1 end } }
local S = { started = true, states = {
    actionbars = { active = true }, bags = { active = true },
    minimap = { active = false }, chat = { active = true },
} }
function S.Apply(id) applied[#applied + 1] = id end
local NS = { Suite = S, Skin = { enabled = true }, GlobalFontPath = function() return path end }
assert(loadfile(root .. "/MSUF_Suite/Core/FontBridge.lua"))("MSUF_Suite", NS)
assert(MSUFSuite_ApplyFontsFromMSUF == S.ApplyGlobalFont)
MSUFSuite_ApplyFontsFromMSUF()
assert(#applied == 3 and applied[1] == "actionbars" and applied[2] == "bags" and applied[3] == "chat",
    "font changes should refresh active Suite text modules only")
assert(blizzardApplies == 1, "MSUF font did not reach the embedded Blizzard typography engine")
MSUFSuite_ApplyFontsFromMSUF()
assert(#applied == 3 and blizzardApplies == 1,
    "an unchanged font generation should not repaint the Suite or Blizzard fonts")
path = "Second.ttf"
MSUFSuite_ApplyFontsFromMSUF()
assert(#applied == 6, "a changed MSUF font did not refresh active Suite modules")
assert(blizzardApplies == 2, "a changed MSUF font did not refresh Blizzard fonts")
MSUF_FontApplyEpoch = epoch + 1
MSUFSuite_ApplyFontsFromMSUF()
assert(#applied == 9, "MSUF's delayed font recovery did not refresh active Suite modules")
assert(blizzardApplies == 3, "MSUF's delayed font recovery did not refresh Blizzard fonts")
S.started = false
path = "Third.ttf"
MSUFSuite_ApplyFontsFromMSUF()
assert(#applied == 9, "font apply started dormant Suite modules")
S.started = true
MSUFSuite_ApplyFontsFromMSUF()
assert(#applied == 12, "a pre-start font change was incorrectly cached")
assert(blizzardApplies == 4, "a pre-start font change did not reach Blizzard fonts")
MapkoSkin.DB.typography.followMSUF = false
path = "Fourth.ttf"
MSUFSuite_ApplyFontsFromMSUF()
assert(blizzardApplies == 4, "an explicit skin font was overwritten by MSUF")
MapkoSkin.DB.typography.followMSUF = true
NS.Skin.enabled = false
path = "Fifth.ttf"
MSUFSuite_ApplyFontsFromMSUF()
assert(blizzardApplies == 4, "disabled Suite skin repainted Blizzard fonts")
print("suite font bridge contract ok")
