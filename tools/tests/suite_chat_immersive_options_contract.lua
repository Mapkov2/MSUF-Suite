-- Build the real Chat page: the new preset's button, preview and gates must
-- follow stored settings through a click, refresh and a return to a flat look.
local root = assert(arg[1])
SUITE_OPTIONS_FIXTURE = true
local F = dofile(root .. "/tools/tests/suite_options_menu_contract.lua")
local P, S = F.optionsNS, F.S
local create, textures = CreateFrame, {}
CreateFrame = function(...)
    local frame = create(...)
    local texture = frame.CreateTexture
    function frame:CreateTexture(...)
        local part = texture(self, ...)
        function part:SetGradient(direction, left, right)
            self.gradient = { direction, left, right }
        end
        textures[#textures + 1] = part
        return part
    end
    return frame
end
assert(P.Set("chat", "look", 2))
local ctx = { key = "suite_chat", width = 720, refreshers = {}, widgets = {}, sections = {}, pageItems = {} }
F.SetCurrent(ctx)
F.M.pages.suite_chat.build(ctx)
if ctx.fixedPreview.record.onActivate then ctx.fixedPreview.record.onActivate() end
local function Refresh() for _, fn in ipairs(ctx.refreshers) do fn() end end
Refresh()
local button = assert(F.registeredControls["menu2.suite_chat.chat.look.7"], "Immersive has no exact button target")
assert(button.registeredMeta.sectionId == "suite_chat_look", "Immersive points to another accordion")
button.scripts.OnClick(button)
Refresh()
local config = S.Config("chat")
assert(config.look == 7 and config.panelGradient and config.messageFading and config.coloredUnreadTabs,
    "clicking Immersive did not apply its complete preset")
assert(not P.Gates.chat(P.catalog.chat.rules.panelTexture), "gradient ignored an enabled texture selector")
local gradients = {}
for _, texture in ipairs(textures) do
    if rawget(texture, "gradient") then gradients[#gradients + 1] = texture end
end
assert(#gradients == 2 and gradients[1]:IsShown() and gradients[2]:IsShown(), "preview did not show two gradient halves")
assert(gradients[1].gradient[2][4] == config.panelAlpha / 100 and gradients[2].gradient[3][4] == 0,
    "minimal preview did not fade its left background to the right")
assert(gradients[1]:GetWidth() == 50, "minimal preview lost its short left margin")
assert(math.abs(gradients[1].gradient[3][4] - config.panelAlpha / 100) < 1e-9,
    "preview alpha differs from its stored setting")
local count = #textures
Refresh()
assert(#textures == count, "refresh allocated another preview texture")
assert(P.Set("chat", "look", 2))
Refresh()
assert(not config.panelGradient and not config.minimalChrome and not config.messageFading and config.idleSeconds == 0,
    "returning to a normal look kept Immersive behavior")
assert(not gradients[1]:IsShown() and not gradients[2]:IsShown(), "flat look retained its preview gradient")
assert(P.Gates.chat(P.catalog.chat.rules.panelTexture), "flat look did not restore the texture selector")
local combat = InCombatLockdown
InCombatLockdown = function() return true end
button.scripts.OnClick(button)
assert(config.look == 2, "preset button wrote settings in combat")
InCombatLockdown, CreateFrame = combat, create
print("Immersive real page click, exact target, preview refresh, preset exit and combat refusal passed")
