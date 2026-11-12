local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
assert(flavor == "Mainline" or flavor == "Forever")
-- A new cooldown icon's count FontString gets its font before any text:
-- with "Show charges and stacks" or "Show charges" off, the first style pass
-- clears the count, which the client rejects on a FontString without a font
-- ("FontString:SetText(): Font not set", 42x on a fresh build in game).
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua", [=[
do
Suite.Client.isForever = arg[2] == "Forever"
-- Native FontStrings reject text before a font is initialized.
local setText = Widget.SetText
Widget.SetText = function(self, ...)
    assert(self.kind ~= "FontString" or self.font, "FontString:SetText(): Font not set")
    return setText(self, ...)
end
local config = S.Config(ID)
module.config, module.context, module.active = config, S.NewContext(ID), true
local KEYS = Suite.CDM.KEYS
-- A returning profile: no first-run capture or defaults stamp rewrites the bars.
config.captured, config.defaultsVersion = true, Suite.CDM.DEFAULTS_VERSION
-- Both switches that hide a cooldown icon's count, one per bar family.
config[KEYS.ess.stackText], config[KEYS.uti.stackText] = false, false
config[KEYS.ext.charges] = false
module:Enable()
Run()
module:Refresh()
Run()
for _, slot in ipairs({ "ess", "uti", "ext" }) do
    assert(C.Diagnostics.IconCount(slot) > 0, slot .. " built no icons")
    assert(C.views[slot] and not C.Const.BarStacks(C.views[slot], true), slot .. " still shows counts")
end
local checked = 0
for _, entry in pairs(C.entries) do
    local icon = entry.icon
    if icon and icon.count then
        assert(icon.count.font, "a cooldown icon's count has no font")
        assert(icon.styleGen == C.views[entry.slot].styleGen, "a cooldown icon's first style pass did not finish")
        assert(icon.countOff == true and (icon.count.text or "") == "", "a hidden count shows text")
        checked = checked + 1
    end
end
assert(checked > 0, "no cooldown icon was checked")
-- The options preview styles its own new icons through the same pass.
local holder = CreateFrame("Frame", nil, UIParent)
local sample = C.Icons.CreateStandalone(holder)
C.Icons.StyleIcon(sample, C.views.ess, 36, 36)
assert(sample.count.font and sample.styleGen == C.views.ess.styleGen, "a new preview icon was not styled")
Widget.SetText = setText
module.active = false
module:Disable()
print("suite_cdm_count_font_contract: new icons with hidden counts get their font before any text passed")
end
]=], "------------------------------------------------------------------ enable: capture")
