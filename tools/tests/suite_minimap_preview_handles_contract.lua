-- The minimap preview's elements: select, drag, nudge, hover, click and hide, on the real
-- options page. Written against the preview's own handle code first and kept as the parity
-- check of its move onto the Suite preview kit.
local root = assert(arg[1])
local original, ui, P = loadfile
-- What the page and the host's helpers do, in the order they do it; the helpers are the host's
-- (the fixture has none), so spies stand in while the page builds.
local order = {}
local function Log(entry) order[#order + 1] = entry end
local spies = {
    NotePreviewElementMoved = function() Log("note") end,
    ShowPreviewMoveCue = function() Log("cue") end,
    RefreshSelectedLayerButtons = function() Log("chips") end,
}
loadfile = function(path)
    local chunk = assert(original(path))
    if path:match("/Pages/MinimapPreview%.lua$") then
        return function(addon, namespace)
            P = namespace
            local register = P.M.RegisterControlMetadata
            P.M.RegisterControlMetadata = function(widget, ...)
                if type(rawget(widget, "previewUI")) == "table" and widget.previewUI.state then ui = widget.previewUI end
                return register(widget, ...)
            end
            chunk(addon, namespace)
            local build = P.BuildMinimapPreview
            P.BuildMinimapPreview = function(...)
                local previous, create = P.M.PreviewHelpers, CreateFrame
                P.M.PreviewHelpers = spies
                CreateFrame = function(...)
                    local frame = create(...)
                    frame.RegisterForClicks = function(self, ...) self.clicksRegistered = { ... } end
                    return frame
                end
                local first, second = build(...)
                P.M.PreviewHelpers, CreateFrame = previous, create
                return first, second
            end
        end
    end
    return chunk
end
assert(original(root .. "/tools/tests/suite_options_menu_contract.lua"))()
loadfile = original
assert(ui and P, "minimap preview did not build")

local config = P.S.Config("minimap")
for key in pairs(ui.state.layers) do ui.state.layers[key] = true end
ui.state.layers.guides, ui.state.layers.hidden = false, false
config.infoLocation, config.infoClock = true, true
ui.body:Show()
ui.Paint()
local function Item(name)
    for _, item in ipairs(ui.textItems) do if item.spec[1] == name then return item.button end end
    error("no text element " .. name)
end
local location, clock = Item("Location"), Item("Clock")
assert(location:IsShown() and clock:IsShown(), "enabled texts are missing from the preview")

local cx, cy, combat, shift, ctrl = 0, 0, false, false, false
GetCursorPosition = function() return cx, cy end
InCombatLockdown = function() return combat end
IsShiftKeyDown = function() return shift end
IsControlKeyDown = function() return ctrl end
local function Script(widget, name, ...)
    local fn = widget:GetScript(name)
    return fn and fn(widget, ...)
end
local function Press(widget, dx, dy)
    cx, cy = 100, 100
    Script(widget, "OnMouseDown", "LeftButton")
    cx, cy = 100 + dx, 100 + dy
    Script(widget, "OnMouseUp", "LeftButton")
end
local function Pixels(widget, pixels) return pixels / (widget:GetEffectiveScale() * (ui.art.scale or 1)) end
local function Round(value) return math.floor(value + 0.5) end

------------------------------------------------------------------ drag
assert(location:GetScript("OnKeyDown") and location:GetScript("OnMouseDown") and location:GetScript("OnMouseUp")
    and location:GetScript("OnDragStart") and location:GetScript("OnDragStop") and location:GetScript("OnClick")
    and location:GetScript("OnEnter") and location:GetScript("OnLeave"), "a movable element lacks a handle script")
local x0, y0 = config.infoLocationX, config.infoLocationY
cx, cy = 100, 100
Script(location, "OnMouseDown", "LeftButton")
assert(location.moving, "pressing an element must start moving it")
cx, cy = 115, 106
Script(location, "OnMouseUp", "LeftButton")
assert(not location.moving, "releasing must end the move")
assert(config.infoLocationX == Round(x0 + Pixels(location, 15)) and config.infoLocationY == Round(y0 + Pixels(location, 6)),
    "a drag must write the offsets moved by the cursor, in preview units")
assert(ui.body._selectedHandle == location and ui.state.selected.key == "infoLocation", "a drag must select its element")
local x1, y1 = config.infoLocationX, config.infoLocationY
Press(location, 1, 0)
assert(config.infoLocationX == x1 and config.infoLocationY == y1, "a press that barely moves must not write")
Press(location, 2, 0)
assert(config.infoLocationX ~= x1 or config.infoLocationY ~= y1, "two pixels are a drag")
x1, y1 = config.infoLocationX, config.infoLocationY
combat = true
cx, cy = 100, 100
Script(location, "OnMouseDown", "LeftButton")
cx = 140
Script(location, "OnMouseUp", "LeftButton")
combat = false
assert(config.infoLocationX == x1 and not location.moving, "combat must refuse a drag")
-- Another button than the left one starts nothing.
cx, cy = 100, 100
Script(location, "OnMouseDown", "RightButton")
assert(not location.moving, "the right button must not drag")

------------------------------------------------------------------ keyboard
Script(location, "OnClick", "LeftButton")
assert(ui.body._selectedHandle == location and location.keyboardEnabled == true, "a click must select and give it the keyboard")
x1 = config.infoLocationX
Script(location, "OnKeyDown", "RIGHT")
assert(config.infoLocationX == x1 + 1, "an arrow nudges the selected element by 1")
shift = true
Script(location, "OnKeyDown", "RIGHT")
shift = false
assert(config.infoLocationX == x1 + 6, "Shift nudges by 5")
ctrl = true
Script(location, "OnKeyDown", "LEFT")
ctrl = false
assert(config.infoLocationX == x1 - 4, "Ctrl nudges by 10")
y1 = config.infoLocationY
Script(location, "OnKeyDown", "UP")
assert(config.infoLocationY == y1 + 1 and location.propagateKeyboard == false, "a nudged arrow must not reach the game")
Script(location, "OnKeyDown", "ESCAPE")
assert(location.propagateKeyboard == true and ui.body._selectedHandle == location, "Escape is not the preview's key")
combat = true
x1 = config.infoLocationX
Script(location, "OnKeyDown", "RIGHT")
combat = false
assert(config.infoLocationX == x1, "combat must refuse a nudge")
-- The body takes the arrows too (the secure bindings land there).
Script(ui.body, "OnKeyDown", "RIGHT")
assert(config.infoLocationX == x1 + 1, "the preview body nudges the selected element")
ui.body._selectedHandle = nil
Script(location, "OnKeyDown", "RIGHT")
assert(config.infoLocationX == x1 + 1, "an arrow with nothing selected must not move an element")
Script(location, "OnClick", "LeftButton")

------------------------------------------------------------------ hover, selection, hide
Script(location, "OnEnter")
assert(ui.hovered == location, "hovering must remember the element")
Script(location, "OnLeave")
assert(ui.hovered == nil, "leaving must forget it")
Script(clock, "OnClick", "LeftButton")
assert(ui.body._selectedHandle == clock and not location.keyboardEnabled and clock.keyboardEnabled == true,
    "selecting another element moves the keyboard to it")
config.infoClock = false
ui.Paint()
assert(not clock:IsShown() and ui.body._selectedHandle == nil, "a hidden element must not stay selected")
config.infoClock = true
ui.Paint()
-- A target without offsets selects nothing but still opens its section.
local compass = ui.compass
Script(location, "OnClick", "LeftButton")
Script(compass, "OnClick", "LeftButton")
assert(ui.body._selectedHandle == nil and ui.state.selected.key == "compass", "a fixed target must clear the selection")
ui.body:Hide()
ui.body:Show()
-- The map itself recenters after its drag and writes the map position.
local map = ui.map
local mx, my = config.x, config.y
Press(map, 10, 0)
assert(config.x ~= mx or config.y ~= my, "dragging the map writes its position")
assert(ui.body._selectedHandle == map, "dragging the map selects it")

------------------------------------------------------------------ clicks and order
-- Only the left button clicks a preview element: a right click selects nothing.
for _, element in ipairs(ui.handles) do
    assert(element.clicksRegistered and #element.clicksRegistered == 1 and element.clicksRegistered[1] == "LeftButtonUp",
        "a movable element takes more than the left button: " .. tostring(element._label))
end
-- Order, as the old code did it: a press moves nothing in the panels; a release stops the move, writes,
-- and only then selects the element and shows its cue (the cue reads the note that it moved); a selection
-- refreshes the layer chips before the keyboard moves.
local setMany, setBindings, helpers = P.SetMany, P.M.SetPreviewArrowBindings, P.M.PreviewHelpers
P.M.PreviewHelpers = spies
P.SetMany = function(id, values) Log("write"); return setMany(id, values) end
P.M.SetPreviewArrowBindings = function(_, enabled) Log("bindings:" .. tostring(enabled)) end
local startMoving, stopMoving, keyboard = clock.StartMoving, clock.StopMovingOrSizing, clock.EnableKeyboard
clock.StartMoving = function(self) Log("startMoving"); return startMoving(self) end
clock.StopMovingOrSizing = function(self) Log("stopMoving"); return stopMoving(self) end
clock.EnableKeyboard = function(self, on) Log("keyboard:" .. tostring(on)); return keyboard(self, on) end
local function Took()
    local out = order
    order = {}
    return out
end
local function InOrder(entries, ...)
    local at = 1
    for _, want in ipairs({ ... }) do
        local found
        for i = at, #entries do
            if entries[i] == want then found = i; break end
        end
        assert(found, "'" .. want .. "' missing or out of order in: " .. table.concat(entries, " "))
        at = found + 1
    end
end
Script(ui.compass, "OnClick", "LeftButton")
Took()
cx, cy = 100, 100
Script(clock, "OnMouseDown", "LeftButton")
local pressed = Took()
InOrder(pressed, "startMoving")
for _, entry in ipairs(pressed) do
    assert(entry ~= "chips" and entry ~= "cue" and entry ~= "write" and entry:sub(1, 8) ~= "keyboard",
        "pressing an element selected it or wrote: " .. entry)
end
cx = 130
Script(clock, "OnMouseUp", "LeftButton")
local released = Took()
InOrder(released, "stopMoving", "write", "chips", "keyboard:true", "bindings:true", "cue")
InOrder(released, "note", "cue")
-- A click that did not move still selects and shows the cue, and writes nothing.
Script(clock, "OnMouseDown", "LeftButton")
Took()
Script(clock, "OnMouseUp", "LeftButton")
local clicked = Took()
InOrder(clicked, "stopMoving", "chips", "cue")
for _, entry in ipairs(clicked) do assert(entry ~= "write" and entry ~= "note", "a click wrote or noted a move") end
P.SetMany, P.M.SetPreviewArrowBindings, P.M.PreviewHelpers = setMany, setBindings, helpers
clock.StartMoving, clock.StopMovingOrSizing, clock.EnableKeyboard = nil, nil, nil
print("minimap preview handles: drag, threshold, combat, keyboard steps, hover, selection, hide, click buttons and order checks passed")
