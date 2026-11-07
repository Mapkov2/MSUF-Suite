local _, P = ...
local E = {}
P.ChatWorkspace = E
local PAGE, ID = "suite_chat", "chat"

-- One persistent preview; only the selected topic's sections are visible.
local TABS = {
    { id = "basics", label = "Basics", sections = "chat_module look window" },
    { id = "appearance", label = "Appearance", sections = "tabs sidebar" },
    { id = "input", label = "Input line", sections = "input" },
    { id = "messages", label = "Messages", sections = "tools text chatComfort_module sounds highlight" },
    { id = "extras", label = "Extras", sections = "bubbles keywordAlerts_module" },
}

local function LayoutSelector(row)
    local width = math.max(1, row.owner:GetWidth() - 32)
    local x, y = 0, 0
    for _, item in ipairs(row.items) do
        local size = math.min(width, item.width)
        if x > 0 and x + size > width then x, y = 0, y - 32 end
        item.button:ClearAllPoints()
        item.button:SetPoint("TOPLEFT", row, "TOPLEFT", x, y)
        item.button:SetSize(size, 26)
        x = x + size + 8
    end
    row:SetSize(width, 26 - y)
end

-- Both supported hosts get visible measured-label wrapping, including older
-- Menu2 versions whose segmented control only offers a single fixed row.
local function Selector(ui, values, apply)
    local row = CreateFrame("Frame", nil, ui.header)
    row.owner, row.items = ui.header, {}
    row:SetPoint("TOPLEFT", ui.header, "TOPLEFT", 16, -12)
    local measureWidth = P.T.MeasureTabWidth
    if not measureWidth then
        local measure = P.PreviewCanvas.Text(row, "", 0, 0, 0)
        measure:SetWordWrap(false)
        measure:Hide()
        measureWidth = function(text)
            measure:SetText(text)
            return math.max(56, math.ceil(measure:GetStringWidth()) + 26)
        end
    end
    local function RefreshSelected()
        for _, item in ipairs(row.items) do item.button:SetActive(ui.selected == item.id) end
    end
    local function Choose(id)
        local selected = apply(id)
        RefreshSelected()
        return selected
    end
    for _, value in ipairs(values) do
        local width = measureWidth(value.text)
        local button = P.T.Button(row, value.text, width, 26)
        P.HM.MarkSegmentChoice(button)
        row.items[#row.items + 1] = { id = value.value, button = button, width = width }
        button:SetScript("OnClick", function() Choose(value.value) end)
        if P.M.RegisterControlMetadata then
            P.M.RegisterControlMetadata(button, P.Meta(PAGE, ID, "view.topic." .. value.value, "ephemeral"), value.text, "button")
        end
    end
    if P.T.TrackTabLayout then
        P.T.TrackTabLayout(row, function(self)
            for _, item in ipairs(self.items) do item.width = measureWidth(item.button:GetText()) end
            LayoutSelector(self)
        end)
    end
    ui.header:HookScript("OnSizeChanged", function() LayoutSelector(row) end)
    P.M.TrackRefresh(ui.ctx, RefreshSelected)
    LayoutSelector(row)
    RefreshSelected()
    return row, Choose
end

function E.Begin(ctx)
    local builder = P.W.PageBuilder(ctx)
    local preview = P.ChatPreview.Build(ctx, builder)
    local grouped, ui = P.MenuWorkspace.Builder(ctx, {
        page = PAGE, module = ID, title = "Chat", builder = builder,
        header = preview and preview.header, toolbar = preview and preview.toolbar,
        height = preview and preview.header:GetHeight() or 310,
        tabs = TABS, buildSelector = Selector,
    })
    ctx.chatWorkspace = ui
    return grouped, ui, preview
end

function E.Helpers(ctx, builder, ui)
    local extras = ui and ui.groups.extras.builder or builder
    P.QoLOwners.Build(ctx, extras, PAGE, ui and function() ui.select("extras") end)
    P.BuildOwnedTool(ctx, builder, "keywordAlerts", ui and function() return ui.select("extras") end)
end

function E.Finish(ui, preview)
    P.MenuWorkspace.Finish(ui)
    if not ui or not preview or not ui.tabs then return end
    local function FitNavigation()
        local extra = math.max(0, ui.tabs:GetHeight() - 26)
        if preview.navigationHeight == extra then return end
        preview.navigationHeight = extra
        preview.viewport:ClearAllPoints()
        preview.viewport:SetPoint("TOPLEFT", preview.header, "TOPLEFT", 16, -42 - extra)
        P.ChatPreview.Layout(preview)
    end
    ui.tabs:HookScript("OnSizeChanged", FitNavigation)
    FitNavigation()
end
