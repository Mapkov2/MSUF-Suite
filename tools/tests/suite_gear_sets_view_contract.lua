local root = assert(arg[1], "repository root required")

local function Widget()
    local object = {}
    function object:SetTexture(file) self.file = file end
    function object:SetPoint() end
    function object:SetSize() end
    function object:SetScript() end
    function object:SetEnabled() end
    function object:SetAlpha() end
    function object:RegisterForClicks() end
    function object:RegisterForDrag() end
    return object
end

local ns = { GearActions = {}, GroupLayout = { UpdateScroll = function() return 0 end } }
assert(loadfile(root .. "/MSUF_Suite_CharacterPanel/GearSetsView.lua"))("MSUF_Suite_CharacterPanel", ns)
local style = { Row = Widget, Fill = Widget, Texture = Widget, Font = Widget, width = 230, text = {} }
function style.Visible(widget, shown) widget.shown = shown end
function style.Text() end
function style.Place() end
function style.Tint() end

local active = { id = 1, name = "Test set", equipped = true }
local session = { rows = { active }, selected = active, selectedID = 1, revision = 1, canCreate = true }
local pane = { parent = Widget(), blank = Widget(), new = Widget(), selectedActions = Widget(), equip = Widget() }
local view = { setPane = pane, setManager = session }
local rail = { view = view, parent = pane.parent, scroll = Widget() }
view.rail = rail
pane.list = { view = view, pane = pane, style = style, canvas = Widget(), height = 36, width = 200, buttons = {} }
ns.GearSetsView.ShowList(rail, nil, {}, false, false, style)
local check = pane.list.buttons[1].check
assert(check.shown and check.file == [[Interface\Buttons\UI-CheckBox-Check]], "the equipped set needs the native check texture")
active.equipped, session.revision = false, 2
ns.GearSetsView.ShowList(rail, nil, {}, false, false, style)
assert(not check.shown, "an unequipped set kept its checkmark")
print("equipment set checkmark shows the native texture only for the equipped set")
