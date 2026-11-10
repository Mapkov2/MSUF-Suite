local root, flavor = assert(arg[1]), arg[2] or "Mainline"
assert(flavor == "Mainline" or flavor == "Forever")
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua", [=[
do (function()
Suite.Client.isForever = arg[2] == "Forever"
local enableMouse = Widget.EnableMouse
Widget.EnableMouse = function(self, value)
    self.feedbackMouse = value
    return enableMouse(self, value)
end
local config = S.Config(ID)
module.config, module.context, module.active = config, S.NewContext(ID), true
module:Enable(); Run()
config.c1_on = true
config.listsData = assert(Codec.EncodeLists({v=1, specs={[62]={c1={}}}}))
local saved = config.listsData
module:Refresh(); Run()
assert(not C.plans.c1 or #C.plans.c1.entries == 0, "empty bar contains icons during normal play")
local picked
assert(S.CooldownManagerSetPreview(true, function(slot) picked = slot end))
Run()
local plan = assert(C.plans.c1, "missing custom plan: on=" .. tostring(C.views.c1 and C.views.c1.on) .. ", preview=" .. tostring(C.state.preview))
assert(#plan.entries == 3 and plan.entries[1].src == "p", "empty preview has no layout samples")
local order = C.Catalog.order
C.Catalog.order = {}
C.Preview.Decorate()
for _, entry in ipairs(plan.entries) do
    assert(entry.texture ~= C.Const.QUESTION_ICON, "empty preview still shows unexplained question marks")
end
C.Catalog.order = order
local texture = C.Catalog.RecordTexture
C.Catalog.RecordTexture = function() return C.Const.QUESTION_ICON end
C.Preview.Decorate()
for _, entry in ipairs(plan.entries) do
    assert(entry.texture ~= C.Const.QUESTION_ICON, "unavailable catalog texture became a sample question mark")
end
C.Catalog.RecordTexture = texture
C.Preview.PaintLabels()
local label = assert(C.Preview.labels.c1)
assert(label:IsShown() and label.label.text:find("empty bar: add spells", 1, true), "empty preview lacks its explanation")
label.scripts.OnClick(label)
assert(picked == "c1", "empty preview cannot open its bar settings")
local before = writes
C.Preview.PaintLabels()
assert(before == writes, "unchanged empty labels repaint")
assert(S.CooldownManagerSetPreview(false))
assert(not C.bars.c1.shown and not label:IsShown(), "closing the editor retained samples until a later frame")
Run()
for _, current in pairs(C.plans) do
    for _, entry in ipairs(current.entries) do assert(entry.src ~= "p", "sample entered the normal runtime") end
end
assert(config.listsData == saved, "preview cleanup changed the user's spell lists")
S.editMode = true; module:Refresh(); Run()
assert(label:IsShown() and label.feedbackMouse == false, "Edit Mode sample label must allow mover drags")
picked = nil; label.scripts.OnClick(label)
assert(picked == nil, "Edit Mode label retained the options callback")
S.editMode = false; module:Refresh(); Run()
assert(#C.plans.c1.entries == 0 and not label:IsShown(), "leaving Edit Mode retained sample icons")
S.CooldownManagerSetPreview(true, function() end); Run()
combat = true; Fire("PLAYER_REGEN_DISABLED")
assert(not label:IsShown(), "combat retained an interactive sample label")
S.CooldownManagerSetPreview(false); Run()
assert(#C.plans.c1.entries == 0, "closing in combat retained an empty sample")
combat = false; Fire("PLAYER_REGEN_ENABLED")
module.active = false; module:Disable()
print("empty CDM preview labels, neutral slots, immediate cleanup and unchanged lists passed: " .. tostring(arg[2]))
end)() end
]=], "------------------------------------------------------------------ enable: capture")
