local root = assert(arg[1], "repository root required")
-- Cooldown manager looks on the options page (package cdm11-B): every new
-- rule has its row in its topic section, the line rules grey out until a
-- glow style or the pandemic window's is Pixel or Autocast (requiresChoice
-- with its second choice, orKey), the spark follows the timer bar rules,
-- and the per-spell glow style offers the new styles. Runs on the options
-- contract's harness after its selected-bar gates.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_options_contract.lua", [=[
do (function()
local KEYS = CDM.KEYS
local function Section(id)
    for _, spec in ipairs(Page.SECTIONS) do
        if spec.id == id then return table.concat(spec.suffixes, ",") .. "," end
    end
    return ""
end
assert(Section("look"):find("swipeAlpha,swipeColor,swipeClass,", 1, true), "the swipe's color follows its opacity")
assert(Section("effects"):find("glowColor,glowLines,glowThickness,glowSpeed,", 1, true), "the lines follow the glow style")
assert(Section("effects"):find("showAura,auraSwipeColor,", 1, true), "the active buff swipe follows its switch")
assert(Section("barstyle"):find("barFill,barSpark,", 1, true), "the spark follows the bar direction")
for _, key in ipairs({ "tenthsSeconds", "urgentSeconds" }) do
    assert(Control(key).parent == ctx.sections[7], "the Text section holds " .. key)
end
assert(Control("urgentColor"), "the urgent color has its swatch")
-- The line rules need Pixel or Autocast as the glow style or (orKey) the pandemic window's.
local lines = Suite.SuiteCatalog[ID].rules[KEYS.c1.glowLines].requiresChoice
assert(lines.key == KEYS.c1.glowStyle and lines.orKey == KEYS.c1.pandemicStyle and lines.values[5] and lines.values[6]
    and not lines.values[4], "the line rules' choices")
local function Lit(suffix) return Control(suffix).enabled end
picker.set("ess")
M.RequestRefresh()
assert(not Lit("glowLines") and not Lit("glowThickness") and not Lit("glowSpeed"), "today's styles grey the line rules")
local ok, why = P.RuleEnabled(ID, Suite.SuiteCatalog[ID].rules[KEYS.c1.glowLines], Page.KeyFn, true)
assert(ok == false and why:find("Pixel", 1, true) and why:find("Autocast", 1, true), "greyed with its reason: " .. tostring(why))
Config().ess_glowStyle = 5
M.RequestRefresh()
assert(Lit("glowLines") and Lit("glowThickness") and Lit("glowSpeed"), "Pixel glows use them")
Config().ess_glowStyle, Config().ess_pandemicStyle = 1, 6
M.RequestRefresh()
assert(Lit("glowLines") and not Lit("pandemicSize"), "an Autocast pandemic window uses them, not its thickness")
Config().ess_pandemicStyle = 4
-- Buff bars have no glow style: the pandemic window's alone decides.
picker.set("bar")
M.RequestRefresh()
assert(not Lit("glowLines"), "a still pandemic border greys them")
Config().bar_pandemicStyle = 5
M.RequestRefresh()
assert(Lit("glowLines") and Lit("barSpark"), "a Pixel pandemic window on Buff bars, and their spark")
Config().bar_pandemicStyle = 4
assert(not Control("swipeColor").isEnabled() and not Lit("swipeClass"), "buff bars draw no swipe")
-- The spark belongs to timer bars: a cooldown bar's only while it shows them.
picker.set("ess")
M.RequestRefresh()
assert(not Lit("barSpark") and Lit("swipeClass"), "cooldown icons: a swipe, no spark")
assert(Control("swipeColor").isEnabled(), "the swipe color is editable")
Config().ess_swipeClass = true
M.RequestRefresh()
assert(not Control("swipeColor").isEnabled(), "the class color replaces the swipe color")
Config().ess_swipeClass, Config().ess_cooldownDuration = false, true
M.RequestRefresh()
assert(Lit("barSpark"), "timer bars show a spark")
Config().ess_cooldownDuration = false
M.RequestRefresh()
-- A spell's own glow style: Pixel and Autocast after the four styles.
local field
for _, row in ipairs(Page.FIELDS) do if row.key == "glowStyle" then field = row end end
local values = assert(field, "glow style row").values
assert(values[1][1] == 0 and values[2][2] == "Blizzard alert" and values[5][2] == "Border" and values[6][1] == 5
    and values[6][2] == "Pixel" and values[7][1] == 6 and values[7][2] == "Autocast" and #values == 7, "per-spell glow styles")
print("suite_cdm_look_options_contract: ok")
end)() end
]=], "------------------------------------------------------------------ list edits")
