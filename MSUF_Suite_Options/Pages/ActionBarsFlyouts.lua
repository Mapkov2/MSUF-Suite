local _, P = ...
local M, S, Tr, HM, T = P.M, P.S, P.Tr, P.HM, P.T
-- Action bar flyouts: presets, the flyout list, its entries and placing it
-- on a bar. The data lives with the action bar addon (S.ActionBarFlyouts,
-- MSUF_Suite_ActionBars/FlyoutAPI.lua), per account and WoW version; these
-- are actions, not profile settings, so nothing here enters the undo history.
local PAGE, MODULE, SECTION = "suite_actionbars", "actionbars", "suite_actionbars_flyouts"
local ROW_COUNT, ROW_HEIGHT = 8, 34
local HELP = P.Help(
    "Group spells, items, toys, mounts and macros behind one action button. A flyout opens like Blizzard's spell "
        .. "flyouts, also in combat, and costs no CPU while it is closed.",
    "Place a flyout on a bar, or pick it up and drop it on any button of the Suite action bars. It opens in that bar's "
        .. "spell flyout direction, at the size of its button. Out of combat a click anywhere else closes it; in combat "
        .. "it closes a few seconds after the mouse leaves. Only what you carry or know shows up, best first, so one food "
        .. "flyout always offers the food in your bags.")

local Page = {}
P.ActionBarFlyoutsPage = Page

local function Api()
    return S.ActionBarFlyouts
end

local function Ready()
    local api = Api()
    return api ~= nil and api.Ready() == true
end

local function Meta(key)
    return P.Meta(PAGE, MODULE, "flyouts." .. key, "ephemeral", SECTION)
end

local function Feedback(text, kind)
    if M.ShowStatusFeedback then M.ShowStatusFeedback(Tr(text), kind, 2.6) end
end

-- A change's answer: true, or nil and an English message.
local function Report(ok, problem, success)
    if ok then
        if success then Feedback(success, "success") end
        return true
    end
    Feedback(problem or "This change could not be made.", "danger")
end

local function Selected(ui)
    local api = Api()
    if not api then return nil end
    local list = api.List()
    for _, row in ipairs(list) do
        if row.id == ui.selected then return row, list end
    end
    ui.selected = list[1] and list[1].id or nil
    return list[1], list
end

local function AddButton(ui, label, x, y, width, run, enabled, key)
    local button = P.Button(ui.ctx, ui.body, label, x, y, width, run, enabled, Meta(key))
    HM.SkipHistoryCheckpoint(button)
    return button
end

------------------------------------------------------------------ presets and flyouts
local function PresetChoices()
    local api, values = Api(), {}
    for _, preset in ipairs(api and api.Presets() or {}) do values[#values + 1] = { value = preset.key, text = Tr(preset.label) } end
    return values
end

local function PresetHelp(ui)
    for _, preset in ipairs(Api() and Api().Presets() or {}) do
        if preset.key == ui.preset then return Tr(preset.description) end
    end
    return ""
end

local function AddPreset(ui)
    local api = Api()
    for _, preset in ipairs(api.Presets()) do
        if preset.key == ui.preset then
            local id, problem = api.AddPreset(preset.key, Tr(preset.flyoutName))
            if Report(id, problem, "Flyout added. Place it on a bar below.") then ui.selected, ui.page = id, 1 end
            return
        end
    end
end

local function NewFlyout(ui)
    P.AskText("actionbar-flyout-new", Tr("Name of the new flyout"), function(text)
        if P.Combat() or not Api() then return end
        local id, problem = Api().Create(text)
        if Report(id, problem) then ui.selected, ui.page = id, 1 end
        P.Refresh()
    end, 16, 64)
end

local function DeleteFlyout(ui)
    local row = Selected(ui)
    if not row then return end
    P.Confirm("actionbar-flyout-delete",
        Tr("Delete the flyout %s? Its macro leaves every action bar."):format(row.name), function()
            if P.Combat() or not Api() then return end
            if Report(Api().Delete(row.id)) then ui.selected = nil end
            P.Refresh()
        end)
end

local function FlyoutChoices(ui)
    local values = {}
    local api = Api()
    for _, row in ipairs(api and api.List() or {}) do values[#values + 1] = { value = row.id, text = row.name } end
    if #values == 0 then values[1] = { value = 0, text = Tr("No flyouts yet") } end
    return values
end

local function BuildTop(ui, y)
    local body, width, half = ui.body, ui.width, ui.half
    local help = P.Description(body, HELP, 16, y, width, Tr("Flyouts"))
    y = y - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 14
    ui.notice = P.Text(body, "", 16, y, width, T.colors.dim or T.colors.muted)
    y = y - 26
    M.BindDropdownAt(ui.ctx, body, Tr("Preset"), 16, y, PresetChoices, half,
        function() return ui.preset end, function(key) ui.preset = key end, Meta("preset"))
    AddButton(ui, "Add preset", 28 + half, y - 23, half, function() AddPreset(ui) end, Ready, "addPreset")
    y = y - 56
    ui.presetHelp = P.Text(body, "", 16, y, width, T.colors.dim or T.colors.muted)
    y = y - 32
    M.BindDropdownAt(ui.ctx, body, Tr("Flyout"), 16, y, function() return FlyoutChoices(ui) end, half,
        function() return ui.selected or 0 end, function(id)
            ui.selected, ui.page = id ~= 0 and id or nil, 1
            P.Refresh()
        end, Meta("selected"))
    local quarter = math.floor((half - 12) / 2)
    AddButton(ui, "New flyout", 28 + half, y - 23, quarter, function() NewFlyout(ui) end, Ready, "new")
    AddButton(ui, "Delete", 40 + half + quarter, y - 23, quarter, function() DeleteFlyout(ui) end,
        function() return Ready() and Selected(ui) ~= nil end, "delete")
    return y - 60
end

------------------------------------------------------------------ the selected flyout
local function Rename(ui)
    local row = Selected(ui)
    if not row then return end
    P.AskText("actionbar-flyout-rename", Tr("New name for %s"):format(row.name), function(text)
        if P.Combat() or not Api() then return end
        Report(Api().Rename(row.id, text))
        P.Refresh()
    end, 16, 64)
end

local function BarChoices()
    local values, api = {}, Api()
    for _, index in ipairs(api and api.Bars() or {}) do
        values[#values + 1] = { value = index, text = Tr(P.Suite.ActionBarTitles[index]) }
    end
    if #values == 0 then values[1] = { value = 0, text = Tr("No action bar is on") } end
    return values
end

local function Place(ui)
    local row = Selected(ui)
    if not row then return end
    local ok, number = Api().Place(row.id, ui.bar)
    if ok then
        Feedback(Tr("%s is on %s, button %d."):format(row.name, Tr(P.Suite.ActionBarTitles[ui.bar]), number), "success")
    else
        Report(nil, number)
    end
end

local function BuildFlyout(ui, y)
    local body, width, half = ui.body, ui.width, ui.half
    local quarter = math.floor((half - 12) / 2)
    ui.summary = P.Text(body, "", 16, y, half, T.colors.text)
    ui.summary:SetWordWrap(false)
    AddButton(ui, "Rename", 28 + half, y + 4, quarter, function() Rename(ui) end,
        function() return Ready() and Selected(ui) ~= nil end, "rename")
    AddButton(ui, "Pick up", 40 + half + quarter, y + 4, quarter, function()
        local row = Selected(ui)
        if not row then return end
        local ok, problem = Api().Pickup(row.id)
        Report(ok, problem, "Drop the flyout on any action button.")
    end, function() return Ready() and Selected(ui) ~= nil end, "pickup")
    y = y - 38
    M.BindSwitchAt(ui.ctx, body, Tr("Only show what I carry or know"), 16, y, width,
        function() local row = Selected(ui) return row == nil or row.owned end,
        function(on)
            local row = Selected(ui)
            if row and not P.Combat() then Report(Api().SetOwned(row.id, on == true)) end
            P.Refresh()
        end, Meta("owned"))
    y = y - 44
    ui.bar = ui.bar or 1
    M.BindDropdownAt(ui.ctx, body, Tr("Place on"), 16, y, BarChoices, half,
        function() return ui.bar end, function(index) ui.bar = index end, Meta("bar"))
    AddButton(ui, "Place on bar", 28 + half, y - 23, half, function() Place(ui) end,
        function() return Ready() and Selected(ui) ~= nil and ui.bar ~= 0 end, "place")
    return y - 62
end

------------------------------------------------------------------ entries
local function RowAction(ui, row, delta)
    local flyout = Selected(ui)
    if not flyout or not row.position or not Api() then return end
    if delta == 0 then
        Report(Api().RemoveEntry(flyout.id, row.position))
    else
        Report(Api().MoveEntry(flyout.id, row.position, delta))
    end
end

local function UpdateRows(ui)
    local flyout = Selected(ui)
    local entries = flyout and Api().Entries(flyout.id) or {}
    local pages = math.max(1, math.ceil(#entries / ROW_COUNT))
    ui.page = math.min(math.max(ui.page or 1, 1), pages)
    local first = (ui.page - 1) * ROW_COUNT
    for offset, row in ipairs(ui.rows) do
        local position = first + offset
        local entry = entries[position]
        row.position, row.count = entry and position or nil, #entries
        row.icon:SetShown(entry ~= nil)
        row.name:SetShown(entry ~= nil)
        row.up:SetShown(entry ~= nil)
        row.down:SetShown(entry ~= nil)
        row.remove:SetShown(entry ~= nil)
        if entry then
            row.icon:SetTexture(entry.icon or 134400)
            row.icon:SetDesaturated(not entry.active)
            local text = entry.active and entry.name or Tr("%s (not carried or known)"):format(entry.name)
            P.SetTranslatedText(row.name, text)
            row.name:SetTextColor(1, 1, 1, entry.active and 1 or .55)
        end
    end
    ui.empty:SetShown(#entries == 0)
    P.SetTranslatedText(ui.pageLabel, Tr("Page %d of %d"):format(ui.page, pages))
end

local function RowButton(ui, row, label, x, width, delta, key, enabled)
    return AddButton(ui, label, x, row.y, width, function() RowAction(ui, row, delta) end, enabled, key)
end

local function BuildRows(ui, y)
    local body, width = ui.body, ui.width
    P.Text(body, Tr("Entries, in the order the flyout shows them"), 16, y, width)
    y = y - 26
    ui.empty = P.Text(body, "Drop spells, items, toys, mounts or macros below.", 16, y, width, T.colors.dim or T.colors.muted)
    local small = 64
    for offset = 1, ROW_COUNT do
        local row = { y = y }
        ui.rows[offset] = row
        row.icon = body:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("TOPLEFT", body, "TOPLEFT", 16, y)
        row.icon:SetTexCoord(.07, .93, .07, .93)
        row.name = P.Text(body, "", 48, y - 5, width - 3 * (small + 8) - 40)
        row.name:SetWordWrap(false)
        local x = 16 + width - 3 * small - 16
        row.up = RowButton(ui, row, "Up", x, small, -1, "up" .. offset,
            function() return Ready() and row.position ~= nil and row.position > 1 end)
        row.down = RowButton(ui, row, "Down", x + small + 8, small, 1, "down" .. offset,
            function() return Ready() and row.position ~= nil and row.position < row.count end)
        row.remove = RowButton(ui, row, "Remove", x + 2 * (small + 8), small, 0, "remove" .. offset,
            function() return Ready() and row.position ~= nil end)
        y = y - ROW_HEIGHT
    end
    AddButton(ui, "Previous", 16, y, 88, function() ui.page = ui.page - 1 end, function() return ui.page > 1 end, "previous")
    ui.pageLabel = P.Text(body, "", 112, y - 6, width - 192)
    ui.pageLabel:SetJustifyH("CENTER")
    AddButton(ui, "Next", 16 + width - 88, y, 88, function() ui.page = ui.page + 1 end,
        function() local row = ui.rows[1] return row.count ~= nil and ui.page * ROW_COUNT < row.count end, "next")
    return y - 40
end

------------------------------------------------------------------ adding
local function AddCursor(ui)
    local row = Selected(ui)
    if not row or P.Combat() or not Api() then return end
    Report(Api().AddCursor(row.id))
end

local function AddText(ui)
    local row = Selected(ui)
    if not row then return end
    P.AskText("actionbar-flyout-add", Tr("Item or spell ID, for example item:4540 or spell:8690"), function(text)
        if P.Combat() or not Api() then return end
        Report(Api().AddText(row.id, text))
        P.Refresh()
    end, 32, 64)
end

local function BuildAdd(ui, y)
    local width = ui.width
    local drop = AddButton(ui, "Drop a spell, item, toy, mount or macro here", 16, y, width - 160, function() AddCursor(ui) end,
        function() return Ready() and Selected(ui) ~= nil end, "drop")
    drop:SetScript("OnReceiveDrag", function()
        AddCursor(ui)
        P.Refresh()
    end)
    AddButton(ui, "Add by ID", 16 + width - 148, y, 148, function() AddText(ui) end,
        function() return Ready() and Selected(ui) ~= nil end, "addText")
    return y - 40
end

------------------------------------------------------------------ refresh
local function Refresh(ui)
    local api = Api()
    local notice = not api and "Turn on the Suite action bars to use flyouts."
        or select(2, api.Ready()) or ""
    P.SetTranslatedText(ui.notice, notice ~= "" and Tr(notice) or "")
    P.SetTranslatedText(ui.presetHelp, PresetHelp(ui))
    local row = Selected(ui)
    if row then
        P.SetTranslatedText(ui.summary, Tr("%s · shows %d of %d entries right now"):format(row.name, row.shown, row.entries))
    else
        P.SetTranslatedText(ui.summary, Tr("Add a preset or a new flyout to begin."))
    end
    UpdateRows(ui)
end

function Page.Build(ctx, builder)
    P.LazySection(builder, SECTION, Tr("Flyouts"), true, {
        content = function(body)
            local width = math.max(260, (HM.GetSectionWidth(body) or builder.width or 720) - 32)
            body._msufSuiteActionBarSectionId = SECTION
            local presets = Api() and Api().Presets() or {}
            local ui = { body = body, ctx = ctx, width = width, half = math.floor((width - 12) / 2), rows = {}, page = 1,
                preset = presets[1] and presets[1].key }
            local y = BuildTop(ui, -18)
            y = BuildFlyout(ui, y)
            y = BuildRows(ui, y)
            y = BuildAdd(ui, y)
            M.TrackRefresh(ctx, function() if body:IsVisible() then Refresh(ui) end end)
            body:HookScript("OnShow", function() Refresh(ui) end)
            EventRegistry:RegisterCallback("MSUFSuite.ActionBars.FlyoutsChanged", function()
                if body:IsVisible() then Refresh(ui) end
            end, body)
            Refresh(ui)
            return y
        end,
        finish = function(body, y) P.FinishBody(builder, body, y) end,
    })
end
