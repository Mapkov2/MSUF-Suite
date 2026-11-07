local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client.isForever then return end
local Data, Lines = P.GatheringData, S.TooltipLines
local M = { names = {}, pending = {}, cache = {}, skills = {}, rows = {} }
local HERBALISM, MINING = 182, 186
local CACHE_LIMIT = 256
local IN_COMBAT = { inCombat = true }

local function ClearCache(self)
    wipe(self.cache)
    self.cacheSize = 0
end

local function ReadSkill(id, child)
    if not C_SkillInfo or not C_SkillInfo.GetSkillLineInfoByID then return end
    local read = C_SkillInfo.GetSkillLineInfoByID
    local info = read(id)
    if not S.Public(info) then return end
    if info == nil then info = read(child) end
    if not S.Public(info) or type(info) ~= "table" or not canaccesstable(info) then return end
    if not S.Finite(info.rank) or not S.Finite(info.modifier) then return end
    return info.rank + info.modifier, S.PublicText(info.name)
end

local function Skills(self)
    local herbs, herbName = ReadSkill(HERBALISM, 2944)
    local ores, oreName = ReadSkill(MINING, 2946)
    self.skills[HERBALISM], self.skills[MINING] = herbs, ores
    self.herbName, self.oreName = herbName, oreName
    ClearCache(self)
end

local function RememberHerb(self, item, name)
    local row = { HERBALISM, Data.herbs[item] }
    self.rows[item], self.names[name] = row, row
end

local function ItemReady(self, _, item, success)
    if not S.Finite(item) or not self.pending[item] or not S.Public(success) then return end
    self.pending[item] = nil
    if not next(self.pending) then self.context:RemoveEvent("ITEM_DATA_LOAD_RESULT") end
    local name = success and S.PublicText(C_Item.GetItemNameByID(item))
    if name then
        RememberHerb(self, item, name)
        ClearCache(self)
    end
end

local function Herbs(self)
    for item in pairs(Data.herbs) do
        if not self.rows[item] and not self.pending[item] then
            local name = S.PublicText(C_Item.GetItemNameByID(item))
            if name then
                RememberHerb(self, item, name)
            else
                if not next(self.pending) then self.context:Event("ITEM_DATA_LOAD_RESULT", ItemReady, IN_COMBAT) end
                self.pending[item] = true
                C_Item.RequestLoadItemDataByID(item)
            end
        end
    end
end

local function Color(rank, required, enabled)
    if rank < required then return 1, .2, .2 end
    if not enabled then return .25, 1, .35 end
    local base = required == 1 and 0 or required
    if rank < base + 25 then return 1, .5, .1 end
    if rank < base + 50 then return 1, .85, .15 end
    if rank < base + 100 then return .25, 1, .35 end
    return .6, .6, .6
end

local function Resolve(self, text)
    local saved = self.cache[text]
    if saved ~= nil then return saved end
    local node = self.names[text]
    if not node then
        local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        node = self.names[plain]
    end
    local row = false
    local rank = node and self.skills[node[1]]
    if rank then
        local name = node[1] == HERBALISM and self.herbName or self.oreName
        name = name or S.Text(node[1] == HERBALISM and "Herbalism" or "Mining")
        local r, g, b = Color(rank, node[2], self.config.skillColors)
        row = { S.Text("%s (%s)"):format(text, name),
            S.Text("Required: %d - Current: %d"):format(node[2], rank), r, g, b }
    end
    if self.cacheSize >= CACHE_LIMIT then ClearCache(self) end
    self.cache[text], self.cacheSize = row, self.cacheSize + 1
    return row
end

local function Append(tooltip, data)
    local lines = data.lines
    if not S.Public(lines) or type(lines) ~= "table" or not canaccesstable(lines) then return end
    for i = 1, #lines do
        local line = lines[i]
        if S.Public(line) and type(line) == "table" and canaccesstable(line) then
            local text = S.PublicText(line.leftText)
            local row = text and Resolve(M, text)
            if row then tooltip:AddDoubleLine(row[1], row[2], .65, .81, .87, row[3], row[4], row[5]) end
        end
    end
end

local function WorldTooltip(tooltip, data)
    if M.config.worldTooltips then Append(tooltip, data) end
end

local function MinimapTooltip(tooltip, data)
    if M.config.minimapTooltips then Append(tooltip, data) end
end

function M:Enable()
    if not self.registered then
        Lines.Add(self, "Object", WorldTooltip)
        Lines.Add(self, "MinimapMouseover", MinimapTooltip)
        for i = 1, #Data.ores do
            local ore = Data.ores[i]
            local row = { MINING, ore[2] }
            self.names[S.Text(ore[1])], self.names[ore[1]] = row, row
        end
        self.registered = true
    end
    Skills(self)
    Herbs(self)
    self.context:Event("SKILL_LINES_CHANGED", Skills, IN_COMBAT)
end

function M:Refresh()
    Skills(self)
    Herbs(self)
end

function M:Disable()
    ClearCache(self)
    wipe(self.pending)
end

S.Install("gatheringTooltips", M)
