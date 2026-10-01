local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local installed, reported = {}, {}
local secret = "secret"
local suite = {
    Install = function(id, module) installed[id] = module end,
    Public = function(value) return value ~= secret end,
    PublicText = function(value)
        return value ~= secret and type(value) == "string" and value ~= "" and value or nil
    end,
    Dispatch = Support.Dispatcher(reported),
}
local blocked = false
local ns = { Safety = { IsForbidden = function() return blocked end } }
local tooltip = {}
GameTooltip = tooltip
-- The first line of a unit tooltip is its name line (GameTooltipTextLeft1).
local nameText = {}
function nameText:SetTextColor(r, g, b) self.color = { r, g, b } end
GameTooltipTextLeft1 = nameText
Enum = { TooltipDataType = { Unit = 2 }, TooltipDataLineType = { UnitName = 12 } }
RAID_CLASS_COLORS = { MAGE = { r = .2, g = .8, b = 1 } }
local player, class = true, "MAGE"
UnitIsPlayer = function(unit) assert(unit == "target"); return player end
UnitClass = function(unit) assert(unit == "target"); return "Mage", class end
local tooltips = Support.TooltipFixture(root, suite, ns)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TooltipClassColors.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
local module = assert(installed.tooltipClassColors)
module.active = true
module:Enable()
module:Enable()
assert(#tooltips.post[Enum.TooltipDataType.Unit] == 1 and not next(tooltips.pre),
    "class colors registered twice or used a line pre-call")
-- Blizzard's line data is read, never written.
local function Data(unitToken)
    local line = { type = Enum.TooltipDataLineType.UnitName, unitToken = unitToken, lineIndex = 1 }
    local readOnly = setmetatable({}, { __index = line, __newindex = function(_, key)
        error("tooltip line data was written: " .. tostring(key))
    end })
    return { lines = { readOnly } }
end
local function Build(unitToken)
    nameText.color = nil
    tooltips.Run(Enum.TooltipDataType.Unit, tooltip, Data(unitToken))
    return nameText.color
end
local color = Build("target")
assert(color and color[1] == .2 and color[2] == .8 and color[3] == 1 and #reported == 0,
    "player name did not use class color")
for _, state in ipairs({ false, secret }) do
    player = state
    assert(not Build("target"), "non-public player state changed the tooltip")
end
player = true
for _, value in ipairs({ secret, "UNKNOWN" }) do
    class = value
    assert(not Build("target"), "unknown class changed the tooltip")
end
class = "MAGE"
assert(not Build(secret), "secret unit was used")
blocked = true
assert(not Build("target"), "forbidden tooltip was changed")
blocked = false
module.active = false
assert(not Build("target") and #reported == 0, "disabled module changed the tooltip")
print("Suite tooltip class colors passed")
