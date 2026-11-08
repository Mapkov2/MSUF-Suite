local _, NS = ...
-- Shared identities for the runtime painter, settings and preview handles.
local Layout = { Texts = {}, ByID = {} }
NS.ExperienceBarLayout = Layout
local function Text(id, region, label, point, relative, x, y, toggle)
    local spec = { id = id, region = region, prefix = region, label = label,
        point = point, relative = relative, x = x, y = y, toggle = toggle }
    Layout.Texts[#Layout.Texts + 1] = spec
    Layout.ByID[id] = spec
end
Text("level", "levelText", "Level text", "LEFT", "LEFT", 6, 0)
Text("xp", "xpText", "Current XP", "LEFT", "LEFT", 50, 0)
Text("percent", "percentText", "Percentage", "RIGHT", "RIGHT", -6, 0)
Text("session", "sessionText", "Session XP", "TOPLEFT", "BOTTOMLEFT", 6, -4, "showSession")
Text("rate", "rateText", "XP per hour", "TOP", "BOTTOM", 0, -4, "showRate")
Text("eta", "etaText", "Time to level", "TOPRIGHT", "BOTTOMRIGHT", -6, -4, "showETA")
Text("levelTime", "levelTimeText", "Time played this level", "TOPRIGHT", "BOTTOMRIGHT", -6, -18, "showLevelTime")

function Layout.BottomPadding(config)
    return config.showLevelTime and 33 or 23
end

Layout.Points = {
    TOPLEFT = { 0, 1 }, TOP = { .5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, .5 }, CENTER = { .5, .5 }, RIGHT = { 1, .5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { .5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
