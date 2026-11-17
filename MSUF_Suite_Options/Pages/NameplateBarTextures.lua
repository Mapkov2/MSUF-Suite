local _, P = ...
local Bridge = P.Suite.HostBridge
local ID = "nameplates"
local Textures = {}
P.NameplateBarTextures = Textures

local health = { page = "opt_bars", section = "suite_nameplate_health_textures",
    title = "Textures & Gradient",
    keys = { "nativeHealthFillTexture", "nativeHealthBackgroundTexture", "powerFillTexture",
        "powerBackgroundTexture", "nativeFocusHealthFillTexture", "barsOverride" } }
local cast = { page = "opt_castbar", section = "suite_nameplate_cast_textures", title = "Nameplate castbar textures",
    keys = { "nativeCastFillTexture", "nativeCastBackgroundTexture", "nativeCastFillColor", "nativeCastLockedColor" } }
local textureKeys = { unpack(health.keys, 1, 5) }
local barKinds = { "health", "power" }
local gradientDirections = {
    { "^", "DirUp", 41, -7 }, { "<", "DirLeft", 18, -30 },
    { ">", "DirRight", 64, -30 }, { "v", "DirDown", 41, -53 },
}
for _, kind in ipairs(barKinds) do
    for _, suffix in ipairs({ "GradientEnabled", "GradientStrength", "GradientColor",
        "GlossEnabled", "GlossStrength" }) do
        health.keys[#health.keys + 1] = kind .. suffix
    end
    for _, direction in ipairs(gradientDirections) do health.keys[#health.keys + 1] = kind .. "Gradient" .. direction[2] end
end
local outline = { page = "opt_bars", section = "suite_nameplate_outline", title = "Frame Outline", keys = {
    "enemyOutlineMode", "friendlyOutlineMode", "selectionBorder", "highlightTarget", "highlightFocus",
    "selectionTargetColor", "selectionFocusColor",
} }
local legacy = { enemyBorderEnabled = true, friendlyBorderEnabled = true,
    enemyNativeBorderEnabled = true, friendlyNativeBorderEnabled = true, hideHealthBarBorders = true }
local highlight = { page = "opt_bars", section = "suite_nameplate_highlights", title = "Highlight Borders", searchBySetting = true, keys = {
    "highlightAggro", "highlightMouseover", "highlightBorderSize", "highlightAggroColor", "highlightMouseoverColor",
    "selectionDim", "selectionDimPercent", "mouseoverHighlight", "mouseoverHighlightColor",
    "highlightPriority", "highlightOrder", "highlightAggroOverride", "castTargetHighlightStyle",
} }
local absorb = { page = "opt_bars", section = "suite_nameplate_absorbs", title = "Absorb Display",
    searchBySetting = true, keys = { "nameplateAbsorbMode", "nameplateHealAbsorbMode" } }
local OutlineSuffixes = { "BorderSize", "BorderColor", "BorderStyle", "OuterFrame", "OuterFrameSize", "OuterFrameColor",
    "ShadowEnabled", "GlowEnabled", "GlowMode", "GlowColor", "EffectSize" }
for _, side in ipairs({ "enemy", "friendly" }) do
    for _, suffix in ipairs(OutlineSuffixes) do
        outline.keys[#outline.keys + 1] = side .. suffix
    end
end
local OPEN_CAST = "Open castbar textures"
local sections = { health, cast, outline, highlight, absorb }

local inherited = {
    nativeHealthFillTexture = true, nativeHealthBackgroundTexture = true,
    powerFillTexture = true, powerBackgroundTexture = true,
    enemyOutlineMode = true, friendlyOutlineMode = true, hideHealthBarBorders = true,
    enemyBorderSize = true, friendlyBorderSize = true, enemyBorderColor = true, friendlyBorderColor = true,
    highlightBorderSize = true, highlightAggroColor = true,
}
for _, key in ipairs(health.keys) do
    if key:match("Gradient") or key:match("Gloss") then inherited[key] = true end
end

local function Shared()
    local read = Bridge.SharedNameplateBars
    return read and read()
end

local function Value(key)
    if inherited[key] and not P.Get(ID, "barsOverride")
        and (key ~= "highlightAggroColor" or not P.Get(ID, "highlightAggroOverride")) then
        local settings = Shared()
        if settings and settings[key] ~= nil then return settings[key] end
    end
    return P.Get(ID, key)
end

local function SetOverride(enabled, key, value)
    local values = { barsOverride = enabled }
    if enabled and not P.Get(ID, "barsOverrideSaved") then
        values.look = P.Get(ID, "look")
        local settings = Shared()
        for key, value in pairs(settings or {}) do
            if inherited[key] and (key ~= "highlightAggroColor" or not P.Get(ID, "highlightAggroOverride")) then
                values[key] = value
            end
        end
        values.barsOverrideSaved = true
    end
    if key then values[key], values.look = value, P.Get(ID, "look") end
    return P.SetMany(ID, values)
end

local function SetOutlineMode(key, value)
    local look = P.Get(ID, "look")
    if P.Get(ID, "hideHealthBarBorders") then
        return P.SetMany(ID, { enemyOutlineMode = 4, friendlyOutlineMode = 4,
            barsOverride = true, barsOverrideSaved = true, hideHealthBarBorders = false,
            look = look, [key] = value })
    end
    if look == 2 then return P.SetMany(ID, { look = look, barsOverride = true, [key] = value }) end
    if not P.Get(ID, "barsOverride") and Shared() then return SetOverride(true, key, value) end
    return P.SetMany(ID, { look = look, [key] = value })
end

local RuleRow = P.RuleRow
function P.RuleRow(page, id, rule, ...)
    local row = RuleRow(page, id, rule, ...)
    if not row or id ~= ID then return row end
    local side = rule.key:match("^(%l+)OutlineMode$")
    if side then
        local function Values()
            local values = {}
            if Value(rule.key) == 1 then
                values[1] = { value = 1, text = P.Tr(rule.choices[1]), disabled = true }
            end
            local native = P.Get(ID, "look") == 2
            for value = 2, #rule.choices do
                if not native or value ~= 3 then values[#values + 1] = { value = value, text = P.Tr(rule.choices[value]) } end
            end
            return values
        end
        row.values = Values
        row.set = function(value) return SetOutlineMode(rule.key, tonumber(value) or rule.default) end
    elseif rule.key == "enemyBorderSize" or rule.key == "friendlyBorderSize" then
        row.min = 1
        row.default = math.max(1, row.default)
    end
    if rule.key == "barsOverride" then row.set = SetOverride end
    if inherited[rule.key] and not rule.color then
        row.get = function()
            local value = Value(rule.key)
            if rule.key == "enemyBorderSize" or rule.key == "friendlyBorderSize" then return math.max(1, value) end
            return value
        end
        if rule.texture then row.values = function() return P.TextureValues(Value(rule.key), rule.defaultLabel) end end
    end
    return row
end

do
    local previousGate = P.Gates[ID]
    P.Gates[ID] = function(rule, key)
        if not inherited[key] and key ~= "barsOverride" then
            if previousGate then return previousGate(rule, key) end
            return true
        end
        local shared = not P.Get(ID, "barsOverride") and Shared()
        if key == "barsOverride" and not shared and not P.Get(ID, "barsOverride") then
            return false, "Unavailable on this client."
        end
        if inherited[key] and shared and shared[key] ~= nil
            and key ~= "enemyOutlineMode" and key ~= "friendlyOutlineMode"
            and (key ~= "highlightAggroColor" or not P.Get(ID, "highlightAggroOverride")) then
            return false, P.Tr("Turn on \"%s\" to change this."):format(P.Tr("Use custom settings for this scope"))
        end
        if (key == "enemyOutlineMode" or key == "friendlyOutlineMode") and P.Get(ID, "look") == 2 then return true end
        if previousGate then return previousGate(rule, key) end
        return true
    end
end

function Textures.Target(key)
    for _, spec in ipairs(sections) do
        if spec.registered then
            for _, candidate in ipairs(spec.keys) do
                if key == candidate then return spec end
            end
        end
    end
end

function Textures.LegacyRule(key) return legacy[key] == true end

function Textures.BarDetailKeys()
    local keys = {}
    for _, spec in ipairs({ outline, highlight, absorb }) do
        for _, key in ipairs(spec.keys) do keys[#keys + 1] = key end
    end
    return keys
end

local function Link(ctx, body, y, width, section, spec, label, target)
    if not spec.registered then return y end
    target = target or spec.keys[1]
    P.Button(ctx, body, label, 16, y, math.min(width, 240), function()
        local key = "msufsuite.nameplates." .. target
        if not Bridge.OpenExactMenuSetting(P.M, spec.page, spec.section, key) then
            P.M.SelectPage(spec.page)
            local page = P.M.cache and P.M.cache[spec.page]
            local target = page and page.sections and page.sections[spec.section]
            local entry = target and P.HM.GetSectionEntry(target)
            local reveal = entry and P.HM.GetSectionEnsureVisible(entry)
            if reveal then reveal() end
            if target and P.W.FocusCollapsibleSection then
                P.W.FocusCollapsibleSection(target, { persist = true })
            elseif entry then
                entry.SetOpenImmediate(true)
            end
        end
    end, nil, P.Meta("suite_nameplates", ID, "link." .. target, "action", section))
    return y - 38
end

function Textures.Link(ctx, body, y, width, section, isCast)
    return Link(ctx, body, y, width, section, isCast and cast or health, isCast and OPEN_CAST or health.title)
end

function Textures.LinkOutline(ctx, body, y, width, section)
    y = Link(ctx, body, y, width, section, outline, outline.title)
    return Link(ctx, body, y, width, section, highlight, highlight.title)
end

function Textures.LinkCastTarget(ctx, body, y, width, section)
    return Link(ctx, body, y, width, section, highlight, "Cast target highlight style", "castTargetHighlightStyle")
end

function Textures.LinkAbsorbs(ctx, body, y, width, section)
    return Link(ctx, body, y, width, section, absorb, absorb.title)
end

local function Rules(spec)
    local catalog, rules = P.catalog[ID], {}
    for _, key in ipairs(spec.keys) do
        local rule = catalog.rules[key]
        if rule and catalog.controlAvailable(rule) then rules[#rules + 1] = rule end
    end
    return rules
end

local function ToggleGradientDirection(prefix, key)
    local count = 0
    for _, direction in ipairs(gradientDirections) do
        if Value(prefix .. direction[2]) then count = count + 1 end
    end
    local active = Value(key) == true
    if active and count == 1 or count == 0 and key == prefix .. "DirRight" then return end
    P.Set(ID, key, not active)
end

local function GradientDirections(ctx, body, prefix, x, y)
    local theme = P.T
    local pad = theme.Panel(body, nil, theme.colors.panel2, theme.colors.borderSoft)
    pad:SetPoint("TOPLEFT", body, "TOPLEFT", x, y)
    pad:SetSize(104, 78)
    local center = pad:CreateTexture(nil, "ARTWORK")
    center:SetPoint("CENTER")
    center:SetSize(10, 10)
    local rim = theme.colors.coreRim or { .043, .096, .150 }
    center:SetColorTexture(rim[1], rim[2], rim[3], .95)
    local buttons = {}
    for i, direction in ipairs(gradientDirections) do
        local key = prefix .. direction[2]
        local rule = P.catalog[ID].rules[key]
        local button = theme.Button(pad, direction[1], 22, 18)
        button:SetPoint("TOPLEFT", direction[3], direction[4])
        if theme.CenterButtonLabel then theme.CenterButtonLabel(button) end
        button:SetScript("OnClick", function()
            if P.RuleEnabled(ID, rule) then ToggleGradientDirection(prefix, key) end
        end)
        if P.M.RegisterControlMetadata then
            P.M.RegisterControlMetadata(button, P.Meta(health.page, ID, key, "setting", health.section),
                rule.label, "button")
        end
        if P.M.AddTooltip then P.M.AddTooltip(button, P.Tr(rule.label),
            P.Tr("Select one or more edges. At least one direction stays active."), { hook = true }) end
        buttons[i] = { button = button, rule = rule }
    end
    local function Refresh()
        local any = false
        for _, entry in ipairs(buttons) do
            if Value(entry.rule.key) then any = true end
        end
        pad:SetAlpha(P.RuleEnabled(ID, buttons[1].rule) and 1 or .45)
        for _, entry in ipairs(buttons) do
            entry.button:SetActive(Value(entry.rule.key) == true or not any and entry.rule.key == prefix .. "DirRight")
            P.W.SetControlEnabled(entry.button, P.RuleEnabled(ID, entry.rule))
        end
    end
    P.M.TrackRefresh(ctx, Refresh)
    Refresh()
end

local function BarControls(ctx, body, prefix, y, width)
    local rules = P.catalog[ID].rules
    return P.RuleGrid(ctx, body, health.page, ID, { rules[prefix .. "Enabled"], rules[prefix .. "Strength"] },
        y, width, nil, health.section, 1)
end

local function PreviewBar(preview, label, y, hex)
    P.Text(preview, label, 10, y - 2, 112)
    local bar = CreateFrame("Frame", nil, preview)
    bar:SetPoint("TOPLEFT", preview, "TOPLEFT", 124, y)
    bar:SetPoint("TOPRIGHT", preview, "TOPRIGHT", -10, y)
    bar:SetHeight(18)
    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(bar)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT")
    fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT")
    local r, g, b = P.RGB(hex)
    return { bar = bar, fill = fill, background = background, r = r, g = g, b = b }
end

local function PreviewArt(texture, path, r, g, b)
    if path then
        texture:SetTexture(path)
        texture:SetVertexColor(r, g, b)
    else
        texture:SetColorTexture(r, g, b)
        texture:SetVertexColor(1, 1, 1)
    end
end

local function BarPreview(ctx, body, y, width)
    local preview = P.T.Panel(body, nil, P.T.colors.panel2, P.T.colors.borderSoft)
    preview:SetPoint("TOPLEFT", body, "TOPLEFT", 16, y)
    preview:SetSize(width, 80)
    P.Text(preview, "Live preview", 10, -6, width - 20)
    local bands = { health = PreviewBar(preview, "Health bar", -27, "cf4545"),
        power = PreviewBar(preview, "Resource Bar", -51, "337be6") }
    local style = P.Suite.NameplateStyle
    local function Refresh()
        if not preview:IsVisible() then return end
        local config = P.S.Config(ID)
        config = style.BarSettings(config, not config.barsOverride and Shared())
        local skinned = P.Get(ID, "enabled") and config.look ~= 2
        local healthBar, resolve = bands.health, P.Suite.ResolveTexture
        local fill = skinned and resolve(config.nativeHealthFillTexture) or nil
        local override = skinned and not style.UsesNativeOutline(config, "enemy")
        local background = override and resolve(config.nativeHealthBackgroundTexture) or nil
        if fill then PreviewArt(healthBar.fill, fill, healthBar.r, healthBar.g, healthBar.b)
        else
            healthBar.fill:SetAtlas("UI-HUD-CoolDownManager-Bar")
            healthBar.fill:SetVertexColor(healthBar.r, healthBar.g, healthBar.b)
        end
        PreviewArt(healthBar.background, background, .16, .16, .16)
        local power = bands.power
        local r, g, b = power.r, power.g, power.b
        if config.enemyPowerByType == false then r, g, b = P.RGB(config.enemyPowerColor or "337be6") end
        PreviewArt(power.fill, resolve(config.powerFillTexture), r, g, b)
        r, g, b = P.RGB(config.enemyPowerBackgroundColor or "10151d")
        PreviewArt(bands.power.background, resolve(config.powerBackgroundTexture), r, g, b)
        bands.power.background:SetAlpha((config.enemyPowerBackgroundAlpha or 80) / 100)
        for _, kind in ipairs(barKinds) do
            local sample = bands[kind]
            sample.fill:SetWidth((width - 134) * (kind == "health" and .72 or .56))
            local plan = skinned and style.Gradient.Plan(config, kind, sample.state and sample.state.plan) or nil
            sample.state = style.Gradient.Paint(sample.bar, sample.state, sample.fill, plan)
        end
    end
    preview:SetScript("OnShow", Refresh)
    P.M.TrackRefresh(ctx, Refresh)
    Refresh()
    return y - 80
end

local function HealthBarsGrid(ctx, body, y, width, rules)
    local textureRules = {}
    for _, key in ipairs(textureKeys) do
        local rule = P.catalog[ID].rules[key]
        if rule and P.catalog[ID].controlAvailable(rule) then textureRules[#textureRules + 1] = rule end
    end
    local catalog = P.catalog[ID].rules
    if Shared() or P.Get(ID, "barsOverride") then
        y = P.RuleGrid(ctx, body, health.page, ID, { catalog.barsOverride }, y, width, nil, health.section, 1) - 10
    end
    local leftWidth = math.min(300, width)
    local wide = width >= 640
    local left = CreateFrame("Frame", nil, body)
    left:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    P.Text(left, "Bar textures (SharedMedia)", 16, 0, leftWidth, nil, "section")
    local leftBottom = P.RuleGrid(ctx, left, health.page, ID, textureRules, -25, leftWidth, nil, health.section, 1)
    local right = CreateFrame("Frame", nil, body)
    local rightWidth = wide and math.floor(width / 2) or width
    local rightY = wide and y or y + leftBottom - 12
    right:SetPoint("TOPLEFT", body, "TOPLEFT", wide and width - rightWidth or 0, rightY)
    P.Text(right, "Gradient", 16, 0, rightWidth, nil, "section")
    local sidePad = rightWidth >= 320
    local controlWidth = math.min(244, sidePad and rightWidth - 120 or rightWidth)
    local bottom = -26
    for _, kind in ipairs(barKinds) do
        local controlsBottom = BarControls(ctx, right, kind .. "Gradient", bottom, controlWidth)
        local padY = sidePad and bottom or controlsBottom
        GradientDirections(ctx, right, kind .. "Gradient", sidePad and 24 + controlWidth or 16, padY)
        bottom = math.min(controlsBottom, padY - 78) - 14
    end
    local glossY = math.min(y + leftBottom, rightY + bottom) - 4
    local powerGlossY = BarControls(ctx, left, "healthGloss", glossY - y, leftWidth) + y
    local powerParent, powerTop = wide and right or left, wide and rightY or y
    local powerStart = wide and glossY or powerGlossY - 8
    local powerBottom = BarControls(ctx, powerParent, "powerGloss", powerStart - powerTop,
        wide and math.min(300, rightWidth) or leftWidth) + powerTop
    -- Size the columns around their controls so search can scroll to them.
    left:SetSize(leftWidth + 16, y - (wide and powerGlossY or powerBottom))
    right:SetSize(wide and rightWidth + 16 or rightWidth, rightY - (wide and powerBottom or rightY + bottom))
    P.AttachRuleColors(body, "Bar Gradient Colors", ID, rules, nil, function(rule) return P.RuleEnabled(ID, rule) end, nil, nil, Value)
    return BarPreview(ctx, body, math.min(powerGlossY, powerBottom) - 8, width)
end

local function OutlineSection(ctx, builder)
    local rules = Rules(outline)
    local groups = { enemy = {}, friendly = {} }
    local selection = {}
    local resetKeys = {}
    for key in pairs(legacy) do resetKeys[#resetKeys + 1] = key end
    for _, rule in ipairs(rules) do
        local side = rule.key:match("^(%l+)[A-Z]")
        if groups[side] then table.insert(groups[side], rule) end
        if not groups[side] then selection[#selection + 1] = rule end
    end
    return P.RuleSection(ctx, builder, outline.page, ID, outline.section, P.Tr(outline.title), rules, {
        resetKeys = resetKeys,
        grid = function(body, y, width)
            P.AttachRuleColors(body, outline.title, ID, rules, nil, function(rule) return P.RuleEnabled(ID, rule) end, nil, nil, Value)
            for _, side in ipairs({ "enemy", "friendly" }) do
                local title = side == "enemy" and P.Tr("Enemy and Neutral") or P.Tr("Friendly and Friendly NPC")
                P.Text(body, title, 16, y, width, nil, "section")
                y = P.RuleGrid(ctx, body, outline.page, ID, groups[side], y - 26, width, nil, outline.section) - 12
            end
            local hint = P.Text(body, "Blizzard outline uses the original health bar background.", 16, y, width)
            y = y - (hint:GetStringHeight() or 14) - 14
            P.Text(body, "Target and focus border", 16, y, width, nil, "section")
            return P.RuleGrid(ctx, body, outline.page, ID, selection, y - 26, width, nil, outline.section)
        end,
    })
end

local HIGHLIGHTS = {
    { key = "target", label = "Target", color = "selectionTargetColor", test = "Test target border" },
    { key = "focus", label = "Focus", color = "selectionFocusColor", test = "Test focus border" },
    { key = "aggro", label = "Aggro", color = "highlightAggroColor", test = "Test aggro border" },
    { key = "mouseover", label = "Mouseover", color = "highlightMouseoverColor", test = "Test mouseover border" },
}
local HIGHLIGHT_DIGITS = { target = 1, focus = 2, aggro = 3, mouseover = 4 }
local HIGHLIGHT_TABS = { { value = "modes", text = "Modes" }, { value = "preview", text = "Preview" },
    { value = "priority", text = "Priority" } }

local function AggroModeRow(built)
    local read = Bridge.SharedAggroBorderEnabled
    if not read or read() == nil then return end
    for _, row in ipairs(built.rows) do
        if row.id == "highlightAggro" then
            row.kind = "dropdown"
            row.values = function()
                local on, off = P.Tr("On"), P.Tr("Off")
                local inherited = read() and on or off
                return {
                    { value = 1, text = ("%s (%s)"):format(P.Tr("Shared"), inherited) },
                    { value = 2, text = on }, { value = 3, text = off },
                }
            end
            row.get = function()
                if not P.Get(ID, "highlightAggroOverride") then return 1 end
                return P.Get(ID, "highlightAggro") and 2 or 3
            end
            row.set = function(value)
                if value == 1 then
                    P.Set(ID, "highlightAggroOverride", false)
                elseif value == 2 or value == 3 then
                    P.SetMany(ID, { highlightAggroOverride = true, highlightAggro = value == 2 })
                end
            end
            return row.values
        end
    end
end

local function HighlightGrid(ctx, body, keys, y, width, prepare)
    local rules = {}
    for _, key in ipairs(keys) do rules[#rules + 1] = P.catalog[ID].rules[key] end
    local built = P.RuleRows(highlight.page, ID, rules, nil, highlight.section)
    local aggroValues = AggroModeRow(built)
    local bottom, entries = P.RuleGrid(ctx, body, highlight.page, ID, rules, y, width, nil, highlight.section, 1, built)
    for _, entry in ipairs(entries) do
        if entry.widget and prepare then P.HM.SetSearchTargetPrepare(entry.widget, prepare) end
        if aggroValues and entry.rule.key == "highlightAggro" and entry.widget and entry.widget.SetValues then
            local widget = entry.widget
            local previous = Bridge.SharedAggroBorderEnabled()
            P.M.TrackRefresh(ctx, function()
                local shared = Bridge.SharedAggroBorderEnabled()
                if shared ~= previous then
                    previous = shared
                    widget:SetValues(aggroValues())
                end
            end)
        end
    end
    if aggroValues and Bridge.OpenSharedAggroBorder then
        P.Button(ctx, body, "Edit Shared Aggro border", 16, bottom, math.min(width, 240),
            function() Bridge.OpenSharedAggroBorder(P.M) end)
        bottom = bottom - 34
    end
    return bottom
end

local function HighlightModes(ctx, panel, width, prepare, top)
    local y = HighlightGrid(ctx, panel,
        { "highlightBorderSize", "highlightAggro", "highlightMouseover", "castTargetHighlightStyle" }, top, width, prepare)
    P.Text(panel, "More Options", 16, y - 10, width, nil, "section")
    return HighlightGrid(ctx, panel, { "selectionDim", "selectionDimPercent", "mouseoverHighlight" },
        y - 36, width, prepare)
end

local function HighlightPreview(ctx, panel, width, _, top)
    local y = top
    for _, mode in ipairs(HIGHLIGHTS) do
        local key = mode.key
        P.Button(ctx, panel, mode.test, 16, y, math.min(width, 240), function()
            if P.Combat() then return end
            P.M.SelectPage("suite_nameplates")
            P.PreviewNameplateHighlight(key)
        end, nil, P.Meta(highlight.page, ID, "preview.highlight." .. key, "action", highlight.section))
        y = y - 34
    end
    return y
end

local function SaveHighlightOrder(order)
    local digits = {}
    for i, key in ipairs(order) do digits[i] = HIGHLIGHT_DIGITS[key] end
    P.Set(ID, "highlightOrder", table.concat(digits))
end

local function HighlightPriority(ctx, panel, width, prepare, top)
    local rule = P.catalog[ID].rules.highlightPriority
    local y = HighlightGrid(ctx, panel, { rule.key }, top, width, prepare)
    local function Enabled() return P.Get(ID, rule.key) and P.RuleEnabled(ID, rule) end
    local hint = P.Text(panel, "The highest active highlight wins.", 16, y, width)
    y = y - (hint:GetStringHeight() or 14) - 8
    local definitions = {}
    for i, mode in ipairs(HIGHLIGHTS) do definitions[i] = { key = mode.key, label = P.Tr(mode.label) } end
    local Style = P.Suite.NameplateStyle
    local holder, refresh = Bridge.HighlightPriorityRows(P.M, panel, definitions, {
        x = 16, y = y, width = math.min(width, 240), dragAllowed = Enabled,
        onReorder = function(rows)
            local order = {}
            for _, row in ipairs(rows) do order[row.slotIndex] = row.key end
            if Enabled() then SaveHighlightOrder(order) end
        end,
    })
    if holder then
        local function Refresh()
            local colors = {}
            for _, mode in ipairs(HIGHLIGHTS) do colors[mode.key] = { P.RGB(P.Get(ID, mode.color)) } end
            refresh(Style.HighlightOrder(P.Get(ID, "highlightOrder")), Enabled(), colors)
        end
        P.M.TrackRefresh(ctx, Refresh)
        Refresh()
        return y - holder:GetHeight() - 10
    end
    for i = 1, #definitions do
        local button = P.Button(ctx, panel, HIGHLIGHTS[i].label, 16, y, math.min(width, 240), function()
            if i < 2 or not Enabled() then return end
            local order = Style.HighlightOrder(P.Get(ID, "highlightOrder"))
            order[i], order[i - 1] = order[i - 1], order[i]
            SaveHighlightOrder(order)
        end, function() return i > 1 and Enabled() end)
        P.M.TrackRefresh(ctx, function()
            local order = Style.HighlightOrder(P.Get(ID, "highlightOrder"))
            P.SetButtonText(button, i == 1 and definitions[HIGHLIGHT_DIGITS[order[i]]].label
                or P.Tr("Move %s up"):format(definitions[HIGHLIGHT_DIGITS[order[i]]].label))
        end)
        y = y - 34
    end
    return y
end

local function HighlightTabs(ctx, builder, body, width, rules)
    P.AttachRuleColors(body, "Highlight Border Colors", ID, rules, nil, function(rule) return P.RuleEnabled(ID, rule) end, nil, nil, Value)
    local inner = math.min(width, 370)
    local panels, bottoms, values = {}, {}, {}
    local build = { modes = HighlightModes, preview = HighlightPreview, priority = HighlightPriority }
    local titles = { modes = "Border Modes", preview = "Preview", priority = "Priority Order" }
    local selectTab
    if not P.W.SegmentTabs or not P.W.ControlCard then
        local y = -12
        for _, tab in ipairs(HIGHLIGHT_TABS) do
            P.Text(body, titles[tab.value], 16, y, inner, nil, "section")
            y = build[tab.value](ctx, body, inner - 24, nil, y - 26) - 14
        end
        return y
    end
    for _, tab in ipairs(HIGHLIGHT_TABS) do
        local key = tab.value
        local panel = P.W.ControlCard(body, titles[key], nil, 16, -49, inner, 60)
        local bottom = build[key](ctx, panel, inner - 32, function() selectTab(key) end, -48)
        panel:SetHeight(-bottom)
        panels[key], bottoms[key] = panel, bottom - 49
        values[#values + 1] = { value = key, text = P.Tr(tab.text) }
    end
    local selected = "modes"
    local tabs, refresh, _, select = P.W.SegmentTabs(ctx, body, {
        label = "", x = 16, y = -12, compact = true, values = values, frames = panels, width = inner,
        defaultTab = selected, get = function() return selected end, set = function(tab) selected = tab end,
        afterRefresh = function(tab) P.FinishBody(builder, body, bottoms[tab]) end,
    })
    selectTab = select
    P.HideControlTitle(tabs)
    refresh()
    return bottoms[selected]
end

local function HighlightSection(ctx, builder)
    local rules = Rules(highlight)
    return P.RuleSection(ctx, builder, highlight.page, ID, highlight.section, P.Tr(highlight.title), rules, {
        grid = function(body, _, width) return HighlightTabs(ctx, builder, body, width, rules) end,
    })
end

local function Register(spec)
    local rules, defaults = {}, {}
    for _, key in ipairs(spec.keys) do
        local rule = P.catalog[ID].rules[key]
        if rule then
            rules[#rules + 1] = rule
            defaults[key] = rule.default
        end
    end
    local provider = {
        build = function(ctx, builder)
            P.M.TrackRefresh(ctx, P.ForgetAvailability)
            local opts = { open = spec == health }
            if spec == health then opts.grid = function(body, y, width) return HealthBarsGrid(ctx, body, y, width, rules) end end
            P.RuleSection(ctx, builder, spec.page, ID, spec.section, P.Tr(spec.title), rules, opts)
        end,
        canReset = function() return P.Available(ID) end,
        prepare = function() return not P.Combat() end,
        reset = function() return P.S.ResetKeys(ID, defaults) end,
        finish = P.Refresh,
        warning = function() return P.Tr("This also resets the nameplate textures on this page.") end,
    }
    if spec == health then
        defaults.barsOverrideSaved = false
        provider.warning = function() return P.Tr("Reset %s to defaults?"):format(P.Tr("Nameplates")) end
        local build, reset = provider.build, provider.reset
        provider.build = function(ctx, builder)
            build(ctx, builder)
            OutlineSection(ctx, builder)
            HighlightSection(ctx, builder)
            local absorbRules = Rules(absorb)
            if #absorbRules > 0 then
                P.RuleSection(ctx, builder, absorb.page, ID, absorb.section, P.Tr(absorb.title), absorbRules, {})
            end
        end
        provider.reset = function()
            for key in pairs(legacy) do
                local rule = P.catalog[ID].rules[key]
                if rule then defaults[key] = rule.default end
            end
            for _, key in ipairs(Textures.BarDetailKeys()) do
                local rule = P.catalog[ID].rules[key]
                if rule then defaults[key] = rule.default end
            end
            return reset()
        end
        spec.registered = Bridge.RegisterBarsScope(P.M, "suite_nameplates", P.Tr("Nameplates"), provider)
        if spec.registered then
            outline.registered, highlight.registered, absorb.registered = true, true, true
            Bridge.RegisterSearchTargetResolver(P.M, "MSUF_Suite.NameplateHealthTextures", function(page, target)
                local section = target and target.sectionId
                if page == spec.page and (section == spec.section or section == outline.section
                    or section == highlight.section or section == absorb.section) then
                    return page, target, { accordion = { [page .. ":" .. section] = true } }
                end
            end)
            return
        end
    end
    spec.registered = Bridge.RegisterPageTail(P.M, spec.page, "MSUF_Suite." .. spec.section, provider)
    if spec == health then outline.registered, highlight.registered, absorb.registered = spec.registered, spec.registered, spec.registered end
end

function Textures.Register()
    if not P.Suite.Client.isMainline then return end
    Register(health)
    Register(cast)
end
