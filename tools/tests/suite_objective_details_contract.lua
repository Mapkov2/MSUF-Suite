local root = assert(arg[1], "repository root required")
local combat, created, writes = false, 0, 0
local O, S = {}, {}
local function Widget()
    local w = { shown = true, attributes = {} }
    function w:RegisterForClicks(...) self.clicks = { ... } end
    function w:SetAttribute(key, value)
        assert(not combat, "protected quest-item attributes changed in combat")
        writes = writes + 1
        self.attributes[key] = value
    end
    function w:Hide() self.shown = false end
    function w:Show() self.shown = true end
    function w:SetPoint() end
    function w:SetWidth() end
    function w:SetSize() end
    function w:SetText(text) self.text = text end
    function w:SetTextColor() end
    function w:SetAtlas(asset) self.atlas = asset end
    function w:SetTexture(asset) self.texture = asset end
    return w
end
UIParent = {}
S.CreateFrame = function(kind, name, parent, template)
    created = created + 1
    assert(kind == "Button" and name == "MSUFSuiteQuestItem" and parent == UIParent
        and template == "SecureActionButtonTemplate", "shortcut must use an independent native secure action")
    return Widget()
end
S.CreateFontString, S.CreateTexture = Widget, Widget
S.SetStyledFont = function() end
assert(loadfile(root .. "/MSUF_Suite_Modules/ObjectivesDetails.lua"))("MSUF_Suite_Modules", {
    NS = { IsCombatLocked = function() return combat end }, Suite = S, Objectives = O,
})
local module = { active = true, config = {}, sources = {
    quests = { count = 2, { group = "quests", itemLink = "item:1" }, { group = "focused", itemLink = "item:2" } },
    world = { count = 1, { group = "world", itemLink = "item:3" } },
} }
O.UpdateQuestItem(module)
local button = module.questItemShortcut
assert(created == 1 and button.attributes.type1 == "item" and button.attributes.item1 == "item:2"
    and button.clicks[1] == "AnyDown" and button.clicks[2] == "AnyUp", "focused item must take priority")
local priorWrites = writes
O.UpdateQuestItem(module)
assert(writes == priorWrites and created == 1, "unchanged selection must not rewrite protected state")
combat = true
module.sources.quests[2].itemLink = "item:4"
O.UpdateQuestItem(module)
assert(button.attributes.item1 == "item:2", "combat selection must remain the last safe item")
combat = false
O.UpdateQuestItem(module)
assert(button.attributes.item1 == "item:4" and created == 1, "after combat use current data on the same button")
module.sources.quests[2].itemLink = nil
O.UpdateQuestItem(module)
assert(button.attributes.item1 == "item:1", "missing focused item must use the first usable tracked item")
module.sources.quests.count = 0
O.UpdateQuestItem(module)
assert(button.attributes.item1 == "item:3", "world quest item must be a valid fallback")
module.config.showQuestItems = false
O.UpdateQuestItem(module)
assert(button.attributes.item1 == nil, "disabled quest items must clear the action")
module.config.showQuestItems = true
O.UpdateQuestItem(module)
O.UpdateQuestItem(module, true)
assert(button.attributes.item1 == nil, "module disable must clear its binding even before active flips")
local row, item, color = {}, { kind = "entry", questID = 1, group = "campaign" }, { 1, 1, 0 }
assert(O.PaintQuestIcon(module, row, item, { questIconStyle = 2 }, color) == 31 and row.questBadge.text == "C")
item.questIcon, item.questIconAtlas = "CampaignInProgressQuestIcon", true
assert(O.PaintQuestIcon(module, row, item, { questIconStyle = 3 }, color) == 31
    and row.questIcon.atlas == item.questIcon and not row.questBadge.shown)
item.questIcon, item.questIconAtlas = "Interface/GossipFrame/ActiveQuestIcon", false
O.PaintQuestIcon(module, row, item, { questIconStyle = 3 }, color)
assert(row.questIcon.texture == item.questIcon, "native texture paths must not be treated as atlases")
assert(O.PaintQuestIcon(module, row, item, { questIconStyle = 1 }, color) == 12
    and not row.questIcon.shown and not row.questBadge.shown, "off must restore ordinary text space")
print("objective shortcut priority, secure lifecycle, reuse and symbol styles passed")
