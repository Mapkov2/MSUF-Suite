local _, P = ...
local NS, S = P.NS, P.Suite

-- One TooltipDataProcessor post-call per tooltip type, shared by every Suite
-- helper that adds to Blizzard's main tooltip, with one eligibility check and
-- one line style. Helpers add lines or recolor the name line after Blizzard
-- built the tooltip and before it is sized and shown. They never ask the
-- tooltip to rebuild: RefreshDataNextUpdate writes GameTooltip's update
-- fields from addon code (GameTooltip.lua). They never register line
-- pre-calls either: with one in place Blizzard packs every line of every
-- tooltip through a forbidden attribute delegate, and a registration cannot be
-- removed (TooltipDataHandler.lua). Lines that become due while a tooltip is
-- open (a modifier pressed, data arriving) join it through Lines.Open and
-- Lines.Grow instead of a rebuild.
local Lines = {}
S.TooltipLines = Lines
local LABEL_R, LABEL_G, LABEL_B = .65, .81, .87
local VALUE_R, VALUE_G, VALUE_B = 1, .88, .58
local callbacks = {}

local function Run(list, tooltip, data)
    if tooltip ~= GameTooltip or NS.Safety.IsForbidden(tooltip)
        or not S.Public(data) or type(data) ~= "table" or not canaccesstable(data) then return end
    for i = 1, #list do
        local entry = list[i]
        if entry.module.active then S.Dispatch(entry.callback, tooltip, data) end
    end
end

-- callback(tooltip, data) runs for one Enum.TooltipDataType name while module
-- is active. Post-calls cannot be removed, so each is registered once.
function Lines.Add(module, kind, callback)
    local list = callbacks[kind]
    if not list then
        list = {}
        callbacks[kind] = list
        local tooltipType = kind == "AllTypes" and TooltipDataProcessor.AllTypes or Enum.TooltipDataType[kind]
        TooltipDataProcessor.AddTooltipPostCall(tooltipType, function(tooltip, data)
            Run(list, tooltip, data)
        end)
    end
    for i = 1, #list do
        if list[i].module == module and list[i].callback == callback then return end
    end
    list[#list + 1] = { module = module, callback = callback }
end

-- The main tooltip and its data while it is open and readable; the data is
-- the table Blizzard handed the post-calls of this build
-- (TooltipDataHandlerMixin:GetPrimaryTooltipData).
function Lines.Open()
    local tooltip = GameTooltip
    if not tooltip:IsShown() or NS.Safety.IsForbidden(tooltip) then return end
    local data = tooltip:GetPrimaryTooltipData()
    if not S.Public(data) or type(data) ~= "table" or not canaccesstable(data) then return end
    return tooltip, data
end

-- Sizes an open tooltip to lines added after its build; Show on a shown
-- tooltip only lays it out again.
function Lines.Grow(tooltip)
    tooltip:Show()
end

-- One label/value line in the Suite tooltip style; label is English text.
function Lines.Line(tooltip, label, value, r, g, b)
    tooltip:AddDoubleLine(S.Text(label), value, LABEL_R, LABEL_G, LABEL_B,
        r or VALUE_R, g or VALUE_G, b or VALUE_B)
end

-- The unit token of a unit tooltip and the text of its name line, read from
-- the UnitName line Blizzard added first (never rebuilt from GUIDs).
function Lines.UnitName(data)
    local lines = data.lines
    if not S.Public(lines) or type(lines) ~= "table" or not canaccesstable(lines) then return end
    local line = lines[1]
    if not S.Public(line) or type(line) ~= "table" or not canaccesstable(line)
        or not S.Public(line.type) or line.type ~= Enum.TooltipDataLineType.UnitName then return end
    local unit = S.PublicText(line.unitToken)
    if not unit then return end
    local index = line.lineIndex
    return unit, S.Public(index) and index == 1 and GameTooltipTextLeft1 or nil
end
