local _, P = ...
local S, Tr, HM = P.S, P.Tr, P.HM
local PAGE, V = "suite_qualityOfLife", P.QoLView
local function PageFor(id)
    local group = V.FindFeature(id)
    return group and V.GetFeaturePage(group) or PAGE
end
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
        if rule.key ~= group.switch and not rule.hidden then rules[#rules + 1] = rule end
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

local function AddLoadoutAction(ctx, body, id, sectionId, y, width)
    P.Button(ctx, body, "Show the reminder now", 16, y, width,
        function() if S.LoadoutReminder then S.LoadoutReminder:Test() end end,
        function() return S.Status(id) == "Active" and not P.Combat() end,
        P.Meta(PageFor(id), id, "action.test", "action", sectionId))
    y = y - 38
    P.Button(ctx, body, "Save current build and loot spec", 16, y, width,
        function() if S.LoadoutReminder then S.LoadoutReminder:SaveCurrent() end end,
        function() return S.Status(id) == "Active" and not P.Combat() end,
        P.Meta(PageFor(id), id, "action.saveCurrent", "action", sectionId))
    y = y - 38
    P.Button(ctx, body, "Clear saved selection", 16, y, width,
        function() if S.LoadoutReminder then S.LoadoutReminder:ClearSaved() end end,
        function() return S.Status(id) == "Active" and not P.Combat() end,
        P.Meta(PageFor(id), id, "action.clearSaved", "action", sectionId))
    y = y - 38
    P.Button(ctx, body, "Set required abilities for this dungeon", 16, y, width,
        function()
            local reminder = S.LoadoutReminder
            if not reminder then return end
            local zone, guid, config = reminder:DungeonAbilityContext()
            if not zone then return end
            P.AskText("loadoutDungeonAbilities",
                Tr("Enter up to six spell names or IDs separated by commas. Enter 0 to clear this dungeon."),
                function(value)
                    if not reminder:SetDungeonAbilities(value, zone, guid, config) then
                        print(Tr("The dungeon ability list could not be saved."))
                    end
                end, 240, 720)
        end,
        function() return S.LoadoutReminder and S.LoadoutReminder:CanSetDungeonAbilities() end,
        P.Meta(PageFor(id), id, "action.dungeonAbilities", "action", sectionId))
    return y - 38
end


-- The Edit Mode element of each module that has one (spec.editElement).
local EDIT_ELEMENTS = {}
for id, spec in pairs(P.catalog) do
    if spec.editElement then EDIT_ELEMENTS[id] = spec.editElement end
end
-- Edit Mode elements that exist only in one setup: the cursor's global
-- cooldown circle is placed only while it stands on its own.
local EDIT_READY = { cursorEffects = function() return P.Get("cursorEffects", "gcdDetached") == true end }
-- Search offers the same Move / resize buttons (Menu/SearchActions.lua).
P.QualityOfLifeEditElements = EDIT_ELEMENTS


local function AddEditModeAction(ctx, body, id, sectionId, y, width, element)
    P.Button(ctx, body, "Move / resize in Edit Mode", 16, y, width,
        function() P.OpenEditMode(id, element) end,
        function()
            return P.EditModeReady() and S.Status(id) == "Active" and (not EDIT_READY[id] or EDIT_READY[id]())
        end,
        P.Meta(PageFor(id), id, "action.edit", "action", sectionId))
    return y - ((id == "xpBar" or id == "innervateCue") and 34 or 38)
end

local function FeatureSectionId(group)
    return PAGE .. "_" .. group.id .. "_" .. group.sections[1]
end

-- Edit Mode uses the same exact feature route as search. A relocated feature
-- must build its destination before its lazy row can be resolved.
function P.Suite.Menu.FocusQualityOfLifeModule(id)
    if P.PlayerAurasPage.Open(id) then return true end
    local group = V.FindFeature(id)
    -- Multi-feature modules such as loot/merchant helpers open the overview.
    if not group then return true end
    local page = V.GetFeaturePage(group)
    if page == "suite_macros" then
        P.MacroPage.PrepareSearch("consumable")
        return P.Suite.Menu.Open(page)
    end
    if page ~= PAGE and not P.Suite.Menu.Open(page) then return false end
    local entry = P.M.cache and P.M.cache[page]
    local resolve = entry and HM.GetMissingSectionResolver(entry)
    local section = resolve and resolve(FeatureSectionId(group))
    if not section then return false end
    -- Focus the detail panel itself, after selecting its category.
    local called, opened, focused = P.M.SearchBridge.OpenSearchTarget(page, "", nil, section, {},
        { pageKey = page, sectionId = FeatureSectionId(group) })
    return called == true and opened == true and focused == true
end

local function FeatureRules(group)
    local sections, all = {}, {}
    for _, key in ipairs(group.sections) do
        local source = P.SectionRules(group.id, key)
        local rules = GroupRules(group, source)
        sections[#sections + 1] = { key = key, source = source, rules = rules }
        for _, rule in ipairs(rules) do all[#all + 1] = rule end
    end
    return sections, all
end

local function FeatureKeywords(group, includeAliases)
    local words = { group.title, Tr(group.title), group.categoryTitle, Tr(group.categoryTitle) }
    if includeAliases then
        for _, word in ipairs(group.aliases or {}) do words[#words + 1] = word end
    end
    for _, word in ipairs(group.keywords or {}) do words[#words + 1] = word end
    if group.tabTitle then
        words[#words + 1], words[#words + 2] = group.tabTitle, Tr(group.tabTitle)
    end
    -- Each detail owns its search words; colors route to the feature shortcut.
    if not includeAliases then return words end
    for _, section in ipairs(group.sections) do
        for _, rule in ipairs(P.SectionRules(group.id, section)) do
            if rule.color and not rule.hidden then
                words[#words + 1], words[#words + 2] = rule.label, Tr(rule.label)
            end
        end
    end
    return words
end

local function AddFeatureHelp(details, group, sections)
    local helpText = {}
    for _, section in ipairs(sections) do helpText[#helpText + 1] = P.QoLHelpText(section.key) end
    local title, text = Tr(group.title), table.concat(helpText, "\n\n")
    local entry = HM.GetSectionEntry(details)
    P.M.AddTooltip(entry and entry.header or details, title, text, { hook = true })
end

local function RuleSearchKind(rule)
    if rule.font or rule.texture or rule.choices then return "dropdown" end
    if type(rule.default) == "boolean" then return "toggle" end
    if type(rule.default) == "number" then return "slider" end
    return "textinput"
end

local function RegisterFeatureRuleSearch(group, sectionId, entries, keywords)
    for _, entry in ipairs(entries or {}) do
        if entry.widget then
            local rule = entry.rule
            local meta = P.Meta(V.GetFeaturePage(group), group.id, rule.key, "setting", sectionId)
            meta.pageKey, meta.kind = V.GetFeaturePage(group), RuleSearchKind(rule)
            local words = { rule.label, Tr(rule.label) }
            for _, word in ipairs(keywords) do words[#words + 1] = word end
            meta.label, meta.keywords = Tr(rule.label), words
            P.M.RegisterSearchWidget(entry.widget, meta)
            HM.SetSearchTargetPrepare(entry.widget, function() return group.reveal(true) ~= nil end)
        end
    end
end

local function BuildFeatureDetails(ctx, details, group, sectionId, width, sections, allRules, keywords)
    if #allRules == 0 and group.id ~= "mailTemplates" and not EDIT_ELEMENTS[group.id]
        and group.id ~= "xpBar" and group.id ~= "innervateCue" and group.id ~= "loadoutReminder"
        and group.id ~= "macroBuilder" then
        return nil, 0
    end
    details._msufSuiteSkipSummary = true
    AddFeatureHelp(details, group, sections)
    local y = P.BuildQoLIndicatorPreview(ctx, details, group.id, width, -18)
    y = P.BuildNewToolActions(ctx, details, group.id, sectionId, y, width - 32)
    for _, section in ipairs(sections) do
        if #sections > 1 and section.source[1] then
            local subtitle = P.Text(details, section.source[1].sectionTitle, 16, y, width - 32, P.T.colors.text)
            y = y - math.max(14, math.ceil(subtitle:GetStringHeight() or 14)) - 6
        end
        if #section.rules > 0 then
            local _, entries
            local rules = group.id == "xpBar" and P.XPBarTextOptions.BarRules(section.rules) or section.rules
            y, entries = P.RuleGrid(ctx, details, V.GetFeaturePage(group), group.id, rules, y,
                width - 32, nil, sectionId, nil, nil, true)
            RegisterFeatureRuleSearch(group, sectionId, entries, keywords)
        end
        y = y - 12
    end
    local element = EDIT_ELEMENTS[group.id]
    if element then y = AddEditModeAction(ctx, details, group.id, sectionId, y, width - 32, element) end
    if group.id == "xpBar" then
        P.Button(ctx, details, "Reset session", 16, y, width - 32,
            function() if S.ResetXPSession then S.ResetXPSession() end end,
            function() return S.Status(group.id) == "Active" end,
            P.Meta(V.GetFeaturePage(group), group.id, "action.resetSession", "action", sectionId))
        y = y - 38
    elseif group.id == "innervateCue" then
        P.Button(ctx, details, "Use current player target", 16, y, width - 32,
            SelectInnervateTarget, HasPlayerTarget,
            P.Meta(V.GetFeaturePage(group), group.id, "action.target", "action", sectionId))
        y = y - 38
    elseif group.id == "loadoutReminder" then
        y = AddLoadoutAction(ctx, details, group.id, sectionId, y, width - 32)
    end
    local colorShortcut = P.AttachRuleColors(details, group.title, group.id, allRules)
    if colorShortcut then
        P.M.RegisterControlMetadata(colorShortcut,
            P.Meta(V.GetFeaturePage(group), group.id, "action.colors." .. group.switch, "action", sectionId),
            Tr("%s Colors"):format(Tr(group.title)), "button")
    end
    local height = math.max(72, -y + 12)
    return y, height, colorShortcut
end

local function FeatureSwitchMeta(group, sectionId)
    if group.id == "macroBuilder" then
        return P.Meta("suite_macros", group.id, group.switch, "setting")
    end
    return P.Meta(V.GetFeaturePage(group), group.id, group.switch, "setting", sectionId)
end

local function PrepareFeatureSwitch(toggle, group)
    HM.SetSearchTargetPrepare(toggle, function()
        if group.id == "macroBuilder" then
            P.MacroPage.PrepareSearch("consumable")
            return P.Suite.Menu.Open("suite_macros")
        end
        return group.reveal(true) ~= nil
    end)
end

local function BindFeatureSwitch(ctx, group, sectionId, onChanged, toggle, body)
    local meta = FeatureSwitchMeta(group, sectionId)
    meta.keywords = FeatureKeywords(group, true)
    local function GetEnabled() return GroupEnabled(group) end
    local function SetEnabled(value)
        if P.Combat() then return end
        onChanged(group)
        SetGroupEnabled(group, value == true)
    end
    if body then
        toggle = P.BindSectionSwitch(ctx, body, {
            label = Tr(group.title), displayLabel = Tr("Enable"), get = GetEnabled, set = SetEnabled, meta = meta,
        })
    else
        P.M.BindBoolWidget(ctx, toggle, GetEnabled, SetEnabled, meta)
    end
    local searchMeta = FeatureSwitchMeta(group, sectionId)
    searchMeta.pageKey, searchMeta.kind = V.GetFeaturePage(group), "toggle"
    searchMeta.label, searchMeta.keywords = Tr(group.title), meta.keywords
    P.M.RegisterSearchWidget(toggle, searchMeta)
    PrepareFeatureSwitch(toggle, group)
    P.M.AddTooltip(toggle, Tr(group.title), P.QoLHelpText(group.sections[1]), { hook = true })
    P.M.TrackRefresh(ctx, function() P.W.SetControlEnabled(toggle, not P.Combat()) end)
    return FeatureKeywords(group), toggle
end

V.GroupEnabled = GroupEnabled
V.FeatureSectionId, V.FeatureRules = FeatureSectionId, FeatureRules
V.BindFeatureSwitch, V.BuildFeatureDetails = BindFeatureSwitch, BuildFeatureDetails
function V.HasDetails(group, rules)
    return #rules > 0 or group.id == "mailTemplates" or group.id == "macroBuilder"
        or EDIT_ELEMENTS[group.id] ~= nil or group.id == "xpBar"
        or group.id == "innervateCue" or group.id == "loadoutReminder"
end

local function Build(ctx)
    P.SortQualityOfLifeCategories()
    local builder = P.W.PageBuilder(ctx)
    V.BuildSelected(ctx, builder, V.GetCategories(), PAGE)
end

P.RegisterPage({ key = PAGE, label = "Quality of Life", title = "Quality of Life", build = Build, notice = P.BuildGraphicsNotice, icon = { 7, 1 },
    nav = "general", navOrder = 1,
    aliases = { "qol", "qualityoflife", "quality_of_life", "actiontracker", "actions", "casts", "merchant",
        "itemlevel", "vault", "lootspec", "tooltipids", "loot", "quests", "combatlog", "logging", "comfort",
        "experience", "xpbar", "xp", "innervate", "whisper", "durability", "repairwarning", "battleres", "brez",
        "combatres", "skyriding", "vigor", "secondwind", "groupfinder", "keys", "keystone", "bloodlust" } })
