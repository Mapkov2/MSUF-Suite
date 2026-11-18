local root = assert(arg[1])
local path = root .. "/MSUF_Suite_CharacterPanel/"
local Strict = dofile(root .. "/../MidnightSimpleUnitFrames-7.0/tools/tests/classpower_secrets.lua")
local writes, frames, modelReads, modelRefreshes, playerModels = 0, 0, 0, 0, 0
local liveCombat, identityRestricted, secretIdentityChecked = false, false, false
local rejectNativeScrollTemplate = false
local secretIdentity = newproxy()
local fontPath, modelReady = "First.ttf", false
local skinEnabled, skinRefreshes, releases = true, 0, 0
local openingWatches = 0
local modelWindow
local cursorX, cursorY, mouseDown = 320, 260, true
local function Write() writes = writes + 1 end

local function StringWidth(font, text)
    return #text * (font:GetEffectiveScale() < .9 and 6.2 or 6)
end

local function StringHeight(font)
    assert(font.wordWrap and font.nonSpaceWrap, "the measuring font must use the same wrap rules as report text")
    local lines, used = 1, 0
    for word in font.text:gmatch("%S+") do
        local width = StringWidth(font, word)
        local gap = used > 0 and StringWidth(font, " ") or 0
        if used + gap + width > font.width and used > 0 then
            lines, used, gap = lines + 1, 0, 0
        end
        used = used + gap + width
        while used > font.width do
            lines, used = lines + 1, used - font.width
        end
    end
    return lines * font.fontSize
end

local methods = {
    SetPoint = function(self, ...) self.point = { ... } Write() end,
    GetPoint = function(self) return unpack(self.point or {}) end,
    ClearAllPoints = function(self) self.point = nil Write() end,
    SetHeight = function(self, height)
        assert(not (self.parent and self.parent.blockScrollLayout), "canvas resized inside a restricted native scroll")
        self.height = height
        Write()
    end,
    SetWidth = function(self, width) self.width = width Write() end,
    SetClipsChildren = function(self, enabled) self.clipsChildren = enabled Write() end,
    SetSize = function(self, width, height) self.width, self.height = width, height Write() end,
    GetWidth = function(self) return self.width end,
    GetHeight = function(self) return self.height end,
    SetJustifyH = Write, SetTexCoord = Write, SetAllPoints = Write,
    SetWordWrap = function(self, wrap) self.wordWrap = wrap Write() end,
    SetNonSpaceWrap = function(self, wrap) self.nonSpaceWrap = wrap Write() end,
    SetMaxLines = function(self, lines) self.maxLines = lines Write() end,
    SetSnapToPixelGrid = Write, SetTexelSnappingBias = Write,
    SetFrameStrata = function(self, strata) self.strata = strata Write() end,
    SetParent = function(self, parent) self.parent = parent Write() end,
    SetHitRectInsets = function(self, left, right, top, bottom) self.insets = {left, right, top, bottom} Write() end,
    SetFrameLevel = function(self, level)
        local parent = self.parent
        self.frameLevel = level
        self.parentLevel = parent and parent.GetFrameLevel and parent:GetFrameLevel()
        Write()
    end,
    GetFrameLevel = function(self)
        local parentLevel = self.parent and self.parent.GetFrameLevel and self.parent:GetFrameLevel() or 0
        if self.frameLevel then return self.frameLevel + (self.parentLevel and parentLevel - self.parentLevel or 0) end
        return parentLevel + 1
    end,
    SetClampedToScreen = Write, SetMovable = Write,
    SetScale = function(self, scale) self.scale = scale Write() end,
    GetEffectiveScale = function(self)
        local parent = self.parent
        return (self.scale or 1) * (parent and parent.GetEffectiveScale and parent:GetEffectiveScale() or 1)
    end,
    GetLeft = function() return 100 end, GetTop = function() return 700 end,
    RegisterForDrag = Write, SetTexture = Write,
    RegisterForClicks = function(self, ...) self.registeredClicks = { ... } Write() end,
    EnableMouse = function(self, enabled) self.mouseEnabled = enabled Write() end,
    EnableMouseWheel = Write, SetAtlas = Write, SetScrollChild = Write, ClearModel = Write,
    SetOrientation = Write, SetAlpha = Write, SetNormalAtlas = Write, SetHighlightAtlas = Write, SetPushedAtlas = Write,
    SetThumbTexture = function(self, thumb) self.thumb = thumb Write() end,
    SetMinMaxValues = function(self, low, high)
        assert(not Strict.IsSecret(low) and not Strict.IsSecret(high) and low <= high, "secret slider bounds")
        self.low, self.high = low, high
        self:SetValue(self.value or low)
    end,
    SetValue = function(self, value)
        assert(not Strict.IsSecret(value), "secret slider value")
        value = math.max(self.low, math.min(value, self.high))
        if self.value == value then return end
        self.value = value
        Write()
        local change = self.scripts.OnValueChanged
        if change then change(self, value) end
    end,
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
    SetUnit = function(self, unit)
        assert(not liveCombat or unit == "player" and rawequal(identityRestricted, false), "restricted model bind")
        assert(modelWindow:IsShown() and self:IsShown(), "model was bound before its window and region were shown")
        modelReads = modelReads + 1
        self.testUnit = unit
        return modelReady
    end,
    RefreshUnit = function(self)
        assert(not liveCombat or self.testUnit == "player" and rawequal(identityRestricted, false), "restricted model refresh")
        modelRefreshes = modelRefreshes + 1
        Write()
    end,
    SetShown = function(self, value)
        if self.shown and not value and self.scripts.OnHide then self.scripts.OnHide(self) end
        self.shown = value
        Write()
    end,
    IsShown = function(self) return self.shown == true end,
    IsVisible = function(self) return self:IsShown() end,
    GetAlpha = function(self) return self.alpha or 1 end,
    SetAlpha = function(self, alpha) self.alpha = alpha Write() end,
    Hide = function(self) self:SetShown(false) end,
    Show = function(self) self:SetShown(true) end,
    SetText = function(self, value)
        assert(self.fontPath and not Strict.IsSecret(value), "font before text and public text only")
        self.text = value
        Write()
    end,
    SetFormattedText = function(self, format, value, extra)
        assert(self.fontPath, "font before formatted text")
        self.formatted = { format, value, extra }
        self.text = nil
        Write()
    end,
    GetUnboundedStringWidth = function(self) return StringWidth(self, self.text) end,
    GetUnboundedStringWidthForText = StringWidth,
    GetStringHeight = StringHeight,
    GetVerticalScroll = function(self) return self.offset or 0 end,
    GetVerticalScrollRange = function(self) return self.range or 1000 end,
    SetVerticalScroll = function(self, offset)
        assert(not self.blockScrollLayout and not Strict.IsSecret(self:GetVerticalScrollRange()),
            "native scroll callback would read a protected range")
        self.offset = offset
        Write()
        local hook = self.scripts.OnVerticalScroll
        if hook then hook(self, offset) end
    end,
}
local function Create(kind, name, parent, template)
    assert(not rejectNativeScrollTemplate or template ~= "ScrollFrameTemplate",
        "Button:SetEnabled(): Cannot be called with secrets due to existing script handlers")
    frames = frames + 1
    if kind == "PlayerModel" then playerModels = playerModels + 1 end
    return setmetatable({ kind = kind, name = name, scripts = {}, parent = parent, template = template }, { __index = methods })
end
CreateFrame = Create
methods.CreateTexture = function() return Create("Texture") end
methods.CreateFontString = function(self) return Create("FontString", nil, self) end
function wipe(values) for key in pairs(values) do values[key] = nil end end
UIParent = { GetWidth = function() return 1600 end, GetHeight = function() return 900 end,
    GetEffectiveScale = function() return 1 end, GetRect = function() return 0, 0, 1600, 900 end }
GameTooltip = { IsOwned = function() return false end }
function GetCursorPosition() return cursorX, cursorY end
function IsMouseButtonDown() return mouseDown end
SetPortraitTexture = Write
ITEM_QUALITY_COLORS = { [2] = { r = 0, g = 1, b = 0 } }
FACTION_BAR_COLORS = {}
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
    CreateFontString = function(parent) return Create("FontString", nil, parent) end,
    SetFont = function(font, path, size) font.fontPath, font.fontSize = path or fontPath, size Write() end,
    GlobalFontPath = function() return fontPath end,
    FontRevision = 0,
    RGB = function(hex)
        if hex == "ff6600" then return 1, .4, 0 end
        assert(hex == "33cc66")
        return .2, .8, .4
    end,
}
MSUFSuite = { Suite = suite }
local function Number(value)
    if not Strict.IsSecret(value) then return tonumber(value) end
end
local function PublicText(value)
    if not Strict.IsSecret(value) and type(value) == "string" and value ~= "" then return value end
end
local ns = { Text = function(value) return value end, Number = Number, Suite = suite, Client = {},
    String = PublicText, IsSecret = Strict.IsSecret,
    Routing = { HoverGearTab = function() end, ReleaseGearClick = function() end },
    Host = { Client = {}, InCombat = function() return liveCombat end } }
ns.Public = function(value)
    if rawequal(value, secretIdentity) then
        secretIdentityChecked = true
        return false
    end
    return true
end
local function Noop() end
local build = setmetatable({}, { __index = function() return function() return {} end end })
ns.CatalogBuild = { ForAddon = function() return build end }
ns.ResolveFont = function(key) return key == "Alternate" and "Alternate.ttf" or nil end
assert(loadfile(root .. "/MSUF_Suite/Core/CharacterTabs.lua"))("MSUF_Suite", ns)
assert(loadfile(root .. "/MSUF_Suite/Core/CharacterBindings.lua"))("MSUF_Suite", ns)
ns.Host.CharacterTabs = ns.CharacterTabs
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/CharacterPanel.lua"))("MSUF_Suite", ns)
assert(loadfile(root .. "/MSUF_Suite/Core/CharacterHeader.lua"))("MSUF_Suite", ns)
assert(loadfile(root .. "/MSUF_Suite/Core/WindowCaption.lua"))("MSUF_Suite", ns)
suite.WindowCaption.PixelFactor = function() return nil end
for _, file in ipairs({ "Stats", "ModelControls", "WindowControls", "TabOverflow", "GroupLayout", "View" }) do
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
assert(view.header.scale == scaled and view.reportMetrics.scale == scaled, "resizing did not reflow visible text on release")
window.maximize.scripts.OnClick(window.maximize)
assert(view.frame.scale > scaled and view.frame.point[1] == "CENTER" and not grip.shown)
assert(view.header.scale == view.frame.scale and view.reportMetrics.scale == view.frame.scale,
    "maximizing did not reflow the visible text")
window.maximize.scripts.OnClick(window.maximize)
assert(view.frame.scale == scaled and view.frame.point[1] == "TOPLEFT" and grip.shown)
-- Docking left with its buttons; a saved dock still places the window.
assert(not window.dockLeft and not window.dockRight, "the caption still offers dock buttons")
window.dock, preferences.dock = "right", "right"
ns.Window.Fit(window)
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

do
    local sample = { level = 3, class = "Paladin" }
    local savedScale = view.window.requestedScale
    view.window.requestedScale = 1
    view:FitScreen()
    view:SetHeader("Hayato", nil, "0.00", "player", "guid", sample)
    local originalWidth = fields.name.width
    view.window.requestedScale = .8
    view:FitScreen()
    for _, key in ipairs({ "name", "level", "class", "itemLevel" }) do
        local field = fields[key]
        local width = key == "itemLevel" and field.text.width or field.width
        assert(width >= field.text:GetUnboundedStringWidth() + 4,
            "the fractional-scale header clips " .. key)
    end
    assert(fields.name.width > originalWidth, "the header reused measurements from the old scale")
    view.window.requestedScale = savedScale
    view:FitScreen()
    view:SetHeader("Mapko", nil, "19", "player", "guid", data)
end

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
local nameWidth = fields.name.text:GetUnboundedStringWidth()
assert(fields.name.width >= nameWidth and fields.name.width <= math.ceil(nameWidth + 4 / view.frame:GetEffectiveScale()) + 1,
    "the name hit area did not stay close to its text")
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
do
    FACTION_BAR_COLORS = { [5] = { r = .2, g = .7, b = .35 } }
    local entries = {
        { label = "Darnassus", value = "Friendly", reputationFill = .4, reputationReaction = 5 },
        { label = "Ironforge", value = "Friendly", reputationFill = 0, reputationReaction = 5 },
        { label = "Stormwind", value = "Friendly", reputationFill = .8 },
    }
    local sample = { { title = "Alliance", rows = entries } }
    local reputation = { { id = "reputation", label = "Reputation" } }
    view:SetTabs(reputation, "reputation")
    view:RefreshAppearance(nil, { reputationBarHeight = 3 })
    entries[1].reputationFill, entries[2].reputationFill, entries[3].reputationFill = nil, nil, nil
    view:ShowGroups(sample)
    assert(not report.cards[1].rows[1].reputationTrack, "disabled bars allocated track textures")
    entries[1].reputationFill, entries[2].reputationFill, entries[3].reputationFill = .4, 0, .8
    view:ShowGroups(sample)
    local card = report.cards[1]
    local row, emptyRow = card.rows[1], card.rows[2]
    local track, bar = row.reputationTrack, row.reputationBar
    assert(track and track:IsShown() and track.height == 3 and row.left.point[5] == 2.5,
        "the reputation track did not lift the row text above the bar")
    assert(bar:IsShown() and bar.width == (row.panelWidth - 20) * .4 and bar.color[2] == .7,
        "the standing did not paint its filled fraction and native color")
    assert(emptyRow.reputationTrack:IsShown() and not emptyRow.reputationBar:IsShown(),
        "zero progress should retain only the track")
    local oldFrames, oldWrites = frames, writes
    view:ShowGroups(sample)
    assert(frames == oldFrames and writes == oldWrites, "warm reputation repaint changed widgets")

    view:RefreshAppearance(nil, { reputationBarHeight = 8, reputationBarColor = "ff6600" })
    assert(track.height == 8 and row.left.point[5] == 5 and bar.color[1] == 1 and bar.color[2] == .4,
        "a visual settings change did not restyle the visible row")
    view:RefreshAppearance(skin, { reputationBarHeight = 8, reputationBarColor = "ff6600", reputationColorFriendly = "33cc66" })
    assert(bar.color[2] == .8 and card.rows[3].reputationBar.color[2] == .4,
        "rank override should take precedence over the shared bar color")
    view:RefreshAppearance(skin, { reputationBarHeight = 8 })
    assert(bar.color[2] == .7 and card.rows[3].reputationBar.color[1] == color,
        "removing the override did not restore standing and theme colors")
    local oldHeight = report.height
    report.height = 24
    report.scroll:SetVerticalScroll(78)
    assert(row.left.text == "Stormwind" and row.reputationBar == bar
        and bar.width == (row.panelWidth - 20) * .8, "scrolling did not reuse and repaint the visible row bar")
    report.height = oldHeight
    report.scroll:SetVerticalScroll(0)

    view:SetTabs(tabs, "overview")
    view:ShowGroups(groups)
    assert(not track:IsShown() and not bar:IsShown() and row.left.point[5] == 0,
        "a recycled row retained its reputation bar or text offset")
    view:SetTabs(reputation, "reputation")
    view:ShowGroups(sample)
    assert(row.reputationTrack == track and track:IsShown() and bar:IsShown(),
        "returning to the report did not reuse the hidden bar")
    entries[1].reputationFill, entries[2].reputationFill, entries[3].reputationFill = nil, nil, nil
    view:ShowGroups(sample)
    assert(not track:IsShown() and not bar:IsShown() and row.left.point[5] == 0,
        "disabling bars left progress art or shifted text")
    view:SetTabs(tabs, "overview")
    view:ShowGroups(shiftedGroups)
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

do
    local rail = view.rail.scroll
    rail.offset, rail.range, rail.blockScrollLayout = 110, Strict.New("number"), true
    local vitals = { { title = "Attributes", rows = { { label = "Health", value = 595 } } } }
    view:ShowGear(item, empty, empty, vitals, nil, empty, true, true)
    assert(not rail:IsShown() and view.combatRail.canvas:IsShown(), "native stats scroller remained active in combat")
    assert(view.combatRail.cards[1].rows[1].right.text == 595, "fixed combat rail dropped vitals")
    assert(rail.offset == 110, "combat repaint reset the native scroller")
    report.scroll.range, report.scroll.blockScrollLayout = Strict.New("number"), true
    view:ShowGroups(vitals, true)
    assert(view.combatReport.canvas:IsShown() and not report.scroll:IsShown(), "Attributes used the native scroller in combat")
    assert(view.combatReport.cards[1].rows[1].right.text == 595)
    report.scroll.scripts.OnVerticalScroll(report.scroll, Strict.New("number"))
    report.scroll.range, report.scroll.blockScrollLayout = nil, nil
    view:ShowGroups(vitals)
    assert(report.scroll:IsShown() and not view.combatReport.canvas:IsShown(), "Attributes stayed in its combat layout")
    rail.range, rail.blockScrollLayout = nil, nil
    view:ShowGear(item, empty, empty, groups, nil, empty, true)
    assert(rail:IsShown() and not view.combatRail.canvas:IsShown(), "normal stats rail did not return after combat")
end
view:ShowGroups(groups)
assert(report.cards[1].panelX == 0 and report.cards[1].panelY == 0 and report.cards[1].rows[1].panelX == 0
    and report.cards[1].rows[1].panelY == 30 and report.cardInset == 0 and report.rowInset == 0,
    "stock report reused the custom card or row displacement")

do
    local value = Strict.New("number")
    local entry = { label = "Spirit", value = 38 }
    local sample = { { title = "Attributes", rows = { entry } } }
    view:ShowGroups(sample)
    local right = report.cards[1].rows[1].right
    assert(right.text == 38)
    view.readableValues = true
    entry.value, entry.displayFormat = value, "%d"
    view:ShowGroups(sample)
    assert(right.formatted[1] == "%d" and rawequal(right.formatted[2], value) and not right.panelText,
        "restricted stat did not reach the font formatter")
    entry.value, entry.displayFormat, entry.displayExtra = 100, "%d (%+d)", value
    view:ShowGroups(sample)
    assert(right.formatted[1] == "%d (%+d)" and right.formatted[2] == 100 and rawequal(right.formatted[3], value),
        "restricted stat modifier did not reach the font formatter")
    entry.value, entry.displayFormat, entry.displayExtra = 38, nil, nil
    view:ShowGroups(sample)
    assert(right.text == 38, "the public text cache kept the restricted text on a recycled row")
    view.readableValues = nil
    view:ShowGroups(groups)
end

do
    liveCombat = true
    C_Secrets = {
        ShouldUnitIdentityBeSecret = function(unit)
            assert(unit == "player", "combat queried a non-player model")
            return identityRestricted
        end,
    }
    view.frame:Show()
    view:SetHeader("Name", "Level 22", "19", "player", "combat-guid")
    local beforeBind, beforeRefresh = modelReads, modelRefreshes
    view:ShowGear(item, empty, empty, groups, nil, empty, true)
    assert(modelReads == beforeBind + 1 and view.model:IsShown(), "public player model was missing on combat open")
    view:RefreshModel()
    assert(modelRefreshes == beforeRefresh + 1, "public player model did not refresh in combat")
    identityRestricted = true
    view:RefreshModel()
    assert(modelRefreshes == beforeRefresh + 1 and view.model:IsShown(), "combat dropped or refreshed an existing restricted model")
    identityRestricted = secretIdentity
    view:SetHeader("Name", "Level 22", "19", "player", "other-combat-guid")
    view:RefreshModel()
    assert(secretIdentityChecked and modelReads == beforeBind + 1 and not view.model:IsShown(),
        "secret model predicate did not block an identity change")
    identityRestricted = nil
    view:RefreshModel()
    assert(modelReads == beforeBind + 1, "unknown model restriction must keep the bind gated")
    liveCombat = false
    view:RefreshModel()
    assert(modelReads == beforeBind + 2 and view.model:IsShown(), "model was not restored when restrictions lifted")
end

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
    assert(loadfile(path .. "Reputation.lua"))("MSUF_Suite_CharacterPanel", ns)
    assert(loadfile(path .. "Pages.lua"))("MSUF_Suite_CharacterPanel", ns)
    local fullStats, previewCombat
    ns.Pages.Overview = function(data, full, combat) data[1], fullStats, previewCombat = groups[1], full, combat end
    ns.Pages.EquipmentSummary = function() end
    local reputationReads = 0
    ns.Pages.Read = function(tab, data, config)
        if tab == "statistics" then
            data[1] = { title = "No data available", rows = {} }
            return
        end
        assert(tab == "reputation")
        reputationReads = reputationReads + 1
        data[1] = { title = "Reputation", rows = {
            { label = "Faction", value = config.reputationValue == 3 and "750 left" or "Friendly",
                reputationFill = config.showReputationBars and .25 or nil },
        } }
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
    assert(reputationReads == 1 and not embedded.report.cards[1].rows[1].reputationTrack)
    local reputation = { showReputationBars = true, reputationValue = 3 }
    preview:Paint(reputation, "own", all, "reputation", {}, 800)
    local faction = embedded.report.cards[1].rows[1]
    assert(reputationReads == 2 and faction.right.text == "750 left" and faction.reputationBar:IsShown(),
        "the same-tab preview did not refresh its progress content")
    reputation.reputationBarHeight, reputation.reputationBarColor = 6, "33cc66"
    preview:Paint(reputation, "own", all, "reputation", {}, 800)
    assert(reputationReads == 2 and faction.reputationTrack.height == 6 and faction.reputationBar.color[2] == .8,
        "the same-tab preview did not restyle its cached bar without reading factions")
    local attributes = { showAttributesTab = true, showFullStats = false }
    preview:Paint(attributes, "own", suite.CharacterHeader.Order(attributes, "tab"), "attributes", {}, 800)
    assert(fullStats == true and embedded.report.scroll:IsShown() and not embedded.gear:IsShown(),
        "Attributes preview did not use the full runtime stats without equipment")
    liveCombat = true
    preview:Paint(attributes, "own", suite.CharacterHeader.Order(attributes, "tab"), "attributes", {}, 800)
    assert(previewCombat == true and embedded.combatReport.canvas:IsShown(), "preview missed the combat edge")
    preview:Paint({}, "own", all, "overview", {}, 800)
    assert(previewCombat == true and embedded.combatRail.canvas:IsShown(), "Overview preview read full combat stats")
    liveCombat = false
    preview:Paint({}, "own", all, "overview", {}, 800)
    assert(previewCombat == false and embedded.rail.scroll:IsShown(), "Overview preview did not restore stats")
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

do
    local left, right, top, scale = 30, 560, 730, 1
    local rail = {
        GetRight = function() return right + 64 end, GetWidth = function() return 64 end,
        GetEffectiveScale = function() return scale end,
    }
    local native = {
        GetLeft = function() return left end, GetRight = function() return right end,
        GetTop = function() return top end, GetEffectiveScale = function() return scale end,
        ModeTabs = rail,
    }
    local beforeModels = playerModels
    local hosted = ns.View.New({
        frameName = "StandaloneInspect",
        tab = function(id) chosenTab = id end, group = Noop,
    }, nil, native)
    local frame = hosted.frame
    assert(frame.parent == UIParent and not frame.name and not frame.mouseEnabled and not hosted.embedded,
        "the hosted shell captured native mouse input or acquired an independent window")
    assert(not hosted.gear and not hosted.model and not hosted.window.grip and not hosted.window.minimize,
        "the hosted shell duplicated native controls")
    assert(frame.point[1] == "TOPLEFT" and frame.point[2] == native
        and frame.point[3] == "TOPRIGHT" and frame.point[4] == 2, "Retail dock overlaps its host")
    local unchanged = writes
    hosted:FitScreen()
    hosted:ApplyWindowPreferences({ dock = "right", scale = 2 })
    hosted:SetMinimized(true)
    hosted:RefreshModel()
    assert(writes == unchanged and playerModels == beforeModels and not hosted:IsMinimized(),
        "unchanged hosted geometry or standalone window controls wrote widgets")

    hosted.frame:Show()
    hosted:SetHeader("Mapko", "Level 22", "19", "player", "player-guid")
    assert(hosted.header.buttons.name.text.text == "Mapko" and hosted.header.rightReserve == 0,
        "the native host dropped the Suite header")
    local all = { { id = "overview", label = "Overview" } }
    for i = 2, 10 do all[i] = { id = "report" .. i, label = "Extra report " .. i } end
    all[11] = { id = "custom1", label = "My custom report", custom = true }
    hosted:SetTabs(all, "overview")
    hosted:ShowGroups(groups)
    assert(hosted.report.scroll:IsShown() and hosted.report.columns == 1 and hosted.report.cards[1].title.label.text == "Quick",
        "the native host dropped the Suite report")
    assert(hosted.report.scroll.template == "ScrollFrameTemplate", "the Retail host lost native scrolling")
    liveCombat = true
    hosted.moreTab.scripts.OnClick(hosted.moreTab)
    menu[#menu].pick(menu[#menu].data)
    assert(chosenTab == "custom1", "hosted custom tabs could not be selected in combat")
    hosted:SetTabs(all, chosenTab)
    assert(hosted.tabButtons[11]:IsShown() and hosted.tabButtons[11].selected,
        "selected hosted custom tab stayed hidden in overflow")
    liveCombat = false

    ns.Host.Client.isForever = true
    hosted:FitScreen()
    assert(frame.point[4] == 66, "Forever dock overlapped the original mode tabs")
    scale = .8
    hosted:FitScreen()
    assert(frame.scale == .8 and math.abs(frame.point[4] - 66.5) < .001, "dock did not follow the native scale")
    scale, left, right = 1, 990, 1540
    hosted:FitScreen()
    assert(frame.point[1] == "TOPRIGHT" and frame.point[3] == "TOPLEFT" and frame.point[4] == -2,
        "dock did not move to the clear side of the screen")
    ns.Host.Client.isForever = false
    left, right = 100, 1500
    hosted:FitScreen()
    assert(frame.point[1] == "TOPLEFT" and math.abs(frame.scale * (frame.width + frame.point[4]) - 100) < .001,
        "dock clipped outside the remaining space instead of scaling to it")
    ns.Host.Client.isForever = true
    native.ModeTabs, right = Strict.New("table"), Strict.New("number")
    Strict.GUARD_NAMES.falsy.Public = true
    local stop = Strict.Watch(path .. "WindowControls.lua", { strict = true })
    hosted:FitScreen()
    local violations = stop()
    assert(#violations == 0, table.concat(violations, " | "))
    assert(frame.point[4] == 66, "restricted geometry lost the stock Forever rail clearance")
    assert(playerModels == beforeModels, "hosted layout created a duplicate model")

    rejectNativeScrollTemplate = true
    local foreverDock = ns.View.New({ tab = Noop, group = Noop }, nil, native)
    rejectNativeScrollTemplate = false
    foreverDock:ShowGroups(groups)
    assert(foreverDock.report.slider and foreverDock.report.scroll:IsShown()
        and foreverDock.report.cards[1].title.label.text == "Quick", "the Forever dock lost its report")
end

do
    local nativeLevel, scale = 25, .8
    local native = { GetEffectiveScale = function() return scale end, GetFrameLevel = function() return nativeLevel end }
    local head = { slot = 1, token = "HeadSlot", label = "Head", name = "Helm", icon = 42, quality = 2, level = 19 }
    local hand = { slot = 10, token = "HandsSlot", label = "Hands", name = "Gloves", icon = 44, quality = 2, level = 22 }
    local main = { slot = 16, token = "MainHandSlot", label = "Main Hand", name = "Staff", icon = 46, level = 31 }
    local off = { slot = 17, token = "SecondaryHandSlot", label = "Off Hand", name = "Shield", icon = 48, level = 27 }
    local gear = { left = { head }, right = { hand }, weapons = { main, off } }

    ns.Host.Client.isForever = false
    local layout = ns.View.NativeLayout(gear)
    layout.rootLevel = nativeLevel
    assert(layout.width == suite.CharacterHeader.Width and layout.height == 552 and layout.strata == "HIGH",
        "the full native view changed the old window geometry or sits above the native flyout")
    assert(layout.artLevel < layout.modelLevel and layout.modelLevel < layout.slotLevel
        and layout.slotLevel < layout.reportLevel and layout.reportLevel < layout.closeLevel,
        "the native presentation layers cannot support the native item flyout or report cover")
    assert(#layout.slots == 4 and layout.slots[1].token == head.token and layout.slots[4].token == off.token,
        "the layout lost an actual slot")
    local nativeHand = layout.slots[2]
    assert(nativeHand.x == 496 and nativeHand.alternateX == 372
        and not layout.slots[1].alternateX and not layout.slots[4].alternateX,
        "the two original layouts changed the wrong native slot hit areas")
    assert(layout.close.x == 912 and layout.close.y == 2 and layout.close.size == 24,
        "the native close moved away from the original Suite caption")
    ns.Host.Client.isForever = true
    local foreverLayout = ns.View.NativeLayout(gear)
    local ammo = foreverLayout.slots[5]
    assert(ammo and ammo.optional and ammo.token == "AmmoSlot", "Forever's optional native ammo slot was omitted")

    local beforeModels = playerModels
    local clicked, actions = nil, {}
    liveCombat, rejectNativeScrollTemplate = true, true
    local full = ns.View.New({
        frameName = "StandaloneInspect",
        windowAction = function(action)
            actions[#actions + 1] = action
            if action == "maximize" or action == "minimize" then return true end
        end,
        tab = Noop, group = Noop, enter = Noop, leave = Noop, drop = Noop, drag = Noop,
        slot = function(slot, _, mouse)
            assert(mouse == "LeftButton", "the card received a protected equipment action")
            clicked = slot
        end,
    }, nil, native, layout)
    liveCombat, rejectNativeScrollTemplate = false, false
    local frame = full.frame
    assert(full.nativeLayout == layout and frame.parent == native and not frame.name and not frame.mouseEnabled
        and frame.width == layout.width and frame.height == layout.height and frame:GetFrameLevel() == nativeLevel + layout.artLevel
        and frame.strata == layout.strata and frame:GetEffectiveScale() == .8 and not frame.scale,
        "the hosted shell did not share native stacking and inherited scale, or blocked native input")
    assert(frame.point[1] == "TOPLEFT" and frame.point[2] == native
        and frame.point[3] == "TOPLEFT" and frame.point[4] == 0 and frame.point[5] == 0,
        "the art moved independently of the actual slot layout")
    -- Windows caption: three equal cells flush in the header's corner; the
    -- close art covers Blizzard's X (opaque, no mouse) and that X keeps the click.
    local close = full.closeArt
    assert(close.point[1] == "TOPRIGHT" and close.point[4] == 0 and close.point[5] == -1
        and close.width == 30 and close.height == layout.close.size and close.caption.base
        and close:GetFrameLevel() == nativeLevel + layout.closeLevel + 1
        and not close.mouseEnabled and not close.scripts.OnClick, "the original Close art intercepted native input")
    local window = full.window
    assert(window.maximize.point[4] == -30 and window.minimize.point[4] == -60 and not window.dockLeft
        and window.maximize.caption.kind == "maximize" and window.minimize.caption.kind == "minimize"
        and close.caption.kind == "close" and window.nativeGrip.point[1] == "BOTTOMRIGHT",
        "the original titlebar or scale-grip art moved")
    window.maximize.scripts.OnClick(window.maximize)
    window.minimize.scripts.OnClick(window.minimize)
    window.nativeTitleDrag.scripts.OnDragStart()
    window.nativeTitleDrag.scripts.OnDragStop()
    window.nativeTitleDrag.scripts.OnHide()
    window.nativeGrip.scripts.OnMouseDown(window.nativeGrip, "RightButton")
    window.nativeGrip.scripts.OnMouseDown(window.nativeGrip, "LeftButton")
    window.nativeGrip.scripts.OnMouseUp(window.nativeGrip, "LeftButton")
    window.nativeGrip.scripts.OnHide()
    assert(table.concat(actions, ",") == "maximize,minimize,moveStart,moveStop,moveStop,scaleStart,scaleStop,scaleStop",
        "the original controls did not call the native geometry owner")
    assert(window.maximize.caption.kind == "restore" and window.minimize.caption.kind == "restore",
        "the original caption did not reflect native maximize/minimize state")
    full.frame:Show()
    full:SetHeader("Mapko", "Level 22", "31", "player", "player-guid")
    assert(full.header.rightReserve == suite.CharacterHeader.CaptionWidth, "the full window shifted the original header fields")
    full:SetTabs(tabs, "overview")
    full:ShowGear(gear.left, gear.right, gear.weapons, groups, nil, empty, true)
    full.characterView = "classic"
    full:ShowGear(gear.left, gear.right, gear.weapons, groups, nil, empty, true)
    assert(not full.plate:IsShown(), "Classic did not reveal the Blizzard model and slot artwork")
    full.characterView = "modern"
    full:ShowGear(gear.left, gear.right, gear.weapons, groups, nil, empty, true)
    assert(full.plate:IsShown(), "Modern did not restore the Suite equipment artwork")
    local card = full.left[1]
    assert(card.texture == head.icon and card.name.text == head.name and card.level.text == head.level,
        "the full native panel lost the original card icon, name, or item level")
    assert(#card.registeredClicks == 1 and card.registeredClicks[1] == "LeftButtonUp"
        and card.insets[1] == 5 + layout.slots[1].size and card.insets[2] == 0
        and not card.scripts.OnReceiveDrag and not card.scripts.OnDragStart,
        "the Suite card covered the native icon or replaced its equipment interaction")
    card.scripts.OnClick(card, "LeftButton")
    assert(clicked == head.slot, "the original gear card no longer opens item details")
    local bodyX, bodyY = full.body.point[2], -full.body.point[3]
    local cards = { card, full.right[1], full.weapons[1], full.weapons[2] }
    for i = 1, #cards do
        local nativeSlot, suiteCard = layout.slots[i], cards[i]
        assert(nativeSlot.x == bodyX + suiteCard.panelX + 5
            and nativeSlot.y == bodyY + suiteCard.panelY + (suiteCard.panelHeight - nativeSlot.size) / 2,
            "the actual button does not cover the old icon")
    end
    assert(layout.model.x == bodyX + full.modelHost.point[2] + 3
        and layout.model.y == bodyY - full.modelHost.point[3] + 28
        and layout.model.width == full.modelHost.width - 6 and layout.model.height == full.modelHost.height - 31,
        "the native model escaped its original stage")
    assert(not full.model and full.modelHost:IsShown() and not full.reportCover:IsShown()
        and full.rail.cards[1].title.label.text == "Quick", "native gear or the original stats rail is missing")
    local zoom, resets = 0, 0
    -- OrbitCameraMixin zoom semantics (live 297d7aaa, Forever bebcb6bf):
    -- zoom percent is clamped, and equal distances make wheel input invisible.
    local function NewCamera(near, far, distance)
        local camera = { yaw = 0, near = near, far = far, percent = 0 }
        function camera:GetYaw() return self.yaw end
        function camera:SetYaw(yaw) self.yaw = yaw end
        function camera:GetMinZoomDistance() return self.near end
        function camera:GetMaxZoomDistance() return self.far end
        function camera:GetZoomDistance() return self.near + (self.far - self.near) * self.percent end
        function camera:SetZoomDistance(value)
            self.percent = self.near == self.far and 0 or math.max(0, math.min(1, (value - self.near) / (self.far - self.near)))
        end
        function camera:SetMinZoomDistance(value)
            self.near = value
            self:SetZoomDistance(self:GetZoomDistance())
        end
        function camera:SetMaxZoomDistance(value)
            self.far = value
            self:SetZoomDistance(self:GetZoomDistance())
        end
        function camera:OnMouseWheel(delta)
            zoom = zoom + delta
            self.percent = math.max(0, math.min(1, self.percent - delta * .1))
        end
        camera:SetZoomDistance(distance)
        return camera
    end
    local camera = NewCamera(6, 6, 6)
    CharacterModelScene = {
        IsVisible = function() return true end,
        GetActiveCamera = function() return camera end,
        Reset = function() resets = resets + 1 camera = NewCamera(6, 6, 6) end,
    }
    local toolbarButtons, toolbarCount = {}, 0
    for control in pairs(full.surfaces) do
        if control.control then
            toolbarCount = toolbarCount + 1
            toolbarButtons[control.control.atlas] = control
            local level = control:GetFrameLevel()
            assert(control.width == 20 and control.height == 20
                and level > full.modelInput:GetFrameLevel() and level > full.nativeSlotMasks[1]:GetFrameLevel()
                and level < full.reportCover:GetFrameLevel(), "native slot hit regions covered the model toolbar")
        end
    end
    assert(toolbarCount == 5, "the native model toolbar lost a button")
    local function ClickModelButton(icon)
        local button = assert(toolbarButtons[icon])
        button.scripts.OnClick(button)
    end
    ClickModelButton("common-icon-zoomin")
    assert(zoom == 1 and camera:GetZoomDistance() < 6, "zoom-in did not move the fixed native camera")
    ClickModelButton("common-icon-zoomout")
    assert(zoom == 0 and math.abs(camera:GetZoomDistance() - 6) < 1e-9, "zoom-out did not recover the native framing")
    ClickModelButton("common-icon-rotateright")
    assert(camera.yaw < 0, "rotate-right used model rotation instead of the opposite camera orbit")
    ClickModelButton("common-icon-rotateleft")
    assert(camera.yaw == 0, "the rotate-left button did not turn the model back")
    ClickModelButton("common-icon-undo")
    assert(resets == 1, "the reset button did not reset the native scene")
    local input = assert(full.modelInput, "the inactive slot mask still overlaps the 3D viewport")
    assert(input.parent == full.modelHost and input.mouseEnabled and input.width == layout.model.width
        and input:GetFrameLevel() > nativeLevel + layout.slotLevel + 1
        and input.point[4] == layout.model.x and input.point[5] == -layout.model.y,
        "the 3D input region crossed the active slots or remained under their mask")
    liveCombat = true
    input.scripts.OnMouseDown(input, "LeftButton")
    cursorX = cursorX + 20
    input.scripts.OnUpdate(input)
    input.scripts.OnMouseUp(input, "LeftButton")
    input.scripts.OnMouseWheel(input, 1)
    assert(camera.yaw < 0 and zoom == 1 and camera:GetZoomDistance() < 6 and not input.scripts.OnUpdate,
        "the center did not follow native dressing-room rotation and zoom after reset")
    input.scripts.OnMouseWheel(input, -100)
    assert(camera:GetZoomDistance() > 6 and camera:GetZoomDistance() == camera:GetMaxZoomDistance(),
        "wheel-down could not zoom out, or escaped the far limit")
    input.scripts.OnMouseWheel(input, 100)
    assert(camera:GetZoomDistance() > 0 and camera:GetZoomDistance() == camera:GetMinZoomDistance(),
        "wheel-up escaped the near limit")
    local previousCamera = camera
    camera = NewCamera(2, 12, 7)
    input.scripts.OnMouseWheel(input, 1)
    assert(camera.near == 2 and camera.far == 12 and math.abs(camera:GetZoomDistance() - 6) < 1e-9,
        "working native zoom limits were replaced")
    assert(previousCamera:GetZoomDistance() == previousCamera:GetMinZoomDistance(), "a stale camera received the wheel")
    input.scripts.OnMouseDown(input, "LeftButton")
    cursorX = cursorX - 20
    input.scripts.OnUpdate(input)
    assert(camera.yaw > 0, "drag-left did not follow the native camera direction")
    mouseDown = false
    input.scripts.OnUpdate(input)
    assert(not input.scripts.OnUpdate, "native drag kept polling after release outside its viewport")
    mouseDown = true
    input.scripts.OnMouseDown(input, "LeftButton")
    input.scripts.OnHide(input)
    assert(not input.scripts.OnUpdate, "hidden native input kept polling")
    local wheelCalls = zoom
    camera.near = secretIdentity
    input.scripts.OnMouseWheel(input, 1)
    assert(zoom == wheelCalls, "secret camera limits reached native Lua zoom arithmetic")
    CharacterModelScene.IsVisible = function() return false end
    camera = NewCamera(6, 6, 6)
    input.scripts.OnMouseWheel(input, 1)
    assert(zoom == wheelCalls and camera.near == camera.far, "hidden native scene was changed")
    liveCombat = false
    CharacterModelScene = nil
    local overviewWidth, overviewLevel = full.right[1].panelWidth, full.right[1]:GetFrameLevel()
    local slotMask = full.nativeSlotMasks[1]
    assert(slotMask.mouseEnabled and slotMask:GetFrameLevel() > nativeLevel + layout.slotLevel
        and slotMask:GetFrameLevel() < nativeLevel + layout.reportLevel and slotMask.point[4] == nativeHand.alternateX
        and slotMask.point[5] == -nativeHand.y and slotMask.width == nativeHand.x - nativeHand.alternateX
        and not slotMask.scripts.OnClick and not full.gearMask:IsShown(), "Overview exposed an inactive slot hit region")

    local transparent = {
        IsEnabled = function() return true end,
        GetColor = function() return .2, .3, .4, .25 end,
        SkinFrame = function(_, target, style)
            if style.role == "navigation" then target.sharedTabMotion = style.motion end
            return true, "applied"
        end,
        SetActive = Noop, RefreshAll = Noop, ReleaseAll = Noop,
    }
    local overviewTab = full.tabButtons[1]
    assert(overviewTab.underline:IsShown(), "fallback selection lost its underline")
    full:RefreshAppearance(transparent)
    assert(overviewTab.sharedTabMotion == true and not overviewTab.underline:IsShown(),
        "themed tabs did not opt into shared selection motion or kept the snapping underline")
    assert(full.artMask.color[4] == 1 and full.reportMask.color[4] == 1 and full.gearMask.color[4] == 1,
        "theme opacity leaked the covered native paper doll through its report")
    liveCombat = true
    nativeLevel = nativeLevel + 12
    full:ShowGroups(groups)
    assert(not full.gear:IsShown() and full.reportCover:IsShown() and full.reportCover.mouseEnabled
        and full.reportCover:GetFrameLevel() == nativeLevel + layout.reportLevel and full.report.scroll.parent == full.reportCover
        and full.report.columns == 2, "the report can click through to native slots")
    full:ShowGear(gear.left, gear.right, gear.weapons, groups, nil, empty, false)
    assert(full.gear:IsShown() and not full.modelHost:IsShown() and not full.reportCover:IsShown()
        and full.gearMask:IsShown() and full.plate:GetFrameLevel() > nativeLevel + layout.modelLevel
        and full.right[1]:GetFrameLevel() > full.plate:GetFrameLevel()
        and full.right[1]:GetFrameLevel() < nativeLevel + layout.slotLevel,
        "Equipment did not hide the model beneath its original wide gear art")
    assert(full.right[1].panelWidth > overviewWidth and bodyX + full.right[1].panelX + 5 == nativeHand.alternateX
        and slotMask.point[4] == nativeHand.alternateX + nativeHand.size
        and slotMask.width == nativeHand.x - nativeHand.alternateX, "Equipment kept the inactive hit rectangle exposed")
    clicked = nil
    slotMask.scripts.OnClick(slotMask, "LeftButton")
    assert(clicked == hand.slot, "the Equipment mask blocked item details over the active card")
    local settled = writes
    full:ShowGear(gear.left, gear.right, gear.weapons, groups, nil, empty, false)
    assert(writes == settled, "unchanged Equipment rewrote native presentation state")
    full:ShowGear(gear.left, gear.right, gear.weapons, groups, nil, empty, true)
    assert(not full.gearMask:IsShown() and full.modelHost:IsShown() and full.right[1]:GetFrameLevel() == overviewLevel + 12
        and slotMask.point[4] == nativeHand.alternateX and not slotMask.scripts.OnClick,
        "returning to Overview kept the wider Equipment geometry active")
    scale = .9
    full:FitScreen()
    full:RefreshAppearance(nil)
    assert(overviewTab.underline:IsShown(), "leaving the skin lost the fallback selection")
    assert(frame:GetEffectiveScale() == .9 and not frame.scale and playerModels == beforeModels,
        "full native mode lost inherited scale or allocated a duplicate model")
    liveCombat = false

    local translucent = true
    transparent.GetLook = function() return "custom" end
    transparent.HasTranslucentShell = function() return translucent end
    local modelVisible, gamepad
    suite.GamepadUI = function() return gamepad == true end
    local previousSkin = ns.Host.Skin
    ns.Host.Skin = { CharacterGeometry = {
        SetGlass = function(root, surface, enabled, withModel)
            assert(root == native and surface == full.frame, "glass changed an unrelated native window")
            modelVisible = enabled and withModel
            return enabled, modelVisible
        end,
    } }
    close.caption.base:Show()
    full:RefreshAppearance(transparent)
    assert(not close.caption.base:IsShown() and close.caption.fill.color[4] == 0
        and close.caption.bars[1]:IsShown() and not close.mouseEnabled,
        "the Glass close glyph kept its resting tile or lost its native click path")
    suite.WindowCaption.SetHover(close, true)
    assert(not close.caption.base:IsShown() and close.caption.fill.color[4] > 0,
        "hover lost the close feedback or brought back the resting tile")
    suite.WindowCaption.SetHover(close, false)
    assert(full.artMask:GetAlpha() == 0 and full.headerFill:GetAlpha() < 1 and full.tabFill:GetAlpha() < 1 and modelVisible,
        "a custom palette with the same translucent shell retained opaque header bands and backing")
    assert(full.surfaces[full.plate].style.keepGlassFill == false
        and full.surfaces[full.rail.cards[1]].style.keepGlassFill == false,
        "the gear plate and stats cards filled over Forever Glass")
    full:ShowGroups(groups)
    assert(full.reportMask:GetAlpha() == 0 and not modelVisible and full.reportCover:IsShown(),
        "Forever Glass left the model behind the report or lost the report hit shield")
    local reportCard = full.report.cards[1]
    local reportSurface = full.surfaces[reportCard]
    local originalPainter = transparent.SkinFrame
    transparent.SkinFrame = function(self, target, style)
        if target == reportCard then return true, "deferred" end
        return originalPainter(self, target, style)
    end
    reportSurface.themed = false
    full:RefreshAppearance(transparent)
    assert(not reportSurface.fill:IsShown() and not reportSurface.border:IsShown(),
        "a deferred combat report skin put a solid card back over the translucent shell")
    transparent.SkinFrame = originalPainter
    full:ShowGear(gear.left, gear.right, gear.weapons, groups, nil, empty, false)
    assert(full.gearMask:GetAlpha() == 0 and not modelVisible and full.gearMask:IsShown(),
        "Forever Glass kept an opaque block when switching to Equipment")
    gamepad = true
    full:RefreshAppearance(transparent)
    assert(full.artMask:GetAlpha() == 1 and full.gearMask:GetAlpha() == 1,
        "the gamepad presentation did not restore native art")
    gamepad = false
    translucent = false
    transparent.GetLook = function() return "foreverGlass" end
    full:RefreshAppearance(transparent)
    assert(full.artMask:GetAlpha() == 1 and full.headerFill:GetAlpha() == 1 and close.caption.base:IsShown(),
        "the opaque shell or its native close cover was treated as Glass")
    full:RefreshAppearance(nil)
    assert(full.artMask:GetAlpha() == 1 and full.gearMask:GetAlpha() == 1 and full.headerFill:GetAlpha() == 1,
        "turning off Forever Glass did not restore the native covers")
    ns.Host.Skin = previousSkin

    local noSet = "No equipment set equipped"
    local wrappedRows = {
        { label = "Movement Speed", value = "100.00%" },
        { label = "Active set", value = noSet },
        { label = "Following row", value = "100" },
    }
    local wrappedReport = { { title = "Equipment sets", rows = wrappedRows } }
    local left = { { slot = 1, name = "Long Enchanted Helm of the Alliance", label = "Head" } }
    full:ShowGear(left, empty, empty, wrappedReport, nil, empty, true)
    local first, wrapped, nextRow = unpack(full.rail.cards[1].rows)
    assert(full.left[1].name.wordWrap and full.left[1].name.maxLines == 2, "gear names cannot use both lines")
    assert(wrapped.right.text == noSet and wrapped.right.wordWrap and wrapped.right.nonSpaceWrap,
        "the equipment set value has no word wrap")
    assert(wrapped.textSplit < first.textSplit and wrapped.panelHeight > first.panelHeight
        and nextRow.panelY == wrapped.panelY + wrapped.panelHeight,
        "the set value did not get horizontal room and push the next row down")
    local expandedHeight = full.rail.content
    wrappedRows[2].value = "Set 1"
    full:ShowGear(left, empty, empty, wrappedReport, nil, empty, true)
    assert(wrapped.panelHeight == first.panelHeight and full.rail.content < expandedHeight,
        "shorter text retained the wrapped row height")

    local longRows = {}
    for i = 1, 48 do longRows[i] = { label = "Row " .. i, value = i } end
    local longReport = { { title = "Long report", rows = longRows } }
    local function CheckOwnedScroll(list)
        assert(list.scroll.kind == "Frame" and not list.scroll.template and list.canvas.parent.clipsChildren
            and list.bar:IsShown(), "the Forever list lost its clipped viewport or scroll controls")
        local slider, offset = list.slider, list.offset
        local trackHeight = list.height - 30
        local expectedHeight = math.floor(trackHeight * list.height / list.content + .5)
        assert(slider.thumb.height == expectedHeight and slider.thumb.width >= 9
            and slider.width >= 16 and slider.thumb.color,
            "the thumb does not reflect visible content or lost its high-contrast treatment")
        assert(offset == 0 and slider.value == 0, "the top of the list placed the thumb at the wrong end")
        list.scroll.scripts.OnMouseWheel(list.scroll, -1)
        assert(list.offset == offset + 30 and list.canvas.point[3] == list.offset,
            "the wheel did not move the report canvas")
        list.down.scripts.OnClick(list.down)
        assert(list.offset == offset + 60 and slider.value == list.offset,
            "the forward stepper did not move the scrollbar with the report")
        list.up.scripts.OnClick(list.up)
        assert(list.offset == offset + 30, "the back stepper did not scroll back")
        local down = list.down
        down.IsMouseOver = function() return true end
        down.scripts.OnMouseDown(down, "LeftButton")
        down.scripts.OnUpdate(down, .31)
        down.scripts.OnMouseUp(down, "LeftButton")
        down.scripts.OnClick(down)
        assert(list.offset == offset + 60 and not down.scripts.OnUpdate,
            "the held stepper failed to repeat or moved a second time on release")
        slider:SetValue(list.range)
        assert(list.offset == list.range and list.cards[1].rows[1].left.text ~= "Row 1",
            "dragging to the bottom did not repaint the visible rows")
        local stop = Strict.Watch(path .. "GroupLayout.lua", { strict = true })
        local hiddenValue = Strict.New("number")
        list.scroll.scripts.OnMouseWheel(list.scroll, hiddenValue)
        slider.scripts.OnValueChanged(slider, hiddenValue)
        local violations = stop()
        assert(#violations == 0, table.concat(violations, " | "))
        assert(list.offset == list.range, "restricted input changed the visible offset")
        list.down.scripts.OnClick(list.down)
        assert(list.offset == list.range, "the bottom stepper scrolled past the last row")
        slider:SetValue(0)
        assert(list.offset == 0 and list.cards[1].rows[1].left.text == "Row 1",
            "dragging the thumb back up did not return to the first row")
    end
    full:ShowGear(gear.left, gear.right, gear.weapons, longReport, nil, empty, true)
    CheckOwnedScroll(full.rail)
    full:ShowGroups(longReport)
    CheckOwnedScroll(full.report)
    local smallThumb = full.report.slider.thumb.height
    for i = #longRows, 20, -1 do longRows[i] = nil end
    full:ShowGroups(longReport)
    assert(full.report.range > 0 and full.report.slider.thumb.height > smallThumb,
        "the thumb did not grow as the scroll range shortened")
    full:ShowGroups(groups)
    assert(full.report.offset == 0 and full.report.canvas.point[3] == 0 and not full.report.bar:IsShown(),
        "shortening the report did not clamp its position and hide the scrollbar")

    liveCombat = true
    full:ShowGear(gear.left, gear.right, gear.weapons, groups, nil, empty, true, true)
    assert(not full.rail.scroll:IsShown() and full.combatRail.canvas:IsShown(), "combat did not select the fixed rail")
    full:ShowGroups(groups, true)
    assert(not full.report.scroll:IsShown() and full.combatReport.canvas:IsShown(), "combat did not select the fixed report")
    liveCombat = false
    full:ShowGroups(longReport)
    assert(full.report.scroll:IsShown() and full.report.bar:IsShown() and not full.combatReport.canvas:IsShown(),
        "combat exit did not restore the report scrollbar")
end

print("Character Panel appearance: full native, hosted fallback, Inspect, preview, fonts, offsets and warm paint passed")
