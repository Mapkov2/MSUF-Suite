local _, NS = ...
local Macros = NS.Macros
local Model = Macros.Model
-- Blizzard_ActionBar/Shared/ActionButtonUtil.lua: normal pages on both supported clients.
local MAX_ACTION_PAGE = 6
local UNITS = { target = true, focus = true, player = true, pet = true, mouseover = true,
    targettarget = true, focustarget = true, pettarget = true, cursor = true }
local MODIFIERS = { shift = true, ctrl = true, alt = true, any = true, none = true }

local function Trim(text)
    return text:match("^%s*(.-)%s*$")
end

local function SafeValue(value, allowComma)
    if not Model.Count(value) or value:find("[\r\n;%[%]{}]") then return false end
    if not allowComma and value:find(",", 1, true) then return false end
    return not value:find("[\001-\031\127]")
end

local function Unit(value)
    if UNITS[value] then return true end
    local prefix, number, suffix = value:match("^(%a+)(%d+)(%a*)$")
    local limit = prefix == "party" and 4 or prefix == "raid" and 40 or prefix == "boss" and 5 or prefix == "arena" and 3
    number = tonumber(number)
    return limit and number and tostring(number) == value:match("%d+") and number >= 1 and number <= limit
        and (suffix == "" or suffix == "target")
end

local function Numbers(value)
    if value == "" or value:find("[^%d/]") or value:find("//", 1, true) or value:sub(-1) == "/" then return false end
    for number in value:gmatch("[^/]+") do if tonumber(number) > 999 then return false end end
    return true
end

local function Condition(condition)
    local key, value, negate = condition.key, Trim(condition.value), condition.negate
    local spec = Model.ConditionByKey[key]
    if not SafeValue(value, false) then return nil end
    if spec.kind == "unit" then return not negate and Unit(value) and "@" .. value or nil end
    if spec.kind == "modifier" then
        if not MODIFIERS[value] then return nil end
        if value == "any" or value == "none" then
            local positive = value == "any"
            return positive ~= negate and "mod" or "nomod"
        end
        return (negate and "nomod:" or "mod:") .. value
    end
    if spec.kind == "boolean" and value ~= "" then return nil end
    if spec.kind == "numbers" and not Numbers(value) then return nil end
    if spec.kind == "spellID" and (not value:match("^%d+$") or tonumber(value) < 1) then return nil end
    if spec.kind == "required" and value == "" then return nil end
    if spec.kind == "group" and value ~= "" and value ~= "party" and value ~= "raid" then return nil end
    return (negate and "no" or "") .. key .. (value ~= "" and ":" .. value or "")
end

local function Conditions(branch, unitOnly)
    local parts, seen = {}, {}
    for _, condition in ipairs(branch.conditions) do
        local token = Condition(condition)
        if not token then return nil, "Invalid macro condition" end
        if unitOnly and token == "@cursor" then return nil, "Invalid macro condition" end
        if condition.key == "unit" and seen.unit then return nil, "Choose one target per rule" end
        if seen[token] then return nil, "Duplicate macro condition" end
        local opposite = token:sub(1, 2) == "no" and token:sub(3) or "no" .. token
        if seen[opposite] then return nil, "Conflicting macro conditions" end
        seen[token], seen[condition.key == "unit" and "unit" or token] = true, true
        parts[#parts + 1] = token
    end
    if seen.help and seen.harm or seen.indoors and seen.outdoors then return nil, "Conflicting macro conditions" end
    if #parts == 0 then return "" end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function Reset(reset)
    local parts = {}
    if reset.target then parts[#parts + 1] = "target" end
    if reset.combat then parts[#parts + 1] = "combat" end
    if reset.seconds and reset.seconds > 0 then
        if reset.seconds % 1 ~= 0 then return nil end
        parts[#parts + 1] = tostring(reset.seconds)
    end
    if reset.mod ~= "" and reset.mod ~= nil then
        if reset.mod ~= "shift" and reset.mod ~= "ctrl" and reset.mod ~= "alt" then return nil end
        parts[#parts + 1] = reset.mod
    end
    return #parts > 0 and "reset=" .. table.concat(parts, "/") .. " " or ""
end

local function Sequence(step)
    if #step.sequence == 0 then return nil, "Add a sequence step" end
    if step.branches[1] and step.branches[1].useFirst then return nil, "Invalid macro action" end
    local values = {}
    for i, value in ipairs(step.sequence) do
        value = Trim(value)
        if value == "" then return nil, "Choose a spell or item" end
        if not SafeValue(value, false) then return nil, "Invalid spell or item" end
        values[i] = value
    end
    if #step.branches > 1 then return nil, "A sequence uses one condition rule" end
    local conditions, errorKey = Conditions(step.branches[1] or Model.NewBranch())
    if not conditions then return nil, errorKey end
    local reset = ""
    if step.command == "castsequence" then reset = Reset(step.reset) end
    if not reset then return nil, "Invalid sequence reset" end
    return "/" .. step.command .. " " .. conditions .. (conditions ~= "" and " " or "") .. reset .. table.concat(values, ",")
end

local function ActionValue(command, value)
    if command == "tm" then
        local prefix, number = value:match("^([!~]?)(%d)$")
        return number and tonumber(number) <= 8 and (prefix == "" or number ~= "0")
    end
    if command == "wm" or command == "cwm" then
        if command == "cwm" and (value == "" or value == "all") then return true end
        return value:match("^[1-8]$") ~= nil
    end
    if command == "changeactionbar" then
        return value:match("^%d+$") and tonumber(value) >= 1 and tonumber(value) <= MAX_ACTION_PAGE
    end
    if command == "swapactionbar" then
        local first, second = value:match("^(%d+)%s+(%d+)$")
        return first and tonumber(first) >= 1 and tonumber(first) <= MAX_ACTION_PAGE
            and tonumber(second) >= 1 and tonumber(second) <= MAX_ACTION_PAGE
    end
    return true
end

local function Branches(step, spec)
    if #step.branches == 0 then return nil, "Add a macro rule" end
    if spec.conditional == false and #step.branches ~= 1 then return nil, "This command uses one rule" end
    local clauses, lastValue, lastConditional = {}, nil, false
    for i, branch in ipairs(step.branches) do
        if i == 1 and branch.useFirst then return nil, "Invalid macro action" end
        local condition, errorKey = Conditions(branch, step.command == "tm")
        if not condition then return nil, errorKey end
        if condition ~= "" and spec.conditional == false then return nil, "This command does not support conditions" end
        local value = Trim(branch.useFirst and step.branches[1].value or branch.value)
        local safe = spec.argument == "text" and not value:find("[\r\n\001-\031\127]") or SafeValue(value, false)
        if not safe then return nil, "Invalid macro action value" end
        if value == "" and (spec.argument == "required" or spec.argument == "text") then return nil, "Choose a spell, item or value" end
        if value ~= "" and spec.argument == "none" then return nil, "This command needs no value" end
        if not ActionValue(step.command, value) then return nil, "Invalid macro action value" end
        if condition == "" and i < #step.branches then return nil, "Place the fallback rule last" end
        if lastConditional and condition ~= "" and lastValue == value and value ~= "" then
            clauses[#clauses] = clauses[#clauses]:sub(1, -(#value + 2)) .. condition .. " " .. value
        else
            clauses[#clauses + 1] = condition .. (condition ~= "" and value ~= "" and " " or "") .. value
        end
        lastValue, lastConditional = value, condition ~= ""
    end
    return "/" .. step.command .. (#clauses > 0 and clauses[1] ~= "" and " " or "") .. table.concat(clauses, ";")
end

local function ClearWorldMarkers(step, line)
    local hasAll = false
    for _, branch in ipairs(step.branches) do
        local value = branch.useFirst and step.branches[1].value or branch.value
        if Trim(value) == "all" then hasAll = true end
    end
    if not hasAll then return line end
    local lines, spec = {}, { argument = "optional" }
    for index = 1, 8 do
        local marker = tostring(index)
        local expanded = { command = "cwm", branches = {} }
        for i, branch in ipairs(step.branches) do
            local value = Trim(branch.useFirst and step.branches[1].value or branch.value)
            expanded.branches[i] = { conditions = branch.conditions, value = (value == "all" or value == marker) and marker or "" }
        end
        lines[index] = Branches(expanded, spec)
    end
    return table.concat(lines, "\n")
end

local function Step(step)
    local spec = Model.CommandByKey[step.command]
    if spec.argument == "raw" then
        if Trim(step.raw) == "" then return nil, "Enter a custom command" end
        return step.raw:gsub("\r\n", "\n"):gsub("\r", "\n")
    end
    if spec.argument == "sequence" then return Sequence(step) end
    local line, errorKey = Branches(step, spec)
    if not line then return nil, errorKey end
    if step.command == "cwm" then return ClearWorldMarkers(step, line) end
    return line
end

local function RaidMarker(step)
    if step.raidMarker == nil then return "" end
    if not Model.CommandByKey[step.command].supportsRaidMarker then return nil, "Invalid macro action" end
    -- Blizzard /tm supports ! to keep the chosen mark on repeated keypresses.
    local value = step.raidMarker == 0 and "0" or "!" .. tostring(step.raidMarker)
    local marker = { command = "tm", branches = {} }
    for i, branch in ipairs(step.branches) do
        if Model.CommandByKey[step.command].argument == "optional" then
            local action = branch.useFirst and step.branches[1].value or branch.value
            if Trim(action) ~= "" then return nil, "Invalid macro action value" end
        end
        marker.branches[i] = { conditions = branch.conditions, value = value }
    end
    if #marker.branches == 0 then marker.branches[1] = { conditions = {}, value = value } end
    return Branches(marker, Model.CommandByKey.tm)
end

local function Rules(document)
    if #document.steps == 0 then return nil, "Add a macro action" end
    local lines, warnings, casts = {}, {}, 0
    if document.showTooltip then lines[1] = "#showtooltip" end
    for _, step in ipairs(document.steps) do
        local line, errorKey = Step(step)
        if not line then return nil, errorKey end
        local marker, markerError = RaidMarker(step)
        if not marker then return nil, markerError end
        -- Mark first: an instant action can change form, stealth or another condition.
        if marker ~= "" then lines[#lines + 1] = marker end
        lines[#lines + 1] = line
        if step.command == "cast" or step.command == "use" or step.command == "castsequence" then casts = casts + 1 end
        if Model.CommandByKey[step.command].category == "Chat" then warnings.chat = true end
        if step.command == "raw" then warnings.raw = true end
    end
    if casts > 1 then warnings.multipleActions = true end
    return table.concat(lines, "\n"), nil, warnings
end

function Macros.Compile(source, consumableResolver)
    local document, errorKey = Model.Normalize(source)
    if not document then return nil, errorKey end
    local body, warnings
    if document.mode == "raw" then
        body, warnings = document.raw, { raw = true }
    elseif document.mode == "consumable" then
        if not consumableResolver then return nil, "Consumable data is not ready" end
        body, errorKey = consumableResolver(document)
    else
        body, errorKey, warnings = Rules(document)
    end
    if not body then return nil, errorKey end
    if NS.IsSecret(body) or type(body) ~= "string" then return nil, "Invalid macro text" end
    body = body:gsub("\r\n", "\n"):gsub("\r", "\n")
    local length = Model.Count(body)
    if not length then return nil, "Invalid macro text" end
    if Trim(body) == "" then return nil, "Enter a macro action" end
    if length > Model.MAX_LENGTH then return nil, "The macro exceeds the 255-character limit", warnings or {}, body end
    return body, nil, warnings or {}
end
