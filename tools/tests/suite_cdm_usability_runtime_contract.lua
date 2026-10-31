local root = assert(arg[1], "repository root required")
-- Usability changes exercise the real controller, event map, movers and
-- pooled preview frames, including zero writes on an unchanged repaint.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua", [=[
do (function()
local CDM, KEYS = Suite.CDM, Suite.CDM.KEYS
local config = S.Config(ID)
module.config, module.context, module.active = config, S.NewContext(ID), true
SecureCmdOptionParse = Evaluate
module:Enable()
Run()
assert(C.Effects.RecommendationFrame() == nil, "an off assisted icon created frames")
module:RegisterMovers()
local function Controls(slot)
    local found = {}
    for _, control in ipairs(elements[slot].extraControls) do found[control.id] = control end
    return found
end
assert(Controls("bar").barWidth and Controls("bar").barHeight and not Controls("bar").size,
    "Buff bars need timer dimensions in Edit Mode")
config.c1_kind, config.c1_on = CDM.KIND.AURA_BAR, true
module:Refresh(); Run(); module:RegisterMovers()
assert(Controls("c1").barWidth and not Controls("c1").size, "custom buff bars need timer dimensions")
config.c1_kind, config.c1_cooldownDuration = CDM.KIND.COOLDOWN, true
module:Refresh(); Run(); module:RegisterMovers()
assert(Controls("c1").barWidth and not Controls("c1").perRow, "cooldown timers need timer dimensions")
config.c1_cooldownDuration = false
module:Refresh(); Run(); module:RegisterMovers()
assert(Controls("c1").size and Controls("c1").perRow and not Controls("c1").barWidth,
    "returning to icons must refresh the registered popup controls")

config.assistIcon, config.assistIconKeySize, config.assistIconKeyPos = true, 17, 1
config.assistIconAlpha, config.assistIconBorder, config.assistIconBorderColor = 65, 2, "336699"
config.assistIconZoom = 15
module:Refresh(); Run()
C.Effects.Assist(133)
local icon = assert(C.Effects.RecommendationFrame())
assert(icon:IsShown() and icon.alpha == .65 and icon.border and icon.border:IsShown(), "assisted icon appearance")
assert(icon.key.size == 17 and icon.layKeyPoint == "TOPLEFT" and icon.layZoom == 15, "assisted icon text/crop")
local before = writes
for i = 1, 10 do C.Effects.Recommendation() end
assert(writes == before, "unchanged recommendations repeated widget writes")
config.assistIconVis = CDM.VIS.COMBAT
module:Refresh(); Run()
assert(not icon:IsShown(), "combat-only icon appeared outside combat")
combat = true
assert(Fire("PLAYER_REGEN_DISABLED"))
assert(icon:IsShown(), "combat transition failed to show assisted icon")
combat = false
assert(Fire("PLAYER_REGEN_ENABLED"))
assert(not icon:IsShown(), "combat end failed to hide assisted icon")
config.assistIconVis = CDM.VIS.COMBAT_OR_TARGET
module:Refresh(); Run()
targetExists = true
assert(Fire("PLAYER_TARGET_CHANGED"))
assert(icon:IsShown(), "target transition failed to show assisted icon")
targetExists = false
assert(Fire("PLAYER_TARGET_CHANGED"))
assert(not icon:IsShown(), "target loss failed to hide assisted icon")
config.assistIconVis, config.assistIconAnchor = CDM.VIS.ALWAYS, 2
module:Refresh(); Run()
assert(icon.point[2] == C.bars.ess.frame, "assisted icon did not attach to Essential cooldowns")
module:RegisterMovers()
local assist = elements.assistIcon
local capture = assist.captureState()
assert(assist.movePosition({ state = capture, deltaX = 12, deltaY = -7, phase = "drag" }))
assert(icon.point[2] == C.bars.ess.frame and icon.point[4] == config.assistIconX + 12
    and icon.point[5] == config.assistIconY - 7, "attached icon drag preview jumped to the screen center")
assert(assist.movePosition({ state = capture, deltaX = 12, deltaY = -7, phase = "commit" }))
module:Refresh(); Run()
assert(icon.point[2] == C.bars.ess.frame and icon.point[4] == capture.values.assistIconX + 12,
    "attached icon commit changed its anchor or offset")
local rect = C.Layout.FrameRect
local center = UIParent.GetCenter
C.Layout.FrameRect = function(unit) assert(unit == "player"); return 100, 200, 300, 400 end
UIParent.GetCenter = function() return 50, 50 end
config.assistIconAnchor, config.assistIconX, config.assistIconY = 3, 0, 0
module:Refresh(); Run()
assert(icon.point[2] == UIParent and icon.point[4] == 150 and icon.point[5] == 250,
    "player attachment must stay outside the protected frame's anchor family")
capture = assist.captureState()
assert(assist.movePosition({ state = capture, deltaX = 12, deltaY = -7, phase = "drag" }))
assert(icon.point[2] == UIParent and icon.point[4] == 162 and icon.point[5] == 243,
    "player-attached icon drag preview lost its rectangle transform")
assert(assist.movePosition({ state = capture, deltaX = 12, deltaY = -7, phase = "commit" }))
module:Refresh(); Run()
assert(icon.point[4] == 162 and icon.point[5] == 243, "player-attached commit jumped after refresh")
C.Layout.FrameRect, UIParent.GetCenter = rect, center

-- Native FontStrings reject text before a font is initialized.
local setText = Widget.SetText
Widget.SetText = function(self, ...)
    assert(self.kind ~= "FontString" or self.font, "FontString:SetText(): Font not set")
    return setText(self, ...)
end
local picked
S.CooldownManagerSetPreview(true, function(slot) picked = slot end)
Run()
C.Preview.PaintLabels()
local label = assert(C.Preview.labels.ess, "shown bar lacks its pooled outline")
assert(label:IsShown(), "outline did not show with options")
label.scripts.OnClick(label)
assert(picked == "ess", "outline click did not select its own bar")
before = writes
C.Preview.PaintLabels()
assert(writes == before, "unchanged labels repainted")
combat = true
assert(Fire("PLAYER_REGEN_DISABLED"))
assert(not label:IsShown(), "combat left an interactive bar outline")
picked = nil
label.scripts.OnClick(label)
assert(picked == nil, "combat outline callback selected a bar")
combat = false
assert(Fire("PLAYER_REGEN_ENABLED"))
assert(C.Preview.labels.ess == label and label:IsShown(), "combat end did not reuse the pooled outline")
S.CooldownManagerSetPreview(false)
assert(not label:IsShown(), "closing options kept the label")
S.CooldownManagerSetPreview(false)
-- A new pooled label stays hidden and uncached if initialization raises.
C.Preview.labels.ess = nil
local styledFont = S.SetStyledFont
S.SetStyledFont = function(font, ...)
    if C.Preview.labels.ess and font == C.Preview.labels.ess.label then error("label initialization failure") end
    return styledFont(font, ...)
end
S.CooldownManagerSetPreview(true, function(slot) picked = slot end)
local errors = #dispatch.errors
dispatch.expect = true
local ok, failure = pcall(Run)
dispatch.expect = false
assert(ok, "label failure escaped its flush boundary: " .. tostring(failure))
assert(#dispatch.errors == errors + 1 and tostring(dispatch.errors[#dispatch.errors]):find("label initialization failure", 1, true),
    "label failure was not reported through the runtime boundary")
local partial = assert(C.Preview.labels.ess)
assert(not partial:IsShown(), "failed label left an empty interactive outline")
assert(partial.labelName == nil and partial.labelTextGen == nil, "failed label committed its render cache")
local placeholders = 0
for _, plan in pairs(C.plans) do
    for _, entry in ipairs(plan.entries) do
        if entry.src == "p" then placeholders = placeholders + 1 end
    end
end
assert(placeholders > 0, "failed preview did not exercise sample icons on live bars")
S.SetStyledFont = styledFont
S.CooldownManagerSetPreview(false)
Run()
for _, plan in pairs(C.plans) do
    for _, entry in ipairs(plan.entries) do
        assert(entry.src ~= "p", "closing after a label failure retained sample icons")
    end
end
assert(C.Preview.mode == nil and not partial:IsShown(), "closing after a failed label kept preview mode")
S.CooldownManagerSetPreview(true, function(slot) picked = slot end)
Run()
assert(C.Preview.labels.ess == partial and partial:IsShown() and partial.label.font and partial.label.text,
    "reopening did not recover the failed pooled label")
before = writes
C.Preview.PaintLabels()
assert(writes == before, "recovered labels repainted unchanged")
S.CooldownManagerSetPreview(false)
Widget.SetText = setText
module.active = false
module:Disable()
print("suite_cdm_usability_runtime_contract: timer popups, assisted icon rules and pooled bar labels passed")
end)() end
]=], "------------------------------------------------------------------ enable: capture")
