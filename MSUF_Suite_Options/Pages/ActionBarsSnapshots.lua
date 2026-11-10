local _, P = ...
local M, Suite, Tr, HM = P.M, P.Suite, P.Tr, P.HM
local PAGE, MODULE, SECTION = "suite_actionbars", "actionbars", "suite_actionbars_account_transfer"
local ROW_COUNT, ROW_HEIGHT = 5, 67
local EMPTY_STATUS = { saved = {}, pending = {}, results = {} }

local Page = {}
P.ActionBarSnapshotsPage = Page

local function Api()
    return Suite.ActionBarSnapshots
end

local function Meta(key)
    return P.Meta(PAGE, MODULE, "transfer." .. key, "ephemeral", SECTION)
end

local function Character(record)
    if not record.realm or record.realm == "" then return record.name end
    return record.name .. "-" .. record.realm
end

local function Setup(record)
    local label = record.setupLabel or record.label or Tr("Action bar setup")
    if record.loadout and record.loadout ~= label then return Tr("%s · Loadout %s"):format(label, record.loadout) end
    return label
end

local function Count(values)
    local count = 0
    for _ in pairs(values) do count = count + 1 end
    return count
end

local function Feedback(text, kind)
    if M.ShowStatusFeedback then M.ShowStatusFeedback(Tr(text), kind, 2.6) end
end

local function List(ui)
    if ui.view == "preview" then return ui.packet and ui.packet.records or EMPTY_STATUS.saved end
    return ui.status[ui.view]
end

local function ReadStatus(ui)
    local api = Api()
    ui.status = api and api.Status() or EMPTY_STATUS
end

local function Refresh(ui)
    ReadStatus(ui)
    local current = ui.status.current
    local label = current and Tr("Current setup for %s · %s"):format(Character(current), Setup(current))
        or Tr("The current action bar setup is unavailable.")
    ui.current:SetText(label)
    P.SetButtonText(ui.automatic, Tr(ui.status.capture and "Disable automatic capture" or "Enable automatic capture"))
    ui.restore:SetEnabled(ui.status.canRestore == true and not P.Combat())
    ui.refreshRows()
end

local function SetView(ui, view)
    ui.view, ui.page = view, 1
    Refresh(ui)
end

local function SetTarget(ui, index, record)
    local packet = ui.packet
    local prompt = Tr("Target for %s · %s. Enter Name-Realm or Name for this realm. Add | Target loadout to use a different loadout name.")
        :format(Character(record), Setup(record))
    P.AskText("actionbar-transfer-target", prompt, function(text)
        if ui.packet ~= packet or P.Combat() then return end
        text = text:match("^%s*(.-)%s*$")
        if text == "" then
            Feedback("Enter a target character name.", "danger")
            return
        end
        ui.assignments[index] = text
        ui.revision = ui.revision + 1
        ui.refreshRows()
    end, 96, 192)
end

local function HandleRow(ui, row)
    local entry = row.entry
    if not entry then return end
    if ui.view == "preview" then
        if ui.assignments[row.index] then
            ui.assignments[row.index] = nil
            ui.revision = ui.revision + 1
            ui.refreshRows()
        else
            SetTarget(ui, row.index, entry)
        end
    elseif ui.view == "pending" and Api() then
        local ok = Api().Cancel(entry.id)
        if not ok then Feedback("The queued transfer could not be removed.", "danger") end
        Refresh(ui)
    end
end

local function Detail(ui, entry, index)
    if ui.view == "preview" then
        local target = ui.assignments[index] or Tr("Skip")
        local slots = Count(entry.slots) + (entry.independentSlots and Count(entry.independentSlots) or 0)
        if entry.scope == "account" then
            return Tr("%s · %d slots · %d shared keys · Target %s"):format(
                Setup(entry), slots, Count(entry.keys), target)
        end
        return Tr("%s · %d slots · %d keys · Target %s"):format(Setup(entry), slots, Count(entry.keys), target)
    elseif ui.view == "saved" then
        return Tr("%s · %d slots · %d keys"):format(Setup(entry), entry.slotCount, entry.keyCount)
    elseif ui.view == "results" then
        if entry.error then return Tr("%s · Transfer could not finish. Review the skipped changes."):format(Setup(entry)) end
        return Tr("%s · %d slots and %d keys applied · %d slots and %d keys skipped"):format(
            Setup(entry), entry.slots, entry.keys, entry.skippedSlots, entry.skippedKeys)
    end
    if entry.waiting == "account" then
        return Setup(entry) .. " · " .. Tr("Waiting for account-wide key bindings")
    elseif entry.waiting == "character" then
        return Setup(entry) .. " · " .. Tr("Waiting for character-specific key bindings")
    end
    return Setup(entry)
end

local function UpdateRow(ui, row, entry, index)
    row.entry, row.index = entry, index
    row.title:SetShown(entry ~= nil)
    row.detail:SetShown(entry ~= nil)
    local action = entry and (ui.view == "preview" or ui.view == "pending")
    row.action:SetShown(action == true)
    if not entry then return end
    row.title:SetText(Character(entry))
    row.detail:SetText(Detail(ui, entry, index))
    if action then
        local label = ui.view == "pending" and "Cancel"
            or (ui.assignments[index] and "Clear target" or "Assign target")
        P.SetButtonText(row.action, Tr(label))
    end
end

local function UpdateRows(ui)
    local list = List(ui)
    local pages = math.max(1, math.ceil(#list / ROW_COUNT))
    ui.page = math.min(ui.page, pages)
    local first = (ui.page - 1) * ROW_COUNT
    for offset, row in ipairs(ui.rows) do
        local index = first + offset
        UpdateRow(ui, row, list[index], index)
    end
    ui.empty:SetShown(#list == 0)
    P.SetTranslatedText(ui.pageLabel, Tr("Page %d of %d"):format(ui.page, pages))
    ui.previous:SetEnabled(ui.page > 1 and not P.Combat())
    ui.next:SetEnabled(ui.page < pages and not P.Combat())
    ui.stage:SetEnabled(ui.packet ~= nil and next(ui.assignments) ~= nil and not P.Combat())
end

local function AddButton(ui, label, x, y, width, run, enabled, key)
    local button = P.Button(ui.ctx, ui.body, Tr(label), x, y, width, run, enabled, Meta(key))
    HM.SkipHistoryCheckpoint(button)
    return button
end

local function BuildTop(ui, y)
    local body, width, half = ui.body, ui.width, ui.half
    local help = P.Text(body,
        Tr("Save spells and keys from the characters you play and transfer those setups to another account.") .. " "
            .. Tr("The import skips unsupported actions and conflicting keys."),
        16, y, width)
    y = y - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 12
    ui.current = P.Text(body, "", 16, y, width)
    ui.current:SetWordWrap(false)
    y = y - 27
    AddButton(ui, "Save current setup", 16, y, half, function()
        if not Api().Capture() then Feedback("The current setup could not be saved.", "danger") end
        Refresh(ui)
    end, function() return Api() ~= nil end, "capture")
    ui.automatic = AddButton(ui, "Enable automatic capture", 28 + half, y, half, function()
        if not Api().SetCapture(not ui.status.capture) then Feedback("Automatic capture could not be changed.", "danger") end
        Refresh(ui)
    end, function() return Api() ~= nil end, "automatic")
    return y - 40
end

local function BuildPackage(ui, y)
    local function Preview(ui)
        local api = Api()
        local packet = api and api.Decode(ui.input:GetText())
        if not packet then
            ui.packet, ui.assignments = nil, {}
            ui.refreshRows()
            Feedback("This action bar package could not be read.", "danger")
            return
        end
        ui.packet, ui.assignments = packet, {}
        SetView(ui, "preview")
    end

    local function Export(ui)
        local api = Api()
        local value = api and api.Export()
        if not value then
            Feedback("No action bar package could be exported.", "danger")
            return
        end
        ui.text = value
        ui.input:SetText(value)
        ui.input:SetFocus()
        ui.input:HighlightText()
        Refresh(ui)
        Feedback("Copy the selected action bar package.", "info")
    end

    local width, half = ui.width, ui.half
    ui.input = M.BindTextInputAt(ui.ctx, ui.body, Tr("Action bar package"), 16, y, width,
        function() return ui.text end, function(text) ui.text = text end, false, Meta("package"))
    ui.input:SetMaxLetters(200000)
    ui.input:HookScript("OnTextChanged", function(input, userInput)
        if userInput then ui.text = input:GetText() end
    end)
    ui.input:HookScript("OnEditFocusLost", function(input) ui.text = input:GetText() end)
    y = y - 54
    local export = AddButton(ui, "Export account setups", 16, y, half, function() Export(ui) end,
        function() return Api() ~= nil end, "export")
    local preview = AddButton(ui, "Preview import", 28 + half, y, half, function() Preview(ui) end,
        function() return Api() ~= nil end, "preview")
    P.ActionBarMenu.Prepare(ui.body, {
        { widget = export, rule = { key = "transfer.export", label = "Export account setups" }, meta = Meta("export") },
        { widget = preview, rule = { key = "transfer.preview", label = "Preview import" }, meta = Meta("preview") },
    })
    return y - 48
end

local function BuildModes(ui, y)
    local applyOptions = {
            { value = "both", text = Tr("Actions and key bindings") },
            { value = "slots", text = Tr("Actions only") },
            { value = "keys", text = Tr("Key bindings only") },
    }

    local listOptions = {
            { value = "saved", text = Tr("Saved setups") },
            { value = "preview", text = Tr("Import preview") },
            { value = "pending", text = Tr("Queued transfers") },
            { value = "results", text = Tr("Transfer results") },
    }

    local function Stage(ui)
        local packet, revision = ui.packet, ui.revision
        if not packet or not next(ui.assignments) then return end
        P.Confirm("actionbar-transfer-queue",
            Tr("Queue the assigned setups? They apply outside combat on the matching setup. Shared keys may affect other characters."),
            function()
                if ui.packet ~= packet or ui.revision ~= revision or P.Combat() or not Api() then return end
                local ok = Api().Queue(packet, ui.assignments, ui.mode ~= "keys", ui.mode ~= "slots")
                if not ok then
                    Feedback("The transfer could not be queued. Check the target names and duplicate assignments.", "danger")
                    return
                end
                ui.packet, ui.assignments = nil, {}
                SetView(ui, "pending")
                P.Refresh()
                Feedback("Action bar transfer queued.", "success")
            end)
    end

    local function Restore(ui)
        P.Confirm("actionbar-transfer-restore", Tr("Restore the action bar state saved before the last transfer?"), function()
            local api = Api()
            if P.Combat() or not api then return end
            if not api.Restore() then Feedback("The previous action bar state could not be restored.", "danger") end
            Refresh(ui)
            P.Refresh()
        end)
    end

    local half = ui.half
    M.BindDropdownAt(ui.ctx, ui.body, Tr("Show"), 16, y, listOptions, half,
        function() return ui.view end, function(view) SetView(ui, view) end, Meta("list"))
    M.BindDropdownAt(ui.ctx, ui.body, Tr("Transfer"), 28 + half, y, applyOptions, half,
        function() return ui.mode end, function(mode)
            if ui.mode == mode then return end
            ui.mode, ui.revision = mode, ui.revision + 1
        end, Meta("mode"))
    y = y - 54
    ui.stage = AddButton(ui, "Queue assigned setups", 16, y, half, function() Stage(ui) end,
        function() return ui.packet ~= nil and next(ui.assignments) ~= nil end, "queue")
    ui.restore = AddButton(ui, "Restore previous setup", 28 + half, y, half, function() Restore(ui) end,
        function() return ui.status.canRestore == true end, "restore")
    return y - 43
end

local function BuildRows(ui, y)
    local body, width = ui.body, ui.width
    local buttonWidth = math.min(ui.half, 150)
    ui.empty = P.Text(body, "Nothing to show here yet.", 16, y, width)
    for offset = 1, ROW_COUNT do
        local row = {}
        ui.rows[offset] = row
        row.title = P.Text(body, "", 16, y, width - buttonWidth - 12)
        row.title:SetWordWrap(false)
        row.detail = P.Text(body, "", 16, y - 27, width)
        row.detail:SetMaxLines(2)
        row.action = AddButton(ui, "Assign target", 16 + width - buttonWidth, y, buttonWidth,
            function() HandleRow(ui, row) end, function() return row.entry ~= nil end, "row" .. offset)
        y = y - ROW_HEIGHT
    end
    ui.previous = AddButton(ui, "Previous", 16, y, 88, function()
        ui.page = ui.page - 1
        ui.refreshRows()
    end, function() return ui.page > 1 end, "previous")
    ui.pageLabel = P.Text(body, "", 112, y - 6, width - 192)
    ui.pageLabel:SetJustifyH("CENTER")
    ui.next = AddButton(ui, "Next", 16 + width - 88, y, 88, function()
        ui.page = ui.page + 1
        ui.refreshRows()
    end, function() return ui.page * ROW_COUNT < #List(ui) end, "next")
    return y - 34
end

function Page.Build(ctx, builder)
    P.LazySection(builder, SECTION, Tr("Account transfer"), false, {
        content = function(body)
            local width = math.max(240, (HM.GetSectionWidth(body) or builder.width or 720) - 32)
            body._msufSuiteActionBarSectionId = SECTION
            local ui = { body = body, ctx = ctx, width = width, half = math.floor((width - 12) / 2),
                status = EMPTY_STATUS, rows = {}, view = "saved", mode = "both", page = 1,
                text = "", assignments = {}, revision = 0 }
            ui.refreshRows = function() UpdateRows(ui) end
            local y = BuildTop(ui, -18)
            y = BuildPackage(ui, y)
            y = BuildModes(ui, y)
            y = BuildRows(ui, y)
            M.TrackRefresh(ctx, function() if body:IsVisible() then Refresh(ui) end end)
            body:HookScript("OnShow", function() Refresh(ui) end)
            Refresh(ui)
            return y
        end,
        finish = function(body, y) P.FinishBody(builder, body, y) end,
    })
end
