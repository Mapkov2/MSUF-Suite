local _, P = ...
local Page = P.MacroPage

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr, T, Macros = P.MacroPage, P.MacroPage.helpers, P.Tr, P.T, P.Suite.Macros
    local Model, Store = Macros.Model, Macros.Store
    Helpers.Preview = function(ui, y)
        local width = ui.panelWidth or ui.width
        Page.Label(ui, "result-title", Tr("Result"), 16, y, width - 32)
        ui.icon = Page.MacroIcon(ui, 16, y - 30)
        ui.counter = Page.Label(ui, "result-count", "", 78, y - 32, width - 94, T.colors.muted)
        ui.dragLabel = Page.Label(ui, "result-drag", "", 78, y - 55, width - 94, T.colors.muted)
        ui.preview = Page.Label(ui, "result-code", "", 16, y - 90, width - 32, T.colors.text)
        ui.preview:SetHeight(110)
        ui.preview:SetJustifyV("TOP")
        ui.status = Page.Label(ui, "result-status", "", 16, y - 206, width - 32, T.colors.muted)
        local column = math.floor((width - 42) / 2)
        ui.publish = Page.Button(ui, "publish", Page.bound and "Update WoW macro" or "Create WoW macro",
            16, y - 240, column, function()
                if Page.bound then Page.Confirm("macro-publish", Tr("Replace the linked WoW macro?"), function() Helpers.Publish(true) end)
                else Helpers.Publish(false) end
            end)
        T.SkinPrimaryButton(ui.publish)
        Page.Button(ui, "save-draft", "Save draft", 26 + column, y - 240, column, function()
            if Helpers.Saved() then Page.message = "Draft saved" Page.Preview() end
        end)
        local pickup = Page.Button(ui, "pickup", "Pick up macro", 16, y - 278, column, Page.DragMacro, Page.pickupReady)
        ui.pickup = pickup
        pickup:RegisterForDrag("LeftButton")
        pickup:SetScript("OnDragStart", function() if Page.Active(ui) then Page.DragMacro() end end)
        local iconButton
        iconButton = Page.Button(ui, "icon", "Choose icon", 26 + column, y - 278, column, function()
            Page.Pick(iconButton, "any", function(_, icon)
                Page.document.icon = icon or 134400
                Page.Changed(false)
            end)
        end)
        Page.Toggle(ui, "showtooltip", "Show tooltip", Page.document.showTooltip, 16, y - 316, column,
            function(value) Page.document.showTooltip = value Page.Changed(false) end)
        if Page.bound then
            Page.Button(ui, "create-copy", "Create another macro", 26 + column, y - 316, column,
                function() Helpers.Publish(false) end)
        end
        Page.Card(ui, "result", 8, y + 10, width - 16, 366)
        Page.Preview()
        return y - 363
    end

    function Page.Preview()
        local ui = Page.ui
        if not ui or not ui.preview or P.Combat() then return end
        Page.RefreshMarkers(ui)
        local body, errorKey, warnings, draftBody = Helpers.Body()
        Page.compiled = body
        local shown = body or draftBody or Page.document.mode == "raw" and Page.document.raw or ""
        ui.preview:SetText(shown)
        local length = Model.Count(shown) or 0
        ui.counter:SetText(string.format(Tr("%d / 255 characters"), length))
        local message = Page.message or errorKey
        if not message and warnings and warnings.multipleActions then message = "Each action follows WoW's cooldown rules" end
        if not message and warnings and warnings.chat then message = "Chat may be restricted during encounters" end
        if not message and Page.document.mode == "consumable" then message = "Prepared outside combat" end
        ui.status:SetText(message and Tr(message) or Tr("Ready"))
        ui.publish:SetEnabled(body ~= nil and Page.document.name ~= "" and not P.Combat())
        Page.pickupReady = body ~= nil and Page.bound and not Page.dirty
            and Page.publishedStamp == Helpers.Stamp(Page.document, body)
        if ui.icon then
            ui.icon.texture:SetTexture(Page.document.icon)
            ui.icon:SetAlpha(Page.pickupReady and 1 or 0.45)
        end
        if ui.dragLabel then ui.dragLabel:SetText(Tr(Page.pickupReady and "Drag to an action bar" or "Save before dragging")) end
        if ui.pickup then ui.pickup:SetEnabled(Page.pickupReady and not P.Combat()) end
    end
end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr, T, Macros = P.MacroPage, P.MacroPage.helpers, P.Tr, P.T, P.Suite.Macros
    local Model, Store = Macros.Model, Macros.Store
    Helpers.BuildContent = function(ctx, builder, body)
        if not Helpers.Ready() then return end
        Page.Close()
        Page.document = Page.document or Model.New("spell")
        Page.tab = Page.tab or "rules"
        Page.ui = { ctx = ctx, builder = builder, body = body, pools = {},
            width = math.max(280, body:GetWidth() or P.HM.GetSectionWidth(body) or builder.width or ctx.width or 720) }
        body:SetScript("OnEvent", Helpers.Events)
        body:SetScript("OnSizeChanged", function(self, width)
            local ui = Page.ui
            if ui and ui.body == self and self:IsVisible() and not P.Combat()
                and type(width) == "number" and width > 0 and math.abs(ui.width - width) >= 1 then
                ui.width = width
                Page.Render()
            end
        end)
        body:HookScript("OnShow", function(self)
            if P.Combat() or not Page.ui or Page.ui.body ~= self then return end
            self:RegisterEvent("PLAYER_REGEN_DISABLED")
            self:RegisterEvent("UPDATE_MACROS")
            if Page.requestedTab then
                local requested = Page.requestedTab
                Page.requestedTab = nil
                Helpers.ChooseTab(requested)
            end
        end)
        body:HookScript("OnHide", function(self)
            if Page.ui and Page.ui.body == self then Page.Close() end
        end)
        body:RegisterEvent("PLAYER_REGEN_DISABLED")
        body:RegisterEvent("UPDATE_MACROS")
        local ui = Page.ui
        P.M.TrackRefresh(ctx, function()
            if Page.ui == ui and not P.Combat() then ui.body:Show() end
        end)
        local requested = Page.requestedTab
        Page.requestedTab = nil
        if requested then Helpers.ChooseTab(requested) else Page.Render() end
    end

    Helpers.ChooseTab = function(tab)
        local function Apply()
            if tab == "raw" and Page.document.mode ~= "raw" and not Page.codeEdited then
                local body, _, _, draftBody = Helpers.Body()
                Page.document.raw = body or draftBody or Page.document.raw
            end
            if tab == "consumable" and not Page.document.consumable then
                Page.document.consumable = Model.New("health").consumable
            end
            if tab ~= "library" and Page.document.mode ~= tab then
                Page.document.mode, Page.dirty = tab, true
            end
            Page.tab, Page.message = tab, nil
            Page.Render()
        end
        if tab == "rules" and Page.document.mode == "raw" then
            Page.Confirm("macro-builder", Tr("Return to the saved builder rules? Custom code stays in the Code tab."), Apply)
        else
            Apply()
        end
    end
end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr, T, Macros = P.MacroPage, P.MacroPage.helpers, P.Tr, P.T, P.Suite.Macros
    local Model, Store = Macros.Model, Macros.Store
    Helpers.Header = function(ui)
        Helpers.EditorChoices()
        local width = ui.width
        local columns = width < 520 and 2 or 4
        local tabWidth = math.floor((width - 32 - (columns - 1) * 5) / columns)
        for i, tab in ipairs(Page.tabs) do
            local x, row = 16 + ((i - 1) % columns) * (tabWidth + 5), math.floor((i - 1) / columns)
            local button = Page.Button(ui, "tab:" .. tab[1], tab[2], x, -16 - row * 34, tabWidth,
                function() Helpers.ChooseTab(tab[1]) end)
            button:SetActive(Page.tab == tab[1])
        end
        local y = -20 - math.ceil(#Page.tabs / columns) * 34
        Page.Label(ui, "quick:title", Tr("Quick start"), 16, y, width - 32, T.colors.muted)
        y = y - 23
        columns = math.max(2, math.min(#Page.quick, math.floor((width - 32) / 108)))
        local quickWidth = math.floor((width - 32 - (columns - 1) * 5) / columns)
        for i, entry in ipairs(Page.quick) do
            local x, row = 16 + ((i - 1) % columns) * (quickWidth + 5), math.floor((i - 1) / columns)
            local button = Page.Button(ui, "quick:" .. entry[1], entry[2], x, y - row * 32, quickWidth,
                function() Helpers.New(entry[1]) end)
            button:SetActive(Page.template == entry[1])
        end
        y = y - math.ceil(#Page.quick / columns) * 32 - 10
        local column = math.floor((width - 42) / 2)
        local templates = { { value = "", text = Tr("Choose a template") } }
        for _, entry in ipairs(Macros.Templates) do templates[#templates + 1] = { value = entry.id, text = Tr(entry.label) } end
        Page.Select(ui, "template", "More templates", templates, Page.template or "", 16, y, column,
            function(id) if id ~= "" then Helpers.New(id) end end)
        Page.Button(ui, "new", "New macro", 26 + column, y - 23, column, function() Helpers.New("spell") end)
        y = y - 61
        Page.Edit(ui, "name", "Name", Page.document.name, 16, y, column, function(value)
            Page.document.name, Page.message = value, nil
            Page.Changed(false)
        end):SetMaxLetters(16)
        Page.Select(ui, "scope", "Save for", Page.scopes, Page.document.scope, 26 + column, y, column,
            function(value) Page.document.scope = value Page.Changed(false) end)
        return y - 70
    end

    function Page.Load(id)
        local function Apply()
            local document = Store.Get(id)
            if not document then return end
            Page.document, Page.id, Page.template = document, id, nil
            Page.codeEdited = document.raw ~= ""
            Page.bound, Page.dirty, Page.message = document.published == true, false, nil
            Helpers.BindPublished(document)
            Page.tab = document.mode == "consumable" and "consumable" or document.mode == "raw" and "raw" or "rules"
            Page.Render()
        end
        if Page.dirty then Page.Confirm("macro-open", Tr("Discard unsaved changes?"), Apply) else Apply() end
    end

    Helpers.New = function(templateID)
        local function Apply()
            Page.document = Model.New(templateID)
            Page.codeEdited = false
            Page.id, Page.bound, Page.dirty, Page.message = nil, false, false, nil
            Page.publishedStamp = nil
            Page.template = templateID
            Page.tab = Page.document.mode == "consumable" and "consumable" or "rules"
            Page.Render()
        end
        if Page.dirty then Page.Confirm("macro-new", Tr("Discard unsaved changes?"), Apply) else Apply() end
    end
end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr, T, Macros = P.MacroPage, P.MacroPage.helpers, P.Tr, P.T, P.Suite.Macros
    local Model, Store = Macros.Model, Macros.Store
    function Page.Render()
        local ui = Page.ui
        if not ui or P.Combat() then return end
        Page.Begin(ui)
        ui.offsetX, ui.panelWidth = 0, nil
        local y = Helpers.Header(ui)
        if Page.tab == "library" then
            ui.preview = nil
            Page.RenderLibrary(ui, y, ui.width)
            return
        end
        local top = y
        local editorWidth = ui.width >= 980 and math.floor((ui.width - 24) * 0.60) or ui.width
        if Page.tab == "rules" then
            y = Page.RenderRules(ui, y, editorWidth)
        elseif Page.tab == "consumable" then
            y = Page.RenderConsumables(ui, y, editorWidth)
        else
            Page.Edit(ui, "raw-code", "Macro code", Page.document.raw, 16, y, editorWidth - 32, function(value)
                Page.document.raw, Page.message = value, nil
                Page.codeEdited = true
                Page.Changed(false)
            end, true)
            y = y - 196
        end
        if editorWidth ~= ui.width then
            ui.offsetX = editorWidth + 24
            ui.panelWidth = ui.width - ui.offsetX
            y = math.min(y, Helpers.Preview(ui, top))
        else
            y = Helpers.Preview(ui, y - 14)
        end
        ui.offsetX, ui.panelWidth = 0, nil
        Page.Finish(ui, y)
    end

    Helpers.Publish = function(replace)
        local id = Helpers.Saved()
        if not id then return end
        local ok, errorKey, index = Store.Publish(id, replace)
        if not ok then Page.Error(errorKey) return end
        Page.bound, Page.message = true, "Macro saved to WoW"
        Helpers.BindPublished(Page.document)
        Page.Render()
    end

    Helpers.BindPublished = function(document)
        Page.publishedStamp = nil
        local body = Store.Preview(document)
        if not body then return end
        for _, native in ipairs(Store.Native()) do
            if native.name == document.name and native.scope == document.scope and native.icon == document.icon
                and native.body == body then Page.publishedStamp = Helpers.Stamp(document, body) break end
        end
    end

    Helpers.Events = function(frame, event)
        if not Page.ui or Page.ui.body ~= frame then return end
        if event == "PLAYER_REGEN_DISABLED" then
            Page.Close()
            frame:Hide()
        elseif event == "UPDATE_MACROS" and Page.tab == "library" then
            Page.LibraryRefresh()
        end
    end
end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr, T, Macros = P.MacroPage, P.MacroPage.helpers, P.Tr, P.T, P.Suite.Macros
    local Model, Store = Macros.Model, Macros.Store
    Page.quick = { { "mouseover", "Mouseover healing" }, { "mouseover-harm", "Mouseover attack" },
        { "focus", "Focus" }, { "self", "Self" },
        { "sequence", "Sequence" }, { "health", "Consumables" } }
    Page.scopes = { { value = "character", text = Tr("This character") }, { value = "account", text = Tr("All characters") } }

    function Page.Finish(ui, y)
        local height = math.max(320, -y + 16)
        ui.body:SetHeight(height)
        P.HM.SetSectionCursor(ui.body, -height + 16)
        ui.builder:FinishSection(ui.body, 16)
    end

    Helpers.Saved = function()
        local id, errorKey = Store.Save(Page.document, Page.id)
        if not id then Page.Error(errorKey) return nil end
        Page.id, Page.dirty = id, false
        return id
    end

    function Page.DragMacro()
        if not Page.Active(Page.ui) then return end
        if not Page.pickupReady then Page.Error("Save before dragging") return end
        local ok, errorKey = Store.Pickup(Page.id)
        if not ok then Page.Error(errorKey) end
    end

    Helpers.Ready = function()
        if P.Combat() then return false end
        if not P.Suite.Client.IsAddOnLoaded("MSUF_Suite_QualityOfLife") then C_AddOns.LoadAddOn("MSUF_Suite_QualityOfLife") end
        return true
    end

    Helpers.Body = function()
        return Store.Preview(Page.document)
    end

    Helpers.Stamp = function(document, body)
        if not body then return nil end
        return document.name .. "\0" .. document.scope .. "\0" .. tostring(document.icon) .. "\0" .. body
    end
end

Page.helpers.EditorChoices = function()
    if Page.tabs then return end
    Page.tabs = { { "rules", "Builder" }, { "consumable", "Consumables" }, { "library", "My macros" }, { "raw", "Code" } }

end

local function Search(ctx)
    Page.helpers.EditorChoices()
    for _, tab in ipairs(Page.tabs) do
        ctx.searchRows[#ctx.searchRows + 1] = { pageKey = "suite_macros",
            label = P.Tr(tab[2]), kind = "section", section = P.Tr("Macro workshop"),
            prepareKind = "suiteMacroTab", prepareValue = tab[1], keywords = { "macro", "macros", "sequence", "consumable", P.Tr(tab[2]) } }
    end
end

function Page.PrepareSearch(tab)
    if tab ~= "rules" and tab ~= "consumable" and tab ~= "library" and tab ~= "raw" then return end
    Page.requestedTab = tab
    if Page.initialized and Page.Active(Page.ui) then
        Page.requestedTab = nil
        Page.helpers.ChooseTab(tab)
    end
end

local function Build(ctx)
    if ctx.searchRows then Search(ctx) return end
    if P.Combat() then return end
    if not Page.initialized then
        for _, initialize in ipairs(Page.initializers) do initialize() end
        Page.initializers, Page.initialized = nil, true
    end
    local builder = P.W.PageBuilder(ctx)
    local body = builder:Section(P.Tr("Macro workshop"), 650)
    if body.title then body.title:Hide() end
    Page.helpers.BuildContent(ctx, builder, body)
end

P.RegisterPage({ key = "suite_macros", label = "Macros", title = "Macro workshop", build = Build,
    icon = { 7, 1 }, nav = "general", navOrder = 2, aliases = { "macro", "macros", "sequence", "consumables", "makros" } })
