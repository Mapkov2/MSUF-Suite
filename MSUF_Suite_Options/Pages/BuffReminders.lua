local _, P = ...
local S, Tr = P.S, P.Tr
local PAGE, ID = "suite_buffReminders", "buffReminders"
local ADDON = "MSUF_Suite_BuffReminders"
-- The recommended consumables use Retail's items and equipment rules.
P.Requires.modernEquipment = function() return P.Suite.Client.modernEquipment == true end
P.Requires.foreverEquipment = function() return P.Suite.Client.isForever == true end

local HELP = {
    demons = "Tick every demon you want out; demons your character has not learned yet can be ticked too. A summoned demon you left unticked gets a notice, as long as one of your ticked demons can be summoned. Another look of a demon counts as that demon once you have summoned it in that look.",
    tracking = P.Help("Choose buffs and consumables to track.", "The class buff is included only when your character knows it. Enter self-buff spell IDs separated by spaces or commas. For a consumable, enter item ID:aura ID; separate pairs with commas. Up to 12 total reminders are shown. Weapon enchant items use the main-hand or off-hand enchant state."),
    recommended = P.Help("Reminders for missing poisons and consumables.", "Mainline covers Rogue poisons, this season's flasks, augment runes and weapon oils, and the Well Fed food buff. Each category clicks the first matching item in your bags; an item you enter for it is tried first. Food is found in your bags by the game's eating spells: the food you enter comes first, then the newest one. With the gray reminder on, a category with nothing left stays visible without a click action. Assassination prefers Deadly Poison; Outlaw and Subtlety prefer Instant Poison. Dragon-Tempered Blades allows two poisons per category. Oils target equipped weapons; known Shaman or Paladin imbues suppress automatic oils."),
    visibility = P.Help("Show missing or expiring buffs outside combat.", "Reminders appear only outside combat. The advance setting also shows active buffs, food and weapon enchants when their remaining time reaches the chosen number of minutes; 0 shows only missing effects. A single scheduled wakeup handles the next threshold. Reminders hide in arenas and battlegrounds, where aura data can be restricted."),
    appearance = "Click a reminder to cast its spell or use its item. Aura checks run on relevant events; there is no repeating scan.",
    position = P.Help("Move the reminder row in MSUF Edit Mode or set its offsets here.",
        "Choose an MSUF or Suite element to follow, then set the reminder point, anchor point and offsets."),
    readycheck = "When a ready check starts outside combat and your mana as a healer is low, a short note shows how much you have; it turns red below half of your limit. Only your own mana is read.",
}
HELP.visibility = P.Help("Show missing or expiring buffs outside combat.", "Pick the places where reminders may show; arenas and battlegrounds never show them. Before a keystone starts, buffs can be asked to last the dungeon's timer or a number of minutes; once the key starts, the normal warning time applies again. One scheduled wakeup handles the next expiry.")
HELP.classReminders = P.Help("Reminders for the buffs your class and specialization keep up.",
    "Switch on the first option, then keep or drop the reminders you want. A reminder shows only when your "
    .. "character knows its spell. Stances, auras, shields, Shadowform and weapon or shield imbues show while "
    .. "they are missing. Buffs you put on an ally (Source of Magic, Blistering Scales, Earth Shield, "
    .. "Symbiotic Relationship) show while your buff is on nobody in the group; target an ally and click the "
    .. "icon to cast it. Right-click or middle-click any reminder to hide it until you reload the UI.")

-- { catalog section, accordion title } in page order.
local SECTIONS = {
    { "tracking", "What to remind" },
    { "classReminders", "Class reminders" },
    { "demons", "Warlock demon choice" },
    { "recommended", "Recommended consumables (Mainline)", "modernEquipment" },
    { "foreverConsumables", "Consumables (Forever)", "foreverEquipment" },
    { "visibility", "When to show" },
    { "readycheck", "Ready check" },
    { "classVisibility", "Class and group reminders" },
    { "personalVisibility", "Personal spell reminders" },
    { "consumableVisibility", "Consumable and weapon reminders" },
    { "appearance", "Icons" },
    { "position", "Anchors" },
}

-- Forever-only class reminders show to their own class.
P.Gates[ID] = function(rule)
    local expected = rule.foreverClass
    if expected then
        local _, class = UnitClass("player")
        return P.Suite.Client.isForever == true and P.Suite.Public(class) and class == expected
    end
    if rule.key == "readyCheckRaidBuffNames" then return P.Suite.Client.modernEquipment == true end
    if rule.key == "campfireBuff" or rule.key == "personalBuffWarningSeconds" then return P.Suite.Client.isForever == true end
    return true
end

-- The map the player stands on joins the map potion's list once.
local function AddPotionMap()
    local map = C_Map.GetBestMapForUnit("player")
    if not P.Suite.Public(map) or type(map) ~= "number" or map <= 0 then return end
    local value = P.Get(ID, "mapPotionMaps")
    for token in value:gmatch("%d+") do
        if tonumber(token) == map then return end
    end
    P.Set(ID, "mapPotionMaps", value == "" and tostring(map) or value .. "," .. map)
end

local function SkinStatus(ctx)
    return function(body, y, width)
        local height = P.Suite.HostBridge.IconSkinStatusRow(P.M, ctx, body, 16, y - 8, width, P.IconSkinKey(ID))
        return height > 0 and y - 8 - height or y
    end
end

local function PlaySoundChoice(choice)
    if P.PreviewCanvas.Runtime(ADDON, "BuffRemindersPlaySound") then
        return S.BuffRemindersPlaySound(choice, P.Get(ID, "reminderSoundChannel"))
    end
end

local function BindSoundPicker(_, entries)
    for _, entry in ipairs(entries or {}) do
        local widget, rule = entry.widget, entry.rule
        if widget and rule.key == "reminderSound" then
            widget:SetScript("OnClick", function(anchor)
                if not P.RuleEnabled(ID, rule) then return end
                P.OpenSoundChoicePicker(anchor, P.Get(ID, rule.key), rule.choices,
                    function(value)
                        if P.RuleEnabled(ID, rule) then P.Set(ID, rule.key, value) end
                    end, PlaySoundChoice)
            end)
            widget:HookScript("OnHide", P.CloseSoundChoicePicker)
            return
        end
    end
end

local function AnchorGrid(ctx, rules)
    return function(body, y, width)
        local section = PAGE .. "_position"
        local built = P.RuleRows(PAGE, ID, rules, nil, section)
        for i = #built.strings, 1, -1 do
            local rule = built.strings[i]
            if rule.key == "anchorTarget" then
                table.remove(built.strings, i)
                local row = P.Meta(PAGE, ID, rule.key, "setting", section)
                row.id, row.label, row.kind = rule.key, Tr(rule.label), "dropdown"
                row.get = function() return P.Get(ID, "anchorTarget") end
                row.set = function(value) return P.Set(ID, "anchorTarget", value) end
                row.values = function()
                    local values = P.Suite.HostBridge.EditAnchorChoices("external:msufsuite.buffreminders:buffs")
                    local current, found = P.Get(ID, "anchorTarget"), false
                    for _, value in ipairs(values) do if value.value == current then found = true end end
                    if not found then values[#values + 1] = { value = current, text = Tr("Unavailable") } end
                    return values
                end
                table.insert(built.rows, 1, row)
                table.insert(built.pending, 1, rule)
            end
        end
        return P.RuleGrid(ctx, body, PAGE, ID, rules, y, width, nil, section, nil, built)
    end
end

local function Build(ctx)
    local b, ui = P.MenuWorkspace.Builder(ctx, { page = PAGE, module = ID, title = "Buff Reminders", height = 202,
        tabs = {
            { id = "reminders", label = "What to remind",
                sections = "buffReminders_module composer tracking classReminders demons recommended foreverConsumables readycheck" },
            { id = "visibility", label = "When to show", sections = "visibility classVisibility personalVisibility consumableVisibility" },
            { id = "appearance", label = "Appearance", sections = "appearance position" },
        } })
    P.MenuSamples.Reminders(ui)
    P.ModuleCard(ctx, b, PAGE, ID, {
        { "Edit Mode", function() P.OpenEditMode(ID, "buffs") end,
            function() return P.EditModeReady() and S.Status(ID) == "Active" end, key = "edit" },
        { "Add this map to the potion maps", AddPotionMap, nil, key = "potionMap" },
        P.PlannerAction("preparation"),
    })
    P.ReminderEditor.Build(ctx, b)
    for _, section in ipairs(SECTIONS) do
        if not section[3] or P.Requires[section[3]]() then
            if section[1]:match("Visibility$") then
                P.ReminderVisibility.Build(ctx, b, section[1], section[2])
            else
                P.MenuWorkspace.Rules(ctx, b, PAGE, ID, PAGE .. "_" .. section[1], Tr(section[2]),
                    P.SectionRules(ID, section[1]), { help = HELP[section[1]], open = false,
                        extra = section[1] == "appearance" and SkinStatus(ctx) or nil,
                        onBuilt = section[1] == "appearance" and BindSoundPicker or nil,
                        grid = section[1] == "position" and AnchorGrid(ctx, P.SectionRules(ID, "position")) or nil })
            end
        end
    end
    P.MenuWorkspace.Finish(ui)
end

P.RegisterPage({ key = PAGE, label = "Buff Reminders", title = "Buff Reminders", build = Build, icon = { 7, 1 },
    nav = "combat", navOrder = 3,
    aliases = { "buffreminders", "buffs", "reminders", "consumables" } })
