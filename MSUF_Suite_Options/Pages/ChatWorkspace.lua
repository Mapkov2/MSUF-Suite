local _, P = ...
local E = {}
P.ChatWorkspace = E
local PAGE, ID = "suite_chat", "chat"

-- One persistent preview; only the selected topic's sections are visible.
local TABS = {
    { id = "basics", label = "Basics", sections = "chat_module window chatComfort_module" },
    { id = "appearance", label = "Appearance", sections = "look tabs sidebar bubbles" },
    { id = "input", label = "Input line", sections = "input" },
    { id = "messages", label = "Messages",
        sections = "tools historyRules spamFilterRules text sounds highlight keywordAlerts_module" },
}

function E.Begin(ctx)
    local builder = P.W.PageBuilder(ctx)
    local preview = P.ChatPreview.Build(ctx, builder)
    local grouped, ui = P.MenuWorkspace.Builder(ctx, {
        page = PAGE, module = ID, title = "Chat", builder = builder,
        header = preview and preview.header, toolbar = preview and preview.toolbar,
        height = preview and preview.header:GetHeight() or 310,
        tabs = TABS, buildSelector = P.MenuWorkspace.WrappingTabs,
    })
    ctx.chatWorkspace = ui
    return grouped, ui, preview
end

function E.Helpers(ctx, builder, ui)
    local messages = ui and ui.groups.messages.builder or builder
    local reveal = ui and function() return ui.select("messages") end
    P.QoLOwners.Build(ctx, messages, PAGE, reveal)
    P.BuildOwnedTool(ctx, builder, "keywordAlerts", reveal)
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
