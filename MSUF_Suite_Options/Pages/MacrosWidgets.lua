local _, P = ...
local Page = {}
P.MacroPage = Page
Page.helpers = {}
-- Widget and editor closures are created only when the macro section opens.
Page.initializers = {}
Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, T, HM, Tr = P.MacroPage, P.MacroPage.helpers, P.T, P.HM, P.Tr
    function Page.Active(ui)
        return ui ~= nil and Page.ui == ui and ui.body:IsVisible() and not P.Combat()
    end

    function Page.Confirm(key, text, callback)
        local ui, document = Page.ui, Page.document
        P.Confirm(key, text, function()
            if Page.Active(ui) and Page.document == document then callback() end
        end)
    end

    function Page.Meta(key)
        if key == "consumable:enabled" then
            return P.Meta("suite_macros", "macroBuilder", "enabled", "setting")
        end
        return P.Meta("suite_macros", "macroBuilder", key, "ephemeral")
    end

    Helpers.Remember = function(ui, kind, key, create)
        local pool = ui.pools[kind]
        if not pool then
            pool = {}
            ui.pools[kind] = pool
        end
        local control = pool[key]
        if not control then
            control = create()
            pool[key] = control
            if kind ~= "label" then HM.SkipHistoryCheckpoint(control) end
        end
        control:Show()
        return control
    end

    function Page.Begin(ui)
        for kind, pool in pairs(ui.pools) do
            for _, control in pairs(pool) do
                if kind == "edit" then control:ClearFocus() end
                control:Hide()
                local title = kind == "select" and HM.GetControlTitle(control)
                if title then title:Hide() end
                local label = kind == "toggle" and HM.GetControlLabel(control)
                if label then label:Hide() end
            end
        end
    end

    function Page.Label(ui, key, text, x, y, width, color)
        local label = Helpers.Remember(ui, "label", key, function()
            return P.Text(ui.body, "", 0, 0, width, color or T.colors.text)
        end)
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", x + (ui.offsetX or 0), y)
        label:SetWidth(width)
        label:SetText(text)
        label:SetTextColor(unpack(color or T.colors.text))
        return label
    end

end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, T, HM, Tr = P.MacroPage, P.MacroPage.helpers, P.T, P.HM, P.Tr
    function Page.Button(ui, key, text, x, y, width, callback, enabled)
        local button = Helpers.Remember(ui, "button", key, function()
            local result = T.Button(ui.body, text, width, 26, { history = false, noSearch = true })
            result:SetScript("OnClick", function(self)
                if Page.Active(ui) and self.action then self.action() end
            end)
            P.M.RegisterControlMetadata(result, Page.Meta(key), text, "button")
            return result
        end)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", x + (ui.offsetX or 0), y)
        button:SetWidth(width)
        button:SetText(Tr(text))
        button:SetEnabled(enabled ~= false and not P.Combat())
        button.action = callback
        return button
    end

    function Page.Select(ui, key, label, values, value, x, y, width, callback)
        local control = Helpers.Remember(ui, "select", key, function()
            local result = P.W.Dropdown(ui.body, label, values, width)
            result:SetOnValueChanged(function(selected)
                if Page.Active(ui) and result.action then result.action(selected) end
            end)
            P.M.RegisterControlMetadata(result, Page.Meta(key), label, "dropdown")
            return result
        end)
        local title = HM.GetControlTitle(control)
        if title then
            title:ClearAllPoints()
            title:SetPoint("TOPLEFT", ui.body, "TOPLEFT", x + (ui.offsetX or 0), y)
            title:SetText(Tr(label))
            title:Show()
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", ui.body, "TOPLEFT", x + (ui.offsetX or 0), y - 23)
        control:SetWidth(width)
        control:SetValues(values)
        control:SetValue(value)
        control.action = callback
        return control
    end

end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, T, HM, Tr = P.MacroPage, P.MacroPage.helpers, P.T, P.HM, P.Tr
    function Page.Edit(ui, key, label, value, x, y, width, callback, multiline)
        if label ~= "" then Page.Label(ui, key .. ":label", Tr(label), x, y, width, T.colors.muted) end
        local edit = Helpers.Remember(ui, "edit", key, function()
            local result = CreateFrame("EditBox", nil, ui.body, "InputBoxTemplate")
            result:SetAutoFocus(false)
            result:SetMultiLine(multiline == true)
            result:SetMaxLetters(multiline and 4096 or 255)
            result:SetFontObject("GameFontHighlightSmall")
            result:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            result:SetScript("OnEnterPressed", function(self) if not multiline then self:ClearFocus() end end)
            result:SetScript("OnTextChanged", function(self, userInput)
                if userInput and Page.Active(ui) and self.action then self.action(self:GetText()) end
            end)
            result:SetScript("OnHide", function(self) self:ClearFocus() end)
            T.SkinEditBox(result)
            P.M.RegisterControlMetadata(result, Page.Meta(key), label, "textinput")
            return result
        end)
        edit:ClearAllPoints()
        edit:SetPoint("TOPLEFT", x + 4 + (ui.offsetX or 0), y - (label == "" and 0 or 23))
        edit:SetSize(width - 8, multiline and 150 or 25)
        edit.action = callback
        edit:SetText(value or "")
        return edit
    end

    function Page.Toggle(ui, key, label, value, x, y, width, callback)
        local button = Helpers.Remember(ui, "toggle", key, function()
            local control = P.W.ToggleAt(ui.body, label, x, y, width - 42)
            control:SetScript("OnClick", function(self)
                if not Page.Active(ui) then return end
                self.macroValue = not self.macroValue
                if self.action then self.action(self.macroValue) end
                self:SetChecked(self.macroValue)
            end)
            return control
        end)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", ui.body, "TOPLEFT", x + (ui.offsetX or 0), y)
        button:SetChecked(value == true)
        button.macroValue, button.action = value == true, callback
        button:SetEnabled(not P.Combat())
        local caption = HM.GetControlLabel(button)
        if caption then caption:SetText(Tr(label)) caption:SetWidth(math.max(30, width - 42)) caption:Show() end
        P.M.RegisterControlMetadata(button, Page.Meta(key), label, "toggle")
        return button
    end

    function Page.Changed(rebuild)
        Page.dirty = true
        Page.message = nil
        if rebuild then Page.Render() else Page.Preview() end
    end

    function Page.Move(list, index, delta)
        local target = index + delta
        if target < 1 or target > #list then return end
        list[index], list[target] = list[target], list[index]
        Page.Changed(true)
    end

    function Page.Error(message)
        Page.message = message and Tr(message) or nil
        if Page.tab == "library" then Page.LibraryRefresh() else Page.Preview() end
    end

end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, T, HM, Tr = P.MacroPage, P.MacroPage.helpers, P.T, P.HM, P.Tr
    function Page.Values(source)
        local values = {}
        for _, entry in ipairs(source) do values[#values + 1] = { value = entry.key, text = Tr(entry.label) } end
        return values
    end

    function Page.Card(ui, key, x, y, width, height)
        local frame = Helpers.Remember(ui, "card", key, function()
            return T.Panel(ui.body)
        end)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", ui.body, "TOPLEFT", x + (ui.offsetX or 0), y)
        frame:SetSize(width, math.max(40, height))
        frame:SetFrameLevel(ui.body:GetFrameLevel())
    end

    function Page.MacroIcon(ui, x, y)
        local button = Helpers.Remember(ui, "icon", "published", function()
            local control = T.Button(ui.body, "", 48, 48, { history = false, noSearch = true })
            control.texture = control:CreateTexture(nil, "ARTWORK")
            control.texture:SetAllPoints()
            control:RegisterForDrag("LeftButton")
            local function Pick()
                if Page.Active(ui) then Page.DragMacro() end
            end
            control:SetScript("OnClick", Pick)
            control:SetScript("OnDragStart", Pick)
            P.M.AddTooltip(control, function() return Page.document.name end, function()
                return Tr(Page.pickupReady and "Drag to an action bar" or "Save before dragging")
            end, { hook = true })
            return control
        end)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", x + (ui.offsetX or 0), y)
        button.texture:SetTexture(Page.document.icon)
        return button
    end

    function Page.Close()
        local ui = Page.ui
        if not ui then return end
        ui.body:UnregisterAllEvents()
        for _, edit in pairs(ui.pools.edit or {}) do edit:ClearFocus() end
        if Page.picker then Page.picker:Hide() end
    end

end
