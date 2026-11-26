local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Validate a pasted Blizzard layout before exposing its mapping to Settings.
local Catalog = C.Catalog
local MAX_INPUT, MAX_ROWS = 16384, 1024
local NO_LAYOUT = "The string has no layout for your current specialization."
local INVALID = "This Blizzard cooldown layout could not be read."
local UNKNOWN = "No current Blizzard cooldowns match this layout."

local function Whole(value, min)
    return S.Finite(value) and value >= min and value < 2147483648 and math.floor(value) == value
end

local function List(input)
    if type(input) ~= "table" or #input > MAX_ROWS then return false end
    for key, id in pairs(input) do
        if not Whole(key, 1) or key > #input or not Whole(id, 1) then return false end
    end
    for index = 1, #input do
        if input[index] == nil then return false end
    end
    return true
end

local function ValidCategory(category)
    return Whole(category, 0) and Catalog.IsImportCategory(category)
end

local function Moves(layout)
    local input, byID, total = layout[2], {}, 0
    if input == nil then return byID end
    if type(input) ~= "table" then return end
    for category, list in pairs(input) do
        if not ValidCategory(category) or not List(list) then return end
        total = total + #list
        if total > MAX_ROWS then return end
        for index = 1, #list do
            local id = list[index]
            if byID[id] ~= nil then return end
            byID[id] = category
        end
    end
    return byID
end

local function Add(bars, seen, moves, id)
    if seen[id] then return 0 end
    seen[id] = true
    local record = Catalog.records[id]
    if not record then return 0 end
    local category = moves[id]
    if category == nil then category = record.defaultCategory end
    local bar = bars[Catalog.BAR_OF[category]]
    if not bar then return 0 end
    bar[#bar + 1] = record.key
    return 1
end

-- Input is always a user paste. It never enters the native settings store or
-- the cache for Blizzard's active layout.
function S.CooldownManagerReadBlizzardString(input)
    if NS.InCombat() or not S.PublicText(input) or #input > MAX_INPUT then return nil, INVALID end
    local blob = input:match("^%s*(1|[A-Za-z0-9+/]*=?=?)%s*$")
    if not blob then return nil, INVALID end
    C.Cold()
    if not Catalog.Ready() then return nil, "Blizzard's cooldown list is not ready yet." end
    local tag = Catalog.SpecTag()
    if not tag then return nil, NO_LAYOUT end
    if Catalog.specTag ~= tag or Catalog.pass.on then Catalog.Rebuild() end
    if Catalog.specTag ~= tag then return nil, NO_LAYOUT end
    local ok, data = S.Dispatch(NS.Finish, Catalog.DecodeBlizzardLayoutData, blob, 98304)
    if not ok or not data then return nil, INVALID end
    local layout = Catalog.ReadActiveLayout(data, tag)
    if not layout then return nil, NO_LAYOUT end
    local order, moves = layout[1], Moves(layout)
    if not moves or (order ~= nil and not List(order)) then return nil, INVALID end
    if (not order or #order == 0) and next(moves) == nil then return nil, INVALID end
    local any = false
    for index = 1, #(order or C.EMPTY) do
        if Catalog.records[order[index]] then any = true end
    end
    if not any then
        for id in pairs(moves) do
            if Catalog.records[id] then any = true break end
        end
    end
    if not any then return nil, UNKNOWN end
    local bars = { ess = {}, uti = {}, buf = {}, bar = {}, ext = {} }
    local seen, count = {}, 0
    for index = 1, #(order or C.EMPTY) do count = count + Add(bars, seen, moves, order[index]) end
    for index = 1, #Catalog.defaultOrderIDs do
        count = count + Add(bars, seen, moves, Catalog.defaultOrderIDs[index])
    end
    if count == 0 then return nil, UNKNOWN end
    return bars, nil, count
end
