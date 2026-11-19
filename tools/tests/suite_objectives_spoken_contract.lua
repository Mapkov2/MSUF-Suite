local root = assert(arg[1])
local objectives = {}
local function Nothing() end
local function Button()
    local button = { scripts = {}, shown = false }
    function button:SetScript(event, callback) self.scripts[event] = callback end
    function button:GetScript(event) return self.scripts[event] end
    function button:EnableMouse(enabled) self.mouse = enabled end
    function button:RegisterForClicks(click) self.click = click end
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
    CreateTexture = function()
        return { SetPoint = Nothing, SetSize = Nothing, SetVertexColor = Nothing,
            SetTexture = function(icon, path) icon.path = path end,
            SetTexCoord = function(icon, left, right) icon.left, icon.right = left, right end }
    end,
}
local row = { GetFrameLevel = function() return 0 end }
local item = { kind = "entry", questID = 100, text = "A quest" }
local color = { 1, 1, 1 }
local safety = { IsForbidden = function(frame) return frame.forbidden end }
GameTooltip = {
    IsOwned = function(tooltip, owner) return tooltip.owner == owner end,
    Hide = function(tooltip) tooltip.owner = nil end,
}
assert(loadfile(root .. "/MSUF_Suite_Modules/ObjectivesVoice.lua"))("MSUF_Suite_Modules",
    { Objectives = objectives, Suite = suite, NS = { Safety = safety } })
local function Paint() return objectives.PaintQuestVoice(row, item, 20, color) end
assert(Paint() == 20 and not row.voiceButton, "missing Spoken built a button")
local binds, click = 0
local states = { [101] = "stop" }
VoiceOver = { QuestOverlayUI = {
    ShowsTrackerButton = function(_, quest) return quest < 200 end,
    BindPlayButton = function(_, button, quest)
        binds = binds + 1
        button:SetScript("OnClick", function(target, mouse, down)
            assert(target == button and mouse == "LeftButton" and not down)
            click = quest
            states[quest] = states[quest] == "stop" and "replay" or "stop"
            target:setPlayState(states[quest] == "stop")
        end)
        button:SetScript("OnEnter", function() error("unguarded Spoken OnEnter") end)
        button:SetScript("OnLeave", function() error("unguarded Spoken OnLeave") end)
    end,
    FollowQueue = function(button) button:SetState(states[button.questID] or "play") end,
    ShowPlayTip = function(_, button) GameTooltip.owner = button end,
} }
assert(Paint() == 40 and row.voiceButton.shown and binds == 1)
local button = row.voiceButton
assert(button.mouse and button.click == "LeftButtonUp", "Play button did not accept left clicks")
assert(button.icon.path == "Interface\\AddOns\\MSUF_Suite\\Media\\QuestVoiceControls.tga")
assert(button.state == "play" and button.icon.left == 0 and button.icon.right == .25)
button:GetScript("OnEnter")(button)
assert(GameTooltip:IsOwned(button), "Spoken did not receive mouseover")
button:GetScript("OnLeave")(button)
assert(not GameTooltip:IsOwned(button), "leaving the button kept the tooltip up")
GameTooltip.forbidden = true
button:GetScript("OnEnter")(button)
assert(not GameTooltip:IsOwned(button), "Play showed a forbidden tooltip")
GameTooltip.forbidden = nil
button.soundData = {}
assert(Paint() == 40 and binds == 1, "same quest was rebound on repaint")
item.questID = 101
assert(Paint() == 40 and binds == 2 and not button.soundData and button.state == "stop")
assert(button.icon.left == .25 and button.icon.right == .5)
button:GetScript("OnClick")(button, "LeftButton", false)
assert(click == 101, "the recycled row still played its former quest")
assert(button.state == "replay" and button.icon.left == .5 and button.icon.right == .75)
item.questID = 200
assert(Paint() == 20 and not button.shown and not button:GetScript("OnClick"), "unvoiced quest retained Play")
item.questID = 100
assert(Paint() == 40 and binds == 3)
objectives.ReleaseQuestVoice(row)
assert(not button.shown and not button.overlay and not button.questID)
print("suite_objectives_spoken_contract: ok")
