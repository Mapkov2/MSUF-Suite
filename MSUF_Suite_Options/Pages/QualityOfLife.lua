local _, P = ...
local S, Tr = P.S, P.Tr
local PAGE = "suite_qualityOfLife"

local HELP = {
    repair = "Repairs only when the cost is within your limit. Guild funds are used first when allowed.",
    junk = "Uses Blizzard's Sell All Junk action when a merchant opens, including its per-bag exclusions. Hold Shift while opening the merchant to skip selling. The optional chat line confirms the request, not completed sales.",
    automation = "Hold Shift to pause. Quests with a money cost and quests with a reward choice always stay manual.",
    filters = "An empty allow-list includes every quest. Separate quest IDs with spaces or commas.",
    collection = "Adds automatic collection on top of Blizzard's own Auto Loot setting, which stays unchanged. Locked slots and confirmations stay manual.",
    history = "Hides or briefly shows the loot history window. Need, Greed and Pass popups stay available.",
    log_dungeons = "Choose the dungeon difficulties where MSUF starts the combat log. Mythic+ begins when the keystone starts.",
    log_raids = "Choose the raid difficulties where MSUF starts the combat log.",
    log_other = "Battlegrounds, arenas, scenarios and delves are independent choices.",
    log_exit = "MSUF stops only a log it started. A log that was already on stays on. Re-entering selected content cancels a pending stop. WoW writes the log in its Logs folder.",
    xp_bar = "Choose Midnight Blue, neutral Midnight Dark glass or MSUF Forever's dark gold frame. All use MSUF's bar texture and font. Turn the 20 XP divisions on or off. The lower line can show session gain, XP per hour and time to level. Move or resize the bar in MSUF Edit Mode; its popup edits X, Y, width, height and scale. Hover for exact values. A session survives /reload and starts fresh on the next login.",
    innervate_cue = "Retail Druids only. Every incoming whisper in combat is a possible Innervate cue; message text cannot be inspected reliably during chat lockdown. The alert waits for a publicly known Innervate cooldown, or shows a generic cue when readiness is unavailable. A preferred target can be outlined on an MSUF group frame resolved outside combat. MSUF Edit Mode previews the alert and edits its position and size.",
    durability_warning = "Shows the lowest equipped durability below your chosen threshold, outside combat. MSUF Edit Mode shows a sample even when your gear is repaired. Its popup edits X, Y, width, height and scale.",
    battle_res = "Shows Blizzard's shared battle resurrection charges in an active Mythic+ run or raid encounter. The icon counts down to the next charge using Blizzard's cooldown display. Hidden when the shared pool is unavailable. MSUF Edit Mode previews the display and edits X, Y, width, height and scale.",
    flight_hud = "Retail only. Shows while Skyriding is available, or only in flight if selected. The bars show speed, Vigor and Second Wind; the icon shows Whirling Surge. MSUF Edit Mode previews the HUD and edits X, Y, width, bar height and scale. Panel height follows the visible content. Unknown charge values display as dashes.",
    flight_typography = "Choose an MSUF or SharedMedia font and bar texture. Font size, outline, shadow, Smooth/Sharp/Slug rendering, bar height and spacing update the HUD immediately. Slug has no shadow.",
    flight_colors = "Pick a preset above or use the three color dots in this header for your own colors. Changing a color marks the look as Custom. Panel opacity and empty bar opacity are separate.",
}

local GROUPS = {
    -- Keep the visible feature names alphabetic; section IDs stay stable for search and history.
    { id = "battleRes", title = "Battle resurrection (Retail)", switch = "enabled",
        sections = { "battle_res" } },
    { id = "loot", title = "Collecting loot", switch = "quickLoot", other = "manageHistory", sections = { "collection" } },
    { id = "combatLog", title = "Combat logging", switch = "enabled",
        sections = { "log_dungeons", "log_raids", "log_other", "log_exit" } },
    { id = "xpBar", title = "Experience bar", switch = "enabled", sections = { "xp_bar" } },
    { id = "innervateCue", title = "Innervate whisper cue (Retail Druid)", switch = "enabled", sections = { "innervate_cue" } },
    { id = "loot", title = "Loot history", switch = "manageHistory", other = "quickLoot", sections = { "history" } },
    { id = "durabilityAlert", title = "Low durability warning", switch = "enabled",
        sections = { "durability_warning" } },
    { id = "quests", title = "Quest helpers", switch = "enabled", sections = { "automation", "filters" } },
    { id = "qol", title = "Repair", switch = "repair", other = "autoJunk", sections = { "repair" } },
    { id = "qol", title = "Sell junk", switch = "autoJunk", other = "repair", sections = { "junk" } },
    { id = "skyriding", title = "Skyriding HUD (Retail)", switch = "enabled",
        sections = { "flight_hud", "flight_typography", "flight_colors" } },
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

local function SelectInnervateTarget()
    local name, realm = UnitFullName("target")
    if not P.Suite.PublicText(name) or not P.Suite.Public(realm) then return end
    P.Set("innervateCue", "targetName", realm and realm ~= "" and (name .. "-" .. realm) or name)
end

local function HasPlayerTarget()
    local player = UnitIsPlayer("target")
    return P.Suite.Public(player) and player == true
end

local function FeatureAccordion(ctx, b, group)
    local id, sectionId = group.id, PAGE .. "_" .. group.id .. "_" .. group.sections[1]
    local title = Tr(group.title)
    local body = b:CollapsibleSection(sectionId, title, 120, false)
    local width = math.max(240, (body._msuf2Width or b.width or 720) - 32)
    local toggle = P.W.SectionSwitch(body, Tr("Enable"), Tr("Enable"))
    P.M.BindBoolWidget(ctx, toggle,
        function() return GroupEnabled(group) end,
        function(value) SetGroupEnabled(group, value == true) end,
        P.Meta(PAGE, id, group.switch, "setting", sectionId))

    local y, allRules = -18, {}
    for _, section in ipairs(group.sections) do
        local source = P.SectionRules(id, section)
        local rules = GroupRules(group, source)
        for _, rule in ipairs(rules) do allRules[#allRules + 1] = rule end
        if #group.sections > 1 then
            local heading = P.Text(body, Tr(source[1].sectionTitle), 16, y, width, P.T.colors.text)
            y = y - math.max(14, math.ceil(heading:GetStringHeight() or 14)) - 6
        end
        local help = P.Text(body, HELP[section], 16, y, width)
        y = y - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 10
        y = P.RuleGrid(ctx, body, PAGE, id, rules, y, width, nil, sectionId)
        y = y - 16
    end
    if id == "xpBar" then
        P.Button(ctx, body, "Move / resize in Edit Mode", 16, y, width,
            function() P.OpenEditMode(id, "experience") end,
            function() return P.EditModeReady() and S.Status(id) == "Active" end,
            P.Meta(PAGE, id, "action.edit", "action", sectionId))
        y = y - 34
        -- S.ResetXPSession comes with the Quality of Life addon.
        P.Button(ctx, body, "Reset session", 16, y, width,
            function() if S.ResetXPSession then S.ResetXPSession() end end,
            function() return S.Status(id) == "Active" end,
            P.Meta(PAGE, id, "action.resetSession", "action", sectionId))
        y = y - 38
    elseif id == "innervateCue" then
        P.Button(ctx, body, "Move / resize in Edit Mode", 16, y, width,
            function() P.OpenEditMode(id, "alert") end,
            function() return P.EditModeReady() and S.Status(id) == "Active" end,
            P.Meta(PAGE, id, "action.edit", "action", sectionId))
        y = y - 34
        P.Button(ctx, body, "Use current player target", 16, y, width,
            SelectInnervateTarget, HasPlayerTarget,
            P.Meta(PAGE, id, "action.target", "action", sectionId))
        y = y - 38
    elseif id == "durabilityAlert" then
        P.Button(ctx, body, "Move / resize in Edit Mode", 16, y, width,
            function() P.OpenEditMode(id, "warning") end,
            function() return P.EditModeReady() and S.Status(id) == "Active" end,
            P.Meta(PAGE, id, "action.edit", "action", sectionId))
        y = y - 38
    elseif id == "battleRes" then
        P.Button(ctx, body, "Move / resize in Edit Mode", 16, y, width,
            function() P.OpenEditMode(id, "charges") end,
            function() return P.EditModeReady() and S.Status(id) == "Active" end,
            P.Meta(PAGE, id, "action.edit", "action", sectionId))
        y = y - 38
    elseif id == "skyriding" then
        P.Button(ctx, body, "Move / resize in Edit Mode", 16, y, width,
            function() P.OpenEditMode(id, "flight") end,
            function() return P.EditModeReady() and S.Status(id) == "Active" end,
            P.Meta(PAGE, id, "action.edit", "action", sectionId))
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
    P.AttachRuleColors(body, title, id, allRules)
    P.AttachSectionReset(ctx, body, title, function()
        return P.ResetRules(id, allRules, nil, { group.switch })
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
    aliases = { "qol", "qualityoflife", "quality_of_life", "merchant", "loot", "quests", "combatlog", "logging", "comfort", "experience", "xpbar", "xp", "innervate", "whisper", "durability", "repairwarning", "battleres", "brez", "combatres", "skyriding", "vigor", "secondwind" } })
