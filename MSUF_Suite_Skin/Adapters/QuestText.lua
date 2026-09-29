local _, NS = ...

-- Blizzard_UIPanels_Game/Mainline/QuestInfo.lua (upstream/forever bd2470ae)
-- sets parchment-dark text in QuestInfo_Display. Our quest and map adapters
-- fade that parchment, so recolor only text currently parented to a skinned
-- quest window. The Blizzard display function remains responsible for content.
-- Blizzard_UIPanels_Game is not load-on-demand (12.1.0, 12.1.5, Forever), so
-- the quest, QuestInfo and gossip frames exist before this skin loads.
local QuestText = {
    roots = setmetatable({}, { __mode = "k" }),
    colors = setmetatable({}, { __mode = "k" }),
    hooks = {},
}
NS.QuestText = QuestText

local Safety = NS.Safety

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
        current = Safety.Read(current, "GetParent")
    end
    return nil
end

-- Puts Blizzard's color back while ours is still showing, then forgets it.
local function Release(region, record)
    local r, g, b, a = Safety.ReadColor(region, "GetTextColor")
    local owned = Safety.ColorMatches(record.applied, r, g, b, a, Safety.COLOR_OWN)
    if record.fixed then
        -- Blizzard uses a fixed font color only with light quest text.
        local native = QuestTextContrast.UseLightText() == true
        Safety.Invoke(region, "SetFixedColor", native)
    end
    if owned then
        local original = record.original
        Safety.Invoke(region, "SetTextColor", original[1], original[2], original[3], original[4])
    end
    QuestText.colors[region] = nil
end

local function Paint(region, role, fixed)
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
    elseif not Safety.ColorMatches(record.applied, currentR, currentG, currentB, currentA, Safety.COLOR_OWN) then
        -- Blizzard has repainted for a different quest/material since our pass.
        local original = record.original
        original[1], original[2], original[3], original[4] = currentR, currentG, currentB, currentA
    end
    local r, g, b = NS.Theme.GetColor(role)
    -- Blizzard applies the fixed-color mode before setting the text color.
    -- Keep that order for quest buttons and registered gossip FontStrings.
    if fixed and Safety.Invoke(region, "SetFixedColor", true) then record.fixed = true end
    if Safety.Invoke(region, "SetTextColor", r, g, b, currentA) then
        local applied = record.applied
        applied[1], applied[2], applied[3], applied[4] = r, g, b, currentA
    end
end

local function PaintRewards(rewards)
    for key, role in pairs(rewardFields) do Paint(rewards[key], role) end
    Paint(rewards.XPFrame.ReceiveText, "text")
end

local function PaintGreetingButtons(pool)
    for button in pool:EnumerateActive() do
        Paint(Safety.Call(button, "GetFontString"), "text", true)
    end
end

-- GossipFrame owns ScrollBox FontStrings rather than the shared QuestInfo
-- globals. Blizzard registers each row and repaints all registered text in
-- UpdateTheme, including after a questTextContrast change.
local function PaintGossip()
    if not QuestText.roots[GossipFrame] then return end
    for region in pairs(GossipFrame.fontStrings) do Paint(region, "text", true) end
end

local function OnGossipFontString(region)
    if not NS.IsCombatLocked() then Paint(region, "text", true) end
end

local function OnGossipTheme()
    if not NS.IsCombatLocked() then PaintGossip() end
end

-- Every hook runs inside Blizzard's own call (QuestInfo_Display, the NPC
-- greeting setup, GossipFrame's row setup), so each paint is its own error
-- boundary and Blizzard's display goes on.
local function Isolated(callback)
    return function(...) Safety.Dispatch(callback, ...) end
end

local function EnsureGossipHooks(root)
    if root ~= GossipFrame or QuestText.hooks[root] then return end
    if type(root.RegisterFontString) ~= "function" or type(root.UpdateTheme) ~= "function" then return end
    hooksecurefunc(root, "RegisterFontString", function(_, region)
        Safety.Dispatch(OnGossipFontString, region)
    end)
    hooksecurefunc(root, "UpdateTheme", Isolated(OnGossipTheme))
    QuestText.hooks[root] = true
end

local function PaintCurrent()
    if NS.IsCombatLocked() then return end
    for name, role in pairs(fields) do Paint(_G[name], role) end
    PaintRewards(QuestInfoRewardsFrame)
    local list = QuestInfoObjectivesFrame.Objectives
    for index = 1, math.min(#list, MAX_OBJECTIVES) do Paint(list[index], "text") end
    Paint(QuestInfoSealFrame.Text, "text")
    PaintGreetingButtons(QuestFrameGreetingPanel.titleButtonPool)
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

-- These Blizzard functions are called through their globals. QUEST_LOG_UPDATE
-- also refreshes the greeting list through QuestFrameGreetingPanel_OnShow.
local PaintCurrentHook = Isolated(PaintCurrent)
local globalHooks = {
    { "QuestInfo_Display", PaintCurrentHook },
    { "QuestFrame_SetTextColor", Isolated(OnGreetingText) },
    { "QuestFrame_SetTitleTextColor", Isolated(OnGreetingTitle) },
    { "QuestFrameGreetingPanel_OnShow", PaintCurrentHook },
}

-- QuestFrame.xml binds the panel's OnShow as function="...", so the script
-- holds the function value from load time and never reaches the global
-- hook above. Opening the greeting is observed on the panel itself.
local function EnsureGreetingShowHook()
    local panel = QuestFrameGreetingPanel
    if QuestText.hooks[panel] then return end
    panel:HookScript("OnShow", PaintCurrentHook)
    QuestText.hooks[panel] = true
end

local function EnsureHooks()
    for index = 1, #globalHooks do
        local name, callback = globalHooks[index][1], globalHooks[index][2]
        if not QuestText.hooks[name] and type(_G[name]) == "function" then
            hooksecurefunc(name, callback)
            QuestText.hooks[name] = true
        end
    end
    EnsureGreetingShowHook()
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
