-- The nameplate crowd-control switches carry one whole translated label per
-- aura group (Catalog/Nameplates.lua). A label joined from two translated
-- fragments keeps the English word order in every language.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_installer_harness.lua")
local LABELS = {
    enemyNpcControl = "Enemy NPC Crowd control",
    enemyPlayerControl = "Enemy player Loss of control",
    friendlyPlayerControl = "Friendly player Loss of control",
}
local LOCALES = { "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

local Suite = H.Setup({ root = root, forever = true })
for key, english in pairs(LABELS) do
    local rule = assert(Suite.Suite.catalog.nameplates.rules[key], key .. " is missing")
    assert(rule.label == english, key .. " reads " .. tostring(rule.label) .. " in English")
end
for _, locale in ipairs(LOCALES) do
    local L = {}
    Suite = H.Setup({ root = root, forever = true, msuf = { LOCALE = locale, L = L } })
    for key, english in pairs(LABELS) do
        local translated = rawget(L, english)
        assert(type(translated) == "string" and translated ~= english,
            locale .. " has no whole translation of '" .. english .. "'")
        local label = Suite.Suite.catalog.nameplates.rules[key].label
        assert(label == translated, locale .. " " .. key .. " reads '" .. tostring(label) .. "', its translation is '"
            .. translated .. "'")
    end
    assert(#H.reported == 0, "a call raised: " .. tostring(H.reported[1]))
end
print("nameplate aura labels contract: ok")
