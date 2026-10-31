local _, P = ...
local NS, S = P.Suite, P.S
P.EverydayToolGroups = {
    { id = "keyAudit", title = "Action and key review", switch = "enabled", sections = { "key_review" } },
    { id = "currencyGoals", title = "Currency goals", switch = "enabled", sections = { "currency_goals" } },
    { id = "keywordAlerts", title = "Chat keyword notices", switch = "enabled", sections = { "keyword_notices" } },
    { id = "waypointLists", title = "Saved waypoint lists", switch = "enabled", sections = { "saved_waypoints" } },
    { id = "soundProfiles", title = "Context sound profiles", switch = "enabled",
        sections = { "sound_volumes", "sound_world", "sound_party", "sound_raid", "sound_pvp", "sound_files" },
        aliases = { "mute sound", "mute sound file", "silence sound", "sound file id" } },
    { id = "notificationHistory", title = "Suite notice history", switch = "enabled", sections = { "notice_history" } },
}
local ACTIONS = {
    keyAudit = "Review actions and keys", currencyGoals = "Manage currency goals", keywordAlerts = "Edit watched phrases",
    waypointLists = "Open saved waypoint lists", notificationHistory = "Open notice history",
}
function P.BuildEverydayToolActions(ctx, body, id, section, y, width)
    local title = ACTIONS[id]
    if not title then return y end
    P.Button(ctx, body, title, 16, y, width, function()
        local owner = S.instances[id]
        if not P.Combat() and owner and owner.active then owner:Open() end
    end, function() return not P.Combat() and S.instances[id] and S.instances[id].active == true end,
        P.Meta(P.catalog[id].page, id, "action.open", "action", section))
    P.Text(body, "Enable this helper above to open its tools.", 16, y - 28, width, P.T.colors.muted)
    return y - 55
end
