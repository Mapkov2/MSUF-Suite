local _, NS = ...
-- Profile data and cold configuration only. Live aura state stays in the
-- native CustomAuraContainer (upstream/live and upstream/forever).
local A = { LIMIT = 8, DEFAULT_COLOR = "659ad2" }
NS.NameplateAuraColors = A
local Public, floor = NS.Public, math.floor

function A.ID(value)
    if not Public(value) or type(value) ~= "number" or value < 1 or value >= 2147483648
        or value ~= floor(value) then return nil end
    return value
end

function A.Hex(value)
    return type(value) == "string" and #value == 6 and not value:find("[^%x]") and value:lower() or A.DEFAULT_COLOR
end

function A.Spec()
    local index = C_SpecializationInfo.GetSpecialization()
    if not A.ID(index) then return nil end
    local id, name = C_SpecializationInfo.GetSpecializationInfo(index)
    return A.ID(id), Public(name) and name or nil
end

function A.Decode(text)
    local out = {}
    if type(text) ~= "string" or #text > 60000 or text:sub(1, 2) ~= "1|" then return out end
    local count = 0
    for part in text:sub(3):gmatch("[^|]+") do
        count = count + 1
        if count > 40 then break end
        local key, body = part:match("^(%d+)=(.*)$")
        local spec = A.ID(tonumber(key))
        if spec then
            local rows, seen = {}, {}
            for record in body:gmatch("[^;]+") do
                local id, enabled, color, cooldown, aliases, source =
                    record:match("^(%d+),([01]),(%x%x%x%x%x%x),(%d+),([%d%.]*),?([CM]?)$")
                id = A.ID(tonumber(id))
                if id and not seen[id] and #rows < A.LIMIT then
                    local row = { id = id, enabled = enabled == "1", color = A.Hex(color),
                        cooldown = A.ID(tonumber(cooldown)), ids = { id }, curated = source == "C" }
                    for alias in aliases:gmatch("%d+") do
                        alias = A.ID(tonumber(alias))
                        if alias and alias ~= id and #row.ids < A.LIMIT then row.ids[#row.ids + 1] = alias end
                    end
                    rows[#rows + 1], seen[id] = row, true
                end
            end
            out[spec] = rows
        end
    end
    return out
end

function A.Encode(data)
    local keys, parts = {}, { "1" }
    for spec in pairs(data) do if A.ID(spec) then keys[#keys + 1] = spec end end
    table.sort(keys)
    for i = 1, math.min(#keys, 40) do
        local rows, records = data[keys[i]], {}
        for j = 1, math.min(#rows, A.LIMIT) do
            local row, aliases = rows[j], {}
            for k = 1, math.min(#(row.ids or {}), A.LIMIT) do
                if A.ID(row.ids[k]) then aliases[#aliases + 1] = tostring(row.ids[k]) end
            end
            if A.ID(row.id) then
                records[#records + 1] = table.concat({ row.id, row.enabled == false and "0" or "1",
                    A.Hex(row.color), A.ID(row.cooldown) or 0, table.concat(aliases, "."), row.curated and "C" or "M" }, ",")
            end
        end
        parts[#parts + 1] = tostring(keys[i]) .. "=" .. table.concat(records, ";")
    end
    return table.concat(parts, "|")
end

function A.Paused(row)
    if not row.cooldown then return false end
    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(row.cooldown)
    if not Public(info) or type(info) ~= "table" or not Public(info.isKnown) or info.isKnown ~= false then return false end
    -- cooldown IDs are catalog handles, not stable spell identities. A
    -- changed client/catalog must not pause a different saved aura.
    if A.ID(info.spellID) == row.id or A.ID(info.overrideSpellID) == row.id then return true end
    if Public(info.linkedSpellIDs) and type(info.linkedSpellIDs) == "table" then
        for _, id in ipairs(info.linkedSpellIDs) do if A.ID(id) == row.id then return true end end
    end
    return false
end

function A.Selected(rows)
    local out = {}
    for _, row in ipairs(rows or {}) do
        if row.enabled ~= false and not A.Paused(row) then out[#out + 1] = row end
    end
    return out
end

local function Suggestion(info, cooldown)
    if not Public(info) or type(info) ~= "table" or not Public(info.hasAura) or info.hasAura ~= true
        or not Public(info.selfAura) or info.selfAura ~= false then return end
    local id = A.ID(info.spellID)
    if not id then return end
    local row, seen = { id = id, cooldown = cooldown, color = A.DEFAULT_COLOR, ids = { id } }, { [id] = true }
    local function Add(alias)
        alias = A.ID(alias)
        if alias and not seen[alias] and #row.ids < A.LIMIT then
            row.ids[#row.ids + 1], seen[alias] = alias, true
        end
    end
    Add(info.overrideSpellID)
    if Public(info.linkedSpellIDs) and type(info.linkedSpellIDs) == "table" then
        for _, alias in ipairs(info.linkedSpellIDs) do Add(alias) end
    end
    return row
end

local function NativeSuggestions()
    local out, seen = {}, {}
    for category = 0, 3 do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(category, true)
        if Public(ids) and type(ids) == "table" then
            for _, cooldown in ipairs(ids) do
                if A.ID(cooldown) and not seen[cooldown] then
                    seen[cooldown] = true
                    local row = Suggestion(C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldown), cooldown)
                    if row then out[#out + 1] = row end
                end
            end
        end
    end
    return out
end

function A.Suggestions()
    local _, class = UnitClass("player")
    local curated = Public(class) and NS.HostBridge.TargetDotCatalog(class) or {}
    local native = NativeSuggestions()
    if #curated == 0 then return native end
    for _, row in ipairs(curated) do
        row.ids, row.color = { row.id }, A.DEFAULT_COLOR
        for _, entry in ipairs(native) do
            for _, id in ipairs(entry.ids) do
                if id == row.id then row.cooldown = entry.cooldown end
            end
        end
    end
    return curated
end

function A.Preview(rows, present, config)
    if not config.auraColorsEnabled or #rows == 0 then return nil end
    local count, first = 0, nil
    for _, row in ipairs(rows) do
        if present[row.id] then count, first = count + 1, first or row end
    end
    -- Every selected DoT active takes the all color, a lone DoT too: its own
    -- color marks it only beside other DoTs that are still missing.
    if count == #rows then return config.auraColorsAll end
    if count == 0 then return config.auraColorsNoneEnabled and config.auraColorsNone or nil end
    return config.auraColorsIndividual and first and first.color or nil
end
