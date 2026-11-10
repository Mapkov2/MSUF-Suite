local _, P = ...
local NS, Tr = P.Suite, P.Tr
P.QoLComfortGroups = {
    { id = "questRewardValue", title = "Quest reward value (Forever)", switch = "enabled", sections = { "quest_reward_value" } },
    { id = "mailRecipients", title = "Mail recipients (Retail)", switch = "enabled", sections = { "mail_recipients" } },
    { id = "groupFinderTools", title = "Group finder filters and statistics (Retail)", switch = "enabled",
        sections = { "group_finder_tools", "group_finder_statistics" } },
    { id = "fishingComfort", title = "Fishing comfort (Forever)", switch = "enabled", sections = { "fishing_comfort" } },
    { id = "autoResponses", title = "Automatic responses", switch = "enabled", sections = { "auto_responses" },
        aliases = { "auto accept summon", "auto accept resurrection", "auto decline duel", "decline invites",
            "block duels", "ignore invites", "summon", "resurrect", "duel", "pet battle duel" } },
}
function P.BuildQoLComfortActions(ctx, body, id, section, y, width)
    if id == "dailyComfort" then
        local spec = P.catalog.parallelWindows
        local rules = { spec.rules.enabled, spec.rules.windowLimit }
        local nextY, entries = P.RuleGrid(ctx, body, "suite_qualityOfLife", spec.id, rules, y, width,
            nil, section, 1)
        for _, entry in ipairs(entries) do
            local rule = entry.rule
            local meta = P.Meta("suite_qualityOfLife", spec.id, rule.key, "setting", section)
            meta.pageKey, meta.kind = "suite_qualityOfLife", rule.key == "enabled" and "toggle" or "slider"
            meta.label = Tr(rule.label)
            P.M.RegisterSearchWidget(entry.widget, meta)
        end
        return nextY
    end
    if id == "groupFinderTools" then
        if NS.Client.isForever then return y end
        local button
        button = P.Button(ctx, body, "Choose dungeons", 16, y, width,
            function() P.ComfortDungeonMenu(button) end, function() return not P.Combat() end,
            P.Meta("suite_qualityOfLife", id, "action.dungeons", "action", section))
        return y - 38
    end
    if id == "dungeonPortals" then
        if NS.Client.isForever then return y end
        local button
        button = P.Button(ctx, body, "Choose dungeon portals", 16, y, width,
            function() P.DungeonPortalMenu(button) end, function() return not P.Combat() end,
            P.Meta("suite_qualityOfLife", id, "action.portals", "action", section))
        return y - 38
    end
    if id ~= "fishingComfort" or not NS.Client.isForever then return y end
    local function Add(title, key, fallback)
        local dropdown = P.W.Dropdown(body, Tr(title), {}, width)
        P.W.MoveWidget(dropdown, body, 16, y, width)
        dropdown:SetScript("OnClick", function(self)
            if not P.Combat() then P.ComfortItemMenu(self, id, key, key) end
        end)
        local meta = P.Meta("suite_qualityOfLife", id, "action." .. key, "action", section)
        P.M.RegisterControlMetadata(dropdown, meta, title, "dropdown")
        P.ComfortSelectedItem(ctx, dropdown, id, key, fallback)
        y = y - 58
    end
    local status = P.Text(body, "", 16, y, width, P.T.colors.muted)
    P.M.TrackRefresh(ctx, function()
        local _, _, _, fishing = GetProfessions()
        P.SetTranslatedText(status, NS.Finite(fishing) and "" or Tr("Learn Fishing first."))
    end)
    y = y - 22
    P.Text(body, "For one-key fishing, enable Blizzard's Interact Key under Controls.", 16, y, width, P.T.colors.muted)
    y = y - 34
    Add("Choose fishing rod from bags", "rod", "Equipped fishing rod")
    Add("Choose lure from bag consumables", "lure", "No lure")
    P.Button(ctx, body, "Open fishing key bindings", 16, y, width,
        function() if not P.Combat() then Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID, "MSUF Suite") end end,
        function() return not P.Combat() end,
        P.Meta("suite_qualityOfLife", id, "action.bindings", "action", section))
    return y - 42
end

function P.QoLTitleLess(a, b)
    local left, right = Tr(a.title), Tr(b.title)
    return left == right and a.title < b.title or left < right
end
