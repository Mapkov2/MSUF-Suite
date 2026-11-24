local root = assert(arg[1], "repository root required")
local host = arg[3] or root .. "/../MidnightSimpleUnitFrames-7.0"
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
    function frame:SetTexture(texture) self.textureID = texture end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:Show()
        if self.shown then return end
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function frame:Hide()
        if not self.shown then return end
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
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
    function frame:EnableKeyboard(value) self.keyboard = value end
    function frame:RegisterForClicks(clicks) self.clicks = clicks end
    function frame:GetFrameLevel() return 1 end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:CreateTexture() return Frame(self) end
    return setmetatable(frame, { __index = function(_, key)
        if key:match("^[A-Z]") then return function() end end
    end })
end
CreateFrame = function(_, _, parent) return Frame(parent) end
C_AddOns = { LoadAddOn = function() loads = loads + 1 end }
local spellIcons, textureReads = { Kick = 135001, Blind = 135002 }, 0
C_Spell = { GetSpellTexture = function(spell) textureReads = textureReads + 1 return spellIcons[spell] end }
C_Container = { GetContainerNumSlots = function() return 0 end }
local NS = { IsSecret = function() return false end, Public = function() return true end }
for _, file in ipairs({ "Model", "Compile", "Templates" }) do
    assert(loadfile(root .. "/MSUF_Suite/Core/Macros/" .. file .. ".lua"))("MSUF_Suite", NS)
end
local saved, serial, native = {}, 0, {}
local appliedBinding, occupiedBinding, bindingChanged, heldModifiers, restored, deleted
NS.Macros.Native = {
    BindingInput = function(raw, isMouse)
        if isMouse then return { button = raw, modifiers = heldModifiers or 0 } end
        if raw ~= "LSHIFT" and raw ~= "LCTRL" and raw ~= "LALT" then return { key = raw } end
    end,
    BindingLabel = function(input) return input.button or input.key end,
    IsReservedClick = function(input) return input.modifiers == 0 and (input.button == "LeftButton" or input.button == "RightButton") end,
    BindingState = function() return { occupied = occupiedBinding } end,
    CheckBinding = function()
        if bindingChanged then return nil, "The binding changed. Choose the button again." end
        return {}
    end,
    ApplyBinding = function(input, _, entry)
        appliedBinding = { input = input, entry = entry }
        return true
    end,
    RemoveBindings = function(entry, reserved) restored = { entry = entry, reserved = reserved } return true end,
}
NS.Macros.Store = {
    Preview = function(document, preserveRanks) return NS.Macros.Compile(document, nil, preserveRanks) end,
    List = function() return saved end,
    Get = function(id) return saved[id] end,
    Save = function(document, id)
        serial = serial + (id and 0 or 1)
        id = id or serial
        saved[id] = assert(NS.Macros.Model.Normalize(document))
        saved[id].id = id
        return id
    end,
    PrepareUpdate = function() return native[1] end,
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
    ResolvePublished = function() return native[1] end,
    DeleteNative = function(entry) deleted = entry native[1] = nil return true end,
    Delete = function(id) saved[id] = nil end,
}
NS.Client = { IsAddOnLoaded = function() return true end, isForever = arg[2] == "Forever" }
local color = { 1, 1, 1, 1 }
local P = { Suite = NS, Tr = function(text) return text end, Combat = function() return combat end,
    Meta = function() return {} end, M = {}, S = {}, W = {}, T = { colors = { text = color, muted = color } }, HM = {} }
function P.Text(parent, text) local result = Frame(parent) result.text = text return result end
function P.T.Button(parent, text) return P.Text(parent, text) end
function P.SetButtonText(button, text) button:SetText(text) end
function P.SetTranslatedText(region, text) region:SetText(text) end
function P.T.Panel(parent) return Frame(parent) end
function P.T.SkinEditBox() end
function P.T.SkinPrimaryButton() end
function P.HM.SkipHistoryCheckpoint() end
function P.HM.MarkSegmentChoice(button) button.isTab = true end
function P.HM.GetControlTitle(control) return rawget(control, "title") end
function P.HM.GetControlLabel(control) return rawget(control, "caption") end
function P.HM.GetSectionWidth() return 720 end
function P.HM.SetSectionCursor(frame, y) frame._msuf2CursorY = y end
function P.M.RegisterControlMetadata() end
function P.M.AddTooltip() end
function P.M.TrackRefresh() end
function P.S.Config() return { enabled = false } end
function P.S.Set() return true end
function P.Confirm(_, _, callback) callback() end
function P.MenuPopupPanel()
    local frame = Frame()
    frame:SetScript("OnShow", function(self)
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("GLOBAL_MOUSE_DOWN")
    end)
    frame:SetScript("OnHide", frame.UnregisterAllEvents)
    return frame
end
function P.W.Dropdown(parent)
    local frame = Frame(parent)
    frame.title = Frame(parent)
    function frame:SetOnValueChanged(callback) self.change = callback end
    function frame:SetValues(values) self.values = values end
    function frame:SetValue(value) self.value = value end
    return frame
end
-- Use the host's real section sizing and stub only the frame and scroll surface.
local function Noop() end
P.T.Font, P.T.ApplySurface = P.Text, Noop
P.W.RegisterSearchObject = Noop
P.W._Shared = { SetSearchTitle = Noop, SetSearchText = Noop }
local menu2 = { Theme = P.T, Widgets = P.W }
local function Require(name)
    assert(name == "MSUF_PixelLayoutRegion", name)
    return function(region) return region end
end
local pageBuilder = host .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets_PageBuilder.lua"
assert(loadfile(pageBuilder))("MidnightSimpleUnitFrames_Options", { MSUF2 = menu2, Require = Require })
P.W.RegisterGuidedRegion = Noop

local function Context()
    local ctx = { width = 720, wrapper = Frame(), viewportHeight = 520 }
    function ctx:SetContentHeight(height)
        self.wrapper:SetHeight(math.max(self.viewportHeight, height))
    end
    return ctx
end

local function CheckScroll(ctx, body)
    local bottom = -body.point[5] + body:GetHeight()
    local height = ctx.wrapper:GetHeight()
    assert(height >= bottom, "the host scroll range stops before the bottom of the macro page")
    local sectionGap = body._msuf2SectionFlowGap or 12
    assert(height == math.max(ctx.viewportHeight, bottom + 28 + sectionGap), "the host scroll range did not follow the current page height")
    return height
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
local ctx = Context()
P.registered.build(ctx)
local page = P.MacroPage
for _, tab in ipairs(page.tabs) do
    assert(page.ui.pools.button["tab:" .. tab[1]].isTab, "macro editor tab is missing its selection style")
end
assert(not page.ui.pools.button["quick:mouseover"].isTab, "quick start button was styled as a tab")
local defaultHeight = CheckScroll(ctx, page.ui.body)
assert(publications == 0 and page.ui.publish.enabled == false, "opening must not publish")
local arenaChoices = 0
for _, choice in ipairs(page.helpers.units) do
    if choice.value:match("^arena") then arenaChoices = arenaChoices + 1 end
end
assert(arenaChoices == (NS.Client.isForever and 0 or 3), "target choices follow arena client support")
page.ui.pools.button["quick:mouseover"].action()
assert(page.document.steps[1].branches[1].conditions[1].value == "mouseover", "mouseover quick start")
local templateHeight = CheckScroll(ctx, page.ui.body)
assert(templateHeight > defaultHeight, "a template with more rules grows the scroll range")
page.ui.pools.button["tab:raw"].action()
assert(CheckScroll(ctx, page.ui.body) < templateHeight, "switching to shorter code shrinks the scroll range")
page.ui.pools.button["tab:rules"].action()
assert(CheckScroll(ctx, page.ui.body) == templateHeight, "returning to rules restores the scroll range")
page.ui.pools.select.template.action("mouseover-mark")
assert(page.document.steps[1].raidMarker == 8, "combined mouseover heal and mark template")
page.ui.pools.button["new"].action()
page.document.name = "Builder"
page.document.steps[1].branches[1].value = "Kick"
page.Preview()
assert(page.compiled:find("/cast Kick", 1, true) and page.ui.publish.enabled, "live preview")
assert(page.ui.icon.texture.textureID == 135001, "typing a spell previews its icon by default")
assert(page.document.icon == page.AUTO_ICON and not page.ui.autoIcon.enabled, "new rules use WoW's automatic icon")
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
do
    local key = "step:1:branch:1"
    local secret = setmetatable({}, { __concat = function() error("secret target name was joined") end })
    local name, suffix, exists = "Forest Spider", nil, true
    local reads, publicationsBefore = 0, publications
    local isSecret = NS.IsSecret
    NS.IsSecret = function(value) return value == secret or isSecret(value) end
    local function ReadName(unit)
        assert(unit == "target", "reads the selected unit only")
        reads = reads + 1
        return name, suffix
    end
    UnitExists = function(unit) return unit == "target" and exists end
    UnitName = function(unit)
        assert(not NS.Client.isForever, "Forever captures the unmodified character name")
        return ReadName(unit)
    end
    UnitNameUnmodified = function(unit)
        assert(NS.Client.isForever, "Retail captures the character name and realm")
        return ReadName(unit)
    end
    Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }

    page.ui.pools.select["step:1:command"].action("targetexact")
    local selectTarget = page.ui.pools.select[key .. ":target"]
    local edit = page.ui.pools.edit[key .. ":target-name"]
    local capture = page.ui.pools.button[key .. ":use-current-target"]
    assert(selectTarget.values[1].text == "Target an exact name", "default exact target uses the name field")
    assert(edit and edit.shown and capture and capture.shown and capture.enabled, "named target controls are available")
    assert(reads == 0, "rendering the name field does not inspect the current target")
    edit:SetText("Wächterin, das Licht")
    edit.scripts.OnTextChanged(edit, true)
    assert(page.compiled:find("/targetexact Wächterin, das Licht", 1, true), "manual NPC name goes into the exact target command")
    CheckScroll(ctx, page.ui.body)

    combat = true
    capture.scripts.OnClick(capture)
    combat = false
    assert(reads == 0 and edit:GetText() == "Wächterin, das Licht", "combat capture has no reads or draft changes")
    capture.scripts.OnClick(capture)
    assert(edit:GetText() == "Forest Spider" and page.compiled:find("/targetexact Forest Spider", 1, true),
        "capture fills the editable name and preview")
    name = "Other Target"
    page.Render()
    assert(reads == 1 and edit:GetText() == "Forest Spider", "capture is a snapshot rather than a dynamic target")
    name, suffix = "Ásha", NS.Client.isForever and "Brightvale" or "Argent Dawn"
    capture.scripts.OnClick(capture)
    local fullName = NS.Client.isForever and "Ásha Brightvale" or "Ásha-ArgentDawn"
    assert(edit:GetText() == fullName and page.compiled:find("/targetexact " .. fullName, 1, true),
        "complete player name uses the client format")

    name, suffix = secret, nil
    capture.scripts.OnClick(capture)
    assert(edit:GetText() == fullName and page.message == "The current target's name is unavailable.",
        "a restricted name leaves the draft intact")
    name, suffix = "Ásha", secret
    capture.scripts.OnClick(capture)
    assert(edit:GetText() == fullName and page.message == "The current target's name is unavailable.",
        "a restricted surname or realm leaves the draft intact")
    name, suffix = "Guard; /cast Kick", nil
    capture.scripts.OnClick(capture)
    assert(edit:GetText() == fullName and page.message == "The current target's name is unavailable.",
        "unsafe macro punctuation leaves the draft intact")
    local readsBefore = reads
    exists = false
    capture.scripts.OnClick(capture)
    assert(reads == readsBefore and edit:GetText() == fullName and page.message == "No target",
        "no target leaves the draft intact")

    selectTarget.action("focus")
    assert(not edit.shown and not capture.shown and page.compiled:find("/targetexact [@focus] ", 1, true),
        "a legacy unit override keeps its behavior and does not offer a name capture")
    selectTarget.action("target")
    assert(edit.shown and edit:GetText() == fullName and publications == publicationsBefore,
        "switching back restores the editable name without publishing")
    NS.IsSecret = isSecret
end
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
C_Spell.GetSpellInfo = function(id) return { name = id == 2 and "Pet Bite" or "Heal", iconID = 135999 } end
C_Spell.GetSpellSubtext = function() return "Rank 1" end
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
local chooseIcon = page.ui.pools.button.icon
chooseIcon.scripts.OnClick(chooseIcon)
local iconRow = page.picker.rows[1]
iconRow.scripts.OnClick(iconRow)
assert(page.document.icon == 135999 and page.ui.autoIcon.enabled, "manual icon selection enables the spell-icon reset")
local action = page.ui.pools.edit["step:1:branch:1:action"]
action.action("Blind")
assert(page.ui.icon.texture.textureID == 135999, "editing the spell keeps the manually chosen icon")
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
local autoIcon = page.ui.autoIcon
autoIcon.scripts.OnClick(autoIcon)
assert(page.document.icon == page.AUTO_ICON and page.ui.icon.texture.textureID == 135002,
    "resetting the icon follows the current spell again")
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
ctx = Context()
P.registered.build(ctx)
assert(page.ui ~= previousUI, "opening page builds directly without an accordion")
local stackedHeight = CheckScroll(ctx, page.ui.body)
page.ui.body.width = 1400
page.ui.body.scripts.OnSizeChanged(page.ui.body, 1400)
assert(page.ui.width == 1400, "layout uses actual body width")
assert(page.ui.pools.label["result-title"].point[2] > 700, "wide layout places results on the right")
assert(CheckScroll(ctx, page.ui.body) < stackedHeight, "side-by-side layout shrinks the scroll range")
local scans, slotReads, cursorReads, clears = 0, 0, 0, 0
local entries = {
    { spellID = 10, itemType = 1, subName = "Rang 1" },
    { spellID = 11, itemType = 1, isOffSpec = true },
    { spellID = 12, itemType = 2 },
    { spellID = 13, itemType = 1, passive = true },
    { spellID = 14, itemType = 1, subName = "Rang 2" },
}
local spellName = "Überwältigender Zauber"
spellIcons[spellName] = 135000
Enum.SpellBookItemType = { Spell = 1, FutureSpell = 2 }
C_SpellBook.GetNumSpellBookSkillLines = function() scans = scans + 1 return 1 end
C_SpellBook.GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #entries } end
C_SpellBook.GetSpellBookItemInfo = function(slot) slotReads = slotReads + 1 return entries[slot] end
C_SpellBook.IsSpellBookItemPassive = function(slot) return entries[slot].passive == true end
C_SpellBook.FindSpellBookSlotForSpell = function(id)
    return id == 10 and 1 or id == 14 and 5 or nil, Enum.SpellBookSpellBank.Player
end
C_Spell.GetSpellInfo = function() return { name = spellName, iconID = 135000 } end
local held, heldID
GetCursorInfo = function() cursorReads = cursorReads + 1 return held, 1, "spell", heldID end
ClearCursor = function() clears, held, heldID = clears + 1, nil, nil end

NS.Client.isForever = false
local choose = assert(page.ui.pools.button["spellbook:choose"], "spellbook entry is visible in Builder")
local drop = assert(page.ui.pools.button["spellbook:drop"], "spellbook drop target is visible in Builder")
assert(scans == 0 and slotReads == 0, "page render does not read the spellbook")
choose.scripts.OnClick(choose)
local picker = page.picker
assert(scans == 1 and slotReads == #entries, "one spellbook pass per open")
assert(#picker.items == 1 and picker.createButtons[1]:IsShown(), "quick list filters to learned, active spells")
picker.search:SetText("No match")
picker.search.scripts.OnTextChanged()
assert(not picker.createButtons[1]:IsShown(), "filter also hides the row's create action")
picker.search:SetText("")
picker.search.scripts.OnTextChanged()
assert(scans == 1 and slotReads == #entries, "filtering never rereads the spellbook")

before = publications
local row = picker.rows[1]
row.scripts.OnClick(row)
assert(not picker:IsShown() and page.dirty and not page.bound and publications == before, "spell row opens an unsaved draft")
assert(page.document.name == "Überwältigender" and page.ui.icon.texture.textureID == 135000,
    "draft prefills a UTF-8-safe name and previews the spell icon")
assert(page.compiled:find("/cast " .. spellName, 1, true), "draft contains the localized cast")

choose.scripts.OnClick(choose)
local create = picker.createButtons[1]
local previousDocument = page.document
local confirm = P.Confirm
local pending
P.Confirm = function(_, _, apply) pending = apply end
create.scripts.OnClick(create)
assert(pending and page.document == previousDocument and publications == before, "one-click creation protects unsaved work")
pending()
P.Confirm = confirm
assert(publications == before + 1 and page.bound and page.pickupReady, "create action publishes one new macro")
assert(native[1].icon == page.AUTO_ICON and page.ui.icon.texture.textureID == 135000,
    "one-click creation keeps WoW's automatic icon with the spell shown in the preview")
assert(scans == 2 and slotReads == 2 * #entries, "reopen refreshes once and creation does not scan")

NS.Client.isForever = true
held, heldID = "item", 10
drop.scripts.OnReceiveDrag(drop)
assert(clears == 0 and cursorReads == 1 and page.bound, "drop leaves unsupported cursor payload alone")
held, heldID = "spell", 10
drop.scripts.OnReceiveDrag(drop)
assert(clears == 1 and not page.bound and publications == before + 1, "drop creates a draft without publishing")
assert(page.compiled:find("/cast " .. spellName .. "(Rang 1)", 1, true), "Forever drop uses the held spell ID and rank")
assert(page.ui.icon.texture.textureID == 135000, "the Forever rank suffix still resolves the spell icon")
local edit = page.ui.pools.edit["step:1:branch:1:action"]
page.ui.pools.select["step:1:branch:1:target"].action("focus")
held, heldID = "spell", 14
edit.scripts.OnReceiveDrag(edit)
assert(page.compiled:find("/cast [@focus] " .. spellName .. "(Rang 2)", 1, true), "field drop only changes that rule's spell")
assert(scans == 2 and slotReads == 2 * #entries + 2 and cursorReads == 3 and clears == 2,
    "each accepted drop resolves only its one spell")
page.ui.pools.select["step:1:command"].action("use")
assert(not edit.scripts.OnReceiveDrag, "a recycled field for an item does not accept spells")

choose.scripts.OnClick(choose)
assert(#picker.items == 3 and scans == 3, "Forever suggestions offer the unranked spell and both learned ranks")
body = page.ui.body
before, slotReads = publications, 0
combat = true
local filtered, beforeTextures = picker.filtered, textureReads
page.Preview()
create.scripts.OnClick(create)
picker.search.scripts.OnTextChanged()
assert(picker.filtered == filtered, "combat does not run the filter")
choose.scripts.OnClick(choose)
drop.scripts.OnReceiveDrag(drop)
body.scripts.OnEvent(body, "PLAYER_REGEN_DISABLED")
assert(not picker:IsShown() and not rawget(picker, "pick") and not rawget(picker, "create") and not drop:IsVisible(),
    "combat hides picker and drop target")
assert(not next(body.events) and not next(picker.events), "combat leaves no subscribed builder or picker events")
assert(scans == 3 and slotReads == 0 and cursorReads == 3 and publications == before and textureReads == beforeTextures,
    "combat skips all spell reads and publication")
assert(not picker.scripts.OnUpdate and not drop.scripts.OnUpdate, "no picker or drop ticker")

-- Rank selection reads known ranks on demand and preserves native macro syntax.
combat = false
P.registered.build(Context())
entries[2].subName, entries[3].subName, entries[4].subName = "Rang 3", "Rang 4", "Rang 5"
entries[#entries + 1] = { spellID = 15, itemType = 1, subName = "Rang 10" }
entries[#entries + 1] = { spellID = 16, itemType = 1, subName = "Rang 1" }
entries[#entries + 1] = { spellID = 17, itemType = 1 }
local petEntries = {
    { spellID = 20, itemType = 1, subName = "Rang 1" },
    { spellID = 21, itemType = 1, subName = "Rang 2" },
    { spellID = 22, itemType = 2, subName = "Rang 3" },
}
C_SpellBook.GetSpellBookItemInfo = function(slot, bank)
    slotReads = slotReads + 1
    return (bank == 2 and petEntries or entries)[slot]
end
C_SpellBook.IsSpellBookItemPassive = function(slot, bank)
    return (bank == 2 and petEntries or entries)[slot].passive == true
end
C_SpellBook.HasPetSpells = function() return #petEntries end
C_Spell.GetSpellInfo = function(id)
    if id == 999 then return nil end
    return { name = id >= 20 and "Pet Bite" or id == 16 and "Other Spell" or id == 17 and "Teleport" or spellName,
        iconID = 135000 }
end
C_Spell.GetSpellSubtext = function() return "" end
page.document = NS.Macros.Model.New("focus")
page.document.icon = 135999
local beforeScans = scans
page.Render()
assert(scans == beforeScans, "rank buttons do not scan the book during rendering")
edit = page.ui.pools.edit["step:1:branch:1:action"]
edit.action(" !" .. spellName:lower() .. " (rang 1) ")
local rankButton = assert(page.ui.pools.button["step:1:branch:1:rank"], "Forever exposes a spell rank button")
rankButton.scripts.OnClick(rankButton)
assert(scans == beforeScans + 1 and #picker.items == 4,
    "rank picker includes automatic and three learned ranks only")
assert(picker.items[1].value == "!" .. spellName and picker.items[1].name == "Highest rank (automatic)",
    "automatic rank is explicit and preserves the non-toggle prefix")
assert(picker.items[2].value == "!" .. spellName .. "(Rang 1)" and picker.items[4].value:find("Rang 10", 1, true),
    "rank order follows the native spellbook")
local readsBeforeFilter = slotReads
picker.search:SetText("Rang 2")
picker.search.scripts.OnTextChanged()
assert(#picker.filtered == 1 and slotReads == readsBeforeFilter, "rank filtering uses the existing snapshot")
picker.rows[1].scripts.OnClick(picker.rows[1])
local ranked = "!" .. spellName .. "(Rang 2)"
assert(page.document.steps[1].branches[1].value == ranked and page.compiled:find(ranked, 1, true),
    "selected rank reaches the native macro preview")
assert(page.document.icon == 135999 and publications == before, "rank selection changes neither icon nor published macro")
assert(page.compiled:find("[@focus,harm,nodead][harm,nodead]", 1, true), "rank change preserves inherited rules")
local rankID = NS.Macros.Store.Save(page.document)
page.document = NS.Macros.Store.Get(rankID)
page.Render()
assert(page.document.steps[1].branches[1].value == ranked, "rank survives the draft persistence boundary")
rankButton = page.ui.pools.button["step:1:branch:1:rank"]
rankButton.scripts.OnClick(rankButton)
picker.rows[1].scripts.OnClick(picker.rows[1])
assert(page.document.steps[1].branches[1].value == "!" .. spellName, "automatic removes only the explicit rank")

edit = page.ui.pools.edit["step:1:branch:1:action"]
edit.action("14")
rankButton.scripts.OnClick(rankButton)
assert(#picker.items == 4 and picker.items[1].value == spellName, "numeric spell IDs resolve the rank family")
local staleRank = picker.pick
page.document = NS.Macros.Model.New("sequence")
page.document.steps[1].sequence = { spellName, "item:5512" }
page.Render()
staleRank(ranked)
assert(page.document.steps[1].sequence[1] == spellName, "rank selection cannot edit a replacement document")
rankButton = assert(page.ui.pools.button["step:1:sequence:1:rank"], "sequence entries expose rank selection")
rankButton.scripts.OnClick(rankButton)
picker.rows[3].scripts.OnClick(picker.rows[3])
assert(page.compiled:find(spellName .. "(Rang 2),item:5512", 1, true), "sequence preserves chosen rank and following item")
local itemRank = page.ui.pools.button["step:1:sequence:2:rank"]
itemRank.scripts.OnClick(itemRank)
assert(not picker:IsShown() and page.message == "No learned ranks found for this spell",
    "item entries do not offer unrelated spell ranks")
assert(page.document.steps[1].sequence[2] == "item:5512", "failed rank lookup preserves the item")

page.document.steps = { NS.Macros.Model.NewStep("petautocasttoggle") }
page.document.steps[1].branches[1].value = "Pet Bite"
page.Render()
beforeScans = scans
rankButton = page.ui.pools.button["step:1:branch:1:rank"]
rankButton.scripts.OnClick(rankButton)
assert(scans == beforeScans and #picker.items == 3, "pet ranks use the pet bank and reject future spells")
picker.rows[3].scripts.OnClick(picker.rows[3])
assert(page.compiled:find("/petautocasttoggle Pet Bite(Rang 2)", 1, true), "pet autocast retains its selected rank")

page.document.steps = { NS.Macros.Model.NewStep("cast") }
page.document.steps[1].branches[1].value = "Teleport"
page.Render()
rankButton = page.ui.pools.button["step:1:branch:1:rank"]
rankButton.scripts.OnClick(rankButton)
assert(not picker:IsShown() and page.message == "No learned ranks found for this spell",
    "unranked spells do not acquire a fabricated rank")
local secret = {}
local originalPublic = NS.Public
NS.Public = function(value) return value ~= secret end
entries[1].subName, entries[5].subName = secret, secret
edit = page.ui.pools.edit["step:1:branch:1:action"]
edit.action(spellName)
rankButton.scripts.OnClick(rankButton)
assert(#picker.items == 2 and picker.items[2].value:find("Rang 10", 1, true), "secret rank text is ignored")
NS.Public = originalPublic
entries[1].subName, entries[5].subName = "Rang 1", "Rang 2"

NS.Client.isForever = false
page.Render()
assert(not rankButton:IsShown(), "Retail does not expose legacy spell rank controls")
assert(not page.ui.pools.toggle["highest-rank"]:IsShown(), "Retail does not expose automatic ranks")
beforeScans, readsBeforeFilter = scans, slotReads
page.PickRank(page.ui.body, "spell", spellName, function() error("Retail rank callback") end)
assert(scans == beforeScans and slotReads == readsBeforeFilter, "Retail rank action never reads legacy rank data")
NS.Client.isForever = true
page.Render()
rankButton.scripts.OnClick(rankButton)
staleRank = picker.pick
combat = true
beforeScans, readsBeforeFilter = scans, slotReads
page.PickRank(rankButton, "spell", spellName, function() error("combat rank callback") end)
staleRank(ranked)
assert(scans == beforeScans and slotReads == readsBeforeFilter
    and page.document.steps[1].branches[1].value == spellName, "combat blocks rank lookup and stale selection")
-- Run the same builder action for a new macro, an existing macro and MMO inputs.
combat = false
local bindingContext = Context()
P.registered.build(bindingContext)
local rankedHeal = "Heal(Rank 1)"
C_Spell.GetSpellInfo = function(value)
    if value == rankedHeal then return { name = "Heal", spellID = 2054 } end
end
C_Spell.GetSpellSubtext = function() return "Rank 1" end
page.helpers.New("spell", function(doc)
    doc.name, doc.steps[1].branches[1].value = "Ranked Heal", rankedHeal
end)
local automaticRank = assert(page.ui.pools.toggle["highest-rank"])
assert(automaticRank:IsShown() and not automaticRank.checked, "new macros start with automatic rank off")
assert(automaticRank.caption.text == "Auto Rank Up" and automaticRank.point[5] > page.ui.publish.point[3],
    "Auto Rank Up must be a visible checkbox above the WoW macro action")
automaticRank.scripts.OnClick(automaticRank)
assert(automaticRank.checked and page.compiled:find("/cast Heal\n?$") and page.dirty,
    "automatic rank did not update the preview")
page.ui.pools.button["tab:raw"].action()
assert(page.document.raw:find(rankedHeal, 1, true) and page.compiled:find("/cast Heal\n?$"),
    "the Code tab lost the original rank or stopped applying the toggle")
automaticRank.scripts.OnClick(automaticRank)
assert(page.compiled == page.document.raw, "turning off automatic ranks did not restore the original code")
automaticRank.scripts.OnClick(automaticRank)
page.ui.pools.button["save-draft"].action()
local rankedDraft = page.id
page.helpers.New("spell")
assert(not automaticRank.checked, "new macro inherited another macro's toggle")
page.Load(rankedDraft)
assert(automaticRank.checked and page.document.highestRank, "the toggle did not survive a draft round trip")
page.ui.publish.scripts.OnClick(page.ui.publish)
local changedTarget = { name = page.document.name, scope = page.document.scope, body = "/cast Heal(Rank 2)" }
local macroStore = NS.Macros.Store
macroStore.PrepareUpdate = function(id)
    assert(id == rankedDraft, "update requested the wrong draft")
    return changedTarget, nil, true
end
local savedPublish, showConfirmation = macroStore.Publish, P.Confirm
local approveUpdate, updatePrompt, approvedTarget
P.Confirm = function(_, prompt, approve) updatePrompt, approveUpdate = prompt, approve end
macroStore.Publish = function(id, replace, target)
    assert(replace and id == rankedDraft, "confirmation did not perform an in-place update")
    approvedTarget = target
    return savedPublish(id)
end
page.ui.publish.scripts.OnClick(page.ui.publish)
assert(approveUpdate and updatePrompt:find(changedTarget.name, 1, true) and not approvedTarget,
    "the existing changed macro must be named and confirmed before updating")
approveUpdate()
assert(approvedTarget == changedTarget, "update did not use the confirmed snapshot")
page.ui.publish.scripts.OnClick(page.ui.publish)
local staleUpdate = approveUpdate
P.Confirm = showConfirmation
macroStore.Publish = savedPublish
page.helpers.New("mouseover", function(doc)
    doc.name, doc.steps[1].branches[1].value = "Click Heal", "Heal"
end)
local priorPublications = publications
staleUpdate()
assert(publications == priorPublications, "an old update dialog published a different draft")
local function BeginBinding(isKey)
    local button = assert(isKey and page.ui.bindKey or page.ui.bindClick, "missing binding control in the macro builder")
    assert(button.enabled and button:IsVisible(), "a valid macro cannot be bound")
    button.scripts.OnClick(button, "LeftButton")
    assert(button.keyboard and button.clicks == (isKey and "LeftButtonUp" or "AnyUp"), "wrong capture mode")
    return button
end
local beforeBinding = publications
local callback, confirmationText
P.Confirm = function(_, text, accept) confirmationText, callback = text, accept end
local bindingButton = BeginBinding()
bindingButton.scripts.OnClick(bindingButton, "RightButton")
assert(publications == beforeBinding and not appliedBinding and not callback and page.message:find("Hold Shift", 1, true))
assert(bindingButton.keyboard and bindingButton.clicks == "AnyUp", "a plain click ended mouse capture")
bindingButton.scripts.OnClick(bindingButton, "LeftButton")
assert(publications == beforeBinding and not appliedBinding, "plain left click was saved")
heldModifiers = 3
bindingButton.scripts.OnClick(bindingButton, "RightButton")
heldModifiers = nil
assert(publications == beforeBinding + 1 and page.pickupReady, "binding did not create the WoW macro")
assert(appliedBinding.input.button == "RightButton" and appliedBinding.entry.name == "Click Heal")
assert(not bindingButton.keyboard and bindingButton.clicks == "LeftButtonUp", "capture was left active")

bindingButton = BeginBinding()
bindingButton.scripts.OnClick(bindingButton, "Button12")
assert(appliedBinding.input.button == "Button12" and publications == beforeBinding + 1)
assert(page.ui.restoreClicks.enabled, "published macro has no recovery action")
page.ui.restoreClicks.action()
assert(restored.entry == native[1] and restored.reserved == true, "recovery must only remove reserved clicks")
bindingButton = BeginBinding(true)
bindingButton.scripts.OnKeyDown(bindingButton, "LSHIFT")
assert(appliedBinding.input.button == "Button12" and bindingButton.keyboard, "Shift alone was bound")
bindingButton.scripts.OnKeyDown(bindingButton, "F11")
assert(appliedBinding.input.key == "F11" and publications == beforeBinding + 1)

bindingButton = BeginBinding()
bindingButton.scripts.OnKeyDown(bindingButton, "F11")
assert(appliedBinding.input.key == "F11" and bindingButton.keyboard, "keyboard input entered click casting")
heldModifiers = 3
assert(bindingButton.scripts.OnMouseDown, "modifier state is not captured when the mouse is pressed")
bindingButton.scripts.OnMouseDown(bindingButton, "LeftButton")
heldModifiers = nil
bindingButton.scripts.OnClick(bindingButton, "LeftButton")
assert(appliedBinding.input.button == "LeftButton" and appliedBinding.input.modifiers == 3)

heldModifiers = 12
bindingButton.scripts.OnMouseDown(bindingButton, "LeftButton")
heldModifiers = nil
bindingButton.scripts.OnClick(bindingButton, "LeftButton")
assert(appliedBinding.input.button == "LeftButton" and appliedBinding.input.modifiers == 12 and not bindingButton.keyboard,
    "a modified click directly on the binding button did not bind")

bindingButton = BeginBinding(true)
bindingButton.scripts.OnClick(bindingButton, "LeftButton")
assert(appliedBinding.input.modifiers == 12 and not bindingButton.keyboard, "a mouse click entered keyboard bindings")

local applied = appliedBinding
bindingButton = BeginBinding()
bindingButton.scripts.OnKeyDown(bindingButton, "ESCAPE")
assert(appliedBinding == applied and not bindingButton.keyboard, "escape committed a binding")

occupiedBinding = true
bindingButton = BeginBinding()
bindingButton.scripts.OnClick(bindingButton, "MiddleButton")
assert(appliedBinding == applied and confirmationText:find("MiddleButton", 1, true), "existing binding was overwritten without confirmation")
bindingChanged = true
callback()
assert(appliedBinding == applied, "stale confirmation overwrote the new binding")
bindingChanged = false
P.Confirm = function(_, _, accept) accept() end

page.ui.pools.button["tab:library"].action()
page.ui.pools.button["library:native:1:delete"].action()
assert(deleted and not native[1] and not page.bound, "WoW macro deletion did not reach the store")
page.ui.pools.button["tab:rules"].action()
bindingButton = BeginBinding()
page.ui.body.scripts.OnEvent(page.ui.body, "PLAYER_REGEN_DISABLED")
assert(appliedBinding == applied and not bindingButton.keyboard, "combat entry left capture active")
print("suite_macros_menu_contract: passed")
