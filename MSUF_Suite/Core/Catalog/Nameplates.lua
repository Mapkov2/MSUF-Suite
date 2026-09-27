local _, NS = ...
local B = NS.CatalogBuild

local function Available()
    if not NS.Client.isMainline then return false, "Nameplate skinning needs Retail or WoW Forever" end
    if not (_G.C_NamePlate and type(_G.C_NamePlate.GetNamePlates) == "function"
        and type(_G.C_NamePlate.GetNamePlateForUnit) == "function") then
        return false, "Blizzard's nameplate frames are not available"
    end
    return true
end

B.Module("nameplates", {
    title = "Nameplates",
    description = "A clean Jundies-inspired skin for Blizzard nameplates. Blizzard keeps health, threat, casts, auras, selection and click handling.",
    page = "suite_nameplates", optIn = true, defaultEnabled = false, available = Available,
    conflicts = { "Plater", "Platynator", "ElvUI", "EllesmereUINameplates" },
    cvars = {
        nameplateStyle = true,
        nameplateSize = true,
        nameplateForceShowUnitName = true,
        nameplateSimplifiedTypes = true,
        nameplateInfoDisplay = true,
        nameplateShowCastBars = true,
        nameplateCastBarDisplay = true,
        nameplateShowOnlyNameForFriendlyPlayerUnits = true,
        ShowClassColorInNameplate = true,
        nameplateShowClassColor = true,
        nameplateUseClassColorForFriendlyPlayerUnitNames = true,
        nameplateShowFriendlyRealmName = true,
        nameplateShowAllPersonalAuras = true,
        nameplateShowFriendlyNpcs = true,
        UnitNamePlayerGuild = true,
        UnitNamePlayerPVPTitle = true,
    },
})

local id = "nameplates"
-- The user's Retail Platynator profile is stored under the technical key
-- DEFAULT. Its selected design is Enemy Nameplates, known to the user as
-- Jundies. Keep this preset as the fresh Suite default.
local EXPRESSWAY_BOLD = "Interface\\AddOns\\MSUF_Suite_Skin\\Media\\Fonts\\Expressway ExtraBold.ttf"
local EXPRESSWAY = "Interface\\AddOns\\MSUF_Suite_Skin\\Media\\Fonts\\Expressway Regular.ttf"
local native = {
    nativeStyle = 1, nativeSize = 1, enemyTextMode = 1,
    enemyRoleColors = false,
    enemyTargetMarker = false, enemyQuestColors = false,
    enemyTargetStyle = 1,
    enemyEliteMarker = false, enemyQuestMarker = false,
    enemyColorsInDungeons = false, enemyColorsOutside = false,
    enemyBorderSize = 0, friendlyBorderSize = 0,
    enemyNameSize = 0, friendlyNameSize = 0,
    enemyTextOutline = 1, friendlyTextOutline = 1, enemyCastOutline = 1,
    enemyCastSize = 0, enemyHealthTextSize = 0,
    enemyTextEnabled = false, friendlyTextEnabled = false, enemyCastTextEnabled = false,
    enemyCastEnabled = 1, enemyCastDisplay = 1,
    auraClickthrough = false,
    enemyNameFont = "", friendlyNameFont = "", enemyCastFont = "",
}
local roles = NS.NameplateStyle.Roles
local function AddOffsets(rules, prefix, element)
    for _, axis in ipairs({ "X", "Y" }) do
        rules[#rules + 1] = B.Number(prefix .. element.key .. "Offset" .. axis,
            element.label .. " " .. axis, 0, -160, 160)
    end
end
for _, role in ipairs(roles) do
    if role.key ~= "TankMode" then native["enemy" .. role.key .. "Enabled"] = false end
end
B.Section(id, "general", "Frame Basics", {
    B.Choice("look", "Look", 1, { "Jundies", "Blizzard", "Custom" }),
    B.Bool("enemy", "Skin enemy nameplates", true),
    B.Bool("friendly", "Skin friendly nameplates", true),
    B.Choice("nativeStyle", "Blizzard plate style", 2,
        { "Keep Blizzard setting", "Modern (text inside)", "Thin", "Block (text inside)",
          "Health focus", "Cast focus", "Legacy", "Classic" }),
    B.Choice("nativeSize", "Blizzard plate size", 3,
        { "Keep Blizzard setting", "Small", "Medium", "Large", "Extra large", "Huge" }),
    B.Choice("friendlyNamesOnly", "Friendly player plates", 2, { "Keep Blizzard setting", "Names only", "Health bars" }),
    B.Choice("classColors", "Player class colors", 2, { "Keep Blizzard setting", "On", "Off" }),
    B.Choice("friendlyNameClassColor", "Friendly player name class color", 2,
        { "Keep Blizzard setting", "On", "Off" }),
    B.Choice("friendlyRealm", "Friendly player realm names", 1,
        { "Keep Blizzard setting", "Show", "Hide" }),
    B.Choice("personalAuras", "Blizzard personal auras", 1, { "Keep Blizzard setting", "Show all", "Blizzard filter" }),
    B.Bool("auraClickthrough", "Let clicks pass through nameplate auras", false),
    B.Choice("friendlyNPCs", "Friendly NPC nameplates", 1, { "Keep Blizzard setting", "Show", "Hide" }),
    B.Choice("playerGuildNames", "Player guild names", 1, { "Keep Blizzard setting", "Show", "Hide" }),
    B.Choice("playerTitles", "Player titles", 1, { "Keep Blizzard setting", "Show", "Hide" }),
    B.Bool("protectImport", "Keep current nameplates on full profile import", false),
})

local function AddEnemyNativeRules(appearance)
    appearance[#appearance + 1] = B.Choice("enemyTextMode", "Enemy names and health text", 4,
        { "Keep Blizzard settings", "Always show name + percent", "Always show name + value",
          "Always show name + value and percent" })
    appearance[#appearance + 1] = B.Choice("enemyRarityIcon", "Blizzard elite / rare icon (all nameplates)", 1,
        { "Keep Blizzard setting", "Show", "Hide" })
    appearance[#appearance + 1] = B.Bool("enemyRaidIcon", "Blizzard raid target icon on enemy plates", true)
end

local function Side(prefix, title, size)
    local font = B.Font(prefix .. "NameFont", "Name font")
    font.default = prefix == "enemy" and EXPRESSWAY_BOLD or EXPRESSWAY
    local appearance = {
        B.Number(prefix .. "BorderSize", "Health border (px)", prefix == "enemy" and 1 or 0, 0, 3),
        B.Color(prefix .. "BorderColor", "Health border", "000000"),
        B.Color(prefix .. "BackdropColor", "Health backdrop", "000000"),
        B.Number(prefix .. "BackdropAlpha", "Health backdrop opacity (%)", 50, 0, 100, 5),
        B.Bool(prefix .. "TextEnabled", "Customize nameplate text", true),
        B.Bool(prefix .. "CustomFont", "Override Blizzard font (empty font = MSUF)", true),
        B.Bool(prefix .. "TextShadow", "Text shadow", prefix == "friendly"),
        B.Number(prefix .. "NameSize", "Name font size (0 = Blizzard)", size, 0, 32),
        B.Choice(prefix .. "TextOutline", "Name and health text outline", 4,
            NS.NameplateStyle.OutlineLabels),
        font,
    }
    if prefix == "enemy" then
        AddEnemyNativeRules(appearance)
        appearance[#appearance + 1] = B.Bool("enemyRoleColors", "Color enemy health fill by type", true)
        appearance[#appearance + 1] = B.Bool("enemyColorsInDungeons", "Role colors in dungeons and raids", true)
        appearance[#appearance + 1] = B.Bool("enemyColorsOutside", "Role colors outdoors", true)
        appearance[#appearance + 1] = B.Bool("enemyQuestColors", "Quest objective colors", true)
        appearance[#appearance + 1] = B.Bool("enemyTankMode", "Tank mode: safe aggro color", false)
        appearance[#appearance + 1] = B.Bool("enemyTargetMarker", "Target arrows", true)
        appearance[#appearance + 1] = B.Bool("enemyTargetHideFriendly", "Hide target arrows on friendly plates", true)
        appearance[#appearance + 1] = B.Choice("enemyTargetStyle", "Target marker", 1, NS.NameplateStyle.TargetLabels)
        appearance[#appearance + 1] = B.Choice("enemyTargetLayout", "Target marker layout", 2,
            { "Single", "Both sides inward", "Both sides outward" })
        appearance[#appearance + 1] = B.Choice("enemyTargetAnchor", "Target marker anchor (single)", 4, NS.AnchorLabels)
        appearance[#appearance + 1] = B.Choice("enemyTargetDirection", "Target marker direction (single)", 1,
            { "Right", "Left", "Up", "Down" })
        appearance[#appearance + 1] = B.Number("enemyTargetMarkerSize", "Target marker size", 16, 8, 96)
        appearance[#appearance + 1] = B.Number("enemyTargetOffsetX", "Target marker X (0 = outside left edge)", 0, -500, 500)
        appearance[#appearance + 1] = B.Number("enemyTargetOffsetY", "Target marker Y", 0, -500, 500)
        appearance[#appearance + 1] = B.Bool("enemyEliteMarker", "Boss and rare marker", false)
        appearance[#appearance + 1] = B.Choice("enemyEliteMarkerAnchor", "Boss and rare marker anchor", 1, NS.NameplateStyle.AnchorLabels)
        appearance[#appearance + 1] = B.Number("enemyEliteMarkerSize", "Boss and rare marker size", 14, 8, 48)
        appearance[#appearance + 1] = B.Number("enemyEliteOffsetX", "Boss and rare marker X", -13, -80, 80)
        appearance[#appearance + 1] = B.Number("enemyEliteOffsetY", "Boss and rare marker Y", 0, -40, 40)
        appearance[#appearance + 1] = B.Bool("enemyQuestMarker", "Quest marker", true)
        appearance[#appearance + 1] = B.Choice("enemyQuestMarkerAnchor", "Quest marker anchor", 5, NS.NameplateStyle.AnchorLabels)
        appearance[#appearance + 1] = B.Number("enemyQuestMarkerSize", "Quest marker size", 15, 8, 48)
        appearance[#appearance + 1] = B.Number("enemyQuestOffsetX", "Quest marker X", -14, -80, 80)
        appearance[#appearance + 1] = B.Number("enemyQuestOffsetY", "Quest marker Y", 0, -40, 40)
        appearance[#appearance + 1] = B.Texture("enemyHealthTexture", "Enemy health fill texture")
        appearance[#appearance + 1] = B.Texture("enemyFocusHealthTexture", "Focus health fill texture")
        appearance[#appearance + 1] = B.Number("enemyHealthTextSize", "Health text size (0 = Blizzard)", 11, 0, 32)
        appearance[#appearance + 1] = B.Choice("enemyPreviewRole", "Enemy preview type", 1,
            NS.NameplateStyle.RoleLabels)
    end
    if prefix == "friendly" then
        appearance[#appearance + 1] = B.Bool("friendlyGroupOnly", "Player names only: party / raid members", false)
        appearance[#appearance + 1] = B.Texture("friendlyHealthTexture", "Friendly health fill texture")
        appearance[#appearance + 1] = B.Texture("friendlyFocusHealthTexture", "Friendly focus health fill texture")
        for _, kind in ipairs({ "Elite", "Quest" }) do
            local label = kind == "Elite" and "Elite / rare / boss marker" or "Quest marker"
            appearance[#appearance + 1] = B.Bool(prefix .. kind .. "Marker", label, false)
            appearance[#appearance + 1] = B.Choice(prefix .. kind .. "MarkerAnchor", label .. " anchor", 1, NS.NameplateStyle.AnchorLabels)
            appearance[#appearance + 1] = B.Number(prefix .. kind .. "MarkerSize", label .. " size", 14, 8, 48)
            appearance[#appearance + 1] = B.Number(prefix .. kind .. "OffsetX", label .. " X", -14, -80, 80)
            appearance[#appearance + 1] = B.Number(prefix .. kind .. "OffsetY", label .. " Y", 0, -40, 40)
        end
        local friendlyCastFont = B.Font("friendlyCastFont", "Friendly cast font")
        friendlyCastFont.default = EXPRESSWAY
        for _, rule in ipairs({
            B.Bool("friendlyCastTextEnabled", "Customize friendly cast text", false),
            B.Bool("friendlyCastCustomFont", "Override friendly cast font", true),
            B.Bool("friendlyCastTextShadow", "Friendly cast text shadow", false),
            B.Number("friendlyCastSize", "Friendly cast text size (0 = Blizzard)", 11, 0, 32),
            B.Choice("friendlyCastOutline", "Friendly cast text outline", 4, NS.NameplateStyle.OutlineLabels),
            friendlyCastFont,
        }) do appearance[#appearance + 1] = rule end
    end
    for _, element in ipairs(NS.NameplateStyle.Elements) do
        if prefix == "friendly" or element.section ~= "castbar" then AddOffsets(appearance, prefix, element) end
    end
    B.Section(id, prefix, title, appearance)
end
Side("enemy", "Enemy appearance", 12)
Side("friendly", "Friendly appearance", 12)

local toggles = {}
for _, role in ipairs(roles) do
    if role.key ~= "TankMode" then
        toggles[#toggles + 1] = B.Bool("enemy" .. role.key .. "Enabled", role.label .. " color", true)
    end
end
B.Section(id, "roleColors", "Enemy color rules", toggles)

local castFont = B.Font("enemyCastFont", "Cast font")
castFont.default = EXPRESSWAY_BOLD
local castRules = {
    B.Choice("enemyCastEnabled", "Show Blizzard nameplate castbars", 2,
        { "Keep Blizzard setting", "Show", "Hide" }),
    B.Choice("enemyCastDisplay", "Blizzard castbar details", 2,
        { "Keep Blizzard setting", "Custom" }),
    B.Bool("enemyCastSpellName", "Spell name", true),
    B.Bool("enemyCastSpellIcon", "Spell icon", false),
    B.Bool("enemyCastSpellTarget", "Spell target", false),
    B.Bool("enemyCastImportant", "Highlight important casts", true),
    B.Bool("enemyCastTargetHighlight", "Highlight casts targeting you", true),
    B.Bool("enemyCastTextEnabled", "Customize cast text", true),
    B.Bool("enemyCastCustomFont", "Override Blizzard cast font (empty font = MSUF)", true),
    B.Bool("enemyCastTextShadow", "Cast text shadow", false),
    B.Number("enemyCastSize", "Cast text size (0 = Blizzard)", 11, 0, 32),
    B.Choice("enemyCastOutline", "Cast text outline", 4,
        NS.NameplateStyle.OutlineLabels),
    castFont,
}
for _, element in ipairs(NS.NameplateStyle.Elements) do
    if element.section == "castbar" then AddOffsets(castRules, "enemy", element) end
end
B.Section(id, "castbar", "Enemy castbar", castRules)

local colors = {}
for _, role in ipairs(roles) do colors[#colors + 1] = B.Color("enemy" .. role.key .. "Color", role.label, role.color) end
colors[#colors + 1] = B.Color("enemyTargetColor", "Target arrows", "ffffff")
B.Section(id, "enemyColors", "Enemy colors", colors)

-- Jundies is the factory appearance. Derive its reset values from the same
-- rules used for fresh profiles so defaults and the preset cannot diverge.
local spec = NS.SuiteCatalog[id]
local appearanceSections = { enemy = true, friendly = true, roleColors = true, castbar = true, enemyColors = true }
local preset, visual = {}, { nativeStyle = true, nativeSize = true, auraClickthrough = true }
for key, rule in pairs(spec.rules) do
    if visual[key] or appearanceSections[rule.section] and key ~= "enemyPreviewRole" then
        preset[key], visual[key] = rule.default, true
    end
end
spec.look = { key = "look", presets = { [1] = preset, [2] = native }, visualKeys = visual, custom = 3 }
