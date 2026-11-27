local _, P = ...
local Text, Bridge = P.Suite.NameplateText, P.Suite.HostBridge
local Fonts = {}
P.NameplateFonts = Fonts
local oldGate, RuleRow = P.Gates.nameplates, P.RuleRow
local PAGE, ID = "opt_fonts", "nameplates"
local TEXT_COLORS, LEGACY_COLORS = "fonts_name_power_colors", "opt_fonts_nameplate_colors"
local COLOR_SCOPES = { "enemy", "neutral", "friendly" }
local STATUS_SCOPES = { "enemy", "neutral", "friendly", "friendlyNpc" }
local SCOPE_LABELS = { enemy = "Enemy", neutral = "Neutral", friendly = "Friendly", friendlyNpc = "Friendly NPC" }
local NAME_RULES = {
    { "friendlyNameClassColor", "friendly" },
    { "enemyPlateNameClassColor", "enemy" },
    { "enemyPlateNameTypeColor", "enemy" },
    { "neutralPlateNameTypeColor", "neutral" },
    { "friendlyNpcPlateNameTypeColor", "friendlyNpc" },
    { "threatNameColor", "enemy" },
}
local OTHER_TEXT_COLORS = { "enemyPowerTextColor", "focusReminderColor", "enemyLevelColor", "auraTimeColor", "auraStackColor" }
local model, style = P.Suite.NameplateExtensions, P.Suite.NameplateStyle
local statusKeys, statusScope = {}, {}
for _, scope in ipairs(STATUS_SCOPES) do
    local keys = {}
    statusKeys[scope] = keys
    for source = model.FirstTextSource, model.LastTextSource do
        keys[#keys + 1] = model.TextKey(scope, source) .. "Color"
    end
    if scope == "enemy" or scope == "friendly" then
        for _, item in ipairs(style.Status) do
            if item.sample and style.StatusSupported(item, scope) then keys[#keys + 1] = scope .. item.key .. "Color" end
        end
    end
    for _, key in ipairs(keys) do statusScope[key] = scope end
end
local colorKeys = {}
for _, scope in ipairs(COLOR_SCOPES) do
    colorKeys[scope .. "NameColor"] = true
    colorKeys[scope .. "NameColorEnabled"] = true
end
for _, entry in ipairs(NAME_RULES) do colorKeys[entry[1]] = true end
for _, key in ipairs(OTHER_TEXT_COLORS) do colorKeys[key] = true end
local function NativeScope()
    local provider = Bridge.NameFormatter()
    return provider and provider.Nameplates ~= nil
end
local function LegacyTextKey(key)
    if Text.SizeOverrides[key] or colorKeys[key] then return false end
    if key == "nameFormattingEnabled" or key == "nameTextUseCustomSettings" then return true end
    for _, prefix in ipairs({ "enemy", "friendly", "enemyCast", "friendlyCast" }) do
        for _, suffix in ipairs(Text.Suffixes) do if key == prefix .. suffix then return true end end
        for _, suffix in ipairs(Text.StyleSuffixes) do
            if key == prefix .. suffix then return key ~= "enemyCastTextEnabled" and key ~= "friendlyCastTextEnabled" end
        end
    end
    return key == "enemyCastFont" or key == "friendlyCastFont"
        or key == "enemyCastOutline" or key == "friendlyCastOutline"
end
Fonts.IsTypography = LegacyTextKey
P.Gates.nameplates = function(rule, key)
    if NativeScope() and LegacyTextKey(key) then return false, "Configure this in Fonts > Nameplates." end
    if oldGate then return oldGate(rule, key) end
end
function P.RuleRow(page, id, rule, ...)
    local row = RuleRow(page, id, rule, ...)
    if id == "nameplates" and row then
        local stored = row.get
        local override = Text.SizeOverrides[rule.key]
        if override and Text.UsesSharedFont(P.S.Config(id)) then row.label = P.Tr("Font size") end
        row.get = function()
            if NativeScope() or override and Text.UsesSharedFont(P.S.Config(id)) then
                local value, resolved = Text.InheritedValue(P.S.Config(id), rule.key)
                if resolved then return value end
            end
            return stored()
        end
        if rule.key == "enemyNameFormat" or rule.key == "friendlyNameFormat" then
            local get = row.get
            row.values[3], row.values[4] = nil, nil
            row.get = function() return Text.Limited(get()) and 2 or 1 end
        end
        if override then
            local set = row.set
            row.set = function(value)
                if Text.UsesSharedFont(P.S.Config(id)) then return P.Set(id, override, tonumber(value) or 0) end
                return set(value)
            end
        end
    end
    return row
end
local SHORTEN = "fonts_name_shortening"

function Fonts.OwnsColor(rule)
    local ui = P.NameplatesHostOptions
    return ui and ui.registered and (colorKeys[rule.key] or statusScope[rule.key]) ~= nil
end

local function ColorSection()
    return Fonts.HasLinks() and TEXT_COLORS or LEGACY_COLORS
end

local function StatusMeta(scope, sectionId)
    return P.Meta(PAGE, ID, "action.statusTextColors." .. scope, "action", sectionId)
end

local function StatusRules(scope)
    local rules, catalog = {}, P.catalog[ID].rules
    for _, key in ipairs(statusKeys[scope]) do rules[#rules + 1] = catalog[key] end
    return rules
end

local function NameColors(ctx, body, y, width, sectionId)
    local rules, labels, catalog = {}, {}, P.catalog[ID].rules
    for _, scope in ipairs(COLOR_SCOPES) do
        local color = catalog[scope .. "NameColor"]
        local toggle = catalog[color.enableKey]
        rules[#rules + 1], rules[#rules + 2] = toggle, color
        labels[toggle.key], labels[color.key] = color.label, "Custom color"
    end
    local grid = P.RuleRows(PAGE, ID, rules, nil, sectionId)
    for _, row in ipairs(grid.rows) do
        row.label = P.Tr(labels[row.id])
        row.startsGroup = row.kind == "toggle"
    end
    return P.RuleGrid(ctx, body, PAGE, ID, rules, y, width, nil, sectionId, 2, grid, true)
end

local function ColorRules(ctx, body, y, width, sectionId)
    local rules, scopes, catalog = {}, {}, P.catalog[ID].rules
    for _, entry in ipairs(NAME_RULES) do
        rules[#rules + 1], scopes[entry[1]] = catalog[entry[1]], entry[2]
    end
    for _, key in ipairs(OTHER_TEXT_COLORS) do
        local rule = {}
        for field, value in pairs(catalog[key]) do rule[field] = value end
        rule.inlineColorPage = PAGE
        rules[#rules + 1] = rule
    end
    local grid = P.RuleRows(PAGE, ID, rules, nil, sectionId)
    for _, row in ipairs(grid.rows) do
        local scope = scopes[row.id]
        if scope then row.label = P.Tr(SCOPE_LABELS[scope]) .. " · " .. row.label end
    end
    return P.RuleGrid(ctx, body, PAGE, ID, rules, y, width, nil, sectionId, width >= 720 and 2 or 1, grid)
end

local HOST_COLOR_FIELDS = { "fontColorR", "fontColorG", "fontColorB" }

local function DefaultColorTarget()
    if not Bridge.HasNameplateFontSettings() then return end
    local profile, suiteProfile = Bridge.CurrentFrameProfile(), P.Suite.DB
    local provider = Bridge.NameFormatter()
    local _, _, state = Bridge.CaptureNameplateSettings()
    local enabled = state and state.nameplates and state.nameplates.fontOverride == true
    if not (profile and provider and provider.Nameplates) then return end
    local function Apply(values, clear)
        if P.Combat() or profile ~= Bridge.CurrentFrameProfile() or suiteProfile ~= P.Suite.DB
            or not Text.UsesSharedFont(P.S.Config(ID)) then return false end
        local ok = Bridge.ApplyNameplateSettings({ version = 1, nameplates = values, clear = clear })
        if ok then P.Refresh() end
        return ok
    end
    return {
        label = P.Tr("Default font color"),
        get = function()
            local color = provider.Nameplates({}).textColor
            return color.r, color.g, color.b
        end,
        set = function(r, g, b)
            return Apply({ fontColorR = r, fontColorG = g, fontColorB = b })
        end,
        captureState = function()
            local _, _, exact = Bridge.CaptureNameplateSettings()
            if not exact then return end
            local values, clear = {}, {}
            local stored = exact.nameplates or {}
            for _, field in ipairs(HOST_COLOR_FIELDS) do
                if stored[field] == nil then clear[#clear + 1] = "nameplates." .. field else values[field] = stored[field] end
            end
            return { values = values, clear = clear }
        end,
        restoreState = function(saved) return Apply(saved.values, saved.clear) end,
    }, enabled, function()
        return P.WithHistory("Use custom settings for this scope", "suite:nameplates.fontOverride", function() return Apply({ fontOverride = true }) end)
    end
end

local function OpenHPColors(anchor, body)
    if not Text.UsesSharedFont(P.S.Config(ID)) then
        if P.M.ShowStatusFeedback then P.M.ShowStatusFeedback(P.Tr("Unavailable with the current settings."), "danger", 3) end
        return true
    end
    local target, enabled, enable = DefaultColorTarget()
    if not target then return false end
    local function Pick()
        return P.OpenRuleColors(body, "HP Text", ID, {}, nil, function() return { target } end)
    end
    if enabled then return Pick() end
    P.AnchoredContextMenu(anchor, function(_, menu)
        menu:CreateTitle(P.Tr("HP Text"))
        menu:CreateButton(P.Tr("Use custom settings for this scope"), function()
            if enable() then Pick() end
        end)
    end)
    return true
end

local function OpenQuickColors(anchor, body, tab)
    if P.Combat() then return end
    local rules = P.catalog[ID].rules
    if tab == "hp" then
        if OpenHPColors(anchor, body) then return end
    elseif tab == "power" then
        if P.OpenRuleColors(body, "Power Text", ID, { rules.enemyPowerTextColor }) then return end
    else
        local scope = P.NameplatesWorkspace.Kind()
        if scope == "friendlyNpc" then scope = "friendly" end
        if P.OpenRuleColors(body, "Name colors", ID, { rules[scope .. "NameColor"] }, nil, nil, true) then return end
    end
    Fonts.OpenColors()
end

function Fonts.AttachColorLink(body, sectionId, key, getTab, y)
    if not P.NameplatesHostOptions.registered then return end
    local widgets = P.W
    local button = widgets.AttachContextColorShortcut and widgets.AttachContextColorShortcut(body, {
        offsetX = -16, offsetY = y or -15, tooltipTitle = "Text Colors",
    })
    if not button then
        button = (widgets.TopButton or P.T.Button)(body, "...", 34, 20)
        button:SetPoint("TOPRIGHT", body, "TOPRIGHT", -16, y or -15)
        if P.M.AddTooltip then P.M.AddTooltip(button, "Text Colors", nil, { hook = true }) end
    end
    P.HM.SkipHistoryCheckpoint(button)
    button:SetScript("OnClick", function(self) OpenQuickColors(self, body, getTab and getTab() or "name") end)
    if P.M.RegisterControlMetadata then
        local meta = P.Meta("suite_nameplates", ID, key .. ".colors", "action", sectionId)
        P.M.RegisterControlMetadata(button, meta, "Text Colors", "button")
    end
    return button
end

local function StatusColors(ctx, body, y, width, sectionId)
    P.Text(body, "Status icons", 16, y, width, nil, "section")
    y = y - 23
    local gap, column = 10, math.floor((width - 10) / 2)
    for index, scope in ipairs(STATUS_SCOPES) do
        local rules, button = StatusRules(scope)
        local row, col = math.floor((index - 1) / 2), (index - 1) % 2
        local title = SCOPE_LABELS[scope]
        button = P.Button(ctx, body, title, 16 + col * (column + gap), y - row * 33, column, function()
            P.OpenRuleColors(button, title, ID, rules)
        end, nil, StatusMeta(scope, sectionId))
    end
    return y - 66
end

local function BuildColors(ctx, body, y, width, sectionId)
    P.Text(body, "Name colors", 16, y, width, nil, "section")
    local help = P.Description(body, "Custom name colors override the other name colors for that reaction.", 16, y - 23, width)
    y = NameColors(ctx, body, y - 35 - math.ceil(help:GetStringHeight() or 14), width, sectionId)
    y = ColorRules(ctx, body, y - 8, width, sectionId)
    return StatusColors(ctx, body, y - 8, width, sectionId)
end

local function ColorSettings()
    local rules, catalog = {}, P.catalog[ID].rules
    for key in pairs(colorKeys) do rules[#rules + 1] = catalog[key] end
    for key in pairs(statusScope) do rules[#rules + 1] = catalog[key] end
    return rules
end

function Fonts.BuildColors(ctx, builder)
    local body = Fonts.HasLinks() and ctx.entry and ctx.entry.sections and ctx.entry.sections[TEXT_COLORS]
    if body then
        local y = (P.HM.GetSectionCursor(body) or -145) - 12
        local width = math.max(240, (P.HM.GetSectionWidth(body) or builder.width) - 32)
        P.FinishBody(builder, body, BuildColors(ctx, body, y, width, TEXT_COLORS))
        P.AttachSectionReset(ctx, body, P.Tr("Text Colors"), function()
            return P.ResetRules(ID, ColorSettings())
        end, nil, nil, P.Tr("Reset Suite text colors"))
    else
        local title = P.Tr("Nameplates") .. " · " .. P.Tr("Text Colors")
        P.RuleSection(ctx, builder, PAGE, ID, LEGACY_COLORS, title, {}, {
            open = true, grid = function(section, y, width) return BuildColors(ctx, section, y, width, LEGACY_COLORS) end,
            resetRules = ColorSettings(),
        })
    end
end

function Fonts.HasLinks()
    return Bridge.HasNameplateFontsMenu(P.M)
end

function Fonts.TargetForSetting(settingKey)
    local key = settingKey and settingKey:match("^msufsuite%.nameplates%.(.+)$")
    if not key then return end
    local provider = P.NameplatesHostOptions
    local native = Fonts.HasLinks()
    if provider and provider.registered and (colorKeys[key] or statusScope[key]) then
        local section = ColorSection()
        local page, target, route = PAGE, { sectionId = section }
        if native then page, target, route = Bridge.NameplateFontsTarget(section) end
        local scope = statusScope[key]
        if scope then
            target.controlId = StatusMeta(scope, section).controlId
        else
            target.settingKey = settingKey
        end
        return page, target, route
    end
    if not LegacyTextKey(key) then return end
    if not native then
        if provider and provider.registered then return "opt_fonts", { sectionId = "opt_fonts_nameplate_text" } end
        return
    end
    if key == "nameFormattingEnabled" or key == "nameTextUseCustomSettings" then
        return Bridge.NameplateFontsTarget(SHORTEN)
    end
    local suffix = key:match("^enemy(.+)$") or key:match("^friendly(.+)$")
    for _, name in ipairs(Text.Suffixes) do
        if suffix == name then return Bridge.NameplateFontsTarget(SHORTEN) end
    end
    local section = key:match("Font$") and "fonts_global_font" or "fonts_text_style"
    return Bridge.NameplateFontsTarget(section)
end

function Fonts.FriendlyNPCColorTarget()
    local colors = Bridge.NPCColors()
    if not colors or not colors.GetNPCColor or not colors.SetNPCColor then return end
    local profile = Bridge.CurrentFrameProfile()
    return {
        label = P.Tr("Friendly NPC Color"),
        settingKey = "colors.npc.color.friendly",
        get = function() return colors.GetNPCColor("friendly") end,
        set = function(r, g, b)
            if P.Combat() or profile ~= Bridge.CurrentFrameProfile() then return false end
            colors.SetNPCColor("friendly", r, g, b)
            P.S.Apply("nameplates")
            P.Refresh()
            return true
        end,
    }
end

function Fonts.OpenColors(settingKey)
    if P.Combat() then return false end
    local page, target, route
    if settingKey then page, target, route = Fonts.TargetForSetting(settingKey) end
    if Fonts.HasLinks() then
        if not target then page, target, route = Bridge.NameplateFontsTarget(TEXT_COLORS) end
    elseif not target then
        page, target = PAGE, { sectionId = LEGACY_COLORS }
    end
    if P.M.SearchBridge and P.M.SearchBridge.OpenSearchTarget then
        local called, opened = P.M.SearchBridge.OpenSearchTarget(page, nil, nil, nil, route, target)
        if called and opened then return true end
    end
    if not P.M.SelectPage(page) then return false end
    local entry = P.M.cache and P.M.cache[page]
    local section = entry and entry.sections and entry.sections[target.sectionId]
    if not section or not P.W.FocusCollapsibleSection then return false end
    return P.W.FocusCollapsibleSection(section, { persist = true })
end

function Fonts.AddLinks(ctx, body, y, width, sectionId)
    if not Fonts.HasLinks() then
        local fallback = P.NameplatesHostOptions
        if not fallback or not fallback.registered then return y end
        P.Button(ctx, body, "Nameplate typography", 16, y, math.min(200, width), function()
            P.M.SelectPage("opt_fonts")
            local page = P.M.cache and P.M.cache.opt_fonts
            local target = page and page.sections and page.sections.opt_fonts_host_nameplates
            if target and P.W.FocusCollapsibleSection then P.W.FocusCollapsibleSection(target, { persist = true }) end
        end, nil, P.Meta("suite_nameplates", "nameplates", "action.fontTypography." .. sectionId, "action", sectionId))
        return y - 34
    end
    local buttonWidth = math.min(164, (width - 8) / 2)
    local function Button(label, x, section, key)
        P.Button(ctx, body, label, x, y, buttonWidth, function() Bridge.OpenNameplateFonts(P.M, section) end,
            nil, P.Meta("suite_nameplates", "nameplates", key .. "." .. sectionId, "action", sectionId))
    end
    Button("Nameplate font", 16, "fonts_global_font", "action.fontTypography")
    Button("Name format", 24 + buttonWidth, SHORTEN, "action.fontNameFormat")
    return y - 34
end
