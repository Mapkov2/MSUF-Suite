local _, P = ...
local Page = P.MacroPage

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr = P.MacroPage, P.MacroPage.helpers, P.Tr
    Helpers.ConsumableChoices = function()
        if Helpers.kinds then return end
        Helpers.kinds = { { value = "health", text = "Health supplies" }, { value = "drink", text = "Food and drink" },
            { value = "food", text = "Buff food" }, { value = "flask", text = "Flasks" }, { value = "bandage", text = "Bandages" } }
        Helpers.priorities = { { value = "stone", text = "Healthstone" }, { value = "potion", text = "Healing potion" },
            { value = "spell", text = "Healing spell" } }
        Helpers.stats = { { value = "any", text = "Automatic" }, { value = "haste", text = "Haste" },
            { value = "criticalStrike", text = "Critical strike" }, { value = "mastery", text = "Mastery" },
            { value = "versatility", text = "Versatility" } }

    end

    Helpers.Choices = function(source)
        local values = {}
        for _, value in ipairs(source) do values[#values + 1] = { value = value.value, text = Tr(value.text) } end
        return values
    end


    Helpers.Health = function(ui, config, y, width)
        local columns = width < 570 and 1 or 3
        local column = math.floor((width - 32 - (columns - 1) * 10) / columns)
        for i = 1, 3 do
            Page.Select(ui, "consumable:priority:" .. i, string.format(Tr("Priority %d"), i), Helpers.Choices(Helpers.priorities),
                config.priorities[i] or Helpers.priorities[i].value, 16 + ((i - 1) % columns) * (column + 10),
                y - math.floor((i - 1) / columns) * 62, column, function(value)
                    local previous = config.priorities[i]
                    for j = 1, 3 do if config.priorities[j] == value then config.priorities[j] = previous end end
                    config.priorities[i] = value
                    Page.Changed(true)
                end)
        end
        y = y - math.ceil(3 / columns) * 62 - 4
        Page.Toggle(ui, "consumable:stop", "Stop casting first", config.stopCasting, 16, y, width - 32,
            function(value) config.stopCasting = value Page.Changed(false) end)
        y = y - 40
        Page.Toggle(ui, "consumable:reset", "Reset when combat ends", config.reset.combat, 16, y, width - 32,
            function(value) config.reset.combat = value Page.Changed(false) end)
        y = y - 43
        Page.Label(ui, "consumable:spells:title", Tr("Healing spells"), 16, y, width - 32)
        return Helpers.PickedList(ui, config, "spells", y - 29, width, "spell")
    end

    Helpers.Recovery = function(ui, config, y, width)
        Page.Toggle(ui, "consumable:conjured", "Prefer conjured food", config.preferConjured, 16, y, width - 32,
            function(value) config.preferConjured = value Page.Changed(false) end)
        y = y - 39
        if config.kind == "drink" then
            Page.Toggle(ui, "consumable:food", "Include food", config.includeFood, 16, y, width - 32,
                function(value) config.includeFood = value Page.Changed(false) end)
            y = y - 39
            Page.Toggle(ui, "consumable:mana", "Mana potion in combat", config.combatMana, 16, y, width - 32,
                function(value) config.combatMana = value Page.Changed(false) end)
            y = y - 39
        end
        return y
    end

end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr = P.MacroPage, P.MacroPage.helpers, P.Tr
    Helpers.PickedList = function(ui, config, field, y, width, kind)
        local values = config[field]
        for i, value in ipairs(values) do
            local key = "consumable:" .. field .. ":" .. i
            local text = tostring(value)
            if field == "items" then
                local name = C_Item.GetItemNameByID(value)
                if not P.Suite.IsSecret(name) and type(name) == "string" then text = name end
            end
            Page.Label(ui, key, text, 20, y - 5, width - 120)
            Page.Button(ui, key .. ":remove", "Remove", width - 90, y, 76, function()
                table.remove(values, i)
                Page.Changed(true)
            end)
            y = y - 34
        end
        local picker
        picker = Page.Button(ui, "consumable:" .. field .. ":add", field == "items" and "Add item" or "Add spell",
            16, y, 130, function()
                Page.Pick(picker, kind, function(value)
                    values[#values + 1] = value
                    Page.Changed(true)
                end)
            end, #values < 24)
        return y - 44
    end

    function Page.RenderConsumables(ui, y, width)
        Helpers.ConsumableChoices()
        local config = Page.document.consumable
        Page.Select(ui, "consumable:kind", "Use", Helpers.Choices(Helpers.kinds), config.kind, 16, y, width - 32,
            function(value) config.kind = value Page.Changed(true) end)
        y = y - 65
        local active = P.S.Config("macroBuilder").enabled == true
        Page.Toggle(ui, "consumable:enabled", "Update consumable macros", active, 16, y, width - 32,
            function(value)
                local ok, errorKey = P.Set("macroBuilder", "enabled", value)
                if not ok then Page.Error(errorKey) end
                Page.Render()
            end)
        y = y - 39
        Page.Toggle(ui, "consumable:managed", "Update this macro outside combat", config.managed ~= false,
            16, y, width - 32, function(value)
                config.managed = value
                Page.Changed(false)
            end)
        y = y - 42
        if not active then
            Page.Label(ui, "consumable:inactive", Tr("Automatic updates are off"), 16, y, width - 32, P.T.colors.muted)
            y = y - 28
        end
        if config.kind == "health" then y = Helpers.Health(ui, config, y, width) end
        if config.kind == "drink" or config.kind == "food" then y = Helpers.Recovery(ui, config, y, width) end
        if config.kind == "flask" then
            Page.Select(ui, "consumable:stat", "Preferred stat", Helpers.Choices(Helpers.stats), config.stat or "any",
                16, y, width - 32, function(value) config.stat = value Page.Changed(false) end)
            y = y - 68
        end
        Page.Label(ui, "consumable:items:title", Tr("Preferred items"), 16, y, width - 32)
        Page.Label(ui, "consumable:items:auto", Tr("Empty list: choose from bags automatically"), 16, y - 21,
            width - 32, P.T.colors.muted)
        y = Helpers.PickedList(ui, config, "items", y - 49, width, "itemID")
        return y
    end

end
