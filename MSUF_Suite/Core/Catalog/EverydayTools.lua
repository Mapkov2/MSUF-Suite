local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
local PAGES = { keyAudit = "suite_actionbars", currencyGoals = "suite_bags", keywordAlerts = "suite_chat" }
local function Module(id, title, description)
    B.Module(id, { title = title, description = description, optIn = true,
        defaultEnabled = false, page = PAGES[id] or "suite_qualityOfLife" })
end
Module("keyAudit", "Action and key review", "Review action slots, missing key bindings and overridden keys without changing your bindings.")
B.Section("keyAudit", "key_review", "Action and key review", {
    B.Bool("onlyIssues", "Show only entries that need review", false),
})
Module("currencyGoals", "Currency goals", "Choose a currency, set a target and receive one notice when you reach it or approach its cap.")
B.Section("currencyGoals", "currency_goals", "Currency goals", {
    B.Bool("notifyGoal", "Notify when a currency goal is reached", true),
    B.Bool("notifyCap", "Notify when near a currency cap", true),
    B.Number("capPercent", "Currency cap warning (percent)", 90, 50, 100, 5),
})
Module("keywordAlerts", "Chat keyword notices", "Watch chosen words in selected chat channels. Private game values are never read.")
B.Section("keywordAlerts", "keyword_notices", "Chat keyword notices", {
    B.String("words", "Words or phrases, one per line", "", 6500),
    B.Bool("party", "Watch party chat", true), B.Bool("raid", "Watch raid chat", true),
    B.Bool("guild", "Watch guild chat"), B.Bool("say", "Watch nearby chat"),
    B.Bool("channels", "Watch public channels"),
    B.Number("cooldown", "Seconds between notices for the same phrase", 30, 5, 300, 5),
    B.Bool("sound", "Play a sound for matching messages"),
})
NS.SuiteCatalog.keywordAlerts.rules.words.hidden = true
Module("waypointLists", "Saved waypoint lists", "Save named map points and activate the next stop with a click. No movement is automated.")
B.Section("waypointLists", "saved_waypoints", "Saved waypoint lists", {
    B.Bool("superTrack", "Track the selected saved waypoint", true),
})
Module("soundProfiles", "Context sound profiles",
    "Choose volumes for each activity. Turning this off restores the previous volumes when they are still owned by MSUF.")
NS.SuiteCatalog.soundProfiles.cvars = {
    Sound_MusicVolume = true, Sound_AmbienceVolume = true, Sound_SFXVolume = true,
}
-- Muting sound files needs no volume profile: this switch stays on for
-- everyone who used the helper before it existed.
B.Section("soundProfiles", "sound_volumes", "Volume profiles", {
    B.Bool("applyVolumes", "Apply volume profiles", true),
})
-- Battlegrounds and arenas keep the player's own volumes until their profile
-- is switched on (the key pvpProfile, SoundProfiles.lua).
local SOUND_AREAS = {
    { "world", "Open world" }, { "party", "Dungeon" }, { "raid", "Raid" },
    { "pvp", "Battleground and arena", B.Bool("pvpProfile", "Use a profile in battlegrounds and arenas") },
}
for _, area in ipairs(SOUND_AREAS) do
    local rules = {
        B.Number(area[1] .. "Music", "Music volume (percent)", 30, 0, 100, 5),
        B.Number(area[1] .. "Ambience", "Ambience volume (percent)", 50, 0, 100, 5),
        B.Number(area[1] .. "Effects", "Effects volume (percent)", 100, 0, 100, 5),
    }
    if area[3] then table.insert(rules, 1, area[3]) end
    B.Section("soundProfiles", "sound_" .. area[1], area[2], rules)
end
do
    local rules = NS.SuiteCatalog.soundProfiles.rules
    for _, area in ipairs(SOUND_AREAS) do
        local switch = area[3] and area[3].key or "applyVolumes"
        for _, suffix in ipairs({ "Music", "Ambience", "Effects" }) do rules[area[1] .. suffix].enableKey = switch end
    end
    rules.pvpProfile.enableKey = "applyVolumes"
end
-- FileDataIDs handed to MuteSoundFile while the helper runs (SoundProfiles.lua).
local mutedFiles = B.String("mutedFileIDs", "Sound file IDs to mute (separated by commas)", "", 2000)
mutedFiles.ids = true
B.Section("soundProfiles", "sound_files", "Muted sound files", {
    B.Tooltip(mutedFiles, "Silences these game sound files, such as a mount or summon sound, while this helper is on. Remove an ID to hear that sound again."),
})
-- The history runs in the shared runtime addon (MSUF_Suite_Modules/SuiteNotices.lua);
-- naming Quality of Life here would load that whole addon for it.
local Shared = NS.CatalogBuild.ForAddon("MSUF_Suite_Modules")
Shared.Module("notificationHistory", { title = "Suite notice history",
    description = "Keep a bounded local history of Suite notices, combine repeats and open the related settings.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife" })
Shared.Section("notificationHistory", "notice_history", "Suite notice history", {
    Shared.Number("limit", "Maximum saved notices", 60, 10, 100, 10),
    Shared.Number("mergeSeconds", "Combine repeated notices within (seconds)", 60, 5, 300, 5),
})
