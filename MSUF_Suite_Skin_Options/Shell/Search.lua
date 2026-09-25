local _, Private = ...
local NS, O = Private.NS, Private.Options
local L = NS.L

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
local defaultMeta = { group = "manage", simple = true, keywords = "" }

-- Keep discovery in lockstep with the runtime catalogs. New styles and color
-- palettes become searchable without duplicating their names in this LoD file.
local function CatalogKeywords(order, labelOf)
    local terms = {}
    for index = 1, #(order or {}) do
        local key = order[index]
        terms[#terms + 1] = tostring(key)
        terms[#terms + 1] = tostring(labelOf(key) or "")
    end
    return table.concat(terms, " ")
end

local lookCatalogKeywords = CatalogKeywords(NS.LookOrder, function(key)
    local look = NS.LookPresets and NS.LookPresets[key]
    return look and look.label
end)
local paletteCatalogKeywords = CatalogKeywords(NS.PaletteOrder, function(key)
    return NS.PaletteLabels and NS.PaletteLabels[key]
end)

-- { page, label, extra keywords }. Labels are the visible control names.
local entries = {
    { "dashboard", NS.L.MASTER_ENABLE, "master on off engine" },
    { "looks", L["Style preset"], "complete coordinated authored look " .. lookCatalogKeywords },
    { "looks", L["Shaded surfaces"], "material gradient on off" },
    { "looks", L["Light direction"], "gradient horizontal vertical" },
    { "looks", L["Shading strength"], "gradient intensity" },
    { "looks", L["Surface depth"], "material depth relief" },
    { "looks", L["Window opacity"], "shell transparency alpha" },
    { "looks", L["Content opacity"], "panel card transparency alpha" },
    { "looks", L["Controls opacity"], "button navigation transparency alpha" },
    { "looks", L["Outline opacity"], "border transparency alpha" },
    { "icons", L["Window action style"], "close x add remove maximize minimize bare soft outline native button" },
    { "icons", L["Window action symbols"], "close x plus minus chevrons glyph fine bold size offset opacity shape radius inset smaller" },
    { "icons", L["Skin Micro Bar"], "micro menu micromenu minimenu buttons hud" },
    { "icons", L["Micro Bar style"], "forever modern compact glass preset" },
    { "icons", L["Micro Bar visibility"], "always combat out of combat mouseover never hide show" },
    { "icons", L["Micro icon colors"], "native theme class monochrome tint normal hover pressed disabled" },
    { "icons", L["Micro Bar backgrounds"], "bar button plates surfaces" },
    { "icons", L["Micro Bar shape and border"], "round continuous squircle radius outline" },
    { "icons", L["Micro icon state opacity"], "normal hover pressed disabled alpha" },
    { "icons", L["Item icon border style"], "item quality theme off icons" },
    { "icons", L["Item icon border geometry"], "thickness padding opacity" },
    { "colors", L["Window and panel colors"], "background ink surface raised card popup input" },
    { "colors", L["Color palette"], "preset coordinated colors " .. paletteCatalogKeywords },
    { "colors", L["Text colors"], "title muted dim disabled blizzard yellow gold chat system" },
    { "colors", L["Accent and status colors"], "accent bright blue success warning danger secondary" },
    { "colors", L["Border colors"], "rim soft button icon outline" },
    { "colors", L["Button interaction colors"], "fill hover pressed active checkmark selection" },
    { "colors", L["Blizzard symbol colors"], "arrow dropdown plus minus expand close x pressed hover disabled" },
    { "colors", L["Exact RGBA / hex entry"], "hex alpha color picker precise" },
    { "typography", L["Override Blizzard fonts"], "global font typeface enable disable" },
    { "typography", L["Font"], "typeface dropdown sharedmedia media addons" },
    { "typography", L["Chat and Communities font"], "console text" },
    { "typography", L["Quest, mail and combat font"], "number special styles" },
    { "typography", L["Custom font path"], "file ttf otf" },
    { "geometry", L["Window corner style"], "panel curve round continuous squircle" },
    { "geometry", L["Button corner style"], "control curve pill round continuous squircle" },
    { "geometry", L["Corner radius"], "4 6 8 12 px" },
    { "geometry", L["Outline thickness"], "border 0 1 2 px" },
    { "geometry", L["Hover highlight style"], "border only soft fill solid fill off" },
    { "geometry", L["Hover intensity"], "highlight strength" },
    { "skins", NS.L.SKIN_GAME_MENU, "escape esc buttons" },
    { "skins", L["Blizzard Settings"], "options addon list dropdown scroll" },
    { "skins", NS.L.SKIN_WORLD_MAP, "map" },
    { "skins", NS.L.SKIN_PLAYER_SPELLS, "player spells" },
    { "skins", NS.L.SKIN_ENCOUNTER_JOURNAL, "encounter journal" },
    { "skins", L["Objective Tracker text and icons"], "quest tracker" },
    { "skins", L["Chat windows and tabs"], "system npc colors" },
    { "skins", NS.L.SKIN_DAMAGE_METER, "combat meter" },
    { "skins", NS.L.SKIN_EDIT_MODE, "editmode" },
    { "skins", NS.L.SKIN_COMMUNITIES, "community mail guild roster" },
    { "coverage", L["Window categories"], "all blizzard ui families" },
    { "coverage", NS.L.DOSSIER_OPTION, "character inspect equipment itemlevel ilvl enchant gems durability ausrüstung betrachten haltbarkeit" },
    { "coverage", NS.L.DOSSIER_OPEN_OPTION, "character inspect expand collapse open close details ausklappen einklappen" },
    { "coverage", NS.L.STATS_OPTION, "character stats attributes haste crit mastery versatility charakter werte tempo meisterschaft" },
    { "coverage", NS.L.EQOL_CHARACTER_OPTION, "eqol enhanceqol character enchant gems sockets upgrade gear layout charakter verzauberungen sockel" },
    { "coverage", NS.L.STATS_DR_OPTION, "diminishing returns dr rating efficiency wertung effizienz" },
    { "coverage", NS.L.CHARACTER_VIEW, "character view modern classic blizzard layout equipment list only cards model breit charakter ansicht liste ausruestung" },
    { "coverage", L["Professions and crafting"], "trade skill" },
    { "coverage", L["Auction and economy"], "auction house merchant" },
    { "coverage", L["Housing interfaces"], "house dashboard" },
    { "hud", L["Objective Tracker background"], "container" },
    { "hud", L["Objective Tracker headers"], "module title" },
    { "hud", L["Objective Tracker progress"], "timer bars" },
    { "hud", L["Damage Meter windows"], "header surfaces" },
    { "hud", L["Damage Meter rows"], "class color plates" },
    { "hud", L["Damage Meter detail window"], "source detail" },
    { "profiles", L["Active profile"], "switch" },
    { "profiles", L["Create or copy profile"], "new duplicate" },
    { "profiles", L["Delete profile"], "remove" },
    { "profiles", L["Import / export"], "share backup MSKIN1 all profiles" },
    { "advanced", NS.L.RESET_ALL, "reset all defaults" },
    { "advanced", L["Runtime contract"], "no polling ticker onupdate combat performance" },
}

function O.GetPageMeta(key)
    return pageMeta[key] or defaultMeta
end

local function Normalize(value)
    return tostring(value or ""):lower()
end

-- Search records are built on the first query, after every page registered
-- its (translated) label, and reused for every keystroke after that.
local records

local function BuildRecords()
    records = {}
    for index = 1, #entries do
        local item = entries[index]
        local key = item[1]
        local definition = O.GetPageDefinition and O.GetPageDefinition(key)
        local pageLabel = definition and definition.label or key
        local meta = O.GetPageMeta(key)
        local label = Normalize(item[2])
        records[index] = {
            page = key,
            label = item[2],
            pageLabel = pageLabel,
            expert = meta.simple == false,
            lowerLabel = label,
            haystack = label .. " " .. Normalize(pageLabel) .. " " .. Normalize(item[3]) .. " " .. Normalize(meta.keywords),
            score = 0,
        }
    end
end

local function MatchTokens(haystack, query)
    for token in query:gmatch("%S+") do
        if not haystack:find(token, 1, true) then return false end
    end
    return true
end

local function Score(label, query)
    if label == query then return 100 end
    local at = label:find(query, 1, true)
    if at == 1 then return 70 end
    return at and 50 or 20
end

local function ByRelevance(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.pageLabel ~= b.pageLabel then return a.pageLabel < b.pageLabel end
    return a.label < b.label
end

-- Returns up to `limit` records ({ page, label, pageLabel, expert }). The
-- list is reused by the next query; callers read it right away.
local results = {}

function O.SearchSettings(query, limit)
    for index = #results, 1, -1 do results[index] = nil end
    query = Normalize(query):match("^%s*(.-)%s*$") or ""
    if #query < 2 then return results end
    if not records then BuildRecords() end
    for index = 1, #records do
        local record = records[index]
        if MatchTokens(record.haystack, query) then
            record.score = Score(record.lowerLabel, query)
            results[#results + 1] = record
        end
    end
    table.sort(results, ByRelevance)
    for index = #results, (limit or 8) + 1, -1 do results[index] = nil end
    return results
end
