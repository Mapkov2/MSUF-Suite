local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_Nameplates")
B.Section("nameplates", "sharing", "Profile Blizzard settings", {
    B.Choice("nativeProfileMode", "Blizzard settings when switching profiles", 1,
        { "Use this profile's Blizzard settings", "Keep current Blizzard settings" }),
})
