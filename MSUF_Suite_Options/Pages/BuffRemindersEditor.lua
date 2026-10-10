local _, P = ...
local Editor, ID, PAGE = {}, "buffReminders", "suite_buffReminders"
P.ReminderEditor = Editor
local Tr, Public = P.Tr, P.Suite.Public

local function Positive(value)
    local id = tonumber(value)
    if id and id == math.floor(id) and id > 0 and id < 2147483647 then return id end
end

function Editor.Entries(config)
    local entries = {}
    for token in (config.spellIDs or ""):gmatch("%d+") do
        entries[#entries + 1] = { kind = "spell", id = tonumber(token), token = tostring(tonumber(token)), key = "spellIDs" }
    end
    for item, aura in (config.items or ""):gmatch("(%d+)%s*:%s*(%d+)") do
        entries[#entries + 1] = { kind = "item", id = tonumber(item), aura = tonumber(aura),
            token = tonumber(item) .. ":" .. tonumber(aura), key = "items" }
    end
    return entries
end

function Editor.Spell(value)
    if type(value) ~= "string" then return nil end
    local id = Positive(value) or Positive(value:match("spell:(%d+)"))
    if id then return id end
    local info = C_Spell.GetSpellInfo(value)
    if Public(info) and type(info) == "table" and Public(info.spellID) then return Positive(info.spellID) end
end

function Editor.Add(kind, spell, item)
    if P.Combat() then return false end
    if kind ~= "spell" and kind ~= "item" then return false, "Enter a valid spell and item." end
    local aura = Editor.Spell(spell)
    local itemID = kind == "item" and type(item) == "string" and (Positive(item) or Positive(item:match("item:(%d+)")))
    if not aura or kind == "item" and not itemID then return false, "Enter a valid spell and item." end
    local key = kind == "item" and "items" or "spellIDs"
    local token = itemID and (itemID .. ":" .. aura) or tostring(aura)
    local config = P.S.Config(ID)
    local entries = Editor.Entries(config)
    for _, entry in ipairs(entries) do
        if entry.key == key and entry.token == token then return false, "This reminder is already listed." end
    end
    if #entries >= 12 then return false, "Up to 12 total reminders are shown." end
    local current = config[key] or ""
    local value = current == "" and token or current .. "," .. token
    if #value > P.catalog[ID].rules[key].maxLength then return false, "Up to 12 total reminders are shown." end
    return P.Set(ID, key, value)
end

function Editor.Remove(entry)
    if P.Combat() then return false end
    local values = {}
    for _, candidate in ipairs(Editor.Entries(P.S.Config(ID))) do
        if candidate.key == entry.key and candidate.token ~= entry.token then values[#values + 1] = candidate.token end
    end
    return P.Set(ID, entry.key, table.concat(values, ","))
end

function Editor.Identity(entry)
    local name, texture
    if entry.kind == "spell" then
        name = C_Spell.GetSpellName(entry.id)
        texture = C_Spell.GetSpellTexture(entry.id)
    else
        name = C_Item.GetItemNameByID(entry.id)
        texture = C_Item.GetItemIconByID(entry.id)
        if Public(name) and name == nil then C_Item.RequestLoadItemDataByID(entry.id) end
    end
    if not Public(name) or type(name) ~= "string" or name == "" then name = tostring(entry.id) end
    if not Public(texture) or type(texture) ~= "number" then texture = 134400 end
    return name, texture
end

local function WatchItemData(body)
    local events = CreateFrame("Frame", nil, body)
    events:SetScript("OnShow", function(self) self:RegisterEvent("ITEM_DATA_LOAD_RESULT") end)
    events:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
    events:SetScript("OnEvent", function(_, _, itemID, success)
        if not Public(itemID) or not Public(success) or success ~= true then return end
        for _, entry in ipairs(Editor.Entries(P.S.Config(ID))) do
            if entry.kind == "item" and entry.id == itemID then
                P.Refresh()
                return
            end
        end
    end)
    if events:IsVisible() then events:RegisterEvent("ITEM_DATA_LOAD_RESULT") end
end

local function Input(ctx, body, label, y, width, state, key, section)
    local meta = P.Meta(PAGE, ID, "composer." .. key, "ephemeral", PAGE .. "_composer")
    local input = P.M.BindTextInputAt(ctx, body, Tr(label), 16, y, width,
        function() return state[key] end, function(value) state[key] = value or "" end, true, meta)
    input:SetMaxBytes(128)
    P.HM.SetSearchTargetPrepare(input, function()
        if key == "item" then state.kind = "item" end
        P.Refresh()
        return true
    end)
    P.MenuWorkspace.Prepare(section or body, { { widget = input, meta = meta,
        rule = { key = "composer." .. key, label = label } } })
    return input
end

local function List(ctx, body, y, width)
    local rows = {}
    for i = 1, 12 do
        local row = CreateFrame("Frame", nil, body)
        row:SetPoint("TOPLEFT", 16, y - (i - 1) * 30)
        row:SetSize(width, 28)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("LEFT")
        row.icon:SetSize(24, 24)
        row.label = P.Text(row, "", 32, -5, width - 128, P.T.colors.text)
        row.label:SetMaxLines(1)
        row.remove = P.Button(ctx, row, "Remove", width - 88, 0, 88, function()
            if row.entry then Editor.Remove(row.entry) end
        end)
        rows[i] = row
    end
    return rows
end

function Editor.Build(ctx, builder)
    local state = { kind = "spell", spell = "", item = "" }
    return P.LazySection(builder, PAGE .. "_composer", Tr("Personal spell reminders"), true, {
        content = function(body)
            local width = math.max(240, (P.HM.GetSectionWidth(body) or builder.width) - 32)
            P.M.BindDropdownAt(ctx, body, Tr("Reminder"), 16, -12, {
                { value = "spell", text = Tr("Personal spell reminders") },
                { value = "item", text = Tr("Consumable and weapon reminders") },
            }, width, function() return state.kind end, function(value) state.kind = value
                P.Refresh() end,
                P.Meta(PAGE, ID, "composer.kind", "ephemeral", PAGE .. "_composer"))
            Input(ctx, body, "Spell name or ID", -72, width, state, "spell")
            local item = CreateFrame("Frame", nil, body)
            item:SetPoint("TOPLEFT", 0, -130)
            item:SetSize(width + 32, 58)
            Input(ctx, item, "Item ID", 0, width, state, "item", body)
            local status = P.Text(body, "", 16, -226, width)
            P.Button(ctx, body, "Add reminder", 16, -192, width, function()
                local ok, reason = Editor.Add(state.kind, state.spell, state.item)
                P.SetTranslatedText(status, Tr(ok and "Added" or reason or "Unavailable"))
            end, function() return not P.Combat() end,
                P.Meta(PAGE, ID, "action.addReminder", "action", PAGE .. "_composer"))
            local rows = List(ctx, body, -260, width)
            WatchItemData(body)
            P.M.TrackRefresh(ctx, function()
                item:SetShown(state.kind == "item")
                local entries = Editor.Entries(P.S.Config(ID))
                for i, row in ipairs(rows) do
                    row.entry = entries[i] or false
                    row:SetShown(row.entry ~= false)
                    if row.entry then
                        local name, texture = Editor.Identity(row.entry)
                        if row.entry.aura then
                            local auraName = Editor.Identity({ kind = "spell", id = row.entry.aura })
                            name = Tr("%s - %s"):format(name, auraName)
                        end
                        row.icon:SetTexture(texture)
                        P.SetTranslatedText(row.label, name)
                        row.remove:SetEnabled(not P.Combat())
                    end
                end
                P.FinishBody(builder, body, -260 - math.min(12, #entries) * 30)
            end)
            return -260 - math.min(12, #Editor.Entries(P.S.Config(ID))) * 30
        end,
        finish = function(body, y) P.FinishBody(builder, body, y) end,
    })
end
