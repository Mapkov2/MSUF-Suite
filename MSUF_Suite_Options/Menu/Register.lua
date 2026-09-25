local _, P = ...
local Suite, M, T, S = P.Suite, P.M, P.T, P.S
-- Suite pages join MSUF's navigation groups by id, in this order. A host menu
-- without a group (Retail MSUF still has Appearance and Features) uses the
-- fallback group, or gets the group title in front of its last group.
local NAV_GROUPS = {
    { id = "combat", title = "Combat",
        pages = { "suite_cooldownManager", "suite_buffReminders", "suite_hud" } },
    { id = "interface", title = "Interface",
        pages = { "suite_actionbars", "suite_minimap", "suite_damageMeter", "suite_bags", "suite_chat", "suite_dataTexts" } },
    { id = "style", title = "Style", fallback = "appearance", pages = { "suite_skin" } },
    { id = "general", title = "General", fallback = "features", after = "gameplay", pages = { "suite_qualityOfLife" } },
}
local PAGE_ADDONS = {
    suite_actionbars = { "actionbars" },
    suite_minimap = { "minimap" },
    suite_damageMeter = { "damageMeter" },
    suite_bags = { "bags" },
    suite_qualityOfLife = { "qol", "quests", "loot", "combatLog", "xpBar", "skyriding" },
    suite_hud = { "objectives", "announcements", "afkScreen" },
    suite_dataTexts = { "dataTexts" },
    suite_buffReminders = { "buffReminders" },
    suite_chat = { "chat" },
    suite_cooldownManager = { "cooldownManager" },
}
if type(M.RegisterHistoryProvider) == "function" then
    P.historyRegistered = M.RegisterHistoryProvider("MSUF_Suite", P.CaptureHistoryState, P.RestoreHistoryState) == true
end

-- Optional navigation icons reuse cells of MSUF's own icon atlas, so suite
-- rows line up with MSUF rows whenever navigation icons are switched on.
local function AddIcons()
    if type(T.navIconGrid) ~= "table" or type(T.navIconColors) ~= "table" then return end
    local neutral = T.navIconColors.gameplay or T.navIconColors.profiles
    local accent = T.navIconColors.home or neutral
    for _, page in ipairs(P.pages) do
        if page.icon and T.navIconGrid[page.key] == nil then T.navIconGrid[page.key] = page.icon end
        if T.navIconColors[page.key] == nil then T.navIconColors[page.key] = page.accent and accent or neutral end
    end
end

local function NavRow(page, group)
    local row = { key = page.key, label = page.label, group = group }
    local modules = PAGE_ADDONS[page.key]
    if modules then
        row.availability = function()
            local firstReason
            for _, id in ipairs(modules) do
                local ok, reason = Suite.Client.AddOnEnabled(P.catalog[id].addon)
                if ok then return true end
                firstReason = firstReason or reason
            end
            return false, firstReason
        end
    elseif page.key == "suite_skin" then
        row.availability = function() return Suite.Client.AddOnEnabled("MSUF_Suite_Skin") end
    end
    return row
end

local function FindTitle(items, id)
    for i, item in ipairs(items) do
        if item.title and item.id == id then return i end
    end
end

-- Resolves the group a spec's pages join, creating its title when the host
-- has neither the group nor its fallback.
local function ResolveGroup(items, spec)
    if FindTitle(items, spec.id) then return spec.id end
    if spec.fallback and FindTitle(items, spec.fallback) then return spec.fallback end
    local at = #items + 1
    for i = #items, 1, -1 do
        if items[i].title then at = i; break end
    end
    table.insert(items, at, { title = spec.title, id = spec.id })
    return spec.id
end

-- Row index a new page of `group` goes after: the `after` page when the group
-- holds it, else the group's last row (its title while it is empty).
local function InsertIndex(items, group, after)
    local last = FindTitle(items, group)
    for i = last + 1, #items do
        local item = items[i]
        if item.title or item.header then break end
        if item.group == group then
            last = i
            if after and item.key == after then break end
        end
    end
    return last
end

-- Navigation rows are inserted in place (other Menu2 files hold references
-- to these tables).
local function AddNavigation()
    local items = M.navItems
    if type(items) ~= "table" then return false end
    local pagesByKey = {}
    for _, page in ipairs(P.pages) do pagesByKey[page.key] = page end
    for _, item in ipairs(items) do
        if item.key and pagesByKey[item.key] then return true end
    end
    local placed = {}
    local function Place(spec, keys)
        local group = ResolveGroup(items, spec)
        local after = spec.after
        for _, key in ipairs(keys) do
            local page = pagesByKey[key]
            if page and not placed[key] then
                table.insert(items, InsertIndex(items, group, after) + 1, NavRow(page, group))
                placed[key], after = true, key
            end
        end
    end
    for _, spec in ipairs(NAV_GROUPS) do Place(spec, spec.pages) end
    -- A page missing from NAV_GROUPS still gets a row, at the end of Interface.
    for _, page in ipairs(P.pages) do
        if not placed[page.key] then Place(NAV_GROUPS[2], { page.key }) end
    end
    if type(M.navPrimaryForKey) == "table" then
        for _, page in ipairs(P.pages) do M.navPrimaryForKey[page.key] = page.key end
    end
    if type(M.ALIASES) == "table" then
        for _, page in ipairs(P.pages) do
            if M.ALIASES[page.key] == nil then M.ALIASES[page.key] = page.key end
            for _, alias in ipairs(page.aliases or {}) do
                if M.ALIASES[alias] == nil then M.ALIASES[alias] = page.key end
            end
        end
    end
    return true
end

local function RegisterPages()
    for _, page in ipairs(P.pages) do
        M.RegisterPage(page.key, { title = page.title, build = page.build, version = 1 })
    end
end

-- Menu2 owns the toolbar and confirmation UI. Suite pages extend its reset
-- contract without changing the MSUF page handlers used by either client.
local function InstallPageResets()
    if M._msufSuitePageResetsInstalled then return end
    M._msufSuitePageResetsInstalled = true
    local oldHas, oldWarning = M.PageHasReset, M.BuildPageResetWarning
    local oldReset, oldConfirm = M.ResetPageToDefaults, M.ShowPageResetConfirm
    local function IsSuitePage(key)
        for _, page in ipairs(P.pages) do if page.key == key then return true end end
        return false
    end
    function M.PageHasReset(key)
        return IsSuitePage(key) or (oldHas and oldHas(key)) or false
    end
    function M.BuildPageResetWarning(key)
        if not IsSuitePage(key) then return oldWarning and oldWarning(key) end
        local title = key
        for _, page in ipairs(P.pages) do if page.key == key then title = P.Tr(page.title); break end end
        return string.format(P.Tr("Reset %s to defaults?\n\nThis resets all settings on this Suite page for the active profile."), title)
    end
    function M.ResetPageToDefaults(key)
        if not IsSuitePage(key) then return oldReset and oldReset(key) or false end
        if P.Combat() then return false end
        if key == "suite_skin" and Suite.Skin and Suite.Skin.EnsureEngine
            and not Suite.Skin.EnsureEngine() then return false end
        local ok = P.WithHistory("Reset " .. tostring(key), "page:reset:" .. tostring(key), function()
            if key == "suite_skin" then return P.ResetSkinPage and P.ResetSkinPage() or false end
            local modules = PAGE_ADDONS[key]
            if not modules then return false end
            for _, id in ipairs(modules) do if not S.Reset(id) then return false end end
            return true
        end)
        if ok then
            P.Refresh()
            if M.ShowStatusFeedback then M.ShowStatusFeedback(P.Tr("Page reset"), "ok", 1.5) end
        end
        return ok
    end
    function M.ShowPageResetConfirm(key)
        if not IsSuitePage(key) then return oldConfirm and oldConfirm(key) or false end
        if P.Combat() then return false end
        local message = M.BuildPageResetWarning(key)
        if not (_G.StaticPopupDialogs and _G.StaticPopup_Show and M.InstallStaticPopup) then
            return M.ResetPageToDefaults(key)
        end
        M.InstallStaticPopup("MSUF_SUITE_PAGE_RESET_CONFIRM", {
            text = "%s", button1 = _G.YES or "Yes", button2 = _G.NO or "No",
            OnAccept = function(_, data)
                if data and data.pageKey then M.ResetPageToDefaults(data.pageKey) end
            end,
        })
        _G.StaticPopup_Show("MSUF_SUITE_PAGE_RESET_CONFIRM", message, nil, { pageKey = key })
        return true
    end
    if M.RefreshToolbarPageReset then M.RefreshToolbarPageReset() end
end

AddIcons()
RegisterPages()
InstallPageResets()
local added = AddNavigation()
-- Menu2 builds its navigation once per session. If the window already exists
-- (options were opened before the suite attached), the rows appear after a reload.
if added and M.frame then
    Suite.Print(P.Tr("Reload the interface to show the Suite pages in the MSUF menu."))
end

Suite.Options = Suite.Options or {}
Suite.Options.RefreshAll = function() P.Refresh() end
if type(P.BuildColorsCategory) == "function" then
    Suite.Options.BuildColorsCategory = function(ctx, builder) return P.BuildColorsCategory(ctx, builder) end
end
if type(P.ApplyForeverStyle) == "function" then
    Suite.Options.ApplyForeverStyle = function() return P.ApplyForeverStyle() end
end
Suite.Menu.attached = true
