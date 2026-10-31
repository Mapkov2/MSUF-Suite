local root = assert(arg[1], "repository root required")
-- Cooldown manager page tools (package cdm11-E), through the real runtime of
-- the main cooldown manager contract's harness: "Pick a frame" (the next left
-- click names the frame under the cursor; a right click, Escape, combat or the
-- menu itself cancel), "Copy layout to other specializations" (all or one,
-- one undoable step, through the per-specialization layout data) and the
-- Masque switch's gate.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua", [=[
do (function()
assert(loadfile(root .. "/MSUF_Suite/Core/ProfileVariants.lua"))("MSUF_Suite", Suite)
local CDM, KEYS = Suite.CDM, Suite.CDM.KEYS
local config = S.Config(ID)
module.config, module.context = config, S.NewContext(ID)
local masqueLoaded = false
C_AddOns = { DoesAddOnExist = function() return true end, GetAddOnEnableState = function() return 2 end,
    IsAddOnLoaded = function(name) return name == "MSUF_Suite" or name == "MSUF_Suite_Modules" or name == ADDON
        or name == "Masque" and masqueLoaded end }
UnitGUID = function() return "Player-1-1" end
GetNumSpecializations = function() return 3 end
GetSpecializationInfoByID = function(id) return id, "Spec" .. id end
S.started = true
assert(S.Set(ID, "enabled", true))
S.Apply(ID)
local function Settle() Run(); Run() end
local function Spec(index)
    specIndex = index
    assert(Fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED"))
    Settle()
end
Settle()
-- Widgets the page tools use beyond the harness.
Widget.SetPropagateKeyboardInput = function(self, on) self.propagate = on end
Widget.EnableKeyboard = function() end
Widget.GetName = function(self) return self.name end
local combatNow = false
local dropdown
local menu = New("Frame", UIParent, "E_Menu")
local options = { Suite = Suite, S = S, T = {}, M = { frame = menu }, W = { OpenDropdown = function(_, items, _, pick) dropdown = { items = items, pick = pick } end },
    catalog = Suite.SuiteCatalog, Gates = {}, SearchPreparers = {}, Tr = function(text) return text end,
    Combat = function() return combatNow end, Refresh = function() end,
    WithHistory = function(_, _, callback) return callback() end }
options.Get = function(id, key) return S.Config(id)[key] end
options.SetMany, options.Set = S.SetMany, S.Set
options.Meta = function() return {} end
for _, name in ipairs({ "CooldownManagerData", "CooldownManagerLists", "CooldownManagerBars", "CooldownManagerFrames" }) do
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/" .. name .. ".lua"))("MSUF_Suite_Options", options)
end
local Page = options.CDMPage
Page.CommitFocus, Page.ClosePopups = function() end, function() end
Page.PlayerSpec, Page.ForeignSpec = Page.Spec, function() return false end
local tools = Page.Tools()
assert(Page.Tools() == tools, "the tools are built once")
local OTHER = CDM.OTHER_ANCHOR

------------------------------------------------------------------ the Masque switch
local gate = options.Gates[ID]
local rule = S.catalog[ID].rules[KEYS.c1.masque]
local ok, why = gate(rule)
assert(ok == false and why == "Masque is not loaded.", "without Masque the switch says why it is off")
masqueLoaded = true
Page.selected = "ess"
assert(gate(rule) == true, "with Masque it is available")
Page.selected = "buf"
assert(gate(rule) == false, "a bar of buff icons has no use for it")
masqueLoaded = false
-- Copying the settings of another bar never copies its attachment, the frame name included.
assert(S.SetMany(ID, { ess_anchorFrame = "FromEss", c2_anchorFrame = "Keep", c2_zoom = 3 }))
Page.selected = "c2"
assert(Page.CopyBarSettings("ess", "c2") and config.c2_zoom == config.ess_zoom and config.c2_anchorFrame == "Keep",
    "copying a bar's settings leaves its attachment alone")
config.ess_anchorFrame, config.c2_anchorFrame = "", ""

------------------------------------------------------------------ copy a layout to the other specializations
local Codec = CDM.Codec
local function Data() return Codec.DecodePositions(config.positionsData) end
Spec(2)
assert(config.specPositions == true and Data().spec == 63, "layouts are kept per specialization")
Page.selected = "c1"
assert(S.SetMany(ID, { c1_on = true, c1_x = 11, c1_y = 22, c1_size = 44, c1_anchor = OTHER, c1_anchorFrame = "ChatFrame1",
    c1_side = 2, c1_gap = 7 }))
Settle()
local before = config.positionsData
combatNow = true
local done, reason = tools.CopyLayout("c1")
assert(done == false and reason == "Finish combat before editing the suite" and config.positionsData == before, "no copy in combat")
combatNow = false
config.specPositions = false
done, reason = tools.CopyLayout("c1")
assert(done == false and reason:find("Save bar layout per specialization", 1, true) and config.positionsData == before,
    "without per-specialization layouts there is nothing to copy to")
config.specPositions = true
local copied, count = tools.CopyLayout("c1")
assert(copied == true and count == 2 and config.positionsData ~= before, "the layout goes to the two other specializations")
Settle()
for _, spec in ipairs({ 62, 64 }) do
    local layout = assert(Data().specs[spec] and Data().specs[spec].c1, "specialization " .. spec .. " has the layout")
    assert(layout.x == 11 and layout.y == 22 and layout.size == 44 and layout.anchor == OTHER and layout.anchorFrame == "ChatFrame1"
        and layout.side == 2 and layout.gap == 7, "position, attachment (the frame name too), rows and sizes travel together")
end
assert(Data().specs[63] == nil or Data().specs[63].c1 == nil, "the current specialization keeps its layout in the settings")
-- Another bar's saved layout is left alone; asking again changes nothing.
copied, count = tools.CopyLayout("c1")
assert(copied == true and count == 0, "a layout that is there already is not copied again")
-- A switch brings the copied layout back.
Spec(1)
assert(config.c1_x == 11 and config.c1_y == 22 and config.c1_size == 44 and config.c1_anchor == OTHER
    and config.c1_anchorFrame == "ChatFrame1", "the other specialization wears the copied layout")
-- To one specialization, from the menu, as one undoable step.
assert(S.SetMany(ID, { c1_x = 99 }))
Settle()
tools.OpenCopy({})
assert(dropdown and dropdown.items[1].value == 0 and dropdown.items[1].text == "All other specializations"
    and dropdown.items[2].value == 63 and dropdown.items[2].text == "Spec63" and dropdown.items[3].value == 64
    and dropdown.items[3].text == "Spec64" and dropdown.items[4] == nil, "the menu names the other specializations")
local previous = config.positionsData
dropdown.pick(64)
Settle()
assert(Data().specs[64].c1.x == 99 and Data().specs[63].c1.x == 11, "one specialization takes it, the other is untouched")
assert(Page.undo, "the copy offers its Undo")
Page.RunUndo()
Settle()
assert(config.positionsData == previous and Data().specs[64].c1.x == 11, "Undo gives every specialization its layout back")
dropdown.pick(0)
Settle()
assert(Data().specs[63].c1.x == 99 and Data().specs[64].c1.x == 99, "All other specializations copies to both")
Spec(2)

------------------------------------------------------------------ pick a frame
local function Watcher()
    for i = #all, 1, -1 do
        if all[i].scripts.OnKeyDown then return all[i] end
    end
end
local mouse = {}
GetMouseFoci = function() return mouse end
local function Click(button) local w = Watcher(); w.scripts.OnEvent(w, "GLOBAL_MOUSE_DOWN", button) end
local function Start()
    combatNow = false
    Page.selected = "c2"
    tools.Pick()
    local w = Watcher()
    assert(w and w.shown, "picking starts a watcher")
    w.scripts.OnShow(w)
    assert(w.events.GLOBAL_MOUSE_DOWN and w.events.PLAYER_REGEN_DISABLED, "it listens to clicks and to combat only while shown")
    return w
end
local w = Start()
assert(not w.scripts.OnUpdate, "no polling")
-- Nothing named under the cursor: it keeps waiting.
mouse = { UIParent, New("Frame", UIParent) }
Click("LeftButton")
assert(w.shown and config.c2_anchor ~= OTHER, "an unnamed spot picks nothing")
-- Inside the menu itself: ignored.
mouse = { New("Frame", menu, "E_MenuChild") }
_G.E_MenuChild = mouse[1]
Click("LeftButton")
assert(w.shown and config.c2_anchor ~= OTHER, "the menu is no target")
-- Other buttons do nothing; the left click names the first named frame at or above what is under the cursor.
local named = New("Frame", UIParent, "E_Named")
_G.E_Named = named
mouse = { New("Frame", New("Frame", named)) }
Click("MiddleButton")
assert(w.shown, "only left and right clicks count")
Click("LeftButton")
assert(not w.shown and config.c2_anchor == OTHER and config.c2_anchorFrame == "E_Named" and config.c2_x == 0 and config.c2_y == 0,
    "the click attaches the bar to the frame")
w.scripts.OnHide(w)
assert(next(w.events) == nil, "the watcher stops listening")
-- A right click, Escape and combat cancel.
config.c2_anchor, config.c2_anchorFrame = 1, ""
w = Start()
Click("RightButton")
assert(not w.shown and config.c2_anchor == 1, "a right click cancels")
w = Start()
w.scripts.OnKeyDown(w, "A")
assert(w.shown and w.propagate == true, "other keys go on")
w.scripts.OnKeyDown(w, "ESCAPE")
assert(not w.shown and w.propagate == false and config.c2_anchor == 1, "Escape cancels and is not passed on")
w = Start()
w.scripts.OnEvent(w, "PLAYER_REGEN_DISABLED")
assert(not w.shown and config.c2_anchor == 1, "combat cancels")
combatNow = true
tools.Pick()
assert(not Watcher().shown, "no picking in combat")
combatNow = false
-- The pick is one history entry and names the bar.
mouse = { named }
w = Start()
Click("LeftButton")
assert(config.c2_anchorFrame == "E_Named" and Page.note and Page.note:find("E_Named", 1, true), "the bar says what it is attached to")
Page.selected = "ess"
config.c2_anchor, config.c2_anchorFrame = 1, ""
module.active = false
module:Disable()
module.context:Release()
Run(5)
print("suite_cdm_layout_options_contract: ok")
end)() end
]=], "------------------------------------------------------------------ enable: capture")
