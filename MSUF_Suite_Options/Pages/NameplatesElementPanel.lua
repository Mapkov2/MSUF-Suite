local _, P = ...
-- The element panel left of the nameplate preview: every element of the
-- sample in its group, with the preview square (shows or hides it in the
-- preview only, as the old layer chips did) and the plate switch (- takes it
-- off the plate, + puts it back; a real profile write). Elements off the plate
-- gather under "Not on the plate". A row click shows and selects the element;
-- a right-click opens its settings.
local M, T, Tr, HM = P.M, P.T, P.Tr, P.HM
local Elements, Layers = P.NameplatesElements, P.NameplatesEditorLayers
local Panel = {}
P.NameplatesElementPanel = Panel
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ROW, HEADER, TITLE, PAD, SQUARE = 22, 20, 28, 6, 12
local POSITION_LABEL = { power = "Power Text", auras = "Position", icons = "Position" }
local ROW_HELP = "Click: show and select. Right-click: settings."
local EYE_HELP = "Click: show or hide preview; right-click: settings"
local PLATE_HELP = "- takes the element off your nameplates, + puts it back. Its settings are kept."

local function Accent() return T.colors.accent or T.colors.coreGlow or T.colors.text end

-- The preview square: filled while the element is on in the preview.
local function Eye(parent, ui, key, color)
    local eye = CreateFrame("Button", nil, parent)
    eye:SetSize(SQUARE + 6, SQUARE + 6)
    local frame = eye:CreateTexture(nil, "BORDER")
    frame:SetPoint("CENTER")
    frame:SetSize(SQUARE, SQUARE)
    frame:SetColorTexture(color[1], color[2], color[3], 1)
    local hollow = eye:CreateTexture(nil, "ARTWORK")
    hollow:SetPoint("CENTER")
    hollow:SetSize(SQUARE - 2, SQUARE - 2)
    hollow:SetColorTexture(0.05, 0.06, 0.08, 1)
    eye.layerKey, eye.hollow = key, hollow
    function eye:Refresh()
        local blocked = Layers.Blocked(ui, key)
        self.hollow:SetShown(not ui:LayerOn(key))
        self:SetAlpha(blocked and 0.45 or (ui:LayerActive(key) and 1 or 0.7))
    end
    P.PreviewInteraction.BindLayerClick(eye, function() return Layers.Toggle(ui, key) end, function(setting)
        if key == "guides" or P.Combat() then return end
        local def = Layers.Def(key)
        if key == "castShield" and ui:CanPickElement() then return Layers.Focus(ui, def.section, key) end
        if type(setting) == "string" and Layers.OpenSetting(setting) then return end
        return Layers.Focus(ui, def and def.section, key)
    end, function() return Layers.Blocked(ui, key) end)
    HM.SetCommandAction(eye, { kind = "toggle", historyMode = "none",
        get = function() return Layers.Blocked(ui, key) == nil and ui:LayerOn(key) end,
        set = function(desired)
            if Layers.Blocked(ui, key) or P.Combat() then return false end
            Layers.SetShown(ui, key, desired == true)
            ui:Paint()
            return ui:LayerOn(key) == (desired == true)
        end })
    local def = Layers.Def(key)
    if M.AddTooltip then
        M.AddTooltip(eye, def and def.label or key, EYE_HELP, { hook = true })
    end
    Layers.Register(eye, "layer." .. key, Tr("%s preview layer"):format(Tr(def and def.label or key)))
    return eye
end

-- Takes the element off the plate or puts it back.
function Panel.SetPresence(ui, def, on)
    if not Elements.SetPresence(ui, def, on) then return false end
    local layer = Layers.Def(def.key)
    local label = Tr(layer and layer.label or def.key)
    if M.ShowStatusFeedback then
        M.ShowStatusFeedback(on and Tr("%s added to the plate"):format(label)
            or Tr("%s removed from the plate"):format(label), "ok", 2.5)
    end
    ui:Paint()
    return true
end

local function ActionButton(row, ui, def)
    local button = T.Button(row, "-", 18, 18)
    button:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
    HM.SkipHistoryCheckpoint(button)
    button:SetScript("OnClick", function()
        local key, on = Elements.Presence(ui, def)
        if key then Panel.SetPresence(ui, def, not on) end
    end)
    if M.AddTooltip then M.AddTooltip(button, "On the plate", PLATE_HELP, { hook = true }) end
    return button
end

local function Row(content, ui, def)
    local layer = Layers.Def(def.key)
    local label = layer and layer.label or def.key
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.def, row.label = def, label
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(row)
    hover:SetColorTexture(1, 1, 1, 0.05)
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints(row)
    row.eye = Eye(row, ui, def.key, layer and layer.color or { 0.6, 0.6, 0.6 })
    row.eye:SetPoint("LEFT", row, "LEFT", PAD - 3, 0)
    row.action = ActionButton(row, ui, def)
    row.status = T.Font(row, "GameFontDisableSmall", "", T.colors.muted)
    row.status:SetPoint("RIGHT", row.action, "LEFT", -4, 0)
    row.status:SetJustifyH("RIGHT")
    row.status:SetWordWrap(false)
    row.text = T.Font(row, "GameFontHighlightSmall", label, T.colors.text)
    row.text:SetPoint("LEFT", row.eye, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", row.status, "LEFT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if not P.Combat() then Layers.Focus(ui, layer and layer.section, def.key) end
            return
        end
        Elements.Inspect(ui, def, true)
    end)
    if M.AddTooltip then M.AddTooltip(row, label, ROW_HELP, { hook = true }) end
    return row
end

local function Header(content, title)
    local header = CreateFrame("Frame", nil, content)
    header:SetHeight(HEADER)
    header.title = T.Font(header, "GameFontDisableSmall", title, T.colors.muted)
    header.title:SetPoint("LEFT", header, "LEFT", PAD, -2)
    header.count = T.Font(header, "GameFontDisableSmall", "", T.colors.muted)
    header.count:SetPoint("RIGHT", header, "RIGHT", -PAD, -2)
    header.title:SetPoint("RIGHT", header.count, "LEFT", -20, 0)
    header.title:SetJustifyH("LEFT")
    header.title:SetWordWrap(false)
    header.title:SetMaxLines(1)
    return header
end

-- The status word on the right of a row.
local function RowState(ui, row)
    local def, key = row.def, row.def.key
    local presenceKey, on = Elements.Presence(ui, def)
    local status = ""
    if presenceKey == nil and def.presence then status = Tr("Blizzard") end
    if not ui:LayerOn(key) then status = Tr("Hidden")
    elseif not ui:LayerActive(key) and on ~= false then status = Tr("Not in sample") end
    P.SetTranslatedText(row.status, status)
    row.action:SetShown(presenceKey ~= nil and not def.locked)
    if presenceKey then
        P.SetButtonText(row.action, on and "-" or "+")
        row.action:SetEnabled(Elements.Locked(ui, def) == nil)
    end
    local accent = Accent()
    local selected = Elements.Current(ui) == def
    row.selected:SetColorTexture(accent[1], accent[2], accent[3], selected and 0.14 or 0)
    local color = selected and accent or (on == false and T.colors.muted or T.colors.text)
    row.text:SetTextColor(color[1], color[2], color[3], 1)
    row.eye:Refresh()
    return presenceKey ~= nil and on == false
end

local function Place(region, content, y, width)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    region:SetWidth(width)
    region:Show()
    return y + region:GetHeight()
end

-- Lays the rows out for the sample shown: on-plate rows in their groups,
-- the rest under "Not on the plate".
local function LayoutRows(ui)
    local panel = ui.elementPanel
    local width = panel.clip:GetWidth()
    if not width or width < 1 then return end
    local selected = Elements.Current(ui)
    local y, off, onCount = 0, {}, 0
    for _, group in ipairs(Elements.GROUPS) do
        local header, shown, total = panel.headers[group.id], 0, 0
        local positions = panel.positions[group.id]
        local start = y
        y = y + HEADER
        for _, row in ipairs(panel.groupRows[group.id]) do
            if Elements.Applies(ui, row.def) then
                total = total + 1
                if RowState(ui, row) then
                    off[#off + 1] = row
                else
                    shown, y = shown + 1, Place(row, panel.content, y, width)
                end
            else
                row:Hide()
            end
        end
        onCount = onCount + shown
        if positions then
            positions:SetShown(total > 0 and selected ~= nil and selected.group == group.id and ui:CanPickElement())
        end
        if total == 0 then
            header:Hide()
            y = start
        else
            Place(header, panel.content, start, width)
            header.count:SetText(shown .. "/" .. total)
            if positions and positions:IsShown() then y = Place(positions, panel.content, y, width) end
            if shown == 0 then y = y + 4 end
        end
    end
    panel.offHeader:SetShown(#off > 0)
    if #off > 0 then
        y = Place(panel.offHeader, panel.content, y + 6, width)
        panel.offHeader.count:SetText(#off)
        for _, row in ipairs(off) do y = Place(row, panel.content, y, width) end
    end
    P.SetTranslatedText(panel.summary, Tr("%d on the plate"):format(onCount))
    panel.contentHeight = y
    Panel.Scroll(ui, panel.offset or 0)
end

function Panel.Scroll(ui, offset)
    local panel = ui.elementPanel
    local visible = panel.clip:GetHeight() or 0
    local limit = math.max(0, (panel.contentHeight or 0) - visible)
    panel.offset = math.max(0, math.min(limit, offset))
    panel.content:ClearAllPoints()
    panel.content:SetPoint("TOPLEFT", panel.clip, "TOPLEFT", 0, panel.offset)
    panel.content:SetPoint("TOPRIGHT", panel.clip, "TOPRIGHT", 0, panel.offset)
    panel.content:SetHeight(math.max(1, panel.contentHeight or 1))
end

function Panel.Build(ui)
    local panel = CreateFrame("Frame", nil, ui.body, "BackdropTemplate")
    ui.elementPanel = panel
    local chrome = M.PreviewHelpers
    if chrome and chrome.ApplyPreviewChrome then chrome.ApplyPreviewChrome(panel, "sidebar", T) end
    panel.title = T.Font(panel, "GameFontNormal", "Elements", T.colors.text, "card")
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 2, -8)
    panel.summary = T.Font(panel, "GameFontDisableSmall", "", T.colors.muted)
    panel.summary:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD - 2, -10)
    panel.clip = CreateFrame("Frame", nil, panel)
    panel.clip:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -TITLE)
    panel.clip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, 4)
    panel.clip:SetClipsChildren(true)
    panel.clip:EnableMouseWheel(true)
    panel.clip:SetScript("OnMouseWheel", function(_, delta) Panel.Scroll(ui, (panel.offset or 0) - delta * ROW * 2) end)
    panel.content = CreateFrame("Frame", nil, panel.clip)
    panel.headers, panel.groupRows, panel.rows = {}, {}, {}
    panel.positions = {}
    ui.layerButtons = {}
    for _, group in ipairs(Elements.GROUPS) do
        panel.headers[group.id] = Header(panel.content, group.title)
        panel.groupRows[group.id] = {}
        local label = POSITION_LABEL[group.id]
        if label then
            local button = T.Button(panel.content, label, 100, ROW)
            HM.SkipHistoryCheckpoint(button)
            button:SetScript("OnClick", function() ui:OpenElementPositions(button, group.id) end)
            Layers.Register(button, "position." .. group.id, label)
            panel.positions[group.id] = button
        end
    end
    for _, def in ipairs(Elements.LIST) do
        local row = Row(panel.content, ui, def)
        panel.rows[#panel.rows + 1] = row
        local list = panel.groupRows[def.group]
        list[#list + 1] = row
        ui.layerButtons[#ui.layerButtons + 1] = row.eye
    end
    panel.offHeader = Header(panel.content, "Not on the plate")
    -- Icons and markers keep the old "Status icons" switch on their header.
    local status = Eye(panel.headers.icons, ui, "status", Layers.Def("status").color)
    status:SetPoint("RIGHT", panel.headers.icons.count, "LEFT", -4, 0)
    ui.layerButtons[#ui.layerButtons + 1] = status
    function ui:LayoutElements() LayoutRows(self) end
    return panel
end
