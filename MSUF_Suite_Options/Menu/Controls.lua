local _, P = ...
local S, M, W, T, Tr = P.S, P.M, P.W, P.T, P.Tr
local Controller = P.Suite.Client

-- The Skinning declarations feed the cold search index and visible controls.
-- Collection reads metadata only: callbacks and widget builders never run.
function P.SkinSearchRow(ctx, row, section, title, help)
    local keywords = { "suite", "skinning", "skin", row.searchLabel or row.label, title }
    for _, value in ipairs(type(row.values) == "table" and row.values or {}) do
        keywords[#keywords + 1] = value.text
    end
    ctx.searchRows[#ctx.searchRows + 1] = {
        pageKey = "suite_skin", suiteModuleId = "skin", label = row.label,
        kind = row.kind, section = title, keywords = keywords, help = help,
        settingKey = row.kind ~= "color" and row.settingKey or nil,
        controlId = row.kind ~= "color" and row.controlId or nil,
        sectionId = section or row.sectionId,
        anchorText = row.kind == "color" and title or nil,
    }
end

function P.SkinSearchButton(ctx, parent, label, x, y, width, onClick, enabled, meta)
    if not ctx.searchRows then return P.Button(ctx, parent, label, x, y, width, onClick, enabled, meta) end
    local row = { label = Tr(label), searchLabel = label, kind = "button",
        controlId = meta and meta.controlId, sectionId = meta and meta.sectionId }
    P.SkinSearchRow(ctx, row)
end

-- Slider increments are a UI choice. Keep catalog steps intact so existing
-- fractional profile values are not rounded during database normalization.
local function Whole(value)
    return type(value) == "number" and value == math.floor(value)
end

function P.SliderStep(minimum, maximum, default, declaredStep)
    if Whole(minimum) and Whole(maximum) and (default == nil or Whole(default))
        and not ((declaredStep or 1) < 1 and maximum - minimum <= 2) then
        return 1
    end
    return 0.01
end

-- Settings store colors as six hex digits (MSUF_Suite/Core/Platform.lua).
P.RGB = P.Suite.RGB

local function Byte(value)
    return math.floor(math.max(0, math.min(1, tonumber(value) or 0)) * 255 + 0.5)
end

local function Hex(r, g, b)
    return string.format("%02x%02x%02x", Byte(r), Byte(g), Byte(b))
end

-- MSUF's own font list (keys or paths) plus the inherited choice; a saved font
-- that is no longer installed stays selectable so it is not silently lost.
function P.FontValues(selected, defaultLabel)
    local values = { { value = "", text = Tr(defaultLabel or "MSUF global font (default)") } }
    local seen = { [""] = true }
    local source = M.GlobalPage and M.GlobalPage.FontValues and M.GlobalPage.FontValues(false) or {}
    for _, entry in ipairs(source) do
        if entry.value ~= nil and not seen[entry.value] then
            values[#values + 1] = { value = entry.value, text = entry.text }
            seen[entry.value] = true
        end
    end
    if type(selected) == "string" and selected ~= "" and not seen[selected] then
        values[#values + 1] = { value = selected, text = Tr("Unavailable font") .. ": " .. selected }
    end
    return values
end

function P.TextureValues(selected)
    local items = M.StatusBarTextureItems and M.StatusBarTextureItems(Tr("Module default")) or {}
    local values, seen = {}, {}
    if not (items[1] and items[1].value == "") then
        values[1] = { value = "", text = Tr("Module default") }
        seen[""] = true
    end
    for _, entry in ipairs(items) do
        if entry.value ~= nil and not seen[entry.value] then
            values[#values + 1] = entry
            seen[entry.value] = true
        end
    end
    if type(selected) == "string" and selected ~= "" and not seen[selected] then
        values[#values + 1] = { value = selected, text = Tr("Unavailable texture") .. ": " .. selected }
    end
    return values
end

local function ChoiceValues(rule)
    if not rule._suiteMenuValues then
        local values = {}
        for i = 1, #rule.choices do
            values[i] = { value = i, text = Tr(rule.choices[i]), icon = rule.choiceIcons and rule.choiceIcons[i] }
        end
        rule._suiteMenuValues = values
    end
    return rule._suiteMenuValues
end

-- Pages may mark single choices unavailable on this client.
local function GatedChoiceValues(base, gate)
    local values = {}
    return function()
        for i = 1, #base do
            values[i] = values[i] or { value = base[i].value, text = base[i].text }
            values[i].disabled = not gate(i)
        end
        return values
    end
end

local function DecimalFormat(value)
    if value ~= math.floor(value) then return string.format("%.2f", value) end
    return tostring(value)
end

-- Only deliberate, useful values appear in a collapsed section. Priority is
-- independent of grid order; offsets, shadows and technical rendering options
-- stay inside the section. Numbered keys share one policy across selected scopes.
local SUMMARY_KEYS = {
    chat = "look fontSize tabFontSize tabAccent panelAlpha sidebarPanel sidebarWidth inputPanel inputAlpha copyMessages",
    actionbars = "look barVisibility barButtons barRows barCooldownSize barKeybind barBackground barBackgroundAlpha pickupModifier cooldownNumbers rangeColoring iconZoom borderSize fontSize",
    bags = "look windowScale windowMoved reagentWindowMoved showItemLevel itemLevelSize backgroundOpacity",
    damageMeter = "look wType wSession windowCount visibility barHeight iconStyle leftSize rightSize bgAlpha headerHeight hoverTooltip tooltipRows timer combatTime",
    dataTexts = "look barLook barWidth barHeight barVisibility barFontSize fontSize textAlign backgroundEnabled backgroundOpacity trackAltGold hideBlizzardBagBar",
    minimap = "stylePreset size point hoverResize hoverWidth shape borderSize styleTexture styleScale styleGlow styleGlowAlpha styleBackdrop styleBackdropAlpha visibility rotate elementRow elementSize showLanding landingIcon collectButtons drawerColumns",
    objectives = "width height entrySize objectiveSize colorStyle backgroundOpacity",
    runSummary = "width scale titleSize detailSize autoHide colorStyle backgroundOpacity",
    announcements = "duration anchor titleSize subtitleSize colorStyle backgroundOpacity",
    buffReminders = "size columns remindBeforeMinutes instancesOnly point classBuff",
    nameplates = "look nativeStyle nativeSize enemyTextMode enemyNameSize friendlyNamesOnly friendlyNameSize enemyAuraMode friendlyAuraMode personalPower",
    skin = "theme.look theme.shellOpacity theme.panelOpacity geometry.family geometry.controlShape icons.windowActions.style theme.iconBorderStyle font.enabled font.face icons.microMenu.preset icons.microMenu.scale",
}
for id, keys in pairs(SUMMARY_KEYS) do
    local ranks, rank = {}, 0
    for key in keys:gmatch("%S+") do rank = rank + 1; ranks[key] = rank end
    SUMMARY_KEYS[id] = ranks
end

function P.SummaryPriority(id, key)
    local ranks = SUMMARY_KEYS[id]
    return ranks and ranks[(key or ""):gsub("^bar%d+", "bar"):gsub("^w%d+", "w")]
end

-- One W.SettingsRows row for a catalog rule. `keyFn` maps the template key to
-- the live key when shared controls edit the selected bar or window.
function P.RuleRow(pageKey, id, rule, keyFn, sectionId)
    if rule.color and pageKey ~= "colors" then return nil end
    local function Key() return keyFn and keyFn(rule.key) or rule.key end
    local row = P.Meta(pageKey, id, rule.key, "setting", sectionId)
    row.id, row.label = rule.key, Tr(rule.label)
    row.summary = not rule.font and not rule.texture and not rule.color and P.SummaryPriority(id, rule.key)
    row.summaryEnabled = function() return P.RuleEnabled(id, rule, keyFn) end
    if rule.color then
        row.kind = "color"
        row.get = function() return P.RGB(P.Get(id, Key())) end
        row.set = function(r, g, b) P.Set(id, Key(), Hex(r, g, b)) end
    elseif rule.font or rule.texture then
        row.kind = "dropdown"
        local list = rule.font and P.FontValues or P.TextureValues
        row.values = function()
            local selected = P.Get(id, Key())
            local values = list(selected == "__BLIZZARD_CHAT_FONT__" and "" or selected, rule.defaultLabel)
            if rule.font and id == "chat" then
                values[#values + 1] = { value = "__BLIZZARD_CHAT_FONT__", text = Tr("Blizzard chat font") }
            end
            return values
        end
        row.get = function() return P.Get(id, Key()) end
        row.set = function(value) P.Set(id, Key(), value or "") end
    elseif rule.choices then
        row.kind, row.values = "dropdown", ChoiceValues(rule)
        local gates = P.ChoiceGates[id]
        local gate = gates and gates[rule.key]
        if gate then row.values = GatedChoiceValues(row.values, gate) end
        row.get = function() return P.Get(id, Key()) end
        row.set = function(value) P.Set(id, Key(), tonumber(value) or rule.default) end
    elseif type(rule.default) == "boolean" then
        row.kind = "toggle"
        row.get = function() return P.Get(id, Key()) == true end
        row.set = function(value) P.Set(id, Key(), value == true) end
    elseif type(rule.default) == "number" then
        row.kind = "slider"
        row.min, row.max, row.default = rule.min, rule.max, rule.default
        row.step = P.SliderStep(rule.min, rule.max, rule.default, rule.step)
        row.roundStep = row.step >= 1
        if id == "chat" and (rule.key == "tabFontSize" or rule.key == "fontSize") then
            row.summaryLabel = Tr("Font size")
            row.valueBoxWidth = 72
            row.format = function(value)
                if (tonumber(value) or 0) <= 0 then return Tr("Default") end
                return tostring(math.floor((tonumber(value) or 0) + 0.5))
            end
        end
        -- Old half-step values stay visible until the slider is moved.
        if not row.format and row.step == 1 and (rule.step or 1) < 1 then row.format = DecimalFormat end
        row.get = function() return P.Get(id, Key()) end
        row.set = function(value) P.Set(id, Key(), tonumber(value) or rule.default) end
    else
        return nil
    end
    return row
end

-- Enables/disables every control of a grid from its rule on each page refresh.
function P.GateControls(ctx, id, entries, keyFn)
    local prepare = P.SearchPreparers[id]
    if prepare then
        for _, entry in ipairs(entries) do
            if entry.widget then
                local rule = entry.rule
                entry.widget._msuf2PrepareExactSearchTarget = function() prepare(rule) end
            end
        end
    end
    if W.SetControlDisabledReason then
        for _, entry in ipairs(entries) do
            if entry.widget then
                local rule = entry.rule
                W.SetControlDisabledReason(entry.widget, function()
                    local _, reason = P.RuleEnabled(id, rule, keyFn, true)
                    return reason
                end)
            end
        end
    end
    M.TrackRefresh(ctx, function()
        for i = 1, #entries do
            local entry = entries[i]
            if entry.widget then W.SetControlEnabled(entry.widget, P.RuleEnabled(id, entry.rule, keyFn)) end
        end
    end)
end

-- Adds a rule grid (two columns) plus full-width text inputs to `parent`,
-- starting at y. Returns the next free y and the list of {rule, widget}.
function P.RuleGrid(ctx, parent, pageKey, id, rules, y, width, keyFn, sectionId, columns)
    local rows, pending, strings = {}, {}, {}
    for _, rule in ipairs(rules) do
        -- Suite pages edit colors from their section shortcut. Only the
        -- canonical MSUF Colors page renders inline color rows.
        if not rule.hidden and (pageKey == "colors" or not rule.color) then
            local row = P.RuleRow(pageKey, id, rule, keyFn, sectionId)
            if row then
                rows[#rows + 1] = row
                pending[#pending + 1] = rule
            elseif type(rule.default) == "string" then
                strings[#strings + 1] = rule
            end
        end
    end
    local entries = {}
    if #rows > 0 then
        local grid = W.SettingsRows(ctx, parent, {
            x = 16, y = y, width = width, columns = columns or (width >= 560 and 2 or 1), rows = rows,
        })
        for _, rule in ipairs(pending) do entries[#entries + 1] = { rule = rule, widget = grid.controls[rule.key] } end
        y = grid.bottomY
    end
    for _, rule in ipairs(strings) do
        local function Key() return keyFn and keyFn(rule.key) or rule.key end
        local input = M.BindTextInputAt(ctx, parent, Tr(rule.label), 16, y, width,
            function() return P.Get(id, Key()) end, function(value) P.Set(id, Key(), value or "") end, true,
            P.Meta(pageKey, id, rule.key, "setting", sectionId))
        if input.SetMaxLetters and rule.maxLength then input:SetMaxLetters(rule.maxLength) end
        entries[#entries + 1] = { rule = rule, widget = input }
        y = y - 58
    end
    P.GateControls(ctx, id, entries, keyFn)
    P.AttachRowsSummary(ctx, parent, rows)
    return y, entries
end

-- A collapsed section still answers what it currently does. Read the same
-- declared getters as its controls, including the selected bar/window scope.
function P.AttachRowsSummary(ctx, body, rows)
    if not W.SetCollapsibleSummary or not body._msuf2CollapsibleEntry
        or body._msufSuiteSummary or body._msufSuiteSkipSummary then return end
    local selected = {}
    for _, row in ipairs(rows) do
        if type(row.summary) == "number" and row.get then selected[#selected + 1] = row end
    end
    if #selected == 0 then return end
    table.sort(selected, function(a, b) return a.summary < b.summary end)
    body._msufSuiteSummary = true
    W.SetCollapsibleSummary(body, "")
    local previous
    M.TrackRefresh(ctx, function()
        local parts = {}
        for _, row in ipairs(selected) do
            if #parts == 2 then break end
            if not row.summaryEnabled or row.summaryEnabled() then
                local value = row.get()
                local shown = row.format and row.format(value) or tostring(value or "")
                if row.kind == "dropdown" then
                    local values = type(row.values) == "function" and row.values() or row.values
                    for _, item in ipairs(values or {}) do
                        if item.value == value then shown = item.text; break end
                    end
                elseif row.kind == "toggle" then shown = Tr(value and "On" or "Off")
                elseif not row.format and type(value) == "number" then shown = DecimalFormat(value) end
                parts[#parts + 1] = (row.summaryLabel or row.label or "") .. ": " .. tostring(shown or "")
            end
        end
        local text = table.concat(parts, " \194\183 ")
        if previous ~= text then W.SetCollapsibleSummary(body, text); previous = text end
    end)
end

-- Suite accordions use this shortcut as their sole color entry point.
function P.AttachRuleColors(body, title, id, rules, keyFn, isRelevant)
    if not (body and W.AttachContextColorShortcut) then return end
    local colors = {}
    for _, rule in ipairs(rules or {}) do
        if rule.color and not rule.hidden then colors[#colors + 1] = rule end
    end
    if #colors == 0 then return end
    local shortcut = W.AttachContextColorShortcut(body, {
        title = Tr(title),
        maxTargets = #colors,
        getTargets = function()
            local targets = {}
            for _, rule in ipairs(colors) do
                local function Key() return keyFn and keyFn(rule.key) or rule.key end
                targets[#targets + 1] = {
                    label = Tr(rule.label),
                    sourceSettingKey = "msufsuite." .. id .. "." .. rule.key,
                    settingKey = "msufsuite." .. id .. "." .. Key(),
                    isEnabled = isRelevant and function() return isRelevant(rule) end or nil,
                    get = function() return P.RGB(P.Get(id, Key())) end,
                    set = function(r, g, b) P.Set(id, Key(), Hex(r, g, b)) end,
                }
            end
            return targets
        end,
    })
    -- Later bound swatches must not replace this complete, curated list.
    if shortcut then shortcut._msuf2BoundColorShortcut = nil end
    return shortcut
end

-- A collapsible section built from catalog rules, with optional help text.
-- opts: help, open, keyFn, columns, onEnsureVisible, extra(body, y) -> y,
-- copy (see P.AttachSectionReset)
function P.RuleSection(ctx, b, pageKey, id, sectionId, title, rules, opts)
    opts = opts or {}
    local body = b:CollapsibleSection(sectionId, title, 120, opts.open)
    local width = math.max(240, (body._msuf2Width or b.width or 720) - 32)
    local y = -18
    if opts.help then
        local help = P.Description(body, opts.help, 16, y, width, title)
        y = y - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 12
    end
    local entries
    y, entries = P.RuleGrid(ctx, body, pageKey, id, rules, y, width, opts.keyFn, sectionId, opts.columns)
    if opts.extra then y = opts.extra(body, y, width) or y end
    P.AttachRuleColors(body, title, id, rules, opts.keyFn)
    P.AttachSectionReset(ctx, body, title, function()
        return P.ResetRules(id, rules, opts.keyFn, opts.resetKeys)
    end, opts.copy)
    local entry = body._msuf2CollapsibleEntry
    if entry and opts.onEnsureVisible then entry._msuf2EnsureVisible = opts.onEnsureVisible end
    P.FinishBody(b, body, y)
    return body, entries
end

-- The Suite looks as one-click buttons for a module's "Choose a look"
-- section. Returns an `extra` builder for P.RuleSection; `after(body, y,
-- width)` may add more below the buttons.
local LOOK_BUTTONS = {
    { 1, "Midnight Blue" }, { 2, "Midnight Dark" },
    { 3, "MSUF Forever" }, { 5, "Clean Modern" },
}

function P.LookPresetButtons(ctx, pageKey, id, sectionId, after)
    return function(body, y, width)
        local gap = 8
        local buttonWidth = math.floor((width - 3 * gap) / 4)
        local buttons = {}
        for index, entry in ipairs(LOOK_BUTTONS) do
            local value, name = entry[1], entry[2]
            local button = T.Button(body, Tr(name), buttonWidth, 26)
            button:SetPoint("TOPLEFT", body, "TOPLEFT", 16 + (index - 1) * (buttonWidth + gap), y)
            button:SetScript("OnClick", function()
                if not P.Combat() then P.Set(id, "look", value) end
            end)
            if M.RegisterControlMetadata then
                M.RegisterControlMetadata(button, P.Meta(pageKey, id, "look." .. value, "action", sectionId),
                    Tr(name), "button")
            end
            buttons[index] = button
        end
        M.TrackRefresh(ctx, function()
            local look = P.Get(id, "look")
            local enabled = P.RuleEnabled(id, P.catalog[id].rules.look)
            for index = 1, #buttons do
                buttons[index]:SetAlpha(look == LOOK_BUTTONS[index][1] and 1 or 0.65)
                buttons[index]:SetEnabled(enabled)
            end
        end)
        y = y - 38
        if after then return after(body, y, width) end
        return y
    end
end

-- A reset writes the exact catalog keys owned by an accordion. Dynamic
-- sections resolve their selected bar/window only when the action is clicked.
function P.ResetRules(id, rules, keyFn, extraKeys)
    if P.Combat() then return false end
    local values = {}
    for _, rule in ipairs(rules or {}) do
        local key = keyFn and keyFn(rule.key) or rule.key
        local live = P.catalog[id].rules[key]
        if live then values[key] = live.default end
    end
    for _, key in ipairs(extraKeys or {}) do
        local live = P.catalog[id].rules[key]
        if live then values[key] = live.default end
    end
    local look = P.catalog[id].look
    if look and values[look.key] ~= nil then
        local preset = look.presets and look.presets[values[look.key]]
        for key, value in pairs(preset or {}) do values[key] = value end
    end
    if not next(values) then return false end
    local ok = P.WithHistory("Reset section", "suite:" .. id .. ".section-reset", function()
        return S.ResetKeys(id, values)
    end)
    if ok then P.Refresh() end
    return ok
end

local function ModuleControls(id)
    local spec = P.catalog[id]
    return spec.getControls and spec.getControls(S.Config(id)) or spec.controls
end

function P.ResetPrefix(id, prefix)
    local rules = {}
    for _, rule in ipairs(ModuleControls(id)) do
        if rule.key:sub(1, #prefix) == prefix
            and not rule.key:sub(#prefix + 1, #prefix + 1):match("%d") then
            rules[#rules + 1] = rule
        end
    end
    return P.ResetRules(id, rules)
end

-- Same header action pattern as the GF/UF accordions. The color shortcut in
-- the body remains available for color sections.
-- copy (optional) adds "Copy section" below the reset, like the UF/GF popup:
--   source() -> id, sourceLabel(id) -> text, targets(id) -> dropdown items,
--   run(source, target) -> ok, label: dropdown title,
--   targetOff(id) -> true keeps a switched-off target listed but locked (offLabel).
local function OffTargetText(text, label)
    text = text .. " - " .. Tr(label or "Disabled")
    local c = T.colors and T.colors.danger
    if not c then return text end
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5), text)
end
-- The "..." button in a section header; the feature switch moves left of it.
local function SectionActionButton(ctx, entry)
    local more = W.TopButton(entry.header, "...", 24, 22)
    if W.StyleSectionActionButton then W.StyleSectionActionButton(more) end
    more:SetPoint("RIGHT", entry.header, "RIGHT", -10, 0)
    more:SetFrameLevel(entry.header:GetFrameLevel() + 4)
    more._msuf2SkipHistoryCheckpoint = true
    entry._msuf2SectionActions = more
    entry._msufSuiteResetButton = more
    entry._msuf2ActionReserve = 34
    if not entry._msuf2UXSummary then
        entry._msuf2ColorSwatchReserve = (entry._msuf2ColorSwatchReserve or 0) + 34
    end
    local function AlignSwitch()
        if entry.featureSwitch then
            entry.featureSwitch:ClearAllPoints()
            entry.featureSwitch:SetPoint("RIGHT", entry.header, "RIGHT", -48, 0)
        end
    end
    AlignSwitch()
    if ctx and M.TrackRefresh then M.TrackRefresh(ctx, AlignSwitch) end
    if entry._msuf2RefreshLayout then entry._msuf2RefreshLayout() end
    return more
end

-- A section's popup state: body, title, header entry, "..." button, the
-- popup once built and the copy source fixed when it opened.
local function ClosePopup(state)
    if state.popup then state.popup:Hide() end
end

local function ShowFeedback(ok, done)
    if M.ShowStatusFeedback then M.ShowStatusFeedback(Tr(ok and done or "Action failed"), ok and "ok" or "danger", 1.5) end
end

-- The source is fixed when the popup opens; Copy refuses once it changed.
local function CopySection(state, target)
    local spec = state.body._msufSuiteSectionCopy
    if P.Combat() or not (spec and target) then return false end
    local source = state.source
    local ok = spec.source() == source and target ~= source
        and not (spec.targetOff and spec.targetOff(target))
        and spec.run(source, target) == true
    ShowFeedback(ok, "Section copied")
    ClosePopup(state)
    return ok
end

-- The destination defaults to the first target that is switched on; with
-- every target off the first one shows marked and Copy locks.
local function RefreshCopyTargets(state, select, copyButton)
    local current = state.body._msufSuiteSectionCopy
    local choices, first = {}, nil
    for _, item in ipairs(current.targets(state.source)) do
        if current.targetOff and current.targetOff(item.value) then
            item = { value = item.value, text = OffTargetText(item.text, current.offLabel),
                translate = false, disabled = true }
        elseif first == nil then
            first = item.value
        end
        choices[#choices + 1] = item
    end
    state.popup.destination = first
    select:SetValues(choices)
    select:SetValue(first or (choices[1] and choices[1].value))
    W.SetControlEnabled(copyButton, first ~= nil)
end

-- "Copy section": the destination dropdown and its button.
local function BuildCopyRow(state, spec)
    local popup = state.popup
    local select = W.Dropdown(popup, Tr(spec.label or "Copy to"), {}, 250)
    W.MoveWidget(select, popup, 14, -76, 250)
    select:SetOnValueChanged(function(value) popup.destination = value end)
    local copyButton = W.TopButton(popup, Tr("Copy section"), 250, 24)
    copyButton:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -132)
    copyButton:SetScript("OnClick", function() CopySection(state, popup.destination) end)
    popup:SetHeight(174)
    popup.RefreshTargets = function() RefreshCopyTargets(state, select, copyButton) end
    popup._msufSuiteCopySection = function(target) return CopySection(state, target) end
end

local function BuildSectionPopup(state, spec)
    local popup = M.CreateMenuPopupPanel(_G.UIParent)
    state.popup = popup
    popup:SetClampedToScreen(true)
    popup:SetSize(288, 82)
    local heading = T.Font(popup, "GameFontHighlight", Tr(state.title), T.colors.text)
    heading:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -12)
    heading:SetWidth(242)
    heading:SetWordWrap(false)
    popup.heading = heading
    local close = W.TopButton(popup, "x", 20, 20)
    close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() ClosePopup(state) end)
    if spec and W.Dropdown and W.MoveWidget then BuildCopyRow(state, spec) end
    local button = W.TopButton(popup, Tr("Reset section"), 250, 24)
    button:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -42)
    button:SetScript("OnClick", function()
        if P.Combat() then return end
        ShowFeedback(state.body._msufSuiteSectionReset(), "Section reset")
        ClosePopup(state)
    end)
    popup._msuf2ResetSection = function() return state.body._msufSuiteSectionReset() end
    state.entry.outer:HookScript("OnHide", function() ClosePopup(state) end)
    Controller.AttachControllerWindow(popup)
    if Controller.isForever then
        popup.SmartNavigationCloseHandler = function() ClosePopup(state); return true end
    end
end

local function ToggleSectionPopup(state)
    if P.Combat() then return end
    local popup = state.popup
    if popup and popup:IsShown() then
        ClosePopup(state)
        return
    end
    local spec = state.body._msufSuiteSectionCopy
    state.source = spec and spec.source() or nil
    if not popup then
        BuildSectionPopup(state, spec)
        popup = state.popup
    end
    if popup.RefreshTargets then popup.RefreshTargets() end
    local title = Tr(state.title)
    popup.heading:SetText(state.source ~= nil and (spec.sourceLabel(state.source) .. " \194\183 " .. title) or title)
    popup:ClearAllPoints()
    popup:SetPoint("TOPRIGHT", state.more, "BOTTOMRIGHT", 0, -4)
    if M.ApplyPopupFramePriority then M.ApplyPopupFramePriority(popup) end
    popup:Show()
    Controller.ResumeControllerWindow(popup)
    Controller.RaiseControllerCursor()
end

function P.AttachSectionReset(ctx, body, title, reset, copy)
    if not body or type(reset) ~= "function" then return end
    body._msufSuiteSectionReset, body._msufSuiteSectionCopy = reset, copy
    local entry = body._msuf2CollapsibleEntry
    if not (entry and entry.header and W.TopButton and M.CreateMenuPopupPanel) then return end
    if entry._msufSuiteResetButton then return entry._msufSuiteResetButton end
    local more = SectionActionButton(ctx, entry)
    local state = { body = body, title = title, entry = entry, more = more }
    more:SetScript("OnClick", function() ToggleSectionPopup(state) end)
    more._msuf2GetSectionPopup = function() return state.popup end
    if M.AddTooltip then M.AddTooltip(more, "Section actions", nil, { hook = true }) end
    return more
end

-- Catalog rules of one section, in declaration order.
function P.SectionRules(id, section, filter)
    local out = {}
    for _, rule in ipairs(ModuleControls(id)) do
        if rule.section == section and rule.key ~= "enabled" and not rule.previewOnly
            and (not filter or filter(rule)) then
            out[#out + 1] = rule
        end
    end
    return out
end

local function SkinColorRow(skin, entry)
    local key = entry[1]
    return {
        id = "skin." .. key,
        kind = "color",
        label = Tr((skin.L and skin.L[entry[2]]) or key),
        get = function()
            local color = skin.Theme.GetColorTable(key)
            return color[1], color[2], color[3], color[4]
        end,
        set = function(r, g, blue, alpha)
            skin.Theme.SetColor(key, r, g, blue, alpha)
            P.Refresh()
        end,
        settingKey = "msufsuite.skin." .. key,
        sectionId = "colors_suite_skin",
    }
end

-- The skin palette joins MSUF Colors once the skin engine is loaded.
local function BuildSkinColors(ctx, b)
    local skin = _G.MapkoSkin
    if not skin and not P.Combat() then
        P.Suite.Skin.EnsureEngine()
        skin = _G.MapkoSkin
    end
    if not (skin and skin.addonName == "MSUF_Suite_Skin" and skin.Theme and skin.ColorOrder) then return end
    local section = b:CollapsibleSection("colors_suite_skin", Tr("Suite skin"), 120, false)
    local width = math.max(240, (section._msuf2Width or b.width or 720) - 32)
    local rows = {}
    for _, entry in ipairs(skin.ColorOrder) do rows[#rows + 1] = SkinColorRow(skin, entry) end
    local grid = W.SettingsRows(ctx, section, { x = 16, y = -18, width = width, columns = 2, rows = rows })
    P.AttachSectionReset(ctx, section, "Suite skin", function()
        if P.Combat() or not skin.Theme.ResetColors then return false end
        local ok = P.WithHistory("Reset Suite skin colors", "suite:skin.colors.reset",
            function() skin.Theme.ResetColors(); return true end)
        if ok then P.Refresh() end
        return ok
    end)
    P.FinishBody(b, section, grid.bottomY)
end

-- The MSUF Colors painter asks for this category lazily. It uses the same
-- bound color rows as Suite pages, so both locations share live values and the
-- native color picker/history path.
function P.BuildColorsCategory(ctx, b)
    -- A refresh pass starts with fresh module availability (Bridge.lua).
    M.TrackRefresh(ctx, P.ForgetAvailability)
    for _, id in ipairs(P.order) do
        local colors = {}
        for _, rule in ipairs(ModuleControls(id)) do
            if rule.color and not rule.hidden then
                local entry = {}
                for key, value in pairs(rule) do entry[key] = value end
                -- Joined text cannot be looked up, so each part translates first.
                entry.label = (rule.sectionTitle and (Tr(rule.sectionTitle) .. " · ") or "") .. Tr(rule.label)
                colors[#colors + 1] = entry
            end
        end
        if #colors > 0 then
            P.RuleSection(ctx, b, "colors", id, "colors_suite_" .. id,
                Tr(P.catalog[id].title), colors, { open = id == "minimap" })
        end
    end
    BuildSkinColors(ctx, b)
end

-- Standard module header card: enable switch, live status and actions.
-- actions: list of { label, onClick, enabled(optional), key = id }.
function P.ModuleCard(ctx, b, pageKey, id, actions, opts)
    opts = opts or {}
    local spec = P.catalog[id]
    local sectionId = pageKey .. "_" .. id .. "_module"
    local title = opts.title or "Basics"
    local body = b:CollapsibleSection(sectionId, Tr(title), 120, true)
    local width = math.max(240, (body._msuf2Width or b.width or 720) - 32)
    local toggle = W.SectionSwitch(body, Tr("Enable"), Tr("Enable"))
    M.BindBoolWidget(ctx, toggle,
        function() return P.Get(id, "enabled") == true end,
        function(value) P.Set(id, "enabled", value == true) end,
        P.Meta(pageKey, id, "enabled", "setting", sectionId))
    local status = P.Text(body, "", 16, -18, width, T.colors.text)
    local description = P.Description(body, spec.description, 16, -42, width, title)
    local y = -42 - math.max(14, math.ceil(description:GetStringHeight() or 14)) - 14
    local columns = width >= 560 and 3 or 2
    local buttonWidth = math.floor((width - (columns - 1) * 12) / columns)
    for i, action in ipairs(actions or {}) do
        local column = (i - 1) % columns
        if column == 0 and i > 1 then y = y - 34 end
        P.Button(ctx, body, action[1], 16 + column * (buttonWidth + 12), y, buttonWidth, action[2],
            action[3] or function() return P.Available(id) and P.Get(id, "enabled") end,
            P.Meta(pageKey, id, "action." .. (action.key or i), "action", sectionId))
    end
    if actions and #actions > 0 then y = y - 38 end
    if opts.help then
        local help = P.Description(body, opts.help, 16, y, width, title)
        y = y - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 12
    end
    if opts.rules then
        y = P.RuleGrid(ctx, body, pageKey, id, opts.rules, y, width, nil, sectionId)
        P.AttachRuleColors(body, title, id, opts.rules)
    end
    M.TrackRefresh(ctx, function()
        local ok, why = P.Available(id)
        -- The preference remains editable even when this client cannot run the
        -- module. S.Apply still enforces Availability before starting it.
        W.SetControlEnabled(toggle, not P.Combat())
        status:SetText(P.StatusText(id))
        local entry = body._msuf2CollapsibleEntry
        if entry and entry.label then
            local suffix = not ok and (" - " .. P.Suite.StatusText(why or "Unavailable on this client", Tr))
                or not P.Get(id, "enabled") and Tr(" - Off") or ""
            entry.label:SetText(Tr(title) .. suffix)
        end
    end)
    P.AttachSectionReset(ctx, body, title, function()
        return P.ResetRules(id, opts.rules or {}, nil, { "enabled" })
    end)
    P.FinishBody(b, body, y)
    return body
end
