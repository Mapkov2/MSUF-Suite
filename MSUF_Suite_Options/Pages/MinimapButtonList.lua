local _, P = ...
local Suite, S, T, M, Tr = P.Suite, P.S, P.T, P.M, P.Tr
local PAGE, ID, KEY = "suite_minimap", "minimap", "drawerKeep"
local Kept = Suite.MinimapKeptButtons
local ROW_STEP, ROW_HEIGHT, PICKER_WIDTH, GAP = 30, 26, 240, 8
local NOTE = "Buttons you add here stay on the minimap and out of the drawer. Click a kept button to put it back."

-- The drawer collects buttons while the module and the collection are on and
-- no dedicated collector (Suite.MinimapButtonCollectors) is loaded.
function P.MinimapDrawerOpen()
    return P.Get(ID, "enabled") and P.Get(ID, "collectButtons") and not Suite.MinimapButtonCollector()
end

local function Keep(valid, name)
    if not valid() then return end
    local text = Kept.With(P.Get(ID, KEY), name)
    if text then
        P.Set(ID, KEY, text)
    else
        S.Print(Tr("The list of kept buttons is full."))
    end
end

-- The buttons the drawer holds right now, as a menu; the choice joins the list.
local function ChooseButton(anchor)
    local valid, names = P.ProfileGuard(), S.MinimapButtonNames()
    P.ContextMenu(anchor, function(_, root)
        root:CreateTitle(Tr("Keep a button on the minimap"))
        if #names == 0 then root:CreateTitle(Tr("No addon buttons in the drawer.")) end
        for _, name in ipairs(names) do
            root:CreateButton(Kept.Label(name), function() Keep(valid, name) end)
        end
    end)
end

-- A kept button's row: one click puts the button back in the drawer.
local function Row(body, top, width, index)
    local row = T.Button(body, "", width, ROW_HEIGHT, { noSearch = true })
    row:SetPoint("TOPLEFT", body, "TOPLEFT", 16, top - (index - 1) * ROW_STEP)
    row:SetScript("OnClick", function(self)
        if not P.Combat() and self.name then P.Set(ID, KEY, Kept.Without(P.Get(ID, KEY), self.name)) end
    end)
    return row
end

local function ShowRows(rows, names, body, top, width)
    for i = 1, math.max(#rows, #names) do
        local name = names[i]
        local row = rows[i]
        if name and not row then
            row = Row(body, top, width, i)
            rows[i] = row
        end
        if row then
            row.name = name
            row:SetShown(name ~= nil)
            if name then
                P.SetButtonText(row, Tr("Put back in the drawer: %s"):format(Kept.Label(name)))
                row:SetEnabled(not P.Combat())
            end
        end
    end
end

-- The "Keep these buttons on the minimap" list of the Addon buttons section
-- (the `extra` builder of its P.RuleSection): its picker, a note and one
-- row per kept button. The rows come and go, so the section is sized again
-- when their number changes.
function P.MinimapKeptButtons(ctx, builder)
    return function(body, y, width)
        P.Text(body, P.catalog[ID].rules[KEY].label, 16, y, width, T.colors.text)
        local note = P.Text(body, NOTE, 16, y - 20, width)
        y = y - 20 - math.max(14, math.ceil(note:GetStringHeight() or 14)) - GAP
        local picker
        picker = P.Button(ctx, body, "Choose a button to keep", 16, y, PICKER_WIDTH, function() ChooseButton(picker) end,
            function() return S.MinimapButtonNames ~= nil and P.MinimapDrawerOpen() end,
            P.Meta(PAGE, ID, "action.keepButton", "action", PAGE .. "_addons"))
        local top = y - ROW_HEIGHT - GAP
        local rows, count = {}, #Kept.Names(P.Get(ID, KEY))
        M.TrackRefresh(ctx, function()
            local names = Kept.Names(P.Get(ID, KEY))
            local collector = P.Get(ID, "collectButtons") and Suite.MinimapButtonCollector()
            P.SetTranslatedText(note, collector and Tr("%s manages your addon buttons while it is loaded."):format(collector)
                or Tr(NOTE))
            ShowRows(rows, names, body, top, width)
            if #names ~= count then
                count = #names
                P.FinishBody(builder, body, top - count * ROW_STEP)
            end
        end)
        return top - count * ROW_STEP
    end
end
