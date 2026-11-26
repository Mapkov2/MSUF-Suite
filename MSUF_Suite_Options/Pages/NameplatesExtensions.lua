local _, P = ...
local UI = {}
P.NameplatesExtensions = UI
local X = P.Suite.NameplateExtensions

local DISPLAY_SECTIONS = {
    plateNameDisplay = { enemy = 41, neutral = 41, friendly = 41, friendlyNpc = 41 },
    plateHealthDisplay = { enemy = 21, neutral = 21, friendly = 21, friendlyNpc = 21 },
    platePvpMarkers = { enemy = 71, friendly = 71 },
    plateNpcMarkers = { enemy = 72, neutral = 72, friendlyNpc = 72 },
    auraSpellEmphasis = { enemy = 31, neutral = 31, friendly = 31, friendlyNpc = 31 },
    platePersonalDisplay = { friendly = 51 },
}

local function AddHelp(help)
    if not help then return end
    help.castFeedback = P.Help("Show timed feedback when Blizzard reports an interrupted cast.",
        "The duration controls the feedback display. The interrupt event provides the interrupter but no enemy school-lockout duration.")
    help.combatExtensions = P.Help("Emphasize focused, casting and low-health enemies. Focus reminders apply to casters and lieutenants.",
        "Reminders appear while you have no hostile focus. The pulse uses your health threshold. Protected scale changes wait until combat ends.")
    help.plateClickArea = P.Help("Adjust the clickable area of native nameplates.",
        "Hit testing stays inside native plate bounds. Changes wait for Blizzard's hit-test permission. Forbidden friendly plates use Blizzard's rules.")
    help.plateRange = P.Help("Choose a spell from your spellbook or enter its ID.",
        "Spell range applies to your current target. Distance and stacking apply to all nameplates.")
    help.plateContext = P.Help("Choose opacity, scale and visibility separately for each unit type.",
        "Location rules cover world, dungeon, raid and PvP. Cast rules follow native events. Unknown unit or location data keeps the plate visible.")
    help.enemyLoadConditions = P.Help("Hide enemy nameplates when any checked condition matches.",
        "Show only below 100% health replaces the three rules for no target and out of combat. "
            .. "A transparent plate can still receive clicks. Hide rules clear the click area when the game permits it.")
    help.extraPlateText = P.Help("Add four labels using native unit, quest-tooltip, threat, resource and Mythic+ data.",
        "NPC titles use tooltip subtitles. Threat differences need public values for you and the tank. Missing data can show a question mark.")
    help.threatDetail = P.Help("Focus > safe tank threat > other tank > threat > tapped > quest > neutral > NPC type.",
        "Separate orange warnings use native threat level 2. Level 1 keeps the usual warning color. Tracked aura colors can cover the role tint.")
    help.plateIdentity = P.Help("Show class and faction icons beside player names when identity data is public.",
        "Blizzard's classification marker continues to show supported flag, cart and orb carriers. Restricted identities hide the extra icons.")
end

local function Gates()
    local previous = P.Gates.nameplates
    P.Gates.nameplates = function(rule, key)
        if rule.section == "castExtensions" or rule.section == "combatExtensions" or rule.section == "plateInteraction"
            or rule.section == "plateContext" or rule.section == "plateDimensions" or rule.section == "enemyLoadConditions"
            or rule.section == "plateOpacity"
            or rule.section == "threatDetail" or rule.section == "plateIdentity"
            or rule.section == "plateExtraText" or DISPLAY_SECTIONS[rule.section] then
            if P.Get("nameplates", "look") == 2 then
                return false, P.Tr("Choose a nameplate look other than Blizzard under Look.")
            end
        end
        if rule.section == "plateOpacity" then
            local side = key:match("^friendly") and "friendly" or "enemy"
            if not P.Get("nameplates", side) then
                return false, P.Tr(side == "enemy" and "Skin enemy nameplates" or "Skin friendly nameplates")
            end
        end
        if rule.section == "enemyLoadConditions" and not P.Get("nameplates", "enemy") then
            return false, P.Tr("Skin enemy nameplates")
        end
        if previous then return previous(rule, key) end
        return true
    end
end

local function EnemyVisibility()
    local keys = {}
    for _, condition in ipairs(X.EnemyConditions or {}) do keys[#keys + 1] = condition.key end
    return { key = "enemyVisibility", area = "enemies", title = "Load Conditions", keys = keys,
        help = "enemyLoadConditions", columns = 3,
        summary = function()
            local config = P.S.Config("nameplates")
            local count = 0
            if config.enabled and config.enemy and config.look ~= 2 then
                for _, condition in ipairs(X.EnemyConditions or {}) do
                    if X.EnemyConditionActive(config, condition) then count = count + 1 end
                end
            end
            return P.Tr("%d active conditions"):format(count)
        end }
end

function UI.Append(sections, help)
    AddHelp(help)
    sections[#sections + 1] = { key = "castExtensions", area = "casts", title = "Interrupted casts",
        colors = { "interruptFeedbackColor" }, help = "castFeedback", keys = {
            "interruptFeedbackEnabled", "interruptFeedbackShared", "interruptFeedbackDuration", "interruptFeedbackFlash", "interruptFeedbackWho" } }
    sections[#sections + 1] = { key = "combatExtensions", area = "enemies", title = "Combat emphasis",
        colors = { "focusReminderColor", "executePulseColor" }, keys = {
            "focusScaleEnabled", "focusScalePercent", "castingScaleEnabled", "castingScalePercent", "focusReminderEnabled",
            "executePulseEnabled", "executePulsePercent", "executePulseAlpha" } }
    sections[#sections + 1] = { key = "threatDetail", area = "colors", title = "Threat warning detail",
        keys = { "enemyThreatTransitionEnabled" }, colors = { "enemyThreatTransitionColor" } }
    sections[#sections + 1] = { key = "plateIdentity", area = "enemies", title = "Player identity icons", tabs = {
        { id = "enemy", label = "Enemy", help = "plateIdentity", keys = {
            "enemyIdentityIcons", "enemyIdentityIconSize", "enemyIdentityIconX", "enemyIdentityIconY" } },
        { id = "friendly", label = "Friendly", help = "plateIdentity", keys = {
            "friendlyIdentityIcons", "friendlyIdentityIconSize", "friendlyIdentityIconX", "friendlyIdentityIconY" } },
    } }
    sections[#sections + 1] = EnemyVisibility()
    for catalog, scopes in pairs(DISPLAY_SECTIONS) do
        sections[#sections + 1] = { key = catalog, catalog = catalog, scopes = scopes }
    end
end

Gates()

local PAGE, ID, Tr = "suite_nameplates", "nameplates", P.Tr

local function AddBookSpells(menu, key)
    local book, spell, public = C_SpellBook, C_Spell, P.Suite.Public
    local bank = Enum.SpellBookSpellBank.Player
    local lines = book.GetNumSpellBookSkillLines()
    if not public(lines) or type(lines) ~= "number" then return end
    local choices, seen = {}, {}
    for i = 1, lines do
        local line = book.GetSpellBookSkillLineInfo(i)
        local offset = public(line) and type(line) == "table" and line.itemIndexOffset
        local count = public(line) and type(line) == "table" and line.numSpellBookItems
        if public(offset) and type(offset) == "number" and public(count) and type(count) == "number" then
            for index = offset + 1, offset + count do
                local info = book.GetSpellBookItemInfo(index, bank)
                local id = public(info) and type(info) == "table" and info.spellID
                if public(id) and type(id) == "number" and id > 0 and not seen[id] then
                    local known, ranged = book.IsSpellKnown(id), spell.SpellHasRange(id)
                    if public(known) and known and public(ranged) and ranged then
                        local name = spell.GetSpellName(id)
                        if public(name) and type(name) == "string" then
                            local icon = info.iconID
                            if not public(icon) or type(icon) ~= "number" or icon <= 0 then icon = nil end
                            seen[id] = true
                            choices[#choices + 1] = { name = name, id = id, icon = icon }
                        end
                    end
                end
            end
        end
    end
    table.sort(choices, function(a, b)
        if a.name == b.name then return a.id < b.id end
        return a.name < b.name
    end)
    for _, entry in ipairs(choices) do
        local id = entry.id
        local label = ("%s (%d)"):format(entry.name, id)
        if entry.icon then
            label = ("|T%d:14:14:0:0:64:64:5:59:5:59|t  %s"):format(entry.icon, label)
        end
        menu:CreateRadio(label, function() return P.Get(ID, key) == id end, function() P.Set(ID, key, id) end)
    end
end

function UI.RangeSpell(ctx, body, y, width, sectionId, rule)
    local key = rule.key
    local label = Tr(rule.label)
    local input = P.M.BindTextInputAt(ctx, body, label, 16, y, math.min(width, 280), function()
        local value = P.Get(ID, key)
        return value > 0 and value or ""
    end, function(value)
        if P.Combat() then return end
        if value == "" then P.Set(ID, key, 0) return end
        local id = tonumber(value)
        if id and id > 0 and id <= rule.max and id == math.floor(id) then P.Set(ID, key, id) end
    end, true, P.Meta(PAGE, ID, key, "setting", sectionId))
    P.StyleMenuControl(input)
    if input.SetNumeric then input:SetNumeric(true) end
    if input.SetMaxLetters then input:SetMaxLetters(8) end
    local button
    local top, x = width < 490 and y - 52 or y - 22, width < 490 and 16 or 312
    button = P.Button(ctx, body, "Choose from spellbook", x, top, 172, function()
        P.ContextMenu(button, function(_, menu)
            if P.Combat() then return end
            if menu.SetScrollMode then menu:SetScrollMode(360) end
            menu:CreateButton(Tr("Clear"), function() P.Set(ID, key, 0) end)
            AddBookSpells(menu, key)
        end)
    end)
    local controls = { { rule = rule, widget = input }, { rule = rule, widget = button } }
    P.GateControls(ctx, ID, controls)
    local bottom = math.min(y - 58, top - 36)
    local selected = P.Text(body, "", 16, bottom + 4, width)
    local previous
    P.M.TrackRefresh(ctx, function()
        if P.Combat() then return end
        local id = P.Get(ID, key)
        if id == previous then return end
        previous = id
        local name = id > 0 and C_Spell.GetSpellName(id)
        selected:SetText(P.Suite.Public(name) and type(name) == "string" and name or "")
    end)
    return bottom - 20, controls
end
