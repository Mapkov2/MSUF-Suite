local _, NS = ...
local Macros = {}
NS.Macros = Macros
local Model = {}
Macros.Model = Model

Model.VERSION, Model.MAX_LENGTH = 1, 255
Model.MAX_STEPS, Model.MAX_BRANCHES, Model.MAX_CONDITIONS = 24, 12, 12
Model.MAX_SEQUENCE = 32
local DEFAULTS = { mode = "rules", scope = "character", stat = "any" }
Model.Commands = {
    { key = "cast", label = "Cast a spell", argument = "required", category = "Spells", supportsRaidMarker = true },
    { key = "use", label = "Use an item", argument = "required", category = "Items", supportsRaidMarker = true },
    { key = "castsequence", label = "Spell or item sequence", argument = "sequence", category = "Spells", supportsRaidMarker = true },
    { key = "castrandom", label = "Random spell or item", argument = "sequence", category = "Spells", supportsRaidMarker = true },
    { key = "startattack", label = "Start attacking", argument = "optional", category = "Combat", supportsRaidMarker = true },
    { key = "stopattack", label = "Stop attacking", argument = "none", category = "Combat" },
    { key = "stopcasting", label = "Stop casting", argument = "none", category = "Combat" },
    { key = "stopspelltarget", label = "Cancel spell targeting", argument = "none", category = "Combat" },
    { key = "stopmacro", label = "Stop this macro", argument = "none", category = "Combat" },
    { key = "cqs", label = "Cancel queued spell", argument = "none", category = "Combat" },
    { key = "cancelaura", label = "Cancel an aura", argument = "required", category = "Spells" },
    { key = "cancelform", label = "Leave shapeshift form", argument = "none", category = "Spells" },
    { key = "target", label = "Target a unit", argument = "optional", category = "Targets" },
    { key = "targetexact", label = "Target an exact name", argument = "required", category = "Targets" },
    { key = "cleartarget", label = "Clear target", argument = "none", category = "Targets" },
    { key = "targetlasttarget", label = "Restore previous target", argument = "none", category = "Targets" },
    { key = "targetenemy", label = "Cycle enemy targets", argument = "optional", category = "Targets" },
    { key = "targetenemyplayer", label = "Cycle enemy players", argument = "optional", category = "Targets" },
    { key = "targetfriend", label = "Cycle friendly targets", argument = "optional", category = "Targets" },
    { key = "targetfriendplayer", label = "Cycle friendly players", argument = "optional", category = "Targets" },
    { key = "targetparty", label = "Cycle party members", argument = "optional", category = "Targets" },
    { key = "targetraid", label = "Cycle raid members", argument = "optional", category = "Targets" },
    { key = "targetlastenemy", label = "Target previous enemy", argument = "optional", category = "Targets" },
    { key = "targetlastfriend", label = "Target previous friend", argument = "optional", category = "Targets" },
    { key = "assist", label = "Assist a unit", argument = "optional", category = "Targets" },
    { key = "focus", label = "Set focus", argument = "optional", category = "Targets" },
    { key = "clearfocus", label = "Clear focus", argument = "none", category = "Targets" },
    { key = "petattack", label = "Pet attack", argument = "optional", category = "Pet", supportsRaidMarker = true },
    { key = "petfollow", label = "Pet follow", argument = "none", category = "Pet" },
    { key = "petmoveto", label = "Move pet to position", argument = "none", category = "Pet" },
    { key = "petstay", label = "Pet stay", argument = "none", category = "Pet" },
    { key = "petdismiss", label = "Dismiss pet", argument = "none", conditional = false, category = "Pet" },
    { key = "petpassive", label = "Pet passive", argument = "none", category = "Pet" },
    { key = "petdefensive", label = "Pet defensive", argument = "none", category = "Pet" },
    { key = "petassist", label = "Pet assist", argument = "none", category = "Pet" },
    { key = "petautocaston", label = "Enable pet autocast", argument = "required", category = "Pet" },
    { key = "petautocastoff", label = "Disable pet autocast", argument = "required", category = "Pet" },
    { key = "petautocasttoggle", label = "Toggle pet autocast", argument = "required", category = "Pet" },
    { key = "equip", label = "Equip an item", argument = "required", category = "Equipment" },
    { key = "equipslot", label = "Equip in a slot", argument = "required", category = "Equipment" },
    { key = "equipset", label = "Equip an equipment set", argument = "required", category = "Equipment" },
    { key = "dismount", label = "Dismount", argument = "none", category = "Travel" },
    { key = "leavevehicle", label = "Leave vehicle", argument = "none", category = "Travel" },
    { key = "changeactionbar", label = "Change action bar", argument = "required", category = "Action bars" },
    { key = "swapactionbar", label = "Swap action bars", argument = "required", category = "Action bars" },
    { key = "say", label = "Say", argument = "text", conditional = false, category = "Chat" },
    { key = "party", label = "Party message", argument = "text", conditional = false, category = "Chat" },
    { key = "raid", label = "Raid message", argument = "text", conditional = false, category = "Chat" },
    { key = "raidwarning", label = "Raid warning", argument = "text", conditional = false, category = "Chat" },
    { key = "emote", label = "Emote", argument = "text", conditional = false, category = "Chat" },
    { key = "tm", label = "Target marker", argument = "required", category = "Group" },
    { key = "wm", label = "World marker", argument = "required", category = "Group" },
    { key = "cwm", label = "Clear world marker", argument = "required", category = "Group" },
    { key = "ping", label = "Ping", argument = "optional", category = "Group" },
    { key = "raw", label = "Custom command", argument = "raw", conditional = false, category = "Advanced" },
}
Model.Conditions = {
    { key = "unit", label = "Target", kind = "unit" },
    { key = "mod", label = "Modifier key", kind = "modifier" },
    { key = "help", label = "Friendly", kind = "boolean" },
    { key = "harm", label = "Hostile", kind = "boolean" },
    { key = "exists", label = "Exists", kind = "boolean" },
    { key = "dead", label = "Dead", kind = "boolean" },
    { key = "combat", label = "In combat", kind = "boolean" },
    { key = "mounted", label = "Mounted", kind = "boolean" },
    { key = "swimming", label = "Swimming", kind = "boolean" },
    { key = "flying", label = "Flying", kind = "boolean" },
    { key = "flyable", label = "Flying allowed", kind = "boolean" },
    { key = "advflyable", label = "Advanced flying allowed", kind = "boolean" },
    { key = "vehicleui", label = "Vehicle interface", kind = "boolean" },
    { key = "indoors", label = "Indoors", kind = "boolean" },
    { key = "outdoors", label = "Outdoors", kind = "boolean" },
    { key = "stealth", label = "Stealthed", kind = "boolean" },
    { key = "channeling", label = "Channeling", kind = "optional" },
    { key = "pet", label = "Pet available", kind = "optional" },
    { key = "group", label = "In a group", kind = "group" },
    { key = "form", label = "Shapeshift form", kind = "numbers" },
    { key = "spec", label = "Specialization", kind = "numbers" },
    { key = "known", label = "Spell known", kind = "spellID" },
    { key = "equipped", label = "Equipped item or type", kind = "required" },
    { key = "button", label = "Mouse button", kind = "numbers" },
    { key = "actionbar", label = "Action bar page", kind = "numbers" },
    { key = "bonusbar", label = "Bonus action bar", kind = "numbers" },
}
Model.CommandByKey, Model.ConditionByKey = {}, {}
for _, command in ipairs(Model.Commands) do Model.CommandByKey[command.key] = command end
for _, condition in ipairs(Model.Conditions) do Model.ConditionByKey[condition.key] = condition end

local INVALID = {}
local function Is(value, kind)
    return not NS.IsSecret(value) and value ~= INVALID and type(value) == kind
end

local function ReadMacroField(source, key, fallback)
    local value = rawget(source, key)
    if NS.IsSecret(value) then return INVALID end
    if value == nil then return fallback end
    return value
end

local function String(value, limit)
    return Is(value, "string") and #value <= limit and not value:find("%z")
end

function Model.Count(text)
    if not String(text, 16384) then return nil end
    local count, at = 0, 1
    while at <= #text do
        local byte = text:byte(at)
        local size = byte < 128 and 1 or byte >= 194 and byte <= 223 and 2
            or byte >= 224 and byte <= 239 and 3 or byte >= 240 and byte <= 244 and 4
        if not size or at + size - 1 > #text then return nil end
        for offset = 1, size - 1 do
            local continuation = text:byte(at + offset)
            if continuation < 128 or continuation > 191 then return nil end
        end
        local second = text:byte(at + 1)
        if size == 3 and (byte == 224 and second < 160 or byte == 237 and second > 159) then return nil end
        if size == 4 and (byte == 240 and second < 144 or byte == 244 and second > 143) then return nil end
        count, at = count + 1, at + size
    end
    return count
end

local function Array(value, maximum)
    if not Is(value, "table") then return false end
    local count = 0
    for key in pairs(value) do
        if not Is(key, "number") or key < 1 or key % 1 ~= 0 or key > maximum then return false end
        count = count + 1
    end
    for i = 1, count do if rawget(value, i) == nil then return false end end
    return count <= maximum
end

local function CopyCondition(source)
    if not Is(source, "table") or not String(source.key, 32) or not Model.ConditionByKey[source.key] then return nil end
    local value = ReadMacroField(source, "value", "")
    if Is(value, "number") and value == value and math.abs(value) < 100000000 then value = tostring(value) end
    local negate = ReadMacroField(source, "negate", false)
    if not String(value, 256) or not Is(negate, "boolean") then return nil end
    return { key = source.key, value = value, negate = negate }
end

local function CopyBranch(source)
    if not Is(source, "table") then return nil end
    local value, conditions = ReadMacroField(source, "value", ""), ReadMacroField(source, "conditions", {})
    if not String(value, 2048) or not Array(conditions, Model.MAX_CONDITIONS) then return nil end
    local useFirst = ReadMacroField(source, "useFirst", false)
    if not Is(useFirst, "boolean") then return nil end
    local result = { value = value, conditions = {}, useFirst = useFirst }
    for i, condition in ipairs(conditions) do
        result.conditions[i] = CopyCondition(condition)
        if not result.conditions[i] then return nil end
    end
    return result
end

local function CopyReset(source)
    if source == nil then return {} end
    if not Is(source, "table") then return nil end
    for _, key in ipairs({ "target", "combat" }) do
        if not Is(ReadMacroField(source, key, false), "boolean") then return nil end
    end
    local seconds = ReadMacroField(source, "seconds")
    if seconds ~= nil and (not Is(seconds, "number") or seconds ~= seconds or seconds < 0 or seconds > 3600) then return nil end
    local mod = ReadMacroField(source, "mod", "")
    if not String(mod, 10) then return nil end
    return { target = ReadMacroField(source, "target", false), combat = ReadMacroField(source, "combat", false), seconds = seconds, mod = mod }
end

local function CopyStep(source)
    if not Is(source, "table") or not String(source.command, 32) or not Model.CommandByKey[source.command] then return nil end
    local branches, sequence = ReadMacroField(source, "branches", {}), ReadMacroField(source, "sequence", {})
    if not Array(branches, Model.MAX_BRANCHES) or not Array(sequence, Model.MAX_SEQUENCE) then return nil end
    local result = { command = source.command, branches = {}, sequence = {}, reset = CopyReset(ReadMacroField(source, "reset")) }
    if not result.reset then return nil end
    local marker = ReadMacroField(source, "raidMarker")
    if marker ~= nil and (not Is(marker, "number") or marker ~= marker or marker < 0 or marker > 8 or marker % 1 ~= 0) then return nil end
    result.raidMarker = marker
    for i, branch in ipairs(branches) do
        result.branches[i] = CopyBranch(branch)
        if not result.branches[i] then return nil end
    end
    for i, value in ipairs(sequence) do
        if not String(value, 256) then return nil end
        result.sequence[i] = value
    end
    result.raw = ReadMacroField(source, "raw", "")
    if not String(result.raw, 8192) then return nil end
    return result
end

local function CopyValues(values)
    if values == nil then values = {} end
    if not Array(values, 32) then return nil end
    local result = {}
    for i, value in ipairs(values) do
        if Is(value, "number") then
            if value ~= value or value < 1 or value > 100000000 or value % 1 ~= 0 then return nil end
        elseif not String(value, 256) then
            return nil
        end
        result[i] = value
    end
    return result
end

local CONSUMABLES = { health = true, drink = true, food = true, flask = true, bandage = true }
local PRIORITIES = { stone = true, potion = true, combatpotion = true, spell = true, bandage = true }
local function CopyConsumable(source)
    if not Is(source, "table") or not String(source.kind, 20) or not CONSUMABLES[source.kind] then return nil end
    local priorities = ReadMacroField(source, "priorities", {})
    if not Array(priorities, 5) then return nil end
    local result = { kind = source.kind, priorities = {}, reset = CopyReset(ReadMacroField(source, "reset")) }
    if not result.reset then return nil end
    for _, key in ipairs({ "preferConjured", "includeFood", "combatMana", "stopCasting", "managed" }) do
        local value = ReadMacroField(source, key, false)
        if not Is(value, "boolean") then return nil end
        result[key] = value
    end
    for i, priority in ipairs(priorities) do
        if not String(priority, 20) or not PRIORITIES[priority] then return nil end
        result.priorities[i] = priority
    end
    result.spells, result.items = CopyValues(ReadMacroField(source, "spells")), CopyValues(ReadMacroField(source, "items"))
    if not result.spells or not result.items then return nil end
    local stat = ReadMacroField(source, "stat", DEFAULTS.stat)
    if stat ~= "any" and stat ~= "haste" and stat ~= "criticalStrike" and stat ~= "mastery" and stat ~= "versatility" then return nil end
    result.stat = stat
    return result
end

function Model.Normalize(source)
    if not Is(source, "table") then return nil, "Invalid macro document" end
    if ReadMacroField(source, "version", Model.VERSION) ~= Model.VERSION then return nil, "Unsupported macro version" end
    local name, raw = ReadMacroField(source, "name", ""), ReadMacroField(source, "raw", "")
    if not String(name, 64) or not Model.Count(name) or Model.Count(name) > 16 then return nil, "Macro names allow up to 16 characters" end
    if name:find("[\r\n]") then return nil, "Invalid macro name" end
    if not String(raw, 8192) or not Model.Count(raw) then return nil, "Invalid macro text" end
    local mode, scope = ReadMacroField(source, "mode", DEFAULTS.mode), ReadMacroField(source, "scope", DEFAULTS.scope)
    if mode ~= "rules" and mode ~= "raw" and mode ~= "consumable" then return nil, "Invalid macro mode" end
    if scope ~= "account" and scope ~= "character" then return nil, "Invalid macro scope" end
    local icon = ReadMacroField(source, "icon", 134400)
    if not Is(icon, "number") or icon ~= icon or icon < 1 or icon > 100000000 or icon % 1 ~= 0 then return nil, "Invalid macro icon" end
    local showTooltip, steps = ReadMacroField(source, "showTooltip", true), ReadMacroField(source, "steps", {})
    if not Is(showTooltip, "boolean") then return nil, "Invalid macro document" end
    if not Array(steps, Model.MAX_STEPS) then return nil, "Too many macro actions" end
    local result = { version = Model.VERSION, name = name, mode = mode, scope = scope, icon = icon,
        raw = raw:gsub("\r\n", "\n"):gsub("\r", "\n"), showTooltip = showTooltip, steps = {} }
    for i, step in ipairs(steps) do
        result.steps[i] = CopyStep(step)
        if not result.steps[i] then return nil, "Invalid macro action" end
    end
    local consumable = ReadMacroField(source, "consumable")
    if consumable ~= nil then
        result.consumable = CopyConsumable(consumable)
        if not result.consumable then return nil, "Invalid consumable settings" end
    elseif mode == "consumable" then
        return nil, "Choose a consumable type"
    end
    return result
end

function Model.NewCondition(key)
    return { key = key or "combat", value = key == "unit" and "target" or key == "mod" and "shift" or "", negate = false }
end

function Model.NewBranch()
    return { conditions = {}, value = "", useFirst = false }
end

function Model.NewStep(command)
    return { command = command or "cast", branches = { Model.NewBranch() }, sequence = {}, reset = {} }
end

function Model.New(templateID)
    for _, template in ipairs(Macros.Templates) do
        if template.id == templateID then return Model.Normalize(template.document) end
    end
    return { version = Model.VERSION, name = "", scope = "character", icon = 134400,
        mode = "rules", raw = "", showTooltip = true, steps = { Model.NewStep() } }
end
