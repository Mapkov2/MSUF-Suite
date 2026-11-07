local _, P = ...
local E, PAGE, ID = {}, "suite_chat", "chat"
P.ChatPreviewLinks = E
local TOOL_KEYS = { "headerToolbar", "animateInput", "copyMessages", "toolbarLocked", "look" }

-- Resolve the catalog identity, not a translated label or the current topic.
-- Exact search owns the one scroll; section focus only persists the accordion.
function E.Open(ui, spec)
    local bridge = P.M.SearchBridge
    if not bridge or not bridge.OpenSearchTarget then return false end
    local section = PAGE .. "_" .. spec.section
    local body = ui.ctx.chatSections and ui.ctx.chatSections[section]
    if body then
        local workspace, topic = ui.ctx.chatWorkspace, body._suiteWorkspaceTab
        if workspace and workspace.selected ~= topic then workspace.select(topic) end
        P.EnsureSectionContent(body)
        if P.W.FocusCollapsibleSection then
            P.W.FocusCollapsibleSection(body, { persist = true, flash = false, scroll = false })
        end
    end
    local exact = P.Meta(PAGE, ID, spec.control, "setting", section)
    local called, opened, focused = bridge.OpenSearchTarget(PAGE, "", nil, nil, {}, exact)
    return called == true and opened == true and focused == true
end

local function Link(ui, region, key)
    if not region then return end
    ui.extraLinks = ui.extraLinks or {}
    local handle = ui.extraLinks[region]
    if not handle then
        local rule = P.catalog[ID].rules[key]
        handle = ui.addHandle(ui, region, { control = key, section = rule.section, label = rule.label }, 6)
        ui.extraLinks[region] = handle
    end
    -- FontString visibility does not propagate to a sibling hit frame.
    handle:SetShown(region:IsShown())
end

function E.Refresh(ui)
    local parts = ui.parts
    if parts.toolbar then
        for index, button in ipairs(parts.toolbar.buttons) do Link(ui, button, TOOL_KEYS[index]) end
    end
    Link(ui, parts.resizeGrip, "lockWindowSize")
    Link(ui, parts.visual and parts.visual.headerClock, "headerClock")
end
