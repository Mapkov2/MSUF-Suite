local _, NS = ...

-- Blizzard_UIPanels_Game/Mainline/QuestInfo.lua (upstream/forever bd2470ae)
-- sets parchment-dark text in QuestInfo_Display. Our quest and map adapters
-- fade that parchment, so recolor only text currently parented to a skinned
-- quest window. The Blizzard display function remains responsible for content.
local QuestText = {
    roots = setmetatable({}, { __mode = "k" }),
    colors = setmetatable({}, { __mode = "k" }),
    hooks = {},
}
NS.QuestText = QuestText

local Safety = NS.Safety

local COLOR_TOLERANCE = 0.015
local MAX_PARENT_DEPTH = 20
local MAX_OBJECTIVES = 40

local fields = {
    QuestInfoTitleHeader = "title",
    QuestInfoDescriptionHeader = "title",
    QuestInfoObjectivesHeader = "title",
    QuestInfoDescriptionText = "text",
    QuestInfoObjectivesText = "text",
    QuestInfoQuestType = "text",
    QuestInfoRewardText = "text",
    QuestInfoGroupSize = "text",
    QuestInfoTimerText = "text",
    QuestInfoSpellObjectiveLearnLabel = "text",
    QuestInfoRequiredMoneyText = "text",
}

local rewardFields = {
    Header = "title",
    ItemChooseText = "text",
    ItemReceiveText = "text",
    PlayerTitleText = "text",
    QuestSessionBonusReward = "text",
}

-- The skinned root this region currently sits under, if any.
local function ActiveRoot(region)
    local current = region
    for _ = 1, MAX_PARENT_DEPTH do
        if not current then return nil end
        if QuestText.roots[current] then return current end
        current = Safety.Call(current, "GetParent")
    end
    return nil
end

-- Compares a stored { r, g, b, a } with four values.
local function SameColor(color, r, g, b, a)
    return color ~= nil and color[1] ~= nil and r ~= nil
        and math.abs(color[1] - r) <= COLOR_TOLERANCE and math.abs(color[2] - g) <= COLOR_TOLERANCE
        and math.abs(color[3] - b) <= COLOR_TOLERANCE and math.abs(color[4] - a) <= COLOR_TOLERANCE
end

-- Puts Blizzard's color back while ours is still showing, then forgets it.
local function Release(region, record)
    if SameColor(record.applied, Safety.ReadColor(region, "GetTextColor")) then
        local original = record.original
        Safety.Invoke(region, "SetTextColor", original[1], original[2], original[3], original[4])
    end
    QuestText.colors[region] = nil
end

local function Paint(region, role)
    if type(region) ~= "table" or type(region.SetTextColor) ~= "function" then return end
    if not ActiveRoot(region) then
        -- QuestInfo FontStrings are shared between the map, NPC dialog and
        -- popup. Blizzard can move one without repainting when its material
        -- cache still matches, so restore our color on an unskinned parent.
        local record = QuestText.colors[region]
        if record then Release(region, record) end
        return
    end
    local currentR, currentG, currentB, currentA = Safety.ReadColor(region, "GetTextColor")
    if not currentR then return end
    local record = QuestText.colors[region]
    if not record then
        record = { original = { currentR, currentG, currentB, currentA }, applied = {} }
        QuestText.colors[region] = record
    elseif not SameColor(record.applied, currentR, currentG, currentB, currentA) then
        -- Blizzard has repainted for a different quest/material since our pass.
        local original = record.original
        original[1], original[2], original[3], original[4] = currentR, currentG, currentB, currentA
    end
    local r, g, b = NS.Theme.GetColor(role)
    if Safety.Invoke(region, "SetTextColor", r, g, b, currentA) then
        local applied = record.applied
        applied[1], applied[2], applied[3], applied[4] = r, g, b, currentA
    end
end

local function PaintRewards(rewards)
    for key, role in pairs(rewardFields) do Paint(rewards[key], role) end
    if rewards.XPFrame then Paint(rewards.XPFrame.ReceiveText, "text") end
end

local function PaintGreetingButtons(pool)
    for button in pool:EnumerateActive() do
        Paint(Safety.Call(button, "GetFontString"), "text")
    end
end

-- GossipFrame owns ScrollBox FontStrings rather than the shared QuestInfo
-- globals. Blizzard registers each row and repaints all registered text in
-- UpdateTheme, including after a questTextContrast change.
local function PaintGossip()
    local gossip = _G.GossipFrame
    local fontStrings = gossip and gossip.fontStrings
    if not gossip or not QuestText.roots[gossip] or type(fontStrings) ~= "table" then return end
    for region in pairs(fontStrings) do Paint(region, "text") end
end

local function EnsureGossipHooks(root)
    if root ~= _G.GossipFrame or QuestText.hooks[root] then return end
    if type(root.RegisterFontString) ~= "function" or type(root.UpdateTheme) ~= "function" then return end
    hooksecurefunc(root, "RegisterFontString", function(_, region)
        if not NS.IsCombatLocked() then Paint(region, "text") end
    end)
    hooksecurefunc(root, "UpdateTheme", function()
        if not NS.IsCombatLocked() then PaintGossip() end
    end)
    QuestText.hooks[root] = true
end

local function PaintCurrent()
    if NS.IsCombatLocked() then return end
    for name, role in pairs(fields) do Paint(_G[name], role) end
    local rewards = _G.QuestInfoRewardsFrame
    if rewards then PaintRewards(rewards) end
    local objectives = _G.QuestInfoObjectivesFrame
    local list = objectives and objectives.Objectives
    if type(list) == "table" then
        for index = 1, math.min(#list, MAX_OBJECTIVES) do Paint(list[index], "text") end
    end
    local seal = _G.QuestInfoSealFrame
    if seal then Paint(seal.Text, "text") end
    local greeting = _G.QuestFrameGreetingPanel
    local pool = greeting and greeting.titleButtonPool
    if pool and type(pool.EnumerateActive) == "function" then PaintGreetingButtons(pool) end
    PaintGossip()
end

local function RestoreRoot(root)
    -- Clearing entries during pairs() is allowed; nothing is added meanwhile.
    for region, record in pairs(QuestText.colors) do
        if ActiveRoot(region) == root then Release(region, record) end
    end
end

-- NPC greeting text uses these native setters outside QuestInfo_Display.
local function OnGreetingText(region)
    if not NS.IsCombatLocked() then Paint(region, "text") end
end

local function OnGreetingTitle(region)
    if not NS.IsCombatLocked() then Paint(region, "title") end
end

local globalHooks = {
    { "QuestInfo_Display", PaintCurrent },
    { "QuestFrame_SetTextColor", OnGreetingText },
    { "QuestFrame_SetTitleTextColor", OnGreetingTitle },
    { "QuestFrameGreetingPanel_OnShow", PaintCurrent },
}

-- These Blizzard functions are called through their globals.
local function EnsureHooks()
    for index = 1, #globalHooks do
        local name, callback = globalHooks[index][1], globalHooks[index][2]
        if not QuestText.hooks[name] and type(_G[name]) == "function" then
            hooksecurefunc(name, callback)
            QuestText.hooks[name] = true
        end
    end
end

function QuestText.Activate(root, owner)
    if not root or NS.IsCombatLocked() then return false end
    local owners = QuestText.roots[root]
    if not owners then
        owners = {}
        QuestText.roots[root] = owners
    end
    owners[owner] = true
    EnsureHooks()
    EnsureGossipHooks(root)
    PaintCurrent()
    return true
end

function QuestText.Deactivate(root, owner)
    local owners = root and QuestText.roots[root]
    if not owners then return end
    owners[owner] = nil
    if next(owners) then return end
    -- Restore while the root is still recognized for parent-chain matching.
    RestoreRoot(root)
    QuestText.roots[root] = nil
end

function QuestText.Refresh()
    PaintCurrent()
end

NS.Registry.AddListener(QuestText, function(_, domain)
    if domain == "color" or domain == "theme" then PaintCurrent() end
end)

return QuestText
