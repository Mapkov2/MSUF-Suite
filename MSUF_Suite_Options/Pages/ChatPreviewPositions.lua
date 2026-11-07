local _, P = ...
local R, ID, PAGE = {}, "chat", "suite_chat"
P.ChatPreviewPositions = R
function R.Initialize()
    if R.elements then return end
    R.elements = {
        { prefix = "window", label = "Chat window", section = "window", control = "lockWindowPosition", gate = "lockWindowPosition" },
        { prefix = "messageText", label = "Message text", section = "text", control = "fontSize", followRegion = "lines" },
        { prefix = "tab", label = "Tabs and accent", section = "tabs", control = "tabHeight", region = "tabGroup" },
        { prefix = "input", label = "Input line", section = "input", control = "inputWidth", region = "input" },
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
        if not spec.prefix then return false end
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

-- Coordinate settings keep their identities and reset scope, while their only
-- editing surface is the shared preview selection bar.
function R.CoordinateSection(ctx, builder, section, title, rules, opts)
    local visible, positions = {}, {}
    for _, rule in ipairs(rules) do
        if R.keys[rule.key] then positions[#positions + 1] = rule.key
        else visible[#visible + 1] = rule end
    end
    local options = opts
    if #positions > 0 then
        options = {}
        for key, value in pairs(opts or {}) do options[key] = value end
        options.resetKeys = positions
        for _, key in ipairs(opts and opts.resetKeys or {}) do positions[#positions + 1] = key end
    end
    local body = P.MenuWorkspace.Rules(ctx, builder, PAGE, ID, section, title, visible, options)
    ctx.chatSections = ctx.chatSections or {}
    ctx.chatSections[section] = body
    return body
end

-- Noninteractive anchors preserve individual search identities without
-- constructing a second set of controls, labels or refresh callbacks.
function R.BindSearch(ui)
    for key, spec in pairs(R.keys) do
        local rule = P.catalog[ID].rules[key]
        local target = CreateFrame("Frame", nil, ui.header)
        local axis = key:sub(-1) == "X" and "axisX" or "axisY"
        target:SetAllPoints(ui.selection and ui.selection[axis] or ui.viewport)
        local function Prepare()
            if P.Combat() or not ui.header:IsVisible() or not ui.ctx.wrapper:IsVisible() then return false end
            P.ChatPreview.Select(ui, spec.prefix)
            return true
        end
        local meta = P.Meta(PAGE, ID, key, "setting", PAGE .. "_preview")
        P.HM.SetSearchTargetPrepare(target, Prepare)
        P.RegisterWorkspaceSearch(target, meta, rule, "suiteWorkspace", Prepare, P.Tr(rule.label))
    end
end

local function ResolvePosition(page, target)
    if page ~= PAGE or not target then return end
    R.Initialize()
    local key = (target.settingKey or ""):match("^msufsuite%.chat%.(.+)$")
    if not key and target.controlId then
        for candidate in pairs(R.keys) do
            if P.Meta(PAGE, ID, candidate, "setting").controlId == target.controlId then key = candidate break end
        end
    end
    if not R.keys[key] then return end
    local prepared = {}
    for name, value in pairs(target) do prepared[name] = value end
    prepared.controlId = P.Meta(PAGE, ID, key, "setting").controlId
    prepared.settingKey, prepared.sectionId = "msufsuite.chat." .. key, PAGE .. "_preview"
    prepared.prepareKind, prepared.prepareValue = "suiteWorkspace", key
    return page, prepared
end
P.Suite.HostBridge.RegisterSearchTargetResolver(P.M, "MSUF_Suite.ChatPosition", ResolvePosition)
