local root = assert(arg[1], "repository root required")
local path, epoch = "First.ttf", 1
MSUF_FontApplyEpoch = epoch
local applied = {}
local S = { started = true, states = {
    actionbars = { active = true }, bags = { active = true },
    minimap = { active = false }, chat = { active = true },
} }
function S.Apply(id) applied[#applied + 1] = id end
local NS = { Suite = S, GlobalFontPath = function() return path end }
assert(loadfile(root .. "/MSUF_Suite/Core/FontBridge.lua"))("MSUF_Suite", NS)
assert(MSUFSuite_ApplyFontsFromMSUF == S.ApplyGlobalFont)
MSUFSuite_ApplyFontsFromMSUF()
assert(#applied == 3 and applied[1] == "actionbars" and applied[2] == "bags" and applied[3] == "chat",
    "font changes should refresh active Suite text modules only")
MSUFSuite_ApplyFontsFromMSUF()
assert(#applied == 3, "an unchanged font generation should not repaint the Suite")
path = "Second.ttf"
MSUFSuite_ApplyFontsFromMSUF()
assert(#applied == 6, "a changed MSUF font did not refresh active Suite modules")
MSUF_FontApplyEpoch = epoch + 1
MSUFSuite_ApplyFontsFromMSUF()
assert(#applied == 9, "MSUF's delayed font recovery did not refresh active Suite modules")
S.started = false
path = "Third.ttf"
MSUFSuite_ApplyFontsFromMSUF()
assert(#applied == 9, "font apply started dormant Suite modules")
S.started = true
MSUFSuite_ApplyFontsFromMSUF()
assert(#applied == 12, "a pre-start font change was incorrectly cached")
print("suite font bridge contract ok")
