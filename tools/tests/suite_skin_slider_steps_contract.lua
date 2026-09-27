-- Exercise the standalone Skin options widgets and pages through their
-- scripts: slider steps, the hex color entry, combat gating, the dropdown
-- filter, the factory reset arm and the page refreshers.
local refreshers = {}
local frames = {}
local function Frame()
    local frame = { scripts = {}, events = {} }
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:GetScript(event) return self.scripts[event] end
    function frame:SetValue(value)
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
    function frame:GetValue() return self.value end
    function frame:SetValueStep(value) self.step = value end
    function frame:CreateTexture() return Frame() end
    function frame:SetText(text) self.text = text end
    function frame:GetText() return self.text end
    function frame:SetFocus() self.focused = true end
    function frame:HasFocus() return self.focused == true end
    -- Like the client, losing focus runs OnEditFocusLost.
    function frame:ClearFocus()
        if not self.focused then return end
        self.focused = false
        if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
    end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown ~= false end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:GetFont() return "font.ttf", 12, "" end
    function frame:GetHeight() return 20 end
    function frame:ClearAllPoints() self.clears = (self.clears or 0) + 1 end
    -- Other widget methods are no-ops; plain fields stay nil.
    return setmetatable(frame, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return function() end end
    end })
end
CreateFrame = function(kind)
    local frame = Frame()
    frame.kind = kind
    frames[#frames + 1] = frame
    return frame
end

local locked = false
local colors = { accent = { 0.2, 0.4, 0.6, 1 } }
local setColors = 0
local NS = {
    path = "",
    IsCombatLocked = function() return locked end,
    L = setmetatable({}, { __index = function(_, key) return key end }),
    DB = { theme = { look = "midnight", preset = "midnight" } },
    Safety = { Read = function(target, name)
        if type(target) == "table" and type(target[name]) == "function" then return target[name](target) end
    end },
    Surface = {
        SkinOwnedButton = function() return {} end,
        Attach = function() return {} end,
        SetActive = function() end,
    },
    Checkmarks = { TrackButton = function() end },
    WindowActionSkin = { Apply = function() end },
}
NS.Theme = {
    GetColor = function() return 1, 1, 1, 1 end,
    GetColorTable = function(key) return colors[key] end,
    -- Like the engine: an edited color turns the look into a custom one.
    SetColor = function(key, r, g, b, a)
        if locked then return false end
        setColors = setColors + 1
        colors[key] = { r, g, b, a }
        NS.DB.theme.look, NS.DB.theme.preset = "custom", "custom"
        return true
    end,
}
local restores = {}
NS.Theme.RestoreColor = function(key, r, g, b, a, preset, look)
    if locked then return false end
    restores[#restores + 1] = { key = key, preset = preset, look = look }
    colors[key] = { r, g, b, a }
    NS.DB.theme.preset, NS.DB.theme.look = preset, look
    return true
end
local history = { begins = 0, commits = 0, cleared = 0 }
local lastText
local texts = {}
local panels = {}
local O = {
    widgetStates = {},
    CreatePanel = function()
        local panel = Frame()
        panels[#panels + 1] = panel
        return panel
    end,
    CreateText = function(_, value)
        local text = Frame()
        text.text = value
        lastText = text
        texts[#texts + 1] = text
        return text
    end,
    SetTextColor = function(text, role) if text then text.role = role end end,
    TrackRefresh = function(callback) refreshers[#refreshers + 1] = callback end,
    BeginUserChange = function()
        if locked then return false end
        history.begins = history.begins + 1
        return true
    end,
    CommitUserChange = function() history.commits = history.commits + 1 end,
    DiscardLastChange = function() history.cleared = history.cleared + 1 end,
    RefreshAll = function() for _, callback in ipairs(refreshers) do callback() end end,
}
-- Retail and Forever always have these; no modifier is held and the click
-- sound goes nowhere unless a check below listens.
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return false end
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1 }
PlaySound = function() end
local widgetsPrivate = { NS = NS, Options = O }
for _, file in ipairs({ "Widgets", "WidgetsDropdown", "WidgetsInput", "WidgetsColor" }) do
    assert(loadfile("MSUF_Suite_Skin_Options/Shell/" .. file .. ".lua"))("MSUF_Suite_Skin_Options",
        widgetsPrivate)
end

local function Slider(minimum, maximum, step, initial)
    local value = initial
    local row = O.CreateSlider(Frame(), "test", minimum, maximum, step,
        function() return value end, function(nextValue) value = nextValue end)
    return row._mskinControl, function() return value end
end
local function Near(actual, expected)
    assert(math.abs(actual - expected) < 0.000001,
        ("expected %s, got %s"):format(expected, actual))
end

local whole, wholeValue = Slider(0, 100, 5, 50)
assert(whole.step == 1, "whole-number slider did not use single steps")
whole:SetValue(51)
Near(wholeValue(), 51)
IsShiftKeyDown = function() return true end
whole:SetValue(63)
Near(wholeValue(), 65)
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return true end
whole:SetValue(79)
Near(wholeValue(), 80)
IsControlKeyDown = function() return false end

local fraction, fractionValue = Slider(0.35, 1, 0.05, 0.95)
Near(fraction.step, 0.01)
fraction:SetValue(0.96)
Near(fractionValue(), 0.96)
IsShiftKeyDown = function() return true end
fraction:SetValue(0.87)
Near(fractionValue(), 0.85)
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return true end
fraction:SetValue(0.91)
Near(fractionValue(), 0.95)
IsControlKeyDown = function() return false end


-- A refresh that finds the value it last painted writes nothing.
local painted = Slider(0, 10, 1, 4)
local valueText = lastText
local writes = 0
local setText = valueText.SetText
function valueText:SetText(...)
    writes = writes + 1
    return setText(self, ...)
end
local setValue = painted.SetValue
local moves = 0
function painted:SetValue(...)
    moves = moves + 1
    return setValue(self, ...)
end
O.RefreshAll()
O.RefreshAll()
assert(writes == 0 and moves == 0, "a slider repainted an unchanged value")
print("Suite Skinning sliders: single, Shift 5x and Ctrl 10x steps passed")

local function LastFrame(kind)
    for index = #frames, 1, -1 do
        if frames[index].kind == kind then return frames[index] end
    end
end

-- Hex entry: only typed text commits, once; focus loss, Escape and the focus
-- loss after Enter change nothing, so the look keeps its name.
history.begins, history.commits = 0, 0
O.CreateColorRow(Frame(), "accent", "Accent")
local input = LastFrame("EditBox")
local swatch = LastFrame("Button")
local function Type(text)
    input:SetFocus()
    input:SetText(text)
    local changed = input:GetScript("OnTextChanged")
    if changed then changed(input, true) end
end
input:SetFocus()
input:ClearFocus()
assert(setColors == 0 and NS.DB.theme.look == "midnight",
    "leaving an untouched hex field changed the color and the look name")
Type("#FF000080")
input:GetScript("OnEscapePressed")(input)
assert(setColors == 0 and colors.accent[1] == 0.2, "Escape committed the typed hex color")
Type("#FF000080")
input:GetScript("OnEnterPressed")(input)
assert(setColors == 1 and history.begins == 1 and history.commits == 1 and colors.accent[1] == 1,
    "Enter did not commit the typed hex color exactly once")
locked = true
Type("#00FF00FF")
input:GetScript("OnEnterPressed")(input)
assert(setColors == 1 and colors.accent[2] == 0, "a hex color was committed in combat")
locked = false

-- Color picker: a cancel in combat writes nothing; combat start closes the
-- picker and restores the color before the lockdown begins.
colors.accent = { 0.2, 0.4, 0.6, 1 }
NS.DB.theme.look, NS.DB.theme.preset = "midnight", "midnight"
ColorPickerFrame = {
    SetupColorPickerAndShow = function(self, info)
        self.info, self.cancelFunc, self.shown = info, info.cancelFunc, true
    end,
    GetColorRGB = function() return 0.9, 0.1, 0.1 end,
    GetColorAlpha = function() return 1 end,
    IsShown = function(self) return self.shown == true end,
    Hide = function(self) self.shown = false end,
}
swatch:GetScript("OnClick")(swatch)
ColorPickerFrame.info.swatchFunc()
assert(colors.accent[1] == 0.9 and NS.DB.theme.look == "custom", "the picker did not apply its color")
locked = true
ColorPickerFrame.info.cancelFunc()
assert(NS.DB.theme.look == "custom" and colors.accent[1] == 0.9,
    "a picker cancel in combat wrote the skin profile")
ColorPickerFrame:Hide()
locked = false
colors.accent = { 0.2, 0.4, 0.6, 1 }
NS.DB.theme.look, NS.DB.theme.preset = "midnight", "midnight"
swatch:GetScript("OnClick")(swatch)
ColorPickerFrame.info.swatchFunc()
local watcher
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_REGEN_DISABLED then watcher = frame end
end
assert(watcher, "an open color picker does not watch for combat")
watcher:GetScript("OnEvent")(watcher, "PLAYER_REGEN_DISABLED")
assert(not ColorPickerFrame.shown and colors.accent[1] == 0.2 and NS.DB.theme.look == "midnight"
    and not watcher.events.PLAYER_REGEN_DISABLED,
    "combat start did not cancel the open color picker")

-- Setting widgets refuse in combat, including the ones without history.
local picked = 0
local segmented = O.CreateSegmented(Frame(), "Segmented", { "a", "b" }, function() return "a" end,
    function() picked = picked + 1 end, 300, nil, { history = false })
local second = segmented.segmentButtons[2]
locked = true
second:GetScript("OnClick")(second, "LeftButton")
assert(picked == 0, "a segmented control without history changed a setting in combat")
local resets = 0
local reset = O.CreateSettingButton(Frame(), "Reset", 100, 24, function() resets = resets + 1 end)
reset:GetScript("OnClick")(reset, "LeftButton")
assert(resets == 0, "a setting button ran in combat")
locked = false
second:GetScript("OnClick")(second, "LeftButton")
reset:GetScript("OnClick")(reset, "LeftButton")
assert(picked == 1 and resets == 1, "setting widgets refused out of combat")

-- A refused slider move or input puts the stored value back on screen.
local refusedSlider, storedValue = Slider(0, 10, 1, 4)
local refusedText = lastText
locked = true
refusedSlider:SetValue(7)
assert(storedValue() == 4 and refusedSlider.value == 4 and refusedText.text == "4",
    "a slider refused in combat kept its moved thumb or text")
local _, field = O.CreateInput(Frame(), "Name", function() return "stored" end, function() end, 300)
field:SetFocus()
field:SetText("typed")
field:GetScript("OnEnterPressed")(field)
assert(field.text == "stored", "an input refused in combat kept the typed text")
locked = false

-- Profile actions refused in combat say so on the page in plain words, the
-- Active profile switch included.
local deleted = 0
NS.Database = {
    GetActiveProfileName = function() return "Default" end,
    GetProfileNames = function() return { "Default" } end,
    DeleteProfile = function() deleted = deleted + 1; return true, "Default" end,
}
NS.ProfileIO = { maxEncodedBytes = 100 }
local profilesBuilder
O.RegisterPage = function(_, _, builder) profilesBuilder = builder end
O.ClearHistory = function() end
assert(loadfile("MSUF_Suite_Skin_Options/Pages/Profiles.lua"))("MSUF_Suite_Skin_Options", { NS = NS, Options = O })
profilesBuilder(Frame())
local deleteButton
for button, widget in pairs(O.widgetStates) do
    if widget.label and widget.label.text == "Delete active" then deleteButton = button end
end
locked = true
deleteButton:GetScript("OnClick")(deleteButton, "LeftButton")
locked = false
local COMBAT_REFUSAL = "Profiles can only change outside combat."
local profileStatus
for _, text in ipairs(texts) do
    if text.text == COMBAT_REFUSAL then profileStatus = text end
end
assert(deleted == 0 and profileStatus, "a profile button refused in combat gave no readable feedback")
local activeButton
for button, widget in pairs(O.widgetStates) do
    if widget.label and widget.label.text == "Default" and button.changesSettings then activeButton = button end
end
profileStatus.text = ""
locked = true
activeButton:GetScript("OnClick")(activeButton, "LeftButton")
locked = false
assert(profileStatus.text == COMBAT_REFUSAL, "the Active profile switch refused in combat gave no feedback")

-- The picker: Blizzard calls swatchFunc and opacityFunc on Okay (and may on
-- open). Ending on the shown color changes nothing; a real change is undone
-- on Cancel through the engine, which restores the look and palette names.
colors.accent = { 0.2, 0.4, 0.6, 1 }
NS.DB.theme.look, NS.DB.theme.preset = "midnight", "midnight"
setColors, history.begins, history.cleared, restores = 0, 0, 0, {}
local pickR, pickG, pickB = 0.2, 0.4, 0.6
ColorPickerFrame.GetColorRGB = function() return pickR, pickG, pickB end
swatch:GetScript("OnClick")(swatch)
ColorPickerFrame.info.swatchFunc()
ColorPickerFrame.info.opacityFunc()
assert(setColors == 0 and history.begins == 0 and NS.DB.theme.look == "midnight",
    "confirming the picker without a change turned the look into a custom one")
ColorPickerFrame.info.cancelFunc()
assert(history.cleared == 0 and #restores == 0, "cancelling an unchanged picker touched the history")
pickR, pickG, pickB = 0.9, 0.1, 0.1
swatch:GetScript("OnClick")(swatch)
ColorPickerFrame.info.swatchFunc()
assert(setColors == 1 and NS.DB.theme.look == "custom", "the picker did not apply a real change")
ColorPickerFrame.info.cancelFunc()
local restored = restores[#restores]
assert(restored and restored.key == "accent" and restored.look == "midnight"
    and restored.preset == "midnight" and colors.accent[1] == 0.2 and NS.DB.theme.look == "midnight",
    "a cancelled picker did not restore through the engine")

-- Dropdown: it does not open in combat, closes when combat starts, and its
-- filter lowers each label once per open.
local choices = {}
for index = 1, 20 do choices[index] = "Choice " .. index end
local _, valueButton = O.CreateDropdown(Frame(), "Dropdown", choices, function() return choices[1] end,
    function() end, 400)
locked = true
valueButton:GetScript("OnClick")(valueButton, "LeftButton")
local dropdown = O.dropdownState
assert(not dropdown.blocker or not dropdown.blocker.shown, "the dropdown opened in combat")
locked = false
valueButton:GetScript("OnClick")(valueButton, "LeftButton")
assert(dropdown.blocker.shown, "the dropdown did not open")
local lower, lowered = string.lower, 0
string.lower = function(...) lowered = lowered + 1; return lower(...) end
for _, text in ipairs({ "c", "ch", "cho" }) do
    dropdown.search:SetText(text)
    dropdown.search:GetScript("OnTextChanged")(dropdown.search, true)
end
string.lower = lower
assert(#dropdown.filtered == 20 and lowered <= 3,
    "the dropdown filter lowered every label per keystroke: " .. lowered)
watcher:GetScript("OnEvent")(watcher, "PLAYER_REGEN_DISABLED")
assert(not dropdown.blocker.shown and not watcher.events.PLAYER_REGEN_DISABLED,
    "the dropdown blocker survived into combat")

-- Setting widgets refuse a click in combat before the click sound plays.
local sounds = 0
PlaySound = function() sounds = sounds + 1 end
O.CreateCycle(Frame(), "Cycle", { "a", "b" }, function() return "a" end, function() end, 300)
local cycleButton = LastFrame("Button")
local soundRow = O.CreateSegmented(Frame(), "Segmented sound", { "a", "b" }, function() return "a" end,
    function() end, 300)
local _, soundDropdown = O.CreateDropdown(Frame(), "Dropdown sound", { "a" }, function() return "a" end,
    function() end, 300)
locked = true
for _, button in ipairs({ cycleButton, soundRow.segmentButtons[2], soundDropdown }) do
    button:GetScript("OnClick")(button, "LeftButton")
end
locked = false
assert(sounds == 0, "a setting widget played its click sound before refusing in combat")
cycleButton:GetScript("OnClick")(cycleButton, "LeftButton")
assert(sounds == 1, "an accepted cycle click played no sound")
PlaySound = function() end

-- Typed text that is no hex color says so in the row's help line, in the
-- error style of a refused profile operation, until the next accepted entry.
colors.accent = { 0.2, 0.4, 0.6, 1 }
O.CreateColorRow(Frame(), "accent", "Accent")
local help = texts[#texts]
local hexField = LastFrame("EditBox")
local function TypeHex(text)
    hexField:SetFocus()
    hexField:SetText(text)
    hexField:GetScript("OnTextChanged")(hexField, true)
    hexField:GetScript("OnEnterPressed")(hexField)
end
local HEX_ERROR = "Error: Hex colors need 6 or 8 digits (#RRGGBB or #RRGGBBAA)"
TypeHex("#abc")
assert(help.text == HEX_ERROR and help.role == "danger" and hexField.text == "#336699FF",
    "a rejected hex color gave no feedback")
TypeHex("#FF000080")
assert(help.text == "accent" and help.role == "dim" and colors.accent[1] == 1,
    "an accepted hex color kept the error")
TypeHex("zz")
hexField:SetFocus()
hexField:GetScript("OnEscapePressed")(hexField)
assert(help.text == "accent", "Escape kept the hex error")
TypeHex("#abc")
colors.accent = { 0.1, 0.2, 0.3, 1 }
O.RefreshAll()
assert(help.text == "accent" and help.role == "dim",
    "a color change by the picker kept the hex format error")

-- The factory reset arm expires: a click long after arming arms again
-- instead of resetting the profile.
local timers = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local factoryResets = 0
NS.Database.ResetAll = function() factoryResets = factoryResets + 1 end
local appliedResets = {}
NS.Database.ApplyActiveSettings = function(reason, domain)
    appliedResets[#appliedResets + 1] = domain .. ":" .. reason
end
NS.CombatGate = { GetPendingCount = function() return 0 end }
NS.version, NS.apiVersion = "test", 1
-- The client's securecallfunction reports an error and returns nothing.
local resetReports = {}
NS.Safety.Dispatch = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        resetReports[#resetReports + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end
local pages = {}
O.RegisterPage = function(key, _, builder) pages[key] = builder end
assert(loadfile("MSUF_Suite_Skin_Options/Pages/Advanced.lua"))("MSUF_Suite_Skin_Options", { NS = NS, Options = O })
pages.advanced(Frame())
local resetButton, resetLabel
for button, widget in pairs(O.widgetStates) do
    if widget.label and widget.label.text == "RESET_ALL" then resetButton, resetLabel = button, widget.label end
end
local function ClickReset() resetButton:GetScript("OnClick")(resetButton, "LeftButton") end
ClickReset()
assert(resetLabel.text == "Confirm factory reset", "the first click did not arm the factory reset")
assert(#timers == 1, "the factory reset arm never expires")
timers[1]()
assert(resetLabel.text == "RESET_ALL", "the factory reset arm did not expire")
ClickReset()
assert(factoryResets == 0 and resetLabel.text == "Confirm factory reset",
    "a click after the arm expired reset the profile")
ClickReset()
assert(factoryResets == 1 and resetLabel.text == "RESET_ALL", "a confirmed factory reset did not run")
ClickReset()
timers[2]()
assert(resetLabel.text == "Confirm factory reset", "the timer of an older arm ended a newer one")
ClickReset()
assert(factoryResets == 2, "the newer arm did not confirm the reset")

-- The factory profile is applied like a profile switch, through the shared
-- Database.ApplyActiveSettings (every stage its own boundary, the dynamic look
-- included), announced as a theme reset. A reset that raises is reported, and
-- the apply and the history still finish.
assert(#appliedResets == 2 and appliedResets[1] == "theme:reset",
    "the factory reset did not apply the profile like a profile switch")
NS.Database.ResetAll = function()
    factoryResets = factoryResets + 1
    error("factory profile failed")
end
history.commits = 0
ClickReset()
ClickReset()
assert(factoryResets == 3 and #appliedResets == 3 and appliedResets[3] == "theme:reset"
    and #resetReports == 1 and resetReports[1]:find("factory profile failed", 1, true)
    and history.commits == 1, "a failing factory reset stopped the apply or the history")
C_Timer = nil

-- The Colors page lays its rows out again when the mode, the query or the
-- group changes, not on every setting refresh (each frame of a color drag).
local mode = "guided"
O.GetMode = function() return mode end
O.ui = { colorGroup = "surfaces" }
O.CreateScrollContainer = function() return Frame(), Frame() end
NS.ColorOrder = { { "background", "Background" }, { "accent", "Accent" }, { "text", "Text" } }
NS.PaletteOrder, NS.PaletteLabels = { "midnight" }, {}
colors.background, colors.text = { 0, 0, 0, 1 }, { 1, 1, 1, 1 }
local firstPanel = #panels + 1
assert(loadfile("MSUF_Suite_Skin_Options/Pages/Colors.lua"))("MSUF_Suite_Skin_Options", { NS = NS, Options = O })
pages.colors(Frame())
local function ColorLayouts()
    local count = 0
    for index = firstPanel, #panels do count = count + (panels[index].clears or 0) end
    return count
end
local laidOut = ColorLayouts()
assert(laidOut > 0, "the Colors page did not lay its rows out")
O.RefreshAll()
O.RefreshAll()
assert(ColorLayouts() == laidOut, "a setting refresh laid the Colors rows out again")
mode = "expert"
O.RefreshAll()
assert(ColorLayouts() > laidOut, "a mode switch did not lay the Colors rows out again")

-- The Icons preview attaches a surface again only when its spec changed, and
-- skins a window-action sample again only after a restore took it back.
local attaches, actionApplies, appliedActions = 0, 0, {}
NS.Surface.Attach = function()
    attaches = attaches + 1
    return {}
end
NS.WindowActionSkin = {
    Apply = function(button)
        actionApplies = actionApplies + 1
        appliedActions[button] = true
    end,
    IsApplied = function(button) return appliedActions[button] == true end,
}
NS.MicroMenuVisual = { ApplyIcon = function() end }
NS.MicroMenuSkin = { GetIconColor = function() return 1, 1, 1, 1 end }
NS.IconSkin = { AnchorLines = function() end }
NS.DB.skins = { microMenu = true }
NS.DB.geometry = { controlShape = "continuous", radius = 6 }
NS.DB.theme.iconBorderStyle, NS.DB.theme.iconBorderOpacity = "theme", 1
NS.DB.icons = {
    windowActions = {},
    microMenu = {
        layoutMode = "owned", iconStyle = "line", iconSize = 18, buttonSize = 28, tint = "theme",
        shape = "round", radius = 6, barBorder = 1, buttonBorder = 1, barBackground = true,
        buttonBackground = true, barMaterial = "modern",
    },
}
O.TrackMode = function(callback) return callback end
O.Labeler = function(labels) return function(value) return labels[value] or tostring(value) end end
O.Pixel, O.Percent = tostring, tostring
assert(loadfile("MSUF_Suite_Skin_Options/Pages/Icons.lua"))("MSUF_Suite_Skin_Options", { NS = NS, Options = O })
pages.icons(Frame())
assert(actionApplies == 3, "the window-action preview was not skinned")
attaches, actionApplies = 0, 0
O.RefreshAll()
assert(attaches == 0 and actionApplies == 0,
    "an unchanged Icons preview attached its surfaces or skinned its samples again")
NS.DB.icons.microMenu.barBorder = 2
O.RefreshAll()
assert(attaches == 1, "a changed bar border attached " .. attaches .. " preview surfaces")
appliedActions = {}
O.RefreshAll()
assert(actionApplies == 3, "a window-action sample a restore took back was not skinned again")

-- The gated rows are painted when the Micro Bar gate changes, not on every
-- refresh.
local gatePaints = 0
local setWidgetEnabled = O.SetWidgetEnabled
O.SetWidgetEnabled = function(...)
    gatePaints = gatePaints + 1
    return setWidgetEnabled(...)
end
O.RefreshAll()
O.RefreshAll()
assert(gatePaints == 0, "every refresh repainted the Micro Bar gates")
NS.DB.skins.microMenu = false
O.RefreshAll()
assert(gatePaints > 0, "a changed Micro Bar gate did not repaint the gated rows")
O.SetWidgetEnabled = setWidgetEnabled
NS.DB.skins.microMenu = true
O.RefreshAll()

-- A disabled label reads "disabled"; enabled again it shows its active state.
local gatedRow = O.CreateSegmented(Frame(), "Gated", { "x", "y" }, function() return "y" end,
    function() end, 300)
local firstLabel = O.widgetStates[gatedRow.segmentButtons[1]].label
local secondLabel = O.widgetStates[gatedRow.segmentButtons[2]].label
O.SetWidgetEnabled(gatedRow, false)
O.SetButtonActive(gatedRow.segmentButtons[1], false)
assert(firstLabel.role == "disabled" and secondLabel.role == "disabled",
    "a disabled segmented row showed an active label color")
O.SetWidgetEnabled(gatedRow, true)
assert(secondLabel.role == "title" and firstLabel.role == "muted",
    "enabling a segmented row lost its active label colors")
print("Suite Skinning widgets: hex entry, combat gating, color picker, dropdown filter, reset arm and page refreshers passed")
