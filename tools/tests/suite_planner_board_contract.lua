-- Real Board/Dialogs builders with the existing Suite native-frame fixture.
-- Geometry checks use stored anchors; font wrapping is a conservative offline estimate.
local root, locale = arg[1] or ".", arg[2] or "enUS"
local fixtureOnly = locale == "--fixture"
if fixtureOnly then locale = "enUS" end
local forever = arg[4] == "Forever"
local E = assert(loadfile(root .. "/tools/tests/suite_inventory_tools_fixture.lua"))().New(root, false)
local savedArgs = arg
arg = { root, "--fixture" }
local Fixture = assert(loadfile(root .. "/tools/tests/suite_planning_tools_contract.lua"))()
arg = savedArgs
local st, NS, S, Plan, owner, P = Fixture()
NS.Client.isForever = forever
local frame = E.S.CreateFrame("Frame")
local methods = getmetatable(frame).__index
local function Noop() end
for _, key in ipairs({ "SetJustifyV", "SetFontObject", "SetSpacing", "SetFrameStrata", "SetClampedToScreen",
    "SetMovable", "EnableMouse", "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetToplevel",
    "SetClipsChildren", "SetTextInsets", "SetVertexColor", "SetVerticalScroll", "SetRotation" }) do
    methods[key] = methods[key] or Noop
end
-- Animation groups finish at once offline; Play reports OnFinished like the client.
local animations = { playing = 0 }
local Animation = {}
Animation.__index = Animation
for _, key in ipairs({ "SetFromAlpha", "SetToAlpha", "SetDuration", "SetSmoothing", "SetScaleFrom", "SetScaleTo", "SetOrigin", "SetOffset" }) do
    Animation[key] = Noop
end
function Animation:SetOffset(x, y) self.offsetX, self.offsetY = x, y end
function Animation:SetScaleFrom(x, y) self.fromX, self.fromY = x, y end
function Animation:SetScaleTo(x, y) self.toX, self.toY = x, y end
function Animation:SetDuration(value) self.duration = value end
local Group = {}
Group.__index = Group
function Group:CreateAnimation() return setmetatable({}, Animation) end
function Group:SetScript(event, fn) self.scripts[event] = fn end
function Group:GetParent() return self.parent end
function Group:Stop() self.playing = nil end
function Group:IsPlaying() return self.playing == true end
function Group:Play()
    animations.playing = animations.playing + 1
    self.playing = true
    if animations.hold then return end
    self.playing = nil
    if self.scripts.OnFinished then self.scripts.OnFinished(self) end
end
function methods:CreateAnimationGroup() return setmetatable({ parent = self, scripts = {} }, Group) end
function methods:SetAlpha(value) self.alpha = value end
function methods:GetAlpha() return self.alpha or 1 end
function methods:HasFocus() return self.focused == true end
function methods:GetEffectiveScale() return 1 end
function methods:EnableKeyboard(value) self.keyboard = value end
function methods:SetPropagateKeyboardInput(value) self.propagate = value end
function methods:SetFrameStrata(value) self.strata = value end
function methods:SetPoint(point, relative, relativePoint, x, y)
    if type(relative) == "number" then x, y, relative, relativePoint = relative, relativePoint, self.parent, point
    elseif relative == nil then relative, relativePoint, x, y = self.parent, point, 0, 0 end
    self.points = self.points or {}
    self.points[#self.points + 1] = { point, relative or self.parent, relativePoint or point, x or 0, y or 0 }
end
function methods:SetAllPoints(relative) self.allPoints = relative or self.parent end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:SetColorTexture(r, g, b, a) self.color = { r, g, b, a or 1 } end
function methods:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a or 1 } end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetJustifyV(value) self.justifyV = value end
function methods:GetWidth() return self.width or 0 end
function methods:GetHeight() return self.height or 0 end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetFrameLevel(value) self.level = value end
function methods:SetNormalTexture(value) self.normalTexture = value end
function methods:SetHighlightTexture(value) self.highlightTexture = value end
function methods:SetPushedTexture(value) self.pushedTexture = value end
function methods:SetScale(value) self.scale = value end
function methods:GetScale() return self.scale or 1 end
function methods:IsEnabled() return self.enabled ~= false end
function methods:SetActive(value) self.active = value end
function methods:ClearAllPoints() self.points, self.allPoints = nil, nil end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetBackdropColor(...) self.backdropColor = { ... } end
function methods:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
function methods:EnableMouseWheel(value) self.mouseWheel = value end
function methods:SetMinMaxValues(low, high) self.minimum, self.maximum = low, high end
function methods:SetValueStep(value) self.step = value end
function methods:SetValue(value)
    value = math.max(self.minimum or value, math.min(self.maximum or value, value))
    self.value = value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function methods:GetValue() return self.value end
function methods:GetChildren()
    local children = {}
    for _, child in ipairs(E.frames) do if child.parent == self and child.kind ~= "FontString" and child.kind ~= "Texture" then children[#children + 1] = child end end
    return unpack(children)
end
function methods:GetRegions()
    local regions = {}
    for _, child in ipairs(E.frames) do if child.parent == self and (child.kind == "FontString" or child.kind == "Texture") then regions[#regions + 1] = child end end
    return unpack(regions)
end
function methods:GetPoint(index) return unpack(self.points[index or 1]) end
function methods:GetParent() return self.parent end
function methods:ClearFocus() self.focused = false end
function methods:GetStringHeight()
    local text = (self.text or ""):gsub("[\128-\191]", "")
    local lines = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines = lines + math.max(1, math.ceil(#line * (self.fontSize or 12) * .6 / math.max(1, self.width or 310)))
    end
    return lines * (self.fontSize or 12) * 1.2
end
local nativeFrame = E.S.CreateFrame
S.CreateFrame = function(kind, name, parent, template)
    local widget = nativeFrame(kind, name, parent, template)
    if widget.Instructions then widget.Instructions.parent = widget end
    if template == "UIPanelScrollBarTemplate" then widget.width = 16 end
    if template == "UIPanelButtonTemplate" then widget.nativeLabel = nativeFrame("FontString", nil, widget) end
    return widget
end
S.CreateTexture = function(parent, name, layer)
    local texture = S.CreateFrame("Texture", name, parent)
    texture.drawLayer = layer or "BACKGROUND"
    return texture
end
S.CreateFontString = function(parent) return S.CreateFrame("FontString", nil, parent) end
local font = { path = "PlannerFirst.ttf", calls = 0 }
function methods:SetFont(path, size, flags)
    self.fontPath, self.fontSize, self.fontFlags = path, size, flags
    self.fontWrites = (self.fontWrites or 0) + 1
    font.calls = font.calls + 1
    return true
end
function methods:GetFont() return self.fontPath or "Native.ttf", self.fontSize or 12, self.fontFlags or "" end
function methods:GetFontString() return self.nativeLabel or self._msuf2Label end
_G.GameFontHighlightSmall = { GetFont = function() return "Native.ttf", 12, "" end }
NS.Suite, NS.GlobalFontPath = S, function() return font.path end
NS.FontFileApplied = function(label, path) return label.fontPath == path end
NS.FontRendering = { SLUG = "slug", SHARP = "sharp" }
S.started, S.order, S.states = true, { "planningTools" }, { planningTools = { active = true } }
S.Apply = function(id) assert(id == "planningTools") owner:Refresh() end
_G.MSUF_FontApplyEpoch = 1
assert(loadfile(root .. "/MSUF_Suite/Core/FontBridge.lua"))("Test", NS)
local native = { materials = 0, buttons = 0, fonts = 0 }
local hostTheme = { colors = setmetatable({ text = { .9, .91, .92, 1 } }, {
    __index = function() return { .12, .13, .14, 1 } end,
}) }
function hostTheme.ApplyMaterial(widget, material)
    native.materials = native.materials + 1
    widget.nativeMaterial = material
end
function hostTheme.Button(parent, text, width, height)
    native.buttons = native.buttons + 1
    local button = S.CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button._msuf2Label = S.CreateFontString(button)
    button._msuf2Label:SetText(text)
    button._msuf2Label:SetPoint("LEFT", 10, 0)
    button._msuf2Label:SetPoint("RIGHT", -10, 0)
    button.RefreshVisual = Noop
    return button
end
function hostTheme.StyleFontString(label, color)
    native.fonts = native.fonts + 1
    if color then label:SetTextColor(unpack(color)) end
end
function hostTheme.ApplyButtonRole(button, role) button.role = role end
_G.MSUF2 = { Theme = hostTheme, GetControlLabel = function(button) return button._msuf2Label end }
local hostProfile = { general = {} }
NS.HostBridge = { CurrentFrameProfile = function() return hostProfile end }
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeMenu.lua"))("Test", NS)
_G.UIParent = S.CreateFrame("Frame")
UIParent:SetSize(1920, 1080)
_G.GameFontHighlight = {}
local translations = {}
if locale == "deDE" then
    _G.MSUF_NS = { LOCALE = locale, L = translations }
    assert(loadfile(root .. "/MSUF_Suite/Locales/deDE.lua"))()
end
S.Text = function(value) return translations[value] or value end
NS.Text, NS.Print = S.Text, S.Print
local savedSuite, surfaceProvider = _G.MSUFSuite, {}
_G.MSUFSuite = { Suite = surfaceProvider }
assert(loadfile(root .. "/MSUF_Suite_Modules/Surfaces.lua"))("Test", {})
_G.MSUFSuite = savedSuite
_G.RAID_CLASS_COLORS = { WARRIOR = { r = .78, g = .61, b = .43 } }
S.ClassRGB = surfaceProvider.ClassRGB
_G.GameTooltip = { lines = {} }
function GameTooltip:SetOwner(owner) self.owner = owner self.lines = {} end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function GameTooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " " .. right end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false self.owner = nil end
function GameTooltip:ClearLines() self.lines = {} end
function GameTooltip:SetText(text) self.lines = { text } end
function GameTooltip:GetOwner() return self.owner end
function GameTooltip:IsOwned(owner) return self.owner == owner end
_G.SlashCmdList = {}
assert(loadfile(root .. "/MSUF_Suite/Core/PlannerCommand.lua"))("Test", NS)
assert(loadfile(root .. "/MSUF_Suite_Modules/Dialogs.lua"))("Test", P)
for _, name in ipairs({ "PlanningOverview", "PlanningBoard", "PlanningBoardAppearance", "PlanningBoardScroll",
    "PlanningBoardMotion", "PlanningBoardNav", "PlanningMatrix", "PlanningMatrixView", "PlanningBoardRows", "PlanningBoardWindow" }) do
    assert(loadfile(root .. "/MSUF_Suite_AdventurePlanner/" .. name .. ".lua"))("Test", P)
end
local checks = 0
local function Check(value, label)
    checks = checks + 1
    assert(value, label)
end
local function Equal(actual, expected, label) Check(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
local function Anchor(point, width, height)
    local x = point:find("LEFT", 1, true) and 0 or point:find("RIGHT", 1, true) and width or width / 2
    local y = point:find("TOP", 1, true) and 0 or point:find("BOTTOM", 1, true) and height or height / 2
    return x, y
end
local function Rect(widget, depth)
    depth = (depth or 0) + 1
    assert(depth < 20, "cyclic native anchor")
    if widget == UIParent then return { x = 0, y = 0, w = widget.width, h = widget.height } end
    if widget.allPoints then return Rect(widget.allPoints, depth) end
    local width, height = widget.width or 0, widget.height or 0
    local points = widget.points or {}
    local p = points[1] or { "TOPLEFT", widget.parent, "TOPLEFT", 0, 0 }
    local relative = Rect(p[2] or widget.parent, depth)
    local rx, ry = Anchor(p[3], relative.w, relative.h)
    if #points > 1 and width == 0 then
        local last = points[#points]
        local r = Rect(last[2] or widget.parent, depth)
        local xx = Anchor(last[3], r.w, r.h)
        width = r.x + xx + last[4] - (relative.x + rx + p[4])
    end
    if #points > 1 and height == 0 then
        local last = points[#points]
        local r = Rect(last[2] or widget.parent, depth)
        local _, yy = Anchor(last[3], r.w, r.h)
        height = r.y + yy - last[5] - (relative.y + ry - p[5])
    end
    local ax, ay = Anchor(p[1], width, height)
    return { x = relative.x + rx + p[4] - ax, y = relative.y + ry - p[5] - ay, w = width, h = height }
end
local function Visible(widget)
    if widget.shown == false then return false end
    return not widget.parent or Visible(widget.parent)
end
local function Descendant(widget, parent)
    while widget do if widget == parent then return true end widget = widget.parent end
    return false
end
local function Inside(a, b)
    return a.x >= b.x and a.y >= b.y and a.x + a.w <= b.x + b.w and a.y + a.h <= b.y + b.h
end
local function Overlap(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end
local function Geometry(window)
    local panel, hitboxes = Rect(window), {}
    for _, widget in ipairs(E.frames) do
        if Descendant(widget, window) and Visible(widget) then
            Check(widget.scripts.OnUpdate == nil, "idle planner keeps an OnUpdate script")
            if widget.scripts.OnClick or widget.kind == "EditBox" or widget.kind == "Slider" or widget.scripts.OnDragStart then
                local box = Rect(widget)
                Check(box.w > 0 and box.h > 0, "interactive area has no dimensions")
                Check(Inside(box, panel), "interactive area extends beyond planner panel")
                if widget.parent == window.list then Check(Inside(box, Rect(window.list)), "character row extends beyond matrix") end
                for _, other in ipairs(hitboxes) do
                    Check(not Overlap(box, other.rect), "interactive planner areas overlap")
                end
                hitboxes[#hitboxes + 1] = { widget = widget, rect = box }
            end
        end
    end
    for _, tab in ipairs(window.tabs) do
        if Visible(tab) then
            Equal(tab.text.wordWrap, false, "rail labels stay on one line like Menu2's")
            Check(tab.text.height and tab.text.height > 0 and tab.text.height <= 42,
                "sidebar label must have an explicit bounded height")
            Check(Inside(Rect(tab.text), Rect(tab)), "sidebar label extends beyond its hitbox")
            local entry = window.spec.tabs[tab.index]
            if locale == "deDE" then Check(translations[entry.label] ~= nil, "German navigation label missing: " .. entry.label) end
            local text = (tab.text.text or ""):gsub("[\128-\191]", "")
            Check(#text * 12 * .6 <= tab.width - 20, "rail label estimate exceeds one line: " .. tab.text.text)
        end
    end
    return hitboxes
end
local function Fonts(window)
    local found = 0
    for _, node in ipairs(E.frames) do
        if Descendant(node, window) and (node.kind == "FontString" or node.kind == "EditBox") then
            found = found + 1
            Equal(node.fontPath, font.path, "every owned text surface follows the selected font")
        end
    end
    Check(found > 20, "font test covers labels, controls and comparison cells")
end
local function FontLifecycle(window)
    local captures, capture = 0, Plan.Weekly.Capture
    Plan.Weekly.Capture = function(...) captures = captures + 1 return capture(...) end
    S.ApplyGlobalFont()
    st.Flush()
    captures = 0
    local queued, frames = st.scheduled, #E.frames
    font.path = "PlannerChanged.ttf"
    S.ApplyGlobalFont()
    st.Flush()
    Fonts(window)
    Equal(captures, 0, "font-only path change does not recapture weekly data")
    Equal(st.scheduled, queued, "font-only path change schedules no refresh")
    local writes = font.calls
    _G.MSUF_FontApplyEpoch = _G.MSUF_FontApplyEpoch + 1
    S.ApplyGlobalFont()
    st.Flush()
    Check(font.calls > writes, "same-face recovery epoch reapplies fonts")
    Fonts(window)
    Equal(captures, 0, "font recovery does not recapture data")
    writes = font.calls
    S.ApplyGlobalFont()
    Equal(font.calls, writes, "unchanged font generation does no paint work")
    Plan.Board.Close(owner)
    font.path = "PlannerClosed.ttf"
    S.ApplyGlobalFont()
    st.Flush()
    Equal(window:IsShown(), false, "font change never opens a closed planner")
    Equal(captures, 0, "closed font change does not recapture data")
    Plan.Window.Open("characters")
    Fonts(window)
    st.Event("PLAYER_REGEN_DISABLED")
    writes = font.calls
    font.path = "PlannerCombat.ttf"
    S.ApplyGlobalFont()
    st.Flush()
    Equal(font.calls, writes, "combat font change does not paint planner")
    Equal(captures, 0, "combat font change does not read weekly data")
    Equal(st.scheduled, queued, "combat font change schedules no work")
    Equal(S.OpenPlanner(), false, "slash API cannot reopen in combat")
    st.Event("PLAYER_REGEN_ENABLED")
    st.Flush()
    Plan.Window.Open("characters")
    Fonts(window)
    Equal(#E.frames, frames, "font lifecycle creates no extra UI objects")
    Plan.Weekly.Capture = capture
end
if fixtureOnly then
    return { st = st, NS = NS, S = S, Plan = Plan, owner = owner, P = P, E = E,
        font = font, native = native, hostTheme = hostTheme, Geometry = Geometry, animations = animations,
        Rect = Rect, Visible = Visible, Descendant = Descendant }
end
owner:Enable()
st.Flush()
local account = Plan.Account()
account.characters = {}
for i = 1, 18 do
    account.characters["char-" .. i] = { name = string.format("Character %02d - VeryLongRealmName", i), at = st.time,
        character = string.format("Character %02d", i), realm = "VeryLongRealmName", classFile = "WARRIOR",
        reset = i == 18 and st.reset - 1 or st.reset, reward = i % 3 == 0,
        key = { name = "A saved dungeon", level = 12 },
        vault = { { kind = 2, index = 1, progress = 3, threshold = 4 }, { kind = 1, index = 1, progress = 2, threshold = 2 },
            { kind = 3, index = 1, progress = 0, threshold = 2 } },
        lockouts = { { name = "Saved Raid", difficulty = 16, expires = st.time + 3600, raid = true } } }
end
local unknown = { label = "Unknown character", snapshot = { at = st.time, realm = "Realm" }, detail = "Unknown snapshot" }
Check(Plan.Overview.Subtitle(unknown, st.time) ~= S.Text("%s • %d lockouts"):format("Realm", 0),
    "missing lockout snapshot must not display an authoritative zero")
Check(not Plan.Overview.Detail(unknown, st.time):find(S.Text("Active instance lockouts: %d"):format(0), 1, true),
    "unknown lockout details must not claim zero active lockouts")
unknown.snapshot.lockouts = {}
Check(Plan.Overview.Detail(unknown, st.time):find(S.Text("Active instance lockouts: %d"):format(0), 1, true) ~= nil,
    "known empty lockout reply must display zero")
local scheduled, timers = st.scheduled, 0
_G.C_Timer = { After = function() timers = timers + 1 end, NewTicker = function() timers = timers + 1 end }
Equal(Plan.Window.Open("characters"), true, "cold planner open")
local window, Board = Plan.Board.window, Plan.Board
local view = window.matrix
Check(view ~= nil, "weekly overview is an activity-row / character-column comparison matrix")
Equal(window, Plan.Window.host, "window route uses real dedicated Board")
Equal(#window.tabs, 8, "eight navigation widgets are reusable")
Equal(#window.spec.tabs, forever and 4 or 7, "all supported tools remain available; Mythic+ goals stay hidden for now")
-- The options page opens the planner tab it names: every section has a visible tab and every tab a section.
do
    local options = { Suite = { Client = { isForever = forever } }, RegisterPage = Noop }
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/PlanningTools.lua"))("Test", options)
    local sections, tabs = {}, {}
    for _, section in ipairs(options.PlannerSections) do
        if not section.hidden and not (section.retail and forever) then sections[section.key] = true end
    end
    for _, tab in ipairs(window.spec.tabs) do tabs[tab.key] = true end
    for key in pairs(sections) do Check(tabs[key], "options section " .. key .. " opens a visible planner tab") end
    for key in pairs(tabs) do Check(sections[key], "planner tab " .. key .. " has an options section") end
end
Equal(#window.buttons, Board.PAGE_ROWS + 1, "non-overview list is bounded: visible rows plus the scroll band")
Equal(#view.headers, 6, "six reusable character column headers")
Equal(#view.cells, 11, "ten taller activity rows plus the scroll band")
for _, row in ipairs(view.cells) do Equal(#row, 6, "six reusable cells per activity") end
Equal(#view.model.columns, 18, "model sees every saved character")
Equal(view.headers[1].character.key, "char-1", "first column is first sorted character")
Equal(view.realms[1].textColor[1], .78, "the realm under each character pill uses its class color")
Check(native.materials >= 3, "actual HostBridge reaches native MSUF material provider")
-- Actions, close, search clear, column paging and headers; the rail paints its own rows.
Check(native.buttons >= 16, "actual HostBridge creates native MSUF controls")
Check(window.nativeMaterial ~= nil and window.close.plannerNativeButton, "shell and close use MSUF native appearance")
local function Cell(kind, field, value)
    for i, activity in ipairs(view.rows) do
        if activity.kind == kind and (not field or activity[field] == value) then
            view.scroller:SetOffset(math.max(0, (i - 4) * Plan.Matrix.ROW_HEIGHT))
            break
        end
    end
    for _, row in ipairs(view.cells) do
        for _, cell in ipairs(row) do
            local a = cell.activity
            if cell.character and a and a.kind == kind and (not field or a[field] == value) then return cell end
        end
    end
end
local progress = forever and Cell("lockout") or Cell("vault", "rewardType", 2)
Check(progress ~= nil, "first viewport includes useful comparison activities")
Equal(progress.text:GetText(), forever and S.Text("Saved") or S.Text("%d / %d"):format(3, 4),
    "matrix shows character-specific activity state")
progress.scripts.OnEnter(progress)
Equal(GameTooltip.owner, progress, "hover details belong to exact matrix cell")
Check(table.concat(GameTooltip.lines, "\n"):find("Character 01", 1, true) ~= nil, "hover names its character")
if not forever then
    Check(table.concat(GameTooltip.lines, "\n"):find(S.Text("%s slot %d: %d / %d"):format(Plan.Weekly.KindLabel(2), 1, 3, 4), 1, true) ~= nil,
        "vault hover preserves exact recorded threshold")
end
progress.scripts.OnLeave(progress)
Equal(GameTooltip.shown, false, "hover tooltip closes")
progress.scripts.OnEnter(progress)
local foreignTooltipOwner = {}
GameTooltip:SetOwner(foreignTooltipOwner)
GameTooltip:Show()
progress.scripts.OnLeave(progress)
Equal(GameTooltip.owner, foreignTooltipOwner, "leaving a matrix cell preserves another tooltip owner")
Equal(GameTooltip.shown, true, "leaving a matrix cell cannot close another frame's tooltip")
Equal(Plan.Matrix.tooltipOwner, nil, "leaving releases the planner ownership marker")
GameTooltip:Hide()
Geometry(window)
local count = #E.frames
window.search:SetText("Character 18")
Equal(#view.columns, 1, "character search filters comparison columns")
Equal(view.headers[1].character.key, "char-18", "search preserves exact character identity")
Check(window.selected == nil or window.selected == "char-18", "character search must not leave an invisible different character selected")
if not forever then
    Equal(Cell("vault", "rewardType", 2).text:GetText(), S.Text("%d / %d"):format(0, 4), "offline since the reset shows no progress")
end
window.search:SetText("missing character")
Equal(#view.rows, 0, "unmatched search has no activity rows")
Equal(window.actions[2].enabled, false, "empty search cannot act on an invisible selected character")
for _, row in ipairs(view.cells) do for _, cell in ipairs(row) do Check(not Visible(cell), "unmatched search leaves no stale clickable cells") end end
window.search:SetText("Saved Raid")
Equal(#view.columns, 18, "activity search keeps all character columns")
Check(Cell("lockout") ~= nil, "activity search finds saved lockout row")
window.search:SetText("")
view.next:Click()
Equal(view.characterOffset, 6, "next page advances six character columns")
local visibleSelection = window.selected == nil
for _, header in ipairs(view.headers) do
    if header.character and header.character.key == window.selected then visibleSelection = true end
end
Check(visibleSelection, "character pagination cannot retain an offscreen action target")
view.headers[2]:Click()
Equal(window.selected, view.columns[8].key, "header selects its own character")
view.previous:Click()
Equal(view.characterOffset, 0, "previous returns to first character columns")
for _, tab in ipairs(window.tabs) do if Visible(tab) then tab:Click() Geometry(window) end end
for _ = 1, 3 do
    Board.Close(owner)
    Equal(window.owner, nil, "close releases owner")
    Equal(window.spec, nil, "close releases spec")
    Equal(#window.items, 0, "close releases row model")
    Equal(#window.filtered, 0, "close releases filtered model")
    Equal(view.model, nil, "close releases comparison model")
    for _, row in ipairs(view.cells) do
        for _, cell in ipairs(row) do Equal(cell.character, nil, "close releases cell character") Equal(cell.activity, nil, "close releases cell activity") end
    end
    Equal(Plan.Window.Open("characters"), true, "reopen planner")
    Equal(Plan.Board.window, window, "reopen reuses window")
    Equal(#E.frames, count, "reopen creates no frames or regions")
end
SlashCmdList.MSUFPLANNER()
Equal(window:IsShown(), false, "/plan toggles an open planner closed")
SlashCmdList.MSUFPLANNER()
Equal(window:IsShown(), true, "/plan opens cached planner")
Equal(window.spec.currentTab(owner), "characters", "/plan opens the character overview")
Equal(st.scheduled, scheduled, "slash toggles do not schedule data capture")
local cursorX, cursorY, mouseDown = 800, 400, false
GetCursorPosition = function() return cursorX, cursorY end
IsMouseButtonDown = function() return mouseDown end
function methods:GetEffectiveScale()
    return self:GetScale() * (self.parent and self.parent:GetEffectiveScale() or 1)
end
function methods:GetLeft()
    local ratio = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local point = self.points[1]
    if point[1] == "TOPLEFT" then return point[4] end
    return UIParent:GetWidth() / (2 * ratio) - self:GetWidth() / 2
end
function methods:GetTop()
    local ratio = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local point = self.points[1]
    if point[1] == "TOPLEFT" then return UIParent:GetHeight() / ratio + point[5] end
    return UIParent:GetHeight() / (2 * ratio) + self:GetHeight() / 2
end
local function Drag(dx, dy)
    mouseDown = true
    window.scaleGrip.scripts.OnMouseDown(window.scaleGrip, "LeftButton")
    cursorX, cursorY = cursorX + dx, cursorY - dy
    window.scaleGrip.scripts.OnUpdate(window.scaleGrip)
    mouseDown = false
    window.scaleGrip.scripts.OnMouseUp(window.scaleGrip, "LeftButton")
end
Drag(-120, -120)
Check(window:GetScale() < 1, "bottom-right drag shrinks the entire planner")
Equal(window.scaleGrip.scripts.OnUpdate, nil, "mouse release stops resize driver")
local savedScale = window:GetScale()
Board.Close(owner)
Plan.Window.Open("characters")
Equal(window:GetScale(), savedScale, "dragged scale survives reopening")
local left = window:GetLeft() * window:GetEffectiveScale()
local top = window:GetTop() * window:GetEffectiveScale()
Drag(80, 80)
Check(window:GetScale() > savedScale, "bottom-right drag enlarges the entire planner")
Check(math.abs(window:GetLeft() * window:GetEffectiveScale() - left) < .01, "resize keeps left edge fixed")
Check(math.abs(window:GetTop() * window:GetEffectiveScale() - top) < .01, "resize keeps top edge fixed")
Plan.Account().windowScale = 1.5
UIParent:SetSize(1024, 768)
Board.Close(owner)
Plan.Window.Open("characters")
Check(window:GetScale() > 0 and window:GetScale() < 1, "small viewport scales planner to fit")
Check(window.width * window:GetScale() <= 984 and window.height * window:GetScale() <= 728, "scaled planner fits viewport margins")
local capped = window:GetScale()
Drag(-80, -80)
Check(window:GetScale() < capped, "drag shrinks immediately from the screen-fit cap")
mouseDown = true
window.scaleGrip.scripts.OnMouseDown(window.scaleGrip, "LeftButton")
Board.Close(owner)
Equal(window.scaleGrip.scripts.OnUpdate, nil, "hide aborts active resize")
UIParent:SetSize(1920, 1080)
Plan.Account().windowScale = nil
Plan.Window.Open("characters")
mouseDown = true
window.scaleGrip.scripts.OnMouseDown(window.scaleGrip, "LeftButton")
st.combat = true
window.scaleGrip.scripts.OnUpdate(window.scaleGrip)
Equal(window.scaleGrip.scripts.OnUpdate, nil, "combat aborts resize")
Equal(Plan.Account().windowScale, nil, "combat does not save a resize")
st.combat, mouseDown = false, false
local originalProfile = NS.DB
NS.DB = {}
window:Refresh()
Equal(window:IsShown(), false, "profile replacement closes stale planner")
NS.DB = originalProfile
Plan.Window.Open("characters")
st.Event("PLAYER_REGEN_DISABLED")
Equal(window:IsShown(), false, "combat entry closes planner")
Equal(window.owner, nil, "combat close releases owner")
Equal(Plan.Window.Open("characters"), false, "combat cannot reopen planner")
Equal(timers, 0, "Board installs no timers or tickers")
Equal(#E.frames, count, "full lifecycle creates no additional frames")
Equal(st.scheduled, scheduled, "UI interactions schedule no planner refresh")
st.Event("PLAYER_REGEN_ENABLED")
st.Flush()
-- Largest supported account: no eager details and fixed 6 x 10 widgets.
local originalCharacters = account.characters
account.characters = {}
for i = 1, 200 do
    local lockouts = {}
    for j = 1, 80 do lockouts[j] = { name = "Saved Raid " .. j, difficulty = 16, expires = st.time + 3600, raid = true } end
    account.characters["large-" .. i] = { name = string.format("Character %03d - Realm", i), realm = "Realm",
        at = st.time, reset = st.reset, vault = {}, lockouts = lockouts }
end
Plan.Changed()
local dates, originalDate = 0, Plan.Date
Plan.Date = function(...) dates = dates + 1 return originalDate(...) end
Plan.Window.tab = "characters"
local largeRows = Plan.Window.Rows()
Equal(#largeRows, 200, "complete supported account")
Equal(dates, 0, "matrix model does not format unselected details")
for _, row in ipairs(largeRows) do Equal(row.detail, nil, "matrix rows defer detail strings") end
local detail = Plan.Overview.Detail(largeRows[1], st.time)
Check(detail:find("Saved Raid 80", 1, true) ~= nil, "selected details preserve every known lockout")
Check(dates > 0 and dates <= 81, "explicit selected detail formats only one character")
dates = 0
Plan.Window.Open("characters")
Check(dates <= 6, "overview paint formats at most six visible last-seen labels")
Equal(#view.model.columns, 200, "comparison model keeps 200 character columns")
Check(#view.model.rows > 14, "many activities scroll within same widget pool")
view.scroller:SetOffset(20 * Plan.Matrix.ROW_HEIGHT)
Equal(view.rowOffset, 20, "activity scrollbar advances row viewport")
Geometry(window)
for _ = 1, 34 do view.next:Click() end
Equal(view.characterOffset, 198, "last page is clamped to 200 characters")
Equal(view.headers[2].character.key, "large-200", "last character remains reachable")
Equal(view.headers[3]:IsShown(), false, "unused final-page columns hidden")
dates = 0
window.search:SetText("Character 200")
Equal(#view.columns, 1, "large-account search selects one column")
Equal(view.rowOffset, 0, "search resets activity scroll")
Equal(view.characterOffset, 0, "search resets character page")
Check(dates <= 1, "search paints only visible selected last-seen text")
Equal(#E.frames, count, "200 characters and 80 lockouts create no per-record widgets")
Plan.Date = originalDate
account.characters = originalCharacters
Plan.Changed()
Plan.Window.Open("characters")
FontLifecycle(window)
Check(native.materials > 3, "font restyle still goes through native material bridge")
Equal(timers, 0, "all planner interactions keep timer count zero")
-- Motion, smooth scrolling and combat. Only a moving scroller or a playing
-- animation runs code; combat entry stops all of it at once.
_G.InCombatLockdown = function() return false end
_G.IsShiftKeyDown = function() return false end
local function Scripts(root)
    local found = 0
    for _, widget in ipairs(E.frames) do
        if Descendant(widget, root) and widget.scripts.OnUpdate then found = found + 1 end
    end
    return found
end
local synthetic = {}
for i = 1, 40 do synthetic[i] = { key = "row-" .. i, label = "Synthetic row " .. i, detail = string.rep("Detail line" .. string.char(10), 80) } end
local synthSpec = { tabs = { { key = "notes", label = "Instance notes and checklists", nav = "Notes", group = "tools" } },
    rows = function() return { unpack(synthetic) } end, currentTab = function() return "notes" end, selectTab = Noop,
    actions = { Plan.Window.Action("Delete note", Noop, true, "danger"), Plan.Window.Action("Refresh", Noop) } }
Equal(Board.Open(owner, synthSpec), window, "a list page opens in the shared board")
Equal(#window.filtered, 40, "list page shows every row")
local chosen = {}
synthSpec.onSelect = function(_, row) chosen[#chosen + 1] = row.key end
Board.RowClicked(window.buttons[2], "LeftButton")
Equal(chosen[1], "row-2", "choosing another row reports it to the page")
Board.RowClicked(window.buttons[2], "LeftButton")
Equal(#chosen, 1, "choosing the selected row again reports nothing")
synthSpec.onSelect = nil
local bar = window.listScroll.bar
window.listScroll:Wheel(-1)
Check(bar.scripts.OnUpdate ~= nil, "wheel eases through a temporary driver")
local ticks = 0
while bar.scripts.OnUpdate and ticks < 200 do
    bar.scripts.OnUpdate(bar, 1 / 60)
    ticks = ticks + 1
end
Check(ticks > 1 and ticks < 200, "wheel motion settles within a bounded number of frames")
Equal(window.listScroll.offset, 2 * Board.ROW_HEIGHT, "one wheel notch moves two list rows")
Equal(window.offset, 2, "the row pool follows the eased offset")
Equal(window.buttons[1].text.text, "Synthetic row 3", "the pool repaints its new first row")
Equal(Scripts(window), 0, "a settled scroll leaves no OnUpdate script")
Geometry(window)
window.listScroll:SetOffset(Board.ROW_HEIGHT * 2.5)
Equal(window.buttons[#window.buttons]:IsShown(), true, "a fractional offset shows the band below the clip edge")
window.listScroll:SetOffset(0)
Equal(window.buttons[#window.buttons]:IsShown(), false, "an exact offset hides the extra band")
window.scripts.OnKeyDown(window, "W")
Equal(window.propagate, true, "other keys reach the game")
Equal(window:IsShown(), true, "other keys leave the planner open")
window.scripts.OnKeyDown(window, "ESCAPE")
Equal(window.propagate, false, "the planner consumes Escape")
Equal(window:IsShown(), false, "Escape closes the planner")
animations.hold = true
Board.Open(owner, synthSpec)
Check(window.openMotion:IsPlaying(), "opening plays MSUF's popup motion")
window.listScroll:Wheel(-1)
window.detailScroll:SetRange(2000, 400)
window.detailScroll:Wheel(-1)
Equal(Scripts(window), 2, "list and details ease at the same time")
st.Event("PLAYER_REGEN_DISABLED")
Equal(window:IsShown(), false, "combat hides a moving planner at once")
Equal(Scripts(window), 0, "combat leaves no OnUpdate script in the planner")
Check(not window.openMotion:IsPlaying() and not window.closeMotion:IsPlaying() and not window.pageMotion:IsPlaying(),
    "combat stops every planner animation")
Equal(window:GetAlpha(), 1, "combat restores the resting alpha")
st.Event("PLAYER_REGEN_ENABLED")
st.Flush()
Board.Open(owner, synthSpec)
Board.Dismiss(owner)
Equal(window:IsShown(), true, "a user close plays the exit before hiding")
Check(window.closeMotion:IsPlaying(), "the exit motion plays")
st.Event("PLAYER_REGEN_DISABLED")
Equal(window:IsShown(), false, "combat during the exit hides at once")
Equal(window.plannerClosing, nil, "combat clears the pending exit")
st.Event("PLAYER_REGEN_ENABLED")
st.Flush()
animations.hold = nil
hostTheme.ReducedMotionEnabled = function() return true end
local plays = animations.playing
Board.Open(owner, synthSpec)
window.listScroll:Wheel(-1)
Equal(animations.playing, plays, "reduced motion plays no animation")
Equal(Scripts(window), 0, "reduced motion scrolls without a driver")
Equal(window.listScroll.offset, 2 * Board.ROW_HEIGHT, "reduced motion jumps to the target")
hostTheme.ReducedMotionEnabled = nil
Board.Close(owner)
-- Before Menu2 loads, the host profile's own reduced-motion field decides.
hostProfile.general.reduceMotion = true
plays = animations.playing
Board.Open(owner, synthSpec)
window.listScroll:Wheel(-1)
Equal(animations.playing, plays, "the host profile's reduced motion applies without Menu2")
Equal(Scripts(window), 0, "profile reduced motion scrolls without a driver")
hostProfile.general.reduceMotion = nil
Board.Close(owner)
Equal(#E.frames, count, "motion and scrolling create no frames")
Plan.Window.Open("characters")
-- The alt overview at a glance: season bests, this week's runs, boss lists
-- and gold land in their cells, tooltips and the header.
local rich = account.characters["char-1"]
rich.season, rich.rating, rich.level, rich.ilvl, rich.money, rich.zone = 15, 2450, 80, 712.4, 12345678, "Dornogal"
rich.dungeons = { { id = 1, level = 12, score = 300, timed = true } }
rich.runs = { { map = 1, level = 14, completed = true } }
rich.lockouts[1].bosses, rich.lockouts[1].defeated = 2, 1
rich.lockouts[1].encounters = { { name = "First Boss", killed = true }, { name = "Second Boss", killed = false } }
Plan.Changed()
Plan.Window.Open("characters")
local function RichCell(kind, field, value)
    for i, activity in ipairs(view.rows) do
        if activity.kind == kind and (not field or activity[field] == value) then
            view.scroller:SetOffset(math.max(0, (i - 4) * Plan.Matrix.ROW_HEIGHT))
            break
        end
    end
    for _, row in ipairs(view.cells) do
        for _, cell in ipairs(row) do
            local a = cell.activity
            if cell.character and cell.character.key == "char-1" and a and a.kind == kind and (not field or a[field] == value) then
                return cell
            end
        end
    end
end
local totalGold = 0
for _, entry in pairs(account.characters) do totalGold = totalGold + (entry.money or 0) end
Check(totalGold > 12345678 and window.summary.text:find(math.floor(totalGold / 10000) .. GOLD_AMOUNT_SYMBOL, 1, true) ~= nil,
    "the header totals the gold of every character")
Equal(RichCell("field", "field", "ilvl").text:GetText(), "712.4", "item level per character")
Equal(RichCell("field", "field", "money").text:GetText(), "1234" .. GOLD_AMOUNT_SYMBOL, "gold per character")
if not forever then
    Equal(RichCell("dungeon").text:GetText(), "+12", "the season best of each dungeon")
    Equal(RichCell("summary", "field", "key").text:GetText(), "A saved dungeon", "overview visibly names the character keystone")
    local keyCell = RichCell("summary", "field", "key")
    Equal(keyCell.keyLevel:GetText(), "+12", "keystone level has its own visible line")
    Check(keyCell.keyLevel:IsShown(), "level does not depend on dungeon-name wrapping")
    Equal(RichCell("runs").text:GetText(), "1 (+14)", "this week's runs and the highest key")
    local runs = RichCell("runs")
    runs.scripts.OnEnter(runs)
    Check(table.concat(GameTooltip.lines, "\n"):find("+14", 1, true) ~= nil, "the runs tooltip lists this week's keys")
    runs.scripts.OnLeave(runs)
end
view.scroller:SetOffset(view.scroller.max)
local lockout = RichCell("lockout")
Check(lockout ~= nil, "lockouts are reachable by scrolling")
Equal(lockout.text:GetText(), S.Text("%d / %d"):format(1, 2), "a lockout shows defeated of all bosses")
local lockBand = lockout:GetParent()
Equal(lockBand.difficulty:GetText(), "Difficulty 16", "full difficulty is visible below the raid name")
Check(lockBand.difficulty:IsShown(), "difficulty is not confined to a tooltip")
lockout.scripts.OnEnter(lockout)
local lines = table.concat(GameTooltip.lines, "\n")
Check(lines:find("First Boss", 1, true) ~= nil and lines:find("Second Boss", 1, true) ~= nil, "the lockout tooltip names every boss")
lockout.scripts.OnLeave(lockout)
view.scroller:SetOffset(0)
local folding
for _, band in ipairs(view.bands) do
    if band.activity and band.activity.key == (forever and "character" or "mythic") then folding = band end
end
Check(folding ~= nil and folding.toggle:IsShown(), "a section header is a fold toggle")
local before = #view.rows
folding.toggle:Click()
Check(#view.rows < before, "a folded section hides its rows")
Equal(Plan.Account().overviewFolded[forever and "character" or "mythic"], true, "the folded state is saved")
folding.toggle:Click()
Equal(#view.rows, before, "unfolding restores the rows")
Equal(#E.frames, count, "the richer overview creates no frames")
-- The planner's existing text editor follows the same live font path too.
assert(loadfile(root .. "/MSUF_Suite_Modules/ToolListWindow.lua"))("Test", P)
local function OpenEditor()
    Plan.Window.Edit("Dungeon target", "Target keystone level (2–99)", "22", 2, function() return true end)
end
OpenEditor()
local editor
for _, node in ipairs(E.frames) do
    if node.owner == owner and node.input and node.save and node.cancel then editor = node end
end
Check(editor ~= nil, "planner invokes the actual shared editor")
Equal(editor.strata, "FULLSCREEN_DIALOG", "the editor stays above the planner's nested content")
window.scripts.OnKeyDown(window, "ESCAPE")
Equal(editor:IsShown(), false, "Escape closes the open editor first")
Equal(window:IsShown(), true, "the planner stays open behind a closed editor")
OpenEditor()
local editorFrames, captures, capture = #E.frames, 0, Plan.Weekly.Capture
Plan.Weekly.Capture = function(...) captures = captures + 1 return capture(...) end
font.path = "PlannerEditor.ttf"
S.ApplyGlobalFont()
st.Flush()
for _, node in ipairs(E.frames) do
    if Descendant(node, editor) and (node.kind == "FontString" or node.kind == "EditBox") and node:GetText() ~= "" then
        Equal(node.fontPath, font.path, "every visible editor string follows global font including close")
    end
end
Equal(editor.save:GetFontString().fontPath, font.path, "editor native save font follows host")
Equal(editor.cancel:GetFontString().fontPath, font.path, "editor native cancel font follows host")
Equal(captures, 0, "editor font update does not recapture planner data")
editor.cancel:Click()
Equal(editor:IsShown(), false, "editor cancel closes")
Equal(editor.input:GetText(), "", "editor close releases typed content")
OpenEditor()
Equal(#E.frames, editorFrames, "editor reopen reuses frames")
st.Event("PLAYER_REGEN_DISABLED")
Equal(editor:IsShown(), false, "combat closes actual editor")
local writes = font.calls
font.path = "PlannerEditorCombat.ttf"
S.ApplyGlobalFont()
st.Flush()
Equal(font.calls, writes, "combat font change leaves editor dormant")
Equal(captures, 0, "combat editor never captures data")
st.Event("PLAYER_REGEN_ENABLED")
st.Flush()
Plan.Weekly.Capture = capture
-- Final clean overview for an optional offline preview export.
Plan.Window.Open("characters")
if arg[3] and arg[3] ~= "-" then
    local function Quote(text)
        return '"' .. tostring(text):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
    end
    local output = assert(io.open(arg[3], "wb"))
    output:write('{"offline":true,"hostAppearance":"instrumented-native-provider","locale":', Quote(locale), ',"width":1180,"height":720,"nodes":[')
    local first, origin, ids = true, Rect(window), {}
    for i, widget in ipairs(E.frames) do ids[widget] = i end
    local function Color(value)
        if not value then return "null" end
        return string.format("[%s,%s,%s,%s]", value[1], value[2], value[3], value[4])
    end
    for _, widget in ipairs(E.frames) do
        if Descendant(widget, window) and Visible(widget) then
            local box = Rect(widget)
            if not first then output:write(',') end
            first = false
            output:write('{"id":', tostring(ids[widget]), ',"parent":', tostring(ids[widget.parent] or 0),
                ',"kind":', Quote(widget.kind or "Frame"), ',"x":', tostring(box.x - origin.x),
                ',"y":', tostring(box.y - origin.y), ',"width":', tostring(box.w), ',"height":', tostring(box.h),
                ',"text":', Quote(widget.text or ''), ',"fontSize":', tostring(widget.fontSize or 12),
                ',"color":', Color(widget.color), ',"textColor":', Color(widget.textColor),
                ',"drawLayer":', Quote(widget.drawLayer or ''), ',"wrap":', tostring(widget.wordWrap == true),
                ',"justifyH":', Quote(widget.justifyH or "LEFT"), ',"justifyV":', Quote(widget.justifyV or "TOP"),
                ',"scrollChild":', tostring(ids[widget.child] or 0), '}')
        end
    end
    output:write(']}') output:close()
end
print("suite_planner_board_contract: " .. (forever and "Forever " or "Mainline ") .. locale .. " " .. checks .. " checks; " .. count .. " frames/regions; zero lifecycle growth")
