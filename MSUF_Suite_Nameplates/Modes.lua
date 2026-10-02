local _, private = ...
-- Choice values of the Nameplates settings (MSUF_Suite/Core/Catalog/
-- Nameplates.lua). The Blizzard rules list "Keep Blizzard setting" first,
-- then Show (or On, Customize, Custom) and Hide (or Off).
private.Mode = {
    KEEP = 1, SHOW = 2, CUSTOMIZE = 2, HIDE = 3,
    -- look: Jundies, Blizzard, Custom, Mapko.
    LOOK_BLIZZARD = 2,
    -- barGeometry: Client default, Same on Retail and Forever.
    SAME_GEOMETRY = 2,
    -- levelAppearance (Forever only): Level number, Blizzard badge.
    LEVEL_BADGE = 2,
    -- friendlyNamesOnly: Keep, Names only (all friendly players), Names only
    -- (party / raid), Health bars.
    ALL_NAMES_ONLY = 2, GROUP_NAMES_ONLY = 3,
}
