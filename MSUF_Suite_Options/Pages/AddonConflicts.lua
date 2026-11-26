local _, P = ...
local Conflicts = P.Suite.AddonConflicts
local PAGE = "suite_addonConflicts"

local function ChooseMine(row)
    local profile = P.Suite.Database.GetActiveProfileName()
    local text = P.Tr("Use MSUF for %s and disable %s for this character?"):format(P.Tr(row.title), table.concat(row.addons, ", "))
    P.Confirm("suite.conflicts." .. row.id, text, function()
        if P.Suite.Database.GetActiveProfileName() ~= profile then return end
        local all, some = Conflicts.UseSuite(row.id, row.addons)
        if not all then P.Suite.Print(P.Tr("Some addon choices could not be applied. Refresh the list.")) end
        if not all and not some then return end
        P.Confirm("suite.conflicts.reload", P.Tr("Reload now to switch addons?"), function()
            if not P.Combat() then ReloadUI() end
        end)
    end)
end

local function BuildChoices(ctx, body, width)
    local y, rows = -12, Conflicts.List()
    if #rows == 0 then
        P.Text(body, "No overlapping addons are active.", 16, y, width)
        return 48
    end
    for _, row in ipairs(rows) do
        local entry = row
        local half = math.floor((width - 8) / 2)
        P.Text(body, entry.title, 16, y, width, nil, "section")
        local addons = P.Text(body, "", 16, y - 21, width)
        P.SetTranslatedText(addons, table.concat(entry.addons, ", "))
        P.Button(ctx, body, "Use MSUF", 16, y - 45, half, function() ChooseMine(entry) end)
        P.Button(ctx, body, "Use the other addon", 24 + half, y - 45, half, function()
            P.Set(entry.id, "enabled", false)
            P.M.InvalidatePage(PAGE)
            P.Suite.Menu.Open(PAGE)
        end)
        y = y - 84
    end
    return -y + 8
end

local function Build(ctx)
    local builder = P.W.PageBuilder(ctx)
    if ctx.searchRows then
        P.SkinSearchRow(ctx, { pageKey = PAGE, kind = "section", label = P.Tr("Addon conflicts") },
            "addon_conflicts", P.Tr("Addon conflicts"))
        return
    end
    P.LazySection(builder, "addon_conflicts", P.Tr("Overlapping addons"), true, {
        content = function(body)
            local width = math.max(240, (P.HM.GetSectionWidth(body) or builder.width or 720) - 32)
            return BuildChoices(ctx, body, width)
        end,
    })
end

P.RegisterPage({ key = PAGE, label = "Addon conflicts", title = "Addon conflicts", build = Build,
    icon = { 7, 1 }, nav = "interface", navOrder = 10, aliases = { "conflict", "addon konflikt" } })
