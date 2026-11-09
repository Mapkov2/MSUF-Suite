local root = assert(arg[1])
local path = root .. "/MSUF_Suite_CharacterPanel/"
local writes, frames, modelReads = 0, 0, 0
local fontPath, modelReady = "First.ttf", false
local skinEnabled, skinRefreshes, releases = true, 0, 0
local openingWatches = 0
local modelWindow
local cursorX, cursorY, mouseDown = 320, 260, true
local function Write() writes = writes + 1 end
local methods = {
    SetPoint = function(self, ...) self.point = { ... } Write() end,
    GetPoint = function(self) return unpack(self.point or {}) end,
    ClearAllPoints = function(self) self.point = nil Write() end,
    SetHeight = Write, SetWidth = Write,
    SetSize = function(self, width, height) self.width, self.height = width, height Write() end,
    GetWidth = function(self) return self.width end,
    GetHeight = function(self) return self.height end,
    SetJustifyH = Write, SetWordWrap = Write, SetTexCoord = Write, SetAllPoints = Write,
    SetFrameStrata = Write, SetClampedToScreen = Write, SetMovable = Write,
    SetScale = function(self, scale) self.scale = scale Write() end,
    GetEffectiveScale = function(self) return self.scale or 1 end,
    GetLeft = function() return 100 end, GetTop = function() return 700 end,
    RegisterForDrag = Write, RegisterForClicks = Write, SetTexture = Write, EnableMouse = Write,
    EnableMouseWheel = Write, SetAtlas = Write, SetScrollChild = Write, ClearModel = Write,
    SetRotation = function(self, angle) self.angle = angle Write() end,
    SetPortraitZoom = function(self, zoom) self.zoom = zoom Write() end,
    SetColorTexture = function(self, ...) self.color = { ... } Write() end,
    SetTextColor = function(self, ...) self.color = { ... } Write() end,
    SetScript = function(self, event, handler) self.scripts[event] = handler end,
    HookScript = function(self, event, handler)
        local original = self.scripts[event]
        self.scripts[event] = function(...)
            if original then original(...) end
            handler(...)
        end
    end,
    SetUnit = function(self)
        assert(modelWindow:IsShown() and self:IsShown(), "model was bound before its window and region were shown")
        modelReads = modelReads + 1
        return modelReady
    end,
    RefreshUnit = Write,
    SetShown = function(self, value)
        if self.shown and not value and self.scripts.OnHide then self.scripts.OnHide(self) end
        self.shown = value
        Write()
    end,
    IsShown = function(self) return self.shown == true end,
    Hide = function(self) self:SetShown(false) end,
    Show = function(self) self:SetShown(true) end,
    SetText = function(self, value) assert(self.fontPath, "font before text") self.text = value Write() end,
    GetUnboundedStringWidth = function(self) return #self.text * 6 end,
    GetVerticalScroll = function(self) return self.offset or 0 end,
    SetVerticalScroll = function(self, offset)
        self.offset = offset
        Write()
        local hook = self.scripts.OnVerticalScroll
        if hook then hook(self, offset) end
    end,
}
local function Create(kind, _, parent)
    frames = frames + 1
    return setmetatable({ kind = kind, scripts = {}, parent = parent }, { __index = methods })
end
CreateFrame = Create
methods.CreateTexture = function() return Create("Texture") end
methods.CreateFontString = function() return Create("FontString") end
function wipe(values) for key in pairs(values) do values[key] = nil end end
UIParent = { GetWidth = function() return 1600 end, GetHeight = function() return 900 end,
    GetEffectiveScale = function() return 1 end, GetRect = function() return 0, 0, 1600, 900 end }
GameTooltip = { IsOwned = function() return false end }
function GetCursorPosition() return cursorX, cursorY end
function IsMouseButtonDown() return mouseDown end
SetPortraitTexture = Write
ITEM_QUALITY_COLORS = { [2] = { r = 0, g = 1, b = 0 } }
local menu, chosenTab
local suite = {
    ContextMenu = function(anchor, generate, ...)
        menu = {}
        generate(anchor, {
            CreateRadio = function(_, label, selected, pick, data)
                menu[#menu + 1] = { label = label, selected = selected, pick = pick, data = data }
            end,
        }, ...)
    end,
    CreateFrame = Create,
    CreateTexture = function() return Create("Texture") end,
    CreateFontString = function() return Create("FontString") end,
    SetFont = function(font, path) font.fontPath = path or fontPath Write() end,
    GlobalFontPath = function() return fontPath end,
    FontRevision = 0,
}
MSUFSuite = { Suite = suite }
local ns = { Text = function(value) return value end, Number = tonumber, Suite = suite, Client = {},
    Host = { InCombat = function() return false end } }
local function Noop() end
local build = setmetatable({}, { __index = function() return function() return {} end end })
ns.CatalogBuild = { ForAddon = function() return build end }
ns.ResolveFont = function(key) return key == "Alternate" and "Alternate.ttf" or nil end
assert(loadfile(root .. "/MSUF_Suite/Core/CharacterTabs.lua"))("MSUF_Suite", ns)
ns.Host.CharacterTabs = ns.CharacterTabs
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/CharacterPanel.lua"))("MSUF_Suite", ns)
assert(loadfile(root .. "/MSUF_Suite/Core/CharacterHeader.lua"))("MSUF_Suite", ns)
for _, file in ipairs({ "ModelControls", "WindowControls", "TabOverflow", "GroupLayout", "View" }) do
    assert(loadfile(path .. file .. ".lua"))("MSUF_Suite_CharacterPanel", ns)
end
local minimizedCount = 0
local view = ns.View.New({
    tab = function(id) chosenTab = id end, slot = Noop, close = Noop, enter = Noop,
    leave = Noop, drag = Noop, drop = Noop, group = Noop,
    minimized = function() minimizedCount = minimizedCount + 1 end,
})
modelWindow = view.frame
local tabs = { { id = "overview", label = "Overview" } }
local item = { { slot = 1, label = "Head", name = "Helm", icon = 42, quality = 2, level = 19 } }
local groups = { { title = "Quick", rows = { { label = "Health", value = 1000 } } } }
local empty = {}
view:SetHeader("Name", "Level 22", "19", "player", "guid")
view:SetTabs(tabs, "overview")
view:ShowGear(item, empty, empty, groups, nil, empty, true)
assert(modelReads == 0, "closed window tried to bind a model")
view.frame:SetShown(true)
view:RefreshModel()
assert(modelReads == 1 and not view.model.shown, "unavailable model did not leave a retryable state")
modelReady = true
view:RefreshModel()
assert(modelReads == 2 and view.model.shown, "model-ready retry did not paint the same unit")
local model = view.model
model.scripts.OnMouseWheel(model, 2)
assert(model.zoom == .3, "mouse wheel did not zoom")
model.scripts.OnMouseDown(model, "LeftButton")
assert(model.scripts.OnUpdate, "model drag did not start")
local atRest = writes
model.scripts.OnUpdate(model)
assert(writes == atRest, "stationary cursor rewrote the pose")
cursorX = cursorX + 25
model.scripts.OnUpdate(model)
assert(model.angle == .25, "model drag did not rotate")
model.scripts.OnHide(model)
assert(not model.scripts.OnUpdate, "hidden model kept polling")
view:RefreshModel()
assert(modelReads == 3 and model.angle == .25 and model.zoom == .3, "same GUID did not recover its pose")
view:SetHeader("Other", "Level 22", "19", "target", "other")
view:ShowGear(item, empty, empty, groups, nil, empty, true)
assert(modelReads == 4 and model.angle == 0 and model.zoom == 0, "different character inherited the camera")

local preferences, window = {}, view.window
view:ApplyWindowPreferences(preferences)
local grip = window.grip
grip.scripts.OnMouseDown(grip, "LeftButton")
assert(grip.scripts.OnUpdate, "scale grip did not start")
atRest = writes
grip.scripts.OnUpdate(grip)
assert(writes == atRest, "stationary scale grip rewrote window geometry")
cursorX = cursorX + 90
grip.scripts.OnUpdate(grip)
local scaled = view.frame.scale
assert(scaled > 1 and view.frame.point[1] == "TOPLEFT", "scaling did not keep the top left")
grip.scripts.OnMouseUp(grip, "LeftButton")
assert(preferences.scale == scaled and not grip.scripts.OnUpdate, "scale was not saved and polling did not stop")
window.maximize.scripts.OnClick(window.maximize)
assert(view.frame.scale > scaled and view.frame.point[1] == "CENTER" and not grip.shown)
window.maximize.scripts.OnClick(window.maximize)
assert(view.frame.scale == scaled and view.frame.point[1] == "TOPLEFT" and grip.shown)
ns.Window.Dock(window, "right")
assert(preferences.dock == "right" and view.frame.point[1] == "TOPRIGHT")
window.minimize.scripts.OnClick(window.minimize)
assert(view:IsMinimized() and not view.body.shown and not grip.shown and view.frame.height < window.height)
window.minimize.scripts.OnClick(window.minimize)
assert(not view:IsMinimized() and view.body.shown and grip.shown and view.frame.height == window.height)
assert(minimizedCount == 2 and view.frame.point[1] == "TOPRIGHT", "restore lost its dock or lifecycle callback")
grip.scripts.OnMouseDown(grip, "LeftButton")
cursorX = cursorX + 100
grip.scripts.OnUpdate(grip)
assert(view.frame.scale == scaled, "right-docked grip responded to movement along its fixed edge")
cursorY = cursorY - 40
grip.scripts.OnUpdate(grip)
assert(view.frame.scale > scaled and view.frame.point[1] == "TOPRIGHT", "right-docked grip did not follow vertically")
local newPreferences = { scale = .8, dock = "left" }
view:ApplyWindowPreferences(newPreferences)
assert(not grip.scripts.OnUpdate and preferences.scale > scaled, "profile switch lost the departing gesture")
assert(view.frame.scale == .8 and view.frame.point[1] == "TOPLEFT", "new profile did not own the window")
grip.scripts.OnMouseDown(grip, "LeftButton")
view:CancelWindowGestures()
assert(not grip.scripts.OnUpdate, "closing did not cancel active resizing")

local name = view.header.buttons.name.text
local fallback = name.color[1]
local outline = view.surfaces[view.frame].border
local hover = view.surfaces[view.left[1]].hover
local color = .31
local skin = {
    IsEnabled = function() return skinEnabled end,
    GetColor = function() return color, .42, .53, 1 end,
    RegisterMenu = function(_, frame, contentOnly)
        assert(frame == view.frame and contentOnly, "opening motion discovered child controls")
        openingWatches = openingWatches + 1
    end,
    SkinFrame = function(_, frame, style) frame.skinRole = style.role return true, "applied" end,
    SetActive = Noop,
    RefreshAll = function() skinRefreshes = skinRefreshes + 1 end,
    ReleaseAll = function() releases = releases + 1 end,
}
view:RefreshAppearance(skin)
assert(view.frame.skinRole == "shell" and outline.shown == false and name.color[1] == .31, "theme not applied")
assert(hover.shown == false, "authored hover masked the active skin hover")
assert(openingWatches == 1, "the window did not claim the shared opening fade")
assert(view.left[1].level.color[2] == 1, "theme replaced item-quality color")
fontPath, suite.FontRevision, color = "Second.ttf", 1, .49
view:RefreshAppearance(skin)
assert(name.fontPath == fontPath and view.rail.cards[1].rows[1].right.fontPath == fontPath, "global font stale")
assert(skinRefreshes == 1 and name.color[1] == .49, "live style did not refresh")
assert(openingWatches == 1, "an appearance change duplicated the opening watch")
local beforeFrames, beforeWrites = frames, writes
for i = 1, 50 do view:ShowGear(item, empty, empty, groups, nil, empty, true) end
assert(frames == beforeFrames and writes == beforeWrites, "unchanged gear paint allocated or wrote widget state")
local movement = { label = "Movement Speed", value = "170%" }
groups[1].rows[2] = movement
local originalHeight = view.rail.content
view:RefreshInspectSummary(groups, true)
local speedRow = view.rail.cards[1].rows[2]
assert(speedRow.shown and speedRow.left.text == movement.label and speedRow.right.text == movement.value
    and speedRow.right.fontPath == fontPath and view.rail.content > originalHeight,
    "new movement speed row was not laid out with the global font")
beforeFrames, beforeWrites = frames, writes
local previousModelReads = modelReads
item[1].name = "Unpainted gear"
movement.value = "200%"
view:RefreshInspectSummary(groups, false)
assert(speedRow.right.text == "200%" and view.left[1].name.text == "Helm"
    and modelReads == previousModelReads and frames == beforeFrames and writes == beforeWrites + 1,
    "value-only Inspect update touched more than the changed text")
item[1].name = "Helm"
beforeWrites = writes
for i = 1, 50 do view:RefreshInspectSummary(groups, false) end
assert(frames == beforeFrames and writes == beforeWrites, "unchanged Inspect summary allocated or rewrote widgets")
groups[1].rows[2] = nil
view:RefreshInspectSummary(groups, true)
assert(not speedRow.shown and view.rail.content == originalHeight, "removed speed row left a gap")
groups[1].rows[2] = movement
view:RefreshInspectSummary(groups, true)
assert(speedRow.shown and view.rail.cards[1].rows[2] == speedRow and frames == beforeFrames,
    "returning movement speed allocated a new row")
groups[1].rows[2] = nil
view:RefreshInspectSummary(groups, true)
skinEnabled = false
view:RefreshAppearance(skin)
assert(releases == 1 and outline.shown and hover.shown and name.color[1] == fallback,
    "disabled skin did not restore panel defaults")
assert(name.fontPath == fontPath, "skin fallback changed the global font")
skinEnabled = true
view:RefreshAppearance(skin)
assert(openingWatches == 2, "re-enabled skin did not restore opening motion")
local data = { level = 22, class = "Priest", specialization = "Holy", guild = "Guild", zone = "Zone" }
local fields = view.header.buttons
view:ApplyHeaderSettings({
    headerPortraitVisible = false, headerNameFont = "Alternate", headerNameSize = 28, headerNameColor = "ff5500",
    headerGuildVisible = true, headerZoneVisible = true, headerOrder = "zone,guild",
})
view:SetHeader("Mapko", nil, "19", "player", "guid", data)
assert(not fields.portrait.shown and name.fontPath == "Alternate.ttf" and name.fontSize == 28)
assert(name.color[1] == 1 and name.color[2] == 85 / 255, "explicit text color lost to skin")
assert(fields.zone.shown and fields.guild.shown and fields.zone.x < fields.guild.x, "header field order not applied")
assert(fields.level.text.text == "Level 22", "header rendered an unlabelled level")
beforeWrites = writes
view:SetHeader("Mapko", nil, "19", "player", "guid", data)
assert(writes == beforeWrites, "unchanged header wrote widget state")
local order = suite.CharacterHeader.Order({ tabOrder = "bad,pvp,stats,gear,pvp" }, "tab")
assert(#order == 7 and order[1].id == "pvp" and order[2].id == "gear" and order[3].id == "overview")

local header = suite.CharacterHeader
local layout = { headerGuildVisible = true, headerZoneVisible = true }
view:ApplyHeaderSettings(layout)
for _, field in ipairs(header.Fields) do
    layout[field.prefix .. "X"], layout[field.prefix .. "Y"] = 6, -5
end
view:ApplyHeaderSettings(layout)
for _, field in ipairs(header.Fields) do
    local region = fields[field.id]
    assert(region.shown and region.x == region.baseX + 6 and region.y == region.baseY + 5, field.id .. " did not move")
    local dx, dy = header.DragOffsets(view.header, field.id, 3000, 3000)
    assert(region.baseX + dx + region.width <= header.PreviewWidth and region.baseY - dy == 0,
        field.id .. " could overlap the window controls")
end
assert(fields.name.width == #"Mapko" * 6, "the name hit area extended beyond its text")
local preview = header.Create(view.frame)
local previewConfig = { headerGuildVisible = false, headerNameX = 6, headerNameY = -5 }
preview:Render(previewConfig, data, skin, header.PreviewWidth, 0)
local nameX = preview.buttons.name.x
assert(not preview.buttons.guild.shown)
preview:Render(previewConfig, data, skin, header.PreviewWidth, 0, { guild = true, portrait = false })
assert(preview.buttons.guild.shown and not preview.buttons.portrait.shown and preview.buttons.name.x == nameX)
assert(previewConfig.headerGuildVisible == false, "preview layer enabled a live field")
local manyTabs = {}
for i = 1, 12 do
    manyTabs[i] = { id = "custom" .. i, label = "A long custom character tab " .. i, custom = true, x = 48, y = -8 }
end
manyTabs[1].x, manyTabs[1].y = -48, 8
view.frame:SetShown(true)
view:SetTabs(manyTabs, "custom12")
assert(view.visibleTabs < #manyTabs and view.moreTab:IsShown() and view.moreTab.selected,
    "overflow did not preserve the active hidden tab")
assert(not view.tabButtons[view.visibleTabs + 1]:IsShown() and view.tabButtons[1].width >= 100,
    "tab overflow squeezed or left hidden tabs visible")
local firstTab, secondTab, lastVisible = view.tabButtons[1], view.tabButtons[2], view.tabButtons[view.visibleTabs]
assert(firstTab.panelX == 12 and firstTab.panelY == 0 and secondTab.panelY == 16
    and secondTab.panelX == 12 + firstTab.naturalWidth + 96, "positioned tabs lost their signed logical anchors")
assert(lastVisible.panelX + lastVisible.panelWidth <= view.moreTab.panelX,
    "the shifted last visible tab covered the overflow control")
beforeWrites = writes
view:SetTabs(manyTabs, "custom12")
assert(writes == beforeWrites, "unchanged positioned tab layout wrote widgets")
view.moreTab.scripts.OnClick(view.moreTab)
assert(#menu == #manyTabs - view.visibleTabs and menu[#menu].selected(menu[#menu].data),
    "More did not list the hidden tabs in order")
menu[1].pick(menu[1].data)
assert(chosenTab == manyTabs[view.visibleTabs + 1].id, "More selected the wrong tab")
view:SetTabs(tabs, "overview")
assert(not view.moreTab:IsShown() and view.visibleTabs == 1, "More remained after tabs fit again")
assert(view.tabButtons[1].panelX == 12 and view.tabButtons[1].panelY == 0 and view.tabButtons[1].panelHeight == 39,
    "returning to stock tabs retained custom displacement or gutters")
chosenTab = nil
menu[1].pick(menu[1].data)
assert(not chosenTab, "a stale overflow entry selected a removed tab")

local shiftedGroups = {
    { title = "Below grid", layout = { x = -48, y = -24, rowUp = 0, rowDown = 10 },
        rows = { { label = "Below card", value = 100, layout = { x = -32, y = -10 } } } },
    { title = "Other column", layout = { x = 48, y = 0, rowUp = 0, rowDown = 0 }, rows = {} },
    { title = "Above grid", layout = { x = 0, y = 24, rowUp = 10, rowDown = 0 },
        rows = { { label = "Above row", value = 200, layout = { x = 32, y = 10 } } } },
}
view:ShowGroups(shiftedGroups)
local report = view.report
assert(report.cards[1].panelX == 0 and report.cards[1].panelY == 58, "card offsets did not use their own grid origin")
assert(report.cards[1].rows[1].panelX == 0 and report.cards[1].rows[1].panelY == 40,
    "row offsets did not use their shifted card origin")
assert(report.cards[3].rows[1].panelX == 64 and report.cards[3].rows[1].panelY == 20,
    "opposite row offsets did not preserve the full signed range")
assert(report.cards[2].panelX + report.cards[2].panelWidth == report.width,
    "a maximum outward card shift exceeded the scroll canvas")
beforeWrites = writes
view:ShowGroups(shiftedGroups)
assert(writes == beforeWrites, "unchanged positioned content wrote widgets")

local function FindCard(title)
    for _, card in ipairs(report.cards) do
        if card:IsShown() and card.title.label.text == title then return card end
    end
end
local reportHeight = report.height
report.height = 20
report.scroll:SetVerticalScroll(115)
local down = assert(FindCard("Below grid"), "an offset card disappeared at its preceding grid row boundary")
assert(down.rows[1]:IsShown() and down.rows[1].left.text == "Below card",
    "an offset row disappeared at its preceding nominal row boundary")
report.scroll:SetVerticalScroll(60)
assert(FindCard("Above grid"), "an offset card disappeared before its following grid row boundary")
report.scroll:SetVerticalScroll(0)
report.height = reportHeight
view:ShowGroups(groups)
assert(report.cards[1].panelX == 0 and report.cards[1].panelY == 0 and report.cards[1].rows[1].panelX == 0
    and report.cards[1].rows[1].panelY == 30 and report.cardInset == 0 and report.rowInset == 0,
    "stock report reused the custom card or row displacement")

do
    local parent = Create("Frame")
    suite.NewContext = function(id)
        assert(id == "characterPanelPreview", "preview reused the live skin context")
        return { Skin = function() return nil end }
    end
    ns.Public = function() return true end
    ns.String = function(value) return type(value) == "string" and value or nil end
    ns.Host.Client = { isForever = false }
    GetInventorySlotInfo = function(token) if token == "HeadSlot" then return 1, 42 end end
    GetInventoryItemTexture = function() return 123 end
    assert(loadfile(path .. "Equipment.lua"))("MSUF_Suite_CharacterPanel", ns)
    assert(loadfile(path .. "Pages.lua"))("MSUF_Suite_CharacterPanel", ns)
    ns.Pages.Overview = function(data) data[1] = groups[1] end
    ns.Pages.EquipmentSummary = function() end
    ns.Pages.Read = function(tab, data)
        if tab == "statistics" then
            data[1] = { title = "No data available", rows = {} }
            return
        end
        assert(tab == "reputation")
        data[1] = { title = "Reputation", rows = { { label = "Faction", value = "Friendly" } } }
    end
    assert(loadfile(path .. "Preview.lua"))("MSUF_Suite_CharacterPanel", ns)
    local preview = suite.CharacterPanelPreview.New(parent, {
        own = { name = "Sample", portrait = "player", itemLevel = "12" },
        inspect = { name = "Inspect Sample", portrait = "player", class = "Priest", level = 23, itemLevel = "19" },
    }, function(id) chosenTab = id end)
    local embedded = preview.view
    assert(embedded.frame.parent == parent, "the preview escaped the menu into a detached live window")
    assert(embedded.header.buttons.portrait.kind == "Button" and view.header.buttons.portrait.kind ~= "Button",
        "only the embedded panel should expose interactive header field buttons")
    modelWindow = embedded.frame
    local all = {
        { id = "overview", label = "Overview" }, { id = "reputation", label = "Reputation" },
        { id = "statistics", label = "Statistics" },
    }
    local size = preview:Paint({}, "own", all, "overview", {}, 800)
    assert(size > 200 and size <= 426 and embedded.gear:IsShown() and embedded.model:IsShown()
        and embedded.left[1].slot == 1 and embedded.rail.cards[1]:IsShown(),
        "the full preview omitted the model, gear slots or Overview rail")
    embedded.left[1].scripts.OnClick(embedded.left[1], "LeftButton")
    assert(embedded.rail.cards[1].title.label.text == "Slot", "preview item selection missed its local details")
    embedded.tabButtons[2].scripts.OnClick(embedded.tabButtons[2])
    assert(chosenTab == "reputation", "runtime tab in embedded view was not interactive")
    preview:Paint({}, "own", all, "reputation", {}, 800)
    assert(embedded.report.scroll:IsShown() and not embedded.gear:IsShown()
        and embedded.report.cards[1].title.label.text == "Reputation",
        "embedded runtime view did not render a complete report tab")
    assert(embedded.report.cards[1].rows[1].left.text == "Faction", "a meaningful built-in report was replaced")
    preview:Paint({}, "own", all, "statistics", {}, 800)
    assert(embedded.report.cards[1].title.label.text == "Statistics"
        and embedded.report.cards[1].rows[1].left.text == "Quests",
        "an empty built-in report did not show safe sample content")
    local custom = {}
    for i = 1, 8 do
        custom[i] = { id = "custom" .. i, name = "A longer custom preview tab " .. i, cards = {} }
    end
    local last = custom[#custom]
    for i = 1, 6 do
        local card = { title = "Card " .. i, rows = {} }
        for j = 1, 10 do card.rows[j] = { source = "itemLevel", label = "Row " .. i .. "." .. j } end
        last.cards[i] = card
    end
    local config = { customTabs = assert(ns.CharacterTabs.Encode(custom)) }
    local order = suite.CharacterHeader.Order(config, "tab")
    local before, after = 0, 0
    local oldIndex, restoredActor
    preview:SetContentChanging(function(instance)
        assert(instance == preview)
        before = before + 1
        if restoredActor then oldIndex = restoredActor.previewCardIndex end
    end)
    preview:SetContentChanged(function(instance)
        assert(instance == preview and before == after + 1, "content callback was not paired around viewport changes")
        after = after + 1
    end)
    preview:Paint(config, "own", order, "reputation", {}, 800)
    assert(not embedded.tabButtons[#order]:IsShown(), "long custom tab unexpectedly fit in the preview")
    embedded.moreTab.scripts.OnClick(embedded.moreTab)
    menu[#menu].pick(menu[#menu].data)
    assert(chosenTab == last.id, "embedded More menu did not select the overflow tab")
    preview:Paint(config, "own", order, chosenTab, {}, 800)
    assert(embedded.tabButtons[#order]:IsShown() and embedded.promotedTab == #order
        and embedded.tabButtons[#order].selected and not embedded.moreTab.selected,
        "overflow-selected custom tab was not promoted to an editable preview actor")
    embedded.moreTab.scripts.OnClick(embedded.moreTab)
    for _, entry in ipairs(menu) do assert(entry.data.id ~= last.id, "visible preview promotion remained hidden in More") end

    local cardCount, rowCount = 0, 0
    local function VerifyHit(kind, hit, cardIndex, rowIndex, actor, canvas)
        assert(hit.kind == "Button" and canvas == embedded.report.canvas and cardIndex >= 1,
            "preview did not publish a real content hit target and its scroll canvas")
        if kind == "card" then
            cardCount = cardCount + 1
            assert(not rowIndex and actor.title == hit and actor.previewCardIndex == cardIndex
                and hit.label.text == "Card " .. cardIndex)
            if not restoredActor then restoredActor = actor end
        else
            rowCount = rowCount + 1
            assert(kind == "row" and hit == actor and hit.previewRowIndex == rowIndex
                and hit.left.text == "Row " .. cardIndex .. "." .. rowIndex and hit.right.text == "712")
        end
    end
    preview:VisitContent(VerifyHit)
    assert(cardCount > 0 and rowCount > 0 and restoredActor.previewCardIndex == 1,
        "custom report did not expose visible card titles and value rows")
    local previousBefore, previousAfter = before, after
    embedded.report.scroll:SetVerticalScroll(380)
    assert(before == previousBefore + 1 and after == previousAfter + 1 and oldIndex == 1
        and restoredActor.previewCardIndex > 1, "scroll did not notify before and after reusing preview actors")
    local firstCount, firstRows = cardCount, rowCount
    preview:VisitContent(VerifyHit)
    assert(cardCount > firstCount and rowCount > firstRows, "scrolled custom report omitted replacement targets")
    preview:Paint(config, "own", order, "reputation", {}, 800)
    preview:VisitContent(function() error("built-in report retained custom handles") end)
    preview:Paint(config, "own", order, last.id, {}, 800)
    preview:Hide()
    preview:VisitContent(function() error("hidden preview retained content targets") end)
    local Strict = dofile(root .. "/../MidnightSimpleUnitFrames/tools/tests/classpower_secrets.lua")
    Strict.Install()
    ns.Public = function(value) return not Strict.IsSecret(value) end
    GetInventoryItemTexture = function() return Strict.New("number") end
    local stop = Strict.Watch(path .. "Preview.lua", { strict = true })
    preview:Paint({}, "inspect", all, "overview", { tabs = false }, 800)
    local violations = stop()
    assert(#violations == 0 and embedded.left[1].texture == 42, table.concat(violations, " | "))
    assert(embedded.gear:IsShown() and not embedded.tabBar:IsShown() and embedded.rail.cards[1].title.label.text == "Inspect",
        "Inspect or preview-only layers did not reach the shared view")
    preview:Hide()
    assert(not embedded.frame:IsShown(), "closing the editor left the embedded view shown")
end

print("Character Panel appearance: runtime and embedded layouts, fonts, model controls, offsets and warm paint passed")
