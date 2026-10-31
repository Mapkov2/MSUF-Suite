local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end
local Filters = {}
P.GroupFinderFilters = Filters
local ID = "groupFinderTools"
local DIFFICULTIES = { "difficultyNormal", "difficultyHeroic", "difficultyMythic", "difficultyMythicPlus" }
local function Eligible()
    local frame = LFGListFrame
    return not NS.InCombat() and frame.SearchPanel:IsVisible()
        and frame.CategorySelection.selectedCategory == GROUP_FINDER_CATEGORY_ID_DUNGEONS
        and GameRulesUtil.IsPlayerAtEffectiveMaxLevel()
end
Filters.Eligible = Eligible
local function Groups(text)
    local ids, seen = {}, {}
    for token in (text or ""):sub(1, 400):gmatch("%d+") do
        local id = tonumber(token)
        if id > 0 and id < 2147483647 and not seen[id] and #ids < 64 then
            ids[#ids + 1], seen[id] = id, true
        end
    end
    return ids, seen
end
function Filters.Apply()
    local m = S.instances[ID]
    if not m.active or not m.config.filters or not Eligible() then return false end
    local native = C_LFGList.GetAdvancedFilter()
    if not S.Public(native) or type(native) ~= "table" then return false end
    -- The API returns data, not a native frame. Preserve every field this
    -- helper does not own (playstyle, class and future native filter fields).
    local data = {}
    for key, value in pairs(native) do data[key] = value end
    local c = m.config
    for index, key in ipairs(DIFFICULTIES) do data[key] = c.difficulty == 1 or c.difficulty == index + 1 end
    data.minimumRating, data.activities = c.minimumRating, Groups(c.activities)
    data.hasTank, data.hasHealer = c.hasTank, c.hasHealer
    if c.needsRole then
        local _, tank, healer, damage = GetLFGRoles()
        if not S.Public(tank) or not S.Public(healer) or not S.Public(damage) then return false end
        data.needsTank, data.needsHealer, data.needsDamage = tank == true, healer == true, damage == true
    else
        data.needsTank, data.needsHealer, data.needsDamage = false, false, false end
    -- The next search the player starts uses the saved filter. Running
    -- LFGListSearchPanel_DoSearch from here would taint the search panel
    -- fields Blizzard reads when it handles the results.
    C_LFGList.SaveAdvancedFilter(data)
    return true
end
local function SelectGroup(id, config, save)
    local ids, seen = Groups(config.activities)
    if seen[id] then
        for i = #ids, 1, -1 do if ids[i] == id then table.remove(ids, i) end end
    elseif #ids < 64 then
        ids[#ids + 1] = id end
    save(table.concat(ids, ","))
end
local function DungeonMenu(root, current, save, valid)
    local groups = C_LFGList.GetAvailableActivityGroups(GROUP_FINDER_CATEGORY_ID_DUNGEONS, Enum.LFGListFilter.PvE)
    if not S.Public(groups) or type(groups) ~= "table" then return end
    root:CreateButton(S.Text("All dungeons"), function() save("") end)
    for i = 1, math.min(#groups, 100) do
        local id = groups[i]
        if S.Finite(id) then
            local name = C_LFGList.GetActivityGroupInfo(id)
            if S.PublicText(name) then
                root:CreateCheckbox(name, function()
                    local _, selected = Groups(current().activities)
                    return selected[id] == true
                end, function()
                    if valid() then SelectGroup(id, current(), save) end
                end)
            end
        end
    end
end
function Filters.Menu(button)
    local m = S.instances[ID]
    if not m.active or not m.config.filters or not Eligible() then return end
    local config, profile, baseline = m.config, NS.DB, m.config.activities
    local function Valid()
        return m.active and m.config.filters and m.config == config and NS.DB == profile
            and config.activities == baseline and Eligible()
    end
    local function Save(value)
        if Valid() and S.Set(ID, "activities", value) then config, baseline = m.config, m.config.activities end
    end
    S.ContextMenu(button, function(_, root)
        root:CreateTitle(S.Text("Search filters"))
        root:CreateButton(S.Text("Apply saved filters"), function() if Valid() then Filters.Apply() end end)
        local dungeons = root:CreateButton(S.Text("Dungeons"))
        DungeonMenu(dungeons, function() return config end, Save, Valid)
        root:CreateButton(S.Text("Configure saved filters"), function() S.Open(ID) end)
    end)
end
