local _, P = ...
local Suite, M, T = P.Suite, P.M, P.T
local GROUP = "suite_modules"
local PAGE_ADDONS = {
    suite_actionbars = { "actionbars" },
    suite_minimap = { "minimap" },
    suite_damageMeter = { "damageMeter" },
    suite_bags = { "bags" },
    suite_qualityOfLife = { "qol", "quests", "loot", "combatLog", "xpBar" },
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

-- Navigation rows are appended in place (other Menu2 files hold references
-- to these tables). The suite group sits right before MSUF's Features group.
local function AddNavigation()
    local items = M.navItems
    if type(items) ~= "table" then return false end
    for _, item in ipairs(items) do
        if item.id == GROUP or item.key == "suite" then return true end
    end
    local at = #items + 1
    for i, item in ipairs(items) do
        if item.title and item.id == "features" then at = i; break end
    end
    local rows = { { title = "UI Suite", id = GROUP } }
    for _, page in ipairs(P.pages) do
        local row = { key = page.key, label = page.label, group = GROUP }
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
        rows[#rows + 1] = row
    end
    for offset, row in ipairs(rows) do table.insert(items, at + offset - 1, row) end
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

AddIcons()
RegisterPages()
local added = AddNavigation()
-- Menu2 builds its navigation once per session. If the window already exists
-- (options were opened before the suite attached), the rows appear after a reload.
if added and M.frame then
    Suite.Print(P.Tr("Reload the interface to show the UI Suite pages in the MSUF menu."))
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
