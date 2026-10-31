local _, P = ...
local NS, Tr = P.Suite, P.Tr
local function IDs(text, limit)
    limit = limit or 32
    local ids, seen = {}, {}
    for token in (text or ""):sub(1, 400):gmatch("%d+") do
        local id = tonumber(token)
        if id > 0 and id < 2147483647 and not seen[id] and #ids < limit then
            ids[#ids + 1], seen[id] = id, true
        end
    end
    return ids, seen
end
local function Session(id, key)
    local current, baseline = P.ProfileGuard(), P.Get(id, key)
    local function Valid() return current() and not P.Combat() and P.Get(id, key) == baseline end
    local function Save(value)
        if Valid() and P.Set(id, key, value) then baseline = P.Get(id, key) end
    end
    return Valid, Save, function() return baseline end
end
local function Rod(class, subclass)
    return NS.Finite(class) and NS.Finite(subclass) and class == Enum.ItemClass.Weapon
        and subclass == Enum.ItemWeaponSubclass.Fishingpole
end
local function ItemRows(kind)
    local rows, seen = {}, {}
    for bag = 0, NUM_BAG_SLOTS do
        local count = C_Container.GetContainerNumSlots(bag)
        if NS.Finite(count) then
            for slot = 1, math.min(count, 100) do
                local item = C_Container.GetContainerItemID(bag, slot)
                if NS.Finite(item) and not seen[item] and #rows < 200 then
                    seen[item] = true
                    local name, _, _, _, _, _, _, _, _, icon, _, class, subclass = C_Item.GetItemInfo(item)
                    local rod = Rod(class, subclass)
                    local consumable = NS.Finite(class) and class == Enum.ItemClass.Consumable
                    if NS.PublicText(name) and (kind == "rod" and rod or kind == "lure" and consumable or kind == "supplies") then
                        rows[#rows + 1] = { id = item, name = name, icon = icon }
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b) return a.name == b.name and a.id < b.id or a.name < b.name end)
    return rows
end
local function Toggle(item, multiple, read, save, limit)
    limit = limit or 32
    local ids, seen = IDs(read(), limit)
    local values = {}
    if multiple then for _, id in ipairs(ids) do if id ~= item then values[#values + 1] = id end end end
    if not seen[item] then
        if #values >= limit then return end
        values[#values + 1] = item
    end
    save(table.concat(values, ","))
end
local function Expert(kind, valid, read, save, multiple)
    P.AskText("comfort-item", Tr("Item ID or item link:"), function(text)
        if not valid() or not NS.PublicText(text) then return end
        local token = text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$")
        local item = token and tonumber(token)
        if item and item > 0 and item < 2147483647 then
            if kind == "rod" then
                local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(item)
                if not Rod(class, subclass) then
                    P.S.Print(Tr("Choose a valid fishing rod."))
                    return
                end
            end
            local _, seen = IDs(read())
            if not seen[item] then Toggle(item, multiple, read, save) end
        else
            P.S.Print(Tr("Enter a valid item ID or item link."))
        end
    end, 260)
end
function P.ComfortItemMenu(anchor, id, key, kind, multiple)
    local valid, save, read = Session(id, key)
    local rows = ItemRows(kind)
    P.ContextMenu(anchor, function(_, root)
        if kind == "lure" then root:CreateTitle(Tr("Choose your lure; other consumables are also listed.")) end
        root:CreateButton(Tr("Clear selection"), function() save("") end)
        if #rows == 0 then root:CreateTitle(Tr("No matching items in your bags.")) end
        for _, row in ipairs(rows) do
            local entry = root:CreateCheckbox(row.name, function()
                local _, seen = IDs(read())
                return seen[row.id] == true
            end, function() if valid() then Toggle(row.id, multiple, read, save) end end)
            entry:SetTooltip(function(tooltip) tooltip:SetItemByID(row.id) end)
        end
        root:CreateButton(Tr("Advanced: enter item ID or link"), function() Expert(kind, valid, read, save, multiple) end)
    end)
end
function P.ComfortDungeonMenu(anchor)
    local valid, save, read = Session("groupFinderTools", "activities")
    local groups = C_LFGList.GetAvailableActivityGroups(GROUP_FINDER_CATEGORY_ID_DUNGEONS, Enum.LFGListFilter.PvE)
    P.ContextMenu(anchor, function(_, root)
        root:CreateButton(Tr("All dungeons"), function() save("") end)
        if not NS.Public(groups) or type(groups) ~= "table" then return end
        for i = 1, math.min(#groups, 100) do
            local id = groups[i]
            local name = NS.Finite(id) and C_LFGList.GetActivityGroupInfo(id)
            if NS.PublicText(name) then
                root:CreateCheckbox(name, function()
                    local _, seen = IDs(read(), 64)
                    return seen[id] == true
                end, function() if valid() then Toggle(id, true, read, save, 64) end end)
            end
        end
    end)
end
local function NativeItemID(text)
    local id = type(text) == "string" and tonumber(text)
    return NS.Finite(id) and id > 0 and id < 2147483647 and id % 1 == 0 and id or nil
end
function P.ComfortSelectedItem(ctx, body, button, id, key, fallback, y, width)
    local label = P.Text(body, "", 20, y, width, P.T.colors.muted)
    P.M.TrackRefresh(ctx, function()
        local item = NativeItemID(P.Get(id, key))
        local name = item and C_Item.GetItemInfo(item)
        if item and key == "rod" then
            local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(item)
            if not Rod(class, subclass) then name = Tr("Choose a valid fishing rod.") end
        end
        P.SetTranslatedText(label, NS.PublicText(name) or Tr(fallback))
    end)
    button:HookScript("OnEnter", function()
        local item = NativeItemID(P.Get(id, key))
        if not item or NS.Safety.IsForbidden(GameTooltip) then return end
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(item)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function()
        if not NS.Safety.IsForbidden(GameTooltip) and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    end)
end

-- Dungeon portals: which learned portals the minimap flyout and the DataText
-- portal and travel menus list (also opened from DataTextsSourcePicker.lua).
-- A Suite popup like the data source picker, so it follows the menu look and
-- the skin; it is built on the first open, so Options load builds none of it.
-- The runtime keeps the lists; the current season follows the game's own.
-- Choosing a portal selects the custom set, as choosing crest currencies does.
local portalPopup
local PORTAL_WIDTH = 430

-- The portals under their group titles, filtered by the search text. Portals
-- not learned yet are grey; they can be chosen ahead and appear once learned.
local function PortalRows(frame)
    local query, y, count, titles = frame.search:GetText():lower(), -2, 0, 0
    frame.note:SetShown(not frame.seasonKnown)
    if not frame.seasonKnown then y = y - math.ceil(frame.note:GetStringHeight() or 28) - 10 end
    for _, group in ipairs(frame.order) do
        local first = true
        for _, choice in ipairs(frame.groups[group[1]]) do
            if query == "" or choice.label:lower():find(query, 1, true) then
                if first then
                    first, titles = false, titles + 1
                    local title = frame.titles[titles] or P.Text(frame.content, "", 0, 0, PORTAL_WIDTH - 48)
                    frame.titles[titles] = title
                    title:ClearAllPoints()
                    title:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, y)
                    P.SetTranslatedText(title, group[2])
                    title:Show()
                    y = y - 23
                end
                count = count + 1
                local row = frame.rows[count]
                if not row then
                    row = frame.Button(frame.content, "", PORTAL_WIDTH - 48, function(self) frame.Toggle(self.choice.id) end)
                    row:SetHeight(26)
                    row:HookScript("OnEnter", function(self)
                        if NS.Safety.IsForbidden(GameTooltip) then return end
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetSpellByID(self.choice.id)
                        GameTooltip:Show()
                    end)
                    row:HookScript("OnLeave", function(self)
                        if not NS.Safety.IsForbidden(GameTooltip) and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
                    end)
                end
                frame.rows[count], row.choice = row, choice
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, y)
                local label = choice.learned and choice.label or "|cff8c8c8c" .. choice.label .. "|r"
                P.SetButtonText(row, NS.Finite(choice.icon) and "|T" .. choice.icon .. ":18|t  " .. label or label)
                row:Show()
                y = y - 30
            end
        end
    end
    for i = count + 1, #frame.rows do frame.rows[i]:Hide() end
    for i = titles + 1, #frame.titles do frame.titles[i]:Hide() end
    frame.empty:SetShown(count == 0)
    frame.content:SetHeight(math.max(1, -y))
    frame.Refresh()
end

-- The saved set, its writes and the mode and action buttons. Every write
-- needs the profile and the combat state the popup opened with (frame.ready).
local function PortalControls(frame)
    function frame.Chosen()
        local saved = P.Get("dungeonPortals", "customPortals")
        if saved ~= frame.saved then
            frame.saved, frame.set = saved, {}
            for token in tostring(saved):sub(1, 1200):gmatch("%d+") do frame.set[tonumber(token)] = true end
        end
        return frame.set
    end
    function frame.Save(values)
        if not frame.ready() then return end
        local ids = {}
        for spell in pairs(values) do ids[#ids + 1] = spell end
        table.sort(ids)
        P.SetMany("dungeonPortals", { portalSet = NS.DungeonPortalSet.CUSTOM, customPortals = table.concat(ids, ",") })
    end
    -- At most as many portals as the flyout and the DataText popup list.
    function frame.Toggle(spell)
        local values, count = {}, 0
        for saved in pairs(frame.Chosen()) do values[saved], count = true, count + 1 end
        if values[spell] then
            values[spell] = nil
        elseif count < 100 then
            values[spell] = true
        else
            return
        end
        frame.Save(values)
    end
    function frame.Refresh()
        local mode, chosen = P.Get("dungeonPortals", "portalSet"), frame.Chosen()
        for value, button in ipairs(frame.modes) do button:SetActive(value == mode) end
        for _, row in ipairs(frame.rows) do
            if row:IsShown() then row:SetActive(chosen[row.choice.id] == true) end
        end
    end
    -- Menu-themed Suite buttons follow the menu look and the skin, hover included.
    local function Button(parent, text, width, onClick)
        local button = P.T.Button(parent, text, width, 24, { noSearch = true })
        button:SetScript("OnClick", function()
            onClick(button)
            frame.Refresh()
        end)
        return button
    end
    frame.Button, frame.modes = Button, {}
    for value, label in ipairs(P.catalog.dungeonPortals.rules.portalSet.choices) do
        frame.modes[value] = Button(frame, label, (PORTAL_WIDTH - 40) / 3 - 4, function()
            if frame.ready() then P.Set("dungeonPortals", "portalSet", value) end
        end)
        frame.modes[value]:SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + (value - 1) * (PORTAL_WIDTH - 40) / 3, -42)
    end
    frame.start = Button(frame, "Start with the current season", (PORTAL_WIDTH - 34) / 2, function()
        local values = {}
        for _, choice in ipairs(frame.groups.season) do values[choice.id] = choice.seasonStart or nil end
        frame.Save(values)
    end)
    frame.start:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -72)
    frame.clear = Button(frame, "Clear custom set", (PORTAL_WIDTH - 34) / 2, function()
        if frame.ready() then P.Set("dungeonPortals", "customPortals", "") end
    end)
    frame.clear:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -72)
end

-- A Suite menu popup (P.MenuPopupPanel, DataTextsSourcePicker.lua): it
-- closes on a click elsewhere, in combat, with the page of its anchor and on
-- a profile change.
local function PortalPopup()
    if portalPopup then return portalPopup end
    local T = P.T
    local frame = P.MenuPopupPanel(PORTAL_WIDTH, 540)
    portalPopup = frame
    frame.rows, frame.titles, frame.hooked = {}, {}, setmetatable({}, { __mode = "k" })
    frame.order = { { "season", Tr("Current season") }, { "learned", Tr("Other learned portals") },
        { "later", Tr("Not learned yet") } }
    P.Text(frame, "Choose dungeon portals", 14, -14, PORTAL_WIDTH - 52, T.colors.text)
    local close = T.Button(frame, "x", 24, 23, { noSearch = true })
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    P.HM.SkipHistoryCheckpoint(close)
    close:SetScript("OnClick", function() frame:Hide() end)
    PortalControls(frame)
    frame.search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.search:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -104)
    frame.search:SetSize(PORTAL_WIDTH - 36, 25)
    frame.search:SetAutoFocus(false)
    frame.search:SetMaxLetters(40)
    if T.SkinEditBox then T.SkinEditBox(frame.search) end
    frame.search:SetScript("OnEscapePressed", function() frame:Hide() end)
    frame.search:SetScript("OnTextChanged", function() if frame:IsShown() then PortalRows(frame) end end)
    P.Text(frame, "Search dungeon portals", 16, -133, PORTAL_WIDTH - 34):SetWordWrap(false)
    frame.scroll = CreateFrame("ScrollFrame", nil, frame)
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -154)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 16)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(PORTAL_WIDTH - 48, 1)
    frame.scroll:SetScrollChild(frame.content)
    frame.scroll:EnableMouseWheel(true)
    frame.scroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 60)))
    end)
    if T.StyleScrollFrame then T.StyleScrollFrame(frame.scroll, frame) end
    frame.note = P.Text(frame.content, "The game has not sent the current season yet; until then every learned portal is listed.",
        0, -2, PORTAL_WIDTH - 48)
    frame.empty = P.Text(frame, "No matching portals.", 14, -160, PORTAL_WIDTH - 48)
    NS.Registry.AddListener(frame, function(_, domain) if domain == "profile" then frame:Hide() end end)
    frame:Hide()
    return frame
end

function P.DungeonPortalMenu(anchor)
    local choices = P.S.DungeonPortalChoices
    if not choices and not P.Combat() then
        C_AddOns.LoadAddOn("MSUF_Suite_QualityOfLife")
        choices = P.S.DungeonPortalChoices
    end
    if not choices or P.Combat() or not anchor then return end
    local frame = PortalPopup()
    if frame:IsShown() and frame.anchor == anchor then
        frame:Hide()
        return
    end
    frame:Hide()
    if not frame.hooked[anchor] then
        frame.hooked[anchor] = true
        anchor:HookScript("OnHide", function() if frame.anchor == anchor then frame:Hide() end end)
    end
    frame.anchor, frame.ready = anchor, P.ProfileGuard()
    frame.groups, frame.seasonKnown = choices()
    local seasonStart = false
    for _, choice in ipairs(frame.groups.season) do seasonStart = seasonStart or choice.seasonStart == true end
    frame.start:SetEnabled(seasonStart)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -5)
    local M = P.M
    if M.ApplyPopupFramePriority then M.ApplyPopupFramePriority(frame) end
    frame.search:SetText("")
    frame:Show()
    PortalRows(frame)
    frame.scroll:SetVerticalScroll(0)
end
