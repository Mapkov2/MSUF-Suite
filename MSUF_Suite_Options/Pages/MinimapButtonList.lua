local _, P = ...
local Suite, S, T, M, Tr = P.Suite, P.S, P.T, P.M, P.Tr
local PAGE, ID, KEY = "suite_minimap", "minimap", "drawerKeep"
local Kept = Suite.MinimapKeptButtons
local ROW_STEP, ROW_HEIGHT, PICKER_WIDTH, GAP = 30, 26, 240, 8
local NOTE = "Kept buttons stay on the minimap and out of the drawer; hidden buttons do not show at all. Click a listed button to undo."

-- The drawer collects buttons while the module and the collection are on and
-- no dedicated collector (Suite.MinimapButtonCollectors) is loaded.
function P.MinimapDrawerOpen()
    return P.Get(ID, "enabled") and P.Get(ID, "collectButtons") and not Suite.MinimapButtonCollector()
end

-- The two lists of the drawer: buttons kept on the map, buttons hidden.
-- Their texts stay literal here so the locale extraction finds them.
local LISTS = { { key = KEY, kept = true }, { key = "drawerHide" } }
local function ListFull(list)
    return Tr(list.kept and "The list of kept buttons is full." or "The list of hidden buttons is full.")
end
local function ListTitle(list)
    return Tr(list.kept and "Keep a button on the minimap" or "Hide a button")
end
local function RowText(list)
    return Tr(list.kept and "Put back in the drawer: %s" or "Show again: %s")
end

local function Add(valid, list, name)
    if not valid() then return end
    local text = Kept.With(P.Get(ID, list.key), name, list.key)
    if text then
        P.Set(ID, list.key, text)
    else
        S.Print(ListFull(list))
    end
end

-- The buttons the drawer holds right now, as a menu; the choice joins the list.
-- Hidden buttons stay collected, so they are left out of both menus.
local function ChooseButton(anchor, list)
    local valid, names = P.ProfileGuard(), S.MinimapButtonNames()
    local _, hidden = Kept.Names(P.Get(ID, "drawerHide"))
    P.ContextMenu(anchor, function(_, root)
        root:CreateTitle(ListTitle(list))
        local any = false
        for _, name in ipairs(names) do
            if not hidden[name] then
                any = true
                root:CreateButton(Kept.Label(name), function() Add(valid, list, name) end)
            end
        end
        if not any then root:CreateTitle(Tr("No addon buttons in the drawer.")) end
    end)
end

-- A listed button's row: one click takes it off its list.
local function Row(body, top, width, index)
    local row = T.Button(body, "", width, ROW_HEIGHT, { noSearch = true })
    row:SetPoint("TOPLEFT", body, "TOPLEFT", 16, top - (index - 1) * ROW_STEP)
    row:SetScript("OnClick", function(self)
        if not P.Combat() and self.name then
            P.Set(ID, self.list.key, Kept.Without(P.Get(ID, self.list.key), self.name))
        end
    end)
    return row
end

-- Kept buttons first, then hidden ones; returns the number of rows shown.
local function ShowRows(rows, body, top, width)
    local entries = {}
    for _, list in ipairs(LISTS) do
        for _, name in ipairs(Kept.Names(P.Get(ID, list.key))) do entries[#entries + 1] = { list = list, name = name } end
    end
    for i = 1, math.max(#rows, #entries) do
        local entry = entries[i]
        local row = rows[i]
        if entry and not row then
            row = Row(body, top, width, i)
            rows[i] = row
        end
        if row then
            row.name, row.list = entry and entry.name, entry and entry.list
            row:SetShown(entry ~= nil)
            if entry then
                P.SetButtonText(row, RowText(entry.list):format(Kept.Label(entry.name)))
                row:SetEnabled(not P.Combat())
            end
        end
    end
    return #entries
end

local function Count()
    local count = 0
    for _, list in ipairs(LISTS) do count = count + #Kept.Names(P.Get(ID, list.key)) end
    return count
end

-- The kept and hidden button lists of the Addon buttons section (the `extra`
-- builder of its rule section): two pickers, a note and one row per listed
-- button. The rows come and go, so the section is sized again when their
-- number changes.
function P.MinimapKeptButtons(ctx, builder)
    return function(body, y, width)
        P.Text(body, "Kept and hidden buttons", 16, y, width, T.colors.text)
        local note = P.Text(body, NOTE, 16, y - 20, width)
        y = y - 20 - math.max(14, math.ceil(note:GetStringHeight() or 14)) - GAP
        local available = function() return S.MinimapButtonNames ~= nil and P.MinimapDrawerOpen() end
        local half = math.min(PICKER_WIDTH, math.floor((width - GAP) / 2))
        local keep, hide
        keep = P.Button(ctx, body, "Choose a button to keep", 16, y, half, function() ChooseButton(keep, LISTS[1]) end,
            available, P.Meta(PAGE, ID, "action.keepButton", "action", PAGE .. "_addons"))
        hide = P.Button(ctx, body, "Choose a button to hide", 16 + half + GAP, y, half,
            function() ChooseButton(hide, LISTS[2]) end,
            available, P.Meta(PAGE, ID, "action.hideButton", "action", PAGE .. "_addons"))
        local top = y - ROW_HEIGHT - GAP
        local rows, count = {}, Count()
        M.TrackRefresh(ctx, function()
            local collector = P.Get(ID, "collectButtons") and Suite.MinimapButtonCollector()
            P.SetTranslatedText(note, collector and Tr("%s manages your addon buttons while it is loaded."):format(collector)
                or Tr(NOTE))
            local shown = ShowRows(rows, body, top, width)
            if shown ~= count then
                count = shown
                P.FinishBody(builder, body, top - count * ROW_STEP)
            end
        end)
        return top - count * ROW_STEP
    end
end
