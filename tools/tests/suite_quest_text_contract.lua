local root = arg and arg[1] or "."
local callbacks = {}
local listener
local theme = { text = { 0.93, 0.95, 0.97 }, title = { 0.98, 0.91, 0.77 } }

hooksecurefunc = function(target, method, callback)
    if type(target) == "string" then
        assert(type(_G[target]) == "function", "hook target missing: " .. target)
        callbacks[target] = method
        return
    end
    assert(type(target[method]) == "function", "object hook target missing: " .. method)
    callbacks[target] = callbacks[target] or {}
    callbacks[target][method] = callback
end
QuestInfo_Display = function() end
QuestFrame_SetTextColor = function() end
QuestFrame_SetTitleTextColor = function() end
QuestFrameGreetingPanel_OnShow = function() end

local NS = {
    Safety = assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Safety.lua"))("MSUF_Suite_Skin", {}),
    IsCombatLocked = function() return false end,
    Theme = { GetColor = function(role)
        local color = assert(theme[role], role)
        return color[1], color[2], color[3], 1
    end },
    Registry = { AddListener = function(_, callback) listener = callback end },
}

local function Frame(parent)
    return { GetParent = function() return parent end }
end

local function Text(parent, r, g, b, a)
    local region = { parent = parent, color = { r, g, b, a or 1 } }
    function region:GetParent() return self.parent end
    function region:GetTextColor() return unpack(self.color) end
    function region:SetTextColor(red, green, blue, alpha)
        self.color = { red, green, blue, alpha or 1 }
    end
    return region
end

local map = Frame()
local quest = Frame()
local other = Frame()
local gossip = Frame()
gossip.fontStrings = {}
function gossip:RegisterFontString(region)
    self.fontStrings[region] = true
    if callbacks[self] then callbacks[self].RegisterFontString(self, region) end
end
function gossip:UpdateTheme()
    for region in pairs(self.fontStrings) do region:SetTextColor(0.21, 0.17, 0.11) end
    if callbacks[self] then callbacks[self].UpdateTheme(self) end
end
GossipFrame = gossip
local details = Frame(map)
local objectiveFrame = Frame(details)
QuestInfoTitleHeader = Text(details, 0.33, 0.21, 0.10)
QuestInfoDescriptionText = Text(details, 0.36, 0.22, 0.11, 0.8)
QuestInfoObjectivesFrame = { Objectives = { Text(objectiveFrame, 0.34, 0.24, 0.12) } }
QuestInfoRewardText = Text(other, 0.24, 0.22, 0.16)
local greeting = Text(quest, 0.25, 0.20, 0.10)
local greetingButtonText = Text(Frame(quest), 0.29, 0.24, 0.17)
QuestFrameGreetingPanel = { titleButtonPool = {
    EnumerateActive = function()
        local shown = false
        return function()
            if shown then return nil end
            shown = true
            return { GetFontString = function() return greetingButtonText end }
        end
    end,
} }

assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/QuestText.lua"))("MSUF_Suite_Skin", NS)
assert(NS.QuestText.Activate(map, "map"))
assert(callbacks.QuestInfo_Display, "native quest display hook missing")
assert(QuestInfoTitleHeader.color[1] == theme.title[1], "title stays dark")
assert(QuestInfoDescriptionText.color[1] == theme.text[1], "body stays dark")
assert(QuestInfoDescriptionText.color[4] == 0.8, "native text alpha changed")
assert(QuestInfoObjectivesFrame.Objectives[1].color[1] == theme.text[1], "objective stays dark")
assert(QuestInfoRewardText.color[1] == 0.24, "unskinned quest changed")

QuestInfoObjectivesText = Text(details, 0.37, 0.23, 0.12)
callbacks.QuestInfo_Display()
assert(QuestInfoObjectivesText.color[1] == theme.text[1], "shared objective text stayed dark")
QuestInfoObjectivesText.parent = other
callbacks.QuestInfo_Display()
assert(QuestInfoObjectivesText.color[1] == 0.37,
    "shared text stayed light after moving to unskinned parchment")

QuestInfoDescriptionText:SetTextColor(0.18, 0.17, 0.16, 0.8)
callbacks.QuestInfo_Display()
assert(QuestInfoDescriptionText.color[1] == theme.text[1], "native quest refresh was not repaired")
theme.text = { 0.84, 0.86, 0.88 }
listener(nil, "theme", "look")
assert(QuestInfoDescriptionText.color[1] == 0.84, "theme change did not refresh quest text")

NS.QuestText.Activate(quest, "quest")
assert(greetingButtonText.color[1] == 0.84, "existing NPC quest list stayed dark")
greeting:SetTextColor(0.28, 0.25, 0.19)
callbacks.QuestFrame_SetTextColor(greeting)
assert(greeting.color[1] == 0.84, "NPC greeting stayed dark")
callbacks.QuestFrame_SetTitleTextColor(greeting)
assert(greeting.color[1] == theme.title[1], "NPC greeting title stayed dark")
greetingButtonText:SetTextColor(0.31, 0.25, 0.18)
callbacks.QuestFrameGreetingPanel_OnShow()
assert(greetingButtonText.color[1] == 0.84, "refreshed NPC quest list stayed dark")

NS.QuestText.Deactivate(map, "map")
assert(QuestInfoTitleHeader.color[1] == 0.33, "title was not restored")
assert(QuestInfoDescriptionText.color[1] == 0.18, "latest native body color was not restored")
assert(greeting.color[1] == theme.title[1], "other active quest root was restored")
NS.QuestText.Deactivate(quest, "quest")
assert(greeting.color[1] == 0.28, "NPC greeting was not restored")
assert(greetingButtonText.color[1] == 0.31, "NPC quest list was not restored")

local gossipGreeting = Text(Frame(gossip), 0.26, 0.20, 0.12)
local gossipOption = Text(Frame(gossip), 0.29, 0.22, 0.14)
gossip:RegisterFontString(gossipGreeting)
gossip:RegisterFontString(gossipOption)
assert(NS.QuestText.Activate(gossip, "gossip"))
assert(gossipGreeting.color[1] == 0.84, "existing gossip greeting stayed dark")
assert(gossipOption.color[1] == 0.84, "existing gossip option stayed dark")
gossip:UpdateTheme()
assert(gossipGreeting.color[1] == 0.84, "gossip theme refresh darkened greeting")
assert(gossipOption.color[1] == 0.84, "gossip theme refresh darkened option")
local newOption = Text(Frame(gossip), 0.30, 0.23, 0.15)
gossip:RegisterFontString(newOption)
assert(newOption.color[1] == 0.84, "new ScrollBox option stayed dark")
NS.QuestText.Deactivate(gossip, "gossip")
assert(gossipGreeting.color[1] == 0.21, "native greeting color was not restored")
assert(gossipOption.color[1] == 0.21, "native option color was not restored")
assert(newOption.color[1] == 0.30, "new option color was not restored")

-- Exercise the actual quest-window adapter path so a future root-list change
-- cannot silently leave GossipFrame unregistered again.
QuestFrame = quest
QuestLogPopupDetailFrame = Frame()
QuestFrameRewardPanel = { MaterialTopLeft = {} }
NS.AdapterKit = {
    Fade = function(_, region) return region ~= nil end,
    Path = function() return nil end,
    WeakSet = function() return setmetatable({}, { __mode = "k" }) end,
    CancelDeferred = function() end,
}
NS.GenericWindows = { IsCategoryEnabled = function(category) return category == "quest" end }
NS.Client = { IsAddOnLoaded = function(addon) return addon == "Blizzard_UIPanels_Game" end }
NS.ControlSkin = { DisableOwner = function() end }
NS.IconSkin = { DisableOwner = function() end }
NS.Cosmetics = { RestoreOwner = function() end }
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/DeepWindows.lua"))("MSUF_Suite_Skin", NS)
assert(NS.DeepWindows.Apply("quest-test"))
assert(gossipGreeting.color[1] == 0.84, "quest adapter did not activate GossipFrame text")
assert(NS.DeepWindows.Disable("quest-test"))
assert(gossipGreeting.color[1] == 0.21, "quest adapter did not restore GossipFrame text")
print("suite quest text contract: OK")
