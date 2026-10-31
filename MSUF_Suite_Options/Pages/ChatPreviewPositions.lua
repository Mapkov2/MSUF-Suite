local _, P = ...
local R, ID, PAGE = {}, "chat", "suite_chat"
P.ChatPreviewPositions = R
function R.Initialize()
    if R.elements then return end
    R.elements = {
        { prefix = "window", label = "Chat window", section = "window", control = "lockWindowPosition", gate = "lockWindowPosition" },
        { prefix = "messageText", label = "Message text", section = "text", control = "messageTextX", region = "textHit", followRegion = "lines" },
        { prefix = "tab", label = "Tabs and accent", section = "tabs", control = "tabX", region = "tabGroup" },
        { prefix = "input", label = "Input line", section = "input", control = "inputX", region = "input" },
        { prefix = "copyButton", label = "Copy", section = "tools", control = "copyMessages", gate = "copyMessages" },
    }
    local ICON_LABELS = { "Friends", "Channels and voice", "Text to speech", "Chat menu", "Newest messages" }
    for index, label in ipairs(ICON_LABELS) do
        R.elements[#R.elements + 1] = { prefix = "sidebarButton" .. index, label = label, section = "sidebar",
            control = "sidebarButton" .. index .. "Moved", gate = "sidebarPanel", icon = index }
    end
    R.keys = {}
    for _, spec in ipairs(R.elements) do
        R.keys[spec.prefix .. "X"], R.keys[spec.prefix .. "Y"] = spec, spec
    end

    function R.Allowed(spec)
        local rule = P.catalog[ID].rules[spec.gate or spec.prefix .. "X"]
        return not P.Combat() and (not spec.gate or P.Get(ID, spec.gate) == true)
            and P.RuleEnabled(ID, rule)
            and (not spec.icon or P.Get(ID, "panelAlpha") > 0)
    end

    function R.Read(ui, spec)
        if not spec.prefix then return 0, 0 end
        if spec.icon and not P.Get(ID, spec.prefix .. "Moved") then
            local region, sidebar = ui.parts.icons[spec.icon], ui.parts.sidebar
            local x, y = region:GetCenter()
            local sx, sy = sidebar:GetCenter()
            if P.Suite.Finite(x) and P.Suite.Finite(y) and P.Suite.Finite(sx) and P.Suite.Finite(sy) then return x - sx, y - sy end
        end
        return P.Get(ID, spec.prefix .. "X"), P.Get(ID, spec.prefix .. "Y")
    end

    function R.Write(spec, x, y)
        if not R.Allowed(spec) or not P.Suite.Finite(x) or not P.Suite.Finite(y) then return false end
        local rules, values = P.catalog[ID].rules, {}
        for axis, value in pairs({ X = x, Y = y }) do
            local key = spec.prefix .. axis
            values[key] = math.max(rules[key].min, math.min(rules[key].max, math.floor(value + .5)))
        end
        if spec.icon then values[spec.prefix .. "Moved"] = true end
        return P.SetMany(ID, values)
    end

    function R.Reset(spec)
        if not R.Allowed(spec) then return false end
        local rules, prefix = P.catalog[ID].rules, spec.prefix
        local values = { [prefix .. "X"] = rules[prefix .. "X"].default, [prefix .. "Y"] = rules[prefix .. "Y"].default }
        if spec.icon then values[prefix .. "Moved"] = false end
        return P.SetMany(ID, values)
    end

end

-- Keep every catalog/reset/search identity. Only the numeric presentation
-- changes: exact inputs replace coordinate sliders in their original section.
function R.CoordinateSection(ctx, builder, section, title, rules, opts)
    local function Input(ctx, body, rule, section, x, y, width)
        local spec = R.keys[rule.key]
        local current, config = P.ProfileGuard(), P.S.Config(ID)
        local input = P.M.BindTextInputAt(ctx, body, P.Tr(rule.label), x, y, width,
            function() return tostring(P.Get(ID, rule.key)) end,
            function(text)
                if not current or not current() or config ~= P.S.Config(ID) or not body:IsVisible() then return end
                local value = tonumber(text)
                if not P.Suite.Finite(value) or not P.RuleEnabled(ID, rule) then return end
                local vx, vy = P.Get(ID, spec.prefix .. "X"), P.Get(ID, spec.prefix .. "Y")
                if rule.key == spec.prefix .. "X" then vx = value else vy = value end
                R.Write(spec, vx, vy)
            end, true, P.Meta(PAGE, ID, rule.key, "setting", section))
        input:HookScript("OnEditFocusGained", function() current, config = P.ProfileGuard(), P.S.Config(ID) end)
        input:HookScript("OnHide", function() current = nil end)
        P.HM.SetSearchTargetPrepare(input, function()
            if ctx.chatPreviewUI then P.ChatPreview.Select(ctx.chatPreviewUI, spec.prefix) end
            return true
        end)
        P.HM.SkipHistoryCheckpoint(input)
        return { rule = rule, widget = input }
    end

    local visible, positions = {}, {}
    for _, rule in ipairs(rules) do
        if R.keys[rule.key] then positions[#positions + 1] = rule
        else visible[#visible + 1] = rule end
    end
    ctx.chatSections = ctx.chatSections or {}
    if #positions == 0 then
        local body = P.RuleSection(ctx, builder, PAGE, ID, section, title, rules, opts)
        ctx.chatSections[section] = body
        return body
    end
    local options = {}
    for key, value in pairs(opts or {}) do options[key] = value end
    local extra = options.extra
    options.resetKeys = {}
    for _, rule in ipairs(positions) do options.resetKeys[#options.resetKeys + 1] = rule.key end
    options.extra = function(body, y, width)
        local entries, columns = {}, width >= 420 and 2 or 1
        local cell = (width - (columns - 1) * 16) / columns
        for index, rule in ipairs(positions) do
            local slot = index - 1
            entries[#entries + 1] = Input(ctx, body, rule, section, 16 + (slot % columns) * (cell + 16),
                y - math.floor(slot / columns) * 58, cell)
        end
        P.GateControls(ctx, ID, entries)
        y = y - math.ceil(#positions / columns) * 58
        return extra and extra(body, y, width) or y
    end
    local body = P.RuleSection(ctx, builder, PAGE, ID, section, title, visible, options)
    ctx.chatSections[section] = body
    return body
end
