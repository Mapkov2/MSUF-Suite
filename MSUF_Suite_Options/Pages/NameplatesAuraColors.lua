local _, P = ...
local Tr, M, W = P.Tr, P.M, P.W
local A, D = P.Suite.NameplateAuraColors, P.NameplatesAuraDraft
local PAGE, ID, SECTION = "suite_nameplates", "nameplates", "suite_nameplates_auraColors"
local UI = {}
P.NameplatesAuraUI = UI
local HELP = P.Help(
    "Individual colors follow list order; a lone DoT uses its own color. With multiple selected DoTs, all active wins over individual and role colors.",
    "Blizzard supplies health and aura updates. List edits and preview work during combat; color pickers work after combat.")
local CUSTOM_HELP = P.Help("Choose DoTs for this specialization. Disabled entries keep their position.",
    "MSUF supplies class suggestions. Unlearned entries pause only when Blizzard supplies their talent mapping.")
local CUSTOM_NOTE = "A valid spell name does not confirm a matching target aura. Custom IDs remain selected until you disable them."

local function Name(id)
    local name = C_Spell.GetSpellName(id)
    if P.Suite.Public(name) and type(name) == "string" then return name end
    return string.format(Tr("Unknown aura %d: check the ID"), id)
end

local function Icon(id)
    local icon = C_Spell.GetSpellTexture(id)
    return P.Suite.Public(icon) and icon or 134400
end

local function Meta(key)
    return P.Meta(PAGE, ID, key, key:match("^action%.") and "action" or "setting", SECTION)
end

local function DraftButton(ctx, parent, label, x, y, width, callback, key, glyph)
    local button = P.T.Button(parent, glyph or label, width, 26)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetScript("OnClick", function()
        callback()
        P.Refresh()
    end)
    M.RegisterControlMetadata(button, Meta(key), label, "button")
    if glyph then M.AddTooltip(button, Tr(label), nil, { hook = true }) end
    return button
end

local function LabelRow(key, label, kind)
    local row = Meta(key)
    row.id, row.label, row.kind = key, Tr(label), kind
    row.get = function() return D.Get(key) end
    row.set = function(value) D.Set(key, value) end
    return row
end

-- The shared host bindings block combat before calling setters. These
-- owned controls edit only D's draft; native/profile writes stay deferred.
local function DraftRows(ctx, parent, spec)
    local grid = W.SettingsRows(ctx, parent, spec)
    for _, row in ipairs(spec.rows) do
        local widget = grid.controls[row.id]
        if row.kind == "toggle" then
            widget:SetScript("OnClick", function()
                row.set(not row.get())
                widget:SetChecked(row.get())
                P.Refresh()
            end)
        elseif row.kind == "dropdown" then
            widget:SetOnValueChanged(function(value)
                row.set(value)
                widget:SetValue(row.get())
                P.Refresh()
            end)
        end
    end
    return grid
end

local function SpecValues()
    local values = {}
    local count = GetNumSpecializations()
    if not P.Suite.Public(count) or type(count) ~= "number" then return values end
    for i = 1, math.min(count, 6) do
        local id, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(i)
        if A.ID(id) and P.Suite.Public(name) and type(name) == "string" then
            values[#values + 1] = { value = id, text = name, icon = P.Suite.Public(icon) and icon or nil }
        end
    end
    return values
end

local function SpecRow()
    local row = Meta("action.auraSpec")
    row.id, row.label, row.kind = "spec", Tr("DoTs by specialization"), "dropdown"
    row.values, row.get = SpecValues, D.Spec
    row.set = function(value)
        D.selected = value
        P.Refresh()
    end
    return row
end

local function Suggestions()
    local values = {}
    UI.suggestions = A.Suggestions()
    for i, row in ipairs(UI.suggestions) do
        local label = string.format(Tr("%s (Aura %d)"), Name(row.id), row.id)
        if A.Paused(row) then label = string.format(Tr("%s (not learned)"), label) end
        values[#values + 1] = { value = i, text = label, icon = Icon(row.id) }
    end
    return values
end

local function Picker(ctx, body, y, width)
    local row = Meta("action.auraSuggestion")
    row.id, row.label, row.kind = "action.auraSuggestion", Tr("Add a DoT from MSUF"), "dropdown"
    row.values, row.get = Suggestions, function() return nil end
    row.set = function(value)
        local entry = UI.suggestions and UI.suggestions[value]
        if entry then D.Add(entry) end
    end
    local grid = DraftRows(ctx, body, { x = 16, y = y, width = width, columns = 1, rows = { row } })
    y = grid.bottomY - 6
    local function Commit(value)
        local id = A.ID(tonumber(value))
        UI.invalidID = not id
        if id then D.Add({ id = id, ids = { id }, color = A.DEFAULT_COLOR }) end
        P.Refresh()
    end
    local input = M.BindTextInputAt(ctx, body, Tr("Custom aura ID"), 16, y, width,
        function() return "" end, Commit, true, Meta("action.auraCustom"))
    input:SetOnValueCommitted(Commit)
    input:SetMaxLetters(10)
    M.AddTooltip(input, Tr("Custom aura ID"), Tr(CUSTOM_NOTE), { hook = true })
    return y - 64
end

local function Entry(index)
    return D.Rows()[index]
end

local function Change(index, callback)
    D.Edit(function(rows) if rows[index] then callback(rows, rows[index]) end end)
end

local function EntryRow(index)
    local row = Meta("action.auraEntry" .. index)
    row.id, row.label, row.kind = "enabled", Tr("Track DoT"), "toggle"
    row.get = function() return (Entry(index) or {}).enabled ~= false end
    row.set = function(value) Change(index, function(_, entry) entry.enabled = value end) end
    return row
end

local function ColorTarget(key, label, entry)
    local get, set = D.BindColor(key, entry)
    return { label = label, sourceSettingKey = "msufsuite.nameplates." .. key,
        settingKey = "msufsuite.nameplates." .. key,
        get = function() return P.RGB(get()) end,
        set = function(r, g, b)
            local hex = string.format("%02x%02x%02x", math.floor(r * 255 + .5),
                math.floor(g * 255 + .5), math.floor(b * 255 + .5))
            set(hex)
        end,
    }
end

local function AttachColors(body)
    local shortcut = W.AttachContextColorShortcut(body, { title = Tr("DoT health colors"), maxTargets = A.LIMIT + 2,
        getTargets = function()
            local targets = { ColorTarget("auraColorsAll", Tr("All selected DoTs")),
                ColorTarget("auraColorsNone", Tr("No selected DoT")) }
            for index, entry in ipairs(D.Rows()) do
                targets[#targets + 1] = ColorTarget("auraColorsData", Name(entry.id), entry)
            end
            return targets
        end,
    })
    P.HM.ReleaseColorShortcut(shortcut)
end

local function Actions(ctx, parent, index)
    local up = DraftButton(ctx, parent, "Move up", 0, -52, 28, function()
        Change(index, function(rows) if index > 1 then rows[index], rows[index - 1] = rows[index - 1], rows[index] end end)
    end, "action.auraUp" .. index, "↑")
    local down = DraftButton(ctx, parent, "Move down", 34, -52, 28, function()
        Change(index, function(rows) if index < #rows then rows[index], rows[index + 1] = rows[index + 1], rows[index] end end)
    end, "action.auraDown" .. index, "↓")
    DraftButton(ctx, parent, "Remove", 68, -52, 28, function()
        D.Edit(function(rows) table.remove(rows, index) end)
    end, "action.auraRemove" .. index, "×")
    DraftButton(ctx, parent, "Show in preview", 104, -52, 128, function()
        local row = Entry(index)
        if row then
            D.sample = "custom"
            D.present[row.id] = not D.present[row.id]
        end
    end, "action.auraPresent" .. index)
    return up, down
end

local function BuildEntry(ctx, list, index, width)
    local body = CreateFrame("Frame", nil, list)
    body:SetSize(width, 90)
    local row = EntryRow(index)
    row.label = ""
    local grid = DraftRows(ctx, body, { x = 0, y = -2, width = 1, columns = 1, rows = { row } })
    local toggle = grid.controls.enabled
    M.AddTooltip(toggle, Tr("Track DoT"), nil, { hook = true })
    local icon = body:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", body, "TOPLEFT", 34, -5)
    local swatch = body:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(14, 14)
    swatch:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -8)
    local label = P.Text(body, "", 60, -7, width - 82)
    label:SetWordWrap(false)
    local detail = P.Text(body, "", 34, -29, width - 34)
    detail:SetWordWrap(false)
    local up, down = Actions(ctx, body, index)
    return { body = body, icon = icon, swatch = swatch, label = label, detail = detail,
        up = up, down = down, height = 90 }
end

local function RefreshList(pool, list, builder, body, y, status)
    local rows, offset = D.Rows(), 0
    for i, ui in ipairs(pool) do
        local row = rows[i]
        ui.body:SetShown(row ~= nil)
        if row then
            ui.body:ClearAllPoints()
            ui.body:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -offset)
            ui.icon:SetTexture(Icon(row.id))
            ui.swatch:SetColorTexture(P.RGB(row.color))
            P.SetTranslatedText(ui.label, Name(row.id))
            local paused = D.Spec() == A.Spec() and A.Paused(row)
            local detail = paused and Tr("Paused: not learned in this specialization")
                or row.cooldown and Tr("Blizzard talent mapping: %d") or row.curated and Tr("MSUF DoT aura ID: %d")
                or Tr("Manual aura ID (unconfirmed): %d")
            P.SetTranslatedText(ui.detail, paused and detail or string.format(detail, row.id))
            ui.up:SetEnabled(i > 1)
            ui.down:SetEnabled(i < #rows)
            offset = offset + ui.height
        end
    end
    list:SetHeight(math.max(1, offset))
    local text = D.Pending() and Tr("Changes will apply after combat")
        or #rows == 0 and Tr("Choose at least one DoT to enable aura colors")
        or #rows >= A.LIMIT and Tr("Maximum of 8 DoTs per specialization") or Tr("Preview uses simulated DoTs")
    if P.Get(ID, "look") == 2 then text = Tr("Choose a nameplate skin to show DoT health colors") end
    if UI.invalidID then text = Tr("Enter a valid numeric aura ID") end
    P.SetTranslatedText(status, text)
    P.FinishBody(builder, body, y - offset - 12)
end

local function PreviewRows()
    local row = Meta("action.auraSample")
    row.id, row.label, row.kind = "sample", Tr("Preview DoT state"), "dropdown"
    row.values = { { value = "none", text = Tr("No DoTs") }, { value = "partial", text = Tr("Some DoTs") },
        { value = "all", text = Tr("All DoTs") }, { value = "custom", text = Tr("Choose preview DoTs") } }
    row.get = function() return D.sample end
    row.set = function(value)
        D.sample = value
        P.Refresh()
    end
    return row
end

function UI.Build(ctx, builder, body)
    local width = math.max(240, (P.HM.GetSectionWidth(body) or builder.width or 720) - 32)
    local help = P.Description(body, HELP, 16, -12, width, Tr("DoT health colors"))
    local y = -24 - math.max(14, math.ceil(help:GetStringHeight() or 14))
    local settings = { SpecRow(), LabelRow("auraColorsEnabled", "Color enemy health by your DoTs", "toggle"),
        LabelRow("auraColorsNoneEnabled", "Warn when no selected DoT is active", "toggle"),
        LabelRow("auraColorsIndividual", "Use individual DoT colors in list order", "toggle"),
        PreviewRows() }
    local grid = DraftRows(ctx, body, { x = 16, y = y, width = width, columns = width >= 560 and 2 or 1, rows = settings })
    y = grid.bottomY - 8
    local status = P.Text(body, "", 16, y, width)
    y = y - 26
    local discard = DraftButton(ctx, body, "Discard pending changes", 16, y, 232, D.Discard, "action.auraDiscard")
    M.TrackRefresh(ctx, function() discard:SetShown(D.Pending()) end)
    discard:SetShown(D.Pending())
    y = y - 34
    local note = P.Description(body, CUSTOM_HELP, 16, y, width, Tr("DoT health colors"))
    y = y - math.max(14, math.ceil(note:GetStringHeight() or 14)) - 12
    y = Picker(ctx, body, y, width)
    local list, pool = CreateFrame("Frame", nil, body), {}
    list:SetSize(width, 1)
    list:SetPoint("TOPLEFT", body, "TOPLEFT", 16, y)
    for i = 1, A.LIMIT do pool[i] = BuildEntry(ctx, list, i, width) end
    M.TrackRefresh(ctx, function() RefreshList(pool, list, builder, body, y, status) end)
    RefreshList(pool, list, builder, body, y, status)
end

function P.BuildNameplatesAuraColors(ctx, builder, sections)
    sections.auraColors = P.LazySection(builder, SECTION, Tr("DoT health colors"), true, {
        content = function(body) UI.Build(ctx, builder, body) end,
        shell = function(body)
            AttachColors(body)
            P.AttachSectionReset(ctx, body, Tr("DoT colors"), function()
                D.ResetColors()
                return true
            end)
        end,
    })
end

function P.BuildNameplatesAuraSamples(editor)
    local bar = CreateFrame("Frame", nil, editor.canvas)
    bar:SetSize(234, 26)
    bar:SetPoint("BOTTOMLEFT", editor.canvas, "BOTTOMLEFT", 6, 4)
    for i, spec in ipairs({ { "none", "No DoTs" }, { "partial", "Some DoTs" }, { "all", "All DoTs" } }) do
        DraftButton(editor.ctx, bar, spec[2], (i - 1) * 78, 0, 74, function()
            D.sample = spec[1]
            editor.sampleKind = "enemy"
            editor:Paint()
        end, "action.auraSample." .. spec[1])
    end
    M.TrackRefresh(editor.ctx, function() bar:SetShown(D.Get("auraColorsEnabled")) end)
    bar:SetShown(D.Get("auraColorsEnabled"))
end
