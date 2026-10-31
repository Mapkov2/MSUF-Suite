local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_CooldownManager")
local Number, Bool, Choice, String, Color, Texture = B.Number, B.Bool, B.Choice, B.String, B.Color, B.Texture

-- Settings for the cooldown manager. Bars are fixed slots: six built-in bars
-- (Blizzard's Cooldown Manager categories plus two preset rows) and six custom bars.
-- Per-bar rules are generated below; spell lists and per-spell choices are
-- two compact data strings (see CDM.Codec) so profiles, sharing and undo
-- carry them without extra database types.
local CDM = {}
NS.CDM = CDM

-- Blizzard's Cooldown Manager API exists on Retail and Forever. The data
-- strings need MSUF's codec, which older MSUF builds do not export.
local function Available()
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
    cvars = { cooldownViewerEnabled = true },
    -- A global look recolors texts, borders, glows and bars from its palette.
    look = {
        extra = function(values, lookIndex)
            local palette = NS.DataTextLooks[lookIndex]
            values.cdColor, values.stackColor, values.keybindColor = palette.value, palette.value, palette.value
            for _, slot in ipairs(CDM.SLOTS) do
                local keys = CDM.KEYS[slot.key]
                if keys.borderColor then values[keys.borderColor] = palette.border end
                if keys.glowColor then values[keys.glowColor] = palette.accent end
                if keys.barColor then values[keys.barColor] = palette.accent end
            end
        end,
    },
})
local id = "cooldownManager"

------------------------------------------------------------------ slots
-- Bar kinds, the values of the "Bar type" choice: cooldown icons, aura
-- (buff) icons and aura bars. Categories are Enum.CooldownViewerCategory
-- values the built-in bars follow (runtime Catalog.lua BAR_OF mirrors them).
-- Essential also takes the equipment slot pool (7, trinkets), after its own
-- entries in Blizzard's order.
CDM.KIND = { COOLDOWN = 1, AURA_ICON = 2, AURA_BAR = 3 }
local KIND = CDM.KIND
-- The "Show" choice of a bar.
CDM.VIS = { ALWAYS = 1, COMBAT = 2, COMBAT_OR_TARGET = 3, HIDDEN = 4 }
-- Hide conditions with a macro conditional, in driver order (runtime
-- Visibility.lua; CDMInspection.lua asks the same conditions).
CDM.HIDE_MACROS = { { suffix = "hideResting", macro = "[resting]" }, { suffix = "hideSolo", macro = "[nogroup]" },
    { suffix = "hideFlying", macro = "[flying]" }, { suffix = "hideDead", macro = "[@player,dead]" } }
-- "Hide outside instances": the IsInInstance types that count as inside.
CDM.INSTANCES = { party = true, raid = true, scenario = true, pvp = true, arena = true }
-- The bar's "Text on top" choice.
CDM.TEXT_TOP = { STACKS = 1, COUNTDOWN = 2 }
-- The family of a Blizzard catalog entry: cooldown spells (Essential,
-- Utility, equipment and potion pools) or auras (tracked buffs and bars).
CDM.FAMILY = { COOLDOWN = 1, AURA = 2 }
-- The bar's layout choices; each value is the saved index of the choice's
-- label list. "New rows" grow down or up (a vertical bar: right or left),
-- "Alignment" places each row, "Attach side" the bar next to its target.
CDM.GROW = { DOWN = 1, UP = 2 }
CDM.ALIGN = { CENTER = 1, START = 2, END = 3 }
CDM.SIDE = { BELOW = 1, ABOVE = 2, LEFT = 3, RIGHT = 4 }
-- "Attach to": free, then another bar (its slot index plus FREE), then
-- MSUF's player and target frames, then any other frame by name (append-only:
-- saved indices keep their meaning). "Send excess cooldowns to": off, then a
-- bar the same way (slot index plus OFF).
CDM.ANCHOR = { FREE = 1 }
CDM.OVERFLOW = { OFF = 1 }
-- Aura bars: "Bar direction" (the timer drains or fills) and "Icon side".
CDM.BAR_FILL = { DRAIN = 1, FILL = 2 }
CDM.BAR_ICON_SIDE = { LEFT = 1, RIGHT = 2 }
-- "Blizzard's cooldown bars": turned off, or running invisibly.
CDM.BLIZZARD = { OFF = 1, INVISIBLE = 2 }
-- preset: "defensives" fills the bar with the class's defensive cooldowns
-- (runtime Presets.lua) until the user edits its list; "racials" appends the
-- character's racial to the bar's Blizzard entries (potions and healthstones).
CDM.SLOTS = {
    { key = "ess", title = "Essential cooldowns", kind = KIND.COOLDOWN, builtin = true, categories = { 0, 7 } },
    { key = "uti", title = "Utility cooldowns", kind = KIND.COOLDOWN, builtin = true, categories = { 1 } },
    { key = "def", title = "Defensives", kind = KIND.COOLDOWN, builtin = true, categories = {}, preset = "defensives" },
    { key = "ext", title = "Potions and racials", kind = KIND.COOLDOWN, builtin = true, categories = { 5 },
        preset = "racials" },
    { key = "buf", title = "Buffs", kind = KIND.AURA_ICON, builtin = true, categories = { 2, 6, 8 } },
    { key = "bar", title = "Buff bars", kind = KIND.AURA_BAR, builtin = true, categories = { 3 } },
}
for i = 1, 6 do
    CDM.SLOTS[#CDM.SLOTS + 1] = { key = "c" .. i, title = NS.Text("Custom bar %d"):format(i), custom = true, categories = {} }
end
CDM.SLOT_INDEX = {}
for i, slot in ipairs(CDM.SLOTS) do CDM.SLOT_INDEX[slot.key] = i end
-- The "Attach to" value of another bar.
local function AttachTo(key) return CDM.SLOT_INDEX[key] + CDM.ANCHOR.FREE end
CDM.POINTS = NS.AnchorPoints
local POINT_LABELS = NS.AnchorLabels
-- Attach targets: 1 free, 2..#SLOTS+1 another bar, then MSUF's unit frames.
local ANCHOR_LABELS = { "Free" }
local OVERFLOW_LABELS = { "Off" }
for i, slot in ipairs(CDM.SLOTS) do ANCHOR_LABELS[i + 1] = slot.title end
for i, slot in ipairs(CDM.SLOTS) do OVERFLOW_LABELS[i + 1] = slot.title end
local PLAYER_ANCHOR, TARGET_ANCHOR, OTHER_ANCHOR = #ANCHOR_LABELS + 1, #ANCHOR_LABELS + 2, #ANCHOR_LABELS + 3
ANCHOR_LABELS[PLAYER_ANCHOR], ANCHOR_LABELS[TARGET_ANCHOR] = "Player frame", "Target frame"
ANCHOR_LABELS[OTHER_ANCHOR] = "Other frame"
CDM.ANCHOR_LABELS = ANCHOR_LABELS
CDM.FRAME_ANCHORS = { [PLAYER_ANCHOR] = "player", [TARGET_ANCHOR] = "target" }
-- "Other frame": the global frame named by the bar's "Frame name" (runtime
-- FrameAnchors.lua follows its rectangle like MSUF's own frames).
CDM.OTHER_ANCHOR = OTHER_ANCHOR

------------------------------------------------------------------ module rules
local SPEC_LAYOUT_TIP =
    "Each specialization keeps its own bar layout: positions, attachments, growth, rows, spacing and sizes. Until it has its own, it uses the current one."
B.Section(id, "general", "General", {
    Choice("blizzard", "Blizzard's cooldown bars", CDM.BLIZZARD.OFF, { "Turn off (fastest)", "Keep running invisibly" }),
    B.Tooltip(Bool("raidEssentials", "Use MSUF cooldown profiles by specialization", true),
        "Uses MSUF's default spell lists for each specialization. Your own list changes are kept. This does not switch Suite profiles."),
    Bool("showGCD", "Show the global cooldown on icons", false),
    Bool("readyGlowCombat", "Ready glows only in combat", true),
    Bool("pulseCombat", "Pulse only in combat", true),
    Number("pulseSize", "Ready pulse size", 96, 32, 256),
    Number("pulseY", "Ready pulse vertical position", 120, -1000, 1000),
    Number("pulseHold", "Ready pulse hold time (seconds)", 0.5, 0.1, 3, 0.1),
    Bool("allGlowsCombat", "All glows only in combat", false),
    Bool("pressFeedback", "Show action bar presses on cooldown icons", false),
    Bool("potionStockIcon", "Show a stocked potion on potion category icons", false),
    Bool("assistIcon", "Standalone assisted combat icon", false),
    Bool("assistIconKeybind", "Assisted icon keybind badge", true),
    Bool("assistIconGCD", "Assisted icon global cooldown swipe", true),
    Bool("keybindStable", "Keep key labels stable across action pages and forms", true),
    Number("assistIconSize", "Assisted icon size", 48, 20, 96),
    Number("assistIconX", "Assisted icon horizontal offset", 0, -4000, 4000),
    Number("assistIconY", "Assisted icon vertical offset", -180, -3000, 3000),
    Choice("assistIconVis", "Assisted icon visibility", CDM.VIS.ALWAYS, { "Always", "In combat", "In combat or with a target" }),
    Number("assistIconAlpha", "Assisted icon opacity (percent)", 100, 0, 100),
    Number("assistIconBorder", "Assisted icon border size", 0, 0, 6),
    Color("assistIconBorderColor", "Assisted icon border color", "000000"),
    Number("assistIconZoom", "Assisted icon zoom (percent)", 8, 0, 30),
    Number("assistIconKeySize", "Assisted icon keybind text size (0 = automatic)", 0, 0, 40),
    Choice("assistIconKeyPos", "Assisted icon keybind position", 9, POINT_LABELS),
    Choice("assistIconAnchor", "Assisted icon attachment", 1, { "Free", "Essential cooldowns", "Player frame" }),
    Bool("muteSounds", "Mute cooldown manager sounds", false),
    Choice("soundChannel", "Sound channel", 1, { "Master", "Sound effects", "Dialog" }),
    B.Tooltip(Bool("specPositions", "Save bar layout per specialization", true), SPEC_LAYOUT_TIP),
})
B.TextSection(id, {
    Color("cdColor", "Countdown color", "ffffff"),
    Color("stackColor", "Charges and stacks color", "ffffff"),
    Color("keybindColor", "Keybind color", "ffffff"),
    Number("thresholdSeconds", "Warn when fewer seconds remain (0 = off)", 0, 0, 10),
    Color("thresholdColor", "Warning countdown color", "ff5a3c"),
    Number("tenthsSeconds", "Show tenths below (seconds, 0 = off)", 0, 0, 10),
    Number("urgentSeconds", "Urgent warning below (seconds, 0 = off)", 0, 0, 10),
    Color("urgentColor", "Urgent warning color", "ff2020"),
})
B.Section(id, "data", "Data", {
    String("listsData", "Bar contents", "", 60000),
    String("spellsData", "Per-spell choices", "", 60000),
    Bool("captured", "Blizzard layout captured", false),
    Number("defaultsVersion", "Defaults version", 0, 0, 1000),
    Bool("essOnViewer", "Essential bar x/y are an offset from Blizzard's bar", false),
    String("positionsData", "Bar layouts by specialization", "", 60000),
})
-- Saved settings older than this are migrated once, because stored values
-- never follow a changed default on their own. 1: every bar setting takes
-- its current default (bar contents and per-spell choices stay). 2: x/y of
-- attached bars became offsets from their anchor, so they start at zero.
-- 3: free bars count from the screen center instead of the same UIParent
-- point (converted in place; unused custom bars start in the middle).
-- A new version that changes what x/y mean converts or drops the layouts
-- positionsData keeps for the other specializations as well.
CDM.DEFAULTS_VERSION = 3
CDM.DEFAULTS_KEEP = { enabled = true, raidEssentials = true, listsData = true, spellsData = true, captured = true, defaultsVersion = true,
    essOnViewer = true, specPositions = true }

------------------------------------------------------------------ per-slot rules
-- Defaults per slot: one centered stack (Essential, Utility under it, Buffs
-- and Buff bars below that; MSUF's class resource sits on top when MSUF
-- follows these bars) plus two rows on MSUF's player frame: Defensives flush
-- right above it, Potions and racials flush left below it. Icons are 10:9.
-- The Essential position is taken once from Blizzard's bar on first use, or
-- set just below the screen center for the player's screen (runtime).
-- Gaps clear MSUF's default player debuff row (above the frame) and player
-- castbar (below it); Essential starts under that castbar.
-- x/y of a free bar are its position; of an attached bar, an offset from
-- the attach point.
local FREE, BELOW, ABOVE = CDM.ANCHOR.FREE, CDM.SIDE.BELOW, CDM.SIDE.ABOVE
local DOWN, UP = CDM.GROW.DOWN, CDM.GROW.UP
local D = {
    ess = { on = true, anchor = FREE, side = BELOW, gap = 2, x = 0, y = -222, size = 40, height = 90, perRow = 9,
        grow = DOWN, usable = true, range = true, swipeAlpha = 70 },
    uti = { on = true, anchor = AttachTo("ess"), side = BELOW, gap = 2, x = 0, y = 0, size = 32, height = 90, perRow = 12,
        grow = DOWN, usable = true, range = true, swipeAlpha = 70 },
    def = { on = true, anchor = PLAYER_ANCHOR, side = ABOVE, gap = 44, align = CDM.ALIGN.END, x = 0, y = 0, size = 32,
        height = 90, perRow = 10, grow = UP, usable = true, range = false, swipeAlpha = 70 },
    ext = { on = true, anchor = PLAYER_ANCHOR, side = BELOW, gap = 22, align = CDM.ALIGN.START, x = 0, y = 0, size = 28,
        height = 90, perRow = 10, grow = DOWN, usable = false, range = false, swipeAlpha = 70 },
    buf = { on = true, anchor = AttachTo("uti"), side = BELOW, gap = 4, x = 0, y = 0, size = 30, height = 90, perRow = 10,
        grow = DOWN, swipeAlpha = 60 },
    bar = { on = true, anchor = AttachTo("buf"), side = BELOW, gap = 4, x = 0, y = 0, size = 20, perRow = 1, grow = DOWN,
        swipeAlpha = 60 },
}
local CUSTOM = { on = false, anchor = FREE, side = BELOW, gap = 4, x = 0, y = 0, size = 36, perRow = 10, grow = DOWN,
    usable = true, range = true, swipeAlpha = 70 }

-- Groups by kind; custom slots carry every group because their kind changes.
local GROUPS = { common = true, icon = { [KIND.COOLDOWN] = true, [KIND.AURA_ICON] = true },
    cooldown = { [KIND.COOLDOWN] = true }, aura = { [KIND.AURA_ICON] = true, [KIND.AURA_BAR] = true },
    bar = { [KIND.AURA_BAR] = true } }
local function Has(slot, group)
    if slot.custom or group == "common" then return true end
    return GROUPS[group][slot.kind] == true
end

CDM.KEYS = {}
CDM.SUFFIXES = {}
-- The glow styles (K.GLOW): of the glows and of the pandemic window.
-- Append-only: Pixel and Autocast (lines or sparks travelling around the
-- border, CDM.LINE_STYLES) came last.
local GLOW_STYLES = { "Blizzard alert", "Marching ants", "Pulse", "Border", "Pixel", "Autocast" }
CDM.LINE_STYLES = { [5] = true, [6] = true }
-- The active buff swipe's color as it always was (the runtime keeps its
-- exact gold for this value).
CDM.AURA_SWIPE = "ffd100"
local INSTANCE_TIP = "Dungeons, raids, delves and scenarios, battlegrounds and arenas count as instances."
local HIDDEN_ALPHA_TIP = "At 0 a hidden bar disappears. Above 0 it fades to this opacity instead, never brighter than it shows."
local HOVER_TIP =
    "Pointing at a hidden or faded bar shows it at its full opacity. Clicks still pass through; its tooltips stay off until the bar shows on its own."
local FADE_TIP = "How long a full fade takes when the bar hides, shows or changes opacity. 0 switches at once."
local FRAME_NAME_TIP =
    "The global name of a frame, for example ChatFrame1. The bar follows its place and size, never anchored to it. Until the frame exists, the bar stays put."
local BAR_WIDTH_TIP =
    "0 matches the width of the bar or frame this bar is attached to and follows when that resizes. A bar attached to nothing uses its usual width."
local MASQUE_TIP =
    "Skins this bar's cooldown icons with Masque, in one Masque group per bar. Buff icons (Blizzard's sealed aura buttons) and timer bars keep their look."
-- Per-bar rules by group, in menu order. Add(rule, suffix) appends to the
-- bar's list; p is the bar's key prefix and d its defaults.
local function CommonRules(Add, p, d, slot)
    Add(Bool(p .. "on", "Show this bar", d.on), "on")
    Add(String(p .. "name", "Bar name", "", 24), "name")
    Add(Choice(p .. "kind", "Bar type", slot.kind or KIND.COOLDOWN, { "Cooldowns", "Buff icons", "Buff bars" }), "kind")
    Add(Number(p .. "x", "Horizontal position", d.x, -4000, 4000), "x")
    Add(Number(p .. "y", "Vertical position", d.y, -3000, 3000), "y")
    Add(Choice(p .. "anchor", "Attach to", d.anchor, ANCHOR_LABELS), "anchor")
    Add(B.Tooltip(String(p .. "anchorFrame", "Frame name", "", 64), FRAME_NAME_TIP), "anchorFrame")
    Add(Choice(p .. "side", "Attach side", d.side, { "Below", "Above", "Left", "Right" }), "side")
    Add(Number(p .. "gap", "Attach gap", d.gap, 0, 60), "gap")
    Add(Number(p .. "alpha", "Opacity (percent)", 100, 0, 100, 5), "alpha")
    Add(Number(p .. "oocAlpha", "Opacity out of combat (percent)", 100, 0, 100, 5), "oocAlpha")
    Add(Choice(p .. "vis", "Show", CDM.VIS.ALWAYS, { "Always", "In combat", "In combat or with a target", "Hidden" }),
        "vis")
    Add(Bool(p .. "hideMounted", "Hide while mounted", false), "hideMounted")
    Add(Bool(p .. "hideVehicle", "Hide in vehicles", true), "hideVehicle")
    Add(Bool(p .. "hideResting", "Hide while resting", false), "hideResting")
    Add(Bool(p .. "hideSolo", "Hide when not in a group", false), "hideSolo")
    Add(B.Tooltip(Bool(p .. "hideWorld", "Hide outside instances", false), INSTANCE_TIP), "hideWorld")
    Add(Bool(p .. "hideFlying", "Hide while flying", false), "hideFlying")
    Add(Bool(p .. "hideDead", "Hide while dead", false), "hideDead")
    Add(B.Tooltip(Number(p .. "hiddenAlpha", "Opacity while hidden (percent)", 0, 0, 100, 5), HIDDEN_ALPHA_TIP), "hiddenAlpha")
    Add(B.Tooltip(Bool(p .. "hoverShow", "Show on mouseover", false), HOVER_TIP), "hoverShow")
    Add(B.Tooltip(Number(p .. "fadeTime", "Fade time (seconds)", 0, 0, 2, 0.1), FADE_TIP), "fadeTime")
    Add(Bool(p .. "tooltips", "Show tooltips", false), "tooltips")
    Add(Choice(p .. "strata", "Frame layer", 3, { "Background", "Low", "Medium", "High" }), "strata")
    Add(Number(p .. "layer", "MSUF layer (-1 = Auto)", -1, -1, 30), "layer")
    -- MSUF's icon skin of the bar's icons (a buff bar: its icon), chosen on
    -- MSUF's Icon Skins page: DEFAULT follows its default skin, CUSTOM keeps
    -- the bar's own border, anything else names a skin.
    Add(String(p .. "iconSkin", "Icon skin", "DEFAULT", 64), "iconSkin")
    -- MSUF's aura icon shapes (MSUF 7.0; older hosts draw every icon square).
    Add(Choice(p .. "iconShape", "Icon shape", 1, NS.IconShapeLabels), "iconShape")
end
local function IconRules(Add, p, d)
    Add(Number(p .. "size", "Icon size", d.size, 12, 96), "size")
    Add(Number(p .. "height", "Icon height (percent)", d.height or 100, 40, 100, 5), "height")
    Add(Number(p .. "spacing", "Icon spacing", 2, -2, 30), "spacing")
    Add(Number(p .. "perRow", "Icons per row", d.perRow, 1, 40), "perRow")
    Add(Number(p .. "maxIcons", "Maximum icons (0 = all)", 0, 0, 40), "maxIcons")
    Add(Bool(p .. "vertical", "Vertical", false), "vertical")
    Add(Choice(p .. "align", "Alignment", d.align or CDM.ALIGN.CENTER, { "Center", "Start", "End" }), "align")
    Add(B.Tooltip(Bool(p .. "centerFirst", "Keep first icon centered", false),
        "Requires Center alignment. Icons alternate around the first icon. Buffs keep fixed places; inactive buffs leave gaps."), "centerFirst")
    Add(Choice(p .. "grow", "New rows", d.grow, { "Down", "Up" }), "grow")
    Add(Number(p .. "zoom", "Icon zoom (percent)", 8, 0, 30), "zoom")
    Add(Number(p .. "border", "Border", 1, 0, 4), "border")
    Add(Color(p .. "borderColor", "Border color", "000000"), "borderColor")
    Add(Bool(p .. "borderClass", "Class-colored border", false), "borderClass")
    Add(Bool(p .. "cdText", "Show countdown", true), "cdText")
    Add(Bool(p .. "stackText", "Show charges and stacks", true), "stackText")
    Add(Choice(p .. "textTop", "Text on top", CDM.TEXT_TOP.STACKS, { "Stacks", "Countdown" }), "textTop")
    Add(Number(p .. "cdSize", "Countdown size (0 = automatic)", 0, 0, 40), "cdSize")
    Add(Number(p .. "stackSize", "Charges and stacks size (0 = automatic)", 0, 0, 40), "stackSize")
    Add(Choice(p .. "stackPos", "Charges and stacks position", 9, POINT_LABELS), "stackPos")
    Add(Number(p .. "swipeAlpha", "Swipe opacity (percent)", d.swipeAlpha, 0, 100, 5), "swipeAlpha")
    Add(Color(p .. "swipeColor", "Swipe color", "000000"), "swipeColor")
    Add(Bool(p .. "swipeClass", "Class-colored swipe", false), "swipeClass")
    Add(Bool(p .. "edge", "Show the swipe edge", false), "edge")
end
-- The pulse follows the bar's cooldowns, not its visibility.
local PULSE_TIP =
    "Shows the spell's icon in the middle of the screen when its cooldown ends, even while this bar is hidden. Its size, place and time are in General."
local function CooldownRules(Add, p, d)
    Add(Bool(p .. "cooldownDuration", "Display cooldowns as timer bars", false), "cooldownDuration")
    Add(Bool(p .. "desat", "Desaturate on cooldown", true), "desat")
    Add(Number(p .. "cdAlpha", "Opacity on cooldown (percent)", 100, 0, 100, 5), "cdAlpha")
    Add(Number(p .. "readyAlpha", "Opacity when ready (percent)", 100, 0, 100, 5), "readyAlpha")
    Add(Bool(p .. "hideReady", "Hide icons that are ready", false), "hideReady")
    Add(Bool(p .. "cooldownFixed", "Keep hidden cooldown icons in fixed places", false), "cooldownFixed")
    Add(Choice(p .. "overflow", "Send excess cooldowns to", CDM.OVERFLOW.OFF, OVERFLOW_LABELS), "overflow")
    Add(Number(p .. "laterPerRow", "Icons in later rows (0 = first row)", 0, 0, 40), "laterPerRow")
    Add(Number(p .. "laterSize", "Later row icon size (0 = first row)", 0, 0, 96), "laterSize")
    Add(Bool(p .. "procGlow", "Spell alert glow", true), "procGlow")
    Add(Bool(p .. "readyGlow", "Glow when ready", false), "readyGlow")
    Add(Bool(p .. "readyResources", "Ready glow requires enough resources", false), "readyResources")
    Add(Bool(p .. "fullChargeGlow", "Glow when all charges are ready", false), "fullChargeGlow")
    Add(Choice(p .. "glowStyle", "Glow style", 1, GLOW_STYLES), "glowStyle")
    Add(Bool(p .. "glowTint", "Tint glows", false), "glowTint")
    Add(Color(p .. "glowColor", "Glow color", "ffd200"), "glowColor")
    Add(Bool(p .. "usable", "Color unusable spells", d.usable ~= false), "usable")
    Add(Bool(p .. "range", "Color out-of-range spells", d.range ~= false), "range")
    Add(Color(p .. "rangeColor", "Out-of-range color", "cc2e2e"), "rangeColor")
    Add(Bool(p .. "showAura", "Show active buff duration", true), "showAura")
    Add(Color(p .. "auraSwipeColor", "Active buff swipe color", CDM.AURA_SWIPE), "auraSwipeColor")
    Add(Bool(p .. "charges", "Show charges", true), "charges")
    Add(Bool(p .. "chargeSwipe", "Show recharge swipe", false), "chargeSwipe")
    Add(Bool(p .. "chargeEdge", "Show recharge edge", true), "chargeEdge")
    Add(Bool(p .. "keybind", "Show keybinds", d.keybind == true), "keybind")
    Add(Number(p .. "keybindSize", "Keybind size (0 = automatic)", 0, 0, 30), "keybindSize")
    Add(Choice(p .. "keybindPos", "Keybind position", 3, POINT_LABELS), "keybindPos")
    Add(Bool(p .. "keybindBadge", "Keybind badge", false), "keybindBadge")
    Add(Color(p .. "keybindBackground", "Keybind badge background", "101010"), "keybindBackground")
    Add(Color(p .. "keybindBorder", "Keybind badge border", "808080"), "keybindBorder")
    Add(Number(p .. "keybindPadding", "Keybind badge padding", 2, 0, 8), "keybindPadding")
    Add(Bool(p .. "assist", "Highlight the assisted combat suggestion", false), "assist")
    Add(B.Tooltip(Bool(p .. "kickMark", "Glow the interrupt while the target's cast can be interrupted", false),
        "Shows each ready interrupt with the bar's glow style while the target's cast can be interrupted. Requires per-interrupt readiness from MSUF."),
        "kickMark")
    Add(Bool(p .. "bling", "Flash when ready", false), "bling")
    Add(B.Tooltip(Bool(p .. "readyPulse", "Pulse ready cooldowns in the screen center", false), PULSE_TIP), "readyPulse")
    Add(B.Tooltip(Bool(p .. "masque", "Skin icons with Masque", false), MASQUE_TIP), "masque")
end
-- Every bar marks the pandemic window: aura bars on their auras, cooldown
-- bars on the aura their icons show, as Blizzard's Cooldown Manager does.
-- Its look: one of the glow styles (4, a still border, by default), a color
-- and the border's thickness (Pulse and Border) in pixels.
local PANDEMIC_TIP =
    "Marks a buff or debuff in its pandemic window, where refreshing it keeps the remaining time. Cooldown icons show it with their aura."
local function AuraRules(Add, p, slot)
    if Has(slot, "aura") then
        Add(Bool(p .. "showMissing", "Show missing buffs dimmed", false), "showMissing")
        Add(Bool(p .. "keepSlots", "Keep buffs in fixed places", false), "keepSlots")
        Add(Bool(p .. "auraGlow", "Glow while active", false), "auraGlow")
    end
    Add(B.Tooltip(Bool(p .. "pandemic", "Highlight the pandemic window", true), PANDEMIC_TIP), "pandemic")
    Add(Choice(p .. "pandemicStyle", "Pandemic window style", 4, GLOW_STYLES), "pandemicStyle")
    Add(Color(p .. "pandemicColor", "Pandemic window color", "ff4d26"), "pandemicColor")
    Add(Number(p .. "pandemicSize", "Pandemic window thickness", 2, 1, 8), "pandemicSize")
    -- Pixel and Autocast (the glows' and the pandemic window's): how many
    -- lines or sparks, how thick, how fast.
    Add(Number(p .. "glowLines", "Glow lines", 8, 1, 16), "glowLines")
    Add(Number(p .. "glowThickness", "Glow thickness", 2, 1, 6), "glowThickness")
    Add(Number(p .. "glowSpeed", "Glow speed (percent)", 100, 25, 400, 5), "glowSpeed")
end
local function BarRules(Add, p, d, slot)
    if not Has(slot, "icon") then
        Add(Choice(p .. "grow", "New rows", d.grow, { "Down", "Up" }), "grow")
        -- Text switches of every bar type (icon bars have them above).
        Add(Bool(p .. "cdText", "Show countdown", true), "cdText")
        Add(Bool(p .. "stackText", "Show charges and stacks", true), "stackText")
        Add(Choice(p .. "textTop", "Text on top", CDM.TEXT_TOP.STACKS, { "Stacks", "Countdown" }), "textTop")
    end
    Add(B.Tooltip(Number(p .. "barWidth", "Bar width", slot.key == "bar" and 220 or 200, 0, 480), BAR_WIDTH_TIP), "barWidth")
    Add(Number(p .. "barHeight", "Bar height", slot.key == "bar" and 20 or 18, 8, 48), "barHeight")
    Add(Texture(p .. "barTexture", "Bar texture"), "barTexture")
    Add(Color(p .. "barColor", "Bar color", NS.Client.isForever and "d8b66a" or "e8b855"), "barColor")
    Add(Bool(p .. "barClass", "Class-colored bars", true), "barClass")
    Add(Number(p .. "barBgAlpha", "Bar background opacity (percent)", 55, 0, 100, 5), "barBgAlpha")
    Add(Bool(p .. "barIcon", "Show icon", true), "barIcon")
    Add(Choice(p .. "barIconSide", "Icon side", CDM.BAR_ICON_SIDE.LEFT, { "Left", "Right" }), "barIconSide")
    Add(Bool(p .. "barName", "Show name", true), "barName")
    Add(Bool(p .. "barTime", "Show time", true), "barTime")
    Add(Choice(p .. "barFill", "Bar direction", CDM.BAR_FILL.DRAIN, { "Drain", "Fill" }), "barFill")
    Add(Bool(p .. "barSpark", "Show a spark", false), "barSpark")
    Add(Bool(p .. "barStacks", "Fill buff bars by stacks", false), "barStacks")
    Add(Bool(p .. "barChargeSegments", "Separate cooldown charges into segments", false), "barChargeSegments")
    Add(Bool(p .. "barChargeDim", "Darken the recharging segment", true), "barChargeDim")
    Add(Number(p .. "barStackMax", "Maximum stacks", 10, 1, 99), "barStackMax")
    Add(Bool(p .. "barStackEach", "Mark every stack", true), "barStackEach")
    Add(String(p .. "barStackMarks", "Stack markers (numbers separated by commas)", "", 240), "barStackMarks")
    Add(Number(p .. "barStackColorAt", "Change bar color from stacks (0 = off)", 0, 0, 99), "barStackColorAt")
    Add(Color(p .. "barStackColor", "Stack threshold bar color", "ff6633"), "barStackColor")
end

local function Rules(slot)
    local d = D[slot.key] or CUSTOM
    local p = slot.key .. "_"
    local list = {}
    local function Add(rule, suffix)
        rule.suffix = suffix
        list[#list + 1] = rule
    end
    CommonRules(Add, p, d, slot)
    if slot.custom then Add(Bool(p .. "shareContents", "Share this group's contents across specializations", false), "shareContents") end
    if Has(slot, "icon") then IconRules(Add, p, d) end
    if Has(slot, "cooldown") then CooldownRules(Add, p, d) end
    AuraRules(Add, p, slot)
    if Has(slot, "bar") or Has(slot, "cooldown") then BarRules(Add, p, d, slot) end
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
for _, key in ipairs({ "listsData", "spellsData", "captured", "defaultsVersion", "essOnViewer", "positionsData" }) do
    rules[key].hidden = true
end
for _, slot in ipairs(CDM.SLOTS) do
    local k = CDM.KEYS[slot.key]
    local function Set(suffix, field, value) if k[suffix] then rules[k[suffix]][field] = value end end
    if slot.builtin then
        Set("name", "hidden", true)
        Set("kind", "hidden", true)
    end
    Set("iconSkin", "hidden", true)
    Set("x", "category", "advanced")
    Set("y", "category", "advanced")
    Set("cdSize", "enableKey", k.cdText)
    Set("rangeColor", "enableKey", k.range)
    Set("keybindSize", "enableKey", k.keybind)
    Set("keybindPos", "enableKey", k.keybind)
    Set("glowColor", "enableKey", k.glowTint)
    Set("borderColor", "disabledBy", k.borderClass)
    Set("barColor", "disabledBy", k.barClass)
    Set("swipeColor", "disabledBy", k.swipeClass)
    -- "Mark every stack" overrides the custom markers; centering needs Center.
    Set("barStackMarks", "disabledBy", k.barStackEach)
    if k.centerFirst then rules[k.centerFirst].requiresChoice = { key = k.align, values = { [CDM.ALIGN.CENTER] = true } } end
    -- The thickness belongs to the border styles (Pulse, Border).
    rules[k.pandemicSize].requiresChoice = { key = k.pandemicStyle, values = { [3] = true, [4] = true } }
    -- The lines' look belongs to Pixel and Autocast, as the glow style or
    -- (orKey) the pandemic window's.
    local lines = { key = k.glowStyle or k.pandemicStyle, orKey = k.glowStyle and k.pandemicStyle, values = CDM.LINE_STYLES }
    for _, suffix in ipairs({ "glowLines", "glowThickness", "glowSpeed" }) do rules[k[suffix]].requiresChoice = lines end
    if k.side then
        rules[k.side].requiresChoice = { key = k.anchor, values = {} }
        rules[k.gap].requiresChoice = rules[k.side].requiresChoice
        for i = 2, #ANCHOR_LABELS do rules[k.side].requiresChoice.values[i] = true end
        -- The frame name belongs to "Other frame" alone.
        rules[k.anchorFrame].requiresChoice = { key = k.anchor, values = { [OTHER_ANCHOR] = true } }
    end
end

-- Assisted-icon dependents keep the switch visible when the feature is off.
for _, key in ipairs({ "assistIconVis", "assistIconAlpha", "assistIconBorder", "assistIconBorderColor", "assistIconZoom",
    "assistIconKeySize", "assistIconKeyPos", "assistIconAnchor", "assistIconSize", "assistIconX", "assistIconY",
    "assistIconKeybind", "assistIconGCD" }) do rules[key].enableKey = "assistIcon" end
rules.assistIconKeySize.requiresChoice = { key = "assistIconKeybind", values = { [true] = true } }
rules.assistIconKeyPos.requiresChoice = rules.assistIconKeySize.requiresChoice
