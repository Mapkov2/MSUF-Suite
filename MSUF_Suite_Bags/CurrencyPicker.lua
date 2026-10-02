local _, P = ...
local S, M = P.Suite, P.BagsModule
local selected, order, seen, options, opened = {}, {}, {}, {}, {}
local MAX_DEPTH = 6

local function ReadSelected()
    for key in pairs(selected) do selected[key] = nil end
    for i = #order, 1, -1 do order[i] = nil end
    for value in (M.config.currencyIDs or ""):gmatch("%d+") do
        local id = tonumber(value)
        if not selected[id] and id > 0 and id < 2147483647 and #order < 8 then
            selected[id], order[#order + 1] = true, id
        end
    end
end

local function Toggle(id)
    if selected[id] then
        selected[id] = nil
        for i = #order, 1, -1 do
            if order[i] == id then
                table.remove(order, i)
                break
            end
        end
    elseif #order < 8 then order[#order + 1], selected[id] = id, true end
    S.Set("bags", "currencyIDs", table.concat(order, ","))
    for currencyID, option in pairs(options) do option:SetEnabled(selected[currencyID] or #order < 8) end
end

local function AddCurrency(root, id, name)
    if not S.Finite(id) or id <= 0 or seen[id] or not S.Public(name) or type(name) ~= "string" then return end
    seen[id] = true
    local option = root:CreateCheckbox(name, function() return selected[id] == true end, function() Toggle(id) end)
    option:SetEnabled(selected[id] or #order < 8)
    options[id] = option
end

local function Header(index)
    local info = C_CurrencyInfo.GetCurrencyListInfo(index)
    if S.Public(info) and type(info) == "table" and S.Public(info.isHeader) and info.isHeader
        and S.Public(info.name) and type(info.name) == "string" then
        return info
    end
end

-- One key per visible header that stays the same while other headers expand
-- or collapse: its parent's key, its name and how many earlier siblings
-- carry that name (two expansions can each hold a "Dungeon and Raid").
-- Blizzard lists a header's children only while it is expanded, so every
-- sibling of a visible header is visible and the count is stable. Read
-- top-down once per pass; expanded[index] is the header's state then.
local keys, expanded, parents, counts = {}, {}, {}, {}
local function ReadHeaders()
    for index in pairs(keys) do keys[index], expanded[index] = nil, nil end
    for name in pairs(counts) do counts[name] = nil end
    for index = 1, C_CurrencyInfo.GetCurrencyListSize() do
        local info = Header(index)
        if info then
            local depth = S.Finite(info.currencyListDepth) and info.currencyListDepth or 0
            local sibling = (depth > 0 and parents[depth - 1] or "") .. "\031" .. info.name
            counts[sibling] = (counts[sibling] or 0) + 1
            local key = sibling .. "#" .. counts[sibling]
            parents[depth], keys[index], expanded[index] = key, key, info.isHeaderExpanded == true
        end
    end
end

-- Blizzard's currency list only returns the entries of expanded headers, and
-- which headers are expanded is the player's own Currency tab state. The
-- picker expands the collapsed ones to read the whole list and collapses
-- exactly those again before it returns. Bottom-up, so expanding or
-- collapsing a header never moves a row that is still to be visited, and the
-- keys read before the pass stay valid for every row it still visits.
local function ExpandAll()
    for _ = 1, MAX_DEPTH do
        local changed = false
        ReadHeaders()
        for index = C_CurrencyInfo.GetCurrencyListSize(), 1, -1 do
            local key = keys[index]
            if key and not expanded[index] and not opened[key] then
                opened[key] = true
                C_CurrencyInfo.ExpandCurrencyList(index, true)
                changed = true
            end
        end
        if not changed then return end
    end
end

local function RestoreExpansion()
    ReadHeaders()
    for index = C_CurrencyInfo.GetCurrencyListSize(), 1, -1 do
        local key = keys[index]
        if key and opened[key] and expanded[index] then C_CurrencyInfo.ExpandCurrencyList(index, false) end
    end
    for key in pairs(opened) do opened[key] = nil end
end

local function AddList(root)
    ExpandAll()
    for index = 1, C_CurrencyInfo.GetCurrencyListSize() do
        local info = C_CurrencyInfo.GetCurrencyListInfo(index)
        if S.Public(info) and type(info) == "table" and S.Public(info.name) and type(info.name) == "string" then
            if S.Public(info.isHeader) and info.isHeader then
                root:CreateTitle(info.name)
            else
                local link = C_CurrencyInfo.GetCurrencyListLink(index)
                if S.Public(link) and type(link) == "string" then
                    AddCurrency(root, C_CurrencyInfo.GetCurrencyIDFromLink(link), info.name)
                end
            end
        end
    end
    RestoreExpansion()
end

function S.BagCurrencyMenu(anchor)
    if not M.active then return false end
    ReadSelected()
    MenuUtil.CreateContextMenu(anchor or UIParent, function(_, root)
        for id in pairs(seen) do seen[id], options[id] = nil, nil end
        root:SetScrollMode(420)
        root:CreateTitle(S.Text("Choose currencies"))
        root:CreateTitle(S.Text("Select up to eight currencies."))
        for i = 1, #order do
            local info = C_CurrencyInfo.GetCurrencyInfo(order[i])
            if S.Public(info) and type(info) == "table" then AddCurrency(root, order[i], info.name) end
        end
        root:CreateButton(S.Text("Clear selection"), function() S.Set("bags", "currencyIDs", "") end)
        root:CreateDivider()
        AddList(root)
    end)
    return true
end
