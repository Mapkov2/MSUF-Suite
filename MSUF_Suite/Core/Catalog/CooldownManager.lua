local _, NS = ...
local B = NS.CatalogBuild
local Number, Bool, Choice, String, Color, Font, Texture = B.Number, B.Bool, B.Choice, B.String, B.Color, B.Font, B.Texture

-- Settings for the cooldown manager. Bars are fixed slots: six built-in bars
-- (Blizzard's Cooldown Manager categories plus two preset rows) and six custom bars.
-- Per-bar rules are generated below; spell lists and per-spell choices are
-- two compact data strings (see CDM.Codec) so profiles, sharing and undo
-- carry them without extra database types.
local CDM = {}
NS.CDM = CDM

local function Available()
    if not NS.Client.isMainline then return false, "Cooldown manager needs Retail or WoW Forever" end
    local viewer, spell = _G.C_CooldownViewer, _G.C_Spell
    if type(viewer) ~= "table" or type(viewer.GetCooldownViewerCategorySet) ~= "function"
        or type(viewer.GetCooldownViewerCooldownInfo) ~= "function" then
        return false, "Blizzard's Cooldown Manager is not available on this client"
    end
    if type(spell) ~= "table" or type(spell.GetSpellCooldownDuration) ~= "function" then
        return false, "Cooldown manager needs Retail or WoW Forever"
    end
    if type(_G.MSUF_EncodeCompactTable) ~= "function" or type(_G.MSUF_TryDecodeCompactString) ~= "function" then
        return false, "Update MSUF to use the cooldown manager"
    end
    return true
end
CDM.Available = Available

B.Module("cooldownManager", {
    title = "Cooldown manager",
    description = "Cooldowns, buffs and buff bars from Blizzard's Cooldown Manager on fast MSUF bars: a centered stack, defensives and potions on the player frame, custom bars, glows, sounds and per-spell choices.",
    core = true, page = "suite_cooldownManager", available = Available,
    conflicts = { "CooldownManagerCentered", "EllesmereUICooldownManager", "Ayije_CDM", "SkironCooldownManager",
        "QUI_CDM", "BetterCooldownManager", "MidnightCooldownManager" },
})
local id = "cooldownManager"

------------------------------------------------------------------ slots
-- kind: 1 cooldown icons, 2 aura icons, 3 aura bars. Categories are
-- Enum.CooldownViewerCategory values the built-in bars follow.
CDM.KIND_COOLDOWN, CDM.KIND_AURA, CDM.KIND_BAR = 1, 2, 3
-- preset: "defensives" fills the bar with the class's defensive cooldowns
-- (runtime Presets.lua) until the user edits its list; "racials" appends the
-- character's racial to the bar's Blizzard entries.
CDM.SLOTS = {
    { key = "ess", title = "Essential cooldowns", kind = 1, builtin = true, categories = { 0 } },
    { key = "uti", title = "Utility cooldowns", kind = 1, builtin = true, categories = { 1 } },
    { key = "def", title = "Defensives", kind = 1, builtin = true, categories = {}, preset = "defensives" },
    { key = "ext", title = "Potions and racials", kind = 1, builtin = true, categories = { 5, 7 }, preset = "racials" },
    { key = "buf", title = "Buffs", kind = 2, builtin = true, categories = { 2, 6, 8 } },
    { key = "bar", title = "Buff bars", kind = 3, builtin = true, categories = { 3 } },
}
for i = 1, 6 do
    CDM.SLOTS[#CDM.SLOTS + 1] = { key = "c" .. i, title = "Custom bar " .. i, custom = true, categories = {} }
end
CDM.SLOT_INDEX = {}
for i, slot in ipairs(CDM.SLOTS) do CDM.SLOT_INDEX[slot.key] = i end
CDM.POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local POINT_LABELS = { "Top left", "Top", "Top right", "Left", "Center", "Right", "Bottom left", "Bottom", "Bottom right" }
-- Attach targets: 1 free, 2..#SLOTS+1 another bar, then MSUF's unit frames.
local ANCHOR_LABELS = { "Free" }
for i, slot in ipairs(CDM.SLOTS) do ANCHOR_LABELS[i + 1] = slot.title end
local PLAYER_ANCHOR, TARGET_ANCHOR = #ANCHOR_LABELS + 1, #ANCHOR_LABELS + 2
ANCHOR_LABELS[PLAYER_ANCHOR], ANCHOR_LABELS[TARGET_ANCHOR] = "Player frame", "Target frame"
CDM.ANCHOR_LABELS = ANCHOR_LABELS
CDM.FRAME_ANCHORS = { [PLAYER_ANCHOR] = "player", [TARGET_ANCHOR] = "target" }
CDM.SIDES = { "BELOW", "ABOVE", "LEFT", "RIGHT" }

------------------------------------------------------------------ module rules
B.Section(id, "general", "General", {
    Choice("blizzard", "Blizzard's cooldown bars", 1, { "Turn off (fastest)", "Keep running invisibly" }),
    Bool("showGCD", "Show the global cooldown on icons", false),
    Bool("readyGlowCombat", "Ready glows only in combat", true),
    Bool("muteSounds", "Mute cooldown manager sounds", false),
    Choice("soundChannel", "Sound channel", 1, { "Master", "Sound effects", "Dialog" }),
})
B.Section(id, "text", "Text", {
    Font("font", "Font"),
    Choice("fontOutline", "Text outline", 1, { "Outline", "Thick outline", "None" }),
    Color("cdColor", "Countdown color", "ffffff"),
    Color("stackColor", "Charges and stacks color", "ffffff"),
    Color("keybindColor", "Keybind color", "ffffff"),
    Number("thresholdSeconds", "Warn when fewer seconds remain (0 = off)", 0, 0, 10),
    Color("thresholdColor", "Warning countdown color", "ff5a3c"),
})
B.Section(id, "data", "Data", {
    String("listsData", "Bar contents", "", 60000),
    String("spellsData", "Per-spell choices", "", 60000),
    Bool("captured", "Blizzard layout captured", false),
    Number("defaultsVersion", "Defaults version", 0, 0, 1000),
    Bool("essOnViewer", "Essential bar x/y are an offset from Blizzard's bar", false),
})
-- Saved settings older than this are migrated once, because stored values
-- never follow a changed default on their own. 1: every bar setting takes
-- its current default (bar contents and per-spell choices stay). 2: x/y of
-- attached bars became offsets from their anchor, so they start at zero.
-- 3: free bars count from the screen center instead of the same UIParent
-- point (converted in place; unused custom bars start in the middle).
CDM.DEFAULTS_VERSION = 3
CDM.DEFAULTS_KEEP = { enabled = true, listsData = true, spellsData = true, captured = true, defaultsVersion = true,
    essOnViewer = true }

------------------------------------------------------------------ per-slot rules
-- Defaults per slot: one centered stack (Essential, Utility under it, Buffs
-- and Buff bars below that; MSUF's class resource sits on top when MSUF
-- follows these bars) plus two rows on MSUF's player frame: Defensives flush
-- right above it, Potions and racials flush left below it. Icons are 10:9.
-- The Essential position is taken once from Blizzard's bar on first use, or
-- set just below the screen center for the player's screen (runtime).
-- Gaps clear MSUF's default player debuff row (above the frame) and player
-- castbar (below it); Essential starts under that castbar.
-- side: 1 below, 2 above; align: 1 center, 2 start, 3 end. x/y of a free
-- bar are its position; of an attached bar, an offset from the attach point.
local D = {
    ess = { on = true, anchor = 1, side = 1, gap = 2, x = 0, y = -222, size = 40, height = 90, perRow = 9,
        grow = 1, usable = true, range = true, swipeAlpha = 70 },
    uti = { on = true, anchor = 2, side = 1, gap = 2, x = 0, y = 0, size = 32, height = 90, perRow = 12,
        grow = 1, usable = true, range = true, swipeAlpha = 70 },
    def = { on = true, anchor = PLAYER_ANCHOR, side = 2, gap = 44, align = 3, x = 0, y = 0, size = 32,
        height = 90, perRow = 10, grow = 2, usable = true, range = false, swipeAlpha = 70 },
    ext = { on = true, anchor = PLAYER_ANCHOR, side = 1, gap = 22, align = 2, x = 0, y = 0, size = 28,
        height = 90, perRow = 10, grow = 1, usable = false, range = false, swipeAlpha = 70 },
    buf = { on = true, anchor = 3, side = 1, gap = 4, x = 0, y = 0, size = 30, height = 90, perRow = 10,
        grow = 1, swipeAlpha = 60 },
    bar = { on = true, anchor = 6, side = 1, gap = 4, x = 0, y = 0, size = 20, perRow = 1, grow = 1,
        swipeAlpha = 60 },
}
local CUSTOM = { on = false, anchor = 1, side = 1, gap = 4, x = 0, y = 0, size = 36, perRow = 10, grow = 1,
    usable = true, range = true, swipeAlpha = 70 }

-- Groups by kind; custom slots carry every group because their kind changes.
local GROUPS = { common = true, icon = { [1] = true, [2] = true }, cooldown = { [1] = true },
    aura = { [2] = true, [3] = true }, bar = { [3] = true } }
local function Has(slot, group)
    if slot.custom or group == "common" then return true end
    return GROUPS[group][slot.kind] == true
end

CDM.KEYS = {}
CDM.SUFFIXES = {}
local function Rules(slot)
    local d = D[slot.key] or CUSTOM
    local p = slot.key .. "_"
    local list = {}
    local function Add(rule, suffix)
        rule.suffix = suffix
        list[#list + 1] = rule
    end
    -- common
    Add(Bool(p .. "on", "Show this bar", d.on), "on")
    Add(String(p .. "name", "Bar name", "", 24), "name")
    Add(Choice(p .. "kind", "Bar type", slot.kind or 1, { "Cooldowns", "Buff icons", "Buff bars" }), "kind")
    Add(Number(p .. "x", "Horizontal position", d.x, -4000, 4000), "x")
    Add(Number(p .. "y", "Vertical position", d.y, -3000, 3000), "y")
    Add(Choice(p .. "anchor", "Attach to", d.anchor, ANCHOR_LABELS), "anchor")
    Add(Choice(p .. "side", "Attach side", d.side, { "Below", "Above", "Left", "Right" }), "side")
    Add(Number(p .. "gap", "Attach gap", d.gap, 0, 60), "gap")
    Add(Number(p .. "alpha", "Opacity (percent)", 100, 0, 100, 5), "alpha")
    Add(Number(p .. "oocAlpha", "Opacity out of combat (percent)", 100, 0, 100, 5), "oocAlpha")
    Add(Choice(p .. "vis", "Show", 1, { "Always", "In combat", "In combat or with a target", "Hidden" }), "vis")
    Add(Bool(p .. "hideMounted", "Hide while mounted", false), "hideMounted")
    Add(Bool(p .. "hideVehicle", "Hide in vehicles", true), "hideVehicle")
    Add(Bool(p .. "tooltips", "Show tooltips", false), "tooltips")
    Add(Choice(p .. "strata", "Frame layer", 3, { "Background", "Low", "Medium", "High" }), "strata")
    if Has(slot, "icon") then
        Add(Number(p .. "size", "Icon size", d.size, 12, 96), "size")
        Add(Number(p .. "height", "Icon height (percent)", d.height or 100, 40, 100, 5), "height")
        Add(Number(p .. "spacing", "Icon spacing", 2, -2, 30), "spacing")
        Add(Number(p .. "perRow", "Icons per row", d.perRow, 1, 40), "perRow")
        Add(Number(p .. "maxIcons", "Maximum icons (0 = all)", 0, 0, 40), "maxIcons")
        Add(Bool(p .. "vertical", "Vertical", false), "vertical")
        Add(Choice(p .. "align", "Alignment", d.align or 1, { "Center", "Start", "End" }), "align")
        Add(Choice(p .. "grow", "New rows", d.grow, { "Down", "Up" }), "grow")
        Add(Number(p .. "zoom", "Icon zoom (percent)", 8, 0, 30), "zoom")
        Add(Number(p .. "border", "Border", 1, 0, 4), "border")
        Add(Color(p .. "borderColor", "Border color", "000000"), "borderColor")
        Add(Bool(p .. "borderClass", "Class-colored border", false), "borderClass")
        Add(Bool(p .. "cdText", "Show countdown", true), "cdText")
        Add(Number(p .. "cdSize", "Countdown size (0 = automatic)", 0, 0, 40), "cdSize")
        Add(Number(p .. "stackSize", "Charges and stacks size (0 = automatic)", 0, 0, 40), "stackSize")
        Add(Choice(p .. "stackPos", "Charges and stacks position", 9, POINT_LABELS), "stackPos")
        Add(Number(p .. "swipeAlpha", "Swipe opacity (percent)", d.swipeAlpha, 0, 100, 5), "swipeAlpha")
        Add(Bool(p .. "edge", "Show the swipe edge", false), "edge")
    end
    if Has(slot, "cooldown") then
        Add(Bool(p .. "desat", "Desaturate on cooldown", true), "desat")
        Add(Number(p .. "cdAlpha", "Opacity on cooldown (percent)", 100, 0, 100, 5), "cdAlpha")
        Add(Number(p .. "readyAlpha", "Opacity when ready (percent)", 100, 0, 100, 5), "readyAlpha")
        Add(Bool(p .. "hideReady", "Hide icons that are ready", false), "hideReady")
        Add(Bool(p .. "procGlow", "Spell alert glow", true), "procGlow")
        Add(Bool(p .. "readyGlow", "Glow when ready", false), "readyGlow")
        Add(Choice(p .. "glowStyle", "Glow style", 1, { "Blizzard alert", "Marching ants", "Pulse", "Border" }), "glowStyle")
        Add(Bool(p .. "glowTint", "Tint glows", false), "glowTint")
        Add(Color(p .. "glowColor", "Glow color", "ffd200"), "glowColor")
        Add(Bool(p .. "usable", "Color unusable spells", d.usable ~= false), "usable")
        Add(Bool(p .. "range", "Color out-of-range spells", d.range ~= false), "range")
        Add(Color(p .. "rangeColor", "Out-of-range color", "cc2e2e"), "rangeColor")
        Add(Bool(p .. "showAura", "Show active buff duration", true), "showAura")
        Add(Bool(p .. "charges", "Show charges", true), "charges")
        Add(Bool(p .. "keybind", "Show keybinds", d.keybind == true), "keybind")
        Add(Number(p .. "keybindSize", "Keybind size (0 = automatic)", 0, 0, 30), "keybindSize")
        Add(Choice(p .. "keybindPos", "Keybind position", 3, POINT_LABELS), "keybindPos")
        Add(Bool(p .. "assist", "Highlight the assisted combat suggestion", false), "assist")
        Add(Bool(p .. "bling", "Flash when ready", false), "bling")
    end
    if Has(slot, "aura") then
        Add(Bool(p .. "showMissing", "Show missing buffs dimmed", false), "showMissing")
        Add(Bool(p .. "keepSlots", "Keep buffs in fixed places", false), "keepSlots")
        Add(Bool(p .. "auraGlow", "Glow while active", false), "auraGlow")
        Add(Bool(p .. "pandemic", "Highlight the refresh window", true), "pandemic")
    end
    if Has(slot, "bar") then
        if not Has(slot, "icon") then Add(Choice(p .. "grow", "New rows", d.grow, { "Down", "Up" }), "grow") end
        Add(Number(p .. "barWidth", "Bar width", slot.key == "bar" and 220 or 200, 60, 480), "barWidth")
        Add(Number(p .. "barHeight", "Bar height", slot.key == "bar" and 20 or 18, 8, 48), "barHeight")
        Add(Texture(p .. "barTexture", "Bar texture"), "barTexture")
        Add(Color(p .. "barColor", "Bar color", NS.Client.isForever and "d8b66a" or "e8b855"), "barColor")
        Add(Bool(p .. "barClass", "Class-colored bars", true), "barClass")
        Add(Number(p .. "barBgAlpha", "Bar background opacity (percent)", 55, 0, 100, 5), "barBgAlpha")
        Add(Bool(p .. "barIcon", "Show icon", true), "barIcon")
        Add(Choice(p .. "barIconSide", "Icon side", 1, { "Left", "Right" }), "barIconSide")
        Add(Bool(p .. "barName", "Show name", true), "barName")
        Add(Bool(p .. "barTime", "Show time", true), "barTime")
        Add(Choice(p .. "barFill", "Bar direction", 1, { "Drain", "Fill" }), "barFill")
    end
    return list
end

for _, slot in ipairs(CDM.SLOTS) do
    local list = Rules(slot)
    local keys = {}
    for _, rule in ipairs(list) do
        keys[rule.suffix] = rule.key
        CDM.SUFFIXES[rule.suffix] = true
    end
    CDM.KEYS[slot.key] = keys
    B.Section(id, slot.key, slot.title, list, { slot = slot.key })
end

------------------------------------------------------------------ presentation metadata
local rules = NS.SuiteCatalog[id].rules
for _, key in ipairs({ "listsData", "spellsData", "captured", "defaultsVersion", "essOnViewer" }) do rules[key].hidden = true end
for _, slot in ipairs(CDM.SLOTS) do
    local k = CDM.KEYS[slot.key]
    local function Set(suffix, field, value) if k[suffix] then rules[k[suffix]][field] = value end end
    if slot.builtin then Set("name", "hidden", true); Set("kind", "hidden", true) end
    Set("x", "category", "advanced"); Set("y", "category", "advanced")
    Set("cdSize", "enableKey", k.cdText)
    Set("rangeColor", "enableKey", k.range)
    Set("keybindSize", "enableKey", k.keybind); Set("keybindPos", "enableKey", k.keybind)
    Set("glowColor", "enableKey", k.glowTint)
    Set("borderColor", "disabledBy", k.borderClass)
    Set("barColor", "disabledBy", k.barClass)
    if k.side then
        rules[k.side].requiresChoice = { key = k.anchor, values = {} }
        rules[k.gap].requiresChoice = rules[k.side].requiresChoice
        for i = 2, #ANCHOR_LABELS do rules[k.side].requiresChoice.values[i] = true end
    end
    -- One template set in the Colors painter, not eleven copies.
    if slot.key ~= "ess" then
        for suffix in pairs(k) do
            if rules[k[suffix]].color then rules[k[suffix]].hideInColors = true end
        end
    end
end

------------------------------------------------------------------ entry keys and data codec
-- Entry keys: b<cooldownID> Blizzard entry, s<spellID> spell, i<itemID> item,
-- e<slot> equipment slot, a<spellID> helpful aura on the player,
-- d<spellID> harmful aura the player cast on the target.
local ENTRY_KINDS = { b = true, s = true, i = true, e = true, a = true, d = true }
function CDM.ValidEntryKey(key)
    if type(key) ~= "string" or #key < 2 or #key > 16 then return false end
    local kind, number = key:match("^(%l)(%d+)$")
    if not kind or not ENTRY_KINDS[kind] then return false end
    number = tonumber(number)
    if not number or number <= 0 or number >= 2147483648 then return false end
    if kind == "e" and number > 19 then return false end
    return true
end
function CDM.EntryKind(key) return key:sub(1, 1) end
function CDM.EntryID(key) return tonumber(key:sub(2)) end
function CDM.IsAuraKey(key)
    local kind = key:sub(1, 1)
    return kind == "a" or kind == "d"
end

local function Bool01(value) return type(value) == "boolean" end
local function Range(min, max)
    return function(value)
        return type(value) == "number" and value == value and value >= min and value <= max
            and math.floor(value) == value
    end
end
local function Hex(value) return type(value) == "string" and #value == 6 and not value:find("[^%x]") end
local function Sound(value)
    if type(value) ~= "string" or #value > 120 then return false end
    if value == "" then return true end
    return value:find("^lsm:.+") ~= nil or value:find("^kit:%d+$") ~= nil or value:find("^file:%d+$") ~= nil
end
CDM.SPELL_FIELDS = {
    procGlow = Bool01, readyGlow = Bool01, auraGlow = Bool01, glowStyle = Range(1, 4), glowColor = Hex,
    desat = Range(1, 3), hideReady = Bool01, readyAlpha = Range(0, 100), cdAlpha = Range(0, 100),
    showAura = Bool01, swipe = Range(1, 3), sound = Sound, lossSound = Sound, tts = Bool01,
    threshold = Range(0, 10), icon = Range(1, 2147483647), showMissing = Bool01,
}
CDM.LIMITS = { specs = 64, entries = 60, hidden = 400, spells = 600 }

local function ValidSpec(value) return type(value) == "number" and value > 0 and value < 100000 and math.floor(value) == value end

-- Returns a clean copy; anything malformed is dropped rather than rejected.
function CDM.CleanLists(data)
    local out = { v = 1, specs = {}, hidden = {} }
    if type(data) ~= "table" then return out end
    local specCount = 0
    if type(data.specs) == "table" then
        for spec, slots in pairs(data.specs) do
            if ValidSpec(spec) and type(slots) == "table" and specCount < CDM.LIMITS.specs then
                local cleanSlots, any = {}, false
                for slotKey, list in pairs(slots) do
                    if CDM.SLOT_INDEX[slotKey] and type(list) == "table" then
                        local clean, seen = {}, {}
                        for i = 1, math.min(#list, CDM.LIMITS.entries) do
                            local key = list[i]
                            if CDM.ValidEntryKey(key) and not seen[key] then
                                seen[key] = true
                                clean[#clean + 1] = key
                            end
                        end
                        cleanSlots[slotKey] = clean
                        any = true
                    end
                end
                if any then out.specs[spec] = cleanSlots; specCount = specCount + 1 end
            end
        end
    end
    if type(data.hidden) == "table" then
        for spec, set in pairs(data.hidden) do
            if ValidSpec(spec) and type(set) == "table" then
                local clean, count = {}, 0
                for key, flag in pairs(set) do
                    if flag == true and CDM.ValidEntryKey(key) and count < CDM.LIMITS.hidden then
                        clean[key] = true
                        count = count + 1
                    end
                end
                if count > 0 then out.hidden[spec] = clean end
            end
        end
    end
    return out
end

function CDM.CleanSpells(data)
    local out = { v = 1, e = {} }
    if type(data) ~= "table" or type(data.e) ~= "table" then return out end
    local count = 0
    for key, fields in pairs(data.e) do
        if count >= CDM.LIMITS.spells then break end
        if CDM.ValidEntryKey(key) and type(fields) == "table" then
            local clean, any = {}, false
            for field, value in pairs(fields) do
                local valid = CDM.SPELL_FIELDS[field]
                if valid and valid(value) then clean[field] = value; any = true end
            end
            if any then out.e[key] = clean; count = count + 1 end
        end
    end
    return out
end

local Codec = {}
CDM.Codec = Codec
-- Empty strings mean "no customization". Decoding never raises; a damaged
-- string yields the empty structure.
function Codec.DecodeLists(text)
    if type(text) ~= "string" or text == "" then return CDM.CleanLists(nil) end
    local decode = _G.MSUF_TryDecodeCompactString
    return CDM.CleanLists(type(decode) == "function" and decode(text) or nil)
end
function Codec.DecodeSpells(text)
    if type(text) ~= "string" or text == "" then return CDM.CleanSpells(nil) end
    local decode = _G.MSUF_TryDecodeCompactString
    return CDM.CleanSpells(type(decode) == "function" and decode(text) or nil)
end
local function Empty(tbl)
    for _, value in pairs(tbl) do
        if type(value) ~= "table" or next(value) ~= nil then return false end
    end
    return true
end
local function Encode(clean, check)
    if check then return "" end
    local encode = _G.MSUF_EncodeCompactTable
    if type(encode) ~= "function" then return nil, "MSUF codec unavailable" end
    local text = encode(clean, "MSUF3")
    if type(text) ~= "string" then return nil, "Could not store the list" end
    if #text > 60000 then return nil, "Too many entries" end
    return text
end
function Codec.EncodeLists(data)
    local clean = CDM.CleanLists(data)
    return Encode(clean, Empty(clean.specs) and Empty(clean.hidden))
end
function Codec.EncodeSpells(data)
    local clean = CDM.CleanSpells(data)
    return Encode(clean, next(clean.e) == nil)
end
