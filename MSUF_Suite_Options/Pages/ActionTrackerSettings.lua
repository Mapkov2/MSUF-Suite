local _, P = ...
local ID = "actionTracker"
local TABS = {
    { "appearance", "Appearance" },
    { "layout", "Layout" },
    { "text", "Text" },
    { "visibility", "Visibility" },
}
local LAYOUT = {
    rows = true, width = true, rowHeight = true, rowGap = true, growth = true, scale = true,
    insertAnimation = true, showHeader = true,
}
local TEXT = {
    showNames = true, font = true, fontSize = true, fontOutline = true, fontRendering = true,
    fontShadow = true, fontShadowOpacity = true, fontShadowDistance = true,
}
local VISIBILITY = { hideAfter = true, pauseInCombat = true }

local function GroupRules(sections)
    local groups = { appearance = {}, layout = {}, text = {}, visibility = {}, instances = {} }
    for _, section in ipairs(sections) do
        for _, rule in ipairs(section.rules) do
            local group = section.key == "action_tracker_visibility" and "instances" or VISIBILITY[rule.key] and "visibility"
                or LAYOUT[rule.key] and "layout" or TEXT[rule.key] and "text" or "appearance"
            local rules = groups[group]
            rules[#rules + 1] = rule
        end
    end
    return groups
end

local function BuildPanel(ctx, panel, width, page, section, groups, key, register, prepare)
    local bottom, entries = P.RuleGrid(ctx, panel, page, ID, groups[key], 0, width, nil, section, nil, nil, true)
    register(entries, prepare)
    if key == "visibility" and #groups.instances > 0 then
        local title = P.Text(panel, "Where to show recent actions", 16, bottom - 8, width)
        bottom = bottom - math.max(16, math.ceil(title:GetStringHeight() or 16)) - 16
        bottom, entries = P.RuleGrid(ctx, panel, page, ID, groups.instances, bottom, width, nil, section, nil, nil, true)
        register(entries, prepare)
    end
    panel:SetHeight(math.max(1, -bottom))
end

function P.BuildActionTrackerSettings(ctx, body, y, width, page, section, sections, register, resize)
    local groups = GroupRules(sections)
    local values, panels = {}, {}
    local choose
    for _, tab in ipairs(TABS) do
        local key = tab[1]
        local panel = CreateFrame("Frame", nil, body)
        panel:SetWidth(width + 32)
        panels[key] = panel
        values[#values + 1] = { value = key, text = P.Tr(tab[2]) }
        BuildPanel(ctx, panel, width, page, section, groups, key, register, function() choose(key) end)
    end
    local bottom
    bottom, choose = P.MenuWorkspace.FeatureTabs(ctx, body, page, ID, width, y, values, panels, resize)
    return bottom, choose
end
