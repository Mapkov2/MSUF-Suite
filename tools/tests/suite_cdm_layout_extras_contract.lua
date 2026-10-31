local root = assert(arg[1], "repository root required")
-- Cooldown manager layout extras (package cdm11-E), on the real module of the
-- main cooldown manager contract's harness: the attach list keeps its saved
-- indices and appends "Other frame" (a global frame by name, followed by its
-- rectangle with probes, never anchored; a missing or refused frame leaves the
-- bar on its own x/y and a later load outside combat finds it); "Bar width 0"
-- takes the width of the bar or frame the bar is attached to and follows it;
-- Masque skins a bar's cooldown icons in one group per bar and costs nothing
-- without it. Every new rule defaults to today's behavior.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua", [=[
do (function()
local CDM = Suite.CDM
local rules, KEYS = S.catalog[ID].rules, CDM.KEYS
local OTHER, PLAYER, TARGET = CDM.OTHER_ANCHOR, 14, 15

------------------------------------------------------------------ catalog: append-only choices, defaults
-- The saved indices of the attach list keep their meaning: Free, the twelve
-- bars in slot order, the player frame, the target frame. Other frame comes last.
local labels = CDM.ANCHOR_LABELS
assert(labels[1] == "Free" and labels[PLAYER] == "Player frame" and labels[TARGET] == "Target frame"
    and labels[OTHER] == "Other frame" and OTHER == 16 and #labels == 16, "the attach list ends with Other frame")
for i, slot in ipairs(CDM.SLOTS) do assert(labels[i + 1] == slot.title, "attach index " .. (i + 1) .. " keeps its bar") end
assert(CDM.FRAME_ANCHORS[PLAYER] == "player" and CDM.FRAME_ANCHORS[TARGET] == "target" and CDM.FRAME_ANCHORS[OTHER] == nil,
    "the unit frame targets keep their meaning")
assert(rules.def_anchor.default == PLAYER and rules.ext_anchor.default == PLAYER and rules.ess_anchor.default == 1
    and rules.uti_anchor.default == 2 and rules.c1_anchor.default == 1, "no attach default moved")
assert(rules.def_anchor.max == 16 and rules.def_anchor.choices[16] == "Other frame", "the choice range grew by one")
for _, slot in ipairs(CDM.SLOTS) do
    local k, wait = KEYS[slot.key], rules[KEYS[slot.key].anchorFrame]
    assert(wait.default == "" and wait.maxLength == 64 and wait.requiresChoice.key == k.anchor
        and wait.requiresChoice.values[OTHER] and not wait.requiresChoice.values[1] and not wait.requiresChoice.values[PLAYER],
        slot.key .. ": the frame name belongs to Other frame")
    assert(rules[k.side].requiresChoice.values[OTHER] and rules[k.gap].requiresChoice.values[OTHER],
        slot.key .. ": side and gap apply to Other frame")
    if k.barWidth then
        local rule = rules[k.barWidth]
        assert(rule.min == 0 and rule.max == 480 and rule.default == (slot.key == "bar" and 220 or 200),
            slot.key .. ": the width reaches 0 and keeps its default")
    end
    if k.masque then assert(rules[k.masque].default == false, slot.key .. ": Masque is off") end
end
assert(not KEYS.buf.masque and not KEYS.bar.masque and KEYS.ess.masque and KEYS.c1.masque,
    "Masque belongs to cooldown icons, not to the sealed aura buttons")
assert(CDM.DEFAULTS_VERSION == 3, "new rules need no defaults reset")
-- A layout kept per specialization carries the frame name with the attachment.
do
    local clean = CDM.CleanPositions({ specs = { [62] = { c1 = { anchor = OTHER, anchorFrame = "ChatFrame1", x = 3 },
        c2 = { anchorFrame = 5 }, c3 = { anchorFrame = string.rep("x", 65) } } } })
    assert(clean.specs[62].c1.anchorFrame == "ChatFrame1" and clean.specs[62].c1.anchor == OTHER, "the frame name travels")
    assert(clean.specs[62].c2 == nil and clean.specs[62].c3 == nil, "a name that is no string or too long is dropped")
end

------------------------------------------------------------------ enable
local config = S.Config(ID)
module.config = config
module.context = S.NewContext(ID)
module.active = true
module:Enable()
Run()
S.states[ID].active = true
module:Refresh()
Run()
local function Edit(values)
    for key, value in pairs(values) do config[key] = value end
    module:Refresh()
    Run()
end
local function Near(a, b) return math.abs(a - b) < 1e-6 end
local function MakeFrame(name, left, bottom, width, height)
    local frame = New("Frame", UIParent, name)
    frame.rect = { left, bottom, width, height }
    _G[name] = frame
    return frame
end
local function Probes(frame)
    local list = {}
    for i = 1, #all do
        local probe = all[i]
        if probe.scripts.OnSizeChanged and probe.point and probe.point[2] == frame then list[#list + 1] = probe end
    end
    return list
end
-- A probe event, as the client sends one when the frame moved or resized.
local function Moved(frame)
    local probe = Probes(frame)[1]
    probe.scripts.OnSizeChanged(probe, 1, 1)
    Run()
end
-- Frames that listened to ADDON_LOADED before any bar waited for a frame.
local known = {}
for i = 1, #all do
    if all[i].events.ADDON_LOADED then known[all[i]] = true end
end
local function Listener()
    for i = 1, #all do
        if all[i].events.ADDON_LOADED and not known[all[i]] then return all[i] end
    end
end
local function Point(bar) return bar.frame.point end
local function At(bar, point, rel, relPoint, x, y, label)
    local p = Point(bar)
    assert(p and p[1] == point and p[2] == rel and p[3] == relPoint and Near(p[4], x) and Near(p[5], y),
        label .. ": " .. tostring(p and p[1]) .. " " .. tostring(p and p[3]) .. " " .. tostring(p and p[4]) .. " " .. tostring(p and p[5]))
end
local views, bars = C.views, C.bars

-- Off by default: no listener, no probe for a bar, no width state, no Masque lookup.
local lookups = 0
LibStub = { GetLibrary = function(_, name) if name == "Masque" then lookups = lookups + 1 end end }
for _, slot in ipairs(CDM.SLOTS) do
    local view = views[slot.key]
    assert(view.anchorFrame == "" and view.barW == nil and view.matchW == nil and not view.masque, slot.key .. ": today's behavior")
end
assert(Listener() == nil, "nothing waits for an add-on by default")
Edit({ ess_zoom = 9 })
assert(lookups == 0, "Masque is not looked up while no bar uses it")

------------------------------------------------------------------ Other frame
Edit({ c1_on = true, c1_anchor = OTHER, c1_anchorFrame = "E_Target", c1_x = 0, c1_y = 0 })
local bar = assert(bars.c1 and bars.c1.shown and bars.c1, "custom bar 1 is shown")
-- The frame does not exist yet: the bar keeps its own x/y and waits for the add-on.
At(bar, Point(bar)[1], UIParent, "CENTER", 0, 0, "a missing frame leaves the bar free")
local listener = assert(Listener(), "a bar that waits listens for ADDON_LOADED")
-- Another add-on's load that does not bring the frame costs one name check.
listener.scripts.OnEvent(listener, "ADDON_LOADED", "Other")
Run()
At(bar, Point(bar)[1], UIParent, "CENTER", 0, 0, "still free until the frame exists")
assert(Listener() == listener, "and it keeps waiting")
local target = MakeFrame("E_Target", 300, 200, 100, 50)
-- Combat holds the retry back; the combat end finds the frame.
combat = true
Fire("PLAYER_REGEN_DISABLED")
listener.scripts.OnEvent(listener, "ADDON_LOADED", "E_Target")
Run()
At(bar, Point(bar)[1], UIParent, "CENTER", 0, 0, "no retry in combat")
combat = false
Fire("PLAYER_REGEN_ENABLED")
Run()
At(bar, "TOP", UIParent, "BOTTOMLEFT", 350, 196, "below the frame, centered, gap 4")
assert(Listener() == nil and #Probes(target) == 2, "found: the listener goes, the frame gets its two probes")
-- A move and a resize reach the bar through the probes alone.
target.rect = { 400, 200, 100, 50 }
Moved(target)
At(bar, "TOP", UIParent, "BOTTOMLEFT", 450, 196, "the bar follows a move")
assert(bar.frame.point[2] ~= target, "the bar is never anchored to the frame itself")
-- The same through a load outside combat, with the listener doing the retry.
Edit({ c1_anchorFrame = "E_Late" })
At(bar, Point(bar)[1], UIParent, "CENTER", 0, 0, "a new missing frame frees the bar again")
listener = assert(Listener(), "and it waits again")
MakeFrame("E_Late", 100, 100, 40, 40)
listener.scripts.OnEvent(listener, "ADDON_LOADED", "E_Late")
Run()
At(bar, "TOP", UIParent, "BOTTOMLEFT", 120, 96, "ADDON_LOADED finds it outside combat")
assert(Listener() == nil, "nothing waits any more")
-- Frames the bar must not follow: itself, a child of it, a frame hanging from it.
_G.E_Self = bar.frame
Edit({ c1_anchorFrame = "E_Self" })
At(bar, Point(bar)[1], UIParent, "CENTER", 0, 0, "the bar's own frame is refused")
_G.E_Child = New("Frame", bar.frame)
Edit({ c1_anchorFrame = "E_Child" })
At(bar, Point(bar)[1], UIParent, "CENTER", 0, 0, "a child of the bar is refused")
local hanging = MakeFrame("E_Hang", 10, 10, 20, 20)
hanging.points = 1
hanging.GetPoint = function() return "TOP", bar.frame, "BOTTOM", 0, 0 end
Edit({ c1_anchorFrame = "E_Hang" })
At(bar, Point(bar)[1], UIParent, "CENTER", 0, 0, "a frame that hangs from the bar is refused")
assert(Listener() == nil, "a refused frame is not waited for")
_G.E_Number, _G.E_Table = 5, {}
for _, name in ipairs({ "E_Number", "E_Table", "", "no such frame" }) do
    Edit({ c1_anchorFrame = name })
    At(bar, Point(bar)[1], UIParent, "CENTER", 0, 0, "'" .. name .. "' is no frame")
end
-- A forbidden frame is never read.
local forbidden = MakeFrame("E_Forbidden", 10, 10, 20, 20)
forbidden.IsForbidden = function() return true end
Edit({ c1_anchorFrame = "E_Forbidden" })
At(bar, Point(bar)[1], UIParent, "CENTER", 0, 0, "a forbidden frame is refused")
assert(#Probes(forbidden) == 0, "and never probed")

------------------------------------------------------------------ Bar width 0
-- Attached to a bar: the width of that bar, and it follows when that bar changes.
assert(views.bar.barW == nil and views.bar.barWidth == 220, "Buff bars keep their width")
local parentWidth = bars.buf.frame.w
Edit({ bar_barWidth = 0 })
assert(views.bar.barWidth == 0 and views.bar.barW and Near(views.bar.barW, parentWidth) and Near(bars.bar.frame.w, parentWidth),
    "Buff bars take the width of the bar they are attached to")
Edit({ buf_size = 50 })
assert(bars.buf.frame.w ~= parentWidth and Near(bars.bar.frame.w, bars.buf.frame.w) and Near(views.bar.barW, bars.buf.frame.w),
    "and follow it when the parent resizes")
-- A relayout of the parent alone (no setting) reaches the bar too.
views.buf.size = 60
C.Layout.Apply("buf")
Run()
assert(Near(bars.bar.frame.w, bars.buf.frame.w), "a parent relayout moves the width of the bars that match it")
views.buf.size = 50
C.Layout.Apply("buf")
Run()
local gen = views.bar.styleGen
Edit({ bar_barWidth = 220 })
assert(views.bar.barW == nil and views.bar.matchW == nil and bars.bar.frame.w == 220 and views.bar.styleGen > gen,
    "any width above 0 is the width again")
Edit({ buf_size = rules.buf_size.default })
-- Attached to a frame: a timer bar takes the frame's width and follows its resizes.
local player = MakeFrame("MSUF_player", 80, 160, 200, 40)
Edit({ c1_kind = 3, c1_anchor = PLAYER, c1_anchorFrame = "", c1_barWidth = 0 })
assert(views.c1.barW == 200 and Near(bars.c1.frame.w, 200), "a timer bar takes the width of MSUF's frame")
gen = views.c1.styleGen
player.rect = { 80, 160, 260, 40 }
Moved(player)
assert(views.c1.barW == 260 and Near(bars.c1.frame.w, 260) and views.c1.styleGen > gen, "and follows its resize, restyled")
Edit({ c1_anchor = 1 })
assert(views.c1.barW == 200 and Near(bars.c1.frame.w, 200), "attached to nothing, the usual width stands")
Edit({ c1_anchor = OTHER, c1_anchorFrame = "E_Target" })
assert(Near(views.c1.barW, 100), "Other frame supplies the width too")
target.rect = { 400, 200, 140, 50 }
Moved(target)
assert(Near(bars.c1.frame.w, 140), "and follows its resize")
-- Cooldowns displayed as timer bars match too; an icon bar ignores the 0.
Edit({ c1_anchor = PLAYER, c1_kind = 1, c1_cooldownDuration = true })
assert(views.c1.barW == 260 and Near(bars.c1.frame.w, 260), "a cooldown timer bar matches")
Edit({ c1_cooldownDuration = false })
assert(bars.c1.frame.w > 0, "an icon bar keeps the 0 without using it")
Edit({ c1_barWidth = 200, c1_kind = 1, c1_anchor = 1, c1_on = false })

------------------------------------------------------------------ Masque
-- Without Masque a bar that asks for it stays plain.
local groups = {}
local function Group(_, addon, name, id)
    local group = { addon = addon, name = name, id = id, buttons = {}, reskins = 0 }
    function group:AddButton(button, regions, kind, strict) self.buttons[button] = { regions = regions, kind = kind, strict = strict } end
    function group:RemoveButton(button) self.buttons[button] = nil end
    function group:ReSkin() self.reskins = self.reskins + 1 end
    function group:Delete() self.deleted = true end
    groups[#groups + 1] = group
    return group
end
LibStub = nil
Edit({ ess_masque = true })
assert(#groups == 0, "no Masque, no group")
for _, entry in pairs(C.entries) do assert(not entry.icon or not entry.icon.masqued, "no icon is taken over without Masque") end
lookups = 0
LibStub = { GetLibrary = function(_, name)
    if name == "Masque" then lookups = lookups + 1; return { Group = Group } end
end }
Edit({ ess_masque = false })
assert(lookups == 0 and #groups == 0, "switched off costs no lookup")
-- One group per bar, holding the bar's cooldown icons.
local essIcons = C.Diagnostics.IconCount("ess")
assert(essIcons > 0)
local function IconsOf(slot)
    local list = {}
    for _, entry in pairs(C.entries) do
        if entry.slot == slot and entry.icon then list[#list + 1] = entry.icon end
    end
    return list
end
local ess = IconsOf("ess")
Edit({ ess_masque = true })
assert(#groups == 1 and groups[1].addon == "MSUF Suite" and groups[1].name == views.ess.title and groups[1].id == "ess",
    "one Masque group for the bar")
local group = groups[1]
for _, icon in ipairs(ess) do
    local held = group.buttons[icon]
    assert(icon.masqued and held and held.regions.Icon == icon.tex and held.regions.Cooldown == icon.cd and held.strict == true
        and held.kind == "Item", "every Essential icon is in the group with its art and its swipe")
end
assert(group.reskins >= 1, "the group is skinned once the icons are in")
Edit({ uti_masque = true })
assert(#groups == 2 and groups[2].id == "uti" and groups[2].buttons[ess[1]] == nil, "another bar has its own group")
Edit({ uti_masque = false })
-- Masque places the art: the style pass leaves it alone, and keeps the border off.
local before = ess[1].tex.calls.SetTexCoord or 0
Edit({ ess_zoom = 13 })
assert((ess[1].tex.calls.SetTexCoord or 0) == before and ess[1].border == 0, "a taken-over icon's art is Masque's")
local plain = IconsOf("uti")
local plainBefore = plain[1].tex.calls.SetTexCoord or 0
Edit({ uti_zoom = 13 })
assert((plain[1].tex.calls.SetTexCoord or 0) > plainBefore, "a plain bar's icons are still styled")
-- Icons come and go with the bar's list.
local plan = C.plans.ess
local last = table.remove(plan.entries)
local icon = last.icon
C.Icons.Sync("ess")
assert(not icon.masqued and group.buttons[icon] == nil, "an icon that leaves the bar leaves the group")
plan.entries[#plan.entries + 1] = last
C.Icons.Sync("ess")
assert(last.icon and last.icon.masqued and group.buttons[last.icon], "an icon that joins the bar joins the group")
-- Only cooldown icons qualify: timer bars and buff bars are not skinned.
local Active = C.Masque.Active
assert(Active({ masque = true, kind = 1 }) and not Active({ masque = true, kind = 1, cooldownDuration = true })
    and not Active({ masque = true, kind = 2 }) and not Active({ masque = true, kind = 3 }) and not Active({ masque = false, kind = 1 }),
    "Masque skins cooldown icons only")
-- Switched off, the icons are restyled and the group goes.
Edit({ ess_masque = false })
assert(group.deleted and next(group.buttons) == nil, "off: no icon stays in the group")
for _, held in ipairs(IconsOf("ess")) do assert(not held.masqued, "off: the icons are the bar's own again") end
assert((ess[1].tex.calls.SetTexCoord or 0) > before, "off: the art is placed again")
NoOnUpdate()
Edit({ c1_on = false })
module.active = false
module:Disable()
module.context:Release()
Run(5)
print("suite_cdm_layout_extras_contract: ok")
end)() end
]=], "------------------------------------------------------------------ enable: capture")
