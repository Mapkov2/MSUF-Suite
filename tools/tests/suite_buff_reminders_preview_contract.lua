-- Real compiler, painter and controller; record C sinks only after the
-- existing runtime budget tests have finished, so their budgets stay intact.
local root = assert(arg[1])
local originalLoad, private = loadfile
local mutations = {
    buffer = { "Entries.lua", "building = previewBuffer or", "building = nil or" },
    effects = { "Preview.lua", "R.AlertTransition(state, button, entry, entry ~= nil)", "-- missing runtime effects" },
    count = { "Preview.lua", "R.StyleCount(button, config)", "-- missing runtime typography" },
    geometry = { "Preview.lua", "button:SetSize(config.size, config.size)", "button:SetSize(38, 38)" },
    cached = { "Preview.lua", "if dirty or changed or not state.list.entries then", "if true then" },
}
loadfile = function(path)
    local chunk = assert(originalLoad(path))
    local mutation = mutations[arg[2]]
    if mutation and path:find("MSUF_Suite_BuffReminders/" .. mutation[1], 1, true) then
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local first, last = assert(source:find(mutation[2], 1, true))
        chunk = assert(loadstring(source:sub(1, first - 1) .. mutation[3] .. source:sub(last + 1), "@" .. path))
    end
    return function(addon, namespace)
        if path:find("MSUF_Suite_BuffReminders/Preview.lua", 1, true) then private = namespace end
        return chunk(addon, namespace)
    end
end
assert(originalLoad(root .. "/tools/tests/suite_buff_reminders_contract.lua"))()
loadfile = originalLoad
local NS, S, R = private.NS, private.Suite, private.BuffReminders
NS.Client.isForever = arg[2] == "Forever"
NS.Client.modernEquipment = not NS.Client.isForever
local function Wrap(frame)
    function frame:SetSize(w, h) self.width, self.height = w, h end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetPoint(point, relative, relativePoint, x, y)
        self.point, self.relativePoint, self.x, self.y = point, relativePoint, x, y
    end
    function frame:SetTexCoord(a, b, c, d) self.crop = { a, b, c, d } end
    function frame:SetColorTexture(r, g, b, a) self.tint = { r, g, b, a } end
    local texture, font = frame.CreateTexture, frame.CreateFontString
    function frame:CreateTexture(...) return Wrap(texture(self, ...)) end
    function frame:CreateFontString(...) return Wrap(font(self, ...)) end
    return frame
end
local nativeFrame = CreateFrame
local secureWrites, sounds = 0, 0
CreateFrame = function(kind, name, parent, template)
    local frame = Wrap(nativeFrame(kind))
    frame.parent, frame.template = parent, template
    local attribute = frame.SetAttribute
    function frame:SetAttribute(...)
        secureWrites = secureWrites + 1
        return attribute(self, ...)
    end
    return frame
end
PlaySound = function() sounds = sounds + 1 end
local config = {}
for key, value in pairs(NS.Defaults.suite.modules.buffReminders) do config[key] = value end
config.spellIDs, config.items = "777", "123:888"
config.mainHandItem, config.offHandItem = "456", ""
config.classBuff, config.groupBuff, config.otherClassBuffs = true, true, false
config.autoFlask, config.autoFood, config.autoRune, config.autoWeapon = false, false, false, false
config.autoRoguePoisons, config.mapPotion = false, false
config.size, config.spacing, config.columns = 72, 12, 2
config.countFont, config.countSize, config.countPosition, config.countX, config.countY = "Custom", 17, 5, 9, -4
config.reminderGlow, config.class_glow, config.personal_glow, config.consumable_glow = 3, 4, 2, 3
config.borderColor, config.class_glowColor, config.consumable_glowColor = "123456", "abcdef", "fedcba"
local module = testModule
module.config, module.view.host = config, nil
S.editMode = true
module:Enable()
local live, entries = module.view, module.list.entries
assert(#entries == 4, "fixture must include class, spell, item and weapon reminders")
local liveFirst, writes = entries[1], secureWrites
local stage, opened = CreateFrame("Frame"), 0
local function Open() opened = opened + 1 end
local w, h, count = S.BuffRemindersDrawPreview(stage, config, true, Open)
local state = stage.buffReminderPreview
assert(count == #entries and w == live.host.width and h == live.host.height,
    "preview changed the runtime row geometry")
assert(state.list.entries == state.menuPreview.buffer.list, "preview ignored its isolated entry buffer")
assert(state.list.entries ~= entries and state.list.entries[1] ~= liveFirst,
    "preview borrowed the active entry buffer")
assert(R.SameEntries(entries, state.list.entries), "preview selection differs from runtime")
for i, button in ipairs(state.view.buttons) do
    local actual = live.buttons[i]
    assert(button.template == nil and button.parent == stage and not next(button.attributes), "preview created a secure action")
    assert(button.width == actual.width and button.height == actual.height, "preview ignored configured icon size")
    assert(button.x == actual.x and button.y == actual.y, "preview ignored runtime spacing or columns")
    assert(button.icon.texture == actual.icon.texture and button.icon.desaturated == actual.icon.desaturated,
        "preview icon identity differs from runtime")
    assert(table.concat(button.icon.crop, ",") == table.concat(actual.icon.crop, ","), "preview crop differs from runtime")
    assert(button.count.fontPath == actual.count.fontPath and button.count.fontSize == actual.count.fontSize
        and button.count.fontFlags == actual.count.fontFlags and button.count.point == actual.count.point
        and button.count.x == actual.count.x and button.count.y == actual.count.y, "preview ignored runtime count typography")
    assert(button.count.text == actual.count.text, "preview count differs from Edit Mode samples")
    assert(button.alertColor == actual.alertColor and button.alertPulsing == actual.alertPulsing,
        "preview ignored runtime category border effects")
end
assert(state.view.buttons[1].alertPulse.playing and not state.view.buttons[2].alertPulsing,
    "preview did not apply independent category effects")
state.view.buttons[1].OnClick()
assert(opened == 1 and secureWrites == writes and sounds == 0, "preview changed runtime actions or played sound")
local compile, builds = R.BuildEntries, 0
R.BuildEntries = function(...) builds = builds + 1; return compile(...) end
config.size, config.spacing, config.columns, config.countSize = 48, 3, 3, 21
S.BuffRemindersDrawPreview(stage, config, false, Open)
assert(builds == 0, "appearance refresh rebuilt the bag selection")
assert(stage.width == 150 and stage.height == 99 and state.view.buttons[4].y == -51,
    "appearance change did not repaint runtime geometry")
assert(state.view.buttons[3].count.fontSize == 21, "count size change did not repaint")
config.spellIDs = "777,778"
S.BuffRemindersDrawPreview(stage, config, false, Open)
assert(builds == 1 and #state.list.entries == 5, "selection change was not compiled")
assert(module.list.entries == entries and entries[1] == liveFirst and #entries == 4,
    "menu compilation overwrote the live entry buffer")
S.BuffRemindersDrawPreview(stage, config, true, Open)
assert(builds == 2, "native bag or spell event did not refresh the selection")
S.BuffRemindersReleasePreview(stage)
assert(not state.view.buttons[1].alertPulse.playing, "hidden menu kept pulsing")
S.BuffRemindersDrawPreview(stage, config, false, Open)
assert(state.view.buttons[1].alertPulse.playing, "reopened preview did not resume its pulse")
config.classBuff, config.groupBuff, config.spellIDs, config.items, config.mainHandItem = false, false, "", "", ""
local _, _, empty = S.BuffRemindersDrawPreview(stage, config, false, Open)
assert(empty == 0, "preview invented reminders for an empty configuration")
for _, button in ipairs(state.view.buttons) do assert(not button.shown and not button.alertPulsing, "removed preview stayed visible") end
assert(secureWrites == writes and sounds == 0, "menu repaint changed runtime actions or played sound")
R.BuildEntries = compile
S.editMode = false
module:Disable()
print("Buff reminder preview: real runtime selection, geometry, count fonts, category effects and isolated lifecycle passed")
