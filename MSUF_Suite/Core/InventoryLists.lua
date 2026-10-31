local _, NS = ...
local Lists = {}
NS.InventoryLists = Lists
local Rules = NS.InventoryRules

function Lists.Quantities(text)
    local result, count = {}, 0
    if type(text) ~= "string" or #text > 12000 then return nil end
    for line in text:gmatch("[^\r\n]+") do
        local id, quantity = line:match("^%s*(%d+)%s*=%s*(%d+)%s*$")
        id, quantity = tonumber(id), tonumber(quantity)
        if not id or id < 1 or id > 9999999 or not quantity or quantity < 1 or quantity > 99999 then return nil end
        if not result[id] then count = count + 1 end
        if count > 200 then return nil end
        result[id] = quantity
    end
    return result
end

function Lists.EncodeQuantities(values)
    local ids, lines = {}, {}
    for id, count in pairs(values) do
        if type(id) ~= "number" or id % 1 ~= 0 or id < 1 or id > 9999999
            or type(count) ~= "number" or count % 1 ~= 0 or count < 1 or count > 99999 then return nil end
        ids[#ids + 1] = id
    end
    if #ids > 200 then return nil end
    table.sort(ids)
    for i = 1, #ids do lines[i] = ids[i] .. "=" .. values[ids[i]] end
    return table.concat(lines, "\n")
end

function Lists.Templates(text)
    local result = {}
    if type(text) ~= "string" or #text > 24000 then return result end
    for line in text:gmatch("[^\r\n]+") do
        local name, recipient, subject, items = line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
        if items and #result < 24 then
            name, recipient, subject, items = Rules.Unescape(name), Rules.Unescape(recipient), Rules.Unescape(subject), Rules.Unescape(items)
            if #name > 0 and #name <= 64 and #recipient <= 128 and #subject <= 120 and Lists.Quantities(items) then
                result[#result + 1] = { name = name, recipient = recipient, subject = subject, items = items }
            end
        end
    end
    return result
end

function Lists.EncodeTemplates(entries)
    if #entries > 24 then return nil end
    local lines = {}
    for i = 1, #entries do
        local row = entries[i]
        if #row.name < 1 or #row.name > 64 or #row.recipient > 128 or #row.subject > 120 or not Lists.Quantities(row.items) then return nil end
        lines[i] = Rules.Escape(row.name) .. "|" .. Rules.Escape(row.recipient) .. "|"
            .. Rules.Escape(row.subject) .. "|" .. Rules.Escape(row.items)
    end
    local text = table.concat(lines, "\n")
    return #text <= 24000 and text or nil
end
