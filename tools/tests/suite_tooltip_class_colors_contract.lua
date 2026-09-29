local root = assert(arg[1], "repository root required")
local installed, callback = {}, nil
local secret = "secret"
local suite = {
    Install = function(id, module) installed[id] = module end,
    Public = function(value) return value ~= secret end,
    PublicText = function(value)
        return value ~= secret and type(value) == "string" and value ~= "" and value or nil
    end,
}
local blocked = false
local ns = { Safety = { IsForbidden = function() return blocked end } }
local tooltip = {}
GameTooltip = tooltip
Enum = { TooltipDataLineType = { UnitName = 12 } }
RAID_CLASS_COLORS = { MAGE = { r = .2, g = .8, b = 1 } }
TooltipDataProcessor = { AddLinePreCall = function(kind, fn)
    assert(kind == Enum.TooltipDataLineType.UnitName and not callback)
    callback = fn
end }
local player, class = true, "MAGE"
UnitIsPlayer = function(unit) assert(unit == "target"); return player end
UnitClass = function(unit) assert(unit == "target"); return "Mage", class end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TooltipClassColors.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
local module = assert(installed.tooltipClassColors)
module.active = true
module:Enable()
module:Enable()
assert(callback, "unit-name tooltip callback was not installed")
local original = { r = 1, g = 1, b = 1 }
local line = { unitToken = "target", leftColor = original }
callback(tooltip, line)
assert(line.leftColor == RAID_CLASS_COLORS.MAGE, "player name did not use class color")

for _, state in ipairs({ false, secret }) do
    player = state
    line.leftColor = original
    callback(tooltip, line)
    assert(line.leftColor == original, "non-public player state changed the tooltip")
end
player = true
for _, value in ipairs({ secret, "UNKNOWN" }) do
    class = value
    line.leftColor = original
    callback(tooltip, line)
    assert(line.leftColor == original, "unknown class changed the tooltip")
end
class = "MAGE"
line.unitToken = secret
callback(tooltip, line)
assert(line.leftColor == original, "secret unit was used")
line.unitToken = "target"
blocked = true
callback(tooltip, line)
assert(line.leftColor == original, "forbidden tooltip was changed")
blocked = false
module.active = false
callback(tooltip, line)
assert(line.leftColor == original, "disabled module changed the tooltip")
print("Suite tooltip class colors passed")
