local _, P = ...
local Suite, S, M, W, Tr, HM = P.Suite, P.S, P.M, P.W, P.Tr, P.HM
local ID, PAGE, SECTION = "actionbars", "suite_actionbars", "suite_actionbars_bar_paging_guided"
local NO_RULE, LAST_MANUAL_PAGE, LAST_FORM_PAGE = 0, 6, 11
local TRIGGERS = {
    { value = "[mod:shift]", modifier = "Shift" },
    { value = "[mod:ctrl]", modifier = "Ctrl" },
    { value = "[mod:alt]", modifier = "Alt" },
    { value = "[@target,harm]", label = "Hostile target" },
    { value = "[@target,help]", label = "Friendly target" },
    { value = "[combat]", label = "In combat" },
    { value = "[mounted]", label = "Mounted" },
}

local Page = {}
P.ActionBarPagingPage = Page

local function TriggerChoices()
    local choices, labels = {}, {}
    for _, trigger in ipairs(TRIGGERS) do
        local label = trigger.modifier and Tr("Hold %s"):format(Tr(trigger.modifier)) or Tr(trigger.label)
        choices[#choices + 1] = { value = trigger.value, text = label, translate = false }
        labels[trigger.value] = label
    end
    return choices, labels
end

-- Editable rules are an ordered list of the supported triggers, each used once.
-- Compound conditions, unconditional fallbacks and other macro syntax stay in the manual editor.
local function ReadRules(text, labels)
    if not text:find("%S") then return {} end
    local parsed = Suite.ParseActionBarPaging(text)
    if not parsed or parsed.final then return nil end
    local rules, seen = {}, {}
    for clause in parsed.driver:gmatch("[^;]+") do
        local trigger, page = clause:match("^%s*(%b[]) (%d+)$")
        if not trigger or not labels[trigger] or seen[trigger] then return nil end
        rules[#rules + 1] = { trigger = trigger, page = tonumber(page) }
        seen[trigger] = true
    end
    return rules
end

local function PageLabel(page, index)
    if page == Suite.ActionBarHomePages[index] then return Tr("Page %d (normal page)"):format(page) end
    if index == 1 and page > LAST_MANUAL_PAGE then return Tr("Page %d (form page)"):format(page) end
    return Tr("Page %d"):format(page)
end

local function ChoicesFor(index)
    local choices = { { value = NO_RULE, text = Tr("No rule"), translate = false } }
    local home = Suite.ActionBarHomePages[index]
    if not home then return choices end
    local config = S.Config(ID)
    local claims = Suite.ActionBarPageClaims(config)
    local last = index == 1 and LAST_FORM_PAGE or math.max(LAST_MANUAL_PAGE, home)
    for page = 1, last do
        if page == home or page >= 2 and page <= (index == 1 and LAST_FORM_PAGE or LAST_MANUAL_PAGE) then
            local allowed, reason, a, b = Suite.ActionBarPagingPageAllowed(config, index, page, claims)
            choices[#choices + 1] = { value = page, text = PageLabel(page, index), translate = false,
                disabled = not allowed, tooltip = not allowed and Tr(reason):format(a, b) or nil }
        end
    end
    return choices
end

local function Find(rules, trigger)
    for index, rule in ipairs(rules or {}) do
        if rule.trigger == trigger then return index, rule.page end
    end
end

local function UpdatedText(rules, trigger, page)
    local match = Find(rules, trigger)
    local clauses = {}
    for index, rule in ipairs(rules) do
        local target = index == match and page or rule.page
        if target ~= NO_RULE then clauses[#clauses + 1] = rule.trigger .. " " .. target end
    end
    if not match and page ~= NO_RULE then clauses[#clauses + 1] = trigger .. " " .. page end
    return table.concat(clauses, "; ")
end

local function Status(rules, labels, index)
    if not Suite.ActionBarHomePages[index] then return Tr("Custom paging is not available for this bar.") end
    if not rules then return Tr("Edit this bar's rule under Macro conditions.") end
    if #rules == 0 then return Tr("No page switching rules set.") end
    local lines = {}
    local config = S.Config(ID)
    local parsed, why, a, b = Suite.ActionBarPaging(config, index)
    if parsed == false then
        lines[1] = Tr("This bar is off; its paging applies once it is on.")
    elseif not parsed then
        lines[1] = Tr("Not applied: %s"):format(Tr(why):format(a, b))
    end
    for _, rule in ipairs(rules) do
        lines[#lines + 1] = labels[rule.trigger] .. " \226\134\146 " .. PageLabel(rule.page, index)
    end
    return table.concat(lines, "\n")
end

local function Editor(ctx, builder, body, selected)
    local width = math.max(240, (HM.GetSectionWidth(body) or builder.width or 720) - 32)
    local title = "Switch the actions on this bar when a condition is met. The first matching rule wins."
    local help = P.Description(body, title, 16, -18, width)
    local y = -30 - math.max(14, math.ceil(help:GetStringHeight() or 14))
    local wide = width >= 460
    local cell = wide and math.floor((width - 12) / 2) or width
    local targetX, targetY = wide and 28 + cell or 16, wide and y or y - 52
    local triggerChoices, labels = TriggerChoices()
    local trigger = triggerChoices[1].value
    local cachedText, rules
    local function Key() return "bar" .. selected() .. "Paging" end
    local function Read()
        local text = P.Get(ID, Key()) or ""
        if text ~= cachedText then
            cachedText, rules = text, ReadRules(text, labels)
        end
        return rules
    end
    local function Enabled()
        local rule = P.catalog[ID].rules[Key()]
        return rule and not rule.hidden and Read() ~= nil and P.RuleEnabled(ID, rule)
    end
    local function TargetPage()
        local _, page = Find(Read(), trigger)
        return page or NO_RULE
    end
    local function SetPage(page)
        if not Enabled() or type(page) ~= "number" or page == TargetPage() then return end
        if page ~= NO_RULE then
            local config = S.Config(ID)
            if not Suite.ActionBarPagingPageAllowed(config, selected(), page, Suite.ActionBarPageClaims(config)) then return end
        end
        P.Set(ID, Key(), UpdatedText(Read(), trigger, page))
    end
    local target
    local condition = M.BindDropdownAt(ctx, body, Tr("When to switch"), 16, y, triggerChoices, cell,
        function() return trigger end, function(value)
            if not labels[value] then return end
            trigger = value
            target:SetValue(TargetPage())
        end, P.Meta(PAGE, ID, "paging.trigger", "ephemeral", SECTION))
    target = M.BindDropdownAt(ctx, body, Tr("Switch to page"), targetX, targetY,
        function() return ChoicesFor(selected()) end, cell, TargetPage, SetPage,
        P.Meta(PAGE, ID, "paging.destination", "ephemeral", SECTION))
    P.StyleMenuControl(condition)
    P.StyleMenuControl(target)
    local statusY = targetY - 54
    local status = P.Text(body, "", 16, statusY, width)
    local lastBottom
    local function Refresh()
        local enabled = Enabled() and true or false
        W.SetControlEnabled(condition, enabled)
        W.SetControlEnabled(target, enabled)
        P.SetTranslatedText(status, Status(Read(), labels, selected()))
        local bottom = statusY - math.max(14, math.ceil(status:GetStringHeight() or 14))
        if lastBottom ~= bottom then
            lastBottom = bottom
            P.FinishBody(builder, body, bottom)
        end
    end
    M.TrackRefresh(ctx, Refresh)
    Refresh()
end

function Page.Build(ctx, builder, selected)
    P.LazySection(builder, SECTION, Tr("Paging for the selected bar"), true, {
        content = function(body) Editor(ctx, builder, body, selected) end,
    })
end
