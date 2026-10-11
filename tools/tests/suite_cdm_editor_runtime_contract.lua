local root = assert(arg[1])
local originalLoad, runtime = loadfile
loadfile = function(path)
    local chunk = assert(originalLoad(path))
    return function(addon, namespace)
        if path:find("MSUF_Suite_CooldownManager/Bootstrap.lua", 1, true) then runtime = namespace end
        return chunk(addon, namespace)
    end
end
assert(originalLoad(root .. "/tools/tests/suite_cooldown_manager_contract.lua"))()
loadfile = originalLoad
local C, NS, S = runtime.CDM, runtime.NS, runtime.Suite
local CDM = NS.CDM
local config = S.Config("cooldownManager")
config.listsData = assert(CDM.Codec.EncodeLists({ specs={ [266]={ess={"s133","s1459"},bar={"a1459"}} },
    replace={ [266]={ess=true,bar=true} } }))
config.spellsData = assert(CDM.Codec.EncodeSpells({ e={s133={icon=101}},s={ [266]={s133={icon=12345}} } }))
C.Cold()
local player, liveLists, liveSpells, plans = C.state.specID, C.lists, C.spells, C.plans
local context = S.CooldownManagerEditorContext(266,9)
assert(context.spec == 266 and context.bars.ess[1].key == "s133" and context.bars.ess[2].key == "s1459",
    "foreign runtime view lost exact saved order")
assert(context.bars.bar[1].key == "a1459" and context.bars.bar[1].family == 2,
    "foreign aura list changed family")
assert(context.choices.s133.icon == 12345, "foreign preview inherited the player's overrides")
local stage = CreateFrame("Frame")
local canvas = assert(S.CooldownManagerRenderPreview(stage,"ess",600,200,context))
assert(canvas.keys[1] == "s133" and canvas.textures[1] == 12345 and canvas.fakes[1].ov.icon == 12345,
    "foreign canvas is a readonly class example or paints the wrong override")
assert(C.state.specID == player and C.lists == liveLists and C.spells == liveSpells and C.plans == plans,
    "foreign preview mutated live CDM state")
local warm = S.CooldownManagerEditorContext(266,9)
assert(warm == context and warm.bars.ess == context.bars.ess, "unchanged foreign context allocated new rows")
S.CooldownManagerRenderPreview(stage,"ess",600,200)
canvas = assert(S.CooldownManagerRenderPreview(stage,"ess",600,200,context))
assert(canvas.keys[1] == "s133" and canvas.textures[1] == 12345 and canvas.count == 2,
    "returning to the same foreign spec retained the player's cached content")
config.spellsData = assert(CDM.Codec.EncodeSpells({ s={ [266]={s133={icon=54321}} } }))
local updated = S.CooldownManagerEditorContext(266,9)
assert(updated ~= context and updated.choices.s133.icon == 54321, "foreign override cache stayed stale")
assert(S.CooldownManagerRenderPreview(stage,"ess",600,200,updated).textures[1] == 54321,
    "foreign canvas ignored a saved override edit")
local color = S.ClassRGB
S.ClassRGB = function(token) assert(token == "WARLOCK"); return .4, .2, .8 end
config[CDM.KEYS.ess.borderClass] = true
C.Cold()
local colored = S.CooldownManagerEditorContext(266, 9, "WARLOCK")
canvas = S.CooldownManagerRenderPreview(stage, "ess", 600, 200, colored)
local view = canvas.icons[1].styleView
assert(view ~= C.views.ess and not view.borderClass and view.borderR == .4 and view.borderG == .2 and view.borderB == .8
    and C.views.ess.borderClass, "foreign class coloring used or mutated the player's live view")
assert(S.CooldownManagerRenderPreview(stage, "ess", 600, 200, colored).icons[1].styleView == view,
    "warm foreign class paint allocated another view")
local styles, style = 0, C.Icons.StyleIcon
C.Icons.StyleIcon = function(...) styles = styles + 1; return style(...) end
S.ClassRGB = function() return .8, .2, .4 end
S.CooldownManagerRenderPreview(stage, "ess", 600, 200, colored)
assert(styles == canvas.count and view.borderR == .8, "changed class palette did not restyle the foreign preview")
C.Icons.StyleIcon, S.ClassRGB = style, color
S.CooldownManagerReleasePreview(stage)
print("CDM foreign runtime preview: saved order, aura family, selected overrides, isolation and warm cache passed")
