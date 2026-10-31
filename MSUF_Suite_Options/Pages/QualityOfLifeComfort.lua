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
    local function Add(title, key, kind, fallback)
        local button
        button = P.Button(ctx, body, title, 16, y, width,
            function() P.ComfortItemMenu(button, id, key, kind) end,
            function() return not P.Combat() end, P.Meta("suite_qualityOfLife", id, "action." .. key, "action", section))
        P.ComfortSelectedItem(ctx, body, button, id, key, fallback, y - 28, width)
        y = y - 58
    end
    local status = P.Text(body, "", 16, y, width, P.T.colors.muted)
    P.M.TrackRefresh(ctx, function()
        local _, _, _, fishing = GetProfessions()
        P.SetTranslatedText(status, NS.Finite(fishing) and "" or Tr("Learn Fishing first."))
    end)
    y = y - 22
    Add("Choose fishing rod from bags", "rod", "rod", "Equipped fishing rod")
    Add("Choose lure from bag consumables", "lure", "lure", "No lure")
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
