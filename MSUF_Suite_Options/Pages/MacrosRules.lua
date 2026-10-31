local _, P = ...
local Page = P.MacroPage

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr, Model = P.MacroPage, P.MacroPage.helpers, P.Tr, P.Suite.Macros.Model
    Helpers.ValueInput = function(ui, key, branch, command, y, width)
        local spec = Model.CommandByKey[command]
        if spec.argument == "none" then return y end
        if command == "tm" then
            local selected = tonumber((branch.value:gsub("^[!~]", ""))) or 8
            Page.Select(ui, key .. ":marker", "Target marker", Helpers.Markers(false), selected,
                16, y, width - 32, function(value)
                    branch.value = value > 0 and "!" .. value or "0"
                    Page.Changed(false)
                end)
            return y - 61
        end
        if command == "wm" or command == "cwm" then
            local selected = branch.value == "all" and "all" or tonumber(branch.value) or 1
            Page.Select(ui, key .. ":world-marker", spec.label, Helpers.WorldMarkers(command == "cwm"), selected,
                16, y, width - 32, function(value) branch.value = tostring(value) Page.Changed(false) end)
            return y - 61
        end
        if command == "equipslot" then return Helpers.EquipSlot(ui, key, branch, y, width) end
        if command == "changeactionbar" or command == "swapactionbar" then
            local values, pages = {}, {}
            for i = 1, 6 do values[i] = { value = i, text = tostring(i) } end
            for page in branch.value:gmatch("%d+") do pages[#pages + 1] = tonumber(page) end
            for i = 1, command == "swapactionbar" and 2 or 1 do
                Page.Select(ui, key .. ":page:" .. i, i == 1 and "Action bar page" or "Second action bar page",
                    values, pages[i] or i, 16, y, width - 32, function(value)
                        pages[i] = value
                        branch.value = tostring(pages[1] or 1)
                        if command == "swapactionbar" then branch.value = branch.value .. " " .. tostring(pages[2] or 2) end
                        Page.Changed(false)
                    end)
                y = y - 61
            end
            return y
        end
        local picker = command == "cast" or command == "use" or command == "cancelaura"
            or command == "equip" or command == "equipslot" or command:find("petautocast", 1, true)
        Page.Edit(ui, key .. ":action", "Then", branch.value, 16, y, width - (picker and 104 or 32), function(value)
            branch.value = value
            Page.Changed(false)
        end)
        if picker then
            local choose
            choose = Page.Button(ui, key .. ":pick", "Choose", width - 82, y - 23, 78, function()
                local kind = "spell"
                if command == "use" or command == "equip" or command == "equipslot" then kind = "item" end
                if command:find("petautocast", 1, true) then kind = "pet" end
                Page.Pick(choose, kind, function(value)
                    branch.value = command == "equipslot" and "16 " .. value or value
                    Page.Changed(true)
                end)
            end)
        end
        return y - 61
    end

    Helpers.WorldMarkers = function(clear)
        local key = clear and "clearWorldMarkers" or "worldMarkers"
        if Helpers[key] then return Helpers[key] end
        local values, markers = {}, Helpers.Markers(false)
        if clear then values[1] = { value = "all", text = Tr("All") } end
        for id, raidID in ipairs({ 6, 4, 3, 7, 1, 2, 5, 8 }) do
            local marker = markers[raidID + 1]
            values[#values + 1] = { value = id, text = marker.text, icon = marker.icon }
        end
        Helpers[key] = values
        return values
    end
end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr, Model = P.MacroPage, P.MacroPage.helpers, P.Tr, P.Suite.Macros.Model
    Helpers.Step = function(ui, step, index, y, width)
        local key = "step:" .. index
        Page.Label(ui, key .. ":title", string.format(Tr("Action %d"), index), 16, y, 150)
        Page.Button(ui, key .. ":up", "Move up", width - 173, y + 3, 83,
            function() Page.Move(Page.document.steps, index, -1) end, index > 1)
        Page.Button(ui, key .. ":remove", "Remove", width - 84, y + 3, 80, function()
            table.remove(Page.document.steps, index)
            Page.Changed(true)
        end)
        y = y - 35
        Page.Select(ui, key .. ":command", "Action", Page.Values(Model.Commands), step.command, 16, y, width - 32,
            function(value)
                local nextStep = Model.NewStep(value)
                if value == "changeactionbar" then nextStep.branches[1].value = "1" end
                if value == "swapactionbar" then nextStep.branches[1].value = "1 2" end
                if value == "tm" then nextStep.branches[1].value = "!8" end
                if value == "wm" or value == "cwm" then nextStep.branches[1].value = "1" end
                Page.document.steps[index] = nextStep
                Page.Changed(true)
            end)
        y = y - 63
        local spec = Model.CommandByKey[step.command]
        if spec.supportsRaidMarker then y = Helpers.AttachedMarker(ui, step, key, y, width) end
        if spec.argument == "raw" then
            Page.Edit(ui, key .. ":raw", "Custom command", step.raw, 16, y, width - 32,
                function(value) step.raw = value Page.Changed(false) end, true)
            return y - 185
        end
        if spec.argument == "sequence" then return Helpers.Sequence(ui, step, index, y, width) - 20 end
        for i, branch in ipairs(step.branches) do y = Helpers.Branch(ui, step, index, branch, i, y, width) end
        if spec.conditional ~= false then
            Page.Button(ui, key .. ":add-rule", "Add alternative", 16, y, 155, function()
                local branch = Model.NewBranch()
                branch.useFirst = true
                step.branches[#step.branches + 1] = branch
                Page.Changed(true)
            end, #step.branches < Model.MAX_BRANCHES)
            y = y - 42
        end
        return y - 15
    end

    Helpers.ConditionRow = function(ui, key, condition, list, index, y, width, ordinal)
        local controlWidth = math.max(100, math.floor((width - 190) / 2))
        local narrow = width < 510
        Page.Select(ui, key .. ":kind", (ordinal or index) == 1 and "If" or "And", Page.Values(Helpers.extraConditions), condition.key,
            16, y, narrow and width - 32 or controlWidth, function(value)
                list[index] = Model.NewCondition(value)
                Page.Changed(true)
            end)
        local valueX, valueY = narrow and 16 or 26 + controlWidth, narrow and y - 57 or y
        Helpers.ConditionValue(ui, key .. ":value", condition, valueX, valueY, controlWidth)
        local actionsY = narrow and y - 81 or y - 23
        local actionsX = width - 150
        local negate = Page.Toggle(ui, key .. ":not", "Not", condition.negate, actionsX, actionsY, 56, function(value)
            condition.negate = value
            Page.Changed(false)
        end)
        negate:SetEnabled(condition.key ~= "unit")
        Page.Button(ui, key .. ":remove", "Remove", actionsX + 61, actionsY, 68, function()
            table.remove(list, index)
            Page.Changed(true)
        end)
        local extra = Model.ConditionByKey[condition.key].kind == "spellID" and 32 or 0
        return y - (narrow and 116 or 60) - extra
    end
end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr, Model = P.MacroPage, P.MacroPage.helpers, P.Tr, P.Suite.Macros.Model
    Helpers.RuleChoices = function()
        if Helpers.modifiers then return end
        Helpers.modifiers = { { value = "shift", text = "Shift" }, { value = "ctrl", text = "Ctrl" },
            { value = "alt", text = "Alt" }, { value = "any", text = "Any modifier" }, { value = "none", text = "No modifier" } }
        Helpers.units = { { value = "target", text = "Current target" }, { value = "mouseover", text = "Mouseover" },
            { value = "focus", text = "Focus" }, { value = "player", text = "Self" },
            { value = "pet", text = "Pet" }, { value = "targettarget", text = "Target of target" },
            { value = "focustarget", text = "Target of focus" }, { value = "pettarget", text = "Target of pet" },
            { value = "cursor", text = "Cursor" } }
        for i = 1, 4 do
            Helpers.units[#Helpers.units + 1] = { value = "party" .. i, text = string.format(Tr("Party member %d"), i) }
        end
        for i = 1, 40 do
            Helpers.units[#Helpers.units + 1] = { value = "raid" .. i, text = string.format(Tr("Raid member %d"), i) }
        end
        for i = 1, 5 do
            Helpers.units[#Helpers.units + 1] = { value = "boss" .. i, text = string.format(Tr("Boss %d"), i) }
        end
        for i = 1, P.Suite.Client.isForever and 0 or 3 do
            Helpers.units[#Helpers.units + 1] = { value = "arena" .. i, text = string.format(Tr("Arena opponent %d"), i) }
        end
        Helpers.reset_keys = { { value = "", text = "None" }, { value = "shift", text = "Shift" },
            { value = "ctrl", text = "Ctrl" }, { value = "alt", text = "Alt" } }
        Helpers.equipment = { { 16, "Main hand" }, { 17, "Off hand" }, { 1, "Head" }, { 2, "Neck" },
            { 3, "Shoulders" }, { 4, "Shirt" }, { 5, "Chest" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" },
            { 9, "Wrists" }, { 10, "Hands" }, { 11, "Ring 1" }, { 12, "Ring 2" }, { 13, "Trinket 1" },
            { 14, "Trinket 2" }, { 15, "Back" }, { 19, "Tabard" } }
        Helpers.extraConditions = {}
        for _, condition in ipairs(Model.Conditions) do
            if condition.key ~= "unit" then Helpers.extraConditions[#Helpers.extraConditions + 1] = condition end
        end

    end

    Helpers.EquipSlot = function(ui, key, branch, y, width)
        local slot, item = branch.value:match("^(%d+)%s+(.*)$")
        slot, item = tonumber(slot) or 16, item or ""
        local slots = {}
        for _, entry in ipairs(Helpers.equipment) do slots[#slots + 1] = { value = entry[1], text = Tr(entry[2]) } end
        Page.Select(ui, key .. ":slot", "Equipment slot", slots, slot, 16, y, width - 32, function(value)
            branch.value = tostring(value) .. " " .. item
            Page.Changed(true)
        end)
        y = y - 61
        Page.Edit(ui, key .. ":item", "Item", item, 16, y, width - 124, function(value)
            item = value
            branch.value = tostring(slot) .. " " .. value
            Page.Changed(false)
        end)
        local picker
        picker = Page.Button(ui, key .. ":pick", "Choose", width - 92, y - 23, 78, function()
            Page.Pick(picker, "item", function(value)
                branch.value = tostring(slot) .. " " .. value
                Page.Changed(true)
            end)
        end)
        return y - 61
    end

    Helpers.MarkerBlocked = function(step)
        for _, branch in ipairs(step.branches) do
            local value = branch.useFirst and step.branches[1].value or branch.value
            if (step.command == "startattack" or step.command == "petattack") and value:find("%S") then return true end
            for _, condition in ipairs(branch.conditions) do
                if condition.key == "unit" and condition.value == "cursor" then return true end
            end
        end
        return false
    end
end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr, Model = P.MacroPage, P.MacroPage.helpers, P.Tr, P.Suite.Macros.Model
    Helpers.Branch = function(ui, step, stepIndex, branch, index, y, width)
        local key = "step:" .. stepIndex .. ":branch:" .. index
        local spec = Model.CommandByKey[step.command]
        Page.Label(ui, key .. ":title", string.format(Tr("Rule %d"), index), 16, y, 150)
        if #step.branches > 1 then
            Page.Button(ui, key .. ":remove", "Remove", width - 84, y + 3, 80, function()
                Helpers.BranchOrder(step, index)
            end)
            Page.Button(ui, key .. ":up", "Move up", width - 173, y + 3, 83,
                function() Helpers.BranchOrder(step, index, -1) end, index > 1)
        end
        y = y - 32
        if spec.conditional ~= false then y = Helpers.Conditions(ui, key, branch, y, width) end
        if index > 1 and spec.argument ~= "none" then
            Page.Toggle(ui, key .. ":same", "Same action", branch.useFirst, 16, y, width - 32, function(value)
                branch.useFirst = value
                Page.Changed(true)
            end)
            y = y - 38
            if branch.useFirst then return y end
        end
        return Helpers.ValueInput(ui, key, branch, step.command, y, width)
    end

    Helpers.SequenceReset = function(ui, step, key, y, width)
        local reset = step.reset
        Page.Label(ui, key .. ":reset", Tr("Reset sequence"), 16, y, width - 32)
        y = y - 26
        local half = math.floor((width - 42) / 2)
        Page.Toggle(ui, key .. ":target", "Target changes", reset.target, 16, y, half, function(value)
            reset.target = value
            Page.Changed(false)
        end)
        Page.Toggle(ui, key .. ":combat", "Combat ends", reset.combat, 26 + half, y, half, function(value)
            reset.combat = value
            Page.Changed(false)
        end)
        y = y - 40
        Page.Edit(ui, key .. ":seconds", "Seconds without pressing", reset.seconds and tostring(reset.seconds) or "",
            16, y, half, function(value) reset.seconds = tonumber(value) Page.Changed(false) end)
        Page.Select(ui, key .. ":mod", "Reset key", Helpers.Translated(Helpers.reset_keys), reset.mod or "", 26 + half, y, half,
            function(value) reset.mod = value Page.Changed(false) end)
        return y - 65
    end

    Helpers.SequenceItem = function(ui, step, stepIndex, index, y, width)
        local key = "step:" .. stepIndex .. ":sequence:" .. index
        local inputWidth = width - 235
        local narrow = inputWidth < 160
        Page.Edit(ui, key, string.format(Tr("Step %d"), index), step.sequence[index], 16, y,
            narrow and width - 32 or inputWidth, function(value) step.sequence[index] = value Page.Changed(false) end)
        local actionY, actionX = narrow and y - 54 or y - 23, narrow and 16 or inputWidth + 24
        local pick
        pick = Page.Button(ui, key .. ":pick", "Choose", actionX, actionY, 76, function()
            Page.Pick(pick, "any", function(value) step.sequence[index] = value Page.Changed(true) end)
        end)
        Page.Button(ui, key .. ":up", "Up", actionX + 81, actionY, 45,
            function() Page.Move(step.sequence, index, -1) end, index > 1)
        Page.Button(ui, key .. ":remove", "Remove", actionX + 131, actionY, 66, function()
            table.remove(step.sequence, index)
            Page.Changed(true)
        end)
        return y - (narrow and 92 or 63)
    end
end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr, Model = P.MacroPage, P.MacroPage.helpers, P.Tr, P.Suite.Macros.Model
    Helpers.Target = function(ui, key, branch, y, width)
        local selected = "target"
        for _, condition in ipairs(branch.conditions) do
            if condition.key == "unit" then selected = condition.value break end
        end
        Page.Select(ui, key .. ":target", "Target", Helpers.Translated(Helpers.units), selected, 16, y, width - 32,
            function(value)
                for i = #branch.conditions, 1, -1 do
                    if branch.conditions[i].key == "unit" then table.remove(branch.conditions, i) end
                end
                if value ~= "target" then
                    local condition = Model.NewCondition("unit")
                    condition.value = value
                    table.insert(branch.conditions, 1, condition)
                end
                Page.Changed(true)
            end)
        return y - 61
    end

    Helpers.ConditionValue = function(ui, key, condition, x, y, width)
        local kind = Model.ConditionByKey[condition.key].kind
        local callback = function(value) condition.value = value Page.Changed(false) end
        if kind == "unit" or kind == "modifier" or kind == "group" then
            local values = kind == "unit" and Helpers.units or kind == "modifier" and Helpers.modifiers
                or { { value = "", text = "Any group" }, { value = "party", text = "Party" }, { value = "raid", text = "Raid" } }
            Page.Select(ui, key, "Value", Helpers.Translated(values), condition.value, x, y, width, callback)
        elseif kind == "spellID" then
            Page.Edit(ui, key, "Spell ID", condition.value, x, y, width, callback)
            local picker
            picker = Page.Button(ui, key .. ":pick", "Choose", x, y - 53, width, function()
                Page.Pick(picker, "spellID", function(value) condition.value = tostring(value) Page.Changed(true) end)
            end)
        elseif kind ~= "boolean" then
            Page.Edit(ui, key, Model.ConditionByKey[condition.key].label, condition.value, x, y, width, callback)
        end
    end

    Helpers.Conditions = function(ui, key, branch, y, width)
        y = Helpers.Target(ui, key, branch, y, width)
        local ordinal = 0
        for i, condition in ipairs(branch.conditions) do
            if condition.key ~= "unit" then
                ordinal = ordinal + 1
                y = Helpers.ConditionRow(ui, key .. ":c" .. i, condition, branch.conditions, i, y, width, ordinal)
            end
        end
        Page.Button(ui, key .. ":add-condition", "Add condition", 16, y, 145, function()
            branch.conditions[#branch.conditions + 1] = Model.NewCondition("mod")
            Page.Changed(true)
        end, #branch.conditions < Model.MAX_CONDITIONS)
        return y - 40
    end

    Helpers.BranchOrder = function(step, index, delta)
        local first = step.branches[1].value
        for _, branch in ipairs(step.branches) do
            if branch.useFirst then branch.value = first end
            branch.useFirst = false
        end
        if delta then
            local target = index + delta
            step.branches[index], step.branches[target] = step.branches[target], step.branches[index]
        else
            table.remove(step.branches, index)
        end
        Page.Changed(true)
    end
end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr, Model = P.MacroPage, P.MacroPage.helpers, P.Tr, P.Suite.Macros.Model
    Helpers.Markers = function(allowOff)
        local key = allowOff and "markersWithOff" or "markers"
        if Helpers[key] then return Helpers[key] end
        local names = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
        local values = {}
        if allowOff then values[#values + 1] = { value = -1, text = Tr("Off") } end
        values[#values + 1] = { value = 0, text = Tr("Clear marker") }
        for id, label in ipairs(names) do
            values[#values + 1] = { value = id, text = Tr(label), icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. id }
        end
        Helpers[key] = values
        return values
    end

    function Page.RenderRules(ui, y, width)
        Helpers.RuleChoices()
        for index, step in ipairs(Page.document.steps) do
            local top = y
            y = Helpers.Step(ui, step, index, y, width)
            Page.Card(ui, "action:" .. index, 8, top + 10, width - 16, top - y - 10)
        end
        Page.Button(ui, "add-action", "Add action", 16, y, 150, function()
            Page.document.steps[#Page.document.steps + 1] = Model.NewStep("cast")
            Page.Changed(true)
        end, #Page.document.steps < Model.MAX_STEPS)
        return y - 46
    end

    function Page.RefreshMarkers(ui)
        for index, step in ipairs(Page.document.steps) do
            local control = ui.pools.select and ui.pools.select["step:" .. index .. ":raid-marker"]
            if control and control:IsShown() then
                local blocked = Helpers.MarkerBlocked(step)
                if control.markerBlocked ~= blocked then
                    control.markerBlocked = blocked
                    control:SetValues(Helpers.MarkerChoices(blocked))
                end
            end
        end
    end

    Helpers.MarkerChoices = function(blocked)
        if not blocked then return Helpers.Markers(true) end
        if not Helpers.blockedMarkers then
            Helpers.blockedMarkers = {}
            for i, entry in ipairs(Helpers.Markers(true)) do
                Helpers.blockedMarkers[i] = { value = entry.value, text = entry.text, icon = entry.icon, disabled = entry.value ~= -1,
                    tooltipTitle = entry.text, tooltip = Tr("Markers need a unit target") }
            end
        end
        return Helpers.blockedMarkers
    end

    Helpers.AttachedMarker = function(ui, step, key, y, width)
        local blocked = Helpers.MarkerBlocked(step)
        local control = Page.Select(ui, key .. ":raid-marker", "Mark same target", Helpers.MarkerChoices(blocked), step.raidMarker or -1,
            16, y, width - 32, function(value)
                if Helpers.MarkerBlocked(step) and value ~= -1 then Page.Error("Markers need a unit target") return end
                step.raidMarker = value ~= -1 and value or nil
                Page.Changed(false)
            end)
        control.markerBlocked = blocked
        return y - 61
    end
end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr, Model = P.MacroPage, P.MacroPage.helpers, P.Tr, P.Suite.Macros.Model
    Helpers.Sequence = function(ui, step, index, y, width)
        for i = 1, #step.sequence do y = Helpers.SequenceItem(ui, step, index, i, y, width) end
        local key = "step:" .. index
        Page.Button(ui, key .. ":add-sequence", "Add step", 16, y, 120, function()
            step.sequence[#step.sequence + 1] = ""
            Page.Changed(true)
        end, #step.sequence < Model.MAX_SEQUENCE)
        y = y - 42
        if step.command == "castsequence" then y = Helpers.SequenceReset(ui, step, key, y, width) end
        return Helpers.Conditions(ui, key .. ":condition", step.branches[1], y, width)
    end

    Helpers.Translated = function(values)
        local result = {}
        for _, row in ipairs(values) do result[#result + 1] = { value = row.value, text = Tr(row.text) } end
        return result
    end
end
