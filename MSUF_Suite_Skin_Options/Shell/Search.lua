local _, Private = ...
local NS, O = Private.NS, Private.Options

-- Static, load-on-demand search metadata keeps every setting discoverable
-- without building all pages or scanning frames. Search work only happens
-- while the user types in the options window.
local pageMeta = {
    dashboard = { group = "start", simple = true, keywords = "home setup enable engine status" },
    looks = { group = "design", simple = true, keywords = "style preset opacity gradient material appearance" },
    icons = { group = "design", simple = true, keywords = "icon icons window actions close x plus minus maximize minimize bare soft outline native chevron micro bar microbar micro menu minimenu hud border tint class monochrome" },
    colors = { group = "design", simple = true, keywords = "colour palette rgba hex text border button hover blizzard gold yellow" },
    typography = { group = "design", simple = true, keywords = "font typeface sharedmedia chat quest mail accessibility" },
    geometry = { group = "design", simple = false, keywords = "corner curve round continuous squircle radius border shape hover" },
    skins = { group = "coverage", simple = true, keywords = "blizzard windows adapters game menu settings map spellbook chat" },
    coverage = { group = "coverage", simple = false, keywords = "categories character inventory npc quest social group profession economy map housing" },
    hud = { group = "coverage", simple = false, keywords = "damage meter combat rows headers" },
    profiles = { group = "manage", simple = true, keywords = "profile copy delete import export share backup" },
    advanced = { group = "manage", simple = false, keywords = "runtime performance api reset factory diagnostics" },
}

-- Keep discovery in lockstep with the runtime catalogs.  New styles and color
-- palettes become searchable without duplicating their names in this LoD file.
local lookCatalogKeywords, paletteCatalogKeywords = "", ""
do
    local lookTerms = {}
    for index = 1, #(NS.LookOrder or {}) do
        local key = NS.LookOrder[index]
        local look = NS.LookPresets and NS.LookPresets[key]
        lookTerms[#lookTerms + 1] = tostring(key)
        if look then
            lookTerms[#lookTerms + 1] = tostring(look.label or "")
        end
    end
    lookCatalogKeywords = table.concat(lookTerms, " ")

    local paletteTerms = {}
    for index = 1, #(NS.PaletteOrder or {}) do
        local key = NS.PaletteOrder[index]
        paletteTerms[#paletteTerms + 1] = tostring(key)
        paletteTerms[#paletteTerms + 1] = tostring(NS.PaletteLabels
            and NS.PaletteLabels[key] or "")
    end
    paletteCatalogKeywords = table.concat(paletteTerms, " ")
end

local entries = {
    { "dashboard", "Enable skinning", "master on off engine" },
    { "looks", "Style preset", "complete coordinated authored look " .. lookCatalogKeywords },
    { "looks", "Shaded surfaces", "material gradient on off" },
    { "looks", "Light direction", "gradient horizontal vertical" },
    { "looks", "Shading strength", "gradient intensity" },
    { "looks", "Surface depth", "material depth relief" },
    { "looks", "Window opacity", "shell transparency alpha" },
    { "looks", "Content opacity", "panel card transparency alpha" },
    { "looks", "Controls opacity", "button navigation transparency alpha" },
    { "looks", "Outline opacity", "border transparency alpha" },
    { "icons", "Window action style", "close x add remove maximize minimize bare soft outline native button" },
    { "icons", "Window action symbols", "close x plus minus chevrons glyph fine bold size offset opacity shape radius inset smaller" },
    { "icons", "Skin Micro Bar", "micro menu micromenu minimenu buttons hud" },
    { "icons", "Micro Bar style", "forever modern compact glass preset" },
    { "icons", "Micro Bar visibility", "always combat out of combat mouseover never hide show" },
    { "icons", "Micro icon colors", "native theme class monochrome tint normal hover pressed disabled" },
    { "icons", "Micro Bar backgrounds", "bar button plates surfaces" },
    { "icons", "Micro Bar shape and border", "round continuous squircle radius outline" },
    { "icons", "Micro icon state opacity", "normal hover pressed disabled alpha" },
    { "icons", "Item icon border style", "item quality theme off icons" },
    { "icons", "Item icon border geometry", "thickness padding opacity" },
    { "colors", "Window and panel colors", "background ink surface raised card popup input" },
    { "colors", "Color palette", "preset coordinated colors " .. paletteCatalogKeywords },
    { "colors", "Text colors", "title muted dim disabled blizzard yellow gold chat system" },
    { "colors", "Accent and status colors", "accent bright blue success warning danger secondary" },
    { "colors", "Border colors", "rim soft button icon outline" },
    { "colors", "Button interaction colors", "fill hover pressed active checkmark selection" },
    { "colors", "Blizzard symbol colors", "arrow dropdown plus minus expand close x pressed hover disabled" },
    { "colors", "Exact RGBA / hex entry", "hex alpha color picker precise" },
    { "typography", "Override Blizzard fonts", "global font typeface enable disable" },
    { "typography", "Font", "typeface dropdown sharedmedia media addons" },
    { "typography", "Chat and Communities font", "console text" },
    { "typography", "Quest, mail and combat font", "number special styles" },
    { "typography", "Custom font path", "file ttf otf" },
    { "geometry", "Window corner style", "panel curve round continuous squircle" },
    { "geometry", "Button corner style", "control curve pill round continuous squircle" },
    { "geometry", "Corner radius", "4 6 8 12 px" },
    { "geometry", "Outline thickness", "border 0 1 2 px" },
    { "geometry", "Hover highlight style", "border only soft fill solid fill off" },
    { "geometry", "Hover intensity", "highlight strength" },
    { "skins", "Game menu", "escape esc buttons" },
    { "skins", "Blizzard Settings", "options addon list dropdown scroll" },
    { "skins", "World Map and Quest Log", "map" },
    { "skins", "Spellbook and talents", "player spells" },
    { "skins", "Adventure Guide", "encounter journal" },
    { "skins", "Objective Tracker text and icons", "quest tracker" },
    { "skins", "Chat windows and tabs", "system npc colors" },
    { "skins", "Damage Meter", "combat meter" },
    { "skins", "HUD Edit Mode", "editmode" },
    { "skins", "Guild and Communities", "community mail guild roster" },
    { "coverage", "Window categories", "all blizzard ui families" },
    { "coverage", NS.L.DOSSIER_OPTION, "character inspect equipment itemlevel ilvl enchant gems durability ausrüstung betrachten haltbarkeit" },
    { "coverage", NS.L.DOSSIER_OPEN_OPTION, "character inspect expand collapse open close details ausklappen einklappen" },
    { "coverage", NS.L.STATS_OPTION, "character stats attributes haste crit mastery versatility charakter werte tempo meisterschaft" },
    { "coverage", NS.L.EQOL_CHARACTER_OPTION, "eqol enhanceqol character enchant gems sockets upgrade gear layout charakter verzauberungen sockel" },
    { "coverage", NS.L.STATS_DR_OPTION, "diminishing returns dr rating efficiency wertung effizienz" },
    { "coverage", NS.L.CHARACTER_VIEW, "character view modern classic blizzard layout equipment list only cards model breit charakter ansicht liste ausruestung" },
    { "coverage", "Professions and crafting", "trade skill" },
    { "coverage", "Auction and economy", "auction house merchant" },
    { "coverage", "Housing interfaces", "house dashboard" },
    { "hud", "Objective Tracker background", "container" },
    { "hud", "Objective Tracker headers", "module title" },
    { "hud", "Objective Tracker progress", "timer bars" },
    { "hud", "Damage Meter windows", "header surfaces" },
    { "hud", "Damage Meter rows", "class color plates" },
    { "hud", "Damage Meter detail window", "source detail" },
    { "profiles", "Active profile", "switch" },
    { "profiles", "Create or copy profile", "new duplicate" },
    { "profiles", "Delete profile", "remove" },
    { "profiles", "Import / export", "share backup MSKIN1 all profiles" },
    { "advanced", "Factory reset", "reset all defaults" },
    { "advanced", "Runtime contract", "no polling ticker onupdate combat performance" },
}

function O.GetPageMeta(key)
    return pageMeta[key] or { group = "manage", simple = true, keywords = "" }
end

local function Normalize(value)
    return tostring(value or ""):lower()
end

local function MatchTokens(haystack, query)
    for token in query:gmatch("%S+") do
        if not haystack:find(token, 1, true) then return false end
    end
    return true
end

function O.SearchSettings(query, limit)
    query = Normalize(query):match("^%s*(.-)%s*$") or ""
    if #query < 2 then return {} end
    local results = {}
    for index = 1, #entries do
        local item = entries[index]
        local definition = O.GetPageDefinition and O.GetPageDefinition(item[1])
        local pageLabel = definition and definition.label or item[1]
        local meta = O.GetPageMeta(item[1])
        local label = Normalize(item[2])
        local haystack = label .. " " .. Normalize(pageLabel) .. " " .. Normalize(item[3]) .. " " .. Normalize(meta.keywords)
        if MatchTokens(haystack, query) then
            local score = label == query and 100 or label:find(query, 1, true) == 1 and 70
                or label:find(query, 1, true) and 50 or 20
            results[#results + 1] = {
                page = item[1], label = item[2], pageLabel = pageLabel,
                expert = meta.simple == false, score = score,
            }
        end
    end
    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.pageLabel ~= b.pageLabel then return a.pageLabel < b.pageLabel end
        return a.label < b.label
    end)
    while #results > (limit or 8) do results[#results] = nil end
    return results
end
