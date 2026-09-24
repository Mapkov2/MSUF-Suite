local _, P = ...
local S, M, W, T, Tr = P.S, P.M, P.W, P.T, P.Tr

-- Slider increments are a UI choice. Keep catalog steps intact so existing
-- fractional profile values are not rounded during database normalization.
function P.SliderStep(minimum, maximum, default, declaredStep)
    local function Whole(value)
        return type(value) == "number" and value == math.floor(value)
    end
    if Whole(minimum) and Whole(maximum) and (default == nil or Whole(default))
        and not ((declaredStep or 1) < 1 and maximum - minimum <= 2) then return 1 end
    return 0.01
end

function P.RGB(hex)
    if type(hex) ~= "string" or #hex ~= 6 then return 1, 1, 1 end
    return (tonumber(hex:sub(1, 2), 16) or 255) / 255, (tonumber(hex:sub(3, 4), 16) or 255) / 255,
        (tonumber(hex:sub(5, 6), 16) or 255) / 255
end
local function Hex(r, g, b)
    local function Byte(value) return math.floor(math.max(0, math.min(1, tonumber(value) or 0)) * 255 + 0.5) end
    return string.format("%02x%02x%02x", Byte(r), Byte(g), Byte(b))
end

-- MSUF's own font list (keys or paths) plus the native choice; a saved font
-- that is no longer installed stays selectable so it is not silently lost.
function P.FontValues(selected, defaultLabel)
    local values, seen = { { value = "", text = Tr(defaultLabel or "Native font") } }, { [""] = true }
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
    if not (items[1] and items[1].value == "") then values[1] = { value = "", text = Tr("Module default") }; seen[""] = true end
    for _, entry in ipairs(items) do
        if entry.value ~= nil and not seen[entry.value] then values[#values + 1] = entry; seen[entry.value] = true end
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
        -- Pages may mark single choices unavailable on this client.
        local gates = P.ChoiceGates[id]
        local gate = gates and gates[rule.key]
        if gate then
            local base = row.values
            local values = {}
            row.values = function()
                for i = 1, #base do
                    values[i] = values[i] or { value = base[i].value, text = base[i].text }
                    values[i].disabled = not gate(i)
                end
                return values
            end
        end
        row.get = function() return P.Get(id, Key()) end
        row.set = function(value) P.Set(id, Key(), tonumber(value) or rule.default) end
    elseif type(rule.default) == "boolean" then
        row.kind = "toggle"
        row.get = function() return P.Get(id, Key()) == true end
        row.set = function(value) P.Set(id, Key(), value == true) end
    elseif type(rule.default) == "number" then
        row.kind, row.min, row.max, row.step, row.default = "slider", rule.min, rule.max,
            P.SliderStep(rule.min, rule.max, rule.default, rule.step), rule.default
        row.roundStep = row.step >= 1
        if row.step == 1 and (rule.step or 1) < 1 then
            row.format = function(value)
                if value ~= math.floor(value) then return string.format("%.2f", value) end
                return tostring(value)
            end
        end
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
            if row then rows[#rows + 1] = row; pending[#pending + 1] = rule
            elseif type(rule.default) == "string" then strings[#strings + 1] = rule end
        end
    end
    local entries = {}
    if #rows > 0 then
        local grid = W.SettingsRows(ctx, parent, { x = 16, y = y, width = width, columns = columns or 2, rows = rows })
        for i, rule in ipairs(pending) do entries[#entries + 1] = { rule = rule, widget = grid.controls[rule.key] } end
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
        title = Tr(title), maxTargets = #colors,
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
    local entry = body._msuf2CollapsibleEntry
    if entry and opts.onEnsureVisible then entry._msuf2EnsureVisible = opts.onEnsureVisible end
    P.FinishBody(b, body, y)
    return body, entries
end

-- Catalog rules of one section, in declaration order.
function P.SectionRules(id, section, filter)
    local out = {}
    for _, rule in ipairs(P.catalog[id].controls) do
        if rule.section == section and rule.key ~= "enabled" and not rule.previewOnly
            and (not filter or filter(rule)) then out[#out + 1] = rule end
    end
    return out
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
    local skin = _G.MapkoSkin
    if not skin and P.Suite.Skin and P.Suite.Skin.EnsureEngine and not P.Combat() then
        P.Suite.Skin.EnsureEngine()
        skin = _G.MapkoSkin
    end
    if not (skin and skin.addonName == "MSUF_Suite_Skin" and skin.Theme and skin.ColorOrder) then return end
    local section = b:CollapsibleSection("colors_suite_skin", Tr("Suite skin"), 120, false)
    local width = math.max(240, (section._msuf2Width or b.width or 720) - 32)
    local rows = {}
    for _, entry in ipairs(skin.ColorOrder) do
        local key = entry[1]
        rows[#rows + 1] = {
            id = "skin." .. key, kind = "color", label = Tr((skin.L and skin.L[entry[2]]) or key),
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
    local grid = W.SettingsRows(ctx, section, { x = 16, y = -18, width = width, columns = 2, rows = rows })
    P.FinishBody(b, section, grid.bottomY)
end

-- Standard module header card: enable switch, live status and actions.
-- actions: list of { label, onClick, enabled(optional) }.
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
    P.FinishBody(b, body, y)
    return body
end
