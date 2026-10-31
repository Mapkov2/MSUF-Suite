local _, P = ...
local NS = P.NS
-- The smart searches a profile keeps for the Filters menus (SmartSearch.lua):
-- state.searches, a list of search texts, at most Saved.MAX. It lives in the
-- module state (Suite.lua S.ModuleState), not in the settings.
local Saved = { MAX = 12 }
P.SavedSearches = Saved
local MAX_LENGTH = 512

local function Usable(text)
    return type(text) == "string" and text ~= "" and #text <= MAX_LENGTH
end

-- The profile's list; a hand-edited or damaged one is cleaned first.
function Saved.List(state)
    local list = type(state.searches) == "table" and state.searches or {}
    local clean, seen = {}, {}
    for i = 1, #list do
        local text = list[i]
        if Usable(text) and not seen[text] and #clean < Saved.MAX then
            clean[#clean + 1], seen[text] = text, true
        end
    end
    if #clean ~= #list or state.searches ~= list then
        state.searches = clean
        return clean
    end
    return list
end

local function Trim(text)
    return type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
end

-- Whether text can be saved now: a valid search that is not saved yet and
-- fits the list. The second result names why not.
function Saved.CanAdd(list, text)
    text = Trim(text)
    if not Usable(text) or not NS.InventoryRules.Compile(text) then return false, "invalid" end
    for i = 1, #list do
        if list[i] == text then return false, "saved" end
    end
    if #list >= Saved.MAX then return false, "full" end
    return true
end

function Saved.Add(list, text)
    local ok, why = Saved.CanAdd(list, text)
    if ok then list[#list + 1] = Trim(text) end
    return ok, why
end

function Saved.Remove(list, index)
    if list[index] then table.remove(list, index) end
end
