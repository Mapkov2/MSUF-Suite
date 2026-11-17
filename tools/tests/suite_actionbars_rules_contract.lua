-- Custom visibility conditions, custom paging per bar and the Masque opt-in
-- of the action bars: the shared catalog checks (Core/Catalog/ActionBars.lua),
-- the runtime drivers (Visibility.lua, Paging.lua) and Masque.lua, each
-- loaded on its own with plain stubs.
-- Usage: lua tools/tests/suite_actionbars_rules_contract.lua <repository root>
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local defaults, NS = Support.CatalogDefaults(root, "actionbars", "ActionBars")
local ENUM = NS.ActionBarEnum
local VIS, COND, TARGET, COMBINE = ENUM.VISIBILITY, ENUM.CONDITION, ENUM.TARGET_CONDITION, ENUM.COMBINE
local rules = NS.SuiteCatalog.actionbars.rules

local function Config(values)
    local config = {}
    for key, value in pairs(defaults) do config[key] = value end
    for key, value in pairs(values or {}) do config[key] = value end
    return config
end

------------------------------------------------------------------ catalog
assert(VIS.NEVER == 6 and VIS.CUSTOM == 7, "saved visibility indexes moved")
for i = 1, NS.ActionBarCount do
    local p = "bar" .. i
    assert(#rules[p .. "Visibility"].choices == 7 and #rules[p .. "ResumeVisibility"].choices == 7,
        "Custom conditions cannot be resumed after a quick switch")
    for _, suffix in ipairs({ "CondCombine", "CondCombat", "CondMounted", "CondTarget", "CondMouseover" }) do
        assert(rules[p .. suffix].requiresChoice.values[VIS.CUSTOM], suffix .. " is not a Custom conditions option")
    end
    assert(rules[p .. "FadeAlpha"].requiresChoice.values[VIS.CUSTOM], "custom mouseover cannot fade")
    assert((rules[p .. "Paging"].hidden == true) == (i >= 10), "paging offered on a bar without pages")
    assert(rules[p .. "Paging"].default == "" and rules[p .. "Paging"].maxLength == 255, "paging text rule")
end
assert(rules.masque.default == false, "Masque must be opt-in")

------------------------------------------------------------------ custom visibility bodies
local c = Config()
assert(NS.ActionBarConditionBody(c, 1) == "[combat] show; fade", "default custom rule is mouseover or combat")
c.bar1CondTarget, c.bar1CondMounted = TARGET.HOSTILE, COND.NO
assert(NS.ActionBarConditionBody(c, 1) == "[@target,harm] show; [combat] show; [nomounted] show; fade", "any")
c.bar1CondCombine = COMBINE.ALL
assert(NS.ActionBarConditionBody(c, 1) == "[@target,harm,combat,nomounted] fade; hide", "all with mouseover")
c.bar1CondMouseover = false
assert(NS.ActionBarConditionBody(c, 1) == "[@target,harm,combat,nomounted] show; hide", "all")
c.bar1CondTarget, c.bar1CondCombat, c.bar1CondMounted = TARGET.IGNORE, COND.IGNORE, COND.IGNORE
assert(NS.ActionBarConditionBody(c, 1) == "show", "nothing chosen shows the bar")
c.bar1CondMouseover = true
assert(NS.ActionBarConditionBody(c, 1) == "fade", "mouseover alone")
c.bar1CondCombine, c.bar1CondTarget, c.bar1CondMouseover = COMBINE.ANY, TARGET.NONE, false
assert(NS.ActionBarConditionBody(c, 1) == "[@target,noexists] show; hide", "no target")
c.bar1Visibility = VIS.CUSTOM
assert(not NS.ActionBarFades(c, 1), "custom without mouseover took hover")
c.bar1CondMouseover = true
assert(NS.ActionBarFades(c, 1) and NS.ActionBarFades(Config({ bar2Visibility = VIS.MOUSEOVER }), 2), "fade modes")
assert(not NS.ActionBarFades(Config({ bar2Visibility = VIS.COMBAT }), 2), "combat mode faded")

------------------------------------------------------------------ paging checks
-- Defaults: every bar is on, so pages 2 to 6 belong to bars 9, 4, 5, 3 and 2.
local function Refused(config, index, expected)
    local parsed, why = NS.ActionBarPaging(config, index)
    assert(parsed == nil and why == expected, ("bar %d: expected %q, got %q"):format(index, expected, tostring(why)))
end
assert(NS.ActionBarPaging(Config(), 1) == false, "empty text pages")
assert(NS.ActionBarPaging(Config({ bar2Paging = "[combat] 3", bar2Visibility = VIS.NEVER }), 2) == false, "off bar pages")
Refused(Config({ bar1Paging = "[mod:shift] 2" }), 1, "Page %d belongs to action bar %d.")
Refused(Config({ bar10Paging = "[combat] 1" }), 10, "Custom paging is not available for this bar.")
Refused(Config({ bar1Paging = "[vehicleui] 7" }), 1, "Unknown condition: %s")
Refused(Config({ bar1Paging = "[petbattle] 7" }), 1, "Unknown condition: %s")
Refused(Config({ bar1Paging = "[combat] 7\"" }), 1, "Use only macro conditions, page numbers and semicolons.")
Refused(Config({ bar1Paging = "[combat] 7; /run x" }), 1, "Each clause ends with a page number: %s")
Refused(Config({ bar1Paging = "[combat] 7; 8; [mod] 9" }), 1, "Nothing can follow a clause without conditions.")
Refused(Config({ bar1Paging = "[combat] 12" }), 1, "Bar 1 pages to pages 1 to 11.")
Refused(Config({ bar2Paging = "[combat] 7" }), 2, "This bar pages to its own page or to a free page from 2 to 6.")
Refused(Config({ bar2Paging = "[combat] 1" }), 2, "This bar pages to its own page or to a free page from 2 to 6.")
Refused(Config({ bar1Paging = "[bar:7] 7" }), 1, "Unsupported value for %s: %s")
Refused(Config({ bar1Paging = "[spec] 7" }), 1, "The condition %s needs a value.")
Refused(Config({ bar1Paging = "[combat:1] 7" }), 1, "The condition %s takes no value.")
Refused(Config({ bar1Paging = "[combat,@target] 7" }), 1, "Unsupported unit: %s")
Refused(Config({ bar1Paging = "[@raid1] 7" }), 1, "Unsupported unit: %s")
Refused(Config({ bar1Paging = "[combat 7" }), 1, "A condition is missing its closing bracket.")
Refused(Config({ bar1Paging = "[combat,] 7" }), 1, "A condition list has an empty entry.")
Refused(Config({ bar1Paging = ";;" }), 1, "Add at least one clause.")
Refused(Config({ bar1Paging = "[combat] 7 \195\164" }), 1, "Use only macro conditions, page numbers and semicolons.")
Refused(Config({ bar1Paging = string.rep("[combat] 7; ", 17) }), 1, "Use at most %d clauses.")
local long = Config({ bar1Paging = string.rep(" ", 250) .. "[combat] 7" })
Refused(long, 1, "Use only macro conditions, page numbers and semicolons.")

local parsed = NS.ActionBarPaging(Config({ bar1Paging = " [MOD:Shift/ctrl , nocombat][Target = Focus,Harm] 8 ;[form:1/2] 7;" }), 1)
assert(parsed and parsed.driver == "[mod:shift/ctrl,nocombat][@focus,harm] 8; [form:1/2] 7" and not parsed.final,
    "text was not normalized: " .. tostring(parsed and parsed.driver))
parsed = NS.ActionBarPaging(Config({ bar1Paging = "[combat] 7; 1" }), 1)
assert(parsed.final and parsed.driver == "[combat] 7; 1", "unconditional last clause")

-- One owner per page: a free page goes to the lowest bar that pages to it.
local free = Config({ bar9Visibility = VIS.NEVER, bar2Paging = "[combat] 2", bar3Paging = "[mod] 2", bar1Paging = "[harm] 2" })
local claims = NS.ActionBarPageClaims(free)
assert(claims[2] == 2 and not claims[6], "claims")
assert(NS.ActionBarPaging(free, 2, claims).driver == "[combat] 2", "lowest bar lost its free page")
Refused(free, 3, "Page %d is already paged by action bar %d.")
Refused(free, 1, "Page %d is already paged by action bar %d.")
free.bar2Paging = ""
assert(NS.ActionBarPaging(free, 3).driver == "[mod] 2" and NS.ActionBarPageClaims(free)[2] == 3, "released page")
free.bar9Visibility = VIS.MOUSEOVER
Refused(free, 3, "Page %d belongs to action bar %d.")

------------------------------------------------------------------ runtime stubs
local combat, drivers, unregistered, executed = false, {}, {}, {}
NS.IsCombatLocked = function() return combat end
RegisterStateDriver = function(frame, state, driver) drivers[frame] = driver; frame:SetAttribute("state-" .. state, driver) end
UnregisterStateDriver = function(frame) unregistered[frame] = true; drivers[frame] = nil end
local function Frame()
    local frame = { attributes = {} }
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:GetAttribute(key) return self.attributes[key] end
    return frame
end
local config = Config()
local AB = { M = { config = config, active = true }, SNIPPET = { BUTTON = "", NATIVE_BUTTON = "" }, ENUM = ENUM, bars = {},
    Diagnostics = {}, BAR_COUNT = NS.ActionBarCount, KEYS = {} }
for i = 1, NS.ActionBarCount do
    AB.KEYS[i] = {}
    for _, suffix in ipairs({ "Visibility", "HideGamepad", "GroupOnly", "CondMouseover" }) do AB.KEYS[i][suffix] = "bar" .. i .. suffix end
end
AB.Execute = function(frame, body)
    if combat then return false end
    executed[#executed + 1] = { frame = frame, body = body }
    return true
end
local S = { Text = function(text) return text end }
local P = { NS = NS, Suite = S, ActionBars = AB }
assert(loadfile(root .. "/MSUF_Suite_ActionBars/Paging.lua"))("MSUF_Suite_ActionBars", P)
assert(loadfile(root .. "/MSUF_Suite_ActionBars/Visibility.lua"))("MSUF_Suite_ActionBars", P)

------------------------------------------------------------------ bar 1 driver
local SPECIAL = "[vehicleui] vehicle; [overridebar] override; [possessbar] possess; [shapeshift] shapeshift; "
local FORMS = "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; "
config.bar9Visibility, config.bar1Paging = VIS.NEVER, "[mod:shift] 2"
assert(AB.PageDriver(config) == SPECIAL .. "[bar:2] 2; " .. FORMS .. "[bonusbar:5] 11; [mod:shift] 2; 1",
    "custom clauses must follow every native and form page: " .. AB.PageDriver(config))
assert(AB.CustomPaging(config), "bar 1 custom paging must route its keys")
config.bar1Paging = "[harm] 7; 3"
Refused(config, 1, "Page %d belongs to action bar %d.")
assert(AB.PageDriver(config) == SPECIAL .. "[bar:2] 2; " .. FORMS .. "[bonusbar:5] 11; 1", "invalid text reached the driver")
config.bar1Paging = "[harm] 7; 2"
assert(AB.PageDriver(config) == SPECIAL .. "[bar:2] 2; " .. FORMS .. "[bonusbar:5] 11; [harm] 7; 2", "final clause")
config.bar2Paging, config.bar1Paging = "[combat] 2", ""
assert(AB.ReservedPage(config, 2) and AB.PageDriver(config) == SPECIAL .. FORMS .. "[bonusbar:5] 11; 1",
    "bar 1 kept a page bar 2 claimed")

------------------------------------------------------------------ bars 2 to 9
local function NewBar(index, native)
    local bar = { index = index, owned = true, native = native, header = Frame(), buttons = {} }
    for i = 1, 12 do bar.buttons[i] = { index = i, button = Frame(), slot = i } end
    AB.bars[index] = bar
    return bar
end
local bar2, bar9 = NewBar(2, true), NewBar(9, false)
bar2.header:SetAttribute("actionpage", 6)
AB.ApplyPaging()
local NATIVE = "[vehicleui][overridebar][possessbar][petbattle] "
assert(drivers[bar2.header] == NATIVE .. "6; [combat] 2; 6", "bar 2 driver: " .. tostring(drivers[bar2.header]))
assert(bar2.customPage and bar2.header:GetAttribute("allow-page-2") and not bar2.header:GetAttribute("allow-page-3"))
assert(bar2.header:GetAttribute("homepage") == 6 and bar2.header:GetAttribute("nativepage") == true, "home attributes")
assert(bar2.buttons[1].button:GetAttribute("_childupdate-page"), "bar 2 buttons take no page")
assert(not drivers[bar9.header] and not bar9.customPage, "bar 9 paged without text")
combat, config.bar2Paging = true, "[combat] 3"
AB.ApplyPaging()
assert(drivers[bar2.header] == NATIVE .. "6; [combat] 2; 6", "paging applied in combat")
combat = false
AB.ApplyPaging()
assert(not drivers[bar2.header] and unregistered[bar2.header] and not bar2.customPage, "invalid text kept its driver")
assert(not bar2.header:GetAttribute("allow-page-2") and executed[#executed].frame == bar2.header, "bar 2 not sent home")
assert(bar2.buttons[3].slot == 3 + 5 * 12, "bar 2 slots not back on its own page")
config.bar9Visibility, config.bar9Paging, config.bar2Paging = VIS.MOUSEOVER, "[stealth] 2; [nostealth] 2", ""
AB.ApplyPaging()
assert(drivers[bar9.header] == NATIVE .. "2; [stealth] 2; [nostealth] 2; 2", "bar 9 home page clause")
AB.StopPaging()
assert(not drivers[bar9.header] and not bar9.customPage, "stop kept a driver")

------------------------------------------------------------------ visibility drivers
config.bar1Visibility = VIS.CUSTOM
config.bar1CondCombat, config.bar1CondMounted, config.bar1CondTarget = COND.YES, COND.IGNORE, TARGET.IGNORE
config.bar1CondCombine, config.bar1CondMouseover = COMBINE.ANY, true
assert(AB.VisibilityDriver(1, VIS.CUSTOM, true) == "[petbattle][vehicleui] hide; [combat] show; fade", "custom driver")
assert(AB.VisibilityDriver(1, VIS.CUSTOM, true, false, true) == "[petbattle][vehicleui] hide; [nocombat] show; [combat] show; fade",
    "the panel reveal lost its place")
config.bar12Visibility, config.bar12CondMounted, config.bar12CondCombat, config.bar12CondMouseover = VIS.CUSTOM, COND.NO, COND.IGNORE, false
config.bar12GroupOnly = true
assert(AB.VisibilityDriver(12, VIS.CUSTOM, true) == "[petbattle][nopet] hide; [nogroup] hide; [nomounted] show; hide", "pet bar")
assert(AB.VisibilityDriver(11, VIS.CUSTOM, false) == "hide", "stance bar without forms")
assert(AB.VisibilityDriver(1, VIS.NEVER, true) == "hide", "Never")

------------------------------------------------------------------ Masque
local lib, joined = nil, {}
local styleEvents = 0
EventRegistry = { TriggerEvent = function(_, event)
    assert(event == "MSUFSuite.ActionBars.StyleChanged", "unexpected action bar event")
    styleEvents = styleEvents + 1
end }
hooksecurefunc = function(target, method, callback)
    local original = assert(target[method])
    target[method] = function(self, ...)
        original(self, ...)
        callback(self, ...)
    end
end
local function NewGroup()
    local group = { buttons = {}, reskins = 0 }
    function group:AddButton(button, regions, kind, strict)
        assert(kind == "Action" and strict == true and regions.Icon and not regions.HotKey, "Masque regions")
        self.buttons[button] = true
        joined[#joined + 1] = button
    end
    function group:RemoveButton(button) self.buttons[button] = nil end
    function group:ReSkin() self.reskins = self.reskins + 1 end
    function group:Delete() self.deleted = true end
    return group
end
LibStub = { GetLibrary = function(_, name) return name == "Masque" and lib or nil end }
NS.HostBridge = { PaintIconSkin = function() return nil end }
local styled = 0
AB.ClearDecoration, AB.ShowEdges = function(rec) rec.cleared = true end, function() end
AB.StyleButton = function(rec) styled = styled + 1; rec.styledMasqued = rec.masqued end
AB.style = {}
assert(loadfile(root .. "/MSUF_Suite_ActionBars/Masque.lua"))("MSUF_Suite_ActionBars", P)
local function Texture()
    local texture = { alpha = 0, shown = true }
    function texture:SetAlpha(value) self.alpha = value end
    function texture:Hide() self.shown = false end
    function texture:Show() self.shown = true end
    return texture
end
local function Button()
    local button = { icon = Texture(), cooldown = {}, normal = Texture() }
    function button:GetNormalTexture() return self.normal end
    function button:GetPushedTexture() return nil end
    function button:GetHighlightTexture() return nil end
    function button:GetCheckedTexture() return nil end
    return button
end
AB.bars = {}
local suiteBar, nativeBar = NewBar(9, false), NewBar(2, true)
local suiteRec = { owned = true, bar = suiteBar, button = Button(), slotTexture = Texture() }
local nativeRec = { owned = true, native = true, bar = nativeBar, button = Button() }
suiteBar.buttons, nativeBar.buttons = { suiteRec }, { nativeRec }
suiteBar.key = { Size = "bar9Size" }
config.masque = true
AB.Masque.Sync(function() return false end)
assert(#AB.Diagnostics.MasqueGroups() == 0 and not suiteRec.masqued, "joined without Masque loaded")
lib = { groups = {} }
function lib:Group(addon, title, id)
    assert(addon == "MSUF Suite" and title and id == "actionbar9", "Masque group identity")
    local group = NewGroup()
    self.groups[#self.groups + 1] = group
    return group
end
combat = true
AB.Masque.Sync()
assert(#joined == 0, "Masque joined in combat")
combat = false
AB.Masque.Sync(function() return false end)
local group = lib.groups[1]
assert(#lib.groups == 1 and group.buttons[suiteRec.button] and #joined == 1, "only the Suite-made button joins")
assert(suiteRec.masqued and suiteRec.cleared and suiteRec.styledMasqued and group.reskins == 1, "join")
assert(suiteRec.button.normal.alpha == 1 and not suiteRec.slotTexture.shown, "Suite art still covers Masque's")
assert(not nativeRec.masqued, "a reused Blizzard button joined Masque")
AB.Masque.Sync(function() return false end)
assert(group.reskins == 1 and #joined == 1, "an unchanged sync reskinned")
AB.Masque.Sync(function(index) return index == 9 end)
assert(group.reskins == 2, "a resized bar was not reskinned")
config.masque = false
AB.Masque.Sync()
assert(not suiteRec.masqued and not group.buttons[suiteRec.button] and group.deleted, "restore")
assert(suiteRec.slotTexture.shown and suiteRec.styledMasqued == nil and not AB.Masque.Active(), "Suite look not restored")

------------------------------------------------------------------ static rules
for _, path in ipairs({ "MSUF_Suite_ActionBars/Masque.lua", "MSUF_Suite_ActionBars/Paging.lua",
    "MSUF_Suite_ActionBars/Visibility.lua", "MSUF_Suite/Core/Catalog/ActionBars.lua" }) do
    local handle = assert(io.open(root .. "/" .. path, "rb"))
    local source = handle:read("*a")
    handle:close()
    local code = source:gsub("%-%-[^\n]*", "")
    for _, banned in ipairs({ "pcall", "OnUpdate", "StaticPopupDialogs", "COMBAT_LOG_EVENT", "NewTicker" }) do
        assert(not code:find(banned, 1, true), path .. " uses " .. banned)
    end
    local lines = select(2, source:gsub("\n", "\n"))
    assert(lines <= 810, path .. " is longer than 810 lines")
end
local toc = assert(io.open(root .. "/MSUF_Suite_ActionBars/MSUF_Suite_ActionBars_Mainline.toc", "rb")):read("*a")
assert(toc:find("\nStyle.lua\r?\nMasque.lua\r?\n"), "Masque.lua is not loaded after Style.lua")
print("Action bar rules: custom visibility, paging validation and ownership, page drivers, combat refusal and Masque opt-in passed")
