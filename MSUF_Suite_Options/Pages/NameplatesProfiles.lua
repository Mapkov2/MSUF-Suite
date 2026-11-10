local _, P = ...
local Suite, Tr, M = P.Suite, P.Tr, P.M
local PAGE, ID, SECTION = "suite_nameplates", "nameplates", "suite_nameplates_profiles"
local UI = {}
P.NameplatesProfiles = UI

local function Meta(key)
    return P.Meta(PAGE, ID, "profiles." .. key, "ephemeral", SECTION)
end

local function Feedback(reason, ok)
    M.ShowStatusFeedback(Tr(reason), ok and "success" or "danger", 4)
end

local function Options(ui)
    return { nameplateSections = ui.selected }
end

local function Values()
    local values = {}
    for _, entry in ipairs(Suite.NameplateProfiles.List()) do
        values[#values + 1] = { value = entry.key, text = entry.builtin and Tr(entry.label) or entry.label }
    end
    return values
end

local function SetText(ui, text)
    ui.text, ui.prepared = text or "", nil
    ui.input:SetText(ui.text)
end

local function Status(ui, text)
    ui.status:SetText(text)
    ui.status:SetHeight(math.max(30, ui.status:GetStringHeight() or 30))
    P.FinishBody(ui.builder, ui.body, ui.statusY - ui.status:GetHeight() - 14)
end

local function Scalar(value)
    if type(value) == "boolean" then return Tr(value and "On" or "Off") end
    if type(value) == "table" then return Tr("Custom rules") end
    return tostring(value or ""):gsub("%c", function(character) return string.format("\\x%02X", character:byte()) end)
end

local function AppendChanges(lines, changes)
    local rules = P.catalog[ID].rules
    for index = 1, math.min(8, #changes) do
        local entry = changes[index]
        local rule = rules[entry.key]
        lines[#lines + 1] = Tr("%s · %s → %s"):format(Tr(rule and rule.label or entry.key),
            Scalar(entry.before), Scalar(entry.value))
    end
end

local function Preview(ui)
    local prepared, reason = Suite.NameplateProfiles.Inspect(ui.input:GetText(), Options(ui))
    ui.prepared = prepared
    if not prepared then Status(ui, Tr(reason)) return end
    local count = #prepared.changes + #prepared.nativeChanges + #prepared.sharedChanges
    local lines = { Tr("%d nameplate settings will change."):format(count) }
    AppendChanges(lines, prepared.changes)
    AppendChanges(lines, prepared.nativeChanges)
    AppendChanges(lines, prepared.sharedChanges)
    if prepared.native then
        lines[#lines + 1] = Tr("The selected Blizzard nameplate settings also apply to Blizzard's interface.")
    elseif prepared.legacy then
        lines[#lines + 1] = Tr("This selection contains no Blizzard nameplate snapshot.")
    end
    if prepared.shared then lines[#lines + 1] = Tr("Nameplate typography and interrupt settings are included.") end
    Status(ui, table.concat(lines, "\n"))
end

local function Apply(ui)
    local ok, reason, report = Suite.NameplateProfiles.Apply(ui.input:GetText(), Options(ui))
    if not ok then Feedback(reason or "Profile import failed", false) return end
    ui.prepared = nil
    P.Refresh()
    local lines = { Tr("Nameplate setup applied.") }
    local skipped = {}
    for key, why in pairs(report and report.skipped or {}) do
        skipped[#skipped + 1] = key .. " · " .. Tr(why)
    end
    table.sort(skipped)
    for _, line in ipairs(skipped) do lines[#lines + 1] = line end
    for _, why in pairs(report and report.skippedShared or {}) do lines[#lines + 1] = Tr(why) end
    Status(ui, table.concat(lines, "\n"))
end

local function Export(ui)
    local text, reason = Suite.ProfileIO.ExportModule(ID, Options(ui))
    if not text then Feedback(reason, false) return end
    SetText(ui, text)
    ui.input:SetFocus()
    ui.input:HighlightText()
    Status(ui, Tr("Copy the selected nameplate setup."))
end

local function Save(ui, duplicate)
    local source, reason
    if duplicate then
        source, reason = Suite.NameplateProfiles.Read(ui.template)
        if not source then
            Feedback(reason, false)
            return
        end
    end
    P.AskText("nameplates.save", Tr("Name for this nameplate template"), function(name)
        local ok, key = Suite.NameplateProfiles.Save(name, source)
        if not ok then Feedback(key, false) return end
        ui.template = key
        P.Refresh()
        Feedback("Nameplate template saved.", true)
    end, 64, 128)
end

local function Templates(ui, y)
    local row = Meta("template")
    row.id = "template"
    row.kind, row.label, row.values = "dropdown", Tr("Nameplate template"), Values
    row.get = function() return ui.template end
    row.set = function(value)
        ui.template = value
        SetText(ui, Suite.NameplateProfiles.Read(value))
        Preview(ui)
    end
    local grid = P.W.SettingsRows(ui.ctx, ui.body, { x = 16, y = y, width = ui.width, rows = { row } })
    y = grid.bottomY - 8
    P.Button(ui.ctx, ui.body, "Load template", 16, y, 150, function()
        SetText(ui, Suite.NameplateProfiles.Read(ui.template))
        Preview(ui)
    end, nil, Meta("load"))
    P.Button(ui.ctx, ui.body, "Save current setup", 176, y, 150, function() Save(ui) end, nil, Meta("save"))
    P.Button(ui.ctx, ui.body, "Duplicate template", 336, y, 150, function() Save(ui, true) end, nil, Meta("duplicate"))
    y = y - 36
    local function Saved() return ui.template:sub(1, 6) == "saved:" end
    P.Button(ui.ctx, ui.body, "Update saved template", 16, y, 200, function()
        local ok, reason = Suite.NameplateProfiles.Save(ui.template:sub(7), nil, true)
        Feedback(ok and "Nameplate template saved." or reason, ok)
    end, Saved, Meta("update"))
    P.Button(ui.ctx, ui.body, "Delete saved template", 228, y, 200, function()
        local selected = ui.template
        P.Confirm("nameplates.delete", Tr("Delete the selected nameplate template?"), function()
            local ok, reason = Suite.NameplateProfiles.Delete(selected)
            if ok then
                if ui.template == selected then ui.template = "compact" end
                P.Refresh()
            else Feedback(reason, false) end
        end)
    end, Saved, Meta("delete"))
    return y - 44
end

local function Groups(ui, y)
    local rows = {}
    for _, group in ipairs(Suite.NameplateProfiles.Groups) do
        local key = group.key
        local row = Meta("group." .. key)
        row.id = key
        row.kind, row.label = "toggle", Tr(group.label)
        row.get = function() return ui.selected[key] end
        row.set = function(value)
            ui.selected[key], ui.prepared = value == true, nil
            if ui.input and ui.input:GetText() ~= "" then Preview(ui) end
        end
        rows[#rows + 1] = row
    end
    local grid = P.W.SettingsRows(ui.ctx, ui.body, { x = 16, y = y, width = ui.width, rows = rows, columns = 2 })
    return grid.bottomY - 12
end

local function Transfer(ui, y)
    ui.input = M.BindTextInputAt(ui.ctx, ui.body, Tr("Nameplate import / export"), 16, y, ui.width,
        function() return ui.text end, function(text) ui.text, ui.prepared = text, nil end, false, Meta("text"))
    ui.input:SetMaxLetters(200000)
    ui.input:HookScript("OnTextChanged", function(input, userInput)
        if userInput then ui.text, ui.prepared = input:GetText(), nil end
    end)
    y = y - 54
    P.Button(ui.ctx, ui.body, "Export selection", 16, y, 150, function() Export(ui) end, nil, Meta("export"))
    P.Button(ui.ctx, ui.body, "Preview import", 176, y, 150, function() Preview(ui) end, nil, Meta("preview"))
    P.Button(ui.ctx, ui.body, "Apply selection", 336, y, 150, function() Apply(ui) end, nil, Meta("apply"))
    y = y - 36
    P.Button(ui.ctx, ui.body, "Restore previous setup", 16, y, 200, function()
        local ok, reason = Suite.NameplateProfiles.RestorePrevious()
        Feedback(ok and "Previous nameplate setup restored." or reason, ok)
        if ok then
            P.Refresh()
            Preview(ui)
        end
    end, function() return Suite.NameplateProfiles.CanRestore() end, Meta("restore"))
    return y - 44
end

function UI.Build(ctx, builder)
    return P.LazySection(builder, SECTION, Tr("Templates and sharing"), false, {
        content = function(body)
            local ui = { ctx = ctx, builder = builder, body = body, template = "compact", text = "", selected = {},
                width = math.max(240, (P.HM.GetSectionWidth(body) or builder.width or 720) - 32), statusY = -12 }
            for _, group in ipairs(Suite.NameplateProfiles.Groups) do ui.selected[group.key] = true end
            -- Both feedback and input exist before the selector can invoke its setter.
            ui.status = P.Description(body, "", 16, ui.statusY, ui.width)
            local y = Groups(ui, -12)
            y = Transfer(ui, y)
            y = Templates(ui, y)
            ui.statusY = y
            ui.status:ClearAllPoints()
            ui.status:SetPoint("TOPLEFT", body, "TOPLEFT", 16, y)
            local text = ui.status:GetText()
            if not text or text == "" then text = Tr("Choose a template or paste a nameplate setup to preview its settings.") end
            Status(ui, text)
        end,
    })
end
