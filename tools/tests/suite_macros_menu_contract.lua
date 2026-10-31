local root = assert(arg[1], "repository root required")
local combat, loads, publications, pickups, occupied = false, 0, 0, 0, false
local function Frame(parent)
    local frame = { scripts = {}, events = {}, shown = true, parent = parent, text = "", width = 720 }
    function frame:SetScript(key, value) self.scripts[key] = value end
    function frame:HookScript(key, value)
        local old = self.scripts[key]
        self.scripts[key] = function(...) if old then old(...) end value(...) end
    end
    function frame:RegisterEvent(key) self.events[key] = true end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:SetText(text) self.text = text end
    function frame:GetText() return self.text end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:GetWidth() return self.width end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetShown(value) self.shown = value end
    function frame:IsShown() return self.shown end
    function frame:IsVisible()
        local parent = rawget(self, "parent")
        return self.shown and (not parent or parent:IsVisible())
    end
    function frame:ClearFocus() self.focus = false end
    function frame:SetFocus() self.focus = true end
    function frame:SetEnabled(value) self.enabled = value end
    function frame:SetActive(value) self.active = value end
    function frame:SetChecked(value) self.checked = value end
    function frame:GetChecked() return self.checked end
    function frame:GetFrameLevel() return 1 end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:CreateTexture() return Frame(self) end
    return setmetatable(frame, { __index = function() return function() end end })
end
CreateFrame = function(_, _, parent) return Frame(parent) end
C_AddOns = { LoadAddOn = function() loads = loads + 1 end }
local NS = { IsSecret = function() return false end, Public = function() return true end }
for _, file in ipairs({ "Model", "Compile", "Templates" }) do
    assert(loadfile(root .. "/MSUF_Suite/Core/Macros/" .. file .. ".lua"))("MSUF_Suite", NS)
end
local saved, serial, native = {}, 0, {}
NS.Macros.Store = {
    Preview = function(document) return NS.Macros.Compile(document) end,
    List = function() return saved end,
    Get = function(id) return saved[id] end,
    Save = function(document, id)
        serial = serial + (id and 0 or 1)
        id = id or serial
        saved[id] = assert(NS.Macros.Model.Normalize(document))
        saved[id].id = id
        return id
    end,
    Publish = function(id)
        publications = publications + 1
        native[1] = { index = 1, name = saved[id].name, scope = saved[id].scope,
            body = NS.Macros.Compile(saved[id]), icon = saved[id].icon }
        return true, nil, 1
    end,
    Pickup = function()
        if occupied then return false, "Clear your cursor before picking up a macro" end
        pickups = pickups + 1
        return true
    end,
    Native = function() return native end,
    Delete = function(id) saved[id] = nil end,
}
NS.Client = { IsAddOnLoaded = function() return true end, isForever = arg[2] == "Forever" }
local color = { 1, 1, 1, 1 }
local P = { Suite = NS, Tr = function(text) return text end, Combat = function() return combat end,
    Meta = function() return {} end, M = {}, S = {}, W = {}, T = { colors = { text = color, muted = color } }, HM = {} }
function P.Text(parent, text) local result = Frame(parent) result.text = text return result end
function P.T.Button(parent, text) return P.Text(parent, text) end
function P.T.Panel(parent) return Frame(parent) end
function P.T.SkinEditBox() end
function P.T.SkinPrimaryButton() end
function P.HM.SkipHistoryCheckpoint() end
function P.HM.GetControlTitle(control) return rawget(control, "title") end
function P.HM.GetControlLabel(control) return rawget(control, "caption") end
function P.HM.GetSectionWidth() return 720 end
function P.HM.SetSectionCursor() end
function P.M.RegisterControlMetadata() end
function P.M.AddTooltip() end
function P.M.TrackRefresh() end
function P.S.Config() return { enabled = false } end
function P.S.Set() return true end
function P.Confirm(_, _, callback) callback() end
function P.MenuPopupPanel() return Frame() end
function P.W.Dropdown(parent)
    local frame = Frame(parent)
    frame.title = Frame(parent)
    function frame:SetOnValueChanged(callback) self.change = callback end
    function frame:SetValues(values) self.values = values end
    function frame:SetValue(value) self.value = value end
    return frame
end
function P.W.PageBuilder()
    return { Section = function() local f = Frame() f.title = Frame(f) return f end, FinishSection = function() end }
end
function P.W.ToggleAt(parent, label)
    local frame = Frame(parent)
    frame.caption = P.Text(parent, label)
    return frame
end
function P.RegisterPage(spec) P.registered = spec end
for _, file in ipairs({ "MacrosWidgets", "MacrosPicker", "MacrosRules", "MacrosConsumables", "MacrosLibrary", "Macros" }) do
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/" .. file .. ".lua"))("MSUF_Suite_Options", P)
end
assert(P.registered.key == "suite_macros" and P.registered.nav == "general", "native menu route")
local search = { searchRows = {} }
P.registered.build(search)
assert(#search.searchRows == 4 and loads == 0 and serial == 0, "cold search is read-only")
assert(not P.MacroPage.initialized and P.MacroPage.ui == nil, "cold search defers editor closures")
P.registered.build({ width = 720 })
local page = P.MacroPage
assert(publications == 0 and page.ui.publish.enabled == false, "opening must not publish")
local arenaChoices = 0
for _, choice in ipairs(page.helpers.units) do
    if choice.value:match("^arena") then arenaChoices = arenaChoices + 1 end
end
assert(arenaChoices == (NS.Client.isForever and 0 or 3), "target choices follow arena client support")
page.ui.pools.button["quick:mouseover"].action()
assert(page.document.steps[1].branches[1].conditions[1].value == "mouseover", "mouseover quick start")
page.ui.pools.select.template.action("mouseover-mark")
assert(page.document.steps[1].raidMarker == 8, "combined mouseover heal and mark template")
page.ui.pools.button["new"].action()
page.document.name = "Builder"
page.document.steps[1].branches[1].value = "Kick"
page.Preview()
assert(page.compiled:find("/cast Kick", 1, true) and page.ui.publish.enabled, "live preview")
local tooltip = page.ui.pools.toggle.showtooltip
tooltip.scripts.OnClick(tooltip)
assert(page.document.showTooltip == false and tooltip.checked == false, "toggle first click")
tooltip.scripts.OnClick(tooltip)
assert(page.document.showTooltip == true and tooltip.checked == true, "toggle second click")
local target = page.ui.pools.select["step:1:branch:1:target"]
assert(target.shown and target.value == "target", "target choice is visible without adding a condition")
target.action("mouseover")
assert(page.compiled:find("[@mouseover]", 1, true), "mouseover target compiles")
page.ui.pools.select["step:1:branch:1:target"].action("focus")
local conditions = page.document.steps[1].branches[1].conditions
assert(#conditions == 1 and conditions[1].value == "focus", "target replacement has no hidden duplicate")
page.ui.pools.select["step:1:branch:1:target"].action("target")
assert(#page.document.steps[1].branches[1].conditions == 0, "current target clears explicit target")
local marker = page.ui.pools.select["step:1:raid-marker"]
assert(marker.value == -1 and #marker.values == 10, "every targeted action exposes marker off, clear and eight icons")
assert(marker.values[10].icon == "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", "native skull icon")
marker.action(8)
page.ui.pools.select["step:1:branch:1:target"].action("mouseover")
assert(page.compiled:find("/cast [@mouseover] Kick", 1, true), "mouseover action kept")
assert(page.compiled:find("/tm [@mouseover] !8", 1, true), "marker follows the same mouseover target without toggling")
page.ui.pools.select["step:1:branch:1:target"].action("cursor")
marker = page.ui.pools.select["step:1:raid-marker"]
assert(not marker.values[1].disabled and marker.values[10].disabled, "cursor keeps Off available while disabling marks")
marker.action(7)
assert(page.document.steps[1].raidMarker == 8, "disabled cursor choices cannot change marker")
marker.action(-1)
assert(page.document.steps[1].raidMarker == nil, "invalid marker combination can be cleared")
page.ui.pools.select["step:1:branch:1:target"].action("target")
page.ui.pools.select["step:1:raid-marker"].action(0)
assert(page.compiled:find("/tm 0", 1, true), "attached clear marker")
page.ui.pools.select["step:1:raid-marker"].action(-1)
assert(not page.compiled:find("/tm", 1, true), "Off removes attached marker")
page.ui.pools.button["step:1:branch:1:add-condition"].action()
assert(page.document.steps[1].branches[1].conditions[1].key == "mod", "condition builder")
assert(page.compiled:find("[mod:shift]", 1, true), "conditions compile directly")
page.document.steps[1].branches = {
    { value = "Heal", conditions = { { key = "unit", value = "mouseover" } } },
    { value = "", useFirst = true, conditions = { { key = "unit", value = "player" } } },
    { value = "Damage", conditions = { { key = "harm", value = "" } } },
}
page.document.steps[1].raidMarker = 8
page.Render()
assert(page.ui.pools.toggle["step:1:branch:2:same"].shown, "fallback shares first action")
page.ui.pools.button["step:1:branch:3:up"].action()
page.ui.pools.button["step:1:branch:2:up"].action()
assert(page.document.steps[1].branches[1].value == "Damage", "alternative can move to first")
assert(page.document.steps[1].branches[3].value == "Heal", "inherited heal survives different first action")
assert(page.compiled and not page.document.steps[1].branches[1].useFirst, "first rule never inherits itself")
assert(page.document.steps[1].raidMarker == 8 and page.compiled:find("/tm [harm][@mouseover][@player] !8", 1, true),
    "reordering alternatives preserves marker and target priority")
page.ui.pools.button["step:1:branch:1:remove"].action()
assert(page.compiled and page.document.steps[1].branches[1].value == "Heal", "removing first preserves fallbacks")
page.ui.pools.select["step:1:command"].action("swapactionbar")
page.ui.pools.select["step:1:branch:1:page:2"].action(5)
assert(page.compiled:find("/swapactionbar 1 5", 1, true), "action bar pages use native dropdowns")
page.ui.pools.select["step:1:command"].action("tm")
page.ui.pools.select["step:1:branch:1:marker"].action(7)
assert(page.compiled:find("/tm !7", 1, true), "standalone icon choice sets and keeps Cross")
page.ui.pools.select["step:1:branch:1:marker"].action(0)
assert(page.compiled:find("/tm 0", 1, true), "standalone clear marker")
page.ui.pools.select["step:1:command"].action("startattack")
local targetArgument = page.ui.pools.edit["step:1:branch:1:action"]
targetArgument.action("focus")
marker = page.ui.pools.select["step:1:raid-marker"]
assert(marker.values[10].disabled, "typed attack target disables incompatible attached markers immediately")
marker.action(8)
assert(page.document.steps[1].raidMarker == nil, "incompatible typed attack target cannot receive attached marker")
targetArgument.action("")
assert(not marker.values[10].disabled, "clearing typed target enables marker choices immediately")
marker.action(7)
assert(page.compiled:find("/tm !7", 1, true), "target-selector attack can carry a marker")
targetArgument.action("  \t ")
assert(not marker.values[10].disabled, "whitespace-only optional target matches compiler validation")
targetArgument.action("")
page.ui.pools.button["step:1:branch:1:add-condition"].action()
page.ui.pools.button["step:1:add-rule"].action()
local sameAction = page.ui.pools.toggle["step:1:branch:2:same"]
sameAction.scripts.OnClick(sameAction)
page.ui.pools.edit["step:1:branch:2:action"].action("focus")
assert(page.ui.pools.select["step:1:raid-marker"].values[10].disabled, "explicit alternate attack target blocks attached marker")
sameAction.scripts.OnClick(sameAction)
marker = page.ui.pools.select["step:1:raid-marker"]
assert(not marker.values[10].disabled and page.compiled, "Same action ignores hidden stale optional target")
assert(page.document.steps[1].branches[2].value == "focus", "inherited mode preserves inactive value for later editing")
marker.action(8)
assert(page.document.steps[1].raidMarker == 8 and page.compiled, "inherited blank target can attach a marker")
page.ui.pools.select["step:1:command"].action("wm")
local worldMarker = page.ui.pools.select["step:1:branch:1:world-marker"]
assert(#worldMarker.values == 8 and worldMarker.values[1].icon == "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
    "world marker one is the native Square icon")
worldMarker.action(4)
assert(page.compiled:find("/wm 4", 1, true), "world marker Cross uses native index four")
page.ui.pools.select["step:1:command"].action("cwm")
worldMarker = page.ui.pools.select["step:1:branch:1:world-marker"]
assert(worldMarker.values[1].value == "all" and #worldMarker.values == 9, "clear world marker exposes locale-independent All")
worldMarker.action("all")
assert(page.compiled and page.compiled:find("/cwm 1", 1, true) and page.compiled:find("/cwm 8", 1, true),
    "clear All is eight native numeric commands")
page.document = NS.Macros.Model.New("sequence")
page.document.name = "Sequence"
page.document.steps[1].sequence = { "Kick", "Blind" }
page.Render()
assert(page.compiled:find("reset=target/combat Kick,Blind", 1, true), "sequence preview")
page.ui.pools.select["step:1:raid-marker"].action(1)
assert(page.compiled:find("/tm !1", 1, true), "sequences can mark the same target")
page.ui.pools.button["step:1:sequence:2:up"].action()
assert(page.document.steps[1].sequence[1] == "Blind", "sequence reorder")
page.ui.pools.button["step:1:sequence:2:remove"].action()
assert(#page.document.steps[1].sequence == 1, "sequence remove")
page.ui.pools.button["tab:raw"].action()
local raw = page.ui.pools.edit["raw-code"]
raw:SetText("#showtooltip\n/cast Kick")
raw.scripts.OnTextChanged(raw, true)
assert(page.document.raw == raw:GetText() and publications == 0, "typing only edits draft")
page.ui.pools.button["tab:rules"].action()
page.ui.pools.button["tab:raw"].action()
assert(page.document.raw == "#showtooltip\n/cast Kick", "returning to code preserves manual changes")
raw = page.ui.pools.edit["raw-code"]
raw:SetText(string.rep("x", 256))
raw.scripts.OnTextChanged(raw, true)
assert(page.ui.counter.text:find("256", 1, true) and not page.ui.publish.enabled, "overflow remains visible")
Enum = { SpellBookSpellBank = { Player = 1, Pet = 2 } }
C_SpellBook = {
    HasPetSpells = function() return 1 end,
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 1 } end,
    GetSpellBookItemInfo = function(_, bank) return { spellID = bank } end,
    IsSpellBookItemPassive = function() return false end,
}
C_Spell = {
    GetSpellInfo = function(id) return { name = id == 2 and "Pet Bite" or "Heal", iconID = 1 } end,
    GetSpellSubtext = function() return "Rank 1" end,
}
page.Pick(page.ui.body, "pet", function() end)
assert(page.picker.items[1].name == "Pet Bite", "pet selector reads the pet spell bank")
NS.Client.isForever = true
page.Pick(page.ui.body, "spell", function() end)
assert(#page.picker.items == 2, "Forever preserves a highest-rank choice and an explicit rank")
page.picker:Hide()
page.document = NS.Macros.Model.New("spell")
page.document.name = "Retained draft"
page.document.steps[1].branches[1].value = "Kick"
page.tab = "rules"
page.Render()
page.ui.pools.button["save-draft"].action()
assert(serial == 1 and publications == 0, "save draft is separate from publishing")
page.ui.pools.button["publish"].action()
assert(publications == 1, "explicit publish")
assert(page.pickupReady and native[1].icon == page.document.icon, "saved icon matches draggable macro")
page.ui.pools.button["tab:library"].action()
page.ui.pools.button["tab:rules"].action()
assert(page.pickupReady and not page.dirty, "view-only navigation preserves saved drag readiness")
page.ui.pools.icon.published.scripts.OnDragStart()
assert(pickups == 1, "saved macro icon can be dragged")
page.document.icon = 135999
page.Changed(false)
page.ui.pools.icon.published.scripts.OnDragStart()
assert(pickups == 1, "unsaved icon changes block stale drag")
page.ui.pools.button["save-draft"].action()
page.ui.pools.icon.published.scripts.OnDragStart()
assert(pickups == 1, "saving only a draft does not enable stale native drag")
page.ui.pools.button["publish"].action()
assert(page.pickupReady and native[1].icon == 135999, "native update saves chosen icon")
occupied = true
page.ui.pools.icon.published.scripts.OnDragStart()
assert(pickups == 1, "occupied cursor blocks icon drag")
occupied = false
local body = page.ui.body
combat = true
body.scripts.OnEvent(body, "PLAYER_REGEN_DISABLED")
assert(next(body.events) == nil and not body.shown, "combat removes all page events")
local before = publications
page.ui.pools.button["publish"].scripts.OnClick(page.ui.pools.button["publish"])
assert(publications == before, "hidden combat controls cannot publish")
combat = false
page.ui.pools.button["publish"].scripts.OnClick(page.ui.pools.button["publish"])
assert(publications == before, "hidden out-of-combat controls cannot publish")
assert(body.scripts.OnUpdate == nil, "no perpetual page work")
local previousUI = page.ui
P.registered.build({ width = 720 })
assert(page.ui ~= previousUI, "opening page builds directly without an accordion")
page.ui.body.width = 1400
page.ui.body.scripts.OnSizeChanged(page.ui.body, 1400)
assert(page.ui.width == 1400, "layout uses actual body width")
assert(page.ui.pools.label["result-title"].point[2] > 700, "wide layout places results on the right")
print("suite_macros_menu_contract: passed")
