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
        nameplateShowFriendlyClassColor = true,
        nameplateUseClassColorForFriendlyPlayerUnitNames = true,
        nameplateShowFriendlyRealmName = true,
        nameplateShowAllPersonalAuras = true,
        nameplateEnemyNpcAuraDisplay = true,
        nameplateEnemyPlayerAuraDisplay = true,
        nameplateFriendlyPlayerAuraDisplay = true,
        nameplateShowDebuffsOnFriendly = true,
        nameplateAuraScale = true,
        nameplateThreatDisplay = true,
        SoftTargetIconEnemy = true,
        SoftTargetIconFriend = true,
        SoftTargetIconInteract = true,
        SoftTargetNameplateSize = true,
        nameplateShowFriendlyNpcs = true,
        UnitNamePlayerGuild = true,
        UnitNamePlayerPVPTitle = true,
    },
})

local id = "nameplates"
-- The user's Retail Platynator profile is stored under the technical key
-- DEFAULT. Its selected design is Enemy Nameplates, known to the user as
-- Jundies. Keep this preset as the fresh Suite default.
local native = {
    nativeStyle = 1, nativeSize = 1, enemyTextMode = 1,
    enemyRoleColors = false,
    enemyTargetMarker = false, enemyQuestColors = false,
    enemyTargetStyle = 1,
    enemyEliteMarker = false, enemyQuestMarker = false,
    enemyColorsInDungeons = false, enemyColorsOutside = false,
    enemyBorderSize = 0, friendlyBorderSize = 0,
    enemyHealthWidthDelta = 0, enemyHealthHeightDelta = 0,
    friendlyHealthWidthDelta = 0, friendlyHealthHeightDelta = 0,
    enemyBorderEnabled = false, friendlyBorderEnabled = false,
    enemyBackdropEnabled = false, friendlyBackdropEnabled = false,
    enemyNameSize = 0, friendlyNameSize = 0,
    enemyLevelSize = 0, friendlyLevelSize = 0,
    enemyTextOutline = 1, friendlyTextOutline = 1, enemyCastOutline = 1,
    enemyCastSize = 0, enemyHealthTextSize = 0,
    enemyTextEnabled = false, friendlyTextEnabled = false, enemyCastTextEnabled = false,
    enemyCastEnabled = 1, enemyCastDisplay = 1,
    auraClickthrough = false,
    enemyNpcAuraMode = 1, enemyPlayerAuraMode = 1, friendlyPlayerAuraMode = 1,
    friendlyNpcDebuffs = 1, auraScaleMode = 1, threatSignalMode = 1,
    threatFlashColorEnabled = false, threatHighlightColorEnabled = false,
    softTargetEnemy = 1, softTargetFriend = 1, softTargetInteract = 1,
    softTargetIconGate = 1,
    personalPowerSkin = false,
    enemyNameFont = "", friendlyNameFont = "", enemyCastFont = "",
}
local roles = NS.NameplateStyle.Roles
-- Preview drag, arrow nudges, profile imports and runtime all share these bounds.
-- Keep enough room for elements outside the compact sample at high UI scales.
local POSITION_LIMIT = 2048
local function AddOffsets(rules, prefix, element)
    for _, axis in ipairs({ "X", "Y" }) do
        rules[#rules + 1] = B.Number(prefix .. element.key .. "Offset" .. axis,
            element.label .. " " .. axis, 0, -POSITION_LIMIT, POSITION_LIMIT)
    end
end
for _, role in ipairs(roles) do
    if role.key ~= "TankMode" then native["enemy" .. role.key .. "Enabled"] = false end
end
local generalRules = {
    B.Choice("look", "Look", 1, { "Jundies", "Blizzard", "Custom" }),
    B.Bool("enemy", "Skin enemy nameplates", true),
    B.Bool("friendly", "Skin friendly nameplates", true),
    B.Choice("nativeStyle", "Blizzard plate style", 2,
        { "Keep Blizzard setting", "Modern (text inside)", "Thin", "Block (text inside)",
          "Health focus", "Cast focus", "Legacy", "Classic" }),
    B.Choice("nativeSize", "Blizzard plate size (health bar + elements)", 3,
        { "Keep Blizzard setting", "Small", "Medium", "Large", "Extra large", "Huge" }),
    B.Choice("classColors", "Player class colors", 2, { "Keep Blizzard setting", "On", "Off" }),
    B.Choice("personalAuras", "Blizzard personal auras", 1, { "Keep Blizzard setting", "Show all", "Blizzard filter" }),
    B.Bool("auraClickthrough", "Let clicks pass through nameplate auras", false),
    B.Choice("friendlyNPCs", "Friendly NPC nameplates", 1, { "Keep Blizzard setting", "Show", "Hide" }),
    B.Choice("playerGuildNames", "Player guild names", 1, { "Keep Blizzard setting", "Show", "Hide" }),
    B.Choice("playerTitles", "Player titles", 1, { "Keep Blizzard setting", "Show", "Hide" }),
    B.Bool("protectImport", "Keep current nameplates on full profile import", false),
}
if NS.Client.isForever then
    native.levelAppearance = 2
    table.insert(generalRules, 6, B.Choice("levelAppearance", "Level appearance", 1,
        { "Jundies number", "Blizzard badge" }))
end
B.Section(id, "general", "Frame Basics", generalRules)

local function AddEnemyNativeRules(appearance)
    appearance[#appearance + 1] = B.Choice("enemyTextMode", "Enemy names and health text", 4,
        { "Keep Blizzard settings", "Always show name + percent", "Always show name + value",
          "Always show name + value and percent" })
    appearance[#appearance + 1] = B.Choice("enemyRarityIcon", "Blizzard elite / rare icon (all nameplates)", 1,
        { "Keep Blizzard setting", "Show", "Hide" })
    appearance[#appearance + 1] = B.Bool("enemyRaidIcon", "Blizzard raid target icon on enemy plates", true)
end

local function AddFriendlyRules(appearance)
    -- Put the outcome first; font and border controls refine that choice.
    table.insert(appearance, 1, B.Choice("friendlyNamesOnly", "Friendly player display", 2,
        { "Keep Blizzard setting", "Names only: all friendly players",
          "Names only: party / raid", "Health bars" }))
    table.insert(appearance, 2, B.Choice("friendlyNameClassColor", "Class color for player names", 2,
        { "Keep Blizzard setting", "On", "Off" }))
    table.insert(appearance, 3, B.Choice("friendlyRealm", "Friendly player realm names", 1,
        { "Keep Blizzard setting", "Show", "Hide" }))
    for _, kind in ipairs({ "Elite", "Quest" }) do
        local label = kind == "Elite" and "Elite / rare / boss marker" or "Quest marker"
        appearance[#appearance + 1] = B.Bool("friendly" .. kind .. "Marker", label, false)
        appearance[#appearance + 1] = B.Choice("friendly" .. kind .. "MarkerAnchor", label .. " anchor", 1, NS.NameplateStyle.AnchorLabels)
        appearance[#appearance + 1] = B.Number("friendly" .. kind .. "MarkerSize", label .. " size", 14, 8, 48)
        appearance[#appearance + 1] = B.Number("friendly" .. kind .. "OffsetX", label .. " X", -14, -POSITION_LIMIT, POSITION_LIMIT)
        appearance[#appearance + 1] = B.Number("friendly" .. kind .. "OffsetY", label .. " Y", 0, -POSITION_LIMIT, POSITION_LIMIT)
    end
    local friendlyCastFont = B.Font("friendlyCastFont", "Friendly cast font")
    for _, rule in ipairs({
        B.Bool("friendlyCastTextEnabled", "Customize friendly cast text", false),
        B.Bool("friendlyCastTimeEnabled", "Show friendly cast time", true),
        B.Bool("friendlyCastCustomFont", "Override friendly cast font", true),
        B.Bool("friendlyCastTextShadow", "Friendly cast text shadow", false),
        B.Number("friendlyCastSize", "Friendly cast text size (0 = Blizzard)", 11, 0, 32),
        B.Choice("friendlyCastOutline", "Friendly cast text outline", 4, NS.NameplateStyle.OutlineLabels),
        friendlyCastFont,
    }) do appearance[#appearance + 1] = rule end
end

local function Side(prefix, title, size)
    local font = B.Font(prefix .. "NameFont", "Name font")
    local appearance = {
        B.Bool(prefix .. "BackdropEnabled", "Skin health backdrop", true),
        B.Bool(prefix .. "BorderEnabled", "Skin health border", true),
        B.Number(prefix .. "BorderSize", "Health border (px)", prefix == "enemy" and 1 or 0, 0, 3),
        B.Color(prefix .. "BorderColor", "Health border", "000000"),
        B.Color(prefix .. "BackdropColor", "Health backdrop", "000000"),
        B.Number(prefix .. "BackdropAlpha", "Health backdrop opacity (%)", 50, 0, 100, 5),
        B.Bool(prefix .. "TextEnabled", "Customize nameplate text", true),
        B.Bool(prefix .. "LevelEnabled", "Show unit level",
            prefix == "enemy" and NS.Client.isForever),
        B.Number(prefix .. "LevelSize", "Jundies level number size (0 = Blizzard)", 0, 0, 32),
        B.Bool(prefix .. "CustomFont", "Override Blizzard font (empty font = MSUF)", true),
        B.Bool(prefix .. "TextShadow", "Text shadow", prefix == "friendly"),
        B.Number(prefix .. "NameSize", "Name font size (0 = Blizzard)", size, 0, 32),
        B.Choice(prefix .. "TextOutline", "Name and health text outline", 4,
            NS.NameplateStyle.OutlineLabels),
        font,
    }
    table.insert(appearance, 1, B.Number(prefix .. "HealthHeightDelta",
        "Health bar height change (px; 0 = Blizzard)", 0, -4, 24))
    table.insert(appearance, 1, B.Number(prefix .. "HealthWidthDelta",
        "Health bar width change (px; 0 = Blizzard)", 0, -30, 160))
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
        appearance[#appearance + 1] = B.Number("enemyTargetOffsetX", "Target marker X (0 = outside left edge)", 0, -POSITION_LIMIT, POSITION_LIMIT)
        appearance[#appearance + 1] = B.Number("enemyTargetOffsetY", "Target marker Y", 0, -POSITION_LIMIT, POSITION_LIMIT)
        appearance[#appearance + 1] = B.Bool("enemyEliteMarker", "Boss and rare marker", false)
        appearance[#appearance + 1] = B.Choice("enemyEliteMarkerAnchor", "Boss and rare marker anchor", 1, NS.NameplateStyle.AnchorLabels)
        appearance[#appearance + 1] = B.Number("enemyEliteMarkerSize", "Boss and rare marker size", 14, 8, 48)
        appearance[#appearance + 1] = B.Number("enemyEliteOffsetX", "Boss and rare marker X", -13, -POSITION_LIMIT, POSITION_LIMIT)
        appearance[#appearance + 1] = B.Number("enemyEliteOffsetY", "Boss and rare marker Y", 0, -POSITION_LIMIT, POSITION_LIMIT)
        appearance[#appearance + 1] = B.Bool("enemyQuestMarker", "Quest marker", true)
        appearance[#appearance + 1] = B.Choice("enemyQuestMarkerAnchor", "Quest marker anchor", 5, NS.NameplateStyle.AnchorLabels)
        appearance[#appearance + 1] = B.Number("enemyQuestMarkerSize", "Quest marker size", 15, 8, 48)
        appearance[#appearance + 1] = B.Number("enemyQuestOffsetX", "Quest marker X", -14, -POSITION_LIMIT, POSITION_LIMIT)
        appearance[#appearance + 1] = B.Number("enemyQuestOffsetY", "Quest marker Y", 0, -POSITION_LIMIT, POSITION_LIMIT)
        appearance[#appearance + 1] = B.Number("enemyHealthTextSize", "Health text size (0 = Blizzard)", 11, 0, 32)
        appearance[#appearance + 1] = B.Choice("enemyPreviewRole", "Enemy preview type", 1,
            NS.NameplateStyle.RoleLabels)
    end
    if prefix == "friendly" then AddFriendlyRules(appearance) end
    for _, element in ipairs(NS.NameplateStyle.Elements) do
        if prefix == "friendly" or element.section ~= "castbar" then AddOffsets(appearance, prefix, element) end
    end
    B.Section(id, prefix, title, appearance)
end
Side("enemy", "Enemy appearance", 12)
Side("friendly", "Friendly appearance", 12)

local auraRules = {}
for _, group in ipairs(NS.NameplateStyle.AuraGroups) do
    local prefix, label, control = group.key, group.label, group.control
    auraRules[#auraRules + 1] = B.Choice(prefix .. "AuraMode", label .. " auras", 1,
        { "Keep Blizzard setting", "Customize" })
    auraRules[#auraRules + 1] = B.Bool(prefix .. "Buffs", label .. " buffs", true)
    auraRules[#auraRules + 1] = B.Bool(prefix .. "Debuffs", label .. " debuffs", true)
    auraRules[#auraRules + 1] = B.Bool(prefix .. "Control", label .. " " .. control, true)
end
auraRules[#auraRules + 1] = B.Choice("friendlyNpcDebuffs", "Friendly NPC debuffs", 1,
    { "Keep Blizzard setting", "Show", "Hide" })
auraRules[#auraRules + 1] = B.Choice("auraScaleMode", "Blizzard aura icon size", 1,
    { "Keep Blizzard setting", "Customize" })
auraRules[#auraRules + 1] = B.Number("auraScalePercent", "Aura icon size (%)", 100, 70, 140, 10)
B.Section(id, "auras", "Blizzard auras", auraRules)

B.Section(id, "signals", "Blizzard indicators", {
    B.Choice("threatSignalMode", "Blizzard aggro signals", 1,
        { "Keep Blizzard setting", "Customize" }),
    B.Bool("threatFlash", "Flash when aggro changes", true),
    B.Bool("threatHighlight", "Progressive aggro highlight", true),
    B.Bool("threatFlashColorEnabled", "Custom flash color", false),
    B.Color("threatFlashColor", "Flash color", "ffff00"),
    B.Bool("threatHighlightColorEnabled", "Custom progressive highlight color", false),
    B.Color("threatHighlightColor", "Progressive highlight color", "ffe93a"),
    B.Choice("softTargetEnemy", "Enemy soft target icon", 1,
        { "Keep Blizzard setting", "Show", "Hide" }),
    B.Choice("softTargetFriend", "Friendly soft target icon", 1,
        { "Keep Blizzard setting", "Show", "Hide" }),
    B.Choice("softTargetInteract", "Interact soft target icon", 1,
        { "Keep Blizzard setting", "Show", "Hide" }),
    B.Choice("softTargetIconGate", "Soft target icon on nameplates", 1,
        { "Keep Blizzard setting", "Show", "Hide" }),
})

B.Section(id, "personal", "Personal power bar", {
    B.Bool("personalPowerSkin", "Skin Blizzard personal mana and alternate power bars", false),
    B.Number("personalPowerBorderSize", "Power border (px)", 1, 0, 3),
    B.Color("personalPowerBorderColor", "Power border", "000000"),
    B.Number("personalPowerOffsetX", "Power bar X", 0, -POSITION_LIMIT, POSITION_LIMIT),
    B.Number("personalPowerOffsetY", "Power bar Y", 0, -POSITION_LIMIT, POSITION_LIMIT),
})

local toggles = {}
for _, role in ipairs(roles) do
    if role.key ~= "TankMode" then
        toggles[#toggles + 1] = B.Bool("enemy" .. role.key .. "Enabled", role.label .. " color", true)
    end
end
B.Section(id, "roleColors", "Enemy color rules", toggles)

local castFont = B.Font("enemyCastFont", "Cast font")
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
    B.Bool("enemyCastTimeEnabled", "Show cast time", true),
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
local appearanceSections = { enemy = true, friendly = true, roleColors = true, castbar = true,
    enemyColors = true, auras = true, signals = true, personal = true }
local preset, visual = {}, { nativeStyle = true, nativeSize = true, auraClickthrough = true }
if NS.Client.isForever then visual.levelAppearance = true end
for key, rule in pairs(spec.rules) do
    if visual[key] or appearanceSections[rule.section] and key ~= "enemyPreviewRole" then
        preset[key], visual[key] = rule.default, true
    end
end
spec.look = { key = "look", presets = { [1] = preset, [2] = native }, visualKeys = visual, custom = 3 }
