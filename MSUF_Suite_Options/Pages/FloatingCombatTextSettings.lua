local _, P = ...
local ID = "floatingCombatText"
local TABS = {
    { "appearance", "Appearance" },
    { "hits", "Enemy hits" },
    { "gains", "Gains and notifications" },
    { "combat", "Combat" },
}
local SECTION_TAB = {
    floating_combat_text = "appearance",
    floating_combat_text_hits = "hits",
    floating_combat_text_gains = "gains",
}
local BLIZZARD = { hideBlizzard = true, hideBlizzardWorldText = true }
local COMBAT = { showCombatState = true, combatSide = true, combatColor = true }
local GAINS = { "showXP", "showLevelUp", "showReputation", "showHonor", "showPower" }

local function GroupRules(sections)
    local groups = { appearance = {}, hits = {}, gains = {}, combat = {}, blizzard = {} }
    for _, section in ipairs(sections) do
        for _, rule in ipairs(section.rules) do
            local tab = BLIZZARD[rule.key] and "blizzard" or COMBAT[rule.key] and "combat"
                or SECTION_TAB[section.key] or "appearance"
            local rules = groups[tab]
            rules[#rules + 1] = rule
        end
    end
    return groups
end

local function CanSetGain(key, enabled)
    return P.Get(ID, key) ~= enabled and P.RuleEnabled(ID, P.catalog[ID].rules[key], nil, false, true)
end

local function AddGainActions(view, panel, y)
    local width = (view.width - 8) / 2
    for index, label in ipairs({ "Enable all", "Disable all" }) do
        local enabled = index == 1
        local function CanSet()
            for _, key in ipairs(GAINS) do
                if CanSetGain(key, enabled) then return true end
            end
            return false
        end
        local function Set()
            if P.Combat() then return end
            local values = {}
            for _, key in ipairs(GAINS) do
                if CanSetGain(key, enabled) then values[key] = enabled end
            end
            if next(values) then P.SetMany(ID, values) end
        end
        local button = P.Button(view.ctx, panel, label, 16 + (index - 1) * (width + 8), y, width, Set, CanSet)
        local worldText = P.catalog[ID].rules.hideBlizzardWorldText
        if not enabled and worldText then
            P.M.AddTooltip(button, P.Tr(worldText.label), P.Tr(worldText.tooltip), {
                hook = true, enabled = function() return P.Get(ID, worldText.key) end,
            })
        end
    end
    return y - 36
end

local function Grid(view, panel, rules, y, prepare)
    local bottom, entries = P.RuleGrid(view.ctx, panel, view.page, ID, rules, y,
        view.width, nil, view.section, nil, nil, true)
    view.register(entries, prepare)
    return bottom
end

local function BuildPanel(view, panel, key, groups, preview, prepare)
    local y = 0
    if preview and preview.BuildSamples then y = preview.BuildSamples(panel, key, y) end
    if key == "gains" then y = AddGainActions(view, panel, y) end
    y = Grid(view, panel, groups[key], y, prepare)
    panel:SetHeight(math.max(1, -y))
end

local function BuildBlizzardSettings(view, body, panels, rules, prepare)
    if #rules == 0 then return end
    -- Both tabs display the same bound widgets. Exact search still opens Enemy hits.
    local blizzard = CreateFrame("Frame", nil, body)
    blizzard:SetWidth(view.width + 32)
    local title = P.Text(blizzard, "Blizzard", 16, -8, view.width)
    local y = -math.max(16, math.ceil(title:GetStringHeight() or 16)) - 16
    local height = -Grid(view, blizzard, rules, y, prepare)
    blizzard:SetHeight(height)

    local offsets = { hits = -panels.hits:GetHeight(), gains = -panels.gains:GetHeight() }
    for key, top in pairs(offsets) do panels[key]:SetHeight(height - top) end
    return function(key)
        local top = offsets[key]
        if top then
            blizzard:ClearAllPoints()
            blizzard:SetPoint("TOPLEFT", panels[key], "TOPLEFT", 0, top)
        end
        blizzard:SetShown(top ~= nil)
    end
end

function P.BuildFloatingCombatTextSettings(ctx, body, y, width, page, section, sections, preview, register, resize)
    local view = { ctx = ctx, width = width, page = page, section = section, register = register }
    local groups = GroupRules(sections)
    local values, panels = {}, {}
    local choose
    for _, tab in ipairs(TABS) do
        local key = tab[1]
        local panel = CreateFrame("Frame", nil, body)
        panel:SetWidth(width + 32)
        panels[key] = panel
        values[#values + 1] = { value = key, text = P.Tr(tab[2]) }
        BuildPanel(view, panel, key, groups, preview, function() choose(key) end)
    end
    local selectBlizzard = BuildBlizzardSettings(view, body, panels, groups.blizzard, function() choose("hits") end)

    local bottom
    bottom, choose = P.MenuWorkspace.FeatureTabs(ctx, body, page, ID, width, y, values, panels, resize, selectBlizzard)
    return bottom
end
