local root = assert(arg[1])
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local c, NS = Support.CatalogDefaults(root, "actionbars", "ActionBars")
local E = NS.ActionBarEnum
local V = E.VISIBILITY
local function ResetConditions()
    for _, suffix in ipairs({ "Combat", "Mounted", "Target", "Focus", "Flying", "Group", "Casting", "Instance", "Skyriding", "Housing" }) do
        c["bar1Cond" .. suffix] = 1
    end
    c.bar1CondMouseover, c.bar1CondCombine, c.bar1Visibility = false, E.COMBINE.ANY, V.CUSTOM
end
ResetConditions()
c.bar1CondTarget, c.bar1CondFocus, c.bar1CondCombine = 4, 2, E.COMBINE.ALL
assert(NS.ActionBarConditionBody(c, 1) == "[@target,noharm] hide; [@focus,noexists] hide; show", "unit selectors leaked")
c.bar1UseGlobalVisibility, c.globalVisibility = true, V.COMBAT
assert(NS.ActionBarVisibilityMode(c, 1) == V.COMBAT, "global inheritance")
c.globalVisibility = V.OUT_OF_COMBAT
assert(NS.ActionBarVisibilityMode(c, 1) == V.OUT_OF_COMBAT, "global change did not propagate")
local detached = NS.ActionBarLocalVisibility(c, 1)
assert(detached.bar1Visibility == V.OUT_OF_COMBAT and detached.bar1UseGlobalVisibility == false,
    "direct bar edit did not begin with inherited values")
assert(c.bar1UseGlobalVisibility and c.globalVisibility == V.OUT_OF_COMBAT, "preparing a direct edit mutated saved rules")
c.bar1Visibility = V.NEVER
assert(NS.ActionBarVisibilityMode(c, 1) == V.NEVER, "global rules reenabled an off bar")
c.bar1UseGlobalVisibility = false
ResetConditions()
c.bar1CondCasting, c.bar1CondInstance = 2, 4
assert(NS.ActionBarConditionBody(c, 1) == "context", "external conditions entered a protected driver")
local state = { casting = false, instanceType = "party", inInstance = true }
assert(NS.ActionBarContextPasses(c, 1, state), "Any did not accept dungeon")
c.bar1CondCombine = E.COMBINE.ALL
assert(not NS.ActionBarContextPasses(c, 1, state), "All accepted a false cast condition")
state.casting = true
assert(NS.ActionBarContextPasses(c, 1, state), "All rejected both conditions")
c.bar1CondCasting, c.bar1CondInstance = 3, 9
state.casting, state.instanceType, state.inInstance = false, "none", false
assert(NS.ActionBarContextPasses(c, 1, state), "inverse contexts")

-- Real alpha owner and optional event subscriptions, with counted native calls.
ResetConditions()
local native, writes, events = 0, 0, {}
local casting, channeling, secret = false, false, {}
UnitCastingInfo = function()
    native = native + 1
    if casting then return rawequal(casting, secret) and secret or "Cast", nil, nil, nil, nil, false end
end
UnitChannelInfo = function()
    native = native + 1
    if channeling then return secret, nil, nil, nil, nil, false end
end
NS.IsCombatLocked = function() return false end
local S = { Public = function(value) return not rawequal(value, secret) end, editMode = false,
    Dispatch = function(fn, ...) return fn(...) end }
local AB = { ENUM = E, BAR_COUNT = NS.ActionBarCount, bars = {}, KEYS = {},
    Painter = { PaintBar = function() end }, M = { active = true, config = c,
        context = { Event = function(_, name, fn) events[name] = fn end,
            RemoveEvent = function(_, name) events[name] = nil end } } }
for i = 1, NS.ActionBarCount do
    local keys = {}
    for key in pairs(NS.SuiteCatalog.actionbars.rules) do
        local suffix = key:match("^bar" .. i .. "(.+)$")
        if suffix then keys[suffix] = key end
    end
    AB.KEYS[i] = keys
end
local attrs = { ["state-vis"] = "context" }
local header = { GetAttribute = function(_, name) return attrs[name] end,
    SetAlpha = function(_, value) writes = writes + 1 end }
local bar = { index = 1, key = AB.KEYS[1], header = header, buttons = {} }
AB.bars[1] = bar
assert(loadfile(root .. "/MSUF_Suite_ActionBars/Visibility.lua"))("MSUF_Suite_ActionBars", { NS = NS, Suite = S, ActionBars = AB })
AB.SyncVisibilityContexts()
assert(native == 0 and next(events) == nil, "disabled context rules performed work")
c.bar1CondCasting = 2
AB.SyncVisibilityContexts()
assert(native == 2 and events.UNIT_SPELLCAST_START, "cast subscriptions missing")
AB.UpdateAlpha(bar)
assert(bar.alpha == .01 and bar.paintDormant, "false cast condition stayed painted")
casting = true
events.UNIT_SPELLCAST_START(nil, "UNIT_SPELLCAST_START", "player")
assert(bar.alpha == 1 and not bar.paintDormant, "cast start did not reveal")
casting = false
events.UNIT_SPELLCAST_STOP(nil, "UNIT_SPELLCAST_STOP", "player")
assert(bar.alpha == .01 and bar.paintDormant, "cast stop did not suspend paint")
local before = writes
events.UNIT_SPELLCAST_STOP(nil, "UNIT_SPELLCAST_STOP", "player")
assert(writes == before, "unchanged condition rewrote alpha")
casting = secret
events.UNIT_SPELLCAST_START(nil, "UNIT_SPELLCAST_START", "player")
assert(bar.alpha == 1, "secret cast name defeated the public event edge")
events.UNIT_SPELLCAST_FAILED(nil, "UNIT_SPELLCAST_FAILED", "player")
assert(bar.alpha == 1, "a failed second spell hid an active cast with a secret name")
casting, channeling = false, true
events.UNIT_SPELLCAST_CHANNEL_START(nil, "UNIT_SPELLCAST_CHANNEL_START", "player")
events.UNIT_SPELLCAST_FAILED(nil, "UNIT_SPELLCAST_FAILED", "player")
assert(bar.alpha == 1, "a failed second spell hid an active channel with a secret name")
channeling = false
events.UNIT_SPELLCAST_CHANNEL_STOP(nil, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
assert(bar.paintDormant, "public cast-presence flag did not clear")
AB.StopVisibilityContexts()
assert(next(events) == nil, "context listeners leaked on stop")
ResetConditions()
c.bar1CondInstance = 4
local inInstance, kind = false, "none"
IsInInstance = function() return inInstance, kind end
AB.SyncVisibilityContexts()
AB.UpdateAlpha(bar)
assert(bar.paintDormant and events.ZONE_CHANGED_NEW_AREA, "instance context did not subscribe or fade")
inInstance, kind = true, "party"
events.ZONE_CHANGED_NEW_AREA()
assert(not bar.paintDormant, "entering dungeon did not reveal")
AB.StopVisibilityContexts()
local forever, foreverNS = Support.CatalogDefaults(root, "actionbars", "ActionBars", { isForever = true })
assert(foreverNS.SuiteCatalog.actionbars.rules.bar1CondHousing.hidden
    and foreverNS.SuiteCatalog.actionbars.rules.bar1CondSkyriding.hidden, "unsupported Forever rules exposed")
forever.bar1CondCasting = 2
assert(foreverNS.ActionBarHasContext(forever, 1), "Forever cast contexts unavailable")

-- Mode selection leaves the ordinary tint as the direct default painter.
S.USABLE = { USABLE = 1, NO_POWER = 2, UNUSABLE = 3, OUT_OF_RANGE = 4 }
AB.styleGen = 1
AB.style = { kr = 1, kg = 1, kb = 1, rr = 1, rg = 0, rb = 0, tints = { [1] = { 1, 1, 1 } } }
AB.Painter.SetTint = function(fn) AB.Painter.Tint = fn end
assert(loadfile(root .. "/MSUF_Suite_ActionBars/RangeText.lua"))("MSUF_Suite_ActionBars", { NS = NS, Suite = S, ActionBars = AB })
AB.ConfigureRangeTint()
assert(AB.Painter.Tint == AB.TintIcon, "default mode added a dispatch wrapper")
local icon, text, textWrites = {}, {}, 0
function icon:SetVertexColor(r, g, b) self.r, self.g, self.b = r, g, b end
function text:SetTextColor(r, g, b) self.r, self.g, self.b = r, g, b; textWrites = textWrites + 1 end
local rec = { button = { icon = icon }, keyText = text, outOfRange = true }
AB.style.rangeKey, AB.style.rangeIcon = true, false
AB.ConfigureRangeTint()
AB.Painter.Tint(rec)
assert(icon.g == 1 and text.g == 0 and rec.outOfRange, "key-only range mode changed icon or lost range state")
local count = textWrites
AB.Painter.Tint(rec)
assert(textWrites == count, "unchanged text color rewrote the native font string")
rec.outOfRange = nil
AB.Painter.Tint(rec)
assert(text.g == 1, "range warning did not clear")
AB.style.rangeIcon, rec.outOfRange, rec.tint = true, true, nil
AB.Painter.Tint(rec)
assert(icon.g == 0 and text.g == 0, "combined range mode")

-- Four font overrides resolve once per style change, never per button.
S.catalog, S.USABLE_TINT = NS.SuiteCatalog, { [1] = { 1, 1, 1 }, [2] = { .5, .5, 1 }, [3] = { .4, .4, .4 } }
local resolves = 0
S.ResolveFont = function(key) resolves = resolves + 1; return key ~= "" and key .. ".ttf" or nil end
S.ClassRGB = function() return 1, 1, 1 end
S.RGB = function() return 1, 1, 1 end
UnitClass = function() return "Warrior", "WARRIOR" end
NS.HostBridge = { IconSkinLook = function() end }
AB.ResolveShape = function(style) style.shape = "RECTANGLE" end
assert(loadfile(root .. "/MSUF_Suite_ActionBars/Style.lua"))("MSUF_Suite_ActionBars", { NS = NS, Suite = S, ActionBars = AB })
c.font, c.fontOutline = "Base", 2
AB.BuildStyle()
assert(resolves == 1 and AB.style.texts.keybind.font == "Base.ttf", "default fonts resolved extra paths")
c.keybindFontOverride, c.keybindFont, c.keybindFontOutline = true, "Keys", 3
c.cooldownFontOverride, c.cooldownFont, c.cooldownFontOutline = true, "Time", 1
AB.BuildStyle()
assert(AB.style.texts.keybind.font == "Keys.ttf" and AB.style.texts.keybind.flags == "", "key font override")
assert(AB.style.texts.cooldown.font == "Time.ttf" and AB.style.texts.cooldown.flags == "OUTLINE", "cooldown font override")
assert(AB.style.texts.macro.font == "Base.ttf" and AB.style.texts.macro.flags == "THICKOUTLINE", "other text types changed")
c.keybindFontOverride = false
AB.BuildStyle()
assert(AB.style.texts.keybind.font == "Base.ttf" and AB.style.texts.keybind.flags == "THICKOUTLINE", "font inheritance did not restore")
print("Action bars: global/context rules, isolated unit selectors, optional cast lifecycle and text range modes passed")
