local _, P = ...
local NS = P.NS
-- The tree behind the visual search builder (QueryEditor.lua). The smart
-- search text (MSUF_Suite/Core/InventoryRules.lua) stays the one stored and
-- matched format: words are AND, "|" separates OR alternatives. A tree of
-- AND/OR groups is written out as that text by expanding it into its
-- alternatives (each nested OR multiplies them), bounded by the limits below
-- and by the 64 filters and 512 characters the search itself takes. Text read
-- back becomes one OR group of AND groups: the nesting of an edit lives as
-- long as its builder window, the text is what is saved.
local Tree = {}
P.QueryTree = Tree
Tree.MAX_DEPTH, Tree.MAX_NODES, Tree.MAX_ALTERNATIVES, Tree.MAX_TERMS, Tree.MAX_LENGTH = 4, 40, 16, 64, 512

-- Fields of the search grammar: kind "text" (contains), "number" (compare or
-- range), "flag" (is:...). exp also takes an expansion name.
Tree.FIELDS = {
    { key = "text", label = "Name contains", kind = "text" },
    { key = "name", label = "Name", kind = "text" },
    { key = "type", label = "Type", kind = "text" },
    { key = "subtype", label = "Subtype", kind = "text" },
    { key = "slot", label = "Equipment slot", kind = "text" },
    { key = "set", label = "Equipment set", kind = "text" },
    { key = "quality", label = "Quality", kind = "number" },
    { key = "level", label = "Item level", kind = "number" },
    { key = "count", label = "Count", kind = "number" },
    { key = "exp", label = "Expansion", kind = "number", named = true },
    { key = "id", label = "Item ID", kind = "number" },
    { key = "bag", label = "Bag", kind = "number" },
    { key = "is", label = "Is", kind = "flag" },
}
Tree.byField = {}
for i = 1, #Tree.FIELDS do Tree.byField[Tree.FIELDS[i].key] = Tree.FIELDS[i] end
Tree.ALIASES = { expansion = "exp" }
Tree.NUMBER_OPS = { "=", ">", "<", ">=", "<=", "range" }
Tree.TEXT_OPS = { ":" }
Tree.FLAGS = { "equipment", "bound", "boe", "wue", "warbound", "junk", "quest", "set", "locked" }
Tree.RETAIL_FLAGS = { wue = true, warbound = true }
local COMPARE = { ["="] = true, [">"] = true, ["<"] = true, [">="] = true, ["<="] = true, [":"] = true }
local FLAG_SET = {}
for i = 1, #Tree.FLAGS do FLAG_SET[Tree.FLAGS[i]] = true end

------------------------------------------------------------------ nodes
function Tree.Group(mode)
    return { kind = "group", mode = mode == "or" and "or" or "and", children = {} }
end

function Tree.Term(field, op, value, negate)
    local spec = Tree.byField[field] or Tree.byField.text
    local term = { kind = "term", field = spec.key, negate = negate == true }
    if spec.kind == "number" then
        term.op = op or ">="
        term.value = value or ""
    elseif spec.kind == "flag" then
        term.op, term.value = ":", FLAG_SET[value] and value or "equipment"
    else
        term.op, term.value = ":", value or ""
    end
    return term
end

-- A word that is no filter of the grammar stays as typed (field "raw"): the
-- search then does not compile and the builder says so.
local function Raw(word, negate)
    return { kind = "term", field = "raw", op = ":", value = word, negate = negate }
end

------------------------------------------------------------------ reading text
-- Splits text like InventoryRules.Compile: quotes group blanks and "|", and
-- vanish; blanks end a word; "|" starts the next alternative.
local function Words(text)
    local alternatives, words, word, quote = {}, {}, "", false
    alternatives[1] = words
    for i = 1, #text do
        local char = text:sub(i, i)
        if char == '"' then
            quote = not quote
        elseif not quote and (char == "|" or char:match("%s")) then
            if word ~= "" then words[#words + 1], word = word, "" end
            if char == "|" then
                words = {}
                alternatives[#alternatives + 1] = words
            end
        else
            word = word .. char
        end
    end
    if word ~= "" then words[#words + 1] = word end
    return alternatives
end

local function NumberTerm(field, op, argument, negate)
    local low, high = argument:match("^(%d+)-(%d+)$")
    if low and (op == "=" or op == ":") then
        return { kind = "term", field = field, op = "range", value = low .. "-" .. high, negate = negate }
    end
    if argument:match("^%d+$") and COMPARE[op] then
        return { kind = "term", field = field, op = op == ":" and "=" or op, value = argument, negate = negate }
    end
    if Tree.byField[field].named and (op == ":" or op == "=") then
        return { kind = "term", field = field, op = "name", value = argument, negate = negate }
    end
end

function Tree.ParseWord(word)
    local negate = word:sub(1, 1) == "!"
    local body = negate and word:sub(2) or word
    if body == "" then return Raw(word, false) end
    local field, op, argument = body:match("^([%a]+)([<>:=]+)(.+)$")
    if not field then return { kind = "term", field = "text", op = ":", value = body, negate = negate } end
    field = field:lower()
    field = Tree.ALIASES[field] or field
    local spec = Tree.byField[field]
    if not spec or spec.key == "text" then return Raw(body, negate) end
    if spec.kind == "number" then return NumberTerm(field, op, argument, negate) or Raw(body, negate) end
    if spec.kind == "flag" then
        local flag = argument:lower()
        if op == ":" and FLAG_SET[flag] then return { kind = "term", field = "is", op = ":", value = flag, negate = negate } end
        return Raw(body, negate)
    end
    if op == ":" or op == "=" then return { kind = "term", field = field, op = ":", value = argument, negate = negate } end
    return Raw(body, negate)
end

-- The tree of a search text: an AND group for one alternative, else an OR
-- group of the alternatives (one filter alone stands without its AND group).
function Tree.Parse(text)
    if type(text) ~= "string" then text = "" end
    local alternatives = Words(text:sub(1, Tree.MAX_LENGTH))
    local groups = {}
    for i = 1, #alternatives do
        local words = alternatives[i]
        if #words > 0 then
            local group = Tree.Group("and")
            for j = 1, #words do group.children[#group.children + 1] = Tree.ParseWord(words[j]) end
            groups[#groups + 1] = group
        end
    end
    if #groups <= 1 then return groups[1] or Tree.Group("and") end
    local root = Tree.Group("or")
    for i = 1, #groups do
        local group = groups[i]
        root.children[i] = #group.children == 1 and group.children[1] or group
    end
    return root
end

------------------------------------------------------------------ writing text
local function Quote(value)
    if value:find("[%s|]") then return '"' .. value .. '"' end
    return value
end

-- A filter's text; nil and a reason for an incomplete one.
function Tree.TermText(term)
    local value = tostring(term.value or ""):gsub('["\r\n]', ""):match("^%s*(.-)%s*$")
    if value == "" then return nil, "Fill in every filter, or remove the empty ones." end
    local prefix = term.negate and "!" or ""
    if term.field == "raw" then return prefix .. Quote(value) end
    if term.field == "text" then
        -- A bare word with an operator would read as a filter: name: keeps it text.
        if value:find("[<>:=!]") then return prefix .. "name:" .. Quote(value) end
        return prefix .. Quote(value)
    end
    local spec = Tree.byField[term.field]
    if not spec then return nil, "Check the search filters." end
    if spec.kind == "flag" then
        if not FLAG_SET[value] then return nil, "Check the search filters." end
        return prefix .. "is:" .. value
    end
    if spec.kind == "number" then
        if term.op == "range" then
            local low, high = value:match("^(%d+)%s*%-%s*(%d+)$")
            if not low then return nil, "Enter a range as two numbers, for example 200-300." end
            return prefix .. spec.key .. "=" .. low .. "-" .. high
        end
        if term.op == "name" and spec.named then return prefix .. spec.key .. ":" .. Quote(value) end
        if not value:match("^%d+$") or not COMPARE[term.op] then return nil, "Enter a whole number." end
        return prefix .. spec.key .. term.op .. value
    end
    return prefix .. spec.key .. ":" .. Quote(value)
end

local Expand

local function AndProduct(alternatives, child, budget)
    local result = {}
    for i = 1, #alternatives do
        for j = 1, #child do
            if #result >= budget then return nil, "This search has too many combinations. Use fewer nested Any of groups." end
            local merged = {}
            for k = 1, #alternatives[i] do merged[#merged + 1] = alternatives[i][k] end
            for k = 1, #child[j] do merged[#merged + 1] = child[j][k] end
            result[#result + 1] = merged
        end
    end
    return result
end

local function ExpandGroup(node, depth)
    local result = node.mode == "or" and {} or { {} }
    local any = false
    for i = 1, #node.children do
        local child, why = Expand(node.children[i], depth + 1)
        if not child then return nil, why end
        if #child > 0 then
            any = true
            if node.mode == "or" then
                for j = 1, #child do result[#result + 1] = child[j] end
                if #result > Tree.MAX_ALTERNATIVES then
                    return nil, "This search has too many combinations. Use fewer nested Any of groups."
                end
            else
                result, why = AndProduct(result, child, Tree.MAX_ALTERNATIVES)
                if not result then return nil, why end
            end
        end
    end
    -- An empty group filters nothing and is left out.
    if not any then return {} end
    return result
end

-- The alternatives of a node: a list of lists of filter texts. An empty
-- group gives none (it is left out); nil and a reason when it cannot be written.
Expand = function(node, depth)
    if node.kind == "group" and depth > Tree.MAX_DEPTH then
        return nil, "Groups can be nested at most four levels deep."
    end
    if node.kind == "term" then
        local text, why = Tree.TermText(node)
        if not text then return nil, why end
        return { { text } }
    end
    return ExpandGroup(node, depth)
end

-- Counts the nodes of a tree (groups and filters).
function Tree.Count(node)
    if node.kind ~= "group" then return 1 end
    local count = 1
    for i = 1, #node.children do count = count + Tree.Count(node.children[i]) end
    return count
end

function Tree.Depth(node)
    if node.kind ~= "group" then return 0 end
    local deepest = 0
    for i = 1, #node.children do deepest = math.max(deepest, Tree.Depth(node.children[i])) end
    return deepest + 1
end

-- The search text of a tree, or nil and a reason. An empty tree is "".
function Tree.Text(root)
    if Tree.Count(root) > Tree.MAX_NODES then return nil, "Use at most 40 filters and groups." end
    local alternatives, why = Expand(root, 1)
    if not alternatives then return nil, why end
    local parts, terms = {}, 0
    for i = 1, #alternatives do
        terms = terms + #alternatives[i]
        parts[i] = table.concat(alternatives[i], " ")
    end
    if terms > Tree.MAX_TERMS then return nil, "This search has more than 64 filters once its groups are combined." end
    local text = table.concat(parts, " | ")
    if #text > Tree.MAX_LENGTH then return nil, "Use a search of at most 512 characters." end
    local rules = NS and NS.InventoryRules
    if rules and text ~= "" then
        local compiled, reason = rules.Compile(text)
        if not compiled then return nil, reason end
    end
    return text
end

------------------------------------------------------------------ editing
-- Adds child to group; false when the tree would grow past its limits.
function Tree.Add(root, group, child, depth)
    if Tree.Count(root) + Tree.Count(child) > Tree.MAX_NODES then return false end
    if child.kind == "group" and depth + 1 > Tree.MAX_DEPTH then return false end
    group.children[#group.children + 1] = child
    return true
end

function Tree.Remove(group, child)
    for i = #group.children, 1, -1 do
        if group.children[i] == child then
            table.remove(group.children, i)
            return true
        end
    end
    return false
end

-- The flat rows of a tree for the builder: node, depth (root 1), parent.
function Tree.Flatten(root, out)
    for i = #out, 1, -1 do out[i] = nil end
    local function Visit(node, depth, parent)
        out[#out + 1] = { node = node, depth = depth, parent = parent }
        if node.kind == "group" then
            for i = 1, #node.children do Visit(node.children[i], depth + 1, node) end
        end
    end
    Visit(root, 1, nil)
    return out
end
