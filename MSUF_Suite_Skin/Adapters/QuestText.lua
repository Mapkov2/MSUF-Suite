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

local function ParentOf(region)
    if not region or type(region.GetParent) ~= "function" then return nil end
    local ok, parent = pcall(region.GetParent, region)
    return ok and parent or nil
end

local function ActiveRoot(region)
    local current = region
    for _ = 1, 20 do
        if not current then return nil end
        if QuestText.roots[current] then return current end
        current = ParentOf(current)
    end
    return nil
end

local function ReadColor(region)
    if not region or type(region.GetTextColor) ~= "function" then return nil end
    local ok, r, g, b, a = pcall(region.GetTextColor, region)
    if not ok or type(r) ~= "number" then return nil end
    return { r, g, b, type(a) == "number" and a or 1 }
end

local function SameColor(a, b)
    if not a or not b then return false end
    for index = 1, 4 do
        if math.abs(a[index] - b[index]) > 0.015 then return false end
    end
    return true
end

local function Paint(region, role)
    if not region or type(region.SetTextColor) ~= "function" then return end
    if not ActiveRoot(region) then
        -- QuestInfo FontStrings are shared between the map, NPC dialog and
        -- popup. Blizzard can move one without repainting when its material
        -- cache still matches, so restore our color on an unskinned parent.
        local record = QuestText.colors[region]
        if record then
            if SameColor(ReadColor(region), record.applied) then
                pcall(region.SetTextColor, region, unpack(record.original))
            end
            QuestText.colors[region] = nil
        end
        return
    end
    local current = ReadColor(region)
    if not current then return end
    local record = QuestText.colors[region]
    if not record then
        record = { original = current }
        QuestText.colors[region] = record
    elseif not SameColor(current, record.applied) then
        -- Blizzard has repainted for a different quest/material since our pass.
        record.original = current
    end
    local r, g, b = NS.Theme.GetColor(role)
    local applied = { r, g, b, current[4] }
    if pcall(region.SetTextColor, region, unpack(applied)) then
        record.applied = applied
    end
end

local function PaintCurrent()
    if NS.IsCombatLocked() then return end
    for name, role in pairs(fields) do Paint(_G[name], role) end
    local rewards = _G.QuestInfoRewardsFrame
    if rewards then
        Paint(rewards.Header, "title")
        Paint(rewards.ItemChooseText, "text")
        Paint(rewards.ItemReceiveText, "text")
        Paint(rewards.PlayerTitleText, "text")
        Paint(rewards.QuestSessionBonusReward, "text")
        if rewards.XPFrame then Paint(rewards.XPFrame.ReceiveText, "text") end
    end
    local objectives = _G.QuestInfoObjectivesFrame
    local list = objectives and objectives.Objectives
    if type(list) == "table" then
        for index = 1, math.min(#list, 40) do Paint(list[index], "text") end
    end
    local seal = _G.QuestInfoSealFrame
    if seal then Paint(seal.Text, "text") end
    local greeting = _G.QuestFrameGreetingPanel
    local pool = greeting and greeting.titleButtonPool
    if pool and type(pool.EnumerateActive) == "function" then
        for button in pool:EnumerateActive() do
            if button and type(button.GetFontString) == "function" then
                Paint(button:GetFontString(), "text")
            end
        end
    end
end

local function RestoreRoot(root)
    for region, record in pairs(QuestText.colors) do
        if ActiveRoot(region) == root then
            if SameColor(ReadColor(region), record.applied) then
                pcall(region.SetTextColor, region, unpack(record.original))
            end
            QuestText.colors[region] = nil
        end
    end
end

local function EnsureHooks()
    if type(hooksecurefunc) ~= "function" then return end
    local function Hook(name, callback)
        if QuestText.hooks[name] or type(_G[name]) ~= "function" then return end
        hooksecurefunc(name, callback)
        QuestText.hooks[name] = true
    end
    Hook("QuestInfo_Display", PaintCurrent)
    -- NPC greeting text uses these native setters outside QuestInfo_Display.
    for _, name in ipairs({ "QuestFrame_SetTextColor", "QuestFrame_SetTitleTextColor" }) do
        Hook(name, function(region)
            if not NS.IsCombatLocked() then
                Paint(region, name == "QuestFrame_SetTitleTextColor" and "title" or "text")
            end
        end)
    end
    Hook("QuestFrameGreetingPanel_OnShow", PaintCurrent)
end

function QuestText.Activate(root, owner)
    if not root or NS.IsCombatLocked() then return false end
    local owners = QuestText.roots[root]
    if not owners then owners = {}; QuestText.roots[root] = owners end
    owners[owner] = true
    EnsureHooks()
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

if NS.Registry then
    NS.Registry.AddListener(QuestText, function(_, domain)
        if domain == "color" or domain == "theme" then PaintCurrent() end
    end)
end
