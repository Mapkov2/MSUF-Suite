-- Nameplate health value in the preview. Live plates show Blizzard's own text:
-- Blizzard_NamePlateUnitFrame:UpdateAnchors (live and forever) places it per
-- name style, Layout.lua only offsets it, and TextStatusBar abbreviates it with
-- AbbreviateLargeNumbers. The preview must start at the same point and format.
local root = assert(arg[1], "Suite root required")

local values = { enemyHealthTextOffsetX = -6, enemyHealthTextOffsetY = -14 }
local P = {
    M = { PreviewSelectionBar = {} }, W = {},
    Suite = { Public = function(value) return value ~= "secret" end },
}
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/NameplatesPreviewLayout.lua"))("MSUF_Suite_Options", P)
local Layout = assert(P.NameplatesPreviewLayout)

-- nameAnchor (1 inside, 2 above, 3 centered above), Forever's inside flag,
-- classic health bar -> native point, relative point, x, y on the health bar.
local NATIVE = {
    { 1, nil, false, "RIGHT", "RIGHT", -4, 0 },
    { 1, true, false, "RIGHT", "RIGHT", -4, 0 },
    { 2, nil, false, "BOTTOMRIGHT", "TOPRIGHT", -4, 2 },
    { 2, false, false, "BOTTOMRIGHT", "TOPRIGHT", -4, 2 },
    { 2, true, false, "RIGHT", "RIGHT", -4, 0 },
    { 3, nil, true, "RIGHT", "RIGHT", -4, -.5 },
    { 3, nil, false, "RIGHT", "RIGHT", -4, 0 },
}
for _, case in ipairs(NATIVE) do
    local point, relative, x, y = Layout.HealthTextAnchor(case[1], case[2], case[3])
    assert(point == case[4] and relative == case[5] and x == case[6] and y == case[7],
        ("native health text anchor diverged for style %d: %s %s %s %s"):format(case[1],
            tostring(point), tostring(relative), tostring(x), tostring(y)))
end

local function Region()
    local region = {}
    function region:ClearAllPoints() self.point = nil end
    function region:SetPoint(...) self.point = { ... } end
    function region:SetWidth(width) self.width = width end
    function region:SetJustifyH(value) self.justifyH = value end
    function region:SetJustifyV(value) self.justifyV = value end
    return region
end
-- The preview's own helpers, as NameplatesPreview.lua passes them.
local function SetupToggle(key, fallback)
    local value = NamePlateSetupOptions[key]
    if P.Suite.Public(value) and type(value) == "boolean" then return value end
    return fallback
end
local function Place(s, frame, point, owner, relative, x, y, key)
    frame:ClearAllPoints()
    if key and not s.metrics.skinDisabled then
        x = x + values[s.prefix .. key .. "OffsetX"]
        y = y + values[s.prefix .. key .. "OffsetY"]
    end
    frame:SetPoint(point, owner, relative, x, y)
end

-- The saved offsets move the live text from its native point; the preview
-- must land on the same point plus the same offsets for every name style.
for _, forever in ipairs({ false, true }) do
    for _, case in ipairs(NATIVE) do
        NamePlateSetupOptions = { unitNameAnchorStyle = case[1], useClassicHealthBar = case[3] }
        if forever then NamePlateSetupOptions.healthTextInsideBarWhenNameAboveHealthBar = case[2] == true end
        local m = { nameAnchor = case[1], classic = false, skinDisabled = false }
        local s = { prefix = "enemy", metrics = m, bar = Region(), healthText = Region(), value = Region() }
        Layout.PlaceHealthText(s, m, SetupToggle, Place)
        local point = s.healthText.point
        local inside = forever and case[2] == true
        local wantPoint, wantRelative, wantY = case[4], case[5], case[7]
        if case[1] == 2 and not inside then wantPoint, wantRelative, wantY = "BOTTOMRIGHT", "TOPRIGHT", 2 end
        assert(point[1] == wantPoint and point[2] == s.bar and point[3] == wantRelative
            and point[4] == -4 + values.enemyHealthTextOffsetX and point[5] == wantY + values.enemyHealthTextOffsetY,
            ("preview health text left the live position (style %d, forever %s): %s %s %s %s"):format(
                case[1], tostring(forever), tostring(point[1]), tostring(point[3]), tostring(point[4]), tostring(point[5])))
        assert(s.value.justifyV == (wantPoint == "BOTTOMRIGHT" and "BOTTOM" or "MIDDLE"),
            "preview value text is not aligned to its native edge")
    end
end
-- A restricted setup value falls back to the client's own default (outside).
NamePlateSetupOptions = { unitNameAnchorStyle = 2, healthTextInsideBarWhenNameAboveHealthBar = "secret" }
local s = { prefix = "enemy", metrics = { skinDisabled = false }, bar = Region(), healthText = Region(), value = Region() }
Layout.PlaceHealthText(s, { nameAnchor = 2, classic = false }, SetupToggle, Place)
assert(s.healthText.point[1] == "BOTTOMRIGHT", "a secret setup flag moved the health text into the bar")
-- A disabled skin ignores the saved offsets, as the live Blizzard plate does.
s.metrics.skinDisabled = true
Layout.PlaceHealthText(s, { nameAnchor = 2, classic = false }, SetupToggle, Place)
assert(s.healthText.point[4] == -4 and s.healthText.point[5] == 2, "disabled skin applied saved offsets")

-- The sample value uses the live formatter, once per sample percent.
local calls = {}
AbbreviateLargeNumbers = function(value)
    calls[#calls + 1] = value
    return value .. " K"
end
assert(Layout.HealthValue(53) == "1855000 K" and Layout.HealthValue(53) == "1855000 K" and #calls == 1,
    "the sample value bypassed or repeated Blizzard's abbreviation")
assert(Layout.HealthValue(100) == "3500000 K" and #calls == 2)

-- The preview renders through these helpers and invents no number format.
local file = assert(io.open(root .. "/MSUF_Suite_Options/Pages/NameplatesPreview.lua", "rb"))
local source = file:read("*a")
file:close()
assert(source:find("P.NameplatesPreviewLayout.PlaceHealthText(s, m, SetupToggle, Place)", 1, true)
    and source:find("P.NameplatesPreviewLayout.HealthValue(health)", 1, true),
    "the preview no longer places or formats the health value like the live plate")
assert(not source:find("%.1fM", 1, true), "the preview still invents its own number format")

print("Nameplate health text preview: native anchors, Forever inside flag, offsets and live number format passed")
