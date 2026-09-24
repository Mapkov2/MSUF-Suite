local _, P = ...
local S, Tr = P.S, P.Tr
local PAGE, ID = "suite_buffReminders", "buffReminders"
P.Requires.buffRemindersMainline = function() return P.Suite.Client.modernEquipment == true end

local HELP = {
    tracking = "The class buff is included only when your character knows it. Enter self-buff spell IDs separated by spaces or commas. For a consumable, enter item ID:aura ID; separate pairs with commas. Up to 12 total reminders are shown. Weapon enchant items use the main-hand or off-hand enchant state.",
    recommended = "Mainline defaults cover Rogue poisons, current flasks, food, augment runes and weapon oils. Assassination prefers Deadly Poison; Outlaw and Subtlety prefer Instant Poison. A known nonlethal poison is also tracked. With Dragon-Tempered Blades, Assassination tracks up to two lethal and two nonlethal poisons. Active alternatives fill their category's slots, and each missing icon casts a known poison that is not already active. Consumables choose supported items already in your bags. Oils target equipped weapons; known Shaman or Paladin imbues suppress automatic oils.",
    visibility = "Reminders appear only outside combat. The advance setting also shows active buffs, food and weapon enchants when their remaining time reaches the chosen number of minutes; 0 shows only missing effects. A single scheduled wakeup handles the next threshold. Reminders hide in arenas and battlegrounds, where aura data can be restricted.",
    appearance = "Click a reminder to cast its spell or use its item. Aura checks run on relevant events; there is no repeating scan.",
    position = "Move the reminder row in MSUF Edit Mode or set its offsets here.",
}

local function Build(ctx)
    local b = P.W.PageBuilder(ctx)
    P.ModuleCard(ctx, b, PAGE, ID, {
        { "Edit Mode", function() S.OpenEditMode(ID, "buffs") end,
            function() return S.Status(ID) == "Active" end, key = "edit" },
        { "Reset module", function()
            P.WithHistory("Reset buff reminders", "suite:buffReminders.reset", function() return S.Reset(ID) end)
        end, key = "reset" },
    })
    for _, section in ipairs({ "tracking", "recommended", "visibility", "appearance", "position" }) do
        local title = ({ tracking="What to remind", recommended="Recommended consumables (Mainline)", visibility="When to show", appearance="Icons", position="Position" })[section]
        P.RuleSection(ctx, b, PAGE, ID, PAGE .. "_" .. section, Tr(title),
            P.SectionRules(ID, section), { help=Tr(HELP[section]), open=section == "tracking" })
    end
end

P.RegisterPage({ key=PAGE, label="Buff Reminders", title="Buff Reminders", build=Build, icon={ 7, 1 },
    aliases={ "buffreminders", "buffs", "reminders", "consumables" } })
