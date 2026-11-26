local root = assert(arg[1])
local path = root .. "/MSUF_Suite_CooldownManager/TotemPulse.lua"
local secret = assert(loadfile(root .. "/../MidnightSimpleUnitFrames-7.0/tools/tests/classpower_secrets.lua"))()
secret.Install()
local unknown = secret.New("number")
local watch = secret.Watch(path, { strict = true })
local now, have, start, duration, spell = 14.5, true, 10, 12, 17354
local reads, writes, clears, frames = 0, 0, 0, 0
local parent, shown = {}, true
local visibility = {}
local icon = { over = parent, coolAlpha = 1, IsVisible = function() return shown end }
function icon:HookScript(name, fn) visibility[name] = fn end
local clockCallback
local clock = {
    SetSize = function(_, w, h) assert(w == 12 and h == 12) end,
    SetPoint = function(_, point, owner) assert(point == "TOPRIGHT" and owner == icon) end,
    SetDrawSwipe = function(_, enabled) assert(enabled) end,
    SetSwipeColor = function() end,
    SetDrawEdge = function(_, enabled) assert(not enabled) end,
    SetDrawBling = function(_, enabled) assert(not enabled) end,
    SetHideCountdownNumbers = function(_, hidden) assert(not hidden) end,
    GetCountdownFontString = function() end,
    SetScript = function(_, name, fn) assert(name == "OnCooldownDone"); clockCallback = fn end,
    SetCooldown = function(self, cycle, length)
        assert(not secret.IsSecret(cycle) and not secret.IsSecret(length))
        self.renderedStart, self.renderedLength = cycle, length
        writes = writes + 1
    end,
    Hide = function(self) self.visible = false end,
    Show = function(self) self.visible = true end,
    Clear = function(self) clears = clears + 1; self.renderedStart = nil end,
}
function UnitClass() return "Shaman", "SHAMAN" end
function GetTime() return now end
function GetTotemInfo(slot)
    assert(slot == 3)
    reads = reads + 1
    return have, nil, start, duration, nil, nil, spell
end
local entry = { slot = "uti", id = 3, icon = icon, ov = {} }
local core = { bars = { uti = {} }, Index = { totems = { entry } }, Ranks = { Canon = function(id)
    assert(not secret.IsSecret(id))
    return id == 17354 and 16190 or id
end } }
local bindings = {
    Public = function(v) return not secret.IsSecret(v) end,
    Finite = function(v) return not secret.IsSecret(v) and type(v) == "number" and v > -math.huge and v < math.huge end,
    CreateFrame = function(kind, _, owner, template)
        assert(kind == "Cooldown" and owner == parent and template == "CooldownFrameTemplate")
        frames = frames + 1
        return clock
    end,
}
assert(loadfile(path))("pulse", { NS = { Client = { isForever = true } }, Suite = bindings, CDM = core })
local pulse = assert(core.TotemPulse)
pulse.Sync(icon, entry, have, start, duration, spell)
assert(frames == 0 and writes == 0)
entry.ov.totemPulse = true
pulse.Sync(icon, entry, have, start, duration, spell)
assert(frames == 1 and writes == 1 and clock.visible and clock.renderedStart == 13 and clock.renderedLength == 3)
pulse.Sync(icon, entry, have, start, duration, spell)
assert(writes == 1, "redundant events rebind the same clock")
now = 15.99
clockCallback(clock)
assert(reads == 1 and writes == 2 and clock.renderedStart == 16)
core.bars.uti.hidden = true
pulse.BarVisibility("uti", true)
assert(not clock.visible and clears == 1)
clockCallback(clock)
assert(reads == 1 and writes == 2, "no read or timer while the native rule hides the bar")
core.bars.uti.hidden = false
now = 19
pulse.BarVisibility("uti", false)
assert(reads == 2 and clock.renderedStart == 19)
for _, values in ipairs({ { unknown, start, duration, spell }, { true, unknown, duration, spell },
    { true, start, unknown, spell }, { true, start, duration, unknown } }) do
    pulse.Sync(icon, entry, unpack(values))
    assert(not clock.visible)
end
now, start, duration, spell = 30, 29, 300, 5394
pulse.Sync(icon, entry, have, start, duration, spell)
assert(clock.visible and clock.renderedLength == 2 and clock.renderedStart == 29)
shown = false
visibility.OnHide(icon)
assert(not clock.visible)
shown = true
visibility.OnShow(icon)
assert(clock.visible)
pulse.Release(icon)
shown = false
pulse.Sync(icon, entry, have, start, duration, spell)
assert(not clock.visible, "an empty/hidden cell must not start ticking")
shown = true
visibility.OnShow(icon)
assert(clock.visible, "the first visible tick comes up with the icon")
pulse.Release(icon)
assert(not clock.visible and clock.entry == nil)
local before = reads
clockCallback(clock)
assert(reads == before)
local violations = watch()
assert(#violations == 0, table.concat(violations, "\n"))
print("suite_cdm_totem_pulse_contract: OK")
