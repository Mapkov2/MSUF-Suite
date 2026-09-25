local _, P = ...
local S, M, W, T, Tr = P.S, P.M, P.W, P.T, P.Tr

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

function P.RGB(hex)
    if type(hex) ~= "string" or #hex ~= 6 then return 1, 1, 1 end
    return (tonumber(hex:sub(1, 2), 16) or 255) / 255,
        (tonumber(hex:sub(3, 4), 16) or 255) / 255,
        (tonumber(hex:sub(5, 6), 16) or 255) / 255
end

local function Byte(value)
    return math.floor(math.max(0, math.min(1, tonumber(value) or 0)) * 255 + 0.5)
end

local function Hex(r, g, b)
    return string.format("%02x%02x%02x", Byte(r), Byte(g), Byte(b))
end

-- MSUF's own font list (keys or paths) plus the native choice; a saved font
-- that is no longer installed stays selectable so it is not silently lost.
function P.FontValues(selected, defaultLabel)
    local values = { { value = "", text = Tr(defaultLabel or "Native font") } }
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
        for i = 1, #rule.choices do values[i] = { value = i, text = Tr(rule.choices[i]) } end
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

-- One W.SettingsRows row for a catalog rule. `keyFn` maps the template key to
-- the live key when shared controls edit the selected bar or window.
function P.RuleRow(pageKey, id, rule, keyFn, sectionId)
    if rule.color and pageKey ~= "colors" then return nil end
    local function Key() return keyFn and keyFn(rule.key) or rule.key end
    local row = P.Meta(pageKey, id, rule.key, "setting", sectionId)
    row.id, row.label = rule.key, Tr(rule.label)
    if rule.color then
        row.kind = "color"
        row.get = function() return P.RGB(P.Get(id, Key())) end
        row.set = function(r, g, b) P.Set(id, Key(), Hex(r, g, b)) end
    elseif rule.font or rule.texture then
        row.kind = "dropdown"
        local list = rule.font and P.FontValues or P.TextureValues
        row.values = function() return list(P.Get(id, Key()), rule.defaultLabel) end
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
        -- Old half-step values stay visible until the slider is moved.
        if row.step == 1 and (rule.step or 1) < 1 then row.format = DecimalFormat end
        row.get = function() return P.Get(id, Key()) end
        row.set = function(value) P.Set(id, Key(), tonumber(value) or rule.default) end
    else
        return nil
    end
    return row
end

-- Enables/disables every control of a grid from its rule on each page refresh.
function P.GateControls(ctx, id, entries, keyFn)
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
        local grid = W.SettingsRows(ctx, parent, { x = 16, y = y, width = width, columns = columns or 2, rows = rows })
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
    return y, entries
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
-- opts: help, open, keyFn, columns, onEnsureVisible, extra(body, y) -> y
function P.RuleSection(ctx, b, pageKey, id, sectionId, title, rules, opts)
    opts = opts or {}
    local body = b:CollapsibleSection(sectionId, title, 120, opts.open)
    local width = math.max(240, (body._msuf2Width or b.width or 720) - 32)
    local y = -18
    if opts.help then
        local help = P.Text(body, opts.help, 16, y, width)
        y = y - math.max(14, math.ceil(help:GetStringHeight() or 14)) - 12
    end
    local entries
    y, entries = P.RuleGrid(ctx, body, pageKey, id, rules, y, width, opts.keyFn, sectionId, opts.columns)
    if opts.extra then y = opts.extra(body, y, width) or y end
    P.AttachRuleColors(body, title, id, rules, opts.keyFn)
    P.AttachSectionReset(ctx, body, title, function()
        return P.ResetRules(id, rules, opts.keyFn, opts.resetKeys)
    end)
    local entry = body._msuf2CollapsibleEntry
    if entry and opts.onEnsureVisible then entry._msuf2EnsureVisible = opts.onEnsureVisible end
    P.FinishBody(b, body, y)
    return body, entries
end

-- The three Suite looks as one-click buttons for a module's "Choose a look"
-- section. Returns an `extra` builder for P.RuleSection; `after(body, y,
-- width)` may add more below the buttons.
local LOOK_NAMES = { "Midnight Blue", "Midnight Dark", "MSUF Forever" }

function P.LookPresetButtons(ctx, pageKey, id, sectionId, after)
    return function(body, y, width)
        local gap = 8
        local buttonWidth = math.floor((width - 2 * gap) / 3)
        local buttons = {}
        for index, name in ipairs(LOOK_NAMES) do
            local button = T.Button(body, Tr(name), buttonWidth, 26)
            button:SetPoint("TOPLEFT", body, "TOPLEFT", 16 + (index - 1) * (buttonWidth + gap), y)
            button:SetScript("OnClick", function()
                if not P.Combat() then P.Set(id, "look", index) end
            end)
            if M.RegisterControlMetadata then
                M.RegisterControlMetadata(button, P.Meta(pageKey, id, "look." .. index, "action", sectionId),
                    Tr(name), "button")
            end
            buttons[index] = button
        end
        M.TrackRefresh(ctx, function()
            local look = P.Get(id, "look")
            local enabled = P.RuleEnabled(id, P.catalog[id].rules.look)
            for index = 1, #buttons do
                buttons[index]:SetAlpha(look == index and 1 or 0.65)
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

function P.ResetPrefix(id, prefix)
    local rules = {}
    for _, rule in ipairs(P.catalog[id].controls) do
        if rule.key:sub(1, #prefix) == prefix
            and not rule.key:sub(#prefix + 1, #prefix + 1):match("%d") then
            rules[#rules + 1] = rule
        end
    end
    return P.ResetRules(id, rules)
end

-- Same header action pattern as the GF/UF accordions. The color shortcut in
-- the body remains available for color sections.
function P.AttachSectionReset(ctx, body, title, reset)
    local entry = body and body._msuf2CollapsibleEntry
    if not (entry and entry.header and W.TopButton and M.CreateMenuPopupPanel and type(reset) == "function") then return end
    body._msufSuiteSectionReset = reset
    if entry._msufSuiteResetButton then return entry._msufSuiteResetButton end
    local more = W.TopButton(entry.header, "...", 24, 22)
    if W.StyleSectionActionButton then W.StyleSectionActionButton(more) end
    more:SetPoint("RIGHT", entry.header, "RIGHT", -10, 0)
    more:SetFrameLevel(entry.header:GetFrameLevel() + 4)
    more._msuf2SkipHistoryCheckpoint = true
    entry._msuf2SectionActions = more
    entry._msufSuiteResetButton = more
    entry._msuf2ActionReserve = 34
    entry._msuf2ColorSwatchReserve = (entry._msuf2ColorSwatchReserve or 0) + 34
    local function AlignSwitch()
        if entry.featureSwitch then
            entry.featureSwitch:ClearAllPoints()
            entry.featureSwitch:SetPoint("RIGHT", entry.header, "RIGHT", -48, 0)
        end
    end
    AlignSwitch()
    if ctx and M.TrackRefresh then M.TrackRefresh(ctx, AlignSwitch) end
    if entry._msuf2RefreshLayout then entry._msuf2RefreshLayout() end
    local popup
    local function Close() if popup then popup:Hide() end end
    more:SetScript("OnClick", function()
        if P.Combat() then return end
        if popup and popup:IsShown() then Close(); return end
        if not popup then
            popup = M.CreateMenuPopupPanel(_G.UIParent)
            popup:SetClampedToScreen(true)
            popup:SetSize(288, 82)
            local heading = T.Font(popup, "GameFontHighlight", Tr(title), T.colors.text)
            heading:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -12)
            heading:SetWidth(242)
            local button = W.TopButton(popup, Tr("Reset section"), 250, 24)
            button:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -42)
            button:SetScript("OnClick", function()
                if P.Combat() then return end
                local ok = body._msufSuiteSectionReset()
                if M.ShowStatusFeedback then M.ShowStatusFeedback(Tr(ok and "Section reset" or "Action failed"), ok and "ok" or "danger", 1.5) end
                Close()
            end)
            popup._msuf2ResetSection = function() return body._msufSuiteSectionReset() end
            entry.outer:HookScript("OnHide", Close)
        end
        popup:ClearAllPoints()
        popup:SetPoint("TOPRIGHT", more, "BOTTOMRIGHT", 0, -4)
        if M.ApplyPopupFramePriority then M.ApplyPopupFramePriority(popup) end
        popup:Show()
    end)
    more._msuf2GetSectionPopup = function() return popup end
    if M.AddTooltip then M.AddTooltip(more, "Section actions", nil, { hook = true }) end
    return more
end

-- Catalog rules of one section, in declaration order.
function P.SectionRules(id, section, filter)
    local out = {}
    for _, rule in ipairs(P.catalog[id].controls) do
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
    if not skin and P.Suite.Skin and P.Suite.Skin.EnsureEngine and not P.Combat() then
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
    for _, id in ipairs(P.order) do
        local colors = {}
        for _, rule in ipairs(P.catalog[id].controls) do
            if rule.color and not rule.hidden then
                local entry = {}
                for key, value in pairs(rule) do entry[key] = value end
                entry.label = (rule.sectionTitle and (rule.sectionTitle .. " · ") or "") .. rule.label
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
    local isFrame = id ~= "qol" and id ~= "quests" and id ~= "loot"
    local title = opts.title or (isFrame and "Frame Basics" or "Module Basics")
    local body = b:CollapsibleSection(sectionId, Tr(title), 120, true)
    local width = math.max(240, (body._msuf2Width or b.width or 720) - 32)
    local toggle = W.SectionSwitch(body, Tr("Enable"), Tr("Enable"))
    M.BindBoolWidget(ctx, toggle,
        function() return P.Get(id, "enabled") == true end,
        function(value) P.Set(id, "enabled", value == true) end,
        P.Meta(pageKey, id, "enabled", "setting", sectionId))
    local status = P.Text(body, "", 16, -18, width, T.colors.text)
    local description = P.Text(body, spec.description, 16, -42, width, T.colors.dim or T.colors.muted)
    local y = -42 - math.max(14, math.ceil(description:GetStringHeight() or 14)) - 14
    local columns = width >= 560 and 3 or 2
    local buttonWidth = math.floor((width - (columns - 1) * 12) / columns)
    for i, action in ipairs(actions or {}) do
        local column = (i - 1) % columns
        if column == 0 and i > 1 then y = y - 34 end
        P.Button(ctx, body, action[1], 16 + column * (buttonWidth + 12), y, buttonWidth, action[2],
            action[3] or function() return S.Availability(id) and P.Get(id, "enabled") end,
            P.Meta(pageKey, id, "action." .. (action.key or i), "action", sectionId))
    end
    if actions and #actions > 0 then y = y - 38 end
    M.TrackRefresh(ctx, function()
        local ok = S.Availability(id)
        -- The preference remains editable even when this client cannot run the
        -- module. S.Apply still enforces Availability before starting it.
        W.SetControlEnabled(toggle, not P.Combat())
        status:SetText(P.StatusText(id))
        local entry = body._msuf2CollapsibleEntry
        if entry and entry.label then
            local suffix = not ok and " - Unavailable" or not P.Get(id, "enabled") and " - Off" or ""
            entry.label:SetText(Tr(title) .. Tr(suffix))
        end
    end)
    P.AttachSectionReset(ctx, body, title, function()
        return P.ResetRules(id, {}, nil, { "enabled" })
    end)
    P.FinishBody(b, body, y)
    return body
end
