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
-- palettes become searchable without duplicating their names in this LoD
-- file, under their key, their English name and the name the player reads.
local function CatalogKeywords(order, labelOf)
    local terms = {}
    for index = 1, #order do
        local key = order[index]
        local label = labelOf(key)
        terms[#terms + 1] = tostring(key)
        if label then
            terms[#terms + 1] = label
            terms[#terms + 1] = L[label]
        end
    end
    return table.concat(terms, " ")
end

local lookCatalogKeywords = CatalogKeywords(NS.LookOrder, function(key)
    local look = NS.LookPresets[key]
    return look and look.label
end)
local paletteCatalogKeywords = CatalogKeywords(NS.PaletteOrder, function(key)
    return NS.PaletteLabels[key]
end)

-- Marks a control Guided mode hides on its page: opening the result
-- switches to Expert mode first, as an Expert-only page does.
local EXPERT = true

-- { page, label, extra keywords, EXPERT or nil }. Labels are the visible
-- control names on that page, so a result reads like the control it opens.
local entries = {
    { "dashboard", NS.L.MASTER_ENABLE, "master on off engine" },
    { "looks", L["Style preset"], "complete coordinated authored look " .. lookCatalogKeywords },
    { "looks", L["Shaded surfaces"], "material gradient on off", EXPERT },
    { "looks", L["Light direction"], "gradient horizontal vertical", EXPERT },
    { "looks", L["Shading strength"], "gradient intensity", EXPERT },
    { "looks", L["Surface depth"], "material depth relief", EXPERT },
    { "looks", L["Window opacity"], "shell transparency alpha" },
    { "looks", L["Content opacity"], "panel card transparency alpha" },
    { "looks", L["Controls opacity"], "button navigation transparency alpha" },
    { "looks", L["Outline opacity"], "border transparency alpha", EXPERT },
    { "icons", L["Button style"], "window action close x add remove maximize minimize bare soft outline native button" },
    { "icons", L["Maximize / minimize symbols"], "window action close x plus minus chevrons glyph fine bold size offset opacity shape radius inset smaller" },
    { "icons", L["Skin the Blizzard Micro Bar"], "micro menu micromenu minimenu buttons hud" },
    { "icons", L["Micro Bar style"], "forever modern compact glass preset" },
    { "icons", L["Icon colors"], "micro native theme class monochrome tint normal hover pressed disabled" },
    { "icons", L["Bar background"], "micro bar button plates surfaces backgrounds individual", EXPERT },
    { "icons", L["Bar and button shape"], "micro round continuous squircle radius outline border", EXPERT },
    { "icons", L["Normal icon opacity"], "micro icon state hover mouse-over pressed disabled alpha", EXPERT },
    { "icons", L["Verified item icon borders"], "item icon border style quality theme off" },
    { "icons", L["Border thickness"], "item icon border geometry distance padding opacity", EXPERT },
    { "colors", L["Surfaces"], "window panel colors background ink surface raised card popup input", EXPERT },
    { "colors", L["Color palette (colors only)"], "preset coordinated colors " .. paletteCatalogKeywords },
    { "colors", L["Text"], "text colors title muted dim disabled blizzard yellow gold chat system", EXPERT },
    { "colors", L["Accents"], "accent status colors bright blue success warning danger secondary", EXPERT },
    { "colors", L["Borders"], "border colors rim soft button icon outline", EXPERT },
    { "colors", L["Controls"], "button interaction colors fill hover pressed active checkmark selection", EXPERT },
    { "colors", L["Blizzard"], "blizzard symbol colors arrow dropdown plus minus expand close x pressed hover disabled", EXPERT },
    { "colors", L["Find a color or UI element..."], "exact rgba hex alpha color picker precise entry" },
    { "typography", L["Override Blizzard fonts"], "global font typeface enable disable" },
    { "typography", L["Font"], "typeface dropdown sharedmedia media addons" },
    { "typography", L["Chat, Communities and console text"], "chat font" },
    { "typography", L["Quest, mail, number and combat styles"], "font special" },
    { "typography", L["Custom font path (used by Custom path)"], "file ttf otf" },
    { "geometry", L["Window corner style"], "panel curve round continuous squircle" },
    { "geometry", L["Button corner style"], "control curve pill round continuous squircle" },
    { "geometry", L["Corner radius"], "4 6 8 12 px" },
    { "geometry", L["Outline thickness"], "border 0 1 2 px" },
    { "geometry", L["Hover highlight"], "hover style border only soft fill solid fill off" },
    { "geometry", L["Hover intensity"], "highlight strength" },
    { "skins", NS.L.SKIN_GAME_MENU, "escape esc buttons" },
    { "skins", NS.L.SKIN_SETTINGS, "blizzard settings options addon list dropdown scroll" },
    { "skins", NS.L.SKIN_WORLD_MAP, "map" },
    { "skins", NS.L.SKIN_PLAYER_SPELLS, "player spells" },
    { "skins", NS.L.SKIN_ENCOUNTER_JOURNAL, "encounter journal" },
    { "skins", NS.L.SKIN_CHAT_FRAMES, "chat windows tabs system npc colors" },
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
    { "hud", L["Window and header surfaces"], "damage meter windows header surfaces" },
    { "hud", L["Class-colored row plates"], "damage meter rows class color plates" },
    { "hud", L["Source detail window"], "damage meter source detail" },
    { "profiles", L["Active profile"], "switch" },
    { "profiles", L["Create clean"], "create copy current new duplicate profile" },
    { "profiles", L["Delete active"], "delete remove profile" },
    { "profiles", L["IMPORT / EXPORT"], "import export share backup MSKIN1 all profiles" },
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
        local definition = O.GetPageDefinition(key)
        local pageLabel = definition and definition.label or key
        local meta = O.GetPageMeta(key)
        local label = Normalize(item[2])
        records[index] = {
            page = key,
            label = item[2],
            pageLabel = pageLabel,
            expert = meta.simple == false or item[4] == EXPERT,
            lowerLabel = label,
            haystack = label .. " " .. Normalize(pageLabel) .. " " .. Normalize(item[3]) .. " " .. Normalize(meta.keywords),
            score = 0,
        }
    end
end

-- The words of the current query, split once per query and reused.
local queryTokens = {}

local function Tokenize(query)
    local count = 0
    for token in query:gmatch("%S+") do
        count = count + 1
        queryTokens[count] = token
    end
    for index = #queryTokens, count + 1, -1 do queryTokens[index] = nil end
    return count
end

local function MatchTokens(haystack, count)
    for index = 1, count do
        if not haystack:find(queryTokens[index], 1, true) then return false end
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
    local tokenCount = Tokenize(query)
    for index = 1, #records do
        local record = records[index]
        if MatchTokens(record.haystack, tokenCount) then
            record.score = Score(record.lowerLabel, query)
            results[#results + 1] = record
        end
    end
    table.sort(results, ByRelevance)
    for index = #results, (limit or 8) + 1, -1 do results[index] = nil end
    return results
end
