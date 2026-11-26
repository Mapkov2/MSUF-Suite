local _, P = ...
local NS, S = P.NS, P.Suite
local ID = "playerBuffGroups"
local HUD = NS.HUDVisibility
local Module = { groups = {} }
local GROUPS = { "class", "consumable", "world", "custom", "custom2", "custom3", "other" }
local BUFF_FILTER = "HELPFUL"
local DEFAULT_CLASS = { 1126, 1459, 21562, 6673 }
local FOREVER_CLASS = {
    1126, 5232, 6756, 5234, 8907, 9884, 9885, 21849, 21850,
    1459, 1460, 1461, 10156, 10157, 23028, 1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564,
    6673, 5242, 6192, 11549, 11550, 11551, 25289, 14752, 14818, 14819, 27841, 27681,
}
local FOREVER_FOOD = { 19705, 18125, 18141, 18192, 18194, 22730, 25661, 1243969, 1249519, 1249520 }
local MAX_CUSTOM_IDS, MAX_ICONS = 80, 16

local function Include(set, list)
    if list then
        for index = 1, #list do set[list[index]] = true end
    end
end

local function PresetGroups(class, food, world)
    Include(class, NS.Client.isForever and FOREVER_CLASS or DEFAULT_CLASS)
    for _, entry in ipairs(NS.BuffReminderClassReminders or {}) do
        local spec = NS.Client.isForever and entry.forever or entry.retail
        if spec and spec.kind == "aura" then
            Include(class, spec.auras)
            Include(class, spec.casts)
        end
    end
    if NS.Client.isForever then
        Include(food, FOREVER_FOOD)
        world[1229741], world[429959] = true, true
    end
end

local function IncludeText(set, text)
    local count = 0
    for value in text:gmatch("%d+") do
        local id = tonumber(value)
        if id and id > 0 and id <= 2147483647 and not set[id] then
            set[id] = true
            count = count + 1
            if count == MAX_CUSTOM_IDS then break end
        end
    end
end

-- Compile once per settings change. Explicit choices take priority over the
-- supplied categories. Excluding every assigned ID keeps Other disjoint.
local function Compile(config)
    local sets, excluded = {}, {}
    for index = 1, #GROUPS - 1 do sets[GROUPS[index]] = {} end
    PresetGroups(sets.class, sets.consumable, sets.world)
    local explicit = {}
    for index = 1, #GROUPS - 1 do
        local key = GROUPS[index]
        local ids = {}
        IncludeText(ids, config[key .. "Spells"])
        for id in pairs(ids) do explicit[id] = key end
    end
    for id, key in pairs(explicit) do
        for index = 1, #GROUPS - 1 do
            local group = GROUPS[index]
            sets[group][id] = group == key or nil
        end
    end
    for index = 1, #GROUPS - 1 do
        for id in pairs(sets[GROUPS[index]]) do
            if excluded[id] then sets[GROUPS[index]][id] = nil else excluded[id] = true end
        end
    end
    local hidden = {}
    IncludeText(hidden, config.hiddenSpells)
    for id in pairs(hidden) do excluded[id] = true end
    for group, set in pairs(sets) do
        for id in pairs(hidden) do set[id] = nil end
        sets[group] = { includeSpellIDs = set }
    end
    sets.other = { excludeSpellIDs = excluded }
    return sets
end

local function Prepare(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetSize(170, 32)
    host:EnableMouse(false)
    self.host = host
    local container = S.CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
    self.container = container
    NS.Client.RealAurasOnly(container)
    container:SetPoint("TOPRIGHT", host, "TOPRIGHT")
    container:SetFlowLayoutAnchorPoint("TOPRIGHT")
    container:SetFlowLayoutGrowthDirection(-1, -1)
    container:SetUnit("player")
end

local function ApplyGroup(self, key, filter, config, index)
    local size = config.iconSize
    local layout = { elementWidth = size, elementHeight = size, elementSpacing = 4,
        groupSpacing = 9, lineSpacing = 5, groupLineSpacing = 5, layoutIndex = index }
    local limit = config[key .. "Compact"] and 1 or MAX_ICONS
    local enabled = config[key .. "Enabled"] == true and (key == "other" or next(filter.includeSpellIDs) ~= nil)
    local container = self.container
    if not self.groups[key] then
        container:AddAuraGroup(key, BUFF_FILTER, {
            candidateFilters = filter, layout = layout, maxFrameCount = limit,
            sortMethod = AuraContainerSortMethod.ExpirationOnly,
        })
        self.groups[key] = true
    else
        container:SetAuraGroupCandidateFilters(key, filter)
        container:SetAuraGroupLayout(key, layout)
        container:SetAuraGroupMaxFrameCount(key, limit)
    end
    container:SetAuraGroupEnabled(key, enabled)
end

local function GroupOrder(config)
    local keys = {}
    for i = 1, #GROUPS do keys[i] = GROUPS[i] end
    table.sort(keys, function(left, right)
        local a, b = config[left .. "Priority"], config[right .. "Priority"]
        if a == b then return left < right end
        return a < b
    end)
    return keys
end

local function Rebuild(self)
    if not self.active then return end
    if NS.InCombat() then return end
    if NS.Client.AuraBuildBlocked() then
        NS.Client.AfterAuraBuild(self, Rebuild)
        return
    end
    self.pending = false
    Prepare(self)
    local config = self.config
    local filters = Compile(config)
    local order = GroupOrder(config)
    self.container:SetEnabled(false)
    self.host:SetSize(config.perRow * (config.iconSize + 4) - 4, config.iconSize)
    S.PlaceHost(self.host, config, "TOPRIGHT")
    self.container:SetFlowLayoutMaximumLineSize(self.host:GetWidth())
    for index = 1, #order do
        local key = order[index]
        ApplyGroup(self, key, filters[key], config, index)
    end
    self.container:SetEnabled(true)
    self.host:SetAlpha(HUD and not S.editMode and HUD.Factor(ID) or 1)
    self.host:Show()
end

local function OnCombatEnd(self)
    if self.pending then Rebuild(self) end
end

function Module:Refresh()
    self.pending = true
    Rebuild(self)
end

function Module:Enable()
    self.context:Event("PLAYER_REGEN_ENABLED", OnCombatEnd)
    self:Refresh()
end

function Module:Disable()
    NS.Client.CancelAuraBuild(self)
    self.pending = false
    if not self.host then return end
    self.host:Hide()
    self.container:SetEnabled(false)
end

function Module:RegisterMovers()
    S.RegisterOwnedMover(ID, "groups", {
        label = "Player buff groups", order = 652,
        point = function() return "TOPRIGHT" end,
        xKey = "x", yKey = "y",
        getFrame = function() return self.host end,
        sizeKeys = { "iconSize", "perRow", "scale" },
    })
end

if HUD then
    HUD.Register(ID, function()
        if Module.active and Module.host then Module.host:SetAlpha(S.editMode and 1 or HUD.Factor(ID)) end
    end)
end

S.Install(ID, Module)
