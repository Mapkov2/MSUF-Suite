local _, P = ...
local Suite, M, T, S = P.Suite, P.M, P.T, P.S
-- Suite pages join MSUF's navigation groups by id, in this order. Each page
-- names its group and its place there (nav, navOrder of P.RegisterPage). A
-- host menu without a group (Retail MSUF still has Appearance and Features)
-- uses the fallback group, or gets the group title in front of its last group.
local NAV_GROUPS = {
    { id = "combat", title = "Combat" },
    { id = "interface", title = "Interface" },
    { id = "style", title = "Style", fallback = "appearance" },
    { id = "general", title = "General", fallback = "features", after = "gameplay" },
}
if type(M.RegisterHistoryProvider) == "function" then
    P.historyRegistered = M.RegisterHistoryProvider("MSUF_Suite", P.CaptureHistoryState, P.RestoreHistoryState) == true
end

-- The HD host atlas gives each Suite destination its own recognizable symbol.
-- Older hosts retain their existing atlas cells.
local HD_NAV_ICONS = {
    suite_nameplates = { 0, 3 }, suite_cooldownManager = { 1, 3 },
    suite_buffReminders = { 2, 3 }, suite_hud = { 3, 3 },
    suite_actionbars = { 4, 3 }, suite_minimap = { 5, 3 },
    suite_damageMeter = { 6, 3 }, suite_bags = { 7, 3 },
    suite_chat = { 0, 4 }, suite_dataTexts = { 1, 4 },
    suite_skin = { 2, 4 }, suite_qualityOfLife = { 3, 4 },
}
local function AddIcons()
    if type(T.navIconGrid) ~= "table" or type(T.navIconColors) ~= "table" then return end
    local neutral = T.navIconColors.gameplay or T.navIconColors.profiles
    local accent = T.navIconColors.home or neutral
    for _, page in ipairs(P.pages) do
        local icon = (tonumber(T.navIconAtlasVersion) or 0) >= 2 and HD_NAV_ICONS[page.key] or page.icon
        if icon and T.navIconGrid[page.key] == nil then T.navIconGrid[page.key] = icon end
        if T.navIconColors[page.key] == nil then T.navIconColors[page.key] = page.accent and accent or neutral end
    end
end

-- Keep unavailable destinations visible and clickable so they can explain how
-- to turn the AddOn on. A saved module switch and Blizzard's AddOn switch are
-- separate: dormant load-on-demand modules still need their settings page.
local ADDON_NOTICE = "You need to turn on the module in Blizzards Addon list"
-- Every catalog module per page; the page reset and the AddOn checks use it.
local PAGE_MODULES = {}
for _, id in ipairs(Suite.SuiteOrder) do
    local key = P.catalog[id].page
    if key then
        local modules = PAGE_MODULES[key] or {}
        PAGE_MODULES[key] = modules
        modules[#modules + 1] = id
    end
end
local function PageAddOnEnabled(key)
    if key == "suite_skin" then return Suite.Client.AddOnEnabled("MSUF_Suite_Skin") end
    local modules = PAGE_MODULES[key]
    if not modules then return true end
    for _, id in ipairs(modules) do
        if Suite.Client.AddOnEnabled(P.catalog[id].addon) then return true end
    end
    return false
end
local function PageEnabled(key)
    if not PageAddOnEnabled(key) then return false, ADDON_NOTICE end
    if key == "suite_skin" then
        return P.SkinningEnabled() == true and Suite.Client.IsAddOnLoaded("MSUF_Suite_Skin"), "Off"
    end
    local modules = PAGE_MODULES[key]
    if not modules then return true end
    for _, id in ipairs(modules) do
        local addon = P.catalog[id].addon
        if S.Config(id).enabled == true and Suite.Client.AddOnEnabled(addon)
            and Suite.Client.IsAddOnLoaded(addon) then return true end
    end
    return false, "Off"
end
local function NavRow(page, group)
    return {
        key = page.key, label = page.label, group = group,
        availability = function() return PageEnabled(page.key) end,
    }
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
        if items[i].title then
            at = i
            break
        end
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

-- The page keys of one navigation group, in their declared order.
local function GroupPages(group)
    local pages = {}
    for _, page in ipairs(P.pages) do
        if page.nav == group then pages[#pages + 1] = page end
    end
    table.sort(pages, function(a, b) return a.navOrder < b.navOrder end)
    for i, page in ipairs(pages) do pages[i] = page.key end
    return pages
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
    for _, spec in ipairs(NAV_GROUPS) do Place(spec, GroupPages(spec.id)) end
    -- A page without a known group still gets a row, at the end of Interface.
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

-- Each refresh pass of a Suite page starts with fresh module availability
-- (Bridge.lua): the first refresher a page registers clears it.
local function PageBuilder(page)
    return function(ctx, ...)
        M.TrackRefresh(ctx, P.ForgetAvailability)
        if not PageAddOnEnabled(page.key) then
            local notice = P.Text(ctx.wrapper, ADDON_NOTICE, 16, -20, math.max(240, (ctx.width or 720) - 32))
            ctx:SetContentHeight(notice:GetStringHeight() + 48)
            return
        end
        return page.build(ctx, ...)
    end
end

local function RegisterPages()
    for _, page in ipairs(P.pages) do
        M.RegisterPage(page.key, { title = page.title, build = PageBuilder(page), version = 1 })
    end
end

-- Menu2 owns the toolbar and confirmation UI. Suite pages extend its reset
-- contract without changing the MSUF page handlers used by either client.
local function InstallPageResets()
    if M._msufSuitePageResetsInstalled then return end
    M._msufSuitePageResetsInstalled = true
    local oldHas, oldWarning = M.PageHasReset, M.BuildPageResetWarning
    local oldReset, oldConfirm = M.ResetPageToDefaults, M.ShowPageResetConfirm
    -- Second result: whether the page resets.
    local function IsSuitePage(key)
        for _, page in ipairs(P.pages) do if page.key == key then return true, page.reset ~= false and PageAddOnEnabled(key) end end
        return false
    end
    function M.PageHasReset(key)
        local suite, resettable = IsSuitePage(key)
        if suite then return resettable end
        return (oldHas and oldHas(key)) or false
    end
    function M.BuildPageResetWarning(key)
        if not IsSuitePage(key) then return oldWarning and oldWarning(key) end
        local title = key
        for _, page in ipairs(P.pages) do
            if page.key == key then
                title = P.Tr(page.title)
                break
            end
        end
        return string.format(P.Tr("Reset %s to defaults?\n\nThis resets all settings on this Suite page for the active profile."), title)
    end
    function M.ResetPageToDefaults(key)
        local suite, resettable = IsSuitePage(key)
        if not suite then return oldReset and oldReset(key) or false end
        if not resettable or P.Combat() then return false end
        if key == "suite_skin" and not Suite.Skin.EnsureEngine() then return false end
        local ok = P.WithHistory("Reset " .. tostring(key), "page:reset:" .. tostring(key), function()
            if key == "suite_skin" then return P.ResetSkinPage() or false end
            local modules = PAGE_MODULES[key]
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
        local suite, resettable = IsSuitePage(key)
        if not suite then return oldConfirm and oldConfirm(key) or false end
        if not resettable or P.Combat() then return false end
        local message = M.BuildPageResetWarning(key)
        if not M.InstallStaticPopup then
            return M.ResetPageToDefaults(key)
        end
        M.InstallStaticPopup("MSUF_SUITE_PAGE_RESET_CONFIRM", {
            text = "%s", button1 = YES, button2 = NO,
            OnAccept = function(_, data)
                if data and data.pageKey then M.ResetPageToDefaults(data.pageKey) end
            end,
        })
        StaticPopup_Show("MSUF_SUITE_PAGE_RESET_CONFIRM", message, nil, { pageKey = key })
        return true
    end
    if M.RefreshToolbarPageReset then M.RefreshToolbarPageReset() end
end

AddIcons()
RegisterPages()

-- Menu2 asks for rows only while its layer overview is open. Keep Suite
-- settings in the Suite profile and use its validated/history-aware setter.
local function SetSuiteLayer(edit, value)
    return P.Set(edit.module, edit.key, value)
end

local function RegisterSuiteLayers()
    if type(M.RegisterLayerOverviewProvider) ~= "function" then return end
    M.RegisterLayerOverviewProvider("suite-owned-surfaces", function(sink)
        local function Add(area, scope, label, module, key, enabled)
            local config = S.Config(module)
            local value = config and config[key]
            local automatic = type(value) ~= "number" or value < 0
            sink:Layer({
                id = "suite." .. module .. "." .. key,
                area = area, scope = scope, label = label,
                value = automatic and 0 or value, default = 0,
                automatic = automatic, enabled = enabled ~= false,
                settingKey = "suite." .. module .. "." .. key,
                edit = { kind = "external", set = SetSuiteLayer, module = module, key = key },
            })
        end

        local cooldown = S.Config("cooldownManager")
        for _, slot in ipairs(Suite.CDM.SLOTS) do
            local keys = Suite.CDM.KEYS[slot.key]
            Add("Suite Cooldown Manager", slot.title, "Whole bar", "cooldownManager", keys.layer,
                cooldown.enabled and cooldown[keys.on])
        end
        local data = S.Config("dataTexts")
        for _, id in ipairs(Suite.DataTextBarIDs(data)) do
            local prefix = "bar" .. id
            local name = data[prefix .. "Name"]
            if type(name) ~= "string" or name == "" then name = P.Tr("Bar %d"):format(id) end
            Add("Suite DataTexts", name, "Whole bar", "dataTexts", prefix .. "Layer",
                data.enabled and data[prefix .. "Enabled"])
        end
        local meter = S.Config("damageMeter")
        for i = 1, Suite.DamageMeterMaxWindows do
            Add("Suite Damage Meter", "Window " .. i, "Whole window", "damageMeter", "w" .. i .. "Layer",
                meter.enabled and i <= meter.windowCount)
        end
        local actions = S.Config("actionbars")
        for i = 1, Suite.ActionBarCount do
            Add("Suite Action Bars", Suite.ActionBarTitles[i], "Whole bar", "actionbars", "bar" .. i .. "Layer",
                actions.enabled and actions["bar" .. i .. "Visibility"] ~= 6)
        end
        local xp = S.Config("xpBar")
        Add("Suite Quality of Life", "Experience", "Experience bar", "xpBar", "layer", xp.enabled)
    end)
end
RegisterSuiteLayers()
InstallPageResets()
local added = AddNavigation()
-- Menu2 builds its navigation once per session. If the window already exists
-- (options were opened before the suite attached), the rows appear after a reload.
if added and M.frame then
    Suite.Print(P.Tr("Reload the interface to show the Suite pages in the MSUF menu."))
end

Suite.Options = {
    RefreshAll = function() P.Refresh() end,
    BuildColorsCategory = function(ctx, builder) return P.BuildColorsCategory(ctx, builder) end,
    ApplyForeverStyle = function() return P.ApplyForeverStyle() end,
}
Suite.Menu.attached = true
