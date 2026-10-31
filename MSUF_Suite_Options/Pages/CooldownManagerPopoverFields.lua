local _, P = ...
-- Cooldown manager page, per-spell popover: its fields (labels and help are
-- plain literals, so the locale extraction sees every one of them) and the
-- menus and sections built from them on the first open. The popover in
-- CooldownManagerPopover.lua paints the rows.
local Page, CDM = P.CDMPage, P.Suite.CDM
if not Page then return end
local SWATCHES = { "ffd200", "ffffff", "ff4d4d", "4dff73", "4db8ff", "c78cff", "4dffff", "ff9933" }
local SWATCH_NAMES = { "Gold", "White", "Red", "Green", "Blue", "Purple", "Cyan", "Orange" }
-- The stack color of an entry that has none.
local STACK_COLOR = CDM.SPELL_DEFAULTS.stackColor
local SHOW_HIDE = { { 0, "Bar setting" }, { 2, "Show" }, { 3, "Hide" } }
local FROM_BOOL = { [true] = 2, [false] = 3 }
-- bar: the bar setting a missing value follows. fromBar: that setting's
-- value as a choice of the row. fallback: the hint when no bar setting
-- stands behind the row. switch: On or nothing (no bar setting to follow).
-- blizzardOnly: Blizzard's entries only (custom auras name their unit).
-- Help texts too long to share a line with their row.
local CHARGE_FADE_HELP =
"Fade the charge spell while at least one charge is usable. Its space stays reserved; the native cooldown controls the opacity without exposing charge counts."
local ACTION_GLOW_HELP =
"Enter a spell name or ID on MSUF action bars. Its buttons glow from the aura and unit selected below. A page change in combat pauses the glow until combat ends."
local ALL_FIELDS = {
    { key = "procGlow", label = "Spell alert glow", kind = "bool", cd = true, spellOnly = true, bar = "procGlow",
      help = "Glow while the game highlights this spell (spell alert)." },
    { key = "readyGlow", label = "Glow when ready", kind = "bool", cd = true, bar = "readyGlow",
      help = "Glow while the spell is ready. \"Ready glows only in combat\" in Basics limits it to combat." },
    { key = "actionUsableGlow", label = "Action-bar glow when usable", kind = "bool", cd = true, spellOnly = true, switch = true,
      help = "Glow on this spell's MSUF action-bar buttons when it is usable and its real cooldown is over. Unavailable state keeps the glow off." },
    { key = "showGCD", label = "Show global cooldown", kind = "bool", cd = true, spellOnly = true,
      help = "Show the global cooldown swipe for this spell. Reset follows the global cooldown setting in Basics." },
    { key = "readyResources", label = "Ready glow requires enough resources", kind = "bool", cd = true, bar = "readyResources",
      help = "Suppress ready glows when resources are insufficient or their state is unavailable." },
    { key = "fullChargeGlow", label = "Glow when all charges are ready", kind = "bool", cd = true, spellOnly = true, bar = "fullChargeGlow",
      help = "Glow when the game reports that this charge spell has finished recharging." },
    { key = "chargeSwipe", label = "Show recharge swipe", kind = "bool", cd = true, spellOnly = true, bar = "chargeSwipe",
      help = "Draw the recharge swipe independently of the main cooldown swipe." },
    { key = "chargeEdge", label = "Show recharge edge", kind = "bool", cd = true, spellOnly = true, bar = "chargeEdge",
      help = "Draw the recharge edge independently of the main cooldown edge." },
    { key = "auraGlow", label = "Glow while active", kind = "bool", aura = true, bar = "auraGlow",
      help = "Glow while the buff is active." },
    { key = "glowStyle", label = "Glow style", kind = "choice", cd = true, aura = true,
      values = { { 0, "Bar setting" }, { 1, "Blizzard alert" }, { 2, "Marching ants" }, { 3, "Pulse" }, { 4, "Border" },
          { 5, "Pixel" }, { 6, "Autocast" } },
      help = "Style of every glow of this spell: spell alert, ready, active buff and stack glows." },
    { key = "glowColor", label = "Glow color", kind = "color", cd = true, aura = true,
      help = "Tints every glow of this spell. Click the chosen color again to follow the bar." },
    { key = "desat", label = "Desaturate on cooldown", kind = "choice", cd = true,
      values = { { 0, "Bar setting" }, { 2, "Never" }, { 3, "Always" } },
      help = "Grey out the icon while the spell is on cooldown." },
    { key = "hideReady", label = "Hide when ready", kind = "bool", cd = true, bar = "hideReady",
      help = "Show the icon only while the spell is on cooldown." },
    { key = "readyAlpha", label = "Opacity when ready", kind = "number", cd = true, bar = "readyAlpha", step = 1, max = 100,
      help = "Icon opacity while the spell is ready. Shift steps by 5, Ctrl by 10." },
    { key = "cdAlpha", label = "Opacity on cooldown", kind = "number", cd = true, bar = "cdAlpha", step = 1, max = 100,
      help = "Icon opacity while the spell is on cooldown. Shift steps by 5, Ctrl by 10." },
    { key = "showAura", label = "Show active buff duration", kind = "bool", cd = true, spellOnly = true, bar = "showAura",
      help = "While the buff of this spell lasts, the icon shows its duration and stacks instead of the cooldown." },
    { key = "showMissing", label = "Show dimmed when missing", kind = "bool", aura = true, bar = "showMissing",
      help = "Keep the icon in its place, dimmed, while the buff is missing." },
    { key = "auraUnit", label = "Track on", kind = "choice", stack = true, blizzardOnly = true,
      values = { { 0, "Automatic" }, { 2, "Me" }, { 3, "Target" }, { 4, "Both" } },
      help = "Where the buff or debuff is looked for. Automatic: harmful spells on your target, all others on you." },
    { key = "stackGlow", label = "Glow at stacks", kind = "number", stack = true, off = true, step = 1, max = 99,
      op = "stackGlowOp", help = "Stack threshold for the selected comparison. Zero disables the stack glow." },
    { key = "hideAvailableCharges", label = "Hide while a charge is available", kind = "bool", cd = true, spellOnly = true,
      help = CHARGE_FADE_HELP },
    -- inline: no row of its own; its choice sits in front of the stackGlow
    -- threshold and shows the mark (third value). rule: the glow in words.
    { key = "stackGlowOp", label = "Stack comparison", kind = "choice", stack = true, inline = true,
      values = { { 0, "At least", ">=", "Glows from %d stacks." }, { 2, "Exactly", "=", "Glows at exactly %d stacks." },
          { 3, "More than", ">", "Glows above %d stacks." }, { 4, "Fewer than", "<", "Glows below %d stacks." },
          { 5, "At most", "<=", "Glows at %d stacks or fewer." } },
      help = "Compare the native stack count with the configured threshold." },
    { key = "actionGlowSpell", label = "Glow on action-bar spell", kind = "spell", stack = true,
      help = ACTION_GLOW_HELP },
    { key = "actionGlowUnit", label = "Action-bar aura source", kind = "choice", stack = true,
      values = { { 0, "Buff on me" }, { 2, "My debuff on target" } },
      help = "Choose your buffs or your own harmful auras on the current target. The additional required buff is always checked on you." },
    { key = "actionGlowMode", label = "Action-bar glow condition", kind = "choice", stack = true,
      values = { { 0, "Aura present" }, { 2, "Stack comparison" } },
      help = "The stack condition uses Glow at stacks and Stack comparison. Buff absence cannot drive a combat glow through the native aura-slot API." },
    { key = "actionGlowRequireSpell", label = "Also require this buff", kind = "spell", stack = true,
      help = "The action-bar glow also requires this buff on you. Clear the field to use only the original buff or stack condition." },
    { key = "stackColorAt", label = "Color stacks from", kind = "number", stack = true, off = true, step = 1, max = 99,
      color = "stackColor", help = "From this many stacks the number shows in the color on the right." },
    { key = "pandemic", label = "Pandemic window", kind = "bool", stack = true, bar = "pandemic",
      help = "Highlight this buff or debuff while refreshing it keeps the remaining time." },
    { key = "swipe", label = "Swipe", kind = "choice", cd = true, aura = true,
      values = { { 0, "Normal" }, { 2, "Reversed" }, { 3, "Hidden" } },
      help = "The dark sweep over the icon while it counts down." },
    { key = "timeText", label = "Countdown", auraLabel = "Seconds", kind = "choice", cd = true, aura = true,
      bar = "cdText", fromBar = FROM_BOOL, values = SHOW_HIDE,
      help = "Show or hide the countdown numbers of this spell. Bar setting follows the bar's Text section." },
    { key = "stackText", label = "Charges", auraLabel = "Stacks", kind = "choice", cd = true, aura = true,
      bar = "stackText", fromBar = FROM_BOOL, values = SHOW_HIDE,
      help = "Show or hide the charges, stacks or item count of this spell." },
    { key = "textTop", label = "Text on top", kind = "choice", cd = true, aura = true, bar = "textTop",
      fromBar = { 2, 3 }, values = { { 0, "Bar setting" }, { 2, "Stacks" }, { 3, "Countdown" } },
      help = "Which number is drawn on top when both show." },
    { key = "threshold", label = "Warn below (seconds)", kind = "number", cd = true, aura = true, step = 1, max = 10,
      fallback = "All bars",
      help = "The countdown turns to the warning color below this many seconds. All bars: the Text section's setting." },
    { key = "timerDuration", label = "Custom duration (seconds)", kind = "number", aura = true, timer = true, off = true,
      step = 1, max = 600,
      help = "Zero uses the game's duration. A custom duration starts on the trigger spell's successful cast. Summon timers use fixed places." },
    { key = "timerSpell", label = "Timer trigger spell", kind = "spell", aura = true, timer = true,
      help = "Enter the cast spell's name or ID. Leave empty for automatic spell matching. Timers start only from readable player cast events." },
    { key = "sound", label = "Sound when ready", auraLabel = "Sound when gained", kind = "sound", cd = true, aura = true,
      help = "Plays when the spell becomes ready (a buff: when you gain it)." },
    { key = "lossSound", label = "Sound when lost", kind = "sound", aura = true, help = "Plays when the buff ends." },
    { key = "tts", label = "Say the name when ready", kind = "bool", cd = true, switch = true,
      help = "Your computer says the spell's name when it becomes ready." },
    -- A buff shows the game's icon while active; its own icon only while missing.
    { key = "icon", label = "Icon file ID (Enter)", auraLabel = "Icon when missing (Enter)", kind = "icon", cd = true,
      aura = true, help = "Type a texture file ID and press Enter to show another icon. Empty follows the game." },
}
-- Rows exist for the fields the catalog stores. Labels and help are plain
-- literals in the rows, so the locale extraction sees every one of them.
local REQUIRE_HELP = "Enter a talent or spell name or ID, then press Enter. Every required spell must be learned. Empty removes this condition."
local EXCLUDE_HELP =
    "Enter a talent or spell name or ID, then press Enter. The entry is hidden while any excluded spell is learned. Conditions update outside combat."
local CONDITIONS = {
    { key = "requireSpell1", label = "Required talent or spell 1", help = REQUIRE_HELP },
    { key = "excludeSpell1", label = "Excluded talent or spell 1", help = EXCLUDE_HELP },
    { key = "requireSpell2", label = "Required talent or spell 2", help = REQUIRE_HELP },
    { key = "excludeSpell2", label = "Excluded talent or spell 2", help = EXCLUDE_HELP },
    { key = "requireSpell3", label = "Required talent or spell 3", help = REQUIRE_HELP },
    { key = "excludeSpell3", label = "Excluded talent or spell 3", help = EXCLUDE_HELP },
}
for _, row in ipairs(CONDITIONS) do
    row.kind, row.cd, row.aura = "spell", true, true
    ALL_FIELDS[#ALL_FIELDS + 1] = row
end
local FIELDS = {}
for _, field in ipairs(ALL_FIELDS) do
    if CDM.SPELL_FIELDS[field.key] then FIELDS[#FIELDS + 1] = field end
end
Page.FIELDS = FIELDS
-- More rows, made on the first open or search (Page.CompleteFields): loading
-- the options pays nothing for them. itemOnly: items and equipment slots.
-- bars: buff bars and cooldowns shown as timer bars.
local function MoreFields()
    return {
        { key = "usableOnly", label = "Show only when usable", kind = "bool", cd = true, spellOnly = true, switch = true,
          help = "Hide the icon while the spell cannot be used: not enough resources or the wrong state." },
        { key = "procOnly", label = "Show only during a spell alert", kind = "bool", cd = true, spellOnly = true, switch = true,
          help = "Hide the icon unless the game highlights this spell (spell alert)." },
        { key = "missingGlow", label = "Glow while missing", kind = "bool", aura = true, switch = true,
          help = "Keep the icon in its place, dimmed, and glow in this spell's glow style while the buff is missing." },
        { key = "activeBorder", label = "Border color while active", kind = "color", stack = true,
          help = "Border color while the buff is active. Click the chosen color again to follow the bar." },
        { key = "itemAura", label = "Show active buff duration", kind = "bool", cd = true, itemOnly = true, switch = true,
          help = "While the buff of this item's use lasts, the icon shows its duration and stacks instead of the cooldown." },
        { key = "barColor", label = "Bar color", kind = "color", cd = true, aura = true, bars = true,
          help = "Fill color of this spell's bar. Click the chosen color again to follow the bar." },
        { key = "barText", label = "Bar name (Enter)", kind = "text", cd = true, aura = true, bars = true,
          help = "Type a name and press Enter to show it on this spell's bar. Empty shows the spell's name." },
        { key = "usedSound", label = "Sound when used", kind = "sound", cd = true,
          help = "Plays when the cooldown starts (a charge spell: when its last charge is used)." },
        { key = "chargeSound", label = "Sound when a charge returns", kind = "sound", cd = true, spellOnly = true,
          help = "Plays when a charge of this spell comes back." },
    }
end
local complete = false
function Page.CompleteFields()
    if complete then return end
    complete = true
    for _, field in ipairs(MoreFields()) do
        if CDM.SPELL_FIELDS[field.key] then ALL_FIELDS[#ALL_FIELDS + 1], FIELDS[#FIELDS + 1] = field, field end
    end
end
local function SwatchItem(value, text, hex)
    local r, g, b = P.RGB(hex)
    return { value = value, text = text, swatchColor = { r, g, b, 1 } }
end
-- Choice menus, row resets, the inline comparison and the sections are
-- prepared on the first open, so loading the options pays only for the
-- field literals.
local function PrepareMenu(field)
    field.menu = {}
    for i, pair in ipairs(field.values) do
        local item = { value = pair[1], text = pair[2] }
        if pair[3] then item.mark, item.rule = pair[3], pair[4] end
        field.menu[i] = item
    end
    -- zero: what a specialization stores for the first choice (the menu's 0,
    -- "inherit" in the shared choices): 0 where the catalog accepts it (Glow
    -- style: the bar's style), else 1 (the bar's text setting, Normal,
    -- Automatic, At least, Aura present, Buff on me).
    field.zero = CDM.SPELL_FIELDS[field.key](0) and 0 or 1
end
-- Rows follow their section; a field no section names keeps its row last.
local function Sort(sections)
    local byKey = {}
    for _, field in ipairs(FIELDS) do byKey[field.key] = field end
    for i = #FIELDS, 1, -1 do FIELDS[i] = nil end
    for _, section in ipairs(sections) do
        for key in section.keys:gmatch("%S+") do
            local field = byKey[key]
            if field then field.section, FIELDS[#FIELDS + 1], byKey[key] = section, field, nil end
        end
    end
    for _, field in ipairs(ALL_FIELDS) do
        if byKey[field.key] then field.section, FIELDS[#FIELDS + 1] = sections[#sections], field end
    end
end
function Page.PreparePopoverFields()
    Page.CompleteFields()
    -- Stack colors: "" is the default color (the field is cleared).
    local COLOR_MENU = { SwatchItem("", "Default", STACK_COLOR) }
    for i, hex in ipairs(SWATCHES) do COLOR_MENU[i + 1] = SwatchItem(hex, SWATCH_NAMES[i], hex) end
    Page.COLOR_MENU = COLOR_MENU
    for _, field in ipairs(FIELDS) do
        if field.values then PrepareMenu(field) end
        -- A companion (stack color, comparison) resets with its row.
        if field.color or field.op then field.clears = { field.key, field.color or field.op } end
        if field.inline then
            for _, host in ipairs(FIELDS) do
                if host.op == field.key then host.opField = field end
            end
        end
    end
    local sections = {
        { label = "Glow", keys = "procGlow readyGlow readyResources fullChargeGlow auraGlow missingGlow glowStyle glowColor" },
        { label = "Appearance",
          keys = "showGCD chargeSwipe chargeEdge swipe desat hideReady hideAvailableCharges usableOnly procOnly readyAlpha cdAlpha "
              .. "showMissing barColor barText icon" },
        { label = "Buff and stacks", keys = "showAura itemAura auraUnit stackGlow stackGlowOp stackColorAt pandemic activeBorder" },
        { label = "Action bars", keys = "actionUsableGlow actionGlowSpell actionGlowUnit actionGlowMode actionGlowRequireSpell" },
        { label = "Text", keys = "timeText stackText textTop threshold" },
        { label = "Custom timer", keys = "timerDuration timerSpell" },
        { label = "Sounds", keys = "sound lossSound usedSound chargeSound tts" },
        { label = "Conditions", keys = "requireSpell1 excludeSpell1 requireSpell2 excludeSpell2 requireSpell3 excludeSpell3" },
    }
    Sort(sections)
    Page.POPOVER_SECTIONS, Page.POPOVER_SWATCHES = sections, SWATCHES
end
