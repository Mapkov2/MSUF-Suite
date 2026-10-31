local _, P = ...
local Page = P.MacroPage
local PAGE_SIZE = 10


Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, T, Tr, NS = P.MacroPage, P.MacroPage.helpers, P.T, P.Tr, P.Suite
    local Public = NS.Public
    Helpers.Add = function(list, seen, name, value, icon)
        if not Public(name) or type(name) ~= "string" or name == "" or seen[value] then return end
        seen[value] = true
        list[#list + 1] = { name = name, value = value, icon = Public(icon) and icon or 134400 }
    end

    Helpers.Spell = function(list, seen, index, bank, ids)
        local info = C_SpellBook.GetSpellBookItemInfo(index, bank)
        if not Public(info) or type(info) ~= "table" then return end
        local id = info.spellID
        if not Public(id) or type(id) ~= "number" then return end
        local passive = C_SpellBook.IsSpellBookItemPassive(index, bank)
        if not Public(passive) or passive then return end
        local data = C_Spell.GetSpellInfo(id)
        if not Public(data) or type(data) ~= "table" or not Public(data.name) or type(data.name) ~= "string" then return end
        Helpers.Add(list, seen, data.name, ids and id or data.name, data.iconID)
        if NS.Client.isForever and not ids then
            local subtext = C_Spell.GetSpellSubtext(id)
            if Public(subtext) and type(subtext) == "string" and subtext ~= "" then
                Helpers.Add(list, seen, data.name .. " (" .. subtext .. ")", data.name .. "(" .. subtext .. ")", data.iconID)
            end
        end
    end

    Helpers.Spells = function(list, seen, pet, ids)
        if pet then
            local count = C_SpellBook.HasPetSpells()
            if Public(count) and type(count) == "number" then
                for index = 1, math.min(count, 1000) do Helpers.Spell(list, seen, index, Enum.SpellBookSpellBank.Pet, ids) end
            end
            return
        end
        local bank = Enum.SpellBookSpellBank.Player
        for skill = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(skill)
            if Public(line) and type(line) == "table" then
                local offset, count = line.itemIndexOffset, line.numSpellBookItems
                if Public(offset) and Public(count) and type(offset) == "number" and type(count) == "number" then
                    for index = offset + 1, math.min(offset + count, offset + 1000) do
                        Helpers.Spell(list, seen, index, bank, ids)
                    end
                end
            end
        end
    end

end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, T, Tr, NS = P.MacroPage, P.MacroPage.helpers, P.T, P.Tr, P.Suite
    local Public = NS.Public
    Helpers.Items = function(list, seen, ids)
        for bag = 0, 5 do
            local count = C_Container.GetContainerNumSlots(bag)
            if Public(count) and type(count) == "number" then
                for slot = 1, count do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if Public(info) and type(info) == "table" then
                        local id = info.itemID
                        if Public(id) and type(id) == "number" then
                            local name = C_Item.GetItemNameByID(id)
                            Helpers.Add(list, seen, name, ids and id or "item:" .. id, info.iconFileID)
                        end
                    end
                end
            end
        end
    end

    Helpers.Filter = function(frame)
        local query = frame.search:GetText():lower()
        local filtered = {}
        for _, item in ipairs(frame.items) do
            if item.name:lower():find(query, 1, true) then filtered[#filtered + 1] = item end
        end
        frame.filtered = filtered
        local maxPage = math.max(1, math.ceil(#filtered / PAGE_SIZE))
        frame.page = math.min(frame.page, maxPage)
        for i, button in ipairs(frame.rows) do
            local item = filtered[(frame.page - 1) * PAGE_SIZE + i]
            button.item = item
            button:SetShown(item ~= nil)
            if item then
                button:SetText(item.name)
                button.icon:SetTexture(item.icon)
            end
        end
        frame.previous:SetEnabled(frame.page > 1)
        frame.next:SetEnabled(frame.page < maxPage)
        frame.count:SetFormattedText(Tr("Page %d / %d"), frame.page, maxPage)
    end

    Helpers.Action = function(frame, text, x, y, width, fn)
        local button = T.Button(frame, text, width, 26, { history = false, noSearch = true })
        button:SetPoint("TOPLEFT", x, y)
        button:SetScript("OnClick", function() if frame:IsShown() and not P.Combat() then fn() end end)
        return button
    end

end

Page.initializers[#Page.initializers + 1] = function()
    local Page, Helpers, T, Tr, NS = P.MacroPage, P.MacroPage.helpers, P.T, P.Tr, P.Suite
    local Public = NS.Public
    Helpers.Picker = function()
        if Page.picker then return Page.picker end
        local frame = P.MenuPopupPanel(360, 415)
        Page.picker = frame
        frame.rows = {}
        frame.title = P.Text(frame, "Choose a spell or item", 14, -13, 295, T.colors.text)
        Helpers.Action(frame, "Close", 290, -10, 58, function() frame:Hide() end)
        frame.search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        frame.search:SetPoint("TOPLEFT", 18, -43)
        frame.search:SetSize(324, 25)
        frame.search:SetAutoFocus(false)
        frame.search:SetMaxLetters(80)
        frame.search:SetFontObject("GameFontHighlightSmall")
        T.SkinEditBox(frame.search)
        frame.search:SetScript("OnTextChanged", function() frame.page = 1 Helpers.Filter(frame) end)
        frame.search:SetScript("OnEscapePressed", function() frame:Hide() end)
        for i = 1, PAGE_SIZE do
            local button = Helpers.Action(frame, "", 14, -77 - (i - 1) * 28, 330, function()
                local selected = frame.rows[i].item
                if selected and frame.pick then
                    frame.pick(selected.value, selected.icon)
                    frame:Hide()
                end
            end)
            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetSize(20, 20)
            button.icon:SetPoint("RIGHT", -6, 0)
            frame.rows[i] = button
        end
        frame.previous = Helpers.Action(frame, "Previous", 14, -369, 86, function() frame.page = frame.page - 1 Helpers.Filter(frame) end)
        frame.next = Helpers.Action(frame, "Next", 260, -369, 84, function() frame.page = frame.page + 1 Helpers.Filter(frame) end)
        frame.count = P.Text(frame, "", 112, -375, 136, T.colors.muted)
        frame:Hide()
        return frame
    end

    function Page.Pick(anchor, kind, callback)
        if P.Combat() then return end
        local frame = Helpers.Picker()
        frame:Hide()
        local ui, document = Page.ui, Page.document
        frame.anchor, frame.page = anchor, 1
        frame.pick = function(...)
            if Page.Active(ui) and Page.document == document then callback(...) end
        end
        frame.items = {}
        local seen = {}
        if kind == "spell" or kind == "spellID" or kind == "any" then Helpers.Spells(frame.items, seen, false, kind == "spellID") end
        if kind == "pet" or kind == "any" then Helpers.Spells(frame.items, seen, true) end
        if kind == "item" or kind == "itemID" or kind == "any" then Helpers.Items(frame.items, seen, kind == "itemID") end
        table.sort(frame.items, function(a, b) return a.name < b.name end)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        frame.search:SetText("")
        frame:Show()
        Helpers.Filter(frame)
        frame.search:SetFocus()
    end

end
