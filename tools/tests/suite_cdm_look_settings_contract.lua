local root = assert(arg[1], "repository root required")
-- Cooldown manager looks through the settings read (package cdm11-B): the
-- new rules default to today's look, each one marks the work it needs (the
-- aura buttons' look count, view.relook, for what their style pass reads
-- from the view), colors are decoded once, and the Text section's tenths and
-- urgent stage reach the countdown formatter's state and drop the cached
-- duration text options. Runs on the main cooldown manager contract's
-- harness up to its first activation.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua", [=[
do (function()
local CDM = Suite.CDM
local rules = S.catalog[ID].rules
local config = S.Config(ID)
module.config = config
module.context = S.NewContext(ID)
module.active = true
module:Enable()
Run()
local K, state = C.Const, C.state
-- Today's look: every new rule's default, the existing ones untouched.
for _, slot in ipairs(CDM.SLOTS) do
    local keys = CDM.KEYS[slot.key]
    assert(rules[keys.glowLines].default == 8 and rules[keys.glowThickness].default == 2 and rules[keys.glowSpeed].default == 100,
        slot.key .. ": line defaults")
    assert(rules[keys.pandemicStyle].default == 4, slot.key .. ": the pandemic window keeps its still border")
    if keys.barSpark then assert(rules[keys.barSpark].default == false, slot.key .. ": no spark") end
    if keys.swipeColor then
        assert(rules[keys.swipeColor].default == "000000" and rules[keys.swipeClass].default == false, slot.key .. ": black swipe")
    end
    if keys.glowStyle then assert(rules[keys.glowStyle].default == 1, slot.key .. ": the alert stays the glow") end
    if keys.auraSwipeColor then assert(rules[keys.auraSwipeColor].default == CDM.AURA_SWIPE, slot.key .. ": gold active buff swipe") end
end
assert(CDM.AURA_SWIPE == "ffd100", "the active buff swipe's gold")
assert(rules.tenthsSeconds.default == 0 and rules.urgentSeconds.default == 0 and rules.urgentColor.default == "ff2020",
    "the countdown's new stages are off")
assert(CDM.DEFAULTS_VERSION == 3, "new rules need no defaults reset")
assert(CDM.SPELL_FIELDS.glowStyle(5) and CDM.SPELL_FIELDS.glowStyle(6) and not CDM.SPELL_FIELDS.glowStyle(7)
    and CDM.SPELL_FIELDS.glowStyle(0), "a spell may choose Pixel and Autocast")
local view = C.views.ess
assert(view.swipeR == 0 and view.swipeG == 0 and view.swipeB == 0 and view.barSpark == false, "the view reads today's look")
assert(state.tenths == 0 and state.urgent == 0 and not state.cdExtra, "no countdown stage")
-- The work each new rule marks.
local WORK = C.Diagnostics.SettingWork
for suffix, flags in pairs({ swipeColor = { "style", "relook" }, swipeClass = { "style", "relook" },
    auraSwipeColor = { "restyle", "relook" }, barSpark = { "bar", "style", "behavior", "relook" },
    glowLines = { "behavior", "restyle", "relook" }, glowThickness = { "behavior", "restyle", "relook" },
    glowSpeed = { "behavior", "restyle", "relook" } }) do
    local work = assert(WORK[suffix], suffix .. " has no work")
    for _, flag in ipairs(flags) do assert(work[flag], suffix .. " misses " .. flag) end
    assert(not work.layout and not work.resolve, suffix .. " never relayouts or resolves")
end
-- A swipe color: decoded once, the bar restyles and its aura look count moves.
local relook = view.relook or 0
C.Flush.Reset()
config[CDM.KEYS.ess.swipeColor] = "336699"
C.Settings.ReadViews(config, false, false)
assert(math.abs(view.swipeR - .2) < 1e-9 and math.abs(view.swipeB - .6) < 1e-9 and view.relook == relook + 1
    and C.Flush.style.ess, "a swipe color restyles the bar")
C.Flush.Reset()
C.Settings.ReadViews(config, false, false)
assert(view.relook == relook + 1 and not C.Flush.style.ess, "an unchanged read moves nothing")
config[CDM.KEYS.ess.auraSwipeColor] = "3366ff"
C.Settings.ReadViews(config, false, false)
assert(view.auraSwipeB == 1 and view.relook == relook + 2 and C.Flush.style.ess, "the active buff swipe restyles the overlays")
assert(K.AuraSwipeRGB(view) == .2, "the bar's active buff swipe color")
config[CDM.KEYS.ess.auraSwipeColor] = CDM.AURA_SWIPE
C.Settings.ReadViews(config, false, false)
assert(K.AuraSwipeRGB(view) == 1 and select(2, K.AuraSwipeRGB(view)) == .82, "the default keeps the exact gold")
config[CDM.KEYS.ess.swipeColor] = "000000"
C.Flush.Reset()
config[CDM.KEYS.buf.glowLines] = 12
C.Settings.ReadViews(config, false, false)
assert(C.views.buf.glowLines == 12 and C.Flush.style.buf and C.Flush.behavior.buf, "the lines restyle in place")
config[CDM.KEYS.buf.glowLines] = 8
C.Settings.ReadViews(config, false, false)
-- The Text section's stages: state, a text restyle and fresh duration text options.
local plain = C.AuraButtons.TextOpts(0)
local textGen = state.textGen
config.tenthsSeconds, config.urgentSeconds, config.urgentColor = 3, 2, "ff0000"
C.Settings.ReadGlobals(config, false)
assert(state.tenths == 3 and state.urgent == 2 and state.cdExtra == true and state.urR == 1 and state.urG == 0
    and state.textGen == textGen + 1, "the stages reach the state and restyle the text")
local staged = C.AuraButtons.TextOpts(0)
assert(staged ~= plain, "the settings read drops the cached duration text options")
assert(K.Countdown(0) and K.Countdown(0) == K.CountdownFormatter(0, state.thR, state.thG, state.thB, 3, 2, 1, 0, 0),
    "the icons' formatter carries both stages")
config.tenthsSeconds, config.urgentSeconds, config.urgentColor = 0, 0, "ff2020"
C.Settings.ReadGlobals(config, false)
assert(not state.cdExtra and K.Countdown(0) == nil and C.AuraButtons.TextOpts(0) == plain, "back to today's countdown")
C.Flush.Reset()
module.active = false; module:Disable(); module.context:Release(); Run(5)
print("suite_cdm_look_settings_contract: ok")
end)() end
]=], "------------------------------------------------------------------ enable: capture")
