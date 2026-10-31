local _, P = ...
local S, Plan = P.Suite, P.PlanningTools
local Notes = {}
Plan.Notes = Notes

function Notes.Save(key, label, text, instanceID, encounterID)
    if not Plan.CanEdit() then return false end
    text, label = Plan.Text(text, 4000), Plan.Name(label)
    local entries = Plan.Bucket("notes")
    if not text or not label or not entries or not S.Finite(instanceID) then return false end
    if not entries[key] and Plan.Count(entries) >= Plan.LIMIT.notes then return false end
    entries[key] = { label = label, text = text, instanceID = instanceID, encounterID = encounterID, updated = Plan.Now() }
    Plan.Changed()
    return true
end

function Notes.Toggle(key, lineIndex)
    if not Plan.CanEdit() then return false end
    local entries = Plan.Bucket("notes")
    local entry = entries and entries[key]
    if not entry then return false end
    local lines = {}
    for line in (entry.text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    local line = lines[lineIndex]
    if not line then return false end
    if line:match("^%[ %]") then
        lines[lineIndex] = line:gsub("^%[ %]", "[x]", 1)
    elseif line:match("^%[[xX]%]") then
        lines[lineIndex] = line:gsub("^%[[xX]%]", "[ ]", 1)
    else
        return false
    end
    entry.text, entry.updated = table.concat(lines, "\n"), Plan.Now()
    Plan.Changed()
    return true
end

function Notes.Rows(contextOnly)
    local rows, instance = {}, Plan.Instance()
    for key, entry in pairs(Plan.Bucket("notes") or {}) do
        if type(entry) == "table" and Plan.Text(entry.label, 80) and Plan.Text(entry.text, 4000)
            and (not contextOnly or instance and instance.id == entry.instanceID) then
            rows[#rows + 1] = { key = key, label = entry.label, note = entry, detail = entry.text,
                search = entry.label .. " " .. entry.text }
        end
    end
    table.sort(rows, Plan.SortNames)
    return rows
end

function Notes.Entry()
    if not Plan.CanEdit() or not Plan.owner.config.entryNotes then return end
    local instance = Plan.Instance()
    local key = instance and instance.key
    if key ~= Notes.last then
        Notes.last = key
        if key and #Notes.Rows(true) > 0 then
            Plan.Notify("notes." .. key, S.Text("Personal instance notes"),
                S.Text("Notes are ready for %s. Open Adventure planner to read them."):format(instance.name))
        end
    end
end
