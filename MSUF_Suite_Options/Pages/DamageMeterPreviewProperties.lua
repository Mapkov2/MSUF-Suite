local _, P = ...
local R, ID = {}, "damageMeter"
P.MeterPreviewProperties = R
local W, Tr = P.W, P.Tr
local FIELDS = { { "size", "Size" }, { "width", "Width" }, { "height", "Height" }, { "layer", "MSUF layer (-1 = Auto)" } }

function R.Key(preview, handle, field)
    local key = handle and handle[field .. "Setting"]
    if key and key:sub(1, 6) == "window" then return "w" .. preview.selected() .. key:sub(7) end
    return key or nil
end

function R.Read(preview, handle, field)
    local key = R.Key(preview, handle, field)
    if not key then return field == "layer" and -1 or 0 end
    local value = P.Get(ID, key)
    if value == 0 and handle.defaultSizeSetting and field == "size" then
        local fallback = P.Get(ID, handle.defaultSizeSetting)
        return handle.defaultSizeSetting == "headerIconSize" and math.min(fallback, P.Get(ID, "headerHeight")) or fallback
    end
    return value
end

local function Set(preview, field, value)
    local handle = preview.viewport._selectedHandle
    if preview.properties.refreshing then return false end
    if preview.inCombat or P.Combat() or not preview.viewport:IsVisible() or not handle or not handle:IsVisible() then return false end
    local key = R.Key(preview, handle, field)
    if not key then return false end
    local rule = P.catalog[ID].rules[key]
    if value == 0 and rule.min > 0 then value = rule.default end
    return P.Set(ID, key, value)
end

function R.Reset(preview)
    local handle = preview.viewport._selectedHandle
    if preview.inCombat or P.Combat() or not preview.viewport:IsVisible() or not handle or not handle:IsVisible() then return false end
    local values, rules = {}, P.catalog[ID].rules
    if handle.canMove then
        local prefix = handle.offsetPrefix
        for _, axis in ipairs({ "X", "Y" }) do values[prefix .. axis] = rules[prefix .. axis].default end
    end
    for _, field in ipairs(FIELDS) do
        local key = R.Key(preview, handle, field[1])
        if key then values[key] = rules[key].default end
    end
    return P.SetMany(ID, values)
end

function R.Build(preview)
    local panel = CreateFrame("Frame", nil, preview.ui.header)
    preview.properties = panel
    panel.values, panel.refreshing = {}, false
    panel.label = P.PreviewCanvas.Text(panel, "Applies to all windows", 0, 0, preview.availableWidth)
    panel.slots, panel.grid = {}, { controls = {} }
    for _, spec in ipairs(FIELDS) do
        local field = spec[1]
        local row = P.Meta("suite_damageMeter", ID, "preview." .. field, "ephemeral", "suite_damageMeter_bars")
        row.id, row.kind, row.min, row.max, row.step, row.default = field, "slider", field == "layer" and -1 or 0, 900, 1, 0
        row.label = Tr(spec[2])
        row.get = function() return R.Read(preview, preview.viewport._selectedHandle, field) end
        row.set = function(value) return Set(preview, field, value) end
        -- Native slider titles, value boxes and step buttons share this
        -- parent. Hide the complete control, never only its slider track.
        local slot = CreateFrame("Frame", nil, panel)
        panel.slots[field] = slot
        local grid = W.SettingsRows(preview.ui.ctx, slot, { rows = { row }, x = 0, y = 0, width = 240, columns = 1 })
        panel.grid.controls[field] = grid.controls[field]
    end
    panel.reset = P.T.Button(panel, "Reset selected element", 180, 22)
    panel.reset:SetScript("OnClick", function() R.Reset(preview) end)
    P.HM.SkipHistoryCheckpoint(panel.reset)
    for _, widget in pairs(panel.grid.controls) do P.HM.SkipHistoryCheckpoint(widget) end
    panel:Hide()
end

local function FieldLayout(preview, field, cell, blocked)
    local panel, handle = preview.properties, preview.viewport._selectedHandle
    local widget, container = panel.grid.controls[field], panel.slots[field]
    local rule = P.catalog[ID].rules[R.Key(preview, handle, field)]
    widget:SetMinMaxValues(field == "size" and handle.defaultSizeSetting and 1 or rule.min, rule.max)
    widget:SetValue(panel.values[field])
    W.SetControlEnabled(widget, not blocked)
    W.MoveWidget(widget, container, 0, 0, cell)
    local title = P.HM.GetControlTitle(widget)
    title:SetWordWrap(true)
    title:SetHeight(0)
    local inputTop = math.max(24, math.ceil(title:GetStringHeight()) + 8)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -inputTop)
    return inputTop + 24
end

function R.Refresh(preview)
    local handle, panel = preview.viewport._selectedHandle, preview.properties
    if not panel then return end
    panel:SetShown(handle ~= nil and handle ~= false)
    if not handle then
        preview.propertiesHeight, panel.lastHandle = 0, nil
        return
    end
    local blocked, changed = preview.inCombat or P.Combat(), panel.lastHandle ~= handle
    for _, spec in ipairs(FIELDS) do
        local value = R.Read(preview, handle, spec[1])
        if panel.values[spec[1]] ~= value then changed = true end
        panel.values[spec[1]] = value
    end
    if not changed and panel.lastWidth == preview.availableWidth and panel.lastBlocked == blocked then return end
    panel.lastHandle, panel.lastWidth, panel.lastBlocked = handle, preview.availableWidth, blocked
    local width, columns = preview.availableWidth, preview.availableWidth >= 540 and 2 or 1
    P.SetTranslatedText(panel.label, handle.widthSetting == "windowWidth" and Tr("Only the selected window") or Tr("Applies to all windows"))
    panel.label:SetWidth(width)
    local extra = math.max(0, math.ceil(panel.label:GetStringHeight()) - 12)
    local slot, top, rowHeight = 0, 20 + extra, 0
    panel.refreshing = true
    for _, spec in ipairs(FIELDS) do
        local field, widget = spec[1], panel.grid.controls[spec[1]]
        local key = R.Key(preview, handle, field)
        local container = panel.slots[field]
        container:SetShown(key ~= nil)
        if key then
            local cell = (width - (columns - 1) * 16) / columns
            container:ClearAllPoints()
            container:SetPoint("TOPLEFT", panel, "TOPLEFT", (slot % columns) * (cell + 16), -top)
            local height = FieldLayout(preview, field, cell, blocked)
            container:SetSize(cell, height)
            rowHeight = math.max(rowHeight, height)
            slot = slot + 1
            if slot % columns == 0 then top, rowHeight = top + rowHeight, 0 end
        end
    end
    panel.refreshing = false
    local bottom = top + rowHeight
    panel.reset:SetEnabled(not blocked)
    panel.reset:SetWidth(width)
    panel.reset:ClearAllPoints()
    panel.reset:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -bottom - 4)
    panel:SetSize(width, bottom + 30)
    preview.propertiesHeight = panel:GetHeight()
end
