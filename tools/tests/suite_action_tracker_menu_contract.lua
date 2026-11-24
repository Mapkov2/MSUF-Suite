local root = assert(arg[1], "repository root required")
local ID = "actionTracker"
local function Load(path, ns)
    assert(loadfile(root .. "/" .. path))("MSUF_Suite", ns)
end
local ns = { Text = function(text) return text end, Client = {} }
Load("MSUF_Suite/Core/SuiteCatalog.lua", ns)
Load("MSUF_Suite/Core/Catalog/QualityOfLife.lua", ns)
local rules = ns.SuiteCatalog[ID].rules

local Widget = {}
Widget.__index = Widget
local function New(parent) return setmetatable({ parent = parent, shown = true }, Widget) end
function Widget:SetWidth(width) self.width = width end
function Widget:SetHeight(height) self.height = height end
function Widget:GetHeight() return self.height or 26 end
function Widget:GetStringHeight() return 16 end
function Widget:SetShown(shown) self.shown = shown end
function Widget:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Widget:ClearAllPoints() end
function Widget:SetPoint(...) self.anchor = { ... } end
function Widget:HookScript(event, fn) self[event] = fn end
CreateFrame = function(_, _, parent) return New(parent) end

local controls, layouts, captions = {}, {}, {}
local tabs, select
local P = { Tr = ns.Text, catalog = ns.SuiteCatalog }
P.Text = function(parent, label)
    local widget = New(parent)
    captions[label] = widget
    return widget
end
P.RuleGrid = function(_, panel, page, id, group, y, _, _, section, _, _, editWhileOff)
    assert(page == "gameplay" and id == ID and section == "section" and editWhileOff)
    local entries = {}
    for _, rule in ipairs(group) do
        if not rule.hidden and not rule.color then entries[#entries + 1] = { rule = rule, widget = New(panel) } end
    end
    return y - #entries * 30, entries
end
Load("MSUF_Suite_Options/Menu/Workspace.lua", P)
P.MenuWorkspace.WrappingTabs = function(picker, values, choose)
    tabs, select = values, choose
    local row = New(picker.header)
    return row, choose
end
Load("MSUF_Suite_Options/Pages/ActionTrackerSettings.lua", P)
local sections = {}
for index, key in ipairs({ "action_tracker", "action_tracker_visibility", "action_tracker_colors" }) do
    local section = { key = key, rules = {} }
    for _, rule in pairs(rules) do
        if rule.section == key and not rule.hidden then section.rules[#section.rules + 1] = rule end
    end
    sections[index] = section
end
local bottom, openTab = P.BuildActionTrackerSettings({}, New(), -250, 640, "gameplay", "section", sections,
    function(entries, prepare)
        for _, entry in ipairs(entries) do
            local key = entry.rule.key
            assert(not controls[key], "duplicate setting " .. key)
            controls[key] = { widget = entry.widget, prepare = prepare }
        end
    end, function(y) layouts[#layouts + 1] = y end)
for key, rule in pairs(rules) do
    if rule.section and not rule.hidden and not rule.color and key ~= "enabled" then
        assert(controls[key], "lost setting " .. key)
    end
end
assert(#tabs == 4 and bottom < -250)
for _, key in ipairs({ "point", "x", "y" }) do assert(not controls[key], "duplicate Edit Mode control " .. key) end
local function Visible(key) return controls[key].widget:IsVisible() end
assert(Visible("look") and Visible("displayPreset") and Visible("glossStrength") and Visible("panelOpacity"))
assert(not Visible("rowHeight") and not Visible("font") and not Visible("hideAfter"))
openTab("layout")
assert(Visible("rows") and Visible("rowHeight") and Visible("insertAnimation") and not Visible("look"))
controls.fontShadowOpacity.prepare()
assert(Visible("showNames") and Visible("font") and Visible("fontSize") and Visible("fontShadowOpacity") and not Visible("insertAnimation"))
controls.showDelves.prepare()
assert(Visible("hideAfter") and Visible("pauseInCombat") and Visible("showDelves") and Visible("showWorld")
    and not Visible("font") and captions["Where to show recent actions"]:IsVisible())
select("appearance")
assert(Visible("look") and not Visible("showDelves") and #layouts >= 3)
print("Action Tracker tabs preserve all settings, exact routing, and accordion height")
