local _, NS = ...
-- Validated entry keys, lists, spell choices and specialization layouts.
-- Loaded after the settings schema; callers keep the same CDM codec API.
local CDM = NS.CDM
local rules = NS.SuiteCatalog.cooldownManager.rules

------------------------------------------------------------------ entry keys and data codec
-- Entry keys: b<cooldownID> Blizzard entry, s<spellID> spell, i<itemID> item,
-- e<slot> equipment slot, a<spellID> helpful aura on the player,
-- d<spellID> harmful aura the player cast on the target.
local ENTRY_KINDS = { b = true, s = true, i = true, e = true, a = true, d = true }
-- One aura entry for several spells of one effect. The key's number is not a
-- spell and never reaches a spell API: `spell` gives the icon and tooltip,
-- `ids` are the player auras looked for, from any caster, in one icon or bar
-- (the haste buff: Bloodlust, Heroism, Time Warp, Ancient Hysteria,
-- Netherwinds, Primal Rage, the drums and Fury of the Aspects; not the
-- Sated lockouts, which the Bloodlust lockout card reports).
CDM.HASTE_KEY = "a2000002825"
CDM.AURA_GROUPS = {
    [2000002825] = { spell = 2825, name = "Bloodlust (any source)",
        ids = { 2825, 32182, 80353, 90355, 160452, 264667, 309658, 390386 } },
}
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
-- A per-spell color, or "" for the bar's color (the default stack color).
local function OwnHex(value) return value == "" or Hex(value) end
local function Sound(value)
    if type(value) ~= "string" or #value > 120 then return false end
    if value == "" then return true end
    return value:find("^lsm:.+") ~= nil or value:find("^kit:%d+$") ~= nil or value:find("^file:%d+$") ~= nil
end
-- A bar's own name for the entry: up to 40 characters, no escape sequences
-- ("|") or control characters; "" is a specialization's explicit spell name.
local function Label(value) return type(value) == "string" and #value <= 40 and not value:find("[|%c]") end
-- Per-spell choice values; absent (the menu's 0) is the bar's setting.
-- timeText and stackText: 2 show, 3 hide; textTop: 2 stacks on top,
-- 3 countdown on top (K.Choice reads 2 as yes and 3 as no).
CDM.CHOICE = { BAR = 1, YES = 2, NO = 3 }
-- desat: 2 never, 3 always. swipe: 1 normal, 2 reversed, 3 hidden.
-- stackGlowOp: at least, exactly, more than, below or at most the stackGlow count.
-- actionGlowMode: 1 while the buff is present, 2 the stack comparison.
CDM.DESAT = { NEVER = 2, ALWAYS = 3 }
CDM.SWIPE = { NORMAL = 1, REVERSED = 2, HIDDEN = 3 }
CDM.STACK_OP = { AT_LEAST = 1, EXACTLY = 2, MORE_THAN = 3, BELOW = 4, AT_MOST = 5 }
CDM.ACTION_GLOW = { PRESENT = 1, STACKS = 2 }
-- glowStyle (1 Blizzard alert, 2 Marching ants, 3 Pulse, 4 Border, 5 Pixel, 6 Autocast) and
-- glowColor style every glow of the entry: ready, spell alert, "glow while
-- active" and the stack glow; absent, the bar's glow style and tint apply.
-- A specialization stores glowStyle 0 for "the bar's style" and glowColor
-- or stackColor "" for the bar's (default) color explicitly, so it does not
-- inherit the shared choice. Older builds drop these and inherit.
-- stackGlow: glow while the aura has at least N applications (0 = off).
-- stackColorAt: stack text in stackColor from N applications (0 = off).
CDM.SPELL_FIELDS = {
    procGlow = Bool01, readyGlow = Bool01, readyResources = Bool01, fullChargeGlow = Bool01,
    chargeSwipe = Bool01, chargeEdge = Bool01, auraGlow = Bool01, pandemic = Bool01, glowStyle = Range(0, 6), glowColor = OwnHex,
    desat = Range(1, 3), hideReady = Bool01, hideAvailableCharges = Bool01, readyAlpha = Range(0, 100), cdAlpha = Range(0, 100),
    showAura = Bool01, swipe = Range(1, 3), sound = Sound, lossSound = Sound, tts = Bool01,
    threshold = Range(0, 10), icon = Range(1, 2147483647), showMissing = Bool01,
    stackGlow = Range(0, 99), stackGlowOp = Range(1, 5), stackColorAt = Range(0, 99), stackColor = OwnHex,
    -- Where a buff-bar aura is looked for: 1 automatic (audited native aura
    -- identities, then cast polarity), 2 the player, 3 the target, 4 both.
    auraUnit = Range(1, 4),
    timerDuration = Range(0, 600), timerSpell = Range(1, 2147483647),
    -- Countdown and charge/stack text: 1 the bar's setting, 2 show, 3 hide.
    -- textTop: 1 the bar's setting, 2 stacks on top, 3 countdown on top.
    timeText = Range(1, 3), stackText = Range(1, 3), textTop = Range(1, 3),
    showGCD = Bool01, actionGlowSpell = Range(1, 2147483647), actionGlowMode = Range(1, 2),
    actionGlowRequireSpell = Range(1, 2147483647), actionGlowUnit = Range(1, 2), actionUsableGlow = Bool01,
    requireSpell1 = Range(1, 2147483647), requireSpell2 = Range(1, 2147483647), requireSpell3 = Range(1, 2147483647),
    excludeSpell1 = Range(1, 2147483647), excludeSpell2 = Range(1, 2147483647), excludeSpell3 = Range(1, 2147483647),
    -- Cooldown icons that show only while usable or during the spell alert;
    -- the border while the buff is active ("": the bar's border); a glow on
    -- a missing buff's stand-in; an item's use buff on its icon; the bar
    -- color and name of buff bars and timer bars ("": the bar's color, the
    -- spell's name); sounds when the cooldown starts and a charge returns.
    usableOnly = Bool01, procOnly = Bool01, activeBorder = OwnHex, missingGlow = Bool01, itemAura = Bool01,
    barColor = OwnHex, barText = Label, usedSound = Sound, chargeSound = Sound,
}
-- What an absent per-spell field means where no bar setting stands behind it.
CDM.SPELL_DEFAULTS = { stackColor = "ff5a3c" }
CDM.LIMITS = { specs = 64, entries = 120, hidden = 400, spells = 600 }

local function ValidSpec(value) return type(value) == "number" and value > 0 and value < 100000 and math.floor(value) == value end

-- The parts of CDM.CleanLists, each filling its part of out from data.
local function CleanShared(data, out)
    if type(data.shared) == "table" then
        for slot, list in pairs(data.shared) do
            local index = CDM.SLOT_INDEX[slot]
            if index and CDM.SLOTS[index].custom and type(list) == "table" then
                local clean, seen = {}, {}
                for i = 1, math.min(#list, CDM.LIMITS.entries) do
                    local key = list[i]
                    -- Blizzard record IDs are specialization-specific; shared
                    -- groups accept explicit spells, received auras and items.
                    if CDM.ValidEntryKey(key) and CDM.EntryKind(key) ~= "b" and not seen[key] then
                        clean[#clean + 1], seen[key] = key, true
                    end
                end
                out.shared[slot] = clean
            end
        end
    end
end
local function CleanSpecs(data, out)
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
                        -- Cross-spec additions inherit that spec's live defaults.
                        -- A manual reorder/import materializes an ordinary list.
                        if list.inherit == true and (slotKey == "ess" or slotKey == "uti"
                            or slotKey == "buf" or slotKey == "bar") then clean.inherit = true end
                        cleanSlots[slotKey] = clean
                        any = true
                    end
                end
                if any then
                    out.specs[spec] = cleanSlots
                    specCount = specCount + 1
                end
            end
        end
    end
end
local function CleanHidden(data, out)
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
end
-- A copied Blizzard layout is a complete selection for each built-in bar.
-- Older saved lists have no replace map and retain append-new-spells.
local function CleanReplace(data, out)
    if type(data.replace) == "table" then
        for spec, slots in pairs(data.replace) do
            if ValidSpec(spec) and type(slots) == "table" and out.specs[spec] then
                local clean = {}
                for slot, flag in pairs(slots) do
                    if flag == true and CDM.SLOT_INDEX[slot] and out.specs[spec][slot] then
                        clean[slot] = true
                    end
                end
                if next(clean) then out.replace[spec] = clean end
            end
        end
    end
end

-- Returns a clean copy; anything malformed is dropped rather than rejected.
function CDM.CleanLists(data)
    local out = { v = 1, specs = {}, hidden = {}, replace = {}, shared = {} }
    if type(data) ~= "table" then return out end
    CleanShared(data, out)
    CleanSpecs(data, out)
    CleanHidden(data, out)
    CleanReplace(data, out)
    return out
end

local function CleanSpellMap(source)
    local out = {}
    if type(source) ~= "table" then return out end
    local count = 0
    for key, fields in pairs(source) do
        if count >= CDM.LIMITS.spells then break end
        if CDM.ValidEntryKey(key) and type(fields) == "table" then
            local clean, any = {}, false
            for field, value in pairs(fields) do
                local valid = CDM.SPELL_FIELDS[field]
                if valid and valid(value) then
                    clean[field] = value
                    any = true
                end
            end
            if any then
                out[key] = clean
                count = count + 1
            end
        end
    end
    return out
end

-- v1's e map is the shared base. v2 adds sparse per-spec differences: clearing
-- a spec choice resumes inheritance, without overwriting the shared value.
function CDM.CleanSpells(data)
    local out = { v = 2, e = {}, s = {} }
    if type(data) ~= "table" then return out end
    out.e = CleanSpellMap(data.e)
    if type(data.s) == "table" then
        local count = 0
        for spec, fields in pairs(data.s) do
            if count >= CDM.LIMITS.specs then break end
            if ValidSpec(spec) then
                local clean = CleanSpellMap(fields)
                if next(clean) then out.s[spec], count = clean, count + 1 end
            end
        end
    end
    return out
end

-- Called on a settings/spec change, never from cooldown events. Unmodified
-- entries reuse the base table; only entries with spec choices need a merge.
function CDM.EffectiveSpells(data, spec)
    local base = type(data) == "table" and type(data.e) == "table" and data.e or {}
    local selected = type(data) == "table" and type(data.s) == "table" and data.s[spec]
    if type(selected) ~= "table" or not next(selected) then return base end
    local out = {}
    for key, fields in pairs(base) do out[key] = fields end
    for key, fields in pairs(selected) do
        local merged = {}
        for field, value in pairs(base[key] or {}) do merged[field] = value end
        for field, value in pairs(fields) do merged[field] = value end
        out[key] = merged
    end
    return out
end

-- "Save bar layout per specialization" (runtime Settings.lua): spec is the
-- specialization the flat settings hold now, specs[id] every other one's
-- layout per bar, by setting suffix ("assist": the assisted icon's x/y).
-- The layout is where a bar sits and how it is arranged: attachment,
-- growth, rows, spacing and size. r marks Essential x/y saved as an offset
-- from Blizzard's bar (essOnViewer). Places of the first format (x, y and
-- the attach target as a) read as that part of the layout.
CDM.LAYOUT_SUFFIXES = { "x", "y", "anchor", "anchorFrame", "side", "gap", "align", "grow", "vertical", "perRow",
    "spacing", "size", "height", "centerFirst", "laterPerRow", "laterSize", "barWidth", "barHeight" }
CDM.PLACE_KEYS = { assist = { x = "assistIconX", y = "assistIconY" } }
for _, slot in ipairs(CDM.SLOTS) do
    local keys, place = CDM.KEYS[slot.key], {}
    for _, suffix in ipairs(CDM.LAYOUT_SUFFIXES) do place[suffix] = keys[suffix] end
    CDM.PLACE_KEYS[slot.key] = place
end
local function Valid(rule, value)
    if type(rule.default) == "boolean" then return type(value) == "boolean" end
    if type(rule.default) == "string" then return type(value) == "string" and #value <= rule.maxLength end
    return type(value) == "number" and value >= rule.min and value <= rule.max and math.floor(value) == value
end
local function CleanPlace(place, keys)
    if type(place) ~= "table" then return nil end
    local clean, any = {}, false
    for suffix, key in pairs(keys) do
        local value = place[suffix]
        if value == nil and suffix == "anchor" then value = place.a end
        if value ~= nil and Valid(rules[key], value) then clean[suffix], any = value, true end
    end
    if not any then return nil end
    if keys.anchor then clean.r = place.r == true or nil end
    return clean
end
function CDM.CleanPositions(data)
    local out = { v = 2, specs = {} }
    if type(data) ~= "table" then return out end
    if ValidSpec(data.spec) then out.spec = data.spec end
    if type(data.specs) ~= "table" then return out end
    local count = 0
    for spec, places in pairs(data.specs) do
        if count >= CDM.LIMITS.specs then break end
        if ValidSpec(spec) and type(places) == "table" then
            local clean = {}
            for slot, keys in pairs(CDM.PLACE_KEYS) do clean[slot] = CleanPlace(places[slot], keys) end
            if next(clean) then out.specs[spec], count = clean, count + 1 end
        end
    end
    return out
end

local Codec = {}
CDM.Codec = Codec
-- Empty strings mean "no customization". Decoding never raises; a damaged
-- string yields the empty structure.
local function Decode(text, Clean)
    if type(text) ~= "string" or text == "" then return Clean(nil) end
    local decode = _G.MSUF_TryDecodeCompactString
    return Clean(type(decode) == "function" and decode(text) or nil)
end
function Codec.DecodeLists(text) return Decode(text, CDM.CleanLists) end
function Codec.DecodeSpells(text) return Decode(text, CDM.CleanSpells) end
function Codec.DecodePositions(text) return Decode(text, CDM.CleanPositions) end
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
    return Encode(clean, Empty(clean.specs) and Empty(clean.hidden) and Empty(clean.replace) and Empty(clean.shared))
end
function Codec.EncodeSpells(data)
    local clean = CDM.CleanSpells(data)
    return Encode(clean, next(clean.e) == nil and next(clean.s) == nil)
end
function Codec.EncodePositions(data)
    local clean = CDM.CleanPositions(data)
    return Encode(clean, clean.spec == nil and next(clean.specs) == nil)
end
