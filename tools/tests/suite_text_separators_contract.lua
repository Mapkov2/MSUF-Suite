local root = assert(arg[1], "repository root required")
local suite, menu = {}, {}
local english = "Current setup for %s · %s"
local translated = "%s · %s verwenden"
local preview = "Saved waypoint · Preview"
local locale = {
    [english] = translated,
    [preview] = "Gespeicherter Wegpunkt · Vorschau",
    ["%d yd"] = "%d Yards",
    ["%d min %02d sec"] = "%d Min. %02d Sek.",
}
local env = setmetatable({ MSUF_NS = { L = locale }, MSUFSuite = suite,
    MSUF2 = { Widgets = {}, Theme = {}, Tr = function(key) return locale[key] or key end } }, { __index = _G })
env._G = env
local function Load(path, private)
    return setfenv(assert(loadfile(root .. "/" .. path)), env)("MSUF_Suite", private)
end

Load("MSUF_Suite/Core/Platform.lua", suite)
local modelNamespace = { Suite = { Text = suite.Text } }
local function Readout(sample)
    return sample.readoutFormat:format(sample.readoutA, sample.readoutB, sample.readoutC)
end
local config = { showDistance = true, showETA = true, units = 1, display = 2, hideDistance = 10 }
local function Sample()
    Load("MSUF_Suite_QualityOfLife/NavigationModel.lua", modelNamespace)
    return modelNamespace.Navigation.Sample({}, config, 1, 450)
end
local yards, minutes = locale["%d yd"], locale["%d min %02d sec"]
locale["%d yd"], locale["%d min %02d sec"] = nil, nil
assert(Readout(Sample()) == "450 yd - 1 min 04 sec", "navigation uses an unreadable distance/ETA separator")
locale["%d yd"], locale["%d min %02d sec"] = yards, minutes
local sample = Sample()
assert(Readout(sample) == "450 Yards - 1 Min. 04 Sek.", "localized distance or ETA lost its format")
assert(sample.info == "Gespeicherter Wegpunkt - Vorschau", "localized waypoint preview kept the unsupported glyph")

locale["%s · %s"] = "%s | %s"
sample = Sample()
assert(Readout(sample) == "450 Yards | 1 Min. 04 Sek.", "translator's plain separator was lost")
locale["%s · %s"] = nil
sample = Sample()
config.showETA = false
modelNamespace.Navigation.Readout(sample, config, 450, 7)
assert(Readout(sample) == "450 Yards", "disabling ETA retained a separator")

suite.HostBridge = { Menu2 = function() return {} end }
suite.Suite = { Text = suite.Text }
Load("MSUF_Suite_Options/Menu/Bridge.lua", menu)
assert(menu.Tr(english) == translated, "plain separator formatting should be explicit")
assert(menu.Tr(english, true):format("Marco", "Tasten · Leveln") == "Marco - Tasten · Leveln verwenden",
    "menu caption should retain user text and replace only its own separator")
assert(suite.Text("col·laborar · B • C", true) == "col·laborar - B - C",
    "separator conversion changed a letter or failed to cover the bullet")
print("Suite separators: localized waypoint and menu caption passed")
