local _, P = ...
local S, Tr = P.S, P.Tr
local PAGE = "suite_qualityOfLife"

local HELP = {
    repair = "Repairs only when the cost is within your limit. Guild funds are used first when allowed.",
    junk = "Sells poor-quality items in small batches when a merchant opens. Hold Shift while opening the merchant to skip selling.",
    automation = "Hold Shift to pause. Quests with a money cost and quests with a reward choice always stay manual.",
    filters = "An empty allow-list includes every quest. Separate quest IDs with spaces or commas.",
    collection = "Adds automatic collection on top of Blizzard's own Auto Loot setting, which stays unchanged. Locked slots and confirmations stay manual.",
    history = "Hides or briefly shows the loot history window. Need, Greed and Pass popups stay available.",
    log_dungeons = "Choose the dungeon difficulties where MSUF starts the combat log. Mythic+ begins when the keystone starts.",
    log_raids = "Choose the raid difficulties where MSUF starts the combat log.",
    log_other = "Battlegrounds, arenas, scenarios and delves are independent choices.",
    log_exit = "MSUF stops only a log it started. A log that was already on stays on. Re-entering selected content cancels a pending stop. WoW writes the log in its Logs folder.",
    xp_bar = "Choose Midnight Blue, neutral Midnight Dark glass or MSUF Forever's dark gold frame. All use MSUF's bar texture and font. Turn the 20 XP divisions on or off. The lower line can show session gain, XP per hour and time to level. Move the bar in MSUF Edit Mode; hover for exact values. A session survives /reload and starts fresh on the next login.",
}

local GROUPS = {
    { id = "xpBar", title = "Experience bar", switch = "enabled", sections = { "xp_bar" } },
    { id = "qol", title = "Repair", switch = "repair", other = "autoJunk", sections = { "repair" } },
    { id = "qol", title = "Sell junk", switch = "autoJunk", other = "repair", sections = { "junk" } },
    { id = "quests", title = "Quest helpers", switch = "enabled", sections = { "automation", "filters" } },
    { id = "loot", title = "Collecting loot", switch = "quickLoot", other = "manageHistory", sections = { "collection" } },
    { id = "loot", title = "Loot history", switch = "manageHistory", other = "quickLoot", sections = { "history" } },
    { id = "combatLog", title = "Combat logging", switch = "enabled",
        sections = { "log_dungeons", "log_raids", "log_other", "log_exit" } },
}

local function GroupEnabled(group)
    return P.Get(group.id, "enabled") == true and P.Get(group.id, group.switch) == true
end

local function SetGroupEnabled(group, value)
    if group.switch == "enabled" then return P.Set(group.id, "enabled", value) end
    local otherActive = P.Get(group.id, "enabled") == true and P.Get(group.id, group.other) == true
    return P.SetMany(group.id, { [group.switch] = value, enabled = value or otherActive })
end

local function GroupRules(group, source)
    local rules = {}
    for _, rule in ipairs(source) do
        if rule.key ~= group.switch then rules[#rules + 1] = rule end
    end
    return rules
end

local function FeatureAccordion(ctx, b, group)
    local id = group.id
    local sectionId = PAGE .. "_" .. id .. "_" .. group.sections[1]
    local title = Tr(group.title)
    local body = b:CollapsibleSection(sectionId, title, 120, false)
    local width = math.max(240, (body._msuf2Width or b.width or 720) - 32)
    local toggle = P.W.SectionSwitch(body, Tr("Enable"), Tr("Enable"))
    P.M.BindBoolWidget(ctx, toggle,
        function() return GroupEnabled(group) end,
        function(value) SetGroupEnabled(group, value == true) end,
        P.Meta(PAGE, id, group.switch, "setting", sectionId))

    local y = -18
    for _, section in ipairs(group.sections) do
        local source = P.SectionRules(id, section)
        if #group.sections > 1 then
            local heading = P.Text(body, Tr(source[1].sectionTitle), 16, y, width, P.T.colors.text)
            y = y - math.max(14, math.ceil(heading:GetStringHeight() or 14)) - 6
        end
        local help = P.Text(body, HELP[section], 16, y, width)
        y = y - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 10
        y = P.RuleGrid(ctx, body, PAGE, id, GroupRules(group, source), y, width, nil, sectionId)
        y = y - 16
    end
    if id == "xpBar" then
        P.Button(ctx, body, "Move in Edit Mode", 16, y, width,
            function() S.OpenEditMode(id, "experience") end,
            function() return S.Status(id) == "Active" end,
            P.Meta(PAGE, id, "action.edit", "action", sectionId))
        y = y - 34
        P.Button(ctx, body, "Reset session", 16, y, width,
            function() if S.ResetXPSession then S.ResetXPSession() end end,
            function() return S.Status(id) == "Active" end,
            P.Meta(PAGE, id, "action.resetSession", "action", sectionId))
        y = y - 38
    end
    P.M.TrackRefresh(ctx, function()
        local available = S.Availability(id)
        P.W.SetControlEnabled(toggle, not P.Combat())
        local entry = body._msuf2CollapsibleEntry
        if entry and entry.label then
            entry.label:SetText(title .. (available and "" or Tr(" - Unavailable")))
        end
    end)
    P.FinishBody(b, body, y)
end

local function Build(ctx)
    local b = P.W.PageBuilder(ctx)
    for _, group in ipairs(GROUPS) do
        FeatureAccordion(ctx, b, group)
    end
end

P.RegisterPage({ key = PAGE, label = "Quality of Life", title = "Quality of Life", build = Build, icon = { 7, 1 },
    aliases = { "qol", "qualityoflife", "quality_of_life", "merchant", "loot", "quests", "combatlog", "logging", "comfort", "experience", "xpbar", "xp" } })
