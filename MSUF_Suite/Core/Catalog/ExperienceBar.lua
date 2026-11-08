local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
local ID, SECTION, TITLE = "xpBar", "xp_bar", "Experience bar"
local anchors = { "Automatic" }
for _, label in ipairs(NS.AnchorLabels) do anchors[#anchors + 1] = label end
B.Add(ID, B.Texture("barTexture", "Foreground texture"), SECTION, TITLE)
B.Add(ID, B.Texture("backgroundTexture", "Background texture"), SECTION, TITLE)

for _, spec in ipairs(NS.ExperienceBarLayout.Texts) do
    local prefix = spec.prefix
    local function Label(pattern) return NS.Text(pattern):format(NS.Text(spec.label)) end
    local function Add(rule)
        rule.xpTextRole = spec.id
        B.Add(ID, rule, SECTION, TITLE)
    end
    Add(B.Font(prefix .. "Font", Label("%s: Font")))
    Add(B.Number(prefix .. "Size", Label("%s: Size (0 = automatic)"), 0, 0, 40))
    Add(B.Choice(prefix .. "Outline", Label("%s: Outline"), 1, { "Automatic", "None", "Outline", "Thick outline" }))
    Add(B.Choice(prefix .. "Anchor", Label("%s: Anchor"), 1, anchors))
    Add(B.Number(prefix .. "X", Label("%s: Horizontal offset"), 0, -1000, 1000))
    Add(B.Number(prefix .. "Y", Label("%s: Vertical offset"), 0, -1000, 1000))
    if not spec.toggle then
        Add(B.Choice(prefix .. "Visibility", Label("%s: Visibility"), 1, { "Automatic", "Shown", "Hidden" }))
    end
    if spec.id == "percent" then
        Add(B.Choice(prefix .. "Format", Label("%s: Format"), 1,
            { "Automatic", "0 decimals", "1 decimal", "2 decimals" }))
    elseif spec.id == "xp" then
        Add(B.Choice(prefix .. "Format", Label("%s: Format"), 1,
            { "Automatic", "Current / maximum", "Current XP", "Remaining XP" }))
    else
        local formats = { "Automatic", "With label", "Value only" }
        if spec.id == "level" then formats[4] = "Level and XP" end
        Add(B.Choice(prefix .. "Format", Label("%s: Format"), 1, formats))
    end
    if spec.id ~= "percent" and spec.id ~= "eta" and spec.id ~= "levelTime" then
        Add(B.Choice(prefix .. "Numbers", Label("%s: Number format"), 1,
            { "Automatic", "Short numbers", "Full numbers" }))
    end
end
