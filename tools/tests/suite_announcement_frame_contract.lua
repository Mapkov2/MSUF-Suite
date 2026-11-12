-- The announcement banner's frame (MSUF_Suite/Core/AnnouncementArt.lua and
-- MSUF_Suite/Core/Catalog/HUD.lua): its own switch beside the artwork, its
-- shapes, thickness, opacity and color sources, the artwork opacity, and
-- profiles saved before the frame had a switch.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
MSUF_NS = {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
InCombatLockdown = function() return false end
local Suite = Support.Load(root, "MSUF_Suite", {}, "Core/Suite.lua")
local Art = assert(Suite.AnnouncementArt, "AnnouncementArt did not load")
local spec = Suite.SuiteCatalog.announcements
local rules = spec.rules
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

------------------------------------------------------------------ catalog
for key, expected in pairs({
    showFrame = { true }, frameStyle = { 1, 1, 3 }, frameThickness = { 1, 1, 4 }, frameOpacity = { 48, 5, 100 },
    frameColorSource = { 1, 1, 3 }, frameColor = { "f5cf70" }, artOpacity = { 100, 10, 100 },
}) do
    local rule = rules[key]
    Check(rule and rule.default == expected[1] and rule.min == expected[2] and rule.max == expected[3],
        "banner setting " .. key .. " has the wrong default or range")
end
Check(rules.showFrame.section == "frame" and rules.frameColor.section == "frame" and rules.artOpacity.section == "artwork",
    "the frame settings left their accordion")
-- The frame switch is independent of the artwork switch; the frame's own
-- settings wait for it, the custom color for its source.
Check(rules.showFrame.enableKey == nil and rules.artOpacity.enableKey == "showBoxArt",
    "the frame switch depends on the artwork switch")
for _, key in ipairs({ "frameStyle", "frameThickness", "frameOpacity", "frameColorSource", "frameColor" }) do
    Check(rules[key].enableKey == "showFrame", key .. " stays editable with the frame off")
end
Check(rules.frameColor.requiresChoice.key == "frameColorSource" and rules.frameColor.requiresChoice.values[3]
    and not rules.frameColor.requiresChoice.values[1], "the custom frame color is editable for the gold frame")
Check(rules.showBoxArt.tooltip and rules.showBoxArt.tooltip:find("own switch", 1, true),
    "the artwork switch does not say that the frame has its own")
-- A frame color edit must not turn every announcement color custom.
Check(spec.look.visualKeys.frameColor == nil and spec.look.visualKeys.zoneColor,
    "the frame color still switches the announcement color source")
-- Profiles saved before the switch: artwork off hid the frame too.
local legacy = { showBoxArt = false }
spec.prepareConfig(legacy)
Check(legacy.showFrame == false, "a saved banner without artwork got its frame back")
local shown = { showBoxArt = true }
spec.prepareConfig(shown)
Check(shown.showFrame == nil, "the carry-over touched a banner with artwork")
local chosen = { showBoxArt = false, showFrame = true }
spec.prepareConfig(chosen)
Check(chosen.showFrame == true, "the carry-over overwrote a chosen frame")

------------------------------------------------------------------ artwork
C_Texture = { GetAtlasInfo = function() return {} end }
-- Textures and font strings alike: each records what was drawn.
local function Texture(layer)
    local texture = { layer = layer, shown = true, points = {} }
    function texture:SetPoint(point, x, y)
        self.x, self.y = x, y
        self.points[point] = { x, y }
    end
    function texture:ClearAllPoints() self.x, self.y, self.points = nil, nil, {} end
    function texture:SetJustifyH(value) self.justify = value end
    function texture:SetWordWrap(value) self.wrap = value end
    function texture:SetText(value) self.text = value end
    function texture:SetTextColor(r, g, b) self.textColor = { r, g, b } end
    function texture:SetSize(width, height) self.width, self.height = width, height end
    function texture:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function texture:SetAtlas(atlas) self.atlas = atlas end
    function texture:SetAlpha(alpha) self.alpha = alpha end
    function texture:Show() self.shown = true end
    function texture:Hide() self.shown = false end
    function texture:SetShown(value) self.shown = value and true or false end
    return texture
end
local art = Art.Create({}, function(_, _, layer) return Texture(layer) end, function(_, _, layer) return Texture(layer) end)
local function Edges()
    local list = {}
    for _, edge in ipairs(art.border) do
        if edge.shown then list[#list + 1] = { edge.x, edge.y, edge.width, edge.height } end
    end
    return list
end
local function SameRects(actual, expected, message)
    Check(#actual == #expected, message .. ": " .. #actual .. " edges")
    for index, rect in ipairs(expected) do
        for field = 1, 4 do
            Check(actual[index][field] == rect[field], message .. ": edge " .. index .. " field " .. field)
        end
    end
end
local function Color(edge) return edge.color[1], edge.color[2], edge.color[3], edge.color[4] end

-- No settings at all: the gold one pixel box the banner always drew.
local config = {}
Art.Layout(art, config)
SameRects(Edges(), { { 65, -8, 530, 1 }, { 65, -118, 530, 1 }, { 65, -9, 1, 109 }, { 594, -9, 1, 109 } },
    "the default frame moved")
local r, g, b, a = Color(art.border[1])
Check(r == .96 and g == .81 and b == .44 and a == .48 and art.border[1].layer == "BORDER", "the default frame changed color")
Check(art.accents[1].shown and art.accents[2].shown and art.style == 1, "the default artwork is missing")
local panel = Art.PANEL
Check(panel.x == 65 and panel.y == -8 and panel.width == 530 and panel.height == 111,
    "the preview's click targets would miss the frame")

-- A config without the frame setting follows the artwork switch.
Art.Layout(art, { showBoxArt = false })
Check(#Edges() == 0 and not art.accents[1].shown, "artwork off without a frame setting kept the frame")
-- Both switches are independent once the frame has its own.
Art.Layout(art, { showBoxArt = false, showFrame = true })
Check(#Edges() == 4 and not art.accents[1].shown, "the frame did not show without the artwork")
Art.Layout(art, { showFrame = false })
Check(#Edges() == 0 and art.accents[1].shown and art.accents[2].shown, "hiding the frame hid the artwork")

-- Shapes and thickness: lines grow inwards from the panel's edge.
Art.Layout(art, { frameStyle = 2 })
SameRects(Edges(), { { 65, -8, 530, 1 }, { 65, -118, 530, 1 } }, "top and bottom lines")
Art.Layout(art, { frameStyle = 3 })
SameRects(Edges(), {
    { 65, -8, 24, 1 }, { 65, -9, 1, 23 }, { 571, -8, 24, 1 }, { 594, -9, 1, 23 },
    { 65, -118, 24, 1 }, { 65, -95, 1, 23 }, { 571, -118, 24, 1 }, { 594, -95, 1, 23 },
}, "corner brackets")
Art.Layout(art, { frameThickness = 3 })
SameRects(Edges(), { { 65, -8, 530, 3 }, { 65, -116, 530, 3 }, { 65, -11, 3, 105 }, { 592, -11, 3, 105 } },
    "a thick frame")
Check(#art.border == 8, "switching shapes created new edges instead of reusing them")

-- Opacity and the three color sources.
config = { frameOpacity = 80 }
Art.Layout(art, config)
Art.Tint(art, .1, .2, .3)
r, g, b, a = Color(art.border[1])
Check(r == .96 and g == .81 and b == .44 and a == .8, "the gold frame followed the headline or ignored its opacity")
config.frameColorSource = 2
Art.Layout(art, config)
r, g, b = Color(art.border[4])
Check(r == .1 and g == .2 and b == .3, "the frame did not take the last headline color")
Art.Tint(art, .4, .5, .6)
r, g, b = Color(art.border[2])
Check(r == .4 and g == .5 and b == .6, "the next banner's headline did not tint the frame")
config.frameColorSource, config.frameColor = 3, "00ff00"
Art.Layout(art, config)
r, g, b = Color(art.border[3])
Check(r == 0 and g == 1 and b == 0, "the custom frame color did not show")
Art.Tint(art, .7, .7, .7)
r, g, b = Color(art.border[3])
Check(r == 0 and g == 1 and b == 0, "a headline tint replaced the custom frame color")

-- The artwork opacity scales plain and atlas accents alike.
Art.Layout(art, { artOpacity = 50 })
Art.Tint(art, 1, 1, 1)
Check(math.abs(art.accents[1].color[4] - .475) < 1e-9 and math.abs(art.accents[2].color[4] - .31) < 1e-9,
    "the artwork opacity missed the classic lines")
Art.Layout(art, { artOpacity = 50, artStyle = 3 })
Check(math.abs(art.accents[1].alpha - .45) < 1e-9 and art.accents[1].atlas == "levelup-bar-gold",
    "the artwork opacity missed the gilded edges")
Check(#Edges() == 4, "the artwork opacity touched the frame")

-- Every visible change moves the revision the menu preview restarts on;
-- an unchanged layout keeps it.
local revision = art.revision
Art.Layout(art, { artOpacity = 50, artStyle = 3 })
Check(art.revision == revision, "an unchanged layout counted as a change")
for _, changed in ipairs({
    { artOpacity = 50, artStyle = 3, frameOpacity = 60 },
    { artOpacity = 50, artStyle = 3, frameOpacity = 60, frameStyle = 2 },
    { artOpacity = 50, artStyle = 3, frameOpacity = 60, frameStyle = 2, frameColorSource = 2 },
    { artOpacity = 60, artStyle = 3, frameOpacity = 60, frameStyle = 2, frameColorSource = 2 },
}) do
    Art.Layout(art, changed)
    Check(art.revision > revision, "a visible change kept the preview revision")
    revision = art.revision
end
------------------------------------------------------------------ text
-- The runtime banner and the menu sample both theme and show through these;
-- the rows match the banner the runtime always drew.
local Runtime = Suite.Suite
local fonts = {}
Runtime.SetStyledFont = function(text, path, size) fonts[text] = { path, size } end
local function Anchor(text, point) return text.points[point][1], text.points[point][2] end
local function Near(value, expected) return math.abs(value - expected) < 1e-9 end
local textConfig = { titleSize = 31, subtitleSize = 16, backgroundOpacity = 57, font = "" }
Art.Theme(art, textConfig, nil)
local title, subtitle = art.title, art.subtitle
Check(title.justify == "CENTER" and title.wrap == false and title.layer == "OVERLAY", "the headline is not a centered row")
local x, y = Anchor(title, "TOPLEFT")
local right = Anchor(title, "TOPRIGHT")
Check(x == 14 and y == -23 and right == -14, "the headline left its row")
x, y = Anchor(subtitle, "TOPLEFT")
right = Anchor(subtitle, "TOPRIGHT")
Check(x == 18 and y == -84 and right == -18, "the subtitle left its row")
Check(fonts[title][2] == 31 and fonts[subtitle][2] == 16 and fonts[title][1] == Suite.GlobalFontPath(),
    "the banner text lost its sizes or the MSUF font")
local bg = art.background.color
Check(Near(bg[1], .02) and Near(bg[2], .025) and Near(bg[3], .035) and Near(bg[4], .57)
    and subtitle.textColor[1] == .91, "the unskinned banner changed its colors")
-- Offsets move a row right and up; the arrows' inset moves both rows in.
textConfig.titleOffsetX, textConfig.titleOffsetY, textConfig.subtitleOffsetY = 10, 5, -7
revision = art.revision
Art.Theme(art, textConfig, nil)
x, y = Anchor(title, "TOPLEFT")
right = Anchor(title, "TOPRIGHT")
Check(x == 24 and y == -18 and right == -4 and art.revision > revision, "the headline offset did not move it")
Check(select(2, Anchor(subtitle, "TOPLEFT")) == -91, "the subtitle offset did not move it")
textConfig.artStyle = 2
Art.Theme(art, textConfig, nil)
Check(Anchor(title, "TOPLEFT") == 75 and Anchor(subtitle, "TOPRIGHT") == -69, "the arrows did not move the text in")
-- The kind's headline color, from the defaults or the custom colors.
Art.Show(art, textConfig, "quest", "Quest title", nil)
Check(title.text == "Quest title" and subtitle.text == "" and title.textColor[1] == .98 and title.textColor[3] == .39,
    "a quest banner lost its text or headline color")
Art.Show(art, textConfig, "unknown", "Other", "Sub")
Check(title.textColor[1] == .96 and title.textColor[2] == .88, "an unknown kind did not take the zone color")
textConfig.colorStyle, textConfig.questColor, textConfig.subtitleColor, textConfig.backgroundColor =
    2, "00ff00", "0000ff", "ff0000"
Art.Theme(art, textConfig, nil)
Art.Show(art, textConfig, "quest", "Quest title", "Sub")
Check(title.textColor[2] == 1 and subtitle.textColor[3] == 1 and art.background.color[1] == 1,
    "custom colors missed the headline, subtitle or background")
-- A skin colors the background and subtitle; its look picks the fallback opacity.
local skin = { look = "midnightLight" }
function skin:GetColor(token) if token == "surface" then return .1, .2, .3 end return .4, .5, .6 end
function skin:GetLook() return self.look end
Art.Theme(art, { titleSize = 31, subtitleSize = 16, font = "" }, skin)
bg = art.background.color
Check(bg[1] == .1 and bg[3] == .3 and Near(bg[4], .5) and subtitle.textColor[1] == .4,
    "the skin did not color the banner or the light look kept the dark opacity")

-- Without settings (another HUD's menu preview) nothing of the banner shows.
Art.Clear(art)
Check(#Edges() == 0 and not art.accents[1].shown and not art.accents[2].shown and not art.background.shown
    and not title.shown and not subtitle.shown, "the banner leaked into another preview")

print(("suite announcement frame contract: %d checks passed"):format(checks))
