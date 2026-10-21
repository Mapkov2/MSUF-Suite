local _, NS = ...

-- Identities come from the native UI's cached data, never a moving list index.
local Rows = {}
NS.CollapseCollectionRows = Rows
local Safety = NS.Safety

local function Scalar(value)
    return type(value) == "string" or type(value) == "number"
end

function Rows.Quest(_, row)
    local sortKey = Safety.Field(row, "sortKey")
    if Scalar(sortKey) then
        local collapsed = Safety.Read(row, "IsCollapsed")
        if type(collapsed) ~= "boolean" then collapsed = Safety.Field(row, "isCollapsed") end
        if type(collapsed) ~= "boolean" then
            local button = Safety.Read(row, "GetCollapseButton") or Safety.Field(row, "CollapseButton")
            collapsed = Safety.Field(button, "collapsed")
        end
        if type(collapsed) ~= "boolean" then return end
        return "header:" .. sortKey, collapsed
    end
    local info = Safety.Field(row, "info")
    local questID = Safety.Field(info, "questID") or Safety.Field(row, "questID")
    if type(questID) ~= "number" then return end
    local key = "quest:" .. questID
    if info then
        local header = Safety.Field(info, "header")
        local parent = Safety.Field(header, "headerSortKey")
        return key, nil, Scalar(parent) and "header:" .. parent or nil
    end
    local text = Safety.Read(Safety.Field(row, "Text"), "GetText")
    if type(text) == "string" then return key .. "/objective:" .. text, nil, key end
end

function Rows.Channel(state, row)
    local category = Safety.Read(row, "GetCategory")
    if not Scalar(category) then return end
    local parent = "header:" .. (type(category) == "number" and "club:" or "category:") .. category
    if Safety.Read(row, "IsHeader") == true then
        local collapsed = Safety.Call(state.root, "IsCollapsed", category)
        if Safety.Public(collapsed) then return parent, collapsed == true end
        return
    end
    local club, stream = Safety.Field(row, "clubId"), Safety.Field(row, "streamId")
    if Scalar(club) and Scalar(stream) then return "stream:" .. club .. "/" .. stream, nil, parent end
    local id = Safety.Read(row, "GetChannelID")
    if Scalar(id) then return parent .. "/channel:" .. id, nil, parent end
end

function Rows.Encounter(_, row)
    local section = Safety.Field(row, "myID") or Safety.Field(row, "sectionID")
    if type(section) == "number" then
        local expanded = Safety.Field(row, "expanded")
        if type(expanded) ~= "boolean" then return end
        local parent = Safety.Field(row, "parentID")
        return "header:" .. section, not expanded, type(parent) == "number" and "header:" .. parent or nil
    end
    local header = Safety.Read(row, "GetParent")
    section = Safety.Field(header, "myID") or Safety.Field(header, "sectionID")
    if type(section) == "number" then return "body:" .. section, nil, "header:" .. section end
end
