local _, P = ...
local Page, Tr = P.CDMPage, P.Tr
local Overrides = {}
P.CDMOverrides = Overrides

function Overrides.Entries()
    local data, spec = Page.SpellOverrides(), Page.Spec()
    local personal = spec and data.s and data.s[spec] or {}
    local rows = {}
    for _, entry in ipairs(Page.Entries(Page.selected) or {}) do
        local key = Page.EntryKey(entry)
        local shared, own = data.e[key], personal[key]
        if shared and next(shared) or own and next(own) then
            rows[#rows + 1] = { entry = entry, key = key, shared = shared and next(shared) ~= nil,
                personal = own and next(own) ~= nil }
        end
    end
    return rows
end

function Overrides.Open(anchor)
    if P.Combat() then return end
    local rows = Overrides.Entries()
    P.ContextMenu(anchor, function(_, menu)
        menu:CreateTitle(Tr("Spell overrides"))
        menu:SetScrollMode(420)
        if #rows == 0 then menu:CreateTitle(Tr("No spell overrides on this bar.")) end
        for _, row in ipairs(rows) do
            local entry, key = row.entry, row.key
            local scope = row.personal and row.shared and Tr("Shared and this specialization")
                or row.personal and Tr("This specialization") or Tr("All bars and specializations")
            local name = Page.Public(entry.name) and entry.name or key
            menu:CreateButton(Tr("%s - %s"):format(name, scope), function()
                Page.spellSpecScope = row.personal == true
                Page.TogglePopover({ key = key, name = name, texture = entry.texture,
                    family = Page.Family(Page.selected), aura = entry.aura, unit = entry.unit }, anchor)
            end)
        end
    end)
end

function Overrides.Build(ctx, builder)
    P.LazySection(builder, "suite_cooldownManager_overrides", Tr("Spell overrides"), false, {
        content = function(body)
            local width = math.max(240, (P.HM.GetSectionWidth(body) or builder.width) - 32)
            P.Text(body, "Choose a spell to inspect its shared or specialization settings.", 16, -18, width)
            local button
            button = P.Button(ctx, body, "Spell overrides", 16, -60, width,
                function() Overrides.Open(button) end, function() return not Page.EditorBlocked() and not P.Combat() end,
                P.Meta(Page.PAGE, Page.ID, "spells.overrides", "action", "suite_cooldownManager_overrides"))
            P.HM.SkipHistoryCheckpoint(button)
            return -100
        end,
        finish = function(body, y) P.FinishBody(builder, body, y) end,
    })
end
