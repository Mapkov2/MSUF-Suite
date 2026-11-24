local root = assert(arg[1], "repository root required")
local function Load(file, P)
    assert(loadfile(root .. "/MSUF_Suite_Options/Pages/" .. file .. ".lua"))("MSUF_Suite_Options", P)
end
local function noop() end
local Widget = {}
Widget.__index = Widget
local function New() return setmetatable({ shown = true, scripts = {} }, Widget) end
for _, name in ipairs({ "SetPoint", "SetFrameLevel", "ClearAllPoints", "SetSize", "RegisterForClicks",
    "SetAllPoints", "SetColorTexture", "SetWidth", "SetTextColor", "ClearFocus", "SetVerticalScroll" }) do
    Widget[name] = noop
end
function Widget:SetHeight(value) self.height = value end
function Widget:SetText(value) self.text = value end
function Widget:SetShown(value) self.shown = value end
function Widget:IsShown() return self.shown end
function Widget:Show() self:SetShown(true) end
function Widget:Hide()
    self:SetShown(false)
    if self.OnClosed then self:OnClosed() end
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Widget:CreateTexture() return New() end
function Widget:GetFrameLevel() return 1 end
function Widget:SetScript(event, callback) self.scripts[event] = callback end
function Widget:HookScript(event, callback) self:SetScript(event, callback) end
function Widget:Click() return self.scripts.OnClick(self) end
CreateFrame = New

local config = { reminderSound = 3, reminderSoundChannel = 2 }
local writes, samples, cdmSounds = 0, {}, {}
local combat, available = false, true
local Page = { ID = "cooldownManager", SetRaw = Widget.SetText }
local function RGB() return 1, 1, 1 end
Page.Accent, Page.TextColor, Page.MutedColor = RGB, RGB, RGB
Page.Label = New
Page.Button = function(_, _, _, _, click)
    local button = New()
    button:SetScript("OnClick", click)
    return button
end
Page.Media = function() return { List = function() return { "Bell" } end } end
Page.PlaySound = function(value) cdmSounds[#cdmSounds + 1] = value end
Page.SoundLabel = function(value) return value:sub(5) end
Page.BlizzardSounds = function() return { groups = {}, names = {} } end
Page.NewPopup = function(_, height)
    local widget = New()
    widget:SetHeight(height)
    widget:Hide()
    return widget
end
Page.ClosePopups = function()
    if Page.soundPicker then Page.soundPicker:Hide() end
end
Page.PlacePopup = function(popup, anchor) popup.anchor = anchor end
Page.Query = function(search) return search.text or "" end
Page.SearchBox = New
Page.ScrollArea = function() return New(), New() end
Page.HideTip, Page.ShowTip = noop, noop

local P = { CDMPage = Page, S = {}, Suite = { Client = {} }, Requires = {}, Gates = {} }
P.Tr = function(text) return text end
P.Get = function(id, key) return id == "buffReminders" and config[key] or key == "muteSounds" end
P.Set = function(id, key, value)
    assert(id == "buffReminders" and key == "reminderSound")
    writes = writes + 1
    config[key] = value
end
P.RuleEnabled = function() return not combat end
P.Combat = function() return combat end
P.S.BuffRemindersPlaySound = function(choice, channel) samples[#samples + 1] = { choice, channel } end
P.PreviewCanvas = { Runtime = function(addon, export)
    assert(addon == "MSUF_Suite_BuffReminders" and export == "BuffRemindersPlaySound")
    return available
end }
local page, sound = nil, New()
local choice = { key = "reminderSound", choices = { "None", "Raid warning", "Ready check", "Quest log", "Alarm clock", "Map ping", "Whisper" } }
P.Help = function(text) return text end
P.RegisterPage = function(spec) page = spec end
P.ModuleCard, P.PlannerAction, P.SectionRules = noop, noop, noop
P.MenuSamples = { Reminders = noop }
P.ReminderEditor, P.ReminderVisibility = { Build = noop }, { Build = noop }
P.MenuWorkspace = {
    Builder = function() return {}, {} end, Finish = noop,
    Rules = function(_, _, _, _, section, _, _, opts)
        if section == "suite_buffReminders_appearance" then
            assert(opts.onBuilt, "the Icons section did not bind a sound picker")
            opts.onBuilt({}, { { rule = choice, widget = sound } })
        end
    end,
}
Load("BuffReminders", P)
Load("CooldownManagerSounds", P)
page.build({})

assert(not P.OpenSoundChoicePicker(sound, 1, nil, noop, noop) and not P.OpenSoundChoicePicker(sound, 1, {}, noop, noop),
    "a missing fixed list may not open the cooldown manager catalog")
sound:Click()
local popup = Page.soundPicker
assert(popup:IsShown() and popup.current == 3 and popup.count == 7 and not popup.search:IsShown())
assert(not popup.rows[1].play:IsShown() and popup.rows[7].play:IsShown(), "only actual sounds may be sampled")
popup.rows[7].play:Click()
assert(popup:IsShown() and writes == 0 and config.reminderSound == 3 and samples[1][1] == 7 and samples[1][2] == 2)
config.reminderSoundChannel = 3
popup.rows[2].play:Click()
assert(samples[2][1] == 2 and samples[2][2] == 3 and writes == 0, "samples must use the current channel")
available = false
popup.rows[2].play:Click()
assert(#samples == 2 and popup:IsShown(), "unavailable runtime may not dispatch playback")
popup.rows[7]:Click()
assert(writes == 1 and config.reminderSound == 7 and not popup:IsShown(), "choosing the row saves once and closes")

sound:Click()
combat = true
popup.rows[2].play:Click()
popup.rows[2]:Click()
assert(#samples == 2 and writes == 1, "combat must block samples and selection")
combat = false
sound:Hide()
assert(not popup:IsShown() and not popup.onPick and not popup.onPlay, "hiding the setting must release the picker")
Page.OpenSoundPicker(New(), "lsm:Bell", noop)
assert(popup:IsShown() and popup.search:IsShown() and popup.muteNote:IsShown() and popup.height == 400)
assert(popup.rows[3].item.value == "lsm:Bell")
popup.rows[3].play:Click()
assert(cdmSounds[1] == "lsm:Bell" and #samples == 2, "reused CDM rows must keep their own sound handler")
print("Buff Reminders sample playback, selected channel, gating, and Cooldown Manager picker reuse passed")
