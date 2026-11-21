local _, P = ...
local Kit, Suite, Tr = P.SkinPageKit, P.Suite, P.Tr
local copyDialog
local statuses = {
    missing = "Not installed", characterDisabled = "Disabled on this character",
    disabled = "Skin disabled", registered = "Registered integration", waiting = "Waiting for addon",
    ready = "Open an addon window", pending = "Waiting for an eligible window",
    applied = "Skin applied", partial = "Skin applied to some windows", error = "Skin paused after a Lua error",
}

local function Status(engine, id)
    if not engine or not engine.GetStatus then return end
    local status, version, phase = engine.GetStatus(id)
    return Tr(statuses[status] or statuses.ready), version, status, phase
end

local function Option(skin, label, key)
    local path = "addonSkins." .. key
    local row = Kit.Row("toggle", label, path, "addon_skins",
        function()
            return skin and skin.DB.addonSkins[key] == true or false
        end,
        function(value)
            local current = skin or Kit.Engine()
            return Kit.Change(current, label, path, function()
                return current.AddonSkins.SetOption(key, value)
            end)
        end)
    if key ~= "enabled" and key ~= "registered" and key ~= "aceGUI" then
        row.tooltip = function()
            local current = skin or Kit.Engine()
            return Status(current and current.AddonSkins, key)
        end
    end
    return row
end

local function CopyText(text)
    if not Suite.Client.IsAddOnLoaded("MSUF_Suite_Modules") then
        if P.Combat() then return end
        local loaded = C_AddOns.LoadAddOn("MSUF_Suite_Modules")
        if not loaded then return end
    end
    copyDialog = copyDialog or Suite.QoLCopyDialog("Copy", "Ctrl+C", 620, { height = 190 })
    copyDialog.edit:SetMultiLine(true)
    copyDialog.edit:SetHeight(114)
    Suite.QoLShowCopy(copyDialog, text)
end

local function ShowReport(skin)
    local _, build = GetBuildInfo()
    local header = ("MSUF Suite | %s | %s %s | %s"):format(
        skin.version or "?", skin.Client.flavor or "?", build or "?", GetLocale())
    local lines = { header }
    for _, entry in ipairs(Suite.AddonSkinDefinitions) do
        local label, version, _, phase = Status(skin.AddonSkins, entry.id)
        local row = ("%s (%s) — %s"):format(entry.label, version or "?", label or "?")
        lines[#lines + 1] = phase and ("%s [%s]"):format(row, phase) or row
    end
    for _, item in ipairs(skin.AddonSkins.DiscoveredWindows()) do
        if item.enabled then lines[#lines + 1] = ("%s — %s"):format(item.name, Tr("Basic skin enabled")) end
    end
    CopyText(table.concat(lines, "\n"))
end

local function EntryMenu(menu, skin, entry, valid)
    local engine, id = skin.AddonSkins, entry.id
    local label, _, status = Status(engine, id)
    if not status or status == "missing" then return end
    local item = menu:CreateButton(("%s — %s"):format(entry.label, label))
    if status == "error" then
        item:CreateButton(Tr("Retry"), function() if valid() then engine.RetryAddon(id) end end)
    end
    if id == "restedXP" or id == "spoken" or status == "registered" then
        item:CreateTitle(label)
        return
    end
    local function Look(key, value)
        if valid() then
            Kit.Change(skin, entry.label, "addonSkins.looks", function() return engine.SetLook(id, key, value) end)
        end
    end
    for _, option in ipairs({ { "nativeFont", "Keep the addon's font" }, { "softerWindow", "Less opaque window" } }) do
        local key, text = option[1], option[2]
        local function Selected()
            local look = engine.GetLook(id)
            return look and look[key] == true
        end
        item:CreateCheckbox(Tr(text), Selected, function() Look(key, not Selected()) end)
    end
    item:CreateButton(Tr("Follow the Suite look"), function() Look("reset") end)
end

local function Conflicts(menu, skin, current)
    local conflicts = Suite.Skin.ListWindowSkinConflicts()
    if #conflicts == 0 then return end
    local group = menu:CreateButton(Tr("Window skin conflicts"))
    for _, name in ipairs(conflicts) do group:CreateTitle(name) end
    local label = "Disable Suite's Blizzard window skin"
    group:CreateButton(Tr(label), function()
        if current() then
            Kit.Change(skin, label, "enabled.windows", function() return skin.Adapters.SetBlizzardWindowsEnabled(false) end)
        end
    end)
end

local function StatusMenu(anchor, skin)
    local engine = skin.AddonSkins
    local validProfile = P.ProfileGuard()
    local profile = skin.DB
    local function Current() return validProfile() and skin.DB == profile end
    P.ContextMenu(anchor, function(_, menu)
        menu:CreateButton(Tr("Copy addon skin report"), function()
            if Current() then ShowReport(skin) end
        end)
        local all = menu:CreateButton(Tr("All supported addons"))
        for _, option in ipairs({ { true, "Enable all" }, { false, "Disable all" } }) do
            local enabled, label = option[1], option[2]
            all:CreateButton(Tr(label), function()
                if Current() then
                    Kit.Change(skin, label, "addonSkins.bulk", function() return engine.SetKnownAddons(enabled) end)
                end
            end)
        end
        Conflicts(menu, skin, Current)
        local entries, missing = {}, nil
        for _, entry in ipairs(Suite.AddonSkinDefinitions) do entries[#entries + 1] = entry end
        table.sort(entries, function(left, right) return left.label:lower() < right.label:lower() end)
        for _, entry in ipairs(entries) do
            EntryMenu(menu, skin, entry, Current)
            if entry.link and engine.GetStatus(entry.id) == "missing" then
                local url = "https://www.curseforge.com/wow/addons/" .. entry.link
                missing = missing or menu:CreateButton(Tr("Not installed"))
                missing:CreateButton(entry.label, function() if Current() then CopyText(url) end end)
            end
        end
    end)
end

local function DiscoveredMenu(anchor, skin, valid)
    local candidates = skin.AddonSkins.DiscoveredWindows()
    P.ContextMenu(anchor, function(_, menu)
        if #candidates == 0 then menu:CreateTitle(Tr("No eligible addon windows found.")) end
        for _, item in ipairs(candidates) do
            local name, enabled = item.name, item.enabled
            menu:CreateCheckbox(name, function() return enabled end, function()
                if valid() then
                    Kit.Change(skin, "Basic addon skin", "addonSkins.discovered", function()
                        return skin.AddonSkins.SetDiscovered(name, not enabled)
                    end)
                end
            end)
        end
    end)
end

local function Actions(ctx, body, y, width)
    local statusButton, scanButton
    local function Current()
        local skin = Kit.Engine()
        return skin and skin.AddonSkins and skin
    end
    local x, gap = 16, 8
    local columns = width >= 440
    local buttonWidth = columns and (width - gap) / 2 or width
    statusButton = P.SkinSearchButton(ctx, body, "Addon skin status", x, y, buttonWidth, function()
        local skin = Current()
        if skin then StatusMenu(statusButton, skin) end
    end, nil, Kit.Meta("addonSkins.status", "addon_skins"))
    scanButton = P.SkinSearchButton(ctx, body, "Find open addon windows",
        columns and x + buttonWidth + gap or x, columns and y or y - 34, buttonWidth,
        function()
            local skin, valid = Current(), P.ProfileGuard()
            if not skin then return end
            local profile = skin.DB
            local function CurrentProfile() return valid() and skin.DB == profile end
            skin.AddonSkins.ScanWindows(function()
                if CurrentProfile() and scanButton:IsVisible() then DiscoveredMenu(scanButton, skin, CurrentProfile) end
            end)
        end, function()
            local skin = Current()
            return skin and skin.DB.addonSkins.enabled and skin.AddonSkins.ScanWindows ~= nil
        end, Kit.Meta("addonSkins.scan", "addon_skins"))
    return y - (columns and 34 or 68)
end

-- Use the same catalog for the visible controls and cold search metadata.
-- Search never loads the optional engine or creates the legacy skin editor.
function P.BuildSkinAddonSection(ctx, builder, skin)
    local rows = {
        Option(skin, "Skin registered addons", "registered"),
        Option(skin, "Skin other addons", "enabled"),
        Option(skin, "AceGUI / AceConfig windows", "aceGUI"),
    }
    for _, entry in ipairs(P.Suite.AddonSkinDefinitions) do
        rows[#rows + 1] = Option(skin, entry.label, entry.id)
    end
    return Kit.Section(ctx, builder, "addon_skins", "Addon skins",
        "Apply your current skin to supported addon windows. Enable the addons you want to skin.", rows, true, function(...) return Actions(ctx, ...) end)
end
