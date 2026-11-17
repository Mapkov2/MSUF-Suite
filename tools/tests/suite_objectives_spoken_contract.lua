local root = assert(arg[1])
local objectives = {}
local function Nothing() end
local function Button()
    local button = { scripts = {}, shown = false }
    function button:SetScript(event, callback) self.scripts[event] = callback end
    function button:GetScript(event) return self.scripts[event] end
    function button:Hide() self.shown = false end
    function button:Show() self.shown = true end
    return setmetatable(button, { __index = function(_, key)
        return key:match("^[A-Z]") and Nothing or nil
    end })
end

local suite = {
    Public = function(value) return value ~= "secret" end,
    Finite = function(value) return type(value) == "number" end,
    Dispatch = function(callback, ...) return callback(...) end,
    CreateFrame = Button,
    CreateFontString = function()
        return { SetPoint = Nothing, SetTextColor = Nothing,
            SetText = function(label, text) label.text = text end }
    end,
}
local row = { GetFrameLevel = function() return 0 end }
local item = { kind = "entry", questID = 100, text = "A quest" }
local color = { 1, 1, 1 }
assert(loadfile(root .. "/MSUF_Suite_Modules/ObjectivesVoice.lua"))("MSUF_Suite_Modules",
    { Objectives = objectives, Suite = suite })
local function Paint() return objectives.PaintQuestVoice(row, item, 20, color) end
assert(Paint() == 20 and not row.voiceButton, "missing Spoken built a button")
local binds, click = 0
VoiceOver = { QuestOverlayUI = {
    ShowsTrackerButton = function(_, quest) return quest < 200 end,
    BindPlayButton = function(_, button, quest)
        binds = binds + 1
        button:SetScript("OnClick", function() click = quest end)
    end,
    FollowQueue = function(button) button:SetState(button.questID == 101 and "stop" or "play") end,
} }
assert(Paint() == 43 and row.voiceButton.shown and binds == 1)
local button = row.voiceButton
button.soundData = {}
assert(Paint() == 43 and binds == 1, "same quest was rebound on repaint")
item.questID = 101
assert(Paint() == 43 and binds == 2 and not button.soundData and button.glyph.text == "■")
button:GetScript("OnClick")()
assert(click == 101, "the recycled row still played its former quest")
item.questID = 200
assert(Paint() == 20 and not button.shown and not button:GetScript("OnClick"), "unvoiced quest retained Play")
item.questID = 100
assert(Paint() == 43 and binds == 3)
objectives.ReleaseQuestVoice(row)
assert(not button.shown and not button.overlay and not button.questID)
print("suite_objectives_spoken_contract: ok")
