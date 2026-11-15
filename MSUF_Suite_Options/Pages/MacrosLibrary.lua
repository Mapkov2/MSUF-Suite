local _, P = ...
local Page = P.MacroPage

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr, Store = P.MacroPage, P.MacroPage.helpers, P.Tr, P.Suite.Macros.Store
    Helpers.Matches = function(name)
        local query = (Page.libraryQuery or ""):lower()
        return query == "" or tostring(name or ""):lower():find(query, 1, true)
    end

    Helpers.HideRows = function(ui)
        for kind, pool in pairs(ui.pools) do
            for key, control in pairs(pool) do
                if key:sub(1, 8) == "library:" then
                    control:Hide()
                    local title = kind == "select" and P.HM.GetControlTitle(control)
                    if title then title:Hide() end
                end
            end
        end
    end

    Helpers.Draft = function(ui, entry, index, y, width)
        local key = "library:draft:" .. index
        local narrow = width < 520
        Page.Label(ui, key .. ":name", entry.name ~= "" and entry.name or Tr("Untitled macro"),
            16, y - 5, narrow and width - 32 or width - 272)
        local actionsX, actionsY = narrow and 16 or width - 251, narrow and y - 30 or y
        Page.Button(ui, key .. ":edit", "Edit", actionsX, actionsY, 74, function() Page.Load(entry.id) end)
        Page.Button(ui, key .. ":pickup", "Pick up", actionsX + 80, actionsY, 80, function()
            local ok, errorKey = Store.Pickup(entry.id)
            if not ok then Page.Error(errorKey) end
        end)
        Page.Button(ui, key .. ":delete", "Delete", actionsX + 166, actionsY, 78, function()
            local prompt = entry.published and "Delete this saved draft and remove its macro bindings?" or "Delete this saved draft?"
            Page.Confirm("macro-draft-delete", Tr(prompt), function()
                local ok, errorKey = Store.Delete(entry.id)
                if not ok then Page.Error(errorKey) return end
                if Page.id == entry.id then Page.id, Page.bound = nil, false end
                Page.LibraryRefresh()
            end)
        end)
        return y - (narrow and 69 or 41)
    end

    Helpers.Native = function(ui, entry, index, y, width)
        local key = "library:native:" .. index
        local narrow = width < 530
        Page.Label(ui, key .. ":name", entry.name, 16, y - 4, narrow and width - 32 or width - 270)
        local actionsX, actionsY = narrow and 16 or width - 251, narrow and y - 29 or y
        Page.Button(ui, key .. ":import", "Edit", actionsX, actionsY, 74, function()
            local id, errorKey = Store.Import(entry.index)
            if id then Page.Load(id) else Page.Error(errorKey) end
        end)
        Page.Button(ui, key .. ":pickup", "Pick up", actionsX + 80, actionsY, 80, function()
            local native = P.Suite.Macros.Native
            local binding = { index = entry.index, name = entry.name, body = entry.body, icon = entry.icon,
                scope = entry.scope, character = entry.scope == "character" and native.Character() or nil }
            local ok, errorKey = native.Pickup(binding)
            if not ok then Page.Error(errorKey) end
        end)
        Page.Button(ui, key .. ":delete", "Delete", actionsX + 166, actionsY, 78, function()
            Page.Confirm("macro-native-delete", Tr("Delete this WoW macro and remove its bindings?"), function()
                local ok, errorKey = Store.DeleteNative(entry)
                if not ok then Page.Error(errorKey) return end
                if Page.bound and Page.document.name == entry.name and Page.document.scope == entry.scope then
                    Page.bound, Page.pickupReady, Page.publishedStamp = false, false, nil
                end
                Page.LibraryRefresh()
            end)
        end)
        return y - (narrow and 67 or 40)
    end

end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, Tr, Store = P.MacroPage, P.MacroPage.helpers, P.Tr, P.Suite.Macros.Store
    function Page.LibraryRefresh()
        local ui = Page.ui
        if not ui or Page.tab ~= "library" or P.Combat() then return end
        Helpers.HideRows(ui)
        local y, count = ui.libraryY, 0
        local width = ui.width
        Page.Label(ui, "library:drafts:title", Tr("Saved drafts"), 16, y, width - 32)
        y = y - 29
        for index, entry in ipairs(Store.List()) do
            if Helpers.Matches(entry.name) then
                y = Helpers.Draft(ui, entry, index, y, width)
                count = count + 1
            end
        end
        if count == 0 then
            Page.Label(ui, "library:drafts:empty", Tr("No matching drafts"), 16, y, width - 32, P.T.colors.muted)
            y = y - 35
        end
        y = y - 12
        Page.Label(ui, "library:native:title", Tr("WoW macros"), 16, y, width - 32)
        y = y - 30
        for index, entry in ipairs(Store.Native()) do
            if Helpers.Matches(entry.name) then y = Helpers.Native(ui, entry, index, y, width) end
        end
        if Page.message then
            Page.Label(ui, "library:status", Page.message, 16, y, width - 32, P.T.colors.muted)
            y = y - 34
        end
        Page.Finish(ui, y - 12)
    end

    function Page.RenderLibrary(ui, y, width)
        Page.Edit(ui, "library-search", "Search", Page.libraryQuery or "", 16, y, width - 32, function(value)
            Page.libraryQuery = value
            Page.LibraryRefresh()
        end)
        ui.libraryY = y - 69
        Page.LibraryRefresh()
    end

end
