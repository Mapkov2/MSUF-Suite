local _, NS = ...
local Rules = {}
NS.InventoryRules = Rules
-- Number fields take a comparison or an inclusive range (level=200-300).
-- exp is the expansion's number, or its name as the client shows it (exp:war).
local FIELDS = { id = "itemID", quality = "quality", count = "count", level = "itemLevel", bag = "bag",
    exp = "expansion", expansion = "expansion" }
local NAMED = { exp = "expansionName", expansion = "expansionName" }
local TEXT = { name = "name", type = "className", subtype = "subclassName", set = "setNames", slot = "slotName" }
local COMPARISONS = { ["="] = true, [":"] = true, [">"] = true, ["<"] = true, [">="] = true, ["<="] = true }
local MAX_NUMBER = 10000000

-- Enum.ItemBind (ItemConstantsDocumentation, Retail and Forever) and
-- Enum.ItemQuality.Poor. Both account bindings are Warbound; Bind on Equip and
-- Warbound until equipped are those states only while the item is not bound.
local BIND_ON_EQUIP, BIND_WARBOUND_UNTIL_EQUIPPED = 2, 9
local WARBOUND = { [7] = true, [8] = true }
local QUALITY_POOR = 0

local FLAGS = {
    bound = function(item) return item.bound == true end,
    quest = function(item) return item.quest == true end,
    locked = function(item) return item.locked == true end,
    equipment = function(item)
        return item.equipLoc and item.equipLoc ~= "" and item.equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
    end,
    boe = function(item) return item.bindType == BIND_ON_EQUIP and item.bound ~= true end,
    wue = function(item) return item.bindType == BIND_WARBOUND_UNTIL_EQUIPPED and item.bound ~= true end,
    warbound = function(item) return WARBOUND[item.bindType] == true end,
    junk = function(item) return item.quality == QUALITY_POOR end,
    set = function(item) return item.setNames ~= nil end,
}

-- low, high of "10-20" (ends in either order); a plain number is low alone.
local function Bounds(argument, operator)
    local first, second = argument:match("^(%d+)-(%d+)$")
    if first and (operator == "=" or operator == ":") then
        first, second = tonumber(first), tonumber(second)
        if first > second then first, second = second, first end
        return first, second
    end
    return tonumber(argument)
end

local function NumberTerm(field, operator, argument, negate)
    if not COMPARISONS[operator] then return nil end
    local number, upper = Bounds(argument, operator)
    if not number or number ~= number or math.abs(number) > MAX_NUMBER or upper and upper > MAX_NUMBER then
        return nil
    end
    return { field = FIELDS[field], operator = operator, number = number, upper = upper, negate = negate }
end

local function Token(value)
    local negate = value:sub(1, 1) == "!"
    if negate then value = value:sub(2) end
    local field, operator, argument = value:match("^([%a]+)([<>:=]+)(.+)$")
    if field then
        field = field:lower()
        local text = operator == ":" or operator == "="
        if FIELDS[field] then
            local term = NumberTerm(field, operator, argument, negate)
            if not term and NAMED[field] and text then
                return { field = NAMED[field], value = argument:lower(), negate = negate }
            end
            return term
        end
        if TEXT[field] and text then
            return { field = TEXT[field], value = argument:lower(), negate = negate }
        end
        local flag = field == "is" and operator == ":" and argument:lower()
        if flag and FLAGS[flag] then return { flag = flag, negate = negate } end
        return nil
    end
    if value == "" then return nil end
    return { field = "search", value = value:lower(), negate = negate }
end

function Rules.Compile(text)
    if type(text) ~= "string" or #text > 512 then return nil, "Use a search of at most 512 characters." end
    local groups, group, word, quote, terms = {}, {}, "", false, 0
    groups[1] = group
    local function Add()
        if word == "" then return true end
        local term = Token(word)
        if not term or terms >= 64 then return false end
        terms, group[#group + 1], word = terms + 1, term, ""
        return true
    end
    for i = 1, #text do
        local char = text:sub(i, i)
        if char == '"' then quote = not quote
        elseif not quote and (char == "|" or char:match("%s")) then
            if not Add() then return nil, "Check the search filters." end
            if char == "|" then
                if #group == 0 then return nil, "Add a filter on both sides of OR." end
                group = {}
                groups[#groups + 1] = group
            end
        else word = word .. char end
    end
    if quote or not Add() then return nil, "Check the search filters and quotation marks." end
    if #groups > 1 and #group == 0 then return nil, "Add a filter on both sides of OR." end
    return groups
end

-- Whether a compiled search holds a term at all. A search of blanks compiles
-- (a search box then filters nothing) but is no rule: it would match every item.
function Rules.HasTerms(compiled)
    for i = 1, #(compiled or {}) do
        if #compiled[i] > 0 then return true end
    end
    return false
end

local function TermMatches(item, term)
    if term.flag then return FLAGS[term.flag](item) end
    local value = item[term.field]
    if term.number then
        if type(value) ~= "number" then return false end
        local op, n = term.operator, term.number
        if term.upper then return value >= n and value <= term.upper end
        if op == ">" then return value > n end
        if op == "<" then return value < n end
        if op == ">=" then return value >= n end
        if op == "<=" then return value <= n end
        return value == n
    end
    if type(value) == "table" then
        for i = 1, #value do
            if value[i]:lower():find(term.value, 1, true) then return true end
        end
        return false
    end
    return type(value) == "string" and value:lower():find(term.value, 1, true) ~= nil
end

-- Accept sanitized inventory records only. Compile on text changes, evaluate without allocations.
function Rules.Matches(compiled, item)
    if not compiled then return false end
    for i = 1, #compiled do
        local match = true
        for j = 1, #compiled[i] do
            local term = compiled[i][j]
            local yes = TermMatches(item, term) and true or false
            if yes == term.negate then match = false break end
        end
        if match then return true end
    end
    return false
end

function Rules.Escape(value)
    return (value:gsub("[%%|\r\n]", function(char) return string.format("%%%02X", char:byte()) end))
end

function Rules.Unescape(value)
    return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end
